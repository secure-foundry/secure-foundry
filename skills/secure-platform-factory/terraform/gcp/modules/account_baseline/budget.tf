# account_baseline — GCP analog of the AWS module of the same name.
# A Cloud Billing budget alert, the same cheap early-warning signal.

variable "billing_account_id" {
  type        = string
  description = "The Cloud Billing account ID this project bills against."
}

variable "project_id" { type = string }

variable "account_alias" {
  type        = string
  description = "Short name for this environment -- used only in the budget's own display name."
}

variable "monthly_budget_usd" {
  type = number
}

variable "alert_email" {
  type        = string
  description = "Where budget threshold alerts are sent -- a real, monitored address."
}

resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account_id
  display_name    = "${var.account_alias}-monthly"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
  }
}

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.account_alias}-budget-alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}
