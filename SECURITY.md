# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability in this project, please follow responsible disclosure practices:

1. **Do NOT** open a public GitHub issue
2. **Do NOT** post the vulnerability in discussions or comments
3. **Email** security details to the project maintainers (if available)
4. **Include** detailed information about the vulnerability:
   - Description of the issue
   - Affected components/scripts
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)

You should receive a response within 48 hours. The project maintainers will work to:
- Verify the vulnerability
- Develop a fix
- Credit you for the discovery (if desired)
- Release a patched version

---

## Threat Model

This project is designed to defend against common cloud security threats targeting small-to-medium scale web applications. The primary security goals are to protect user data, ensure service availability, and control costs.

### In-Scope Threats

The security controls implemented in this project primarily mitigate the following threats:

- **Unauthorized Access:**
  - *Threat:* Malicious actors gaining shell access to the VM or administrative access to GCP resources.
  - *Mitigation:* Use of Identity-Aware Proxy (IAP) for SSH, OS Login, least-privilege IAM roles, and firewall rules.

- **Data Breaches:**
  - *Threat:* Exposure of sensitive information such as API keys, credentials, or user data.
  - *Mitigation:* Storing all secrets in Google Secret Manager, using encrypted and versioned GCS buckets for backups and Terraform state.

- **Denial of Service (DoS) / DDoS Attacks:**
  - *Threat:* Overwhelming the web server or other public-facing services with traffic, causing service unavailability.
  - *Mitigation:* Basic rate limiting implemented in Nginx. For more advanced protection, Google Cloud Armor is recommended.

- **Cost Overruns:**
  - *Threat:* Accidental or malicious activity leading to unexpected and high GCP bills.
  - *Mitigation:* GCP budget alerts and the automated "Cost Killer" Cloud Function that shuts down the VM when a budget threshold is exceeded.

- **Data Loss:**
  - *Threat:* Loss of application data due to hardware failure, accidental deletion, or corruption.
  - *Mitigation:* Automated daily backups to Google Cloud Storage with versioning enabled. A disaster recovery plan is also documented.

### Out-of-Scope Threats

This project is a learning resource and a template; it is not hardened against all possible threats. The following are considered out of scope for the default configuration:

- **Advanced Persistent Threats (APTs):** Sophisticated, long-term attacks by well-funded actors.
- **Physical Access Attacks:** Compromise of physical GCP data center hardware.
- **Supply Chain Attacks on Dependencies:** Malicious code injected into third-party libraries (e.g., npm packages, Docker base images). While container scanning is included, a full audit of all dependencies is not performed.
- **Insider Threats:** Malicious actions by authorized users with legitimate access to the GCP project.

---

## Security Best Practices

### For Project Users

#### 1. **Secrets Management**
- **Never commit secrets to Git** - Use Google Secret Manager
- All sensitive data should be stored in environment variables or Secret Manager
- `.gitignore` includes: `*.tfvars`, `*.env`, `*.key`, `*.pem`
- Review files before adding to ensure no credentials are included

**Example of SAFE:**
```bash
# Using Secret Manager
export DOMAIN=$(gcloud secrets versions access latest --secret="domain_name")
```

**Example of UNSAFE:**
```bash
# ❌ Never do this
export API_KEY="sk-1234567890abcdef"
git add .
git commit -m "Add API key"
```

#### 2. **IAM Roles and Permissions**
- **Principle of Least Privilege**: Grant only necessary permissions
- Never use `Editor` or `Owner` role for service accounts
- Use predefined roles when possible
- Regularly audit IAM bindings

**Recommended Roles:**
```bash
# For Compute Engine VM
roles/compute.instanceAdmin.v1

# For Cloud Run deployment
roles/run.admin

# For GKE management
roles/container.developer

# For Terraform
roles/iam.securityAdmin (for IAM updates)
roles/compute.admin
roles/storage.admin
roles/run.admin
```

**Audit IAM policies:**
```bash
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" | sort | uniq -c
```

#### 3. **Network Security**
- **Firewall Rules**: Only open necessary ports
- **SSH Access**: Restrict to specific IPs or use OS Login + IAP
- **HTTPS Only**: Always use SSL/TLS for web traffic
- **DDoS Protection**: Consider Cloud Armor for production

**Firewall Best Practices:**
```bash
# ✅ Good: Restrict SSH to specific IPs
gcloud compute firewall-rules create allow-ssh-from-office \
  --allow=tcp:22 \
  --source-ranges=203.0.113.0/24

# ❌ Avoid: Open SSH to the world
gcloud compute firewall-rules create allow-ssh-everywhere \
  --allow=tcp:22 \
  --source-ranges=0.0.0.0/0
```

