import AppKit
import Charts
import Observation
import SwiftUI

/// The tabs at the top of the working window.
enum LearnTab: String, CaseIterable, Identifiable {
    case route = "Roadmap"
    case graph = "Graph"

    var id: Self { self }

    var shortcut: KeyEquivalent {
        switch self {
        case .route: "1"
        case .graph: "2"
        }
    }
}

/// What the working window shows: the problems read (or typed), the one selected, and where
/// things stand on its roadmap.
@Observable @MainActor
final class LearnModel {
    var solutions: [Solution]
    var selectedProblem: Int
    var tab: LearnTab = .route
    /// Whether the problem is being typed or changed.
    var isEditing = false
    var input = ""
    /// Goes up each time the field is asked for, so it takes the keys again.
    var typingRequests = 0
    var message: String?
    var copied: String?
    /// Which answer is picked, when there are several, and whether its check is open.
    var selectedAnswer = 0
    var showsCheck = false
    /// The step that's open on the roadmap.
    var openStop: Int? {
        didSet {
            // The blue line reaches the open step's dot, and goes back up when none is open,
            // except while one step closes before the next opens (see `open(stop:)`).
            if openStop != nil || !holdsLine { lineStop = openStop }
        }
    }
    /// The step whose dot the blue line reaches.
    var lineStop: Int?
    /// How long the open step takes to change: shorter for a step closing on its way to the next.
    var stopDuration: Double = 0.42
    @ObservationIgnored private var holdsLine = false
    @ObservationIgnored private var opening: Task<Void, Never>?
    /// The part of the maths picked to look at.
    var picked: MathPart?
    /// The number being changed, and what's typed for it so far.
    var changing: MathNumber?
    var numberText = ""
    /// Trying it first: steps stay covered until they're asked for.
    var tryFirst = false
    var revealed = 0
    var answerRevealed = false
    /// What the pointer is over: a control, a part of the maths, a number.
    var hovered: String?
    var hoveredPart: String?
    var hoveredNumber: String?
    /// The angle or line of a diagram under the pointer.
    var hoveredFigure: Figure.Target?
    /// Whether open steps show what they did, written out, and a graph of it. Each stays on
    /// from step to step.
    var visualises = false
    var graphs = false
    /// How far the roadmap is zoomed and moved.
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var titlebarHeight: CGFloat = 28
    @ObservationIgnored let prefs: Preferences
    /// The answers given before, and whether they're showing in place of the working.
    @ObservationIgnored var history: History?
    var showsHistory = false
    /// Asking before the history is cleared.
    var confirmsClear = false
    /// What's typed to find something in the history.
    var historySearch = ""
    /// The shortcut that reads the maths, as it's written: ⌃⌥=.
    @ObservationIgnored var shortcut: String?
    /// The ways to work out each problem, worked out once each.
    @ObservationIgnored private var methodCache: [String: [Methods.Method]] = [:]
    /// Opens an answer from the history; false if it can't be worked out again.
    @ObservationIgnored var openEntry: ((History.Entry) -> Bool)?
    @ObservationIgnored var angles: AngleUnit
    /// Closes the window, and opens Settings: the window sets these.
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var showSettings: (() -> Void)?
    /// Where the roadmap's canvas is in the window (from the top-left), and the roadmap's size.
    @ObservationIgnored var canvasFrame: CGRect = .zero
    @ObservationIgnored var routeSize: CGSize = .zero
    @ObservationIgnored private var panStart: CGSize?
    @ObservationIgnored private var lastPan = Date.distantPast
    @ObservationIgnored private var bringsOpenStopIntoView = false

    static let zoomRange: ClosedRange<CGFloat> = 0.5...2.5
    /// The space above the roadmap.
    static let routeTop: CGFloat = 30

    /// With no solutions, the window opens on the field for typing a problem.
    init(solutions: [Solution] = [], selected: Int = 0, angles: AngleUnit, prefs: Preferences) {
        self.prefs = prefs
        self.angles = angles
        self.solutions = solutions
        selectedProblem = max(min(selected, solutions.count - 1), 0)
    }

    /// Nothing has been read or typed yet: there's only the field for typing a problem.
    var isEmpty: Bool { solutions.isEmpty }

    /// The problem showing. There has to be one: see `isEmpty`.
    var solution: Solution { solutions[min(max(selectedProblem, 0), solutions.count - 1)] }

    /// Each answer as the lines it's made of: one line, or one per unknown.
    var answerItems: [[MathLine]] {
        let items = solution.answerSets ?? solution.answers.map { [$0] }
        return rounding == .exact ? items : items.map { $0.map(rounding.apply) }
    }

    /// Your own working while trying it yourself, a line at a time.
    var myLines: [String] = [""] {
        didSet {
            // Trying it yourself: reaching the answer shows it.
            if tryFirst, writesOwn, !answerRevealed, Checker.isFinished(myLines, against: solution, angles: angles) { answerRevealed = true }
        }
    }
    /// How much help the line being written has had: its step's name, then its line.
    var hintLevel = 0
    /// Working written on the roadmap while trying it yourself, the stroke being drawn, and
    /// what Undo goes back to.
    var marks: [InkMark] = []
    var drawing: InkMark?
    var inkHistory: [[InkMark]] = []
    /// What Undo took away, for Redo. Writing anything new empties it.
    var inkFuture: [[InkMark]] = []
    var inkTool: InkTool = .pen
    var inkColor: InkColor = .white
    /// The text being typed on the roadmap.
    var editingNote: UUID?
    @ObservationIgnored private var erasedThisDrag = false
    @ObservationIgnored private var lastEraser: CGPoint?

    /// Trying it yourself by writing your own working on the roadmap, which this problem
    /// can check; otherwise the steps are covered and uncovered one at a time.
    var writesOwn: Bool { tryFirst && Checker.canCheck(solution) }

    /// Trying it yourself where the working can't be checked as equations (a diagram,
    /// differentiating): each step asks for what it finds, one after another.
    var fillsIn: Bool { tryFirst && !Checker.canCheck(solution) }
    /// What there is to fill in: each line of each step that ends in what it works out, as
    /// (step, line). What's read off the diagram is given, not found.
    var blanks: [(step: Int, line: Int)] {
        stops.indices.flatMap { index -> [(step: Int, line: Int)] in
            guard stops[index].title != "From the diagram" else { return [] }
            return stops[index].lines.indices.filter { Self.canAsk(for: stops[index].lines[$0]) }.map { (index, $0) }
        }
    }
    /// Whether a line ends in something that can be typed: a rule written in the diagram's
    /// angle names (∠BAD = ∠BCD/2) is shown, not asked for.
    static func canAsk(for line: MathLine) -> Bool {
        guard line.parts.count >= 2, let target = line.parts.last,
              let back = Parser.expression(Format.text(target)) else { return false }
        return matches(back, target, rounded: false)
    }
    /// The blanks filled in right, and those last filled in wrong, by their place in `blanks`.
    var solvedSteps: Set<Int> = []
    var wrongSteps: Set<Int> = []

    /// The blank being filled in now, and the step it's in.
    var currentBlank: Int? { blanks.indices.first { !solvedSteps.contains($0) } }
    var currentFill: Int? { currentBlank.map { blanks[$0].step } }

    /// Return in a blank: right, and the next is asked for; wrong, and it says so.
    func submitFill(_ index: Int) {
        let all = blanks
        guard all.indices.contains(index), myLines.indices.contains(index) else { return }
        let line = stops[all[index].step].lines[all[index].line]
        guard let target = line.parts.last else { return }
        var typed = myLines[index].trimmingCharacters(in: .whitespaces)
        typed = typed.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
        if let unit = line.suffix, unit != "°", typed.hasSuffix(unit) { typed = String(typed.dropLast(unit.count)).trimmingCharacters(in: .whitespaces) }
        guard !typed.isEmpty else { return }
        if let value = Parser.expression(typed), Self.matches(value, target, rounded: line.relation == "≈") {
            solvedSteps.insert(index)
            wrongSteps.remove(index)
            // Going straight to what the next line in the step comes to does that one too.
            var next = index + 1
            while all.indices.contains(next), all[next].step == all[index].step, !solvedSteps.contains(next),
                  let later = stops[all[next].step].lines[all[next].line].parts.last,
                  Self.matches(value, later, rounded: stops[all[next].step].lines[all[next].line].relation == "≈") {
                if myLines.indices.contains(next) { myLines[next] = myLines[index] }
                solvedSteps.insert(next)
                wrongSteps.remove(next)
                next += 1
            }
            hintLevel = 0
            revealed = currentFill ?? stops.count
            if currentBlank == nil { answerRevealed = true }
            focusedLine = currentBlank ?? index
            focusRequests += 1
        } else {
            wrongSteps.insert(index)
        }
    }

