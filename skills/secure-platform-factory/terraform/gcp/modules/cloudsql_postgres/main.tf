# cloudsql_postgres — a private-IP-only Cloud SQL Postgres instance,
# TLS-required, CMEK-encrypted. GCP analog of the AWS rds_postgres module.

terraform {
  required_providers {
    google-beta = { source = "hashicorp/google-beta" }
    random      = { source = "hashicorp/random" }
  }
}

variable "env_name" { type = string }
variable "project_id" { type = string }
variable "region" { type = string }
variable "network_id" { type = string }
variable "kms_crypto_key_id" { type = string }
variable "tier" {
  type    = string
  default = "db-f1-micro"
}
variable "is_production" {
  type    = bool
  default = false
}

resource "google_project_service_identity" "sql" {
  provider = google-beta
  project  = var.project_id
  service  = "sqladmin.googleapis.com"
}

# Cloud SQL's own service agent needs explicit encrypt/decrypt access to
# your CMEK -- the GCP equivalent of the AWS gap in security-history.md
# #2 (a managed feature needing its OWN grant on your key, not inherited
# from anything else).
resource "google_kms_crypto_key_iam_member" "sql_encrypter" {
  crypto_key_id = var.kms_crypto_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.sql.email}"
}

resource "google_sql_database_instance" "this" {
  name                = var.env_name
  project             = var.project_id
  region              = var.region
  database_version    = "POSTGRES_16"
  encryption_key_name = var.kms_crypto_key_id

  deletion_protection = var.is_production

  settings {
    tier = var.tier

    ip_configuration {
      ipv4_enabled    = false # no public IP, ever
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY" # rejects any non-TLS connection at the engine level
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.is_production
      transaction_log_retention_days = var.is_production ? 7 : 1
    }

    dynamic "insights_config" {
      for_each = [1]
      content {
        query_insights_enabled = true
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.sql_encrypter]
}

resource "random_password" "master" {
  length  = 32
  special = false # Cloud SQL's own connection string handling is stricter about special characters than Postgres itself
}

resource "google_sql_user" "app" {
  name     = "app"
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  password = random_password.master.result
}

resource "google_secret_manager_secret" "master_password" {
  project   = var.project_id
  secret_id = "${var.env_name}-db-password"
  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = var.kms_crypto_key_id
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "master_password" {
  secret      = google_secret_manager_secret.master_password.id
  secret_data = random_password.master.result
}

output "connection_name" { value = google_sql_database_instance.this.connection_name }
output "private_ip_address" { value = google_sql_database_instance.this.private_ip_address }
output "master_password_secret_id" { value = google_secret_manager_secret.master_password.secret_id }
