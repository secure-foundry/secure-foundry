# workload_identity — keyless CI-to-GCP authentication via Workload
# Identity Federation. GCP analog of the AWS cicd_oidc module -- same
# underlying idea (GitHub's OIDC token exchanged for temporary cloud
# credentials, no long-lived key stored anywhere), different mechanism:
# GCP has no direct "assume this role" step. Instead, GitHub's token is
# exchanged for permission to IMPERSONATE a dedicated service account,
# and that service account (not the workflow's federated identity
# directly) is what actually holds IAM permissions.
#
# THE PART THAT MATTERS, same as the AWS module: the attribute condition
# below matches on GitHub's immutable numeric repository_id, never on
# the repository name -- see security-history.md for why a name-based
# match is a real, previously-caught vulnerability class.

variable "env_name" { type = string }
variable "project_id" { type = string }
variable "project_number" {
  type        = string
  description = "Numeric GCP project number (not the project ID string) -- required for the workload identity pool provider's resource name."
}
variable "github_repository_id" {
  type        = string
  description = "GitHub's own numeric repository ID. Find it via: gh api repos/OWNER/REPO --jq .id"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.env_name}-github"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"

  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository_id" = "assertion.repository_id"
  }

  # THE FIX: condition on the numeric repository_id claim, not
  # assertion.repository (the human-readable "owner/repo" name string).
  attribute_condition = "assertion.repository_id == \"${var.github_repository_id}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deploy" {
  project      = var.project_id
  account_id   = "${var.env_name}-deploy"
  display_name = "CI deploy identity for ${var.env_name}"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${var.github_repository_id}"
}

output "deploy_service_account_email" { value = google_service_account.deploy.email }
output "workload_identity_provider" { value = google_iam_workload_identity_pool_provider.github.name }
