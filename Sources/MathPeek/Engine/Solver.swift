import Foundation

/// Solves equations, and simultaneous equations, with the working.
enum Solver {
    static func solve(_ equations: [Equation], unknowns: [String], _ problem: Problem) -> Solution? {
        if equations.count == 1 { return single(equations[0], unknowns.first, problem) }
        return system(equations, unknowns, problem)
    }

    // MARK: One equation

    static func single(_ equation: Equation, _ unknown: String?, _ problem: Problem) -> Solution? {
        let question = MathLine(equation.left, equation.right)
        let symbols = equation.left.symbols.union(equation.right.symbols)
        guard let x = unknown ?? Parser.mainVariable(symbols) else {
            // No letters: is it true?
            let left = Simplify.run(equation.left), right = Simplify.run(equation.right)
            guard let l = left.evaluate(), let r = right.evaluate() else { return nil }
            let holds = abs(l - r) < 1e-9 * max(1, abs(l))
            return Solution(problem: problem, question: question, task: "Check",
                            answers: [MathLine(left, right, relation: holds ? "=" : "≠")],
                            steps: [Step("Work out each side", "", [MathLine(left, right, relation: holds ? "=" : "≠")])],
                            note: holds ? "It's true." : "It's false.")
        }
        var steps: [Step] = []
        var expression = Simplify.run(equation.left - equation.right)
        var denominator: Expr = .one
        if Engine.hasSymbolicDenominator(expression), Simplify.together(expression) != expression {
            let together = Simplify.together(expression)
            let (top, bottom) = Simplify.numeratorAndDenominator(together)
            if bottom.contains(x) {
                steps.append(Step("Clear the fractions", "Multiply both sides by \(Format.text(bottom)).",
                                  [MathLine(Simplify.expand(top), .zero)]))
                denominator = bottom
                expression = Simplify.expand(top)
            }
        }
        var outcome: (answers: [Expr], steps: [Step], note: String?, approximate: Bool)?
        if let form = PolynomialForm(expression, in: x), form.coefficients.values.allSatisfy({ !$0.contains(x) }) {
            switch form.degree {
            case 0:
                let always = Simplify.run(form.coefficient(0)).isZero
                return Solution(problem: problem, question: question, task: "Solve for \(x)", answers: [], steps: steps,
                                note: always ? "Every value of \(x) works: both sides are always equal."
                                             : "There's no solution: the two sides can never be equal.")
            case 1:
                outcome = linear(equation, form, x)
            case 2:
                outcome = quadratic(form, x, rearranged: !equation.right.isZero || Simplify.run(equation.left) != equation.left)
            default:
                outcome = higher(form, x)
            }
        } else {
            outcome = isolate(equation, x) ?? numeric(expression, x)
        }
        guard let (found, moreSteps, note, approximate) = outcome else { return nil }
        var answers = found
        steps += moreSteps
        // Values that would divide by zero aren't solutions.
        if !denominator.isOne {
            answers = answers.filter { value in
                guard let d = Simplify.run(denominator.substituting(x, with: value)).evaluate() else { return true }
                return abs(d) > 1e-12
            }
        }
        if !approximate, let check = checkStep(equation, x, answers) { steps.append(check) }
        let lines = answers.map { MathLine(.symbol(x), $0, relation: approximate ? "≈" : "=") }
        var approximation: String?
        if !approximate {
            let decimals = answers.compactMap { value -> String? in
                guard value.number?.rational?.isInteger != true, value.symbols.isEmpty, let v = value.evaluate() else { return nil }
                return "\(x) ≈ " + Format.decimal(v)
            }
            if !decimals.isEmpty { approximation = decimals.joined(separator: " or ") }
        }
        let marks = answers.compactMap { $0.evaluate() }
        return Solution(problem: problem, question: question, task: "Solve for \(x)", answers: lines,
                        approximation: approximation, steps: steps, note: answers.isEmpty ? (note ?? "There are no real solutions.") : note,
                        plot: Engine.plot(of: equation.right.isZero ? [(Format.text(equation.left), equation.left)]
                                                    : [(Format.text(equation.left), equation.left), (Format.text(equation.right), equation.right)],
                                          marks: marks))
    }

