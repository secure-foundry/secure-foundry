# config_recorder — this account's own AWS Config recorder + delivery
# channel, so you get a real, queryable resource-configuration history and
# drift record -- not just something Config's console says is possible.
#
# Two delivery modes, controlled by var.central_bucket_name:
#
# - Left empty (default): delivers to a bucket created in THIS SAME
#   account -- a self-contained starter setup that works with zero other
#   accounts required.
# - Set to a bucket name: delivers to that bucket instead (skips creating
#   a local one), and grants this account's Config role the matching
#   cross-account write permission -- the identity-policy side of the
#   grant; the bucket's OWNING account still needs its own resource
#   policy allowing this account's delivery (see example-log-archive/
#   config-storage.tf for that side, and accounts-aws.md for why
#   centralizing into one log-archive account is the proven pattern once
#   you have that account).

variable "env_name" {
  type        = string
  description = "Environment name (e.g. \"dev\", \"prod\") -- used in resource naming."
}

variable "central_bucket_name" {
  type        = string
  default     = ""
  description = "Name of an existing bucket (typically in your log-archive account) to deliver to instead of creating one here. Leave empty for the self-contained same-account default."
}

data "aws_caller_identity" "current" {}

locals {
  centralized = var.central_bucket_name != ""
  # S3 bucket names are globally unique across every AWS account, not just
  # yours -- a name like "dev-config-logs" with no account-specific suffix
  # will collide with someone else's bucket the moment a second adopter of
  # this template copies it verbatim. The account ID makes this collision-
  # proof with no adopter input required.
  bucket_name = "${var.env_name}-config-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "config" {
  count  = local.centralized ? 0 : 1
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "config" {
  count  = local.centralized ? 0 : 1
  bucket = aws_s3_bucket.config[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "config" {
  count                   = local.centralized ? 0 : 1
  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  count  = local.centralized ? 0 : 1
  bucket = aws_s3_bucket.config[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  count  = local.centralized ? 0 : 1
  bucket = aws_s3_bucket.config[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config[0].arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.config[0].arn, "${aws_s3_bucket.config[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_iam_role" "config" {
  name = "${var.env_name}-config-recorder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # AWS's own documented recommended trust policy for this exact role
      # includes this condition, to prevent the confused-deputy problem --
      # without it, the trust policy technically allows any account's
      # Config service to assume this role, not just this one's.
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Only needed in centralized mode: AWS_ConfigRole covers the Describe/List
# read access recording needs, but not delivery to a bucket that lives in
# a DIFFERENT account -- that needs its own explicit grant here, mirrored
# by the central bucket's own policy on the receiving end (a cross-account
# S3 write needs both sides -- the writer's identity policy and the
# bucket's resource policy -- to allow it). Same-account mode doesn't need
# this: the bucket policy above already covers it.
resource "aws_iam_role_policy" "config_s3_delivery" {
  count = local.centralized ? 1 : 0
  name  = "${var.env_name}-config-s3-delivery"
  role  = aws_iam_role.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.central_bucket_name}"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.central_bucket_name}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "this" {
  name     = var.env_name
  role_arn = aws_iam_role.config.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = var.env_name
  s3_bucket_name = local.centralized ? var.central_bucket_name : aws_s3_bucket.config[0].id
  s3_key_prefix  = local.centralized ? "AWSLogs/${data.aws_caller_identity.current.account_id}/Config" : null
  depends_on     = [aws_config_configuration_recorder.this, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}
