import Foundation

/// Works problems out exactly, with the working a teacher would show.
enum Engine {
    static func solve(_ problem: Problem, angles: AngleUnit) -> Solution? {
        MathSettings.$angles.withValue(problem.angles ?? angles) {
            switch problem.kind {
            case .evaluate(let expr): evaluate(expr, problem)
            case .simplify(let expr): simplify(expr, problem)
            case .expand(let expr): expand(expr, problem)
            case .factorise(let expr): factorise(expr, problem)
            case .substitute(let expr, let values): substitute(expr, values, problem)
            case .solve(let equations, let unknowns): Solver.solve(equations, unknowns: unknowns, problem)
            case .differentiate(let expr, let variable, let order):
                MathSettings.$angles.withValue(.radians) { Calculus.differentiate(expr, variable, order: order, problem) }
            case .integrate(let expr, let variable, let from, let to):
                MathSettings.$angles.withValue(.radians) { Calculus.integrate(expr, variable, from: from, to: to, problem) }
            }
        }
    }

    // MARK: Arithmetic

    static func evaluate(_ expr: Expr, _ problem: Problem) -> Solution? {
        // Adding fractions is shown with a common denominator.
        if !problem.usesDecimals, let fractions = fractionSteps(expr) {
            let (answer, approximation) = presentNumber(fractions.result, decimals: false)
            return Solution(problem: problem, question: MathLine(expr), task: "Work out", answers: [MathLine(answer)],
                            approximation: approximation, steps: fractions.steps)
        }
        let (steps, value) = orderOfOperations(expr, decimals: problem.usesDecimals)
        guard let value else {
            return Solution(problem: problem, question: MathLine(expr), task: "Work out", answers: [],
                            steps: steps, note: undefinedReason(expr))
        }
        let (answer, approximation) = presentNumber(value, decimals: problem.usesDecimals)
        var note: String?
        if let written = problem.writtenAnswer, let expected = written.evaluate(), let actual = value.evaluate() {
            note = abs(expected - actual) < 1e-9 * max(1, abs(actual))
                ? "It says = \(Format.text(written)): that's right."
                : "It says = \(Format.text(written)), but the answer is \(Format.text(answer))."
        }
        return Solution(problem: problem, question: MathLine(expr), task: "Work out", answers: [MathLine(answer)],
                        approximation: approximation, steps: steps.count > 1 ? steps : [], note: note)
    }

    /// Why a sum has no answer.
    static func undefinedReason(_ expr: Expr) -> String {
        if case .multiply(let factors) = expr, factors.contains(where: {
            if case .power(let base, let e) = $0, e.number?.isNegative == true, Simplify.run(base).isZero { return true }
            return false
        }) { return "Can't divide by zero." }
        return "This has no real answer."
    }

    /// An exact answer, or a decimal if the question used decimals; and a decimal
    /// approximation of an exact fraction or surd.
    static func presentNumber(_ value: Expr, decimals: Bool) -> (Expr, String?) {
        guard let double = value.evaluate() else { return (value, nil) }
        if case .number(.exact(let rational)) = value {
            if rational.isInteger { return (value, nil) }
            if decimals { return (.number(.real(double)), nil) }
            return (value, "≈ " + Format.decimal(double))
        }
        if case .number = value { return (value, nil) }
        if decimals { return (.number(.real(double)), nil) }
        // A surd or π: keep it exact, with its value.
        return (value, "≈ " + Format.decimal(double))
    }

    /// Works a sum out the way it's taught: the innermost operations first, a line per round.
    static func orderOfOperations(_ expr: Expr, decimals: Bool = false) -> ([Step], Expr?) {
        var current = expr
        var steps: [Step] = []
        for _ in 0..<12 {
            if isValue(current) { break }
            guard let (next, title, explanation) = reduceOnce(current, decimals: decimals) else { return (steps, nil) }
            if next == current { break }
            // A round that only rewrites (1 ÷ 3 as 1/3) isn't worth a line.
            if Format.text(next) != Format.text(current) {
                steps.append(Step(title, explanation, [MathLine(next)]))
            }
            current = next
        }
        let value = Simplify.run(current)
        return (steps, value.evaluate() != nil ? value : nil)
    }

    /// A number as written: 3, −3, 1/2.
    private static func isValue(_ expr: Expr) -> Bool {
        switch expr {
        case .number: true
        case .multiply(let factors): factors.count == 2 && factors[0] == .minusOne && factors[1].number != nil
        default: false
        }
    }

