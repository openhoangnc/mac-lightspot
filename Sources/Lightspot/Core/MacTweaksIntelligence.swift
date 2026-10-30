import AppKit
import Foundation

// MARK: - Mac Tweaks: Apple Intelligence
//
// Turn Apple Intelligence off for every account on this Mac: a System-scope profile switches
// the features off and blocks the model downloads, then the downloaded models are removed
// through Apple's asset service. Ported from RemoveMacAI's Catalog.swift, System.swift and
// Commands.swift (MIT); the asset-service work and the download block are pared's. The catalog
// is data (arrays of plain structs); the asset-service calls run in a short-lived helper child
// (AppleAssetService), never in Lightspot's own process (platform report finding 1). Scans and
// applies block, so they run on MacTweaksProvider's queue, only once the user opens Mac Tweaks;
// the summary and the plan are built from what the last scan learned and read nothing.

/// A preference the profile forces while a feature is off.
struct ForcedPreference: Equatable, Sendable {
    let domain: String
    let key: String
    let off: Bool
}

/// One thing a person can switch off, the switches it takes, and the model sets it needs.
/// `since` is the first macOS (major, minor) to have it; a feature the running macOS lacks is
/// hidden rather than switched off with keys the system ignores.
struct Feature: Sendable {
    let id: String
    let title: String
    /// Lightspot's voice: what it does and what stops working (rule 6).
    let detail: String
    let restrictions: [String]
    let preferences: [ForcedPreference]
    let modelSets: [String]
    var since: (Int, Int) = (15, 1)
    /// The preference that decides whether the feature reads off when nothing forces it (Siri's
    /// `Assistant Enabled`), so a secondary preference alone can't make it read off. Without one,
    /// a feature with a single readable preference uses that one.
    var deciding: String? = nil
}

/// A downloadable model set in Apple's asset service.
struct ModelSet: Sendable {
    let name: String
    let assetType: String
    let title: String
}

enum Catalog {
    static let foundationModels = "com.apple.modelcatalog"
    static let visualModels = "com.apple.MobileAsset.UAF.FM.Visual"
    static let codeModels = "com.apple.MobileAsset.UAF.FM.CodeLM"
    static let cleanUpModels = "com.apple.MobileAsset.UAF.Photos.MagicCleanup"
    static let spatialModels = "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"

    static let modelSets: [ModelSet] = [
        ModelSet(name: foundationModels, assetType: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
                 title: "Apple Intelligence foundation models"),
        ModelSet(name: visualModels, assetType: visualModels, title: "Image and Genmoji models"),
        ModelSet(name: spatialModels, assetType: spatialModels, title: "Spatial Photos models"),
        ModelSet(name: cleanUpModels, assetType: cleanUpModels, title: "Photos Clean Up models"),
        ModelSet(name: codeModels, assetType: codeModels, title: "Xcode code completion models"),
    ]

    static let features: [Feature] = [
        Feature(id: "siri", title: "Siri and Siri AI",
                detail: "Siri, including its Apple Intelligence answers. Off means Siri won't respond.",
                restrictions: ["allowAssistant"],
                preferences: [
                    ForcedPreference(domain: "com.apple.assistant.support", key: "Assistant Enabled", off: false),
                    ForcedPreference(domain: "com.apple.Siri", key: "StatusMenuVisible", off: false),
                    ForcedPreference(domain: "com.apple.Siri", key: "VoiceTriggerUserEnabled", off: false),
                ], modelSets: [foundationModels], deciding: "Assistant Enabled"),
        Feature(id: "chatgpt", title: "ChatGPT and other AI extensions",
                detail: "Third-party AI in Apple apps. Off means they can't be used or signed into.",
                restrictions: ["allowExternalIntelligenceIntegrations", "allowExternalIntelligenceIntegrationsSignIn"],
                preferences: [], modelSets: [], since: (15, 2)),
        Feature(id: "writing-tools", title: "Writing Tools",
                detail: "Rewrite, proofread and summarize in text fields. Off removes the Writing Tools menu.",
                restrictions: ["allowWritingTools"], preferences: [], modelSets: [foundationModels]),
        Feature(id: "genmoji", title: "Genmoji",
                detail: "Making your own emoji from a description. Off hides Genmoji in the keyboard.",
                restrictions: ["allowGenmoji"], preferences: [], modelSets: [foundationModels, visualModels]),
        Feature(id: "image-playground", title: "Image Playground",
                detail: "The Image Playground app and image generation in Apple apps. Off disables both.",
                restrictions: ["allowImagePlayground"], preferences: [], modelSets: [foundationModels, visualModels]),
        Feature(id: "mail", title: "Mail summaries and smart replies",
                detail: "Mail's message summaries and suggested replies. Off stops Mail summarizing or suggesting.",
                restrictions: ["allowMailSummary", "allowMailSmartReplies"],
                preferences: [
                    ForcedPreference(domain: "group.com.apple.mail", key: "DisableAutomaticMessageSummarization", off: true),
                    ForcedPreference(domain: "group.com.apple.mail", key: "PersonalizedSmartReplies", off: false),
                ], modelSets: [foundationModels]),
        Feature(id: "notification-summaries", title: "Notification summaries",
                detail: "Summaries of stacked notifications. Off shows notifications as they arrive.",
                restrictions: [],
                preferences: [ForcedPreference(domain: "group.com.apple.usernoted", key: "summarize_previews", off: false)],
                modelSets: [foundationModels]),
        Feature(id: "messages-summaries", title: "Messages summaries",
                detail: "Summaries of long message threads. Off shows messages as they arrive.",
                restrictions: [],
                preferences: [ForcedPreference(domain: "com.apple.MobileSMS", key: "messageSummarizationEnabled", off: false)],
                modelSets: [foundationModels]),
        Feature(id: "safari-summaries", title: "Safari summaries",
                detail: "Summaries of web pages in Safari. Off removes the summarize button.",
                restrictions: ["allowSafariSummary"], preferences: [], modelSets: [foundationModels], since: (15, 4)),
        Feature(id: "notes-summaries", title: "Notes transcription summaries",
                detail: "Summaries of recorded-audio transcripts in Notes. Off leaves transcripts as they are.",
                restrictions: ["allowNotesTranscriptionSummary"], preferences: [], modelSets: [foundationModels], since: (15, 3)),
        Feature(id: "inline-predictions", title: "Inline text predictions",
                detail: "Grey suggested text while typing. Off stops the suggestions.",
                restrictions: [],
                preferences: [ForcedPreference(domain: ".GlobalPreferences", key: "NSAutomaticInlinePredictionEnabled", off: false)],
                modelSets: []),
        Feature(id: "spatial-photos", title: "Spatial Photos",
                detail: "Turning flat photos into spatial ones. Off keeps them flat.",
                restrictions: [],
                preferences: [ForcedPreference(domain: "com.apple.spatialphotosrelive", key: "LocallyDisabled", off: true)],
                modelSets: [spatialModels], since: (26, 0)),
        Feature(id: "photos-clean-up", title: "Photos Clean Up",
                detail: "The Clean Up tool in Photos that removes objects. Off removes its model, so the tool stops working.",
                restrictions: [], preferences: [], modelSets: [cleanUpModels]),
        Feature(id: "xcode-completion", title: "Xcode predictive code completion",
                detail: "Predictive code completion in Xcode. Off removes its model, so completion stops working.",
                restrictions: [], preferences: [], modelSets: [codeModels]),
    ]

