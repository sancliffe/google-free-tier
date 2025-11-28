variable "billing_account_id" {
  description = "The ID of the billing account to associate this project with."
  type        = string
}

variable "budget_amount" {
  description = "The amount to set the budget alert at (e.g. 10 USD)."
  type        = string
  default     = "10"
}

resource "google_billing_budget" "budget" {
  billing_account = var.billing_account_id
  display_name    = "Free Tier Budget Alert"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.budget_amount
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
}