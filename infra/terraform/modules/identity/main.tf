# =====================================================================
# Module: identity
#   User-assigned managed identity for App Service -> Azure services.
#
#   Why user-assigned (not system-assigned):
#   - system-assigned identities are per SLOT: 2 regions x 2 slots = 4
#     identities to grant; a missed one breaks the app after a swap
#   - one user-assigned identity is attached to all apps/slots, granted once
#   - it exists before the apps, so role assignments don't wait on them
#
#   Least-privilege role assignments are created next to each target
#   resource (Key Vault, Storage, SQL) using principal_id from this module.
# =====================================================================

resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
