#!/bin/bash
set -euo pipefail
echo "🛑 Stopping running Lightspot process..."
killall -9 Lightspot 2>/dev/null || pkill -9 -x Lightspot 2>/dev/null || true
sleep 0.2

FOUND=0
for TARGET_DIR in "$HOME/Applications" "/Applications"; do
    APP="$TARGET_DIR/Lightspot.app"
    if [ -d "$APP" ]; then
        rm -rf "$APP"
        echo "✅ Uninstalled Lightspot from $TARGET_DIR"
        FOUND=1
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "⚠️  Lightspot not found in /Applications or ~/Applications"
fi
