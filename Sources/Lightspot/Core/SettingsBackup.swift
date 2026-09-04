import Foundation

// MARK: - Path Sanitizer

public enum PathSanitizer {
    /// Replaces occurrences of the user's home directory (/Users/username) with ~ or ${USER}
    public static func sanitizeForExport(_ string: String) -> String {
        let home = NSHomeDirectory()
        let username = NSUserName()
        var result = string

        if !home.isEmpty && result.contains(home) {
            result = result.replacingOccurrences(of: home, with: "~")
        }

        let userDir = "/Users/\(username)"
        if !username.isEmpty && result.contains(userDir) {
            result = result.replacingOccurrences(of: userDir, with: "~")
        }

        return result
    }

    /// Restores ~ or ${USER} to current user's paths when importing
    public static func expandForImport(_ string: String) -> String {
        var result = string
        let home = NSHomeDirectory()
        let username = NSUserName()

        if result.contains("${USER}") {
            result = result.replacingOccurrences(of: "${USER}", with: username)
        }
        if result.contains("$USER") {
            result = result.replacingOccurrences(of: "$USER", with: username)
        }
        if result == "~" {
            return home
        }
        if result.hasPrefix("~/") {
            result = home + String(result.dropFirst(1))
        } else if result.contains("~/") {
            result = result.replacingOccurrences(of: "~/", with: "\(home)/")
        }
        return result
    }
}

// MARK: - SearchAction Sanitization Extension

extension SearchAction {
    func sanitizedForExport() -> SearchAction {
        switch self {
        case .launchApp(let path):
            return .launchApp(path: PathSanitizer.sanitizeForExport(path))
        case .openFolder(let path):
            return .openFolder(path: PathSanitizer.sanitizeForExport(path))
        case .openProject(let path, let bundleID):
            return .openProject(path: PathSanitizer.sanitizeForExport(path), appBundleID: bundleID)
        case .runInTerminal(let command):
            return .runInTerminal(command: PathSanitizer.sanitizeForExport(command))
        case .runQuickAction(let script, let usesOsascript):
            return .runQuickAction(script: PathSanitizer.sanitizeForExport(script), usesOsascript: usesOsascript)
        default:
            return self
        }
    }
}

// MARK: - Settings Backup Models

struct LightspotSettingsBackup: Codable, Sendable, Equatable {
    static let currentVersion: Int = 1
    static let appIdentifier: String = "com.lightspot.app"

    var version: Int
    var app: String
    var exportedAt: Date

    // General preferences
    var preferences: LightspotPreferencesBackup

    // Custom commands configured by user
    var customCommands: [CustomCommand]

    // Pinned shell commands (ordered)
    var pinnedCommands: [String]

    // Search history and item ranking (optional)
    var searchHistory: SearchHistoryBackupData?

    // Recent app bundle IDs (optional)
    var recentAppBundleIDs: [String]?

    init(
        version: Int = currentVersion,
        app: String = appIdentifier,
        exportedAt: Date = Date(),
        preferences: LightspotPreferencesBackup,
        customCommands: [CustomCommand],
        pinnedCommands: [String],
        searchHistory: SearchHistoryBackupData? = nil,
        recentAppBundleIDs: [String]? = nil
    ) {
        self.version = version
        self.app = app
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.customCommands = customCommands
        self.pinnedCommands = pinnedCommands
        self.searchHistory = searchHistory
        self.recentAppBundleIDs = recentAppBundleIDs
    }

    /// Creates a sanitized copy where home directories are replaced with ~ or ${USER}
    func sanitizedForExport() -> LightspotSettingsBackup {
        let sanitizedCommands = customCommands.map { cmd in
            var c = cmd
            c.target = PathSanitizer.sanitizeForExport(c.target)
            return c
        }

        let sanitizedPinned = pinnedCommands.map {
            PathSanitizer.sanitizeForExport($0)
        }

        var sanitizedHistory = searchHistory
        if let history = sanitizedHistory {
            let entries = history.entries.map { entry in
                SearchHistoryEntry(
                    id: entry.id,
                    itemId: entry.itemId,
                    query: entry.query,
                    title: PathSanitizer.sanitizeForExport(entry.title),
                    subtitle: PathSanitizer.sanitizeForExport(entry.subtitle),
                    category: entry.category,
                    iconType: entry.iconType,
                    action: entry.action.sanitizedForExport(),
                    selectedAt: entry.selectedAt,
                    selectionCount: entry.selectionCount
                )
            }
            sanitizedHistory = SearchHistoryBackupData(entries: entries, itemStats: history.itemStats)
        }

        return LightspotSettingsBackup(
            version: version,
            app: app,
            exportedAt: exportedAt,
            preferences: preferences,
            customCommands: sanitizedCommands,
            pinnedCommands: sanitizedPinned,
            searchHistory: sanitizedHistory,
            recentAppBundleIDs: recentAppBundleIDs
        )
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let sanitized = self.sanitizedForExport()
        let data = try encoder.encode(sanitized)

        // As an additional safeguard, ensure no raw /Users/<username> remains in the encoded UTF-8 JSON
        if let jsonString = String(data: data, encoding: .utf8) {
            let cleanString = PathSanitizer.sanitizeForExport(jsonString)
            if let cleanData = cleanString.data(using: .utf8) {
                return cleanData
            }
        }
        return data
    }

    static func decode(from data: Data) throws -> LightspotSettingsBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LightspotSettingsBackup
        do {
            backup = try decoder.decode(LightspotSettingsBackup.self, from: data)
        } catch {
            throw SettingsBackupError.invalidData(error.localizedDescription)
        }

        guard backup.version <= currentVersion else {
            throw SettingsBackupError.unsupportedVersion(backup.version)
        }
        guard backup.app == appIdentifier || backup.app == "Lightspot" else {
            throw SettingsBackupError.invalidAppIdentifier(backup.app)
        }
        return backup
    }
}

struct LightspotPreferencesBackup: Codable, Sendable, Equatable {
    var hotkeyOption: String
    var autoStartEnabled: Bool
    var hideMenuBarIcon: Bool
    var browserHistoryDays: Int?

    init(hotkeyOption: String, autoStartEnabled: Bool, hideMenuBarIcon: Bool, browserHistoryDays: Int? = nil) {
        self.hotkeyOption = hotkeyOption
        self.autoStartEnabled = autoStartEnabled
        self.hideMenuBarIcon = hideMenuBarIcon
        self.browserHistoryDays = browserHistoryDays
    }
}

struct SearchHistoryBackupData: Codable, Sendable, Equatable {
    var entries: [SearchHistoryEntry]
    var itemStats: [String: ItemUsageRecord]

    init(entries: [SearchHistoryEntry], itemStats: [String: ItemUsageRecord]) {
        self.entries = entries
        self.itemStats = itemStats
    }
}

enum SettingsBackupError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidAppIdentifier(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "This backup file was created by a newer version of Lightspot (schema v\(v)). Please update Lightspot to import this file."
        case .invalidAppIdentifier(let id):
            return "The selected file is not a valid Lightspot backup file (identifier: '\(id)')."
        case .invalidData(let detail):
            return "Unable to parse backup data: \(detail)"
        }
    }
}