    /// ax + b = 0, shown as the moves people make: subtract, then divide.
    private static func linear(_ equation: Equation, _ form: PolynomialForm, _ x: String) -> ([Expr], [Step], String?, Bool) {
        var steps: [Step] = []
        let a = form.coefficient(1), b = form.coefficient(0)
        if Engine.containsBrackets(equation.left) || Engine.containsBrackets(equation.right) {
            steps.append(Step("Expand the brackets", "",
                              [MathLine(Simplify.expand(equation.left), Simplify.expand(equation.right))]))
        }
        let left = PolynomialForm(equation.left, in: x), right = PolynomialForm(equation.right, in: x)
        var moves: [String] = []
        if let right, !right.coefficient(1).isZero {
            moves.append(describe(right.coefficient(1), times: x, side: "from"))
        }
        if let left, !left.coefficient(0).isZero {
            moves.append(describe(left.coefficient(0), times: nil, side: "from"))
        }
        let ax = Simplify.multiply([a, .symbol(x)])
        let minusB = Simplify.run(-b)
        steps.append(Step(moves.isEmpty ? "Collect the \(x) terms" : moves.joined(separator: ", and ").capitalizedFirst,
                          "Get the \(x) terms on one side and the rest on the other.", [MathLine(ax, minusB)]))
        let value = Simplify.run(minusB / a)
        if !a.isOne {
            steps.append(Step("Divide both sides by \(Format.text(a))", "", [MathLine(.symbol(x), value)]))
        }
        return ([value], steps, nil, false)
    }

    /// "Subtract 3 from both sides" or "Add 3 to both sides".
    private static func describe(_ amount: Expr, times x: String?, side: String) -> String {
        let (coefficient, _) = Simplify.splitCoefficient(amount)
        let negative = coefficient.isNegative || amount.number?.isNegative == true
        let size = negative ? Simplify.run(-amount) : amount
        let term = x.map { Format.text(Simplify.multiply([size, .symbol($0)])) } ?? Format.text(size)
        return negative ? "add \(term) to both sides" : "subtract \(term) from both sides"
    }

    private static func quadratic(_ form: PolynomialForm, _ x: String, rearranged: Bool) -> ([Expr], [Step], String?, Bool) {
        var steps: [Step] = []
        let a = form.coefficient(2), b = form.coefficient(1), c = form.coefficient(0)
        let variable = Expr.symbol(x)
        let standard = Simplify.add([Simplify.multiply([a, Simplify.power(variable, .two)]), Simplify.multiply([b, variable]), c])
        if rearranged {
            steps.append(Step("Rearrange to equal zero", "Get everything on one side, in the form ax² + bx + c = 0.",
                              [MathLine(standard, .zero)]))
        }
        if let poly = Polynomial(standard, in: x) {
            // x(ax + b) = 0
            if c.isZero {
                let inner = Simplify.add([Simplify.multiply([a, variable]), b])
                steps.append(Step("Take out \(x) as a common factor", "", [MathLine(.multiply([variable, inner]), .zero)]))
                let other = Simplify.run(-b / a)
                steps.append(Step("Set each factor to zero", "If a product is zero, one of its factors is zero.",
                                  [MathLine(variable, .zero), MathLine(variable, other)]))
                return (sortedValues([.zero, other]), steps, nil, false)
            }
            let roots = poly.rationalRoots
            if !roots.isEmpty {
                let (factors, _, factorSteps) = Engine.factorPolynomial(poly)
                steps += factorSteps.map { step in
                    var step = step
                    step.lines = step.lines.map { MathLine($0.parts[0], .zero) }
                    return step
                }
                let values = roots.map { Expr.number(.exact($0)) }
                steps.append(Step("Set each bracket to zero", "If a product is zero, one of its factors is zero.",
                                  factors.filter { $0.contains(x) }.map { MathLine($0, .zero) }))
                return (values, steps, roots.count == 1 ? "This is a repeated root." : nil, false)
            }
        }
        // The quadratic formula.
        let discriminant = Simplify.run(Simplify.power(b, .two) - Simplify.multiply([.integer(4), a, c]))
        steps.append(Step("Use the quadratic formula",
                          "x = (−b ± √(b² − 4ac)) / 2a, with a = \(Format.text(a)), b = \(Format.text(b)), c = \(Format.text(c)).",
                          []))
        steps.append(Step("Work out the discriminant", "b² − 4ac tells you how many real solutions there are.",
                          [MathLine(.add([.power(b, .two), .multiply([.minusOne, .multiply([.integer(4), a, c])])]), discriminant)]))
        if let d = discriminant.evaluate(), d < 0, discriminant.symbols.isEmpty {
            // Complex roots: −b/2a ± (√|D|/2a) i
            let real = Simplify.run(-b / (.two * a))
            let imaginary = Simplify.run(Simplify.power(Simplify.run(-discriminant), .half) / (.two * a))
            let i = Expr.symbol("i")
            let roots = [Simplify.add([real, Simplify.multiply([imaginary, i])]),
                         Simplify.add([real, Simplify.multiply([Simplify.run(-imaginary), i])])]
            steps.append(Step("The discriminant is negative", "So there are no real solutions. Using i = √−1, the complex solutions are:",
                              roots.map { MathLine(variable, $0) }))
            return ([], steps, "No real solutions. Complex: \(x) = " + roots.map(Format.text).joined(separator: " or "), false)
        }
        let root = Simplify.power(discriminant, .half)
        let values = [Expr.add([-b, root]), Expr.add([-b, -root])].map { top in
            tidiest([Simplify.run(.multiply([top, .power(Simplify.run(.two * a), .minusOne)])),
                     Simplify.expand(top / (.two * a))])
        }
        steps.append(Step("Put the numbers in", "", values.map { MathLine(variable, $0) }))
        if discriminant.isZero { return ([values[0]], steps, "This is a repeated root.", false) }
        return (sortedValues(values), steps, nil, false)
    }

