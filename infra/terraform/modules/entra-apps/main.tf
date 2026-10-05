# =====================================================================
# Module: entra-apps  (Microsoft Entra ID / Azure AD app registrations)
#
#   1. orders API     - the RESOURCE. Exposes the delegated scope
#                       "Orders.Read". APIM validates tokens issued
#                       for this app (audience = its client ID).
#   2. orders SPA     - the CLIENT (React app). Public client, no secret.
#                       Uses auth code + PKCE via MSAL to sign the user
#                       in and get an access token for Orders.Read.
#
#   Token flow:  user -> SPA (MSAL) -> Entra ID -> access token (aud=API,
#                scp=Orders.Read) -> SPA calls APIM with Bearer token
#                -> APIM validate-jwt -> backend
# =====================================================================

data "azuread_client_config" "current" {}

# Well-known app ID of the Azure CLI - pre-authorized so you can test the
# API from the terminal with: az account get-access-token --scope ...
locals {
  azure_cli_app_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
}

resource "random_uuid" "scope_id" {}

# ---------------------------------------------------------------------
# 1. API (resource) app registration
# ---------------------------------------------------------------------
resource "azuread_application" "api" {
  display_name     = "${var.name_prefix}-orders-api-${var.name_suffix}"
  sign_in_audience = "AzureADMyOrg" # single tenant
  owners           = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2 # v2 tokens: iss=.../v2.0, aud=<client id>

    oauth2_permission_scope {
      id                         = random_uuid.scope_id.result
      value                      = var.scope_name
      type                       = "User"
      enabled                    = true
      admin_consent_display_name = "Read orders"
      admin_consent_description  = "Allows the app to read orders on behalf of the signed-in user."
      user_consent_display_name  = "Read your orders"
      user_consent_description   = "Allows the app to read orders on your behalf."
    }
  }

  # identifier_uris is managed by azuread_application_identifier_uri below
  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

# Application ID URI = api://<client id>  (the tenant-policy-safe format)
resource "azuread_application_identifier_uri" "api" {
  application_id = azuread_application.api.id
  identifier_uri = "api://${azuread_application.api.client_id}"
}

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# ---------------------------------------------------------------------
# 2. SPA (client) app registration
# ---------------------------------------------------------------------
resource "azuread_application" "spa" {
  display_name     = "${var.name_prefix}-orders-spa-${var.name_suffix}"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  # SPA platform = auth code flow with PKCE, no client secret
  single_page_application {
    redirect_uris = var.spa_redirect_uris
  }

  # The SPA asks for the API's Orders.Read scope
  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = random_uuid.scope_id.result
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "spa" {
  client_id = azuread_application.spa.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# ---------------------------------------------------------------------
# Pre-authorize clients on the API (no consent prompt for these apps)
# ---------------------------------------------------------------------
resource "azuread_application_pre_authorized" "spa" {
  application_id       = azuread_application.api.id
  authorized_client_id = azuread_application.spa.client_id
  permission_ids       = [random_uuid.scope_id.result]
}

resource "azuread_application_pre_authorized" "azure_cli" {
  application_id       = azuread_application.api.id
  authorized_client_id = local.azure_cli_app_id
  permission_ids       = [random_uuid.scope_id.result]
}
