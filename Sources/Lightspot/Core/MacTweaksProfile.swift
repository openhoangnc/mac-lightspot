import CryptoKit
import Foundation

// MARK: - The Mac Tweaks configuration profile
//
// One System-scope profile holds every locked setting: Apple Intelligence off (except the
// kept features), a download block so removed models can't come back, and the Settings
// section's profile-backed tweaks. Removing the profile undoes all of it. Ported from
// RemoveMacAI's Profile.swift (MIT); the asset-service technique is pared's. The models are
// shared by every account and the profile is System scope, so it changes Apple Intelligence
// for everyone on this Mac.
//
// The builder (`data`) is pure and is what tests exercise. Writing the file, opening it,
// polling the marker and removing the profile are injected into the engine's environment, so
// no test installs or removes anything.

enum MacTweaksProfile {
    static let identifier = "com.lightspot.app.tweaks"
    static let displayName = "Lightspot Mac Tweaks"
    static let organization = "Lightspot"

    /// Point the asset service at a closed local port for each removed set, so a download fails
    /// instead of refilling the disk (pared's technique).
    static let downloadDomain = "com.apple.MobileAsset"
    static let downloadKeyPrefix = "DownloadServerBaseURLOverride-"
    static let blockedURL = "https://127.0.0.1:9/lightspot-blocked/"

    static func downloadKey(_ set: ModelSet) -> String { downloadKeyPrefix + set.assetType }

    /// Where the file is written before it is opened for approval: never `~/Downloads`, which is
    /// TCC-protected. Removed once the profile is installed.
    static func fileURL(home: String) -> URL {
        URL(fileURLWithPath: home + "/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig")
    }

    /// What the profile contains: Apple Intelligence off except the kept features (nil leaves
    /// Apple Intelligence alone), and the Settings tweaks it locks. Changing `ai` keeps `tweaks`.
    struct Contents: Equatable, Sendable {
        var ai: Set<String>?
        var tweaks: Set<String>

        var isEmpty: Bool { ai == nil && tweaks.isEmpty }
    }

    // MARK: Building

    static func data(keeping kept: Set<String>, tweaks: Set<String>) throws -> Data {
        try data(Contents(ai: kept, tweaks: tweaks))
    }

    static func data(_ contents: Contents) throws -> Data {
        var restrictions = payload(type: "com.apple.applicationaccess", suffix: "restrictions", name: "Restrictions")
        var forced: [String: [String: Any]] = [:]

        if let kept = contents.ai {
            for feature in Catalog.availableFeatures where !kept.contains(feature.id) {
                for key in feature.restrictions { restrictions[key] = false }
                for pref in feature.preferences { forced[pref.domain, default: [:]][pref.key] = pref.off }
            }
            for name in Catalog.setsToRemove(keeping: kept) {
                guard let set = Catalog.modelSet(name) else { continue }
                forced[downloadDomain, default: [:]][downloadKey(set)] = blockedURL
            }
        }
        // The profile-backed Settings tweaks this version knows: their restrictions and forced
        // keys. The marker records exactly those, so changing `ai` keeps them.
        let tweaks = MacTweaksSettings.profileTweaks(contents.tweaks)
        for tweak in tweaks {
            for change in tweak.changes {
                switch change {
                case .restriction(let key): restrictions[key] = false
                case .forced(let domain, let key, let value):
                    if let object = value.object { forced[domain, default: [:]][key] = object }
                default: break
                }
            }
        }

        let marker: [String: Any] = [
            "installed": true,
            "ai": contents.ai != nil,
            "tweaks": tweaks.map(\.id).sorted().joined(separator: ","),
            "kept": (contents.ai ?? []).sorted().joined(separator: ","),
            "features": Catalog.availableFeatures.map(\.id).sorted().joined(separator: ","),
        ]
        forced[identifier] = marker

        let preferences = forced.keys.sorted().map { domain -> [String: Any] in
            var p = payload(type: "com.apple.ManagedClient.preferences", suffix: "preferences." + domain,
                            name: "Forced settings: \(domain)")
            p["PayloadContent"] = [domain: ["Forced": [["mcx_preference_settings": forced[domain]!]]]]
            return p
        }

        var profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier,
            "PayloadUUID": uuid(identifier),
            "PayloadDisplayName": displayName,
            "PayloadDescription": description(contents, tweaks: tweaks),
            "PayloadOrganization": organization,
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": false,
        ]
        // A restrictions payload only when there is an `allow…` key to set.
        let hasRestrictions = restrictions.keys.contains { $0.hasPrefix("allow") }
        profile["PayloadContent"] = (hasRestrictions ? [restrictions] : []) + preferences
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    /// What the profile does, as System Settings shows it before the owner approves it.
    static func description(_ contents: Contents, tweaks: [MacTweaksSettings.Tweak]) -> String {
        var text: String
        if contents.ai != nil {
            text = tweaks.isEmpty
                ? "Turns off Apple Intelligence as chosen in Lightspot's Mac Tweaks, and stops removed models downloading again."
                : "Turns off Apple Intelligence and the settings chosen in Lightspot's Mac Tweaks, and stops removed models downloading again."
        } else {
            text = "Locks the settings chosen in Lightspot's Mac Tweaks: " + tweaks.map(\.title).joined(separator: "; ") + "."
        }
        return text + " Remove this profile to undo everything it changed."
    }

