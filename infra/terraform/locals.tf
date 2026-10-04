# Random suffix for names that must be globally unique (Key Vault, Storage, SQL, apps...)
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix = random_string.suffix.result

  # Both regions are described once; apps are created per region with for_each later.
  regions = {
    cin = { location = var.primary_location, weight = 80 }
    sin = { location = var.secondary_location, weight = 20 }
  }

  # azurerm has no "default tags" feature, so every resource uses local.tags
  tags = merge(var.tags, {
    project    = var.project
    managed-by = "terraform"
  })
}