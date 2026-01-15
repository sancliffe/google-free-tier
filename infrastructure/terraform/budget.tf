# --- APIs ---
resource "google_project_service" "billing_apis" {
  for_each = toset([
    "billingbudgets.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "appengine.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# --- Pub/Sub Topic for Billing Alerts ---
resource "google_pubsub_topic" "billing_alert_topic" {
  name       = "billing-alerts"
  depends_on = [google_project_service.billing_apis]
}

# --- Budget ---
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

  all_updates_rule {
    pubsub_topic = google_pubsub_topic.billing_alert_topic.id
  }

  depends_on = [google_project_service.billing_apis]
}

# --- Cloud Function: Cost Killer ---

resource "google_storage_bucket" "functions_bucket" {
  name                        = "${var.project_id}-functions"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

data "archive_file" "cost_killer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions/cost-killer"
  output_path = "${path.module}/functions/cost-killer.zip"
}

resource "google_storage_bucket_object" "cost_killer_zip" {
  name   = "cost-killer-${data.archive_file.cost_killer_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.cost_killer_zip.output_path
}

resource "google_project_service" "appengine_api" {
  service            = "appengine.googleapis.com"
  disable_on_destroy = false
}

# Ensure App Engine app exists
resource "google_app_engine_application" "app" {
  count       = var.enable_vm ? 1 : 0
  location_id = var.region
  depends_on  = [google_project_service.appengine_api]
}

resource "google_project_iam_custom_role" "vm_stopper" {
  role_id     = "vmStopper"
  title       = "VM Instance Stopper"
  description = "Can only stop specific VM instances"
  permissions = [
    "compute.instances.get",
    "compute.instances.stop",
    "compute.zones.get"
  ]
}

# FIXED: Create IAM binding BEFORE the function to avoid race conditions
resource "google_project_iam_member" "cost_killer_sa_compute" {
  count      = var.enable_vm ? 1 : 0
  project    = var.project_id
  role       = "projects/${var.project_id}/roles/vmStopper"
  member     = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
  depends_on = [google_app_engine_application.app[0]]
}

resource "google_project_iam_member" "cost_killer_sa_datastore" {
  count      = var.enable_vm ? 1 : 0
  project    = var.project_id
  role       = "roles/datastore.user"
  member     = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
  depends_on = [google_app_engine_application.app[0]]
}

# This null_resource is a robust way to handle IAM propagation delays.
# It uses exponential backoff to poll the IAM policy until the new
# member is present, with a maximum timeout. This is more reliable than fixed sleep intervals.
resource "null_resource" "verify_iam" {
  count      = var.enable_vm ? 1 : 0
  depends_on = [google_project_iam_member.cost_killer_sa_compute, google_project_iam_member.cost_killer_sa_datastore]

  provisioner "local-exec" {
    command = <<EOF
RETRY_DELAY=2
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  
  if gcloud projects get-iam-policy ${var.project_id} \
     --flatten="bindings[].members" \
     --filter="bindings.role:projects/${var.project_id}/roles/vmStopper AND bindings.members:serviceAccount:${var.project_id}@appspot.gserviceaccount.com" \
     --format="value(bindings.members)" 2>/dev/null | grep -q "${var.project_id}@appspot.gserviceaccount.com"; then
    echo "✓ IAM policy verified on attempt $ATTEMPT"
    exit 0
  fi
  
  if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    echo "IAM not yet propagated. Attempt $ATTEMPT/$MAX_ATTEMPTS. Waiting $${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
    RETRY_DELAY=$((RETRY_DELAY * 2))
    # Cap exponential backoff at 60 seconds
    if [ $RETRY_DELAY -gt 60 ]; then
      RETRY_DELAY=60
    fi
  fi
done

echo "✗ Timed out waiting for IAM propagation after $MAX_ATTEMPTS attempts (max wait: ~$${RETRY_DELAY}s)"
exit 1
EOF
  }
}

resource "google_cloudfunctions_function" "cost_killer" {
  count                 = var.enable_vm ? 1 : 0
  name                  = "cost-killer"
  description           = "Stops the VM when billing budget is exceeded"
  runtime               = "nodejs${var.nodejs_version}"
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.functions_bucket.name
  source_archive_object = google_storage_bucket_object.cost_killer_zip.name
  trigger_http          = false
  entry_point           = "stopBilling"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.billing_alert_topic.name
  }

  environment_variables = {
    PROJECT_ID         = var.project_id
    ZONE               = var.zone
    INSTANCE_NAME      = google_compute_instance.default[0].name
    SHUTDOWN_THRESHOLD = var.cost_killer_shutdown_threshold
  }

  # Ensure APIs and IAM permissions are ready before creating the function
  depends_on = [
    google_project_service.billing_apis,
    null_resource.verify_iam[0]
  ]
}

# --- Cloud Function: Backup Monitor ---
data "archive_file" "backup_monitor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions/backup-monitor"
  output_path = "${path.module}/functions/backup-monitor.zip"
}

