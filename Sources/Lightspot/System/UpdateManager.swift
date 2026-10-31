import AppKit
import Foundation

// MARK: - Semantic Version

/// Comparable version number parsed from a release tag or `CFBundleShortVersionString`.
/// Accepts a leading `v`, any number of numeric components, and a pre-release suffix
/// (`1.2.0-beta.1`), which sorts below the same version without one.
struct SemanticVersion: Comparable, CustomStringConvertible, Sendable, Equatable {
    let components: [Int]
    let preRelease: String?

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        // Split off a pre-release / build suffix before parsing numbers.
        let core: String
        if let dash = text.firstIndex(of: "-") {
            core = String(text[text.startIndex..<dash])
            let suffix = String(text[text.index(after: dash)...])
            preRelease = suffix.isEmpty ? nil : suffix
        } else if let plus = text.firstIndex(of: "+") {
            core = String(text[text.startIndex..<plus])
            preRelease = nil
        } else {
            core = text
            preRelease = nil
        }

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    /// Pads to a common length so `1.2` and `1.2.0` compare equal.
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            if l != r { return l < r }
        }
        // Equal numbers: a pre-release precedes the final release.
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        case (let l?, let r?): return l < r
        }
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    var description: String {
        let core = components.map(String.init).joined(separator: ".")
        return preRelease.map { "\(core)-\($0)" } ?? core
    }
}

// MARK: - Architecture

/// The kind of processor a Mac has, as the release names its per-architecture builds.
enum MacArchitecture: String, CaseIterable, Sendable {
    case arm64
    case x86_64

    /// This Mac's, from `hw.optional.arm64`: 1 on Apple silicon, also inside a process
    /// that Rosetta runs (there `uname -m` says x86_64); Intel Macs lack the key or
    /// report 0. Never this process's own architecture, so a Lightspot running under
    /// Rosetta, or an Intel build carried over to an Apple silicon Mac, updates to the
    /// native build.
    static let current: MacArchitecture = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return .x86_64 }
        return value == 1 ? .arm64 : .x86_64
    }()

    /// The release asset holding the app built for this architecture alone.
    var assetName: String { "Lightspot-\(rawValue).zip" }

    var displayName: String {
        switch self {
        case .arm64: return "Apple silicon"
        case .x86_64: return "Intel"
        }
    }

    /// The Mach-O `cputype` of its code: `CPU_TYPE_ARM64` (arm64e is a subtype of it)
    /// and `CPU_TYPE_X86_64`, from <mach/machine.h>.
    var cpuType: UInt32 {
        switch self {
        case .arm64: return 0x0100_000C
        case .x86_64: return 0x0100_0007
        }
    }

    init?(cpuType: UInt32) {
        guard let match = Self.allCases.first(where: { $0.cpuType == cpuType }) else { return nil }
        self = match
    }
}

// MARK: - Release Info

struct ReleaseInfo: Sendable, Equatable {
    let version: SemanticVersion
    let tagName: String
    /// Direct download for the packaged `.app` archive.
    let downloadURL: URL
    /// Human-readable release page, used for "View Release Notes".
    let pageURL: URL?
    let notes: String?
    let assetSize: Int?

    var displayVersion: String { version.description }
}

enum UpdateCheckOutcome: Sendable {
    case upToDate(current: String)
    case available(ReleaseInfo)
    case failed(String)
}

enum UpdateInstallOutcome: Sendable {
    /// The new build is in place and has finished launching. Quit now: it is waiting
    /// for this process to exit before it shows anything.
    case relaunching
    case failed(String)
}

/// One poll of the copy an update started.
enum HandOverStep: Equatable, Sendable {
    case waiting
    case launched
    case failed(String)
}

// MARK: - Update Manager

