import Foundation

/// One line of maths: expressions joined by a relation, like "h/6 = 3h/18" or "x ≈ 1.414".
struct MathLine: Sendable, Hashable {
    var parts: [Expr]
    var relation: String = "="
    /// Words after the maths: "(mod 13)".
    var suffix: String?

    init(_ parts: Expr..., relation: String = "=", suffix: String? = nil) {
        self.parts = parts
        self.relation = relation
        self.suffix = suffix
    }

    init(parts: [Expr], relation: String = "=", suffix: String? = nil) {
        self.parts = parts
        self.relation = relation
        self.suffix = suffix
    }

    var text: String {
        // A degree sign goes straight after the number.
        parts.map(Format.text).joined(separator: " \(relation) ") + (suffix.map { $0 == "°" ? $0 : " " + $0 } ?? "")
    }

    var latex: String {
        let relation = relation == "≈" ? "\\approx" : (relation == "≠" ? "\\neq" : (relation == "≡" ? "\\equiv" : relation))
        var ending = ""
        if let suffix {
            // "(mod 13)" has its own command.
            let modulus = suffix.filter(\.isNumber)
            ending = suffix == "°" ? "^\\circ" : (suffix.hasPrefix("(mod") && !modulus.isEmpty ? " \\pmod{\(modulus)}" : " \\text{ \(suffix)}")
        }
        return parts.map(Format.latex).joined(separator: " \(relation) ") + ending
    }
}

/// A step of the working: what was done, why, and the maths that came out of it.
struct Step: Sendable, Identifiable, Hashable {
    let id = UUID()
    var title: String
    var explanation: String
    var lines: [MathLine]

    init(_ title: String, _ explanation: String = "", _ lines: [MathLine] = []) {
        self.title = title
        self.explanation = explanation
        self.lines = lines
    }
}

/// A graph worth showing alongside: the functions of `variable`, with points to mark.
struct Plot: Sendable, Hashable {
    var functions: [(label: String, expr: Expr)]
    var variable: String
    var marks: [Double]
    var range: ClosedRange<Double>

    static func == (a: Plot, b: Plot) -> Bool { a.variable == b.variable && a.marks == b.marks && a.functions.map(\.label) == b.functions.map(\.label) }
    func hash(into hasher: inout Hasher) { hasher.combine(variable); hasher.combine(marks) }
}

/// A worked problem.
struct Solution: Sendable {
    var problem: Problem
    /// The question, written out neatly.
    var question: MathLine
    /// What the question asks for, in a few words: "Simplify", "Solve for x".
    var task: String
    var answers: [MathLine]
    /// A decimal value of an exact answer, like ≈ 0.3889 for 7/18.
    var approximation: String?
    var steps: [Step]
    /// Something worth knowing about the answer: "No real solutions", "+ C is any constant".
    var note: String?
    var plot: Plot?
    /// For simultaneous equations: the answers grouped into sets, "x = 2, y = 3".
    var answerSets: [[MathLine]]?
    /// How the problem was read, when Apple Intelligence helped.
    var source: String?

    /// The answer as one line: "x = 2 or x = 3".
    var answerText: String {
        if let answerSets {
            return answerSets.map { $0.map(\.text).joined(separator: ", ") }.joined(separator: " or ")
        }
        return answers.map(\.text).joined(separator: answers.count > 2 ? ", " : " or ")
    }

    var answerLatex: String {
        if let answerSets {
            return answerSets.map { $0.map(\.latex).joined(separator: ", ") }.joined(separator: " \\text{ or } ")
        }
        return answers.map(\.latex).joined(separator: answers.count > 2 ? ", \\quad " : " \\text{ or } ")
    }

    /// All of it as plain text: question, working and answer, for pasting into notes.
    var workingText: String {
        var lines = ["\(task): \(question.text)", ""]
        for (index, step) in steps.enumerated() {
            lines.append("\(index + 1). \(step.title)" + (step.explanation.isEmpty ? "" : ": \(step.explanation)"))
            lines += step.lines.map { "   " + $0.text }
        }
        lines.append("")
        lines.append("Answer: " + answerText + (approximation.map { " (\($0))" } ?? ""))
        if let note { lines.append(note) }
        return lines.joined(separator: "\n")
    }
}
