# Release Guide

This document describes the process for releasing new versions of the google-free-tier project.

## Versioning Strategy

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version (X.0.0) - Breaking changes to scripts or infrastructure
- **MINOR** version (0.X.0) - New features or improvements (backward compatible)
- **PATCH** version (0.0.X) - Bug fixes and security patches

### Examples

```
1.0.0 → 1.1.0  (New feature: Firestore visitor counter)
1.1.0 → 1.1.1  (Bug fix: SSL certificate renewal issue)
1.1.1 → 2.0.0  (Breaking change: New infrastructure approach)
```

---

## Pre-Release Checklist

### Code Quality
- [ ] All tests pass (if applicable)
- [ ] No uncommitted changes (`git status` is clean)
- [ ] All security issues are resolved
- [ ] Code follows project conventions
- [ ] Recent commits are reviewed and approved

### Documentation
- [ ] README.md is up-to-date
- [ ] CHANGELOG.md is updated with all changes
- [ ] API/script documentation is current
- [ ] Examples are tested and working
- [ ] Known issues are documented

### Security
- [ ] No hardcoded secrets in code
- [ ] Dependencies are up-to-date
- [ ] Security advisories have been reviewed
- [ ] .gitignore includes all sensitive files
- [ ] SECURITY.md is current

### Testing
- [ ] Manual testing on fresh GCP project completed
- [ ] All scripts execute without errors
- [ ] Firewall rules work as expected
- [ ] Backups can be restored
- [ ] SSL certificates renew properly

### Cleanup
- [ ] Remove debug code and console logs
- [ ] Remove temporary test files
- [ ] Remove commented-out code
- [ ] Update any TODO comments
- [ ] Verify no large files are committed

---

## Release Process

### Step 1: Prepare Release Branch

```bash
# Update to latest main
git checkout main
git pull origin main

# Create release branch
git checkout -b release/X.Y.Z
```

### Step 2: Update Version Numbers

Update version references in:

#### 2.1 README.md
```bash
# Find and update version in README
grep -n "version" README.md
# Update the version line in the document
```

#### 2.2 package.json (if using Node.js components)
```json
{
  "version": "X.Y.Z",
  "name": "google-free-tier",
  "description": "..."
}
```

#### 2.3 Terraform variables
```hcl
# terraform/variables.tf
variable "project_version" {
  default = "X.Y.Z"
}
```

#### 2.4 Dockerfile labels (if applicable)
```dockerfile
LABEL version="X.Y.Z"
LABEL release="X.Y.Z"
```

### Step 3: Update CHANGELOG.md

Create or update `CHANGELOG.md` at the root of the project:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [X.Y.Z] - YYYY-MM-DD

### Added
- New feature 1
- New feature 2

### Changed
- Improvement 1
- Improvement 2

### Fixed
- Bug fix 1
- Bug fix 2

### Security
- Security fix 1
- Security fix 2

### Deprecated
- Feature to be removed in next major version

### Removed
- Removed deprecated feature

### Breaking Changes
- Description of breaking changes (if MAJOR version)

## [X.Y.Z-1] - YYYY-MM-DD

...
```

**Template for each release:**

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- Detailed description of new features

### Changed
- Detailed description of changes

### Fixed
- Detailed description of bug fixes

### Security
- Security improvements or fixes

### Known Issues
- Known limitations in this release

### Migration Guide
- Steps for users to upgrade from previous version (if breaking changes)
```

### Step 4: Update Documentation

Review and update as needed:

```bash
# Check README.md
cat README.md | head -50

# Check SECURITY.md
tail -5 SECURITY.md

# Check BASH_IMPROVEMENTS.md
head -30 BASH_IMPROVEMENTS.md

# Review all documentation
grep -r "TODO" . --include="*.md"
```

Update version history at the end of SECURITY.md:

```markdown
## Security Updates History

| Date | Update | Severity |
|------|--------|----------|
| YYYY-MM-DD | Security improvements in X.Y.Z | - |
| 2025-11-28 | Initial security policy | - |
```

### Step 5: Commit Changes

