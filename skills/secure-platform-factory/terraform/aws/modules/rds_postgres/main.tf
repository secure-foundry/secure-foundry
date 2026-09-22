# rds_postgres — a private-subnet-only Postgres instance with TLS
# enforced at the engine level and encryption on both the storage AND the
# auto-generated master secret (see encryption-secrets-aws.md and
# security-history.md #2 for why that second part needs to be explicit).

variable "env_name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_security_group_id" {
  type        = string
  description = "The one security group allowed to reach this database (typically the application's own ECS security group). This is the RDS side of the trust chain described in network-vpn.md -- nothing else should be able to reach port 5432."
}
variable "kms_key_arn" { type = string }
variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "is_production" {
  type        = bool
  default     = false
  description = "Only production gets deletion protection and a final snapshot before destroy -- see accounts-aws.md's 'non-production vs. production defaults' section for why this split matters."
}

resource "aws_db_subnet_group" "this" {
  name       = var.env_name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.env_name}-rds-"
  vpc_id      = var.vpc_id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "from_app" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.allowed_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# force_ssl=1 rejects any non-TLS connection attempt at the ENGINE level --
# not an application-layer convention that has to be remembered correctly
# in every code path that opens a connection.
resource "aws_db_parameter_group" "this" {
  name   = var.env_name
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.env_name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  allocated_storage      = var.allocated_storage_gb
  storage_encrypted      = true
  kms_key_id             = var.kms_key_arn
  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # AWS generates and manages this master credential for you -- but a
  # managed feature defaulting to the AWS-managed key instead of yours
  # is a real, previously-caught gap. Set this explicitly.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  deletion_protection       = var.is_production
  skip_final_snapshot       = !var.is_production
  final_snapshot_identifier = var.is_production ? "${var.env_name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}" : null

  backup_retention_period = var.is_production ? 30 : 3

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

output "endpoint" { value = aws_db_instance.this.endpoint }
output "master_secret_arn" { value = aws_db_instance.this.master_user_secret[0].secret_arn }