    /// Cubics and above: the factor theorem, then whatever's left.
    private static func higher(_ form: PolynomialForm, _ x: String) -> ([Expr], [Step], String?, Bool)? {
        let standard = Simplify.add((0...form.degree).map { Simplify.multiply([form.coefficient($0), Simplify.power(.symbol(x), .integer($0))]) })
        guard let poly = Polynomial(standard, in: x) else { return nil }
        var steps = [Step("Rearrange to equal zero", "", [MathLine(standard, .zero)])]
        let (factors, remaining, factorSteps) = Engine.factorPolynomial(poly)
        steps += factorSteps
        var values: [Expr] = poly.rationalRoots.map { .number(.exact($0)) }
        var approximate = false
        if remaining.degree == 2, let (more, moreSteps, _, _) = Optional(quadratic(PolynomialForm(remaining.expr, in: x)!, x, rearranged: false)) {
            steps += moreSteps
            values += more
        } else if remaining.degree > 2 {
            let numeric = remaining.realRoots.map { Expr.number(.real($0)) }
            if !numeric.isEmpty {
                steps.append(Step("Find the other roots numerically", "What's left doesn't factorise into nice numbers.",
                                  numeric.map { MathLine(.symbol(x), $0, relation: "≈") }))
                if factors.isEmpty { approximate = true }
                values += numeric
            }
        }
        if !factors.isEmpty {
            steps.append(Step("Set each factor to zero", "", factors.map { MathLine($0, .zero) }))
        }
        return (sortedValues(values), steps, nil, approximate)
    }

