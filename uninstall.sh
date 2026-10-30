#!/bin/bash
set -euo pipefail

APP_NAME="Lightspot"

# Check OS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: ${APP_NAME} is only supported on macOS."
    exit 1
fi

# Parse flags (when piped: curl ... | bash -s -- --dry-run)
DRY_RUN=0
RESTORE_SPOTLIGHT=1
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        --keep-spotlight-disabled)
            RESTORE_SPOTLIGHT=0
            ;;
    esac
done

# Runs a command, or only prints it with --dry-run.
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

# Same, discarding the command's output and ignoring its failure.
run_quiet() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] $*"
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

# True when a person can answer a prompt. Under `curl ... | bash` stdin is the
# script itself, so prompts read from the terminal instead.
can_prompt() {
    [ -t 1 ] && { : </dev/tty; } 2>/dev/null
}

if [ "$DRY_RUN" -eq 1 ]; then
    echo "=== Uninstalling ${APP_NAME} (dry run: nothing will be changed) ==="
else
    echo "=== Uninstalling ${APP_NAME} ==="
fi

# 1. Unregister login item via App binary before termination/deletion
for TARGET_DIR in "$HOME/Applications" "/Applications"; do
    APP_PATH="${TARGET_DIR}/${APP_NAME}.app"
    if [ -x "${APP_PATH}/Contents/MacOS/${APP_NAME}" ]; then
        echo "--> Unregistering Open at Login item..."
        run_quiet "${APP_PATH}/Contents/MacOS/${APP_NAME}" --cleanup-login-item
    fi
done

# 2. Terminate running instance gracefully then force. This user's copies only: another
# account on this Mac runs its own Lightspot, which this user may not signal.
own_pids() {
    pgrep -u "$(id -u)" -x "${APP_NAME}"
}
running_pids() {
    own_pids | tr '\n' ' ' | sed 's/ $//'
}
if own_pids >/dev/null 2>&1; then
    echo "--> Stopping running ${APP_NAME} process..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] pkill -u $(id -u) -x ${APP_NAME} (pid $(running_pids))"
    else
        pkill -u "$(id -u)" -x "${APP_NAME}" 2>/dev/null || true
        for _ in {1..30}; do
            if ! own_pids >/dev/null 2>&1; then
                break
            fi
            sleep 0.1
        done
        if own_pids >/dev/null 2>&1; then
            echo "⚠️ Forcing termination of lingering ${APP_NAME} process..."
            pkill -9 -u "$(id -u)" -x "${APP_NAME}" 2>/dev/null || true
            sleep 0.2
        fi
        if own_pids >/dev/null 2>&1; then
            echo "⚠️ Could not stop ${APP_NAME} (pid $(running_pids)): not permitted from this shell."
            echo "   Quit it from its menu bar icon (Quit Lightspot) once this script finishes."
        fi
    fi
fi

# 3. Remove App bundle
FOUND=0
for TARGET_DIR in "$HOME/Applications" "/Applications"; do
    APP_PATH="${TARGET_DIR}/${APP_NAME}.app"
    if [ -d "${APP_PATH}" ]; then
        echo "--> Removing ${APP_PATH}..."
        run rm -rf "${APP_PATH}"
        FOUND=1
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "⚠️  ${APP_NAME} not found in /Applications or ~/Applications"
fi

# 4. Remove Preferences, the single-instance lock directory, and the HTTP cache,
#    HTTP storage and cookie jar that versions up to 1.2.0 left behind (their update
#    check used URLSession.shared, which writes all three; see LegacyNetworkStores).
#    Mac Tweaks' undo journal and Dock backup stay: they are the only record of what
#    Lightspot changed, and reinstalling Lightspot can still undo it from them. So do
#    the journals it couldn't read and kept aside, which a person can still read.
echo "--> Clearing application preferences..."
run_quiet defaults delete com.lightspot.app
run rm -f "${HOME}/Library/Preferences/com.lightspot.app.plist"
SUPPORT_DIR="${HOME}/Library/Application Support/${APP_NAME}"
TWEAKS_JOURNAL="${SUPPORT_DIR}/tweaks-journal.json"
DOCK_BACKUP="${SUPPORT_DIR}/dock-backup.plist"
UNREADABLE_JOURNALS=0
for ITEM in "${SUPPORT_DIR}"/tweaks-journal-unreadable-*.json; do
    if [ -f "${ITEM}" ]; then
        UNREADABLE_JOURNALS=1
    fi
