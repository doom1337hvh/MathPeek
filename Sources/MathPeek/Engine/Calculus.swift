import Foundation

/// Differentiation and integration, with the rules used named in the working.
enum Calculus {
    // MARK: Differentiation

    static func differentiate(_ expr: Expr, _ x: String, order: Int, _ problem: Problem) -> Solution? {
        var steps: [Step] = []
        var current = Simplify.run(expr)
        for round in 1...max(order, 1) {
            if round > 1 { steps.append(Step("Differentiate again", "The second derivative is the derivative of the first.")) }
            steps += explain(current, x)
            current = differentiated(current, x)
            if round == 1 && order > 1 { steps.append(Step("First derivative", "", [MathLine(.symbol("dy/d\(x)"), current)])) }
        }
        let name = order == 2 ? "d²y/d\(x)²" : "dy/d\(x)"
        let plot = Engine.plot(of: [("y", expr), (name, current)])
        return Solution(problem: problem, question: MathLine(expr), task: order == 2 ? "Differentiate twice" : "Differentiate",
                        answers: [MathLine(.symbol(name), current)], steps: steps, plot: plot)
    }

    /// The derivative, written tidily; a quotient keeps its bottom squared, (…)/(x − 1)².
    static func differentiated(_ expr: Expr, _ x: String) -> Expr {
        let (_, rest) = Simplify.splitCoefficient(expr)
        if rest == expr, let (u, v) = quotient(expr, x) {
            let top = Simplify.expand(derivative(u, x) * v - u * derivative(v, x))
            let factored = Simplify.run(.multiply([top, .power(.power(v, .two), .minusOne)]))
            return Solver.tidiest([factored, tidy(derivative(expr, x))])
        }
        return tidy(derivative(expr, x))
    }

    /// The tidiest of the ways to write a derivative.
    static func tidy(_ raw: Expr) -> Expr {
        let simplified = Simplify.run(raw)
        var options = [simplified, Simplify.expand(simplified)]
        if Engine.hasSymbolicDenominator(simplified) { options.append(Simplify.together(simplified)) }
        return Solver.tidiest(options)
    }

    /// The working for one differentiation: term by term, then the rule each term needs.
    private static func explain(_ expr: Expr, _ x: String) -> [Step] {
        if case .add(let terms) = expr {
            let lines = terms.map { MathLine($0, tidy(derivative($0, x)), relation: "→") }
            var steps = [Step("Differentiate term by term", ruleSummary(terms, x), lines)]
            for term in terms { steps += detail(term, x) }
            return steps
        }
        let rule = detail(expr, x)
        if rule.isEmpty {
            return [Step(ruleName(expr, x).capitalizedFirst, "", [MathLine(expr, tidy(derivative(expr, x)), relation: "→")])]
        }
        return rule
    }

    private static func ruleSummary(_ terms: [Expr], _ x: String) -> String {
        let names = Set(terms.map { ruleName($0, x) })
        return "Using the " + names.sorted().joined(separator: ", ") + "."
    }

    private static func ruleName(_ expr: Expr, _ x: String) -> String {
        let (_, rest) = Simplify.splitCoefficient(expr)
        if !rest.contains(x) { return "rule that constants differentiate to 0" }
        if let (u, v) = quotient(rest, x), u.contains(x) || v.contains(x) { return "quotient rule" }
        if case .multiply(let factors) = rest, factors.filter({ $0.contains(x) }).count > 1 { return "product rule" }
        if case .power(let base, _) = rest, base == .symbol(x) { return "power rule" }
        if case .symbol = rest { return "power rule" }
        if hasInner(rest, x) { return "chain rule" }
        if case .power(.constant(.e), _) = rest { return "rule d/dx eˣ = eˣ" }
        if case .function(let f, _) = rest { return "standard derivative of \(Format.functionName(f))" }
        return "standard rules"
    }

