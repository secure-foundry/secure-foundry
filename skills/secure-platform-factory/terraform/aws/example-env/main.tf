# example-env/main.tf — how the seven modules wire together into one
# real environment. Copy this into your own infra/envs/<name>/main.tf
# and fill in the real values -- this file is the composition pattern,
# not a drop-in you apply as-is.
#
# One of these per environment (dev/test/staging/prod), each in its OWN
# AWS account (see accounts-aws.md), each with its own Terraform state
# backend (see backend.tf.example alongside this file).

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "env_name" { type = string } # "dev" | "test" | "staging" | "prod"
variable "domain_name" { type = string }
variable "is_production" {
  type    = bool
  default = false
}
variable "backend_image_uri" { type = string }
variable "frontend_image_uri" { type = string }
variable "vpn_authkey_secret_arn" { type = string }
variable "vpn_advertised_cidr" { type = string }
variable "vpn_image_uri" { type = string }
variable "github_repository_id" { type = string }
variable "github_repository_owner_id" { type = string }
variable "budget_alert_email" { type = string }
variable "monthly_budget_usd" {
  type    = number
  default = 50
}

# Pause this environment's compute to zero cost without destroying it --
# see ecs_service's own desired_count variable for what this actually
# does. Flip to 1 to resume.
variable "desired_count" {
  type    = number
  default = 1
}

# Leave empty for a self-contained single-account setup (config_recorder
# creates its own bucket here). Once you have a log-archive account
# (example-log-archive), set this to that account's centralized bucket
# name (its own config-storage.tf output) instead -- see accounts-aws.md.
variable "central_config_bucket_name" {
  type    = string
  default = ""
}

data "aws_caller_identity" "current" {}

# key_user_role_arns is deliberately left at its default ([]): the roles
# that need to use this key (the ECS task roles below) are themselves
# created by modules that need this key's ARN as an input -- naming them
# here would be a circular module dependency. Those modules instead grant
# themselves kms:Decrypt via their own IAM role policy (see ecs_service's
# execution_secrets policy) -- see kms/main.tf's variable description for
# why this is the correct pattern, not a workaround.
module "kms" {
  source              = "../modules/kms"
  env_name            = var.env_name
  key_admin_role_arns = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
}

module "network" {
  source      = "../modules/network"
  env_name    = var.env_name
  domain_name = var.domain_name
  public_alb  = var.is_production
  vpn_cidr    = var.vpn_advertised_cidr
  kms_key_arn = module.kms.key_arn
}

module "config_recorder" {
  source              = "../modules/config_recorder"
  env_name            = var.env_name
  central_bucket_name = var.central_config_bucket_name
}

# Applied once per account, same as account_baseline above. If you've
# adopted the full multi-account layout (example-management,
# example-log-archive), remove this block -- example-log-archive already
# applies it ONCE there instead, which is the only place that sees every
# account's Security Hub/GuardDuty findings. Leave it here only for a
# single-account starter setup.
module "security_alerting" {
  source       = "../modules/security_alerting"
  env_name     = var.env_name
  alert_emails = [var.budget_alert_email]
}

module "rds" {
  source                    = "../modules/rds_postgres"
  env_name                  = var.env_name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  allowed_security_group_id = module.network.ecs_security_group_id
  kms_key_arn               = module.kms.key_arn
  is_production             = var.is_production
}

resource "aws_secretsmanager_secret" "cookie_signing_key" {
  name       = "${var.env_name}-cookie-signing-key"
  kms_key_id = module.kms.key_arn
}
# Value is a one-time human-provided bootstrap secret -- set via:
#   aws secretsmanager put-secret-value --secret-id <name> \
#     --secret-string "$(openssl rand -base64 32)"

resource "aws_ecs_cluster" "this" {
  name = var.env_name
}

module "vpn_router" {
  source                       = "../modules/vpn_router"
  env_name                     = var.env_name
  vpc_id                       = module.network.vpc_id
  private_subnet_id            = module.network.private_subnet_ids[0]
  ecs_security_group_id        = module.network.ecs_security_group_id
  cluster_id                   = aws_ecs_cluster.this.id
  kms_key_arn                  = module.kms.key_arn
  tailscale_authkey_secret_arn = var.vpn_authkey_secret_arn
  advertised_cidr              = var.vpn_advertised_cidr
  image                        = var.vpn_image_uri
  desired_count                = var.desired_count
}

module "ecs_service_backend" {
  source                 = "../modules/ecs_service"
  env_name               = var.env_name
  service_name           = "backend"
  image_uri              = var.backend_image_uri
  container_port         = 3000
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  security_group_id      = module.network.ecs_security_group_id
  kms_key_arn            = module.kms.key_arn
  cluster_id             = aws_ecs_cluster.this.id
  alb_arn_suffix         = module.network.alb_arn_suffix
  listener_arn           = module.network.https_listener_arn
  path_pattern           = ["/api/*"]
  listener_rule_priority = 10
  desired_count          = var.desired_count
  secrets = {
    DB_CREDENTIALS        = module.rds.master_secret_arn
    COOKIE_SIGNING_SECRET = aws_secretsmanager_secret.cookie_signing_key.arn
  }
  environment = {
    DB_HOST         = split(":", module.rds.endpoint)[0]
    DB_PORT         = split(":", module.rds.endpoint)[1]
    DB_SSL_MODE     = "verify-full"
    PUBLIC_BASE_URL = "https://${var.domain_name}"
  }
}

module "ecs_service_frontend" {
  source                 = "../modules/ecs_service"
  env_name               = var.env_name
  service_name           = "frontend"
  image_uri              = var.frontend_image_uri
  container_port         = 8080
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  security_group_id      = module.network.ecs_security_group_id
  kms_key_arn            = module.kms.key_arn
  cluster_id             = aws_ecs_cluster.this.id
  alb_arn_suffix         = module.network.alb_arn_suffix
  listener_arn           = module.network.https_listener_arn
  path_pattern           = ["/*"]
  listener_rule_priority = 100
  desired_count          = var.desired_count
}

module "cicd_oidc" {
  source                     = "../modules/cicd_oidc"
  env_name                   = var.env_name
  github_repository_id       = var.github_repository_id
  github_repository_owner_id = var.github_repository_owner_id
  deploy_permissions_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:UpdateService", "ecs:DescribeServices", "ecs:RegisterTaskDefinition",
        "ecs:DescribeTaskDefinition", "rds:DescribeDBInstances",
        "secretsmanager:GetSecretValue",
      ]
      Resource = "*" # narrow this to your specific resource ARNs before using in production
    }]
  })
}

module "account_baseline" {
  source             = "../modules/account_baseline"
  account_alias      = var.env_name
  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.budget_alert_email
}

output "deploy_role_arn" { value = module.cicd_oidc.deploy_role_arn }
output "zone_name_servers" { value = module.network.zone_name_servers }
output "rds_master_secret_arn" { value = module.rds.master_secret_arn }
