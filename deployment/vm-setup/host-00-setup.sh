#!/bin/bash
#
# This script orchestrates the entire Host setup process.
# It runs on the VM instance to configure software and settings.
# It runs each setup script in sequence.

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

set_strict_mode

# Source common logging functions
# shellcheck disable=SC1091

# Legacy function for backward compatibility
log() {
    log_info "$@"
}

# Ensure running as root
ensure_root

# --- Main ---

# --- Diagnostic Check ---
if [[ "${DEBUG:-false}" != "true" ]]; then
    log_error "DIAGNOSTIC: DEBUG environment variable was not set to 'true'. This indicates the orchestrator script (gcp-00-setup.sh) may be stale or is not exporting it correctly. Aborting."
    exit 1
fi
# --- End Diagnostic Check ---

# Default flags for skipping steps
SKIP_SWAP=false
SKIP_DUCKDNS=false
SKIP_FIREWALL=false
SKIP_NGINX=false
NON_INTERACTIVE=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --skip-swap) SKIP_SWAP=true ;;
        --skip-duckdns) SKIP_DUCKDNS=true ;;
        --skip-firewall) SKIP_FIREWALL=true ;;
        --skip-nginx) SKIP_NGINX=true ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --skip-swap         Skip swap file configuration."
            echo "  --skip-duckdns      Skip DuckDNS setup."
            echo "  --skip-firewall     Skip firewall configuration."
            echo "  --skip-nginx        Skip Nginx installation."
            echo "  --non-interactive   Run without user prompts."
            echo "  -h, --help          Display this help message."
            exit 0
            ;;
        *) log_error "Unknown option: $1. Use -h or --help for usage."; exit 1 ;;
    esac
    shift
done

print_newline
print_banner
log_info "Starting Host setup..."
log_info "⏱️  Estimated time: 5-10 minutes"
print_banner
print_newline

# Verify required tools
for tool in grep sed awk; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "Required tool '$tool' is not installed."
        exit 1
    fi
done

START_TIME=$(date +%s)

# Ensure sub-scripts are executable
find "${SCRIPT_DIR}" -maxdepth 1 -name "host-0[1-9]*.sh" -exec chmod +x {} \;

log "Checking existing configuration..."

# Flags for actual execution status
RUN_SWAP=true
RUN_DUCKDNS=true
RUN_FIREWALL=true
RUN_NGINX=true

print_newline
# Check Swap (Phase 1)
if grep -q "/swapfile" /etc/fstab; then
  log_info "  ⏭️  Swap file: Already configured"
  RUN_SWAP=false
else
  log_info "  ✨ Swap file: Will configure"
fi

# Apply skip flags
if "$SKIP_SWAP"; then
    log "  ⏭️  Swap configuration: Skipped by --skip-swap flag."
    RUN_SWAP=false
fi
if "$SKIP_DUCKDNS"; then
    log "  ⏭️  DuckDNS setup: Skipped by --skip-duckdns flag."
    RUN_DUCKDNS=false
fi
if "$SKIP_FIREWALL"; then
    log "  ⏭️  Firewall configuration: Skipped by --skip-firewall flag."
    RUN_FIREWALL=false
fi
if "$SKIP_NGINX"; then
    log "  ⏭️  Nginx installation: Skipped by --skip-nginx flag."
    RUN_NGINX=false
fi

print_newline

log "📊 Final Plan:"
log "  Swap Configuration: $(if "$RUN_SWAP"; then echo "RUN"; else echo "SKIP"; fi)"
log "  DuckDNS Setup:      $(if "$RUN_DUCKDNS"; then echo "RUN"; else echo "SKIP"; fi)"
log "  Firewall Config:    $(if "$RUN_FIREWALL"; then echo "RUN"; else echo "SKIP"; fi)"
log "  Nginx Installation: $(if "$RUN_NGINX"; then echo "RUN"; else echo "SKIP"; fi)"
echo ""

if [ -t 0 ] && ! "$NON_INTERACTIVE"; then
    read -p "Continue with setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Setup cancelled."
      exit 0
    fi
else
    log_info "Non-interactive mode detected. Proceeding..."
fi

print_newline
print_banner
log_info "🚀 Starting setup execution..."
print_banner

# Execute setup scripts based on flags
if "$RUN_SWAP"; then
    log "Step 1/4: Configuring Swap..."
    "${SCRIPT_DIR}/host-01-create-swap.sh"
fi

if "$RUN_DUCKDNS"; then
    log "Step 2/4: Setting up DuckDNS..."
    "${SCRIPT_DIR}/host-02-setup-duckdns.sh"
fi

if "$RUN_FIREWALL"; then
    log "Step 3/4: Configuring Firewall..."
    "${SCRIPT_DIR}/host-03-firewall-config.sh"
fi

if "$RUN_NGINX"; then
    log "Step 4/4: Installing Nginx..."
    "${SCRIPT_DIR}/host-04-install-nginx.sh"
fi

print_newline
print_banner
log_info "✅ Host setup completed successfully!"
print_banner

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log_info "⏱️  Total setup time: $((DURATION / 60))m $((DURATION % 60))s"