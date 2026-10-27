import Foundation

// MARK: - cdm Rules
//
// CleanDevMac (cdm, https://github.com/cleandevmac/cdm) keeps what it cleans in JSON, not
// in code: `rules/index.json` lists the pattern files, and each pattern file contributes
// categories (`icon`, `name`, `desc`, `method`, `default`, `paths`, optionally `procs`).
// Lightspot reads the same files, so a rule added to cdm reaches both tools. The cache
// categories and cdm's per-repo project scan run natively; Docker / Podman, Rust
// toolchains and their offline docs, and orphaned app data stay with cdm itself, one ⌘↵
// away in a terminal.

/// One category of a cdm pattern file that Lightspot can clean on its own.
struct CleanDevMacRule: Sendable, Equatable {
    enum Kind: String, Sendable {
        case paths
        /// Android system images: the candidates come from `images`, minus every image an
        /// AVD still boots from. cdm keeps them out of `paths` so that an interpreter that
        /// does not know this kind offers nothing rather than every image.
        case androidImages = "android-images"
        /// The system images, from `images`, that only AVDs idle for `idleDays` boot: one
        /// row each, naming the AVDs that would no longer boot.
        case androidIdleImages = "android-idle-images"
        /// Each `candidates` glob is a family of versions (build-tools/*); all but the
        /// newest of each are offered.
        case olderVersions = "older-versions"
        /// Claude Code sessions, in the project folders `candidates` names, untouched for
        /// `idleDays`: always to the Trash and never ticked, whatever the rule says.
        case claudeTranscripts = "claude-transcripts"
        /// The copies of its app bundle a Chromium browser clones at every launch and
        /// leaves behind when it is killed, matched by `candidates` in the user folder's X:
        /// never one a running copy of the app may use, sized by what the copies alone hold.
        case codeSignClones = "code-sign-clones"
        /// One code repo's junk, found by the repo scan. Never read from a rule file: cdm's
        /// `project` and `gitignore` categories become `CleanDevMacProjectRules` instead.
        case project
    }

    enum Method: String, Sendable {
        /// Delete permanently; the target regenerates.
        case rm
        /// Make the tree writable first (Go module cache, Cargo sources), then delete.
        case rmforce
        /// Move to the Trash, where it can be restored.
        case trash
        /// Permanently erase what is already in the Trash.
        case emptytrash

        var isPermanent: Bool { self != .trash }
    }

    let kind: Kind
    let icon: String
    let name: String
    let desc: String
    let method: Method
    /// Pre-selected: the rule's `default`. A true one costs a rebuild or a small re-download.
    let isDefault: Bool
    /// `~` and `*` patterns, or ones starting with `@cache/`, `@temp/` or `@boot-temp/` for
    /// the user folder's C, T and X: the rule's `paths`, its `images` for the Android image
    /// kinds, or its `candidates` for `.olderVersions`, `.claudeTranscripts` and
    /// `.codeSignClones`.
    let patterns: [String]
    /// Process names of the apps that rewrite this category's caches while they run.
    let procs: [String]
    /// The age in days the idle kinds go by (`idleDays`); nil for every other kind.
    var idleDays: Int? = nil
}

/// What cdm's repo scan looks for (`scan` plus its `project` and `gitignore` categories):
/// git repos under `roots`, directories named in `dirs`, and, with `gitignoreMethod`, every
/// other file a repo ignores.
struct CleanDevMacProjectRules: Sendable, Equatable {
    struct JunkName: Sendable, Equatable {
        let name: String
        let method: CleanDevMacRule.Method
    }

    var roots: [String] = []
    /// Names never descended into (`Library`, `.npm`, `vendor`…), wherever they are.
    var prune: [String] = []
    /// Folders whose repos collapse into one row each (an AI agent's session store).
    var groups: [String] = []
    /// cdm's own defaults until a rule file sets them.
    var maxDepth = 8
    var maxRepos = 400
    /// Regenerable directory names, first category first, with the method each maps to.
    var dirs: [JunkName] = []
    /// The method for any other git-ignored entry; nil without a `gitignore` category.
    var gitignoreMethod: CleanDevMacRule.Method?
    /// The categories' names, for the note when the scan cannot run.
    var categoryNames: [String] = []

