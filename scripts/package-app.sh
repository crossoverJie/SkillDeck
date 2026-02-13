#!/bin/bash
# package-app.sh — 构建通用二进制文件并组装 macOS .app bundle
#
# 功能：
#   1. 使用 swift build 编译 arm64 + x86_64 通用二进制
#   2. 创建标准 .app bundle 目录结构
#   3. 生成 Info.plist（包含版本号等元数据）
#   4. 复制图标和 SPM 资源 bundle
#
# 用法：
#   ./scripts/package-app.sh                    # 默认版本 0.0.0-dev
#   ./scripts/package-app.sh --version 1.0.0    # 指定版本号
#
# 输出：
#   build/SkillDeck.app

set -euo pipefail

# ── 解析命令行参数 ──────────────────────────────────────────
# 默认版本号，用于本地开发构建
VERSION="0.0.0-dev"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--version X.Y.Z]"
            exit 1
            ;;
    esac
done

echo "==> Building SkillDeck v${VERSION}"

# ── 获取项目根目录 ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# ── 编译通用二进制（arm64 + x86_64）─────────────────────────
# --arch 参数让 Swift 编译双架构，生成的二进制同时支持 Intel 和 Apple Silicon Mac
echo "==> Building universal binary (arm64 + x86_64) ..."
swift build -c release --arch arm64 --arch x86_64

# ── 定位编译产物 ─────────────────────────────────────────────
# 通用二进制构建输出在 .build/apple/Products/Release/ 目录下
BINARY_PATH=".build/apple/Products/Release/SkillDeck"

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    echo "Trying single-arch path ..."
    BINARY_PATH=".build/release/SkillDeck"
    if [ ! -f "$BINARY_PATH" ]; then
        echo "Error: Binary not found. Build may have failed."
        exit 1
    fi
fi

echo "==> Binary found: $BINARY_PATH"
echo "    Architecture: $(file "$BINARY_PATH" | sed 's/.*: //')"

# ── 定位 SPM 资源 bundle ────────────────────────────────────
# SPM 会将 Package.swift 中 resources 声明的文件打包为 <Target>_<Target>.bundle
# 通用构建路径在 .build/apple/Products/Release/，单架构在 .build/release/
RESOURCE_BUNDLE=""
for candidate in \
    ".build/apple/Products/Release/SkillDeck_SkillDeck.bundle" \
    ".build/release/SkillDeck_SkillDeck.bundle"; do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done

if [ -z "$RESOURCE_BUNDLE" ]; then
    echo "Warning: SPM resource bundle not found. App may lack bundled resources."
fi

# ── 创建 .app bundle 目录结构 ────────────────────────────────
# macOS .app bundle 是一个特殊目录结构，Finder 会将其显示为单个应用图标
# 标准结构：
#   SkillDeck.app/Contents/
#     Info.plist          ← 应用元数据（版本号、标识符等）
#     MacOS/SkillDeck     ← 可执行文件
#     Resources/          ← 图标、资源文件
APP_DIR="build/SkillDeck.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 清理旧的构建产物
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Assembling .app bundle ..."

# ── 复制可执行文件 ───────────────────────────────────────────
cp "$BINARY_PATH" "$MACOS_DIR/SkillDeck"
chmod +x "$MACOS_DIR/SkillDeck"

# ── 复制应用图标 ─────────────────────────────────────────────
ICON_SOURCE="Sources/SkillDeck/Resources/AppIcon.icns"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
    echo "    Copied AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found at $ICON_SOURCE"
fi

# ── 复制 SPM 资源 bundle ────────────────────────────────────
# Bundle.module 在运行时会查找同级目录下的资源 bundle
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    echo "    Copied SPM resource bundle"
fi

# ── 生成 Info.plist ──────────────────────────────────────────
# Info.plist 是 macOS 应用的核心配置文件，告诉系统如何运行和显示应用
# 类似于 Android 的 AndroidManifest.xml
cat > "$CONTENTS_DIR/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 应用的唯一标识符，类似于 Android 的 package name -->
    <key>CFBundleIdentifier</key>
    <string>com.github.skilldeck</string>

    <!-- 应用显示名称 -->
    <key>CFBundleName</key>
    <string>SkillDeck</string>

    <!-- 可执行文件名（对应 MacOS/ 目录下的文件名） -->
    <key>CFBundleExecutable</key>
    <string>SkillDeck</string>

    <!-- 用户可见的版本号（如 1.0.0） -->
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <!-- 内部构建版本号（这里与用户版本相同） -->
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <!-- 应用图标文件名（不含 .icns 扩展名） -->
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <!-- bundle 类型：APPL 表示这是一个应用 -->
    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <!-- Info.plist 格式版本 -->
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <!-- 最低支持的 macOS 版本 -->
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- 支持高分辨率 Retina 显示 -->
    <key>NSHighResolutionCapable</key>
    <true/>

    <!-- 应用类别：开发者工具 -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST_EOF

echo "    Generated Info.plist (version: ${VERSION})"

# ── 输出结果 ─────────────────────────────────────────────────
echo ""
echo "==> Done! App bundle created at: $APP_DIR"
echo "    Size: $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "To launch:"
echo "    open $APP_DIR"
echo ""
echo "To verify architecture:"
echo "    file $MACOS_DIR/SkillDeck"
