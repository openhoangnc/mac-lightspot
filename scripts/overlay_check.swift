import AppKit
import SwiftUI

// The Mac Tweaks and Clean Dev Mac windows, hosted offscreen: the real controllers building the
// app's own windows (`ToolWindowController.makeWindow`: the `MacTweaksView` or `CleanDevMacView`
// in its `NSHostingView`) at (-6000, -6000). Mac Tweaks: its model on a provider that scans this Mac read-only
// (every writer refuses, Apple Intelligence's inventory runs in-process, never the Lightspot
// binary). Each section is scanned, rescanned with the cursor on its last row, and left for
// every other section and back, so the rows on show shrink each way they can: once with the
// rescan first, once with the switches first, since the first shrink is where a bad row view
// traps. Up to 1.4.0's QA, a row view reading `model.rows[index]` trapped there. The keys go
// through the window as AppKit delivers them (`sendEvent`): ↓ to the last row, ⇥ and ⇧⇥, Space,
// ⌫ to mark a row for deletion and unmark it, ↵ for the plan, Esc back out of it, Esc to close,
// and ⌘W after a reopen.
//
// Clean Dev Mac, after them: its window on a scan of this Mac's caches (cdm's rules from the
// repository, never fetched), its keys (↓, Space, ↵ for the plan and Esc out of it, never a
// second ↵, Esc to close, ⌘W after a reopen).
//
// Each run is a child process of its own, so a trap ends only that one and the report says
// which. Nothing is applied, cleaned, written, moved, asked for or opened (a link's ↵ goes
// nowhere); Lightspot isn't launched and the app is never activated.
//
//   swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift \
//       $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift)
//   /tmp/overlay_check            # from the repository root (it reads Resources/cdm-rules)
//   /tmp/overlay_check --render <folder>   # each window as PNGs, light and dark

@main
struct OverlayCheck {
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render"), flag + 1 < arguments.count {
            let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            exit(MainActor.assumeIsolated { Render(folder).run() })
        }
        if arguments.contains("--cleaner") {
            MainActor.assumeIsolated { CleanerRun().run() }
            exit(0)
        }
        if let flag = arguments.firstIndex(of: "--section"), flag + 1 < arguments.count,
           let section = MacTweaksSection(rawValue: arguments[flag + 1]) {
            let switchesFirst = arguments.contains("--switches-first")
            MainActor.assumeIsolated { SectionRun(section).run(switchesFirst: switchesFirst) }
            exit(0)
        }
        exit(runAll())
    }

    /// The parent: two children per built section (the rescan first, the switches first), then
    /// Clean Dev Mac's, each reported as it ends.
    static func runAll() -> Int32 {
        let me = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var failed = 0
        var runs = 0
        print("Mac Tweaks window, offscreen, sections: \(MacTweaksSection.built.map(\.title).joined(separator: ", ")); then Clean Dev Mac's")
        let children = MacTweaksSection.built.flatMap { section in
            [false, true].map { switchesFirst in
                ("\(section.title), \(switchesFirst ? "switches first" : "rescan first")",
                 ["--section", section.rawValue] + (switchesFirst ? ["--switches-first"] : []))
            }
        } + [("Clean Dev Mac", ["--cleaner"])]
        for (name, arguments) in children {
            runs += 1
            let process = Process()
            process.executableURL = URL(fileURLWithPath: me)
            process.arguments = arguments
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
                print("✅ \(name): survived every " + (arguments.first == "--cleaner" ? "key" : "rescan and switch"))
            }
        }
        print(failed == 0 ? "\n✅ The windows survived all \(runs) runs." : "\n❌ \(failed) of \(runs) runs failed.")
        return failed == 0 ? 0 : 1
    }
}

/// One child: the window on screen (offscreen), driven through one section's rescan and switches.
@MainActor
final class SectionRun {
    nonisolated static let survived = "SURVIVED"
    /// The longest a scan may take: Free Up Space measures every offered item.
    static let scanTimeout: TimeInterval = 120
    static let offscreen = NSPoint(x: -6000, y: -6000)

