import Foundation

/// What a picked part of the maths is, said about this problem rather than in general: what
/// it means, what's done with it here, which terms it goes with, and what it comes to at the
/// answer.
enum Explain {
    /// Where the part is: the line it's in, and which side of the = (if it's an equation).
    struct Place {
        var line: MathLine
        var side: Int
        /// Steps into the expression from that side: empty for the whole side.
        var inside: [Int]
    }

    static func note(for part: MathPart, in solution: Solution, steps: [Step]) -> (name: String, detail: String) {
        let place = locate(part, in: solution, steps: steps)
        let x = solution.problem.kind.variable
        let answer = x.flatMap { value(of: $0, in: solution) }
        let (negative, size) = signed(part.expr)
        var sentences: [String] = []
        let name: String

        let isEquation = place.map { $0.line.relation == "=" && $0.line.parts.count == 2 } ?? false
        let isSolving: Bool = if case .solve = solution.problem.kind { true } else { false }
        let sideExpr = place.flatMap { $0.line.parts.indices.contains($0.side) ? $0.line.parts[$0.side] : nil }
        let otherSide = place.flatMap { isEquation ? $0.line.parts[1 - $0.side] : nil }
        let isWholeSide = place?.inside.isEmpty ?? false
        let sideTerms = sideExpr.map(terms) ?? []
        let isTermOfSum = !isWholeSide && sideTerms.count > 1 && sideTerms.contains(part.expr)

        do {
            switch size {
            case .number(let number):
                name = isTermOfSum ? "Constant term" : "Number"
                if !(isWholeSide && otherSide.map({ !$0.symbols.isEmpty }) == true) {
                    sentences.append(numberSentence(number, negative: negative, isTerm: isTermOfSum))
                }
                if isWholeSide, let otherSide, case .symbol(let letter) = otherSide, letter == x {
                    sentences.append("The answer: \(letter) = \(Format.text(part.expr)).")
                } else if isWholeSide, let otherSide, !otherSide.symbols.isEmpty {
                    sentences.append("It's what the other side, \(Format.text(otherSide)), is equal to.")
                }
                if isTermOfSum, isSolving, isEquation, let x, sideExpr?.symbols.contains(x) == true {
                    let shown = Format.text(size)
                    sentences.append(negative ? "To move it to the other side, add \(shown) to both sides: it arrives as +\(shown)."
                                              : "To move it to the other side, take \(shown) from both sides: it arrives as −\(shown).")
                } else if isTermOfSum, let x, sideExpr?.symbols.contains(x) == true {
                    sentences.append("It stays the same whatever \(x) is, so it can only be added to other numbers.")
                }
            case .symbol(let letter):
                name = letter == x ? "The unknown" : "Letter"
                sentences.append(letter == x && isSolving ? "The letter whose value the equation is solved for." : "A letter standing for a number.")
            default:
                (name, sentences) = term(size, negative: negative, x: x, isSolving: isSolving && isEquation, sideTerms: sideTerms, sideExpr: sideExpr)
            }
        }

        // Like terms in the same line.
        if let x, isTermOfSum, let line = place?.line {
            let others = line.parts.enumerated().flatMap { index, side in terms(side).map { (index, $0) } }
                .filter { $0.1 != part.expr && likeTerms($0.1, part.expr, x) }
            if let other = others.first {
                let sameSide = other.0 == place?.side
                sentences.append(sameSide ? "\(Format.text(other.1)) is a like term: same letter, same power. They can be added together."
                                          : "\(Format.text(other.1)) on the other side is a like term: bring them to one side to add them.")
            }
        }

        // What it comes to at the answer.
        if let x, let answer, part.expr.symbols == [x], part.expr != .symbol(x), let worth = part.expr.evaluate([x: answer]), worth.isFinite, !isWholeSide || isEquation {
            sentences.append("With \(x) = \(Format.decimal(answer)) it comes to \(Format.decimal((worth * 1e6).rounded() / 1e6)).")
        }
        return (name, sentences.joined(separator: " "))
    }

    // MARK: Terms

