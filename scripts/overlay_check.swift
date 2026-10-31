import AppKit
import SwiftUI

// The Mac Tweaks overlay, hosted offscreen: the real `MacTweaksView` in an `NSHostingView` in a
// borderless window at (-6000, -6000), its model on a provider that scans this Mac read-only
// (every writer refuses, Apple Intelligence's inventory runs in-process, never the Lightspot
// binary). Each section is scanned, rescanned with the cursor on its last row, and left for
// every other section and back, so the rows on show shrink each way they can: once with the
// rescan first, once with the switches first, since the first shrink is where a bad row view
// traps. Up to 1.4.0's QA, a row view reading `model.rows[index]` trapped there.
//
// Each run is a child process of its own, so a trap ends only that one and the report says
// which. Nothing is applied, written, moved, asked for or opened; Lightspot isn't launched.
//
//   swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift \
//       $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift)
//   /tmp/overlay_check            # from the repository root (it reads Resources/cdm-rules)

@main
struct OverlayCheck {
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--section"), flag + 1 < arguments.count,
           let section = MacTweaksSection(rawValue: arguments[flag + 1]) {
            let switchesFirst = arguments.contains("--switches-first")
            MainActor.assumeIsolated { SectionRun(section).run(switchesFirst: switchesFirst) }
            exit(0)
        }
        exit(runAll())
    }

    /// The parent: two children per built section (the rescan first, the switches first), each
    /// reported as it ends.
    static func runAll() -> Int32 {
        let me = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var failed = 0
        var runs = 0
        print("Mac Tweaks overlay, offscreen, sections: \(MacTweaksSection.built.map(\.title).joined(separator: ", "))")
        for section in MacTweaksSection.built {
          for switchesFirst in [false, true] {
            runs += 1
            let name = "\(section.title), \(switchesFirst ? "switches first" : "rescan first")"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: me)
            process.arguments = ["--section", section.rawValue] + (switchesFirst ? ["--switches-first"] : [])
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch {
                print("❌ \(name): couldn't start (\(error.localizedDescription))")
                failed += 1
                continue
            }
            // Read to the end before waiting (invariant 1).
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let lines = output.split(separator: "\n").map { "     " + $0 }
            print(lines.joined(separator: "\n"))
            if process.terminationReason == .uncaughtSignal {
                print("❌ \(name): CRASHED (signal \(process.terminationStatus)) after the last step above")
                failed += 1
            } else if process.terminationStatus != 0 || !output.contains(SectionRun.survived) {
                print("❌ \(name): failed (exit \(process.terminationStatus))")
                failed += 1
            } else {
                print("✅ \(name): survived every rescan and switch")
            }
          }
        }
        print(failed == 0 ? "\n✅ The overlay survived all \(runs) runs." : "\n❌ \(failed) of \(runs) runs failed.")
        return failed == 0 ? 0 : 1
    }
}

/// One child: the overlay on screen (offscreen), driven through one section's rescan and switches.
@MainActor
final class SectionRun {
    nonisolated static let survived = "SURVIVED"
    /// The longest a scan may take: Free Up Space measures every offered item.
    static let scanTimeout: TimeInterval = 120

    let section: MacTweaksSection
    let provider: MacTweaksProvider
    let model: MacTweaksModel
    let window: NSWindow
    let hosting: NSView

