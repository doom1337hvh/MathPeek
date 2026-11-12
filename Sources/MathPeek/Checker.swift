import Foundation

/// Checks working typed in a line at a time against the question, the way a teacher would
/// read it down the page: each line still right, or where it went wrong and how, and whether
/// it got to the answer. Any route that's right is right: a line is checked against what the
/// question means, not against MathPeek's own steps.
enum Checker {
    enum Status: Equatable {
        case empty
        /// Not readable as maths.
        case unread
        /// Still true.
        case holds
        /// An answer to the question.
        case answer
        case wrong
    }

    struct Result: Equatable {
        var status: Status
        var note: String?
    }

    /// Whether working for this kind of problem can be checked.
    static func canCheck(_ solution: Solution) -> Bool {
        switch solution.problem.kind {
        case .solve: return !answerValues(solution).isEmpty
        case .evaluate, .simplify, .expand, .factorise: return expression(of: solution) != nil
        default: return false
        }
    }

    /// Whether the working has got to every answer, with nothing wrong on the way.
    static func isFinished(_ lines: [String], against solution: Solution, angles: AngleUnit) -> Bool {
        let (results, verdict) = check(lines, against: solution, angles: angles)
        return !results.contains { $0.status == .wrong } && (verdict?.hasPrefix("Right: that's") ?? false)
    }

    /// Each line's result, and what the working comes to as a whole, if it says anything yet.
    static func check(_ lines: [String], against solution: Solution, angles: AngleUnit) -> (results: [Result], verdict: String?) {
        var results: [Result] = []
        var foundAnswers: Set<String> = []
        for text in lines {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { results.append(Result(status: .empty)); continue }
            let result: Result
            if case .solve = solution.problem.kind {
                result = equationLine(trimmed, solution, angles: angles, found: &foundAnswers)
            } else {
                result = expressionLine(trimmed, solution)
            }
            results.append(result)
        }
        // The first line that's wrong is where it went wrong.
        if let first = results.firstIndex(where: { $0.status == .wrong }) {
            let before = results[..<first].lastIndex { $0.status == .holds || $0.status == .answer }
            let place = before == nil ? "in line \(first + 1)" : "between line \(before! + 1) and line \(first + 1)"
            return (results, "Something went wrong \(place).")
        }
        guard let last = results.lastIndex(where: { $0.status != .empty }), results[last].status == .answer else { return (results, nil) }
        // How many of the answers have been reached.
        let wanted = answerValues(solution)
        if case .solve = solution.problem.kind, wanted.count > 1 {
            let missing = wanted.count - foundAnswers.count
            return (results, missing <= 0 ? "Right: that's every answer." : "Right so far. There's \(missing == 1 ? "another answer" : "\(missing) more answers") to find.")
        }
        return (results, "Right: that's the answer.")
    }

    // MARK: Equations

    /// The answers, as values of the unknowns: x = 2 or x = 3 is [[x: 2], [x: 3]].
    private static func answerValues(_ solution: Solution) -> [[String: Double]] {
        let sets = solution.answerSets ?? solution.answers.map { [$0] }
        return sets.compactMap { lines in
            var values: [String: Double] = [:]
            for line in lines {
                guard line.parts.count == 2, case .symbol(let name) = line.parts[0], let value = line.parts[1].evaluate(), value.isFinite else { return nil }
                values[name] = value
            }
            return values.isEmpty ? nil : values
        }
    }

    private static func holds(_ equation: Equation, at values: [String: Double]) -> Bool? {
        guard equation.left.symbols.union(equation.right.symbols).isSubset(of: Set(values.keys)),
              let left = equation.left.evaluate(values), let right = equation.right.evaluate(values) else { return nil }
        return abs(left - right) <= 1e-6 * max(1, abs(left), abs(right))
    }