    private static func term(_ expr: Expr, negative: Bool, x: String?, isSolving: Bool, sideTerms: [Expr], sideExpr: Expr?) -> (String, [String]) {
        let text = Format.text(expr)
        var sentences: [String] = []
        // A fraction: something over a whole number.
        if let (top, bottom) = fraction(expr) {
            sentences.append("\(Format.text(top)) divided by \(bottom)" + (top.symbols.isEmpty ? "." : ": \(fractionWords(bottom)) of \(Format.text(top)).") )
            if isSolving, sideTerms.count == 1 {
                sentences.append("Multiply both sides by \(bottom) to undo the division.")
            } else if sideTerms.count > 1 {
                let denominators = sideTerms.compactMap { fraction(signed($0).1)?.1 }
                if denominators.count > 1, Set(denominators).count > 1 {
                    let common = denominators.reduce(1) { Rational.lcm($0, $1) ?? $0 }
                    sentences.append("To add it to the other fractions, rewrite each over \(common), the lowest common multiple of the denominators.")
                }
            }
            return ("Fraction", sentences)
        }
        // Brackets.
        if case .add = expr {
            sentences.append("A bracket: what's inside is worked out first and used as one value.")
            if let x, let root = linearRoot(expr, x) { sentences.append("It's zero when \(x) = \(Format.decimal(root)).") }
            return ("Bracket", sentences)
        }
        if case .multiply(let factors) = expr {
            let brackets = factors.filter { if case .add = $0 { true } else { false } }
            if brackets.count >= 2 {
                sentences.append("\(brackets.count == 2 ? "Two" : "\(brackets.count)") brackets multiplied together.")
                if let x {
                    let roots = brackets.compactMap { linearRoot($0, x) }
                    if roots.count == brackets.count, isSolving {
                        sentences.append("If they multiply to zero, one of them is zero: \(roots.map { "\(x) = \(Format.decimal($0))" }.joined(separator: " or ")).")
                    } else {
                        sentences.append("Multiplying every term in one by every term in the other gives \(Format.text(Simplify.expand(expr))).")
                    }
                }
                return ("Brackets multiplied", sentences)
            }
            if brackets.count == 1, let outside = factors.first(where: { if case .add = $0 { false } else { true } }) {
                sentences.append("\(Format.text(outside)) times a bracket: it multiplies every term inside, giving \(Format.text(Simplify.expand(expr))).")
                if isSolving, sideTerms.count == 1 { sentences.append("Or divide both sides by \(Format.text(outside)) first.") }
                return ("Bracket with a multiplier", sentences)
            }
        }
        // A term in the unknown: coefficient, letter and power.
        if let x, let form = PolynomialForm(expr, in: x), form.degree >= 1, form.coefficients.count == 1 {
            let coefficient = form.coefficient(form.degree)
            let power = form.degree
            let letterPart = power == 1 ? x : "\(x)\(superscript(power))"
            let names = [1: "Term in \(x)", 2: "Squared term", 3: "Cubed term"]
            let coefficientText = Format.text(coefficient)
            let part = coefficient.number?.rational
            if power == 1, let part, !part.isInteger {
                // A fraction of the letter: x/3 is a third of x.
                let share = part.numerator == 1 ? fractionWords(part.denominator) : "\(part.numerator)/\(part.denominator)"
                sentences.append("\(share.prefix(1).uppercased() + share.dropFirst()) of \(x)" + (negative ? ", taken away." : "."))
                if isSolving, sideTerms.count == 1 {
                    let undo = part.numerator == 1 ? "\(part.denominator)" : "\(part.denominator)/\(part.numerator)"
                    sentences.append("To get \(x) on its own, multiply both sides by \(undo).")
                }
            } else if power == 1 {
                if coefficient == .one {
                    sentences.append(negative ? "\(x) taken away: its coefficient is −1." : "\(x) on its own: its coefficient is 1.")
                } else {
                    sentences.append(negative ? "\(coefficientText) lots of \(x), taken away: the coefficient is −\(coefficientText)."
                                              : "\(coefficientText) lots of \(x): the \(coefficientText) in front is the coefficient, and it multiplies \(x).")
                }
                if isSolving, sideTerms.count == 1, coefficient != .one || negative {
                    sentences.append("To get \(x) on its own, divide both sides by \(negative ? "−" : "")\(coefficientText).")
                }
            } else {
                let times = Array(repeating: x, count: power).joined(separator: " × ")
                sentences.append("\(letterPart) means \(times)" + (coefficient == .one ? "." : ", and the \(coefficientText) in front multiplies it."))
                if isSolving, power == 2 { sentences.append("A squared term makes the equation quadratic, so there can be two answers.") }
                if isSolving, power == 3 { sentences.append("A cubed term makes the equation cubic: up to three answers.") }
            }
            return (names[power] ?? "Power of \(x)", sentences)
        }
        // A number to a power.
        if case .power(let base, let exponent) = expr, base.symbols.isEmpty, let times = exponent.number?.integer, times >= 2, times <= 12 {
            let value = expr.evaluate().map { Format.decimal($0) } ?? ""
            sentences.append("\(Format.text(base)) to the power \(times): \(times) lots of \(Format.text(base)) multiplied together" + (value.isEmpty ? "." : ", which is \(value)."))
            return ("Power", sentences)
        }
        // Roots and functions.
        if case .power(let base, let exponent) = expr, exponent == .half {
            sentences.append("The square root of \(Format.text(base)): the number that, multiplied by itself, gives \(Format.text(base)).")
            return ("Square root", sentences)
        }
        if case .function(let function, let argument) = expr {
            let inside = Format.text(argument)
            let words: [MathFunction: (String, String)] = [
                .sin: ("Sine", "In a right-angled triangle, the opposite side over the hypotenuse for the angle \(inside)."),
                .cos: ("Cosine", "In a right-angled triangle, the adjacent side over the hypotenuse for the angle \(inside)."),
                .tan: ("Tangent", "In a right-angled triangle, the opposite side over the adjacent for the angle \(inside)."),
                .ln: ("Natural logarithm", "The power e has to be raised to, to give \(inside)."),
                .log: ("Logarithm", "The power 10 has to be raised to, to give \(inside)."),
                .abs: ("Modulus", "How far \(inside) is from zero, so it's never negative."),
            ]
            if let (title, detail) = words[function] { return (title, [detail]) }
        }
        return ("Term", ["\(text), worked out as one value."])
    }

