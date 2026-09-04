import SwiftUI
import AppKit

// MARK: - Search History Manager View

struct SearchHistoryView: View {
    let entries: [SearchHistoryEntry]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onRun: (Int) -> Void
    let onDelete: (Int) -> Void
    let onClearAll: () -> Void
    let onClose: () -> Void

    init(
        entries: [SearchHistoryEntry],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void,
        onRun: @escaping (Int) -> Void,
        onDelete: @escaping (Int) -> Void,
        onClearAll: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.entries = entries
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onRun = onRun
        self.onDelete = onDelete
        self.onClearAll = onClearAll
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(Color.white.opacity(0.12))

            if entries.isEmpty {
                emptyState
            } else {
                list
            }

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
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            Text("Search History")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(.white)

            Text("\(entries.count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            Spacer()

            if !entries.isEmpty {
                Button(action: onClearAll) {
                    Text("Clear All")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Clear all search history")
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

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        SearchHistoryRow(
                            index: index,
                            entry: entry,
                            isSelected: index == selectedIndex,
                            onSelect: { onSelect(index) },
                            onRun: { onRun(index) },
                            onDelete: { onDelete(index) }
                        )
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedIndex) { newIndex in
                if newIndex >= 0 && newIndex < entries.count {
                    proxy.scrollTo(entries[newIndex].id, anchor: nil)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text("No search history yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Text("Items you select from search will appear here.")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.38))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            hint(key: "↑↓", label: "Select")
            hint(key: "⏎", label: "Open")
            hint(key: "⌫", label: "Delete")
            hint(key: "Esc", label: "Close")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
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

struct SearchHistoryRow: View {
    let index: Int
    let entry: SearchHistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            iconView
                .frame(width: 28, height: 28)

            // Titles
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)

                    if !entry.query.isEmpty {
                        Text("“\(entry.query)”")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                            )
                    }
                }

                HStack(spacing: 5) {
                    Text(entry.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))

                    Text(relativeTimeString(from: entry.selectedAt))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.40))
                }
            }

            Spacer(minLength: 8)

            // Frequency Pill & Actions
            HStack(spacing: 8) {
                if entry.selectionCount > 1 {
                    Text("\(entry.selectionCount)×")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.white.opacity(0.12))
                        )
                }

                Button(action: onRun) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Open (Return)")

                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Delete from history (Delete)")
            }
            .opacity(isHovered || isSelected ? 1 : 0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(0.18)
                        : (isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        switch entry.iconType {
        case .app(let path):
            LazyAppIconView(path: path, size: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .systemSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
        case .customImage(let base64):
            if let img = CustomIconCache.shared.image(for: base64) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "command.square.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        if elapsed < 604800 { return "\(Int(elapsed / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}
