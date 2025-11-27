#!/bin/bash
#
# Phase 7: Harden server security with Fail2Ban.
#
# This script installs Fail2Ban and configures it to protect against
# brute-force attacks on SSH and Nginx.

source "/tmp/2-host-setup/common.sh"

# --- Main Logic ---
main() {
    log_info "--- Phase 7: Hardening Security with Fail2Ban ---"
    ensure_root

    if dpkg-query -W fail2ban &>/dev/null; then
        log_success "Fail2Ban is already installed. Skipping installation."
    else
        log_info "Installing Fail2Ban..."
        apt-get update -qq
        apt-get install -y -qq fail2ban
        log_success "Fail2Ban installed successfully."
    fi

    log_info "Creating Fail2Ban local configuration..."
    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
# Ban hosts for 10 minutes
bantime = 10m

# Override /etc/fail2ban/jail.d/defaults-debian.conf
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
        log_error "Fail2Ban is not running. Please check the service status."
        log_info "👉 Try running: sudo systemctl status fail2ban"
        exit 1
    fi

    log_info "----------------------------------------------------"
}

main "$@"
