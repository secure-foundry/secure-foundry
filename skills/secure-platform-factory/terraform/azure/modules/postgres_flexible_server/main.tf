# postgres_flexible_server — VNet-integrated, TLS-required,
# customer-managed-key-encrypted Postgres. Azure analog of the AWS
# rds_postgres / GCP cloudsql_postgres modules.

variable "env_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "data_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "key_vault_id" { type = string }
variable "cmk_id" { type = string }
variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}
variable "is_production" {
  type    = bool
  default = false
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

# The server's own managed identity needs explicit wrap/unwrap access to
# the CMK before the server resource itself can be created with
# customer_managed_key configured -- the same "a managed feature needs
# its OWN grant on your key" gap as AWS security-history.md #2 and the
# GCP cloudsql module's identical comment.
resource "azurerm_user_assigned_identity" "postgres" {
  name                = "${var.env_name}-postgres"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "postgres_key_access" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.postgres.principal_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.env_name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "16"
  sku_name            = var.sku_name

  administrator_login    = "psqladmin"
  administrator_password = random_password.admin.result

  delegated_subnet_id           = var.data_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  backup_retention_days        = var.is_production ? 30 : 3
  geo_redundant_backup_enabled = var.is_production

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.postgres.id]
  }

  customer_managed_key {
    key_vault_key_id                  = var.cmk_id
    primary_user_assigned_identity_id = azurerm_user_assigned_identity.postgres.id
  }

  depends_on = [azurerm_role_assignment.postgres_key_access]
}

# Rejects any non-TLS connection at the database engine level -- same
# requirement as AWS's rds.force_ssl and GCP's ssl_mode.
resource "azurerm_postgresql_flexible_server_configuration" "require_tls" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "ON"
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "${var.env_name}-db-password"
  value        = random_password.admin.result
  key_vault_id = var.key_vault_id
}

output "fqdn" { value = azurerm_postgresql_flexible_server.this.fqdn }
output "admin_password_secret_name" { value = azurerm_key_vault_secret.admin_password.name }
