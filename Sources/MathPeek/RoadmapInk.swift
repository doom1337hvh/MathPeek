import AppKit
import SwiftUI

/// Keys for what's awkward to type, under the line being written: powers, a root, π, × and
/// ÷, degrees. A click puts it where the cursor is.
struct SymbolKeys: View {
    @Bindable var model: LearnModel
    var size: CGFloat = 1

    private static let keys: [(label: String, typed: String)] = [
        ("x²", "²"), ("x³", "³"), ("xⁿ", "^"), ("√", "√("), ("π", "π"), ("×", "×"), ("÷", "÷"), ("°", "°"),
    ]

    var body: some View {
        HStack(spacing: 5 * size) {
            ForEach(Array(Self.keys.enumerated()), id: \.offset) { _, key in
                let id = "key.\(key.typed)"
                Text(key.label)
                    .font(.system(size: 13 * size, weight: .medium, design: Z.maths))
                    .foregroundStyle(model.hovered == id ? Z.text : Z.body)
                    .frame(minWidth: 30 * size, minHeight: 24 * size)
                    .background(RoundedRectangle(cornerRadius: 5 * size, style: .continuous)
                        .fill(Color.white.opacity(model.hovered == id ? 0.14 : 0.08)))
                    .contentShape(Rectangle())
                    .onTapGesture { Self.type(key.typed) }
                    .hoverID(id, in: model)
            }
        }
    }

    /// Types into the field being written in, as the keyboard would.
    static func type(_ text: String) {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        editor.insertText(text, replacementRange: editor.selectedRange())
    }
}

// MARK: Writing on the roadmap

/// What a drag does on the roadmap while trying it yourself.
enum InkTool: CaseIterable, Hashable {
    case move, pen, highlighter, text, eraser

    var name: String {
        switch self {
        case .move: "Move"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .eraser: "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .move: "hand.raised"
        case .pen: "pencil"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }

    /// The key that picks it.
    var key: String {
        switch self {
        case .move: "m"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .eraser: "e"
        }
    }
}

/// The pointer over the roadmap shows the tool: a hand to move, a cross to write or rub out,
/// a text cursor to type. (Where the Mac is new enough to set it.)
struct InkPointer: ViewModifier {
    let tool: InkTool?

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(tool.map { tool -> PointerStyle in
                switch tool {
                case .move: .grabIdle
                case .text: .horizontalText
                case .pen, .highlighter, .eraser: .rectSelection
                }
            })
        } else {
            content
        }
    }
}

enum InkColor: CaseIterable, Hashable {
    case white, blue, red, yellow

