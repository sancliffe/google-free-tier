#!/bin/bash
#
# Common utilities and settings for shell scripts.
# This script is intended to be sourced, not executed directly.

# --- Strict Mode ---
set -euo pipefail

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
    local prefix="${timestamp} [${level}]"

    # Console Output
    # Errors go to stderr, everything else to stdout
    if [[ "${level}" == "ERROR" ]]; then
        echo -e "${prefix} ${color}${message}\033[0m" >&2
    else
        echo -e "${prefix} ${color}${message}\033[0m"
    fi

    # File Output
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Strip ANSI color codes for plain text logging
        echo "${prefix} ${message}" >> "${LOG_FILE}"
    fi
}

log_info() {
    _log "INFO" "" "$1"
}

log_success() {
    # Green
    _log "✅" "\033[0;32m" "$1"
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

# --- Root Check ---
ensure_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root."
        log_info "👉 Try running: sudo bash ${0##*/}"
        exit 1
    fi
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