    /// Works out every operation whose parts are already numbers, in one round. Nil if
    /// something can't be worked out (dividing by zero).
    private static func reduceOnce(_ expr: Expr, decimals: Bool) -> (Expr, String, String)? {
        var kinds = Set<String>()
        var failed = false
        func reduce(_ e: Expr, insideBrackets: Bool) -> Expr {
            if isValue(e) { return e }
            let children: [Expr]
            switch e {
            case .add(let parts), .multiply(let parts): children = parts
            case .power(let b, let x): children = [b, x]
            case .function(_, let a): children = [a]
            default: return e
            }
            // Division by a number is part of its multiplication.
            let ready = children.allSatisfy { child in
                if isValue(child) { return true }
                if case .power(let b, let x) = child, isValue(b), x == .minusOne { return true }
                return false
            }
            if ready {
                let value = Simplify.run(e)
                guard value.number != nil || value.evaluate() != nil else { failed = true; return e }
                switch e {
                case .add: kinds.insert(insideBrackets ? "brackets" : "add")
                case .multiply: kinds.insert(insideBrackets ? "brackets" : "multiply")
                case .power: kinds.insert("power")
                default: kinds.insert("function")
                }
                guard let v = value.evaluate() else { return value }
                if decimals, case .number(.exact(let r)) = value, !r.isInteger { return .number(.real(v)) }
                // Surds and logs stay exact unless the question used decimals.
                return value.number != nil || !decimals ? value : .number(.real(v))
            }
            let isProduct: Bool = if case .multiply = e { true } else if case .power = e { true } else if case .function = e { true } else { false }
            switch e {
            case .add(let parts): return .add(parts.map { reduce($0, insideBrackets: insideBrackets) })
            case .multiply(let parts): return .multiply(parts.map { reduce($0, insideBrackets: isProduct) })
            case .power(let b, let x): return .power(reduce(b, insideBrackets: true), reduce(x, insideBrackets: true))
            case .function(let f, let a): return .function(f, reduce(a, insideBrackets: true))
            default: return e
            }
        }
        let next = reduce(expr, insideBrackets: false)
        guard !failed else { return nil }
        guard next != expr else { return (expr, "", "") }
        let (title, explanation): (String, String) =
            if kinds.contains("brackets") { ("Brackets first", "Work out what's inside the brackets.") }
            else if kinds.contains("power") || kinds.contains("function") { ("Powers and roots", "These come before ×, ÷, + and −.") }
            else if kinds.contains("multiply") { ("Multiply and divide", "× and ÷ come before + and −.") }
            else { ("Add and subtract", "Left to right.") }
        return (next, title, explanation)
    }

    // MARK: Algebra

    static func simplify(_ expr: Expr, _ problem: Problem) -> Solution? {
        var steps: [Step] = []
        let simplified = Simplify.run(expr)
        let result: Expr
        if let fractionSteps = fractionSteps(expr) {
            steps = fractionSteps.steps
            result = fractionSteps.result
        } else if hasSymbolicDenominator(simplified) {
            let together = Simplify.together(expr)
            steps.append(Step("Use a common denominator", "Write everything as one fraction, then multiply out the top.",
                              [MathLine(together)]))
            result = together
        } else {
            let expanded = Simplify.expand(expr)
            if containsBrackets(expr), Format.text(expanded).count < 3 * max(Format.text(simplified).count, 12) {
                steps.append(Step("Expand the brackets", "Multiply each term inside by what's outside.",
                                  [MathLine(expandedUncollected(expr))]))
                if expanded != expandedUncollected(expr) {
                    steps.append(Step("Collect like terms", "Add up the terms with the same letters and powers.",
                                      [MathLine(expanded)]))
                }
                result = expanded
            } else {
                if simplified != expr, termCount(expr) > termCount(simplified) {
                    steps.append(Step("Collect like terms", "Add up the terms with the same letters and powers.",
                                      [MathLine(simplified)]))
                }
                result = simplified
            }
        }
        let decimals = result.symbols.isEmpty ? presentNumber(result, decimals: problem.usesDecimals).1 : nil
        return Solution(problem: problem, question: MathLine(expr), task: "Simplify", answers: [MathLine(result)],
                        approximation: decimals, steps: steps, plot: plot(of: [("y", result)]))
    }

