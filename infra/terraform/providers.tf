terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Remote state in the storage account from Step 4.
  # use_azuread_auth = your az login identity, no storage keys.
  backend "azurerm" {
    resource_group_name  = "rg-task6-tfstate"
    storage_account_name = "sttask6tf78731"
    container_name       = "tfstate"
    key                  = "task6-multitier.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true # lets you destroy/recreate cleanly in a lab
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true # data-plane calls use Azure AD, not keys
}

provider "azuread" {}