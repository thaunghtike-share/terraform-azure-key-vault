terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "mbftfstatestorage"
    container_name       = "tfstate"
    key                  = "mbr_prod_key_vaults.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

data "terraform_remote_state" "rg_layer" {
  backend = "azurerm"

  config = {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "mbftfstatestorage"
    container_name       = "tfstate"
    key                  = "mbr_prod_resource_groups.tfstate"
    use_azuread_auth     = true
  }
}