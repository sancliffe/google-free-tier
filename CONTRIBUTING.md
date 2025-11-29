# Contributing to google-free-tier

Thank you for your interest in contributing to the google-free-tier project! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Reporting Issues](#reporting-issues)
- [Security Issues](#security-issues)
- [Asking Questions](#asking-questions)
- [Recognition](#recognition)

---

## Code of Conduct

This project is committed to providing a welcoming and inspiring community for all. We expect all contributors to:

- Be respectful and constructive in all interactions
- Welcome newcomers and help them succeed
- Focus on what is best for the community
- Show empathy towards other community members
- Be patient and understanding
- Report unacceptable behavior to project maintainers

By participating, you agree to uphold this code of conduct.

---

## Getting Started

### Prerequisites

Before you start contributing, ensure you have:

- **Git** installed and configured
- **Google Cloud Project** (free tier eligible)
- **gcloud CLI** installed and authenticated
- **Bash shell** knowledge (for script contributions)
- **Basic understanding** of:
  - Terraform (for infrastructure changes)
  - Nginx (for web server changes)
  - Docker (for container changes)
  - Kubernetes (optional, for GKE changes)

### Fork and Clone

```bash
# Fork the repository on GitHub
# https://github.com/BranchingBad/google-free-tier

# Clone your fork
git clone https://github.com/YOUR_USERNAME/google-free-tier.git
cd google-free-tier

# Add upstream remote
git remote add upstream https://github.com/BranchingBad/google-free-tier.git

# Verify remotes
git remote -v
```

### Create a Branch

```bash
# Update main branch
git fetch upstream
git checkout main
git merge upstream/main

# Create feature branch
git checkout -b feature/your-feature-name
# or for bug fixes:
git checkout -b bugfix/issue-description
# or for documentation:
git checkout -b docs/documentation-title
```

Branch naming convention:
- `feature/description` - New features
- `bugfix/issue-number` - Bug fixes
- `docs/title` - Documentation improvements
- `refactor/description` - Code refactoring
- `test/description` - Test additions
- `chore/description` - Maintenance tasks

---

## Development Setup

### Local Environment

```bash
# Set up local test environment
cd /tmp
mkdir -p gft-test
cd gft-test

# Copy scripts from project
cp -r ~/git-projects/google-free-tier/2-host-setup/* .

# Create test VM (in GCP)
gcloud compute instances create test-gft \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --machine-type=e2-micro \
  --zone=us-central1-a
```

### Testing Scripts Locally

```bash
# Syntax validation
bash -n 2-host-setup/common.sh
bash -n 2-host-setup/1-create-swap.sh

# ShellCheck for style issues (if installed)
shellcheck 2-host-setup/*.sh

# Run script in test environment (safely)
sudo bash -x 2-host-setup/1-create-swap.sh
```

### GCP Project Setup for Testing

```bash
# Create test project
gcloud projects create gft-test --name="GFT Testing"

# Set as active
gcloud config set project gft-test

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable container.googleapis.com
```

---

## Making Changes

### Types of Contributions

#### 1. Bug Fixes

```bash
# Create bugfix branch
git checkout -b bugfix/issue-123-description

# Make your changes
# ... edit files ...

# Test thoroughly
bash -n scripts/file.sh
terraform validate

# Commit with reference
git add .
git commit -m "fix: Brief description of fix (closes #123)

Detailed explanation of what was broken and how this fixes it.
Include any relevant context or dependencies."
```

#### 2. New Features

```bash
# Create feature branch
git checkout -b feature/new-feature-name

# Implement feature
# ... create/edit files ...

# Add tests/verification
# ... add test scripts ...

# Update documentation
# ... update README/docs ...

# Commit feature
git add .
git commit -m "feat: Add new feature name

- Implement component A
- Implement component B
- Add documentation for feature"
```

#### 3. Documentation Improvements

```bash
# Create docs branch
git checkout -b docs/improve-readme

# Update documentation
# ... edit .md files ...

# Verify markdown formatting
cat README.md | head -50

# Commit
git add docs/
git commit -m "docs: Improve documentation clarity

- Clarify installation steps
- Add more examples
- Fix typos"
```

#### 4. Performance/Refactoring

```bash
# Create refactor branch
git checkout -b refactor/improve-script-efficiency

# Make improvements
# ... refactor code ...

# Verify functionality unchanged
bash -n scripts/file.sh
bash scripts/file.sh  # Run actual test

# Commit with notes
git add .
git commit -m "refactor: Improve script efficiency

- Reduce redundant operations
- Simplify error handling
- Maintain backward compatibility"
```

### File Organization

```
google-free-tier/
├── 1-gcp-setup/              # GCP account/project setup
├── 2-host-setup/             # VM setup scripts
│   ├── common.sh             # Shared functions
│   ├── 1-create-swap.sh      # Add swap memory
│   ├── 2-install-nginx.sh    # Web server
│   ├── 3-setup-duckdns.sh    # Dynamic DNS
│   ├── 4-setup-ssl.sh        # SSL certificates
│   ├── 5-adjust-firewall.sh  # Security rules
│   ├── 6-setup-backups.sh    # Automated backups
│   ├── 7-setup-security.sh   # Security hardening
│   └── 8-setup-ops-agent.sh  # Monitoring agent
├── 3-cloud-run-deployment/   # Cloud Run setup
├── 3-gke-deployment/         # Kubernetes setup
├── packer/                   # VM image building
├── terraform/                # Infrastructure as code
└── docs/                     # Documentation
```

When adding new files:
- Use clear, descriptive names
- Follow existing naming conventions
- Place in appropriate directory
- Update README with references

---

## Commit Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Commit Types

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style changes (formatting, semicolons, etc.)
- **refactor**: Code refactoring without feature changes
- **perf**: Performance improvements
- **test**: Adding or updating tests
- **chore**: Build, dependencies, or tooling changes
- **ci**: CI/CD configuration changes
- **security**: Security-related changes

### Commit Scope

Examples:
- `feat(swap)`: Changes to swap creation
- `fix(nginx)`: Nginx configuration fixes
- `docs(readme)`: README updates
- `refactor(common)`: Refactor common.sh

### Commit Examples

```bash
# Simple fix
git commit -m "fix(ssl): Handle certificate renewal timeout"

# Feature with details
git commit -m "feat(backups): Add archive verification

- Verify backup files are not empty
- Check GCS upload success
- Add detailed logging of backup process"

# Breaking change
git commit -m "feat(terraform)!: Restructure GCP resources

BREAKING CHANGE: This reorganizes the Terraform structure
and requires state migration. See MIGRATING.md for details."
```

### Before Committing

```bash
# Check what's staged
git status

# Review changes
git diff

# Review staged changes
git diff --staged

# Verify syntax of changed scripts
bash -n 2-host-setup/*.sh

# Run security checks
grep -r "password\|token\|secret" . --include="*.sh" --include="*.tf"
```

---

## Pull Request Process

### 1. Prepare Your PR

```bash
# Ensure your branch is up to date
git fetch upstream
git rebase upstream/main

# Push your branch
git push origin feature/your-feature-name
```

### 2. Create Pull Request

**Title Format:** `[TYPE] Brief description`
- ✅ Good: `[FEAT] Add automated backup verification`
- ✅ Good: `[FIX] Fix SSL certificate renewal timeout`
- ❌ Bad: `Updates`
- ❌ Bad: `Fix stuff`

**Description Template:**

```markdown
## Description
Brief description of what this PR does.

## Related Issues
Closes #123
Related to #456

## Changes Made
- Change 1
- Change 2
- Change 3

## Testing
- Tested on GCP e2-micro instance
- Verified scripts pass `bash -n` syntax check
- Tested backup restoration process

## Checklist
- [x] Code follows style guidelines
- [x] Self-reviewed my own code
- [x] Comments added for complex logic
- [x] Documentation updated
- [x] No new warnings generated
- [x] Added tests (if applicable)
- [x] Tests pass locally
- [x] No breaking changes (or documented)

## Screenshots/Evidence
If applicable, add screenshots or test output.

## Additional Context
Any additional context or concerns about this PR.
```

### 3. PR Requirements

Before submitting, ensure:

- [ ] Branch is based on latest `upstream/main`
- [ ] Commits follow Conventional Commits format
- [ ] Code follows project style guidelines
- [ ] Scripts pass `bash -n` syntax check
- [ ] No hardcoded secrets or credentials
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if applicable)
- [ ] Tests added/updated (if applicable)
- [ ] No unrelated changes included
- [ ] PR description is clear and complete

### 4. PR Review Process

**What to expect:**

1. **Automated Checks** (if configured)
   - Syntax validation
   - Security scanning
   - Dependency checks

2. **Maintainer Review**
   - Code quality assessment
   - Security review
   - Testing verification
   - Documentation review

3. **Feedback & Iteration**
   - Respond to reviewer comments
   - Make requested changes
   - Re-request review when ready

4. **Approval & Merge**
   - Maintainer approves PR
   - PR is merged to main
   - Your branch is deleted

### 5. Handling Feedback

```bash
# Make requested changes
# ... edit files ...

# Commit with clear message
git add .
git commit -m "Address review feedback

- Clarify error messages
- Add additional validation
- Improve test coverage"

# Push changes (no force push needed)
git push origin feature/your-feature-name

# Re-request review in PR comments
# (Mention reviewer: @username)
```

---

## Coding Standards

### Bash Scripts

**Style Guide:**

```bash
#!/bin/bash
set -euo pipefail

# Clear header comment
# Script: brief description
# Purpose: what this does
# Usage: how to use it

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Use meaningful variable names
readonly REQUIRED_DISK_SPACE=2500
readonly SWAP_FILE_PATH="/swapfile"
readonly SWAP_SIZE="2GB"

# Functions before main logic
create_swap_file() {
  local size="$1"
  log_info "Creating swap file: $size"
  # Implementation
}

verify_swap() {
  log_info "Verifying swap configuration"
  # Implementation
}

# Main logic
main() {
  log_info "Starting swap setup"
  
  # Validation
  ensure_root
  check_disk_space "/" "${REQUIRED_DISK_SPACE}"
  
  # Operations
  create_swap_file "${SWAP_SIZE}"
  verify_swap
  
  log_success "Swap setup completed"
}

# Execute main
main "$@"
```

**Best Practices:**

✅ **Do:**
- Use `set -euo pipefail` at the start
- Quote all variables: `"$var"` not `$var`
- Use `local` for function variables
- Make scripts idempotent (safe to re-run)
- Add error handling and cleanup
- Use meaningful variable names
- Document complex logic with comments
- Source common.sh for shared functions
- Use `log_info`, `log_error`, `log_success`
- Validate inputs and prerequisites

❌ **Don't:**
- Use backticks (use `$()` instead)
- Hardcode paths (use variables)
- Use `sudo` inside scripts (run script as root)
- Ignore errors (use `set -e`)
- Mix tabs and spaces
- Use cryptic variable names
- Leave debug code in production
- Commit secrets or credentials
- Use deprecated bash features
- Assume tools are installed

### Terraform

**Style Guide:**

```hcl
# Use consistent formatting
resource "google_compute_instance" "vm" {
  name         = "my-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  # Clear variable usage
  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_size
    }
  }

  # Use locals for computed values
  metadata = {
    startup-script = file("${path.module}/startup.sh")
  }

  tags = ["http", "https"]
}
```

**Best Practices:**

✅ Do:
- Use `terraform fmt` to format
- Use variables for parameterization
- Use locals for computed values
- Add descriptions to variables and outputs
- Use modules for code reuse
- Validate with `terraform validate`
- Plan before applying: `terraform plan`
- Use state locking
- Document assumptions

❌ Don't:
- Hardcode values
- Use inconsistent formatting
- Mix resources and data sources without organization
- Create unnecessary modules
- Skip validation
- Apply without planning
- Commit sensitive data (use `.gitignore`)
- Use deprecated resource types

### Documentation

**Markdown Style:**

```markdown
# Main Heading

## Section Heading

### Subsection

Clear, concise explanation using proper grammar.

#### Code Examples

Include practical examples:

\`\`\`bash
# Good example that demonstrates the concept
script_name --option value
\`\`\`

#### Important Notes

Use blockquotes for important information:

> **Note:** This is important context you should know.

Use tables for reference material:

| Option | Description | Default |
|--------|-------------|---------|
| --help | Show help message | N/A |
| --force | Force operation | false |

```

**Best Practices:**

✅ Do:
- Use clear, simple language
- Include practical examples
- Add headers and subheadings
- Use formatting (bold, italic, code blocks)
- Include tables for reference
- Add links to relevant docs
- Update when code changes
- Proofread before submitting

❌ Don't:
- Write unclear or vague explanations
- Leave documentation out of date
- Use overly technical jargon without explanation
- Forget to update related docs
- Include typos or grammar errors
- Leave broken links
- Make docs too long without sections

---

## Testing

### Script Testing

```bash
# 1. Syntax Check
bash -n 2-host-setup/common.sh
bash -n 2-host-setup/1-create-swap.sh

# 2. ShellCheck (if installed)
shellcheck 2-host-setup/*.sh

# 3. Dry-Run Test
# For scripts with --dry-run option
./2-host-setup/script.sh --dry-run

# 4. Test on VM
gcloud compute ssh your-vm --zone=us-central1-a \
  --command="bash -s" < 2-host-setup/1-create-swap.sh

# 5. Verify Results
gcloud compute ssh your-vm --zone=us-central1-a \
  --command="free -h"  # Verify swap was created
```

### Terraform Testing

```bash
# Validate syntax
terraform validate

# Format check
terraform fmt -check -recursive

# Plan changes (no apply)
terraform plan -out=tfplan

# Show plan details
terraform show tfplan

# Destroy test infrastructure
terraform destroy -auto-approve
```

### Manual Testing Checklist

For new features, test:

- [ ] Runs without errors
- [ ] Idempotent (safe to re-run)
- [ ] Handles missing dependencies gracefully
- [ ] Shows clear error messages on failure
- [ ] Cleans up on exit
- [ ] Works with different input values
- [ ] Logs all important operations
- [ ] Doesn't expose sensitive data in logs

---

## Documentation

### Update Documentation When

- Adding new features
- Changing existing behavior
- Fixing bugs that might affect users
- Updating dependencies
- Changing installation steps
- Adding new scripts or modules

### Files to Update

1. **README.md** - Main documentation
   - Feature overview
   - Installation steps
   - Usage examples
   - Troubleshooting

2. **BASH_IMPROVEMENTS.md** - Bash-specific documentation
   - Function documentation
   - Usage examples
   - Best practices

3. **CHANGELOG.md** - Version history
   - Added features
   - Bug fixes
   - Breaking changes

4. **CONTRIBUTING.md** - This file (contribution guidelines)

5. **SECURITY.md** - Security information
   - New security features
   - Vulnerability information

6. **RELEASING.md** - Release procedures
   - Version updates

### Documentation Review

Before submitting PR:

```bash
# Check for typos
grep -n "teh\|recieve\|occured" *.md

# Verify links work
grep -o '\[.*\](.*)'

# Check code block formatting
grep -A 2 '```'

# Review for clarity
# Read documentation aloud or have someone review
```

---

## Reporting Issues

### Before Reporting

- [ ] Search existing issues
- [ ] Check documentation for the answer
- [ ] Try the latest version
- [ ] Gather relevant information

### Issue Template

**Title:** `[CATEGORY] Brief description`

**Description:**

```markdown
## Description
Clear description of the issue.

## Environment
- OS: Ubuntu 20.04
- GCP Region: us-central1
- Project Version: 1.1.0
- VM Type: e2-micro

## Steps to Reproduce
1. First step
2. Second step
3. Third step

## Expected Behavior
What should happen

## Actual Behavior
What actually happened

## Error Output
```
Error message or log output
```

## Attempted Solutions
What you've already tried to fix it

## Additional Context
Screenshots, configuration files, or other context
```

### Issue Categories

- 🐛 **Bug Report** - Something isn't working
- ✨ **Feature Request** - Suggest a new feature
- 📚 **Documentation** - Documentation improvement
- 🤔 **Question** - How do I...?
- 🔒 **Security** - Security vulnerability (see Security Issues)

---

## Security Issues

**Do NOT open public issues for security vulnerabilities!**

Please follow the responsible disclosure process in [SECURITY.md](SECURITY.md):

1. Email security details to maintainers
2. Include detailed information about the vulnerability
3. Allow time for fixes before public disclosure
4. Credit will be given in release notes

---

## Asking Questions

### Where to Ask

- **Documentation unclear?** → Open an issue with the `documentation` label
- **How do I...?** → Start a GitHub Discussion
- **Bug or unexpected behavior?** → Open an issue with the `bug` label
- **Feature request?** → Open an issue with the `enhancement` label
- **Quick question?** → Ask in GitHub Discussions

### Question Guidelines

✅ Do:
- Be specific and detailed
- Include error messages
- Describe what you've tried
- Provide context and environment info
- Be respectful and patient

❌ Don't:
- Ask for email/private help
- Demand immediate responses
- Be disrespectful
- Report bugs as questions
- Include sensitive credentials

---

## Recognition

### Contribution Recognition

Contributors are recognized in:

1. **Git commit history** - Your name and email
2. **GitHub contributor graph** - Shows your contributions
3. **CHANGELOG.md** - Named in release notes
4. **GitHub Releases** - Listed as contributor
5. **Project discussions** - Thanked publicly

### Getting Credit

```bash
# Configure your git identity
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Verify configuration
git config --list | grep user
```

### Types of Contributions Recognized

- 💻 Code contributions
- 📚 Documentation
- 🐛 Bug reports and fixes
- 💡 Feature suggestions
- 🔍 Code reviews
- ❓ Community support
- 🎨 Design improvements
- 🏗️ Infrastructure improvements

---

## Additional Resources

### Documentation
- [README.md](README.md) - Project overview
- [SECURITY.md](SECURITY.md) - Security guidelines
- [RELEASING.md](RELEASING.md) - Release process
- [BASH_IMPROVEMENTS.md](BASH_IMPROVEMENTS.md) - Bash functions documentation

### External Resources
- [Git Documentation](https://git-scm.com/doc)
- [GitHub Guides](https://guides.github.com/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Google Cloud Documentation](https://cloud.google.com/docs)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [Terraform Documentation](https://www.terraform.io/docs)

### Getting Help
- Open a GitHub Discussion
- Check existing issues
- Review documentation
- Ask in pull request comments

---

## Questions About Contributing?

If you have questions about the contribution process:

1. Check this document first
2. Search GitHub Discussions
3. Open a new Discussion with your question
4. Be as specific as possible about what you need help with

---

## Thank You! 🎉

We appreciate your contributions to making google-free-tier better for everyone. Whether you're fixing bugs, adding features, improving documentation, or helping other users, you're helping the community grow.

Happy contributing! 🚀

---

**Last Updated:** November 29, 2025  
**Version:** 1.0