    /// A hint for the blank being filled in: its step's rule first, then the answer, written in.
    func fillHint(_ index: Int) {
        let all = blanks
        guard all.indices.contains(index) else { return }
        if hintLevel == 0 {
            hintLevel = 1
        } else if let target = stops[all[index].step].lines[all[index].line].parts.last, myLines.indices.contains(index) {
            myLines[index] = Format.text(target)
            hintLevel = 0
            submitFill(index)
        }
    }

    /// Whether what's typed is what the step found: the same at a few values of its letters,
    /// and near enough for an answer that was rounded.
    static func matches(_ typed: Expr, _ target: Expr, rounded: Bool) -> Bool {
        let letters = typed.symbols.union(target.symbols).sorted()
        for sample in [1.3, -0.7, 2.6] {
            let values = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($0.element, sample + Double($0.offset)) })
            guard let a = typed.evaluate(values), let b = target.evaluate(values), a.isFinite, b.isFinite else { return false }
            let allowed = rounded ? max(0.06, abs(b) * 0.005) : 1e-6 * max(1, abs(b))
            if abs(a - b) > allowed { return false }
        }
        return true
    }

    /// MathPeek's step that comes next after the lines that are right so far.
    func nextStep(after right: Int) -> Step? {
        let usable = stops.filter { !$0.lines.isEmpty }
        guard !usable.isEmpty else { return nil }
        return usable[min(right, usable.count - 1)]
    }

    /// A hint for the line being written: first the next step's name, then its line, written in.
    func hint(at index: Int, right: Int) {
        guard let step = nextStep(after: right) else { return }
        if hintLevel == 0 {
            hintLevel = 1
        } else if let line = step.lines.last, myLines.indices.contains(index) {
            myLines[index] = line.text
            hintLevel = 0
            focusedLine = index
            focusRequests += 1
        }
    }
    /// The line to type in next, and a count that changes each time it's asked for.
    var focusedLine = 0
    var focusRequests = 0

    /// Return in a line: a new one under it.
    func newLine(after index: Int) {
        hintLevel = 0
        myLines.insert("", at: min(index + 1, myLines.count))
        focusedLine = index + 1
        focusRequests += 1
    }

    /// Delete in an empty line: it goes, and the one above takes the keys.
    func removeLine(_ index: Int) {
        guard myLines.count > 1, myLines.indices.contains(index) else { return }
        myLines.remove(at: index)
        focusedLine = max(index - 1, 0)
        focusRequests += 1
    }

    func moveLine(from index: Int, by delta: Int) {
        let next = index + delta
        guard myLines.indices.contains(next) else { return }
        focusedLine = next
        focusRequests += 1
    }

    /// How the answers are rounded, as a question asks for: exactly, or to some places.
    var rounding: Rounding = .exact

    /// Whether rounding would change anything: an answer that isn't a whole number.
    var canRound: Bool {
        (solution.answerSets?.flatMap { $0 } ?? solution.answers).contains { line in
            guard let value = line.parts.last?.evaluate(), value.isFinite else { return false }
            return abs(value - value.rounded()) > 1e-9
        }
    }

    /// The answers in a line, as they're rounded.
    var answerText: String {
        guard rounding != .exact else { return solution.answerText }
        return answerItems.map { $0.map(\.text).joined(separator: ", ") }.joined(separator: " or ")
    }

    /// The steps along the roadmap. Checking an answer isn't one: each answer opens its own check.
    var stops: [Step] {
        solution.steps.filter { $0.title != "Check" }
    }

    func load(_ solutions: [Solution], selected: Int) {
        self.solutions = solutions
        select(problem: min(max(selected, 0), solutions.count - 1))
        // Something new was read: its roadmap starts from the top.
        pan = .zero
    }

    func isAvailable(_ tab: LearnTab) -> Bool {
        tab == .graph ? solution.plot != nil : true
    }

    func select(problem index: Int) {
        guard solutions.indices.contains(index) else { return }
        // Another angle or line of the diagram that's showing: the picture is the same one
        // in the same place, so the roadmap stays where it's been moved to.
        let samePicture = Self.isDiagram(solution) && Self.isDiagram(solutions[index])
        selectedProblem = index
        isEditing = false
        resetRoute()
        if samePicture { keepInView() } else { pan = .zero }
        if !isAvailable(tab) { tab = .route }
    }

    private static func isDiagram(_ solution: Solution) -> Bool {
        if case .diagram = solution.problem.kind { return true }
        return false
    }

    /// The roadmap wasn't moved, but the one now showing may be shorter: once it has its
    /// size, this makes sure some of it is still in view.
    private func keepInView() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            let kept = self.clamped(self.pan)
            guard kept != self.pan else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.pan = kept }
        }
    }

    /// An angle or line clicked in the diagram becomes the thing to find: its own tab with
    /// its working, or the tab it already has.
    func find(_ target: Figure.Target) {
        guard case .diagram(let diagram, _) = solution.problem.kind, let figure = Figure(solution.problem.kind) else { return }
        let wanted = figure.light(for: target, isFound: true)
        func isWanted(_ solution: Solution) -> Bool {
            guard case .diagram(_, let find) = solution.problem.kind,
                  let light = Figure(solution.problem.kind)?.light(for: find, isFound: true) else { return false }
            return figure.same(light, wanted)
        }
        if let index = solutions.firstIndex(where: isWanted) {
            if index != selectedProblem { select(problem: index) }
            return
        }
        if let size = figure.given(target) {
            message = "\(figure.name(of: target)) is given: \(size)"
            return
        }
        // Asked for as the question would ask for it, and worked out again.
        let name = figure.name(of: target)
        var asking = diagram
        switch (asking, target) {
        case (.circle(var circle), .corner(let vertex, let from, let to)):
            circle.asked.append(.init(vertex: vertex, from: from, to: to, name: name))
            asking = .circle(circle)
        case (.circle(var circle), .side(let a, let b)):
            circle.askedLengths.append(.init(a: a, b: b, name: name))
            asking = .circle(circle)
        case (.triangle(var triangle), _):
            triangle.asked.append(name)
            asking = .triangle(triangle)
        }
        guard let found = asking.solutions.first(where: isWanted) else {
            message = "\(name) can't be worked out from what's given."
            return
        }
        solutions.append(found)
        select(problem: solutions.count - 1)
        hoveredFigure = nil
    }

    /// Shows the field for typing a problem: empty, or holding the current one to change.
    func beginEditing(prefilled: Bool) {
        input = prefilled && !isEmpty ? Self.inputText(for: solution) : ""
        message = nil
        changing = nil
        isEditing = !isEmpty
        typingRequests += 1
    }

    /// Back to the problem. With none to go back to, the window closes.
    func cancelEditing() {
        message = nil
        if isEmpty { close?() } else { isEditing = false }
    }

    /// Works out what's in the field. It takes the place of the problem that was showing.
    func workItOut() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let problem = Parser.problem(text) else {
            message = "MathPeek couldn't read that as maths."
            return
        }
        guard let solution = Engine.solve(problem, angles: angles) else {
            message = "MathPeek can't work that one out yet."
            return
        }
        if isEmpty {
            solutions = [solution]
            selectedProblem = 0
        } else {
            solutions[selectedProblem] = solution
        }
        history?.add([solution], selected: 0)
        isEditing = false
        resetRoute()
        pan = .zero
        tab = .route
    }

    /// The ways there are to work out the problem showing: none when there's only one.
    var methods: [Methods.Method] {
        let key = solution.problem.text
        if let known = methodCache[key] { return known }
        let found = Methods.all(for: solution, angles: angles)
        methodCache[key] = found
        return found
    }

    /// Which of `methods` is showing.
    var methodIndex: Int? {
        let titles = solution.steps.map(\.title)
        return methods.firstIndex { $0.solution.steps.map(\.title) == titles }
    }

    func choose(method index: Int) {
        let all = methods
        guard all.indices.contains(index), index != methodIndex else { return }
        solutions[selectedProblem] = all[index].solution
        resetRoute()
    }

    /// Another problem like each one shown, found ahead so the link is only offered when
    /// there is one. Found in the background: it can take a few hundred tries.
    var practiceReady: [String: Solution] = [:]
    @ObservationIgnored private var practiceTried: Set<String> = []

    func preparePractice() async {
        let key = solution.problem.text
        guard !practiceTried.contains(key), Practice.canVary(solution) else { return }
        practiceTried.insert(key)
        let current = solution, angles = angles
        let made = await Task.detached(priority: .utility) { Practice.another(like: current, angles: angles) }.value
        if let made { practiceReady[key] = made }
    }

    /// The same kind of problem with other numbers, to try yourself: the steps and answer
    /// covered until they're asked for.
    func anotherLikeThis() {
        guard let made = practiceReady.removeValue(forKey: solution.problem.text) else { return }
        solutions[selectedProblem] = made
        pan = .zero
        tab = .route
        setTryFirst(true)
    }

    /// The working as a picture, for pasting into notes.
    func copyImage() {
        let renderer = ImageRenderer(content: WorkingSheet(solution: solution, steps: stops))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = "Image"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.copied == "Image" { self?.copied = nil }
        }
    }

    func copy(_ text: String, as label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.replacingOccurrences(of: "−", with: "-"), forType: .string)
        copied = label
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.copied == label { self?.copied = nil }
        }
    }

    private func resetRoute() {
        myLines = [""]
        marks = []
        inkHistory = []
        inkFuture = []
        drawing = nil
        editingNote = nil
        selectedAnswer = 0
        showsCheck = false
        openStop = nil
        picked = nil
        changing = nil
        revealed = 0
        answerRevealed = false
        message = nil
    }

    // MARK: The roadmap

    /// Runs what a click does, unless the click was the end of dragging the roadmap about.
    func tap(_ action: () -> Void) {
        guard Date().timeIntervalSince(lastPan) > 0.25 else { return }
        action()
    }

    /// Opens a step where it is, or closes it.
    func toggle(stop index: Int) {
        guard stops.indices.contains(index), !tryFirst || index < revealed else { return }
        endChanging()
        if openStop == index {
            opening?.cancel()
            stopDuration = 0.42
            openStop = nil
        } else {
            open(stop: index)
        }
        if let line = picked?.line, line.hasPrefix("step.") { picked = nil }
    }

    /// Going down to a step from one that's open above it, the open one closes first and only
    /// then does the line run on, so the dot it runs to stays still: closing a card above it
    /// would otherwise move it up to meet the line.
    private func open(stop index: Int) {
        opening?.cancel()
        if let current = openStop, current < index {
            holdsLine = true
            stopDuration = 0.26
            openStop = nil
            holdsLine = false
            opening = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.24))
                guard !Task.isCancelled, let self else { return }
                self.stopDuration = 0.42
                self.reveal(stop: index)
            }
            return
        }
        stopDuration = 0.42
        reveal(stop: index)
    }

    private func reveal(stop index: Int) {
        openStop = index
        bringsOpenStopIntoView = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            self?.bringsOpenStopIntoView = false
        }
    }

    /// Uncovers the next step, when trying it first.
    func revealNext() {
        guard tryFirst, revealed < stops.count else { return }
        revealed += 1
        open(stop: revealed - 1)
    }

    /// Up and down the steps with the arrow keys.
    func step(by delta: Int) {
        guard !stops.isEmpty else { return }
        let next = (openStop ?? (delta > 0 ? -1 : 0)) + delta
        guard next >= 0 else {
            openStop = nil
            return
        }
        guard next < stops.count else { return }
        if tryFirst, next >= revealed { revealed = next + 1 }
        if let line = picked?.line, line.hasPrefix("step.") { picked = nil }
        open(stop: next)
    }

    /// Moves the roadmap so a step that's just opened is all in view.
    func bringIntoView(_ frame: CGRect) {
        guard bringsOpenStopIntoView, canvasFrame.height > 0 else { return }
        bringsOpenStopIntoView = false
        var shift: CGFloat = 0
        if frame.maxY > canvasFrame.height - 16 { shift = canvasFrame.height - 16 - frame.maxY }
        if frame.minY + shift < 16 { shift = 16 - frame.minY }
        guard abs(shift) > 1 else { return }
        withAnimation(.easeOut(duration: 0.22)) { pan.height += shift }
    }

    func setTryFirst(_ on: Bool) {
        finishNote()
        tryFirst = on
        revealed = 0
        answerRevealed = false
        solvedSteps = []
        wrongSteps = []
        myLines = fillsIn ? Array(repeating: "", count: max(blanks.count, 1)) : [""]
        hintLevel = 0
        focusedLine = fillsIn ? (currentBlank ?? 0) : 0
        if fillsIn {
            revealed = currentFill ?? stops.count
            answerRevealed = on && currentBlank == nil
        }
        focusRequests += 1
        openStop = nil
        showsCheck = false
        picked = nil
        endChanging()
    }

    /// Picks an answer and opens its check; picking it again closes it.
    func select(answer index: Int) {
        if selectedAnswer == index, showsCheck {
            showsCheck = false
        } else {
            selectedAnswer = index
            showsCheck = true
        }
    }

    func pick(_ part: MathPart) {
        endChanging()
        picked = picked == part ? nil : part
    }

    /// Escape, or a click on nothing: puts away the innermost thing that's open.
    func dismiss() {
        opening?.cancel()
        stopDuration = 0.42
        if changing != nil {
            changing = nil
        } else if picked != nil {
            picked = nil
        } else if showsCheck {
            showsCheck = false
        } else {
            openStop = nil
        }
    }

    func hover(_ id: String, _ inside: Bool) {
        if id.hasPrefix("n:") {
            if inside { hoveredNumber = id } else if hoveredNumber == id { hoveredNumber = nil }
        } else {
            if inside { hoveredPart = id } else if hoveredPart == id { hoveredPart = nil }
        }
    }

    /// What clicking a line of maths does: its parts can be picked and, in the problem, its
    /// numbers changed.
    func touch(line: String, changesNumbers: Bool = false) -> MathTouch {
        MathTouch(line: line, accent: Z.blue, picked: picked, hovered: hoveredPart, hoveredNumber: hoveredNumber,
                  pick: { [weak self] part in self?.tap { self?.pick(part) } },
                  hover: { [weak self] id, inside in self?.hover(id, inside) },
                  change: changesNumbers ? { [weak self] number in self?.tap { self?.beginChanging(number) } } : nil,
                  changing: changing,
                  field: changesNumbers ? { [weak self] _, size in
                      guard let self else { return AnyView(EmptyView()) }
                      return AnyView(NumberField(model: self, size: size))
                  } : nil)
    }

    /// What a picked part is.
    func note(for part: MathPart) -> (name: String, detail: String) {
        Explain.note(for: part, in: solution, steps: stops)
    }

    // MARK: Changing a number

    func beginChanging(_ number: MathNumber) {
        picked = nil
        message = nil
        numberText = Format.number(number.shown).replacingOccurrences(of: "−", with: "-")
        changing = number
    }

    func endChanging() {
        guard changing != nil else { return }
        commitNumber()
    }

    /// Puts the typed number into the problem and works it out again.
    func commitNumber() {
        guard let number = changing else { return }
        changing = nil
        let text = numberText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let typed = Parser.expression(text), let value = Simplify.run(typed).number else { return }
        guard value != number.shown else { return }
        apply(value, to: number)
    }

    /// One more or one less, with the field still open.
    func nudgeNumber(by delta: Int) {
        guard var number = changing, let typed = Parser.expression(numberText), let value = Simplify.run(typed).number else { return }
        let next = value + .integer(delta)
        guard apply(next, to: number) else { return }
        number.shown = next
        numberText = Format.number(next).replacingOccurrences(of: "−", with: "-")
        changing = number
    }

    @discardableResult
    private func apply(_ value: Number, to number: MathNumber) -> Bool {
        var problem = solution.problem
        let lines = problem.kind.lines
        guard let lineIndex = Int(number.line.dropFirst("problem.".count)), lines.indices.contains(lineIndex),
              let side = number.path.first, lines[lineIndex].parts.indices.contains(side),
              let changed = lines[lineIndex].parts[side].replacing(at: number.path.dropFirst(), with: .number(number.negated ? value.negated : value))
        else { return false }
        problem.kind = problem.kind.replacing(line: lineIndex, side: side, with: changed)
        problem.text = problem.kind.text
        problem.writtenAnswer = nil
        // How the question in words became this maths no longer holds once a number changes.
        problem.lead = []
        problem.wantsTermNumber = false
        if case .real = value { problem.usesDecimals = true }
        guard let solved = Engine.solve(problem, angles: angles) else {
            message = "MathPeek can't work that one out."
            return false
        }
        solutions[selectedProblem] = solved
        message = nil
        selectedAnswer = 0
        showsCheck = false
        picked = nil
        if let open = openStop, open >= stops.count { openStop = nil }
        if tryFirst {
            revealed = 0
            answerRevealed = false
            openStop = nil
        }
        return true
    }

    // MARK: Moving about

    /// Dragging the roadmap.
    func drag(by translation: CGSize) {
        if panStart == nil { panStart = pan }
        guard let start = panStart else { return }
        pan = clamped(CGSize(width: start.width + translation.width, height: start.height + translation.height))
        lastPan = Date()
    }

    func endDrag() {
        panStart = nil
        lastPan = Date()
    }

    // MARK: Working on the roadmap

    /// Where the roadmap hangs from in the canvas: the middle of its top edge.
    private var routeAnchor: CGPoint { CGPoint(x: canvasFrame.width / 2 + pan.width, y: Self.routeTop + pan.height) }

    /// A point in the canvas as a point on the roadmap, so ink moves and zooms with it.
    func onRoute(_ point: CGPoint) -> CGPoint {
        let anchor = routeAnchor
        return CGPoint(x: (point.x - anchor.x) / zoom, y: (point.y - anchor.y) / zoom)
    }

    /// A point on the roadmap as it is in the canvas now.
    func inCanvas(_ point: CGPoint, width: CGFloat) -> CGPoint {
        CGPoint(x: width / 2 + pan.width + point.x * zoom, y: Self.routeTop + pan.height + point.y * zoom)
    }

    func choose(tool: InkTool) {
        finishNote()
        inkTool = tool
    }

    /// A colour for what's written next, and for the text being typed. Picked while moving
    /// or rubbing out, it's for the pen.
    func choose(color: InkColor) {
        inkColor = color
        if let id = editingNote, let index = marks.firstIndex(where: { $0.id == id }) { marks[index].color = color }
        if inkTool == .move || inkTool == .eraser { inkTool = .pen }
    }

    /// Dragging while trying it yourself does what the tool does; with Move or Text it moves
    /// the roadmap, as scrolling always does.
    func inkDrag(at point: CGPoint, from start: CGPoint) {
        switch inkTool {
        case .move, .text:
            drag(by: CGSize(width: point.x - start.x, height: point.y - start.y))
        case .pen, .highlighter:
            if drawing == nil { drawing = InkMark(points: [onRoute(start)], color: inkColor, wide: inkTool == .highlighter) }
            drawing?.points.append(onRoute(point))
        case .eraser:
            erase(from: lastEraser ?? onRoute(start), to: onRoute(point))
            lastEraser = onRoute(point)
        }
    }

    func endInkDrag() {
        switch inkTool {
        case .move, .text:
            endDrag()
        case .pen, .highlighter:
            if let drawing {
                saveInk()
                marks.append(drawing)
            }
            drawing = nil
        case .eraser:
            erasedThisDrag = false
            lastEraser = nil
        }
    }

    /// Rubs out every mark the eraser passes over, from one point to the next.
    private func erase(from start: CGPoint, to end: CGPoint) {
        let reach = 7 / zoom
        let hit = marks.filter { $0.isTouched(from: start, to: end, within: reach) }.map(\.id)
        guard !hit.isEmpty else { return }
        if !erasedThisDrag {
            saveInk()
            erasedThisDrag = true
        }
        marks.removeAll { hit.contains($0.id) }
    }

    /// A click with Text: on writing, that's changed; elsewhere, new writing starts there.
    /// Another click ends the one being typed. Nil when the click is for something else.
    func inkTap(at point: CGPoint) -> Bool {
        guard tryFirst, inkTool == .text || inkTool == .eraser else { return false }
        let spot = onRoute(point)
        if inkTool == .eraser {
            erase(from: spot, to: spot)
            erasedThisDrag = false
            return true
        }
        if editingNote != nil {
            finishNote()
            return true
        }
        if let note = marks.last(where: { $0.text != nil && $0.isTouched(from: spot, to: spot, within: 2) }) {
            editingNote = note.id
            return true
        }
        saveInk()
        let note = InkMark(points: [CGPoint(x: spot.x, y: spot.y - InkMark.textSize * 0.7)], color: inkColor, text: "")
        marks.append(note)
        editingNote = note.id
        return true
    }

    func setNote(_ id: UUID, text: String) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[index].text = text
    }

    /// Stops typing on the roadmap; writing left empty goes.
    func finishNote() {
        guard let id = editingNote else { return }
        editingNote = nil
        if let index = marks.firstIndex(where: { $0.id == id }),
           marks[index].text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
            marks.remove(at: index)
            // Nothing was added, so there's nothing for Undo to take away.
            if inkHistory.last == marks { inkHistory.removeLast() }
        }
    }

    private func saveInk() {
        inkHistory.append(marks)
        if inkHistory.count > 200 { inkHistory.removeFirst() }
        inkFuture = []
    }

    func undoInk() {
        finishNote()
        guard let last = inkHistory.popLast() else { return }
        inkFuture.append(marks)
        marks = last
    }

    func redoInk() {
        finishNote()
        guard let next = inkFuture.popLast() else { return }
        inkHistory.append(marks)
        marks = next
    }

    /// Keys for writing on the roadmap: ⌘Z (or ⌃Z) undoes, ⇧⌘Z (or ⌃Y) redoes, a letter picks
    /// a tool and 1 to 4 a colour. While a text box has the keys it keeps letters and numbers,
    /// and Undo and Redo too while it has typing to undo or redo. True when the key was used.
    func inkKey(_ key: String, flags: NSEvent.ModifierFlags, typing: Bool, typingCanUndo: Bool, typingCanRedo: Bool) -> Bool {
        guard tryFirst, tab == .route, !showsHistory else { return false }
        let flags = flags.intersection([.command, .shift, .option, .control])
        let undo = (flags == .command || flags == .control) && key == "z"
        let redo = ((flags == [.command, .shift] || flags == [.control, .shift]) && key == "z")
            || (flags == .control && key == "y")
        if undo || redo {
            if typing && (undo ? typingCanUndo : typingCanRedo) { return false }
            if undo { undoInk() } else { redoInk() }
            return true
        }
        guard flags.isEmpty, !typing else { return false }
        if let tool = InkTool.allCases.first(where: { $0.key == key }) {
            choose(tool: tool)
            return true
        }
        if let number = Int(key), InkColor.allCases.indices.contains(number - 1) {
            choose(color: InkColor.allCases[number - 1])
            return true
        }
        return false
    }

    func clearInk() {
        finishNote()
        guard !marks.isEmpty else { return }
        saveInk()
        marks = []
    }

    func scroll(by delta: CGSize) {
        pan = clamped(CGSize(width: pan.width + delta.width, height: pan.height + delta.height))
    }

    /// Zooms, keeping what's at `point` (in the canvas) where it is. Nil is the middle.
    func zoom(by factor: CGFloat, around point: CGPoint? = nil) {
        let target = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let change = target / zoom
        guard abs(change - 1) > 0.0001 else { return }
        let point = point ?? CGPoint(x: canvasFrame.width / 2, y: canvasFrame.height / 2)
        // The roadmap hangs from the middle of the canvas's top edge.
        let anchor = CGPoint(x: canvasFrame.width / 2 + pan.width, y: Self.routeTop + pan.height)
        zoom = target
        routeSize = CGSize(width: routeSize.width * change, height: routeSize.height * change)
        pan = clamped(CGSize(width: pan.width + (1 - change) * (point.x - anchor.x), height: pan.height + (1 - change) * (point.y - anchor.y)))
    }

    func resetView() {
        zoom = 1
        pan = .zero
    }

    /// Keeps some of the roadmap in view, so it can't be lost off the edge.
    private func clamped(_ pan: CGSize) -> CGSize {
        let view = canvasFrame.size
        guard view.width > 0, routeSize.width > 0 else { return pan }
        let keep: CGFloat = 90
        let sideways = (view.width + routeSize.width) / 2 - keep
        let lowest = keep - routeSize.height - Self.routeTop
        let highest = view.height - keep - Self.routeTop
        return CGSize(width: min(max(pan.width, -sideways), sideways),
                      height: min(max(pan.height, min(lowest, 0)), max(highest, 0)))
    }

    // MARK: Words for a problem

    /// The problem written so MathPeek can read it back.
    static func inputText(for solution: Solution) -> String {
        switch solution.problem.kind {
        case .solve(let equations, _) where equations.count > 1:
            return equations.map { Format.text($0.left) + " = " + Format.text($0.right) }.joined(separator: "; ")
        default:
            return solution.problem.text
        }
    }

    /// A problem in a line: "d/dx x² sin x", "∫ x² dx from 0 to 3".
    static func summary(_ solution: Solution) -> String {
        switch solution.problem.kind {
        case .solve(let equations, _) where equations.count > 1:
            return equations.map { Format.text($0.left) + " = " + Format.text($0.right) }.joined(separator: ",  ")
        case .differentiate(let expr, let x, let order):
            return (order == 2 ? "d²/d\(x)² " : "d/d\(x) ") + Format.text(expr)
        case .integrate(let expr, let x, let from, let to):
            let limits = from.flatMap { a in to.map { b in " from \(Format.text(a)) to \(Format.text(b))" } } ?? ""
            return "∫ " + Format.text(expr) + " d\(x)" + limits
        case .expand(let expr):
            return "Expand " + Format.text(expr)
        case .factorise(let expr):
            return "Factorise " + Format.text(expr)
        case .substitute(let expr, let values):
            return Format.text(expr) + ", " + values.sorted { $0.key < $1.key }.map { "\($0.key) = \(Format.text($0.value))" }.joined(separator: ", ")
        case .remainder(let expr, let modulus):
            return Format.text(expr) + " mod \(modulus)"
        default:
            return solution.question.text
        }
    }

    /// What a problem's tab is called: an angle's name, or the problem in a line.
    static func tabTitle(_ solution: Solution) -> String {
        if case .diagram(_, let find) = solution.problem.kind { return find }
        return summary(solution)
    }

    /// What the problem asks for, in a few words, when the maths alone doesn't say.
    static func subtitle(_ solution: Solution) -> String? {
        switch solution.problem.kind {
        case .evaluate: nil
        case .solve: Insight.anatomy(of: solution.problem).kind
        default: solution.task
        }
    }
}

