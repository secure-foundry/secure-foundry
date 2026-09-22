# account_baseline — Azure analog of the AWS/GCP modules of the same
# name. A Cost Management budget alert scoped to this environment's
# resource group.

variable "resource_group_id" { type = string }
variable "account_alias" { type = string }
variable "monthly_budget_usd" { type = number }
variable "alert_email" { type = string }

resource "azurerm_consumption_budget_resource_group" "monthly" {
  name              = "${var.account_alias}-monthly"
  resource_group_id = var.resource_group_id

  amount     = var.monthly_budget_usd
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }

  lifecycle {
    ignore_changes = [time_period[0].start_date] # avoid perpetual drift -- this only needs to be roughly "the current month" once, not exactly on every apply
  }
}
