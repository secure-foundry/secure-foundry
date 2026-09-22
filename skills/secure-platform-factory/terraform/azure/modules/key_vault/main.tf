# key_vault — one Key Vault per environment, holding both the
# customer-managed encryption key AND the application's secrets. See
# encryption-secrets-azure.md for why this is one module here where AWS
# and GCP split it into two.

variable "env_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = "kv-${var.env_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Non-negotiable, not production-only -- see encryption-secrets-azure.md.
  # Without this, a deleted vault or object can be purged before its
  # soft-delete retention elapses, defeating soft-delete's entire purpose.
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # Azure RBAC, not the legacy vault access-policy model -- see
  # encryption-secrets-azure.md for why this keeps access auditable
  # through the same RBAC trail as every other Azure resource.
  rbac_authorization_enabled = true
}

resource "azurerm_role_assignment" "admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "cmk" {
  name         = "${var.env_name}-cmk"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = ["decrypt", "encrypt", "wrapKey", "unwrapKey"]

  # Usage grants (Key Vault Crypto User) for consuming resources are
  # deliberately NOT declared here -- same reasoning as the AWS/GCP
  # kms modules: a resource created by a module that needs this vault's
  # ID as an input would create a circular module dependency. Grant that
  # role on the specific resource from the CONSUMING module instead.
  depends_on = [azurerm_role_assignment.admin]
}

output "key_vault_id" { value = azurerm_key_vault.this.id }
output "key_vault_uri" { value = azurerm_key_vault.this.vault_uri }
output "cmk_id" { value = azurerm_key_vault_key.cmk.id }
