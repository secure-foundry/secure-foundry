# container_app_service — Azure analog of the AWS ecs_service / GCP
# cloud_run_service modules. Azure Container Apps shares GCP Cloud Run's
# scale-to-zero, per-use billing model -- the same note in
# cloud_run_service's header about not needing a desired_count pause
# pattern applies here too, for the same reason.

variable "env_name" { type = string }
variable "service_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "app_subnet_id" { type = string }
variable "image_uri" { type = string }
variable "container_port" { type = number }
variable "external_ingress" {
  type        = bool
  default     = false
  description = "true only for the public-facing service in a public-fronted environment -- see network module's public_frontend variable."
}
variable "cpu" {
  type    = number
  default = 0.5
}
variable "memory" {
  type    = string
  default = "1Gi"
}
variable "max_replicas" {
  type    = number
  default = 5
}
variable "key_vault_id" { type = string }
variable "secrets" {
  type    = map(string) # env var name -> Key Vault secret name
  default = {}
}
variable "environment" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${var.env_name}-${var.service_name}"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  infrastructure_subnet_id       = var.app_subnet_id
  internal_load_balancer_enabled = !var.external_ingress
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.env_name}-${var.service_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "secrets_access" {
  for_each             = var.secrets
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_container_app" "this" {
  name                         = "${var.env_name}-${var.service_name}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single" # a new revision automatically replaces the old one on deploy; ECS's/Cloud Run's own rollback-on-failure is Container Apps' built-in revision health check + automatic rollback to the last healthy revision

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  dynamic "secret" {
    for_each = var.secrets
    content {
      name                = lower(replace(secret.key, "_", "-"))
      key_vault_secret_id = secret.value
      identity            = azurerm_user_assigned_identity.this.id
    }
  }

  template {
    min_replicas = 0 # scales to zero when idle -- see module header
    max_replicas = var.max_replicas

    container {
      name   = var.service_name
      image  = var.image_uri
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.environment
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets
        content {
          name        = env.key
          secret_name = lower(replace(env.key, "_", "-"))
        }
      }
    }
  }

  ingress {
    external_enabled = var.external_ingress
    target_port      = var.container_port
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

output "fqdn" { value = azurerm_container_app.this.latest_revision_fqdn }
output "identity_principal_id" { value = azurerm_user_assigned_identity.this.principal_id }