/// Rounding an answer as exam questions ask: to some decimal places or significant figures.
enum Rounding: String, CaseIterable, Identifiable {
    case exact = "Exact"
    case one = "1 dp"
    case two = "2 dp"
    case three = "3 sf"

    var id: Self { self }

    var words: String {
        switch self {
        case .exact: "exactly"
        case .one: "to 1 decimal place"
        case .two: "to 2 decimal places"
        case .three: "to 3 significant figures"
        }
    }

    func round(_ value: Double) -> Double {
        switch self {
        case .exact: return value
        case .one: return (value * 10).rounded() / 10
        case .two: return (value * 100).rounded() / 100
        case .three:
            guard value != 0 else { return 0 }
            let scale = pow(10, 2 - floor(log10(abs(value))))
            return (value * scale).rounded() / scale
        }
    }

    /// An answer line with its value rounded, ≈ where that changed it.
    func apply(_ line: MathLine) -> MathLine {
        guard self != .exact, let last = line.parts.last, let value = last.evaluate(), value.isFinite,
              abs(value - value.rounded()) > 1e-9 else { return line }
        let shown = round(value)
        var parts = Array(line.parts.dropLast())
        // 1.5 to 3 sf is 1.50: the places asked for are written.
        let text: String = switch self {
        case .one: String(format: "%.1f", shown)
        case .two: String(format: "%.2f", shown)
        default: Format.decimal(shown)
        }
        parts.append(.symbol(text.replacingOccurrences(of: "-", with: "−")))
        return MathLine(parts: parts, relation: abs(shown - value) < 1e-12 ? line.relation : "≈", suffix: line.suffix)
    }
}

