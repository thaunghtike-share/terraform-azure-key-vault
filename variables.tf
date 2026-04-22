variable "tenant_id" {
  type = string
}

variable "current_user_object_id" {
  type = string
}

variable "envs" {
  type = map(object({
    kv_name = string
  }))
}