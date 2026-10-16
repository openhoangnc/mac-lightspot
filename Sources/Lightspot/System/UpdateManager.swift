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
    /// The swap helper is staged and the app is about to be replaced and relaunched.
    case relaunching
    case failed(String)
}

// MARK: - Update Manager

/// Checks GitHub Releases for a newer build, then downloads, verifies and swaps the
/// running app bundle in place.
///
/// Trust model, stated plainly: releases are ad-hoc signed (the project ships no
/// Developer ID), so there is no signature to validate against. What is enforced is
/// HTTPS, a GitHub host allowlist, a bundle-identifier and version check on the
/// unpacked bundle, and a refusal to ever install an older version. That is the same
/// trust placed in `install.sh`, no more and no less.
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    // MARK: Configuration

    nonisolated static let repository = "openhoangnc/mac-lightspot"
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

        URLSession.shared.dataTask(with: request) { data, response, error in
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
                                     current: String) -> UpdateCheckOutcome {
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
            release = try parseRelease(from: data)
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

    /// Reads the fields Lightspot needs out of a GitHub `releases/latest` payload.
    nonisolated static func parseRelease(from data: Data) throws -> ReleaseInfo {
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
        let asset = assets.first { ($0["name"] as? String) == assetName }
            ?? assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }

        guard let asset = asset,
              let urlString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString) else {
            throw UpdateError(message: "Release \(tag) has no \(assetName) attached.")
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

    /// Downloads the release, verifies the unpacked bundle, then hands the swap to a
    /// detached helper and quits — a running bundle cannot replace itself.
    /// `completion` runs on the main actor; `.relaunching` means the app is about to exit.
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

        URLSession.shared.downloadTask(with: request) { location, response, error in
            let result = Self.stageDownload(location: location,
                                            response: response,
                                            error: error,
                                            expected: expected,
                                            destination: destination)
            Task { @MainActor in
                switch result {
                case .failure(let message):
                    self.isInstalling = false
                    completion?(.failed(message))
                case .success(let staged):
                    guard Self.launchSwapHelper(staged: staged, destination: destination) else {
                        self.isInstalling = false
                        try? FileManager.default.removeItem(at: staged.workDirectory)
                        completion?(.failed("Could not start the update helper."))
                        return
                    }
                    completion?(.relaunching)
                }
            }
        }.resume()
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
        if let problem = validate(bundle: bundle, expected: expected, fileManager: fm) {
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
    /// must be Lightspot, must be runnable, and must not be a downgrade.
    nonisolated static func validate(bundle: URL,
                                     expected: SemanticVersion,
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
        return nil
    }

    // MARK: - The swap helper

    /// Shell-quotes a path for single-quoted use in the helper script.
    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The script that replaces the bundle once this process is gone.
    ///
    /// It waits for our PID, keeps the old bundle aside as a rollback, copies with
    /// `ditto`, clears quarantine, re-signs ad-hoc (the release is ad-hoc signed and
    /// the signature does not survive a plain copy), relaunches and cleans up.
    /// When run with admin rights it relaunches through `launchctl asuser` so the app
    /// does not come back as root.
    nonisolated static func installerScript(pid: Int32,
                                            stagedBundle: String,
                                            destination: String,
                                            workDirectory: String,
                                            uid: uid_t,
                                            privileged: Bool) -> String {
        let staged = shellQuote(stagedBundle)
        let dest = shellQuote(destination)
        let work = shellQuote(workDirectory)
        let rollback = shellQuote(destination + ".lightspot-old")

        let relaunch = privileged
            ? "/bin/launchctl asuser \(uid) /usr/bin/open \(dest)"
            : "/usr/bin/open \(dest)"
        let chown = privileged
            ? "/usr/sbin/chown -R \(uid) \(dest) 2>/dev/null || true\n"
            : ""

        return """
        #!/bin/sh
        # Lightspot update helper — replaces the app bundle after it exits.

        waited=0
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.2
            waited=$((waited + 1))
            if [ "$waited" -ge 150 ]; then
                kill -9 \(pid) 2>/dev/null || true
                sleep 0.5
                break
            fi
        done

        rm -rf \(rollback)
        if [ -d \(dest) ]; then
            mv \(dest) \(rollback) || exit 1
        fi

        if /usr/bin/ditto \(staged) \(dest); then
            /usr/bin/xattr -dr com.apple.quarantine \(dest) 2>/dev/null || true
            /usr/bin/codesign --force --deep --sign - \(dest) 2>/dev/null || true
        \(chown)    rm -rf \(rollback)
        else
            # Roll back to the version that was working a moment ago.
            rm -rf \(dest)
            if [ -d \(rollback) ]; then
                mv \(rollback) \(dest)
            fi
        fi

        \(relaunch) || true

        rm -rf \(work)
        rm -f "$0"
        """
    }

    /// Writes the helper to its own directory and launches it detached.
    nonisolated static func launchSwapHelper(staged: StagedUpdate, destination: URL) -> Bool {
        let fm = FileManager.default
        // The helper deletes the staging directory, so it must not live inside it.
        let helperDirectory = fm.temporaryDirectory
            .appendingPathComponent("lightspot-updater-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: helperDirectory, withIntermediateDirectories: true)) != nil else {
            return false
        }
        let script = helperDirectory.appendingPathComponent("install.sh")

        let body = installerScript(pid: getpid(),
                                   stagedBundle: staged.bundle.path,
                                   destination: destination.path,
                                   workDirectory: staged.workDirectory.path,
                                   uid: getuid(),
                                   privileged: staged.needsPrivileges)
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            NSLog("UpdateManager: could not write the update helper: %@", error.localizedDescription)
            return false
        }

        if staged.needsPrivileges {
            // Background it inside the privileged shell so sudo returns immediately;
            // this process has to be able to exit for the swap to proceed.
            let command = "nohup /bin/sh \(shellQuote(script.path)) >/dev/null 2>&1 &"
            return QuickActionsProvider.executePrivilegedWithTouchID(command: command)
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
            return false
        }
        return true
    }
}
