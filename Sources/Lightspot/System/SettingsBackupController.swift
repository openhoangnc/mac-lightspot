import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsBackupController {
    static let shared = SettingsBackupController()

    weak var hotkeyManager: HotkeyManager?
    weak var menuBarController: MenuBarController?
    weak var viewModel: SearchViewModel?

    private init() {}

    func createCurrentBackup() -> LightspotSettingsBackup {
        let hotkey = hotkeyManager?.currentOption.rawValue ?? (UserDefaults.standard.string(forKey: "lightspot_hotkey_option") ?? "commandSpace")
        let autoStart = AutoStartManager.isEnabled
        let hideIcon = menuBarController?.isMenuBarIconHidden ?? UserDefaults.standard.bool(forKey: "lightspot_hide_menubar_icon")

        let customCommands = CustomCommandsStore.shared.entries()
        let pinnedCommands = PinnedCommandsStore.shared.commands()
        let (historyEntries, historyStats) = SearchHistoryManager.shared.currentHistoryData()
        let recents = UserDefaults.standard.stringArray(forKey: "lightspot_recent_app_bundle_ids") ?? []

        return LightspotSettingsBackup(
            version: LightspotSettingsBackup.currentVersion,
            app: LightspotSettingsBackup.appIdentifier,
            exportedAt: Date(),
            preferences: LightspotPreferencesBackup(
                hotkeyOption: hotkey,
                autoStartEnabled: autoStart,
                hideMenuBarIcon: hideIcon
            ),
            customCommands: customCommands,
            pinnedCommands: pinnedCommands,
            searchHistory: SearchHistoryBackupData(entries: historyEntries, itemStats: historyStats),
            recentAppBundleIDs: recents
        )
    }

    func exportSettings(from window: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        let savePanel = NSSavePanel()
        savePanel.title = "Export Lightspot Settings"
        savePanel.prompt = "Export"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "Lightspot-Settings-\(dateString).json"

        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else { return }

        do {
            let backup = createCurrentBackup()
            let data = try backup.encode()
            try data.write(to: url, options: .atomic)

            showAlert(
                title: "Settings Exported",
                message: "Successfully exported settings to:\n\(url.lastPathComponent)\n\n• Custom commands: \(backup.customCommands.count)\n• Pinned commands: \(backup.pinnedCommands.count)\n• Hotkey: \(backup.preferences.hotkeyOption)\n• Launch at login: \(backup.preferences.autoStartEnabled ? "Enabled" : "Disabled")"
            )
        } catch {
            showAlert(
                title: "Export Failed",
                message: "Could not export settings:\n\(error.localizedDescription)",
                style: .critical
            )
        }
    }

    func importSettings(from window: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        let openPanel = NSOpenPanel()
        openPanel.title = "Import Lightspot Settings"
        openPanel.prompt = "Import"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        let response = openPanel.runModal()
        guard response == .OK, let url = openPanel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let backup = try LightspotSettingsBackup.decode(from: data)

            let hotkeyDisplay: String = {
                if let opt = HotkeyOption(rawValue: backup.preferences.hotkeyOption) {
                    return opt.displayName
                }
                return backup.preferences.hotkeyOption
            }()

            var summaryLines: [String] = [
                "• Custom Commands: \(backup.customCommands.count)",
                "• Pinned Commands: \(backup.pinnedCommands.count)",
                "• Hotkey: \(hotkeyDisplay)",
                "• Launch at Login: \(backup.preferences.autoStartEnabled ? "Enabled" : "Disabled")",
                "• Hide Menu Bar Icon: \(backup.preferences.hideMenuBarIcon ? "Yes" : "No")"
            ]
            if let history = backup.searchHistory {
                summaryLines.append("• Search History: \(history.entries.count) entries")
            }
            if let recents = backup.recentAppBundleIDs {
                summaryLines.append("• Recent Apps: \(recents.count) items")
            }

            let alert = NSAlert()
            alert.messageText = "Import Lightspot Settings?"
            alert.informativeText = """
            Importing will replace your current settings, custom commands, and pinned commands with the configuration from "\(url.lastPathComponent)".

            Backup Summary:
            \(summaryLines.joined(separator: "\n"))

            Do you want to proceed?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Import")
            alert.addButton(withTitle: "Cancel")
            alert.window.level = .floating
            alert.window.center()
            alert.window.orderFrontRegardless()

            let confirmResponse = alert.runModal()
            guard confirmResponse == .alertFirstButtonReturn else { return }

            apply(backup: backup)

            showAlert(
                title: "Settings Imported",
                message: "Successfully restored configuration from \(url.lastPathComponent)."
            )
        } catch {
            showAlert(
                title: "Import Failed",
                message: "Could not import settings:\n\(error.localizedDescription)",
                style: .critical
            )
        }
    }

    func apply(backup: LightspotSettingsBackup) {
        // 1. Custom Commands
        CustomCommandsStore.shared.reset(to: backup.customCommands)

        // 2. Pinned Commands
        PinnedCommandsStore.shared.reset(to: backup.pinnedCommands)

        // 3. Search History (if included)
        if let history = backup.searchHistory {
            SearchHistoryManager.shared.restore(entries: history.entries, stats: history.itemStats)
        }

        // 4. Recent Apps (if included)
        if let recents = backup.recentAppBundleIDs {
            RecentAppsManager.shared.restore(bundleIDs: recents)
        }

        // 5. Hotkey Option
        if let option = HotkeyOption(rawValue: backup.preferences.hotkeyOption) {
            hotkeyManager?.currentOption = option
        }

        // 6. Launch at Login
        _ = AutoStartManager.setEnabled(backup.preferences.autoStartEnabled)

        // 7. Menu Bar Icon Visibility
        menuBarController?.isMenuBarIconHidden = backup.preferences.hideMenuBarIcon

        // 8. Rebuild UI & View Model
        menuBarController?.rebuildMenu()
        viewModel?.reloadAfterSettingsImport()
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()
        alert.runModal()
    }
}
