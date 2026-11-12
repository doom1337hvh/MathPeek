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
    /// Looking over the screens for problems to highlight, and what's been found so far.
    private var scan: Task<Void, Never>?
    private var spotted: [[Solution]] = []
    /// What was made out, drawn over the screen, when that's turned on in Settings.
    private let overlay = SeenOverlay()
    private var watch: Task<Void, Never>?
    /// Where the bubble for what was just read has got to. What was made out stays on screen
    /// as long as that bubble does, and goes with it.
    private enum BubbleState { case coming, showing, gone }
    private var bubbleState = BubbleState.coming
    /// Opens the working: every problem found, and which to show first.
    var showWorking: (([Solution], Int) -> Void)?

    init(prefs: Preferences, access: ScreenAccess, bubble: AnswerBubble) {
        self.prefs = prefs
        self.access = access
        self.bubble = bubble
        bubble.onHide = { [weak self] in self?.bubbleWent() }
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

    /// Dims the screen so you can drag out the area to read. Meanwhile each screen is looked
    /// over for problems, which are highlighted as they're found: clicking one shows its answer.
    func readChosenArea() {
        guard hasAccess(showingAt: NSEvent.mouseLocation) else { return }
        scan?.cancel()
        spotted = []
        clearOverlay()
        picker.pick { [weak self] picked in
            guard let self else { return }
            self.scan?.cancel()
            self.clearOverlay()
            switch picked {
            case .area(let rect):
                self.read(rect, focus: CGPoint(x: rect.midX, y: rect.midY), bubbleAt: NSEvent.mouseLocation)
            case .point(let point):
                self.readAround(point)
            case .spot(let number):
                guard self.spotted.indices.contains(number) else { return }
                self.task?.cancel()
                self.show(.solved(self.spotted[number], primary: 0), at: NSEvent.mouseLocation)
            case nil:
                break
            }
        }
        // The screen the pointer is on first.
        let pointer = NSEvent.mouseLocation
        let all = NSScreen.screens
        let screens = (all.filter { $0.frame.contains(pointer) } + all.filter { !$0.frame.contains(pointer) }).compactMap { screen -> (ScreenArea, CGRect)? in
            ScreenArea(screen.frame, focus: CGPoint(x: screen.frame.midX, y: screen.frame.midY), on: screen).map { ($0, screen.frame) }
        }
        let options = ReadOptions(angles: prefs.angles, useModel: false)
        let watching = prefs.showsWhatItSees
        scan = Task { [weak self] in
            for (area, frame) in screens {
                let seen = watching ? SeenBox() : nil
                let found = await Task.detached(priority: .userInitiated) { await ScreenReader.spot(area, options, seen: seen) }.value
                guard let self, !Task.isCancelled, self.picker.isPicking else { return }
                if let seen = seen?.seen { self.overlay.show(seen, over: frame, outlined: false) }
                let first = self.spotted.count
                self.spotted += found.map(\.solutions)
                // From the top-left of the screen, to global coordinates.
                self.picker.highlight(found.enumerated().map { index, spot in
                    (first + index, CGRect(x: frame.minX + spot.box.minX, y: frame.maxY - spot.box.maxY,
                                           width: spot.box.width, height: spot.box.height))
                })
            }
        }
    }

    func stop() {
        picker.cancel()
        scan?.cancel()
        task?.cancel()
        clearOverlay()
        bubble.hide()
    }

    /// Takes away what was drawn for the last read. A bubble still showing from it no longer
    /// has anything to take with it.
    private func clearOverlay() {
        watch?.cancel()
        overlay.hide()
        bubbleState = .coming
    }

    /// The bubble for what was just read has gone, and what was made out goes with it.
    private func bubbleWent() {
        guard bubbleState == .showing else { return }
        bubbleState = .gone
        overlay.hide()
    }

    /// Draws what's made out in the area just read, over it, until the bubble goes or the
    /// shortcut is pressed again. If the bubble has gone before it's ready, it stays for as
    /// long as an answer does (Settings).
    private func showWhatWasSeen(in area: ScreenArea, over frame: CGRect) {
        let options = ReadOptions(angles: prefs.angles, useModel: false)
        let seconds = prefs.answerSeconds
        watch = Task { [weak self] in
            let seen = SeenBox()
            _ = await Task.detached(priority: .utility) { await ScreenReader.spot(area, options, seen: seen) }.value
            guard let self, !Task.isCancelled, let seen = seen.seen else { return }
            self.overlay.show(seen, over: frame, outlined: true)
            guard self.bubbleState == .gone else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.overlay.hide()
        }
    }

    private func readAround(_ point: CGPoint) {
        let size = CGSize(width: prefs.areaWidth, height: prefs.areaHeight)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        // A diagram is bigger than the area for a line of maths.
        let side = max(size.width, size.height, 900)
        read(rect, wide: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side), focus: point, bubbleAt: point)
    }

    private func read(_ rect: CGRect, wide: CGRect? = nil, focus: CGPoint, bubbleAt anchor: CGPoint) {
        guard hasAccess(showingAt: anchor) else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(focus) }) ?? NSScreen.main,
              let area = ScreenArea(rect, focus: focus, on: screen) else { return }
        let around = wide.flatMap { ScreenArea($0, focus: focus, on: screen) }
        task?.cancel()
        clearOverlay()
        if prefs.showsWhatItSees { showWhatWasSeen(in: area, over: rect.intersection(screen.frame).integral) }
        bubble.prepare(at: anchor)
        let options = ReadOptions(angles: prefs.angles, useModel: prefs.useAppleIntelligence)
        task = Task { [weak self] in
            // Off the main thread: text recognition takes a moment.
            let reading = await Task.detached(priority: .userInitiated) {
                await ScreenReader.read(area, wide: around, options)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.show(reading, at: anchor)
        }
    }

    private func show(_ reading: Reading, at anchor: CGPoint) {
        // With what was made out drawn on screen, every bubble stays at least as long as an
        // answer does, so the two can be looked at together.
        bubbleState = .showing
        bubble.minimumSeconds = prefs.showsWhatItSees ? prefs.answerSeconds : 0
        switch reading {
        case .solved(let solutions, let primary) where solutions.count > 1:
            let open: () -> Void = { [weak self] in self?.showWorking?(solutions, primary) }
            let rows = solutions.enumerated().map { index, solution in
                BubbleRow(question: summary(of: solution), answer: solution.answers.isEmpty ? (solution.note ?? "No solution") : answer(of: solution),
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
            var math = solution.answerSets == nil && solution.answers.count <= 4 && solution.answerText.count <= 48
                ? solution.answers : []
            // An angle's name is in the line above: just its size here.
            if case .diagram = solution.problem.kind, let line = solution.answers.first, let size = line.parts.last { math = [MathLine(size, suffix: line.suffix)] }
            bubble.show(.answer(sum: summary(of: solution), answer: answer(of: solution),
                                detail: detail.isEmpty ? nil : detail, copy: copyText(solution), math: math),
                        at: anchor, for: prefs.answerSeconds, action: open)
        case .unsolved(let text):
            bubble.show(.message(symbol: "questionmark.circle", title: "Can't work that out yet",
                                 detail: "MathPeek read “\(text)” but doesn't know how to solve it."),
                        at: anchor, for: 5)
        case .words:
            let hint = prefs.useAppleIntelligence || !Tutor.isAvailable ? "" : " Use Apple Intelligence, in Settings, can read more of them."
            bubble.show(.message(symbol: "questionmark.circle", title: "Can't read this question",
                                 detail: "MathPeek couldn't turn these words into maths." + hint),
                        at: anchor, for: 5)
        case .unclear:
            bubble.show(.message(symbol: "questionmark.circle", title: "Can't read that clearly",
                                 detail: "Part of it is too small or too close together to make out. Zoom in and try again."),
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
        case .evaluate, .simplify, .diagram:
            return solution.question.text + " ="
        default:
            return LearnModel.summary(solution)
        }
    }

    /// The answer as the bubble shows it. An angle's name is already beside it.
    private func answer(of solution: Solution) -> String {
        // An angle has its degree sign, a length what it's measured in.
        if case .diagram = solution.problem.kind, let line = solution.answers.first, let size = line.parts.last {
            return Format.text(size) + (line.suffix.map { $0 == "°" ? $0 : " " + $0 } ?? "")
        }
        return solution.answerText
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