done
if [ -f "${TWEAKS_JOURNAL}" ] || [ -f "${DOCK_BACKUP}" ] || [ "${UNREADABLE_JOURNALS}" -eq 1 ]; then
    for ITEM in "${SUPPORT_DIR}"/* "${SUPPORT_DIR}"/.[!.]*; do
        [ -e "${ITEM}" ] || continue
        case "$(basename "${ITEM}")" in
            tweaks-journal.json|tweaks-journal-unreadable-*.json|dock-backup.plist) continue ;;
        esac
        run rm -rf "${ITEM}"
    done
else
    run rm -rf "${SUPPORT_DIR}"
fi
for LEFTOVER in "${HOME}/Library/Caches/com.lightspot.app" "${HOME}/Library/HTTPStorages/com.lightspot.app" \
                "${HOME}/Library/HTTPStorages/com.lightspot.app.binarycookies"; do
    if [ -e "${LEFTOVER}" ]; then
        run rm -rf "${LEFTOVER}"
    fi
done

# 5. Restore Apple Spotlight. Lightspot's "Disable Everything" (offered at first
#    launch) turns off the Spotlight shortcut, the Spotlight agent and indexing;
#    with Lightspot gone that would leave the Mac without a launcher.

# Spotlight shortcuts: symbolic hotkeys 64 ("Show Spotlight search", ⌘Space by
# default) and 65 ("Show Finder search window", ⌥⌘Space). Lightspot turns off both
# (SpotlightManager.spotlightHotkeyIDs). Only `enabled` is flipped, keeping the key
# each one had. Read and written through `defaults` (cfprefsd), which would
# otherwise keep serving a cached copy of a file edited underneath it.
restore_spotlight_shortcut() {
    local domain="com.apple.symbolichotkeys"
    local exported
    exported="$(mktemp -t lightspot-hotkeys)"
    if ! defaults export "$domain" "$exported" 2>/dev/null; then
        rm -f "$exported"
        return 0
    fi

    local buddy="/usr/libexec/PlistBuddy"
    local id key type params i value restored=0
    for id in 64 65; do
        key=":AppleSymbolicHotKeys:${id}"
        # A CFBoolean prints as false; `defaults write -int 0` leaves a 0.
        case "$("$buddy" -c "Print ${key}:enabled" "$exported" 2>/dev/null)" in
            false|0) ;;
            *) continue ;;
        esac

        type="$("$buddy" -c "Print ${key}:value:type" "$exported" 2>/dev/null || echo standard)"
        params=""
        for i in 0 1 2; do
            value="$("$buddy" -c "Print ${key}:value:parameters:${i}" "$exported" 2>/dev/null)" || break
            params="${params}<integer>${value}</integer>"
        done
        if [ -z "$params" ]; then
            if [ "$id" -eq 65 ]; then
                params="<integer>32</integer><integer>49</integer><integer>1572864</integer>" # ⌥⌘Space
            else
                params="<integer>32</integer><integer>49</integer><integer>1048576</integer>" # ⌘Space
            fi
        fi

        if [ "$restored" -eq 0 ]; then
            echo "--> Re-enabling the Spotlight keyboard shortcuts..."
        fi
        run defaults write "$domain" AppleSymbolicHotKeys -dict-add "$id" \
            "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array>${params}</array><key>type</key><string>${type}</string></dict></dict>"
        restored=1
    done
    rm -f "$exported"
    if [ "$restored" -eq 0 ]; then
        return 0
    fi

    # Apply now instead of at next login.
    local activate="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
    if [ -x "$activate" ]; then
        run_quiet "$activate" -u
    else
        echo "    The shortcut takes effect after you log out and back in."
    fi
}

# Spotlight agent: `launchctl disable gui/<uid>/com.apple.Spotlight`.
restore_spotlight_agent() {
    local uid disabled
    uid="$(id -u)"
    # Captured first: `| grep -q` under pipefail can fail on SIGPIPE even on a match.
    disabled="$(launchctl print-disabled "gui/${uid}" 2>/dev/null || true)"
    if ! grep -Eq '"com\.apple\.Spotlight" => (disabled|true)' <<<"$disabled"; then
        return 0
    fi

    echo "--> Re-enabling the Spotlight agent (com.apple.Spotlight)..."
    run launchctl enable "gui/${uid}/com.apple.Spotlight"
    # Start it now: load it if it was left out at login, then make sure it runs.
    run_quiet launchctl bootstrap "gui/${uid}" /System/Library/LaunchAgents/com.apple.Spotlight.plist
    run_quiet launchctl kickstart "gui/${uid}/com.apple.Spotlight"
}

# Spotlight indexing: `mdutil -a -i off`. Switching it back on is a system-wide
# setting, so it needs an administrator password; ask before using sudo.
restore_spotlight_indexing() {
    if ! mdutil -s / 2>/dev/null | grep -q "Indexing disabled"; then
        return 0
    fi

    local command="sudo mdutil -a -i on"
    echo "--> Spotlight indexing is turned off."
    echo "    Turning it back on changes a system-wide setting, so macOS asks for an"
    echo "    administrator password (sudo). Spotlight then rebuilds its index in the"
    echo "    background, which can take a while."

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] would ask, then run: ${command}"
        return 0
    fi

    local answer=""
    if can_prompt; then
        read -r -p "    Re-enable Spotlight indexing now? [Y/n] " answer </dev/tty || answer="n"
        case "$answer" in
            ""|y|Y|yes|YES|Yes)
                if sudo mdutil -a -i on </dev/tty; then
                    echo "    Spotlight indexing re-enabled."
                    return 0
                fi
                echo "⚠️ Could not re-enable indexing."
                ;;
        esac
    fi
    echo "    To re-enable it later, run:"
    echo "      ${command}"
}

# 6. Say what Mac Tweaks changed and leaves as it is. Nothing is reverted here: undoing
#    a setting means knowing its earlier value, which only Lightspot reads.
TWEAKS_PROFILE=0
for MANAGED in "/Library/Managed Preferences/com.lightspot.app.tweaks.plist" \
               "/Library/Managed Preferences/$(id -un)/com.lightspot.app.tweaks.plist"; do
    if [ -f "${MANAGED}" ]; then
        TWEAKS_PROFILE=1
    fi
done
TWEAKS_LEFT=0
if [ -f "${TWEAKS_JOURNAL}" ] || [ -f "${DOCK_BACKUP}" ] || [ "${UNREADABLE_JOURNALS}" -eq 1 ] || [ "${TWEAKS_PROFILE}" -eq 1 ]; then
    TWEAKS_LEFT=1
fi
mac_tweaks_notice() {
    if [ "${TWEAKS_LEFT}" -eq 0 ]; then
        return 0
    fi
    echo "--> Mac Tweaks' changes stay on this Mac:"
    if [ -f "${TWEAKS_JOURNAL}" ]; then
        echo "    - settings Lightspot changed; their earlier values are kept in"
        echo "      ~/Library/Application Support/${APP_NAME}/tweaks-journal.json"
    fi
    if [ "${UNREADABLE_JOURNALS}" -eq 1 ]; then
        echo "    - undo journals Lightspot couldn't read, kept aside as"
        echo "      ~/Library/Application Support/${APP_NAME}/tweaks-journal-unreadable-*.json"
    fi
    if [ "${TWEAKS_PROFILE}" -eq 1 ]; then
        echo "    - the configuration profile \"Lightspot Mac Tweaks\", for every account on this Mac"
    fi
    if [ -f "${DOCK_BACKUP}" ]; then
        echo "    - the Dock icons Clear Dock Icons removed, kept in"
        echo "      ~/Library/Application Support/${APP_NAME}/dock-backup.plist"
    fi
    if [ -f "${TWEAKS_JOURNAL}" ] && [ "${TWEAKS_PROFILE}" -eq 1 ]; then
        echo "    To undo the settings, reinstall ${APP_NAME} and choose \"Undo everything Lightspot changed\" in"
        echo "    Mac Tweaks > Settings, or remove \"Lightspot Mac Tweaks\" in System Settings > General >"
        echo "    Device Management for the locked ones."
    elif [ -f "${TWEAKS_JOURNAL}" ]; then
        echo "    To undo the settings, reinstall ${APP_NAME} and choose \"Undo everything Lightspot changed\" in"
        echo "    Mac Tweaks > Settings."
    elif [ "${TWEAKS_PROFILE}" -eq 1 ]; then
        echo "    To undo the settings, remove \"Lightspot Mac Tweaks\" in System Settings > General >"
        echo "    Device Management, or reinstall ${APP_NAME} and choose \"Undo everything Lightspot changed\"."
    fi
    if [ -f "${DOCK_BACKUP}" ]; then
        echo "    To put the Dock icons back, reinstall ${APP_NAME} and choose Restore Dock Icons."
    fi
}
mac_tweaks_notice

if [ "$RESTORE_SPOTLIGHT" -eq 1 ]; then
    restore_spotlight_shortcut
    restore_spotlight_agent
    restore_spotlight_indexing
else
    echo "--> Leaving Apple Spotlight settings as they are (--keep-spotlight-disabled)."
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "=== Dry run complete. Nothing was changed. ==="
else
    if [ "${TWEAKS_LEFT}" -eq 1 ]; then
        echo "=== Uninstallation Complete! ${APP_NAME} is removed; what Mac Tweaks changed stays (see above). ==="
    else
        echo "=== Uninstallation Complete! ${APP_NAME} has been completely removed. ==="
    fi
fi