    static func feature(_ id: String) -> Feature? { features.first { $0.id == id } }
    static func modelSet(_ name: String) -> ModelSet? { modelSets.first { $0.name == name } }

    /// The running macOS, as (major, minor).
    static var currentOS: (Int, Int) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return (os.majorVersion, os.minorVersion)
    }

    /// Apple Intelligence needs Apple silicon: an Intel Mac has none of these features.
    static var hasAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// The features a macOS version has, by `since` only. The scan hides a feature further when
    /// the service has retired every model set it needs (Spatial Photos on 26.7.2).
    static func availableFeatures(os: (Int, Int)) -> [Feature] { features.filter { os >= $0.since } }

    static var availableFeatures: [Feature] { availableFeatures(os: currentOS) }

    /// The model sets a version-available feature names.
    static var availableModelSets: [ModelSet] {
        modelSets.filter { set in availableFeatures.contains { $0.modelSets.contains(set.name) } }
    }

    /// The sets to remove: every available set whose features are all being turned off.
    static func setsToRemove(keeping kept: Set<String>) -> [String] {
        availableModelSets.map(\.name).filter { set in
            let users = availableFeatures.filter { $0.modelSets.contains(set) }
            return !users.isEmpty && users.allSatisfy { !kept.contains($0.id) }
        }
    }
}

/// Whether a feature is off, and why.
enum FeatureState: Equatable, Sendable {
    /// Off because Lightspot's profile locks it off.
    case lockedOff
    /// Off, read from the user's own preferences.
    case off
    case on
    /// Model sizes could not be read, so on or off is unknown.
    case unknown
    /// Another configuration profile sets at least one of its keys; Lightspot leaves it alone.
    case managed

    var isOn: Bool { self == .on }

    var label: String {
        switch self {
        case .lockedOff: return "Locked off"
        case .off: return "Off"
        case .on: return "On"
        case .unknown: return "Unknown"
        case .managed: return "Managed"
        }
    }
}

enum MacTweaksIntelligence {
    typealias ProviderEnvironment = MacTweaksProvider.Environment

    /// The action row that turns Apple Intelligence back on.
    static let turnOnID = "turn-on"
    static let turnOnTitle = "Turn Apple Intelligence back on"
    /// The action row that finishes a removal left incomplete (the profile is installed and the
    /// sets it blocks still hold models, e.g. after a locked set needed a restart).
    static let finishRemovalID = "finish-removal"
    static let finishRemovalTitle = "Finish removing the models"

    /// The caveat every feature row carries while RemoveMacAI manages Apple Intelligence.
    static let coexistCaveat = "RemoveMacAI manages Apple Intelligence on this Mac."
    /// On a feature a stale profile was made without.
    static let staleCaveat = "New since Lightspot's profile was made. Applying adds it to the profile."
    static let everyAccount = "Changes Apple Intelligence for every account on this Mac."
    static let notOnThisMac = "Apple Intelligence's models aren't on this Mac"
    static let storageNote =
        "System Settings' Storage can keep counting the models for a while; macOS deletes the files on its own schedule."
    static let lockedReason =
        "macOS is still using these models. Restart your Mac, then open Mac Tweaks again to finish."
    static let approvalMessage =
        "In System Settings › General › Device Management, double-click Lightspot Mac Tweaks, then click Install."
    static let removalInstruction =
        "In System Settings › General › Device Management, select Lightspot Mac Tweaks, then click Remove."

    /// Domains a non-sandboxed app can't read (the real values live in the apps' containers;
    /// platform report B1 and finding 12): a feature's keys there are judged by their forced
    /// value only, so the user's own value never makes the feature read off.
    static let unreadableDomains: Set<String> = ["group.com.apple.mail", "group.com.apple.usernoted", "com.apple.Safari"]

    /// An action row rather than a feature (the turn-on and finish-removal rows).
    static func isActionRow(_ id: String) -> Bool { id == turnOnID || id == finishRemovalID }

    // MARK: What a scan learned

    /// What the last scan read: the inventory, Lightspot's marker and RemoveMacAI's. The provider
    /// keeps it with the rows, so the summary and the plan are built from memory.
    struct ScanContext: Sendable, Equatable {
        var inventory: AssetInventory?
        var installed = MacTweaksProfile.Installed()
        var removeMacAI = false
    }

    enum Mode: Equatable, Sendable {
        /// Lightspot's profile doesn't turn Apple Intelligence off: the features are changeable.
        case normal
        /// It does, but was made on an older macOS and leaves new features on: changeable again.
        case stale
        /// It does: the features are read-only, the action rows undo or finish it.
        case turnOn
        /// RemoveMacAI's profile manages it: read-only, but Lightspot's own profile can go.
        case coexist
    }

    static func mode(_ context: ScanContext) -> Mode {
        if context.removeMacAI { return .coexist }
        let ours = context.installed
        guard ours.on && ours.ai else { return .normal }
        return ours.stale ? .stale : .turnOn
    }

    // MARK: Feature state

    /// Whether Lightspot's profile turns this feature off: it is installed, turns Apple
    /// Intelligence off, was made for the feature, and doesn't keep it.
    static func covers(_ ours: MacTweaksProfile.Installed, _ feature: Feature) -> Bool {
        ours.on && ours.ai && !ours.kept.contains(feature.id) && (ours.features?.contains(feature.id) ?? true)
    }

