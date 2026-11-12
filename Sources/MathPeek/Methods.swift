import Foundation

/// Other ways to the same answers, where there's more than one way that's taught: a quadratic
/// equation by factorising, by the formula, or by completing the square. Each is a solution
/// of its own, with the same answers and its own steps.
enum Methods {
    struct Method {
        var name: String
        var solution: Solution
    }

    /// Every way to work the problem out, the one MathPeek chose first. Just the one when
    /// there's no other.
    static func all(for solution: Solution, angles: AngleUnit) -> [Method] {
        guard case .solve(let equations, _) = solution.problem.kind, equations.count == 1,
              let x = solution.problem.kind.variable,
              let quadratic = coefficients(equations[0], x) else { return [] }
        let first = Engine.solve(solution.problem, angles: angles) ?? solution
        let firstName = name(of: first)
        // Without real answers there's nothing to find another way to.
        guard let bSquared = quadratic.b * quadratic.b, let ac = quadratic.a * quadratic.c, let ac4 = ac * Rational(4),
              let discriminant = bSquared - ac4, discriminant.numerator >= 0 else { return [] }
        var methods = [Method(name: firstName, solution: first)]
        if firstName != "Formula", let formula = formula(quadratic, x, like: first) {
            methods.append(Method(name: "Formula", solution: formula))
        }
        if firstName != "Completing the square", !quadratic.b.isZero, let square = completingTheSquare(quadratic, x, like: first) {
            methods.append(Method(name: "Completing the square", solution: square))
        }
        return methods.count > 1 ? methods : []
    }

    /// What a solution's working does, from its step titles.
    private static func name(of solution: Solution) -> String {
        let titles = solution.steps.map { $0.title.lowercased() }
        if titles.contains(where: { $0.contains("formula") }) { return "Formula" }
        if titles.contains(where: { $0.contains("square") && $0.contains("complet") }) { return "Completing the square" }
        if titles.contains(where: { $0.contains("factoris") }) { return "Factorising" }
        if titles.contains(where: { $0.contains("square root") }) { return "Square root" }
        return "Usual way"
    }

    // MARK: The quadratic

    private struct Quadratic {
        var a: Rational
        var b: Rational
        var c: Rational
    }

    /// a, b and c of ax² + bx + c = 0, when they're plain numbers.
    private static func coefficients(_ equation: Equation, _ x: String) -> Quadratic? {
        let difference = Expr.add([equation.left, .multiply([.minusOne, equation.right])])
        guard let form = PolynomialForm(difference, in: x), form.degree == 2,
              let a = form.coefficient(2).number?.rational ?? Simplify.run(form.coefficient(2)).number?.rational,
              let b = Simplify.run(form.coefficient(1)).number?.rational,
              let c = Simplify.run(form.coefficient(0)).number?.rational, !a.isZero else { return nil }
        return Quadratic(a: a, b: b, c: c)
    }

    private static func number(_ value: Rational) -> Expr { .number(.exact(value)) }
    private static func text(_ value: Rational) -> String { Format.text(number(value)) }

    /// The square root of a fraction, when it's exact.
    private static func root(_ value: Rational) -> Rational? {
        guard value.numerator >= 0, let top = Rational.exactRoot(value.numerator, 2), let bottom = Rational.exactRoot(value.denominator, 2) else { return nil }
        return Rational.make(top, bottom)
    }

    /// A copy of the solution with other steps: same problem, same answers.
    private static func with(_ steps: [Step], like solution: Solution) -> Solution {
        var made = solution
        made.steps = steps
        return made
    }

    // MARK: The formula

