# cloudtrail.tf — the org trail. Requires this account to already be
# registered as CloudTrail's delegated administrator
# (example-management/security-delegation.tf) -- that's a separate
# delegation from GuardDuty/Security Hub/Config, and skipping it makes
# `terraform apply` here fail outright with AccessDenied.

resource "aws_s3_bucket" "trail" {
  # Account-ID suffix: S3 bucket names are globally unique across every
  # AWS account, not just yours -- a name with no account-specific suffix
  # will collide with someone else's bucket the moment a second adopter of
  # this template copies it verbatim.
  bucket              = "org-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object_lock_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.kms.key_arn
    }
  }
}

locals {
  # Trail ARN constructed from known literals (not a reference to
  # aws_cloudtrail.org) so the bucket policy can name it without creating a
  # resource-graph cycle: aws_cloudtrail.org depends on this bucket policy
  # (see depends_on below), so the policy can't in turn reference an
  # attribute of aws_cloudtrail.org.
  trail_arn = "arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/org-trail"
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["${aws_s3_bucket.trail.arn}", "${aws_s3_bucket.trail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "org" {
  name                       = "org-trail"
  s3_bucket_name             = aws_s3_bucket.trail.id
  is_organization_trail      = true
  is_multi_region_trail      = true
  enable_log_file_validation = true
  kms_key_id                 = module.kms.key_arn

  # CloudTrail validates the bucket policy at trail-creation time, so the
  # policy (including the AWSCloudTrailAclCheck/AWSCloudTrailWrite
  # statements above) must exist first. There's no attribute reference
  # forcing that ordering, hence the explicit depends_on.
  depends_on = [aws_s3_bucket_policy.trail]
}
