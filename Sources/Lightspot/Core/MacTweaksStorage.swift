import Foundation
import Darwin

// MARK: - Mac Tweaks: Free Up Space
//
// Space macOS keeps that its own Storage settings won't give back: old macOS installers,
// iPhone and iPad updates, unavailable simulators, Time Machine's local snapshots, the
// shared aerial videos, Apple's optional apps and other apps' caches. Ported from
// RemoveMacAI's Storage (MIT, see THIRD-PARTY-NOTICES.md) and fitted to Lightspot: every
// row's folders are fixed in code, every path passes `isAllowed` when it is offered and
// again just before it moves, files go to the Trash, what another user owns moves in one
// administrator batch, simulators go through simctl and snapshots through tmutil. Sizes
// are Clean Dev Mac's du-exact walk. All of it blocks, so it runs on MacTweaksProvider's
// queue, and only once the user opens Mac Tweaks.

enum MacTweaksStorage {
    typealias Environment = MacTweaksProvider.Environment

    // MARK: Catalog

    /// The rows, in display order.
    enum RowID: String, CaseIterable, Sendable {
        case installers
        case iosUpdates = "ios-updates"
        case simulators
        case snapshots
        case aerials
        case garageband
        case imovie, keynote, numbers, pages
        case caches
        case cleanDevMac = "clean-dev-mac"
        case storageSettings = "storage-settings"
    }

    /// How a row's items go.
    enum Method: Sendable, Equatable {
        /// To the Trash; what another user owns, through the administrator batch.
        case trash
        /// `simctl delete unavailable`, as this user.
        case simulators
        /// `tmutil deletelocalsnapshots <date>` each, in the administrator batch.
        case snapshots
        case link(MacTweaksLink)
    }

    struct Definition: Sendable {
        let id: RowID
        let title: String
        let symbol: String
        let detail: String
        var caveat: String?
        let isDefault: Bool
        let method: Method
    }

    /// The tag on a row that may need an administrator: macOS asks for Touch ID or the
    /// password, and a file another user owns may still move without either.
    static let passwordTag = "May ask for password"

    /// What the plan says, and the step shows, when the administrator batch will run.
    static let passwordNote = "macOS may ask for Touch ID or your password."

    /// System Settings' Storage pane, as SettingsProvider links it.
    static let storageSettingsLink = "x-apple.systempreferences:com.apple.settings.Storage"

    static let optionalAppDetail = "One of Apple's optional apps. It reinstalls free from the App Store. Your documents stay."

    static let catalog: [Definition] = [
        Definition(id: .installers, title: "macOS installers", symbol: "arrow.down.circle",
                   detail: "Old Install macOS apps left in Applications after an upgrade. The App Store downloads one again if you need it.",
                   isDefault: true, method: .trash),
        Definition(id: .iosUpdates, title: "iPhone and iPad updates", symbol: "iphone",
                   detail: "Software updates Finder downloaded for iPhones and iPads. Finder downloads them again when it needs them.",
                   isDefault: true, method: .trash),
        Definition(id: .simulators, title: "Unavailable simulators", symbol: "apps.iphone",
                   detail: "Simulators whose runtime is no longer installed, so they can't start.",
                   caveat: "Deleted right away by simctl, not moved to the Trash.",
                   isDefault: true, method: .simulators),
        Definition(id: .snapshots, title: "Time Machine local snapshots", symbol: "clock.arrow.circlepath",
                   detail: "Hourly copies Time Machine keeps on this disk between backups. macOS counts them as System Data.",
                   caveat: "Deleted right away. Backups on your backup disk aren't touched.",
                   isDefault: false, method: .snapshots),
        Definition(id: .aerials, title: "Aerial videos", symbol: "photo.on.rectangle",
                   detail: "Videos for the moving aerial wallpapers and screen savers, shared by every account on this Mac. macOS downloads one again when you choose it.",
                   isDefault: false, method: .trash),
        Definition(id: .garageband, title: "GarageBand and its sound library", symbol: "guitars",
                   detail: "One of Apple's optional apps, with the loops and instruments it downloaded. It reinstalls free from the App Store.",
                   isDefault: false, method: .trash),
        Definition(id: .imovie, title: "iMovie", symbol: "film", detail: optionalAppDetail, isDefault: false, method: .trash),
        Definition(id: .keynote, title: "Keynote", symbol: "play.rectangle", detail: optionalAppDetail, isDefault: false, method: .trash),
        Definition(id: .numbers, title: "Numbers", symbol: "tablecells", detail: optionalAppDetail, isDefault: false, method: .trash),
        Definition(id: .pages, title: "Pages", symbol: "doc.richtext", detail: optionalAppDetail, isDefault: false, method: .trash),
        Definition(id: .caches, title: "App caches", symbol: "archivebox",
                   detail: "Files apps keep to start faster. Apps rebuild them, so the next launch can be slower. Developer and browser caches are in Clean Dev Mac.",
                   caveat: "Quit your apps first. macOS's own caches stay.",
                   isDefault: false, method: .trash),
        Definition(id: .cleanDevMac, title: "Developer caches and project junk", symbol: "sparkles",
                   detail: "Opens Clean Dev Mac.", isDefault: false, method: .link(.cleanDevMac)),
        Definition(id: .storageSettings, title: "More in System Settings", symbol: "gearshape",
                   detail: "iPhone backups, Messages attachments and other files only macOS can manage.",
                   isDefault: false, method: .link(.settings(deepLink: storageSettingsLink))),
    ]

    static func definition(_ id: RowID) -> Definition {
        catalog.first { $0.id == id }!
    }

    static func method(of row: MacTweaksRow) -> Method? {
        RowID(rawValue: row.id).map { definition($0).method }
    }

    /// Apple's optional apps: the bundle in /Applications, and the identifier it must carry.
    /// A `Pages.app` that isn't Apple's is never offered.
    static let optionalApps: [(id: RowID, app: String, bundleID: String)] = [
        (.garageband, "GarageBand.app", "com.apple.garageband10"),
        (.imovie, "iMovie.app", "com.apple.iMovieApp"),
        (.keynote, "Keynote.app", "com.apple.iWork.Keynote"),
        (.numbers, "Numbers.app", "com.apple.iWork.Numbers"),
        (.pages, "Pages.app", "com.apple.iWork.Pages"),
    ]

