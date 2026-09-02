#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/build.sh"
echo "🚀 Launching Lightspot..."
open "$SCRIPT_DIR/build/Lightspot.app"