    let section: MacTweaksSection
    let provider: MacTweaksProvider
    let model: MacTweaksModel
    let controller: MacTweaksWindowController
    /// Links handed to the app.
    var links = 0

    init(_ section: MacTweaksSection) {
        self.section = section
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        provider = MacTweaksProvider(environment: Self.readOnlyEnvironment())
        model = MacTweaksModel(provider: provider)
        controller = MacTweaksWindowController(model: model, placement: .offscreen(Self.offscreen))
        // A link's ↵ (Clean Dev Mac, System Settings) goes nowhere here.
        controller.onLink = { [weak self] link in
            self?.links += 1
            self?.log("  (link \(link) not followed)")
        }
    }

    var window: ToolWindow? { controller.window }

    func log(_ line: String) {
        print(line)
        fflush(stdout)
    }

    var state: String {
        let s = model.state
        return "\(model.section.title): \(s.phase), \(s.rows.count) rows, cursor \(model.cursor)"
    }

    func fail(_ message: String) -> Never {
        log("FAIL: " + message)
        exit(3)
    }

    /// Runs the main loop (SwiftUI's updates, the provider's notifications) for `seconds`, or
    /// until `done`, drawing as it goes.
    @discardableResult
    func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            if let window {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            if done() { return true }
        }
        return done()
    }

    /// A key as AppKit hands it to the window.
    func press(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) {
        guard let window else { fail("a key with the window closed: \(state)") }
        Keys.press(window, keyCode, characters, flags)
        pump(0.05)
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
        // ↓ as the window takes it; it wraps, so at most `count` presses.
        for _ in 0..<count where model.cursor != count - 1 { press(125, "\u{F701}", [.numericPad, .function]) }
        if model.cursor != count - 1 { fail("↓ didn't reach the last row: \(state)") }
        pump(0.3)
    }

    func run(switchesFirst: Bool) {
        log("== \(section.title), \(switchesFirst ? "switches first" : "rescan first")")
        controller.show(section)
        guard let window else { fail("no window") }
        if !(window.contentView is NSHostingView<MacTweaksView>) || window.contentMinSize != MacTweaksWindowController.contentSize
            || window.title != MacTweaksProvider.title || !window.styleMask.contains(.titled) || window.hidesOnDeactivate {
            fail("the window isn't the app's: \(window.styleMask), \(window.contentMinSize)")
        }
        waitReady()
        log("scanned: \(state)")
        if switchesFirst {
            switches()
            rescan()
        } else {
            rescan()
            switches()
        }
        // The plan and back, then the window closed and opened again.
        cursorToLast()
        press(49, " ") // Space (nothing on a link row)
        if let link = model.selectedRow?.link, case .section = link {} else if model.selectedRow?.isLink == true {
            let before = links
            press(36, "\r") // ↵ on a link: handed to the app, the window stays
            if links != before + 1 || !controller.isOpen { fail("↵ on a link row didn't hand it over: \(state)") }
        }
        for _ in model.rows where model.selectedRow?.isLink == true { press(126, "\u{F700}", [.numericPad, .function]) }
        // ⌫ marks the row for deletion (Background Items) and unmarks it; on a leftover it is Space.
        if let row = model.selectedRow, MacTweaksTicks.canDelete(row) {
            let before = model.box(row)
            press(51, "\u{7F}")
            let marked = model.box(row)
            press(51, "\u{7F}")
            if marked == before || model.box(row) != before || (marked != .delete && before != .delete) {
                fail("⌫ didn't mark and unmark \(row.title): \(before) → \(marked) → \(model.box(row))")
            }
            log("⌫ on \(row.title): \(before) → \(marked) → \(model.box(row))")
        }
        // Something to review: Space ticks the row when nothing is ticked yet.
        if model.checkedRows.isEmpty, MacTweaksTicks.isTickable(model.selectedRow) { press(49, " ") }
        if model.selectedRow?.isLink == false, !model.checkedRows.isEmpty {
            press(36, "\r") // ↵: the plan
            pump(0.5)
            log("plan: confirming \(model.isConfirming), \(model.checkedRows.count) ticked")
            if !model.isConfirming { fail("↵ didn't show the plan: \(state)") }
            press(53, "\u{1B}") // Esc: back to the list
            if model.isConfirming || !controller.isOpen { fail("Esc didn't back out of the plan only: \(state)") }
        } else {
            log("plan: nothing ticked on a row to review")
        }
        waitReady()
        press(53, "\u{1B}") // Esc: closes
        pump(0.5)
        if controller.isOpen { fail("Esc didn't close the window: \(state)") }
        let closedWindow = window
        controller.show(nil)
        guard let reopened = self.window, reopened !== closedWindow else { fail("reopening didn't make a new window") }
        waitReady()
        log("reopened: \(state)")
        press(13, "w", .command) // ⌘W
        pump(0.5)
        if controller.isOpen { fail("⌘W didn't close the window") }
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

    /// Away to every other section and back, each switch from this section's last row: by the
    /// tabs' own action (`model.select`), then once by ⇥ and ⇧⇥.
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
        guard MacTweaksSection.built.count > 1 else { return }
        waitReady()
        cursorToLast()
        press(48, "\t") // ⇥
        let next = model.section
        log("⇥ to \(next.title): \(state)")
        if next == section { fail("⇥ didn't switch sections") }
        waitReady()
        cursorToLast()
        press(48, "\u{19}", .shift) // ⇧⇥
        log("⇧⇥ back: \(state)")
        if model.section != section { fail("⇧⇥ didn't come back to \(section.title)") }
        waitReady()
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
        journal.update = { _ in .failed("overlay_check never writes the journal") }
        env.backgroundItems.journal = journal
        return env
    }
}

