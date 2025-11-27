#!/bin/bash
#
# Phase 3: Set up DuckDNS for dynamic IP updates.

source "/tmp/2-host-setup/common.sh"

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

    DOMAIN="${1:-}"
    TOKEN="${2:-}"

    if [[ -z "${DOMAIN}" || -z "${TOKEN}" ]]; then
        prompt_for_credentials
    else
        log_info "Using domain and token from script arguments."
    fi

    log_info "Creating installation directory at ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"

    log_info "Creating updater script: ${SCRIPT_FILE}"
    
    # Use consistent ISO 8601 timestamps in the generated script
    cat <<EOF > "${SCRIPT_FILE}"
#!/bin/bash
# Auto-generated DuckDNS update script
# Logs to: ${LOG_FILE}

DIR="\$(cd "\$(dirname "\$0")" && pwd)"
LOG_FILE="\${DIR}/duck.log"

# Log format: YYYY-MM-DDTHH:MM:SSZ [Result]
echo -n "\$(date -u +"%Y-%m-%dT%H:%M:%SZ") " >> "\${LOG_FILE}"
curl -s "https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ip=" >> "\${LOG_FILE}"
echo "" >> "\${LOG_FILE}"
EOF

    log_info "Setting script permissions..."
    chmod 700 "${SCRIPT_FILE}"

    log_info "Running initial test..."
    "${SCRIPT_FILE}"

    if tail -n 1 "${LOG_FILE}" | grep -q "OK"; then
        log_success "DuckDNS update successful."
        log_info "Setting up cron job to run every 5 minutes..."
        
        CRON_CMD="*/5 * * * * ${SCRIPT_FILE}"
        (crontab -l 2>/dev/null | grep -vF "${SCRIPT_FILE}"; echo "${CRON_CMD}") | crontab -

        log_success "Cron job successfully configured."
    else
        log_error "DuckDNS update failed. Please check your settings."
        log_info "See the log for details: ${LOG_FILE}"
    fi

    log_info "-------------------------------------"
}

main "$@"