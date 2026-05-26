variable "tenant_id" {
  type        = string
  description = "Azure Tenant ID"
}

variable "aks_keyvault_csi_object_id" {
  type        = string
  description = "Object ID of AKS Azure Key Vault CSI addon managed identity"
}

variable "envs" {
  type = map(object({
    kv_name = string
  }))

  description = "Key Vault names per environment"
}