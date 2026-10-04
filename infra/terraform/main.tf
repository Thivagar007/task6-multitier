# =====================================================================
# Root module: resource groups + module calls
#
#   modules/monitoring    -> Log Analytics + Application Insights
#   modules/identity      -> backend user-assigned managed identity
#   modules/data          -> Key Vault, Storage, SQL + least-privilege access
#   (next) modules/regional-app   -> per region: plan, apps, slots, autoscale (for_each)
#   (next) modules/traffic-manager, modules/front-door, modules/apim
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
