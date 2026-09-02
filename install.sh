#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_APP="$SCRIPT_DIR/build/Lightspot.app"

# Target resolution
TARGET_DIR="/Applications"
if [ "${1:-}" = "--user" ]; then
    TARGET_DIR="$HOME/Applications"
elif [ "${1:-}" = "--system" ]; then
    TARGET_DIR="/Applications"
else
    # Auto-detect: prefer /Applications if writable, else ~/Applications
    if [ ! -w "/Applications" ]; then
        TARGET_DIR="$HOME/Applications"
    fi
fi

DEST_APP="$TARGET_DIR/Lightspot.app"

echo "=========================================="
echo "  Lightspot Installer"
echo "=========================================="
echo "Target directory: $TARGET_DIR"

# 1. Build release bundle
echo "🔨 Building release binary..."
"$SCRIPT_DIR/build.sh"

if [ ! -d "$BUILD_APP" ]; then
    echo "❌ Build failed: $BUILD_APP not found"
    exit 1
fi

# 2. Stop running instance
echo "🛑 Stopping existing Lightspot process..."
killall Lightspot 2>/dev/null || true
sleep 0.5

# 3. Create destination directory
mkdir -p "$TARGET_DIR"

# 4. Copy app bundle
echo "📦 Installing to $DEST_APP..."
rm -rf "$DEST_APP"
cp -R "$BUILD_APP" "$DEST_APP"

# 5. Clear quarantine and codesign
echo "🔏 Setting permissions and codesigning..."
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
codesign --force --deep --sign - "$DEST_APP" 2>/dev/null || true

# 6. Launch installed application
echo "🚀 Launching Lightspot..."
open "$DEST_APP"

echo "=========================================="
echo "✅ Installation complete!"
echo "📍 Location: $DEST_APP"
echo "⌨️ Hotkey: ⌘Space (Command + Space)"
echo "=========================================="
