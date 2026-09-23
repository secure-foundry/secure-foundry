# example-log-archive/main.tf — the account GuardDuty, Security Hub, and
# CloudTrail are all delegated to (accounts-aws.md). No application
# workload ever runs here. Copy this whole directory into your own
# infra/envs/log-archive/ and fill in the real values.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "kms" {
  source              = "../modules/kms"
  env_name            = "log-archive"
  key_admin_role_arns = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
}

variable "budget_alert_email" { type = string }
variable "monthly_budget_usd" {
  type    = number
  default = 50
}

module "account_baseline" {
  source             = "../modules/account_baseline"
  account_alias      = "log-archive"
  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.budget_alert_email
}

# Applied ONCE, here -- not per environment. This is the account
# GuardDuty/Security Hub are delegated to, so it's the one place a single
# EventBridge rule sees every account's findings.
module "security_alerting" {
  source       = "../modules/security_alerting"
  env_name     = "log-archive"
  alert_emails = [var.budget_alert_email]
}
