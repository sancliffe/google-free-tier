#!/bin/bash
#
# Phase 8: Install Google Cloud Ops Agent

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
set_strict_mode

main() {
    echo ""
    printf '=%.0s' {1..60}; echo
    log_info "Phase 8: Installing Google Cloud Ops Agent"
    printf '=%.0s' {1..60}; echo
    echo ""
    ensure_root || exit 1

    if command -v google-cloud-ops-agent &> /dev/null; then
        log_success "Ops Agent is already installed."
        exit 0
    fi

    log_info "Downloading agent repository script..."
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh

    log_info "Installing agent..."
    bash add-google-cloud-ops-agent-repo.sh --also-install

    # FIXED: Check if Nginx metrics endpoint is actually available
    log_info "Checking Nginx metrics availability..."
    local enable_nginx_metrics=false
    if curl -s -f http://127.0.0.1/stub_status > /dev/null; then
        log_success "Nginx stub_status detected. Configuring metrics."
        enable_nginx_metrics=true
    else
        log_warn "Nginx stub_status NOT detected. Skipping Nginx metrics configuration."
    fi

    log_info "Configuring agent..."
    cat <<EOF > /etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    nginx_access:
      type: nginx_access
      include_paths:
        - /var/log/nginx/access.log
    nginx_error:
      type: nginx_error
      include_paths:
        - /var/log/nginx/error.log
  service:
    pipelines:
      nginx:
        receivers: [nginx_access, nginx_error]
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
${nginx_config}
  service:
    pipelines:
      host:
        receivers: [hostmetrics]
${nginx_pipeline}
EOF

    log_info "Restarting Ops Agent..."
    systemctl restart google-cloud-ops-agent

    log_success "Ops Agent installed and configured."
    rm add-google-cloud-ops-agent-repo.sh
}

main "$@"