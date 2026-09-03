import AppKit
import Foundation

// MARK: - VS Code Project Model

struct VSCodeProject: Sendable, Hashable {
    let name: String
    let path: String
    let displayPath: String
    let lowercaseName: String
    let nameTokens: [String]
    let initials: String
    let pathTokens: [String]
    let recency: Double

    init(name: String, path: String, displayPath: String, recency: Double) {
        self.name = name
        self.path = path
        self.displayPath = displayPath
        self.recency = recency

        let lowerName = name.lowercased()
        self.lowercaseName = lowerName

        // Split on hyphens, underscores, dots, and whitespace
        let separators = CharacterSet(charactersIn: "-_ .")
        let tokens = lowerName
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        self.nameTokens = tokens
        self.initials = String(tokens.compactMap { $0.first })

        // Path tokens (e.g. "priv", "cleandevmac")
        let lowerPath = displayPath.lowercased()
        self.pathTokens = lowerPath
            .components(separatedBy: CharacterSet(charactersIn: "/~-_ ."))
            .filter { !$0.isEmpty }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: VSCodeProject, rhs: VSCodeProject) -> Bool {
        lhs.path == rhs.path
    }
}

// MARK: - VS Code Projects Provider

final class VSCodeProjectsProvider: @unchecked Sendable {
    static let shared = VSCodeProjectsProvider()

    static let minimumScore: Double = 65.0
    static let minimumQueryLength = 2
    static let maxProjects = 50
    static let maxResults = 8
    private static let maxRecencyBonus: Double = 4.5

    private let lock = NSLock()
    private var projects: [VSCodeProject] = []
    private var loadedSignature: String = ""
    private var isLoading = false

    private init() {}

    // MARK: - Application Path

