variable "env_name" {
  type        = string
  description = "Environment name (e.g. \"dev\", \"prod\") -- used in resource naming and tags."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Give each environment's VPC a distinct, non-overlapping CIDR if you ever expect to peer or VPN between them."
}

variable "public_alb" {
  type        = bool
  default     = false
  description = "true only for the one environment that should be reachable from the public internet (typically production). Every other environment's ALB is internal-only, reachable solely through the VPN layer -- see network-vpn.md."
}

variable "domain_name" {
  type        = string
  description = "The domain this environment serves, e.g. \"dev.example.com\"."
}

variable "acm_validation_zone_is_public" {
  type        = bool
  default     = true
  description = "Whether ACM's DNS validation record should be created in the public zone (needed the first time a domain is validated) or can rely on an already-validated wildcard/parent certificate."
}

variable "vpn_cidr" {
  type        = string
  description = "The CIDR range your VPN pattern's traffic arrives from (e.g. your Tailscale/WireGuard mesh's own address range), so a non-public ALB can allow exactly that range instead of 0.0.0.0/0. See network-vpn.md."
}

variable "kms_key_arn" {
  type        = string
  description = "This environment's own customer-managed key (module.kms.key_arn) -- encrypts the VPC Flow Logs log group. The kms module already grants CloudWatch Logs the needed encrypt/decrypt permissions."
}