    /// A product, quotient or chain rule step for a term that needs one.
    private static func detail(_ expr: Expr, _ x: String) -> [Step] {
        let (_, rest) = Simplify.splitCoefficient(expr)
        if let (u, v) = quotient(rest, x) {
            let du = tidy(derivative(u, x)), dv = tidy(derivative(v, x))
            return [Step("Use the quotient rule", "d/dx (u/v) = (u′v − uv′) / v², with u = \(Format.text(u)) and v = \(Format.text(v)).",
                         [MathLine(.symbol("u′"), du), MathLine(.symbol("v′"), dv),
                          MathLine(.multiply([.add([.multiply([du, v]), .multiply([.minusOne, u, dv])]), .power(.power(v, .two), .minusOne)]),
                                   tidy(derivative(rest, x)))])]
        }
        if case .multiply(let factors) = rest {
            let withX = factors.filter { $0.contains(x) }
            if withX.count == 2 {
                let (u, v) = (withX[0], withX[1])
                let du = tidy(derivative(u, x)), dv = tidy(derivative(v, x))
                return [Step("Use the product rule", "d/dx (uv) = u′v + uv′, with u = \(Format.text(u)) and v = \(Format.text(v)).",
                             [MathLine(.symbol("u′"), du), MathLine(.symbol("v′"), dv),
                              MathLine(.add([.multiply([du, v]), .multiply([u, dv])]), tidy(derivative(rest, x)))])]
            }
        }
        if let inner = innerFunction(rest, x) {
            let dInner = tidy(derivative(inner, x))
            return [Step("Use the chain rule", "Differentiate the outside, keep the inside, then multiply by the derivative of the inside, \(Format.text(inner)).",
                         [MathLine(.symbol("inside′"), dInner), MathLine(rest, tidy(derivative(rest, x)), relation: "→")])]
        }
        return []
    }

    /// u/v when a term is a fraction with the letter on the bottom.
    private static func quotient(_ expr: Expr, _ x: String) -> (Expr, Expr)? {
        let (top, bottom) = Simplify.numeratorAndDenominator(expr)
        guard bottom.contains(x), top.contains(x) else { return nil }
        return (top, bottom)
    }

    private static func hasInner(_ expr: Expr, _ x: String) -> Bool { innerFunction(expr, x) != nil }

    /// What's inside a function of a function, like 3x + 1 in sin(3x + 1).
    private static func innerFunction(_ expr: Expr, _ x: String) -> Expr? {
        switch expr {
        case .function(_, let argument) where argument != .symbol(x) && argument.contains(x): return argument
        case .power(let base, let exponent) where !exponent.contains(x) && base != .symbol(x) && base.contains(x): return base
        case .power(let base, let exponent) where !base.contains(x) && exponent != .symbol(x) && exponent.contains(x): return exponent
        default: return nil
        }
    }

