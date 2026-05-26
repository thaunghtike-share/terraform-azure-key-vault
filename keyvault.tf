data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  for_each = var.envs

  name                = each.value.kv_name
  resource_group_name = data.terraform_remote_state.rg_layer.outputs.resource_groups["keyvault-management"].name
  location            = data.terraform_remote_state.rg_layer.outputs.resource_groups["keyvault-management"].location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = {
    environment = each.key
    managed_by  = "Terraform"
  }
}

resource "azurerm_role_assignment" "github_keyvault_admin" {
  for_each = azurerm_key_vault.kv

  scope                = each.value.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"

  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "aks_csi_keyvault_secrets_user" {
  for_each = azurerm_key_vault.kv

  scope                = each.value.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.aks_keyvault_csi_object_id
  principal_type       = "ServicePrincipal"

  skip_service_principal_aad_check = true
}