    /// Adding fractions with number denominators, the way it's taught: h/6 + 2h/9 over 18.
    private static func fractionSteps(_ expr: Expr) -> (steps: [Step], result: Expr)? {
        guard case .add(let rawTerms) = expr else { return nil }
        let terms = rawTerms.map(Simplify.run)
        var parts: [(sign: Int, top: Expr, bottom: Int)] = []
        for term in terms {
            let (coefficient, rest) = Simplify.splitCoefficient(term)
            if case .number(let n) = term, let r = n.rational {
                parts.append((r.numerator < 0 ? -1 : 1, .integer(abs(r.numerator)), r.denominator))
                continue
            }
            guard let r = coefficient.rational else { return nil }
            let (restTop, restBottom) = Simplify.numeratorAndDenominator(rest)
            guard restBottom.isOne else { return nil }
            parts.append((r.numerator < 0 ? -1 : 1, Simplify.multiply([.integer(abs(r.numerator)), restTop]), r.denominator))
        }
        let denominators = Set(parts.map(\.bottom))
        guard parts.count >= 2, denominators.contains(where: { $0 > 1 }), denominators.count > 1 || parts.contains(where: { $0.bottom > 1 }) else { return nil }
        var common = 1
        for part in parts {
            guard let next = Rational.lcm(common, part.bottom) else { return nil }
            common = next
        }
        func fraction(_ top: Expr, _ bottom: Int) -> Expr { .multiply([top, .power(.integer(bottom), .minusOne)]) }
        func signed(_ sign: Int, _ e: Expr) -> Expr { sign < 0 ? .multiply([.minusOne, e]) : e }
        var steps: [Step] = []
        let rewritten = parts.map { part -> (Expr, Expr) in
            let factor = common / part.bottom
            let newTop = Simplify.multiply([.integer(factor), part.top])
            return (fraction(part.top, part.bottom), fraction(newTop, common))
        }
        if denominators.count > 1 || denominators.first != common {
            let list = parts.map(\.bottom).filter { $0 > 1 }.map(String.init).joined(separator: " and ")
            steps.append(Step("Find a common denominator",
                              "The lowest common multiple of \(list) is \(common)."))
            steps.append(Step("Rewrite each fraction over \(common)",
                              "Multiply the top and bottom of each by the same number.",
                              rewritten.filter { $0.0 != $0.1 }.map { MathLine($0.0, $0.1) }))
        }
        var newTops: [Expr] = []
        var newFractions: [Expr] = []
        for (part, pair) in zip(parts, rewritten) {
            let newFraction: Expr = pair.1
            if case .multiply(let f) = newFraction { newTops.append(signed(part.sign, f[0])) } else { newTops.append(part.top) }
            newFractions.append(signed(part.sign, newFraction))
        }
        let added = Simplify.run(.add(newTops))
        steps.append(Step("Add the numerators", "The denominator stays the same.",
                          [MathLine(.add(newFractions), fraction(added, common))]))
        let result = Simplify.run(fraction(added, common))
        if result != Simplify.run(.multiply([added, .power(.integer(common), .minusOne)])) || hasCommonFactor(added, common) {
            steps.append(Step("Simplify", "Cancel any common factor of the top and bottom.", [MathLine(result)]))
        }
        return (steps, result)
    }

    private static func hasCommonFactor(_ top: Expr, _ bottom: Int) -> Bool {
        let (coefficient, _) = Simplify.splitCoefficient(top)
        guard let n = coefficient.integer else { return false }
        return Rational.gcd(abs(n), bottom) > 1
    }

    static func hasSymbolicDenominator(_ expr: Expr) -> Bool {
        switch expr {
        case .power(let base, let exponent): !base.symbols.isEmpty && (exponent.number?.isNegative ?? false)
        case .add(let parts), .multiply(let parts): parts.contains(where: hasSymbolicDenominator)
        default: false
        }
    }

    static func containsBrackets(_ expr: Expr) -> Bool {
        switch expr {
        case .multiply(let parts): parts.contains { if case .add = $0 { true } else { containsBrackets($0) } }
        case .power(let base, let exponent):
            if case .add = base, let n = exponent.number?.integer, n > 1 { true } else { false }
        case .add(let parts): parts.contains(where: containsBrackets)
        default: false
        }
    }

    private static func termCount(_ expr: Expr) -> Int {
        if case .add(let parts) = expr { return parts.count }
        return 1
    }

    /// Brackets multiplied out but like terms not yet collected, to show that step.
    static func expandedUncollected(_ expr: Expr) -> Expr {
        func products(_ e: Expr) -> [Expr] {
            switch e {
            case .add(let parts): return parts.flatMap(products)
            case .multiply(let factors):
                var terms: [Expr] = [.one]
                for factor in factors {
                    let pieces = products(factor)
                    terms = terms.flatMap { t in pieces.map { Simplify.multiply([t, $0]) } }
                }
                return terms
            case .power(let base, let exponent):
                if case .add = base, let n = exponent.number?.integer, n > 1, n <= 6 {
                    return products(.multiply(Array(repeating: base, count: n)))
                }
                return [Simplify.run(e)]
            default:
                return [Simplify.run(e)]
            }
        }
        let terms = products(expr)
        return terms.count == 1 ? terms[0] : .add(terms)
    }

