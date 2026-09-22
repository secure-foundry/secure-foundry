# account_baseline — a per-account cost guardrail.
#
# Not a security control by itself, but a cheap early-warning signal: an
# agentic workflow, a misconfigured autoscaling policy, or a forgotten
# resource left running can all burn budget fast and silently. This alerts
# a real person before the bill does.

variable "account_alias" {
  type        = string
  description = "Short name for this account (e.g. \"dev\", \"prod\") — used only in the budget's own name."
}

variable "monthly_budget_usd" {
  type        = number
  description = "Monthly spend threshold in USD. Alerts fire at 80% actual and 100% forecasted."
}

variable "alert_email" {
  type        = string
  description = "Where budget threshold alerts are sent. A real, monitored address — not a shared inbox nobody reads."
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.account_alias}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
