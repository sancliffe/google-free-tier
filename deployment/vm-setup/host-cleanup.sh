#!/bin/bash
# host-cleanup.sh
# Removes resources and configurations created by the host-phase setup scripts (10-18).
# This script reverses the setup performed by scripts such as:
# - host-01-create-swap.sh
# - host-02-setup-duckdns.sh
# - host-03-firewall-config.sh
# - host-04-install-nginx.sh
# - host-05-setup-ssl.sh
# - host-06-setup-security.sh
# - host-07-setup-backups.sh
# - host-09-setup-ops-agent.sh

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Default values
BACKUP_DIR=""
REMOVE_BACKUPS=false

# --- Usage ---
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Removes the host-phase configurations and resources created by setup scripts.

OPTIONS:
    --backup-dir DIR       The backup directory path (optional, will not remove if not specified)
    --remove-backups       Also remove backup files (use with caution!)
    -h, --help             Show this help message
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir)      BACKUP_DIR="$2"; shift 2;;
        --remove-backups)  REMOVE_BACKUPS=true; shift;;
        -h|--help)         show_usage; exit 0;;
        *)                 echo "Unknown option: $1"; show_usage; exit 1;;
    esac
done

# --- Logging Helpers ---
log_info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m $*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

echo "------------------------------------------------------------"
log_info "Starting Host-Phase Cleanup"
echo "------------------------------------------------------------"
log_warn "This script will REMOVE the following:"
log_warn "  - Swap file configuration from /etc/fstab"
log_warn "  - DuckDNS cron jobs and installation directory"
log_warn "  - Firewall rules (UFW)"
log_warn "  - Nginx configuration and service"
log_warn "  - SSL certificates and Certbot"
log_warn "  - Security tools (Fail2Ban, UFW)"
log_warn "  - Backup cron jobs and rsync configurations"
log_warn "  - Google Cloud Ops Agent"
if [[ "${REMOVE_BACKUPS}" == "true" && -n "${BACKUP_DIR}" ]]; then
    log_warn "  - Backup files in: ${BACKUP_DIR}"
fi
echo "------------------------------------------------------------"
read -rp "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" ]]; then
    log_info "Cleanup cancelled."
    exit 0
fi
echo "------------------------------------------------------------"

# Verify we have sudo/root access
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# --- Step 1: Remove Swap File ---
log_info "Step 1: Removing swap file configuration..."
SWAP_FILE_PATH="/swapfile"

if grep -q "${SWAP_FILE_PATH}" /etc/fstab; then
    log_info "Disabling swap..."
    if swapoff "${SWAP_FILE_PATH}" 2>/dev/null; then
        log_success "Swap disabled"
    else
        log_warn "Failed to disable swap (may not be active)"
    fi
    
    log_info "Removing from /etc/fstab..."
    sed -i "\|${SWAP_FILE_PATH}|d" /etc/fstab
    log_success "Removed from /etc/fstab"
    
    log_info "Removing swap file..."
    if rm -f "${SWAP_FILE_PATH}"; then
        log_success "Swap file deleted"
    else
        log_warn "Failed to delete swap file"
    fi
else
    log_info "Swap file not found in /etc/fstab"
fi

# --- Step 2: Remove DuckDNS ---
log_info "Step 2: Removing DuckDNS setup..."

# Remove DuckDNS cron job
CRON_JOB_PATTERN="duckdns"
if (crontab -l 2>/dev/null | grep -q "${CRON_JOB_PATTERN}"); then
    log_info "Removing DuckDNS cron job..."
    crontab -l 2>/dev/null | grep -v "${CRON_JOB_PATTERN}" | crontab -
    log_success "DuckDNS cron job removed"
else
    log_info "No DuckDNS cron job found"
fi

# Remove DuckDNS installation directory
DUCKDNS_DIR="${HOME}/.duckdns"
if [[ -d "${DUCKDNS_DIR}" ]]; then
    log_info "Removing DuckDNS directory: ${DUCKDNS_DIR}"
    rm -rf "${DUCKDNS_DIR}"
    log_success "DuckDNS directory removed"
else
    log_info "DuckDNS directory not found"
fi

# --- Step 3: Remove Firewall Rules ---
log_info "Step 3: Removing firewall rules..."

if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        log_info "UFW is active. Disabling..."
        ufw --force disable
        log_success "UFW disabled"
    else
        log_info "UFW is not active"
    fi
else
    log_info "UFW not installed"
fi

# --- Step 4: Remove Nginx ---
log_info "Step 4: Removing Nginx..."

if systemctl is-active --quiet nginx; then
    log_info "Stopping Nginx service..."
    systemctl stop nginx
    log_success "Nginx stopped"
fi

if systemctl is-enabled --quiet nginx 2>/dev/null; then
    log_info "Disabling Nginx service..."
    systemctl disable nginx
    log_success "Nginx disabled"
fi

if command -v nginx &> /dev/null; then
    log_info "Uninstalling Nginx package..."
    apt-get purge -y nginx nginx-common > /dev/null 2>&1 || {
        log_warn "Failed to purge nginx package"
    }
    log_success "Nginx package removed"
    
    # Clean up Nginx configuration backups
    if [[ -d /etc/nginx.bak ]]; then
        log_info "Removing Nginx backup directory..."
        rm -rf /etc/nginx.bak
    fi
else
    log_info "Nginx not installed"
fi

# --- Step 5: Remove SSL/Certbot ---
log_info "Step 5: Removing SSL certificates and Certbot..."

