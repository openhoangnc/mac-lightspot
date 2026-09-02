import AppKit
import SwiftUI

// MARK: - SearchFieldView (NSViewRepresentable wrapping NSTextField)

struct SearchFieldView: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Lightspot Search"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.textColor = .labelColor
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.onAction(_:))

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Do not overwrite stringValue while user is actively typing in the field editor
        if let editor = nsView.currentEditor() {
            if text.isEmpty && !editor.string.isEmpty {
                editor.string = ""
                nsView.stringValue = ""
            }
        } else {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onTextChange: (String) -> Void

        init(text: Binding<String>, onTextChange: @escaping (String) -> Void) {
            _text = text
            self.onTextChange = onTextChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let currentText = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
            text = currentText
            onTextChange(currentText)
        }

        @objc func onAction(_ sender: NSTextField) {
            // Return key handled by field editor
        }
    }
}