    private static func equationLine(_ text: String, _ solution: Solution, angles: AngleUnit, found: inout Set<String>) -> Result {
        guard let problem = Parser.problem(text), case .solve(let equations, _) = problem.kind, !equations.isEmpty else {
            return Result(status: .unread, note: "MathPeek can't read this as an equation.")
        }
        let wanted = answerValues(solution)
        // A line that names an answer: x = 6.
        if equations.count == 1, case .symbol(let name) = equations[0].left, let value = equations[0].right.evaluate() {
            if let match = wanted.first(where: { $0[name].map { abs($0 - value) < 1e-6 } ?? false }) {
                found.insert(match.keys.sorted().map { "\($0)=\(match[$0]!)" }.joined(separator: ","))
                return Result(status: .answer)
            }
            let right = wanted.compactMap { $0[name] }.map { Format.decimal(($0 * 1e6).rounded() / 1e6) }
            return Result(status: .wrong, note: right.isEmpty ? "The question doesn't find \(name)."
                                                              : "The question gives \(name) = \(right.joined(separator: " or ")), not \(Format.decimal(value)).")
        }
        // Otherwise it has to stay true at the answers. A line from one of two cases (x − 2 = 0
        // when the answers are 2 and 3) needs to be true at one of them only.
        let truths = wanted.map { values in equations.map { holds($0, at: values) } }
        let allTrue = truths.contains { $0.allSatisfy { $0 == true } }
        if allTrue {
            // And it mustn't let in answers the question doesn't have.
            if equations.count == 1, let own = Engine.solve(problem, angles: angles) {
                let extra = own.answers.compactMap { line -> String? in
                    guard line.parts.count == 2, case .symbol(let name) = line.parts[0], let value = line.parts[1].evaluate() else { return nil }
                    return wanted.contains { $0[name].map { abs($0 - value) < 1e-6 } ?? true } ? nil : "\(name) = \(Format.decimal((value * 1e6).rounded() / 1e6))"
                }
                if !extra.isEmpty {
                    return Result(status: .wrong, note: "This also gives \(extra.joined(separator: " and ")), which the question doesn't.")
                }
            }
            return Result(status: .holds)
        }
        if truths.contains(where: { $0.contains(nil) }) {
            return Result(status: .unread, note: "This line has a letter the question doesn't.")
        }
        // What it gives instead, if it can be worked out.
        if equations.count == 1, let own = Engine.solve(problem, angles: angles), !own.answers.isEmpty {
            return Result(status: .wrong, note: "This gives \(own.answerText), but the question gives \(solution.answerText).")
        }
        return Result(status: .wrong, note: "This isn't true for the answer, \(solution.answerText).")
    }

    // MARK: Expressions

    private static func expression(of solution: Solution) -> Expr? {
        let lines = solution.problem.kind.lines
        guard lines.count == 1, let first = lines[0].parts.first else { return nil }
        return first
    }

    /// Whether two expressions are equal, tried at a few values of their letters.
    private static func equal(_ a: Expr, _ b: Expr) -> (Bool, sample: [String: Double], Double?, Double?) {
        let letters = a.symbols.union(b.symbols).sorted()
        var last: ([String: Double], Double?, Double?) = ([:], nil, nil)
        for sample in [2.0, -1.5, 3.25] {
            let values = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($0.element, sample + Double($0.offset)) })
            let x = a.evaluate(values), y = b.evaluate(values)
            last = (values, x, y)
            guard let x, let y, x.isFinite, y.isFinite else { return (false, values, x, y) }
            if abs(x - y) > 1e-7 * max(1, abs(x), abs(y)) { return (false, values, x, y) }
        }
        return (true, last.0, last.1, last.2)
    }

    private static func expressionLine(_ text: String, _ solution: Solution) -> Result {
        // "= 90" is read as 90.
        var text = text
        while text.hasPrefix("=") { text.removeFirst(); text = text.trimmingCharacters(in: .whitespaces) }
        guard let question = expression(of: solution), let line = Parser.expression(text) else {
            return Result(status: .unread, note: "MathPeek can't read this line.")
        }
        let (same, values, mine, theirs) = equal(line, question)
        if same {
            let isAnswer = Format.text(line) == solution.answerText
                || (line.symbols.isEmpty && Parser.expression(text).map { if case .number = $0 { true } else { false } } == true)
            return Result(status: isAnswer ? .answer : .holds)
        }
        guard let mine, let theirs else { return Result(status: .wrong, note: "This isn't equal to the question.") }
        let shown = { (value: Double) in Format.decimal((value * 1e6).rounded() / 1e6) }
        if values.isEmpty {
            return Result(status: .wrong, note: "This comes to \(shown(mine)), but the question comes to \(shown(theirs)).")
        }
        let at = values.keys.sorted().map { "\($0) = \(shown(values[$0]!))" }.joined(separator: ", ")
        return Result(status: .wrong, note: "Not equal to the question: with \(at) this comes to \(shown(mine)), the question to \(shown(theirs)).")
    }
}
