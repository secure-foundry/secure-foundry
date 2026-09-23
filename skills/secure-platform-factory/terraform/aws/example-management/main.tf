# example-management/main.tf — the org's payer/root account. Holds no
# application workloads. Copy this into your own infra/envs/management/main.tf
# and fill in the real values -- see accounts-aws.md for the account
# layout this fits into.
#
# aws_organizations_organization is a singleton: this manages SETTINGS on
# an AWS Organization that already exists, it does not create one from
# nothing (creating the org itself needs the AWS web console -- there's no
# API for that first step). Applying this for the first time against a
# brand-new org (just IAM Identity Center enabled, nothing else) is the
# expected starting point -- but Terraform still needs to be told that
# org already exists before its first apply here, or CreateOrganization
# fails outright (the account already belongs to one). One-time, before
# the first apply:
#   terraform import aws_organizations_organization.this $(aws organizations describe-organization --query Organization.Id --output text)

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "budget_alert_email" { type = string }
variable "monthly_budget_usd" {
  type    = number
  default = 50
}

variable "log_archive_account_email" {
  type        = string
  description = "A real, deliverable email address for the new log-archive account -- AWS sends account-recovery and billing mail here. Most mail providers support a + suffix (you+aws-log-archive@yourdomain.com) so one real inbox can own every account."
}
variable "build_registry_account_email" { type = string }
variable "dev_account_email" { type = string }
variable "test_account_email" { type = string }
variable "staging_account_email" { type = string }
variable "prod_account_email" { type = string }

# This list REPLACES the org's full enabled-service-principals set on
# every apply, it does not add to it -- omitting a principal that's
# already enabled (e.g. sso.amazonaws.com, auto-registered when Identity
# Center was first turned on, before this config ever existed) actively
# disables it as a side effect. List everything that should stay enabled,
# not just what this config newly wants (found the hard way: Identity
# Center losing its org trust after an apply that "only" added
# guardduty.amazonaws.com).
resource "aws_organizations_organization" "this" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
  ]
  # Left unset, this defaults to "none enabled" and Terraform will actively
  # call DisablePolicyType to match -- found the hard way too: a plan tried
  # to undo SCP enablement moments after a different apply had just turned
  # it on.
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
  feature_set          = "ALL"
}

resource "aws_organizations_account" "log_archive" {
  name  = "log-archive"
  email = var.log_archive_account_email
}
resource "aws_organizations_account" "build_registry" {
  name  = "build-registry"
  email = var.build_registry_account_email
}
resource "aws_organizations_account" "dev" {
  name  = "dev"
  email = var.dev_account_email
}
resource "aws_organizations_account" "test" {
  name  = "test"
  email = var.test_account_email
}
resource "aws_organizations_account" "staging" {
  name  = "staging"
  email = var.staging_account_email
}
resource "aws_organizations_account" "prod" {
  name  = "prod"
  email = var.prod_account_email
}

# --- Cost guardrail: this account's monthly budget + billing alerts ---
module "account_baseline" {
  source             = "../modules/account_baseline"
  account_alias      = "management"
  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.budget_alert_email
}
