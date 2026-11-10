import AppKit

/// What happens when the shortcut is pressed: pick the area (around the pointer, or dragged
/// out), read it, and show the answer by the pointer.
@MainActor
final class MathReader {
    private let prefs: Preferences
    private let access: ScreenAccess
    private let bubble: AnswerBubble
    private let picker = AreaPicker()
    private var task: Task<Void, Never>?
    /// Opens the working: every problem found, and which to show first.
    var showWorking: (([Solution], Int) -> Void)?

    init(prefs: Preferences, access: ScreenAccess, bubble: AnswerBubble) {
        self.prefs = prefs
        self.access = access
        self.bubble = bubble
    }

    /// The shortcut. Pressed again while you're dragging out an area, it cancels.
    func readByPointer() {
        if picker.isPicking {
            picker.cancel()
            return
        }
        switch prefs.areaMode {
        case .aroundPointer: readAround(NSEvent.mouseLocation)
        case .drag: readChosenArea()
        }
    }

    /// Dims the screen so you can drag out the area to read.
    func readChosenArea() {
        guard hasAccess(showingAt: NSEvent.mouseLocation) else { return }
        picker.pick { [weak self] rect in
            guard let self, let rect else { return }
            if rect.size == .zero {
                self.readAround(rect.origin)
            } else {
                self.read(rect, focus: CGPoint(x: rect.midX, y: rect.midY), bubbleAt: NSEvent.mouseLocation)
            }
        }
    }

    func stop() {
        picker.cancel()
        task?.cancel()
        bubble.hide()
    }

    private func readAround(_ point: CGPoint) {
        let size = CGSize(width: prefs.areaWidth, height: prefs.areaHeight)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        read(rect, focus: point, bubbleAt: point)
    }

    private func read(_ rect: CGRect, focus: CGPoint, bubbleAt anchor: CGPoint) {
        guard hasAccess(showingAt: anchor) else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(focus) }) ?? NSScreen.main,
              let area = ScreenArea(rect, focus: focus, on: screen) else { return }
        task?.cancel()
        bubble.prepare(at: anchor)
        let options = ReadOptions(angles: prefs.angles, useModel: prefs.useAppleIntelligence)
        task = Task { [weak self] in
            // Off the main thread: text recognition takes a moment.
            let reading = await Task.detached(priority: .userInitiated) {
                await ScreenReader.read(area, options)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.show(reading, at: anchor)
        }
    }

    private func show(_ reading: Reading, at anchor: CGPoint) {
        switch reading {
        case .solved(let solutions, let primary) where solutions.count > 1:
            let open: () -> Void = { [weak self] in self?.showWorking?(solutions, primary) }
            let rows = solutions.enumerated().map { index, solution in
                BubbleRow(question: summary(of: solution), answer: solution.answers.isEmpty ? (solution.note ?? "No solution") : solution.answerText,
                          isNearest: index == primary)
            }
            let copy = solutions.enumerated().map { "\($0 + 1). \(copyText($1))" }.joined(separator: "\n")
            bubble.show(.list(rows: Array(rows.prefix(6)), copy: copy), at: anchor, for: prefs.answerSeconds + 2, action: open)
        case .solved(let solutions, _):
            let solution = solutions[0]
            let open: () -> Void = { [weak self] in self?.showWorking?(solutions, 0) }
            guard !solution.answers.isEmpty else {
                bubble.show(.problem(sum: summary(of: solution), message: solution.note ?? "No solution"),
                            at: anchor, for: prefs.answerSeconds, action: open)
                return
            }
            let detail = [solution.approximation, solution.note.flatMap { $0.hasPrefix("C is") ? nil : $0 }]
                .compactMap { $0 }.joined(separator: " · ")
            let math = solution.answerSets == nil && solution.answers.count <= 4 && solution.answerText.count <= 48
                ? solution.answers : []
            bubble.show(.answer(sum: summary(of: solution), answer: solution.answerText,
                                detail: detail.isEmpty ? nil : detail, copy: copyText(solution), math: math),
                        at: anchor, for: prefs.answerSeconds, action: open)
        case .unsolved(let text):
            bubble.show(.message(symbol: "questionmark.circle", title: "Can't work that out yet",
                                 detail: "MathPeek read “\(text)” but doesn't know how to solve it."),
                        at: anchor, for: 5)
        case .noMaths:
            let near = prefs.areaMode == .drag ? "in that area" : "near the pointer"
            bubble.show(.message(symbol: "questionmark.circle", title: "No maths found",
                                 detail: "There's nothing to work out \(near)."),
                        at: anchor, for: 3)
        case .failed(let reason):
            bubble.show(.message(symbol: "exclamationmark.triangle", title: "Couldn't read that",
                                 detail: reason),
                        at: anchor, for: 6)
        }
    }

    /// The question in a line: "12 × (3 + 4.5) =", "x² − 5x + 6 = 0", "d/dx x² sin x".
    private func summary(of solution: Solution) -> String {
        switch solution.problem.kind {
        case .evaluate, .simplify:
            return solution.question.text + " ="
        default:
            return LearnModel.summary(solution)
        }
    }

    /// What ⌘C copies: the answer on its own, with a plain minus sign.
    private func copyText(_ solution: Solution) -> String {
        solution.answerText.replacingOccurrences(of: "−", with: "-")
    }

    /// Screen Recording. The first time, macOS asks, and the bubble says why; after that, the
    /// bubble offers System Settings.
    private func hasAccess(showingAt anchor: CGPoint) -> Bool {
        access.refresh()
        guard !access.isAllowed else { return true }
        let title = "MathPeek needs Screen Recording"
        if !prefs.askedForScreenRecording {
            prefs.askedForScreenRecording = true
            bubble.show(.message(symbol: "lock.shield", title: title,
                                 detail: "It reads the maths around the pointer, only when you press the shortcut, and only on this Mac. Allow it when macOS asks, then press the shortcut again."),
                        at: anchor, for: 15)
            access.request()
        } else {
            bubble.show(.message(symbol: "lock.shield", title: title,
                                 detail: "To read the maths on screen. Click here to open System Settings, turn on MathPeek, then press the shortcut again."),
                        at: anchor, for: 10, action: { [weak self] in self?.access.openSettings() })
        }
        return false
    }
}
