import AppKit
import SwiftUI

/// The Mac Tweaks overlay's state: the provider's latest snapshot, the section on show, and
/// per section the ticks, the cursor and whether the plan is up for confirmation. Ticks
/// start at each row's default after every scan. Made the first time Mac Tweaks opens, so
/// launch builds nothing for it.
@MainActor
final class MacTweaksModel: ObservableObject {
    typealias Row = MacTweaksRow
    typealias SectionState = MacTweaksProvider.SectionState

    @Published private(set) var snapshot: MacTweaksProvider.Snapshot
    @Published private(set) var section: MacTweaksSection
    /// Per section, by `MacTweaksSection.index`.
    @Published private(set) var checked: [Set<String>]
    @Published private(set) var cursors: [Int]
    /// The itemized plan is showing; ↵ now applies.
    @Published private(set) var isConfirming = false

    /// ↵ on a link row: the view model owns the panel, so it opens the link.
    var onLink: ((MacTweaksLink) -> Void)?

    private let provider: MacTweaksProvider
    private var generations: [Int]
    /// The overlay is on screen: only then does a stale section scan again by itself.
    private var isShown = false

    init(provider: MacTweaksProvider = .shared) {
        self.provider = provider
        let snapshot = provider.snapshot
        self.snapshot = snapshot
        self.section = MacTweaksSection.built.first ?? .freeUpSpace
        let all = MacTweaksSection.allCases
        checked = all.map { Self.defaultTicks(snapshot[$0].rows) }
        cursors = all.map { _ in 0 }
        generations = all.map { snapshot[$0].generation }
        provider.setObserver { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var home: String { provider.environment.home }
    var sections: [MacTweaksSection] { MacTweaksSection.built }
    var state: SectionState { snapshot[section] }
    var rows: [Row] { state.rows }
    var cursor: Int { cursors[section.index] }
    var checkedIDs: Set<String> { checked[section.index] }
    /// The ticked rows an apply gets: never a link or a preset.
    var checkedRows: [Row] { MacTweaksTicks.ticked(rows, checkedIDs) }
    var offeredRows: [Row] { rows.filter { !$0.isLink } }
    var selectedRow: Row? { cursor >= 0 && cursor < rows.count ? rows[cursor] : nil }
    /// Any row Space can tick: without one (every row read-only) the tick buttons and hints go.
    var hasTickable: Bool { MacTweaksTicks.hasTickable(rows) }
    /// The plan's closing sentences, built from memory (the scan on show).
    var planNotes: [String] { provider.planNotes(section, rows: checkedRows) }
    var logPath: String { CleanDevMacEngine.displayPath(provider.environment.logURL.path, home: home) }

    /// What was found and what is ticked. Each section phrases its own.
    var summaryLine: String {
        if section == .appleIntelligence {
            return MacTweaksIntelligence.summary(rows: rows, context: snapshot.appleIntelligenceScan)
        }
        if section == .settings {
            return MacTweaksSettings.summary(rows: rows, ticked: checkedRows, context: snapshot.settingsScan)
        }
        if section == .backgroundItems { return MacTweaksBackground.summary(rows: rows, ticked: checkedRows) }
        let offered = offeredRows
        guard !offered.isEmpty else { return "Nothing to free right now." }
        let found = "Found \(Self.amount(offered)) in \(offered.count) \(offered.count == 1 ? "place" : "places")"
        let ticked = checkedRows
        return ticked.isEmpty ? found : found + " · " + Self.amount(ticked) + " ticked"
    }

    /// The plan's title and button: "Free up 16.3 GB", or "Turn off 3 features".
    var applyTitle: String {
        if section == .appleIntelligence { return MacTweaksIntelligence.applyTitle(ticked: checkedRows) }
        if section == .settings { return MacTweaksSettings.applyTitle(ticked: checkedRows) }
        if section == .backgroundItems { return MacTweaksBackground.applyTitle(ticked: checkedRows) }
        return "Free up " + Self.amount(checkedRows)
    }

    /// A size, plus what has none ("4 snapshots").
    static func amount(_ rows: [Row]) -> String {
        let bytes = rows.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        let counted = rows.compactMap { $0.bytes == nil ? $0.countLabel : nil }
        let parts = (bytes > 0 || counted.isEmpty ? [MacTweaksProvider.size(bytes)] : []) + counted
        return parts.joined(separator: " and ")
    }

    /// The footer's keys for where the section stands.
    var hints: [(key: String, label: String)] {
        let tab: [(key: String, label: String)] = sections.count > 1 ? [("⇥", "Section")] : []
        switch state.phase {
        case .ready where isConfirming:
            return [("⏎", "Apply"), ("Esc", "Back")]
        case .ready:
            var hints: [(key: String, label: String)] = [("↑↓", "Select")]
            if selectedRow?.isLink == true {
                hints.append(("⏎", "Open"))
            } else {
                if MacTweaksTicks.isTickable(selectedRow) { hints.append(("Space", "Tick")) }
                if hasTickable { hints.append(("⏎", "Review")) }
            }
            if revealPath != nil { hints.append(("⌥⏎", "Finder")) }
            return hints + tab + [("Esc", "Close")]
        case .finished:
            return [("⏎", "Rescan")] + (revealPath != nil ? [("⌥⏎", "Finder")] : []) + tab + [("Esc", "Close")]
        case .applying:
            // Esc stops a wait for System Settings; otherwise it closes and the apply goes on.
            return tab + [("Esc", MacTweaksProvider.escapeLabel(state))]
        case .idle, .scanning:
            return tab + [("Esc", "Close")]
        }
    }

    private static func defaultTicks(_ rows: [Row]) -> Set<String> {
        MacTweaksTicks.defaults(rows)
    }

    private func refresh() {
        let next = provider.snapshot
        for section in MacTweaksSection.built where next[section].generation != generations[section.index] {
            generations[section.index] = next[section].generation
            checked[section.index] = Self.defaultTicks(next[section].rows)
            cursors[section.index] = 0
            if section == self.section { isConfirming = false }
        }
        // The cursors fit the new rows before they are published: no view sees a cursor past
        // the end of its rows.
        for section in MacTweaksSection.built {
            let count = next[section].rows.count
            if cursors[section.index] >= max(count, 1) { cursors[section.index] = max(count - 1, 0) }
        }
        if next.revision != snapshot.revision { snapshot = next }
        // Off the plan if what it showed is gone (the rows were dropped or applied).
        if isConfirming && next[section].phase != .ready { isConfirming = false }
        // Another section's apply made the rows on show stale: scan them again now, off the plan.
        if isShown && next[section].isStale {
            isConfirming = false
            provider.open(section)
        }
    }

    // MARK: Opening and closing

    /// Scans the section on show unless it is busy or a recent scan or receipt stands.
    func open() {
        isConfirming = false
        isShown = true
        provider.open(section)
    }

    /// The overlay went away: the provider drops what no longer needs to be in memory.
    func close() {
        isConfirming = false
        isShown = false
        provider.overlayClosed()
        refresh()
    }

    /// ⇥ and ⇧⇥: the next or previous built section, opening it.
    func nextSection() { switchSection(by: 1) }
    func previousSection() { switchSection(by: -1) }

    func select(_ section: MacTweaksSection) {
        guard sections.contains(section), section != self.section else { return }
        self.section = section
        open()
    }

    /// Opens straight on a section (the Apple Intelligence search row), as opening does.
    func show(_ section: MacTweaksSection) {
        if sections.contains(section) { self.section = section }
        open()
    }

    private func switchSection(by offset: Int) {
        guard sections.count > 1, let index = sections.firstIndex(of: section) else { return }
        select(sections[(index + offset + sections.count) % sections.count])
    }

    // MARK: List

    func moveUp() {
        guard !isConfirming, !rows.isEmpty else { return }
        cursors[section.index] = cursor > 0 ? cursor - 1 : rows.count - 1
    }

    func moveDown() {
        guard !isConfirming, !rows.isEmpty else { return }
        cursors[section.index] = cursor < rows.count - 1 ? cursor + 1 : 0
    }

    /// A click on a row: the cursor goes to it, found by its ID among the rows on show now, so a
    /// click that lands as the rows change never selects another row.
    func setCursor(id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        cursors[section.index] = index
    }

    /// Space, or a click on the box: ticks or unticks a row. Nothing on a link or read-only row;
    /// an exclusive row is applied alone (`MacTweaksTicks.toggled`).
    func toggle(_ id: String) {
        guard !isConfirming, state.phase == .ready else { return }
        checked[section.index] = MacTweaksTicks.toggled(checked[section.index], id, in: rows)
    }

    /// How a row's box is drawn: ticked, an undo arrow, a preset partly ticked, a lock or a link.
    func box(_ row: Row) -> MacTweaksTicks.Box { MacTweaksTicks.box(row, checkedIDs, in: rows) }

    /// Whether any row starts ticked, so "Defaults" means something.
    var hasDefaults: Bool { rows.contains { $0.isDefault } }

    func toggleCursor() {
        guard let row = selectedRow else { return }
        toggle(row.id)
    }

    func tickDefaults() { checked[section.index] = Self.defaultTicks(rows) }
    func tickNone() { checked[section.index] = [] }

    // MARK: Plan and apply

    /// ↵: scan, open a link, show the plan, or apply it, depending on where the section stands.
    func primaryAction() {
        switch state.phase {
        case .idle, .finished:
            provider.startScan(section, force: true)
        case .ready:
            if isConfirming {
                confirm()
            } else if let link = selectedRow?.link {
                onLink?(link)
            } else if offeredRows.isEmpty {
                provider.startScan(section, force: true)
            } else {
                reviewPlan()
            }
        case .scanning, .applying:
            break
        }
    }

    func reviewPlan() {
        guard state.phase == .ready, !checkedRows.isEmpty else { return }
        isConfirming = true
    }

    func confirm() {
        guard isConfirming else { return }
        isConfirming = false
        provider.apply(section, ids: Set(checkedRows.map(\.id)))
    }

    /// Esc while the plan shows goes back to the list. False when there was no plan.
    func cancelConfirmation() -> Bool {
        guard isConfirming else { return false }
        isConfirming = false
        return true
    }

    /// Esc while this section waits for System Settings: stop that wait, this section's only.
    /// Panel hiding (System Settings taking the focus) does not reach here, so the wait survives
    /// that.
    func requestCancel() {
        provider.cancelWait(section)
    }

    /// A click on a link row's arrow.
    func open(_ link: MacTweaksLink) {
        onLink?(link)
    }

    /// ⌥↵: the path Finder shows for the selected row, where it has one; on a receipt, the
    /// app macOS wouldn't let go.
    var revealPath: String? {
        if state.phase == .finished { return state.receipt?.reveal }
        guard !isConfirming, let row = selectedRow, row.revealsInFinder else { return nil }
        return row.items.first?.target
    }
}