    init(_ section: MacTweaksSection) {
        self.section = section
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        provider = MacTweaksProvider(environment: Self.readOnlyEnvironment())
        model = MacTweaksModel(provider: provider)
        // The panel's overlay size (SpotlightView: the panel's width, 450 pt tall).
        window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 740, height: 450),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        hosting = NSHostingView(rootView: MacTweaksView(model: model, onClose: {}).frame(width: 740, height: 450))
        window.contentView = hosting
        window.orderFrontRegardless()
    }

    func log(_ line: String) {
        print(line)
        fflush(stdout)
    }

    var state: String {
        let s = model.state
        return "\(model.section.title): \(s.phase), \(s.rows.count) rows, cursor \(model.cursor)"
    }

    /// Runs the main loop (SwiftUI's updates, the provider's notifications) for `seconds`, or
    /// until `done`, drawing as it goes.
    @discardableResult
    func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if done() { return true }
        }
        return done()
    }

    func waitReady() {
        let ready = pump(Self.scanTimeout) { if case .ready = model.state.phase { return true }; return false }
        if !ready { log("  (still not ready after \(Int(Self.scanTimeout)) s: \(state))") }
        pump(0.5)
        // The list keys its rows by ID: two rows with one ID would draw one of them twice.
        let ids = model.rows.map(\.id)
        if Set(ids).count != ids.count {
            log("FAIL: \(model.section.title) has rows sharing an ID: \(ids)")
            exit(2)
        }
    }

    /// The cursor on the last row, which is what a shrink leaves past the end.
    func cursorToLast() {
        let count = model.rows.count
        guard count > 1 else { return }
        // ↓ as the keys move it; it wraps, so at most `count` presses.
        for _ in 0..<count where model.cursor != count - 1 { model.moveDown() }
        pump(0.3)
    }

    func run(switchesFirst: Bool) {
        log("== \(section.title), \(switchesFirst ? "switches first" : "rescan first")")
        model.show(section)
        waitReady()
        log("scanned: \(state)")
        if switchesFirst {
            switches()
            rescan()
        } else {
            rescan()
            switches()
        }
        // The plan and back, then the overlay closed and opened again.
        cursorToLast()
        model.toggleCursor()
        model.reviewPlan()
        pump(0.5)
        log("plan: confirming \(model.isConfirming), \(model.checkedRows.count) ticked")
        _ = model.cancelConfirmation()
        model.close()
        pump(0.5)
        model.open()
        waitReady()
        log("reopened: \(state)")
        log(Self.survived)
    }

    /// A rescan from the last row: it drops the rows at its start.
    func rescan() {
        cursorToLast()
        log("cursor on the last row: \(state)")
        provider.startScan(section, force: true)
        pump(0.3)
        log("rescan started: \(state)")
        waitReady()
        log("rescan done: \(state)")
    }

    /// Away to every other section and back, each switch from this section's last row.
    func switches() {
        for other in MacTweaksSection.built where other != section {
            cursorToLast()
            model.select(other)
            pump(0.3)
            log("switched to \(other.title): \(state)")
            waitReady()
            log("  \(other.title) ready: \(state)")
            cursorToLast()
            model.select(section)
            pump(0.5)
            log("back to \(section.title): \(state)")
        }
    }

    /// The live environment with every writer refusing, as deep_verify builds it: scans read this
    /// Mac and change nothing.
    static func readOnlyEnvironment() -> MacTweaksProvider.Environment {
        var env = MacTweaksProvider.Environment.live
        env.moveToTrash = { _ in throw CocoaError(.featureUnsupported) }
        env.runAdmin = { _ in .refused("overlay_check never asks for a password") }
        // The app falls back on the rules inside Lightspot.app; this runner uses the repository's.
        let bundled = CleanDevMacRules.load(directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Resources/cdm-rules"),
                                            source: .bundled)
        env.cleanDevMacRules = { home in MacTweaksStorage.cleanDevMacRules(home: home) ?? bundled }
        // Apple Intelligence: the read-only bridge in this process, never the helper child.
        env.intelligence.assetInventory = { AssetServiceHelper.inventory(bridge: AssetServiceBridge()) }
        env.intelligence.resetAssetSet = { _ in .noAnswer }
        env.intelligence.presentProfile = { _ in throw CocoaError(.featureUnsupported) }
        env.intelligence.removeProfileFile = {}
        env.intelligence.openDeviceManagement = {}
        env.intelligence.sleep = { _ in }
        // Settings: launchctl reads only; no preference, flag, restart or file written.
        let settingsLaunchctl = env.settings.launchctl
        env.settings.launchctl = { args in
            guard args.first == "print" || args.first == "print-disabled" else { return (1, "overlay_check never changes launchd") }
            return settingsLaunchctl(args)
        }
        var store = env.settings.preferences
        store.write = { _, _, _ in false }
        env.settings.preferences = store
        env.settings.setHidden = { _, _ in false }
        env.settings.restart = { _ in false }
        var files = env.settings.fileSystem
        files.write = { _, _ in throw CocoaError(.featureUnsupported) }
        files.remove = { _ in throw CocoaError(.featureUnsupported) }
        files.move = { _, _ in throw CocoaError(.featureUnsupported) }
        env.settings.fileSystem = files
        // Background Items: the same refusals, and a journal that never writes.
        let backgroundLaunchctl = env.backgroundItems.launchctl
        env.backgroundItems.launchctl = { args in
            guard args.first == "print" || args.first == "print-disabled" else { return (1, "overlay_check never changes launchd") }
            return backgroundLaunchctl(args)
        }
        var journal = MacTweaksBackground.journal(env)
        journal.recordAhead = { _ in .failed("overlay_check never writes the journal") }
        journal.remove = { _ in "overlay_check never writes the journal" }
        env.backgroundItems.journal = journal
        return env
    }
}
