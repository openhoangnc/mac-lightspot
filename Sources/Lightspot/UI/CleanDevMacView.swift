import SwiftUI
import AppKit

// MARK: - Clean Dev Mac (cdm) Overlay

/// cdm's menu, inside the panel: what can be reclaimed, biggest first, ticked to cdm's safe
/// defaults; an itemized plan to confirm; then the receipt. Drawn as an overlay like the
/// other managers, so the search field keeps focus and routes every key here.
struct CleanDevMacView: View {
    typealias Entry = CleanDevMacProvider.Entry

    @ObservedObject var model: CleanDevMacModel
    let onClose: () -> Void
    let onOpenInTerminal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(Color.white.opacity(0.12))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(Color.white.opacity(0.12))

            footer
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.88))

                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow, cornerRadius: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Color.black.opacity(0.72)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.85)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 14)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: CleanDevMacProvider.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            Text(CleanDevMacProvider.title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(.white)

            Text("cdm")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            Spacer()

            if let disk = model.snapshot.disk {
                Text(disk.line)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.snapshot.phase {
        case .idle, .loadingRules:
            progress(title: "Loading cdm's rules…", value: nil)
        case .measuring(let done, let total):
            progress(title: "Measuring reclaimable space… \(done) of \(total)",
                     value: total > 0 ? Double(done) / Double(total) : nil)
        case .ready:
            if model.isConfirming {
                plan
            } else if model.entries.isEmpty {
                message(symbol: "checkmark.seal", title: "Nothing to reclaim",
                        detail: "Everything cdm's rules cover is already clean.")
            } else {
                list
            }
        case .cleaning(let done, let total):
            progress(title: "Cleaning… \(done) of \(total)",
                     value: total > 0 ? Double(done) / Double(total) : nil)
        case .finished:
            receipt
        case .failed(let reason):
            message(symbol: "exclamationmark.triangle", title: "The scan could not run", detail: reason)
        }
    }

    private func progress(title: String, value: Double?) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Group {
                if let value {
                    ProgressView(value: value)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .frame(width: 280)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text("This keeps running if you close the panel.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            terminalNote
                .padding(.top, 6)
            Spacer()
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(CleanDevMacEngine.humanKB(model.totalKB)) reclaimable in \(model.entries.count) \(model.entries.count == 1 ? "category" : "categories")")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                tickButton("Defaults", help: "Tick cdm's safe defaults", action: model.tickDefaults)
                tickButton("All", help: "Tick every category", action: model.tickAll)
                tickButton("None", help: "Untick every category", action: model.tickNone)
                Button(action: model.reviewPlan) {
                    Text(model.checked.isEmpty ? "Nothing ticked" : "Clean \(CleanDevMacEngine.humanKB(model.checkedKB))…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(model.checked.isEmpty ? 0.4 : 0.95))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(model.checked.isEmpty ? Color.white.opacity(0.06) : Color.red.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .disabled(model.checked.isEmpty)
                .help("Review the plan, then clean (Return)")
            }
            .padding(.horizontal, 18)
            .padding(.top, 9)
            .padding(.bottom, 3)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            CleanDevMacRow(
                                entry: entry,
                                home: model.home,
                                isChecked: model.checked.contains(entry.id),
                                isSelected: index == model.cursor,
                                onToggle: { model.toggle(entry.id) },
                                onSelect: { model.cursor = index }
                            )
                            .id(entry.id)
                        }
                        terminalNote
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.cursor) { newIndex in
                    if newIndex >= 0 && newIndex < model.entries.count {
                        proxy.scrollTo(model.entries[newIndex].id, anchor: nil)
                    }
                }
            }
        }
    }

    private func tickButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// What only cdm itself cleans, and the key that runs it.
    @ViewBuilder
    private var terminalNote: some View {
        let names = model.snapshot.terminalOnly
        if !names.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                Text("⌘↵ runs cdm in Terminal for what it cleans there: \(names.joined(separator: ", ")).")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
    }

    // MARK: - Plan

    /// The itemized confirmation cdm prints before it asks `Proceed? (y/N)`.
    private var plan: some View {
        let entries = model.checkedEntries
        let permanent = entries.contains { $0.rule.method.isPermanent }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Clean \(CleanDevMacEngine.humanKB(model.checkedKB))?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        HStack(spacing: 10) {
                            CleanDevMacMethodTag(method: entry.rule.method)
                            Text(entry.rule.icon)
                                .font(.system(size: 13))
                            Text(entry.rule.name)
                                .font(.system(size: 12.5))
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                            Spacer()
                            Text(CleanDevMacEngine.humanKB(entry.sizeKB))
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
            }

            if permanent {
                Text("Delete removes permanently; caches regenerate on the next build or launch. Trash can be undone.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.5))
            }

            if !model.runningApps.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow.opacity(0.85))
                    Text(model.runningApps.count == 1
                         ? "Still running: \(model.runningApps[0]). Quit it first so it doesn't rewrite the caches you're about to delete, then reopen it after the clean."
                         : "Still running: \(model.runningApps.joined(separator: ", ")). Quit them first so they don't rewrite the caches you're about to delete, then reopen them after the clean.")
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11.5))
            }

            HStack(spacing: 10) {
                Spacer()
                Button(action: { _ = model.cancelConfirmation() }) {
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Back to the list (Esc)")

                Button(action: model.confirm) {
                    Text("Clean \(CleanDevMacEngine.humanKB(model.checkedKB))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red.opacity(0.65)))
                }
                .buttonStyle(.plain)
                .help("Clean now (Return)")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Receipt

    private var receipt: some View {
        let receipt = model.snapshot.receipt
        let before = receipt?.diskBefore
        let after = receipt?.diskAfter
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green.opacity(0.85))
                Text("Done. Freed roughly \(CleanDevMacEngine.humanKB(receipt?.freedKB ?? 0)).")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            if let after {
                // The volume's own number can lag the one above: the Trash still holds what
                // was moved there. Only claim a gain the volume agrees with.
                let gained = before.map { after.freeKB - $0.freeKB } ?? 0
                Text("Disk: \(after.line)" + (gained > 0 ? " (+\(CleanDevMacEngine.humanKB(gained)) free)" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }

            if receipt?.movedToTrash == true {
                Text("Items moved to the Trash can be restored from there.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            if let problems = receipt?.problems, !problems.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                            Text(problem)
                                .font(.system(size: 11.5))
                                .foregroundColor(.yellow.opacity(0.75))
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }

            Text("Logged to \(CleanDevMacEngine.displayPath(CleanDevMacEngine.logURL(home: model.home).path, home: model.home))")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.42))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                self.hint(key: hint.key, label: hint.label)
            }
            Spacer()
            // The list and the plan carry their own buttons; everywhere else the way on
            // is cdm itself.
            if !(model.snapshot.phase == .ready && (model.isConfirming || !model.entries.isEmpty)) {
                Button(action: onOpenInTerminal) {
                    Text("cdm in Terminal")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Run cdm in your terminal (⌘↵)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var hints: [(key: String, label: String)] {
        switch model.snapshot.phase {
        case .ready where model.isConfirming:
            return [("⏎", "Clean now"), ("Esc", "Back")]
        case .ready where !model.entries.isEmpty:
            return [("↑↓", "Select"), ("Space", "Tick"), ("⏎", "Review & clean"), ("⌥⏎", "Finder"), ("⌘⏎", "cdm in Terminal"), ("Esc", "Close")]
        case .ready, .finished:
            return [("⏎", "Rescan"), ("⌘⏎", "cdm in Terminal"), ("Esc", "Close")]
        case .failed:
            return [("⏎", "Retry"), ("⌘⏎", "cdm in Terminal"), ("Esc", "Close")]
        case .idle, .loadingRules, .measuring, .cleaning:
            return [("Esc", "Close")]
        }
    }

    private func hint(key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
        }
    }
}

// MARK: - Row

struct CleanDevMacRow: View {
    let entry: CleanDevMacProvider.Entry
    let home: String
    let isChecked: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    /// Paths listed under the selected row before "and N more".
    private static let shownPaths = 4

    @ViewState private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(isChecked ? 0.92 : 0.45))
                }
                .buttonStyle(.plain)
                .help(isChecked ? "Untick (Space)" : "Tick (Space)")

                Text(entry.rule.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)

                Text(entry.rule.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: 8)

                CleanDevMacMethodTag(method: entry.rule.method)

                Text(CleanDevMacEngine.humanKB(entry.sizeKB))
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(minWidth: 64, alignment: .trailing)
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 2) {
                    if !entry.rule.desc.isEmpty {
                        Text(entry.rule.desc)
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)
                    }
                    ForEach(Array(zip(entry.paths, entry.sizes).prefix(Self.shownPaths).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Text(CleanDevMacEngine.displayPath(item.0, home: home))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(CleanDevMacEngine.humanKB(item.1))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    if entry.paths.count > Self.shownPaths {
                        Text("and \(entry.paths.count - Self.shownPaths) more")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                .padding(.leading, 54)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(0.16)
                        : (isHovered ? Color.white.opacity(0.07) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}

/// cdm's plan tags: what happens to a category's paths.
struct CleanDevMacMethodTag: View {
    let method: CleanDevMacRule.Method

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(color.opacity(0.95))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
    }

    private var label: String {
        switch method {
        case .rm, .rmforce: return "DELETE"
        case .trash: return "TRASH"
        case .emptytrash: return "EMPTY TRASH"
        }
    }

    private var color: Color {
        method == .trash ? .yellow : .red
    }
}