    /// Undoes what's been done to the unknown, one move at a time: 2^x = 8, sin x = 0.5,
    /// (x + 1)² = 9, ln x = 2.
    private static func isolate(_ equation: Equation, _ x: String) -> ([Expr], [Step], String?, Bool)? {
        var left = Simplify.run(equation.left), right = Simplify.run(equation.right)
        if !left.contains(x) { swap(&left, &right) }
        guard left.contains(x), !right.contains(x) else { return nil }
        var branches: [Expr] = [right]
        var steps: [Step] = []
        var trigApplied = false
        for _ in 0..<12 {
            if left == .symbol(x) { break }
            switch left {
            case .add(let terms):
                let with = terms.filter { $0.contains(x) }, without = terms.filter { !$0.contains(x) }
                guard with.count == 1 else { return nil }
                let moved = Simplify.add(without)
                branches = branches.map { Simplify.run($0 - moved) }
                left = with[0]
                steps.append(Step(describe(moved, times: nil, side: "from").capitalizedFirst, "",
                                  branches.map { MathLine(left, $0) }))
            case .multiply(let factors):
                let with = factors.filter { $0.contains(x) }, without = factors.filter { !$0.contains(x) }
                guard with.count == 1 else { return nil }
                let divisor = Simplify.multiply(without)
                branches = branches.map { Simplify.run($0 / divisor) }
                left = with[0]
                let isDivision = (divisor.number?.rational.map { !$0.isInteger && $0.numerator == 1 }) ?? false
                let title = isDivision ? "Multiply both sides by \(Format.text(Simplify.run(.one / divisor)))"
                                       : "Divide both sides by \(Format.text(divisor))"
                steps.append(Step(title, "", branches.map { MathLine(left, $0) }))
            case .power(let base, let exponent) where base.contains(x) && !exponent.contains(x):
                let inverse = Simplify.run(.one / exponent)
                if let n = exponent.number?.integer, n % 2 == 0 {
                    branches = branches.flatMap { value -> [Expr] in
                        guard (value.evaluate() ?? 0) >= 0 else { return [] }
                        let root = Simplify.power(value, inverse)
                        return root.isZero ? [root] : [root, Simplify.run(-root)]
                    }
                    steps.append(Step("Take the square root of both sides" + (n == 2 ? "" : " (\(n)th root)"),
                                      "Remember the ± : both the positive and negative roots work.",
                                      branches.map { MathLine(base, $0) }))
                } else {
                    branches = branches.map { Simplify.power($0, inverse) }
                    let title = exponent == .minusOne ? "Flip both sides" : "Raise both sides to the power \(Format.text(inverse))"
                    steps.append(Step(title, "", branches.map { MathLine(base, $0) }))
                }
                left = base
            case .power(let base, let exponent) where exponent.contains(x) && !base.contains(x):
                branches = branches.compactMap { value in
                    guard (value.evaluate() ?? 1) > 0 else { return nil }
                    return logarithm(value, base: base)
                }
                let explanation = base == .constant(.e) ? "ln undoes e^." : "Take logs, then divide by log \(Format.text(base))."
                steps.append(Step("Take logs of both sides", explanation, branches.map { MathLine(exponent, $0) }))
                left = exponent
            case .function(let function, let argument):
                switch function {
                case .ln:
                    branches = branches.map { Simplify.power(.constant(.e), $0) }
                    steps.append(Step("Raise e to both sides", "e^ undoes ln.", branches.map { MathLine(argument, $0) }))
                case .log:
                    branches = branches.map { Simplify.power(.integer(10), $0) }
                    steps.append(Step("Raise 10 to both sides", "10^ undoes log.", branches.map { MathLine(argument, $0) }))
                case .abs:
                    branches = branches.flatMap { [$0, Simplify.run(-$0)] }
                    steps.append(Step("Remove the modulus", "What's inside is either the value or minus it.",
                                      branches.map { MathLine(argument, $0) }))
                case .sin, .cos, .tan:
                    let inverse: MathFunction = function == .sin ? .asin : (function == .cos ? .acos : .atan)
                    let principal = branches.map { Simplify.apply(inverse, $0) }
                    steps.append(Step("Use the inverse \(function.rawValue)", "This gives the principal value.",
                                      principal.map { MathLine(argument, $0) }))
                    trigApplied = true
                    left = argument
                    branches = principal
                    continue
                default:
                    return nil
                }
                left = argument
            default:
                return nil
            }
        }
        guard left == .symbol(x) else { return nil }
        if trigApplied {
            // Every solution in one turn, found from the graph's symmetry and checked numerically.
            let f = Simplify.run(equation.left - equation.right)
            let degrees = MathSettings.angles == .degrees
            let range = degrees ? 0.0...360.0 : 0.0...(2 * Double.pi)
            let values = roots(of: f, x, in: range).filter { $0 < range.upperBound - 1e-9 }.map { exactAngle($0) }
            steps.append(Step("Find every solution from " + (degrees ? "0° to 360°" : "0 to 2π"),
                              "Sine and cosine repeat every 360°, so there are usually two solutions in one turn.",
                              values.map { MathLine(.symbol(x), $0) }))
            return (values, steps, degrees ? "Solutions between 0° and 360°." : "Solutions between 0 and 2π.", false)
        }
        return (sortedValues(branches.map(Simplify.run)), steps, nil, false)
    }