    static func derivative(_ expr: Expr, _ x: String) -> Expr {
        guard expr.contains(x) else { return .zero }
        switch expr {
        case .symbol: return .one
        case .add(let terms): return .add(terms.map { derivative($0, x) })
        case .multiply(let factors):
            let constant = factors.filter { !$0.contains(x) }
            let variable = factors.filter { $0.contains(x) }
            let products: [Expr] = variable.indices.map { i in
                .multiply(variable.enumerated().map { j, factor in j == i ? derivative(factor, x) : factor })
            }
            return .multiply(constant + [.add(products)])
        case .power(let base, let exponent):
            if !exponent.contains(x) {
                // Power rule and chain rule: n u^(n−1) u′
                return .multiply([exponent, .power(base, Simplify.run(exponent - .one)), derivative(base, x)])
            }
            if !base.contains(x) {
                // a^u = a^u ln a · u′
                let log: Expr = base == .constant(.e) ? .one : .function(.ln, base)
                return .multiply([expr, log, derivative(exponent, x)])
            }
            // u^v = u^v (v′ ln u + v u′/u)
            return .multiply([expr, .add([.multiply([derivative(exponent, x), .function(.ln, base)]),
                                          .multiply([exponent, derivative(base, x), .power(base, .minusOne)])])])
        case .function(let function, let u):
            let outer: Expr = switch function {
            case .sin: .function(.cos, u)
            case .cos: -.function(.sin, u)
            case .tan: .power(.function(.sec, u), .two)
            case .sec: .multiply([.function(.sec, u), .function(.tan, u)])
            case .csc: -.multiply([.function(.csc, u), .function(.cot, u)])
            case .cot: -.power(.function(.csc, u), .two)
            case .asin: .power(.one - .power(u, .two), .fraction(-1, 2))
            case .acos: -.power(.one - .power(u, .two), .fraction(-1, 2))
            case .atan: .power(.one + .power(u, .two), .minusOne)
            case .sinh: .function(.cosh, u)
            case .cosh: .function(.sinh, u)
            case .tanh: .one - .power(.function(.tanh, u), .two)
            case .ln: .power(u, .minusOne)
            case .log: .power(.multiply([u, .function(.ln, .integer(10))]), .minusOne)
            case .abs: .multiply([u, .power(.function(.abs, u), .minusOne)])
            }
            return .multiply([outer, derivative(u, x)])
        default:
            return .zero
        }
    }

    // MARK: Integration

    static func integrate(_ expr: Expr, _ x: String, from: Expr?, to: Expr?, _ problem: Problem) -> Solution? {
        let integrand = Simplify.run(expr)
        let found = integral(integrand, x, depth: 0)
        var steps = found?.1 ?? []
        let question = MathLine(expr)
        if let from, let to {
            let a = Simplify.run(from), b = Simplify.run(to)
            let task = "Integrate from \(Format.text(a)) to \(Format.text(b))"
            if let (antiderivative, _) = found {
                let upper = Simplify.run(antiderivative.substituting(x, with: b))
                let lower = Simplify.run(antiderivative.substituting(x, with: a))
                let value = Simplify.run(upper - lower)
                steps.append(Step("Put in the limits", "F(\(Format.text(b))) − F(\(Format.text(a))), where F = \(Format.text(antiderivative)).",
                                  [MathLine(.add([upper, .multiply([.minusOne, lower])]), value)]))
                let (answer, approximation) = Engine.presentNumber(value, decimals: problem.usesDecimals)
                return Solution(problem: problem, question: question, task: task, answers: [MathLine(answer)],
                                approximation: approximation, steps: steps,
                                plot: Engine.plot(of: [("y", integrand)], marks: [a.evaluate(), b.evaluate()].compactMap { $0 }))
            }
            guard let lowValue = a.evaluate(), let highValue = b.evaluate(),
                  let value = simpson(integrand, x, lowValue, highValue) else { return nil }
            steps = [Step("Integrate numerically", "There's no neat formula for this one, so MathPeek added up thin slices under the curve (Simpson's rule).",
                          [MathLine(.number(.real(value)))])]
            return Solution(problem: problem, question: question, task: task,
                            answers: [MathLine(.number(.real(value)), relation: "≈")], steps: steps,
                            plot: Engine.plot(of: [("y", integrand)], marks: [lowValue, highValue]))
        }
        guard let (antiderivative, _) = found else {
            return Solution(problem: problem, question: question, task: "Integrate", answers: [], steps: [],
                            note: "MathPeek can't integrate this exactly. Give limits (from a to b) to get a number.")
        }
        let withConstant = Expr.add([antiderivative, .symbol("C")])
        return Solution(problem: problem, question: question, task: "Integrate", answers: [MathLine(withConstant)],
                        steps: steps, note: "C is any constant: differentiating it gives 0.",
                        plot: Engine.plot(of: [("y", integrand), ("∫", antiderivative)]))
    }

