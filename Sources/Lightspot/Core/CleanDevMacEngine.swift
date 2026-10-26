import Foundation
import Darwin

// MARK: - cdm Engine
//
// The file-system half of cdm, ported from its bash: pattern expansion, sizing, the safety
// gate every deletion passes, deletion itself, the disk line and the clean log. All of it
// blocks, so it runs on CleanDevMacProvider's queue, never on the keystroke path.

enum CleanDevMacEngine {

    // MARK: Paths

    /// cdm's `expand_tilde`: `~/x` and `~` resolve against `home`; anything else is kept.
    static func expandTilde(_ pattern: String, home: String) -> String {
        if pattern == "~" { return home }
        if pattern.hasPrefix("~/") { return home + "/" + pattern.dropFirst(2) }
        return pattern
    }

    /// Pathname expansion with glob(3), which keeps the shell rules cdm relies on: `*`
    /// never matches a leading dot, and a pattern with no wildcard comes back only if it
    /// exists. Sorted, like the shell's.
    static func expandGlob(_ pattern: String) -> [String] {
        var matches = glob_t()
        defer { globfree(&matches) }
        guard glob(pattern, 0, nil, &matches) == 0 else { return [] }
        return (0..<Int(matches.gl_pathc)).compactMap { index in
            matches.gl_pathv[index].map { String(cString: $0) }
        }
    }