/// The working window: dark and semi-transparent, so what's behind shows through, with tabs
/// along the top: the roadmap from the problem to its answers, and a graph.
@MainActor
final class LearnWindow {
    private let prefs: Preferences
    private var window: NSWindow?
    private var model: LearnModel?
    private var monitor: Any?
    private var keys: Any?
    /// Clicks in other apps, watched only while the window is open.
    private var clicksElsewhere: Any?
    /// Opens behind the other windows, without becoming the active app: for looking at the
    /// demo without taking over the screen.
    var opensBehind = false
    /// Opens Settings: ⌘, in the window.
    var showSettings: (() -> Void)?

    private let history: History

    init(prefs: Preferences, history: History) {
        self.prefs = prefs
        self.history = history
    }

    /// Opens the window on the history of answers.
    func showHistory() {
        open()
        model?.showsHistory = true
    }

    /// Opens an answer from the history.
    func open(_ entry: History.Entry) -> Bool {
        guard let solutions = history.solutions(for: entry, angles: prefs.angles) else { return false }
        show(solutions, selected: 0, angles: prefs.angles)
        return true
    }

    func show(_ solution: Solution, angles: AngleUnit, tab: LearnTab = .route) {
        show([solution], selected: 0, angles: angles, tab: tab)
    }

    func show(_ solutions: [Solution], selected: Int, angles: AngleUnit, tab: LearnTab = .route) {
        guard !solutions.isEmpty else { return }
        // Its working is kept with its place in the history, for opening it again.
        if !History.isDemo { history.add(solutions, selected: selected) }
        if let model, let window {
            model.angles = angles
            model.showsHistory = false
            model.load(solutions, selected: selected)
            model.tab = model.isAvailable(tab) ? tab : .route
            bringForward(window)
            return
        }
        let model = LearnModel(solutions: solutions, selected: selected, angles: angles, prefs: prefs)
        model.tab = model.isAvailable(tab) ? tab : .route
        makeWindow(for: model)
    }