    /// An antiderivative and the working, or nil.
    static func integral(_ f: Expr, _ x: String, depth: Int) -> (Expr, [Step])? {
        guard depth < 6 else { return nil }
        if !f.contains(x) {
            return (Simplify.multiply([f, .symbol(x)]), [])
        }
        if case .add(let terms) = f {
            var parts: [Expr] = [], steps: [Step] = [], lines: [MathLine] = []
            for term in terms {
                guard let (part, more) = integral(term, x, depth: depth + 1) else { return nil }
                parts.append(part)
                lines.append(MathLine(term, part, relation: "→"))
                steps += more
            }
            let result = Simplify.add(parts)
            return (result, depth == 0 ? [Step("Integrate term by term", "Add 1 to each power and divide by the new power; standard forms for the rest.", lines)] + steps : steps)
        }
        let (coefficient, rest) = Simplify.splitCoefficient(f)
        if !coefficient.isOne, let (part, steps) = integral(rest, x, depth: depth) {
            let result = Simplify.multiply([.number(coefficient), part])
            return (result, depth == 0 && steps.isEmpty ? [Step(rule(rest, x), "", [MathLine(f, result, relation: "→")])] : steps)
        }
        if case .multiply(let factors) = rest {
            let constants = factors.filter { !$0.contains(x) }
            if !constants.isEmpty {
                let remaining = Simplify.multiply(factors.filter { $0.contains(x) })
                if let (part, steps) = integral(remaining, x, depth: depth + 1) {
                    return (Simplify.multiply(constants + [part]), steps)
                }
            }
        }
        if let result = standard(rest, x) {
            return (result, depth == 0 ? [Step(rule(rest, x), "", [MathLine(rest, result, relation: "→")])] : [])
        }
        // Brackets multiplied out: x(x + 1)² and so on.
        if Engine.containsBrackets(rest) {
            let expanded = Simplify.expand(rest)
            if expanded != rest, let (result, steps) = integral(expanded, x, depth: depth + 1) {
                return (result, [Step("Expand the brackets first", "", [MathLine(expanded)])] + steps)
            }
        }
        if let found = partialFractions(rest, x) { return found }
        if let found = substitution(rest, x, depth: depth) { return found }
        if let found = byParts(rest, x, depth: depth) { return found }
        return nil
    }

    private static func rule(_ f: Expr, _ x: String) -> String {
        if case .power(.symbol, let n) = f, n != .minusOne { return "Power rule: add 1 to the power, divide by the new power" }
        if f == .symbol(x) { return "Power rule: add 1 to the power, divide by the new power" }
        if case .power(.symbol, .minusOne) = f { return "Standard integral: 1/x integrates to ln|x|" }
        return "Standard integral"
    }

    /// a·x + b, if `expr` is linear in x.
    private static func linear(_ expr: Expr, _ x: String) -> (Expr, Expr)? {
        guard let form = PolynomialForm(expr, in: x), form.degree == 1 else { return nil }
        let a = form.coefficient(1), b = form.coefficient(0)
        guard !a.contains(x), !b.contains(x) else { return nil }
        return (a, b)
    }

