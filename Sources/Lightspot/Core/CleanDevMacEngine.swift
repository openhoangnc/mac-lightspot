import Foundation
import Darwin

// MARK: - cdm Engine
//
// The file-system half of cdm, ported from its bash: pattern expansion, sizing, the safety
// gate every deletion passes, deletion itself, the disk line with its restart estimate, the
// Claude Code note and the clean log. All of it blocks, so it runs on CleanDevMacProvider's
// queue, never on the keystroke path.

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

    /// cdm's `find -mtime +days`: unchanged for more than `days` whole days before `now`.
    /// macOS's find drops the part of a day (the man page says it rounds up; it does
    /// not), so a file 30 days and 23 hours old is not past 30 days until it is 31.
    static func isOlder(mtime: Int, than days: Int, now: Int) -> Bool {
        (now - mtime) / 86_400 > days
    }

    /// cdm's `register_transcripts`: in each project folder `patterns` match, the
    /// `<id>.jsonl` transcripts older than `days` days (`isOlder`), each with its `<id>/`
    /// folder of subagent transcripts and tool output. Never a running session's, and never
    /// a name that is not a session id — so never auto memory's `memory/`.
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
        var paths: [String] = []
        var sessions = 0
        for folder in folders {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
            for name in names where name.hasSuffix(".jsonl") {
                let id = String(name.dropLast(".jsonl".count))
                let transcript = folder + "/" + name
                var info = stat()
                guard isSessionID(id), !running.contains(id), lstat(transcript, &info) == 0,
                      info.st_mode & S_IFMT == S_IFREG, isOlder(mtime: Int(info.st_mtimespec.tv_sec), than: days, now: now),
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

    struct FileID: Hashable, Sendable {
        let device: dev_t
        let inode: ino_t
    }

    /// A file with more than one link, as one walk met it.
    struct LinkedFile: Sendable {
        /// Its link count.
        let links: Int
        /// How many of those links the walk went through.
        var met: Int
        let blocks: Int64
    }

    /// One walk below a path: the 512-byte blocks of its folders and single-link files,
    /// and every file with more than one link, kept apart so that `allocatedKB(_:)` can
    /// count a file two paths of a row share the way `du` does.
    struct Usage: Sendable {
        var blocks: Int64 = 0
        var linked: [FileID: LinkedFile] = [:]
    }

    /// Walks `path` as `du` does, symlinks not followed; with `oneFileSystem`, as `du -x`
    /// does. Nil once `deadline` has passed, as cdm's `bounded` gives up on a du.
    static func usage(_ path: String, oneFileSystem: Bool = false, until deadline: Date = .distantFuture) -> Usage? {
        guard let cPath = strdup(path) else { return Usage() }
        defer { free(cPath) }
        var roots: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        // FTS_NOCHDIR: the working directory is per process, and paths are measured on
        // several threads at once.
        guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | (oneFileSystem ? FTS_XDEV : 0), nil) else { return Usage() }
        defer { fts_close(tree) }
        var usage = Usage()
        var visited = 0
        while let entry = fts_read(tree) {
            // The clock is read on the first entry and every 1024th after it.
            visited += 1
            if visited % 1024 == 1, Date() >= deadline { return nil }
            switch Int32(entry.pointee.fts_info) {
            case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let info = entry.pointee.fts_statp?.pointee else { continue }
                if Int32(entry.pointee.fts_info) != FTS_D, info.st_nlink > 1 {
                    usage.linked[FileID(device: info.st_dev, inode: info.st_ino),
                                 default: LinkedFile(links: Int(info.st_nlink), met: 0, blocks: Int64(info.st_blocks))].met += 1
                } else {
                    usage.blocks += Int64(info.st_blocks)
                }
            default:
                continue
            }
        }
        return usage
    }

    /// What `du -sk` prints for each path when handed them all at once, in order, from
    /// each path's own walk: cdm sizes a row with one `du` over its paths. A file
    /// hard-linked into two of them counts in the first. Once the walks have met every
    /// link of a file, du forgets it, so a later path that meets it again counts it again
    /// (a folder, then a folder inside it). Rounded up to KiB per path, as du rounds.
    static func allocatedKB(_ walks: [Usage]) -> [Int] {
        var met: [FileID: Int] = [:]
        return walks.map { walk in
            var blocks = walk.blocks
            for (id, file) in walk.linked {
                let before = met[id, default: 0]
                // du counts its 1st, (n+1)th, (2n+1)th… meeting of a file with n links: the
                // multiples of n among this walk's meetings, numbered from 0 across the row.
                let counted = (before + file.met + file.links - 1) / file.links - (before + file.links - 1) / file.links
                blocks += Int64(counted) * file.blocks
                met[id] = before + file.met
            }
            return Int((blocks + 1) / 2)
        }
    }

    /// What `du -sk` reports for `path`: allocated 512-byte blocks of everything below it,
    /// symlinks not followed, a hard-linked file counted once, rounded up to KiB.
    static func allocatedKB(_ path: String) -> Int {
        allocatedKB([usage(path) ?? Usage()])[0]
    }

    // MARK: What a restart would free

    /// cdm's restart estimate: what a restart gives back that no clean can delete as
    /// files. Each part is 0 when it cannot be measured.
    struct RestartEstimate: Equatable, Sendable {
        /// macOS's swap files.
        var swapKB = 0
        /// The temp folders a boot empties.
        var tempKB = 0
        /// Files deleted while an app still holds them open.
        var heldKB = 0
        /// The three apps holding the most of `heldKB`, biggest first.
        var heldApps: [String] = []

        var totalKB: Int { swapKB + tempKB + heldKB }

        /// cdm's `restart_line`: nil unless the total is at least `restartNoteMinKB` and at
        /// least `freeKB`, past which a restart gives back more than any clean can. Parts
        /// under 1 MiB are left out, and the holders are named only from
        /// `restartHoldersMinKB`: below that they are daemons nobody can quit.
        func line(freeKB: Int) -> String? {
            guard totalKB >= CleanDevMacEngine.restartNoteMinKB, totalKB >= freeKB else { return nil }
            var parts: [String] = []
            if swapKB >= 1024 { parts.append("\(CleanDevMacEngine.humanKB(swapKB)) of swap") }
            if tempKB >= 1024 { parts.append("\(CleanDevMacEngine.humanKB(tempKB)) of temp files") }
            if heldKB >= 1024 {
                var held = "\(CleanDevMacEngine.humanKB(heldKB)) of deleted files still held open"
                if heldKB >= CleanDevMacEngine.restartHoldersMinKB, !heldApps.isEmpty {
                    held += " by \(heldApps.joined(separator: ", ")) — quitting them frees that part now"
                }
                parts.append(held)
            }
            return "A restart would free about \(CleanDevMacEngine.humanKB(totalKB)): \(parts.joined(separator: ", "))"
        }
    }

    /// cdm's `RESTART_NOTE_MIN_KB` and `RESTART_HOLDERS_MIN_KB`.
    static let restartNoteMinKB = 102_400
    static let restartHoldersMinKB = 1_048_576

    /// A mounted volume, as a row of `df -Pk` shows it.
    struct Volume: Equatable, Sendable {
        let device: String
        let mountPoint: String
        /// df's Used column: what the volume itself holds.
        let usedKB: Int
    }

    /// The volume holding `path`. Its Used is what df prints: on APFS the volume's own
    /// share of its container (`ATTR_VOL_SPACEUSED`), where statfs's free blocks are the
    /// whole container's (it put the VM volume's swap at 177 GB, df at 7); statfs's
    /// blocks in use where a volume cannot say.
    static func volume(of path: String) -> Volume? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        func text<Field>(_ field: Field) -> String {
            withUnsafeBytes(of: field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
        let mountPoint = text(info.f_mntonname)
        var usedBytes = (Int64(info.f_blocks) - Int64(info.f_bfree)) * Int64(info.f_bsize)
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        var reply = [UInt8](repeating: 0, count: 16)
        // Volume attributes are asked of the volume's root. The reply is packed on 4-byte
        // boundaries: its length, then the off_t.
        if getattrlist(mountPoint, &request, &reply, reply.count, 0) == 0,
           reply.withUnsafeBytes({ $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }) >= 12 {
            usedBytes = reply.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
        }
        return Volume(device: text(info.f_mntfromname), mountPoint: mountPoint, usedKB: Int(usedBytes / 1024))
    }

    /// The APFS container a device is in: the device minus its `s<N>…` suffix, so
    /// `/dev/disk3s5` and `/dev/disk3s6` are both `/dev/disk3`'s, and `/dev/disk12s1` is not
    /// `/dev/disk1`'s. Like cdm's `%%s[[:digit:]]*`, it cuts at the first `s` and digit.
    static func container(of device: String) -> String {
        let bytes = Array(device.utf8)
        for index in bytes.indices.dropLast()
        where bytes[index] == UInt8(ascii: "s") && (0x30...0x39).contains(bytes[index + 1]) {
            return String(decoding: bytes[..<index], as: UTF8.self)
        }
        return device
    }

    /// cdm's `swap_stats`: the VM volume's Used column, counted only when that volume shares
    /// the home volume's APFS container, i.e. when the swap is inside the disk line's
    /// "used". The VM row must be mounted at `/System/Volumes/VM`: for a path that is not
    /// its own mount, statfs answers for whichever volume holds it.
    static func swapKB(home: Volume, vm: Volume?) -> Int {
        guard let vm, vm.mountPoint == "/System/Volumes/VM", home.device.hasPrefix("/dev/disk"),
              container(of: home.device) == container(of: vm.device) else { return 0 }
        return vm.usedKB
    }

    /// cdm's `BOOT_TEMP_DIRS`: the per-user `DARWIN_USER_TEMP_DIR` and `/private/tmp`, the
    /// two temp folders a boot empties; not `/private/var/tmp`, which survives one.
    static func bootTempFolders() -> [String] {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let user = length > 0 && length <= buffer.count
            ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : ""
        return [user, "/private/tmp"]
    }

    /// cdm's `temp_stats`: what `folders` hold, counting only a folder on the device
    /// `homeDevice` names (anywhere else it is not in "used"), each walked as `du -skx`
    /// within five seconds or not at all: a temp folder a runaway process filled can hold
    /// millions of files.
    static func tempKB(homeDevice: String, folders: [String]) -> Int {
        var total = 0
        for folder in folders where !folder.isEmpty && fileType(folder) == S_IFDIR {
            guard volume(of: folder)?.device == homeDevice,
                  let walk = usage(folder, oneFileSystem: true, until: Date().addingTimeInterval(5)) else { continue }
            total += allocatedKB([walk])[0]
        }
        return total
    }

    /// cdm's `held_stats` parse of `lsof -F pctsiD`: deleted files still held open, in KiB,
    /// and the three biggest holders. lsof lists one record per open handle, so a file
    /// counts once, by device and inode, and only a regular file; it counts for the first
    /// process that holds it.
    static func heldOpen(lsofFields output: String) -> (kb: Int, apps: [String]) {
        var seen = Set<String>()
        var total: Int64 = 0
        var byApp: [String: Int64] = [:]
        var command = "", type = "", size = "", inode = "", device = ""
        func flush() {
            if type == "REG", !size.isEmpty, !inode.isEmpty, seen.insert(device + ":" + inode).inserted {
                let bytes = Int64(size) ?? 0
                total += bytes
                byApp[command, default: 0] += bytes
            }
            type = ""; size = ""; inode = ""; device = ""
        }
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p", "f": flush()
            case "c": command = value
            case "t": type = value
            case "s": size = value
            case "i": inode = value
            case "D": device = value
            default: break
            }
        }
        flush()
        let apps = byApp.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map(\.key)
        return (Int(total / 1024), apps)
    }

    /// cdm's `held_stats`: the files on the volume mounted at `mountPoint` that were
    /// deleted while an app still holds them open (their blocks come back only when it
    /// closes them), from `lsof -a -nP +L1` within five seconds. `-a` ANDs the two filters,
    /// which lsof would otherwise OR into every open file. Only this user's processes are
    /// visible, so the figure is a floor.
    static func heldOpen(mountPoint: String) -> (kb: Int, apps: [String]) {
        heldOpen(lsofFields: output(of: "/usr/sbin/lsof", ["-a", "-nP", "+L1", "-F", "pctsiD", mountPoint], timeout: 5))
    }

    /// What `executable` prints to stdout, read as it comes so a full pipe never blocks it
    /// (invariant 1). At `timeout` seconds it is stopped, its process group with it, and
    /// what it printed so far is returned, as a pipe into cdm's awk gets it when `bounded`
    /// kills the command; a child that left the group and keeps the pipe open is waited
    /// for one second more, not forever.
    static func output(of executable: String, _ arguments: [String], timeout: TimeInterval) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let reader = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(reader, F_SETFL, fcntl(reader, F_GETFL, 0) | O_NONBLOCK)
        var deadline = Date().addingTimeInterval(timeout)
        var stopped = false
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(reader, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count < 0 && (errno == EAGAIN || errno == EINTR) {
                if Date() >= deadline {
                    guard !stopped else { break }
                    if process.isRunning { process.terminate() }
                    stopped = true
                    deadline = Date().addingTimeInterval(1)
                }
                usleep(10_000)
            } else {
                break
            }
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Blocking, five seconds at most per part: cdm's `restart_stats` for the volume
    /// holding `home`.
    static func restartEstimate(home: String) -> RestartEstimate {
        guard let homeVolume = volume(of: home) else { return RestartEstimate() }
        let held = heldOpen(mountPoint: homeVolume.mountPoint)
        return RestartEstimate(
            swapKB: swapKB(home: homeVolume, vm: volume(of: "/System/Volumes/VM")),
            tempKB: tempKB(homeDevice: homeVolume.device, folders: bootTempFolders()),
            heldKB: held.kb,
            heldApps: held.apps
        )
    }

    // MARK: Claude Code's session history

    /// cdm's `CLAUDE_DIR`: Claude Code's folder, `CLAUDE_CONFIG_DIR` when that is set.
    static func claudeFolder(home: String, environment: [String: String]) -> String {
        environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
    }

    /// cdm's Claude Code note: how big the session history is, and the setting that has
    /// Claude Code age Claude Desktop and Cowork sessions out too.
    struct ClaudeNote: Equatable, Sendable {
        let summary: String
        let advice: String
    }

    /// cdm's `claude_history_stats`: Claude Code's session history, and how many
    /// transcripts outlived Claude Code's own age limit, which it keeps for sessions from
    /// Claude Desktop and Cowork unless `desktopSessionCleanupPeriodDays` is set.
    struct ClaudeHistory: Equatable, Sendable {
        /// Claude Code's folder.
        let folder: String
        /// What its `projects/` holds.
        let sizeKB: Int
        /// Sessions (`<uuid>.jsonl`) older than `keepDays` days, as `isOlder` counts them.
        let oldTranscripts: Int
        /// Claude Code's `cleanupPeriodDays`; 30 unless settings.json says otherwise.
        let keepDays: Int

        /// cdm's `claude_history_line`: nil unless some transcript outlived the limit and the
        /// history is at least `claudeNoteMinKB`.
        func note(home: String) -> ClaudeNote? {
            guard oldTranscripts > 0, sizeKB >= CleanDevMacEngine.claudeNoteMinKB else { return nil }
            let shown = CleanDevMacEngine.displayPath(folder, home: home)
            return ClaudeNote(
                summary: "\(CleanDevMacEngine.humanKB(sizeKB)) of session history in \(shown)/projects, \(oldTranscripts) \(oldTranscripts == 1 ? "transcript" : "transcripts") older than \(keepDays) days.",
                advice: "Claude Code keeps Claude Desktop and Cowork sessions at any age; to have it delete them after \(keepDays) days too, add \"desktopSessionCleanupPeriodDays\": \(keepDays) to \(shown)/settings.json"
            )
        }
    }

    /// cdm's `CLAUDE_NOTE_MIN_KB`.
    static let claudeNoteMinKB = 1_048_576

    /// `cleanupPeriodDays` as cdm's grep reads it from settings.json: the first number given
    /// for it, on one line, if at least 1.
    static func cleanupPeriodDays(settings: String) -> Int? {
        guard let pattern = try? NSRegularExpression(pattern: #""cleanupPeriodDays"[ \t\r\f\x0B]*:[ \t\r\f\x0B]*([0-9]+)"#),
              let match = pattern.firstMatch(in: settings, range: NSRange(settings.startIndex..., in: settings)),
              let range = Range(match.range(at: 1), in: settings), let days = Int(settings[range]), days >= 1 else { return nil }
        return days
    }

    /// Blocking: cdm's `claude_history_stats` for Claude Code's `folder`. Nil, measuring
    /// nothing, without a `projects/` folder, once settings.json names
    /// `desktopSessionCleanupPeriodDays` (Claude Code then ages those transcripts out
    /// itself), when no transcript is past the limit, or when `projects/` cannot be walked
    /// within ten seconds. Settings are read, never written.
    static func claudeHistory(folder: String, now: Int) -> ClaudeHistory? {
        let projects = folder + "/projects"
        guard fileType(projects) == S_IFDIR else { return nil }
        let settings = FileManager.default.contents(atPath: folder + "/settings.json").map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard !settings.contains("\"desktopSessionCleanupPeriodDays\"") else { return nil }
        let keepDays = cleanupPeriodDays(settings: settings) ?? 30
        // Sessions only, as `oldTranscripts` counts them: `<uuid>.jsonl` right inside a
        // project folder, as cdm's `find -mindepth 2 -maxdepth 2 -type f` finds them, and
        // as old as its `-mtime` says.
        var old = 0
        for project in (try? FileManager.default.contentsOfDirectory(atPath: projects)) ?? [] {
            let projectFolder = projects + "/" + project
            var folderInfo = stat()
            guard lstat(projectFolder, &folderInfo) == 0, folderInfo.st_mode & S_IFMT == S_IFDIR else { continue }
            for name in (try? FileManager.default.contentsOfDirectory(atPath: projectFolder)) ?? [] where name.hasSuffix(".jsonl") {
                var info = stat()
                guard isSessionID(String(name.dropLast(".jsonl".count))), lstat(projectFolder + "/" + name, &info) == 0,
                      info.st_mode & S_IFMT == S_IFREG, isOlder(mtime: Int(info.st_mtimespec.tv_sec), than: keepDays, now: now) else { continue }
                old += 1
            }
        }
        guard old > 0, let walk = usage(projects, until: Date().addingTimeInterval(10)) else { return nil }
        return ClaudeHistory(folder: folder, sizeKB: allocatedKB([walk])[0], oldTranscripts: old, keepDays: keepDays)
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
