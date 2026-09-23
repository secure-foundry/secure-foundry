# scp.tf — Identity Center as the ONLY door for human access, enforced
# structurally at the org level, not by convention.
#
# NOTE: an earlier version of a policy like this tried to gate access on
# aws:MultiFactorAuthPresent. That key is not populated for IAM Identity
# Center federated sessions at all, regardless of MFA factor or access
# method -- it's designed around a classic IAM user/root principal calling
# sts:AssumeRole with an explicit MFA serial+token, not Identity Center's
# federation model. An SCP cannot re-verify MFA for Identity Center
# sessions; there is no condition key that carries this signal through.
#
# Current model: authentication and authorization are separate layers.
# Identity Center's own "Prompt for MFA: Every time they sign in" setting
# is what actually enforces MFA, at sign-in time. This SCP's job is
# narrower and fully achievable: close off every *other* human access
# path so Identity Center is the only door. It denies all actions by
# classic IAM users outright, and separately blocks anyone (including an
# admin) from creating a new IAM user, login profile, or access key --
# exactly the "long-lived credential for a human" pattern this whole
# skill avoids everywhere else. A one-off bootstrap IAM user (the kind
# used to stand an account up before Identity Center is wired up)
# requires deliberately, temporarily detaching this policy first -- that
# friction is intentional, not an oversight.
resource "aws_organizations_policy" "prevent_alternate_human_access" {
  name = "prevent-alternate-human-access"
  type = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyAllActionsByIamUsers"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          ArnLike = { "aws:PrincipalArn" = "arn:aws:iam::*:user/*" }
        }
      },
      {
        Sid    = "PreventNewIamUsersAndLongLivedHumanCredentials"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateLoginProfile",
          "iam:UpdateLoginProfile",
          "iam:CreateAccessKey",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "root" {
  policy_id = aws_organizations_policy.prevent_alternate_human_access.id
  target_id = aws_organizations_organization.this.roots[0].id
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "break_glass" {
  name = "break-glass"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
      # No aws:MultiFactorAuthPresent condition here -- same reason as the
      # policy above: this key doesn't populate reliably across every path
      # root might sign in through, and a break-glass role that silently
      # fails to assume during an actual emergency is worse than one gated
      # "only" on already being root, which itself requires root's own
      # separate hardware-MFA-backed sign-in to reach in the first place.
    }]
  })
}
# Attach AdministratorAccess to this role manually, only when actually
# needed for an incident -- document the runbook for this in your own
# repo, don't auto-attach it here.
