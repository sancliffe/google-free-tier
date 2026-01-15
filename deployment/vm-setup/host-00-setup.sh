#!/bin/bash
#
# This script orchestrates the entire Host setup process.
# It runs on the VM instance to configure software and settings.
# It runs each setup script in sequence.

set -eo pipefail

# --- Preamble ---

# Absolute path to the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common logging functions
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || {
    # Fallback logging functions if common.sh is not available
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    NC='\033[0m'
    
    log_info() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${CYAN}[INFO]${NC} $*"
    }
    log_error() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${RED}[ERROR]${NC} $*" >&2
    }
    log_success() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${GREEN}[✅ SUCCESS]${NC} $*"
    }
    log_warn() {
        echo -e "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${YELLOW}[WARN]${NC} $*"
    }
}

# Legacy function for backward compatibility
log() {
    log_info "$@"
}

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root."
   exit 1
fi

# --- Main ---

echo ""
printf '=%.0s' {1..60}; echo
log "Starting Host setup..."
log "⏱️  Estimated time: 5-10 minutes"
printf '=%.0s' {1..60}; echo
echo ""

# Verify required tools
for tool in grep sed awk; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

START_TIME=$(date +%s)

# Ensure scripts are executable
chmod +x "${SCRIPT_DIR}"/host-0[1-9]*.sh 2>/dev/null || true

log "Checking existing configuration..."
SKIP_COUNT=0
CREATE_COUNT=0

echo ""
# Check Swap (Phase 1)
if grep -q "/swapfile" /etc/fstab; then
  log "  ⏭️  Swap file: Already configured"
  SKIP_COUNT=$((SKIP_COUNT + 1))
else
  log "  ✨ Swap file: Will configure"
  CREATE_COUNT=$((CREATE_COUNT + 1))
fi

echo ""
log "📊 Summary: $((CREATE_COUNT + 3)) tasks to run, $SKIP_COUNT tasks to skip"
echo ""

if [ -t 0 ]; then
    read -p "Continue with setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log "Setup cancelled."
      exit 0
    fi
else
    log "Non-interactive session detected. Proceeding..."
fi

echo ""
printf '=%.0s' {1..60}; echo
log "🚀 Starting setup execution..."
printf '=%.0s' {1..60}; echo

# Execute setup scripts in order
log "Step 1/4: Configuring Swap..."
"${SCRIPT_DIR}/host-01-create-swap.sh"

"${SCRIPT_DIR}/host-02-setup-duckdns.sh"
log "Step 2/4: Setting up DuckDNS..."
"${SCRIPT_DIR}/host-02-setup-duckdns.sh"

log "Step 3/4: Configuring Firewall..."
"${SCRIPT_DIR}/host-03-firewall-config.sh"

log "Step 4/4: Installing Nginx..."
"${SCRIPT_DIR}/host-04-install-nginx.sh"

echo ""
printf '=%.0s' {1..60}; echo
log "✅ Host setup completed successfully!"
printf '=%.0s' {1..60}; echo

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
log "⏱️  Total setup time: $((DURATION / 60))m $((DURATION % 60))s"
echo ""