    /// An installer is Apple's when its identifier starts with this.
    static let installerBundlePrefix = "com.apple.InstallAssistant"

    /// GarageBand's sound library: three folders, each named exactly, under /Library.
    static let soundLibrary: [(folder: String, name: String)] = [
        ("Library/Application Support", "GarageBand"),
        ("Library/Application Support", "Logic"),
        ("Library/Audio/Apple Loops", "Apple"),
    ]

    /// Apps that share GarageBand's sound library; while one is installed the library stays.
    static let soundLibraryApps: [(bundleID: String, name: String)] = [
        ("com.apple.logic10", "Logic Pro"),
        ("com.apple.mainstage3", "MainStage"),
    ]

    /// macOS's own caches without a `com.apple.` name: RemoveMacAI's list, plus what macOS
    /// wrote on the Mac this was ported on (Setup Assistant's `MiniLauncher` and
    /// `mbuseragent`, the drawing framework's `Brushes`). Lowercased.
    static let appleCacheNames: Set<String> = [
        "amsdatamigratortool", "animoji", "apple", "askpermissiond", "cloudkit", "colorsync", "crashreporter",
        "energykit", "familycircle", "familycircled", "gamekit", "geoservices", "icloudmailagent", "jetpackcache",
        "maps", "metal", "passkit", "protectedcloudstorage", "screentimeagent", "siritts", "speechsynthesis",
        "storeassetd", "storedownloadd",
        "brushes", "mbuseragent", "minilauncher",
    ]

    /// Lowercased name prefixes macOS's caches carry: `com.apple.`, and the Apple Account
    /// picture (`AAProfilePicture_<UUID>.png`).
    static let appleCachePrefixes = ["com.apple.", "aaprofilepicture"]

    /// Lightspot's own cache folder stays too.
    static let ownCacheNames: Set<String> = ["com.lightspot.app"]

    static func isAppleCache(_ name: String) -> Bool {
        let lower = name.lowercased()
        return appleCacheNames.contains(lower) || appleCachePrefixes.contains { lower.hasPrefix($0) }
    }

    // MARK: Roots

    /// The fixed folders, as written and where they must resolve: the home folder and the
    /// system root ("/" on a real Mac, a temp folder in tests). Made once per scan or apply,
    /// for one thread.
    final class Roots {
        let home: String
        let physicalHome: String
        /// "" for "/", so that `system + "/Applications"` is "/Applications".
        let system: String
        let physicalSystem: String
        private let loadCleanDevMacRules: () -> CleanDevMacRuleSet?
        private let findSoundLibrarySharers: () -> [String]

        init(_ environment: Environment) {
            home = environment.home
            physicalHome = MacTweaksStorage.resolved(environment.home) ?? environment.home
            let root = environment.systemRoot == "/" ? "" : environment.systemRoot
            system = root
            physicalSystem = root.isEmpty ? "" : (MacTweaksStorage.resolved(root) ?? root)
            loadCleanDevMacRules = { environment.cleanDevMacRules(environment.home) }
            findSoundLibrarySharers = { MacTweaksStorage.soundLibrarySharers(environment) }
        }

        /// The installed apps that share GarageBand's sound library: LaunchServices is asked
        /// the first time a library folder is looked at, which only GarageBand's row does.
        private(set) lazy var soundLibrarySharers: [String] = findSoundLibrarySharers()

        /// The `~/Library/Caches` entries Clean Dev Mac's rules reach, as globs: read the first
        /// time App caches looks, then kept for this scan.
        private(set) lazy var cleanDevMacCacheGlobs: [String] = MacTweaksStorage.cacheGlobs(of: loadCleanDevMacRules(), home: home)

        /// An entry the cleaner offers, or offers part of: App caches leaves it to Clean Dev
        /// Mac, so the two never count the same folder.
        func isCleanDevMacCache(_ name: String) -> Bool {
            cleanDevMacCacheGlobs.contains { fnmatch($0, name, FNM_PERIOD | FNM_CASEFOLD) == 0 }
        }

        func inHome(_ relative: String) -> (lexical: String, physical: String) {
            (home + "/" + relative, physicalHome + "/" + relative)
        }

        func inSystem(_ relative: String) -> (lexical: String, physical: String) {
            (system + "/" + relative, physicalSystem + "/" + relative)
        }

        var applications: (lexical: String, physical: String) { inSystem("Applications") }
        var iTunesUpdates: [(lexical: String, physical: String)] {
            [inHome("Library/iTunes/iPhone Software Updates"), inHome("Library/iTunes/iPad Software Updates")]
        }
        var simulatorDevices: (lexical: String, physical: String) { inHome("Library/Developer/CoreSimulator/Devices") }
        var aerials: (lexical: String, physical: String) { inSystem("Library/Application Support/com.apple.idleassetsd/Customer") }
        var caches: (lexical: String, physical: String) { inHome("Library/Caches") }
        var wallpaperIndex: String { home + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist" }
        var trash: String { home + "/.Trash" }

        /// Places nothing here may reach, whatever a row says: the sealed system, and the
        /// folders macOS guards for the user (TCC) or that hold their documents.
        var neverTouched: [String] {
            let guarded = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
                           "Library/Mobile Documents", "Library/Containers", "Library/Group Containers",
                           "Library/Mail", "Library/Messages", "Library/Application Support/MobileSync"]
            return [system + "/System", physicalSystem + "/System"]
                + guarded.flatMap { [home + "/" + $0, physicalHome + "/" + $0] }
        }
    }

    /// One folder a row may take direct children of.
    struct Scope {
        let folder: String
        let physical: String
        let accepts: (String) -> Bool
    }