    /// A feature's switches: its restrictions (off is false) and its forced preferences.
    static func switches(_ feature: Feature) -> [ForcedPreference] {
        feature.restrictions.map { ForcedPreference(domain: "com.apple.applicationaccess", key: $0, off: false) }
            + feature.preferences
    }

    /// Whether a feature is off, and why. Any forced key means a profile sets it: Lightspot's own
    /// when it covers the feature and every key is forced to its off value (locked off), anyone
    /// else's otherwise (managed, whatever the values). With nothing forced, a model-only feature
    /// follows its models, and another reads off from its deciding preference.
    static func state(_ feature: Feature, inventory: AssetInventory?, env: ProviderEnvironment,
                      ours: MacTweaksProfile.Installed) -> FeatureState {
        let ai = env.intelligence
        let keys = switches(feature)
        let forced = keys.filter { ai.prefForced($0.domain, $0.key) }
        if !forced.isEmpty {
            let allOff = forced.count == keys.count && keys.allSatisfy { ai.prefBool($0.domain, $0.key) == $0.off }
            return covers(ours, feature) && allOff ? .lockedOff : .managed
        }
        if keys.isEmpty {
            // Only models: locked off while Lightspot's profile blocks their download.
            return covers(ours, feature) ? .lockedOff : modelState(feature.modelSets, inventory: inventory)
        }
        return readsOff(feature, env: env) ? .off : .on
    }

    /// Off from the user's own preferences: the deciding preference reads off. Preferences in a
    /// domain Lightspot can't read never count. Without a deciding one, every readable
    /// preference that is set reads off, and one is set.
    static func readsOff(_ feature: Feature, env: ProviderEnvironment) -> Bool {
        let ai = env.intelligence
        let readable = feature.preferences.filter { !unreadableDomains.contains($0.domain) }
        let deciding = feature.deciding.flatMap { key in readable.first { $0.key == key } }
            ?? (readable.count == 1 ? readable.first : nil)
        if let deciding { return ai.prefBool(deciding.domain, deciding.key) == deciding.off }
        let set = readable.compactMap { pref in ai.prefBool(pref.domain, pref.key).map { ($0, pref.off) } }
        return !set.isEmpty && set.allSatisfy { $0.0 == $0.1 }
    }

    static func modelState(_ sets: [String], inventory: AssetInventory?) -> FeatureState {
        let readings = sets.map { inventory?.bytes($0) }
        if readings.contains(where: { ($0 ?? 0) > 0 }) { return .on }
        return readings.allSatisfy { $0 == 0 } ? .off : .unknown
    }

    // MARK: Models, and what a removal does

    /// The bytes of these sets, or nil when the service didn't answer or one size is unknown.
    static func total(_ sets: [String], inventory: AssetInventory?) -> Int64? {
        guard let inventory, inventory.available else { return nil }
        var sum: Int64 = 0
        for set in sets {
            guard let bytes = inventory.bytes(set) else { return nil }
            sum += bytes
        }
        return sum
    }

    /// The models on disk across the sets the service knows, or nil when it can't say.
    static func modelBytes(_ inventory: AssetInventory?) -> Int64? {
        guard let inventory, inventory.available else { return nil }
        return total(Catalog.modelSets.map(\.name).filter { inventory.info($0)?.known == true }, inventory: inventory)
    }

    /// What a removal would do for a set of kept features. The plan and the apply both use it, so
    /// the plan says exactly what the apply does.
    struct RemovalPlan: Equatable, Sendable {
        /// The sets no kept feature needs that the service knows on this macOS.
        var removing: [String] = []
        /// The sets no kept feature needs that the service doesn't know: left alone.
        var skipped: [String] = []
        /// What `removing` holds; nil when the inventory can't say.
        var bytes: Int64?
        /// The service answered.
        var available = false

        /// RemoveMacAI's rule: a removal is requested only when the sets to remove hold bytes or
        /// their size is unknown. A known 0 means the models aren't on this Mac: nothing is sent.
        var isNeeded: Bool { available && !removing.isEmpty && bytes != 0 }
    }

    static func removalPlan(keeping kept: Set<String>, inventory: AssetInventory?) -> RemovalPlan {
        let toRemove = Catalog.setsToRemove(keeping: kept)
        guard let inventory, inventory.available else { return RemovalPlan(bytes: nil, available: false) }
        // Only sets whose asset type still matches the catalog's (RemoveMacAI's `matching`).
        let removing = toRemove.filter { inventory.info($0)?.known == true }
        return RemovalPlan(removing: removing, skipped: toRemove.filter { !removing.contains($0) },
                           bytes: total(removing, inventory: inventory), available: true)
    }

    static func skippedSentence(_ sets: [String]) -> String {
        let titles = sets.map { Catalog.modelSet($0)?.title ?? $0 }.joined(separator: ", ")
        return "\(titles) \(sets.count == 1 ? "stays" : "stay"): not found on this version of macOS, so left alone."
    }

    /// Why nothing is removed when a plan isn't needed: the features kept need every set, the
    /// models on this Mac belong to kept features, or there are none. nil when only unknown sets
    /// were to go (their own sentence says so).
    static func noRemovalNote(_ plan: RemovalPlan, inventory: AssetInventory?) -> String? {
        if plan.removing.isEmpty {
            return plan.skipped.isEmpty ? "No models are removed: the features you kept need them." : nil
        }
        let others = Catalog.modelSets.map(\.name).filter { !plan.removing.contains($0) && inventory?.info($0)?.known == true }
        if let kept = total(others, inventory: inventory), kept > 0 {
            return "No models to remove: the ones on this Mac belong to features you kept."
        }
        return notOnThisMac + "."
    }

    /// The plan's sentence about the models.
    static func removalSentence(_ plan: RemovalPlan, inventory: AssetInventory?) -> String {
        var text: String
        if !plan.available {
            text = "Apple's asset service didn't answer, so the models can't be removed now. The profile still stops macOS downloading them."
        } else if let bytes = plan.bytes, bytes > 0 {
            text = "Deletes \(MacTweaksProvider.size(bytes)) of models and stops macOS downloading them again."
        } else if plan.isNeeded {
            text = "Asks macOS to remove the models, whose size it couldn't report, and stops it downloading them again."
        } else if let note = noRemovalNote(plan, inventory: inventory) {
            text = plan.removing.isEmpty ? note : note + " The profile stops macOS downloading them."
        } else {
            text = ""
        }
        if !plan.skipped.isEmpty { text += (text.isEmpty ? "" : " ") + skippedSentence(plan.skipped) }
        return text
    }

