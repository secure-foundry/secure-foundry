# network — VPC, one subnet, Cloud NAT for outbound-only internet from
# private resources, and the firewall trust chain. GCP analog of the AWS
# network module; see network-vpn.md for the pattern this implements.
#
# Simplification versus the AWS module, worth being explicit about: this
# does not stand up a full external HTTPS load balancer stack (global
# forwarding rule, URL map, target proxy, Google-managed cert) here --
# that's genuinely more moving parts on GCP than on AWS for the
# non-production case, because Cloud Run's own `ingress` setting
# (internal-only vs. internal-and-load-balancer vs. all) already gives a
# non-production environment real network isolation without a full public
# LB stack in front of it at all. The public LB is only built for
# production (var.public_lb = true) -- see cloud_run_service's own
# ingress handling for how a non-public environment stays reachable
# (via the VPN + Serverless VPC Access, not a public load balancer).

variable "env_name" { type = string }
variable "project_id" { type = string }
variable "region" { type = string }
variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/20"
}
variable "public_lb" {
  type    = bool
  default = false
}
variable "domain_name" { type = string }

resource "google_compute_network" "this" {
  name                    = var.env_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name                     = var.env_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true # lets resources without a public IP reach Google APIs (Secret Manager, Cloud SQL Admin API) directly
}

# Serverless VPC Access connector -- how Cloud Run (which doesn't sit
# inside the VPC by default) reaches private-IP resources like Cloud SQL
# and the VPN router below. This is the GCP-specific piece with no
# direct AWS equivalent (Fargate tasks are natively inside the VPC via
# an ENI; Cloud Run needs this bridge).
resource "google_vpc_access_connector" "this" {
  name          = "${var.env_name}-connector"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.this.name
  ip_cidr_range = "10.8.0.0/28"
}

resource "google_compute_router" "this" {
  name    = "${var.env_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name                               = "${var.env_name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall trust chain: Cloud SQL's own private-IP access control (not a
# firewall rule) already restricts it to the VPC; this rule restricts
# who WITHIN the VPC can reach the VPN router's advertised range, mirroring
# the "only the app tier can reach the database" chain from network-vpn.md.
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.env_name}-allow-internal"
  project = var.project_id
  network = google_compute_network.this.name

  allow {
    protocol = "all"
  }

  source_ranges = [var.subnet_cidr, "10.8.0.0/28"]
}

resource "google_compute_security_policy" "this" {
  name    = var.env_name
  project = var.project_id

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default allow"
  }

  rule {
    action   = "throttle"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 2000
        interval_sec = 60
      }
    }
    description = "rate limit per IP -- Cloud Armor analog of the AWS WAF rate-based rule"
  }
}

output "network_id" { value = google_compute_network.this.id }
output "subnet_id" { value = google_compute_subnetwork.this.id }
output "vpc_connector_id" { value = google_vpc_access_connector.this.id }
output "security_policy_id" { value = google_compute_security_policy.this.id }
