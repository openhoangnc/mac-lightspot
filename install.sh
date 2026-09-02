#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/build.sh"
DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Lightspot.app"
cp -R "$SCRIPT_DIR/build/Lightspot.app" "$DEST/Lightspot.app"
echo "✅ Installed to $DEST/Lightspot.app"
