#!/bin/bash
#
# Phase 2: Install and configure Nginx.
#
# This script installs Nginx, enables it to start on boot, and verifies
# that it is running. It is idempotent and can be safely run multiple times.

# --- Source Common Utilities ---
#
# The `source` command runs the given script in the current shell's context.
# We use it to import our helper functions and settings from common.sh.
# The `dirname "$0"` part ensures we find common.sh relative to this script's
# location, regardless of where the script is called from.
source "/tmp/2-host-setup/common.sh"

# --- Main Logic ---
main() {
    log_info "--- Phase 2: Installing Nginx ---"
    
    ensure_root

    # Check if Nginx is already installed
    #
    # The `dpkg-query` command checks the package manager's database.
    # The `-W` flag shows the status of a package.
    # We redirect output to /dev/null because we only care about the exit code.
    if dpkg-query -W nginx &>/dev/null; then
        log_success "Nginx is already installed. Skipping installation."
    else
        log_info "Updating package lists..."
        # -qq is quieter than -q
        apt-get update -qq

        log_info "Installing Nginx..."
        apt-get install -y -qq nginx
        log_success "Nginx installed successfully."
    fi

    log_info "Ensuring Nginx is enabled to start on boot..."
    # `systemctl enable` is idempotent. It will only create the link if it doesn't exist.
    systemctl enable nginx

    # Verify that Nginx is active
    #
    # `systemctl is-active` returns a zero exit code if the service is running.
    if systemctl is-active --quiet nginx; then
        log_success "Nginx is running."
    else
        log_error "Nginx is not running. Please check the service status."
        log_info "👉 Try running: sudo systemctl status nginx"
        exit 1
    fi

    log_info "-----------------------------------"
}

# --- Script Execution ---
#
# This is a standard Bash practice. The `main` function is not called until the
# entire script has been read. The `${1:-}` is a parameter expansion that
# provides an empty string if no arguments are passed, preventing an "unbound
# variable" error in `set -u` mode.
main "${1:-}"