    // MARK: Which features to show

    /// Version-available features, minus those whose every model set the service has retired
    /// (so `getAssetSet:` returns nil): hidden rather than shown with a switch macOS ignores.
    static func visibleFeatures(os: (Int, Int), inventory: AssetInventory?) -> [Feature] {
        Catalog.features.filter { feature in
            guard os >= feature.since else { return false }
            guard let inventory, inventory.available, !feature.modelSets.isEmpty else { return true }
            return feature.modelSets.contains { inventory.info($0)?.known == true }
        }
    }

    /// An SF Symbol per feature; the action rows' too. deep_verify checks each one exists.
    static let symbols: [String: String] = [
        "siri": "mic", "chatgpt": "bubble.left.and.bubble.right", "writing-tools": "textformat",
        "genmoji": "face.smiling", "image-playground": "photo.artframe", "mail": "envelope",
        "notification-summaries": "bell", "messages-summaries": "message", "safari-summaries": "safari",
        "notes-summaries": "note.text", "inline-predictions": "text.cursor", "spatial-photos": "cube",
        "photos-clean-up": "wand.and.stars", "xcode-completion": "chevron.left.forwardslash.chevron.right",
        turnOnID: "arrow.clockwise", finishRemovalID: "trash",
    ]

    static func symbol(_ id: String) -> String { symbols[id] ?? "sparkles" }

    // MARK: Scanning

    /// The model sets a feature needs, as items with sizes, for the selected row's detail.
    static func modelItems(_ feature: Feature, inventory: AssetInventory?) -> [MacTweaksItem] {
        feature.modelSets.compactMap { name in
            guard let set = Catalog.modelSet(name) else { return nil }
            return MacTweaksItem(target: set.title, bytes: max(0, inventory?.bytes(name) ?? 0))
        }
    }

    /// Blocking: the inventory (the helper child), Lightspot's marker and RemoveMacAI's.
    static func readContext(_ env: ProviderEnvironment) -> ScanContext {
        let ai = env.intelligence
        return ScanContext(inventory: ai.assetInventory(), installed: ai.profileInstalled(), removeMacAI: ai.removeMacAIInstalled())
    }

    /// The rows for an inventory already read, with the markers read now.
    static func scan(_ env: ProviderEnvironment, inventory: AssetInventory?,
                     progress: (@Sendable (String) -> Void)? = nil) -> [MacTweaksRow] {
        let ai = env.intelligence
        let context = ScanContext(inventory: inventory, installed: ai.profileInstalled(), removeMacAI: ai.removeMacAIInstalled())
        return scan(env, context: context, progress: progress)
    }

    /// The rows for the section: one per shown feature, with its state and the models it needs;
    /// "Finish removing the models" while Lightspot's profile blocks sets that still hold models;
    /// "Turn Apple Intelligence back on" while its profile turns it off; every feature read-only
    /// while that profile is in force (not stale) or RemoveMacAI manages Apple Intelligence.
    static func scan(_ env: ProviderEnvironment, context: ScanContext,
                     progress: (@Sendable (String) -> Void)? = nil) -> [MacTweaksRow] {
        let ai = env.intelligence
        let ours = context.installed
        let mode = mode(context)
        let coexist = mode == .coexist
        let turnOnMode = mode == .turnOn
        // The profile file is needed only until the profile is installed.
        if ours.on { ai.removeProfileFile() }
        var rows: [MacTweaksRow] = []

        // Only when it would do something: never when the inventory knows the sets total 0.
        if turnOnMode, removalPlan(keeping: ours.kept, inventory: context.inventory).isNeeded {
            var row = MacTweaksRow(id: finishRemovalID, symbol: symbol(finishRemovalID), title: finishRemovalTitle,
                                   detail: "Apple Intelligence is off, but some of its models are still on this Mac. Remove them now.")
            row.isDefault = true
            row.exclusive = true
            row.outcome = "Models removed"
            row.countLabel = ""
            rows.append(row)
        }
        // Unticked, so reopening after Esc or a timeout never defaults to undoing the user's choice.
        if ours.on && ours.ai {
            var row = MacTweaksRow(id: turnOnID, symbol: symbol(turnOnID), title: turnOnTitle,
                                   detail: MacTweaksSettings.heldTweaks(ours).isEmpty
                                       ? "Removes Lightspot's profile so macOS can use Apple Intelligence again. It downloads the models when you next turn a feature on."
                                       : "Updates Lightspot's profile to stop turning Apple Intelligence off, keeping your other Mac Tweaks settings.")
            row.exclusive = true
            row.outcome = "Apple Intelligence back on"
            row.countLabel = ""
            rows.append(row)
        }

        for feature in visibleFeatures(os: ai.osVersion(), inventory: context.inventory) {
            let featureState = state(feature, inventory: context.inventory, env: env, ours: ours)
            var row = MacTweaksRow(id: feature.id, symbol: symbol(feature.id), title: feature.title, detail: feature.detail)
            row.items = modelItems(feature, inventory: context.inventory)
            row.countLabel = featureState.label
            let readOnly = coexist || turnOnMode || featureState == .managed
            row.readOnly = readOnly
            // Ticked means "turn off", and every changeable feature starts ticked; a stale
            // profile's features start as its marker had them, the ones it kept unticked.
            row.isDefault = !readOnly && !(mode == .stale && ours.kept.contains(feature.id))
            row.outcome = outcome(for: featureState)
            if coexist {
                row.caveat = coexistCaveat
            } else if featureState == .managed {
                row.caveat = "Another configuration profile sets this, so Lightspot leaves it alone."
            } else if mode == .stale, !(ours.features?.contains(feature.id) ?? true) {
                row.caveat = staleCaveat
            } else if featureState == .unknown {
                row.caveat = "Apple's asset service didn't report this model's size."
            }
            rows.append(row)
        }
        return rows
    }

