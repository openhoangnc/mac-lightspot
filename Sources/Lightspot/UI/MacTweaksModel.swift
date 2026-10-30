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
    var checkedRows: [Row] { rows.filter { !$0.isLink && checkedIDs.contains($0.id) } }
    var offeredRows: [Row] { rows.filter { !$0.isLink } }
    var selectedRow: Row? { cursor >= 0 && cursor < rows.count ? rows[cursor] : nil }
    /// The plan's closing sentences.
    var planNotes: [String] { provider.planNotes(section, rows: checkedRows) }
    var logPath: String { CleanDevMacEngine.displayPath(provider.environment.logURL.path, home: home) }

    /// What was found and what is ticked.
    var summaryLine: String {
        let offered = offeredRows
        guard !offered.isEmpty else { return "Nothing to free right now." }
        let found = "Found \(Self.amount(offered)) in \(offered.count) \(offered.count == 1 ? "place" : "places")"
        let ticked = checkedRows
        return ticked.isEmpty ? found : found + " · " + Self.amount(ticked) + " ticked"
    }

    /// The plan's title and button: "Free up 16.3 GB", "Free up 2.1 GB and 4 snapshots".
    var applyTitle: String { "Free up " + Self.amount(checkedRows) }

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
            hints += selectedRow?.isLink == true ? [("⏎", "Open")] : [("Space", "Tick"), ("⏎", "Review")]
            if revealPath != nil { hints.append(("⌥⏎", "Finder")) }
            return hints + tab + [("Esc", "Close")]
        case .finished:
            return [("⏎", "Rescan")] + (revealPath != nil ? [("⌥⏎", "Finder")] : []) + tab + [("Esc", "Close")]
        case .idle, .scanning, .applying:
            return tab + [("Esc", "Close")]
        }
    }

    private static func defaultTicks(_ rows: [Row]) -> Set<String> {
        Set(rows.filter { $0.isDefault && !$0.isLink }.map(\.id))
    }

    private func refresh() {
        let next = provider.snapshot
        for section in MacTweaksSection.built where next[section].generation != generations[section.index] {
            generations[section.index] = next[section].generation
            checked[section.index] = Self.defaultTicks(next[section].rows)
            cursors[section.index] = 0
            if section == self.section { isConfirming = false }
        }
        if next.revision != snapshot.revision { snapshot = next }
        // Off the plan if what it showed is gone (the rows were dropped or applied).
        if isConfirming && next[section].phase != .ready { isConfirming = false }
        for section in MacTweaksSection.built {
            let count = next[section].rows.count
            if cursors[section.index] >= max(count, 1) { cursors[section.index] = max(count - 1, 0) }
        }
    }

    // MARK: Opening and closing

    /// Scans the section on show unless it is busy or a recent scan or receipt stands.
    func open() {
        isConfirming = false
        provider.open(section)
    }

    /// The overlay went away: the provider drops what no longer needs to be in memory.
    func close() {
        isConfirming = false
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

    func setCursor(_ index: Int) {
        guard index >= 0, index < rows.count else { return }
        cursors[section.index] = index
    }

    /// Space, or a click on the box: ticks or unticks a row. Nothing on a link row.
    func toggle(_ id: String) {
        guard !isConfirming, state.phase == .ready, let row = rows.first(where: { $0.id == id }), !row.isLink else { return }
        if checked[section.index].contains(id) {
            checked[section.index].remove(id)
        } else {
            checked[section.index].insert(id)
        }
    }

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