    // MARK: Helpers

    private static func numberSentence(_ number: Number, negative: Bool, isTerm: Bool) -> String {
        if let rational = number.rational, !rational.isInteger {
            return "\(rational.numerator) out of \(rational.denominator) equal parts" + (negative ? (isTerm ? ", taken away." : ", below zero.") : ".")
        }
        if isTerm { return negative ? "A constant taken away: a plain number, with no letter." : "A constant: a plain number, with no letter." }
        return negative ? "A negative number." : "A number."
    }

    private static func fractionWords(_ bottom: Int) -> String {
        let words = [2: "a half", 3: "a third", 4: "a quarter", 5: "a fifth", 6: "a sixth", 7: "a seventh", 8: "an eighth", 9: "a ninth",
                     10: "a tenth", 11: "an eleventh", 12: "a twelfth", 15: "a fifteenth", 16: "a sixteenth", 18: "an eighteenth",
                     20: "a twentieth", 24: "a twenty-fourth", 100: "a hundredth"]
        return words[bottom] ?? "1/\(bottom)"
    }

    private static func superscript(_ number: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        return String(String(number).compactMap { digits[$0] })
    }

    /// Something over a whole number: 2h/9 is (2h, 9).
    private static func fraction(_ expr: Expr) -> (Expr, Int)? {
        guard case .multiply(let factors) = expr, factors.count >= 2,
              case .power(let base, let exponent) = factors[factors.count - 1], exponent == .minusOne,
              let bottom = base.number?.integer, bottom > 1 else { return nil }
        let rest = Array(factors.dropLast())
        return (rest.count == 1 ? rest[0] : .multiply(rest), bottom)
    }

    /// Where a straight line in `x` is zero.
    private static func linearRoot(_ expr: Expr, _ x: String) -> Double? {
        guard expr.symbols == [x], let zero = expr.evaluate([x: 0]), let one = expr.evaluate([x: 1]), let two = expr.evaluate([x: 2]),
              abs(two - (zero + 2 * (one - zero))) < 1e-9, abs(one - zero) > 1e-12 else { return nil }
        return (-zero / (one - zero) * 1e6).rounded() / 1e6
    }

    private static func likeTerms(_ a: Expr, _ b: Expr, _ x: String) -> Bool {
        guard let first = PolynomialForm(a, in: x), let second = PolynomialForm(b, in: x),
              first.coefficients.count == 1, second.coefficients.count == 1 else { return false }
        return first.degree == second.degree && first.degree >= 1
    }

    /// The terms as they're read, however the sum was built up.
    private static func terms(_ expr: Expr) -> [Expr] {
        if case .add(let parts) = expr { return parts.flatMap(terms) }
        return [expr]
    }

    private static func signed(_ term: Expr) -> (Bool, Expr) {
        switch term {
        case .number(let value) where value.isNegative: return (true, .number(value.negated))
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                if value.negated.isOne, factors.count > 1 {
                    let rest = Array(factors.dropFirst())
                    return (true, rest.count == 1 ? rest[0] : .multiply(rest))
                }
                return (true, .multiply([.number(value.negated)] + factors.dropFirst()))
            }
            return (false, term)
        default:
            return (false, term)
        }
    }

    /// The unknown's value, when the problem has exactly one.
    private static func value(of x: String, in solution: Solution) -> Double? {
        let values = solution.answers.compactMap { line -> Double? in
            guard line.parts.count == 2, case .symbol(let name) = line.parts[0], name == x else { return nil }
            return line.parts[1].evaluate()
        }
        return values.count == 1 ? values[0] : nil
    }

    private static func locate(_ part: MathPart, in solution: Solution, steps: [Step]) -> Place? {
        guard let side = part.path.first else { return nil }
        let line: MathLine?
        if part.line.hasPrefix("problem.") {
            let index = Int(part.line.dropFirst("problem.".count)) ?? 0
            let lines = solution.problem.kind.lines
            line = lines.indices.contains(index) ? lines[index] : nil
        } else if part.line.hasPrefix("step.") {
            let numbers = part.line.dropFirst("step.".count).split(separator: ".").compactMap { Int($0) }
            line = numbers.count == 2 && steps.indices.contains(numbers[0]) && steps[numbers[0]].lines.indices.contains(numbers[1])
                ? steps[numbers[0]].lines[numbers[1]] : nil
        } else {
            line = nil
        }
        return line.map { Place(line: $0, side: side, inside: Array(part.path.dropFirst())) }
    }
}
