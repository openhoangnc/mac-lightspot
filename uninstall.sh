#!/bin/bash
set -euo pipefail
APP="$HOME/Applications/Lightspot.app"
if [ -d "$APP" ]; then
    rm -rf "$APP"
    echo "✅ Uninstalled Lightspot from ~/Applications"
else
    echo "⚠️  Lightspot not found in ~/Applications"
fi
