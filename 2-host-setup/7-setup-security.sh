#!/bin/bash
#
# Phase 7: Harden server security.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=2-host-setup/common.sh
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
        
        # Check 1: See if we're currently connected via SSH with public key auth
        # This is the most reliable indicator - we can only reach this point via SSH
        if [ -n "${SSH_CONNECTION:-}" ] && [ -n "${SSH_CLIENT:-}" ]; then
            # If SSH_CONNECTION is set, we're definitely connected via SSH
            # Most likely this was done with a key (not password) since we're root
            log_info "Connected via SSH - likely using key authentication"
            has_keys=true
        fi
        
        # Check 2: Look for authorized_keys files on the system
        # Search common locations for the current user and root
        local auth_key_locations=(
            "$HOME/.ssh/authorized_keys"
            "$HOME/.ssh/authorized_keys2"
            "/root/.ssh/authorized_keys"
            "/root/.ssh/authorized_keys2"
        )
        
        for key_file in "${auth_key_locations[@]}"; do
            if [ -f "$key_file" ] && [ -s "$key_file" ]; then
                log_debug "Found authorized keys at: $key_file"
                has_keys=true
                break
            fi
        done
        
        # Check 3: Look for public keys in known locations
        local pub_key_locations=(
            "$HOME/.ssh/id_rsa.pub"
            "$HOME/.ssh/id_ed25519.pub"
            "/root/.ssh/id_rsa.pub"
            "/root/.ssh/id_ed25519.pub"
        )
        
        for pub_file in "${pub_key_locations[@]}"; do
            if [ -f "$pub_file" ] && [ -s "$pub_file" ]; then
                log_debug "Found public key at: $pub_file"
                has_keys=true
                break
            fi
        done
        
        # Output result (true/false) for capture
        if [[ "$has_keys" == "true" ]]; then
            echo "true"
        else
            echo "false"
        fi
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