    static func expand(_ expr: Expr, _ problem: Problem) -> Solution? {
        var steps: [Step] = []
        let uncollected = expandedUncollected(expr)
        let result = Simplify.expand(expr)
        if case .power(let base, let exponent) = expr, case .add = base, let n = exponent.number?.integer, n > 1, n <= 4 {
            steps.append(Step("Write out the power", "A power of a bracket is the bracket multiplied by itself.",
                              [MathLine(.multiply(Array(repeating: base, count: n)))]))
        }
        steps.append(Step("Multiply out", "Multiply every term in one bracket by every term in the other.",
                          [MathLine(uncollected)]))
        if uncollected != result {
            steps.append(Step("Collect like terms", "Add up the terms with the same letters and powers.", [MathLine(result)]))
        }
        return Solution(problem: problem, question: MathLine(expr), task: "Expand", answers: [MathLine(result)],
                        steps: steps, plot: plot(of: [("y", result)]))
    }

    static func factorise(_ expr: Expr, _ problem: Problem) -> Solution? {
        let expanded = Simplify.expand(expr)
        var steps: [Step] = []
        let (common, rest) = commonFactor(expanded)
        var factors: [Expr] = []
        if !common.isOne {
            steps.append(Step("Take out the common factor", "Every term is a multiple of \(Format.text(common)).",
                              [MathLine(.multiply([common, rest]))]))
            factors.append(common)
        }
        let symbols = rest.symbols
        if symbols.count == 1, let variable = symbols.first, let poly = Polynomial(rest, in: variable), poly.degree >= 2 {
            let (linear, remaining, polySteps) = factorPolynomial(poly)
            steps += polySteps
            factors += linear
            if !(remaining.degree == 0 && remaining.coefficient(0) == Rational(1)) { factors.append(remaining.expr) }
        } else {
            factors.append(rest)
        }
        let result = Simplify.multiply(factors.filter { !$0.isOne }.isEmpty ? [.one] : factors.filter { !$0.isOne })
        let display: Expr = factors.count > 1 ? .multiply(factors) : result
        if steps.isEmpty { steps.append(Step("It doesn't factorise", "There's no common factor, and no whole-number roots.")) }
        return Solution(problem: problem, question: MathLine(expr), task: "Factorise", answers: [MathLine(display)],
                        steps: steps, plot: plot(of: [("y", expanded)]))
    }

    /// The largest number and power of each letter that divides every term: 6x² + 9x = 3x(2x + 3).
    static func commonFactor(_ expr: Expr) -> (Expr, Expr) {
        let terms: [Expr] = if case .add(let parts) = expr { parts } else { [expr] }
        guard terms.count > 1 else { return (.one, expr) }
        var numeric: Int?
        var lowest: [String: Int]?
        for term in terms {
            let (coefficient, rest) = Simplify.splitCoefficient(term)
            guard let n = coefficient.integer else { return (.one, expr) }
            numeric = numeric.map { Rational.gcd($0, abs(n)) } ?? abs(n)
            var powers: [String: Int] = [:]
            let factors: [Expr] = if case .multiply(let parts) = rest { parts } else { [rest] }
            for factor in factors {
                if case .symbol(let name) = factor { powers[name, default: 0] += 1 }
                if case .power(.symbol(let name), let e) = factor, let k = e.number?.integer, k > 0 { powers[name, default: 0] += k }
            }
            if let current = lowest {
                lowest = current.reduce(into: [:]) { result, entry in
                    if let k = powers[entry.key] { result[entry.key] = min(entry.value, k) }
                }
            } else {
                lowest = powers
            }
        }
        // Take out a minus sign if the first term is negative.
        let firstNegative = Simplify.splitCoefficient(terms[0]).0.isNegative
        var common: [Expr] = [.integer((numeric ?? 1) * (firstNegative ? -1 : 1))]
        for (name, k) in (lowest ?? [:]).sorted(by: { $0.key < $1.key }) where k > 0 {
            common.append(Simplify.power(.symbol(name), .integer(k)))
        }
        let factor = Simplify.multiply(common)
        guard !factor.isOne else { return (.one, expr) }
        return (factor, Simplify.expand(Simplify.run(expr / factor)))
    }

