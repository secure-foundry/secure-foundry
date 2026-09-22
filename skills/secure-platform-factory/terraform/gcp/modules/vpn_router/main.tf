# vpn_router — a Tailscale subnet router. GCP analog of the AWS
# vpn_router module, but on a small Compute Engine VM rather than a
# serverless container -- a genuine, worth-explaining difference, not an
# arbitrary inconsistency with the AWS module's Fargate-based approach.
#
# WHY A VM AND NOT CLOUD RUN: a subnet router's entire job is letting
# EXTERNAL tailnet clients reach INTO the private VPC by advertising a
# route to a persistent, VPC-resident node. Cloud Run's Serverless VPC
# Access connector (used by cloud_run_service) is EGRESS-only -- it lets
# Cloud Run reach INTO the VPC, but nothing in the VPC (or arriving via
# the tailnet) can reach a specific Cloud Run instance at a stable
# internal address the way subnet-routing requires. A small, persistent
# VM is the correct tool here, not a workaround.
#
# Runs Tailscale in the same userspace/netstack mode as the AWS module
# would need on Fargate -- not because GCE requires it (a GCE VM CAN run
# Tailscale in full kernel-routing mode, unlike Fargate), but for
# consistency: userspace mode needs no elevated container/OS privileges
# at all, which is the safer default regardless of whether the platform
# would technically allow more.

variable "env_name" { type = string }
variable "project_id" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "network_id" { type = string }
variable "subnet_id" { type = string }
variable "advertised_cidr" {
  type        = string
  description = "The subnet CIDR this router advertises to the tailnet."
}
variable "tailscale_authkey_secret_id" {
  type        = string
  description = "Secret Manager secret ID holding a Tailscale reusable, tagged, ephemeral auth key -- a one-time human-provided bootstrap secret, not something Terraform creates."
}

resource "google_service_account" "router" {
  project      = var.project_id
  account_id   = "${var.env_name}-vpn-router"
  display_name = "VPN subnet router for ${var.env_name}"
}

resource "google_secret_manager_secret_iam_member" "authkey_access" {
  secret_id = var.tailscale_authkey_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.router.email}"
}

resource "google_compute_instance" "router" {
  name         = "${var.env_name}-vpn-router"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-micro" # smallest available -- this VM does no compute work of its own, only relays

  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable" # Container-Optimized OS -- minimal attack surface, no general-purpose shell/package manager
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_id
    # No access_config block -- deliberately no public IP. This VM is
    # reached only via the tailnet it creates, and reaches Secret
    # Manager/the Tailscale coordination service via Cloud NAT.
  }

  service_account {
    email  = google_service_account.router.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    google-logging-enabled = "true"
    gce-container-declaration = yamlencode({
      spec = {
        containers = [{
          name  = "tailscale"
          image = "tailscale/tailscale:stable"
          env = [
            { name = "TS_AUTHKEY", valueFrom = { secretKeyRef = { name = var.tailscale_authkey_secret_id, key = "latest" } } },
            { name = "TS_ROUTES", value = var.advertised_cidr },
            { name = "TS_USERSPACE", value = "true" },
            { name = "TS_EXTRA_ARGS", value = "--advertise-tags=tag:ci --accept-routes=false" },
          ]
          securityContext = { privileged = false }
        }]
        restartPolicy = "Always"
      }
    })
  }
}
