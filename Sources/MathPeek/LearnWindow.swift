import AppKit
import Charts
import Observation
import SwiftUI

/// The tabs at the top of the working window.
enum LearnTab: String, CaseIterable, Identifiable {
    case answer = "Answer"
    case steps = "Steps"
    case graph = "Graph"
    case breakdown = "Breakdown"

    var id: Self { self }

    var shortcut: KeyEquivalent {
        switch self {
        case .answer: "1"
        case .steps: "2"
        case .graph: "3"
        case .breakdown: "4"
        }
    }
}

/// What the working window shows: the problems read (or typed), the one selected, and what's
/// picked in it.
@Observable @MainActor
final class LearnModel {
    var solutions: [Solution]
    var selectedProblem: Int
    var tab: LearnTab = .answer
    /// Whether the problem is being typed or changed.
    var isEditing = false
    var input = ""
    var message: String?
    var copied: String?
    /// Which answer is picked, when there are several.
    var selectedAnswer = 0
    var selectedStep = 0
    /// Which part of the problem the breakdown is showing.
    var selectedPart = 0
    /// What the pointer is over, for hover highlights.
    var hovered: String?
    var titlebarHeight: CGFloat = 28
    @ObservationIgnored let prefs: Preferences
    @ObservationIgnored var angles: AngleUnit

    init(solutions: [Solution], selected: Int, angles: AngleUnit, prefs: Preferences) {
        self.prefs = prefs
        self.angles = angles
        self.solutions = solutions
        selectedProblem = min(max(selected, 0), solutions.count - 1)
    }

    var solution: Solution { solutions[min(max(selectedProblem, 0), solutions.count - 1)] }

    /// Each answer as the lines it's made of: one line, or one per unknown.
    var answerItems: [[MathLine]] {
        solution.answerSets ?? solution.answers.map { [$0] }
    }

    func load(_ solutions: [Solution], selected: Int) {
        self.solutions = solutions
        select(problem: min(max(selected, 0), solutions.count - 1))
    }

    func isAvailable(_ tab: LearnTab) -> Bool {
        switch tab {
        case .steps: !solution.steps.isEmpty
        case .graph: solution.plot != nil
        default: true
        }
    }

    func select(problem index: Int) {
        guard solutions.indices.contains(index) else { return }
        selectedProblem = index
        isEditing = false
        resetSelections()
        if !isAvailable(tab) { tab = .answer }
    }

    /// Shows the field for typing a problem: empty, or holding the current one to change.
    func beginEditing(prefilled: Bool) {
        input = prefilled ? Self.inputText(for: solution) : ""
        message = nil
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
        message = nil
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
        solutions[selectedProblem] = solution
        isEditing = false
        resetSelections()
        tab = .answer
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

    private func resetSelections() {
        selectedAnswer = 0
        selectedStep = 0
        selectedPart = 0
        message = nil
    }

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
        default:
            return solution.question.text
        }
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

/// The working window: dark and semi-transparent, so what's behind shows through, with tabs
/// along the top: the answer, the steps, a graph, and the problem taken apart.
@MainActor
final class LearnWindow {
    private let prefs: Preferences
    private var window: NSWindow?
    private var model: LearnModel?

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    func show(_ solution: Solution, angles: AngleUnit, tab: LearnTab = .answer) {
        show([solution], selected: 0, angles: angles, tab: tab)
    }

    func show(_ solutions: [Solution], selected: Int, angles: AngleUnit, tab: LearnTab = .answer) {
        guard !solutions.isEmpty else { return }
        if let model, let window {
            model.angles = angles
            model.load(solutions, selected: selected)
            model.tab = model.isAvailable(tab) ? tab : .answer
            bringForward(window)
            return
        }
        let model = LearnModel(solutions: solutions, selected: selected, angles: angles, prefs: prefs)
        model.tab = model.isAvailable(tab) ? tab : .answer
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1080, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
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
        model.titlebarHeight = max(window.frame.height - window.contentLayoutRect.height, 28)
        window.center()
        window.setFrameAutosaveName("MathPeekWindow")
        self.window = window
        self.model = model
        bringForward(window)
    }

    /// Shows the field for typing a problem.
    func beginTyping(prefilled: Bool = false) {
        model?.beginEditing(prefilled: prefilled)
    }

    /// Picks an answer, step or part: for README clips.
    func showDemo(answer: Int = 0, step: Int = 0, part: Int = 0) {
        model?.selectedAnswer = answer
        model?.selectedStep = step
        model?.selectedPart = part
    }