    private static func formula(_ q: Quadratic, _ x: String, like solution: Solution) -> Solution? {
        guard let bSquared = q.b * q.b, let fourAC = q.a * q.c, let fourAC4 = fourAC * Rational(4), let discriminant = bSquared - fourAC4,
              let twoA = q.a * Rational(2) else { return nil }
        var steps: [Step] = []
        steps.append(Step("Read off a, b and c", "In ax² + bx + c = 0: the number in front of \(x)², of \(x), and on its own.",
                          [MathLine(.symbol("a"), number(q.a)), MathLine(.symbol("b"), number(q.b)), MathLine(.symbol("c"), number(q.c))]))
        steps.append(Step("Work out the discriminant", "b² − 4ac: positive gives two answers, zero gives one, negative gives none.",
                          [MathLine(.symbol("b² − 4ac"), .add([.power(number(q.b), .integer(2)), .multiply([.integer(-4), number(q.a), number(q.c)])])),
                           MathLine(.symbol("b² − 4ac"), number(discriminant))]))
        let minusB = text(q.b.negated)
        let bottom = text(twoA)
        if discriminant.numerator < 0 {
            steps.append(Step("No real answers", "A negative number has no real square root, so nothing makes the equation true."))
            return with(steps, like: solution)
        }
        steps.append(Step("Put them into the formula", "\(x) = (−b ± √(b² − 4ac)) / 2a.",
                          [MathLine(.symbol(x), .symbol("\(minusB) ± √\(text(discriminant))/\(bottom)"))]))
        if let r = root(discriminant) {
            if discriminant.isZero {
                if let value = q.b.negated / twoA {
                    steps.append(Step("One answer", "With nothing to add or take away, both answers are the same.",
                                      [MathLine(.symbol(x), .symbol("\(minusB)/\(bottom)"), number(value))]))
                }
            } else if let plus = q.b.negated + r, let minus = q.b.negated - r, let first = plus / twoA, let second = minus / twoA {
                steps.append(Step("Take the + and the − in turn", "",
                                  [MathLine(.symbol(x), .symbol("\(minusB) + \(text(r))/\(bottom)"), number(first)),
                                   MathLine(.symbol(x), .symbol("\(minusB) − \(text(r))/\(bottom)"), number(second))]))
            }
        } else {
            steps.append(Step("Take the + and the − in turn", "The square root isn't exact, so the answers keep it.", solution.answers))
        }
        return with(steps, like: solution)
    }

    // MARK: Completing the square

    /// What moves the number in the bracket across: taking it away, or adding it.
    private static func move(_ h: Rational) -> String {
        h.numerator < 0 ? "Add \(text(h.negated)) to both sides" : "Take \(text(h)) from both sides"
    }

    private static func completingTheSquare(_ q: Quadratic, _ x: String, like solution: Solution) -> Solution? {
        guard let p = q.b / q.a, let s = q.c / q.a, let h = p / Rational(2), let hSquared = h * h, let right = hSquared - s else { return nil }
        let letter = Expr.symbol(x)
        var steps: [Step] = []
        if q.a != Rational(1) {
            steps.append(Step("Divide through by \(text(q.a))", "So \(x)² is on its own at the front.",
                              [MathLine(.add([.power(letter, .integer(2)), .multiply([number(p), letter]), number(s)]), .integer(0))]))
        }
        let bracket = Expr.add([letter, number(h)])
        steps.append(Step("Halve the number in front of \(x)", "Half of \(text(p)) is \(text(h)).", [MathLine(number(h))]))
        steps.append(Step("Write it as a square", "(\(x) + \(text(h)))² makes \(x)² + \(text(p))\(x) + \(text(hSquared)), so take the extra \(text(hSquared)) away again.",
                          [MathLine(.add([.power(bracket, .integer(2)), number(hSquared.negated), number(s)]), .integer(0)),
                           MathLine(.power(bracket, .integer(2)), number(right))]))
        if right.numerator < 0 {
            steps.append(Step("No real answers", "A square can't be negative, so nothing makes the equation true."))
            return with(steps, like: solution)
        }
        if let r = root(right) {
            steps.append(Step("Square root both sides", r.isZero ? "" : "A square root can be + or −.",
                              [MathLine(bracket, r.isZero ? .integer(0) : .symbol("±" + text(r)))]))
            if let first = r - h, let second = r.negated - h {
                steps.append(Step(move(h), "",
                                  r.isZero ? [MathLine(letter, number(first))] : [MathLine(letter, number(first)), MathLine(letter, number(second))]))
            }
        } else {
            steps.append(Step("Square root both sides", "A square root can be + or −, and this one isn't exact.",
                              [MathLine(bracket, .symbol("±√" + text(right)))]))
            steps.append(Step(move(h), "", solution.answers))
        }
        return with(steps, like: solution)
    }
}