    /// Where each row's paths may be. Only direct children of these folders, each folder as
    /// written and as it must resolve, never the folder itself.
    static func scopes(_ id: RowID, roots: Roots, environment: Environment) -> [Scope] {
        func scope(_ folder: (lexical: String, physical: String), _ accepts: @escaping (String) -> Bool) -> Scope {
            Scope(folder: folder.lexical, physical: folder.physical, accepts: accepts)
        }
        func visible(_ name: String) -> Bool { !name.hasPrefix(".") }
        switch id {
        case .installers:
            return [scope(roots.applications) { $0.hasPrefix("Install macOS") && $0.hasSuffix(".app") }]
        case .iosUpdates:
            return roots.iTunesUpdates.map { scope($0, visible) }
        case .simulators:
            return [scope(roots.simulatorDevices, isDeviceID)]
        case .aerials:
            // The video folders; not the strings bundle macOS installs beside them.
            return [scope(roots.aerials) { visible($0) && !$0.hasSuffix(".bundle") }]
        case .garageband:
            var scopes = [scope(roots.applications) { $0 == "GarageBand.app" }]
            // The library only while no other app uses it.
            for folder in Set(soundLibrary.map(\.folder)).sorted() {
                let names = Set(soundLibrary.filter { $0.folder == folder }.map(\.name))
                scopes.append(scope(roots.inSystem(folder)) { names.contains($0) && roots.soundLibrarySharers.isEmpty })
            }
            return scopes
        case .imovie, .keynote, .numbers, .pages:
            let app = optionalApps.first { $0.id == id }?.app ?? ""
            return [scope(roots.applications) { $0 == app }]
        case .caches:
            return [scope(roots.caches) {
                visible($0) && !isAppleCache($0) && !ownCacheNames.contains($0.lowercased()) && !roots.isCleanDevMacCache($0)
            }]
        case .snapshots, .cleanDevMac, .storageSettings:
            return []
        }
    }

    /// The first name below `~/Library/Caches` in each of Clean Dev Mac's patterns, as a
    /// glob (`Google`, `*.ShipIt`): a rule that reaches inside an entry takes the whole entry.
    /// A rule naming `~/Library/Caches` itself would take them all.
    static func cacheGlobs(of rules: CleanDevMacRuleSet?, home: String) -> [String] {
        let caches = home + "/Library/Caches"
        var globs: [String] = []
        for pattern in rules?.rules.flatMap(\.patterns) ?? [] {
            let expanded = CleanDevMacEngine.expandTilde(pattern, home: home)
            let glob: String
            if expanded == caches || expanded == caches + "/" {
                glob = "*"
            } else if expanded.hasPrefix(caches + "/") {
                glob = String(expanded.dropFirst(caches.count + 1).prefix { $0 != "/" })
            } else {
                continue
            }
            if !glob.isEmpty && !globs.contains(glob) { globs.append(glob) }
        }
        return globs
    }

    /// Clean Dev Mac's rules as the app has them, never fetched: those the cleaner holds in
    /// memory, else cdm's own `~/.cleandevmac/rules`, else the copy inside Lightspot.app.
    static func cleanDevMacRules(home: String) -> CleanDevMacRuleSet? {
        if let held = CleanDevMacProvider.shared.heldRules { return held }
        let local = CleanDevMacRules.localDirectory(home: home)
        if FileManager.default.fileExists(atPath: local.appendingPathComponent(CleanDevMacRules.indexFileName).path),
           let rules = CleanDevMacRules.load(directory: local, source: .local) {
            return rules
        }
        return CleanDevMacRules.bundledDirectory.flatMap { CleanDevMacRules.load(directory: $0, source: .bundled) }
    }

    /// A simulator device folder's name: a UUID.
    static func isDeviceID(_ name: String) -> Bool {
        UUID(uuidString: name) != nil
    }

    /// The apps installed now that share GarageBand's sound library, by name.
    static func soundLibrarySharers(_ environment: Environment) -> [String] {
        soundLibraryApps.filter { environment.isAppInstalled($0.bundleID) }.map(\.name)
    }

    // MARK: The gate

    /// Whether `path` may be offered, or moved, for row `id`: absolute with no `.`, `..` or
    /// empty segment; a direct child of one of the row's fixed folders that the folder
    /// accepts, never the folder itself; the parent resolving to where that folder must be
    /// (so no symlink on the way leads out of it); the last component itself not a symlink;
    /// nothing in a place macOS guards; and an app or installer has to be Apple's, by
    /// bundle identifier. Checked when the path is offered and again before it moves.
    static func isAllowed(_ path: String, _ id: RowID, environment: Environment, roots: Roots? = nil) -> Bool {
        let roots = roots ?? Roots(environment)
        guard isPlainAbsolute(path) else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        guard let scope = scopes(id, roots: roots, environment: environment).first(where: { $0.folder == parent }),
              scope.accepts(name),
              resolved(parent) == scope.physical else { return false }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { return false }
        let physical = scope.physical + "/" + name
        guard !roots.neverTouched.contains(where: { isInside(path, $0) || isInside(physical, $0) }) else { return false }
        switch id {
        case .installers:
            return bundleIdentifier(ofApp: path)?.hasPrefix(installerBundlePrefix) == true
        case .garageband where name == "GarageBand.app", .imovie, .keynote, .numbers, .pages:
            return bundleIdentifier(ofApp: path) == optionalApps.first { $0.id == id }?.bundleID
        default:
            return true
        }
    }

