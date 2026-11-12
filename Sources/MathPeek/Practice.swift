import Foundation

/// Another problem like the one showing: the same maths with different numbers, chosen so
/// the answers come out as tidily as the original's, for trying it again yourself.
enum Practice {
    /// Whether the problem has numbers that can be changed to make another.
    static func canVary(_ solution: Solution) -> Bool {
        switch solution.problem.kind {
        case .diagram, .worded, .sequence: return false
        default:
            // A percentage or a fraction written as one number would come out as an odd fraction.
            let spots = places(in: solution.problem.kind)
            return !spots.isEmpty && spots.allSatisfy { $0.value.rational?.isInteger ?? true }
        }
    }

    static func another(like solution: Solution, angles: AngleUnit) -> Solution? {
        guard canVary(solution) else { return nil }
        let original = solution.problem
        let spots = places(in: original.kind)
        let tidy = isTidy(solution)
        let whole = isWhole(solution)
        var generator = SystemRandomNumberGenerator()

        /// The problem with some of its numbers changed, worked out, if it's as good a
        /// problem as the original.
        func attempt(_ values: [Int: Number]) -> Solution? {
            var kind = original.kind
            for (index, value) in values {
                let spot = spots[index]
                let lines = kind.lines
                guard lines.indices.contains(spot.line), lines[spot.line].parts.indices.contains(spot.side),
                      let replaced = lines[spot.line].parts[spot.side].replacing(at: spot.path[...], with: .number(value)) else { return nil }
                kind = kind.replacing(line: spot.line, side: spot.side, with: replaced)
            }
            var problem = original
            problem.kind = kind
            problem.text = kind.text
            problem.writtenAnswer = nil
            problem.lead = []
            problem.wantsTermNumber = false
            guard problem.text != original.text,
                  let made = Engine.solve(problem, angles: angles),
                  made.answers.count == solution.answers.count, !made.answers.isEmpty || solution.answers.isEmpty,
                  abs(made.steps.count - solution.steps.count) <= 1,
                  !tidy || isTidy(made), !whole || isWhole(made),
                  fractionsInLowestTerms(kind),
                  // Something to do: what was worked out still changes ("Factorise x² + 4x + 5"
                  // can't be), and an answer that wasn't zero isn't zero now.
                  changes(solution) == changes(made),
                  isZero(solution) || !isZero(made) else { return nil }
            return made
        }

        // Numbers that are all powers of one number (√81 = 9ⁿ: 81 is 9², 9 is 9¹) have to stay
        // that way: change the number they're powers of, and every one with it.
        if let base = commonBase(spots.map(\.value)) {
            for next in (2...12).shuffled(using: &generator) where next != base.base {
                var values: [Int: Number] = [:]
                for (index, power) in base.powers.enumerated() {
                    guard let value = Rational(next).power(power), abs(value.numerator) < 100_000 else { values = [:]; break }
                    values[index] = .exact(spots[index].value.isNegative ? value.negated : value)
                }
                if !values.isEmpty, let made = attempt(values) { return made }
            }
        }
        // Otherwise numbers chosen afresh: all of them, or only some, since some may have to
        // stay as they are for the problem to work out.
        // Numbers that are the same stay the same as each other (2⁵ × 2³ stays a power of one
        // number times another power of it).
        var groups: [[Int]] = []
        for index in spots.indices {
            if let group = groups.firstIndex(where: { spots[$0[0]].value == spots[index].value }) { groups[group].append(index) } else { groups.append([index]) }
        }
        for round in 0..<300 {
            var values: [Int: Number] = [:]
            for group in groups where round < 150 || Bool.random(using: &generator) {
                let new = vary(spots[group[0]].value, using: &generator)
                guard new != spots[group[0]].value else { continue }
                for index in group { values[index] = new }
            }
            guard !values.isEmpty else { continue }
            if let made = attempt(values) { return made }
        }
        return nil
    }

    /// The largest whole number that every one of the numbers is a whole power of, and those
    /// powers: 81 and 9 are 9² and 9¹. Nil when there's no such number but the numbers themselves.
    private static func commonBase(_ values: [Number]) -> (base: Int, powers: [Int])? {
        let sizes = values.compactMap { $0.rational.flatMap { $0.isInteger ? abs($0.numerator) : nil } }
        guard sizes.count == values.count, sizes.count >= 2, let smallest = sizes.min(), smallest >= 2 else { return nil }
        for base in stride(from: smallest, through: 2, by: -1) {
            var powers: [Int] = []
            for size in sizes {
                var power = 0, rest = size
                while rest % base == 0, rest > 1 { rest /= base; power += 1 }
                guard rest == 1, power >= 1 else { powers = []; break }
                powers.append(power)
            }
            // Only worth it when they aren't all the same power of it (then it's no link at all).
            if powers.count == sizes.count, Set(powers).count > 1 || powers.allSatisfy({ $0 > 1 }) { return (base, powers) }
        }
        return nil
    }

