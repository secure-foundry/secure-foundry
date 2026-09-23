# security-delegation.tf — makes log-archive the delegated administrator
# for GuardDuty, Security Hub, Config, and CloudTrail. This has to happen
# from the management account: organizations:RegisterDelegatedAdministrator
# is only callable here, not from log-archive itself, no matter how much
# access log-archive's own credentials have.

resource "aws_organizations_delegated_administrator" "guardduty" {
  account_id        = aws_organizations_account.log_archive.id
  service_principal = "guardduty.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "securityhub" {
  account_id        = aws_organizations_account.log_archive.id
  service_principal = "securityhub.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "config" {
  account_id        = aws_organizations_account.log_archive.id
  service_principal = "config.amazonaws.com"
}

# CloudTrail needs its OWN separate delegation, distinct from the three
# above -- an org trail's `terraform apply` (example-log-archive/cloudtrail.tf)
# fails outright with AccessDenied without this, even with GuardDuty/
# Security Hub/Config delegation already in place.
resource "aws_organizations_delegated_administrator" "cloudtrail" {
  account_id        = aws_organizations_account.log_archive.id
  service_principal = "cloudtrail.amazonaws.com"
}