#### 4. **SSL/TLS Certificates**
- Use Let's Encrypt (included in setup scripts)
- Enable HTTPS redirect
- Set appropriate security headers
- Monitor certificate expiration

**Nginx Security Headers:**
```nginx
# Add to Nginx config for additional security
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
```

#### 5. **Access Control**
- Enable OS Login for managed SSH access
- Use Identity-Aware Proxy (IAP) for SSH tunneling
- Enable 2FA on GCP account
- Use service accounts with restricted scopes

**Enable OS Login:**
```bash
gcloud compute instances add-metadata free-tier-vm \
  --metadata enable-oslogin=TRUE \
  --zone=us-central1-a
```

**Use IAP for SSH:**
```bash
gcloud compute ssh free-tier-vm --zone=us-central1-a --tunnel-through-iap
```

#### 6. **Monitoring and Logging**
- Enable Cloud Logging
- Set up audit logging for GCP resources
- Monitor failed SSH attempts
- Enable Cloud Monitoring alerts

**Check SSH Logs:**
```bash
# View failed SSH attempts on the VM
sudo grep "Failed password" /var/log/auth.log | tail -20

# View all SSH connection attempts
sudo journalctl _SYSTEMD_UNIT=ssh.service -n 50
```

**View GCP Audit Logs:**
```bash
gcloud logging read "resource.type=gce_instance AND protoPayload.methodName=compute.instances.get" \
  --limit=10 \
  --format=json
```

#### 7. **Secrets Rotation**
- Rotate all credentials regularly (every 90 days minimum)
- Use Secret Manager's automatic rotation features
- Document rotation procedures
- Consider implementing a Cloud Function to send reminders for manual rotation or to fully automate rotation for certain secrets (e.g., DuckDNS token).

**Rotate DuckDNS Token:**
```bash
# Get new token from DuckDNS, then update Secret Manager
echo -n "new-token" | gcloud secrets versions add duckdns_token --data-file=-
```

#### 8. **Backup Security**
- Encrypt backups at rest
- Test backup restoration regularly
- Restrict backup access to authorized users only
- Store off-site backups for disaster recovery

**Enable encryption for GCS backups:**
```bash
gsutil encryption set gs://your-backup-bucket
```

#### 9. **Dependencies and Updates**
- Keep all software up to date
- Use automated security updates
- Monitor CVE announcements
- Review dependency changes

**Check for system updates:**
```bash
sudo apt update
sudo apt list --upgradable
sudo apt upgrade -y  # Install updates
```

**View Debian security advisories:**
```bash
sudo apt-listchanges
```

#### 10. **Configuration Security**
- Review all configuration files for hardcoded secrets
- Use environment variables for sensitive config
- Restrict file permissions appropriately
- Version control configuration (but not secrets)

**Secure File Permissions:**
```bash
# Swap file should only be readable by root
-rw------- root root /swapfile

# SSH directory permissions
drwx------ .ssh
-rw------- .ssh/authorized_keys
-rw------- .ssh/id_rsa
-rw-r--r-- .ssh/id_rsa.pub

# Configuration files
-rw-r--r-- nginx config files
-rw------- /etc/ssl/private/key.pem
```

---

## Security Checklist

### Before Deployment

- [ ] All secrets are in Secret Manager, not in code
- [ ] `.gitignore` includes all sensitive file patterns
- [ ] IAM roles follow least privilege principle
- [ ] Firewall rules are restrictive (not 0.0.0.0/0 for SSH)
- [ ] HTTPS/SSL is configured
- [ ] 2FA enabled on GCP account
- [ ] OS Login is enabled for the VM
- [ ] Monitoring and logging are configured
- [ ] Backup strategy is tested and documented
- [ ] Security advisories have been reviewed

### After Deployment

- [ ] Verify HTTPS is working and redirects from HTTP
- [ ] Test firewall rules (SSH, HTTP, HTTPS)
- [ ] Confirm backups are being created
- [ ] Monitor logs for suspicious activity
- [ ] Schedule regular security updates
- [ ] Set calendar reminders for credential rotation
- [ ] Document all security decisions
- [ ] Test disaster recovery procedures
- [ ] Review IAM roles monthly
- [ ] Check for unused resources

---

## Common Vulnerabilities

### SQL Injection
Not applicable to this project (no database in basic setup), but if adding a database:
- Use parameterized queries
- Validate and sanitize all inputs
- Use ORM frameworks when possible

### Cross-Site Scripting (XSS)
- Enable Content Security Policy headers
- Escape user input in templates
- Use security-focused templating engines
- Never use `eval()` or `innerHTML`