    /// What the plan says applying does to a ticked feature, by its state now.
    static func outcome(for state: FeatureState) -> String {
        switch state {
        case .off: return "Stays off, now locked off"
        case .lockedOff: return "Stays locked off"
        case .on, .unknown, .managed: return "Turned off"
        }
    }

    // MARK: The summary, the plan and its button

    static func summary(rows: [MacTweaksRow], context: ScanContext?) -> String {
        let context = context ?? ScanContext()
        if context.removeMacAI {
            let ours = context.installed
            return "RemoveMacAI manages Apple Intelligence on this Mac, so Lightspot leaves it alone."
                + (ours.on && ours.ai ? " Lightspot's own profile can still be removed." : "")
        }
        let features = rows.filter { !isActionRow($0.id) }
        let on = features.filter { $0.countLabel == FeatureState.on.label }.count
        var parts = ["\(on) of \(features.count) \(features.count == 1 ? "feature" : "features") on"]
        if let bytes = modelBytes(context.inventory) {
            parts.append(bytes > 0 ? "\(MacTweaksProvider.size(bytes)) of models on this Mac" : notOnThisMac)
        } else {
            parts.append(context.inventory?.available == true ? "the models' size is unknown" : "Apple's asset service didn't answer")
        }
        let added = features.filter { $0.caveat == staleCaveat }.map(\.title)
        if !added.isEmpty { parts.append("Lightspot's profile predates \(added.joined(separator: ", "))") }
        return parts.joined(separator: " · ") + ". " + everyAccount
    }

    static func applyTitle(ticked rows: [MacTweaksRow]) -> String {
        if rows.contains(where: { $0.id == turnOnID }) { return turnOnTitle }
        if rows.contains(where: { $0.id == finishRemovalID }) { return finishRemovalTitle }
        let n = rows.count
        return "Turn off \(n) \(n == 1 ? "feature" : "features")"
    }

    /// The plan's closing sentences, from the scan on show: `ticked` are the ticked rows, `shown`
    /// all of them, `context` what that scan read. Reads nothing, so the plan view can build it on
    /// the main thread (invariant 0).
    static func planNotes(ticked: [MacTweaksRow], shown: [MacTweaksRow], context: ScanContext?) -> [String] {
        let context = context ?? ScanContext()
        let ours = context.installed
        // Settings tweaks this version doesn't know can't go in a new profile.
        let dropped = [MacTweaksSettings.droppedNote(MacTweaksSettings.unknownTweaks(ours))].compactMap { $0 }
        if ticked.contains(where: { $0.id == turnOnID }) {
            if MacTweaksSettings.heldTweaks(ours).isEmpty {
                return ["Removes Lightspot's profile, so macOS can use Apple Intelligence again on every account on this Mac.",
                        "Lightspot asks for your administrator password to remove its profile."] + dropped
            }
            return ["Updates Lightspot's profile to stop turning Apple Intelligence off on every account on this Mac. Your other Mac Tweaks settings stay.",
                    "System Settings asks you to approve the updated profile."] + dropped
        }
        if ticked.contains(where: { $0.id == finishRemovalID }) {
            return ["Apple Intelligence stays off.",
                    removalSentence(removalPlan(keeping: ours.kept, inventory: context.inventory), inventory: context.inventory)]
        }
        let tickedIDs = Set(ticked.map(\.id))
        let kept = Set(Catalog.availableFeatures.map(\.id)).subtracting(tickedIDs)
        var notes = ["Turns these features off for every account on this Mac."]
        let keptShown = shown.filter { !isActionRow($0.id) && !$0.readOnly && !tickedIDs.contains($0.id) }.map(\.title)
        if !keptShown.isEmpty { notes.append("Kept on: \(keptShown.joined(separator: ", ")).") }
        let models = removalSentence(removalPlan(keeping: kept, inventory: context.inventory), inventory: context.inventory)
        if !models.isEmpty { notes.append(models) }
        let target = MacTweaksProfile.Contents(ai: kept, tweaks: MacTweaksSettings.heldTweaks(ours))
        if MacTweaksProfile.matches(target, installed: ours) {
            notes.append("The profile is already installed.")
        } else {
            notes.append("System Settings asks you to approve one profile.")
            notes += dropped
        }
        return notes
    }

    // MARK: Applying

