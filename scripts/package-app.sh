#!/bin/bash
# package-app.sh — Build universal binary and assemble macOS .app bundle
#
# Features:
#   1. Compile arm64 + x86_64 universal binary using swift build
#   2. Create standard .app bundle directory structure
#   3. Generate Info.plist (including version metadata)
#   4. Copy icon and SPM resource bundle
#
# Usage:
#   ./scripts/package-app.sh                    # Default version 0.0.0-dev
#   ./scripts/package-app.sh --version 1.0.0    # Specify version
#
# Output:
#   build/SkillDeck.app

set -euo pipefail

# ── Parse Command Line Arguments ──────────────────────────────────────────
# Default version number, used for local development build
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

# ── Get Project Root Directory ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# ── Build Universal Binary (arm64 + x86_64) ─────────────────────────
# --arch parameter enables Swift to compile dual architecture, resulting binary supports both Intel and Apple Silicon Mac
echo "==> Building universal binary (arm64 + x86_64) ..."
swift build -c release --arch arm64 --arch x86_64

# ── Locate Build Artifact ─────────────────────────────────────────────
# Universal binary build output is in .build/apple/Products/Release/
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

# ── Locate SPM Resource Bundle ────────────────────────────────────
# SPM packages files declared in Package.swift resources as <Target>_<Target>.bundle
# Universal build path in .build/apple/Products/Release/, single arch in .build/release/
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

# ── Create .app Bundle Directory Structure ────────────────────────────────
# macOS .app bundle is a special directory structure displayed as a single app icon by Finder
# Standard structure:
#   SkillDeck.app/Contents/
#     Info.plist          ← App metadata (version, identifier, etc.)
#     MacOS/SkillDeck     ← Executable file
#     Resources/          ← Icon, resource files
APP_DIR="build/SkillDeck.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean up old build artifacts
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Assembling .app bundle ..."

# ── Copy Executable ───────────────────────────────────────────
cp "$BINARY_PATH" "$MACOS_DIR/SkillDeck"
chmod +x "$MACOS_DIR/SkillDeck"

# ── Copy App Icon ─────────────────────────────────────────────
ICON_SOURCE="Sources/SkillDeck/Resources/AppIcon.icns"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
    echo "    Copied AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found at $ICON_SOURCE"
fi

# ── Copy SPM Resource Bundle ────────────────────────────────────
# Bundle.module looks for resource bundle in sibling directory at runtime
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    echo "    Copied SPM resource bundle"
fi

# ── Generate Info.plist ──────────────────────────────────────────
# Info.plist is the core configuration file for macOS apps, telling system how to run and display the app
# Similar to AndroidManifest.xml for Android
cat > "$CONTENTS_DIR/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Unique Identifier, similar to Android package name -->
    <key>CFBundleIdentifier</key>
    <string>com.github.skilldeck</string>

    <!-- App Display Name -->
    <key>CFBundleName</key>
    <string>SkillDeck</string>

    <!-- Executable Filename (matches filename in MacOS/ directory) -->
    <key>CFBundleExecutable</key>
    <string>SkillDeck</string>

    <!-- User-visible Version Number (e.g. 1.0.0) -->
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <!-- Internal Build Version Number (here same as user version) -->
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <!-- App Icon Filename (without .icns extension) -->
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <!-- Bundle Type: APPL indicates this is an application -->
    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <!-- Info.plist Format Version -->
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <!-- Minimum Supported macOS Version -->
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- Support High Resolution Retina Display -->
    <key>NSHighResolutionCapable</key>
    <true/>

    <!-- App Category: Developer Tools -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST_EOF

echo "    Generated Info.plist (version: ${VERSION})"

# ── Output Results ─────────────────────────────────────────────────
echo ""
echo "==> Done! App bundle created at: $APP_DIR"
echo "    Size: $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "To launch:"
echo "    open $APP_DIR"
echo ""
echo "To verify architecture:"
echo "    file $MACOS_DIR/SkillDeck"
