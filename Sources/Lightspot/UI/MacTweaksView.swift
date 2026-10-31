import SwiftUI
import AppKit

// MARK: - Mac Tweaks

/// Mac Tweaks in its own window (`MacTweaksWindowController`): one tab per built section; in
/// each, what it offers with the safe ones ticked, an itemized plan to confirm, the steps while
/// it applies, then the receipt. The window takes every key (`MacTweaksWindow.onKey`); clicks
/// reach the views. Dark in both appearances, filling the window under its transparent title bar.
///
/// Built from small view structs that take plain values: SwiftUI spells a view's whole type
/// out in every symbol name it generates, and one nested `body` of a few hundred lines made
/// names of 2,000 characters by the hundred (most of the binary's growth).
struct MacTweaksView: View {
    @ObservedObject var model: MacTweaksModel

    var body: some View {
        VStack(spacing: 0) {
            MacTweaksHeader(section: model.section, sections: model.sections, onSelect: model.select)
            OverlayDivider()
            MacTweaksContent(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OverlayDivider()
            MacTweaksFooter(hints: model.hints)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: MacTweaksWindowController.background))
    }
}

struct OverlayDivider: View {
    var body: some View {
        Divider().background(Color.white.opacity(0.12))
    }
}

/// A capsule button's label: the overlay's buttons, prominent (red) or quiet.
struct MacTweaksPill: View {
    let title: String
    var prominent = false
    var enabled = true

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(.white.opacity(enabled ? 0.95 : 0.4))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Capsule().fill(prominent && enabled ? Color.red.opacity(0.6) : Color.white.opacity(enabled ? 0.12 : 0.06)))
    }
}

// MARK: - Header

struct MacTweaksHeader: View {
    let section: MacTweaksSection
    let sections: [MacTweaksSection]
    let onSelect: (MacTweaksSection) -> Void

    var body: some View {
        // The section tabs; the window's title bar names Mac Tweaks and holds the close button.
        // Four tabs fit on one line at the window's 740 pt minimum: they were measured offscreen
        // at 700 pt with the title before them and the widest tab selected.
        HStack(spacing: 8) {
            ForEach(sections, id: \.self) { tab in
                Button(action: { onSelect(tab) }) {
                    MacTweaksTab(section: tab, selected: tab == section)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

struct MacTweaksTab: View {
    let section: MacTweaksSection
    let selected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: section.symbol)
                .font(.system(size: 10.5, weight: .semibold))
            Text(section.title)
                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(selected ? 0.95 : 0.55))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0.06)))
    }
}

// MARK: - Content

struct MacTweaksContent: View {
    @ObservedObject var model: MacTweaksModel

    var body: some View {
        switch model.state.phase {
        case .idle:
            MacTweaksMessage(title: model.section.scanningTitle)
        case .scanning(let line):
            MacTweaksMessage(title: line)
        case .ready:
            if model.isConfirming {
                MacTweaksPlan(model: model)
            } else {
                MacTweaksList(model: model)
            }
        case .applying(let steps):
            MacTweaksSteps(steps: steps, waiting: model.state.waiting)
        case .finished:
            MacTweaksReceiptView(receipt: model.state.receipt, logPath: model.logPath)
        }
    }
}