    // MARK: The numbers to change

    private struct Spot {
        var line: Int
        var side: Int
        var path: [Int]
        var value: Number
    }

    /// Every number in the problem that can change without changing what kind of problem it
    /// is: not a power (that would change x² into x³), and not 0 or 1 (which come and go).
    private static func places(in kind: ProblemKind) -> [Spot] {
        var found: [Spot] = []
        for (line, mathLine) in kind.lines.enumerated() {
            for (side, part) in mathLine.parts.enumerated() {
                walk(part, path: []) { path, value in found.append(Spot(line: line, side: side, path: path, value: value)) }
            }
        }
        return found
    }

    private static func walk(_ expr: Expr, path: [Int], _ visit: ([Int], Number) -> Void) {
        switch expr {
        case .number(let value):
            let size = abs(value.double)
            if size != 0, size != 1 { visit(path, value) }
        case .add(let parts), .multiply(let parts):
            for (index, part) in parts.enumerated() { walk(part, path: path + [index], visit) }
        case .power(let base, let exponent):
            // The base only: its power stays as it is. Nor is a denominator of 10, 100 or 1000
            // changed: it's a decimal or a percentage written as a fraction.
            if exponent == .minusOne, let bottom = base.number?.integer, [10, 100, 1000].contains(bottom) { return }
            walk(base, path: path + [0], visit)
        case .function(_, let argument):
            walk(argument, path: path + [0], visit)
        default:
            break
        }
    }

    /// A nearby number of the same kind: a whole number stays whole and keeps its sign, a
    /// decimal keeps its places, a fraction stays a fraction.
    private static func vary(_ value: Number, using generator: inout SystemRandomNumberGenerator) -> Number {
        if let rational = value.rational {
            if rational.isInteger {
                let size = abs(rational.numerator)
                let top = max(9, min(size * 2, 99))
                let new = Int.random(in: 2...top, using: &generator)
                return .integer(rational.numerator < 0 ? -new : new)
            }
            let bottom = Int.random(in: 2...12, using: &generator)
            let numerator = Int.random(in: 1...(bottom * 2), using: &generator)
            return Rational.make(rational.numerator < 0 ? -numerator : numerator, bottom).map { .exact($0) } ?? value
        }
        let text = Format.decimal(abs(value.double))
        let pieces = text.split(separator: ".")
        let places = pieces.count == 2 ? pieces[1].count : 0
        let scale = pow(10, Double(places))
        let new = (Double.random(in: 1...max(10, abs(value.double) * 2), using: &generator) * scale).rounded() / scale
        return .real(value.double < 0 ? -new : new)
    }

    /// Whether the answer is the question written differently, rather than the same again.
    private static func changes(_ solution: Solution) -> Bool {
        solution.answerText != solution.question.text && !solution.steps.isEmpty
    }

    /// Whether the answer is zero.
    private static func isZero(_ solution: Solution) -> Bool {
        let lines = solution.answerSets?.flatMap { $0 } ?? solution.answers
        return !lines.isEmpty && lines.allSatisfy { $0.parts.last?.number?.isZero == true }
    }

    /// Whether every answer is a whole number.
    private static func isWhole(_ solution: Solution) -> Bool {
        let lines = solution.answerSets?.flatMap { $0 } ?? solution.answers
        return !lines.isEmpty && lines.allSatisfy { $0.parts.last?.number?.rational?.isInteger == true }
    }

    /// Every fraction in the problem written as it would be in a question: in its lowest
    /// terms, and with a top that isn't zero.
    private static func fractionsInLowestTerms(_ kind: ProblemKind) -> Bool {
        func check(_ expr: Expr) -> Bool {
            switch expr {
            case .multiply(let factors):
                if factors.count == 2, let top = factors[0].number?.integer, case .power(let base, let exponent) = factors[1],
                   exponent == .minusOne, let bottom = base.number?.integer {
                    return Rational.gcd(abs(top), abs(bottom)) == 1 && abs(top) < abs(bottom) * 3
                }
                return factors.allSatisfy(check)
            case .add(let parts): return parts.allSatisfy(check)
            case .power(let base, _): return check(base)
            case .function(_, let argument): return check(argument)
            default: return true
            }
        }
        return kind.lines.allSatisfy { $0.parts.allSatisfy(check) }
    }

    /// Whether every answer is a whole number or a simple fraction.
    private static func isTidy(_ solution: Solution) -> Bool {
        let lines = solution.answerSets?.flatMap { $0 } ?? solution.answers
        guard !lines.isEmpty else { return true }
        return lines.allSatisfy { line in
            guard let last = line.parts.last else { return false }
            if let rational = last.number?.rational { return rational.isInteger || (rational.denominator <= 12 && abs(rational.numerator) <= 1000) }
            return !last.symbols.isEmpty
        }
    }
}
