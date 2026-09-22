# kms — one customer-managed key per environment.
#
# Never rely on AWS's shared default key for anything an audit would care
# about. This key encrypts this environment's database, its secrets, and
# its log groups — see encryption-secrets-aws.md for why the auto-generated
# resources (like a managed database's own master-password secret) need to
# be checked explicitly, since they can default to the AWS-managed key even
# when everything else correctly uses this one.

variable "env_name" {
  type        = string
  description = "Environment name (e.g. \"dev\", \"prod\") — used only in the key's alias and description."
}

variable "key_admin_role_arns" {
  type        = list(string)
  description = "IAM role ARNs allowed to manage this key's policy (rotate, disable, schedule deletion). Keep this list short and deliberate."
}

variable "key_user_role_arns" {
  type        = list(string)
  default     = []
  description = <<-EOT
    IAM role ARNs granted key usage directly in THIS key's own policy.
    Leave empty for roles created by a module that itself needs this
    key's ARN as an input (e.g. ecs_service) -- naming that role here
    would create a circular module dependency. For that common case,
    grant kms:Decrypt/Encrypt via an IAM policy attached to the role
    instead (see ecs_service's own execution_secrets policy for the
    pattern) -- the account-root fail-safe statement below already
    permits this, since IAM identity-based policies and this key's
    resource policy both have to allow an action for it to succeed, and
    the root statement satisfies this key's side of that AND unconditionally.
    Use this variable only for roles that exist independently of this
    key (e.g. a break-glass admin role, a CI role from a separate stack).
  EOT
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "this" {
  description             = "Customer-managed key for the ${var.env_name} environment"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # The account root always retains policy-management ability as a
  # fail-safe (AWS's own recommended pattern) — without this, a mistake in
  # the explicit statements below could lock every principal, including
  # the account owner, out of ever fixing the policy again.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "AccountRootFailSafe"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = var.key_admin_role_arns }
        Action = [
          "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
          "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
          "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
          "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      ], length(var.key_user_role_arns) > 0 ? [{
        # AWS rejects an empty Principal.AWS array outright, so this
        # statement only exists at all when there's at least one role to
        # name -- an empty list here just means "no directly-named key
        # users," not "everyone."
        Sid       = "KeyUsage"
        Effect    = "Allow"
        Principal = { AWS = var.key_user_role_arns }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey",
        ]
        Resource = "*"
      }] : [], [
      # Narrow, service-specific grants -- each conditioned on that
      # service's own ARN pattern, never a blanket service principal grant.
      # These are the two services that commonly need to write
      # KMS-encrypted data on this account's behalf.
      {
        Sid       = "AllowCloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      },
      {
        Sid       = "AllowCloudWatchLogsEncrypt"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      },
    ])
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.env_name}"
  target_key_id = aws_kms_key.this.key_id
}

output "key_arn" {
  value = aws_kms_key.this.arn
}

output "key_id" {
  value = aws_kms_key.this.key_id
}
