#!/bin/bash
#
# Phase 4: Set up SSL with Let's Encrypt and Certbot.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=2-host-setup/common.sh
source "${SCRIPT_DIR}/common.sh"
set_strict_mode

# --- DNS Pre-flight Check ---
check_dns() {
    log_info "Performing DNS pre-flight check for ${DOMAIN}..."
    
    # Verify dig is available
    ensure_command "dig" "Install: sudo apt-get install dnsutils" || exit 1
    
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

    # Strictly filter for IPv4 and handle multiple records
    log_debug "Looking up DNS records for ${DOMAIN}..."
    local domain_ip
    domain_ip=$(timeout 10 dig +short "${DOMAIN}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)

    if [[ -z "${domain_ip}" ]]; then
        log_error "DNS record for ${DOMAIN} not found or not yet propagated."
        log_info "Please ensure an A record exists pointing to ${public_ip}"
        log_info "💡 DuckDNS might take 5-10 minutes to propagate."
        exit 1
    fi
    
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
    log_info "--- Phase 4: Setting up SSL with Let's Encrypt ---"
    ensure_root || exit 1

    local DOMAIN
    DOMAIN=$(cat /run/secrets/domain_name)
    local EMAIL
    EMAIL=$(cat /run/secrets/email_address)

    if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
        log_error "Required secrets not found in /run/secrets. Ensure startup script ran successfully."
        exit 1
    else
        log_info "Using domain: ${DOMAIN}"
        log_info "Using email: ${EMAIL}"
    fi
    
    # Verify Nginx is running
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx is not running. Please install and start Nginx first."
        exit 1
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
        trap 'rm -rf "${backup_dir}"' EXIT
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
    
    log_info "----------------------------------------------------"
}

main "$@"