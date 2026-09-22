# vpn_router — a Tailscale subnet router running as a Fargate task,
# replacing a bastion host entirely. See network-vpn.md for the pattern
# and the alternatives (Headscale for a fully self-hosted path, or a
# cloud-native Client VPN if a third-party control plane isn't
# acceptable for your threat model).
#
# Runs in USERSPACE/NETSTACK mode deliberately -- Fargate cannot grant
# the NET_ADMIN capability kernel-mode routing needs. In userspace mode,
# the VPC's own security groups still see this router's own ENI as the
# traffic source for anything it proxies, which preserves the trust-chain
# model in security_groups.tf exactly as if a human were connecting from
# inside the VPC directly.

variable "env_name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_id" { type = string }
variable "ecs_security_group_id" { type = string }
variable "cluster_id" { type = string }
variable "kms_key_arn" { type = string }
variable "tailscale_authkey_secret_arn" {
  type        = string
  description = "Secrets Manager ARN holding a Tailscale reusable, tagged, ephemeral auth key. Generate this once from your Tailscale admin console -- it is a one-time human-provided bootstrap secret, not something Terraform can create."
}
variable "advertised_cidr" {
  type        = string
  description = "The private subnet CIDR this router advertises to the tailnet -- authorized tailnet devices can then reach anything in this range."
}
variable "image" {
  type        = string
  description = "Full image URI for the Tailscale container. Mirror it into your own container registry rather than pulling tailscale/tailscale:latest directly in CI -- Docker Hub's anonymous pull rate limit can stall repeated task launches."
}

variable "desired_count" {
  type        = number
  default     = 1
  description = "0 to pause this router along with the rest of a paused environment -- see ecs_service module's identical variable for the reasoning."
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/${var.env_name}/vpn-router"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "execution" {
  name = "${var.env_name}-vpn-router-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = var.tailscale_authkey_secret_arn },
      { Effect = "Allow", Action = "kms:Decrypt", Resource = var.kms_key_arn },
    ]
  })
}

resource "aws_ecs_task_definition" "router" {
  family                   = "${var.env_name}-vpn-router"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([{
    name      = "vpn-router"
    image     = var.image
    essential = true
    secrets   = [{ name = "TS_AUTHKEY", valueFrom = var.tailscale_authkey_secret_arn }]
    environment = [
      { name = "TS_ROUTES", value = var.advertised_cidr },
      { name = "TS_USERSPACE", value = "true" }, # netstack mode -- see module header
      { name = "TS_EXTRA_ARGS", value = "--advertise-tags=tag:ci --accept-routes=false" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "vpn-router"
      }
    }
  }])
}

data "aws_region" "current" {}

resource "aws_ecs_service" "router" {
  name            = "${var.env_name}-vpn-router"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.router.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [var.private_subnet_id]
    security_groups = [var.ecs_security_group_id]
  }
}
