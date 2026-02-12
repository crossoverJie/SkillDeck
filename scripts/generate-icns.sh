#!/bin/bash
# generate-icns.sh — 将 SVG 图标转换为 macOS .icns 文件
#
# 依赖：
#   - swift (Xcode Command Line Tools)
#   - iconutil (macOS 内置)
#
# 用法：
#   ./scripts/generate-icns.sh
#
# 输出：
#   Sources/SkillDeck/Resources/AppIcon.icns

set -euo pipefail

# 获取项目根目录（脚本所在目录的上一级）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SVG_FILE="$PROJECT_ROOT/Assets/AppIcon.svg"
TMPDIR_ROOT="$(mktemp -d)"
ICONSET_DIR="$TMPDIR_ROOT/AppIcon.iconset"
OUTPUT_ICNS="$PROJECT_ROOT/Sources/SkillDeck/Resources/AppIcon.icns"

# 检查依赖
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

# 创建 .iconset 目录
mkdir -p "$ICONSET_DIR"

echo "Generating PNGs from $SVG_FILE ..."

# 使用 Swift + AppKit 的 NSImage 将 SVG 渲染为多尺寸 PNG
# NSImage 原生支持 SVG，无需额外依赖
SWIFT_SCRIPT="$TMPDIR_ROOT/svg2png.swift"
cat > "$SWIFT_SCRIPT" << 'SWIFT_EOF'
import AppKit
import Foundation

// 命令行参数: svg2png <svgPath> <outputDir>
let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: svg2png <svgPath> <outputDir>\n", stderr)
    exit(1)
}

let svgPath = args[1]
let outputDir = args[2]

// 加载 SVG 文件为 NSImage
guard let image = NSImage(contentsOfFile: svgPath) else {
    fputs("Error: Failed to load SVG from \(svgPath)\n", stderr)
    exit(1)
}

// macOS .icns 需要以下 10 个尺寸的 PNG：
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

    // 创建指定像素尺寸的位图上下文（RGBA, 8位/通道）
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

    // 设置 size 属性为像素尺寸（1:1 映射，避免 HiDPI 缩放问题）
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    // 在位图上下文中绘制 SVG
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fputs("Error: Failed to create graphics context for \(entry.label)\n", stderr)
        exit(1)
    }
    NSGraphicsContext.current = context

    // 清除背景为透明（SVG 中 clipPath 外的区域需要保持透明）
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

    // 绘制 SVG 图像到整个位图区域
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()

    // 导出为 PNG
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

# 编译 Swift 脚本（链接 AppKit 框架）
echo "Compiling SVG renderer ..."
SWIFT_BIN="$TMPDIR_ROOT/svg2png"
swiftc "$SWIFT_SCRIPT" -o "$SWIFT_BIN" -framework AppKit 2>&1

# 运行 SVG → PNG 转换
"$SWIFT_BIN" "$SVG_FILE" "$ICONSET_DIR"

echo ""
echo "Creating .icns with iconutil ..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

# 清理临时目录
rm -rf "$TMPDIR_ROOT"

echo ""
echo "Done! Output: $OUTPUT_ICNS"
echo "File size: $(du -h "$OUTPUT_ICNS" | cut -f1)"