    /// log base `base` of `value`, exactly when it's whole: log₂ 8 = 3.
    private static func logarithm(_ value: Expr, base: Expr) -> Expr {
        if base == .constant(.e) { return Simplify.apply(.ln, value) }
        if let v = value.evaluate(), let b = base.evaluate(), v > 0, b > 0 {
            let exact = Foundation.log(v) / Foundation.log(b)
            if abs(exact - exact.rounded()) < 1e-12 { return .integer(Int(exact.rounded())) }
            if let r = nearbyFraction(exact) { return .number(.exact(r)) }
        }
        return Simplify.run(.function(.ln, value) / .function(.ln, base))
    }

    private static func nearbyFraction(_ value: Double) -> Rational? {
        for denominator in 2...12 {
            let top = (value * Double(denominator)).rounded()
            if abs(top / Double(denominator) - value) < 1e-12 { return Rational.make(Int(top), denominator) }
        }
        return nil
    }

    /// An angle as a nice value if it's close to one: 30, or π/6.
    private static func exactAngle(_ value: Double) -> Expr {
        if MathSettings.angles == .degrees {
            if abs(value - value.rounded()) < 1e-7 { return .integer(Int(value.rounded())) }
            return .number(.real(value))
        }
        if let k = nearbyFraction(value / .pi) ?? (abs(value / .pi - (value / .pi).rounded()) < 1e-9 ? Rational(Int((value / .pi).rounded())) : nil) {
            return Simplify.multiply([.number(.exact(k)), .pi])
        }
        return .number(.real(value))
    }

    /// When nothing else works: where the two sides cross, found numerically.
    private static func numeric(_ f: Expr, _ x: String) -> ([Expr], [Step], String?, Bool)? {
        let range = MathSettings.angles == .degrees && f.containsFunction ? -360.0...360.0 : -100.0...100.0
        let found = roots(of: f, x, in: range)
        let values = found.map { Expr.number(.real($0)) }
        let step = Step("Solve numerically", "This can't be rearranged for \(x), so MathPeek found where both sides are equal, between \(Format.decimal(range.lowerBound)) and \(Format.decimal(range.upperBound)).",
                        values.map { MathLine(.symbol(x), $0, relation: "≈") })
        return (values, [step], values.isEmpty ? "No solutions between \(Format.decimal(range.lowerBound)) and \(Format.decimal(range.upperBound))." : nil, true)
    }

    /// Where `f` is zero in `range`: sign changes, narrowed down by halving.
    static func roots(of f: Expr, _ x: String, in range: ClosedRange<Double>) -> [Double] {
        let samples = 4000
        let width = (range.upperBound - range.lowerBound) / Double(samples)
        func value(_ t: Double) -> Double? { f.evaluate([x: t]) }
        var found: [Double] = []
        var previous: (Double, Double)?
        for i in 0...samples {
            let t = range.lowerBound + Double(i) * width
            guard let v = value(t) else { previous = nil; continue }
            if abs(v) < 1e-12 { found.append(t) }
            if let (pt, pv) = previous, pv * v < 0 {
                var (low, high) = (pt, t)
                for _ in 0..<100 {
                    let middle = (low + high) / 2
                    guard let mv = value(middle) else { break }
                    if mv * pv < 0 { high = middle } else { low = middle }
                }
                let root = (low + high) / 2
                // A jump across an asymptote isn't a root.
                if let rv = value(root), abs(rv) < 1e-6 { found.append(root) }
            }
            previous = (t, v)
        }
        var distinct: [Double] = []
        for root in found.sorted() where !distinct.contains(where: { abs($0 - root) < 1e-7 }) {
            distinct.append(abs(root) < 1e-12 ? 0 : root)
        }
        return distinct
    }

    private static func sortedValues(_ values: [Expr]) -> [Expr] {
        var unique: [Expr] = []
        for value in values where !unique.contains(value) { unique.append(value) }
        return unique.sorted { ($0.evaluate() ?? 0) < ($1.evaluate() ?? 0) }
    }

    /// The shortest way to write it.
    static func tidiest(_ options: [Expr]) -> Expr {
        options.min { Format.text($0).count < Format.text($1).count } ?? options[0]
    }