    private func bringForward(_ window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - Look

private enum Z {
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
    /// Maths is set in the system font, like the rest of the window.
    static let maths: Font.Design = .default
}

private extension View {
    /// Tells the model what the pointer is over.
    func hoverID(_ id: String, in model: LearnModel) -> some View {
        onHover { inside in
            if inside { model.hovered = id } else if model.hovered == id { model.hovered = nil }
        }
    }
}

struct WorkingView: View {
    @Bindable var model: LearnModel

    var body: some View {
        VStack(spacing: 0) {
            TitleStrip(model: model)
            TabStrip(model: model)
            ScrollView {
                VStack(spacing: 30) {
                    if model.solutions.count > 1 { ProblemPills(model: model) }
                    if model.isEditing { EditHeader(model: model) } else { Heading(model: model) }
                    Group {
                        switch model.tab {
                        case .answer: AnswerTab(model: model)
                        case .steps: StepsTab(model: model)
                        case .graph: GraphTab(model: model)
                        case .breakdown: BreakdownTab(model: model)
                        }
                    }
                    .transition(.opacity)
                }
                .padding(.horizontal, 44)
                .padding(.top, 26)
                .padding(.bottom, 30)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            FooterBar(model: model)
        }
        .foregroundStyle(Z.text)
        .background(Z.tint.opacity(1 - model.prefs.windowTranslucency))
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { Toast(label: model.copied).padding(.bottom, 78) }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.18), value: model.tab)
        .animation(.easeOut(duration: 0.18), value: model.selectedProblem)
        .animation(.easeOut(duration: 0.18), value: model.isEditing)
        .animation(.easeOut(duration: 0.14), value: model.selectedStep)
        .animation(.easeOut(duration: 0.14), value: model.selectedAnswer)
        .animation(.easeOut(duration: 0.14), value: model.selectedPart)
        .animation(.spring(duration: 0.3), value: model.copied)
    }
}

// MARK: Top

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

/// The tabs, with a blue line under the one showing. ⌘1 to ⌘4 switch between them.
private struct TabStrip: View {
    @Bindable var model: LearnModel
    private static let width: CGFloat = 136

    var body: some View {
        let tabs = LearnTab.allCases
        let index = tabs.firstIndex(of: model.tab) ?? 0
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabButton(model: model, tab: tab)
                        .frame(width: Self.width, height: 38)
                }
            }
            Rectangle()
                .fill(Z.blue)
                .frame(width: Self.width, height: 2)
                .offset(x: CGFloat(index) * Self.width)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) { Rectangle().fill(Z.hairline).frame(height: 1) }
        .background(Color.black.opacity(0.22))
    }
}

private struct TabButton: View {
    @Bindable var model: LearnModel
    let tab: LearnTab

    var body: some View {
        let selected = model.tab == tab
        let available = model.isAvailable(tab)
        let hovered = model.hovered == "tab." + tab.rawValue
        Button {
            model.tab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : (hovered ? Z.text : Z.secondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.shortcut, modifiers: .command)
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
        .hoverID("tab." + tab.rawValue, in: model)
    }
}

/// The problems read from the screen, when there's more than one.
private struct ProblemPills: View {
    @Bindable var model: LearnModel

