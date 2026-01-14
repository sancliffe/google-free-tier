#!/bin/bash
#
# Common utilities and settings for shell scripts.
# This script is intended to be sourced, not executed directly.

# --- Strict Mode ---
set -euo pipefail

set_strict_mode() {
    set -euo pipefail
    if [[ "${TRACE:-0}" == "1" ]]; then
        set -x
    fi
}

# --- Log Formatting ---
#
# Usage:
#   log_info "Message"
#   log_success "Message"
#   log_warn "Message"
#   log_error "Message"
#   log_debug "Message" (Requires DEBUG=true)
#
# Optional: Set LOG_FILE to a path to append logs to a file.

_log() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local prefix="${timestamp} ${color}[${level}]\033[0m"

    # Console Output
    # Errors go to stderr, everything else to stdout
    if [[ "${level}" == "ERROR" ]]; then
        echo -e "${prefix} ${message}" >&2
    else
        echo -e "${prefix} ${message}"
    fi

    # File Output
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Strip ANSI color codes for plain text logging
        echo "${timestamp} [${level}] ${message}" >> "${LOG_FILE}"
    fi
}

log_info() {
    # Blue
    _log "INFO" "\033[0;36m" "$1"
}

log_success() {
    # Green with checkmark
    _log "✅ SUCCESS" "\033[0;32m" "$1"
}

log_warn() {
    # Yellow
    _log "WARN" "\033[0;33m" "$1"
}

log_error() {
    # Red
    _log "ERROR" "\033[0;31m" "$1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        # Purple
        _log "DEBUG" "\033[0;35m" "$1"
    fi
}

# --- Section Headers ---
# Display a prominent section header with timestamp
section_header() {
    local title="$1"
    local width=60
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo ""
    echo "$(printf '=%.0s' {1..60})"
    echo "[${timestamp}] ${title}"
    echo "$(printf '=%.0s' {1..60})"
    echo ""
}

# Display a step header with automatic numbering
log_step() {
    local step_num="$1"
    local description="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo ""
    echo "[${timestamp}] ➜ Step ${step_num}: ${description}"
}

# Display a sub-step or detail
log_detail() {
    local message="$1"
    echo "  • ${message}"
}

# Root Check ---
ensure_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root."
        log_info "👉 Try running: sudo bash ${0##*/}"
        return 1
    fi
    return 0
}

# --- Stability: Wait for Apt Locks ---
wait_for_apt() {
    local max_retries=30
    local count=0
    
    log_info "Checking for apt locks..."
    
    # Check for lock files used by dpkg/apt
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        
        log_warn "Apt lock is held by another process. Waiting (attempt $((count+1))/${max_retries})..."
        sleep 2
        count=$((count+1))
        
        if [[ "$count" -ge "$max_retries" ]]; then
            log_error "Timed out waiting for apt lock."
            # Proceeding anyway might fail, but we've waited 60s
            break
        fi
    done
}

# --- Command Validation ---
ensure_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "Required command '${cmd}' not found."
        if [[ -n "${install_hint}" ]]; then
            log_info "💡 Install hint: ${install_hint}"
        fi
        return 1
    fi
    log_debug "Command '${cmd}' is available."
    return 0
}

# --- Disk Space Checking ---
check_disk_space() {
    local target_path="${1:-.}"
    local min_space_mb="${2:-100}"
    
    # Get available space in MB
    local available_mb
    available_mb=$(df "${target_path}" | awk 'NR==2 {print int($4)}') || return 1
    
    if ! [[ "${available_mb}" =~ ^[0-9]+$ ]]; then
        log_error "Failed to parse available disk space."
        return 1
    fi
    
    if [[ "${available_mb}" -lt "${min_space_mb}" ]]; then
        log_error "Insufficient disk space in ${target_path}. Required: ${min_space_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    log_debug "Disk space check passed: ${available_mb}MB available (need ${min_space_mb}MB)"
    return 0
}

# --- File Backup Function ---
backup_file() {
    local file="$1"
    local backup_dir="${2:-.}"
    
    if [[ ! -f "${file}" ]]; then
        log_warn "File '${file}' does not exist, skipping backup."
        return 0
    fi
    
    local backup_file
    backup_file="${backup_dir}/$(basename "${file}").bak.$(date -u +%s)"
    cp "${file}" "${backup_file}"
    log_success "Backed up '${file}' to '${backup_file}'"
}

# --- Service Wait Function ---
wait_for_service() {
    local service="$1"
    local max_retries="${2:-30}"
    local count=0
    
    log_info "Waiting for service '${service}' to be active..."
    
    while ! systemctl is-active --quiet "${service}"; do
        count=$((count+1))
        if [[ "$count" -ge "$max_retries" ]]; then
            log_error "Service '${service}' did not become active within timeout."
            return 1
        fi
        log_debug "Service '${service}' not ready yet (attempt ${count}/${max_retries})..."
        sleep 1
    done
    
    log_success "Service '${service}' is active."
    return 0
}

# --- Version Comparison ---
validate_version() {
    local cmd="$1"
    local min_version="${2:-}"
    
    if [[ -z "${min_version}" ]]; then
        return 0
    fi
    
    local current_version
    current_version=$(${cmd} --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "${current_version}" ]]; then
        log_warn "Could not parse version for '${cmd}'. Skipping version check."
        return 0
    fi
    
    log_debug "Version check for '${cmd}': current=${current_version}, minimum=${min_version}"
}

# --- Exit Trap Handler ---
# Registers cleanup actions that run on exit or error
cleanup_on_error() {
    # This is a placeholder for cleanup actions.
    # For example, it could remove temporary files.
    log_debug "Running cleanup actions..."
}

handle_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Error on line $line_no (exit code: $exit_code)"
    cleanup_on_error
    exit "$exit_code"
}

trap 'handle_error $LINENO' ERR