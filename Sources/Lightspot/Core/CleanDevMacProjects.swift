import Foundation
import Darwin

// MARK: - cdm's repo scan
//
// cdm's `scan_projects`, ported: find the git repos under the home folder, nominate the
// directories whose names cdm's rules list (`node_modules`, `dist`, `target`…), and offer
// only what each repo's own git says it ignores — a matching name is not evidence, a
// `.gitignore` entry is. Everything is grouped per repo (or per group root), and every
// item keeps its own method: regenerable directories are deleted, any other ignored file
// goes to the Trash, and `.env*` files are never offered.

enum CleanDevMacProjects {

    // MARK: git

    /// A real git binary, never `/usr/bin/git`: without the Command Line Tools that shim
    /// opens macOS's "install developer tools" dialog instead of running.
    static func gitExecutable(candidates: [String] = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// cdm's ignored listing for one repo: every path that is both ignored and untracked,
    /// a wholly ignored folder collapsed to one entry. Absolute, without a trailing slash.
    /// Empty when git fails, so a repo it cannot read proves nothing.
    static func ignoredEntries(repo: String, git: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-c", "core.quotePath=false", "ls-files", "-z", "--others", "--ignored",
                             "--exclude-standard", "--directory"]
        process.currentDirectoryURL = URL(fileURLWithPath: repo)
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        // Read before waiting: a full pipe would otherwise block git forever (invariant 1).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return data.split(separator: 0).compactMap { bytes in
            var relative = String(decoding: bytes, as: UTF8.self)
            if relative.hasSuffix("/") { relative.removeLast() }
            return relative.isEmpty ? nil : repo + "/" + relative
        }
    }

    // MARK: The walk

    struct Walk: Sendable, Equatable {
        /// Folders that directly hold a `.git` directory.
        var repos: [String] = []
        /// Directories named like junk, not yet proven to be.
        var candidates: [String] = []
    }

    /// Folders under the home folder the walk never enters: cdm's protected folders (its
    /// safety gate refuses every path in them anyway) and `~/Library`. Reading inside
    /// Documents, Desktop or Downloads would also make macOS ask whether Lightspot may.
    static func skippedFolders(home: String) -> Set<String> {
        Set((CleanDevMacEngine.protectedFolders + ["Library"]).map { home + "/" + $0 })
    }

    /// cdm's single find pass, as fts: a `.git` directory marks its parent as a repo and is
    /// not entered, a pruned name or a skipped folder is not entered, and a directory named
    /// like junk is nominated and not entered. Entries `maxDepth` levels below a root are
    /// still looked at, but nothing deeper. Roots outside the home folder are ignored.
    static func walk(_ rules: CleanDevMacProjectRules, home: String) -> Walk {
        let prune = Set(rules.prune).subtracting([".git"])
        let junk = Set(rules.dirs.map(\.name))
        let skipped = skippedFolders(home: home)
        var walk = Walk()
        for root in rules.roots {
            let path = CleanDevMacEngine.expandTilde(root, home: home)
            guard path == home || path.hasPrefix(home + "/"), let cPath = strdup(path) else { continue }
            defer { free(cPath) }
            var roots: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
            guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { continue }
            defer { fts_close(tree) }
            while let entry = fts_read(tree) {
                guard entry.pointee.fts_level > 0, Int32(entry.pointee.fts_info) == FTS_D else { continue }
                let entryPath = String(cString: entry.pointee.fts_path)
                let name = (entryPath as NSString).lastPathComponent
                var enter = Int(entry.pointee.fts_level) < rules.maxDepth
                if name == ".git" {
                    walk.repos.append((entryPath as NSString).deletingLastPathComponent)
                    enter = false
                } else if prune.contains(name) || skipped.contains(entryPath) {
                    enter = false
                } else if junk.contains(name) {
                    walk.candidates.append(entryPath)
                    enter = false
                }
                if !enter { fts_set(tree, entry, FTS_SKIP) }
            }
        }
        // The home folder is never a project, or a dotfiles repo would sweep in everything.
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        walk.repos.removeAll { $0 == home || $0 == physicalHome || skipped.contains($0) }
        return walk
    }

    // MARK: Proof and grouping

    /// One offered path, with the repo (or group root) it is listed under.
    struct Item: Sendable, Equatable {
        let key: String
        let method: CleanDevMacRule.Method
        let path: String
    }

    /// Repo roots, longest first, so the first that contains a path is its nearest repo.
    static func sortedRepos(_ repos: [String]) -> [String] {
        var seen = Set<String>()
        return repos.sorted { $0.utf8.count > $1.utf8.count }.filter { seen.insert($0).inserted }
    }

    /// cdm's `project_key`: the nearest repo holding `path`, or nil outside every repo.
    static func projectKey(_ path: String, repos: [String]) -> String? {
        repos.first { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// The repos git lists, in cdm's order: those holding a candidate first, so the cap
    /// sheds repos with nothing name-matched to lose, then every repo for the git-ignored
    /// pass. Capped at `maxRepos`; a repo past the cap proves nothing.
    static func reposToList(_ walk: Walk, rules: CleanDevMacProjectRules) -> [String] {
        let repos = sortedRepos(walk.repos)
        var ordered = walk.candidates.compactMap { projectKey($0, repos: repos) }
        if rules.gitignoreMethod != nil { ordered += repos }
        var seen = Set<String>()
        return Array(ordered.filter { seen.insert($0).inserted }.prefix(rules.maxRepos))
    }

    /// Byte order, like cdm's `LC_ALL=C sort`.
    private static func byteOrder(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    /// What gets offered, from the walk and each listed repo's ignored entries:
    ///
    /// - a nominated directory, when it or an ancestor below its own repo root is ignored
    ///   (the walk stops at the root: an outer repo ignoring a nested checkout says nothing
    ///   about what that checkout tracks);
    /// - with a `gitignore` category, every other ignored entry except `.env*`;
    /// - never a path holding another repo (Lightspot's addition: an outer repo that ignores
    ///   a whole nested checkout would otherwise offer it; `withoutOtherCheckouts` extends
    ///   this to checkouts the walk did not see), nor one the safety gate refuses;
    /// - an item inside another kept item is dropped, and a repo under a group root is
    ///   listed under the group root.
    static func items(_ walk: Walk, ignored: [String: [String]], listed: [String],
                      rules: CleanDevMacProjectRules, home: String, physicalHome: String) -> [Item] {
        let repos = sortedRepos(walk.repos)
        let ignoredPaths = Set(ignored.values.joined())
        var items: [Item] = []

        for candidate in walk.candidates {
            guard let key = projectKey(candidate, repos: repos) else { continue }
            var folder = candidate
            while folder != key && !folder.isEmpty && folder != "/" {
                if ignoredPaths.contains(folder) {
                    let name = (candidate as NSString).lastPathComponent
                    items.append(Item(key: key, method: rules.method(forName: name) ?? .rm, path: candidate))
                    break
                }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        if let gitignoreMethod = rules.gitignoreMethod {
            for repo in listed {
                for path in ignored[repo] ?? [] {
                    let name = (path as NSString).lastPathComponent
                    // Secrets and machine-local config nothing regenerates (cdm's rule).
                    guard !name.hasPrefix(".env") else { continue }
                    items.append(Item(key: repo, method: rules.method(forName: name) ?? gitignoreMethod, path: path))
                }
            }
        }

        items.removeAll { item in
            repos.contains { $0 == item.path || $0.hasPrefix(item.path + "/") }
                || !CleanDevMacEngine.isSafeTarget(item.path, home: home, physicalHome: physicalHome)
        }

        // Sorting by path puts an ancestor right before its descendants; on a tie, `rm`
        // sorts before `trash`, as cdm's whole-line sort does.
        items.sort { $0.path != $1.path ? byteOrder($0.path, $1.path) : byteOrder($0.method.rawValue, $1.method.rawValue) }
        let groups = rules.groups.map { CleanDevMacEngine.expandTilde($0, home: home) }
        var kept: String?
        var result: [Item] = []
        for item in items {
            if let kept, item.path == kept || item.path.hasPrefix(kept + "/") { continue }
            kept = item.path
            let key = groups.first { item.key == $0 || item.key.hasPrefix($0 + "/") } ?? item.key
            result.append(Item(key: key, method: item.method, path: item.path))
        }
        return result
    }

    /// One row of the cleaner: a repo, or a group root and every repo under it.
    struct Project: Sendable, Equatable {
        let key: String
        let paths: [String]
        let methods: [CleanDevMacRule.Method]
        /// The offered names, unique, in byte order; a group root's start with its repo count.
        let summary: String
    }

    /// cdm's grouping: one project per key, keys in byte order, paths in path order.
    static func projects(_ items: [Item], repos: [String], groups: [String], home: String) -> [Project] {
        let sortedRepos = sortedRepos(repos)
        let groupRoots = Set(groups.map { CleanDevMacEngine.expandTilde($0, home: home) })
        var byKey: [String: [Item]] = [:]
        for item in items { byKey[item.key, default: []].append(item) }
        return byKey.keys.sorted(by: byteOrder).map { key in
            let items = byKey[key] ?? []
            var names = Array(Set(items.map { ($0.path as NSString).lastPathComponent })).sorted(by: byteOrder).joined(separator: ", ")
            if groupRoots.contains(key) {
                let count = Set(items.compactMap { projectKey($0.path, repos: sortedRepos) }).count
                if count > 0 { names = "\(count) \(count == 1 ? "repo" : "repos") · " + names }
            }
            return Project(key: key, paths: items.map(\.path), methods: items.map(\.method), summary: names)
        }
    }

    /// Blocking: the whole scan. `progress` gets (repos listed, repos to list).
    static func scan(_ rules: CleanDevMacProjectRules, home: String, git: String,
                     progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) -> (projects: [Project], repoCount: Int) {
        let found = walk(rules, home: home)
        let listed = reposToList(found, rules: rules)
        progress?(0, listed.count)
        let listings = Listings(count: listed.count)
        DispatchQueue.concurrentPerform(iterations: listed.count) { index in
            let done = listings.record(ignoredEntries(repo: listed[index], git: git), at: index)
            progress?(done, listed.count)
        }
        var ignored: [String: [String]] = [:]
        for (repo, entries) in zip(listed, listings.all) { ignored[repo] = entries }
        let physicalHome = CleanDevMacEngine.physicalPath(home)
        let offered = items(found, ignored: ignored, listed: listed, rules: rules, home: home, physicalHome: physicalHome)
        let kept = withoutOtherCheckouts(offered, repos: sortedRepos(found.repos))
        return (projects(kept, repos: found.repos, groups: rules.groups, home: home), Set(found.repos).count)
    }

    // MARK: Other checkouts

    /// Whether `gitPath` (a `.git` entry) makes its folder a checkout: a `.git` directory
    /// with a `HEAD`, or the `.git` file of a worktree or submodule (`gitdir: …`).
    static func isCheckoutMarker(_ gitPath: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue { return access(gitPath + "/HEAD", F_OK) == 0 }
        guard let handle = FileHandle(forReadingAtPath: gitPath) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 8)) == Data("gitdir: ".utf8)
    }

    /// Whether `path` holds a checkout anywhere below it. Blocking: reads every directory
    /// under `path`, names only. A folder it cannot read counts as holding one.
    static func holdsCheckout(_ path: String) -> Bool {
        guard let cPath = strdup(path) else { return true }
        defer { free(cPath) }
        var roots: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_NOSTAT, nil) else { return true }
        defer { fts_close(tree) }
        while let entry = fts_read(tree) {
            let info = Int32(entry.pointee.fts_info)
            if info == FTS_DNR || info == FTS_ERR { return true }
            guard entry.pointee.fts_level > 0, entry.pointee.fts_namelen == 4, info != FTS_DP else { continue }
            let entryPath = String(cString: entry.pointee.fts_path)
            guard (entryPath as NSString).lastPathComponent == ".git" else { continue }
            if isCheckoutMarker(entryPath) { return true }
            if info == FTS_D { fts_set(tree, entry, FTS_SKIP) }
        }
        return false
    }

    /// `items` minus every path that holds another checkout or sits inside one below its
    /// own repo (Lightspot's addition). The walk counts only `.git` directories as repos,
    /// as cdm does, and never enters pruned names such as `.claude` or `vendor`, while git
    /// lists an ignored folder whole: without this, a folder offered for the Trash could
    /// hold a worktree with uncommitted work, and a checkout's tracked `build/` could be
    /// offered on the strength of an outer repo ignoring the checkout.
    static func withoutOtherCheckouts(_ items: [Item], repos: [String]) -> [Item] {
        let touched = Probes(count: items.count)
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            let path = items[index].path
            let repo = projectKey(path, repos: repos) ?? items[index].key
            var folder = (path as NSString).deletingLastPathComponent
            var inside = false
            while folder.hasPrefix(repo + "/") && !inside {
                inside = isCheckoutMarker(folder + "/.git")
                folder = (folder as NSString).deletingLastPathComponent
            }
            touched.record(inside || holdsCheckout(path), at: index)
        }
        return zip(items, touched.all).filter { !$0.1 }.map(\.0)
    }

    private final class Probes: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Bool]

        init(count: Int) {
            results = Array(repeating: true, count: count)
        }

        func record(_ result: Bool, at index: Int) {
            lock.lock()
            defer { lock.unlock() }
            results[index] = result
        }

        var all: [Bool] {
            lock.lock()
            defer { lock.unlock() }
            return results
        }
    }

    private final class Listings: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [[String]]
        private var done = 0

        init(count: Int) {
            entries = Array(repeating: [], count: count)
        }

        func record(_ list: [String], at index: Int) -> Int {
            lock.lock()
            defer { lock.unlock() }
            entries[index] = list
            done += 1
            return done
        }

        var all: [[String]] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }
}
