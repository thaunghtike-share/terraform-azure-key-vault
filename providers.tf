terraform {
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
    key                  = "kv.tfstate"
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
  }
}

data "azurerm_client_config" "current" {}