    var body: some View {
        FlowRow(spacing: 8, centered: true) {
            ForEach(Array(model.solutions.enumerated()), id: \.offset) { index, solution in
                Pill(model: model, id: "problem.\(index)", selected: index == model.selectedProblem,
                     vertical: 7, action: { model.select(problem: index) }) {
                    Text(LearnModel.summary(solution))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(index == model.selectedProblem ? Z.text : Z.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 250)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The problem, large and centred.
private struct Heading: View {
    @Bindable var model: LearnModel

    var body: some View {
        let solution = model.solution
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                problem(solution)
                ScrollView(.horizontal, showsIndicators: false) { problem(solution) }
            }
            if let subtitle = LearnModel.subtitle(solution) {
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Z.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func problem(_ solution: Solution) -> some View {
        if case .solve(let equations, _) = solution.problem.kind, equations.count > 1 {
            VStack(spacing: 8) {
                ForEach(Array(equations.enumerated()), id: \.offset) { _, equation in
                    MathLineView(line: MathLine(equation.left, equation.right), size: 24, design: Z.maths, weight: .semibold)
                }
            }
        } else {
            MathLineView(line: solution.question, size: 28, design: Z.maths, weight: .semibold)
        }
    }
}

/// A field for typing a problem, in place of the heading.
private struct EditHeader: View {
    @Bindable var model: LearnModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Type a problem", text: $model.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .monospaced))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Z.blue, lineWidth: 1.5))
                    .frame(maxWidth: 460)
                    .onSubmit { model.workItOut() }
                ZButton(model: model, id: "edit.go", title: "Solve", kind: .primary, width: 96) { model.workItOut() }
                ZButton(model: model, id: "edit.cancel", title: "Cancel", width: 96) { model.cancelEditing() }
                    .keyboardShortcut(.cancelAction)
            }
            if let message = model.message {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Z.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: Pieces

/// A rounded pill. The selected one is outlined.
private struct Pill<Content: View>: View {
    @Bindable var model: LearnModel
    let id: String
    var selected = false
    /// Filled with blue; plain grey otherwise.
    var tinted = false
    var vertical: CGFloat = 9
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        let lit = selected || model.hovered == id
        Button(action: action) {
            content
                .padding(.horizontal, 13)
                .padding(.vertical, vertical)
                .background(tinted ? Z.blue.opacity(lit ? 0.26 : 0.17) : Color.white.opacity(lit ? 0.11 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Z.blue : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverID(id, in: model)
    }
}

/// A darker panel floating over the window, for the details of what's selected.
private struct Panel<Content: View>: View {
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

/// A solid blue button for the main thing to do, or a grey one for the rest.
private struct ZButton: View {
    enum Kind { case primary, secondary }

    @Bindable var model: LearnModel
    let id: String
    let title: String
    var kind: Kind = .secondary
    var width: CGFloat?
    let action: () -> Void

    var body: some View {
        let hovered = model.hovered == id
        let fill: Color = kind == .primary ? (hovered ? Z.blueHover : Z.blue) : Color.white.opacity(hovered ? 0.15 : 0.09)
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(minWidth: width, maxWidth: width ?? .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverID(id, in: model)
    }
}

/// Blue text that does something.
private struct LinkButton: View {
    @Bindable var model: LearnModel
    let id: String
    let title: String
    let action: () -> Void

    var body: some View {
        let hovered = model.hovered == id
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovered ? Z.blueHover : Z.blue)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverID(id, in: model)
    }
}

/// A quiet line of text: a count, a decimal value, a note.
private struct Quiet: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Z.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

// MARK: Answer

private struct AnswerTab: View {
    @Bindable var model: LearnModel

    var body: some View {
        let solution = model.solution
        let items = model.answerItems
        let checks = Insight.checks(solution)
        if checks.isEmpty {
            // Nothing to check it against: the answer on its own, in the middle.
            VStack(spacing: 14) {
                answers(solution, items, centered: true)
                details(solution, items, alignment: .center)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    if items.count > 1 { Quiet("\(items.count) solutions") }
                    answers(solution, items, centered: false)
                    details(solution, items, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if checks.indices.contains(model.selectedAnswer) {
                    CheckPanel(check: checks[model.selectedAnswer], named: items.count > 1)
                        .frame(width: 300)
                }
            }
        }
    }

    @ViewBuilder private func answers(_ solution: Solution, _ items: [[MathLine]], centered: Bool) -> some View {
        if items.isEmpty {
            Text(solution.note ?? "No answer")
                .font(.system(size: 15))
                .foregroundStyle(Z.body)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else if items.count == 1 {
            Pill(model: model, id: "answer.0", tinted: true, vertical: 16,
                 action: { model.copy(solution.answerText, as: "Answer") }) {
                HStack(spacing: 26) {
                    ForEach(Array(items[0].enumerated()), id: \.offset) { _, line in
                        MathLineView(line: line, size: line.text.count > 26 ? 22 : 30, design: Z.maths, weight: .semibold)
                    }
                }
                .padding(.horizontal, 6)
            }
        } else {
            FlowRow(spacing: 8, centered: centered) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, lines in
                    Pill(model: model, id: "answer.\(index)", selected: index == model.selectedAnswer, tinted: true,
                         vertical: 11, action: { model.selectedAnswer = index }) {
                        HStack(spacing: 18) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                MathLineView(line: line, size: 19, design: Z.maths, weight: .medium)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The decimal value, and anything worth knowing about the answer.
    @ViewBuilder private func details(_ solution: Solution, _ items: [[MathLine]], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            if let approximation = solution.approximation { Quiet(approximation) }
            if let note = solution.note, !items.isEmpty { Quiet(note) }
        }
    }
}

/// The answer put back into the question.
private struct CheckPanel: View {
    let check: AnswerCheck
    /// Whether to say which answer it is, because there are several.
    let named: Bool

    var body: some View {
        // "0 = 0" says nothing: only the lines that show something.
        let shown = check.lines.filter { $0.parts.count != 2 || Format.text($0.parts[0]) != Format.text($0.parts[1]) }
        let lines = shown.isEmpty ? check.lines : shown
        Panel {
            Text(named ? "Check \(check.answer)" : "Check")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Z.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 10) {
                            MathLineView(line: line, size: 15, design: Z.maths)
                            if index == lines.count - 1 {
                                Image(systemName: check.holds ? "checkmark" : "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(check.holds ? Z.green : Z.red)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Steps

private struct StepsTab: View {
    @Bindable var model: LearnModel

    var body: some View {
        let steps = model.solution.steps
        let index = min(max(model.selectedStep, 0), max(steps.count - 1, 0))
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { number, step in
                    Pill(model: model, id: "step.\(number)", selected: number == index, vertical: 10,
                         action: { model.selectedStep = number }) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(number + 1)")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Z.tertiary)
                                .frame(width: 16, alignment: .leading)
                            Text(step.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(number == index ? Z.text : Z.body)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(width: 290)
            if steps.indices.contains(index) {
                StepPanel(model: model, step: steps[index], index: index, count: steps.count)
            }
        }
    }
}

/// One step: what was done, the maths, why it works and what to watch out for.
private struct StepPanel: View {
    @Bindable var model: LearnModel
    let step: Step
    let index: Int
    let count: Int

    var body: some View {
        let why = Insight.why(step)
        let watch = Insight.watchOut(step)
        Panel(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 19, weight: .semibold))
                if !step.explanation.isEmpty {
                    Text(step.explanation)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Z.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !step.lines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                            MathLineView(line: line, size: step.lines.count > 3 ? 17 : 21, design: Z.maths)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if why != nil || watch != nil {
                Rectangle().fill(Z.hairline).frame(height: 1)
                if let why { note("Why it works", why) }
                if let watch { note("Watch out", watch) }
            }
            HStack(spacing: 10) {
                ZButton(model: model, id: "step.previous", title: "Previous") { model.selectedStep = max(index - 1, 0) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.4 : 1)
                ZButton(model: model, id: "step.next", title: "Next", kind: .primary) { model.selectedStep = min(index + 1, count - 1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(index == count - 1)
                    .opacity(index == count - 1 ? 0.4 : 1)
            }
            .padding(.top, 2)
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Z.secondary)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Z.body)
                .fixedSize(horizontal: false, vertical: true)
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
                    GraphView(plot: plot, selected: model.selectedAnswer)
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
        let colors = Array([Z.blue, Z.yellow, Color.white.opacity(0.6)].prefix(labels.count))
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
                        .annotation(position: .top, spacing: 8) {
                            if index == selected {
                                Text("\(plot.variable) = \(Format.decimal(mark))")
                                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color.black)
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

// MARK: Breakdown

/// The problem taken apart: each part, which can be clicked to see what it is.
private struct BreakdownTab: View {
    @Bindable var model: LearnModel

    var body: some View {
        let parts = Insight.anatomy(of: model.solution.problem).parts
        HStack(alignment: .top, spacing: 24) {
            FlowRow(spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Pill(model: model, id: "part.\(index)", selected: index == model.selectedPart, tinted: true,
                         vertical: 11, action: { model.selectedPart = index }) {
                        MathView(expr: part.expr, size: 19, design: Z.maths, weight: .medium)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if parts.indices.contains(model.selectedPart) {
                let part = parts[model.selectedPart]
                Panel(spacing: 6) {
                    Text(part.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(part.detail)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Z.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 300)
            }
        }
    }
}

// MARK: Footer

/// Along the bottom: change the problem on the left, copy on the right.
private struct FooterBar: View {
    @Bindable var model: LearnModel

    var body: some View {
        let solution = model.solution
        let empty = solution.answers.isEmpty
        HStack(spacing: 10) {
            LinkButton(model: model, id: "footer.edit", title: "Edit Problem") {
                model.beginEditing(prefilled: true)
            }
            .keyboardShortcut("e", modifiers: .command)
            Spacer()
            ZButton(model: model, id: "footer.latex", title: "Copy LaTeX", width: 130) {
                model.copy(solution.answerLatex, as: "LaTeX")
            }
            .keyboardShortcut("c", modifiers: [.command, .control])
            .disabled(empty)
            .opacity(empty ? 0.4 : 1)
            ZButton(model: model, id: "footer.working", title: "Copy Working", width: 130) {
                model.copy(solution.workingText, as: "Working")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            ZButton(model: model, id: "footer.answer", title: "Copy Answer", kind: .primary, width: 160) {
                model.copy(solution.answerText, as: "Answer")
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
private struct FlowRow: SwiftUI.Layout {
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
