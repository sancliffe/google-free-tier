#!/bin/bash
# host-03-firewall-config.sh
# Configures UFW (Uncomplicated Firewall) on the host.

set -e
source "$(dirname "$0")/common.sh"

echo ""
echo "============================================================"
log_info "Phase 5: Adjusting Local Firewall (UFW)"
echo "============================================================"
echo ""

check_root

# 1. Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    log_warn "UFW is not installed. Installing now..."
    wait_for_apt_lock
    apt-get update -qq && apt-get install -y ufw -qq
    log_success "UFW installed successfully."
fi

# 2. Reset UFW to defaults
log_info "Resetting UFW rules to default..."
ufw --force reset >/dev/null

# 3. Set Default Policies
log_info "Setting default policies (Deny Incoming, Allow Outgoing)..."
ufw default deny incoming
ufw default allow outgoing

# 4. Allow Critical Ports
log_info "Allowing SSH (Port 22)..."
ufw allow 22/tcp
log_info "Rule added: Allow SSH"

log_info "Allowing HTTP (Port 80)..."
ufw allow 80/tcp
log_info "Rule added: Allow HTTP"

log_info "Allowing HTTPS (Port 443)..."
ufw allow 443/tcp
log_info "Rule added: Allow HTTPS"

# 5. Enable UFW
log_info "Enabling UFW..."
# --force avoids the "Command may disrupt existing ssh connections" prompt
ufw --force enable

# 6. Verify
log_info "Verifying Firewall Status..."
ufw status verbose

log_success "Firewall configured successfully."