/// A scan's progress: a bar, what it is doing, and that it keeps going.
struct MacTweaksMessage: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 280)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text("This keeps running if you close the window.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - List

struct MacTweaksList: View {
    @ObservedObject var model: MacTweaksModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Up to three lines when snapshots or a long button ("Turn off 11 features, lock 3
                // already off…") leave it narrow, never cut short.
                Text(model.summaryLine)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if model.hasTickable {
                    if model.hasDefaults {
                        Button(action: model.tickDefaults) { MacTweaksPill(title: "Defaults") }.buttonStyle(.plain)
                    }
                    Button(action: model.tickNone) { MacTweaksPill(title: "None") }.buttonStyle(.plain)
                    Button(action: model.reviewPlan) {
                        MacTweaksPill(title: model.checkedRows.isEmpty ? "Nothing ticked" : model.applyTitle + "…",
                                      prominent: true, enabled: !model.checkedRows.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.checkedRows.isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 9)
            .padding(.bottom, 3)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        // Each row's own value, never an index into `model.rows`: the rows shrink
                        // (another section, a rescan's reset), and a row view still holding an
                        // index past the end trapped (1.4.0 QA).
                        let rows = model.rows
                        let headers = Self.groupHeaders(rows)
                        let cursor = model.cursor
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 3) {
                                if let header = headers[row.id] {
                                    MacTweaksGroupHeader(title: header)
                                }
                                MacTweaksRowView(row: model.shown(row), box: model.box(row), selected: index == cursor, home: model.home,
                                                 onBox: { if let link = row.link { model.open(link) } else { model.toggle(row.id) } },
                                                 onSelect: { model.setCursor(id: row.id) })
                            }
                            .id(row.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.cursor) { index in
                    let rows = model.rows
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id, anchor: nil) }
                }
            }
        }
    }

    /// The group header above each row that starts a group (Settings' Privacy, Finder…), by row ID.
    static func groupHeaders(_ rows: [MacTweaksRow]) -> [String: String] {
        var headers: [String: String] = [:]
        var previous: String?
        for row in rows {
            if let group = row.group, group != previous { headers[row.id] = group }
            previous = row.group
        }
        return headers
    }
}

/// The header above the first row of a group (Settings' Privacy, Finder…).
struct MacTweaksGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(.white.opacity(0.45))
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 1)
    }
}

// MARK: - Row

/// One row, from plain values: it never reads the model, so a row the list no longer has is
/// never asked to draw itself from rows that shrank.
struct MacTweaksRowView: View {
    let row: MacTweaksRow
    let box: MacTweaksTicks.Box
    let selected: Bool
    let home: String
    /// A click on the box: opens a link, else ticks or unticks the row.
    let onBox: () -> Void
    let onSelect: () -> Void

    /// Items listed under the selected row before "and N more".
    private static let shownItems = 4

    /// The box: an arrow for a link, a lock for a read-only row, an undo arrow for a tick that
    /// undoes, a dash for a preset partly ticked, else a tick box.
    static func boxSymbol(_ box: MacTweaksTicks.Box) -> String {
        switch box {
        case .link: return "arrow.up.forward.square"
        case .locked: return "lock.fill"
        case .unticked: return "square"
        case .ticked: return "checkmark.square.fill"
        case .undo: return "arrow.uturn.backward.square.fill"
        case .mixed: return "minus.square.fill"
        case .delete: return "trash.square.fill"
        }
    }