/// Checks GitHub Releases for a newer build, then downloads, verifies and swaps the
/// running app bundle in place.
///
/// Trust model, stated plainly: releases are ad-hoc signed (the project ships no
/// Developer ID), so there is no signature to validate against. What is enforced is
/// HTTPS, a GitHub host allowlist, a bundle-identifier and version check on the
/// unpacked bundle, its executable holding this Mac's architecture, and a refusal to
/// ever install an older version. That is the same trust placed in `install.sh`, no
/// more and no less.
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    // MARK: Configuration

    nonisolated static let repository = "openhoangnc/mac-lightspot"
    /// The universal build. Every release keeps it under this name: the updaters of
    /// 1.2.0 to 1.3.9 download exactly it, and so do older links to
    /// `releases/latest/download/Lightspot.zip`. This version prefers the build for
    /// this Mac (`MacArchitecture.assetName`) and falls back to it.
    nonisolated static let assetName = "Lightspot.zip"
    nonisolated static let latestReleaseEndpoint =
        "https://api.github.com/repos/\(repository)/releases/latest"

    /// GitHub serves release assets from `github.com` and redirects to its object
    /// store; nothing else is accepted, before or after a redirect.
    nonisolated static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    nonisolated static func isAllowedDownloadHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedDownloadHosts.contains(host)
    }

    /// How long a successful check is good for.
    nonisolated static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Used for the check and the download. Ephemeral, so no response or cookie lands
    /// in `~/Library/Caches/<bundle id>/Cache.db` or `~/Library/HTTPStorages`:
    /// `URLSession.shared` stored every release feed there, and
    /// `.reloadIgnoringLocalCacheData` only skips reading the cache, not writing it.
    nonisolated static let session = URLSession(configuration: .ephemeral)

    // MARK: Persisted preferences

    private nonisolated static let automaticKey = "lightspot_auto_update_enabled"
    private nonisolated static let lastCheckKey = "lightspot_last_update_check"
    private nonisolated static let skippedVersionKey = "lightspot_skipped_version"

    /// Automatic checks are on by default; the menu bar exposes the toggle.
    var isAutomaticEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticKey) }
    }

    private var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastCheckKey) }
    }

    /// A version the user chose to skip; it stops prompting but never blocks a manual check.
    private(set) var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.skippedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.skippedVersionKey) }
    }

    // MARK: Cached state
    //
    // The menu reads these directly, so they must stay pure in-memory properties
    // (see invariant 0): no probing, no I/O, no network from a getter.

    private(set) var availableUpdate: ReleaseInfo?
    private(set) var isChecking = false
    private(set) var isInstalling = false

    /// Set when a background check fails, so a later manual check can show the reason.
    private(set) var lastErrorMessage: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Checking

    /// Runs a check if automatic updates are on and the interval has elapsed.
    /// Safe to call from `applicationDidFinishLaunching` and whenever a menu opens:
    /// it returns immediately and does the work on a URLSession background queue.
    func checkAutomaticallyIfDue(onUpdateFound: (@Sendable @MainActor (ReleaseInfo) -> Void)? = nil) {
        guard isAutomaticEnabled, !isChecking, !isInstalling else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }

        checkForUpdates(userInitiated: false) { outcome in
            if case .available(let release) = outcome { onUpdateFound?(release) }
        }
    }

    /// Fetches the latest release and compares it with the running build.
    /// `completion` always runs on the main actor.
    func checkForUpdates(userInitiated: Bool,
                         completion: (@Sendable @MainActor (UpdateCheckOutcome) -> Void)? = nil) {
        guard !isChecking else { return }
        guard let endpoint = URL(string: Self.latestReleaseEndpoint),
              Self.isAllowedDownloadHost(endpoint) else {
            completion?(.failed("The update endpoint is not a valid GitHub HTTPS URL."))
            return
        }

        isChecking = true
        let current = currentVersion

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects API requests without a User-Agent.
        request.setValue("Lightspot/\(current) (+https://github.com/\(Self.repository))",
                         forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        Self.session.dataTask(with: request) { data, response, error in
            let outcome = Self.evaluate(data: data, response: response, error: error, current: current)
            Task { @MainActor in
                self.isChecking = false
                switch outcome {
                case .available(let release):
                    self.availableUpdate = release
                    self.lastErrorMessage = nil
                    self.lastCheck = Date()
                case .upToDate:
                    self.availableUpdate = nil
                    self.lastErrorMessage = nil
                    self.lastCheck = Date()
                case .failed(let message):
                    self.lastErrorMessage = message
                    // A failure does not reset the clock, so the next launch retries.
                }
                completion?(outcome)
            }
        }.resume()
    }

    /// Pure decision step, split out so the version/JSON handling is testable offline.
    nonisolated static func evaluate(data: Data?,
                                     response: URLResponse?,
                                     error: Error?,
                                     current: String,
                                     architecture: MacArchitecture = .current) -> UpdateCheckOutcome {
        if let error = error {
            return .failed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 404 {
                return .failed("No published release was found for \(repository).")
            }
            if http.statusCode == 403 {
                return .failed("GitHub rate-limited the update check. Try again later.")
            }
            return .failed("GitHub returned HTTP \(http.statusCode).")
        }
        guard let data = data, !data.isEmpty else {
            return .failed("The update check returned no data.")
        }

        let release: ReleaseInfo
        do {
            release = try parseRelease(from: data, architecture: architecture)
        } catch let failure as UpdateError {
            return .failed(failure.message)
        } catch {
            return .failed(error.localizedDescription)
        }

        guard let currentVersion = SemanticVersion(current) else {
            return .failed("The running build has an unreadable version number (\(current)).")
        }
        guard currentVersion < release.version else {
            return .upToDate(current: current)
        }
        return .available(release)
    }

    struct UpdateError: Error, Equatable {
        let message: String
    }

    /// Reads the fields Lightspot needs out of a GitHub `releases/latest` payload, with
    /// the download a Mac of `architecture` should take (`chooseAsset`).
    nonisolated static func parseRelease(from data: Data,
                                         architecture: MacArchitecture = .current) throws -> ReleaseInfo {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UpdateError(message: "The release feed was not valid JSON.")
        }
        guard let tag = root["tag_name"] as? String, !tag.isEmpty else {
            throw UpdateError(message: "The release feed carried no tag name.")
        }
        guard let version = SemanticVersion(tag) else {
            throw UpdateError(message: "Release tag '\(tag)' is not a version number.")
        }

        let assets = root["assets"] as? [[String: Any]] ?? []
        guard let asset = chooseAsset(assets, for: architecture),
              let urlString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString) else {
            throw UpdateError(message: "Release \(tag) has no \(architecture.assetName) or \(assetName) attached.")
        }
        guard isAllowedDownloadHost(downloadURL) else {
            throw UpdateError(message: "Release \(tag) points its download at an unexpected host.")
        }

        let page = (root["html_url"] as? String).flatMap(URL.init(string:))
        let notes = (root["body"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return ReleaseInfo(
            version: version,
            tagName: tag,
            downloadURL: downloadURL,
            pageURL: page,
            notes: notes,
            assetSize: asset["size"] as? Int
        )
    }

    /// The asset a Mac of `architecture` downloads, by name, whatever order the release
    /// lists them in: the build for it alone (`Lightspot-arm64.zip`), else the universal
    /// `Lightspot.zip` (the only build up to 1.3.9), else any other `.zip` except the
    /// dSYM and another architecture's build. `validate` checks the architecture again
    /// once the download is unpacked.
    nonisolated static func chooseAsset(_ assets: [[String: Any]],
                                        for architecture: MacArchitecture) -> [String: Any]? {
        func named(_ name: String) -> [String: Any]? {
            assets.first { ($0["name"] as? String) == name }
        }
        if let own = named(architecture.assetName) { return own }
        if let universal = named(assetName) { return universal }
        let otherBuilds = Set(MacArchitecture.allCases.filter { $0 != architecture }
            .map { $0.assetName.lowercased() })
        return assets.first { asset in
            guard let name = asset["name"] as? String, name.hasSuffix(".zip") else { return false }
            let lowered = name.lowercased()
            return !lowered.hasSuffix(".dsym.zip") && !otherBuilds.contains(lowered)
        }
    }

    // MARK: - Skipping

    func skip(_ release: ReleaseInfo) {
        skippedVersion = release.tagName
        availableUpdate = nil
    }

    /// True when there is an update the user has not already dismissed.
    var hasPromptableUpdate: Bool {
        guard let update = availableUpdate else { return false }
        return update.tagName != skippedVersion
    }

    // MARK: - Installing

    /// Downloads the release, verifies the unpacked bundle, swaps it into place while
    /// this copy keeps running, then starts the new build and waits for it to finish
    /// launching. `completion` runs on the main actor; `.relaunching` means the new
    /// build is up and this copy should quit, which is what lets it take over.
    ///
    /// The order is what keeps Lightspot on screen. The first launch of a freshly
    /// swapped and re-signed bundle goes through LaunchServices' "node has changed"
    /// path and a Gatekeeper scan (measured at 30 s in a sibling app), and the process
    /// sits paused meanwhile. Quitting first and relaunching from a helper, as up to
    /// 1.3.2, left the user with no Lightspot for that whole scan.
    func install(_ release: ReleaseInfo,
                 completion: (@Sendable @MainActor (UpdateInstallOutcome) -> Void)? = nil) {
        guard !isInstalling else { return }
        guard Self.isAllowedDownloadHost(release.downloadURL) else {
            completion?(.failed("The download URL is not a GitHub HTTPS address."))
            return
        }

        isInstalling = true
        let destination = Bundle.main.bundleURL
        let expected = release.version

        var request = URLRequest(url: release.downloadURL)
        request.setValue("Lightspot/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300

        Self.session.downloadTask(with: request) { location, response, error in
            let result = Self.stageDownload(location: location,
                                            response: response,
                                            error: error,
                                            expected: expected,
                                            architecture: .current,
                                            destination: destination)
            Task { @MainActor in
                switch result {
                case .failure(let message):
                    self.isInstalling = false
                    completion?(.failed(message))
                case .success(let staged):
                    let outcome = await self.swapAndHandOver(staged, release: release, destination: destination)
                    if case .failed = outcome { self.isInstalling = false }
                    completion?(outcome)
                }
            }
        }.resume()
    }

    /// How long this copy waits for the helper to put the new bundle in place. The
    /// privileged path has already been authorised by then; this is ditto + codesign.
    nonisolated static let swapTimeout: TimeInterval = 120
    /// How long the new build gets to finish launching. Generous on purpose: this copy
    /// stays up all along, so waiting costs nothing, and a first launch can sit in a
    /// Gatekeeper scan for half a minute.
    nonisolated static let handOverTimeout: TimeInterval = 180
    /// How long a rollback may take before the failure is reported anyway.
    nonisolated static let restoreTimeout: TimeInterval = 15

    /// Files the helper and this copy talk through, inside the helper's own folder.
    nonisolated static let helperStatusFile = "status"
    nonisolated static let helperRestoreFile = "restore"

    /// The helper runs on its own serial queue: the privileged path blocks on Touch ID
    /// or the password dialog, and its fallback is an `NSAppleScript`.
    private nonisolated static let helperQueue = DispatchQueue(label: "lightspot.update.helper")

    private func swapAndHandOver(_ staged: StagedUpdate,
                                 release: ReleaseInfo,
                                 destination: URL) async -> UpdateInstallOutcome {
        let fm = FileManager.default
        let helper: URL? = await withCheckedContinuation { continuation in
            Self.helperQueue.async {
                continuation.resume(returning: Self.launchSwapHelper(staged: staged, destination: destination))
            }
        }
        guard let helper else {
            try? fm.removeItem(at: staged.workDirectory)
            return .failed("Could not start the update helper.")
        }

        // 1. The swap. This copy keeps running from the bundle the helper moves aside.
        let swapDeadline = Date().addingTimeInterval(Self.swapTimeout)
        var status = Self.helperStatus(in: helper)
        while status == nil, Date() < swapDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            status = Self.helperStatus(in: helper)
        }
        switch status {
        case "swapped":
            break
        case "failed":
            try? fm.removeItem(at: helper)
            return .failed("Lightspot \(release.displayVersion) could not be copied into place. Lightspot \(currentVersion) is still installed.")
        default:
            // Still copying: the helper rolls back as soon as it reaches the hand-over.
            Self.requestRestore(in: helper)
            return .failed("The update helper did not finish. Lightspot \(currentVersion) stays installed.")
        }

        // 2. The hand-over: start the new build as a second copy and wait for it to
        //    finish launching. It waits for this process to exit before showing
        //    anything, so the user never sees two.
        var newCopy: NSRunningApplication?
        var failure: String
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.arguments = SingleInstanceGuard.replacingArguments(pid: getpid())
            let app = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            newCopy = app
            let deadline = Date().addingTimeInterval(Self.handOverTimeout)
            while true {
                let step = Self.handOverStep(isTerminated: app.isTerminated,
                                             isFinishedLaunching: app.isFinishedLaunching,
                                             timedOut: Date() >= deadline)
                if step == .launched {
                    NSLog("UpdateManager: %@ is up (pid %d), handing over", release.displayVersion, app.processIdentifier)
                    return .relaunching
                }
                if case .failed(let reason) = step {
                    failure = reason
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        } catch {
            failure = error.localizedDescription
        }

        // The new build did not take over: put the old bundle back and keep running it.
        NSLog("UpdateManager: %@ did not take over (%@); rolling back", release.displayVersion, failure)
        if let newCopy, !newCopy.isTerminated {
            newCopy.forceTerminate()
            let deadline = Date().addingTimeInterval(2)
            while !newCopy.isTerminated, Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        Self.requestRestore(in: helper)
        let restoreDeadline = Date().addingTimeInterval(Self.restoreTimeout)
        while Self.helperStatus(in: helper) != "restored", Date() < restoreDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        try? fm.removeItem(at: helper)
        return .failed("Lightspot \(release.displayVersion) did not start (\(failure)). Lightspot \(currentVersion) is still installed and running.")
    }

    /// Pure decision for one poll of the new copy, split out to be testable.
    nonisolated static func handOverStep(isTerminated: Bool,
                                         isFinishedLaunching: Bool,
                                         timedOut: Bool) -> HandOverStep {
        if isTerminated { return .failed("it quit while starting") }
        if isFinishedLaunching { return .launched }
        if timedOut { return .failed("it took too long to start") }
        return .waiting
    }

    /// What the helper last reported: `swapped`, `failed` or `restored`; nil until then.
    nonisolated static func helperStatus(in helperDirectory: URL) -> String? {
        let file = helperDirectory.appendingPathComponent(helperStatusFile)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let status = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return status.isEmpty ? nil : status
    }

    /// Asks the helper to put the old bundle back instead of deleting it.
    nonisolated static func requestRestore(in helperDirectory: URL) {
        FileManager.default.createFile(atPath: helperDirectory.appendingPathComponent(helperRestoreFile).path,
                                       contents: Data())
    }

    struct StagedUpdate: Sendable {
        let bundle: URL
        let workDirectory: URL
        /// True when the destination's parent is not user-writable and the swap needs admin rights.
        let needsPrivileges: Bool
    }

    enum StageResult: Sendable {
        case success(StagedUpdate)
        case failure(String)
    }

    /// Unpacks and validates the download. Blocking; runs on the URLSession queue.
    nonisolated static func stageDownload(location: URL?,
                                          response: URLResponse?,
                                          error: Error?,
                                          expected: SemanticVersion,
                                          architecture: MacArchitecture,
                                          destination: URL) -> StageResult {
        if let error = error { return .failure(error.localizedDescription) }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return .failure("The download failed with HTTP \(http.statusCode).")
        }
        // Validate the URL the response actually came from, redirects included.
        if let finalURL = response?.url, !isAllowedDownloadHost(finalURL) {
            return .failure("The download was redirected to an unexpected host.")
        }
        guard let location = location else { return .failure("The download produced no file.") }

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("lightspot-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            return .failure("Could not create a staging directory: \(error.localizedDescription)")
        }

        func fail(_ message: String) -> StageResult {
            try? fm.removeItem(at: work)
            return .failure(message)
        }

        // Move the download next to where it will be unpacked.
        let archive = work.appendingPathComponent("Lightspot.zip")
        do {
            try fm.moveItem(at: location, to: archive)
        } catch {
            return fail("Could not stage the download: \(error.localizedDescription)")
        }

        // `ditto -x -k` keeps bundle metadata that `unzip` drops.
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, unpacked.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            return fail("Could not unpack the download: \(error.localizedDescription)")
        }
        guard ditto.terminationStatus == 0 else {
            return fail("The downloaded archive could not be expanded.")
        }

        guard let bundle = findAppBundle(in: unpacked, fileManager: fm) else {
            return fail("The archive did not contain \(destination.lastPathComponent).")
        }
        if let problem = validate(bundle: bundle, expected: expected, architecture: architecture, fileManager: fm) {
            return fail(problem)
        }

        let parent = destination.deletingLastPathComponent().path
        return .success(StagedUpdate(bundle: bundle,
                                     workDirectory: work,
                                     needsPrivileges: !fm.isWritableFile(atPath: parent)))
    }

    /// Finds the single top-level `.app` in an expanded archive.
    nonisolated static func findAppBundle(in directory: URL, fileManager fm: FileManager) -> URL? {
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else { return nil }
        if let app = entries.first(where: { $0.pathExtension == "app" }) { return app }
        // Some archives wrap the bundle in a folder.
        for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let nested = try? fm.contentsOfDirectory(at: entry,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]),
               let app = nested.first(where: { $0.pathExtension == "app" }) {
                return app
            }
        }
        return nil
    }

    /// Returns a reason to refuse the bundle, or nil when it is acceptable.
    /// Without a Developer ID to verify, these checks are the whole gate: the bundle
    /// must be Lightspot, must be runnable on this Mac, and must not be a downgrade.
    nonisolated static func validate(bundle: URL,
                                     expected: SemanticVersion,
                                     architecture: MacArchitecture,
                                     fileManager fm: FileManager) -> String? {
        let infoPlist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlist) as? [String: Any] else {
            return "The downloaded bundle has no readable Info.plist."
        }
        guard let identifier = info["CFBundleIdentifier"] as? String,
              identifier == LightspotSettingsBackup.appIdentifier else {
            return "The downloaded bundle is not Lightspot."
        }
        guard let executableName = info["CFBundleExecutable"] as? String else {
            return "The downloaded bundle declares no executable."
        }
        let executable = bundle.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard fm.isExecutableFile(atPath: executable.path) else {
            return "The downloaded bundle has no runnable executable."
        }
        guard let shortVersion = info["CFBundleShortVersionString"] as? String,
              let bundleVersion = SemanticVersion(shortVersion) else {
            return "The downloaded bundle has no readable version number."
        }
        guard bundleVersion == expected else {
            return "The downloaded bundle is version \(bundleVersion), not the expected \(expected)."
        }
        // Another architecture's build would install and then never start.
        guard let cpuTypes = machOCPUTypes(of: executable) else {
            return "The downloaded executable is not a Mac program."
        }
        guard cpuTypes.contains(architecture.cpuType) else {
            var builtFor: [String] = []    // arm64 and arm64e slices are both Apple silicon
            for type in cpuTypes {
                let name = MacArchitecture(cpuType: type)?.displayName ?? String(format: "CPU type 0x%x", type)
                if !builtFor.contains(name) { builtFor.append(name) }
            }
            return "The downloaded build is for \(builtFor.joined(separator: " and ")) only; this Mac has \(architecture.displayName)."
        }
        return nil
    }

    /// The `cputype` of each architecture an executable holds, from its Mach-O header:
    /// a thin binary's own, or each slice a universal one lists. Nil when the file is not
    /// Mach-O. Read here, not with `lipo -archs`: on a Mac without the Command Line Tools,
    /// `/usr/bin/lipo` is the shim that opens their installer.
    nonisolated static func machOCPUTypes(of executable: URL) -> [UInt32]? {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return nil }
        defer { try? handle.close() }
        // A universal header lists at most `maxSlices` slices of 32 bytes after 8.
        guard let header = try? handle.read(upToCount: 8 + 32 * maxSlices) else { return nil }
        return machOCPUTypes(header: header)
    }

    nonisolated static let maxSlices = 32

    /// `machOCPUTypes(of:)` on the file's first bytes. A thin header (`MH_MAGIC_64`,
    /// `MH_MAGIC`) is in the file's byte order, as its magic reads; a universal one
    /// (`FAT_MAGIC`, `FAT_MAGIC_64`) is big-endian, with `nfat_arch` slices of 20 or 32
    /// bytes, each starting with its `cputype`.
    nonisolated static func machOCPUTypes(header: Data) -> [UInt32]? {
        let bytes = [UInt8](header)
        func word(_ offset: Int, bigEndian: Bool) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            let four = Array(bytes[offset..<offset + 4])
            return (bigEndian ? four : four.reversed()).reduce(0) { ($0 << 8) | UInt32($1) }
        }
        guard let magic = word(0, bigEndian: true) else { return nil }
        switch magic {
        case 0xCFFA_EDFE, 0xCEFA_EDFE:          // MH_MAGIC_64, MH_MAGIC, stored little-endian
            return word(4, bigEndian: false).map { [$0] }
        case 0xFEED_FACF, 0xFEED_FACE:          // the same, stored big-endian
            return word(4, bigEndian: true).map { [$0] }
        case 0xCAFE_BABE, 0xCAFE_BABF:          // FAT_MAGIC, FAT_MAGIC_64
            let stride = magic == 0xCAFE_BABE ? 20 : 32
            guard let count = word(4, bigEndian: true), count > 0, count <= UInt32(maxSlices) else { return nil }
            var types: [UInt32] = []
            for index in 0..<Int(count) {
                guard let type = word(8 + index * stride, bigEndian: true) else { return nil }
                types.append(type)
            }
            return types
        default:
            return nil
        }
    }

    // MARK: - The swap helper

    /// Shell-quotes a path for single-quoted use in the helper script.
    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The script that swaps the bundle while this process is still running, then
    /// waits out the hand-over.
    ///
    /// It keeps the old bundle aside as a rollback, copies with `ditto`, clears
    /// quarantine, re-signs ad-hoc (the release is ad-hoc signed and the signature does
    /// not survive a plain copy) and reports `swapped` (or `failed`, after restoring)
    /// in its status file. Then it waits: once our PID exits, the new copy has taken
    /// over and the rollback goes; if a restore file appears instead, the new copy did
    /// not start, and the old bundle goes back in place (`restored`).
    ///
    /// It no longer relaunches anything: this process starts the new build itself,
    /// as the user, so the privileged path needs no `launchctl asuser`.
    nonisolated static func installerScript(pid: Int32,
                                            stagedBundle: String,
                                            destination: String,
                                            workDirectory: String,
                                            helperDirectory: String,
                                            uid: uid_t,
                                            privileged: Bool) -> String {
        let staged = shellQuote(stagedBundle)
        let dest = shellQuote(destination)
        let work = shellQuote(workDirectory)
        let rollback = shellQuote(destination + ".lightspot-old")
        let status = shellQuote(helperDirectory + "/" + helperStatusFile)
        let statusTemp = shellQuote(helperDirectory + "/" + helperStatusFile + ".tmp")
        let restore = shellQuote(helperDirectory + "/" + helperRestoreFile)
        let helper = shellQuote(helperDirectory)

        let chown = privileged
            ? "    /usr/sbin/chown -R \(uid) \(dest) 2>/dev/null || true\n"
            : ""

        return """
        #!/bin/sh
        # Lightspot update helper — swaps the app bundle while Lightspot runs, then
        # waits for the hand-over to the new build.

        report() {
            echo "$1" > \(statusTemp) && mv -f \(statusTemp) \(status)
        }

        put_back() {
            rm -rf \(dest)
            if [ -d \(rollback) ]; then
                mv \(rollback) \(dest)
            fi
        }

        rm -rf \(rollback)
        if [ -d \(dest) ]; then
            if ! mv \(dest) \(rollback); then
                rm -rf \(work)
                report failed
                exit 1
            fi
        fi

        if /usr/bin/ditto \(staged) \(dest); then
            /usr/bin/xattr -dr com.apple.quarantine \(dest) 2>/dev/null || true
            /usr/bin/codesign --force --deep --sign - \(dest) 2>/dev/null || true
        \(chown)else
            # Roll back to the version that is running right now.
            put_back
            rm -rf \(work)
            report failed
            exit 1
        fi
        rm -rf \(work)
        report swapped

        # Lightspot now starts the new build and quits once it has finished launching.
        waited=0
        while kill -0 \(pid) 2>/dev/null; do
            if [ -e \(restore) ]; then
                put_back
                report restored
                exit 0
            fi
            sleep 0.2
            waited=$((waited + 1))
            # Lightspot gives up on the new build long before this.
            if [ "$waited" -ge 3000 ]; then
                break
            fi
        done

        rm -rf \(rollback)
        rm -rf \(helper)
        """
    }

    /// Writes the helper to its own directory and launches it detached. Returns that
    /// directory, where the helper reports its progress, or nil if it did not start.
    /// Blocking on the privileged path (Touch ID or the password dialog).
    nonisolated static func launchSwapHelper(staged: StagedUpdate, destination: URL) -> URL? {
        let fm = FileManager.default
        // The helper deletes the staging directory, so it must not live inside it.
        let helperDirectory = fm.temporaryDirectory
            .appendingPathComponent("lightspot-updater-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: helperDirectory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let script = helperDirectory.appendingPathComponent("install.sh")

        let body = installerScript(pid: getpid(),
                                   stagedBundle: staged.bundle.path,
                                   destination: destination.path,
                                   workDirectory: staged.workDirectory.path,
                                   helperDirectory: helperDirectory.path,
                                   uid: getuid(),
                                   privileged: staged.needsPrivileges)
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            NSLog("UpdateManager: could not write the update helper: %@", error.localizedDescription)
            try? fm.removeItem(at: helperDirectory)
            return nil
        }

        if staged.needsPrivileges {
            // Background it inside the privileged shell so sudo returns; the helper
            // outlives it, waiting for this process to hand over.
            let command = "nohup /bin/sh \(shellQuote(script.path)) >/dev/null 2>&1 &"
            guard QuickActionsProvider.executePrivilegedWithTouchID(command: command) else {
                try? fm.removeItem(at: helperDirectory)
                return nil
            }
            return helperDirectory
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("UpdateManager: could not launch the update helper: %@", error.localizedDescription)
            try? fm.removeItem(at: helperDirectory)
            return nil
        }
        return helperDirectory
    }
}