    private static func payload(type: String, suffix: String, name: String) -> [String: Any] {
        let id = identifier + "." + suffix
        return [
            "PayloadType": type, "PayloadVersion": 1, "PayloadIdentifier": id,
            "PayloadUUID": uuid(id), "PayloadDisplayName": name,
        ]
    }

    /// A stable UUID per payload (version 5 style, SHA-1 of the identifier; CryptoKit is already
    /// linked), so installing a new version replaces the old one.
    static func uuid(_ name: String) -> String {
        var bytes = Array(Insecure.SHA1.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
    }

    // MARK: Reading the marker

    struct Installed: Equatable, Sendable {
        var on = false
        /// Whether the profile turns Apple Intelligence off. A missing flag means yes (older
        /// profiles only did that).
        var ai = false
        var kept: Set<String> = []
        var tweaks: Set<String> = []
        /// The features the profile was made for; older profiles don't record them.
        var features: Set<String>? = nil

        /// Made on an older macOS that lacked some of this one's features, so it leaves them on
        /// and has to be installed again.
        var stale: Bool {
            guard ai, let features else { return false }
            return !Set(Catalog.availableFeatures.map(\.id)).isSubset(of: features)
        }

        var contents: Contents? { on ? Contents(ai: ai && !stale ? kept : nil, tweaks: tweaks) : nil }
    }

    /// Parses an installed marker into `Installed`. Pure, so a test can feed the marker a built
    /// profile carries and check it reads back. `forced` is whether `installed` is forced;
    /// `value` copies one marker key.
    static func read(forced: Bool, value: (String) -> Any?) -> Installed {
        guard forced else { return Installed() }
        func list(_ key: String) -> Set<String> {
            let s = value(key) as? String ?? ""
            return Set(s.split(separator: ",").map(String.init))
        }
        let ai = value("ai") as? Bool ?? true
        let features = value("features") == nil ? nil : list("features")
        return Installed(on: true, ai: ai, kept: list("kept"), tweaks: list("tweaks"), features: features)
    }

    /// The live marker, read through cfprefsd (invariant 8: synchronize, then read back).
    static func installed() -> Installed {
        let domain = identifier as CFString
        CFPreferencesAppSynchronize(domain)
        let forced = CFPreferencesAppValueIsForced("installed" as CFString, domain)
        return read(forced: forced) { key in CFPreferencesCopyAppValue(key as CFString, domain) }
    }

    /// Whether another tool's profile manages Apple Intelligence (RemoveMacAI). Then the section
    /// is read-only.
    static let removeMacAIIdentifier = "io.github.omlahore.removemacai"

    static func removeMacAIInstalled() -> Bool {
        let domain = removeMacAIIdentifier as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesAppValueIsForced("installed" as CFString, domain)
    }

    /// Whether the installed profile is `contents`. A target without Apple Intelligence never
    /// matches a profile that turns it off, a stale one included (whose `contents` reads as
    /// leaving it alone): otherwise turning it back on would end at once with the profile still in.
    static func matches(_ contents: Contents, installed: Installed) -> Bool {
        installed.contents == contents && !(contents.ai == nil && installed.on && installed.ai)
    }

    // MARK: The removal

    /// The command that removes the profile as root: `profiles remove … -forced` suppresses
    /// confirmation (platform report B3). It runs as one step of the administrator batch in
    /// Free Up Space's form (`MacTweaksStorage.adminScript`: stdin from /dev/null, the step's own
    /// status reported, `exit 0`); the result is judged by the marker.
    static func removeCommand(profiles: String = "/usr/bin/profiles") -> String {
        "\(MacTweaksStorage.shellQuote(profiles)) remove -identifier \(MacTweaksStorage.shellQuote(identifier)) -forced"
    }

    // MARK: Changing it

    /// How a change of the profile ended, judged by the marker.
    enum ChangeOutcome: Sendable, Equatable {
        /// The installed profile is already the target: nothing to do.
        case alreadyMatches
        /// The marker now matches the target.
        case installed
        /// The profile is gone.
        case removed
        /// The approval wait ran out, or Esc stopped it; the profile stays pending in System Settings.
        case notApproved
        /// The batch ran but the profile stayed, and the owner's Remove didn't come within the wait.
        case notRemoved
        /// The administrator prompt was dismissed: nothing ran.
        case promptCancelled
        /// Not authorized: nothing ran.
        case promptRefused(String)
        /// The profile file couldn't be written.
        case writeFailed(String)
    }

    /// The one routine Apple Intelligence and Settings change the profile with. A target with
    /// something in it is installed: written, opened, Device Management opened, then the marker
    /// polled once a second for up to 10 minutes (Esc stops it), and the file removed once it is in.
    /// An empty target removes the profile: one administrator batch in Free Up Space's form, with
    /// `alsoAsAdministrator` after the removal so an apply asks once (Undo everything's background
    /// daemons); with no profile to remove, that batch holds `alsoAsAdministrator` alone. A
    /// cancelled or refused prompt stops there; a batch that ran and left the profile opens Device
    /// Management and waits for the owner's Remove. Progress lines and log lines go through
    /// `progress` and `log`; once the batch ran, `extraResults` gets each `alsoAsAdministrator`
    /// step's status and output, by its index there (Undo everything says why a daemon stayed).
    static func change(to target: Contents, env: MacTweaksProvider.Environment, alsoAsAdministrator extra: [String] = [],
                       progress: (@Sendable (String) -> Void)?, log: inout [String],
                       extraResults: (([Int: (status: Int32, output: String)]) -> Void)? = nil) -> ChangeOutcome {
        let ai = env.intelligence
        let ours = ai.profileInstalled()
        if target.isEmpty {
            let removing = ours.on
            guard removing || !extra.isEmpty else { return .alreadyMatches }
            let what = removing ? "profiles remove" : "administrator steps"
            progress?(removing ? "Removing the profile…" : "Asking for your password…")
            let tag = "__LS_" + String(UUID().uuidString.prefix(8))
            switch env.runAdmin(MacTweaksStorage.adminScript((removing ? [removeCommand()] : []) + extra, tag: tag)) {
            case .cancelled:
                log.append("\(what): the prompt was cancelled")
                return .promptCancelled
            case .refused(let message):
                log.append("\(what): not authorized (\(message))")
                return .promptRefused(message)
            case .ran(_, let output):
                let steps = MacTweaksStorage.batchResults(output, tag: tag)
                if removing {
                    log.append("profiles remove: " + (steps[1].map {
                        "status \($0.status)" + ($0.status == 0 ? "" : " (\(MacTweaksStorage.reason($0.output)))")
                    } ?? "no report"))
                }
                let first = removing ? 2 : 1
                var results: [Int: (status: Int32, output: String)] = [:]
                for index in extra.indices {
                    guard let step = steps[index + first] else { continue }
                    log.append("administrator step \(index + first): status \(step.status)")
                    results[index] = step
                }
                extraResults?(results)
            }
            guard removing else { return .alreadyMatches }
            if !ai.profileInstalled().on { return .removed }
            // The batch ran and the profile stayed: the owner removes it in System Settings.
            progress?(MacTweaksIntelligence.removalInstruction)
            ai.openDeviceManagement()
            if MacTweaksIntelligence.waitForRemoval(env: env) {
                log.append("profile removed in System Settings")
                return .removed
            }
            log.append("profile not removed within the wait")
            return .notRemoved
        }
        if matches(target, installed: ours) {
            log.append("the profile already matches")
            return .alreadyMatches
        }
        progress?("Preparing the profile…")
        do { try ai.presentProfile(target) } catch {
            log.append("profile write failed: \(error.localizedDescription)")
            return .writeFailed(error.localizedDescription)
        }
        progress?(MacTweaksIntelligence.approvalMessage)
        log.append("presented the profile for approval")
        guard MacTweaksIntelligence.waitForProfile(target, env: env) else {
            log.append("the profile was not installed within the wait")
            return .notApproved
        }
        ai.removeProfileFile()
        log.append("profile installed")
        return .installed
    }
}
