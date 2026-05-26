output "key_vaults" {
  value = {
    for env, kv in azurerm_key_vault.kv : env => {
      name = kv.name
      id   = kv.id
      uri  = kv.vault_uri
    }
  }
}