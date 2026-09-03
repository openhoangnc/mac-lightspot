import Foundation

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

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
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

    init(hotkeyOption: String, autoStartEnabled: Bool, hideMenuBarIcon: Bool) {
        self.hotkeyOption = hotkeyOption
        self.autoStartEnabled = autoStartEnabled
        self.hideMenuBarIcon = hideMenuBarIcon
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
