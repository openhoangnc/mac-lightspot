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
        recency: Double
    ) {
        self.name = name
        self.path = path
        self.displayPath = displayPath
        self.ideName = ideName
        self.ideBundleID = ideBundleID
        self.iconAppPath = iconAppPath
        self.recency = recency

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

        // VS Code
        let vsCodeStorage = "\(home)/Library/Application Support/Code/User/globalStorage/storage.json"
        if let attrs = try? fm.attributesOfItem(atPath: vsCodeStorage) {
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            sig += "vscode:\(mtime);"
        }

        // Cursor
        let cursorStorage = "\(home)/Library/Application Support/Cursor/User/globalStorage/storage.json"
        if let attrs = try? fm.attributesOfItem(atPath: cursorStorage) {
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            sig += "cursor:\(mtime);"
        }

        // Zed
        let zedDB = "\(home)/Library/Application Support/Zed/db.sqlite"
        if let attrs = try? fm.attributesOfItem(atPath: zedDB) {
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            sig += "zed:\(mtime);"
        }

        // JetBrains options directory
        let jetbrainsDir = "\(home)/Library/Application Support/JetBrains"
        if let contents = try? fm.contentsOfDirectory(atPath: jetbrainsDir) {
            for item in contents {
                let xml = "\(jetbrainsDir)/\(item)/options/recentProjects.xml"
                if let attrs = try? fm.attributesOfItem(atPath: xml) {
                    let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    sig += "jb-\(item):\(mtime);"
                }
            }
        }

        // Sublime Text
        let sublimeSession = "\(home)/Library/Application Support/Sublime Text/Local/Session.sublime_session"
        if let attrs = try? fm.attributesOfItem(atPath: sublimeSession) {
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            sig += "sublime:\(mtime);"
        }

        return sig
    }

    // MARK: - Project Discovery

    public static func discoverAllProjects() -> [RecentProject] {
        var allFound: [RecentProject] = []
        let home = NSHomeDirectory()

        // 1. VS Code
        allFound.append(contentsOf: loadVSCodeProjects())

        // 2. Cursor
        let cursorApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92")?.path
        let cursorStorage = "\(home)/Library/Application Support/Cursor/User/globalStorage/storage.json"
        allFound.append(contentsOf: loadJSONStorageProjects(
            filePath: cursorStorage,
            ideName: "Cursor",
            ideBundleID: "com.todesktop.230313mzl4w4u92",
            iconAppPath: cursorApp
        ))

        // 3. Zed
        let zedApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed")?.path
        let zedDB = "\(home)/Library/Application Support/Zed/db.sqlite"
        allFound.append(contentsOf: loadZedProjects(dbPath: zedDB, iconAppPath: zedApp))

        // 4. JetBrains Suite
        allFound.append(contentsOf: loadJetBrainsProjects())

        // 5. Sublime Text
        let sublimeApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.sublimetext.4")?.path
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.sublimetext.3")?.path
        let sublimeSession = "\(home)/Library/Application Support/Sublime Text/Local/Session.sublime_session"
        allFound.append(contentsOf: loadSublimeProjects(sessionPath: sublimeSession, iconAppPath: sublimeApp))

        // Deduplicate by path (keep the one with highest recency)
        var unique: [String: RecentProject] = [:]
        for proj in allFound {
            if let existing = unique[proj.path] {
                if proj.recency > existing.recency {
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

    // MARK: - VS Code Parser

    private static func loadVSCodeProjects() -> [RecentProject] {
        let vsCodeApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")?.path
            ?? (FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app") ? "/Applications/Visual Studio Code.app" : nil)
        let home = NSHomeDirectory()
        let vsCodeStorage = "\(home)/Library/Application Support/Code/User/globalStorage/storage.json"

        return loadJSONStorageProjects(
            filePath: vsCodeStorage,
            ideName: "VS Code",
            ideBundleID: "com.microsoft.VSCode",
            iconAppPath: vsCodeApp
        )
    }

    // MARK: - Generic JSON Storage Parser (VS Code & Cursor)

    public static func loadJSONStorageProjects(
        filePath: String,
        ideName: String,
        ideBundleID: String,
        iconAppPath: String?
    ) -> [RecentProject] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let home = NSHomeDirectory()
        let fm = FileManager.default
        var pathsInOrder: [String] = []

        // Extract profileAssociations.workspaces keys
        if let profileAssoc = json["profileAssociations"] as? [String: Any],
           let workspaces = profileAssoc["workspaces"] as? [String: Any] {
            for (key, _) in workspaces {
                if let path = decodeURIPath(key) {
                    pathsInOrder.append(path)
                }
            }
        }

        // Also check openedPathsList / entries
        if let openedPaths = json["openedPathsList"] as? [String: Any],
           let entries = openedPaths["entries"] as? [[String: Any]] {
            for entry in entries {
                if let folderUri = entry["folderUri"] as? String, let path = decodeURIPath(folderUri) {
                    pathsInOrder.append(path)
                } else if let fileUri = entry["fileUri"] as? String, let path = decodeURIPath(fileUri) {
                    pathsInOrder.append(path)
                }
            }
        }

        var results: [RecentProject] = []
        var seen = Set<String>()
        let total = Double(max(pathsInOrder.count, 1))

        for (idx, rawPath) in pathsInOrder.enumerated() {
            guard !seen.contains(rawPath) else { continue }
            seen.insert(rawPath)

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rawPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let name = URL(fileURLWithPath: rawPath).lastPathComponent
            guard !name.isEmpty && name != "/" else { continue }

            let displayPath: String
            if rawPath.hasPrefix(home) {
                displayPath = "~" + rawPath.dropFirst(home.count)
            } else {
                displayPath = rawPath
            }

            let recency = 1.0 - (Double(idx) / total)
            results.append(RecentProject(
                name: name,
                path: rawPath,
                displayPath: displayPath,
                ideName: ideName,
                ideBundleID: ideBundleID,
                iconAppPath: iconAppPath,
                recency: recency
            ))
        }

        return results
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

    public static func loadZedProjects(dbPath: String, iconAppPath: String?) -> [RecentProject] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        // Use sqlite3 CLI or read file string to extract workspace directory paths without locking
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["file:\(dbPath)?immutable=1", "SELECT paths FROM workspaces;"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let home = NSHomeDirectory()
            let fm = FileManager.default
            var results: [RecentProject] = []
            var seen = Set<String>()

            let lines = output.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty && candidate.hasPrefix("/") && !seen.contains(candidate) else { continue }
                seen.insert(candidate)

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue else { continue }

                let name = URL(fileURLWithPath: candidate).lastPathComponent
                guard !name.isEmpty && name != "/" else { continue }

                let displayPath = candidate.hasPrefix(home) ? "~" + candidate.dropFirst(home.count) : candidate
                let recency = 1.0 - (Double(idx) / Double(max(lines.count, 1)))

                results.append(RecentProject(
                    name: name,
                    path: candidate,
                    displayPath: displayPath,
                    ideName: "Zed",
                    ideBundleID: "dev.zed.Zed",
                    iconAppPath: iconAppPath,
                    recency: recency
                ))
            }
            return results
        } catch {
            return []
        }
    }

    // MARK: - JetBrains Parser

    public static func loadJetBrainsProjects() -> [RecentProject] {
        let home = NSHomeDirectory()
        let jetbrainsDir = "\(home)/Library/Application Support/JetBrains"
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: jetbrainsDir) else { return [] }

        var results: [RecentProject] = []
        var seen = Set<String>()

        for item in items {
            let xmlPath = "\(jetbrainsDir)/\(item)/options/recentProjects.xml"
            guard fm.fileExists(atPath: xmlPath),
                  let content = try? String(contentsOfFile: xmlPath, encoding: .utf8) else {
                continue
            }

            // Determine JetBrains product display name and bundle ID
            let (productName, bundleID) = jetBrainsProductInfo(for: item)
            let appPath = bundleID != nil ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID!)?.path : nil

            // Parse <entry key="$USER_HOME$/..." or <entry key="/..."
            let lines = content.components(separatedBy: .newlines)
            var extractedPaths: [String] = []

            for line in lines {
                if line.contains("<entry key=\"") {
                    let parts = line.components(separatedBy: "<entry key=\"")
                    if parts.count > 1, let pathPart = parts[1].components(separatedBy: "\"").first {
                        let expanded = pathPart.replacingOccurrences(of: "$USER_HOME$", with: home)
                        if !seen.contains(expanded) {
                            extractedPaths.append(expanded)
                            seen.insert(expanded)
                        }
                    }
                }
            }

            let total = Double(max(extractedPaths.count, 1))
            for (idx, rawPath) in extractedPaths.enumerated() {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: rawPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let name = URL(fileURLWithPath: rawPath).lastPathComponent
                guard !name.isEmpty && name != "/" else { continue }

                let displayPath = rawPath.hasPrefix(home) ? "~" + rawPath.dropFirst(home.count) : rawPath
                let recency = 1.0 - (Double(idx) / total)

                results.append(RecentProject(
                    name: name,
                    path: rawPath,
                    displayPath: displayPath,
                    ideName: productName,
                    ideBundleID: bundleID,
                    iconAppPath: appPath,
                    recency: recency
                ))
            }
        }

        return results
    }

    private static func jetBrainsProductInfo(for folderName: String) -> (name: String, bundleID: String?) {
        let lower = folderName.lowercased()
        if lower.contains("intellij") || lower.contains("idea") {
            return ("IntelliJ IDEA", "com.jetbrains.intellij")
        } else if lower.contains("pycharm") {
            return ("PyCharm", "com.jetbrains.pycharm")
        } else if lower.contains("webstorm") {
            return ("WebStorm", "com.jetbrains.webstorm")
        } else if lower.contains("goland") {
            return ("GoLand", "com.jetbrains.goland")
        } else if lower.contains("clion") {
            return ("CLion", "com.jetbrains.CLion")
        } else if lower.contains("rustrover") {
            return ("RustRover", "com.jetbrains.rustrover")
        }
        return ("JetBrains", nil)
    }

    // MARK: - Sublime Text Parser

    public static func loadSublimeProjects(sessionPath: String, iconAppPath: String?) -> [RecentProject] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let home = NSHomeDirectory()
        let fm = FileManager.default
        var extractedPaths: [String] = []

        // Parse workspaces -> recent
        if let workspaces = json["workspaces"] as? [String: Any],
           let recent = workspaces["recent"] as? [String] {
            for item in recent {
                // If it's a .sublime-project file, use its parent folder
                if item.hasSuffix(".sublime-project") {
                    let parent = URL(fileURLWithPath: item).deletingLastPathComponent().path
                    extractedPaths.append(parent)
                } else {
                    extractedPaths.append(item)
                }
            }
        }

        // Parse folder_history
        if let folderHistory = json["folder_history"] as? [String] {
            extractedPaths.append(contentsOf: folderHistory)
        }

        var results: [RecentProject] = []
        var seen = Set<String>()
        let total = Double(max(extractedPaths.count, 1))

        for (idx, rawPath) in extractedPaths.enumerated() {
            guard !seen.contains(rawPath) else { continue }
            seen.insert(rawPath)

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rawPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let name = URL(fileURLWithPath: rawPath).lastPathComponent
            guard !name.isEmpty && name != "/" else { continue }

            let displayPath = rawPath.hasPrefix(home) ? "~" + rawPath.dropFirst(home.count) : rawPath
            let recency = 1.0 - (Double(idx) / total)

            results.append(RecentProject(
                name: name,
                path: rawPath,
                displayPath: displayPath,
                ideName: "Sublime Text",
                ideBundleID: "com.sublimetext.4",
                iconAppPath: iconAppPath,
                recency: recency
            ))
        }

        return results
    }
}