    typealias ApplyResult = (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow], context: ScanContext?)

    /// Turns the ticked features off, finishes a removal, or turns Apple Intelligence back on.
    /// Turning off puts the profile in first, so the models can't download again, then removes
    /// them. `shown` is the scan the plan came from (for the headline). Blocking: the provider
    /// runs it on its queue.
    static func apply(_ rows: [MacTweaksRow], shown: [MacTweaksRow]? = nil, env: ProviderEnvironment,
                      progress: (@Sendable (String) -> Void)? = nil) -> ApplyResult {
        let started = env.now()
        let ai = env.intelligence

        // Lightspot's own profile can always go, RemoveMacAI's installed or not.
        if rows.contains(where: { $0.id == turnOnID }) {
            return turnBackOn(env: env, started: started, progress: progress)
        }
        if ai.removeMacAIInstalled() {
            return finish(MacTweaksReceipt(headline: "Nothing changed.",
                problems: ["RemoveMacAI manages Apple Intelligence on this Mac. Turn it on or off in RemoveMacAI, or remove RemoveMacAI's profile first."],
                isSuccess: false),
                env: env, started: started, log: ["coexistence: RemoveMacAI manages Apple Intelligence"])
        }
        if rows.contains(where: { $0.id == finishRemovalID }) {
            return finishRemoval(env: env, started: started, progress: progress)
        }

        // Turn off. Every feature left unticked is kept, a hidden one included: the profile never
        // touches a feature the user didn't choose, and a kept one stays kept whatever the service
        // says now.
        let tickedIDs = Set(rows.map(\.id))
        let kept = Set(Catalog.availableFeatures.map(\.id)).subtracting(tickedIDs)
        let ours = ai.profileInstalled()
        // The Settings tweaks the profile holds stay in it.
        let target = MacTweaksProfile.Contents(ai: kept, tweaks: MacTweaksSettings.heldTweaks(ours))
        var log: [String] = []

        // 1. The profile, through the routine Settings shares.
        switch MacTweaksProfile.change(to: target, env: env, progress: progress, log: &log) {
        case .writeFailed(let message):
            return finish(MacTweaksReceipt(headline: "Couldn't start.",
                problems: ["Lightspot couldn't write the profile: \(message)"], isSuccess: false),
                env: env, started: started, log: log)
        case .installed, .alreadyMatches, .removed:
            break
        case .notApproved, .notRemoved, .promptCancelled, .promptRefused:
            return finish(MacTweaksReceipt(headline: "Waiting for the profile.",
                notes: ["The profile isn't installed yet. Approve it in System Settings › General › Device Management, then open Mac Tweaks again to finish."],
                isSuccess: false),
                env: env, started: started, log: log)
        }

        // 2. The models, now that they can't download again.
        progress?("Checking the models…")
        let result = removeModels(keeping: kept, env: env, log: &log, progress: progress)
        let everyShownTicked = shown.map { $0.filter { !isActionRow($0.id) }.allSatisfy { tickedIDs.contains($0.id) } } ?? true
        var headline = everyShownTicked ? "Apple Intelligence is off." : "The selected features are off."
        if result.requested && !result.complete { headline += " Model removal is incomplete." }
        let receipt = MacTweaksReceipt(headline: headline, lines: result.lines, problems: result.problems, notes: result.notes,
                                       isSuccess: result.problems.isEmpty && (!result.requested || result.complete))
        return finish(receipt, env: env, started: started, log: log, rescan: true)
    }

    /// What one removal did.
    struct RemovalResult: Sendable {
        var lines: [String] = []
        var problems: [String] = []
        var notes: [String] = []
        /// A reset was asked of the service (the plan was needed).
        var requested = false
        /// Every set reached 0 with nothing locked or failed (or nothing needed removing).
        var complete = false
        var anyLocked = false
        /// Every set asked about stayed locked.
        var allLocked = false
    }

    /// Removes the downloaded models of every set no kept feature needs, under the plan's rule:
    /// nothing is sent when the inventory knows those sets total 0. A fresh inventory, since the
    /// approval can take minutes (RemoveMacAI takes a fresh snapshot too). The helper decides per
    /// set whether anything is on disk (RemoveMacAI's `present`).
    private static func removeModels(keeping kept: Set<String>, env: ProviderEnvironment, log: inout [String],
                                     progress: (@Sendable (String) -> Void)? = nil) -> RemovalResult {
        let ai = env.intelligence
        let inventory = ai.assetInventory()
        let plan = removalPlan(keeping: kept, inventory: inventory)
        var result = RemovalResult()
        guard plan.available else {
            log.append("asset service unavailable; no removal requested")
            result.problems.append("Apple's asset service didn't answer, so the models weren't removed. The profile still stops them downloading again.")
            return result
        }
        if !plan.skipped.isEmpty {
            result.problems.append(skippedSentence(plan.skipped))
            log.append("left alone, not on this macOS: \(plan.skipped.joined(separator: ", "))")
        }
        guard plan.isNeeded else {
            log.append(plan.removing.isEmpty ? "no set to remove" : "the sets to remove hold 0 bytes; nothing sent")
            if let note = noRemovalNote(plan, inventory: inventory) { result.notes.append(note) }
            result.complete = true
            return result
        }
        progress?("Removing the models…")
        result.requested = true
        var locked = 0, done = 0, failed = 0
        for set in plan.removing {
            let title = Catalog.modelSet(set)?.title ?? set
            switch retrying({ ai.resetAssetSet(set) }, delays: [5, 15], env: env) {
            case .done: done += 1; log.append("reset requested: \(set)")
            case .notPresent: log.append("nothing on disk, nothing sent: \(set)")
            case .locked: locked += 1; result.problems.append("\(title): macOS is still using it."); log.append("locked: \(set)")
            case .noAnswer: failed += 1; result.problems.append("\(title): the asset service didn't answer."); log.append("no answer: \(set)")
            case .failed(let m): failed += 1; result.problems.append("\(title): \(m)"); log.append("failed: \(set) (\(m))")
            case .refused(let m): failed += 1; result.problems.append("\(title): \(m)"); log.append("refused: \(set) (\(m))")
            }
        }
        result.anyLocked = locked > 0
        result.allLocked = locked > 0 && done == 0 && failed == 0
        let (after, verified) = verifyRemoved(plan.removing, env: env)
        var deleted: Int64?
        if let before = plan.bytes, let after { deleted = max(0, before - after) }
        let goneUnknown = plan.bytes == nil && after == 0
        if let deleted, deleted > 0 {
            result.lines.append("Deleted \(MacTweaksProvider.size(deleted)) of models.")
        } else if goneUnknown {
            result.lines.append("The models are gone. How much that freed is unknown: the asset service didn't report every size.")
        }
        if after == nil {
            result.problems.append("Lightspot couldn't confirm the models were removed.")
        } else if let after, after > 0 {
            result.problems.append("\(MacTweaksProvider.size(after)) of models remain.")
        }
        if result.anyLocked {
            result.notes.append(lockedReason)
        } else if !verified {
            result.notes.append("macOS hadn't finished removing them when Lightspot last looked.")
        }
        if (deleted ?? 0) > 0 || goneUnknown { result.notes.append(storageNote) }
        result.complete = verified && after == 0 && locked == 0 && failed == 0
        log.append("before \(plan.bytes.map(String.init) ?? "unknown"), after \(after.map(String.init) ?? "unknown"), verified \(verified)")
        return result
    }

    /// Asks again after each delay while the set is locked (5 s, then 15 s).
    static func retrying(_ attempt: () -> AssetResetOutcome, delays: [TimeInterval], env: ProviderEnvironment) -> AssetResetOutcome {
        var outcome = attempt()
        for delay in delays where outcome == .locked {
            env.intelligence.sleep(delay)
            outcome = attempt()
        }
        return outcome
    }

    /// Polls the inventory every 3 s for up to 30 s until the sets reach 0 (not faster: each read
    /// takes short-term locks). Returns the last total (nil when the service couldn't say) and
    /// whether it reached 0.
    static func verifyRemoved(_ sets: [String], env: ProviderEnvironment,
                              interval: TimeInterval = 3, timeout: TimeInterval = 30) -> (after: Int64?, verified: Bool) {
        func current() -> Int64? { total(sets, inventory: env.intelligence.assetInventory()) }
        var after = current()
        if after == 0 { return (0, true) }
        let deadline = env.now().addingTimeInterval(timeout)
        while env.now() < deadline {
            env.intelligence.sleep(interval)
            after = current()
            if after == 0 { return (0, true) }
        }
        return (after, false)
    }

    /// Polls Lightspot's marker once a second for up to 10 minutes until the profile matches. The
    /// wait survives the panel hiding (System Settings takes the focus); Esc stops it, and only
    /// while it waits (`waiting`).
    static func waitForProfile(_ target: MacTweaksProfile.Contents, env: ProviderEnvironment,
                               interval: TimeInterval = 1, timeout: TimeInterval = 600) -> Bool {
        let ai = env.intelligence
        ai.waiting(true)
        defer { ai.waiting(false) }
        let deadline = env.now().addingTimeInterval(timeout)
        while env.now() < deadline {
            if MacTweaksProfile.matches(target, installed: ai.profileInstalled()) { return true }
            if ai.isCancelled() { return false }
            ai.sleep(interval)
        }
        return false
    }

    /// Polls until Lightspot's profile is gone, once a second for up to 10 minutes; Esc stops it.
    static func waitForRemoval(env: ProviderEnvironment, interval: TimeInterval = 1, timeout: TimeInterval = 600) -> Bool {
        let ai = env.intelligence
        ai.waiting(true)
        defer { ai.waiting(false) }
        let deadline = env.now().addingTimeInterval(timeout)
        while env.now() < deadline {
            if !ai.profileInstalled().on { return true }
            if ai.isCancelled() { return false }
            ai.sleep(interval)
        }
        return false
    }

    /// Finishes a removal left incomplete, only with Lightspot's profile in force and made for
    /// this macOS: then the sets it blocks are the ones to remove and the kept features' stay.
    /// Without it a reset could take models a kept feature needs, with nothing to stop them
    /// downloading again, so nothing is sent.
    private static func finishRemoval(env: ProviderEnvironment, started: Date,
                                      progress: (@Sendable (String) -> Void)?) -> ApplyResult {
        let ours = env.intelligence.profileInstalled()
        guard ours.on && ours.ai && !ours.stale else {
            return finish(MacTweaksReceipt(headline: "Nothing changed.",
                notes: ["Lightspot's profile isn't installed any more, so the models stay. Turn the features off again to remove them."],
                isSuccess: false),
                env: env, started: started, log: ["finish: the profile is not installed; nothing sent"], rescan: true)
        }
        var log = ["finishing model removal"]
        let result = removeModels(keeping: ours.kept, env: env, log: &log, progress: progress)
        let headline: String
        if !result.requested {
            headline = "No models to remove."
        } else if result.complete {
            headline = "Models removed."
        } else if result.allLocked {
            headline = "macOS is still using the models."
        } else {
            headline = "Some models remain."
        }
        let receipt = MacTweaksReceipt(headline: headline, lines: result.lines, problems: result.problems, notes: result.notes,
                                       isSuccess: result.problems.isEmpty && (!result.requested || result.complete))
        return finish(receipt, env: env, started: started, log: log, rescan: true)
    }

    /// Removes Lightspot's profile through the administrator batch (or reinstalls it without
    /// Apple Intelligence when it holds Settings tweaks), so macOS can use Apple Intelligence
    /// again. Through the routine Settings shares (`MacTweaksProfile.change`).
    private static func turnBackOn(env: ProviderEnvironment, started: Date,
                                   progress: (@Sendable (String) -> Void)?) -> ApplyResult {
        let ai = env.intelligence
        let ours = ai.profileInstalled()
        let backOn = MacTweaksReceipt(headline: "Apple Intelligence is back on.",
                                      notes: ["macOS downloads the models again when you next turn a feature on."])
        guard ours.on && ours.ai else {
            return finish(MacTweaksReceipt(headline: "Nothing to do.",
                notes: ["Lightspot isn't turning Apple Intelligence off on this Mac."], isSuccess: false),
                env: env, started: started, log: ["turn-on: the profile doesn't turn Apple Intelligence off"], rescan: true)
        }
        let tweaks = MacTweaksSettings.heldTweaks(ours)
        var log: [String] = []
        let change = MacTweaksProfile.change(to: MacTweaksProfile.Contents(ai: nil, tweaks: tweaks), env: env,
                                             progress: progress, log: &log)
        if !tweaks.isEmpty {
            // Keep the Settings tweaks: reinstalled without Apple Intelligence.
            switch change {
            case .writeFailed(let message):
                return finish(MacTweaksReceipt(headline: "Couldn't start.",
                    problems: ["Lightspot couldn't write the profile: \(message)"], isSuccess: false),
                    env: env, started: started, log: log)
            case .installed, .alreadyMatches, .removed:
                var receipt = backOn
                receipt.notes.insert("Your other Mac Tweaks settings are still in the profile.", at: 0)
                return finish(receipt, env: env, started: started, log: log + ["reinstalled without Apple Intelligence"], rescan: true)
            case .notApproved, .notRemoved, .promptCancelled, .promptRefused:
                return finish(MacTweaksReceipt(headline: "Waiting for the profile.",
                    notes: ["Approve the updated profile in System Settings › General › Device Management, then open Mac Tweaks again."],
                    isSuccess: false),
                    env: env, started: started, log: log + ["reinstall not approved within the wait"])
            }
        }
        switch change {
        case .removed, .alreadyMatches:
            return finish(backOn, env: env, started: started, log: log, rescan: true)
        case .promptCancelled:
            return finish(MacTweaksReceipt(headline: "The profile is still installed.",
                notes: ["The administrator prompt was cancelled, so Lightspot didn't remove its profile."], isSuccess: false),
                env: env, started: started, log: log)
        case .promptRefused:
            return finish(MacTweaksReceipt(headline: "The profile is still installed.",
                notes: ["macOS didn't accept the administrator password, so Lightspot didn't remove its profile."], isSuccess: false),
                env: env, started: started, log: log)
        case .notRemoved, .installed, .notApproved, .writeFailed:
            return finish(MacTweaksReceipt(headline: "The profile is still installed.",
                notes: [removalInstruction + " Then open Mac Tweaks again."], isSuccess: false),
                env: env, started: started, log: log)
        }
    }

    /// Writes the receipt to the log and, when something changed, scans again.
    private static func finish(_ receipt: MacTweaksReceipt, env: ProviderEnvironment, started: Date,
                               log: [String], rescan: Bool = false) -> ApplyResult {
        MacTweaksProvider.appendReceipt(section: .appleIntelligence,
                                        lines: log + [receipt.headline] + receipt.lines + receipt.problems,
                                        environment: env, started: started)
        guard rescan else { return (receipt, [], nil) }
        let context = readContext(env)
        return (receipt, scan(env, context: context), context)
    }

    // MARK: The section's environment

    /// Everything the section reads or changes, injected so tests use fakes and deep_verify the
    /// read-only bridge in-process. `.inert` is the safe default; `.live` wires the real system.
    struct Environment: Sendable {
        /// The asset inventory from the short-lived helper child (never the framework in
        /// Lightspot's own process).
        var assetInventory: @Sendable () -> AssetInventory? = { nil }
        /// Resets one set through the helper child.
        var resetAssetSet: @Sendable (String) -> AssetResetOutcome = { _ in .noAnswer }
        /// Lightspot's installed profile, read from its marker.
        var profileInstalled: @Sendable () -> MacTweaksProfile.Installed = { MacTweaksProfile.Installed() }
        /// Whether RemoveMacAI's profile manages Apple Intelligence.
        var removeMacAIInstalled: @Sendable () -> Bool = { false }
        /// Whether a preference key is forced (by any profile), and its boolean value.
        var prefForced: @Sendable (_ domain: String, _ key: String) -> Bool = { _, _ in false }
        var prefBool: @Sendable (_ domain: String, _ key: String) -> Bool? = { _, _ in nil }
        /// Writes the profile, opens it, and opens Device Management for approval.
        var presentProfile: @Sendable (MacTweaksProfile.Contents) throws -> Void = { _ in }
        /// Removes the profile file once the profile is installed: it is needed only until then.
        var removeProfileFile: @Sendable () -> Void = {}
        /// Opens the Device Management pane (for a removal the owner finishes).
        var openDeviceManagement: @Sendable () -> Void = {}
        /// The running macOS version, as (major, minor).
        var osVersion: @Sendable () -> (Int, Int) = { Catalog.currentOS }
        /// Sleeps while retrying, polling and waiting; a fake clock drives tests instantly.
        var sleep: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        /// A wait for System Settings starts (true) or ends (false): Esc stops only a wait, and
        /// the overlay says "Stop waiting" while there is one.
        var waiting: @Sendable (Bool) -> Void = { _ in }
        /// Whether Esc stopped the wait that is running.
        var isCancelled: @Sendable () -> Bool = { false }

        static let inert = Environment()

        static func live(home: String) -> Environment {
            var env = Environment()
            let client = AssetServiceClient.live
            env.assetInventory = { client.inventory() }
            env.resetAssetSet = { client.reset($0) }
            env.profileInstalled = { MacTweaksProfile.installed() }
            env.removeMacAIInstalled = { MacTweaksProfile.removeMacAIInstalled() }
            env.prefForced = { domain, key in
                CFPreferencesAppSynchronize(domain as CFString)
                return CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
            }
            env.prefBool = { domain, key in CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool }
            env.presentProfile = { contents in
                try MacTweaksIntelligence.presentProfile(contents, home: home, open: MacTweaksIntelligence.openInWorkspace,
                                                         pause: { Thread.sleep(forTimeInterval: $0) })
            }
            env.removeProfileFile = { try? FileManager.default.removeItem(at: MacTweaksProfile.fileURL(home: home)) }
            env.openDeviceManagement = { MacTweaksIntelligence.openInWorkspace(MacTweaksIntelligence.deviceManagementURL) }
            return env
        }
    }

    /// System Settings' Device Management pane, the link SettingsProvider's row uses.
    static var deviceManagementURL: URL { URL(string: SettingsProvider.deviceManagementLink)! }

    /// Writes the profile to `~/Library/Application Support/Lightspot/`, opens it, waits a second
    /// and opens Device Management, as RemoveMacAI does. `open` and `pause` are injected so a test
    /// can check the order without opening anything.
    static func presentProfile(_ contents: MacTweaksProfile.Contents, home: String,
                               open: (URL) -> Void, pause: (TimeInterval) -> Void) throws {
        let url = MacTweaksProfile.fileURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MacTweaksProfile.data(contents).write(to: url)
        open(url)
        pause(1)
        open(deviceManagementURL)
    }

    /// The profile file and Device Management both open in System Settings, so both go
    /// through `SystemSettingsOpener`, whose one queue keeps them in this order.
    static func openInWorkspace(_ url: URL) {
        SystemSettingsOpener.open(url)
    }

    /// Apple Intelligence as a Mac Tweaks section. A class so the provider can read what the last
    /// scan, or the apply's rescan, learned; it carries the scan on show, so building the plan
    /// reads nothing.
    final class Engine: MacTweaksSectionEngine, @unchecked Sendable {
        let environment: ProviderEnvironment
        /// The scan the overlay shows, for the plan and the apply's headline.
        let shown: [MacTweaksRow]
        let scanned: ScanContext?
        private let lock = NSLock()
        private var _lastContext: ScanContext?

        init(environment: ProviderEnvironment, shown: [MacTweaksRow] = [], scanned: ScanContext? = nil) {
            self.environment = environment
            self.shown = shown
            self.scanned = scanned
        }

        /// What the last scan or rescan read (nil until one ran). Read by the provider.
        var lastContext: ScanContext? { lock.lock(); defer { lock.unlock() }; return _lastContext }

        private func remember(_ context: ScanContext?) {
            guard let context else { return }
            lock.lock(); _lastContext = context; lock.unlock()
        }

        func scan(only: Set<String>?, progress: (@Sendable (String) -> Void)?) -> [MacTweaksRow] {
            progress?("Checking Apple Intelligence…")
            let context = MacTweaksIntelligence.readContext(environment)
            remember(context)
            return MacTweaksIntelligence.scan(environment, context: context, progress: progress)
        }

        func apply(_ rows: [MacTweaksRow], progress: (@Sendable (String) -> Void)?) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow]) {
            let result = MacTweaksIntelligence.apply(rows, shown: shown, env: environment, progress: progress)
            remember(result.context)
            return (result.receipt, result.rescanned)
        }

        func planNotes(for rows: [MacTweaksRow]) -> [String] {
            MacTweaksIntelligence.planNotes(ticked: rows, shown: shown, context: scanned)
        }
    }
}
