#!/bin/bash
# generate-icns.sh — Convert SVG icon to macOS .icns file
#
# Dependencies:
#   - swift (Xcode Command Line Tools)
#   - iconutil (macOS builtin)
#
# Usage:
#   ./scripts/generate-icns.sh
#
# Output:
#   Sources/SkillDeck/Resources/AppIcon.icns

set -euo pipefail

# Get project root directory (parent directory of script location)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SVG_FILE="$PROJECT_ROOT/Assets/AppIcon.svg"
TMPDIR_ROOT="$(mktemp -d)"
ICONSET_DIR="$TMPDIR_ROOT/AppIcon.iconset"
OUTPUT_ICNS="$PROJECT_ROOT/Sources/SkillDeck/Resources/AppIcon.icns"

# Check dependencies
if ! command -v swift &>/dev/null; then
    echo "Error: swift not found. Install Xcode Command Line Tools."
    exit 1
fi

if ! command -v iconutil &>/dev/null; then
    echo "Error: iconutil not found. This script requires macOS."
    exit 1
fi

if [ ! -f "$SVG_FILE" ]; then
    echo "Error: SVG file not found at $SVG_FILE"
    exit 1
fi

# Create .iconset directory
mkdir -p "$ICONSET_DIR"

echo "Generating PNGs from $SVG_FILE ..."

# Use Swift + AppKit NSImage to render SVG to multi-size PNGs
# NSImage natively supports SVG, no extra dependencies needed
SWIFT_SCRIPT="$TMPDIR_ROOT/svg2png.swift"
cat > "$SWIFT_SCRIPT" << 'SWIFT_EOF'
import AppKit
import Foundation

// Command line arguments: svg2png <svgPath> <outputDir>
let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: svg2png <svgPath> <outputDir>\n", stderr)
    exit(1)
}

let svgPath = args[1]
let outputDir = args[2]

// Load SVG file as NSImage
guard let image = NSImage(contentsOfFile: svgPath) else {
    fputs("Error: Failed to load SVG from \(svgPath)\n", stderr)
    exit(1)
}

// macOS .icns requires the following 10 PNG sizes:
// icon_16x16.png (16), icon_16x16@2x.png (32),
// icon_32x32.png (32), icon_32x32@2x.png (64),
// icon_128x128.png (128), icon_128x128@2x.png (256),
// icon_256x256.png (256), icon_256x256@2x.png (512),
// icon_512x512.png (512), icon_512x512@2x.png (1024)
let sizes: [(label: String, pixels: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let pixelSize = entry.pixels

    // Create bitmap context of specified pixel size (RGBA, 8 bits/channel)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Error: Failed to create bitmap for \(entry.label)\n", stderr)
        exit(1)
    }

    // Set size property to pixel size (1:1 mapping, avoiding HiDPI scaling issues)
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    // Draw SVG in bitmap context
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fputs("Error: Failed to create graphics context for \(entry.label)\n", stderr)
        exit(1)
    }
    NSGraphicsContext.current = context

    // Clear background to transparent (areas outside clipPath in SVG need to remain transparent)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

    // Draw SVG image to entire bitmap area
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()

    // Export as PNG
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Error: Failed to create PNG data for \(entry.label)\n", stderr)
        exit(1)
    }

    let outputPath = "\(outputDir)/\(entry.label).png"
    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("  \(entry.label).png (\(pixelSize)x\(pixelSize))")
    } catch {
        fputs("Error: Failed to write \(outputPath): \(error)\n", stderr)
        exit(1)
    }
}

print("All PNGs generated successfully.")
SWIFT_EOF

# Compile Swift script (linking AppKit framework)
echo "Compiling SVG renderer ..."
SWIFT_BIN="$TMPDIR_ROOT/svg2png"
swiftc "$SWIFT_SCRIPT" -o "$SWIFT_BIN" -framework AppKit 2>&1

# Run SVG -> PNG conversion
"$SWIFT_BIN" "$SVG_FILE" "$ICONSET_DIR"

echo ""
echo "Creating .icns with iconutil ..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

# Clean up temp directory
rm -rf "$TMPDIR_ROOT"

echo ""
echo "Done! Output: $OUTPUT_ICNS"
echo "File size: $(du -h "$OUTPUT_ICNS" | cut -f1)"