    /// Puts the answer back into the question.
    private static func checkStep(_ equation: Equation, _ x: String, _ answers: [Expr]) -> Step? {
        guard let value = answers.first, value.number?.rational != nil, answers.count <= 3 else { return nil }
        let left = equation.left.substituting(x, with: value)
        let right = equation.right.substituting(x, with: value)
        guard let l = left.evaluate(), let r = right.evaluate(), abs(l - r) < 1e-6 * max(1, abs(l)) else { return nil }
        let leftValue = Simplify.run(left), rightValue = Simplify.run(right)
        return Step("Check", "Put \(x) = \(Format.text(value)) back in: both sides match.",
                    [MathLine(left, leftValue), MathLine(right, rightValue)])
    }

    // MARK: Simultaneous equations

    private static func system(_ equations: [Equation], _ given: [String], _ problem: Problem) -> Solution? {
        let symbols = equations.reduce(into: Set<String>()) { $0.formUnion($1.left.symbols.union($1.right.symbols)) }
        let unknowns = given.isEmpty ? symbols.sorted { order($0) < order($1) } : given
        guard !unknowns.isEmpty else { return nil }
        let question = MathLine(parts: [], relation: "")
        let labelled = equations.enumerated().map { MathLine($1.left, $1.right) }
        var steps = [Step("Number the equations", "", labelled)]
        steps[0].explanation = labelled.indices.map { "(\($0 + 1))" }.joined(separator: ", ")

        if let (values, moreSteps) = linearSystem(equations, unknowns) {
            steps += moreSteps
            let lines = zip(unknowns, values).map { MathLine(.symbol($0), $1) }
            var solution = Solution(problem: problem, question: question, task: "Solve the simultaneous equations",
                                    answers: lines, steps: steps)
            solution.answerSets = [lines]
            solution.question = MathLine(parts: equations.map { $0.left }, relation: ",")
            solution.question = labelled.first!
            return solution
        }
        // Not linear: rearrange one for a letter and substitute.
        for (index, equation) in equations.enumerated() {
            for variable in unknowns {
                guard let form = PolynomialForm(Simplify.run(equation.left - equation.right), in: variable), form.degree == 1,
                      let coefficient = Optional(form.coefficient(1)), coefficient.symbols.isEmpty else { continue }
                let expression = Simplify.run(-form.coefficient(0) / coefficient)
                steps.append(Step("Rearrange (\(index + 1)) for \(variable)", "", [MathLine(.symbol(variable), expression)]))
                let others = equations.enumerated().filter { $0.offset != index }.map { $0.element }
                let substituted = others.map { Equation(left: Simplify.run($0.left.substituting(variable, with: expression)),
                                                        right: Simplify.run($0.right.substituting(variable, with: expression))) }
                steps.append(Step("Substitute into the other equation", "", substituted.map { MathLine($0.left, $0.right) }))
                let remainingUnknowns = unknowns.filter { $0 != variable }
                guard substituted.count == 1, let first = remainingUnknowns.first,
                      let inner = single(substituted[0], first, problem) else { continue }
                steps += inner.steps.filter { $0.title != "Check" }
                var sets: [[MathLine]] = []
                for answer in inner.answers {
                    guard let value = answer.parts.last else { continue }
                    let back = Simplify.run(expression.substituting(first, with: value))
                    sets.append([MathLine(.symbol(first), value, relation: answer.relation), MathLine(.symbol(variable), back, relation: answer.relation)]
                        .sorted { order(Format.text($0.parts[0])) < order(Format.text($1.parts[0])) })
                }
                if !sets.isEmpty {
                    steps.append(Step("Substitute back", "Find \(variable) for each value of \(first).", sets.flatMap { $0 }))
                }
                var solution = Solution(problem: problem, question: labelled.first!, task: "Solve the simultaneous equations",
                                        answers: sets.flatMap { $0 }, steps: steps,
                                        note: sets.isEmpty ? "There are no real solutions." : nil)
                solution.answerSets = sets
                return solution
            }
        }
        return nil
    }

    private static func order(_ name: String) -> Int {
        ["x": 0, "y": 1, "z": 2][name] ?? 3 + Int(name.unicodeScalars.first?.value ?? 0)
    }

