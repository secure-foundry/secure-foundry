# kms — one customer-managed Cloud KMS key ring + key per environment.
# GCP analog of the AWS kms module; same reasoning in encryption-secrets-gcp.md.

variable "env_name" { type = string }
variable "project_id" { type = string }
variable "location" {
  type    = string
  default = "us"
}

variable "key_admin_members" {
  type        = list(string)
  description = "IAM members (e.g. \"group:platform-admins@example.com\") granted roles/cloudkms.admin on this key ring."
}

resource "google_kms_key_ring" "this" {
  name     = var.env_name
  project  = var.project_id
  location = var.location
}

resource "google_kms_crypto_key" "this" {
  name            = "${var.env_name}-key"
  key_ring        = google_kms_key_ring.this.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true # a destroyed CryptoKey (not just its version) makes everything it ever encrypted permanently unrecoverable
  }
}

resource "google_kms_key_ring_iam_member" "admins" {
  for_each    = toset(var.key_admin_members)
  key_ring_id = google_kms_key_ring.this.id
  role        = "roles/cloudkms.admin"
  member      = each.value
}

# Usage grants (roles/cloudkms.cryptoKeyEncrypterDecrypter) are deliberately
# NOT declared here for consuming service accounts -- see the AWS kms
# module's identical reasoning: a service account created by a module that
# itself needs this key's ID as an input would create a circular module
# dependency. Grant that role on the SPECIFIC crypto key resource from the
# consuming module instead (see cloud_run_service's own IAM binding for
# the pattern).

output "key_ring_id" { value = google_kms_key_ring.this.id }
output "crypto_key_id" { value = google_kms_crypto_key.this.id }