    /// Absolute, without a trailing slash or an empty, `.` or `..` segment.
    static func isPlainAbsolute(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count > 1, !path.hasSuffix("/") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// `path` with every symlink resolved; nil when it doesn't exist.
    static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    /// The `CFBundleIdentifier` in an app's own Info.plist, read as a file: no `Bundle`, which
    /// would stay cached for the life of the app. Neither `Contents` nor the Info.plist may be
    /// a symlink, which could lend a bundle another app's identity.
    static func bundleIdentifier(ofApp path: String) -> String? {
        var info = stat()
        guard lstat(path + "/Contents", &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              lstat(path + "/Contents/Info.plist", &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              let data = FileManager.default.contents(atPath: path + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    static func owner(of path: String) -> uid_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_uid : nil
    }

    /// Anything at `path`, a symlink included.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// A real folder, not a symlink to one.
    static func isFolder(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// A folder's direct children, sorted; none when it isn't a real folder.
    static func children(of folder: String) -> [String] {
        guard isFolder(folder) else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted().map { folder + "/" + $0 }
    }

    // MARK: simctl and tmutil

    /// simctl from the developer folder `xcode-select -p` names, and only once
    /// `~/Library/Developer/CoreSimulator/Devices` exists: never `/usr/bin/xcrun`, which opens
    /// the Command Line Tools installer on a Mac without them, and with the Command Line
    /// Tools alone there is no simctl at all, so no row and nothing to run.
    static func simctl(_ environment: Environment, roots: Roots) -> String? {
        guard isFolder(roots.simulatorDevices.lexical) else { return nil }
        let selected = environment.run(environment.xcodeSelect, ["-p"], 10)
        let developer = selected.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selected.status == 0, developer.hasPrefix("/") else { return nil }
        let simctl = developer + "/usr/bin/simctl"
        return FileManager.default.isExecutableFile(atPath: simctl) ? simctl : nil
    }

    /// The device folders `simctl list devices unavailable -j` names: each `dataPath`'s
    /// parent (or `<devices>/<udid>` without one), once each, in runtime order.
    static func unavailableSimulatorFolders(json: String, devices: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let runtimes = object["devices"] as? [String: Any] else { return [] }
        var folders: [String] = []
        for runtime in runtimes.keys.sorted() {
            for device in (runtimes[runtime] as? [[String: Any]]) ?? [] {
                let folder: String
                if let dataPath = device["dataPath"] as? String {
                    folder = (dataPath as NSString).deletingLastPathComponent
                } else if let udid = device["udid"] as? String {
                    folder = devices + "/" + udid
                } else {
                    continue
                }
                if !folders.contains(folder) { folders.append(folder) }
            }
        }
        return folders
    }

    /// The dates in `tmutil listlocalsnapshotdates /`: the lines that start with a digit
    /// (its header doesn't), and only digits and dashes, since each goes to tmutil as root.
    static func snapshotDates(tmutilOutput: String) -> [String] {
        tmutilOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter(isSnapshotDate)
    }

    static func isSnapshotDate(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, ("0"..."9").contains(first), text.count <= 32 else { return false }
        return text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Whether the wallpaper store names an aerial: then macOS downloads its video again.
    static func mentionsAerial(plistAt path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return false }
        return "\(plist)".lowercased().contains("aerial")
    }

    // MARK: Scanning

    /// Blocking: the rows with something to offer, in catalog order, the two links last.
    /// `only` limits it to those row IDs (the verify pass). Every path passes the gate;
    /// items macOS won't let Lightspot read measure 0 and are left out, as nothing could
    /// move them either.
    /// `progress` is optional rather than defaulted: a closure argument makes the compiler
    /// copy the whole function once per closure it is called with.
    static func scan(_ environment: Environment, only: Set<String>? = nil,
                     progress: (@Sendable (String) -> Void)? = nil) -> [MacTweaksRow] {
        let roots = Roots(environment)
        func wanted(_ id: RowID) -> Bool { only?.contains(id.rawValue) ?? true }
        func allowed(_ paths: [String], _ id: RowID) -> [String] {
            paths.filter { isAllowed($0, id, environment: environment, roots: roots) }
        }
        var found: [RowID: [String]] = [:]
        var caveats: [RowID: String] = [:]
        var snapshotDates: [String] = []

        if wanted(.installers) || optionalApps.contains(where: { wanted($0.id) }) {
            progress?("Looking in Applications…")
        }
        if wanted(.installers) {
            found[.installers] = allowed(children(of: roots.applications.lexical), .installers)
        }
        for app in optionalApps where wanted(app.id) {
            let path = roots.applications.lexical + "/" + app.app
            guard isAllowed(path, app.id, environment: environment, roots: roots) else { continue }
            var paths = [path]
            if app.id == .garageband {
                let library = soundLibrary.map { roots.inSystem($0.folder).lexical + "/" + $0.name }.filter(exists)
                let sharers = library.isEmpty ? [] : roots.soundLibrarySharers
                if sharers.isEmpty {
                    paths += allowed(library, .garageband)
                } else {
                    caveats[.garageband] = "Its sound library stays, because \(sharers.joined(separator: " and ")) \(sharers.count == 1 ? "uses" : "use") it too."
                }
            }
            found[app.id] = paths
        }
        if wanted(.iosUpdates) {
            found[.iosUpdates] = allowed(roots.iTunesUpdates.flatMap { children(of: $0.lexical) }, .iosUpdates)
        }
        if wanted(.simulators), let simctl = simctl(environment, roots: roots) {
            progress?("Asking simctl about unavailable simulators…")
            let listed = environment.run(simctl, ["list", "devices", "unavailable", "-j"], 60)
            if listed.status == 0 {
                found[.simulators] = allowed(unavailableSimulatorFolders(json: listed.output, devices: roots.simulatorDevices.lexical),
                                             .simulators)
            }
        }
        if wanted(.snapshots) {
            progress?("Asking Time Machine about local snapshots…")
            let listed = environment.run(environment.tmutil, ["listlocalsnapshotdates", "/"], 30)
            if listed.status == 0 { snapshotDates = Self.snapshotDates(tmutilOutput: listed.output) }
        }
        if wanted(.aerials) {
            found[.aerials] = allowed(children(of: roots.aerials.lexical).filter(isFolder), .aerials)
        }
        if wanted(.caches) {
            progress?("Looking at app caches…")
            found[.caches] = allowed(children(of: roots.caches.lexical), .caches)
        }

        // One concurrent measuring pass over every row, each row sized as one du over its
        // paths, as Clean Dev Mac sizes a category.
        let measured = catalog.map(\.id).filter { found[$0]?.isEmpty == false }
        let sizes = CleanDevMacProvider.measure(measured.map { found[$0] ?? [] }) { done, total in
            progress?("Measuring… \(done) of \(total)")
        }
        var rows: [MacTweaksRow] = []
        for definition in catalog where wanted(definition.id) {
            var row = MacTweaksRow(id: definition.id.rawValue, symbol: definition.symbol, title: definition.title,
                                   detail: definition.detail, caveat: caveats[definition.id] ?? definition.caveat,
                                   isDefault: definition.isDefault)
            switch definition.method {
            case .link(let link):
                row.link = link
                rows.append(row)
                continue
            case .snapshots:
                guard !snapshotDates.isEmpty else { continue }
                row.items = snapshotDates.map { MacTweaksItem(target: $0) }
                row.countLabel = "\(snapshotDates.count) \(snapshotDates.count == 1 ? "snapshot" : "snapshots")"
                row.tags = ["Deleted right away", passwordTag]
                row.outcome = "Deleted right away by tmutil"
            case .simulators, .trash:
                guard let index = measured.firstIndex(of: definition.id) else { continue }
                let paths = found[definition.id] ?? []
                row.items = zip(paths, sizes[index]).filter { $0.1 > 0 }.map { path, kb in
                    let owner = environment.ownerOf(path)
                    return MacTweaksItem(target: path, bytes: Int64(kb) * 1024, isForeign: owner != environment.userID)
                }
                guard !row.items.isEmpty else { continue }
                row.bytes = row.items.reduce(0) { $0 + $1.bytes }
                row.revealsInFinder = true
                if definition.method == .simulators {
                    row.tags = ["Deleted right away"]
                    row.outcome = "Deleted right away by simctl"
                } else {
                    row.tags = row.items.contains(where: \.isForeign) ? [passwordTag] : []
                    row.outcome = "Moved to the Trash"
                }
            }
            if definition.id == .aerials, mentionsAerial(plistAt: roots.wallpaperIndex) {
                row.caveat = "You use an aerial wallpaper or screen saver now, so macOS will download it again."
            }
            rows.append(row)
        }

        // A link to the Apple Intelligence section when its models are on disk (their size is
        // the last Apple Intelligence scan's total; nil, so no row, until that section is
        // scanned). On a full scan only.
        if only == nil, let bytes = environment.appleIntelligenceModelBytes(), bytes > 0 {
            var row = MacTweaksRow(id: "apple-intelligence-models", symbol: "sparkles",
                                   title: "Apple Intelligence models",
                                   detail: "The downloaded Apple Intelligence models. Opens the Apple Intelligence section to remove them.")
            row.bytes = bytes
            row.link = .section(.appleIntelligence)
            rows.insert(row, at: rows.firstIndex { $0.isLink } ?? rows.endIndex)
        }
        return rows
    }

    // MARK: Cleaning

    /// One argument for `/bin/sh`, single-quoted: inside single quotes nothing is special
    /// but the quote itself, which becomes `'\''`. Exact for any name, line breaks included;
    /// `runPrivilegedScript` hands the script over untouched.
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The administrator batch, one `/bin/sh` script for both of `runPrivilegedScript`'s
    /// backends (sudo on a pty, and `do shell script`, each run it with `/bin/sh -c`): stdin
    /// from /dev/null, so nothing waits on the pty; every command in its own subshell, so a
    /// failure stops nothing after it; each followed by a `<tag> <n> <status>` line on a line
    /// of its own, so the receipt can say why something stayed; and `exit 0`, so a failed step
    /// is never taken for a failed prompt. What it did is judged by looking again. Programs and
    /// paths are absolute, but for the `./<name>` a step's own `cd` anchors (`guardedMove`):
    /// neither backend promises a working folder or a `HOME`.
    static func adminScript(_ commands: [String], tag: String) -> String {
        (["exec </dev/null"]
            + commands.enumerated().map { "( \($0.element) ) 2>&1; printf '\\n%s %d %d\\n' '\(tag)' \($0.offset + 1) $?" }
            + ["exit 0"]).joined(separator: "; ")
    }

    /// The root `mv` of one item into the Trash, checked again as it runs. It works from inside
    /// the item's folder: `cd -P` into it, on only if `pwd -P` is `physicalParent`, where the
    /// gate found it, then `mv ./<name>`, so the entry moves from the folder just verified even
    /// if the path is swapped for a symlink after the checks (`./` also keeps a name starting
    /// with `-` from reading as an option). And: the Trash still a real folder; the item not a
    /// symlink; nothing yet at the name it goes to (onto a folder, `mv -n` would move it
    /// inside; onto a file, skip it and still exit 0). Each step runs in a subshell of its
    /// own, so the `cd` ends with it.
    static func guardedMove(_ source: String, to destination: String, trash: String, physicalParent: String) -> String {
        let folder = shellQuote((source as NSString).deletingLastPathComponent)
        let item = shellQuote("./" + (source as NSString).lastPathComponent)
        let (d, t) = (shellQuote(destination), shellQuote(trash))
        return "if cd -P -- \(folder) 2>/dev/null && [ \"$(pwd -P)\" = \(shellQuote(physicalParent)) ] "
            + "&& [ -d \(t) ] && [ ! -L \(t) ] && [ ! -L \(item) ] && [ ! -e \(d) ] && [ ! -L \(d) ]; then /bin/mv -n \(item) \(d); "
            + "else echo 'Lightspot: the item or the Trash changed before the move'; exit 1; fi"
    }

    /// Each batch command's exit status and what it printed, from the batch's output, by its
    /// 1-based position. The tag is random, so a file name can't pass for a status line, and
    /// each status line starts a line of its own whatever its command printed, `\r` included.
    static func batchResults(_ output: String, tag: String) -> [Int: (status: Int32, output: String)] {
        var results: [Int: (status: Int32, output: String)] = [:]
        var printed: [String] = []
        for line in output.components(separatedBy: "\n") {
            let fields = line.trimmingCharacters(in: CharacterSet(charactersIn: " \r")).split(separator: " ")
            if fields.count == 3, fields[0] == tag, let index = Int(fields[1]), let status = Int32(fields[2]) {
                results[index] = (status, printed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                printed = []
            } else {
                printed.append(line)
            }
        }
        return results
    }

    /// What a failed command printed, shortened to its reason: mv's "Operation not permitted"
    /// out of "mv: rename <from> to <to>: Operation not permitted".
    static func reason(_ printed: String) -> String {
        let last = printed.split(separator: "\n").last.map(String.init) ?? ""
        guard let colon = last.range(of: ": ", options: .backwards) else { return last }
        return String(last[colon.upperBound...])
    }

    /// Whether moving failed because macOS said no (EPERM or EACCES), rather than for a reason
    /// of its own (a full disk, a name too long).
    static func isPermissionError(_ error: Error) -> Bool {
        posixCodes(error).contains { $0 == EPERM || $0 == EACCES } || chain(error).contains {
            $0.domain == NSCocoaErrorDomain
                && ($0.code == CocoaError.fileWriteNoPermission.rawValue || $0.code == CocoaError.fileReadNoPermission.rawValue)
        }
    }

    /// EACCES: a folder's permissions said no, which an administrator overrides, whoever owns
    /// the item. EPERM is macOS saying no (flags, System Integrity Protection, App Management).
    static func isAccessDenied(_ error: Error) -> Bool {
        posixCodes(error).contains(EACCES)
    }

    private static func chain(_ error: Error) -> [NSError] {
        var errors: [NSError] = []
        var current: NSError? = error as NSError
        while let next = current, errors.count < 8 {
            errors.append(next)
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return errors
    }

    private static func posixCodes(_ error: Error) -> [Int32] {
        chain(error).compactMap { $0.domain == NSPOSIXErrorDomain ? Int32(clamping: $0.code) : nil }
    }

    /// Whether `path` is an app bundle: an installer, an optional app, GarageBand itself; by its
    /// row, never by a name ending in ".app" (a cache folder can be called "com.example.app").
    static func isAppBundle(_ path: String, _ id: RowID) -> Bool {
        switch id {
        case .installers, .imovie, .keynote, .numbers, .pages: return true
        case .garageband: return (path as NSString).lastPathComponent == "GarageBand.app"
        default: return false
        }
    }

    /// What to say about an app macOS wouldn't let go: from macOS 13 on, moving another
    /// developer's app takes the App Management permission, which an ad-hoc signed Lightspot
    /// doesn't have, and would lose with every update.
    static func appManagementAdvice(_ path: String) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return "macOS didn't let Lightspot move \(name). Drag it to the Trash in Finder (⌥↵ shows it), "
            + "or allow Lightspot under Privacy & Security › App Management."
    }

    /// A name for `name` in the Trash: free in the folder and not yet taken by this batch
    /// (`taken` holds the batch's names, lowercased: the disk ignores case). "Name 2.app",
    /// "Name 3.app"… The Trash can't be listed (macOS guards it), but a name in it can be
    /// looked up.
    static func uniqueTrashName(_ name: String, in folder: String, taken: inout Set<String>) -> String {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = name
        var number = 2
        while taken.contains(candidate.lowercased()) || exists(folder + "/" + candidate) {
            candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            number += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }

    /// Puts `row` where the catalog has it among `rows`, which are in catalog order.
    private static func insertInOrder(_ row: MacTweaksRow, into rows: inout [MacTweaksRow]) {
        let position = { (id: String) in catalog.firstIndex { $0.id.rawValue == id } ?? 0 }
        rows.insert(row, at: rows.firstIndex { position($0.id) > position(row.id) } ?? rows.endIndex)
    }

    private static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }

    /// Blocking: frees what `rows` hold, then looks again.
    ///
    /// 1. Every file goes to `FileManager.trashItem` first. When it can't: gone already,
    ///    skipped; refused by a folder's permissions (EACCES), or refused and another user's,
    ///    for the administrator; refused (EPERM) and this user's, an app (App Management) or
    ///    else protected by macOS; anything else, reported as macOS put it.
    /// 2. Only then is a Trash name reserved for each of the administrator's items, so no
    ///    later move can take it, each through the gate once more, and each `mv -n` guarded in
    ///    the script (`guardedMove`). The batch, snapshots included, runs once, after at most
    ///    one prompt, and only if it has something to do.
    /// 3. Simulators go through simctl as this user, after the batch: nothing slow sits
    ///    between the checks and the prompt.
    /// 4. Freed is what Lightspot moved or deleted, less what grew back at the same path:
    ///    never an item gone on its own (listed), nor a fresh scan's guess, whose gate could
    ///    answer differently by now. What stayed, and why, comes from looking, and from what
    ///    the batch printed.
    static func apply(_ rows: [MacTweaksRow], environment: Environment,
                      progress: (@Sendable (String) -> Void)? = nil) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow]) {
        let started = environment.now()
        let roots = Roots(environment)
        func shown(_ path: String) -> String { CleanDevMacEngine.displayPath(path, home: environment.home) }
        var log: [String] = []
        var problems: [String] = []
        var trashed: [MacTweaksItem] = []
        var protected: [MacTweaksItem] = []
        /// The first app macOS kept, which ⌥↵ on the receipt shows in Finder.
        var keptApp: String?
        func appRefused(_ path: String) {
            problems.append(appManagementAdvice(path))
            log.append("not allowed (App Management?): \(shown(path))")
            if keptApp == nil { keptApp = path }
        }

        // 1. The Trash.
        var forAdministrator: [(item: MacTweaksItem, id: RowID)] = []
        let fileRows = rows.filter { method(of: $0) == .trash }
        let fileCount = fileRows.reduce(0) { $0 + $1.items.count }
        if fileCount > 0 { progress?("Moving \(count(fileCount, "item", "items")) to the Trash…") }
        for row in fileRows {
            guard let id = RowID(rawValue: row.id) else { continue }
            for item in row.items {
                let path = item.target
                guard exists(path) else {
                    log.append("gone already: \(shown(path))")
                    continue
                }
                guard isAllowed(path, id, environment: environment, roots: roots) else {
                    log.append("skip (refused): \(path)")
                    problems.append("\(shown(path)) stays: it no longer passes Mac Tweaks' checks.")
                    continue
                }
                do {
                    try environment.moveToTrash(URL(fileURLWithPath: path))
                    trashed.append(item)
                    log.append("trashed: \(shown(path))")
                } catch {
                    guard exists(path) else {
                        log.append("gone already: \(shown(path))")
                        continue
                    }
                    if !isPermissionError(error) {
                        problems.append("\(shown(path)) stays: \(error.localizedDescription)")
                        log.append("failed: \(shown(path)) (\(error.localizedDescription))")
                    } else if isAccessDenied(error) || environment.ownerOf(path) != environment.userID {
                        forAdministrator.append((item, id))
                    } else if isAppBundle(path, id) {
                        appRefused(path)
                    } else {
                        // Nobody, an administrator included, moves it without turning
                        // protections off.
                        protected.append(item)
                        log.append("protected by macOS: \(shown(path)) (\(error.localizedDescription))")
                    }
                }
            }
        }

        // 2. The administrator batch.
        var adminMoves: [(item: MacTweaksItem, id: RowID, step: Int, destination: String)] = []
        var adminCommands: [String] = []
        var taken = Set<String>()
        for (item, id) in forAdministrator {
            let path = item.target
            guard exists(path) else {
                log.append("gone already: \(shown(path))")
                continue
            }
            // The gate, and where it just found the item's folder: root moves it only from there.
            guard isAllowed(path, id, environment: environment, roots: roots),
                  let physicalParent = resolved((path as NSString).deletingLastPathComponent) else {
                log.append("skip (refused): \(path)")
                problems.append("\(shown(path)) stays: it no longer passes Mac Tweaks' checks.")
                continue
            }
            let destination = roots.trash + "/" + uniqueTrashName((path as NSString).lastPathComponent, in: roots.trash, taken: &taken)
            adminCommands.append(guardedMove(path, to: destination, trash: roots.trash, physicalParent: physicalParent))
            adminMoves.append((item, id, adminCommands.count, destination))
        }
        let snapshotRow = rows.first { $0.id == RowID.snapshots.rawValue }
        var snapshotSteps: [String: Int] = [:]
        for item in snapshotRow?.items ?? [] where isSnapshotDate(item.target) {
            adminCommands.append("\(shellQuote(environment.tmutil)) deletelocalsnapshots \(shellQuote(item.target))")
            snapshotSteps[item.target] = adminCommands.count
        }
        var adminRun: QuickActionsProvider.PrivilegedRun?
        var stepResults: [Int: (status: Int32, output: String)] = [:]
        if !adminCommands.isEmpty {
            progress?(passwordNote)
            let tag = "__LS_" + UUID().uuidString.prefix(8)
            let run = environment.runAdmin(adminScript(adminCommands, tag: tag))
            adminRun = run
            switch run {
            case .ran(let status, let output):
                stepResults = batchResults(output, tag: tag)
                log.append("administrator batch (\(count(adminCommands.count, "step", "steps"))): ran (status \(status))")
            case .cancelled:
                log.append("administrator batch: the prompt was cancelled")
            case .refused(let message):
                log.append("administrator batch: not authorized (\(message))")
            }
        }
        /// Why administrator steps left what they act on in place, one item ("it") or several,
        /// or nil when macOS itself protects it.
        func whyStayed(_ steps: [Int], tool: String, verb: String, plural: Bool) -> String? {
            let it = plural ? "them" : "it"
            switch adminRun {
            case .cancelled?:
                return "\(plural ? "they need" : "it needs") Touch ID or your password, and the prompt was cancelled"
            case .refused?:
                return "\(plural ? "they need" : "it needs") Touch ID or your password, and macOS didn't accept it"
            case .ran?, nil:
                let results = steps.compactMap { stepResults[$0] }
                guard results.count == steps.count else { return "the administrator batch stopped before \(it)" }
                if let failed = results.first(where: { $0.status != 0 }) {
                    if reason(failed.output) == "Operation not permitted" { return nil }
                    let why = reason(failed.output)
                    return "\(tool) couldn't \(verb) \(it)" + (why.isEmpty ? "" : " (\(why))")
                }
                return "\(tool) reported no error, but \(it) didn't go"
            }
        }

        // 3. Simulators.
        var simctlRan = false
        var simulatorsBeforeSimctl: [MacTweaksItem] = []
        if let simulators = rows.first(where: { $0.id == RowID.simulators.rawValue }) {
            simulatorsBeforeSimctl = simulators.items.filter { exists($0.target) }
            progress?("Deleting unavailable simulators…")
            if let simctl = simctl(environment, roots: roots) {
                let deleted = environment.run(simctl, ["delete", "unavailable"], 600)
                simctlRan = true
                log.append("simctl delete unavailable: " + (deleted.status == 0 ? "done" : "failed (status \(deleted.status))"))
            } else {
                problems.append("Unavailable simulators stay: simctl is no longer where Xcode keeps it.")
            }
        }

        // 4. Look again.
        progress?("Checking what was freed…")
        var lines: [String] = []
        var adminMoved: [MacTweaksItem] = []
        var batchRan = false
        if case .ran? = adminRun { batchRan = true }
        for move in adminMoves {
            let path = move.item.target
            // The administrator's move: the batch ran, the step reported no error (or the
            // report stops before it), the item is gone and its Trash name is there. Gone any
            // other way, someone else took it, even into the Trash under that very name.
            if !exists(path) && exists(move.destination) && batchRan && (stepResults[move.step]?.status ?? 0) == 0 {
                adminMoved.append(move.item)
                log.append("moved by the administrator: \(shown(path))")
            } else if !exists(path) {
                problems.append("\(shown(path)): It was gone before Lightspot moved it.")
                log.append("gone before the administrator moved it: \(shown(path))")
            } else if let why = whyStayed([move.step], tool: "the administrator", verb: "move", plural: false) {
                problems.append("\(shown(path)) stays: \(why).")
                log.append("stayed: \(shown(path)) (\(why))")
            } else if isAppBundle(path, move.id) {
                appRefused(path)
            } else {
                protected.append(move.item)
                log.append("protected by macOS: \(shown(path))")
            }
        }
        let moved = trashed + adminMoved
        if !moved.isEmpty {
            lines.append("Moved \(count(moved.count, "item", "items")) to the Trash (\(MacTweaksProvider.size(moved.reduce(0) { $0 + $1.bytes }))).")
        }

        // Freed: only what Lightspot moved or deleted, less whatever has grown back at the same
        // path since (an app rebuilding its cache); never something gone on its own, nor a
        // fresh scan's guess (its gate may answer differently by now).
        let regrown = moved.map(\.target).filter(exists)
        let regrownKB = CleanDevMacProvider.measure([regrown]).first ?? []
        let regrownBytes = Dictionary(uniqueKeysWithValues: zip(regrown, regrownKB.map { Int64($0) * 1024 }))
        var freed = moved.reduce(Int64(0)) { $0 + max(0, $1.bytes - (regrownBytes[$1.target] ?? 0)) }
        freed += simulatorsBeforeSimctl.filter { !exists($0.target) }.reduce(0) { $0 + $1.bytes }

        // The rows to show again: files scanned again, simulators whose folders are still
        // there (with simctl gone a scan would see none), snapshots tmutil still lists.
        var after = scan(environment, only: Set(fileRows.map(\.id)))
        var simulatorsLeft: [MacTweaksItem] = []
        if var simulators = rows.first(where: { $0.id == RowID.simulators.rawValue }) {
            simulatorsLeft = simulators.items.filter { exists($0.target) }
            let deleted = simulatorsBeforeSimctl.filter { !exists($0.target) }.count
            if deleted > 0 { lines.append("Deleted \(count(deleted, "unavailable simulator", "unavailable simulators")).") }
            if !simulatorsLeft.isEmpty {
                if simctlRan {
                    let left = simulatorsLeft.count
                    problems.append("\(count(left, "unavailable simulator stays", "unavailable simulators stay")): simctl didn't delete \(left == 1 ? "it" : "them").")
                }
                simulators.items = simulatorsLeft
                simulators.bytes = simulatorsLeft.reduce(0) { $0 + $1.bytes }
                insertInOrder(simulators, into: &after)
            }
        }
        if var snapshots = snapshotRow {
            let listed = environment.run(environment.tmutil, ["listlocalsnapshotdates", "/"], 30)
            var left = snapshots.items.map(\.target)
            if listed.status == 0 {
                let remaining = Set(snapshotDates(tmutilOutput: listed.output))
                left = left.filter { remaining.contains($0) }
                let deleted = snapshots.items.count - left.count
                if deleted > 0 { lines.append("Deleted \(count(deleted, "local snapshot", "local snapshots")).") }
                if !left.isEmpty {
                    let why = whyStayed(left.compactMap { snapshotSteps[$0] }, tool: "tmutil", verb: "delete", plural: left.count > 1)
                        ?? "macOS didn't allow it"
                    problems.append("\(count(left.count, "snapshot stays", "snapshots stay")): \(why).")
                    log.append("stayed: \(count(left.count, "snapshot", "snapshots")) (\(why))")
                }
            } else {
                // Unknown: none is counted as deleted, and the row stays offered as it was.
                problems.append("Time Machine didn't say which snapshots are left, so none are counted as deleted.")
            }
            if !left.isEmpty {
                snapshots.items = left.map { MacTweaksItem(target: $0) }
                snapshots.countLabel = count(left.count, "snapshot", "snapshots")
                insertInOrder(snapshots, into: &after)
            }
        }
        if !protected.isEmpty {
            lines.append("\(count(protected.count, "item", "items")) (\(MacTweaksProvider.size(protected.reduce(0) { $0 + $1.bytes }))) "
                         + "\(protected.count == 1 ? "is" : "are") protected by macOS and \(protected.count == 1 ? "stays" : "stay"): "
                         + "nobody can move \(protected.count == 1 ? "it" : "them") without turning protections off.")
        }

        let headline: String
        if freed > 0 {
            headline = "Freed \(MacTweaksProvider.size(freed))."
        } else if !lines.isEmpty {
            headline = "Done."
        } else {
            headline = "Nothing was freed."
        }
        var notes: [String] = []
        if !moved.isEmpty { notes.append("Empty the Trash to get the space back.") }
        let receipt = MacTweaksReceipt(headline: headline, lines: lines, problems: problems, notes: notes, reveal: keptApp)

        MacTweaksProvider.appendReceipt(section: .freeUpSpace, lines: log + lines + problems + ["freed: \(MacTweaksProvider.size(freed))"],
                                        environment: environment, started: started)
        return (receipt, after)
    }

    /// The plan's closing sentences: where things go, and that macOS may ask for Touch ID or
    /// the password when the administrator batch may have something to do.
    static func planNotes(_ rows: [MacTweaksRow]) -> [String] {
        var notes: [String] = []
        let ids = Set(rows.map(\.id))
        let files = rows.filter { method(of: $0) == .trash }
        if !files.isEmpty { notes.append("Files go to the Trash.") }
        switch (ids.contains(RowID.simulators.rawValue), ids.contains(RowID.snapshots.rawValue)) {
        case (true, true): notes.append("Simulators and snapshots are deleted right away.")
        case (true, false): notes.append("Simulators are deleted right away.")
        case (false, true): notes.append("Snapshots are deleted right away.")
        case (false, false): break
        }
        if ids.contains(RowID.snapshots.rawValue) || files.contains(where: { $0.items.contains(where: \.isForeign) }) {
            notes.append(passwordNote)
        }
        return notes
    }

    /// Free Up Space as a Mac Tweaks section.
    struct Engine: MacTweaksSectionEngine {
        let environment: Environment

        func scan(only: Set<String>?, progress: (@Sendable (String) -> Void)?) -> [MacTweaksRow] {
            MacTweaksStorage.scan(environment, only: only, progress: progress)
        }

        func apply(_ rows: [MacTweaksRow], progress: (@Sendable (String) -> Void)?) -> (receipt: MacTweaksReceipt, rescanned: [MacTweaksRow]) {
            MacTweaksStorage.apply(rows, environment: environment, progress: progress)
        }

        func planNotes(for rows: [MacTweaksRow]) -> [String] {
            MacTweaksStorage.planNotes(rows)
        }
    }
}
