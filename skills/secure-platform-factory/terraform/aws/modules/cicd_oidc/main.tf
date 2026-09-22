# cicd_oidc — keyless CI-to-AWS authentication via GitHub's OIDC provider.
#
# Replaces long-lived AWS access keys stored as GitHub secrets entirely.
# GitHub's own OIDC token is exchanged for temporary AWS credentials at
# workflow run time, scoped to exactly this repository (and, if you use
# GitHub Environments, exactly this environment) via a trust policy.
#
# THE PART THAT MATTERS: this trust policy matches on GitHub's immutable
# NUMERIC repository_id and repository_owner_id claims, never on the
# human-readable repository/org NAME. A name-based match (even an exact
# one, and definitely a wildcard/prefix one) is vulnerable to repository
# transfer, renaming, or an attacker registering a similarly-named org --
# none of which changes the numeric IDs. This is a real, previously-caught
# issue -- see security-history.md.

variable "env_name" {
  type        = string
  description = "Environment this deploy role is scoped to (e.g. \"dev\", \"prod\") -- used only in resource naming."
}

variable "github_repository_id" {
  type        = string
  description = "GitHub's own numeric repository ID (not the name). Find it via: gh api repos/OWNER/REPO --jq .id"
}

variable "github_repository_owner_id" {
  type        = string
  description = "GitHub's own numeric organization/owner ID (not the name). Find it via: gh api orgs/OWNER --jq .id (or users/OWNER for a personal account)"
}

variable "github_environment_name" {
  type        = string
  default     = null
  description = "If set, further scopes the trust policy to only workflow runs targeting this specific GitHub Environment -- tighter than repo-wide trust. Recommended once you're using GitHub Environments (see github-setup.md)."
}

variable "deploy_permissions_policy_json" {
  type        = string
  description = "The IAM policy document (as JSON) granting this deploy role exactly what it needs -- ECS deploy, the specific S3/DynamoDB it needs for Terraform state, etc. Scope this as narrowly as your actual deploy steps require; this module doesn't assume what those are."
}

# Only one of these should exist per AWS account -- if your account already
# has a GitHub OIDC provider (e.g. from another environment's setup),
# reference the existing one instead of creating a second.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's own documented root CA thumbprint. AWS has verified GitHub's
  # certificate chain automatically since 2023 regardless of this value,
  # but the argument is still required by the resource.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # THE FIX: numeric IDs, not names. repository_id and
    # repository_owner_id are immutable for the life of the repo/org --
    # a rename, transfer, or an attacker's similarly-named org cannot
    # produce a matching value.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_id"
      values   = [var.github_repository_id]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_owner_id"
      values   = [var.github_repository_owner_id]
    }

    # Environment scoping, if requested, still has to match on the
    # human-readable environment NAME (GitHub doesn't issue a numeric ID
    # for environments) -- acceptable here because it's an additional,
    # narrower restriction layered on top of the numeric repo/org match
    # above, not a replacement for it.
    dynamic "condition" {
      for_each = var.github_environment_name != null ? [1] : []
      content {
        test     = "StringLike"
        variable = "token.actions.githubusercontent.com:sub"
        values   = ["repo:*:environment:${var.github_environment_name}"]
      }
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.env_name}-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy-permissions"
  role   = aws_iam_role.deploy.id
  policy = var.deploy_permissions_policy_json
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
