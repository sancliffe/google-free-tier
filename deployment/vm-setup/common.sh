#!/bin/bash
# common.sh
# Shared utilities and configuration for VM setup scripts.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
log_info() {
    echo -e "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [${BLUE}INFO${NC}] $1"
}

log_warn() {
    echo -e "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [${YELLOW}WARN${NC}] $1"
}

log_error() {
    echo -e "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [${RED}ERROR${NC}] $1" >&2
}

log_success() {
    echo -e "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [${GREEN}SUCCESS${NC}] $1"
}

# -----------------------------------------------------------------------------
# Error Handling & Mode Settings
# -----------------------------------------------------------------------------
# Exit logic that can be trapped
handle_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "An error occurred on line $1. Exit code: $exit_code"
        exit $exit_code
    fi
}

# Sets strict bash modes to fail on error, unset vars, or pipe failures
set_strict_mode() {
    set -euo pipefail
    trap 'handle_error $LINENO' ERR
}

# -----------------------------------------------------------------------------
# Secret Management
# -----------------------------------------------------------------------------
# Usage: fetch_secret "secret_name_in_gcp" "env_var_fallback_name"
fetch_secret() {
    local secret_name="$1"
    local env_var_name="${2:-}"
    local secret_value=""

    # 1. Try to fetch from Google Cloud Secret Manager
    if command -v gcloud &> /dev/null; then
        # Check if we are authenticated or on a VM with scopes
        if secret_value=$(gcloud secrets versions access latest --secret="$secret_name" --quiet 2>/dev/null); then
            if [[ -n "$secret_value" ]]; then
                echo "$secret_value"
                return 0
            fi
        fi
    fi

    # 2. Try Environment Variable (if passed as argument)
    if [[ -n "$env_var_name" && -n "${!env_var_name}" ]]; then
        # Check if variable is set in current environment
        echo "${!env_var_name}"
        return 0
    fi

    # 3. Try reading from a local config.sh file (Fallback)
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")
    if [[ -f "$script_dir/config.sh" ]]; then
        # Source the config file in a subshell to check for the variable
        secret_value=$(source "$script_dir/config.sh" 2>/dev/null && echo "${!env_var_name}")
        if [[ -n "$secret_value" ]]; then
            echo "$secret_value"
            return 0
        fi
    fi

    # 4. If all fail, return 1
    log_warn "Could not retrieve secret '$secret_name' from Secret Manager or environment variable '$env_var_name'." >&2
    return 1
}

# -----------------------------------------------------------------------------
# System Utilities
# -----------------------------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Please use sudo."
        exit 1
    fi
}

# Alias for check_root
ensure_root() {
    check_root
}

backup_file() {
    local file_path="$1"
    local dest_dir="${2:-}" 
    
    if [ -f "$file_path" ]; then
        local timestamp
        timestamp=$(date +%s)
        local backup_path
        
        if [ -n "$dest_dir" ]; then
             mkdir -p "$dest_dir"
             backup_path="${dest_dir}/$(basename "$file_path").bak.${timestamp}"
        else
             backup_path="${file_path}.bak.${timestamp}"
        fi
        
        cp "$file_path" "$backup_path"
        log_success "Backed up '$file_path' to '$backup_path'"
    else
        log_warn "File '$file_path' does not exist, skipping backup."
    fi
}

wait_for_apt_lock() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        log_info "Waiting for other apt processes to finish..."
        sleep 2
    done
}

# Alias for wait_for_apt_lock to fix script errors
wait_for_apt() {
    wait_for_apt_lock
}

check_disk_space() {
    local path="$1"
    local required_mb="$2"
    
    # Get available space in KB
    local available_kb
    available_kb=$(df -k --output=avail "$path" | tail -n 1)
    local available_mb=$((available_kb / 1024))
    
    if [[ "$available_mb" -lt "$required_mb" ]]; then
        log_error "Insufficient disk space on $path. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    log_info "Disk space check passed. Available: ${available_mb}MB"
}