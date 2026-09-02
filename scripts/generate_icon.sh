#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ICON_DIR="$PROJECT_DIR/Resources"
TEMP_DIR=$(mktemp -d)
ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"

mkdir -p "$ICONSET_DIR"
mkdir -p "$ICON_DIR"

echo "🎨 Generating Lightspot icon..."

# Generate 1024x1024 icon using Swift + Core Graphics
swift - << 'SWIFT_SCRIPT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("Failed to get graphics context")
    exit(1)
}

// Background: rounded rect with gradient
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = size * 0.22 // macOS icon corner ratio
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Gradient: blue to purple
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0),
    CGColor(red: 0.5, green: 0.2, blue: 0.9, alpha: 1.0)
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
ctx.restoreGState()

// Draw magnifying glass
let centerX = size * 0.42
let centerY = size * 0.58
let lensRadius: CGFloat = size * 0.22
let handleLength: CGFloat = size * 0.2
let lineWidth: CGFloat = size * 0.055

ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)

// Lens circle
ctx.addArc(center: CGPoint(x: centerX, y: centerY), radius: lensRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// Glass fill (subtle inner glow)
ctx.saveGState()
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
ctx.addArc(center: CGPoint(x: centerX, y: centerY), radius: lensRadius - lineWidth / 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.fillPath()
ctx.restoreGState()

// Handle
let handleAngle: CGFloat = -.pi / 4 // 45 degrees down-right
let handleStartX = centerX + (lensRadius + lineWidth * 0.3) * cos(handleAngle)
let handleStartY = centerY + (lensRadius + lineWidth * 0.3) * sin(handleAngle)
let handleEndX = handleStartX + handleLength * cos(handleAngle)
let handleEndY = handleStartY + handleLength * sin(handleAngle)

ctx.move(to: CGPoint(x: handleStartX, y: handleStartY))
ctx.addLine(to: CGPoint(x: handleEndX, y: handleEndY))
ctx.setLineWidth(lineWidth * 1.1)
ctx.strokePath()

// Small light sparkle on the lens
ctx.saveGState()
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
let sparkleSize: CGFloat = lensRadius * 0.2
ctx.addArc(center: CGPoint(x: centerX - lensRadius * 0.35, y: centerY + lensRadius * 0.35),
           radius: sparkleSize, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.fillPath()
ctx.restoreGState()

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/lightspot_icon_1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("✅ Generated icon at \(outputPath)")
SWIFT_SCRIPT

BASE_PNG="/tmp/lightspot_icon_1024.png"

# Generate all required sizes
declare -a SIZES=("16" "32" "64" "128" "256" "512")

for s in "${SIZES[@]}"; do
    sips -z "$s" "$s" "$BASE_PNG" --out "$ICONSET_DIR/icon_${s}x${s}.png" > /dev/null 2>&1
done

# @2x variants
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_64x64@2x.png" > /dev/null 2>&1
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

# Build .icns
iconutil -c icns "$ICONSET_DIR" -o "$ICON_DIR/AppIcon.icns"

# Clean up
rm -rf "$TEMP_DIR" "$BASE_PNG"

echo "✅ Icon generated: $ICON_DIR/AppIcon.icns"
