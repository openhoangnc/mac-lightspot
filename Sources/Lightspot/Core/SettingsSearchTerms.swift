import Foundation

// MARK: - System Settings Search Terms

/// System Settings' own search vocabulary. Every settings pane is an ExtensionKit
/// extension whose Info.plist names a `.searchTerms` file (`searchTermsFileName`); each
/// entry in it has a `title`, the setting as System Settings lists it ("Night Shift
/// options"), and an `index` of comma-separated words that find it ("warm, sunset,
/// temperature"). The extension's bundle identifier is the pane ID a deep link opens,
/// so the entries map straight onto `SettingsItem`s.
///
/// Reading them costs 40-140 ms (51 extensions, ~240 Info.plists to find them, two
/// languages), so it happens once, off the main thread, at launch. The keystroke path
/// only binary-searches the sorted keys built here.
enum SettingsSearchTerms {
    static let extensionDirectories = [
        URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions"),
        // General is bundled inside the app rather than with the other panes.
        URL(fileURLWithPath: "/System/Applications/System Settings.app/Contents/PlugIns"),
        // macOS 26 ships Passwords in the Safari cryptex.
        URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Library/CoreServices"),
    ]

    static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    struct PaneExtension {
        let bundleURL: URL
        let termsFileName: String?
    }

    struct Entry {
        let section: String
        let title: String
        let index: [String]
    }

    /// The user's languages in their order (System Settings searches the first), then
    /// English, because Lightspot's pane names and curated keywords are English. When two
    /// languages match equally, the earlier one names the setting.
    static func preferredLanguages() -> [String] {
        Locale.preferredLanguages + ["en"]
    }

    /// Every settings extension in `directories`, keyed by bundle identifier.
    static func paneExtensions(in directories: [URL] = extensionDirectories) -> [String: PaneExtension] {
        var found: [String: PaneExtension] = [:]
        let fm = FileManager.default
        for directory in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasSuffix(".appex") {
                let bundleURL = directory.appendingPathComponent(name)
                guard let plist = readPlist(bundleURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                      let attributes = plist["EXAppExtensionAttributes"] as? [String: Any],
                      attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
                      let bundleID = plist["CFBundleIdentifier"] as? String else { continue }
                let settings = attributes["SettingsExtensionAttributes"] as? [String: Any]
                found[bundleID] = PaneExtension(bundleURL: bundleURL, termsFileName: settings?["searchTermsFileName"] as? String)
            }
        }
        return found
    }