    /// Splits a polynomial into linear factors from its fraction roots (the factor theorem),
    /// with what's left over.
    static func factorPolynomial(_ poly: Polynomial) -> ([Expr], Polynomial, [Step]) {
        var remaining = poly
        var factors: [Expr] = []
        var steps: [Step] = []
        let x = Expr.symbol(poly.variable)
        if poly.degree == 2 {
            let (a, b, c) = (poly.coefficient(2), poly.coefficient(1), poly.coefficient(0))
            let roots = poly.rationalRoots
            if !roots.isEmpty, let ac = a * c {
                let explanation = a == Rational(1)
                    ? "Find two numbers that multiply to \(Format.number(.exact(c))) and add to \(Format.number(.exact(b)))."
                    : "Find two numbers that multiply to a × c = \(Format.number(.exact(ac))) and add to b = \(Format.number(.exact(b)))."
                var pair: [Expr] = []
                for root in (roots.count == 1 ? [roots[0], roots[0]] : roots) {
                    // (qx − p) for the root p/q
                    pair.append(Simplify.run(.add([.multiply([.integer(root.denominator), x]), .integer(-root.numerator)])))
                }
                let scale = (a / Rational(roots.count == 1 ? roots[0].denominator * roots[0].denominator : roots.map(\.denominator).reduce(1, *))) ?? Rational(1)
                factors = (scale == Rational(1) ? [] : [Expr.number(.exact(scale))]) + pair
                steps.append(Step("Factorise", explanation, [MathLine(.multiply(factors))]))
                return (factors, Polynomial([Rational(1)], variable: poly.variable), steps)
            }
            return ([], poly, steps)
        }
        for root in poly.rationalRoots {
            // Down to a quadratic; that's factorised the usual way.
            guard remaining.degree > 2 else { break }
            let linear = Polynomial([root.negated, Rational(1)], variable: poly.variable)
            guard let (quotient, remainder) = remaining.divided(by: linear), remainder.isZero else { continue }
            steps.append(Step("Use the factor theorem",
                              "f(\(Format.number(.exact(root)))) = 0, so (\(Format.text(linear.expr))) is a factor.",
                              [MathLine(.multiply([linear.expr, quotient.expr]))]))
            factors.append(linear.expr)
            remaining = quotient
        }
        if remaining.degree == 2, let (more, rest, moreSteps) = Optional(factorPolynomial(remaining)), !more.isEmpty {
            let all = factors + more
            var finalSteps = steps + moreSteps
            if poly.degree > 2 {
                finalSteps.append(Step("Put the factors together", "It's now written fully as brackets multiplied together.",
                                       [MathLine(.multiply(all))]))
            }
            return (all, rest, finalSteps)
        }
        return (factors, remaining, steps)
    }

    static func substitute(_ expr: Expr, _ values: [String: Expr], _ problem: Problem) -> Solution? {
        var substituted = expr
        for (name, value) in values { substituted = substituted.substituting(name, with: value) }
        let assignment = values.sorted { $0.key < $1.key }.map { "\($0.key) = \(Format.text($0.value))" }.joined(separator: ", ")
        var steps = [Step("Substitute", "Put \(assignment) into the formula.", [MathLine(substituted)])]
        let (more, value) = orderOfOperations(substituted)
        steps += more
        guard let value else {
            return Solution(problem: problem, question: MathLine(expr), task: "Substitute", answers: [], steps: steps,
                            note: undefinedReason(substituted))
        }
        let (answer, approximation) = presentNumber(value, decimals: problem.usesDecimals)
        return Solution(problem: problem, question: MathLine(expr), task: "Find the value when \(assignment)",
                        answers: [MathLine(answer)], approximation: approximation, steps: steps)
    }

    // MARK: Graphs

    /// A graph of expressions in one letter, if they have one.
    static func plot(of functions: [(String, Expr)], marks: [Double] = []) -> Plot? {
        let symbols = functions.reduce(into: Set<String>()) { $0.formUnion($1.1.symbols) }
        guard symbols.count == 1, let variable = symbols.first else { return nil }
        // Around the answers, with room either side; otherwise the middle of the axes.
        let half: Double
        let center: Double
        if let low = marks.min(), let high = marks.max() {
            center = (low + high) / 2
            half = marks.count > 1 ? max((high - low) * 0.9 + 1.5, 3) : max(abs(center) * 0.6, 5)
        } else {
            center = 0
            half = 10
        }
        let usesDegrees = MathSettings.angles == .degrees && functions.contains { $0.1.containsFunction }
        let range = usesDegrees ? -360.0...360.0 : (center - half)...(center + half)
        return Plot(functions: functions.map { (label: $0.0, expr: $0.1) }, variable: variable, marks: marks, range: range)
    }
}
