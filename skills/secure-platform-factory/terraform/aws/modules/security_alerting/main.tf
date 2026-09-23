# security_alerting — routes Security Hub's imported findings (HIGH/
# CRITICAL) to a human, instead of leaving them collected in a dashboard
# nobody watches. Security Hub auto-imports every GuardDuty finding as
# its own finding type, so this single rule covers both -- see
# accounts-aws.md and monitoring-compliance-aws.md for the detection
# side this closes the loop on.
#
# Applied once per account (like account_baseline). For the proven
# multi-account layout, that's your log-archive account -- the one
# GuardDuty/Security Hub are delegated to -- not every environment
# separately; this module doesn't know or care which account it's in.

variable "env_name" {
  type        = string
  description = "Environment name (e.g. \"dev\", \"prod\") -- used only in resource naming."
}

# --- Email: zero manual setup, the day-one default ---

variable "alert_emails" {
  type        = list(string)
  default     = []
  description = "Email addresses subscribed to security-finding alerts. Each gets an SNS confirmation email that must be clicked once before delivery starts."
}

resource "aws_sns_topic" "security_alerts" {
  name = "${var.env_name}-security-alerts"
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.security_alerts.arn
      # Scoped to the specific rule that should be allowed to publish
      # here, not "any EventBridge rule anywhere" -- confused-deputy
      # prevention, matching AWS's own documented pattern for
      # EventBridge's Lambda/SQS targets (its SNS-target doc page omits
      # this condition, but the underlying reasoning is identical).
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.security_hub_high_severity.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- Slack / Teams: AWS Chatbot, not a custom Lambda relay ---
# A native platform feature (Chatbot renders SNS/finding JSON into
# readable chat messages on its own) beats hand-rolling and maintaining a
# webhook-relay function for something AWS already does. Both Slack and
# Teams require a one-time MANUAL authorization in the AWS Chatbot console
# (link the Slack workspace / Microsoft Teams team) before Terraform has
# an ID to reference -- that's *why* these stay off (count = 0) by
# default. To turn one on: do that one-time console step, set the
# matching variable, re-apply.

variable "slack_team_id" {
  type        = string
  default     = ""
  description = "Slack workspace ID from the AWS Chatbot console, after the one-time manual Slack authorization there. Empty = Slack alerting stays disabled."
}

variable "slack_channel_id" {
  type        = string
  default     = ""
  description = "Slack channel ID (e.g. C07EZ1ABC23) to post security alerts to."
}

variable "teams_team_id" {
  type        = string
  default     = ""
  description = "Microsoft Teams team ID from the AWS Chatbot console, after the one-time manual Teams authorization there. Empty = Teams alerting stays disabled."
}

variable "teams_tenant_id" {
  type        = string
  default     = ""
  description = "Microsoft Teams tenant ID."
}

variable "teams_channel_id" {
  type        = string
  default     = ""
  description = "Microsoft Teams channel ID to post security alerts to."
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "chatbot" {
  count = (var.slack_team_id != "" || var.teams_team_id != "") ? 1 : 0
  name  = "${var.env_name}-security-alerts-chatbot"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "chatbot.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Same confused-deputy prevention as every other service-principal
      # trust policy in this module.
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_chatbot_slack_channel_configuration" "security_alerts" {
  count              = var.slack_team_id != "" ? 1 : 0
  configuration_name = "${var.env_name}-security-alerts"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_team_id
  sns_topic_arns     = [aws_sns_topic.security_alerts.arn]
  # Notification-only: nobody should be able to run interactive AWS
  # commands from chat under an effectively-admin identity. Overrides the
  # provider's own "AdministratorAccess if unset" default guardrail.
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

resource "aws_chatbot_teams_channel_configuration" "security_alerts" {
  count                 = var.teams_team_id != "" ? 1 : 0
  configuration_name    = "${var.env_name}-security-alerts"
  iam_role_arn          = aws_iam_role.chatbot[0].arn
  channel_id            = var.teams_channel_id
  team_id               = var.teams_team_id
  tenant_id             = var.teams_tenant_id
  sns_topic_arns        = [aws_sns_topic.security_alerts.arn]
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

# --- Route Security Hub (covers GuardDuty too) findings here ---

resource "aws_cloudwatch_event_rule" "security_hub_high_severity" {
  name = "${var.env_name}-security-hub-high-severity"
  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["HIGH", "CRITICAL"] }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "security_hub_to_sns" {
  rule = aws_cloudwatch_event_rule.security_hub_high_severity.name
  arn  = aws_sns_topic.security_alerts.arn
}
