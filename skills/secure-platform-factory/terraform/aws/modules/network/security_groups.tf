# security_groups.tf — the layered trust chain: RDS trusts only ECS, ECS
# trusts only the ALB. Every rule references another security group by ID,
# never a raw CIDR block -- so the trust relationship survives IP churn
# and can't be loosened by accident to "anyone who can reach this subnet."

resource "aws_security_group" "alb" {
  name_prefix = "${var.env_name}-alb-"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.env_name}-alb" }
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.public_alb ? "0.0.0.0/0" : var.vpn_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.env_name}-ecs-"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.env_name}-ecs" }
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

output "alb_security_group_id" { value = aws_security_group.alb.id }
output "ecs_security_group_id" { value = aws_security_group.ecs.id }
