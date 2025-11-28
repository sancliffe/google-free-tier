#!/bin/bash
#
# Phase 4: Set up SSL with Let's Encrypt and Certbot.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Function to prompt for user input ---
prompt_for_details() {
    # Prompt for Domain
    while [[ -z "${DOMAIN:-}" ]]; do
        read -p "Enter your full domain name (e.g., my.duckdns.org): " DOMAIN
        if [[ -z "${DOMAIN}" ]]; then
            log_error "Domain cannot be empty."
        fi
    done
    
    # Prompt for Email
    while [[ -z "${EMAIL:-}" ]]; do
        read -p "Enter your email (for renewal notices): " EMAIL
        # Basic email validation
        if ! [[ "${EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            log_error "Please enter a valid email address."
            EMAIL="" # Reset for re-looping
        fi
    done
}

# --- DNS Pre-flight Check ---
check_dns() {
    log_info "Performing DNS pre-flight check for ${DOMAIN}..."
    
    # Get the server's public IP
    local public_ip
    public_ip=$(curl -s http://ifconfig.me/ip)
    
    # Get the domain's resolved IP
    local domain_ip
    domain_ip=$(dig +short "${DOMAIN}")

    if [[ -z "${domain_ip}" ]]; then
        log_error "DNS record for ${DOMAIN} not found."
        log_info "Please create an A record pointing to ${public_ip} and wait a few minutes."
        exit 1
    fi
    
    if [[ "${public_ip}" != "${domain_ip}" ]]; then
        log_error "DNS mismatch!"
        log_error "  - Your server's public IP: ${public_ip}"
        log_error "  - ${DOMAIN} points to:   ${domain_ip}"
        log_info "Please update your DNS A record and wait for it to propagate."
        exit 1
    fi
    
    log_success "DNS check passed. ${DOMAIN} correctly points to this server."
}


# --- Main Logic ---
main() {
    log_info "--- Phase 4: Setting up SSL with Let's Encrypt ---"
    ensure_root

    # Support both Env Vars and CLI Args
    DOMAIN="${1:-${DOMAIN}}"
    EMAIL="${2:-${EMAIL}}"

    if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
        prompt_for_details
    else
        log_info "Using domain and email from environment/arguments."
    fi
    
    # Ensure dependencies are installed
    if ! command -v certbot &> /dev/null; then
        log_info "Certbot is not installed. Installing now..."
        wait_for_apt
        apt-get update -qq
        apt-get install -y -qq certbot python3-certbot-nginx
        log_success "Certbot installed."
    fi

    # Ensure Nginx is configured for this domain
    # Certbot needs a server block with a matching server_name to work correctly
    local nginx_config="/etc/nginx/sites-available/${DOMAIN}"
    if [[ ! -f "${nginx_config}" ]]; then
        log_info "Creating Nginx server block for ${DOMAIN}..."
        
        cat <<EOF > "${nginx_config}"
server {
    listen 80;
    server_name ${DOMAIN};
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        # Link to enabled sites
        ln -sf "${nginx_config}" "/etc/nginx/sites-enabled/"
        
        # Remove default config if it exists to avoid conflicts
        if [[ -f "/etc/nginx/sites-enabled/default" ]]; then
            log_info "Disabling default Nginx config..."
            rm "/etc/nginx/sites-enabled/default"
        fi

        log_info "Reloading Nginx to apply changes..."
        systemctl reload nginx
    else
        log_info "Nginx configuration for ${DOMAIN} already exists."
    fi

    check_dns

    log_info "Requesting SSL certificate for ${DOMAIN}..."
    certbot --nginx \
        -d "${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        -m "${EMAIL}" \
        --redirect \
        --expand

    if [[ $? -eq 0 ]]; then
        log_success "SSL Certificate installed and configured successfully!"
        log_info "Your site is now available at: https://${DOMAIN}"
        certbot renew --dry-run
    else
        log_error "Certbot failed to obtain an SSL certificate."
    fi
    
    log_info "----------------------------------------------------"
}

main "$@"