    /// Opens the window with nothing to work out: as it was left, or, the first time, on the
    /// field for typing a problem.
    func open() {
        if let window {
            bringForward(window)
        } else {
            makeWindow(for: LearnModel(angles: prefs.angles, prefs: prefs))
        }
    }

    private func makeWindow(for model: LearnModel) {
        model.history = history
        model.shortcut = prefs.hotkey?.display
        model.openEntry = { [weak self] entry in self?.open(entry) ?? false }
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let frame = CGRect(x: 0, y: 0, width: 1080, height: 760)
        // For a README clip, a window that can go on the stage off the screen (see DemoStage).
        let window = DemoStage.isFilming ? DemoWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
            : NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.title = "MathPeek"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = CGSize(width: 880, height: 600)
        // Semi-transparent: what's behind the window shows through, blurred, under a dark tint
        // that the view draws (Settings sets how strong).
        window.isOpaque = false
        window.backgroundColor = .clear
        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        let hosting = NSHostingView(rootView: WorkingView(model: model))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        backdrop.addSubview(hosting)
        window.contentView = backdrop
        hosting.frame = backdrop.bounds
        window.addTitlebarAccessoryViewController(Self.settingsButton(for: model))
        model.titlebarHeight = max(window.frame.height - window.contentLayoutRect.height, 28)
        model.close = { [weak window] in window?.close() }
        model.showSettings = { [weak self] in self?.showSettings?() }
        window.center()
        if !DemoStage.isFilming { window.setFrameAutosaveName("MathPeekWindow") }
        self.window = window
        self.model = model
        watchScrolling(in: window)
        watchKeys(in: window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopWatchingClicksElsewhere() }
        }
        bringForward(window)
    }

    /// The gear at the right of the title bar, which opens Settings. It's part of the title
    /// bar: a view that's only drawn under a see-through title bar doesn't get the clicks.
    static func settingsButton(for model: LearnModel) -> NSTitlebarAccessoryViewController {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        let hosting = NSHostingView(rootView: TitleButtons(model: model))
        hosting.frame.size = hosting.fittingSize
        accessory.view = hosting
        return accessory
    }

    /// Shows the field for typing a problem, opening the window if it isn't open.
    func beginTyping(prefilled: Bool = false) {
        open()
        model?.beginEditing(prefilled: prefilled)
    }

    /// Sets the roadmap up a certain way: for README clips.
    func showDemo(stop: Int? = nil, answer: Int? = nil, part: Int? = nil, tryFirst: Int? = nil, zoom: CGFloat? = nil) {
        guard let model else { return }
        if let tryFirst {
            model.setTryFirst(true)
            model.revealed = tryFirst
        } else if model.tryFirst {
            model.setTryFirst(false)
        }
        if let stop { model.openStop = stop }
        if let answer {
            model.selectedAnswer = answer
            model.showsCheck = model.tab == .route
        }
        if let part {
            let parts = Insight.anatomy(of: model.solution.problem).parts
            let lines = model.solution.problem.kind.lines
            if parts.indices.contains(part), let line = lines.first {
                for (side, expr) in line.parts.enumerated() {
                    if let path = expr.path(to: parts[part].expr) {
                        model.picked = MathPart(line: "problem.0", path: [side] + path, expr: parts[part].expr)
                        break
                    }
                }
            }
        }
        if let zoom { model.zoom = zoom }
    }

    /// The window and what it shows, for a README clip to act on.
    var demo: (window: NSWindow, model: LearnModel)? {
        guard let window, let model else { return nil }
        return (window, model)
    }

    /// Opens a step, or closes the one open, as a click would: for filming the roadmap.
    func openStop(_ index: Int?) {
        guard let model else { return }
        if let index { model.toggle(stop: index) } else if let open = model.openStop { model.toggle(stop: open) }
    }

    /// Two fingers move the roadmap, and a pinch (or ⌘ and scrolling) zooms it. SwiftUI doesn't
    /// hand these on, so they're taken from the window's events.
    private func watchScrolling(in window: NSWindow) {
        let number = window.windowNumber
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard event.windowNumber == number else { return event }
            let location = event.locationInWindow
            let isPinch = event.type == .magnify
            let magnification = isPinch ? event.magnification : 0
            let delta = isPinch ? .zero : CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
            let isPrecise = isPinch || event.hasPreciseScrollingDeltas
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let model = self.model, let content = self.window?.contentView,
                      model.tab == .route, !model.isEmpty else { return false }
                let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
                guard model.canvasFrame.contains(point) else { return false }
                let inCanvas = CGPoint(x: point.x - model.canvasFrame.minX, y: point.y - model.canvasFrame.minY)
                if isPinch {
                    model.zoom(by: 1 + magnification, around: inCanvas)
                } else if command {
                    model.zoom(by: exp(delta.height * (isPrecise ? 0.01 : 0.08)), around: inCanvas)
                } else {
                    let scale: CGFloat = isPrecise ? 1 : 10
                    model.scroll(by: CGSize(width: delta.width * scale, height: delta.height * scale))
                }
                return true
            }
            return handled ? nil : event
        }
    }

    /// Undo, Redo and the tool keys for writing on the roadmap. Taken from the window's events
    /// so ⌃Z works as well as ⌘Z, and so a text box keeps ⌘Z while it has typing to undo.
    private func watchKeys(in window: NSWindow) {
        let number = window.windowNumber
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.windowNumber == number, let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            let flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let model = self.model else { return false }
                let editor = self.window?.firstResponder as? NSTextView
                let undoer = editor?.undoManager
                // In a text box ⌃Z does what ⌘Z does there.
                if let undoer, flags.intersection([.command, .shift, .option, .control]) == .control,
                   key == "z", undoer.canUndo {
                    undoer.undo()
                    return true
                }
                return model.inkKey(key, flags: flags, typing: editor != nil,
                                    typingCanUndo: undoer?.canUndo ?? false, typingCanRedo: undoer?.canRedo ?? false)
            }
            return handled ? nil : event
        }
    }

    private func bringForward(_ window: NSWindow) {
        if DemoStage.isFilming {
            DemoStage.show(window)
            return
        }
        if opensBehind {
            window.orderBack(nil)
            return
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        // Plain `activate()` is only a request, which macOS turns down when the window is opened
        // from the bubble: that never makes MathPeek the active app.
        NSApp.activate(ignoringOtherApps: true)
        watchClicksElsewhere()
    }

    /// While the window is open, a click on another app's window gets it out of that window's
    /// way, which macOS doesn't always see to: MathPeek's window can be in front without
    /// MathPeek being the active app, and it floats over an app that's in full screen.
    private func watchClicksElsewhere() {
        guard clicksElsewhere == nil else { return }
        clicksElsewhere = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.makeWay(forClickAt: NSEvent.mouseLocation) }
        }
    }

    private func stopWatchingClicksElsewhere() {
        if let clicksElsewhere { NSEvent.removeMonitor(clicksElsewhere) }
        clicksElsewhere = nil
    }

    /// Puts the window behind the window that was clicked, as happens to any window. Nothing
    /// can go behind the window of an app in full screen: this window stays over it whatever
    /// is asked. Then it's taken off the screen instead, and opening it again (from an answer,
    /// or by opening MathPeek) brings it back as it was.
    private func makeWay(forClickAt point: CGPoint) {
        guard let window, window.isVisible else { return }
        let clicked = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard window.isInFront(ofWindow: clicked) else { return }
        window.order(.below, relativeTo: clicked)
        // A moment for the windows to be put in their new order, by this or by the other app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isVisible, window.isInFront(ofWindow: clicked) else { return }
                window.orderOut(nil)
                self.stopWatchingClicksElsewhere()
            }
        }
    }
}