if systemctl is-active --quiet certbot.timer 2>/dev/null; then
    log_info "Stopping Certbot renewal timer..."
    systemctl stop certbot.timer
    systemctl disable certbot.timer
    log_success "Certbot timer stopped and disabled"
fi

if command -v certbot &> /dev/null; then
    # List all certificates and remove them
    CERTS=$(certbot certificates 2>/dev/null | grep "Certificate Name:" | awk '{print $NF}' || true)
    if [[ -n "${CERTS}" ]]; then
        log_info "Removing Certbot certificates..."
        while IFS= read -r cert_name; do
            if [[ -n "${cert_name}" ]]; then
                certbot delete --non-interactive --cert-name "${cert_name}" || {
                    log_warn "Failed to remove certificate: ${cert_name}"
                }
            fi
        done <<< "${CERTS}"
        log_success "Certbot certificates removed"
    fi
    
    log_info "Uninstalling Certbot package..."
    apt-get purge -y certbot python3-certbot-nginx > /dev/null 2>&1 || {
        log_warn "Failed to purge certbot packages"
    }
    log_success "Certbot package removed"
else
    log_info "Certbot not installed"
fi

# Clean up Let's Encrypt directory
if [[ -d /etc/letsencrypt ]]; then
    log_info "Removing Let's Encrypt configuration..."
    rm -rf /etc/letsencrypt
fi

# --- Step 6: Remove Security Tools ---
log_info "Step 6: Removing security tools..."

# Remove Fail2Ban
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    log_info "Stopping Fail2Ban service..."
    systemctl stop fail2ban
    systemctl disable fail2ban
    log_success "Fail2Ban stopped and disabled"
fi

if command -v fail2ban-server &> /dev/null; then
    log_info "Uninstalling Fail2Ban package..."
    apt-get purge -y fail2ban > /dev/null 2>&1 || {
        log_warn "Failed to purge fail2ban"
    }
    log_success "Fail2Ban package removed"
else
    log_info "Fail2Ban not installed"
fi

# --- Step 7: Remove Backup Configuration ---
log_info "Step 7: Removing backup configuration..."

# Remove backup cron jobs
BACKUP_CRON_PATTERN="backup.sh"
if (crontab -l 2>/dev/null | grep -q "${BACKUP_CRON_PATTERN}"); then
    log_info "Removing backup cron job..."
    crontab -l 2>/dev/null | grep -v "${BACKUP_CRON_PATTERN}" | crontab -
    log_success "Backup cron job removed"
else
    log_info "No backup cron job found"
fi

# Remove backup script if it exists
if [[ -f "${HOME}/backup.sh" ]]; then
    log_info "Removing backup script..."
    rm -f "${HOME}/backup.sh"
    log_success "Backup script removed"
fi

# Optionally remove backup directory
if [[ "${REMOVE_BACKUPS}" == "true" && -n "${BACKUP_DIR}" ]]; then
    if [[ -d "${BACKUP_DIR}" ]]; then
        log_warn "Removing backup directory: ${BACKUP_DIR}"
        read -rp "Are you absolutely sure? This cannot be undone (y/N): " CONFIRM_BACKUPS
        if [[ "${CONFIRM_BACKUPS}" == "y" ]]; then
            rm -rf "${BACKUP_DIR}"
            log_success "Backup directory deleted"
        else
            log_info "Backup directory preserved"
        fi
    fi
else
    if [[ -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]]; then
        log_info "Backup directory preserved: ${BACKUP_DIR}"
    fi
fi

# --- Step 8: Remove Google Cloud Ops Agent ---
log_info "Step 8: Removing Google Cloud Ops Agent..."

if systemctl is-active --quiet google-cloud-ops-agent 2>/dev/null; then
    log_info "Stopping Google Cloud Ops Agent service..."
    systemctl stop google-cloud-ops-agent
    systemctl disable google-cloud-ops-agent
    log_success "Google Cloud Ops Agent stopped and disabled"
fi

if command -v google-cloud-ops-agent &> /dev/null; then
    log_info "Uninstalling Google Cloud Ops Agent package..."
    apt-get purge -y google-cloud-ops-agent google-cloud-ops-agent-fluent-bit > /dev/null 2>&1 || {
        log_warn "Failed to purge google-cloud-ops-agent"
    }
    log_success "Google Cloud Ops Agent package removed"
else
    log_info "Google Cloud Ops Agent not installed"
fi

# Clean up Ops Agent configuration
if [[ -d /etc/google-cloud-ops-agent ]]; then
    log_info "Removing Ops Agent configuration..."
    rm -rf /etc/google-cloud-ops-agent
fi

# --- Step 9: Clean up APT ---
log_info "Step 9: Cleaning up package manager..."
apt-get autoremove -y > /dev/null 2>&1 || {
    log_warn "Failed to run apt-get autoremove"
}
apt-get autoclean > /dev/null 2>&1 || {
    log_warn "Failed to run apt-get autoclean"
}
log_success "Package cleanup completed"

echo "------------------------------------------------------------"
log_success "Host-Phase Cleanup Finished!"
echo "------------------------------------------------------------"
echo ""
log_info "Manual cleanup items (if needed):"
log_info "  - Review system logs: journalctl -u nginx, journalctl -u fail2ban"
log_info "  - Check /var/log/ directory for application logs"
log_info "  - Review /root/.ssh/authorized_keys if SSH key setup was done"
if [[ -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]]; then
    log_info "  - Backup directory still exists: ${BACKUP_DIR}"
fi
echo ""