    static var vsCodeAppPath: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            return url.path
        }
        if FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app") {
            return "/Applications/Visual Studio Code.app"
        }
        return ""
    }

    static var isVSCodeInstalled: Bool {
        !vsCodeAppPath.isEmpty
    }

    // MARK: - Loading

    func startLoading() {
        load(force: true)
    }

    func refreshIfNeeded() {
        load(force: false)
    }

    func projectCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return projects.count
    }

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

            guard Self.isVSCodeInstalled else {
                self.lock.lock()
                self.projects = []
                self.loadedSignature = ""
                self.lock.unlock()
                return
            }

            let currentSig = Self.currentSignature()
            if !force && !currentSig.isEmpty && currentSig == previousSignature {
                return
            }

            let loaded = Self.loadRecentProjects()

            self.lock.lock()
            self.projects = loaded
            self.loadedSignature = currentSig
            self.lock.unlock()
        }
    }

    // MARK: - Signature

    private static func currentSignature() -> String {
        let home = NSHomeDirectory()
        let storagePath = "\(home)/Library/Application Support/Code/User/globalStorage/storage.json"
        let wsDirPath = "\(home)/Library/Application Support/Code/User/workspaceStorage"

        var sig = ""
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: storagePath) {
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            sig += "\(mtime)|\(size);"
        }
        if let wsAttrs = try? fm.attributesOfItem(atPath: wsDirPath) {
            let wsMtime = (wsAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            sig += "\(wsMtime)"
        }
        return sig
    }

    // MARK: - Parsing Recent Projects

    static func loadRecentProjects() -> [VSCodeProject] {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // Map path -> (name, path, recency)
        var pathMap: [String: (name: String, path: String, recency: Double)] = [:]

        // 1. Read storage.json (top items from lastKnownMenubarData)
        let storagePath = "\(home)/Library/Application Support/Code/User/globalStorage/storage.json"
        if let storageData = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
           let json = try? JSONSerialization.jsonObject(with: storageData) as? [String: Any],
           let menubar = json["lastKnownMenubarData"] as? [String: Any],
           let menus = menubar["menus"] as? [String: Any],
           let fileMenu = menus["File"] as? [String: Any],
           let items = fileMenu["items"] as? [[String: Any]] {
            for item in items where (item["id"] as? String) == "submenuitem.MenubarRecentMenu" {
                if let submenu = item["submenu"] as? [String: Any],
                   let subItems = submenu["items"] as? [[String: Any]] {
                    // Highest rank to items at top of list
                    var rank = 10_000_000_000.0
                    for sub in subItems {
                        rank -= 1.0
                        let id = sub["id"] as? String ?? ""
                        if id == "openRecentFolder" || id == "openRecentWorkspace" {
                            if let uriDict = sub["uri"] as? [String: Any],
                               let p = uriDict["path"] as? String,
                               !p.isEmpty {
                                let normalized = (p as NSString).standardizingPath
                                if shouldIncludePath(normalized) {
                                    let name = (normalized as NSString).lastPathComponent
                                    pathMap[normalized] = (name: name, path: normalized, recency: rank)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Read workspaceStorage/*/workspace.json
        let wsDirPath = "\(home)/Library/Application Support/Code/User/workspaceStorage"
        if let subdirs = try? fm.contentsOfDirectory(atPath: wsDirPath) {
            for subdir in subdirs {
                let wsFolder = "\(wsDirPath)/\(subdir)"
                let wsJsonPath = "\(wsFolder)/workspace.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: wsJsonPath)),
                      let wsObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let rawUri = (wsObj["folder"] as? String) ?? (wsObj["workspace"] as? String)
                guard let rawUri = rawUri, !rawUri.isEmpty else { continue }

                guard let parsedPath = parseURIPath(rawUri) else { continue }
                let normalized = (parsedPath as NSString).standardizingPath

                guard shouldIncludePath(normalized) else { continue }

                // Determine recency timestamp from state.vscdb or wsJson
                let stateDbPath = "\(wsFolder)/state.vscdb"
                var mtime: Double = 0
                if let attrs = try? fm.attributesOfItem(atPath: stateDbPath),
                   let date = attrs[.modificationDate] as? Date {
                    mtime = date.timeIntervalSince1970
                } else if let attrs = try? fm.attributesOfItem(atPath: wsJsonPath),
                          let date = attrs[.modificationDate] as? Date {
                    mtime = date.timeIntervalSince1970
                }

                // If not already in pathMap or if timestamp is newer (when not an explicit menubar item)
                if let existing = pathMap[normalized] {
                    if existing.recency < 5_000_000_000.0 && mtime > existing.recency {
                        pathMap[normalized] = (name: existing.name, path: normalized, recency: mtime)
                    }
                } else {
                    let name = (normalized as NSString).lastPathComponent
                    pathMap[normalized] = (name: name, path: normalized, recency: mtime)
                }
            }
        }

        // 3. Sort by recency descending, limit to maxProjects
        let sortedEntries = pathMap.values
            .sorted { $0.recency > $1.recency }
            .prefix(maxProjects)

        // 4. Construct VSCodeProject models with tilde-shortened displayPath
        return sortedEntries.map { entry in
            let display = tildeShortenedPath(for: entry.path)
            return VSCodeProject(
                name: entry.name,
                path: entry.path,
                displayPath: display,
                recency: entry.recency
            )
        }
    }

    static func parseURIPath(_ rawUri: String) -> String? {
        if rawUri.hasPrefix("file://") {
            if let url = URL(string: rawUri) {
                return url.path
            }
            let stripped = String(rawUri.dropFirst(7))
            return stripped.removingPercentEncoding ?? stripped
        } else if rawUri.hasPrefix("/") {
            return rawUri
        }
        return nil
    }

    static func shouldIncludePath(_ path: String) -> Bool {
        let fm = FileManager.default

        // 1. Must exist on disk
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return false
        }

        // 2. Exclude git internal dirs
        if path.hasSuffix(".git") || path.contains("/.git/") {
            return false
        }

        // 3. Exclude Claude transient worktrees
        if path.contains("/.claude/worktrees/") {
            return false
        }

        // 4. Exclude internal VS Code application support workspaces
        if path.contains("/Library/Application Support/Code/") {
            return false
        }

        // 5. Exclude unmounted / non-standard volumes if disconnected
        if path.hasPrefix("/Volumes/") {
            guard fm.fileExists(atPath: path) else { return false }
        }

        // 6. Exclude bare root, home dir itself, or system dirs
        let home = NSHomeDirectory()
        if path == home || path == "/" || path == "/Users" {
            return false
        }

        return true
    }

    static func tildeShortenedPath(for path: String) -> String {
        let home = NSHomeDirectory()
        let parent = (path as NSString).deletingLastPathComponent
        if parent == home {
            return "~"
        } else if parent.hasPrefix(home) {
            return "~" + parent.dropFirst(home.count)
        }
        return parent
    }

    // MARK: - Search

    func search(_ query: SearchQuery) -> [SearchResult] {
        if query.lowercased.count < Self.minimumQueryLength { return [] }

        lock.lock()
        let currentProjects = projects
        lock.unlock()

        guard !currentProjects.isEmpty else { return [] }

        return Self.search(query, projects: currentProjects)
    }

    static func search(_ query: SearchQuery, projects: [VSCodeProject]) -> [SearchResult] {
        let q = query.lowercased
        if q.count < minimumQueryLength { return [] }

        var scored: [(project: VSCodeProject, score: Double)] = []
        scored.reserveCapacity(min(projects.count, 16))

        let isBrowseQuery = (q == "proj" || q == "project" || q == "vscode" || q == "code" || q == "recent" || q == "finder")

        for (index, project) in projects.enumerated() {
            var highestScore: Double? = FuzzyMatcher.score(
                query: query,
                targetLower: project.lowercaseName,
                targetTokens: project.nameTokens,
                targetInitials: project.initials
            )

            // Path segment match (scaled x0.90)
            for pathToken in project.pathTokens {
                let tokenInitials = String(pathToken.prefix(1))
                if let pScore = FuzzyMatcher.score(
                    query: query,
                    targetLower: pathToken,
                    targetTokens: [pathToken],
                    targetInitials: tokenInitials
                ) {
                    let weighted = pScore * 0.90
                    if let current = highestScore {
                        highestScore = max(current, weighted)
                    } else {
                        highestScore = weighted
                    }
                }
            }

            // Generic browse keywords fallback (score 68)
            if isBrowseQuery && (highestScore == nil || highestScore! < 68.0) {
                highestScore = 68.0
            }

            if let base = highestScore, base >= minimumScore {
                // Add recency bonus (0 .. 4.5)
                let bonus = orderBonus(index: index, count: projects.count)
                let finalScore = base + bonus
                scored.append((project: project, score: finalScore))
            }
        }

        let appPath = vsCodeAppPath
        let iconType: ResultIconType = !appPath.isEmpty
            ? .app(path: appPath)
            : .systemSymbol(name: "folder.fill")

        return scored
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { item in
                SearchResult(
                    id: "project-\(item.project.path)",
                    title: item.project.name,
                    subtitle: item.project.displayPath,
                    iconType: iconType,
                    category: .recentProjects,
                    score: item.score,
                    action: .openFolder(path: item.project.path)
                )
            }
    }

    private static func orderBonus(index: Int, count: Int) -> Double {
        guard count > 1 else { return maxRecencyBonus }
        let position = Double(count - 1 - index) / Double(count - 1)
        return maxRecencyBonus * position
    }
}