### Cross-Site Request Forgery (CSRF)
- Use CSRF tokens for state-changing requests
- Validate origin headers
- Use SameSite cookie attribute

### Denial of Service (DoS)
- Use Cloud Armor for DDoS protection
- Implement rate limiting
- Monitor resource usage
- Set up alerts for unusual traffic patterns

### Man-in-the-Middle (MITM)
- Enforce HTTPS everywhere
- Use HSTS headers
- Pin SSL certificates for critical APIs
- Validate certificate chains

### Privilege Escalation
- Never run services as root unless necessary
- Use dedicated service accounts
- Implement proper permission boundaries
- Regularly audit sudo access

### Information Disclosure
- Disable verbose error messages in production
- Remove debugging endpoints
- Don't expose internal IPs or hostnames
- Use security headers to prevent information leakage

---

## Tools for Security Testing

### Local Security Checks

```bash
# Check bash script security
sudo apt-get install shellcheck
shellcheck 2-host-setup/*.sh

# Scan for hardcoded secrets
sudo apt-get install truffleHog
truffleHog filesystem .

# Check file permissions
find . -type f -perm /go+w

# Verify no .git folders in public directories
find . -name ".git" -type d
```

### GCP Security Checks

```bash
# Enable Security Command Center (SCC)
gcloud scc databases list

# Check VPC Flow Logs
gcloud compute networks subnets describe default --region=us-central1

# Review firewall rules
gcloud compute firewall-rules list --format=table

# Check for public IPs
gcloud compute addresses list --filter="status:IN_USE"

# Audit Cloud Storage public access
gsutil iam ch -d allUsers gs://your-bucket
```

### SSL/TLS Verification

```bash
# Test SSL certificate
openssl s_client -connect your-domain.duckdns.org:443

# Check certificate expiration
echo | openssl s_client -servername your-domain.duckdns.org \
  -connect your-domain.duckdns.org:443 2>/dev/null | \
  openssl x509 -noout -dates

# Use SSL Labs for comprehensive testing
# https://www.ssllabs.com/ssltest/
```

---

## Incident Response

If you suspect a security breach:

1. **Immediate Actions**
   - Change all passwords and credentials
   - Revoke compromised API keys/tokens
   - Check for unauthorized access in audit logs
   - Isolate affected systems if necessary

2. **Investigation**
   - Review all audit logs (GCP, OS, application)
   - Check for unauthorized changes
   - Identify scope of compromise
   - Document timeline of events

3. **Remediation**
   - Apply security patches
   - Rotate all credentials
   - Update security rules
   - Review and fix identified vulnerabilities

4. **Recovery**
   - Restore from clean backups if necessary
   - Deploy patched versions
   - Gradually restore service
   - Monitor for signs of re-compromise

5. **Post-Incident**
   - Conduct post-mortem analysis
   - Document lessons learned
   - Update security policies
   - Communicate changes to stakeholders

---

## Security References

### Google Cloud Security
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Cloud Security Command Center](https://cloud.google.com/security-command-center)
- [Google Cloud IAM Best Practices](https://cloud.google.com/iam/docs/best-practices)
- [VPC Service Controls](https://cloud.google.com/vpc-service-controls)

### Web Application Security
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP Cheat Sheets](https://cheatsheetseries.owasp.org/)
- [Mozilla Web Security Guidelines](https://infosec.mozilla.org/guidelines/web_security)

### Linux Security
- [CIS Linux Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [Linux Foundation Security](https://www.linuxfoundation.org/projects/linux-foundation-referenced-specifications/)
- [Debian Security](https://www.debian.org/security/)

### SSL/TLS
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [NIST Cryptographic Standards](https://csrc.nist.gov/projects/cryptographic-standards-and-guidelines/)

---

## Security Advisories and Updates

### Staying Informed
- Subscribe to [Google Cloud Security Advisories](https://cloud.google.com/security/bulletins)
- Monitor [CVE Databases](https://cve.mitre.org/)
- Follow [Debian Security](https://security.debian.org/)
- Check [Node.js Security](https://nodejs.org/en/security/) (if using Node.js apps)

### Version Pinning
Pin specific versions in `package.json` for Node.js apps:
```json
{
  "dependencies": {
    "express": "4.18.2",
    "firestore": "7.0.0"
  }
}
```

---

## Contributors

Security is a shared responsibility. If you discover a vulnerability or have security suggestions, please follow the responsible disclosure process at the top of this document.

---

## Security Updates History

| Date | Update | Severity |
|------|--------|----------|
| 2025-11-29 | Initial security policy | - |

---

## License

This security policy is part of the google-free-tier project and is available under the same license as the main project (MIT License).

---

**Last Updated:** November 29, 2025  
**Version:** 1.0
