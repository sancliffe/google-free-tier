#!/bin/bash
#
# Phase 1: Create and configure a swap file.
#
# The e2-micro instances have very little RAM. A swap file helps prevent
# out-of-memory errors by using disk space as virtual RAM. This script is
# idempotent and will not create a new swapfile if one already exists.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"
set_strict_mode

# --- Constants ---
#
# Using variables for these values makes them easier to change later.
SWAP_FILE_PATH="/swapfile"
SWAP_SIZE="2G" # 2 Gigabytes
SWAPPINESS_VALUE="10" # 10 is a good value for servers

main() {
    echo ""
    echo "$(printf '=%.0s' {1..60})"
    log_info "Phase 1: Configuring Swap File"
    echo "$(printf '=%.0s' {1..60})"
    echo ""
    ensure_root || exit 1

    # Check disk space before creating swap
    check_disk_space "/" 2500 || exit 1 # Need ~2.5GB for 2GB swap file
    
    # Check if the swap file is already configured in /etc/fstab
    #
    # `grep -q` runs in "quiet" mode, not printing the matching line,
    # and immediately exits with a success status if a match is found.
    if grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
        log_success "Swap file is already configured in /etc/fstab. Skipping."
        # Also check if it's active
        if swapon --show | grep -q "${SWAP_FILE_PATH}"; then
             log_success "Swap is active."
        else
             log_warn "Swap is configured but not active. Enabling now..."
             swapon "${SWAP_FILE_PATH}" || {
                 log_error "Failed to enable swap."
                 exit 1
             }
        fi
        echo ""
        exit 0
    fi

    log_info "Creating swap file at ${SWAP_FILE_PATH} with size ${SWAP_SIZE}..."
    # Try using fallocate first for speed. If it fails, fall back to dd.
    if fallocate -l "${SWAP_SIZE}" "${SWAP_FILE_PATH}"; then
        log_info "Swap file allocated successfully with fallocate."
    else
        log_warn "fallocate failed. Falling back to dd, which is more compatible but slower."
        # SWAP_SIZE is 2G, so we use a block size of 1G and a count of 2.
        if ! dd if=/dev/zero of="${SWAP_FILE_PATH}" bs=1G count=2 status=progress; then
            log_error "dd command failed to create swap file."
            rm -f "${SWAP_FILE_PATH}" # Clean up partial file
            exit 1
        fi
        log_success "Swap file created with dd."
    fi

    log_info "Setting secure permissions for swap file..."
    # Only the root user should be able to read/write the swap file.
    chmod 600 "${SWAP_FILE_PATH}"

    log_info "Formatting file as swap space..."
    if ! mkswap "${SWAP_FILE_PATH}"; then
        log_error "Failed to format swap file."
        rm -f "${SWAP_FILE_PATH}"
        exit 1
    fi

    log_info "Enabling swap..."
    if ! swapon "${SWAP_FILE_PATH}"; then
        log_error "Failed to enable swap."
        rm -f "${SWAP_FILE_PATH}"
        exit 1
    fi

    log_info "Adding swap file to /etc/fstab to make it permanent..."
    # Backup /etc/fstab before modification
    backup_file "/etc/fstab" "/tmp"
    # This ensures the swap file is activated on reboot.
    echo "${SWAP_FILE_PATH} none swap sw 0 0" >> /etc/fstab

    log_info "Tuning swappiness to ${SWAPPINESS_VALUE}..."
    # Swappiness determines how aggressively the system uses swap.
    # A low value is better for server performance.
    sysctl vm.swappiness="${SWAPPINESS_VALUE}"
    
    log_info "Making swappiness setting permanent..."
    backup_file "/etc/sysctl.conf" "/tmp"
    echo "vm.swappiness=${SWAPPINESS_VALUE}" >> /etc/sysctl.conf

    log_success "Swap file configured successfully."
    log_info "Verifying swap status..."
    free -h || log_warn "Could not run free -h"
    echo ""
}

main "${1:-}"