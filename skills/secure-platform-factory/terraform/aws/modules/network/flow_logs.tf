# flow_logs.tf — VPC Flow Logs, for network forensics after an incident.
#
# Not load-bearing for day-to-day detection if GuardDuty's own
# network-based findings are already active (accounts-aws.md) -- this is
# the retained-evidence complement to that, not a duplicate of it. See
# monitoring-compliance-aws.md's own gap-tracking table, which this
# closes.

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/flow-logs/${var.env_name}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
}

data "aws_caller_identity" "flow_logs" {}
data "aws_region" "flow_logs" {}

resource "aws_iam_role" "flow_logs" {
  name = "${var.env_name}-vpc-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # AWS's own recommended hardening (confused-deputy prevention):
      # without this, the trust policy technically allows any account's
      # flow-logs service to assume this role, not just this one's. The
      # flow-log-id portion of SourceArn is wildcarded because the role
      # must exist before the flow log resource that would supply it --
      # AWS's own docs recommend exactly this workaround.
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.flow_logs.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ec2:${data.aws_region.flow_logs.name}:${data.aws_caller_identity.flow_logs.account_id}:vpc-flow-log/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.env_name}-vpc-flow-logs"
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      # Resource "*", matching AWS's own documented policy for this
      # exact role -- an earlier version scoped this to the specific
      # log group's ARN, which looks like tighter least-privilege but
      # actually breaks flow log delivery: DescribeLogGroups and
      # CreateLogGroup don't support resource-level permissions at all,
      # so scoping the whole statement away from "*" causes AccessDenied
      # the moment the flow-logs service tries to validate/discover the
      # destination (caught by independent review before merge).
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 600
  tags                     = { Name = "${var.env_name}-flow-log" }
}