    /// `[ -e ]`: true for anything that exists, following symlinks, so a dangling link is
    /// false.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0
    }

    private static func fileType(_ path: String) -> mode_t? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }

    /// cdm's `is_nonempty`: a regular file, or a directory holding anything at all (a
    /// dangling symlink inside counts). A folder Lightspot may not list is not offered.
    static func isNonEmpty(_ path: String) -> Bool {
        switch fileType(path) {
        case S_IFREG:
            return true
        case S_IFDIR:
            guard let dir = opendir(path) else { return false }
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                    String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
                }
                if name != "." && name != ".." { return true }
            }
            return false
        default:
            return false
        }
    }

    /// Folders whose patterns are never expanded. They hold other apps' sandbox
    /// containers, and reading inside one makes macOS ask whether Lightspot may "access
    /// data from other apps" — a prompt that would come back with every update of an
    /// ad-hoc signed app. cdm reaches them from the terminal, which has its own grant.
    static let outOfScopeFolders = ["Library/Containers", "Library/Group Containers"]

    static func isOutOfScope(_ expandedPattern: String, home: String) -> Bool {
        outOfScopeFolders.contains { folder in
            let root = home + "/" + folder
            return expandedPattern == root || expandedPattern.hasPrefix(root + "/")
        }
    }

    /// cdm's `ends_with_any`: `path` is, or ends in `/` + , one of `suffixes`.
    static func endsWithAny(_ path: String, _ suffixes: [String]) -> Bool {
        suffixes.contains { !$0.isEmpty && (path == $0 || path.hasSuffix("/" + $0)) }
    }

    /// cdm's `register_paths`: every existing, non-empty match of `patterns`, in pattern
    /// order and without duplicates; a match `skip` names is left out. Unlike cdm, a match
    /// the safety gate would refuse is not offered either, rather than listed and then
    /// skipped at clean time.
    static func matchedPaths(patterns: [String], home: String, physicalHome: String, skip: [String] = []) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for pattern in patterns where !pattern.isEmpty {
            let expanded = expandTilde(pattern, home: home)
            guard !isOutOfScope(expanded, home: home) else { continue }
            for match in expandGlob(expanded) {
                guard seen.insert(match).inserted, isNonEmpty(match), !endsWithAny(match, skip),
                      isSafeTarget(match, home: home, physicalHome: physicalHome) else { continue }
                found.append(match)
            }
        }
        return found
    }

    // MARK: Android system images

    /// cdm's `avd_configs`: every AVD's config.ini, `<avd home>/*.avd/config.ini` plus
    /// wherever a `<avd home>/<name>.ini` points with `path=` (an AVD may live elsewhere).
    static func avdConfigFiles(home: String, environment: [String: String]) -> [String] {
        let userHome = environment["ANDROID_USER_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.android"
        var configs: [String] = []
        var seen = Set<String>()
        for avdHome in [environment["ANDROID_AVD_HOME"] ?? "", userHome + "/avd", home + "/.android/avd"] {
            guard !avdHome.isEmpty, fileType(avdHome) == S_IFDIR, seen.insert(avdHome).inserted else { continue }
            configs.append(contentsOf: expandGlob(avdHome + "/*.avd/config.ini").filter { fileType($0) == S_IFREG })
            for ini in expandGlob(avdHome + "/*.ini") where fileType(ini) == S_IFREG {
                for line in lines(of: ini) where line.hasPrefix("path=") {
                    let config = String(line.dropFirst("path=".count)) + "/config.ini"
                    if fileType(config) == S_IFREG { configs.append(config) }
                }
            }
        }
        return configs
    }

    /// One AVD booting one system image (a line of cdm's `avd_image_users`).
    struct AVDImageUser: Equatable, Sendable {
        /// The SDK-relative image folder (`image.sysdir.N=`).
        let ref: String
        /// The AVD's folder name without `.avd`.
        let avd: String
        /// When it last ran, in seconds since 1970 (`avdLastStarted`).
        let lastStarted: Int
    }

    /// cdm's `avd_image_users`: every image each AVD boots from (each `image.sysdir.N=`
    /// value, without surrounding spaces or a trailing slash), with the AVD's name and
    /// when it last ran.
    static func avdImageUsers(home: String, environment: [String: String]) -> [AVDImageUser] {
        var users: [AVDImageUser] = []
        for config in avdConfigFiles(home: home, environment: environment) {
            let folder = (config as NSString).deletingLastPathComponent
            var avd = (folder as NSString).lastPathComponent
            if avd.hasSuffix(".avd") { avd = String(avd.dropLast(".avd".count)) }
            let lastStarted = avdLastStarted(folder)
            for line in lines(of: config) where line.hasPrefix("image.sysdir.") {
                guard let equals = line.firstIndex(of: "=") else { continue }
                var value = Substring(line[line.index(after: equals)...])
                while value.hasPrefix(" ") { value = value.dropFirst() }
                while value.hasSuffix(" ") || value.hasSuffix("/") { value = value.dropLast() }
                if !value.isEmpty { users.append(AVDImageUser(ref: String(value), avd: avd, lastStarted: lastStarted)) }
            }
        }
        return users
    }

    /// cdm's `avd_image_refs`: the SDK-relative system-image folders the AVDs boot from.
    static func avdImageRefs(home: String, environment: [String: String]) -> [String] {
        avdImageUsers(home: home, environment: environment).map(\.ref)
    }

    /// cdm's `avd_last_started`: when an AVD last ran, as the newest modification time
    /// (seconds since 1970) of what its folder holds — the emulator rewrites
    /// hardware-qemu.ini and its userdata image every run. config.ini counts only when
    /// nothing else is there: Android Studio rewrites it without booting anything. 0 for
    /// a folder that holds nothing.
    static func avdLastStarted(_ folder: String) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return 0 }
        var newest = 0
        var config = 0
        // Like the shell's `*` cdm reads them with: hidden names are not looked at, and a
        // symlink is dated by itself, not by what it points at.
        for name in names where !name.hasPrefix(".") {
            var info = stat()
            guard lstat(folder + "/" + name, &info) == 0 else { continue }
            let modified = Int(info.st_mtimespec.tv_sec)
            if name == "config.ini" { config = modified } else { newest = max(newest, modified) }
        }
        return newest > 0 ? newest : config
    }

    /// A system image only idle AVDs boot (cdm's `register_idle_images`).
    struct IdleImage: Equatable, Sendable {
        let path: String
        /// The AVDs that boot it, each once, in the order they were found.
        let avds: [String]
        /// When the most recently run of them last ran.
        let lastStarted: Int
    }

    /// cdm's `register_idle_images`: each existing, non-empty match of `patterns` that some
    /// AVD in `users` boots, when none of the AVDs booting it has run in `days` days
    /// before `now`. An image no AVD boots is the `.androidImages` row's, not this one's.
    static func idleImages(patterns: [String], users: [AVDImageUser], days: Int, now: Int,
                           home: String, physicalHome: String) -> [IdleImage] {
        let cutoff = now - days * 86_400
        var found: [IdleImage] = []
        var seen = Set<String>()
        for pattern in patterns where !pattern.isEmpty {
            let expanded = expandTilde(pattern, home: home)
            guard !isOutOfScope(expanded, home: home) else { continue }
            for match in expandGlob(expanded) where seen.insert(match).inserted && isNonEmpty(match) {
                let booting = users.filter { endsWithAny(match, [$0.ref]) }
                guard !booting.isEmpty, booting.allSatisfy({ $0.lastStarted < cutoff }),
                      isSafeTarget(match, home: home, physicalHome: physicalHome) else { continue }
                var avds: [String] = []
                // One AVD is found twice: as <home>/<name>.avd and through <name>.ini.
                for user in booting where !avds.contains(user.avd) { avds.append(user.avd) }
                found.append(IdleImage(path: match, avds: avds, lastStarted: booting.map(\.lastStarted).max() ?? 0))
            }
        }
        return found
    }

    // MARK: Older versions

    /// cdm's `newest_version`: the path whose name carries the highest version. Numeric
    /// fields compare as numbers (36.1 above 36, 37.0 above 36.1), and a release ranks
    /// above its own pre-release (36.0.0 above 36.0.0-rc1); equal versions go by path.
    static func newestVersion(_ paths: [String]) -> String? {
        paths.max { versionKey($0).utf8.lexicographicallyPrecedes(versionKey($1).utf8) }
    }

    /// The sort key cdm builds in awk: the name's first run of digits and dots, as eight
    /// fields zero-padded to 20 digits (a missing field is 0), then `~` for a release or
    /// `!` when anything follows the version; and the path itself, for a tie.
    static func versionKey(_ path: String) -> String {
        let name = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
        var version = ""
        var tail = name
        if let start = name.firstIndex(where: { $0.isASCII && $0.isNumber }) {
            let run = name[start...].prefix { ($0.isASCII && $0.isNumber) || $0 == "." }
            version = String(run)
            tail = String(name[run.endIndex...])
        }
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        var key = ""
        for index in 0..<8 {
            let field = index < fields.count && !fields[index].isEmpty ? String(fields[index]) : "0"
            key += String(repeating: "0", count: max(0, 20 - field.count)) + field + "."
        }
        return key + (!version.isEmpty && tail.isEmpty ? "~" : "!") + "\t" + path
    }

    /// cdm's `register_older`: each pattern is one family of sibling versions, and every
    /// existing, non-empty match but the family's newest is offered — once, and only when
    /// the safety gate would let it go. A family of one offers nothing.
    static func olderVersionPaths(patterns: [String], home: String, physicalHome: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for pattern in patterns where !pattern.isEmpty {
            let expanded = expandTilde(pattern, home: home)
            guard !isOutOfScope(expanded, home: home) else { continue }
            let family = expandGlob(expanded).filter(isNonEmpty)
            guard family.count > 1, let newest = newestVersion(family) else { continue }
            for path in family where path != newest && isSafeTarget(path, home: home, physicalHome: physicalHome)
                && seen.insert(path).inserted {
                found.append(path)
            }
        }
        return found
    }

    // MARK: Claude Code transcripts

    /// A Claude Code session id: a UUID, 36 characters of ASCII hex digits and dashes.
    static func isSessionID(_ name: String) -> Bool {
        name.utf8.count == 36 && name.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte) || byte == 0x2D
        }
    }

    /// The session ids Claude Code's `sessions/*.json` files name: its running sessions.
    /// A listed id counts whether or not its process is still alive, since a crash leaves
    /// the file until the next launch. Read the way cdm greps them, so a file that is not
    /// valid JSON still names its session.
    static func runningSessionIDs(claudeFolder: String) -> Set<String> {
        let folder = claudeFolder + "/sessions"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder),
              let pattern = try? NSRegularExpression(pattern: #""sessionId"\s*:\s*"([^"]*)""#) else { return [] }
        var ids = Set<String>()
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            guard fileType(folder + "/" + name) == S_IFREG,
                  let text = try? String(contentsOfFile: folder + "/" + name, encoding: .utf8), text.utf8.count <= 1 << 20,
                  let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text), !text[range].isEmpty else { continue }
            ids.insert(String(text[range]))
        }
        return ids
    }

    /// The old sessions cdm's `register_transcripts` offers.
    struct OldTranscripts: Equatable, Sendable {
        /// Each session's transcript, then its folder when it has one.
        let paths: [String]
        let sessions: Int
    }

    /// cdm's `register_transcripts`: in each project folder `patterns` match, the
    /// `<id>.jsonl` transcripts unchanged for more than `days` days before `now`, each
    /// with its `<id>/` folder of subagent transcripts and tool output. Never a running
    /// session's, and never a name that is not a session id — so never auto memory's
    /// `memory/`.
    static func oldTranscripts(patterns: [String], days: Int, now: Int, home: String, physicalHome: String) -> OldTranscripts {
        var folders: [String] = []
        var seen = Set<String>()
        for pattern in patterns where !pattern.isEmpty {
            let expanded = expandTilde(pattern, home: home)
            guard !isOutOfScope(expanded, home: home) else { continue }
            for match in expandGlob(expanded) where fileType(match) == S_IFDIR && seen.insert(match).inserted {
                folders.append(match)
            }
        }
        // The sessions/ that lists running sessions sits beside projects/.
        var running = Set<String>()
        var roots = Set<String>()
        for folder in folders {
            guard let projects = folder.range(of: "/projects/", options: .backwards) else { continue }
            let root = String(folder[..<projects.lowerBound])
            if roots.insert(root).inserted { running.formUnion(runningSessionIDs(claudeFolder: root)) }
        }
        let cutoff = now - days * 86_400
        var paths: [String] = []
        var sessions = 0
        for folder in folders {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
            for name in names where name.hasSuffix(".jsonl") {
                let id = String(name.dropLast(".jsonl".count))
                let transcript = folder + "/" + name
                var info = stat()
                guard isSessionID(id), !running.contains(id), lstat(transcript, &info) == 0,
                      info.st_mode & S_IFMT == S_IFREG, Int(info.st_mtimespec.tv_sec) < cutoff,
                      isSafeTarget(transcript, home: home, physicalHome: physicalHome) else { continue }
                paths.append(transcript)
                sessions += 1
                let sessionFolder = folder + "/" + id
                var folderInfo = stat()
                if lstat(sessionFolder, &folderInfo) == 0, folderInfo.st_mode & S_IFMT == S_IFDIR,
                   isSafeTarget(sessionFolder, home: home, physicalHome: physicalHome) {
                    paths.append(sessionFolder)
                }
            }
        }
        return OldTranscripts(paths: paths, sessions: sessions)
    }

    /// The lines of a small text file, each without its trailing `\r`.
    private static func lines(of path: String) -> [String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    // MARK: Sizing

    private struct FileID: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// What `du -sk` reports for `path`: allocated 512-byte blocks of everything below it,
    /// symlinks not followed, a hard-linked file counted once, rounded up to KiB.
    static func allocatedKB(_ path: String) -> Int {
        guard let cPath = strdup(path) else { return 0 }
        defer { free(cPath) }
        var roots: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        // FTS_NOCHDIR: the working directory is per process, and paths are measured on
        // several threads at once.
        guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(tree) }
        var blocks: Int64 = 0
        var linked = Set<FileID>()
        while let entry = fts_read(tree) {
            switch Int32(entry.pointee.fts_info) {
            case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let info = entry.pointee.fts_statp?.pointee else { continue }
                if Int32(entry.pointee.fts_info) != FTS_D, info.st_nlink > 1,
                   !linked.insert(FileID(device: info.st_dev, inode: info.st_ino)).inserted {
                    continue
                }
                blocks += Int64(info.st_blocks)
            default:
                continue
            }
        }
        return Int((blocks + 1) / 2)
    }

    // MARK: Safety gate

    /// Folders no rule may reach, whatever it says. cdm's list, unchanged.
    static let protectedFolders = [
        "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
        ".ssh", ".gnupg", "Library/Mobile Documents",
    ]

    /// `home` with every symlink resolved (cdm's `HOME_P`), for the physical check.
    static func physicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// cdm's `is_safe_target`, the last line of defense before anything is deleted, and
    /// one no rule can opt out of: a non-empty, absolute, existing path without `..`,
    /// outside the protected folders, under `home` both as written and once the parent's
    /// symlinks are resolved — so a symlinked component cannot walk a delete off the home
    /// tree. `home` itself and `/` are refused.
    static func isSafeTarget(_ path: String, home: String, physicalHome: String) -> Bool {
        guard !path.isEmpty, path.hasPrefix("/") else { return false }
        if ["/", home, home + "/", physicalHome, physicalHome + "/"].contains(path) { return false }
        guard !path.contains(".."), exists(path) else { return false }
        for folder in protectedFolders {
            let root = home + "/" + folder
            if path == root || path.hasPrefix(root + "/") { return false }
        }
        guard path.hasPrefix(home + "/") else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard let resolved = realpath(parent, nil) else { return false }
        defer { free(resolved) }
        return (String(cString: resolved) + "/").hasPrefix(physicalHome + "/")
    }

    // MARK: Deletion

    enum DeleteOutcome: Equatable, Sendable {
        /// Nothing there any more, e.g. removed by an overlapping category earlier in the run.
        case alreadyGone
        case deleted
        case trashed
        /// Refused by `isSafeTarget`.
        case unsafe
        case failed(String)

        var removed: Bool { self == .deleted || self == .trashed }
    }

    /// The one folder `.emptytrash` may empty, whatever path its rule names. cdm's
    /// `empty_trash` ignores the rule's paths the same way.
    static func trashPath(home: String) -> String { home + "/.Trash" }

    /// Moves an item to the user's Trash, where Finder's Put Back can restore it.
    static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// cdm's `delete_path`. `.emptytrash` erases what is inside the Trash (cdm's
    /// `empty_trash`), each item through the safety gate. A symlink is removed, never
    /// followed, whatever the method.
    static func delete(_ path: String, method: CleanDevMacRule.Method, home: String, physicalHome: String,
                       trash: (URL) throws -> Void = moveToTrash) -> DeleteOutcome {
        guard exists(path) else { return .alreadyGone }
        guard isSafeTarget(path, home: home, physicalHome: physicalHome) else { return .unsafe }
        let fm = FileManager.default
        switch method {
        case .trash:
            do {
                try trash(URL(fileURLWithPath: path))
                return .trashed
            } catch {
                return .failed(error.localizedDescription)
            }
        case .emptytrash:
            guard path == trashPath(home: home) else { return .unsafe }
            guard let items = try? fm.contentsOfDirectory(atPath: path) else {
                return .failed("The Trash could not be read")
            }
            var failure: String?
            for item in items {
                let itemPath = path + "/" + item
                guard isSafeTarget(itemPath, home: home, physicalHome: physicalHome) else { continue }
                do { try fm.removeItem(atPath: itemPath) } catch { failure = error.localizedDescription }
            }
            return failure.map { .failed($0) } ?? .deleted
        case .rm, .rmforce:
            if method == .rmforce { makeWritable(path) }
            do {
                try fm.removeItem(atPath: path)
                return .deleted
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    /// `chmod -R u+w` for the folders of a read-only tree (Go's module cache, Cargo's
    /// sources): a file can be unlinked from a writable folder whatever its own mode.
    static func makeWritable(_ path: String) {
        guard let cPath = strdup(path) else { return }
        defer { free(cPath) }
        var roots: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
        defer { fts_close(tree) }
        while let entry = fts_read(tree) {
            guard Int32(entry.pointee.fts_info) == FTS_D, let info = entry.pointee.fts_statp?.pointee,
                  info.st_mode & S_IWUSR == 0 else { continue }
            chmod(entry.pointee.fts_path, (info.st_mode & 0o7777) | S_IWUSR)
        }
    }

    // MARK: Running apps

    /// Every running process name as `proc_name` reports it (up to 31 bytes), the names a
    /// rule's `procs` lists. About a millisecond for a few hundred processes.
    static func runningProcessNames() -> Set<String> {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var names = Set<String>()
        var buffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
                names.insert(buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
            }
        }
        return names
    }

    // MARK: Disk status

    /// The volume holding `home`, as `df -Pk` reports it. Used is derived from total and
    /// free, never read: on APFS the three columns do not add up, and side by side they
    /// have to.
    struct DiskStats: Equatable, Sendable {
        let totalKB: Int
        let freeKB: Int

        var usedKB: Int { totalKB - freeKB }
        var usedPercent: Int { totalKB > 0 ? (usedKB * 100 + totalKB / 2) / totalKB : 0 }

        /// "228.27 GB total · 161.72 GB used (71%) · 66.55 GB free"
        var line: String {
            "\(CleanDevMacEngine.humanKB(totalKB)) total · \(CleanDevMacEngine.humanKB(usedKB)) used (\(usedPercent)%) · \(CleanDevMacEngine.humanKB(freeKB)) free"
        }
    }

    /// `$HOME`, not `/`: since Catalina the root is a small read-only system volume.
    static func diskStats(path: String) -> DiskStats? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let blockSize = Int64(info.f_bsize)
        let total = Int64(info.f_blocks) * blockSize / 1024
        let free = min(Int64(info.f_bavail) * blockSize / 1024, total)
        guard total > 0 else { return nil }
        return DiskStats(totalKB: Int(total), freeKB: Int(free))
    }

    // MARK: Formatting

    /// cdm's `human_kb`: whole KiB to "1.25 GB", "640 MB" or "512 KB". Always a "." for
    /// the decimal separator, whatever the locale, as cdm pins it.
    static func humanKB(_ kb: Int) -> String {
        if kb >= 1_048_576 { return String(format: "%.2f GB", Double(kb) / 1_048_576) }
        if kb >= 1024 { return String(format: "%.0f MB", Double(kb) / 1024) }
        return "\(max(kb, 0)) KB"
    }

    /// `path` with `home` shown as `~`.
    static func displayPath(_ path: String, home: String) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: Clean log

    /// cdm's receipt log, shared with cdm so one file records every clean either tool ran.
    static func logURL(home: String) -> URL {
        URL(fileURLWithPath: home + "/.cleandevmac/clean.log")
    }

    /// cdm's cap: past 1 MiB the log keeps its newest 256 KiB. A tool that reclaims disk
    /// has no business being what quietly fills it.
    static let logMaxBytes = 1024 * 1024
    static let logKeepBytes = 256 * 1024

    /// `date(1)`'s default format, in English whatever the locale. Two per clean, so a
    /// formatter is simply made each time.
    static func logDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss zzz yyyy"
        return formatter.string(from: date)
    }

    /// cdm's `rotate_log` on the log's bytes: nil when under the cap, else a header plus
    /// the newest `logKeepBytes`, minus the partial line the cut lands in.
    static func rotatedLog(_ data: Data, now: Date) -> Data? {
        guard data.count > logMaxBytes else { return nil }
        var tail = data.suffix(logKeepBytes)
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
            tail = tail[tail.index(after: newline)...]
        } else {
            tail = Data()[...]
        }
        let rule = String(repeating: "=", count: 50)
        let header = "\(rule)\nTruncated \(logDate(now)): older entries dropped at \(logMaxBytes) bytes.\n\(rule)\n"
        return Data(header.utf8) + tail
    }

    /// Appends one run's receipt, rotating first. Best effort: a log that cannot be written
    /// never stops or fails a clean.
    static func appendToLog(_ text: String, home: String, now: Date = Date()) {
        let url = logURL(home: home)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: url), let rotated = rotatedLog(existing, now: now) {
            try? rotated.write(to: url, options: .atomic)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}
