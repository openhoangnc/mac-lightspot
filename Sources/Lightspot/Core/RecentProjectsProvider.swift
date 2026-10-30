import AppKit
import Foundation

// MARK: - Recent Project Model

public struct RecentProject: Sendable, Hashable {
    public let name: String
    public let path: String
    public let displayPath: String
    public let ideName: String
    public let ideBundleID: String?
    public let iconAppPath: String?
    public let recency: Double
    /// When the editor last had the folder open (seconds since 1970), where it records
    /// that. Unlike `recency`, a position in one editor's own list, it compares across
    /// editors, so it decides which editor a folder open in several belongs to.
    public let lastUsed: TimeInterval?

    public let lowercaseName: String
    public let nameTokens: [String]
    public let initials: String
    public let pathTokens: [String]

    public init(
        name: String,
        path: String,
        displayPath: String,
        ideName: String,
        ideBundleID: String?,
        iconAppPath: String?,
        recency: Double,
        lastUsed: TimeInterval? = nil
    ) {
        self.name = name
        self.path = path
        self.displayPath = displayPath
        self.ideName = ideName
        self.ideBundleID = ideBundleID
        self.iconAppPath = iconAppPath
        self.recency = recency
        self.lastUsed = lastUsed

        let lowerName = name.lowercased()
        self.lowercaseName = lowerName

        let separators = CharacterSet(charactersIn: "-_ .")
        let tokens = lowerName.components(separatedBy: separators).filter { !$0.isEmpty }
        self.nameTokens = tokens
        self.initials = String(tokens.compactMap { $0.first })

        let lowerPath = displayPath.lowercased()
        self.pathTokens = lowerPath
            .components(separatedBy: CharacterSet(charactersIn: "/~-_ ."))
            .filter { !$0.isEmpty }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    public static func == (lhs: RecentProject, rhs: RecentProject) -> Bool {
        lhs.path == rhs.path
    }
}

// MARK: - Recent Projects Provider

public final class RecentProjectsProvider: @unchecked Sendable {
    public static let shared = RecentProjectsProvider()

    public static let minimumScore: Double = 65.0
    public static let minimumQueryLength = 2
    public static let maxProjects = 75
    public static let maxResults = 8
    private static let maxRecencyBonus: Double = 4.5

    private let lock = NSLock()
    private var projects: [RecentProject] = []
    private var loadedSignature: String = ""
    private var isLoading = false

    private init() {}

    // MARK: - Public Lifecycle

    public func startLoading() {
        load(force: true)
    }

    public func refreshIfNeeded() {
        load(force: false)
    }

    public func reclaimMemory() {}

    public func projectCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return projects.count
    }

    public func allProjects() -> [RecentProject] {
        lock.lock()
        defer { lock.unlock() }
        return projects
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.trimmed.count < Self.minimumQueryLength { return [] }

        lock.lock()
        let items = projects
        lock.unlock()

        guard !items.isEmpty else { return [] }

        var scored: [(project: RecentProject, score: Double)] = []
        scored.reserveCapacity(items.count)

        for project in items {
            let baseScore = FuzzyMatcher.score(
                query: query,
                targetLower: project.lowercaseName,
                targetTokens: project.nameTokens,
                targetInitials: project.initials
            )

            var highestScore = baseScore

            // Fallback match on path tokens (weighted 0.85)
            if highestScore == nil {
                for token in project.pathTokens {
                    if let pScore = FuzzyMatcher.score(query: query, targetLower: token, targetTokens: [], targetInitials: nil) {
                        let weighted = pScore * 0.85
                        if let current = highestScore {
                            highestScore = max(current, weighted)
                        } else {
                            highestScore = weighted
                        }
                    }
                }
            }

            if let score = highestScore, score >= Self.minimumScore {
                let finalScore = min(score + project.recency * Self.maxRecencyBonus, 100.0)
                scored.append((project, finalScore))
            }
        }

        scored.sort { $0.score > $1.score }

        let topMatches = scored.prefix(Self.maxResults)
        return topMatches.map { match in
            let proj = match.project
            let iconType: ResultIconType
            if let appPath = proj.iconAppPath, !appPath.isEmpty {
                iconType = .app(path: appPath)
            } else {
                iconType = .systemSymbol(name: "folder.fill")
            }

            return SearchResult(
                id: "project-\(proj.path)",
                title: proj.name,
                subtitle: "\(proj.displayPath) · \(proj.ideName)",
                iconType: iconType,
                category: .recentProjects,
                score: match.score,
                action: .openProject(path: proj.path, appBundleID: proj.ideBundleID)
            )
        }
    }

