import Foundation
import Observation

/// Every answer MathPeek has given, newest first: what was asked and what came out, kept in a
/// file on this Mac and nowhere else. A problem that can be read again from its words can be
/// opened again; one read from a picture (a diagram) can be while MathPeek stays open.
@Observable @MainActor
final class History {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var date: Date
        /// The problem in a line: "12 × (3 + 4.5)", "x² − 5x + 6 = 0".
        var question: String
        var answer: String
        /// What to read again to work it out again, if it can be.
        var input: String?
        /// Kept at the top, and never dropped to make room.
        var pinned: Bool?
        /// What kind of maths it is: "Quadratic equations", "Fractions".
        var topic: String?

        var isPinned: Bool { pinned == true }
    }

    private(set) var entries: [Entry] = []
    /// The working of entries made this time MathPeek has been open, by entry.
    @ObservationIgnored private var working: [UUID: [Solution]] = [:]
    @ObservationIgnored private let prefs: Preferences

    static let limit = 500

    init(prefs: Preferences) {
        self.prefs = prefs
        load()
    }

    /// Adds an answer at the top. The same question asked again moves up, with its new answer.
    func add(question: String, answer: String, input: String?, solutions: [Solution]? = nil) {
        guard prefs.keepsHistory, !question.isEmpty, !answer.isEmpty else { return }
        let question = Self.tidy(question)
        var entry = Entry(date: Date(), question: question, answer: answer, input: input)
        // Its topic from the working, or from working it out again from its words.
        let worked = solutions?.first ?? input.flatMap { Parser.problem($0) }.flatMap { Engine.solve($0, angles: prefs.angles) }
        entry.topic = worked.flatMap(Self.topic)
        if let index = entries.prefix(20).firstIndex(where: { $0.question == question }) {
            let old = entries.remove(at: index)
            entry.id = old.id
            entry.input = input ?? old.input
            entry.pinned = old.pinned
            entry.topic = entry.topic ?? old.topic
        }
        entries.insert(entry, at: 0)
        // The oldest go to make room, unless they're pinned.
        while entries.count > Self.limit, let last = entries.lastIndex(where: { !$0.isPinned }) { entries.remove(at: last) }
        if let solutions { working[entry.id] = solutions }
        save()
    }

    /// Records a worked problem: its question, its answer, and its working for this time open.
    func add(_ solutions: [Solution], selected: Int) {
        guard solutions.indices.contains(selected) else { return }
        let solution = solutions[selected]
        let answer = solution.answers.isEmpty ? (solution.note ?? "") : solution.answerText
        let input: String? = switch solution.problem.kind {
        case .diagram, .worded: nil
        default: LearnModel.inputText(for: solution)
        }
        add(question: Self.question(for: solution), answer: answer, input: input, solutions: solutions)
    }

    /// The working for an entry: as it was, if it was worked out this time MathPeek has been
    /// open, or worked out again from its words.
    func solutions(for entry: Entry, angles: AngleUnit) -> [Solution]? {
        if let kept = working[entry.id] { return kept }
        guard let input = entry.input, let problem = Parser.problem(input), let solution = Engine.solve(problem, angles: angles) else { return nil }
        return [solution]
    }

    func canOpen(_ entry: Entry) -> Bool {
        working[entry.id] != nil || entry.input != nil
    }

    func togglePin(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned = entries[index].isPinned ? nil : true
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        working[entry.id] = nil
        save()
    }

    /// Everything, or only what's pinned when `keepingPinned`.
    func clear(keepingPinned: Bool = false) {
        entries = keepingPinned ? entries.filter(\.isPinned) : []
        working = working.filter { id, _ in entries.contains { $0.id == id } }
        save()
    }

    /// What kind of maths a problem is, as a topic to find it by.
    static func topic(for solution: Solution) -> String? {
        switch solution.problem.kind {
        case .diagram(.circle, _): return "Circle theorems"
        case .diagram(.triangle, _): return "Triangles"
        case .evaluate(let expr):
            let hasFraction = solution.question.text.contains("/") || Format.text(expr).contains("/")
            return hasFraction ? "Fractions" : (solution.question.text.contains("%") ? "Percentages" : "Arithmetic")
        case .simplify: return "Simplifying"
        case .expand: return "Expanding brackets"
        case .factorise: return "Factorising"
        case .differentiate: return "Differentiation"
        case .integrate: return "Integration"
        case .substitute: return "Substitution"
        case .remainder: return "Remainders"
        case .sequence: return "Sequences"
        case .worded: return "Word problems"
        case .solve(let equations, _):
            if equations.count > 1 { return "Simultaneous equations" }
            // "Quadratic equation in x" is filed under quadratic equations.
            guard let kind = LearnModel.subtitle(solution) else { return "Equations" }
            let name = kind.components(separatedBy: " in ").first ?? kind
            return name.hasSuffix("equation") ? name + "s" : name
        }
    }

    /// A problem in a line, as the bubble shows it.
    static func question(for solution: Solution) -> String {
        switch solution.problem.kind {
        case .evaluate, .simplify, .diagram: solution.question.text
        default: LearnModel.summary(solution)
        }
    }

    /// The question as words to read again, if they can be: a diagram's angle can't.
    static func readable(_ question: String) -> String? {
        let text = tidy(question)
        return Parser.problem(text) == nil ? nil : text
    }

    /// Without the "=" the bubble puts after a sum to work out.
    static func tidy(_ question: String) -> String {
        var text = question.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("=") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        return text
    }

    // MARK: The file

    private var file: URL? {
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let name = Bundle.main.bundleIdentifier ?? "MathPeek"
        return folder.appendingPathComponent(name, isDirectory: true).appendingPathComponent("History.json")
    }

    private func load() {
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = saved
        // Answers kept before topics were: their topic worked out from their words.
        var filled = false
        for index in entries.indices where entries[index].topic == nil {
            guard let input = entries[index].input, let problem = Parser.problem(input),
                  let solution = Engine.solve(problem, angles: prefs.angles), let topic = Self.topic(for: solution) else { continue }
            entries[index].topic = topic
            filled = true
        }
        if filled { save() }
    }

    /// Whether this is a README clip (`-demo <scene>`, as `AppShell.demoScene` reads it), which
    /// never changes the history.
    static var isDemo: Bool { UserDefaults.standard.string(forKey: "demo") != nil }

    private func save() {
        guard !Self.isDemo, let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            // Losing the history is better than failing to show an answer.
        }
    }
}
