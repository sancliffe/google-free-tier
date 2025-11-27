# 1. DuckDNS Token
printf "your-duckdns-token" | gcloud secrets create duckdns_token --data-file=-

# 2. Email Address
printf "your-email@example.com" | gcloud secrets create email_address --data-file=-

# 3. Domain Name
printf "your-domain.duckdns.org" | gcloud secrets create domain_name --data-file=-

# 4. Backup Bucket Name
printf "your-backup-bucket-name" | gcloud secrets create gcs_bucket_name --data-file=-

# 5. Terraform State Bucket Name
printf "your-tf-state-bucket-name" | gcloud secrets create tf_state_bucket --data-file=-

# 6. Backup Directory (e.g., /var/www/html)
printf "/var/www/html" | gcloud secrets create backup_dir --data-file=-

# 7. Grant Cloud Build permission to access these secrets
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"