/// A key as AppKit hands it to a window: through its `sendEvent`, where the tool takes it.
@MainActor
enum Keys {
    static func press(_ window: NSWindow, _ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else {
            print("FAIL: couldn't make key \(keyCode)")
            exit(3)
        }
        window.sendEvent(event)
    }

    /// The window and its title bar, drawn offscreen with `cacheDisplay` (ImageRenderer blanks
    /// scroll views), as a PNG at `url`.
    static func render(_ window: NSWindow, to url: URL) -> Bool {
        guard let frame = window.contentView?.superview else { return false }
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return false }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return false }
        print("wrote \(url.path) (\(rep.pixelsWide) × \(rep.pixelsHigh))")
        return true
    }
}

/// `--cleaner`: Clean Dev Mac's window on a read-only scan of this Mac's caches, through its keys.
/// Its plan is shown and backed out of, never confirmed.
@MainActor
final class CleanerRun {
    static let scanTimeout: TimeInterval = 180

    let provider: CleanDevMacProvider
    let model: CleanDevMacModel
    let controller: CleanDevMacWindowController
    var terminals = 0

    init() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        provider = CleanDevMacProvider(environment: Self.readOnlyEnvironment())
        model = CleanDevMacModel(provider: provider)
        controller = CleanDevMacWindowController(model: model, placement: .offscreen(SectionRun.offscreen))
        controller.onOpenInTerminal = { [weak self] in self?.terminals += 1 }
    }

    /// The live environment, offline (cdm's rules from the repository) and refusing the Trash.
    static func readOnlyEnvironment() -> CleanDevMacProvider.Environment {
        var env = CleanDevMacProvider.Environment.live
        env.bundledRules = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Resources/cdm-rules")
        env.fetchRemoteRules = { $0(nil) }
        env.moveToTrash = { _ in throw CocoaError(.featureUnsupported) }
        return env
    }

    func log(_ line: String) {
        print(line)
        fflush(stdout)
    }

    func fail(_ message: String) -> Never {
        log("FAIL: " + message)
        exit(3)
    }

    var state: String { "\(model.snapshot.phase), \(model.entries.count) categories, cursor \(model.cursor), \(model.checked.count) ticked" }

    @discardableResult
    func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            if let window = controller.window {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            if done() { return true }
        }
        return done()
    }

    func press(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) {
        guard let window = controller.window else { fail("a key with the window closed: \(state)") }
        Keys.press(window, keyCode, characters, flags)
        pump(0.05)
    }

    func waitSettled() {
        let settled = pump(Self.scanTimeout) {
            switch model.snapshot.phase {
            case .ready, .finished, .failed: return true
            default: return false
            }
        }
        if !settled { log("  (still scanning after \(Int(Self.scanTimeout)) s: \(state))") }
        pump(0.5)
    }

    func run() {
        log("== Clean Dev Mac")
        controller.show()
        guard let window = controller.window else { fail("no window") }
        if !(window.contentView is NSHostingView<CleanDevMacView>) || window.contentMinSize != CleanDevMacWindowController.size
            || window.title != CleanDevMacProvider.title || window.hidesOnDeactivate {
            fail("the window isn't the app's: \(window.styleMask), \(window.contentMinSize)")
        }
        waitSettled()
        log("scanned: \(state)")
        let count = model.entries.count
        if count > 1 {
            for _ in 0..<count where model.cursor != count - 1 { press(125, "\u{F701}", [.numericPad, .function]) }
            if model.cursor != count - 1 { fail("↓ didn't reach the last category: \(state)") }
            let before = model.checked
            press(49, " ") // Space
            if model.checked == before { fail("Space didn't tick or untick: \(state)") }
            press(49, " ")
            if model.checked != before { fail("Space again didn't put the tick back: \(state)") }
        }
        press(36, "\r", .command) // ⌘↵: cdm in the terminal (counted here, never run)
        if terminals != 1 || !controller.isOpen { fail("⌘↵ didn't hand cdm to the terminal with the window left open") }
        if model.snapshot.phase == .ready, !model.checked.isEmpty, !model.isConfirming {
            press(36, "\r") // ↵: the plan, never confirmed
            pump(0.3)
            log("plan: confirming \(model.isConfirming), \(model.checked.count) ticked")
            if !model.isConfirming { fail("↵ didn't show the plan: \(state)") }
            press(53, "\u{1B}") // Esc: back to the list
            if model.isConfirming || !controller.isOpen { fail("Esc didn't back out of the plan only: \(state)") }
        } else {
            log("plan: nothing ticked to review")
        }
        press(53, "\u{1B}") // Esc: closes
        pump(0.5)
        if controller.isOpen { fail("Esc didn't close the window") }
        controller.show()
        guard let reopened = controller.window, reopened !== window else { fail("reopening didn't make a new window") }
        waitSettled()
        log("reopened: \(state)")
        press(13, "w", .command) // ⌘W
        pump(0.5)
        if controller.isOpen { fail("⌘W didn't close the window") }
        log(SectionRun.survived)
    }
}