    // MARK: - Loading & File Watch

    private func load(force: Bool) {
        lock.lock()
        if isLoading {
            lock.unlock()
            return
        }
        isLoading = true
        let previousSignature = loadedSignature
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.isLoading = false
                self.lock.unlock()
            }

            let currentSig = Self.currentSignature()
            if !force && !currentSig.isEmpty && currentSig == previousSignature {
                return
            }

            let loaded = Self.discoverAllProjects()

            self.lock.lock()
            self.projects = loaded
            self.loadedSignature = currentSig
            self.lock.unlock()
        }
    }

    private static func currentSignature() -> String {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var sig = ""

        // VS Code and Cursor: the recent list sits in globalStorage/state.vscdb, the Open
        // Recent menu's copy in storage.json, a folder's last use in workspaceStorage.
        for editor in vsCodeFamily {
            let user = "\(home)/Library/Application Support/\(editor.folder)/User"
            for file in ["globalStorage/storage.json", "globalStorage/state.vscdb", "globalStorage/state.vscdb-wal", "workspaceStorage"] {
                if let mtime = modificationTime("\(user)/\(file)") {
                    sig += "\(editor.folder):\(file):\(mtime);"
                }
            }
        }

        // Zed. New workspaces land in the WAL long before a checkpoint touches db.sqlite.
        for zed in zedDatabases(home: home) {
            for file in [zed.path, zed.path + "-wal"] {
                if let mtime = modificationTime(file) {
                    sig += "zed:\(file):\(mtime);"
                }
            }
        }

        // JetBrains (and Android Studio) options directories
        for root in jetBrainsConfigRoots(home: home) {
            guard let contents = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in contents {
                if let mtime = modificationTime("\(root)/\(item)/options/recentProjects.xml") {
                    sig += "jb-\(item):\(mtime);"
                }
            }
        }

        // Sublime Text: both session files of each version
        for session in sublimeInstalls.flatMap({ sublimeSessionFiles(home: home, folder: $0.folder) }) {
            if let mtime = modificationTime(session) {
                sig += "sublime:\(session):\(mtime);"
            }
        }

        return sig
    }

    private static func modificationTime(_ path: String) -> TimeInterval? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    // MARK: - Project Discovery

    public static func discoverAllProjects() -> [RecentProject] {
        var allFound: [RecentProject] = []
        let home = NSHomeDirectory()

        // 1-2. VS Code and Cursor
        for editor in vsCodeFamily {
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID)?.path
                ?? (FileManager.default.fileExists(atPath: editor.appPath) ? editor.appPath : nil)
            allFound.append(contentsOf: loadVSCodeFamilyProjects(
                userDir: "\(home)/Library/Application Support/\(editor.folder)/User",
                ideName: editor.name,
                ideBundleID: editor.bundleID,
                iconAppPath: app
            ))
        }

        // 3. Zed (stable, preview and nightly keep separate databases)
        for zed in zedDatabases(home: home) {
            let zedApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: zed.bundleID)?.path
            allFound.append(contentsOf: loadZedProjects(dbPath: zed.path, ideName: zed.name, ideBundleID: zed.bundleID, iconAppPath: zedApp))
        }

        // 4. JetBrains Suite
        allFound.append(contentsOf: loadJetBrainsProjects())

        // 5. Sublime Text (4 and 3 keep separate data folders)
        for sublime in sublimeInstalls {
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sublime.bundleID)?.path
            allFound.append(contentsOf: loadSublimeProjects(
                sessionPaths: sublimeSessionFiles(home: home, folder: sublime.folder),
                ideBundleID: sublime.bundleID,
                iconAppPath: app
            ))
        }

        // Deduplicate by path, keeping the editor that had the folder open last
        var unique: [String: RecentProject] = [:]
        for proj in allFound {
            if let existing = unique[proj.path] {
                if isMoreRecent(proj, than: existing) {
                    unique[proj.path] = proj
                }
            } else {
                unique[proj.path] = proj
            }
        }

        var result = Array(unique.values)
        result.sort { $0.recency > $1.recency }
        return Array(result.prefix(maxProjects))
    }

    /// By the date each editor recorded when both have one, else by position in each list.
    static func isMoreRecent(_ project: RecentProject, than other: RecentProject) -> Bool {
        if let mine = project.lastUsed, let theirs = other.lastUsed, mine != theirs {
            return mine > theirs
        }
        return project.recency > other.recency
    }

    // MARK: - Shared Helpers

    /// Builds the projects of one editor from its paths, most recent first: the first
    /// occurrence of a path wins, and only folders that still exist are kept.
    static func makeProjects(
        _ paths: [String],
        lastUsed: [String: TimeInterval] = [:],
        ideName: String,
        ideBundleID: String?,
        iconAppPath: String?
    ) -> [RecentProject] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var seen = Set<String>()
        var kept: [String] = []

        for rawPath in paths where rawPath.hasPrefix("/") && !seen.contains(rawPath) {
            seen.insert(rawPath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rawPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = URL(fileURLWithPath: rawPath).lastPathComponent
            guard !name.isEmpty && name != "/" else { continue }
            kept.append(rawPath)
        }

        let total = Double(max(kept.count, 1))
        return kept.enumerated().map { idx, rawPath in
            RecentProject(
                name: URL(fileURLWithPath: rawPath).lastPathComponent,
                path: rawPath,
                displayPath: rawPath.hasPrefix(home) ? "~" + rawPath.dropFirst(home.count) : rawPath,
                ideName: ideName,
                ideBundleID: ideBundleID,
                iconAppPath: iconAppPath,
                recency: 1.0 - (Double(idx) / total),
                lastUsed: lastUsed[rawPath]
            )
        }
    }

    /// Runs one query against another app's SQLite database without getting in its way.
    /// With a WAL beside it, the database opens read-only (`mode=ro`), which reads the WAL:
    /// `immutable=1` skips it, and with it everything written since the last checkpoint
    /// (Zed's newest workspaces). Without one, `immutable=1` takes no lock, so an app
    /// writing through a rollback journal (VS Code) never finds its database busy.
    static func querySQLite(dbPath: String, sql: String) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dbPath) else { return nil }
        let mode = fm.fileExists(atPath: dbPath + "-wal") ? "mode=ro" : "immutable=1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["file:\(dbPath)?\(mode)", sql]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - VS Code Family Parser (VS Code & Cursor)

    /// Editors laid out as VS Code is, under `Application Support/<folder>/User`.
    static let vsCodeFamily: [(folder: String, name: String, bundleID: String, appPath: String)] = [
        ("Code", "VS Code", "com.microsoft.VSCode", "/Applications/Visual Studio Code.app"),
        ("Cursor", "Cursor", "com.todesktop.230313mzl4w4u92", "/Applications/Cursor.app"),
    ]

    /// Most recent first, from four places in order:
    /// 1. `history.recentlyOpenedPathsList` in `globalStorage/state.vscdb`, the editor's
    ///    own recent list (`storage.json` held it as `openedPathsList` before 1.5x);
    /// 2. the File ▸ Open Recent menu cached in `storage.json`, its top entries;
    /// 3. `workspaceStorage/*/workspace.json`, by when the folder's `state.vscdb` was last
    ///    written, i.e. last open, which covers folders the list has dropped;
    /// 4. `profileAssociations`, every folder ever opened, but a dictionary, so in no order.
    public static func loadVSCodeFamilyProjects(
        userDir: String,
        ideName: String,
        ideBundleID: String,
        iconAppPath: String?
    ) -> [RecentProject] {
        var paths: [String] = []

        if let raw = querySQLite(
            dbPath: "\(userDir)/globalStorage/state.vscdb",
            sql: "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList';"
        ), let data = raw.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            paths += recentListFolders(list)
        }

        let storage = (try? Data(contentsOf: URL(fileURLWithPath: "\(userDir)/globalStorage/storage.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let legacyList = storage["openedPathsList"] as? [String: Any] {
            paths += recentListFolders(legacyList)
        }
        paths += menubarRecentFolders(storage)
        let opened = workspaceStorageFolders("\(userDir)/workspaceStorage")
        paths += opened.map(\.path)
        if let profileAssoc = storage["profileAssociations"] as? [String: Any],
           let workspaces = profileAssoc["workspaces"] as? [String: Any] {
            paths += workspaces.keys.sorted().compactMap(decodeURIPath)
        }

        // Sorted newest first, so a folder with several storage folders keeps its latest.
        var lastUsed: [String: TimeInterval] = [:]
        for folder in opened where lastUsed[folder.path] == nil {
            lastUsed[folder.path] = folder.time
        }
        return makeProjects(paths, lastUsed: lastUsed, ideName: ideName, ideBundleID: ideBundleID, iconAppPath: iconAppPath)
    }

    /// The folders of a recent list (`{"entries": [{"folderUri": …}, {"fileUri": …}, …]}`).
    static func recentListFolders(_ list: [String: Any]) -> [String] {
        guard let entries = list["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry["remoteAuthority"] == nil, let uri = entry["folderUri"] as? String else { return nil }
            return decodeURIPath(uri)
        }
    }

    static func menubarRecentFolders(_ storage: [String: Any]) -> [String] {
        guard let menubar = storage["lastKnownMenubarData"] as? [String: Any],
              let menus = menubar["menus"] as? [String: Any],
              let fileMenu = menus["File"] as? [String: Any],
              let items = fileMenu["items"] as? [[String: Any]],
              let recent = items.first(where: { ($0["id"] as? String) == "submenuitem.MenubarRecentMenu" }),
              let submenu = recent["submenu"] as? [String: Any],
              let subItems = submenu["items"] as? [[String: Any]] else {
            return []
        }
        return subItems.compactMap { item in
            guard (item["id"] as? String) == "openRecentFolder",
                  let uri = item["uri"] as? [String: Any],
                  (uri["scheme"] as? String ?? "file") == "file",
                  let path = uri["path"] as? String,
                  !path.hasSuffix(".git") else { return nil }
            return path
        }
    }

    static func workspaceStorageFolders(_ dir: String) -> [(path: String, time: TimeInterval)] {
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var dated: [(path: String, time: TimeInterval)] = []
        for subdir in subdirs {
            let folder = "\(dir)/\(subdir)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: "\(folder)/workspace.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uri = json["folder"] as? String,
                  let path = decodeURIPath(uri) else { continue }
            let time = modificationTime("\(folder)/state.vscdb") ?? modificationTime("\(folder)/workspace.json") ?? 0
            dated.append((path, time))
        }
        return dated.sorted { $0.time > $1.time }
    }

    private static func decodeURIPath(_ uriString: String) -> String? {
        if uriString.hasPrefix("file://") {
            if let url = URL(string: uriString) {
                let path = url.path
                return path.hasSuffix(".git") ? nil : path
            }
        } else if uriString.hasPrefix("/") {
            return uriString.hasSuffix(".git") ? nil : uriString
        }
        return nil
    }

    // MARK: - Zed Parser

    /// Zed's database per release channel: `db/<scope>-<channel>/db.sqlite`, where the
    /// scope is `0` unless Zed was started with a custom data directory. `0-global` holds
    /// app-wide state, no workspaces.
    static let zedChannels: [(folder: String, name: String, bundleID: String)] = [
        ("0-stable", "Zed", "dev.zed.Zed"),
        ("0-preview", "Zed Preview", "dev.zed.Zed-Preview"),
        ("0-nightly", "Zed Nightly", "dev.zed.Zed-Nightly"),
    ]

    static func zedDatabases(home: String) -> [(path: String, name: String, bundleID: String)] {
        let root = "\(home)/Library/Application Support/Zed/db"
        return zedChannels.compactMap { channel in
            let path = "\(root)/\(channel.folder)/db.sqlite"
            return FileManager.default.fileExists(atPath: path) ? (path, channel.name, channel.bundleID) : nil
        }
    }

    public static func loadZedProjects(dbPath: String, ideName: String = "Zed", ideBundleID: String = "dev.zed.Zed", iconAppPath: String?) -> [RecentProject] {
        // `paths` is the workspace's folders, one per line, so each row comes back as its
        // UTC timestamp in epoch seconds and its folders, tab-separated. A remote
        // workspace names paths on another host.
        guard let output = querySQLite(
            dbPath: dbPath,
            sql: """
            SELECT strftime('%s', timestamp) || char(9) || replace(paths, char(10), char(9)) FROM workspaces \
            WHERE remote_connection_id IS NULL AND paths != '' ORDER BY timestamp DESC;
            """
        ) else { return [] }

        var paths: [String] = []
        var lastUsed: [String: TimeInterval] = [:]
        for row in output.components(separatedBy: .newlines) {
            let fields = row.components(separatedBy: "\t")
            guard fields.count > 1, let time = TimeInterval(fields[0]) else { continue }
            for path in fields.dropFirst() where !path.isEmpty {
                paths.append(path)
                if lastUsed[path] == nil { lastUsed[path] = time }
            }
        }
        return makeProjects(paths, lastUsed: lastUsed, ideName: ideName, ideBundleID: ideBundleID, iconAppPath: iconAppPath)
    }

    // MARK: - JetBrains Parser

    public static func loadJetBrainsProjects() -> [RecentProject] {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // (root, config folder) pairs. The Google root also holds Chrome and friends,
        // so only folders naming a known product are read from it.
        var folders: [(root: String, item: String)] = []
        for root in jetBrainsConfigRoots(home: home) {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            let isJetBrainsRoot = root.hasSuffix("/JetBrains")
            for item in items where isJetBrainsRoot || jetBrainsProduct(forFolder: item) != nil {
                folders.append((root, item))
            }
        }

        var results: [RecentProject] = []
        for (root, item) in folders {
            guard let data = fm.contents(atPath: "\(root)/\(item)/options/recentProjects.xml") else { continue }

            // Determine JetBrains product display name and the bundle ID actually installed
            let product = jetBrainsProduct(forFolder: item)
            let bundleID = product.flatMap { resolveInstalledBundleID($0.bundleIDs) }
            let appPath = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }

            let recent = parseJetBrainsRecentProjects(data, home: home)
            var lastUsed: [String: TimeInterval] = [:]
            for project in recent {
                lastUsed[project.path] = project.lastUsed
            }
            results += makeProjects(
                recent.map(\.path),
                lastUsed: lastUsed,
                ideName: product?.name ?? "JetBrains",
                ideBundleID: bundleID,
                iconAppPath: appPath
            )
        }
        return results
    }

    /// The projects in a `recentProjects.xml`, most recent first. They are the keys of the
    /// `additionalInfo` map; opening a project moves its entry to the end, and the IDE lists
    /// the map reversed, leaving out entries marked hidden
    /// (`RecentProjectsManagerBase.markPathRecent` / `getRecentPaths`). Last used is the
    /// later of `activationTimestamp` and `projectOpenTimestamp` (milliseconds).
    static func parseJetBrainsRecentProjects(_ data: Data, home: String) -> [(path: String, lastUsed: TimeInterval?)] {
        let delegate = JetBrainsRecentProjectsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.entries.reversed().map { entry in
            (entry.key.replacingOccurrences(of: "$USER_HOME$", with: home), entry.timestamp.map { $0 / 1000 })
        }
    }

    /// An IntelliJ-platform IDE, identified by the prefix of its per-version config
    /// folder (`PyCharmCE2024.1` → `pycharmce`).
    public struct JetBrainsProduct: Equatable, Sendable {
        public let name: String
        /// Stable-build bundle IDs in preference order. A config folder does not say
        /// which edition is installed — since 2025.1 IntelliJ IDEA and PyCharm ship as
        /// one app that reads the old Ultimate/Professional folders — so the first
        /// installed candidate wins (see `resolveInstalledBundleID`).
        public let bundleIDs: [String]
    }

    /// Keyed by `jetBrainsFolderPrefix`. Bundle IDs and folder names are the ones the
    /// Homebrew casks record; note the mixed case (`WebStorm`, `CLion`, `PhpStorm`).
    static let jetBrainsProducts: [String: JetBrainsProduct] = [
        "intellijidea": JetBrainsProduct(name: "IntelliJ IDEA", bundleIDs: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]),
        "ideaic": JetBrainsProduct(name: "IntelliJ IDEA CE", bundleIDs: ["com.jetbrains.intellij.ce", "com.jetbrains.intellij"]),
        "pycharm": JetBrainsProduct(name: "PyCharm", bundleIDs: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]),
        "pycharmce": JetBrainsProduct(name: "PyCharm CE", bundleIDs: ["com.jetbrains.pycharm.ce", "com.jetbrains.pycharm"]),
        "webstorm": JetBrainsProduct(name: "WebStorm", bundleIDs: ["com.jetbrains.WebStorm"]),
        "goland": JetBrainsProduct(name: "GoLand", bundleIDs: ["com.jetbrains.goland"]),
        "clion": JetBrainsProduct(name: "CLion", bundleIDs: ["com.jetbrains.CLion"]),
        "rustrover": JetBrainsProduct(name: "RustRover", bundleIDs: ["com.jetbrains.rustrover"]),
        "rider": JetBrainsProduct(name: "Rider", bundleIDs: ["com.jetbrains.rider"]),
        "phpstorm": JetBrainsProduct(name: "PhpStorm", bundleIDs: ["com.jetbrains.PhpStorm"]),
        "datagrip": JetBrainsProduct(name: "DataGrip", bundleIDs: ["com.jetbrains.datagrip"]),
        "rubymine": JetBrainsProduct(name: "RubyMine", bundleIDs: ["com.jetbrains.rubymine"]),
        "dataspell": JetBrainsProduct(name: "DataSpell", bundleIDs: ["com.jetbrains.dataspell"]),
        "androidstudio": JetBrainsProduct(name: "Android Studio", bundleIDs: ["com.google.android.studio"]),
        "androidstudiopreview": JetBrainsProduct(name: "Android Studio Preview", bundleIDs: ["com.google.android.studio-EAP", "com.google.android.studio"]),
    ]

    /// Where IntelliJ-platform IDEs keep their per-version config folders. Android
    /// Studio is built on the same platform but files them under Google.
    static func jetBrainsConfigRoots(home: String) -> [String] {
        [
            "\(home)/Library/Application Support/JetBrains",
            "\(home)/Library/Application Support/Google",
        ]
    }

    /// The product part of a config folder name, lowercased: the letters before the
    /// version (`IntelliJIdea2024.3` → `intellijidea`, `AndroidStudio2026.2.1` →
    /// `androidstudio`).
    static func jetBrainsFolderPrefix(_ folderName: String) -> String {
        String(folderName.prefix { $0.isLetter }).lowercased()
    }

    public static func jetBrainsProduct(forFolder folderName: String) -> JetBrainsProduct? {
        jetBrainsProducts[jetBrainsFolderPrefix(folderName)]
    }

    /// The first of `bundleIDs` that is installed, trying each one's EAP build
    /// (`<id>-EAP`) after the stable ones. nil when none is, so ↵ falls back to the
    /// default opener instead of naming an IDE that is not there.
    static func resolveInstalledBundleID(
        _ bundleIDs: [String],
        isInstalled: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) -> String? {
        let candidates = bundleIDs + bundleIDs.map { "\($0)-EAP" }
        return candidates.first(where: isInstalled)
    }

    // MARK: - Sublime Text Parser

    static let sublimeInstalls: [(folder: String, bundleID: String)] = [
        ("Sublime Text", "com.sublimetext.4"),
        ("Sublime Text 3", "com.sublimetext.3"),
    ]

    /// Sublime Text writes `Session.sublime_session` when it quits and
    /// `Auto Save Session.sublime_session` while it runs (hot exit), so the newer one is
    /// current. Newest first.
    static func sublimeSessionFiles(home: String, folder: String) -> [String] {
        let local = "\(home)/Library/Application Support/\(folder)/Local"
        return ["Auto Save Session.sublime_session", "Session.sublime_session"]
            .map { "\(local)/\($0)" }
            .compactMap { path in modificationTime(path).map { (path, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    public static func loadSublimeProjects(sessionPaths: [String], ideBundleID: String, iconAppPath: String?) -> [RecentProject] {
        let paths = sessionPaths.flatMap { path -> [String] in
            guard let data = FileManager.default.contents(atPath: path) else { return [] }
            return parseSublimeSession(data)
        }
        return makeProjects(paths, ideName: "Sublime Text", ideBundleID: ideBundleID, iconAppPath: iconAppPath)
    }

    /// `workspaces.recent_workspaces` lists `.sublime-workspace` files, each beside its
    /// project, and `folder_history` the folders opened without one; both most recent first.
    static func parseSublimeSession(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var paths: [String] = []

        if let workspaces = json["workspaces"] as? [String: Any],
           let recent = workspaces["recent_workspaces"] as? [String] {
            for item in recent {
                if item.hasSuffix(".sublime-workspace") || item.hasSuffix(".sublime-project") {
                    paths.append(URL(fileURLWithPath: item).deletingLastPathComponent().path)
                } else {
                    paths.append(item)
                }
            }
        }

        if let folderHistory = json["folder_history"] as? [String] {
            paths.append(contentsOf: folderHistory)
        }
        return paths
    }
}

/// Collects the keys of `<option name="additionalInfo"><map><entry key="…">` in document
/// order, with their newest timestamp, skipping entries marked hidden.
private final class JetBrainsRecentProjectsParser: NSObject, XMLParserDelegate {
    private(set) var entries: [(key: String, timestamp: TimeInterval?)] = []
    private var stack: [(element: String, optionName: String?)] = []
    private var entry: (key: String, depth: Int, hidden: Bool, timestamp: TimeInterval?)?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        if entry == nil, elementName == "entry", let key = attributes["key"],
           stack.count >= 2, stack[stack.count - 1].element == "map",
           stack[stack.count - 2].optionName == "additionalInfo" {
            entry = (key, stack.count, false, nil)
        } else if let current = entry {
            let name = elementName == "option" ? attributes["name"] : nil
            if (name == "hidden" && attributes["value"] == "true")
                || (elementName == "RecentProjectMetaInfo" && attributes["hidden"] == "true") {
                entry?.hidden = true
            }
            if name == "activationTimestamp" || name == "projectOpenTimestamp",
               let value = attributes["value"].flatMap(TimeInterval.init) {
                entry?.timestamp = max(current.timestamp ?? 0, value)
            }
        }
        stack.append((elementName, elementName == "option" ? attributes["name"] : nil))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        stack.removeLast()
        if let current = entry, stack.count == current.depth {
            if !current.hidden { entries.append((current.key, current.timestamp)) }
            entry = nil
        }
    }
}
