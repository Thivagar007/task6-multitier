# =====================================================================
# Root module: resource groups + module calls
#
#   modules/monitoring    -> Log Analytics + Application Insights
#   modules/identity      -> backend user-assigned managed identity
#   modules/data          -> Key Vault, Storage, SQL + least-privilege access
#   modules/regional-app  -> per region: plan, apps, slots, autoscale (for_each)
#   modules/traffic-manager -> weighted DNS routing across regional backends
#   (next) modules/front-door, modules/apim
# =====================================================================

# ---------- Resource groups ----------

# Shared services live in the primary region
resource "azurerm_resource_group" "shared" {
  name     = "rg-${var.project}-shared"
  location = var.primary_location
  tags     = local.tags
}

# One resource group per region for the App Service plans and apps
resource "azurerm_resource_group" "region" {
  for_each = local.regions

  name     = "rg-${var.project}-${each.key}"
  location = each.value.location
  tags     = local.tags
}

# ---------- Shared modules ----------

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix         = var.project
  name_suffix         = local.suffix
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

module "backend_identity" {
  source = "./modules/identity"

  name                = "id-${var.project}-backend"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

# ---------- Data services (Key Vault, Storage, SQL) ----------

data "azurerm_client_config" "current" {}

module "data" {
  source = "./modules/data"

  name_prefix          = var.project
  name_suffix          = local.suffix
  location             = azurerm_resource_group.shared.location
  resource_group_name  = azurerm_resource_group.shared.name
  tags                 = local.tags
  deployer_object_id   = data.azurerm_client_config.current.object_id
  deployer_login       = var.deployer_login
  backend_principal_id = module.backend_identity.principal_id
  allowed_client_ip    = var.allowed_client_ip
}

# ---------- Regional app stacks (one per region) ----------

module "region" {
  source   = "./modules/regional-app"
  for_each = local.regions # cin = Central India (primary), sin = South India

  region_key          = each.key
  location            = each.value.location
  resource_group_name = azurerm_resource_group.region[each.key].name
  name_prefix         = var.project
  name_suffix         = local.suffix
  tags                = local.tags

  backend_identity_id        = module.backend_identity.id
  backend_identity_client_id = module.backend_identity.client_id

  key_vault_uri          = module.data.key_vault_uri
  storage_account_url    = module.data.storage_account_url
  storage_container_name = module.data.storage_container_name
  sql_server_fqdn        = module.data.sql_server_fqdn
  sql_database_name      = module.data.sql_database_name

  app_insights_connection_string = module.monitoring.app_insights_connection_string
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id
}

# ---------- Traffic Manager: weighted 80/20 across the regional backends ----------

module "traffic_manager" {
  source = "./modules/traffic-manager"

  name                = "tm-${var.project}-api-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags

  endpoints = {
    for k, r in module.region : k => {
      target_resource_id = r.backend_id
      weight             = local.regions[k].weight # cin 80, sin 20 (locals.tf)
    }
  }
}
