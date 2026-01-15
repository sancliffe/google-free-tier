#!/bin/bash
# common.sh
# Shared utilities and configuration for VM setup scripts.

# Color codes
CYAN='\033[0;36m'      # INFO
GREEN='\033[0;32m'     # SUCCESS
YELLOW='\033[0;33m'    # WARN
RED='\033[0;31m'       # ERROR
PURPLE='\033[0;35m'    # DEBUG
NC='\033[0m'           # No Color

# Internal logging function
_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local prefix="${timestamp} ${color}[${level}]${NC}"

    # Console Output - Errors go to stderr, everything else to stdout
    if [[ "${level}" == "ERROR" ]]; then
        echo -e "${prefix} ${message}" >&2
    else
        echo -e "${prefix} ${message}"
    fi

    # File Output (if LOG_FILE is set)
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Strip ANSI color codes for plain text logging
        echo "${timestamp} [${level}] ${message}" >> "${LOG_FILE}"
    fi
}

# Logging Functions
log_info() {
    _log "INFO" "${CYAN}" "$1"
}

log_warn() {
    _log "WARN" "${YELLOW}" "$1"
}

log_error() {
    _log "ERROR" "${RED}" "$1"
}

log_success() {
    _log "✅ SUCCESS" "${GREEN}" "$1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        _log "DEBUG" "${PURPLE}" "$1"
    fi
}

error_exit() {
    log_error "$1"
    exit 1
}

# A function to run a command and log it.
# The last argument is the description.
run_command() {
    local description="${@: -1}"
    # All arguments except the last are the command
    local cmd=("${@:1:$#-1}")

    log_info "$description"
    # Execute the command
    if ! "${cmd[@]}"; then
        error_exit "Command failed: '${cmd[*]}'"
    fi
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

    if [[ -z "$secret_name" ]]; then
        log_error "fetch_secret: secret_name cannot be empty. Usage: fetch_secret <secret_name> [env_var_fallback_name]" >&2
        return 1
    fi

    # 1. Try to fetch from Google Cloud Secret Manager
    if command -v gcloud &> /dev/null; then
        # Check if we are authenticated or on a VM with scopes
        if secret_value=$(gcloud secrets versions access latest --secret="$secret_name" --quiet 2>/dev/null); then
            if [[ -n "$secret_value" ]]; then
                echo "$secret_value"
                return 0
            fi
        else
            log_debug "fetch_secret: gcloud secrets access failed for '$secret_name'. (This is expected if not authenticated or secret doesn't exist in Secret Manager)."
        fi
    fi

    # 2. Try Environment Variable (if passed as argument)
    if [[ -n "$env_var_name" && -n "${!env_var_name}" ]]; then
        # Check if variable is set in current environment
        echo "${!env_var_name}"
        return 0
    else
        log_debug "fetch_secret: Environment variable '$env_var_name' not set or empty."
    fi

    # 3. Try reading from a local config.sh file (Fallback)
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")
    if [[ -f "$script_dir/config.sh" ]]; then
        # Source the config file in a subshell to check for the variable
        # shellcheck disable=SC1091
        # Source config.sh with its stdout redirected to /dev/null to prevent
        # any 'echo' statements within config.sh from polluting the output.
        # Then, explicitly echo the value of the requested environment variable.
        secret_value=$( (source "$script_dir/config.sh" >/dev/null 2>&1; echo "${!env_var_name}") )
        if [[ -n "$secret_value" ]]; then
            echo "$secret_value"
            return 0
        fi
    else
        log_debug "fetch_secret: config.sh not found or variable '$env_var_name' not defined within it."
    fi

    # 4. If all fail, return 1
    log_error "Failed to retrieve secret '$secret_name'. Please ensure it's in Secret Manager, set as environment variable '$env_var_name', or defined in config.sh." >&2
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
    
    if [[ -z "$file_path" ]]; then
        log_error "backup_file: file_path cannot be empty. Usage: backup_file <file_to_backup> [destination_directory]"
        return 1
    fi

    if [ -f "$file_path" ]; then
        local timestamp
        timestamp=$(date +%s)
        local backup_path
        
        if [ -n "$dest_dir" ]; then
             mkdir -p "$dest_dir" || { log_error "backup_file: Failed to create backup directory '$dest_dir'."; return 1; }
             backup_path="${dest_dir}/$(basename "$file_path").bak.${timestamp}"
        else
             backup_path="${file_path}.bak.${timestamp}"
        fi
        
        cp "$file_path" "$backup_path"
        log_success "Backed up '$file_path' to '$backup_path'"
    elif [ ! -e "$file_path" ]; then # Check if it doesn't exist at all
        log_debug "File '$file_path' does not exist, skipping backup as it's not present."
    else
        log_warn "File '$file_path' is not a regular file or does not exist, skipping backup."
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
    
    if [[ -z "$path" ]]; then
        log_error "check_disk_space: path cannot be empty. Usage: check_disk_space <path> <required_mb>"
        return 1
    fi
    if ! [[ "$required_mb" =~ ^[0-9]+$ ]] || (( required_mb <= 0 )); then
        log_error "check_disk_space: required_mb must be a positive integer. Received: '$required_mb'."
        return 1
    fi

    # Get available space in KB
    local available_kb
    if ! available_kb=$(df -k --output=avail "$path" 2>/dev/null | tail -n 1); then
        log_error "check_disk_space: Failed to get disk space for path '$path'. Is the path valid?"
        return 1
    fi
    local available_mb=$((available_kb / 1024)) # Integer division is fine here
    
    if [[ "$available_mb" -lt "$required_mb" ]]; then
        log_error "Insufficient disk space on $path. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    log_info "Disk space check passed. Available: ${available_mb}MB"
}

# -----------------------------------------------------------------------------
# Output Formatting
# -----------------------------------------------------------------------------
# Prints a standardized banner for visual separation in logs.
print_banner() {
    printf '=%.0s' {1..60}
    print_newline
}

# Prints a single empty line for spacing.
print_newline() {
    echo ""
}

# -----------------------------------------------------------------------------
# Package Management
# -----------------------------------------------------------------------------
# Updates apt package lists and installs specified packages.
install_packages() {
    local packages=("$@")
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "install_packages: No packages specified for installation. Skipping."
        return 0 # Not an error, just nothing to do
    fi

    wait_for_apt_lock
    log_info "Updating package lists..."
    apt-get update -qq || { log_error "install_packages: Failed to update apt package lists. Check network connectivity or apt sources."; return 1; }

    log_info "Installing packages: ${packages[*]}..."
    apt-get install -y "${packages[@]}" -qq || { log_error "install_packages: Failed to install packages: ${packages[*]}"; return 1; }

    log_success "Successfully installed packages: ${packages[*]}"
}