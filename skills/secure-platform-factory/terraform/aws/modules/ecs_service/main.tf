# ecs_service — a Fargate service hardened by default: non-root user,
# read-only root filesystem, automatic rollback on a failed deploy, and a
# desired_count variable that lets the whole service be paused to zero
# cost without being destroyed. See security-history.md and
# monitoring-compliance-aws.md for the reasoning behind each piece below.

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/${var.env_name}/${var.service_name}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "execution" {
  name = "${var.env_name}-${var.service_name}-exec"
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

# Execution role needs read access to exactly the secrets THIS service
# uses, and to the KMS key that encrypts them -- nothing broader.
resource "aws_iam_role_policy" "execution_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  name  = "secrets-access"
  role  = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = values(var.secrets)
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
      },
    ]
  })
}

resource "aws_iam_role" "task" {
  name = "${var.env_name}-${var.service_name}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  # The running APPLICATION's own permissions attach here, separately
  # from the execution role above (which only pulls the image and
  # resolves secrets at startup) -- keep these two roles distinct even
  # though it's tempting to collapse them into one.
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.env_name}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # A read-only root filesystem needs somewhere for a process to write
  # its own runtime state (a PID file, a temp file) -- this ephemeral,
  # task-scoped volume is that somewhere, without granting write access
  # to the container image itself.
  volume {
    name = "tmp"
  }

  container_definitions = jsonencode([{
    name                   = var.service_name
    image                  = var.image_uri
    essential              = true
    portMappings           = [{ containerPort = var.container_port }]
    readonlyRootFilesystem = true
    user                   = "10001" # never root
    mountPoints = [
      { sourceVolume = "tmp", containerPath = "/tmp", readOnly = false },
    ]
    secrets     = [for name, arn in var.secrets : { name = name, valueFrom = arn }]
    environment = [for name, value in var.environment : { name = name, value = value }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.service_name
      }
    }
  }])
}

resource "aws_lb_target_group" "this" {
  name        = "${var.env_name}-${var.service_name}"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = var.path_pattern
    }
  }
}

resource "aws_ecs_service" "this" {
  name            = "${var.env_name}-${var.service_name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [var.security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # ECS's own automatic rollback to the last known-good task definition
  # revision on a failed deploy -- no human has to notice and intervene.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Registering a new task-definition revision on every deploy is the
  # CI pipeline's job (see cicd-pipeline.md's "build once, promote
  # forward"), not Terraform's -- ignore drift on which exact revision
  # is currently running so Terraform and the deploy pipeline don't
  # fight over it.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener_rule.this]
}

resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  alarm_name          = "${var.env_name}-${var.service_name}-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "${var.env_name}-${var.service_name}-unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }
  treat_missing_data = "notBreaching"
}

output "target_group_arn" { value = aws_lb_target_group.this.arn }
output "task_role_arn" { value = aws_iam_role.task.arn }