resource "google_storage_bucket_object" "backup_monitor_zip" {
  name   = "backup-monitor-${data.archive_file.backup_monitor_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.backup_monitor_zip.output_path
}

resource "google_service_account" "backup_monitor_sa" {
  count        = var.enable_vm ? 1 : 0
  account_id   = "backup-monitor-sa"
  display_name = "Backup Monitor Function Service Account"
}

resource "google_project_iam_member" "backup_monitor_viewer" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.backup_monitor_sa[0].email}"
}

resource "google_project_iam_member" "backup_monitor_logger" {
  count   = var.enable_vm ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.backup_monitor_sa[0].email}"
}

resource "google_cloudfunctions_function" "backup_monitor" {
  count                 = var.enable_vm ? 1 : 0
  name                  = "backup-monitor"
  description           = "Checks daily backups for overdue status"
  runtime               = "nodejs${var.nodejs_version}"
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.functions_bucket.name
  source_archive_object = google_storage_bucket_object.backup_monitor_zip.name
  trigger_http          = true
  entry_point           = "checkBackups"
  service_account_email = google_service_account.backup_monitor_sa[0].email

  environment_variables = {
    BACKUP_BUCKET_NAME     = google_storage_bucket.backup_bucket[0].name
    BACKUP_PREFIX          = "backup-" # This matches the backup script's naming convention
    BACKUP_THRESHOLD_HOURS = var.backup_threshold_hours
  }

  depends_on = [
    google_project_service.billing_apis, # cloudfunctions API
    google_storage_bucket.backup_bucket, # Ensure backup bucket exists
    google_project_iam_member.backup_monitor_viewer,
    google_project_iam_member.backup_monitor_logger
  ]
}

resource "google_cloud_scheduler_job" "backup_check" {
  count    = var.enable_vm ? 1 : 0 # Only create if VM is enabled and thus backups are relevant
  name     = "backup-monitor-daily"
  schedule = "0 4 * * *" # 4 AM daily

  http_target {
    http_method = "GET" # Cloud Scheduler makes a GET request to HTTP triggered functions
    uri         = google_cloudfunctions_function.backup_monitor[0].https_trigger_url
  }

  # Ensure the Cloud Function and its HTTP trigger URL are available
  depends_on = [google_cloudfunctions_function.backup_monitor]
}

# --- Alert for Backup Failures ---
resource "google_project_service" "monitoring_api" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_monitoring_alert_policy" "backup_failed_alert" {
  count        = var.enable_vm ? 1 : 0
  display_name = "Backup Monitor Failure Alert"
  combiner     = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email[0].name,
  ]

  conditions {
    display_name = "Backup check reported overdue"
    condition_matched_log {
      filter = <<EOT
resource.type="cloud_function"
resource.labels.function_name="backup-monitor"
severity=ERROR
textPayload:"Backup is overdue!"
EOT
    }
  }

  documentation {
    content   = "The daily backup check failed or reported an overdue backup. Please investigate the 'backup-monitor' Cloud Function logs."
    mime_type = "text/markdown"
  }

  depends_on = [
    google_project_service.monitoring_api,
    google_cloudfunctions_function.backup_monitor,
    google_monitoring_notification_channel.email # Ensure notification channel is available
  ]
}