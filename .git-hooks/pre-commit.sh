#!/bin/bash

# --- Pre-commit Hook ---
# This hook runs linting and formatting checks before allowing a commit.
# To install:
#    cp .git-hooks/pre-commit .git/hooks/pre-commit
#    chmod +x .git/hooks/pre-commit
# Or configure git to use the .git-hooks directory directly:
#    git config core.hooksPath .git-hooks

echo "Running pre-commit checks..."

# Check shell scripts with shellcheck
echo "--> Running shellcheck on staged shell scripts..."
if git diff --cached --name-only --diff-filter=ACM -- '*.sh' | grep -q .; then
  git diff --cached --name-only --diff-filter=ACM -z -- '*.sh' | xargs -0 shellcheck
  if [ $? -ne 0 ]; then
    echo "Shellcheck failed. Please fix the issues before committing."
    exit 1
  fi
else
  echo "No staged shell scripts to check."
fi

# Check Terraform formatting
echo "--> Running terraform fmt -check on staged .tf files..."
if git diff --cached --name-only --diff-filter=ACM -- '*.tf' | grep -q .; then
  git diff --cached --name-only --diff-filter=ACM -z -- '*.tf' | xargs -0 terraform fmt -check
  if [ $? -ne 0 ]; then
    echo "Terraform formatting issues detected. Run 'terraform fmt' to fix."
    exit 1
  fi
else
  echo "No staged Terraform files to check."
fi

echo "Pre-commit checks passed."
exit 0
