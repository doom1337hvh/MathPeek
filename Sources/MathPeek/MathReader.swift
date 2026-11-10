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
        task = Task { [weak self] in
            // Off the main thread: text recognition takes a moment.
            let reading = await Task.detached(priority: .userInitiated) {
                await ScreenReader.read(area)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.show(reading, at: anchor)
        }
    }

    private func show(_ reading: Reading, at anchor: CGPoint) {
        switch reading {
        case .sum(let calculation):
            switch calculation.answer {
            case .success(let value):
                bubble.show(.answer(sum: calculation.text, answer: Maths.format(value),
                                    copy: Maths.format(value, forCopying: true)),
                            at: anchor, for: prefs.answerSeconds)
            case .failure(let problem):
                bubble.show(.problem(sum: calculation.text, message: problem.message),
                            at: anchor, for: prefs.answerSeconds)
            }
        case .noMaths:
            let near = prefs.areaMode == .drag ? "in that area" : "near the pointer"
            bubble.show(.message(symbol: "questionmark.circle", title: "No maths found",
                                 detail: "There's no sum to work out \(near)."),
                        at: anchor, for: 3)
        case .failed(let reason):
            bubble.show(.message(symbol: "exclamationmark.triangle", title: "Couldn't read that",
                                 detail: reason),
                        at: anchor, for: 6)
        }
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
