import SwiftUI
import AppKit

// MARK: - Custom Commands Manager View

struct CustomCommandsView: View {
    let commands: [CustomCommand]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onRun: (Int) -> Void
    let onDelete: (Int) -> Void
    let onMove: (Int, Int) -> Void
    let onSave: (CustomCommand) -> Void
    let onClose: () -> Void

    @State private var isEditing: Bool = false
    @State private var editingCommand: CustomCommand? = nil

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                editorView
            } else {
                listView
            }
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

    // MARK: - List Mode View

    private var listView: some View {
        VStack(spacing: 0) {
            listHeader

            Divider()
                .background(Color.white.opacity(0.12))

            if commands.isEmpty {
                emptyState
            } else {
                listContent
            }

            Divider()
                .background(Color.white.opacity(0.12))

            listFooter
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            Text("Custom Commands")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(.white)

            Text("\(commands.count)/\(CustomCommandsStore.maxCommands)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            Spacer()

            Button(action: {
                editingCommand = CustomCommand(name: "", type: .url, target: "", keywords: [])
                isEditing = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("New")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .help("Add new custom command")

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

    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        CustomCommandRow(
                            index: index,
                            command: command,
                            isSelected: index == selectedIndex,
                            isFirst: index == 0,
                            isLast: index == commands.count - 1,
                            onSelect: { onSelect(index) },
                            onRun: { onRun(index) },
                            onEdit: {
                                editingCommand = command
                                isEditing = true
                            },
                            onDelete: { onDelete(index) },
                            onMoveUp: { onMove(index, -1) },
                            onMoveDown: { onMove(index, 1) }
                        )
                        .id(command.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedIndex) { newIndex in
                if newIndex >= 0 && newIndex < commands.count {
                    proxy.scrollTo(commands[newIndex].id, anchor: nil)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "command.square")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.white.opacity(0.3))

            Text("No custom commands yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            Text("Add commands to open websites, launch Terminal scripts, or run AppleScript.")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                editingCommand = CustomCommand(name: "", type: .url, target: "", keywords: [])
                isEditing = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Command")
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listFooter: some View {
        HStack(spacing: 14) {
            hint(key: "↑↓", label: "Select")
            hint(key: "⏎", label: "Run")
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

    // MARK: - Editor Mode View

    private var editorView: some View {
        CustomCommandEditorView(
            command: editingCommand ?? CustomCommand(name: "", type: .url, target: "", keywords: []),
            onSave: { updated in
                onSave(updated)
                isEditing = false
                editingCommand = nil
            },
            onCancel: {
                isEditing = false
                editingCommand = nil
            }
        )
    }
}

// MARK: - Custom Command Row

struct CustomCommandRow: View {
    let index: Int
    let command: CustomCommand
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 18, alignment: .trailing)

            // Type Icon
            Image(systemName: command.type.sfSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Color.white.opacity(0.12))
                )

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(command.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)

                    Text(command.type.displayName)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(Color.white.opacity(0.10))
                        )
                }

                Text(command.target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Action Buttons
            HStack(spacing: 2) {
                iconButton(symbol: "chevron.up", help: "Move up", disabled: isFirst, action: onMoveUp)
                iconButton(symbol: "chevron.down", help: "Move down", disabled: isLast, action: onMoveDown)
                iconButton(symbol: "pencil", help: "Edit", disabled: false, action: onEdit)
                iconButton(symbol: "play.fill", help: "Run", disabled: false, action: onRun)
                iconButton(symbol: "trash.fill", help: "Delete", disabled: false, action: onDelete)
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

    private func iconButton(symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(disabled ? 0.2 : 0.75))
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

// MARK: - Custom Command Editor View

struct CustomCommandEditorView: View {
    let command: CustomCommand
    let onSave: (CustomCommand) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var type: CustomCommandType
    @State private var target: String
    @State private var keywords: String

    init(command: CustomCommand, onSave: @escaping (CustomCommand) -> Void, onCancel: @escaping () -> Void) {
        self.command = command
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: command.name)
        _type = State(initialValue: command.type)
        _target = State(initialValue: command.target)
        _keywords = State(initialValue: command.keywords.joined(separator: ", "))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: command.name.isEmpty ? "plus.square.fill" : "pencil.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Text(command.name.isEmpty ? "New Custom Command" : "Edit Custom Command")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()
                .background(Color.white.opacity(0.12))

            // Form Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Type Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command Type")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        HStack(spacing: 6) {
                            ForEach(CustomCommandType.allCases, id: \.self) { cmdType in
                                Button(action: { type = cmdType }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: cmdType.sfSymbol)
                                            .font(.system(size: 11))
                                        Text(cmdType.displayName)
                                            .font(.system(size: 12, weight: type == cmdType ? .semibold : .regular))
                                    }
                                    .foregroundColor(type == cmdType ? .white : .white.opacity(0.65))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(type == cmdType ? Color.white.opacity(0.20) : Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(type == cmdType ? 0.35 : 0.08), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Name Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("e.g. Open GitHub", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                            )
                    }

                    // Target Field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(targetLabel)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(targetHint)
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        TextField(type.placeholder, text: $target)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                            )
                    }

                    // Keywords Field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Keywords")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("Optional, comma-separated")
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        TextField("e.g. gh, code, pr, issues", text: $keywords)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                            )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Footer
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .buttonStyle(.plain)

                Spacer()

                Button(action: saveAction) {
                    Text("Save Command")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isValid ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isValid ? Color.blue.opacity(0.7) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
    }

    private var targetLabel: String {
        switch type {
        case .url: return "URL"
        case .terminal: return "Terminal Command"
        case .appleScript: return "AppleScript Code"
        case .shell: return "Shell Script Command"
        }
    }

    private var targetHint: String {
        switch type {
        case .url: return "Opens in default browser"
        case .terminal: return "Runs in Terminal.app window"
        case .appleScript: return "Runs via osascript"
        case .shell: return "Runs in background (/bin/zsh)"
        }
    }

    private func saveAction() {
        guard isValid else { return }
        let parsedKeywords = keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let updated = CustomCommand(
            id: command.id,
            name: name,
            type: type,
            target: target,
            keywords: parsedKeywords
        )
        onSave(updated)
    }
}
