#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🛑 Terminating any running Lightspot instances..."
killall Lightspot 2>/dev/null || pkill -x Lightspot 2>/dev/null || true
sleep 0.2
if pgrep -x Lightspot >/dev/null 2>&1; then
    # Refused from some shells (e.g. sandboxed ones). The new build asks the running
    # one to quit when it launches; versions before that could not be asked.
    echo "⚠️ Could not stop Lightspot (pid $(pgrep -x Lightspot | tr '\n' ' ')); the new build will ask it to quit."
fi

"$SCRIPT_DIR/build.sh"

echo "🚀 Launching Lightspot..."
open "$SCRIPT_DIR/build/Lightspot.app"
