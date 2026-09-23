# config-storage.tf — the centralized bucket every environment account's
# Config recorder (terraform/aws/modules/config_recorder, pointed here via
# its central_bucket_name variable) delivers to, instead of each account
# hosting its own. Matches the org CloudTrail trail's own centralization
# pattern above.

variable "config_member_account_ids" {
  type        = list(string)
  description = "Account IDs of every environment whose Config recorder delivers here (dev/test/staging/prod -- NOT log-archive or management, which don't run config_recorder against this bucket)."
}

resource "aws_s3_bucket" "config" {
  # Account-ID suffix for the same global-uniqueness reason as the
  # CloudTrail bucket above.
  bucket = "org-config-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (AES256), not this account's own customer-managed KMS key (unlike
# the CloudTrail bucket above) -- this bucket takes cross-account writes
# from every environment account's Config recorder, and granting each of
# their IAM roles encrypt/decrypt on a KMS key means adding cross-account
# principal statements to this account's key policy for roles that don't
# exist until each member account's own Terraform state first applies
# them -- a real cross-state chicken-and-egg problem. Config delivery data
# is resource-configuration metadata, not application secrets or PHI, so
# AWS-managed SSE-S3 is an acceptable, deliberate simplification here.
# Upgrade path: a shared cross-account CMK with each member account's
# config role ARN added to its key policy, if a future compliance
# requirement demands customer-managed keys specifically for this bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [for account_id in var.config_member_account_ids : {
        Sid       = "AWSConfigBucketPermissionsCheck-${account_id}"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config.arn
        Condition = { StringEquals = { "aws:SourceAccount" = account_id } }
      }],
      [for account_id in var.config_member_account_ids : {
        Sid       = "AWSConfigBucketDelivery-${account_id}"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${account_id}/Config/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      }],
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }]
    )
  })
}

output "config_bucket_name" {
  value       = aws_s3_bucket.config.id
  description = "Pass this as central_config_bucket_name in every environment's example-env (accounts-aws.md step 5)."
}
