#!/bin/bash
#
# Phase 8: Install Google Cloud Ops Agent
#
# This agent collects Memory, Swap, and Process metrics which are NOT
# available by default in the Google Cloud Console. This is critical
# for monitoring the 1GB RAM limit of the e2-micro instance.

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

main() {
    log_info "--- Phase 8: Installing Google Cloud Ops Agent ---"
    ensure_root

    if command -v google-cloud-ops-agent &> /dev/null; then
        log_success "Ops Agent is already installed."
        exit 0
    fi

    log_info "Downloading agent repository script..."
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh

    log_info "Installing agent..."
    # --also-install runs the installation immediately after adding the repo
    bash add-google-cloud-ops-agent-repo.sh --also-install

    # Configure the agent to monitor Nginx (Optional but recommended)
    # We place a config file to capture nginx logs and metrics
    log_info "Configuring agent for Nginx..."
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
    nginx:
      type: nginx
      stub_status_url: http://127.0.0.1/status
  service:
    pipelines:
      host:
        receivers: [hostmetrics]
      nginx:
        receivers: [nginx]
EOF

    log_info "Restarting Ops Agent..."
    systemctl restart google-cloud-ops-agent

    log_success "Ops Agent installed and configured."
    log_info "You can now view Memory and Swap usage in the GCP Monitoring Console."
    
    # Cleanup
    rm add-google-cloud-ops-agent-repo.sh
}

main "$@"