    var isEmpty: Bool { roots.isEmpty || (dirs.isEmpty && gitignoreMethod == nil) }

    /// cdm's `classify_method`: the method a known regenerable name maps to.
    func method(forName name: String) -> CleanDevMacRule.Method? {
        dirs.first { $0.name == name }?.method
    }
}

/// Every rule Lightspot loaded, and where from.
struct CleanDevMacRuleSet: Sendable, Equatable {
    enum Source: String, Sendable {
        /// `~/.cleandevmac/rules`, the folder cdm itself reads before going online.
        case local
        /// cdm's live rules on GitHub, which piped `cdm` runs read too.
        case remote
        /// The copy shipped inside Lightspot.app, for when GitHub cannot be reached.
        case bundled

        var displayName: String {
            switch self {
            case .local: return "~/.cleandevmac/rules"
            case .remote: return "cdm on GitHub"
            case .bundled: return "built-in copy"
            }
        }
    }

    let rules: [CleanDevMacRule]
    /// Categories only cdm itself cleans (Docker / Podman, Rust toolchains and offline docs,
    /// orphaned app data). They are named in the cleaner and handed to the terminal, never
    /// run here.
    let terminalOnly: [String]
    var projects = CleanDevMacProjectRules()
    let source: Source
}

enum CleanDevMacRules {
    /// cdm's `REMOTE_BASE`.
    static let remoteBase = URL(string: "https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/")!
    static let remoteHost = "raw.githubusercontent.com"
    static let indexFileName = "index.json"
    /// cdm's rule files are ~15 KB each; anything this large is not one.
    static let maxFileBytes = 2 * 1024 * 1024
    static let maxPatternFiles = 32

    /// The kinds only cdm runs, because their clean is a command rather than a file
    /// operation: a container engine's prune, `rustup toolchain uninstall`, and
    /// `rustup component remove rust-docs`.
    static let terminalOnlyKinds: Set<String> = ["container", "rust-toolchains", "rust-docs"]

    /// Ephemeral, like every other request Lightspot makes (invariant 12): nothing of the
    /// fetch lands in `~/Library/Caches` or `~/Library/HTTPStorages`.
    static let session = URLSession(configuration: .ephemeral)

    /// cdm's own local rules folder, which overrides the network for cdm and so here too.
    static func localDirectory(home: String) -> URL {
        URL(fileURLWithPath: home + "/.cleandevmac/rules", isDirectory: true)
    }