```bash
# Stage all changes
git add README.md CHANGELOG.md SECURITY.md package.json terraform/variables.tf

# Commit with clear message
git commit -m "chore: Prepare release X.Y.Z

- Update version numbers across all components
- Update CHANGELOG with all improvements
- Update SECURITY.md with latest advisories
- Verify all documentation is current"

# Verify commit
git log -1 --stat
```

### Step 6: Create Release Tag

```bash
# Create annotated tag
git tag -a vX.Y.Z -m "Release version X.Y.Z

Release highlights:
- Feature/fix 1
- Feature/fix 2
- Feature/fix 3

See CHANGELOG.md for complete details."

# Verify tag
git tag -l -n5 vX.Y.Z

# Show full tag details
git show vX.Y.Z
```

### Step 7: Push to Repository

```bash
# Push release branch
git push origin release/X.Y.Z

# Push tag
git push origin vX.Y.Z

# Verify push
git branch -r | grep release
git tag -l | grep vX.Y.Z
```

### Step 8: Create GitHub Release

1. Go to: `https://github.com/BranchingBad/google-free-tier/releases`
2. Click "Draft a new release"
3. Select tag: `vX.Y.Z`
4. Fill in release title: `Release X.Y.Z`
5. Copy CHANGELOG content into description
6. For pre-releases, check "This is a pre-release"
7. Click "Publish release"

**Release Description Template:**

```markdown
# Release X.Y.Z - [Release Name/Theme]

## What's New

### Features
- Feature 1: Description
- Feature 2: Description

### Improvements
- Improvement 1: Description
- Improvement 2: Description

### Bug Fixes
- Bug 1: Description
- Bug 2: Description

### Security Updates
- Security fix 1: Description
- Security fix 2: Description

## Upgrading

### From X.Y.Z-1
No breaking changes. Simply pull the latest code:
```bash
git pull origin main
git checkout vX.Y.Z
```

### From earlier versions
See CHANGELOG.md for migration steps if applicable.

## Contributors
- Contributor 1
- Contributor 2
- Contributor 3 (and [X more](https://github.com/BranchingBad/google-free-tier/graphs/contributors))

## Downloads
- Source code: [zip](https://github.com/BranchingBad/google-free-tier/archive/refs/tags/vX.Y.Z.zip)
- Source code: [tar.gz](https://github.com/BranchingBad/google-free-tier/archive/refs/tags/vX.Y.Z.tar.gz)
```

### Step 9: Merge Release Branch

```bash
# Switch to main
git checkout main

# Pull latest
git pull origin main

# Merge release branch
git merge release/X.Y.Z

# Push to main
git push origin main
```

### Step 10: Delete Release Branch

```bash
# Delete local branch
git branch -d release/X.Y.Z

# Delete remote branch
git push origin --delete release/X.Y.Z

# Verify deletion
git branch -r | grep release
```

---

## Post-Release Tasks

### Communication
- [ ] Announce release in project discussions
- [ ] Update social media/community channels
- [ ] Notify stakeholders of new features/fixes
- [ ] Send announcement email (if applicable)

### Monitoring
- [ ] Monitor issue tracker for problems
- [ ] Watch for bug reports related to new features
- [ ] Track download/usage statistics
- [ ] Respond to user questions

### Documentation
- [ ] Update external documentation sites
- [ ] Archive old release documentation
- [ ] Update installation instructions
- [ ] Add release to version matrix

### Maintenance
- [ ] Create GitHub Discussions post for feedback
- [ ] Backport critical fixes to older versions (if applicable)
- [ ] Update project roadmap
- [ ] Plan next release cycle

---

## Hotfix Releases (X.Y.Z+1)

For urgent security or critical bug fixes:

```bash
# Create hotfix branch from tag
git checkout -b hotfix/X.Y.Z+1 vX.Y.Z

# Make fixes
# ... commit changes ...

# Update version and CHANGELOG
git add CHANGELOG.md README.md
git commit -m "chore: Prepare hotfix X.Y.Z+1"

# Tag and release
git tag -a vX.Y.Z+1 -m "Hotfix release X.Y.Z+1"
git push origin hotfix/X.Y.Z+1
git push origin vX.Y.Z+1

# Merge back to main
git checkout main
git pull origin main
git merge hotfix/X.Y.Z+1
git push origin main
```

