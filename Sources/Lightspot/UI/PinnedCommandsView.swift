import SwiftUI
import AppKit

// MARK: - Pinned Commands Manager

/// The pin manager sheet. It is drawn as an overlay inside the panel rather than as
/// a real `.sheet`: `SpotlightPanel` is a non-activating borderless panel that never
/// becomes main, so an AppKit sheet would have no window to attach to and would take
/// focus away from the search field that owns all keyboard routing.
struct PinnedCommandsView: View {
    let commands: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onRun: (Int) -> Void
    let onUnpin: (Int) -> Void
    /// `(index, offset)` — offset is -1 for "move up", +1 for "move down".
    let onMove: (Int, Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(Color.white.opacity(0.12))

            if commands.isEmpty {
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
            Image(systemName: "pin.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            Text("Pinned Commands")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(.white)

            Text("\(commands.count)/\(PinnedCommandsStore.maxPinned)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            Spacer()

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
                    ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                        PinnedCommandRow(
                            index: index,
                            command: command,
                            isSelected: index == selectedIndex,
                            isFirst: index == 0,
                            isLast: index == commands.count - 1,
                            onSelect: { onSelect(index) },
                            onRun: { onRun(index) },
                            onUnpin: { onUnpin(index) },
                            onMoveUp: { onMove(index, -1) },
                            onMoveDown: { onMove(index, 1) }
                        )
                        .id(command)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedIndex) { newIndex in
                if newIndex >= 0 && newIndex < commands.count {
                    proxy.scrollTo(commands[newIndex], anchor: nil)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "pin.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text("No pinned commands yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Text("Search your zsh history, then press ⌘P on a result to pin it here.")
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
            hint(key: "⏎", label: "Run in Terminal")
            hint(key: "⌘P", label: "Unpin")
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

struct PinnedCommandRow: View {
    let index: Int
    let command: String
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onUnpin: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 18, alignment: .trailing)

            Image(systemName: "pin.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text(singleLineCommand)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                iconButton(symbol: "chevron.up", help: "Move up", disabled: isFirst, action: onMoveUp)
                iconButton(symbol: "chevron.down", help: "Move down", disabled: isLast, action: onMoveDown)
                iconButton(symbol: "play.fill", help: "Run in Terminal", disabled: false, action: onRun)
                iconButton(symbol: "pin.slash.fill", help: "Unpin", disabled: false, action: onUnpin)
            }
            .opacity(isHovered || isSelected ? 1 : 0.35)
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

    /// Multi-line history entries are shown on a single line, like search results.
    private var singleLineCommand: String {
        guard command.contains("\n") else { return command }
        return command
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ⏎ ")
    }

    private func iconButton(symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(disabled ? 0.2 : 0.7))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(disabled ? 0.0 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}