    /// The `.searchTerms` files of `pane` in each of `languages` that it is localized in.
    static func termsFiles(of pane: PaneExtension, languages: [String]) -> [URL] {
        guard let fileName = pane.termsFileName else { return [] }
        let resources = pane.bundleURL.appendingPathComponent("Contents/Resources")
        let available = ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
        guard !available.isEmpty else { return [] }

        var chosen: [String] = []
        for language in languages {
            // preferredLocalizations falls back to *some* localization when none fits, so
            // keep its pick only when it is the language asked for.
            guard let pick = Bundle.preferredLocalizations(from: available, forPreferences: [language]).first,
                  Locale(identifier: pick).language.languageCode == Locale(identifier: language).language.languageCode,
                  !chosen.contains(pick) else { continue }
            chosen.append(pick)
        }
        return chosen
            .map { resources.appendingPathComponent("\($0).lproj/\(fileName).searchTerms") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The entries of one `.searchTerms` file: `{section: {localizableStrings: [{title, index}]}}`.
    static func entries(inFile url: URL) -> [Entry] {
        guard let root = readPlist(url) as? [String: Any] else { return [] }
        var entries: [Entry] = []
        for (section, value) in root {
            guard let strings = (value as? [String: Any])?["localizableStrings"] as? [[String: Any]] else { continue }
            for string in strings {
                guard let title = (string["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
                let index = ((string["index"] as? String) ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                entries.append(Entry(section: section, title: title, index: index))
            }
        }
        return entries
    }

    static func buildIndex(for items: [SettingsItem], directories: [URL] = extensionDirectories, languages: [String] = preferredLanguages()) -> SettingsSearchIndex {
        let panes = paneExtensions(in: directories)
        var builder = SettingsSearchIndex.Builder()
        for (itemIndex, item) in items.enumerated() {
            guard let pane = panes[item.extensionID] else { continue }
            for (languageRank, file) in termsFiles(of: pane, languages: languages).enumerated() {
                for entry in entries(inFile: file) {
                    if let sections = item.termSections, !sections.contains(entry.section) { continue }
                    builder.add(entry, item: itemIndex, languageRank: languageRank)
                }
            }
        }
        return builder.build()
    }

    /// Lowercased and NFC, with the typography Apple's files use folded to what a
    /// keyboard types: "Wi‑Fi" is spelled with a non-breaking hyphen (U+2011).
    static func normalize(_ term: String) -> String {
        // Most terms are ASCII, and the Foundation calls below dominate the load time.
        if term.utf8.allSatisfy({ $0 < 0x80 }) {
            var folded = term.lowercased().trimmingCharacters(in: .whitespaces)
            folded.makeContiguousUTF8()
            return folded
        }
        var folded = term.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespaces)
        // Foundation hands back bridged strings; the keystroke path reads these as UTF-8.
        folded.makeContiguousUTF8()
        return folded
    }

    private static func readPlist(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }
}

// MARK: - Search Index

struct SettingsSearchIndex: Sendable {
    struct Match: Sendable {
        let score: Double
        /// The System Settings entry that matched, shown as the reason for the row.
        let title: String
        let languageRank: Int
    }

    /// An entry title names one setting, so matching it is nearly as good as a curated
    /// keyword. Index words are synonyms and are often generic ("show", "top", "word"):
    /// they list the pane, but at most 55, below the 60 a Top Hit needs.
    static let titleWeight = 0.9
    static let indexWeight = 0.55
    /// A single letter would list most panes on every first keystroke.
    static let minimumQueryLength = 2

    private struct Key: Sendable {
        /// Normalized text from a word start in a term to its end, so "shift" finds
        /// "night shift" and "legacy net" finds "show legacy networks".
        let text: String
        let item: Int
        let title: Int
        let isWholeTerm: Bool
        let isTitle: Bool
        /// Position of the term's language in `preferredLanguages()`; breaks ties.
        let languageRank: Int

        var weight: Double { isTitle ? SettingsSearchIndex.titleWeight : SettingsSearchIndex.indexWeight }
    }

    /// Sorted by UTF-8 bytes, so every key starting with a query is one contiguous run.
    private let keys: [Key]
    private let titles: [String]

    static let empty = SettingsSearchIndex(keys: [], titles: [])

    var keyCount: Int { keys.count }

    /// The best match per item, keyed by the item's position in the list the index was
    /// built for.
    func matches(for query: String) -> [Int: Match] {
        let q = query.utf8
        guard q.count >= Self.minimumQueryLength, !keys.isEmpty else { return [:] }

        var lo = 0
        var hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid].text.utf8.lexicographicallyPrecedes(q) {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        var best: [Int: Match] = [:]
        var i = lo
        while i < keys.count, keys[i].text.utf8.starts(with: q) {
            let key = keys[i]
            i += 1
            // The tiers FuzzyMatcher uses: exact, prefix, word-boundary prefix.
            let tier: Double = key.isWholeTerm ? (key.text.utf8.count == q.count ? 100 : 95) : 85
            let score = tier * key.weight
            if let current = best[key.item] {
                guard score > current.score || (score == current.score && key.languageRank < current.languageRank) else { continue }
            }
            best[key.item] = Match(score: score, title: titles[key.title], languageRank: key.languageRank)
        }
        return best
    }

    struct Builder {
        private var keys: [String: Key] = [:]
        private var titles: [String] = []
        private var titleIDs: [String: Int] = [:]

        mutating func add(_ entry: SettingsSearchTerms.Entry, item: Int, languageRank: Int = 0) {
            let title: Int
            if let known = titleIDs[entry.title] {
                title = known
            } else {
                title = titles.count
                titles.append(entry.title)
                titleIDs[entry.title] = title
            }
            addTerm(entry.title, item: item, title: title, isTitle: true, languageRank: languageRank)
            for word in entry.index {
                addTerm(word, item: item, title: title, isTitle: false, languageRank: languageRank)
            }
        }

        private mutating func addTerm(_ term: String, item: Int, title: Int, isTitle: Bool, languageRank: Int) {
            let text = SettingsSearchTerms.normalize(term)
            guard !text.isEmpty else { return }
            var start = text.startIndex
            var isWholeTerm = true
            while true {
                let suffix = String(text[start...])
                let key = Key(text: suffix, item: item, title: title, isWholeTerm: isWholeTerm, isTitle: isTitle, languageRank: languageRank)
                // One key per text and item: keep the one that scores higher, then the
                // one in the earlier language.
                let id = "\(item)\u{1F}\(suffix)"
                if let existing = keys[id] {
                    let (new, old) = (Self.rank(key), Self.rank(existing))
                    if new > old || (new == old && key.languageRank < existing.languageRank) { keys[id] = key }
                } else {
                    keys[id] = key
                }
                guard let space = text[start...].firstIndex(of: " ") else { break }
                start = text.index(after: space)
                while start < text.endIndex, text[start] == " " { start = text.index(after: start) }
                if start == text.endIndex { break }
                isWholeTerm = false
            }
        }

        private static func rank(_ key: Key) -> Double {
            (key.isWholeTerm ? 95 : 85) * key.weight
        }

        func build() -> SettingsSearchIndex {
            let sorted = keys.values.sorted { $0.text.utf8.lexicographicallyPrecedes($1.text.utf8) }
            return SettingsSearchIndex(keys: sorted, titles: titles)
        }
    }

    private init(keys: [Key], titles: [String]) {
        self.keys = keys
        self.titles = titles
    }
}
