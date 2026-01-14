#!/bin/bash
# host-04-install-nginx.sh
# Installs and configures Nginx with basic optimizations for e2-micro.

set -e
source "$(dirname "$0")/common.sh"

echo ""
echo "============================================================"
log_info "Phase 2: Installing Nginx"
echo "============================================================"
echo ""

check_root

# 1. Install Nginx
log_info "Checking for apt locks..."
wait_for_apt_lock

log_info "Updating package lists..."
apt-get update -qq

log_info "Installing Nginx..."
apt-get install -y nginx -qq

log_success "Nginx installed successfully."

# 2. Optimize Nginx for e2-micro (Limited RAM)
log_info "Applying Nginx performance optimizations for e2-micro..."

NGINX_CONF="/etc/nginx/nginx.conf"
backup_file "$NGINX_CONF"

# Adjust worker processes to auto (usually 2 for e2-micro) or set to 1 to save RAM
# 'auto' is generally fine, but we'll ensure worker_connections is reasonable.
sed -i 's/worker_processes auto;/worker_processes 1;/g' "$NGINX_CONF"
log_info "Updated worker_processes in main nginx.conf"

# Disable default gzip (we can enable it more selectively if needed, saves CPU)
sed -i 's/gzip on;/gzip off;/g' "$NGINX_CONF"
log_info "Disabled default gzip settings in main nginx.conf to save CPU"

# Create a custom config for timeout and buffer adjustments
OPTIM_CONF="/etc/nginx/conf.d/e2-micro-optimizations.conf"
backup_file "$OPTIM_CONF"

cat > "$OPTIM_CONF" <<EOF
# Optimizations for low-resource environments (e2-micro)
client_body_buffer_size 10K;
client_header_buffer_size 1k;
client_max_body_size 8m;
large_client_header_buffers 2 1k;

# Timeouts to release connections quickly
client_body_timeout 12;
client_header_timeout 12;
keepalive_timeout 15;
send_timeout 10;
EOF

log_success "Nginx optimization config created at $OPTIM_CONF."

# 3. Configure stub_status for Ops Agent Metrics
# This is CRITICAL for the Google Cloud Ops Agent to report Nginx metrics
STATUS_CONF="/etc/nginx/conf.d/status.conf"
log_info "Configuring Nginx stub_status for Ops Agent metrics..."

cat > "$STATUS_CONF" <<EOF
server {
    listen 80;
    server_name 127.0.0.1;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
log_success "Created $STATUS_CONF for metrics collection."

# 4. Enable and Start Nginx
log_info "Ensuring Nginx is enabled to start on boot..."
systemctl enable nginx

log_info "Testing Nginx configuration..."
nginx -t

log_info "Starting/reloading Nginx service..."
systemctl restart nginx

# 5. Verify
log_info "Performing health check on Nginx..."
if systemctl is-active --quiet nginx; then
    log_success "Nginx health check passed. Service is responding."
    
    # Verify metrics endpoint locally
    if curl -s http://127.0.0.1/nginx_status | grep -q "Active connections"; then
        log_success "Metrics endpoint (stub_status) is active and reachable."
    else
        log_warn "Metrics endpoint configured but returned unexpected output."
    fi
else
    log_error "Nginx is not running!"
    exit 1
fi

log_success "Nginx is running and configured to start on boot."