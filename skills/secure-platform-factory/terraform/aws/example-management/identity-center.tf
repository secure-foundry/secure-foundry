# identity-center.tf — IAM Identity Center (SSO) permission set + account
# assignments. Requires Identity Center to already be enabled for this
# organization (a one-time, console-only step -- there's no API to turn
# it on for the first time either, same as creating the org itself).

data "aws_ssoadmin_instances" "this" {}

resource "aws_ssoadmin_permission_set" "admin" {
  name             = "Admin"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

variable "admin_principal_id" {
  type        = string
  description = "Identity Center user ID (a UUID, not an email) to grant admin access to every account below. Find it via: aws identitystore list-users --identity-store-id <id-from-aws_ssoadmin_instances> --filters AttributePath=UserName,AttributeValue=<email>. Switch principal_type below to \"GROUP\" as soon as there's a second admin -- assigning individually per new hire doesn't scale."
}

variable "member_account_ids" {
  type        = map(string)
  description = "env-name -> AWS account ID, for every account this admin should reach (e.g. { management = \"...\", dev = \"...\", test = \"...\", staging = \"...\", prod = \"...\", \"log-archive\" = \"...\", \"build-registry\" = \"...\" }). Get these from each aws_organizations_account resource's own id attribute once management/main.tf has been applied once, or from the AWS Organizations console."
}

resource "aws_ssoadmin_account_assignment" "admin" {
  for_each           = var.member_account_ids
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_id       = var.admin_principal_id
  principal_type     = "USER"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}
