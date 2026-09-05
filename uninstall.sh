#!/bin/bash
set -euo pipefail

APP_NAME="Lightspot"

# Check OS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: ${APP_NAME} is only supported on macOS."
    exit 1
fi

echo "=== Uninstalling ${APP_NAME} ==="

# 1. Unregister login item via App binary before termination/deletion
for TARGET_DIR in "$HOME/Applications" "/Applications"; do
    APP_PATH="${TARGET_DIR}/${APP_NAME}.app"
    if [ -x "${APP_PATH}/Contents/MacOS/${APP_NAME}" ]; then
        echo "--> Unregistering Open at Login item..."
        "${APP_PATH}/Contents/MacOS/${APP_NAME}" --cleanup-login-item 2>/dev/null || true
    fi
done

# 2. Terminate running instance gracefully then force
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "--> Stopping running ${APP_NAME} process..."
    killall "${APP_NAME}" 2>/dev/null || pkill -x "${APP_NAME}" 2>/dev/null || true
    for _ in {1..30}; do
        if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        echo "⚠️ Forcing termination of lingering ${APP_NAME} process..."
        killall -9 "${APP_NAME}" 2>/dev/null || pkill -9 -x "${APP_NAME}" 2>/dev/null || true
        sleep 0.2
    fi
fi

# 3. Remove App bundle
FOUND=0
for TARGET_DIR in "$HOME/Applications" "/Applications"; do
    APP_PATH="${TARGET_DIR}/${APP_NAME}.app"
    if [ -d "${APP_PATH}" ]; then
        echo "--> Removing ${APP_PATH}..."
        rm -rf "${APP_PATH}"
        FOUND=1
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "⚠️  ${APP_NAME} not found in /Applications or ~/Applications"
fi

# 4. Remove Preferences
echo "--> Clearing application preferences..."
defaults delete com.lightspot.app 2>/dev/null || true
rm -f "${HOME}/Library/Preferences/com.lightspot.app.plist"

echo "=== Uninstallation Complete! ${APP_NAME} has been completely removed. ==="
