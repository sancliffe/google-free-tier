#!/bin/bash
#
# Phase 5: Adjust the local firewall (UFW).
#
# This script opens ports for Nginx (HTTP & HTTPS) if the UFW firewall
# is active on the VM.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
    log_info "--- Phase 5: Adjusting Local Firewall (UFW) ---"
    ensure_root || exit 1

    # Check if ufw is installed
    #
    # `command -v` is a reliable way to check if a command exists.
    if ! command -v ufw &> /dev/null; then
        log_warn "UFW is not installed. Skipping firewall adjustment."
        log_info "-------------------------------------------------"
        exit 0
    fi

    # Check if ufw is active
    if ! ufw status | grep -q "Status: active"; then
        log_warn "UFW is not active. Skipping firewall adjustment."
        log_info "You can enable it with: sudo ufw enable"
        log_info "-------------------------------------------------"
        exit 0
    fi

    log_info "Allowing 'Nginx Full' profile in UFW..."
    # The 'Nginx Full' profile includes both port 80 (HTTP) and 443 (HTTPS).
    # The `ufw allow` command is idempotent; it won't add a duplicate rule.
    ufw allow 'Nginx Full'

    log_success "Firewall rule for Nginx applied."
    log_info "-------------------------------------------------"
}

main "${1:-}"