---

## Release Workflow Diagram

```
main branch
    ↓
create release/X.Y.Z
    ↓
Update versions & CHANGELOG
    ↓
Commit: "Prepare release X.Y.Z"
    ↓
Create tag: vX.Y.Z
    ↓
Push branch & tag
    ↓
Create GitHub Release
    ↓
Merge to main
    ↓
Delete release branch
    ↓
v X.Y.Z Released! ✓
```

---

## Version History

| Version | Release Date | Status |
|---------|--------------|--------|
| 2.0.0 | 2025-11-29 | Latest |
| 1.1.0 | 2025-11-29 | Stable |
| 1.0.0 | 2025-11-01 | Stable |

---

## Troubleshooting

### Tag Already Exists

```bash
# Delete local tag
git tag -d vX.Y.Z

# Delete remote tag
git push origin --delete vX.Y.Z

# Recreate tag
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z
```

### Wrong Commit in Release

```bash
# Reset to previous commit
git reset --hard HEAD~1

# Force push (use with caution!)
git push origin release/X.Y.Z --force

# Delete and recreate tag if needed
git tag -d vX.Y.Z
git push origin --delete vX.Y.Z
```

### Merge Conflicts

```bash
# Resolve conflicts manually
git status
# Edit conflicting files

# Stage resolved files
git add resolved_file.txt

# Complete merge
git commit -m "Merge release/X.Y.Z into main"
```

### Can't Push to Repository

```bash
# Verify remote is configured
git remote -v

# Verify you have push permissions
# Check GitHub credentials
git config --global --list | grep github

# Try pushing again with verbose output
git push origin main -v
```

---

## Best Practices

### ✅ Do

- Create a release branch for version updates
- Write detailed CHANGELOG entries
- Test releases in staging before announcing
- Use semantic versioning consistently
- Document breaking changes clearly
- Tag releases with annotated tags
- Keep release notes concise but informative
- Announce releases to users
- Plan releases in advance
- Review all changes before release

### ❌ Don't

- Release directly from main without a release branch
- Skip CHANGELOG updates
- Use lightweight tags for releases
- Merge unreviewed code into releases
- Release without testing
- Forget to update version numbers
- Release with known critical bugs
- Change version numbers mid-release
- Skip documentation updates
- Release at unusual hours (if possible)

---

## Release Cadence

| Phase | Duration | Details |
|-------|----------|---------|
| Planning | 1-2 weeks | Gather requirements, plan features |
| Development | 2-4 weeks | Implement features, fix bugs |
| Testing | 1 week | Comprehensive testing, bug fixes |
| Release Prep | 2-3 days | Documentation, version updates |
| Release | 1 day | Tag, publish, announce |
| Monitoring | 1 week | Watch for issues, respond to feedback |

---

## Security Considerations

Before releasing:

1. **Review all commits** for accidentally committed secrets
   ```bash
   git log --oneline vX.Y.Z-1..vX.Y.Z | while read commit; do
     git show $commit | grep -i "password\|token\|api.key\|secret"
   done
   ```

2. **Check dependencies** for known vulnerabilities
   ```bash
   npm audit (if using npm)
   safety check (if using Python)
   ```

3. **Verify permissions** on sensitive files
   ```bash
   find . -type f -perm /go+w -ls
   ```

4. **Scan for secrets**
   ```bash
   git log -p | grep -i "password\|token\|api"
   ```

---

## Continuous Integration

If using GitHub Actions (recommended setup):

```yaml
name: Release CI

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Verify syntax
        run: |
          for script in 2-host-setup/*.sh; do
            bash -n "$script"
          done
      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
```

---

## References

- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [Git Tagging](https://git-scm.com/book/en/v2/Git-Basics-Tagging)
- [Conventional Commits](https://www.conventionalcommits.org/)

---

**Last Updated:** November 29, 2025  
**Version:** 1.0
