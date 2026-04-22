locals {
  all_files = flatten([
    for env in keys(var.envs) : [
      for file in fileset("${path.module}/secrets/${env}", "*.env") : {
        key      = "${replace(file, ".env", "")}-${env}"
        env_name = env
        app_name = "${replace(file, ".env", "")}-${env}"
        filepath = "${path.module}/secrets/${env}/${file}"
      }
    ]
  ])

  secret_map = {
    for item in local.all_files : item.key => {
      env_name    = item.env_name
      secret_name = item.app_name
      raw_content = file(item.filepath)
    }
  }
}

resource "azurerm_key_vault" "kv" {
  for_each            = var.envs
  name                = each.value.kv_name
  resource_group_name = data.terraform_remote_state.rg_layer.outputs.resource_groups["keyvault-management"].name
  location            = data.terraform_remote_state.rg_layer.outputs.resource_groups["keyvault-management"].location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  tags = {
    environment = each.key
    managed_by  = "Terraform"
  }
}

resource "azurerm_role_assignment" "vault_admin" {
  for_each             = azurerm_key_vault.kv
  scope                = each.value.id
  role_definition_name = "Key Vault Administrator"

  principal_id   = data.azurerm_client_config.current.object_id
  principal_type = data.azurerm_client_config.current.client_id == "77aa94d2-63c8-4123-af83-7a9df1af640e" ? "ServicePrincipal" : "User"

  skip_service_principal_aad_check = true
}

resource "azurerm_key_vault_secret" "app_combined_env" {
  for_each     = local.secret_map
  name         = each.value.secret_name
  value        = each.value.raw_content
  key_vault_id = azurerm_key_vault.kv[each.value.env_name].id

  depends_on = [azurerm_role_assignment.vault_admin]

  tags = {
    environment = each.value.env_name
    managed_by  = "Terraform"
  }
}