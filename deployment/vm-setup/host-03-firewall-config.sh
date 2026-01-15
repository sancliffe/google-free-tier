#!/bin/bash
# host-03-firewall-config.sh
# Configures UFW (Uncomplicated Firewall) on the host.

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"
set_strict_mode

print_newline
log_info "Starting Firewall configuration..."
print_newline

check_root

# 1. Fetch SSH allowed IPs (optional)
SSH_SOURCE_IPS=$(fetch_secret "ssh_allowed_ips" "SSH_ALLOWED_IPS")
if [[ -z "$SSH_SOURCE_IPS" ]]; then
    log_error "Failed to retrieve 'ssh_allowed_ips'. SSH access cannot be restricted. Exiting for security."
    exit 1
fi

# 2. Install UFW
if ! command -v ufw &> /dev/null; then
    log_warn "UFW is not installed. Installing now..."
    install_packages "ufw"
    log_success "UFW installed successfully."
fi

# 3. Reset UFW to defaults
log_info "Resetting UFW rules to default..."
ufw --force reset >/dev/null

# 4. Set Default Policies
log_info "Setting default policies (Deny Incoming, Allow Outgoing)..."
ufw default deny incoming
ufw default allow outgoing

# 5. Allow Critical Ports
log_info "Allowing SSH (Port 22)..."
log_info "Restricting SSH access to: $SSH_SOURCE_IPS"
ufw allow from "$SSH_SOURCE_IPS" to any port 22/tcp
log_info "Rule added: Allow SSH"

# Add SSH rate limiting
log_info "Adding SSH rate limiting..."
ufw limit ssh
log_info "Rule added: Limit SSH attempts"

log_info "Allowing HTTP (Port 80)..."
ufw allow 80/tcp
log_info "Rule added: Allow HTTP"

log_info "Allowing HTTPS (Port 443)..."
ufw allow 443/tcp
log_info "Rule added: Allow HTTPS"

# 6. Enable UFW Logging
log_info "Enabling UFW logging..."
ufw logging on

# 7. Enable UFW
log_info "Enabling UFW..."
# --force avoids the "Command may disrupt existing ssh connections" prompt
ufw --force enable

# 8. Verify
log_info "Verifying Firewall Status..."
ufw status verbose

log_success "Firewall configured successfully."