    /// `Contents/Resources/cdm-rules`, copied there by build.sh from `Resources/cdm-rules`.
    static var bundledDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("cdm-rules", isDirectory: true)
    }

    // MARK: Parsing

    /// The names a file in index.json may have. Each one is joined onto a folder or onto
    /// `remoteBase`, so it has to be a bare `*.json` name: no separator, no `..`, nothing
    /// hidden. cdm joins whatever the index says; a rule file has no business naming
    /// anything else, so the names are checked here.
    static func isSafeFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".json"), name.count > ".json".count, !name.hasPrefix("."),
              !name.contains(".."), name.utf8.count <= 128 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    /// The pattern files index.json lists (`patternFiles`), in order. nil when it is not
    /// JSON; names that fail `isSafeFileName` are dropped.
    static func patternFileNames(fromIndex data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let names = (object["patternFiles"] as? [Any] ?? []).compactMap { $0 as? String }.filter(isSafeFileName)
        return Array(names.prefix(maxPatternFiles))
    }

    /// Whether index.json names an orphan config: cdm's orphaned-app-data scan, which
    /// only cdm runs.
    static func indexHasOrphanConfig(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["orphanConfig"] as? String).map { !$0.isEmpty } ?? false
    }

    struct PatternFile {
        var rules: [CleanDevMacRule] = []
        var terminalOnly: [String] = []
        var projects = CleanDevMacProjectRules()
        /// Set only when the file's `scan` names them, so a later file can override.
        var maxDepth: Int?
        var maxRepos: Int?
    }

    /// One pattern file, read the way cdm's JXA parser reads it: a missing `kind` is
    /// `paths`, a missing `method` is `rm`, `default` is false unless set. nil when the
    /// file is not a JSON object.
    ///
    /// A category whose method cdm would not act on is left out rather than offered: cdm
    /// deletes nothing for a method it does not know, and listing one here would promise
    /// a clean that never happens. An unknown `kind` is read as `paths`, as cdm reads it;
    /// cdm's rule format keeps a new kind's candidates in a field of their own for exactly
    /// that reason.
    static func parsePatternFile(_ data: Data) -> PatternFile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var file = PatternFile()
        if let scan = object["scan"] as? [String: Any] {
            file.projects.roots = strings(scan["roots"])
            file.projects.prune = strings(scan["prune"])
            file.projects.groups = strings(scan["groups"])
            // cdm reads any value and falls back to 6 and 400 for one that is not a number.
            if scan["maxDepth"] != nil { file.maxDepth = positiveInt(scan["maxDepth"]) ?? 6 }
            if scan["maxRepos"] != nil { file.maxRepos = positiveInt(scan["maxRepos"]) ?? 400 }
        }
        for category in object["categories"] as? [[String: Any]] ?? [] {
            let kindName = category["kind"] as? String ?? "paths"
            let name = category["name"] as? String ?? ""
            if terminalOnlyKinds.contains(kindName) {
                if !name.isEmpty { file.terminalOnly.append(name) }
                continue
            }
            guard let method = CleanDevMacRule.Method(rawValue: category["method"] as? String ?? "rm") else { continue }
            if kindName == "project" {
                // A name with a find wildcard could match more than it says: cdm skips it.
                let dirs = strings(category["dirs"]).filter { !$0.contains(where: { "*?[".contains($0) }) }
                file.projects.dirs += dirs.map { CleanDevMacProjectRules.JunkName(name: $0, method: method) }
                if !name.isEmpty { file.projects.categoryNames.append(name) }
                continue
            }
            if kindName == "gitignore" {
                file.projects.gitignoreMethod = method
                if !name.isEmpty { file.projects.categoryNames.append(name) }
                continue
            }
            let kind = CleanDevMacRule.Kind(rawValue: kindName).flatMap { $0 == .project ? nil : $0 } ?? .paths
            let patterns = strings(category[patternField(kind)])
            guard !patterns.isEmpty else { continue }
            // The idle kinds go by an age; without a usable one cdm offers nothing for them.
            var idleDays: Int?
            if kind == .androidIdleImages || kind == .claudeTranscripts {
                guard let days = dayCount(category["idleDays"]) else { continue }
                idleDays = days
            }
            // A transcript is the one record of a conversation: cdm only ever moves it to
            // the Trash, and never ticks it, whatever the rule says.
            let transcripts = kind == .claudeTranscripts
            file.rules.append(CleanDevMacRule(
                kind: kind,
                icon: category["icon"] as? String ?? "",
                name: name,
                desc: category["desc"] as? String ?? "",
                method: transcripts ? .trash : method,
                isDefault: transcripts ? false : category["default"] as? Bool ?? false,
                patterns: patterns,
                procs: strings(category["procs"]),
                idleDays: idleDays
            ))
        }
        return file
    }

    /// Where a kind's patterns live. A kind that works out its offer keeps them out of
    /// `paths`, so an interpreter that does not know it offers nothing.
    static func patternField(_ kind: CleanDevMacRule.Kind) -> String {
        switch kind {
        case .androidImages, .androidIdleImages: return "images"
        case .olderVersions, .claudeTranscripts, .codeSignClones: return "candidates"
        case .paths, .project: return "paths"
        }
    }

    /// `idleDays` as cdm reads it: a whole number of days, 0 or more, written as a number
    /// or as a string of digits; nil for anything else.
    private static func dayCount(_ value: Any?) -> Int? {
        if let text = value as? String {
            guard !text.isEmpty, text.utf8.count <= 9, text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            return Int(text)
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded(), number.doubleValue >= 0,
              number.doubleValue < 1_000_000_000 else { return nil }
        return number.intValue
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, number.doubleValue == number.doubleValue.rounded(),
              number.intValue > 0, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.intValue
    }

    /// Assembles a rule set from fetched or read files, in index order. Files that are
    /// missing or not JSON are skipped, as cdm skips them; with none parsed at all the
    /// answer is nil, because a load failure must not look like a clean Mac.
    static func ruleSet(index: Data, files: [String: Data], source: CleanDevMacRuleSet.Source) -> CleanDevMacRuleSet? {
        guard let names = patternFileNames(fromIndex: index) else { return nil }
        var rules: [CleanDevMacRule] = []
        var terminalOnly: [String] = []
        var projects = CleanDevMacProjectRules()
        var parsed = 0
        for name in names {
            guard let data = files[name], let file = parsePatternFile(data) else { continue }
            parsed += 1
            rules.append(contentsOf: file.rules)
            terminalOnly.append(contentsOf: file.terminalOnly)
            // cdm keeps one scan config across files: lists add up, numbers are replaced.
            projects.roots += file.projects.roots
            projects.prune += file.projects.prune
            projects.groups += file.projects.groups
            projects.dirs += file.projects.dirs
            projects.categoryNames += file.projects.categoryNames
            if let maxDepth = file.maxDepth { projects.maxDepth = maxDepth }
            if let maxRepos = file.maxRepos { projects.maxRepos = maxRepos }
            if let method = file.projects.gitignoreMethod { projects.gitignoreMethod = method }
        }
        guard parsed > 0 else { return nil }
        if indexHasOrphanConfig(index) { terminalOnly.append("Orphaned app data") }
        return CleanDevMacRuleSet(rules: rules, terminalOnly: terminalOnly, projects: projects, source: source)
    }

    // MARK: Loading

    /// Blocking: index.json and the files it lists, from a local folder.
    static func load(directory: URL, source: CleanDevMacRuleSet.Source) -> CleanDevMacRuleSet? {
        guard let index = readFile(directory.appendingPathComponent(indexFileName)),
              let names = patternFileNames(fromIndex: index) else { return nil }
        var files: [String: Data] = [:]
        for name in names {
            files[name] = readFile(directory.appendingPathComponent(name))
        }
        return ruleSet(index: index, files: files, source: source)
    }

    private static func readFile(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= maxFileBytes else { return nil }
        return data
    }

    /// HTTPS to GitHub's raw host and nowhere else, checked before the request and again
    /// on the URL that answered, after any redirect.
    static func isAllowedRemoteURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == remoteHost
    }

    /// Fetches index.json and every file it lists from cdm's GitHub. Calls back once, on a
    /// background queue, with nil if anything failed: a partial set would quietly drop
    /// categories, and the bundled copy is complete.
    static func fetchRemote(base: URL = remoteBase, completion: @escaping @Sendable (CleanDevMacRuleSet?) -> Void) {
        fetch(base.appendingPathComponent(indexFileName)) { index in
            guard let index, let names = patternFileNames(fromIndex: index), !names.isEmpty else {
                completion(nil)
                return
            }
            let files = FetchedFiles()
            let group = DispatchGroup()
            for name in names {
                group.enter()
                fetch(base.appendingPathComponent(name)) { data in
                    if let data { files.set(name, data) }
                    group.leave()
                }
            }
            group.notify(queue: .global(qos: .userInitiated)) {
                let fetched = files.all
                guard fetched.count == names.count else {
                    completion(nil)
                    return
                }
                completion(ruleSet(index: index, files: fetched, source: .remote))
            }
        }
    }

    private static func fetch(_ url: URL, completion: @escaping @Sendable (Data?) -> Void) {
        guard isAllowedRemoteURL(url) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let answeredURL = http.url, isAllowedRemoteURL(answeredURL),
                  let data, data.count <= maxFileBytes else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

    private final class FetchedFiles: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String: Data] = [:]

        func set(_ name: String, _ data: Data) {
            lock.lock()
            files[name] = data
            lock.unlock()
        }

        var all: [String: Data] {
            lock.lock()
            defer { lock.unlock() }
            return files
        }
    }
}
