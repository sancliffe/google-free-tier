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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=2-host-setup/common.sh
source "${SCRIPT_DIR}/common.sh"
set_strict_mode

create_optimized_nginx_config() {
    log_info "Applying Nginx performance optimizations for e2-micro..."
    
    local config_file="/etc/nginx/conf.d/e2-micro-optimizations.conf"
    
    # backup_file is from common.sh
    backup_file "$config_file" "/etc/nginx/conf.d"
    
    cat <<'EOF' > "$config_file"
# Custom optimizations for e2-micro instances.
# These values are tuned for a low-memory, shared-CPU environment.

# e2-micro has 2 vCPUs, but they are shared-core. 
# 1 worker process is a safe default to conserve memory.
worker_processes 1;

events {
    # Lower the number of connections per worker. Default is 768 on Debian.
    # 512 is a conservative value for a 1GB RAM instance.
    worker_connections 512;
}

# Shorter timeouts to free up worker connections faster, reducing memory usage.
keepalive_timeout 20s;
client_body_timeout 15s;
client_header_timeout 15s;
send_timeout 15s;

# Disable access logging to reduce disk I/O, which can be slow on standard disks.
# Error logs are still enabled by default in nginx.conf.
access_log off;

# Gzip compression is a trade-off between CPU and bandwidth.
# Enable for text-based assets, but use a moderate compression level.
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 4; # Lower level to reduce CPU usage
gzip_min_length 256;
gzip_types
    application/atom+xml
    application/geo+json
    application/javascript
    application/x-javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rdf+xml
    application/rss+xml
    application/vnd.ms-fontobject
    application/wasm
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/eot
    font/otf
    font/ttf
    image/svg+xml
    text/css
    text/javascript
    text/plain
    text/xml;
EOF

    log_success "Nginx optimization config created at $config_file."
}

# --- Main Logic ---
main() {
    log_info "--- Phase 2: Installing Nginx ---"
    
    ensure_root || exit 1
    
    # Check disk space
    check_disk_space "/" 500 || exit 1 # Need ~500MB for Nginx

    # Check if Nginx is already installed
    #
    # The `dpkg-query` command checks the package manager's database.
    # The `-W` flag shows the status of a package.
    # We redirect output to /dev/null because we only care about the exit code.
    if dpkg-query -W nginx &>/dev/null; then
        log_success "Nginx is already installed. Skipping installation."
    else
        wait_for_apt
        
        log_info "Updating package lists..."
        # -qq is quieter than -q
        if ! apt-get update -qq; then
            log_error "Failed to update package lists."
            exit 1
        fi

        log_info "Installing Nginx..."
        if ! apt-get install -y -qq nginx; then
            log_error "Failed to install Nginx."
            exit 1
        fi
        log_success "Nginx installed successfully."
    fi

    # Apply performance optimizations for e2-micro
    create_optimized_nginx_config

    log_info "Ensuring Nginx is enabled to start on boot..."
    # `systemctl enable` is idempotent. It will only create the link if it doesn't exist.
    if ! systemctl enable nginx; then
        log_error "Failed to enable Nginx to start on boot."
        exit 1
    fi

    log_info "Starting/reloading Nginx service..."
    if ! systemctl reload-or-restart nginx; then
        log_error "Failed to start or reload Nginx."
        exit 1
    fi

    # Verify that Nginx is active
    #
    # `systemctl is-active` returns a zero exit code if the service is running.
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx is not running. Please check the service status."
        log_info "👉 Try running: sudo systemctl status nginx"
        log_info "👉 Try running: sudo journalctl -u nginx -n 50"
        exit 1
    fi
    
    log_info "Performing health check on Nginx..."
    # Ensure curl is installed for the health check
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found, installing for health check..."
        apt-get install -y -qq curl || { log_error "Failed to install curl"; exit 1; }
    fi

    # Loop for up to 30 seconds waiting for Nginx to respond
    for i in {1..30}; do
        # -s for silent, -f for fail-fast (don't output HTML on error), -o /dev/null to discard output
        if curl -sfo /dev/null http://localhost; then
            log_success "Nginx health check passed. Service is responding."
            break
        fi
        
        if [ "$i" -eq 30 ]; then
            log_error "Nginx health check failed. The service started but is not responding."
            exit 1
        fi
        
        log_debug "Nginx not responding yet, waiting 1s... (Attempt $i/30)"
        sleep 1
    done
    
    log_success "Nginx is running and configured to start on boot."

    log_info "-----------------------------------"
}

# --- Script Execution ---
#
# This is a standard Bash practice. The `main` function is not called until the
# entire script has been read. The `${1:-}` is a parameter expansion that
# provides an empty string if no arguments are passed, preventing an "unbound
# variable" error in `set -u` mode.
main "${1:-}"