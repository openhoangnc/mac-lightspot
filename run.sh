#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🛑 Terminating any running Lightspot instances..."
killall Lightspot 2>/dev/null || pkill -x Lightspot 2>/dev/null || true
sleep 0.2

"$SCRIPT_DIR/build.sh"

echo "🚀 Launching Lightspot..."
open "$SCRIPT_DIR/build/Lightspot.app"
