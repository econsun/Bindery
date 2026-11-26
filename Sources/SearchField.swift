import AppKit
import SwiftUI

/// AppKit-backed search field. SwiftUI's plain TextField uses a different
/// baseline for its prompt, which made the placeholder jump when editing; this
/// keeps the text and placeholder on the same line and gives us deterministic
/// Escape/click-away focus handling.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = .labelColor
        field.alignment = .left
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.placeholderAttributedString = placeholderString
        field.cell?.usesSingleLineMode = true
        field.cell?.alignment = .left
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderAttributedString = placeholderString
        if field.stringValue != text {
            field.stringValue = text
        }
        if isFocused, field.currentEditor() == nil {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    private var placeholderString: NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .left
                    return style
                }()
            ]
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        weak var field: NSTextField?
        private var clickMonitor: Any?
        private var keyMonitor: Any?

        init(_ parent: SearchField) {
            self.parent = parent
        }

        deinit {
            removeMonitors()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
            installMonitors()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
            removeMonitors()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.isFocused = false
                control.window?.makeFirstResponder(nil)
                parent.isFocused = false
                parent.onEscape()
                return true
            }
            return false
        }

        private func installMonitors() {
            if clickMonitor == nil {
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard let self, let field = self.field, event.window === field.window else { return event }
                    let point = field.convert(event.locationInWindow, from: nil)
                    if !field.bounds.contains(point) {
                        field.window?.makeFirstResponder(nil)
                    }
                    return event
                }
            }

            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let field = self.field,
                          event.keyCode == 53,
                          field.currentEditor() != nil else { return event }
                    field.window?.makeFirstResponder(nil)
                    self.parent.isFocused = false
                    self.parent.onEscape()
                    return nil
                }
            }
        }

        private func removeMonitors() {
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }
}
