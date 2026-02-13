#!/bin/bash
# release.sh — 创建 git tag 并推送到 GitHub 触发 release 构建
#
# 功能：
#   1. 检查工作目录是否干净（避免忘记提交代码）
#   2. 检查当前分支是否已推送到远程
#   3. 验证版本号格式（语义化版本 x.y.z）
#   4. 检查 tag 是否已存在（防止重复发布）
#   5. 创建带注释的 git tag 并推送到 GitHub
#   6. 推送后会自动触发 .github/workflows/release.yml 工作流
#
# 用法：
#   ./scripts/release.sh 1.0.0        # 创建 v1.0.0 tag 并推送
#   ./scripts/release.sh 1.0.0 --dry  # 预演模式，只检查不执行
#
# 依赖：
#   - git（版本管理）
#   - gh（GitHub CLI，用于显示 Actions 链接，可选）

set -euo pipefail

# ── 颜色定义 ──────────────────────────────────────────────────
# ANSI 转义码用于在终端输出带颜色的文字，提升可读性
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color（重置颜色）

# ── 辅助函数 ──────────────────────────────────────────────────
# 统一的日志输出格式
info()  { echo -e "${CYAN}==> ${NC}$1"; }
ok()    { echo -e "${GREEN}  ✓ ${NC}$1"; }
warn()  { echo -e "${YELLOW}  ⚠ ${NC}$1"; }
error() { echo -e "${RED}  ✗ ${NC}$1" >&2; }

# ── 解析参数 ──────────────────────────────────────────────────
# $# 是 bash 的特殊变量，表示传入的参数个数
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <version> [--dry]"
    echo ""
    echo "Examples:"
    echo "  $0 1.0.0        # Create and push v1.0.0 tag"
    echo "  $0 1.0.0 --dry  # Dry run, check only"
    echo ""
    echo "Recent tags:"
    # git tag --sort=-creatordate：按创建时间倒序列出 tag
    # head -5：只显示最近 5 个
    git tag --sort=-creatordate | head -5 || echo "  (no tags yet)"
    exit 1
fi

VERSION="$1"
DRY_RUN=false

# 检查是否传入了 --dry 参数
if [[ "${2:-}" == "--dry" ]]; then
    DRY_RUN=true
fi

# ── 验证版本号格式 ────────────────────────────────────────────
# 语义化版本号（Semantic Versioning）格式：主版本.次版本.修订号
# =~ 是 bash 的正则匹配运算符
# ^[0-9]+\.[0-9]+\.[0-9]+$ 匹配 x.y.z 格式（纯数字）
TAG="v${VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: '${VERSION}'"
    echo "  Expected: x.y.z (e.g. 1.0.0, 0.2.1)"
    exit 1
fi

ok "Version format valid: ${TAG}"

# ── 检查是否在 git 仓库中 ────────────────────────────────────
# rev-parse --git-dir 检查当前目录是否在 git 仓库内
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository"
    exit 1
fi

# ── 检查工作目录是否干净 ──────────────────────────────────────
# git status --porcelain 以机器可读格式输出状态
# 如果输出不为空，说明有未提交的更改
if [[ -n "$(git status --porcelain)" ]]; then
    error "Working directory is not clean. Please commit or stash changes first."
    echo ""
    git status --short
    exit 1
fi

ok "Working directory is clean"

# ── 检查当前分支 ──────────────────────────────────────────────
# git branch --show-current 显示当前分支名
BRANCH=$(git branch --show-current)
info "Current branch: ${BRANCH}"

# 通常建议从 main 分支发布，但不强制
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
    warn "Not on main/master branch (current: ${BRANCH})"
    # -r 让 read 支持反斜杠，-p 显示提示符
    read -r -p "  Continue anyway? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ── 检查本地是否领先远程 ──────────────────────────────────────
# 确保所有代码都已推送到远程，避免 tag 指向远程没有的 commit
# git rev-parse HEAD 获取本地最新 commit 的 hash
# git rev-parse @{u} 获取上游（远程跟踪分支）的最新 commit hash
# @{u} 是 git 的简写，等同于 origin/<branch>
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

# ── 检查 tag 是否已存在 ───────────────────────────────────────
# git rev-parse 检查 tag 是否存在，输出丢弃到 /dev/null
if git rev-parse "$TAG" > /dev/null 2>&1; then
    error "Tag '${TAG}' already exists!"
    echo "  To delete and recreate:"
    echo "    git tag -d ${TAG}"
    echo "    git push origin :refs/tags/${TAG}"
    exit 1
fi

ok "Tag '${TAG}' is available"

# ── 显示发布摘要 ──────────────────────────────────────────────
echo ""
info "Release Summary"
echo "  Tag:      ${TAG}"
echo "  Branch:   ${BRANCH}"
# git rev-parse --short HEAD 输出 7 位短 hash，更易读
echo "  Commit:   $(git rev-parse --short HEAD)"
# git log -1 --format=%s 获取最新 commit 的标题（%s = subject）
echo "  Message:  $(git log -1 --format=%s)"
echo ""

# ── 预演模式检查 ──────────────────────────────────────────────
if $DRY_RUN; then
    info "Dry run complete. No changes made."
    echo "  Remove --dry to create and push the tag."
    exit 0
fi

# ── 确认发布 ──────────────────────────────────────────────────
read -r -p "Create and push ${TAG}? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
fi

# ── 创建带注释的 tag ──────────────────────────────────────────
# -a 创建带注释的 tag（annotated tag），会存储额外的元数据（作者、日期、消息）
# 相比轻量级 tag（lightweight tag），annotated tag 更适合发布版本
# -m 指定 tag 的注释消息
info "Creating tag ${TAG} ..."
git tag -a "$TAG" -m "Release ${TAG}"
ok "Tag created"

# ── 推送 tag 到远程 ───────────────────────────────────────────
# 只推送特定 tag，不用 --tags（避免推送所有本地 tag）
info "Pushing ${TAG} to origin ..."
git push origin "$TAG"
ok "Tag pushed"

# ── 显示结果 ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}==> Release ${TAG} triggered! ${NC}"
echo ""

# 尝试用 gh CLI 显示 Actions 运行链接（gh 是 GitHub 官方的命令行工具）
# command -v 检查命令是否存在（类似 which，但更可靠）
if command -v gh > /dev/null 2>&1; then
    # gh api 调用 GitHub REST API 获取仓库信息
    # --jq 使用 jq 语法从 JSON 响应中提取字段
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