    /// The table of standard integrals, including f(ax + b).
    private static func standard(_ f: Expr, _ x: String) -> Expr? {
        let variable = Expr.symbol(x)
        if f == variable { return Simplify.run(.half * .power(variable, .two)) }
        switch f {
        case .power(let base, let exponent) where !exponent.contains(x):
            guard let (a, _) = linear(base, x) else { break }
            if exponent == .minusOne {
                return Simplify.run(.function(.ln, .function(.abs, base)) / a)
            }
            // sec²(ax + b) is cos(ax + b)^−2
            if exponent == .integer(-2), case .function(.cos, let inner) = base, let (k, _) = linear(inner, x) {
                return Simplify.run(.function(.tan, inner) / k)
            }
            let n1 = Simplify.run(exponent + .one)
            return Simplify.run(.power(base, n1) / (n1 * a))
        case .power(.function(.cos, let inner), let exponent) where exponent == .integer(-2):
            guard let (k, _) = linear(inner, x) else { break }
            return Simplify.run(.function(.tan, inner) / k)
        case .power(.function(.sec, let inner), let exponent) where exponent == .two:
            guard let (k, _) = linear(inner, x) else { break }
            return Simplify.run(.function(.tan, inner) / k)
        case .power(let base, let exponent) where !base.contains(x):
            guard let (a, _) = linear(exponent, x) else { break }
            let log: Expr = base == .constant(.e) ? .one : .function(.ln, base)
            return Simplify.run(f / (a * log))
        case .function(let function, let inner):
            guard let (a, _) = linear(inner, x) else { break }
            let result: Expr? = switch function {
            case .sin: -.function(.cos, inner)
            case .cos: .function(.sin, inner)
            case .tan: -.function(.ln, .function(.abs, .function(.cos, inner)))
            case .sinh: .function(.cosh, inner)
            case .cosh: .function(.sinh, inner)
            case .ln: inner * .function(.ln, inner) - inner
            case .sec: .function(.ln, .function(.abs, .function(.sec, inner) + .function(.tan, inner)))
            default: nil
            }
            return result.map { Simplify.run($0 / a) }
        default:
            break
        }
        // 1/(1 + x²) and 1/√(1 − x²)
        if f == .power(.add([.power(variable, .two), .one]), .minusOne) || f == .power(.add([.one, .power(variable, .two)]), .minusOne) {
            return .function(.atan, variable)
        }
        if case .power(let base, let exponent) = f, exponent == .fraction(-1, 2),
           Simplify.run(base) == Simplify.run(.one - .power(variable, .two)) {
            return .function(.asin, variable)
        }
        return nil
    }

    /// ∫ g(u(x)) u′(x) dx = ∫ g(u) du, trying each inner part as u.
    private static func substitution(_ f: Expr, _ x: String, depth: Int) -> (Expr, [Step])? {
        for inner in innerParts(f, x) {
            let du = Simplify.run(derivative(inner, x))
            guard !du.isZero else { continue }
            let ratio = Simplify.run(f / du)
            let u = Expr.symbol("u")
            let inU = Simplify.run(ratio.replacing(inner, with: u))
            guard !inU.contains(x), let (result, _) = integral(inU, "u", depth: depth + 1) else { continue }
            let back = Simplify.run(result.substituting("u", with: inner))
            return (back, [Step("Substitute u = \(Format.text(inner))",
                                "Then du = \(Format.text(du)) d\(x), and the integral becomes one in u.",
                                [MathLine(inU, result, relation: "→"), MathLine(result, back, relation: "→")])])
        }
        return nil
    }

    private static func innerParts(_ f: Expr, _ x: String) -> [Expr] {
        var parts: [Expr] = []
        func visit(_ e: Expr) {
            switch e {
            case .function(_, let argument):
                if argument.contains(x) && argument != .symbol(x) { parts.append(argument) }
                visit(argument)
            case .power(let base, let exponent):
                if base.contains(x) && base != .symbol(x) { parts.append(base) }
                if exponent.contains(x) && exponent != .symbol(x) { parts.append(exponent) }
                visit(base)
                visit(exponent)
            case .add(let items), .multiply(let items):
                items.forEach(visit)
            default:
                break
            }
        }
        visit(f)
        return parts
    }

