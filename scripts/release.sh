#!/bin/bash
# release.sh — Create git tag and push to GitHub to trigger release build
#
# Features:
#   1. Check if working directory is clean (prevent forgetting to commit code)
#   2. Check if current branch is pushed to remote
#   3. Validate version format (semantic versioning x.y.z)
#   4. Check if tag already exists (prevent duplicate releases)
#   5. Create annotated git tag and push to GitHub
#   6. Pushing will automatically trigger .github/workflows/release.yml workflow
#
# Usage:
#   ./scripts/release.sh 1.0.0        # Create and push v1.0.0 tag
#   ./scripts/release.sh 1.0.0 --dry  # Dry run, only check, no execution
#
# Dependencies:
#   - git (version control)
#   - gh (GitHub CLI, for displaying Actions links, optional)

set -euo pipefail

# ── Color Definitions ──────────────────────────────────────────────────
# ANSI escape codes for colored terminal output to improve readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color (reset color)

# ── Helper Functions ──────────────────────────────────────────────────
# Unified log output format
info()  { echo -e "${CYAN}==> ${NC}$1"; }
ok()    { echo -e "${GREEN}  ✓ ${NC}$1"; }
warn()  { echo -e "${YELLOW}  ⚠ ${NC}$1"; }
error() { echo -e "${RED}  ✗ ${NC}$1" >&2; }

# ── Parse Arguments ──────────────────────────────────────────────────
# $# is bash special variable, representing number of arguments passed
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <version> [--dry]"
    echo ""
    echo "Examples:"
    echo "  $0 1.0.0        # Create and push v1.0.0 tag"
    echo "  $0 v1.0.0       # Same as above (v prefix is optional)"
    echo "  $0 1.0.0 --dry  # Dry run, check only"
    echo ""
    echo "Recent tags:"
    # git tag --sort=-creatordate: List tags sorted by creation date descending
    # head -5: Show only latest 5
    git tag --sort=-creatordate | head -5 || echo "  (no tags yet)"
    exit 1
fi

INPUT="$1"
DRY_RUN=false

# Check if --dry argument is passed
if [[ "${2:-}" == "--dry" ]]; then
    DRY_RUN=true
fi

# ── Validate Version Format ────────────────────────────────────────────
# Semantic Versioning format: Major.Minor.Patch
# Supports two input formats: v1.0.0 or 1.0.0, handled uniformly
# ${INPUT#v} is bash parameter expansion syntax, removing prefix "v" (if present)
VERSION="${INPUT#v}"
TAG="v${VERSION}"

# =~ is bash regex match operator
# ^[0-9]+\.[0-9]+\.[0-9]+$ matches x.y.z format (digits only)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: '${INPUT}'"
    echo "  Expected: x.y.z or vx.y.z (e.g. 1.0.0, v0.2.1)"
    exit 1
fi

ok "Version format valid: ${TAG}"

# ── Check if inside git repository ────────────────────────────────────
# rev-parse --git-dir checks if current directory is inside a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository"
    exit 1
fi

# ── Check if working directory is clean ──────────────────────────────────────
# git status --porcelain outputs status in machine-readable format
# If output is not empty, there are uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
    error "Working directory is not clean. Please commit or stash changes first."
    echo ""
    git status --short
    exit 1
fi

ok "Working directory is clean"

# ── Check current branch ──────────────────────────────────────────────
# git branch --show-current shows current branch name
BRANCH=$(git branch --show-current)
info "Current branch: ${BRANCH}"

# Usually recommended to release from main branch, but not enforced
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
    warn "Not on main/master branch (current: ${BRANCH})"
    # -r allows read backslash, -p shows prompt
    read -r -p "  Continue anyway? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ── Check if local is ahead of remote ──────────────────────────────────────
# Ensure all code is pushed to remote, avoid tag pointing to commit not on remote
# git rev-parse HEAD gets local latest commit hash
# git rev-parse @{u} gets upstream (remote tracking branch) latest commit hash
# @{u} is git shorthand, equivalent to origin/<branch>
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse "@{u}" 2>/dev/null || echo "")

if [[ -z "$REMOTE_HEAD" ]]; then
    error "No upstream branch set. Push your branch first:"
    echo "  git push -u origin ${BRANCH}"
    exit 1
fi

if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
    error "Local branch is out of sync with remote."
    echo "  Please push or pull first:"
    echo "    git push origin ${BRANCH}"
    exit 1
fi

ok "Branch is in sync with remote"

# ── Check if tag already exists ───────────────────────────────────────
# git rev-parse checks if tag exists, output discarded to /dev/null
if git rev-parse "$TAG" > /dev/null 2>&1; then
    error "Tag '${TAG}' already exists!"
    echo "  To delete and recreate:"
    echo "    git tag -d ${TAG}"
    echo "    git push origin :refs/tags/${TAG}"
    exit 1
fi

ok "Tag '${TAG}' is available"

# ── Show Release Summary ──────────────────────────────────────────────
echo ""
info "Release Summary"
echo "  Tag:      ${TAG}"
echo "  Branch:   ${BRANCH}"
# git rev-parse --short HEAD outputs 7-char short hash, more readable
echo "  Commit:   $(git rev-parse --short HEAD)"
# git log -1 --format=%s gets latest commit subject (%s = subject)
echo "  Message:  $(git log -1 --format=%s)"
echo ""

# ── Dry run check ──────────────────────────────────────────────
if $DRY_RUN; then
    info "Dry run complete. No changes made."
    echo "  Remove --dry to create and push the tag."
    exit 0
fi

# ── Confirm Release ──────────────────────────────────────────────────
read -r -p "Create and push ${TAG}? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
fi

# ── Create annotated tag ──────────────────────────────────────────
# -a creates annotated tag, storing extra metadata (author, date, message)
# Compared to lightweight tag, annotated tag is better for version release
# -m specifies tag message
info "Creating tag ${TAG} ..."
git tag -a "$TAG" -m "Release ${TAG}"
ok "Tag created"

# ── Push tag to remote ───────────────────────────────────────────
# Push only specific tag, not --tags (avoid pushing all local tags)
info "Pushing ${TAG} to origin ..."
git push origin "$TAG"
ok "Tag pushed"

# ── Show Results ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}==> Release ${TAG} triggered! ${NC}"
echo ""

# Try to use gh CLI to show Actions run link (gh is GitHub official CLI tool)
# command -v checks if command exists (similar to which, but more reliable)
if command -v gh > /dev/null 2>&1; then
    # gh api calls GitHub REST API to get repo info
    # --jq uses jq syntax to extract fields from JSON response
    REPO_URL=$(gh api repos/:owner/:repo --jq '.html_url' 2>/dev/null || echo "")
    if [[ -n "$REPO_URL" ]]; then
        echo "  Actions:  ${REPO_URL}/actions"
        echo "  Release:  ${REPO_URL}/releases/tag/${TAG}"
    fi
else
    echo "  Tip: Install GitHub CLI (gh) to see direct links to Actions."
fi

echo ""
echo "  The release workflow will:"
echo "    1. Run tests"
echo "    2. Build universal binary (.app)"
echo "    3. Create GitHub Release with zip download"