/// `--render <folder>`: each built section's window, and Clean Dev Mac's, as the app shows them
/// after a scan, drawn offscreen under both app appearances, title bar included. The windows are
/// dark in both; this shows they stay so.
@MainActor
final class Render {
    let folder: URL

    init(_ folder: URL) { self.folder = folder }

    func run() -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        var written = 0
        for section in MacTweaksSection.built {
            let run = SectionRun(section)
            run.controller.show(section)
            run.waitReady()
            // The second row selected, so its items show; in Background Items marked for deletion
            // with ⌫, so the trash box, the Delete tag and the delete's commands show.
            if run.model.rows.count > 1 { run.press(125, "\u{F701}", [.numericPad, .function]) }
            if let row = run.model.selectedRow, MacTweaksTicks.canDelete(row), !row.deletes { run.press(51, "\u{7F}") }
            run.pump(0.5)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                app.appearance = NSAppearance(named: appearance)
                run.pump(0.5)
                guard let window = run.window else { continue }
                if Keys.render(window, to: folder.appendingPathComponent("mac-tweaks-\(section.rawValue)-\(name).png")) { written += 1 }
            }
            run.controller.close()
            run.pump(0.3)
        }
        let cleaner = CleanerRun()
        cleaner.controller.show()
        cleaner.waitSettled()
        if cleaner.model.entries.count > 1 { cleaner.press(125, "\u{F701}", [.numericPad, .function]) }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            cleaner.pump(0.5)
            guard let window = cleaner.controller.window else { continue }
            if Keys.render(window, to: folder.appendingPathComponent("clean-dev-mac-\(name).png")) { written += 1 }
        }
        cleaner.controller.close()
        return written > 0 ? 0 : 1
    }
}
