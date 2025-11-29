#!/bin/bash
#
# Phase 7: Harden server security.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Main Logic ---
main() {
    log_info "--- Phase 7: Hardening Server Security ---"
    ensure_root || exit 1

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
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
EOF

    systemctl restart fail2ban
    if systemctl is-active --quiet fail2ban; then
        log_success "Fail2Ban is running."
    else
        log_error "Fail2Ban is not running. Check status."
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

    echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades

    # --- 3. SSH Hardening ---
    log_info "Hardening SSH configuration..."

    # More reliable check for SSH keys before disabling password auth to prevent lockout
    check_ssh_keys() {
        local has_keys=false
        
        # Check if we're connected via SSH key right now
        if [ -n "${SSH_CONNECTION:-}" ]; then
            # Check the auth method of current session (requires sudo/root to read auth.log)
            if grep -q "Accepted publickey" /var/log/auth.log 2>/dev/null; then
                log_info "Current SSH session using key authentication"
                has_keys=true
            fi
        fi
        
        # Check for any authorized_keys
        if [ -s "$HOME/.ssh/authorized_keys" ] || \
           [ -s /root/.ssh/authorized_keys ]; then
            has_keys=true
        fi
        
        echo "$has_keys"
    }

    local has_keys
    has_keys=$(check_ssh_keys)


    if [[ "$has_keys" == "false" ]]; then
        log_warn "NO SSH KEYS DETECTED! Skipping SSH hardening to prevent lockout."
        log_warn "Please set up SSH keys before disabling password authentication."
    else
        # Safe to proceed
        cat <<EOF > /etc/ssh/sshd_config.d/99-hardening.conf
# Hardened SSH Configuration
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
EOF

        # Validate config before restarting
        if sshd -t; then
            log_info "Restarting SSH service..."
            systemctl restart sshd
            log_success "SSH security hardening applied."
        else
            log_error "SSH configuration invalid! Reverting..."
            rm /etc/ssh/sshd_config.d/99-hardening.conf
        fi
    fi

    log_info "----------------------------------------------------"
}

main "$@"