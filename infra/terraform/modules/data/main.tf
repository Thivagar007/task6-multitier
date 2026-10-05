# =====================================================================
# Module: data
#   Key Vault + Storage + Azure SQL, each with LEAST-PRIVILEGE access
#   for the backend managed identity:
#
#   Target            Role                         Scope (narrowest possible)
#   ----------------  ---------------------------  ---------------------------
#   Key Vault         Key Vault Secrets User       ONE secret (app-message)
#   Storage           Storage Blob Data Reader     ONE container (documents)
#   SQL               db_datareader (T-SQL)        ONE database
#
#   No passwords or keys: Key Vault uses RBAC, Storage has shared keys
#   disabled, SQL is Entra-ID-only authentication.
# =====================================================================

# ---------------------------------------------------------------------
# Key Vault (RBAC mode, no access policies)
# ---------------------------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.name_prefix}-${var.name_suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true # Azure RBAC instead of legacy access policies
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # lab: allows clean destroy/recreate
  tags                       = var.tags
}

# You (the deployer) need to WRITE the demo secret
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
}

# ---------------------------------------------------------------------
# Storage account (Azure AD only - shared keys disabled)
# ---------------------------------------------------------------------
resource "azurerm_storage_account" "this" {
  name                            = "st${var.name_prefix}${var.name_suffix}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false # no account keys / SAS: identity only
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# storage_account_id = created through the ARM management plane (no data-plane auth needed)
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

locals {
  documents_container_scope = "${azurerm_storage_account.this.id}/blobServices/default/containers/${azurerm_storage_container.documents.name}"
}

# You (the deployer) need to upload the sample blob
resource "azurerm_role_assignment" "deployer_blob_contributor" {
  scope                = local.documents_container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.deployer_object_id
}

# ---------------------------------------------------------------------
# Wait for the deployer role assignments to propagate (RBAC is eventually
# consistent; writing the secret/blob immediately often returns 403)
# ---------------------------------------------------------------------
resource "time_sleep" "wait_for_deployer_rbac" {
  create_duration = "90s"
  depends_on = [
    azurerm_role_assignment.deployer_kv_secrets_officer,
    azurerm_role_assignment.deployer_blob_contributor,
  ]
}

# ---------------------------------------------------------------------
# Demo data the backend reads
# ---------------------------------------------------------------------
resource "azurerm_key_vault_secret" "app_message" {
  name         = "app-message"
  value        = "Hello from Key Vault - read with a managed identity, no secrets in code"
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
  tags         = var.tags
  depends_on   = [time_sleep.wait_for_deployer_rbac]
}

resource "azurerm_storage_blob" "sample" {
  name                 = "welcome.txt"
  storage_container_id = azurerm_storage_container.documents.id
  type                 = "Block"
  source_content       = "Sample document served via managed identity (Storage Blob Data Reader)."
  depends_on           = [time_sleep.wait_for_deployer_rbac]
}

# ---------------------------------------------------------------------
# Least-privilege access for the BACKEND managed identity
# ---------------------------------------------------------------------

# Read ONE secret - not every secret in the vault
resource "azurerm_role_assignment" "backend_kv_secret_user" {
  scope                = azurerm_key_vault_secret.app_message.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.backend_principal_id
}

# Read blobs in ONE container - not the whole account, no write/delete
resource "azurerm_role_assignment" "backend_blob_reader" {
  scope                = local.documents_container_scope
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.backend_principal_id
}

# ---------------------------------------------------------------------
# Azure SQL (Entra ID authentication ONLY - no SQL admin password exists)
# ---------------------------------------------------------------------
resource "azurerm_mssql_server" "this" {
  name                = "sql-${var.name_prefix}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = "12.0"
  minimum_tls_version = "1.2"

  azuread_administrator {
    login_username              = var.deployer_login
    object_id                   = var.deployer_object_id
    azuread_authentication_only = true
  }

  tags = var.tags
}

resource "azurerm_mssql_database" "this" {
  name        = "sqldb-${var.name_prefix}"
  server_id   = azurerm_mssql_server.this.id
  sku_name    = "Basic" # cheapest tier, plenty for the demo
  max_size_gb = 2
  tags        = var.tags
}

# 0.0.0.0 = "Allow Azure services" (App Service outbound IPs are not static per app)
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Your IP, so you can run scripts/sql/setup.sql (creates table + DB user for the identity)
resource "azurerm_mssql_firewall_rule" "deployer" {
  count            = var.allowed_client_ip == null ? 0 : 1
  name             = "Deployer"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = var.allowed_client_ip
  end_ip_address   = var.allowed_client_ip
}

# NOTE: the SQL-side permission (CREATE USER ... FROM EXTERNAL PROVIDER +
# db_datareader) is T-SQL, which azurerm cannot run. It lives in
# scripts/sql/setup.sql and is executed once by the Entra admin (you).
