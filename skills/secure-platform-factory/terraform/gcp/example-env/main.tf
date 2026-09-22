# example-env/main.tf — GCP composition, mirroring the AWS example-env.
# Copy into your own infra/envs/<name>/main.tf and fill in real values.

terraform {
  required_version = ">= 1.7"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
    random      = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

variable "env_name" { type = string }
variable "project_id" { type = string }
variable "project_number" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
variable "billing_account_id" { type = string }
variable "domain_name" { type = string }
variable "is_production" {
  type    = bool
  default = false
}
variable "backend_image_uri" { type = string }
variable "frontend_image_uri" { type = string }
variable "github_repository_id" { type = string }
variable "vpn_authkey_secret_id" { type = string }
variable "budget_alert_email" { type = string }
variable "monthly_budget_usd" {
  type    = number
  default = 50
}
variable "key_admin_members" { type = list(string) }

module "kms" {
  source            = "../modules/kms"
  env_name          = var.env_name
  project_id        = var.project_id
  key_admin_members = var.key_admin_members
}

module "network" {
  source      = "../modules/network"
  env_name    = var.env_name
  project_id  = var.project_id
  region      = var.region
  domain_name = var.domain_name
  public_lb   = var.is_production
}

module "cloudsql" {
  source            = "../modules/cloudsql_postgres"
  env_name          = var.env_name
  project_id        = var.project_id
  region            = var.region
  network_id        = module.network.network_id
  kms_crypto_key_id = module.kms.crypto_key_id
  is_production     = var.is_production
}

module "vpn_router" {
  source                      = "../modules/vpn_router"
  env_name                    = var.env_name
  project_id                  = var.project_id
  region                      = var.region
  zone                        = "${var.region}-a"
  network_id                  = module.network.network_id
  subnet_id                   = module.network.subnet_id
  advertised_cidr             = "10.0.0.0/20"
  tailscale_authkey_secret_id = var.vpn_authkey_secret_id
}

module "backend_service" {
  source           = "../modules/cloud_run_service"
  env_name         = var.env_name
  service_name     = "backend"
  project_id       = var.project_id
  region           = var.region
  image_uri        = var.backend_image_uri
  container_port   = 3000
  vpc_connector_id = module.network.vpc_connector_id
  ingress          = var.is_production ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
  secrets = {
    DB_PASSWORD = module.cloudsql.master_password_secret_id
  }
  environment = {
    DB_HOST         = module.cloudsql.private_ip_address
    PUBLIC_BASE_URL = "https://${var.domain_name}"
  }
}

module "frontend_service" {
  source           = "../modules/cloud_run_service"
  env_name         = var.env_name
  service_name     = "frontend"
  project_id       = var.project_id
  region           = var.region
  image_uri        = var.frontend_image_uri
  container_port   = 8080
  vpc_connector_id = module.network.vpc_connector_id
  ingress          = var.is_production ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
}

module "workload_identity" {
  source               = "../modules/workload_identity"
  env_name             = var.env_name
  project_id           = var.project_id
  project_number       = var.project_number
  github_repository_id = var.github_repository_id
}

module "account_baseline" {
  source             = "../modules/account_baseline"
  project_id         = var.project_id
  billing_account_id = var.billing_account_id
  account_alias      = var.env_name
  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.budget_alert_email
}

output "backend_url" { value = module.backend_service.service_url }
output "frontend_url" { value = module.frontend_service.service_url }
output "deploy_service_account" { value = module.workload_identity.deploy_service_account_email }
