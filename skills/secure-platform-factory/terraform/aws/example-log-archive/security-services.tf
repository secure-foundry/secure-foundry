# security-services.tf — org-wide GuardDuty, Security Hub, and the Config
# aggregator. Applies once this account is registered as delegated admin
# for each service (example-management/security-delegation.tf) -- apply
# management first, or these fail with AccessDenied.

resource "aws_guardduty_detector" "this" {
  enable = true
}

resource "aws_guardduty_organization_configuration" "this" {
  detector_id                      = aws_guardduty_detector.this.id
  auto_enable_organization_members = "ALL"
}

# Runtime Monitoring watches actual running workload behavior (unexpected
# process execution, malware-like file/network activity in a running
# container) -- distinct from image scanning, which only re-checks stored
# images, never what's actually executing. AWS auto-manages the sidecar
# agent (ECS_FARGATE_AGENT_MANAGEMENT) -- no task definition or IAM role
# changes needed in any environment account. Two things this does NOT do,
# by AWS design: (1) Fargate tasks are immutable -- the sidecar only
# attaches at task launch, so tasks already running when this is enabled
# get zero coverage until each is next redeployed. (2) GuardDuty
# auto-creates an unmanaged VPC interface endpoint + security group in
# every monitored VPC, entirely outside Terraform's view -- expect to see
# it in each workload account and don't "fix" it as drift.
resource "aws_guardduty_organization_configuration_feature" "runtime_monitoring" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  auto_enable = "ALL"

  additional_configuration {
    name        = "ECS_FARGATE_AGENT_MANAGEMENT"
    auto_enable = "ALL"
  }
}

resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = true
  auto_enable_standards = "DEFAULT"
}

resource "aws_config_configuration_aggregator" "org" {
  name = "org-aggregator"
  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }
}

resource "aws_iam_role" "config_aggregator" {
  name = "config-aggregator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}
