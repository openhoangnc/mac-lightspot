#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# This user's copies only: another account on this Mac runs its own Lightspot, which
# this user may not signal.
echo "🛑 Terminating any running Lightspot instances..."
pkill -u "$(id -u)" -x Lightspot 2>/dev/null || true
sleep 0.2
if pgrep -u "$(id -u)" -x Lightspot >/dev/null 2>&1; then
    # Refused from some shells (e.g. sandboxed ones). The new build asks the running
    # one to quit when it launches; versions before that could not be asked.
    echo "⚠️ Could not stop Lightspot (pid $(pgrep -u "$(id -u)" -x Lightspot | tr '\n' ' ')); the new build will ask it to quit."
fi

"$SCRIPT_DIR/build.sh"

echo "🚀 Launching Lightspot..."
open "$SCRIPT_DIR/build/Lightspot.app"
