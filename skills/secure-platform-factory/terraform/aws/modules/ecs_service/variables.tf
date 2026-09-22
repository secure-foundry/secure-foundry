variable "env_name" { type = string }
variable "service_name" { type = string } # e.g. "backend", "frontend"
variable "image_uri" { type = string }
variable "container_port" { type = number }
variable "cpu" {
  type    = string
  default = "256"
}
variable "memory" {
  type    = string
  default = "512"
}
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "kms_key_arn" { type = string }
variable "cluster_id" { type = string }
variable "alb_arn_suffix" { type = string }
variable "listener_arn" { type = string }
variable "path_pattern" {
  type        = list(string)
  description = "ALB listener-rule path pattern this service answers, e.g. [\"/api/*\"]. Use [\"/*\"] for the default/catch-all service."
}
variable "listener_rule_priority" { type = number }

variable "desired_count" {
  type        = number
  default     = 1
  description = "0 to scale this service down to zero running tasks -- e.g. pausing a lightly-used environment to save Fargate compute cost -- without tearing down the service, task definition, or ALB target group. This is the exact mechanism this skill's own maintainers used to cut a real environment's cost to near-zero without losing any configuration."
}

variable "secrets" {
  type        = map(string) # env var name -> Secrets Manager ARN
  default     = {}
  description = "Every credential this container needs, injected via the ECS secrets mechanism -- never baked into the image or passed as plain environment values. See encryption-secrets-aws.md."
}

variable "environment" {
  type    = map(string) # env var name -> plain, non-secret value
  default = {}
}