    var name: String {
        switch self {
        case .white: "White"
        case .blue: "Blue"
        case .red: "Red"
        case .yellow: "Yellow"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .white: NSColor(white: 1, alpha: 0.9)
        case .blue: NSColor(red: 0.45, green: 0.68, blue: 1, alpha: 1)
        case .red: NSColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)
        case .yellow: NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

/// One thing written on the roadmap: a stroke of pen or highlighter, or typed text at its
/// top-left corner. In the roadmap's own units, so it moves and zooms with the steps.
struct InkMark: Identifiable, Equatable {
    var id = UUID()
    var points: [CGPoint]
    var color: InkColor
    var wide = false
    var text: String?

    static let textSize: CGFloat = 16

    /// Roughly where typed text sits.
    var textBox: CGRect? {
        guard let text, let corner = points.first else { return nil }
        return CGRect(x: corner.x, y: corner.y, width: max(14, CGFloat(text.count) * Self.textSize * 0.56), height: Self.textSize * 1.35)
    }

    /// Whether a line from `start` to `end` comes within `reach` of it.
    func isTouched(from start: CGPoint, to end: CGPoint, within reach: CGFloat) -> Bool {
        if let box = textBox?.insetBy(dx: -reach, dy: -reach) {
            return [start, end, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)].contains { box.contains($0) }
        }
        let near = reach + (wide ? 7 : 1)
        if points.contains(where: { Self.distance(from: $0, toLine: start, end) <= near }) { return true }
        return zip(points, points.dropFirst()).contains { a, b in
            Self.distance(from: start, toLine: a, b) <= near || Self.distance(from: end, toLine: a, b) <= near
        }
    }

    static func distance(from point: CGPoint, toLine a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / length, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

/// Your own working written anywhere on the roadmap while trying it yourself.
struct RoadmapInk: View {
    @Bindable var model: LearnModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for mark in model.marks + (model.drawing.map { [$0] } ?? []) where mark.text == nil {
                        let points = mark.points.map { model.inCanvas($0, width: size.width) }
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: first)
                        if points.count == 1 {
                            path.addEllipse(in: CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2))
                        }
                        // Smoothed through the middles of the points.
                        for index in points.indices.dropFirst() {
                            let previous = points[index - 1], point = points[index]
                            path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
                        }
                        if let last = points.last { path.addLine(to: last) }
                        context.stroke(path, with: .color(mark.color.color.opacity(mark.wide ? 0.32 : 1)),
                                       style: StrokeStyle(lineWidth: (mark.wide ? 14 : 2) * model.zoom, lineCap: .round, lineJoin: .round))
                    }
                }
                .allowsHitTesting(false)
                ForEach(model.marks.filter { $0.text != nil }) { note in
                    let corner = model.inCanvas(note.points[0], width: width)
                    if model.editingNote == note.id {
                        NoteField(model: model, id: note.id, text: note.text ?? "", color: note.color, zoom: model.zoom)
                            .frame(width: max(80, (note.textBox?.width ?? 0) + 40) * model.zoom, height: InkMark.textSize * 1.35 * model.zoom)
                            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1).padding(-3))
                            .offset(x: corner.x - 2 * model.zoom, y: corner.y)
                    } else {
                        Text(note.text ?? "")
                            .font(.system(size: InkMark.textSize * model.zoom))
                            .foregroundStyle(note.color.color)
                            .fixedSize()
                            .frame(height: InkMark.textSize * 1.35 * model.zoom)
                            .offset(x: corner.x, y: corner.y)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// Typing on the roadmap. Return or Escape finishes it, as does clicking elsewhere.
private struct NoteField: NSViewRepresentable {
    let model: LearnModel
    let id: UUID
    let text: String
    let color: InkColor
    let zoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(model: model, id: id) }

    func makeNSView(context: Context) -> NSTextField {
        let field = ProblemTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        style(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.id = id
        if field.stringValue != text { field.stringValue = text }
        style(field)
    }

    private func style(_ field: NSTextField) {
        field.font = .systemFont(ofSize: InkMark.textSize * zoom)
        field.textColor = color.nsColor
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LearnModel
        var id: UUID

        init(model: LearnModel, id: UUID) {
            self.model = model
            self.id = id
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.setNote(id, text: field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if model.editingNote == id { model.finishNote() }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
                model.finishNote()
                return true
            default:
                return false
            }
        }
    }
}

/// The tools for writing on the roadmap, its colours, and Undo and Clear.
struct InkToolbar: View {
    @Bindable var model: LearnModel

    var body: some View {
        HStack(spacing: 1) {
            ForEach(InkTool.allCases, id: \.self) { tool in
                let id = "tool.\(tool.name)"
                let chosen = model.inkTool == tool
                Image(systemName: tool.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(chosen || model.hovered == id ? Z.text : Z.secondary)
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(chosen ? 0.16 : 0)))
                    .contentShape(Rectangle())
                    .onTapGesture { model.choose(tool: tool) }
                    .hoverID(id, in: model)
                    .help("\(tool.name) (\(tool.key.uppercased()))")
            }
            divider
            ForEach(InkColor.allCases, id: \.self) { color in
                Circle()
                    .fill(color.color)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(Color.white.opacity(model.inkColor == color ? 0.85 : 0), lineWidth: 1.3).padding(-3.5))
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
                    .onTapGesture { model.choose(color: color) }
                    .help("\(color.name) (\((InkColor.allCases.firstIndex(of: color) ?? 0) + 1))")
            }
            divider
            key("Undo", id: "ink.undo", enabled: !model.inkHistory.isEmpty) { model.undoInk() }
                .help("Undo (⌘Z). Redo is ⇧⌘Z")
            key("Clear", id: "ink.clear", enabled: !model.marks.isEmpty) { model.clearInk() }
        }
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.32)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14).padding(.horizontal, 4)
    }

    private func key(_ title: String, id: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(enabled && model.hovered == id ? Z.text : Z.secondary)
            .opacity(enabled ? 1 : 0.4)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .hoverID(id, in: model)
    }
}
