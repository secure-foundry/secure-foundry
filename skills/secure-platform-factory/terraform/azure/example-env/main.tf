# example-env/main.tf — Azure composition, mirroring the AWS/GCP
# example-env files. Copy into your own infra/envs/<name>/main.tf and
# fill in real values.

terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "azurerm" {
  features {}
}

variable "env_name" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}
variable "tenant_id" { type = string }
variable "domain_name" { type = string }
variable "is_production" {
  type    = bool
  default = false
}
variable "backend_image_uri" { type = string }
variable "frontend_image_uri" { type = string }
variable "github_owner" { type = string }
variable "github_repository" { type = string }
variable "github_environment_name" { type = string }
variable "vpn_authkey_secret_name" { type = string }
variable "budget_alert_email" { type = string }
variable "monthly_budget_usd" {
  type    = number
  default = 50
}

data "azurerm_subscription" "current" {}

module "network" {
  source          = "../modules/network"
  env_name        = var.env_name
  location        = var.location
  domain_name     = var.domain_name
  public_frontend = var.is_production
}

module "key_vault" {
  source              = "../modules/key_vault"
  env_name            = var.env_name
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  tenant_id           = var.tenant_id
}

module "postgres" {
  source              = "../modules/postgres_flexible_server"
  env_name            = var.env_name
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  data_subnet_id      = module.network.data_subnet_id
  private_dns_zone_id = module.network.private_dns_zone_id
  key_vault_id        = module.key_vault.key_vault_id
  cmk_id              = module.key_vault.cmk_id
  is_production       = var.is_production
}

module "backend_service" {
  source              = "../modules/container_app_service"
  env_name            = var.env_name
  service_name        = "backend"
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  app_subnet_id       = module.network.app_subnet_id
  image_uri           = var.backend_image_uri
  container_port      = 3000
  external_ingress    = var.is_production
  key_vault_id        = module.key_vault.key_vault_id
  secrets = {
    DB_PASSWORD = module.postgres.admin_password_secret_name
  }
  environment = {
    DB_HOST         = module.postgres.fqdn
    PUBLIC_BASE_URL = "https://${var.domain_name}"
  }
}

module "frontend_service" {
  source              = "../modules/container_app_service"
  env_name            = var.env_name
  service_name        = "frontend"
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  app_subnet_id       = module.network.app_subnet_id
  image_uri           = var.frontend_image_uri
  container_port      = 8080
  external_ingress    = var.is_production
  key_vault_id        = module.key_vault.key_vault_id
}

module "vpn_router" {
  source                        = "../modules/vpn_router"
  env_name                      = var.env_name
  resource_group_name           = module.network.resource_group_name
  location                      = module.network.location
  app_subnet_id                 = module.network.app_subnet_id
  advertised_cidr               = "10.0.0.0/16"
  key_vault_id                  = module.key_vault.key_vault_id
  key_vault_name                = "kv-${var.env_name}"
  tailscale_authkey_secret_name = var.vpn_authkey_secret_name
}

module "workload_identity" {
  source                  = "../modules/workload_identity"
  env_name                = var.env_name
  github_owner            = var.github_owner
  github_repository       = var.github_repository
  github_environment_name = var.github_environment_name
}

module "account_baseline" {
  source             = "../modules/account_baseline"
  resource_group_id  = "${data.azurerm_subscription.current.id}/resourceGroups/${module.network.resource_group_name}"
  account_alias      = var.env_name
  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.budget_alert_email
}

output "backend_fqdn" { value = module.backend_service.fqdn }
output "frontend_fqdn" { value = module.frontend_service.fqdn }
output "deploy_client_id" { value = module.workload_identity.client_id }
output "public_dns_zone_name_servers" { value = module.network.public_dns_zone_name_servers }