    /// ∫ u dv = uv − ∫ v du: a polynomial times eˣ, sin or cos; or anything times ln x.
    private static func byParts(_ f: Expr, _ x: String, depth: Int) -> (Expr, [Step])? {
        guard depth < 4, case .multiply(let factors) = f else { return nil }
        let isLog: (Expr) -> Bool = { if case .function(.ln, _) = $0 { true } else { false } }
        let (u, dv): (Expr, Expr)
        if let log = factors.first(where: isLog) {
            u = log
            dv = Simplify.multiply(factors.filter { $0 != log })
        } else {
            let polynomial = factors.filter { Polynomial($0, in: x) != nil && $0.contains(x) }
            guard let p = polynomial.first else { return nil }
            u = p
            dv = Simplify.multiply(factors.filter { $0 != p })
        }
        guard let (v, _) = integral(dv, x, depth: depth + 1) else { return nil }
        let du = Simplify.run(derivative(u, x))
        guard let (rest, _) = integral(Simplify.run(v * du), x, depth: depth + 1) else { return nil }
        let result = Simplify.run(u * v - rest)
        return (Solver.tidiest([result, Simplify.expand(result)]),
                [Step("Integrate by parts", "∫u dv = uv − ∫v du, with u = \(Format.text(u)) and dv = \(Format.text(dv)) d\(x).",
                      [MathLine(.symbol("du"), du), MathLine(.symbol("v"), v), MathLine(Simplify.run(u * v - rest), relation: "")])])
    }

    /// A fraction of polynomials whose bottom has distinct whole-number roots, split up:
    /// 1/((x + 1)(x + 2)) = 1/(x + 1) − 1/(x + 2).
    private static func partialFractions(_ f: Expr, _ x: String) -> (Expr, [Step])? {
        let (top, bottom) = Simplify.numeratorAndDenominator(Simplify.together(f))
        guard bottom.contains(x), let n = Polynomial(top, in: x), let d = Polynomial(Simplify.expand(bottom), in: x),
              d.degree >= 2, n.degree < d.degree else { return nil }
        let roots = d.rationalRoots
        guard roots.count == d.degree else { return nil }
        let derivative = d.derivative
        var terms: [Expr] = []
        for root in roots {
            guard let numerator = n.evaluate(root), let slope = derivative.evaluate(root), let a = numerator / slope else { return nil }
            terms.append(Simplify.run(.number(.exact(a)) / (Expr.symbol(x) - .number(.exact(root)))))
        }
        let split = Simplify.add(terms)
        guard let (result, _) = integral(split, x, depth: 3) else { return nil }
        return (result, [Step("Split into partial fractions", "Write it as a sum of simpler fractions, one for each factor of the bottom.",
                              [MathLine(f, split)]),
                         Step("Integrate each part", "Each 1/(x − a) integrates to ln|x − a|.", [MathLine(split, result, relation: "→")])])
    }

    /// Simpson's rule with many slices.
    private static func simpson(_ f: Expr, _ x: String, _ a: Double, _ b: Double) -> Double? {
        let n = 2000
        let h = (b - a) / Double(n)
        var sum = 0.0
        for i in 0...n {
            guard let value = f.evaluate([x: a + Double(i) * h]) else { return nil }
            sum += value * (i == 0 || i == n ? 1 : (i % 2 == 1 ? 4 : 2))
        }
        return sum * h / 3
    }
}

extension Expr {
    /// Replaces every occurrence of `target`.
    func replacing(_ target: Expr, with replacement: Expr) -> Expr {
        if self == target { return replacement }
        switch self {
        case .add(let parts): return .add(parts.map { $0.replacing(target, with: replacement) })
        case .multiply(let parts):
            // Also a power of the target: x² when replacing x² in x⁴, and so on.
            return .multiply(parts.map { $0.replacing(target, with: replacement) })
        case .power(let base, let exponent):
            if case .power(let tBase, let tExponent) = target, tBase == base,
               let ratio = Simplify.run(exponent / tExponent).number?.integer {
                return .power(replacement, .integer(ratio))
            }
            return .power(base.replacing(target, with: replacement), exponent.replacing(target, with: replacement))
        case .function(let f, let argument): return .function(f, argument.replacing(target, with: replacement))
        default: return self
        }
    }
}
