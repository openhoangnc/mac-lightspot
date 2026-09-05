#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/Lightspot.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "🔨 Building Lightspot..."

ARCH_FLAGS=${ARCH_FLAGS:-}

# Build with SPM (Maximum Optimization)
echo "🚀 Compiling with maximum optimizations..."
swift build -c release $ARCH_FLAGS \
    -Xswiftc -Osize \
    -Xswiftc -whole-module-optimization \
    -Xswiftc -cross-module-optimization \
    -Xswiftc -enforce-exclusivity=unchecked \
    --package-path "$SCRIPT_DIR" 2>&1

# Find the built binary
BINARY=$(swift build -c release $ARCH_FLAGS --package-path "$SCRIPT_DIR" --show-bin-path)/Lightspot


if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed: binary not found"
    exit 1
fi

echo "📦 Creating app bundle..."

# Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy binary
cp "$BINARY" "$CONTENTS/MacOS/Lightspot"

# Strip binary to minimize size
echo "🔪 Stripping debug symbols..."
strip -S "$CONTENTS/MacOS/Lightspot"

# Copy Info.plist
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon if it exists
if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# Write PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Ad-hoc codesign
echo "🔏 Signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Build complete: $APP_BUNDLE"
