#!/bin/bash
#
# Phase 3: Set up DuckDNS for dynamic IP updates.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Constants ---
INSTALL_DIR="${HOME}/.duckdns"
SCRIPT_FILE="${INSTALL_DIR}/update.sh"
LOG_FILE="${INSTALL_DIR}/duck.log"

# --- Function to prompt for user input ---
prompt_for_credentials() {
    while [[ -z "${DOMAIN:-}" ]]; do
        read -p "Enter your DuckDNS Subdomain (e.g., 'myserver'): " DOMAIN
        if [[ -z "${DOMAIN}" ]]; then log_error "Domain cannot be empty."; fi
    done
    
    while [[ -z "${TOKEN:-}" ]]; do
        read -s -p "Enter your DuckDNS Token: " TOKEN
        echo ""
        if [[ -z "${TOKEN}" ]]; then log_error "Token cannot be empty."; fi
    done
}

# --- Main Logic ---
main() {
    log_info "--- Phase 3: Setting up DuckDNS ---"

    # Support both Env Vars and CLI Args
    DOMAIN="${1:-${DOMAIN:-}}"
    TOKEN="${2:-${DUCKDNS_TOKEN:-}}"

    if [[ -z "${DOMAIN}" || -z "${TOKEN}" ]]; then
        prompt_for_credentials
    else
        log_info "Using credentials from environment/arguments."
    fi

    log_info "Creating installation directory at ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"

    log_info "Storing DuckDNS token securely in ${INSTALL_DIR}/.token..."
    cat <<EOF > "${INSTALL_DIR}/.token"
${TOKEN}
EOF
    chmod 600 "${INSTALL_DIR}/.token"

    log_info "Creating updater script: ${SCRIPT_FILE}"
    
    cat <<EOF > "${SCRIPT_FILE}"
#!/bin/bash
# Auto-generated DuckDNS update script
# Logs to: ${LOG_FILE}

DIR="\$(cd "\$(dirname "\$0")" && pwd)"
LOG_FILE="\${DIR}/duck.log"

TOKEN="$(cat "${DIR}/.token")"
RESPONSE="\$(curl -s "https://www.duckdns.org/update?domains=${DOMAIN}&token=\${TOKEN}&ip=")"

if [[ "\$RESPONSE" == "OK" ]]; then
    echo "\$(date -u +"%Y-%m-%dT%H:%M:%SZ") [OK] DuckDNS update successful: \$RESPONSE" >> "\${LOG_FILE}"
    exit 0
else
    echo "\$(date -u +"%Y-%m-%dT%H:%M:%SZ") [ERROR] DuckDNS update failed: \$RESPONSE" >> "\${LOG_FILE}"
    exit 1
fi
EOF

    log_info "Setting script permissions..."
    chmod 700 "${SCRIPT_FILE}"

    log_info "Running initial test..."
    if "${SCRIPT_FILE}"; then
        log_success "DuckDNS initial update successful."
        log_info "Setting up cron job to run every 5 minutes..."
        
        CRON_CMD="*/5 * * * * ${SCRIPT_FILE} >> ${LOG_FILE} 2>&1"
        # Safer cron manipulation
        (crontab -l 2>/dev/null | grep -vF "${SCRIPT_FILE}"; echo "${CRON_CMD}") | crontab -

        log_success "Cron job successfully configured."
    else
        log_error "DuckDNS initial update failed. Please check your settings and the log for details: ${LOG_FILE}"
    fi

    log_info "-------------------------------------"
}

main "$@"