    static func boxColor(_ box: MacTweaksTicks.Box) -> Color {
        switch box {
        case .delete: return Color.red.opacity(0.85)
        case .link, .ticked, .undo, .mixed: return Color.white.opacity(0.9)
        case .locked, .unticked: return Color.white.opacity(0.45)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button(action: onBox) {
                    Image(systemName: Self.boxSymbol(box))
                        .font(.system(size: 14))
                        .foregroundColor(Self.boxColor(box))
                }
                .buttonStyle(.plain)
                Image(systemName: row.symbol)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Text(row.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(selected ? nil : 1)
                }
                Spacer(minLength: 8)
                ForEach(row.tags, id: \.self) { tag in
                    OverlayTag(label: tag, color: tag == "Deleted right away" || tag == MacTweaksTicks.deleteTag ? .red : .white,
                               symbol: tag == MacTweaksSettings.profileTag ? "lock" : nil)
                }
                Text(row.value)
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(minWidth: 64, alignment: .trailing)
            }
            if let caveat = row.caveat {
                Text(caveat)
                    .font(.system(size: 11))
                    .foregroundColor(.yellow.opacity(0.75))
                    .lineLimit(selected ? nil : 1)
                    .padding(.leading, 54)
            }
            if selected {
                MacTweaksItems(items: row.items, home: home, limit: Self.shownItems, sizes: true)
                    .padding(.leading, 54)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(selected ? 0.16 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// The first items of a row, then "and N more". Each in full, wrapped: a command or a path cut in
/// the middle ("defaults write NS…ain …") hides what runs.
struct MacTweaksItems: View {
    let items: [MacTweaksItem]
    let home: String
    let limit: Int
    let sizes: Bool

    private func line(_ item: MacTweaksItem) -> String {
        let path = CleanDevMacEngine.displayPath(item.target, home: home)
        return sizes && item.bytes > 0 ? path + "  " + MacTweaksProvider.size(item.bytes) : path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
                Text(verbatim: line(item))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if items.count > limit {
                Text("and \(items.count - limit) more")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}

// MARK: - Plan

struct MacTweaksPlan: View {
    @ObservedObject var model: MacTweaksModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.applyTitle + "?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(model.checkedRows) { row in
                        MacTweaksPlanRow(row: row, home: model.home)
                    }
                }
            }
            Text(model.planNotes.joined(separator: " "))
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.55))
            HStack(spacing: 10) {
                Spacer()
                Button(action: { _ = model.cancelConfirmation() }) { MacTweaksPill(title: "Back") }
                    .buttonStyle(.plain)
                Button(action: model.confirm) { MacTweaksPill(title: model.applyTitle, prominent: true) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

struct MacTweaksPlanRow: View {
    let row: MacTweaksRow
    let home: String

    /// Paths listed under each ticked row of the plan before "and N more".
    private static let planPaths = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: row.symbol)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 20)
                Text(row.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(row.value)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.countLabel != nil ? row.outcome : "\(row.items.count) \(row.items.count == 1 ? "item" : "items") · \(row.outcome)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                // Undo everything lists all it puts back.
                MacTweaksItems(items: row.items, home: home, limit: row.exclusive ? max(row.items.count, 1) : Self.planPaths, sizes: false)
                if let caveat = row.caveat {
                    Text(caveat)
                        .font(.system(size: 11))
                        .foregroundColor(.yellow.opacity(0.8))
                }
            }
            .padding(.leading, 30)
        }
    }
}

// MARK: - Applying and the receipt

struct MacTweaksSteps: View {
    let steps: [String]
    /// Waiting for System Settings: Esc stops the wait, and the line below says so.
    var waiting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Applying…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            // Done steps ticked, the running one last.
            Text(steps.enumerated().map { ($0.offset == steps.count - 1 ? "…  " : "✓  ") + $0.element }.joined(separator: "\n"))
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.75))
                .lineSpacing(5)
            Text(waiting ? MacTweaksProvider.waitNote : MacTweaksProvider.workingNote)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacTweaksReceiptView: View {
    let receipt: MacTweaksReceipt?
    let logPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                // The green check only when it did what was asked.
                Image(systemName: receipt?.isSuccess == false ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(receipt?.isSuccess == false ? .yellow.opacity(0.85) : .green.opacity(0.85))
                Text(receipt?.headline ?? "Done.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            // Lines, problems and notes scroll as one, so a long receipt never loses its end, and
            // the problems take room only when there are some.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 9) {
                    MacTweaksReceiptText(lines: receipt?.lines ?? [], size: 12, opacity: 0.75)
                    MacTweaksReceiptText(lines: receipt?.problems ?? [], size: 11.5, opacity: 0.75, color: .yellow)
                    MacTweaksReceiptText(lines: (receipt?.notes ?? []) + ["Logged to \(logPath)"], size: 12, opacity: 0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .flashingIndicators()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// A receipt longer than the overlay flashes its scroller once, so it shows there is more
    /// (macOS 14 and later; macOS 13 shows the cut-off line only).
    @ViewBuilder func flashingIndicators() -> some View {
        if #available(macOS 14.0, *) {
            scrollIndicatorsFlash(onAppear: true)
        } else {
            self
        }
    }
}

/// One block of the receipt, wrapped to the width; nothing for no lines.
struct MacTweaksReceiptText: View {
    let lines: [String]
    let size: CGFloat
    let opacity: Double
    var color: Color = .white

    var body: some View {
        if !lines.isEmpty {
            Text(verbatim: lines.joined(separator: "\n"))
                .font(.system(size: size))
                .foregroundColor(color.opacity(opacity))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Footer

struct MacTweaksFooter: View {
    let hints: [(key: String, label: String)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                OverlayKeyHint(key: hint.key, label: hint.label)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}
