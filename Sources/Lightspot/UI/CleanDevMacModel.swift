import AppKit
import SwiftUI

/// Clean Dev Mac's state: the provider's latest snapshot, which categories are ticked, the
/// cursor, and whether the plan is up for confirmation. Ticks start at each rule's `default`
/// after every scan, as they do in cdm's menu. Made the first time the window opens, so launch
/// builds nothing for it, and kept while Lightspot runs (`CleanDevMacWindowController`).
@MainActor
final class CleanDevMacModel: ObservableObject {
    typealias Entry = CleanDevMacProvider.Entry

    @Published private(set) var snapshot: CleanDevMacProvider.Snapshot
    @Published private(set) var checked: Set<Int>
    @Published var cursor = 0
    /// The itemized plan is showing; ↵ now cleans.
    @Published private(set) var isConfirming = false
    /// Apps that own a ticked cache and are running, read when the plan opens.
    @Published private(set) var runningApps: [String] = []

    private let provider: CleanDevMacProvider
    private var generation: Int

    init(provider: CleanDevMacProvider = .shared) {
        self.provider = provider
        let snapshot = provider.snapshot
        self.snapshot = snapshot
        self.generation = snapshot.generation
        self.checked = Self.defaultTicks(snapshot.entries)
        provider.setObserver { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var home: String { provider.environment.home }
    var entries: [Entry] { snapshot.entries }
    /// The cache scan is done and cdm's repo question is open.
    var canScanRepos: Bool { snapshot.phase == .ready && snapshot.repos == .offered && !isConfirming }
    var checkedEntries: [Entry] { entries.filter { checked.contains($0.id) } }
    var checkedKB: Int { CleanDevMacProvider.uniqueKB(checkedEntries) }
    var totalKB: Int { CleanDevMacProvider.uniqueKB(entries) }

    /// cdm's row under its status row: what a restart would free, once that is at least
    /// what the disk has free.
    var restartNote: String? {
        guard let disk = snapshot.disk else { return nil }
        return snapshot.restart?.line(freeKB: disk.freeKB)
    }

    /// cdm's Claude Code note: the setting that ages Desktop and Cowork sessions out too.
    var claudeNote: CleanDevMacEngine.ClaudeNote? { snapshot.claudeHistory?.note(home: home) }

    private static func defaultTicks(_ entries: [Entry]) -> Set<Int> {
        Set(entries.filter(\.rule.isDefault).map(\.id))
    }

    private func refresh() {
        let next = provider.snapshot
        if next.generation != generation {
            generation = next.generation
            checked = Self.defaultTicks(next.entries)
            cursor = 0
            isConfirming = false
        }
        if next != snapshot { snapshot = next }
        if cursor >= max(next.entries.count, 1) { cursor = max(next.entries.count - 1, 0) }
    }

    // MARK: Actions

    /// Opening measures again unless a recent scan stands.
    func open() {
        isConfirming = false
        provider.startScan()
    }

    func moveUp() {
        guard !isConfirming, !entries.isEmpty else { return }
        cursor = cursor > 0 ? cursor - 1 : entries.count - 1
    }

    func moveDown() {
        guard !isConfirming, !entries.isEmpty else { return }
        cursor = cursor < entries.count - 1 ? cursor + 1 : 0
    }

    func toggle(_ id: Int) {
        guard !isConfirming else { return }
        if checked.contains(id) {
            checked.remove(id)
        } else {
            checked.insert(id)
        }
    }

    /// Space.
    func toggleCursor() {
        guard cursor >= 0, cursor < entries.count else { return }
        toggle(entries[cursor].id)
    }

    func tickDefaults() { checked = Self.defaultTicks(entries) }
    func tickAll() { checked = Set(entries.map(\.id)) }
    func tickNone() { checked = [] }

    /// ⇥: cdm's "Also scan your code repos for build/dependency junk?".
    func scanRepos() {
        guard canScanRepos else { return }
        provider.scanRepos()
    }

    /// ↵: scan, review the plan, or confirm it, depending on where the cleaner stands.
    func primaryAction() {
        switch snapshot.phase {
        case .idle, .failed:
            provider.startScan(force: true)
        case .finished:
            // A rescan after a clean covers the repos again if they were scanned, as cdm's does.
            if case .scanned = snapshot.repos {
                provider.startScan(force: true, includeRepos: true)
            } else {
                provider.startScan(force: true)
            }
        case .ready:
            if isConfirming {
                confirm()
            } else if entries.isEmpty {
                provider.startScan(force: true)
            } else if !checked.isEmpty {
                reviewPlan()
            }
        case .loadingRules, .measuring, .scanningRepos, .cleaning:
            break
        }
    }

    /// cdm names the apps still running before the confirm, not after: quitting them
    /// first is what keeps a cleared cache from being written straight back.
    func reviewPlan() {
        guard snapshot.phase == .ready, !checked.isEmpty else { return }
        runningApps = CleanDevMacProvider.runningApps(for: checkedEntries)
        isConfirming = true
    }

    func confirm() {
        guard isConfirming else { return }
        isConfirming = false
        provider.clean(checked)
    }

    /// Esc while the plan shows goes back to the list. False when there was no plan.
    func cancelConfirmation() -> Bool {
        guard isConfirming else { return false }
        isConfirming = false
        return true
    }

    /// ⌥↵: the selected category's first path in Finder.
    func revealCursorInFinder() {
        guard cursor >= 0, cursor < entries.count, let path = entries[cursor].paths.first else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