extension NSWindow {
    /// Whether this window is in front of another app's window. Only an ordinary window
    /// counts: not the desktop, the Dock or a menu.
    func isInFront(ofWindow other: Int) -> Bool {
        guard other > 0, other != windowNumber else { return false }
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Front to back.
        let numbers = onScreen.map { $0[kCGWindowNumber as String] as? Int ?? 0 }
        guard let mine = numbers.firstIndex(of: windowNumber), let theirs = numbers.firstIndex(of: other), mine < theirs else { return false }
        return onScreen[theirs][kCGWindowLayer as String] as? Int == 0
            && onScreen[theirs][kCGWindowOwnerPID as String] as? Int32 != ProcessInfo.processInfo.processIdentifier
    }
}

extension Expr {
    /// Where `target` is in this, if it's there.
    func path(to target: Expr) -> [Int]? {
        if self == target { return [] }
        let children: [Expr]
        switch self {
        case .add(let parts), .multiply(let parts): children = parts
        case .power(let base, let exponent): children = [base, exponent]
        case .function(_, let argument): children = [argument]
        default: return nil
        }
        for (index, child) in children.enumerated() {
            if let rest = child.path(to: target) { return [index] + rest }
        }
        return nil
    }
}

// MARK: - Look

enum Z {
    static let blue = Color(red: 0.04, green: 0.62, blue: 1.0)
    static let blueHover = Color(red: 0.24, green: 0.71, blue: 1.0)
    static let yellow = Color(red: 0.97, green: 0.73, blue: 0.27)
    static let green = Color(red: 0.37, green: 0.85, blue: 0.57)
    static let red = Color(red: 1.0, green: 0.46, blue: 0.43)
    static let text = Color.white.opacity(0.95)
    static let body = Color.white.opacity(0.84)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.4)
    static let hairline = Color.white.opacity(0.08)
    static let tint = Color(red: 0.07, green: 0.075, blue: 0.105)
    /// Maths is set in a serif, numbers and signs as well as letters, as it's printed in a
    /// maths book; the words around it stay in the system font.
    static let maths: Font.Design = .serif
}

extension LearnModel {
    /// Blue that's see-through like the window behind it, so what's behind shows through it,
    /// blurred, as it does through the window: the more the window lets through (Settings
    /// sets how much), the more this does. Everything in the window's blue is drawn in it:
    /// names, buttons, outlines and the roadmap's line.
    var softBlue: Color { Z.blue.opacity(blueStrength) }

    /// The same, under the pointer.
    var softBlueHover: Color { Z.blueHover.opacity(blueStrength) }

    private var blueStrength: Double { 0.85 - 0.3 * prefs.windowTranslucency }

    /// The wash of blue over a frosted button (see `BlueGlass`): solid when the window is,
    /// and thinner the more the window lets through, so the blur shows through the button
    /// as it does through the window.
    var glassBlue: Color { Z.blue.opacity(1 - 0.7 * prefs.windowTranslucency) }

    /// The same, under the pointer.
    var glassBlueHover: Color { Z.blueHover.opacity(1 - 0.7 * prefs.windowTranslucency) }

    /// The window's own dark, under a pale wash of blue on frosted glass. Thinner than the
    /// window's, so a frosted box shows more of what's behind than the window round it, and
    /// solid when the window is.
    var glassShade: Color {
        let through = prefs.windowTranslucency
        return Z.tint.opacity((1 - through) * (1 - through))
    }
}

extension View {
    /// Tells the model what the pointer is over.
    func hoverID(_ id: String, in model: LearnModel) -> some View {
        onHover { inside in
            if inside { model.hovered = id } else if model.hovered == id { model.hovered = nil }
        }
        .demoPlace(id)
    }
}

struct WorkingView: View {
    @Bindable var model: LearnModel

    var body: some View {
        VStack(spacing: 0) {
            TitleStrip(model: model)
            if model.showsHistory, let history = model.history {
                HistoryView(model: model, history: history)
            } else if model.isEmpty {
                // Nothing to show yet: only the field, a little above the middle. Until the
                // first answer, the shortcut over it, since that's how MathPeek is mostly used.
                VStack(spacing: 34) {
                    if let shortcut = model.shortcut, model.history?.entries.isEmpty ?? true {
                        FirstUse(shortcut: shortcut)
                    }
                    EditHeader(model: model)
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabStrip(model: model)
                if model.isEditing {
                    EditHeader(model: model)
                        .padding(.horizontal, 44)
                        .padding(.top, 16)
                }
                switch model.tab {
                case .route:
                    RouteCanvas(model: model)
                case .graph:
                    ScrollView {
                        VStack(spacing: 30) {
                            if !model.isEditing { Heading(model: model) }
                            GraphTab(model: model)
                        }
                        .padding(.horizontal, 44)
                        .padding(.top, 26)
                        .padding(.bottom, 30)
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                    }
                }
                FooterBar(model: model)
            }
        }
        .foregroundStyle(Z.text)
        .background { Keys(model: model) }
        .background(Z.tint.opacity(1 - model.prefs.windowTranslucency))
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { Toast(label: model.copied).padding(.bottom, 78) }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.18), value: model.tab)
        .animation(.easeOut(duration: 0.18), value: model.selectedProblem)
        .animation(.easeOut(duration: 0.18), value: model.isEditing)
        .animation(.easeOut(duration: 0.18), value: model.isEmpty)
        // One smooth curve for a step opening: the cards move, the card grows and the blue
        // runs down the line together, and settle without a bounce.
        .animation(.smooth(duration: model.stopDuration), value: model.openStop)
        .animation(.smooth(duration: 0.42), value: model.lineStop)
        .animation(.easeOut(duration: 0.2), value: model.revealed)
        .animation(.easeOut(duration: 0.2), value: model.answerRevealed)
        .animation(.easeOut(duration: 0.2), value: model.tryFirst)
        .animation(.easeOut(duration: 0.16), value: model.showsCheck)
        .animation(.easeOut(duration: 0.14), value: model.selectedAnswer)
        .animation(.easeOut(duration: 0.14), value: model.picked)
        .animation(.spring(duration: 0.3), value: model.copied)
    }
}

/// Keys that work anywhere on the roadmap: the arrows step through it, Escape puts things
/// away, and ⌘+, ⌘− and ⌘0 zoom. ⌘, opens Settings from anywhere in the window.
private struct Keys: View {
    @Bindable var model: LearnModel

