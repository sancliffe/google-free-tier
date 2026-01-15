#!/bin/bash
#
# Phase 4: Set up SSL with Let's Encrypt and Certbot.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
set_strict_mode

# --- DNS Pre-flight Check ---
check_dns() {
    log_info "Performing DNS pre-flight check for ${DOMAIN}..."
    
    # Verify dig is available
    if ! command -v dig &> /dev/null; then
        log_error "Command 'dig' not found. Install: sudo apt-get install dnsutils"
        exit 1
    fi
    
    # Get public IP with timeout
    log_debug "Retrieving public IP address..."
    local public_ip
    public_ip=$(timeout 10 curl -s http://ifconfig.me/ip 2>/dev/null || echo "")
    
    if [[ -z "${public_ip}" ]]; then
        log_error "Could not determine public IP. Check network connectivity."
        log_info "💡 Try running: curl http://ifconfig.me/ip"
        exit 1
    fi
    
    log_debug "Public IP: ${public_ip}"

    # Check DNS against multiple servers for consistency during propagation
    log_debug "Looking up DNS records for ${DOMAIN}..."
    local domain_ip
    local dns_servers=("8.8.8.8" "1.1.1.1")
    local all_ips=()
    
    for dns_server in "${dns_servers[@]}"; do
        local ip
        ip=$(timeout 5 dig +short @"${dns_server}" "${DOMAIN}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
        if [[ -n "${ip}" ]]; then
            all_ips+=("${ip}")
        fi
    done
    
    if [[ ${#all_ips[@]} -eq 0 ]]; then
        log_error "DNS record for ${DOMAIN} not found or not yet propagated."
        log_info "Please ensure an A record exists pointing to ${public_ip}"
        log_info "💡 DuckDNS might take 5-10 minutes to propagate."
        exit 1
    fi
    
    # Use the first resolved IP
    domain_ip="${all_ips[0]}"
    
    if [[ "${public_ip}" != "${domain_ip}" ]]; then
        log_error "DNS mismatch detected!"
        log_error "  - Your server's public IP: ${public_ip}"
        log_error "  - ${DOMAIN} resolves to:  ${domain_ip}"
        log_info "Please update your DNS A record and wait for propagation (5-10 minutes)."
        exit 1
    fi
    
    log_success "DNS check passed. ${DOMAIN} correctly points to ${public_ip}."
}

# --- Main Logic ---
main() {
    echo ""
    printf '=%.0s' {1..60}; echo
    log_info "Phase 4: Setting up SSL with Let's Encrypt"
    printf '=%.0s' {1..60}; echo
    echo ""
    ensure_root || exit 1

    # Initialize variables: prioritize command-line args, then env vars, then Google Cloud Secret Manager
    local DOMAIN="${1:-${DOMAIN:-}}"
    local EMAIL="${2:-${EMAIL_ADDRESS:-}}"

    if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
        log_info "Domain or email not provided as arguments or environment variables. Trying to read from Google Cloud Secret Manager..."
        
        # Get the GCP project ID
        local PROJECT_ID
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "Could not determine GCP project ID. Run: gcloud config set project PROJECT_ID"
            exit 1
        fi
        
        # Try to retrieve secrets from Google Cloud Secret Manager
        if command -v gcloud &> /dev/null; then
            DOMAIN="${DOMAIN:-$(gcloud secrets versions access latest --secret=domain_name --project="${PROJECT_ID}" 2>/dev/null || echo '')}"
            EMAIL="${EMAIL:-$(gcloud secrets versions access latest --secret=email_address --project="${PROJECT_ID}" 2>/dev/null || echo '')}"
            
            if [[ -n "${DOMAIN}" && -n "${EMAIL}" ]]; then
                log_info "Using credentials from Google Cloud Secret Manager."
            else
                log_error "Could not retrieve domain_name or email_address secrets from Google Cloud Secret Manager."
                log_info "Ensure secrets were created with gcp-04-create-secrets.sh"
                log_info "Usage: $0 [domain] [email]"
                log_info "Or set DOMAIN and EMAIL_ADDRESS environment variables (from config.sh)"
                exit 1
            fi
        else
            log_error "gcloud CLI not found. Cannot access Google Cloud Secret Manager."
            log_info "Usage: $0 [domain] [email]"
            log_info "Or set DOMAIN and EMAIL_ADDRESS environment variables (from config.sh)"
            exit 1
        fi
    else
        if [[ -n "${1:-}" || -n "${2:-}" ]]; then
            log_info "Using credentials provided as command-line arguments."
        else
            log_info "Using credentials from environment variables."
        fi
    fi

    if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
        log_error "Domain or email is empty. Please provide valid credentials."
        exit 1
    fi

    log_info "Using domain: ${DOMAIN}"
    log_info "Using email: ${EMAIL}"
    
    # Verify Nginx is running
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx is not running. Please install and start Nginx first."
        exit 1
    fi

    # Install dnsutils if not present
    if ! command -v dig &> /dev/null; then
        log_info "dnsutils (for 'dig' command) is not installed. Installing now..."
        wait_for_apt
        if ! apt-get update -qq; then
            log_error "Failed to update package lists."
            exit 1
        fi
        if ! apt-get install -y -qq dnsutils; then
            log_error "Failed to install dnsutils."
            exit 1
        fi
        log_success "dnsutils installed successfully."
    else
        log_success "dnsutils is already installed."
    fi
    
    # Check/install Certbot
    if ! command -v certbot &> /dev/null; then
        log_info "Certbot is not installed. Installing now..."
        wait_for_apt
        if ! apt-get update -qq; then
            log_error "Failed to update package lists."
            exit 1
        fi
        if ! apt-get install -y -qq certbot python3-certbot-nginx; then
            log_error "Failed to install Certbot."
            exit 1
        fi
        log_success "Certbot installed successfully."
    else
        log_success "Certbot is already installed."
    fi

    local nginx_config="/etc/nginx/sites-available/${DOMAIN}"
    if [[ ! -f "${nginx_config}" ]]; then
        log_info "Creating Nginx server block for ${DOMAIN}..."
        
        # Create rate-limiting configuration
        cat <<EOF > /etc/nginx/conf.d/ratelimit.conf
# Global rate limit for all requests
limit_req_zone \$binary_remote_addr zone=one:10m rate=15r/s;

# Stricter rate limit for sensitive locations like a login page
limit_req_zone \$binary_remote_addr zone=login:10m rate=5r/m;
EOF
        
        # Backup default config before modification
        local backup_dir
        backup_dir=$(mktemp -d)
        # shellcheck disable=SC2064
        trap "rm -rf '${backup_dir}'" EXIT
        backup_file "/etc/nginx/sites-available/default" "${backup_dir}"
        
        # Added stub_status for Google Cloud Ops Agent metrics
        cat <<EOF > "${nginx_config}"
server {
    listen 80;
    server_name ${DOMAIN};
    
    # Apply the global rate limit
    limit_req zone=one burst=30 nodelay;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Example for a sensitive endpoint with stricter rate limiting
    location = /login {
        limit_req zone=login burst=5 nodelay;
        
        # In a real application, this would proxy to a backend service.
        # For now, we return a simple message.
        add_header Content-Type text/plain;
        return 200 'Login page placeholder. Rate limited to 5 requests per minute.';
    }

    # Internal metrics for Google Cloud Ops Agent
    location /stub_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
        log_debug "Nginx config created at: ${nginx_config}"
        
        # Enable site
        if ln -sf "${nginx_config}" "/etc/nginx/sites-enabled/"; then
            log_success "Site configuration symlinked to sites-enabled."
        else
            log_error "Failed to create symlink."
            exit 1
        fi
        
        if [[ -f "/etc/nginx/sites-enabled/default" ]]; then
            log_info "Disabling default Nginx config..."
            rm -f "/etc/nginx/sites-enabled/default"
        fi

        log_info "Testing and reloading Nginx configuration..."
        if ! nginx -t; then
            log_error "Nginx configuration test failed. Please review the config."
            exit 1
        fi
        systemctl reload nginx
        log_success "Nginx reloaded successfully."
    else
        log_info "Nginx configuration for ${DOMAIN} already exists."
    fi

    check_dns

    log_info "Requesting SSL certificate for ${DOMAIN}..."
    log_info "⏳ This may take a few minutes..."
    
    MAX_ATTEMPTS=3
    for attempt in $(seq 1 $MAX_ATTEMPTS); do
      log_info "Attempt $attempt of $MAX_ATTEMPTS to obtain certificate..."
      if timeout 300 certbot --nginx \
          -d "${DOMAIN}" \
          --non-interactive \
          --agree-tos \
          -m "${EMAIL}" \
          --redirect \
          --expand; then
          log_success "🔒 SSL Certificate installed and configured successfully!"
          log_success "Your site is now available at: https://${DOMAIN}"
          log_info "Certificate expires in 90 days. Renewal will happen automatically."
          break # Success
      fi

      if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
        BACKOFF=$((30 * attempt))
        log_warn "Attempt $attempt failed. Retrying in ${BACKOFF}s..."
        sleep "$BACKOFF"
      else
        log_error "Certbot failed to obtain an SSL certificate after $MAX_ATTEMPTS attempts."
        log_info "💡 Review errors above and try: sudo certbot --nginx -d ${DOMAIN}"
        exit 1
      fi
    done
    
    echo ""
}

main "$@"