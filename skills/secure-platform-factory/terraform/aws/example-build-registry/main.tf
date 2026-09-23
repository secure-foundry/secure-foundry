# example-build-registry/main.tf — the shared container registry every
# environment pulls from cross-account. Applied ONCE, ever, in its own
# account -- structurally independent of any single environment's stack,
# so tearing down or rebuilding an environment never touches the actual
# built artifacts. Images are built and scanned exactly once (typically in
# your first/dev environment's CI pipeline) and promoted forward unchanged
# -- see cicd-pipeline.md's "build once, promote forward". Copy this whole
# directory into your own infra/envs/build-registry/.

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

variable "org_id" {
  type        = string
  description = "AWS Organization ID (o-xxxxxxxxxx), from aws_organizations_organization.this.id in example-management."
}

resource "aws_kms_key" "registry" {
  description         = "Encrypts the shared build-registry ECR repos"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      # Cross-account image pulls need the PULLING account's own ECS task
      # execution role to have kms:Decrypt on this key -- a plain named-
      # role-ARN grant can never reach roles that live in every other
      # environment's own separate AWS account. AWS requires kms:Decrypt on
      # the encrypting key to pull a KMS-encrypted ECR image, not just an
      # ECR repository-policy grant -- matches the identical
      # aws:PrincipalOrgID condition on the repository policies below, for
      # the same reason.
      #
      # kms:GenerateDataKey* is for the PUSH side (only this account's own
      # CI role ever pushes) -- ECR's envelope encryption needs it on every
      # ecr:PutImage, same as kms:Decrypt is needed on every pull. Granting
      # it org-wide alongside Decrypt is safe despite the broader scope:
      # actual push capability is still gated by each repository's own
      # policy (which never grants ecr:PutImage to any account but this
      # one), so a same-org principal that can generate a data key still
      # can't push without that separate, narrower grant.
      #
      # kms:CreateGrant/RetireGrant added deliberately alongside Decrypt/
      # GenerateDataKey*, not instead of them -- AWS's own ECR +
      # customer-managed-KMS-key documentation is genuinely ambiguous
      # between "ECR creates a grant on the caller's behalf, which only
      # needs CreateGrant/DescribeKey" and "the caller needs Decrypt/
      # GenerateDataKey directly." Granting both covers whichever is true
      # rather than gambling on one reading of ambiguous docs.
      {
        Sid       = "AllowOrgDecryptAndGenerateDataKey"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:RetireGrant"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:PrincipalOrgID" = var.org_id } }
      }
    ]
  })
}

resource "aws_ecr_repository" "frontend" {
  name                 = "frontend"
  image_tag_mutability = "IMMUTABLE"
  # Deliberately NOT force_delete=true -- this registry is meant to survive
  # indefinitely, so `terraform destroy` refusing to proceed while real
  # images exist is correct safety behavior, not friction to route around.
  # prevent_destroy on top of that: force_delete alone only blocks destroy
  # while images actually exist -- an EMPTY repo would still destroy
  # silently otherwise. This is the one guard that holds regardless of
  # what's in the repo at the time.
  lifecycle {
    prevent_destroy = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.registry.arn
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "backend"
  image_tag_mutability = "IMMUTABLE"
  lifecycle {
    prevent_destroy = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.registry.arn
  }
}

# ADAPT THIS: only relevant if your VPN pattern (network-vpn.md) mirrors a
# third-party image like Tailscale's rather than pulling it directly --
# mirroring avoids a public registry's anonymous per-IP pull rate limit
# stalling repeated task launches (crash-loop retries, routine redeploys)
# with no ECR-side alternative. MUTABLE (unlike backend/frontend): this
# gets periodically re-mirrored from upstream under the same tag, not
# rebuilt per commit. Delete this repo entirely if your VPN image pulls
# from its public registry directly instead.
resource "aws_ecr_repository" "vpn_router" {
  name                 = "vpn-router"
  image_tag_mutability = "MUTABLE"
  lifecycle {
    prevent_destroy = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.registry.arn
  }
}

# Every re-mirror overwrites the MUTABLE tag but leaves the previous digest
# behind, now untagged -- without this, those orphaned digests accumulate
# forever. backend/frontend need no untagged-cleanup rule: they're
# IMMUTABLE-tagged, so a push either creates a brand new tag or is
# rejected outright, never orphaning an existing one.
resource "aws_ecr_lifecycle_policy" "vpn_router" {
  repository = aws_ecr_repository.vpn_router.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images (superseded mirror digests) after 3 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# backend/frontend get a brand new immutable tag on every real CI deploy --
# without a retention policy, both storage and the number of old,
# potentially-vulnerable images grow without bound (AWS Security Hub's
# ECR.3 control flags exactly this). Keeps a real rollback window (50
# images) without needing to know which tag is "current" from here.
locals {
  retain_last_n_tagged_images = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the newest 50 tagged images (real rollback window)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 50
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy     = local.retain_last_n_tagged_images
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy     = local.retain_last_n_tagged_images
}

# No account-ID allowlisting, IAM role ARNs, or "principal AWS = list of
# account ARNs" pattern -- aws:PrincipalOrgID decouples this from needing
# to know or update account IDs when environment accounts are added or
# changed. Push is NOT granted here (ecr:PutImage is deliberately absent)
# -- only this account's own CI role, with its own separate, narrower
# permissions, can push.
resource "aws_ecr_repository_policy" "vpn_router_cross_account" {
  repository = aws_ecr_repository.vpn_router.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrgPull"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.org_id } }
    }]
  })
}

resource "aws_ecr_repository_policy" "backend_cross_account" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrgPull"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.org_id } }
    }]
  })
}

resource "aws_ecr_repository_policy" "frontend_cross_account" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrgPull"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.org_id } }
    }]
  })
}

# --- CI push identity ---
# The repository policies above are pull-only (no ecr:PutImage), matching
# "only this account's own CI role can push" -- but that role has to
# actually exist somewhere. Since builds happen in THIS account (not each
# environment's own account -- see the file header), it lives here, using
# the same OIDC pattern every environment's own deploy role uses.
variable "github_repository_id" {
  type        = string
  description = "GitHub's own numeric repository ID for the repo whose CI pushes images here. Find it via: gh api repos/OWNER/REPO --jq .id"
}

variable "github_repository_owner_id" {
  type        = string
  description = "GitHub's own numeric organization/owner ID. Find it via: gh api orgs/OWNER --jq .id"
}

module "cicd_oidc" {
  source                     = "../modules/cicd_oidc"
  env_name                   = "build-registry"
  github_repository_id       = var.github_repository_id
  github_repository_owner_id = var.github_repository_owner_id
  deploy_permissions_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken" # this one action does NOT support resource-level scoping -- must stay Resource "*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = [
          aws_ecr_repository.backend.arn,
          aws_ecr_repository.frontend.arn,
          aws_ecr_repository.vpn_router.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
        Resource = aws_kms_key.registry.arn
      }
    ]
  })
}

resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["ECR"] # continuous/enhanced scanning, not just scan-on-push
}

output "ecr_registry" {
  # Host portion of the registry, e.g. "123456789012.dkr.ecr.us-east-1.amazonaws.com".
  # repository_url is "<registry>/<repo-name>", so strip the trailing repo path.
  value       = split("/", aws_ecr_repository.backend.repository_url)[0]
  description = "Record as ecr_registry in every environment's terraform.tfvars, and as a GitHub Actions repo variable your deploy workflow reads."
}