    /// Elimination, with exact fractions. Two unknowns are shown the way it's taught.
    private static func linearSystem(_ equations: [Equation], _ unknowns: [String]) -> ([Expr], [Step])? {
        let n = unknowns.count
        guard equations.count == n else { return nil }
        var matrix: [[Rational]] = []
        for equation in equations {
            let f = Simplify.expand(equation.left - equation.right)
            var row: [Rational] = []
            var rest = f
            for variable in unknowns {
                guard let form = PolynomialForm(rest, in: variable), form.degree <= 1 else { return nil }
                guard case .number(.exact(let c)) = Simplify.run(form.coefficient(1)) else {
                    if form.coefficient(1).isZero { row.append(Rational(0)); rest = form.coefficient(0); continue }
                    return nil
                }
                row.append(c)
                rest = form.coefficient(0)
            }
            guard case .number(.exact(let constant)) = Simplify.run(rest) else { return nil }
            row.append(constant.negated)
            matrix.append(row)
        }
        var steps: [Step] = []
        func line(_ row: [Rational]) -> MathLine {
            let left = Simplify.add(zip(row, unknowns).map { Simplify.multiply([.number(.exact($0)), .symbol($1)]) })
            return MathLine(left, .number(.exact(row[n])))
        }
        if n == 2 {
            let sameForm = matrix.map(line)
            if zip(sameForm, equations).contains(where: { $0.text != MathLine($1.left, $1.right).text }) {
                steps.append(Step("Write them in the same form", "", sameForm))
            }
            // Eliminate the letter whose coefficients are easiest to match.
            let target = abs(matrix[0][1].double) == abs(matrix[1][1].double) && abs(matrix[0][0].double) != abs(matrix[1][0].double) ? 1 : 0
            let keep = 1 - target
            let (p, q) = (matrix[0][target], matrix[1][target])
            guard !p.isZero || !q.isZero else { return nil }
            var top = matrix[0], bottom = matrix[1]
            if !p.isZero && !q.isZero && abs(p.double) != abs(q.double) {
                top = top.compactMap { $0 * q }
                bottom = bottom.compactMap { $0 * p }
                steps.append(Step("Match the \(unknowns[target]) coefficients",
                                  "Multiply (1) by \(Format.number(.exact(q))) and (2) by \(Format.number(.exact(p))).",
                                  [line(top), line(bottom)]))
            }
            let same = top[target] == bottom[target]
            let combined: [Rational] = zip(top, bottom).compactMap { same ? $0 - $1 : $0 + $1 }
            guard combined.count == 3, !combined[keep].isZero else { return nil }
            steps.append(Step((same ? "Subtract" : "Add") + " the equations", "This eliminates \(unknowns[target]).", [line(combined)]))
            guard let keepValue = combined[2] / combined[keep] else { return nil }
            steps.append(Step("Solve for \(unknowns[keep])", "", [MathLine(.symbol(unknowns[keep]), .number(.exact(keepValue)))]))
            // Back into (1), or (2) if (1) has no target term.
            let source = matrix[0][target].isZero ? matrix[1] : matrix[0]
            guard let product = source[keep] * keepValue, let remainder = source[2] - product,
                  let targetValue = remainder / source[target] else { return nil }
            let substituted = Simplify.add([Simplify.multiply([.number(.exact(source[target])), .symbol(unknowns[target])]),
                                            .multiply([.number(.exact(source[keep])), .number(.exact(keepValue))])])
            steps.append(Step("Substitute \(unknowns[keep]) = \(Format.number(.exact(keepValue))) into (\(source == matrix[0] ? 1 : 2))", "",
                              [MathLine(substituted, .number(.exact(source[2]))),
                               MathLine(.symbol(unknowns[target]), .number(.exact(targetValue)))]))
            var values = [Expr](repeating: .zero, count: 2)
            values[target] = .number(.exact(targetValue))
            values[keep] = .number(.exact(keepValue))
            return (values, steps)
        }
        // Gaussian elimination for three or more.
        var m = matrix
        for column in 0..<n {
            guard let pivot = (column..<n).first(where: { !m[$0][column].isZero }) else { return nil }
            m.swapAt(column, pivot)
            for row in 0..<n where row != column && !m[row][column].isZero {
                guard let factor = m[row][column] / m[column][column] else { return nil }
                m[row] = zip(m[row], m[column]).compactMap { a, b in (b * factor).flatMap { a - $0 } }
                guard m[row].count == n + 1 else { return nil }
            }
            steps.append(Step("Eliminate \(unknowns[column]) from the other equations", "", m.map(line)))
        }
        let values = (0..<n).compactMap { m[$0][n] / m[$0][$0] }.map { Expr.number(.exact($0)) }
        guard values.count == n else { return nil }
        return (values, steps)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
