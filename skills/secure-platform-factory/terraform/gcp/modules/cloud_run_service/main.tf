# cloud_run_service — GCP analog of the AWS ecs_service module, with one
# genuine, worth-naming architectural difference: Cloud Run bills per
# request/execution time and natively scales to zero when idle. There is
# no equivalent of ecs_service's desired_count=0 "pause" pattern needed
# here, because an idle Cloud Run service ALREADY costs approximately
# nothing -- Fargate's always-on task is what made AWS's pause pattern
# necessary in the first place. Don't force this module to imitate a
# problem GCP's own billing model doesn't have.

variable "env_name" { type = string }
variable "service_name" { type = string }
variable "project_id" { type = string }
variable "region" { type = string }
variable "image_uri" { type = string }
variable "container_port" { type = number }
variable "vpc_connector_id" { type = string }
variable "ingress" {
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  description = "INGRESS_TRAFFIC_ALL for a public-facing service (production only, matching the AWS module's public_alb pattern), INGRESS_TRAFFIC_INTERNAL_ONLY otherwise -- reachable only via the VPC connector, i.e. only from inside the VPN-connected network."
}
variable "secrets" {
  type    = map(string) # env var name -> Secret Manager secret ID
  default = {}
}
variable "environment" {
  type    = map(string)
  default = {}
}
variable "cpu" {
  type    = string
  default = "1"
}
variable "memory" {
  type    = string
  default = "512Mi"
}
variable "max_instance_count" {
  type    = number
  default = 10
}

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = "${var.env_name}-${var.service_name}"
  display_name = "Runtime identity for ${var.service_name} in ${var.env_name}"
}

resource "google_secret_manager_secret_iam_member" "access" {
  for_each  = var.secrets
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.this.email}"
}

resource "google_cloud_run_v2_service" "this" {
  name     = "${var.env_name}-${var.service_name}"
  project  = var.project_id
  location = var.region
  ingress  = var.ingress

  template {
    service_account = google_service_account.this.email

    containers {
      image = var.image_uri
      ports {
        container_port = var.container_port
      }
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.environment
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      # Read-only root filesystem is Cloud Run's default -- unlike
      # Fargate, there's no separate flag to set here; a container that
      # needs scratch space writes to the same ephemeral in-memory /tmp
      # every Cloud Run container gets automatically.
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instance_count
    }
  }

  # Cloud Run's own equivalent of ECS's deployment circuit breaker:
  # traffic only shifts to a new revision after it passes its own
  # readiness check, and a percentage-based rollout (not configured here
  # by default, but available via the traffic block) lets you canary a
  # risky deploy instead of an all-at-once cutover.
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

output "service_url" { value = google_cloud_run_v2_service.this.uri }
output "service_account_email" { value = google_service_account.this.email }
