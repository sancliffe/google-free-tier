#!/bin/bash
# host-02-setup-duckdns.sh
# Sets up a cron job to update DuckDNS for dynamic IP.

set -e
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

echo ""
echo "============================================================"
log_info "Phase 3: Setting up DuckDNS"
echo "============================================================"
echo ""

check_root

# 1. Fetch Credentials
log_info "Fetching DuckDNS credentials..."
DUCKDNS_DOMAIN=$(fetch_secret "domain_name" "DOMAIN")
DUCKDNS_TOKEN=$(fetch_secret "duckdns_token" "DUCKDNS_TOKEN")

if [[ -z "$DUCKDNS_DOMAIN" || -z "$DUCKDNS_TOKEN" ]]; then
    log_error "Failed to retrieve DuckDNS credentials."
    log_info "Please ensure secrets are in Secret Manager OR 'DUCKDNS_DOMAIN' and 'DUCKDNS_TOKEN' are set in config.sh."
    exit 1
fi

log_info "Configuring DuckDNS for domain: $DUCKDNS_DOMAIN"

# 2. Create Script Directory
INSTALL_DIR="/opt/duckdns"
mkdir -p "$INSTALL_DIR"

# 3. Create Update Script
SCRIPT_PATH="$INSTALL_DIR/duck.sh"
LOG_PATH="/var/log/duckdns.log"

cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
# Update DuckDNS
echo url="https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" | curl -k -o $LOG_PATH -K -
EOF

chmod +x "$SCRIPT_PATH"
log_success "Created update script at $SCRIPT_PATH"

# 4. Run once to verify
log_info "Testing DuckDNS update..."
"$SCRIPT_PATH"

if grep -q "OK" "$LOG_PATH"; then
    log_success "DuckDNS update successful (Response: OK)."
else
    log_warn "DuckDNS update might have failed. Check $LOG_PATH."
    cat "$LOG_PATH"
fi

# 5. Setup Cron Job (Run every 5 minutes)
CRON_JOB="*/5 * * * * $SCRIPT_PATH >/dev/null 2>&1"
CRON_FILE="/etc/cron.d/duckdns"

echo "$CRON_JOB" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

log_success "Cron job created at $CRON_FILE"