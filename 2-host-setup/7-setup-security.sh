#!/bin/bash
#
# Phase 7: Harden server security.
#
# This script installs Fail2Ban, enables unattended security updates,
# and hardens the SSH configuration.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Main Logic ---
main() {
    log_info "--- Phase 7: Hardening Server Security ---"
    ensure_root

    # --- 1. Fail2Ban ---
    if dpkg-query -W fail2ban &>/dev/null; then
        log_success "Fail2Ban is already installed."
    else
        log_info "Installing Fail2Ban..."
        wait_for_apt
        apt-get update -qq
        apt-get install -y -qq fail2ban
        log_success "Fail2Ban installed successfully."
    fi

    log_info "Configuring Fail2Ban..."
    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
# Ban hosts for 1 hour
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
EOF

    log_info "Restarting Fail2Ban service..."
    systemctl restart fail2ban

    if systemctl is-active --quiet fail2ban; then
        log_success "Fail2Ban is running."
    else
        log_error "Fail2Ban is not running. Please check: sudo systemctl status fail2ban"
    fi

    # --- 2. Unattended Upgrades ---
    if dpkg-query -W unattended-upgrades &>/dev/null; then
        log_success "Unattended Upgrades is already installed."
    else
        log_info "Installing Unattended Upgrades..."
        wait_for_apt
        apt-get install -y -qq unattended-upgrades
        log_success "Unattended Upgrades installed."
    fi

    log_info "Enabling automatic security updates..."
    # Pre-seed the configuration to enable auto updates without prompting
    echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades

    # --- 3. SSH Hardening ---
    log_info "Hardening SSH configuration..."
    
    # Create a drop-in configuration file for overrides
    # Debian 12 uses /etc/ssh/sshd_config.d/ by default.
    cat <<EOF > /etc/ssh/sshd_config.d/99-hardening.conf
# Hardened SSH Configuration added by setup script
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
EOF

    log_info "Restarting SSH service..."
    systemctl restart sshd

    log_success "Security hardening complete."
    log_info "----------------------------------------------------"
}

main "$@"