    var body: some View {
        ZStack {
            Button("") { model.showSettings?() }.keyboardShortcut(",", modifiers: .command)
            Button("") { model.showsHistory.toggle() }.keyboardShortcut("y", modifiers: .command)
            if model.showsHistory {
                Button("") { model.showsHistory = false }.keyboardShortcut(.cancelAction)
            }
            if model.tab == .route, !model.isEditing, !model.isEmpty, !model.showsHistory, !model.writesOwn, !model.fillsIn {
                Button("") { model.step(by: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { model.step(by: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { model.dismiss() }.keyboardShortcut(.cancelAction)
                Button("") { model.zoom(by: 1.2) }.keyboardShortcut("=", modifiers: .command)
                Button("") { model.zoom(by: 1.2) }.keyboardShortcut("+", modifiers: .command)
                Button("") { model.zoom(by: 1 / 1.2) }.keyboardShortcut("-", modifiers: .command)
                Button("") { model.resetView() }.keyboardShortcut("0", modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: Top

/// The shortcut, shown the first time the window opens: its keys, and what it does.
private struct FirstUse: View {
    let shortcut: String

    /// Each modifier on its own key, then the key itself.
    private var keys: [String] {
        let modifiers = Set("⌃⌥⇧⌘")
        var result: [String] = []
        var rest = ""
        for character in shortcut {
            if modifiers.contains(character), rest.isEmpty { result.append(String(character)) } else { rest.append(character) }
        }
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Z.text)
                        .frame(minWidth: 46, minHeight: 46)
                        .padding(.horizontal, key.count > 1 ? 10 : 0)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
                }
            }
            Text("Press it over maths anywhere on screen to see the answer by the pointer.")
                .font(.system(size: 14))
                .foregroundStyle(Z.secondary)
        }
    }
}

/// The window's title, between the window buttons.
private struct TitleStrip: View {
    @Bindable var model: LearnModel

    var body: some View {
        Text("MathPeek")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Z.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: model.titlebarHeight)
            .background(Color.black.opacity(0.22))
    }
}

/// The gear in the title bar: opens Settings.
private struct TitleButtons: View {
    @Bindable var model: LearnModel

    var body: some View {
        HStack(spacing: 0) {
            button("clock.arrow.circlepath", id: "history", help: "History", lit: model.showsHistory) {
                withAnimation(.easeOut(duration: 0.18)) { model.showsHistory.toggle() }
            }
            button("gearshape", id: "settings", help: "Settings", lit: false) { model.showSettings?() }
        }
        .padding(.trailing, 6)
    }

    private func button(_ symbol: String, id: String, help: String, lit: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(lit ? model.softBlue : (model.hovered == id ? Z.text : Z.secondary))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverID(id, in: model)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The tabs, with the one showing named in blue. One problem has its roadmap and its
/// graph; several (each angle of a diagram, each sum in an area) have a tab apiece, and the
/// graph of the one showing after them. ⌘1 to ⌘9 switch between them.
private struct TabStrip: View {
    @Bindable var model: LearnModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs
            ScrollView(.horizontal, showsIndicators: false) { tabs }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) { Rectangle().fill(Z.hairline).frame(height: 1) }
        .background(Color.black.opacity(0.22))
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            if model.solutions.count > 1 {
                ForEach(Array(model.solutions.enumerated()), id: \.offset) { index, solution in
                    TabButton(model: model, id: "tab.problem.\(index)", title: LearnModel.tabTitle(solution),
                              selected: model.tab == .route && index == model.selectedProblem,
                              shortcut: index < 9 ? KeyEquivalent(Character("\(index + 1)")) : nil) {
                        model.select(problem: index)
                        model.tab = .route
                    }
                }
                if model.isAvailable(.graph) {
                    TabButton(model: model, id: "tab.graph", title: LearnTab.graph.rawValue, selected: model.tab == .graph, shortcut: nil) {
                        model.tab = .graph
                    }
                }
            } else {
                ForEach(LearnTab.allCases) { tab in
                    TabButton(model: model, id: "tab." + tab.rawValue, title: tab.rawValue, selected: model.tab == tab,
                              shortcut: tab.shortcut, available: model.isAvailable(tab), width: 136) {
                        model.tab = tab
                    }
                }
            }
        }
    }
}

private struct TabButton: View {
    @Bindable var model: LearnModel
    let id: String
    let title: String
    let selected: Bool
    let shortcut: KeyEquivalent?
    var available = true
    /// Wide enough for its title, unless it's given a width.
    var width: CGFloat?
    let action: () -> Void

    /// The tab showing has its name in the window's see-through blue.
    private var selectedColor: Color { model.softBlue }

    var body: some View {
        let hovered = model.hovered == id
        let button = Button(action: action) {
            MathText(text: title, size: 13, weight: selected ? .semibold : .medium)
                .foregroundStyle(selected ? selectedColor : (hovered ? Z.text : Z.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, width == nil ? 22 : 0)
                .frame(minWidth: width ?? 96, maxWidth: width ?? 230, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 38)
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
        .hoverID(id, in: model)
        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            button
        }
    }
}

/// The problem, large and centred, over the graph.
private struct Heading: View {
    @Bindable var model: LearnModel

    var body: some View {
        let solution = model.solution
        let lines = solution.problem.kind.lines
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                problem(lines)
                ScrollView(.horizontal, showsIndicators: false) { problem(lines) }
            }
            if let subtitle = LearnModel.subtitle(solution) {
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Z.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func problem(_ lines: [MathLine]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MathLineView(line: line, size: lines.count > 1 ? 24 : 28, design: Z.maths, weight: .semibold)
            }
        }
    }
}

/// A field for typing a problem, in place of the heading. Before there's any problem it's all
/// the window shows, and there's nothing to cancel back to.
private struct EditHeader: View {
    @Bindable var model: LearnModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProblemInput(model: model, text: model.input, request: model.typingRequests)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(model.softBlue, lineWidth: 1.5))
                    .frame(maxWidth: 460)
                ZButton(model: model, id: "edit.go", title: "Solve", kind: .primary, width: 96) { model.workItOut() }
                if !model.isEmpty {
                    ZButton(model: model, id: "edit.cancel", title: "Cancel", width: 96) { model.cancelEditing() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            if let message = model.message {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Z.red)
            } else if model.isEmpty {
                // Room for the message, so the field stays where it is when one shows.
                Text(" ").font(.system(size: 12.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// The text of the field a problem is typed in. It takes the keys as soon as it shows, so a
/// problem can be typed straight away: Return works it out and Escape leaves.
private struct ProblemInput: NSViewRepresentable {
    let model: LearnModel
    let text: String
    /// Changes when the field is asked for again while it's already showing.
    let request: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model, request: request) }

    func makeNSView(context: Context) -> NSTextField {
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let field = ProblemTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = font
        field.placeholderAttributedString = NSAttributedString(string: "Type a problem", attributes: [
            .font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.3),
        ])
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.request != request {
            context.coordinator.request = request
            (field as? ProblemTextField)?.takeKeys()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LearnModel
        var request: Int

        init(model: LearnModel, request: Int) {
            self.model = model
            self.request = request
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.input = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                model.workItOut()
            case #selector(NSResponder.cancelOperation(_:)):
                model.cancelEditing()
            default:
                return false
            }
            return true
        }
    }
}

/// MathPeek has no Edit menu, which is where a text field gets ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z from, so
/// this one sees to them itself.
final class ProblemTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.takeKeys() }
    }

    /// Typing goes here, after what's already in it: a problem being changed isn't selected,
    /// so the first key doesn't wipe it.
    func takeKeys() {
        guard let window, window.makeFirstResponder(self) else { return }
        currentEditor()?.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let editor = currentEditor(), window?.firstResponder === editor,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch (event.modifierFlags.intersection([.command, .shift, .option, .control]), key) {
        case (.command, "v"): editor.paste(nil)
        case (.command, "c"): editor.copy(nil)
        case (.command, "x"): editor.cut(nil)
        case (.command, "a"): editor.selectAll(nil)
        case (.command, "z"): editor.undoManager?.undo()
        case ([.command, .shift], "z"): editor.undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

// MARK: Pieces

/// A rounded pill. The selected one is outlined.
struct Pill<Content: View>: View {
    @Bindable var model: LearnModel
    let id: String
    var selected = false
    /// Filled with blue; plain grey otherwise.
    var tinted = false
    var vertical: CGFloat = 9
    var horizontal: CGFloat = 13
    var radius: CGFloat = 6
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        let lit = selected || model.hovered == id
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background {
                if tinted {
                    BlueGlass(radius: radius, wash: Z.blue.opacity(lit ? 0.36 : 0.25), shade: model.glassShade)
                } else {
                    Color.white.opacity(lit ? 0.11 : 0.06)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? model.softBlue : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture { model.tap(action) }
            .hoverID(id, in: model)
    }
}

/// Frosted blue, for what's filled with the window's blue: what's behind the window,
/// blurred the way the window's own background blurs it, under a wash of blue.
struct BlueGlass: View {
    let radius: CGFloat
    /// The blue over the blur.
    let wash: Color
    /// The window's dark between the two, for a wash too pale to stand on the blur alone.
    var shade: Color = .clear

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            Frost(radius: radius)
            shape.fill(shade)
            shape.fill(wash)
        }
        // Clicks are for whatever it's behind.
        .allowsHitTesting(false)
    }
}

/// The blur itself: the same material as the window's background, cut to a rounded shape.
/// It shows what's behind the window, not what's under it in the window.
private struct Frost: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: radius)
        context.coordinator.radius = radius
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // The corners grow with the roadmap's zoom.
        guard context.coordinator.radius != radius else { return }
        context.coordinator.radius = radius
        view.maskImage = Self.mask(radius: radius)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var radius: CGFloat = 0
    }

