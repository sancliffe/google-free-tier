#!/bin/bash
#
# Phase 4: Set up SSL with Let's Encrypt and Certbot.
#
# This script automates the installation of an SSL certificate for a given
# domain. It requires Nginx to be installed and the domain's DNS A record
# to be pointing to this server's IP address.

source "/tmp/2-host-setup/common.sh"

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

    # Allow passing credentials as arguments for automation
    # ./setup_ssl.sh [domain] [email]
    DOMAIN="${1:-}"
    EMAIL="${2:-}"

    if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
        prompt_for_details
    else
        log_info "Using domain and email from script arguments."
    fi
    
    # --- Dependencies ---
    if ! command -v certbot &> /dev/null; then
        log_info "Certbot is not installed. Installing now..."
        apt-get update -qq
        apt-get install -y -qq certbot python3-certbot-nginx
        log_success "Certbot installed."
    fi

    # --- Pre-flight checks ---
    check_dns

    log_info "Requesting SSL certificate for ${DOMAIN}..."
    log_info "This may take a few seconds..."

    # Use certbot to get the certificate.
    # The flags make it non-interactive.
    certbot --nginx \
        -d "${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        -m "${EMAIL}" \
        --redirect \
        --expand

    # Check the exit code of the last command
    if [[ $? -eq 0 ]]; then
        log_success "SSL Certificate installed and configured successfully!"
        log_info "Your site is now available at: https://${DOMAIN}"
        
        log_info "Testing certificate auto-renewal..."
        certbot renew --dry-run
    else
        log_error "Certbot failed to obtain an SSL certificate."
        log_info "Common issues:"
        log_info "  1. DNS propagation: Did you wait long enough after setting the A record?"
        log_info "  2. GCP Firewall: Ensure 'http-server' and 'https-server' tags are applied to the VM."
        log_info "  3. Nginx is not running or configured correctly."
    fi
    
    log_info "----------------------------------------------------"
}

main "$@"
