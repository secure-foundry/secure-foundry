# workload_identity — keyless CI-to-Azure authentication via Azure AD
# Workload Identity Federation. Azure analog of the AWS cicd_oidc / GCP
# workload_identity modules.
#
# A NOTE ON WHY THE "MATCH EXACT, NOT WILDCARD" CAUTION APPLIES
# DIFFERENTLY HERE: Azure AD federated identity credentials require an
# exact string match on the subject claim (e.g.
# "repo:OWNER/REPO:environment:prod") -- there is no wildcard/pattern
# matching mode to accidentally misuse the way a hand-written trust
# policy condition on another cloud could be. This makes the specific
# vulnerability class in security-history.md structurally harder to
# introduce here by default. It does NOT make the general principle
# moot: still confirm the subject string names YOUR exact repository and
# environment, since a copy-pasted example value is just as real a
# mistake as a wildcard would be on another cloud.

terraform {
  required_providers {
    azuread = { source = "hashicorp/azuread" }
  }
}

variable "env_name" { type = string }
variable "github_owner" {
  type        = string
  description = "GitHub organization or user name, e.g. \"your-org\"."
}
variable "github_repository" {
  type        = string
  description = "Repository name only, e.g. \"your-repo\" (not owner/repo)."
}
variable "github_environment_name" {
  type        = string
  description = "The GitHub Environment name this credential is scoped to (see github-setup.md) -- narrower than a whole-repo trust."
}

resource "azuread_application" "deploy" {
  display_name = "${var.env_name}-deploy"
}

resource "azuread_service_principal" "deploy" {
  client_id = azuread_application.deploy.client_id
}

resource "azuread_application_federated_identity_credential" "github" {
  application_id = azuread_application.deploy.id
  display_name   = "github-actions-${var.env_name}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"

  # Exact subject match -- see module header. Format is fixed by GitHub's
  # own OIDC token issuance, not something this module invents.
  subject = "repo:${var.github_owner}/${var.github_repository}:environment:${var.github_environment_name}"
}

output "client_id" { value = azuread_application.deploy.client_id }
output "service_principal_object_id" { value = azuread_service_principal.deploy.object_id }