    /// A rounded square that stretches from its middle, with the same corners the rest of
    /// the window draws.
    private static func mask(radius: CGFloat) -> NSImage {
        let inset = ceil(radius * 2)
        let edge = inset * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }
}

/// A darker panel floating over the window, for the details of what's selected.
struct Panel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }
}

/// A frosted blue button for the main thing to do, or a grey one for the rest.
struct ZButton: View {
    enum Kind { case primary, secondary }

    @Bindable var model: LearnModel
    let id: String
    let title: String
    var kind: Kind = .secondary
    var width: CGFloat?
    let action: () -> Void

    var body: some View {
        let hovered = model.hovered == id
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(minWidth: width, maxWidth: width ?? .infinity)
                .frame(height: 34)
                .background {
                    if kind == .primary {
                        BlueGlass(radius: 6, wash: hovered ? model.glassBlueHover : model.glassBlue)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(hovered ? 0.15 : 0.09))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverID(id, in: model)
    }
}

/// Blue text that does something.
struct LinkButton: View {
    @Bindable var model: LearnModel
    let id: String
    let title: String
    let action: () -> Void

    var body: some View {
        let hovered = model.hovered == id
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovered ? model.softBlueHover : model.softBlue)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverID(id, in: model)
    }
}

private struct Toast: View {
    let label: String?

    var body: some View {
        if let label {
            Text("\(label) copied")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.1).opacity(0.96)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: Graph

private struct GraphTab: View {
    @Bindable var model: LearnModel

    var body: some View {
        if let plot = model.solution.plot {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    GraphView(plot: plot, selected: model.selectedAnswer, blue: model.softBlue)
                        .frame(height: 300)
                }
                if plot.marks.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(Array(plot.marks.enumerated()), id: \.offset) { index, mark in
                            Pill(model: model, id: "mark.\(index)", selected: index == model.selectedAnswer, tinted: true,
                                 vertical: 7, action: { model.selectedAnswer = index }) {
                                Text("\(plot.variable) = \(Format.decimal(mark))")
                                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A graph of the functions in a solution, with its answers marked and one picked out.
struct GraphView: View {
    let plot: Plot
    var selected: Int = 0

    /// An answer as its label shows it: to four decimal places at most, which is all a graph
    /// can tell apart.
    static func shown(_ value: Double) -> String {
        Format.decimal((value * 10_000).rounded() / 10_000)
    }

    static func isRounded(_ value: Double) -> Bool {
        abs((value * 10_000).rounded() / 10_000 - value) > 1e-9
    }
    /// The first curve's blue: the window's see-through blue.
    var blue = Z.blue

    private struct Point: Identifiable {
        let id: Int
        let series: String
        let label: String
        let x: Double
        let y: Double
    }

    var body: some View {
        let (points, yRange) = samples()
        let labels = plot.functions.map(\.label)
        let colors = Array([blue, Z.yellow, Color.white.opacity(0.6)].prefix(labels.count))
        Chart {
            RuleMark(y: .value("zero", 0)).foregroundStyle(Color.white.opacity(0.32)).lineStyle(StrokeStyle(lineWidth: 1))
            RuleMark(x: .value("zero", 0)).foregroundStyle(Color.white.opacity(0.32)).lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(points) { point in
                LineMark(x: .value(plot.variable, point.x), y: .value("y", point.y), series: .value("Series", point.series))
                    .foregroundStyle(by: .value("Function", point.label))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(Array(plot.marks.enumerated()), id: \.offset) { index, mark in
                if let y = plot.functions.first?.expr.evaluate([plot.variable: mark]), yRange.contains(y) {
                    PointMark(x: .value(plot.variable, mark), y: .value("y", y))
                        .symbolSize(index == selected ? 150 : 60)
                        .foregroundStyle(index == selected ? Z.yellow : Color.white.opacity(0.85))
                        // Its full width, kept inside the graph: a label near the edge would
                        // otherwise be cut short to "x =…".
                        .annotation(position: .top, spacing: 8,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if index == selected {
                                Text("\(plot.variable) \(Self.isRounded(mark) ? "≈" : "=") \(Self.shown(mark))")
                                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color.black)
                                    .fixedSize()
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Z.yellow))
                            }
                        }
                }
            }
        }
        .chartForegroundStyleScale(domain: labels, range: colors)
        .chartYScale(domain: yRange)
        .chartXScale(domain: plot.range)
        .chartLegend(plot.functions.count > 1 ? .visible : .hidden)
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                AxisValueLabel().font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Z.secondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                AxisValueLabel().font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Z.secondary)
            }
        }
    }

    /// Points along each function, split where it jumps (at an asymptote), and a y range that
    /// leaves out the extremes.
    private func samples() -> ([Point], ClosedRange<Double>) {
        var raw: [(label: String, x: Double, y: Double?)] = []
        let count = 400
        let step = (plot.range.upperBound - plot.range.lowerBound) / Double(count)
        for function in plot.functions {
            for i in 0...count {
                let x = plot.range.lowerBound + Double(i) * step
                raw.append((function.label, x, function.expr.evaluate([plot.variable: x])))
            }
        }
        let ys = raw.compactMap(\.y).sorted()
        guard !ys.isEmpty else { return ([], -10...10) }
        var low = ys[Int(Double(ys.count - 1) * 0.05)], high = ys[Int(Double(ys.count - 1) * 0.95)]
        low = min(low, 0); high = max(high, 0)
        let pad = max((high - low) * 0.15, 1)
        let range = (low - pad)...(high + pad)
        var points: [Point] = []
        var segment = 0
        var previous: (String, Double)?
        for (index, sample) in raw.enumerated() {
            guard let y = sample.y, range.contains(y) else { segment += 1; previous = nil; continue }
            if let (label, lastY) = previous, label == sample.label, abs(y - lastY) > (range.upperBound - range.lowerBound) * 0.5 {
                segment += 1
            }
            points.append(Point(id: index, series: "\(sample.label)#\(segment)", label: sample.label, x: sample.x, y: y))
            previous = (sample.label, y)
        }
        return (points, range)
    }
}

// MARK: Footer

/// Along the bottom: change the problem or try it first on the left, copy on the right.
private struct FooterBar: View {
    @Bindable var model: LearnModel

    var body: some View {
        let solution = model.solution
        let empty = solution.answers.isEmpty
        HStack(spacing: 10) {
            // A diagram was read from a picture: there's nothing to retype.
            let canEdit: Bool = switch solution.problem.kind {
            case .diagram, .worded: false
            default: true
            }
            if canEdit {
                LinkButton(model: model, id: "footer.edit", title: "Edit Problem") {
                    model.beginEditing(prefilled: true)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
            if model.tab == .route, !model.stops.isEmpty {
                LinkButton(model: model, id: "footer.try", title: model.tryFirst ? "Show Everything" : "Try It Yourself") {
                    model.setTryFirst(!model.tryFirst)
                }
                .keyboardShortcut("t", modifiers: .command)
                .padding(.leading, canEdit ? 14 : 0)
            }
            Spacer()
            ZButton(model: model, id: "footer.latex", title: "Copy LaTeX", width: 120) {
                model.copy(solution.answerLatex, as: "LaTeX")
            }
            .keyboardShortcut("c", modifiers: [.command, .control])
            .disabled(empty)
            .opacity(empty ? 0.4 : 1)
            ZButton(model: model, id: "footer.image", title: "Copy Image", width: 120) {
                model.copyImage()
            }
            ZButton(model: model, id: "footer.working", title: "Copy Working", width: 120) {
                model.copy(solution.workingText, as: "Working")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            ZButton(model: model, id: "footer.answer", title: "Copy Answer", kind: .primary, width: 140) {
                model.copy(model.answerText, as: "Answer")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(empty)
            .opacity(empty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) { Rectangle().fill(Z.hairline).frame(height: 1) }
    }
}

/// Lays its children out left to right, wrapping onto new lines, each line centred if asked.
struct FlowRow: SwiftUI.Layout {
    var spacing: CGFloat = 6
    var centered = false

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
            rows[rows.count - 1] = row
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let rows = rows(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(rows.map(\.width).max() ?? 0, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX + (centered ? max((bounds.width - row.width) / 2, 0) : 0)
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }
}
