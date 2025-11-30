#!/bin/bash
#
# Phase 3: Set up DuckDNS for dynamic IP updates.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=2-host-setup/common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Constants ---
INSTALL_DIR="${HOME}/.duckdns"
SCRIPT_FILE="${INSTALL_DIR}/update.sh"
LOG_FILE="${INSTALL_DIR}/duck.log"

# --- Main Logic ---
main() {
    log_info "--- Phase 3: Setting up DuckDNS ---"

        # Read secrets from environment variables

        local DOMAIN="${DOMAIN_NAME}"

        local TOKEN="${DD_AUTH_STRING}"

    

        if [[ -z "${DOMAIN}" || -z "${TOKEN}" ]]; then

            log_error "Required secrets (DOMAIN_NAME or DD_AUTH_STRING) not found in environment. Ensure startup script ran successfully."

            exit 1

        fi
    log_info "Using credentials from environment."

    log_info "Creating installation directory at ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"

    # No longer storing token in local file, read directly from file
    log_info "Creating updater script: ${SCRIPT_FILE}"
    
    cat <<EOF > "${SCRIPT_FILE}"
#!/bin/bash
# Auto-generated DuckDNS update script
# Logs to: ${LOG_FILE}

# This script is called by cron with the domain and token as arguments

if [[ \$# -ne 2 ]]; then
    echo "Usage: \$0 <domain> <token>"
    exit 1
fi

DOMAIN="\$1"
TOKEN="\$2"

RESPONSE="\$(curl -s "https://www.duckdns.org/update?domains=\${DOMAIN}&token=\${TOKEN}&ip=")"

if [[ "\$RESPONSE" == "OK" ]]; then
    echo "\$(date -u +"%Y-%m-%dT%H:%M:%SZ") [OK] DuckDNS update successful: \$RESPONSE" >> "${LOG_FILE}"
    exit 0
else
    echo "\$(date -u +"%Y-%m-%dT%H:%M:%SZ") [ERROR] DuckDNS update failed: \$RESPONSE" >> "${LOG_FILE}"
    exit 1
fi
EOF

    log_info "Setting script permissions..."
    chmod 700 "${SCRIPT_FILE}"

    log_info "Running initial test..."
    if "${SCRIPT_FILE}" "${DOMAIN}" "${TOKEN}"; then
        log_success "DuckDNS initial update successful."
        log_info "Setting up cron job to run every 5 minutes..."
        
        CRON_CMD="*/5 * * * * ${SCRIPT_FILE} '${DOMAIN}' '${TOKEN}' >> ${LOG_FILE} 2>&1"
        # Safer cron manipulation
        (crontab -l 2>/dev/null | grep -vF "${SCRIPT_FILE}"; echo "${CRON_CMD}") | crontab -

        log_success "Cron job successfully configured."
    else
        log_error "DuckDNS initial update failed. Please check your settings and the log for details: ${LOG_FILE}"
    fi

    log_info "-------------------------------------"
}

main "$@"