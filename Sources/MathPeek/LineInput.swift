import AppKit
import SwiftUI

/// One line of working being typed. Return starts the next line, Delete in an empty line
/// takes it away, and the up and down arrows move between lines.
struct LineInput: NSViewRepresentable {
    let model: LearnModel
    let index: Int
    let text: String
    let request: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model, index: index, request: request) }

    func makeNSView(context: Context) -> NSTextField {
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let field = ProblemTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = font
        field.placeholderAttributedString = NSAttributedString(string: model.fillsIn ? "" : (index == 0 ? "Your first line" : "Your next line"), attributes: [
            .font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.3),
        ])
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.index = index
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.request != request {
            context.coordinator.request = request
            if model.focusedLine == index {
                DispatchQueue.main.async { (field as? ProblemTextField)?.takeKeys() }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LearnModel
        var index: Int
        var request: Int

        init(model: LearnModel, index: Int, request: Int) {
            self.model = model
            self.index = index
            self.request = request
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, model.myLines.indices.contains(index) else { return }
            model.myLines[index] = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if model.fillsIn { model.submitFill(index) } else { model.newLine(after: index) }
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty && !model.fillsIn:
                model.removeLine(index)
            case #selector(NSResponder.moveUp(_:)):
                model.moveLine(from: index, by: -1)
            case #selector(NSResponder.moveDown(_:)):
                model.moveLine(from: index, by: 1)
            default:
                return false
            }
            return true
        }
    }
}
