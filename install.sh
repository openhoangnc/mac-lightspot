#!/bin/bash
set -euo pipefail

REPO="openhoangnc/mac-lightspot"
APP_NAME="Lightspot"

# Check OS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: ${APP_NAME} is only supported on macOS."
    exit 1
fi

# Parse flags
TARGET_DIR=""
for arg in "$@"; do
    case "$arg" in
        --user)
            TARGET_DIR="$HOME/Applications"
            ;;
        --system)
            TARGET_DIR="/Applications"
            ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    # Auto-detect: prefer /Applications if writable, else ~/Applications
    if [ -w "/Applications" ]; then
        TARGET_DIR="/Applications"
    else
        TARGET_DIR="$HOME/Applications"
    fi
fi

DEST_APP="$TARGET_DIR/${APP_NAME}.app"

echo "=========================================="
echo "  ${APP_NAME} Installer"
echo "=========================================="
echo "Target directory: $TARGET_DIR"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Detect whether running from a local checkout or piped (curl ... | bash)
SOURCE_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

APP_SRC=""

if [ -n "${SOURCE_DIR}" ] && [ -f "${SOURCE_DIR}/build.sh" ]; then
    # Local checkout: build from source
    echo "[1/3] Local source detected — building ${APP_NAME} from source..."
    ( cd "${SOURCE_DIR}" && ./build.sh )
    APP_SRC="${SOURCE_DIR}/build/${APP_NAME}.app"
    if [ ! -d "${APP_SRC}" ]; then
        echo "❌ Build failed: ${APP_SRC} not found"
        exit 1
    fi
else
    # Remote install: download prebuilt release from GitHub
    echo "[1/3] Downloading latest release of ${APP_NAME}..."
    LATEST_ZIP_URL="https://github.com/${REPO}/releases/latest/download/${APP_NAME}.zip"
    if curl -fsSL -o "${TMP_DIR}/${APP_NAME}.zip" "${LATEST_ZIP_URL}"; then
        echo "--> Downloaded ${APP_NAME}.zip from GitHub Release."
        unzip -q "${TMP_DIR}/${APP_NAME}.zip" -d "${TMP_DIR}"
        APP_SRC="${TMP_DIR}/${APP_NAME}.app"
    fi
    if [ ! -d "${APP_SRC}" ]; then
        echo "❌ Error: Could not download ${APP_NAME}. Ensure a GitHub release exists, or run this script from a local checkout to build from source."
        exit 1
    fi
fi

echo "[2/3] Installing to ${DEST_APP}..."

# Stop running instance robustly before copying. This user's copies only: another
# account on this Mac runs its own Lightspot, which this user may not signal, and the
# wait and force-kill below used to spend themselves on it and then report a failure.
own_pids() {
    pgrep -u "$(id -u)" -x "${APP_NAME}"
}
echo "🛑 Stopping existing ${APP_NAME} process..."
if own_pids >/dev/null 2>&1; then
    pkill -u "$(id -u)" -x "${APP_NAME}" 2>/dev/null || true
    # Wait up to 3 seconds for graceful shutdown
    for _ in {1..30}; do
        if ! own_pids >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    # Force kill if still lingering
    if own_pids >/dev/null 2>&1; then
        echo "⚠️ Forcing termination of lingering ${APP_NAME} process..."
        pkill -9 -u "$(id -u)" -x "${APP_NAME}" 2>/dev/null || true
        sleep 0.2
    fi
    # Signals are refused from some shells (e.g. sandboxed ones). The new copy asks the
    # running one to quit when it launches; versions before that could not be asked.
    if own_pids >/dev/null 2>&1; then
        echo "⚠️ Could not stop ${APP_NAME} (pid $(own_pids | tr '\n' ' ')): not permitted from this shell."
        echo "   The new copy will ask it to quit. If two keep running, quit the old one from its menu bar icon."
    fi
fi

# Create destination directory
mkdir -p "$TARGET_DIR"

# Copy app bundle
rm -rf "$DEST_APP"
cp -R "$APP_SRC" "$DEST_APP"

# Clear quarantine and codesign
echo "🔏 Setting permissions and codesigning..."
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
codesign --force --deep --sign - "$DEST_APP" 2>/dev/null || true

# Launch installed application
echo "[3/3] Launching ${APP_NAME}..."
open "$DEST_APP"

echo "=========================================="
echo "✅ Installation complete!"
echo "📍 Location: $DEST_APP"
echo "⌨️ Hotkey: ⌘Space (Command + Space)"
echo ""
echo "To uninstall at any time, run:"
echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/uninstall.sh | bash"
echo "=========================================="
