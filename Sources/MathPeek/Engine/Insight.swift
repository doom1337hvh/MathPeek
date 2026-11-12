import Foundation

/// A look inside a problem: what kind of problem it is, and each of its parts.
struct Anatomy: Sendable {
    struct Part: Sendable, Hashable {
        var expr: Expr
        var name: String
        var detail: String
    }

    var kind: String
    var summary: String
    var parts: [Part]
}

/// One answer put back into the question.
struct AnswerCheck: Sendable {
    var answer: String
    var lines: [MathLine]
    var holds: Bool
}

/// The learning side of a solution: the problem taken apart, why each step works and the
/// mistake to avoid there, and each answer checked.
enum Insight {
    // MARK: The problem taken apart

    static func anatomy(of problem: Problem) -> Anatomy {
        switch problem.kind {
        case .evaluate(let expr):
            return Anatomy(kind: "Arithmetic",
                           summary: "Work it out in order: brackets, then powers, then × and ÷, then + and −.",
                           parts: terms(expr).map { part($0, nil) })
        case .simplify(let expr):
            let hasFractions = Engine.hasSymbolicDenominator(expr) || terms(expr).contains { Simplify.numeratorAndDenominator(Simplify.run($0)).1 != .one }
            return Anatomy(kind: hasFractions ? "Algebraic fractions" : "Algebraic expression",
                           summary: hasFractions ? "Combine the fractions into one, over a common denominator."
                                                 : "Write it with as few terms as possible: expand any brackets and collect like terms.",
                           parts: terms(expr).map { part($0, Parser.mainVariable(expr.symbols)) })
        case .expand(let expr):
            let factors: [Expr] = if case .multiply(let parts) = expr { parts } else { [expr] }
            return Anatomy(kind: "Brackets to multiply out",
                           summary: "Multiply every term in one bracket by every term in the other, then collect like terms.",
                           parts: factors.enumerated().map { index, factor in
                               Anatomy.Part(expr: factor, name: "Factor \(index + 1)",
                                            detail: factor.isBracket ? "A bracket with \(terms(factor).count) terms." : "Multiplies everything in the brackets.")
                           })
        case .factorise(let expr):
            let x = Parser.mainVariable(expr.symbols)
            let degree = x.flatMap { PolynomialForm(expr, in: $0)?.degree } ?? 0
            return Anatomy(kind: degree > 0 ? "Polynomial of degree \(degree)" : "Expression to factorise",
                           summary: "Write it as things multiplied together: first any common factor, then brackets.",
                           parts: terms(expr).map { part($0, x) })
        case .solve(let equations, let unknowns):
            if equations.count > 1 {
                let symbols = equations.reduce(into: Set<String>()) { $0.formUnion($1.left.symbols.union($1.right.symbols)) }
                let names = (unknowns.isEmpty ? symbols.sorted() : unknowns).joined(separator: " and ")
                return Anatomy(kind: "Simultaneous equations in \(names)",
                               summary: "Find the values that make every equation true at the same time.",
                               parts: equations.enumerated().map { index, equation in
                                   Anatomy.Part(expr: Simplify.run(equation.left - equation.right),
                                                name: "Equation (\(index + 1))",
                                                detail: "\(Format.text(equation.left)) = \(Format.text(equation.right)). " + equationKind(equation, symbols))
                               })
            }
            let equation = equations[0]
            let x = unknowns.first ?? Parser.mainVariable(equation.left.symbols.union(equation.right.symbols)) ?? "x"
            let (kind, summary) = equationKind(equation, x)
            let left = terms(equation.left).map { part($0, x, side: "left") }
            let right = Simplify.run(equation.right).isZero ? [] : terms(equation.right).map { part($0, x, side: "right") }
            return Anatomy(kind: kind, summary: summary, parts: left + right)
        case .differentiate(let expr, let x, let order):
            return Anatomy(kind: order == 2 ? "Second derivative" : "Differentiation",
                           summary: "Find how fast it changes as \(x) changes: the gradient of its graph at any point.",
                           parts: terms(expr).map { term in
                               var piece = part(term, x)
                               piece.detail += " " + derivativeRule(term, x)
                               return piece
                           })
        case .integrate(let expr, let x, let from, let to):
            let definite = from != nil && to != nil
            return Anatomy(kind: definite ? "Definite integral" : "Integration",
                           summary: definite ? "Find the area under the curve between \(Format.text(from!)) and \(Format.text(to!)) (areas below the axis count as negative)."
                                             : "Find a function whose derivative is this. Any constant can be added, so the answer ends with + C.",
                           parts: terms(expr).map { part($0, x) })
        case .substitute(let expr, let values):
            let given = values.sorted { $0.key < $1.key }.map {
                Anatomy.Part(expr: .symbol($0.key), name: "\($0.key) = \(Format.text($0.value))", detail: "Put \(Format.text($0.value)) wherever \($0.key) appears.")
            }
            return Anatomy(kind: "Substitution",
                           summary: "Replace each letter with its value, then work it out in order.",
                           parts: given + terms(expr).map { part($0, nil) })
        case .sequence:
            return Anatomy(kind: "Sequence", summary: "Find the rule that gives every term from its position, n.", parts: [])
        case .diagram(.circle(let diagram), _):
            let hasCircle = diagram.points.contains { $0.place == .onCircle || $0.place == .centre }
            return Anatomy(kind: hasCircle ? "Circle diagram" : "Angle diagram",
                           summary: hasCircle ? "Work from the angles that are given, one fact about circles at a time." : "Work from the angles that are given, one fact at a time.", parts: [])
        case .worded:
            return Anatomy(kind: "Question in words", summary: "Turn the words into sums, one step at a time.", parts: [])
        case .diagram(.triangle, _):
            return Anatomy(kind: "Triangle", summary: "Work from the sides and angles that are given to the one that's wanted.", parts: [])
        case .remainder(let expr, let modulus):
            return Anatomy(kind: "Remainder",
                           summary: "Find what's left over after dividing by \(modulus), without working out the big numbers.",
                           parts: terms(expr).map { term in
                               if case .power(let base, let exponent) = term, let power = exponent.number?.integer, power > 20 {
                                   return Anatomy.Part(expr: term, name: "Power",
                                                       detail: "\(Format.text(base)) multiplied by itself \(power) times. Far too big to work out, but its remainders repeat.")
                               }
                               return part(term, nil)
                           })
        }
    }

    /// What one part of some working is: a term, or a bracket in a product.
    static func describe(_ expr: Expr, variable x: String?) -> (name: String, detail: String) {
        if case .add = expr {
            let count = terms(expr).count
            if let x, let form = PolynomialForm(expr, in: x), form.degree == 1, form.coefficient(1).symbols.isEmpty {
                let root = Simplify.run(.multiply([.minusOne, form.coefficient(0), .power(form.coefficient(1), .minusOne)]))
                return ("Bracket", "A factor with \(count) terms. It's zero when \(x) = \(Format.text(root)).")
            }
            return ("Bracket", "\(count) terms, treated as one thing.")
        }
        if case .power(let base, let exponent) = expr, case .add = base {
            return ("Bracket to a power", "\(Format.text(base)) multiplied by itself, \(Format.text(exponent)) times over.")
        }
        if case .symbol(let name) = expr {
            return name == x ? ("Unknown", "The value being looked for.") : ("Letter", "Stands for a number.")
        }
        let described = part(expr, x)
        return (described.name, described.detail)
    }

    /// The terms as written, however the sum was built up.
    private static func terms(_ expr: Expr) -> [Expr] {
        if case .add(let parts) = expr { return parts.flatMap(terms) }
        return [expr]
    }

    private static func equationKind(_ equation: Equation, _ x: String) -> (String, String) {
        let f = Simplify.run(equation.left - equation.right)
        if let form = PolynomialForm(f, in: x), form.coefficients.values.allSatisfy({ !$0.contains(x) }) {
            let names = [1: "Linear", 2: "Quadratic", 3: "Cubic", 4: "Quartic"]
            let name = names[form.degree].map { "\($0) equation in \(x)" } ?? "Polynomial equation of degree \(form.degree)"
            let most = form.degree == 1 ? "one solution" : "at most \(form.degree) real solutions"
            return (name, "Find every value of \(x) that makes both sides equal. A \(name.lowercased().components(separatedBy: " equation").first ?? "") equation has \(most).")
        }
        let trig: Set<MathFunction> = [.sin, .cos, .tan]
        if f.functions.contains(where: trig.contains) {
            return ("Trigonometric equation in \(x)", "Find every angle that makes both sides equal. Sine and cosine repeat, so there's usually more than one.")
        }
        if f.functions.contains(.abs) {
            return ("Equation with a modulus", "|A| = b means A = b or A = −b, so there are usually two solutions.")
        }
        if f.hasVariableExponent(x) {
            return ("Exponential equation in \(x)", "The unknown is in a power, so logarithms bring it down.")
        }
        if f.functions.contains(.ln) || f.functions.contains(.log) {
            return ("Logarithmic equation in \(x)", "Raise both sides to undo the logarithm.")
        }
        return ("Equation in \(x)", "Find every value of \(x) that makes both sides equal.")
    }

    private static func equationKind(_ equation: Equation, _ symbols: Set<String>) -> String {
        let f = Simplify.expand(equation.left - equation.right)
        let degree = symbols.compactMap { PolynomialForm(f, in: $0)?.degree }.max() ?? 0
        return degree <= 1 ? "Linear." : (degree == 2 ? "Quadratic." : "Degree \(degree).")
    }

    /// What one term is: "Squared term: −6x², coefficient −6."
    private static func part(_ term: Expr, _ x: String?, side: String? = nil) -> Anatomy.Part {
        let simplified = Simplify.run(term)
        let place = side.map { " On the \($0)-hand side." } ?? ""
        let text = Format.text(simplified)
        if simplified.symbols.isEmpty {
            if case .number(.exact(let r)) = simplified, !r.isInteger {
                return Anatomy.Part(expr: term, name: "Fraction",
                                    detail: "\(abs(r.numerator)) over \(r.denominator): \(abs(r.numerator)) parts of size 1/\(r.denominator)." + place)
            }
            if case .multiply = term, Simplify.numeratorAndDenominator(term).1 != .one {
                return Anatomy.Part(expr: term, name: "Fraction", detail: "\(text), a number divided by another." + place)
            }
            if term.containsFunction {
                return Anatomy.Part(expr: term, name: "Function of a number", detail: "\(Format.text(term)) is worth \(text)." + place)
            }
            return Anatomy.Part(expr: term, name: "Constant", detail: "A plain number, \(text)." + place)
        }
        let (top, bottom) = Simplify.numeratorAndDenominator(simplified)
        if !bottom.isOne {
            if let x, bottom.contains(x) {
                return Anatomy.Part(expr: term, name: "Fraction with \(x) on the bottom",
                                    detail: "\(Format.text(top)) over \(Format.text(bottom)). \(x) can't make the bottom zero." + place)
            }
            return Anatomy.Part(expr: term, name: "Algebraic fraction",
                                detail: "\(Format.text(top)) over \(Format.text(bottom)). The denominator is \(Format.text(bottom))." + place)
        }
        if case .function(let function, let argument) = Simplify.splitCoefficient(simplified).1 {
            let names: [MathFunction: String] = [.sin: "sine", .cos: "cosine", .tan: "tangent", .ln: "natural log", .log: "log base 10", .abs: "modulus"]
            return Anatomy.Part(expr: term, name: (names[function] ?? Format.functionName(function)).capitalizedFirst,
                                detail: "The \(names[function] ?? Format.functionName(function)) of \(Format.text(argument))." + place)
        }
        if let x, let form = PolynomialForm(simplified, in: x), form.coefficients.count == 1, let degree = form.coefficients.keys.first {
            let coefficient = form.coefficient(degree)
            let names = [0: "Constant", 1: "Linear term", 2: "Squared term", 3: "Cubed term"]
            let name = names[degree] ?? "\(x) to the power \(degree)"
            let power = degree == 1 ? x : "\(x)\(degree == 2 ? "²" : (degree == 3 ? "³" : "^\(degree)"))"
            let detail: String
            if degree == 0 {
                detail = "A plain number, \(text). It doesn't change with \(x)."
            } else if coefficient.isOne {
                detail = "\(power) on its own, so its coefficient is 1."
            } else {
                detail = "\(Format.text(coefficient)) times \(power): its coefficient is \(Format.text(coefficient))."
            }
            return Anatomy.Part(expr: term, name: name, detail: detail + place)
        }
        return Anatomy.Part(expr: term, name: "Term in \(simplified.symbols.sorted().joined(separator: ", "))", detail: text + "." + place)
    }

    private static func derivativeRule(_ term: Expr, _ x: String) -> String {
        let (_, rest) = Simplify.splitCoefficient(Simplify.run(term))
        if !rest.contains(x) { return "A constant: its derivative is 0." }
        let (top, bottom) = Simplify.numeratorAndDenominator(rest)
        if bottom.contains(x) && top.contains(x) { return "Needs the quotient rule." }
        if case .multiply(let factors) = rest, factors.filter({ $0.contains(x) }).count > 1 { return "Needs the product rule." }
        if case .power(let base, _) = rest, base != .symbol(x), base.contains(x) { return "Needs the chain rule." }
        if case .function(_, let argument) = rest, argument != .symbol(x) { return "Needs the chain rule." }
        if rest == .symbol(x) || { if case .power(.symbol(x), _) = rest { true } else { false } }() { return "Uses the power rule." }
        return "A standard derivative."
    }

    // MARK: Why each step works

    private static let guides: [(prefix: String, why: String, watchOut: String?)] = [
        ("take the remainder of each number", "Numbers that differ by a multiple of the divisor leave the same remainder, so one can stand in for the other.", nil),
        ("find a power of", "Once a power leaves remainder 1, multiplying by it changes nothing, so the remainders repeat from there.", nil),
        ("reduce the power", "aᵐ⁺ⁿ = aᵐ × aⁿ, so every full cycle in the power is worth 1 and only what's left over counts.", "Divide the power by the length of the cycle, not by the number you're dividing by."),
        ("follow the remainders", "Each remainder depends only on the one before, so once one comes round again the rest follow.", nil),
        ("add the remainders", "Remainders add and multiply just like the numbers they came from.", "If the total reaches the divisor, take the remainder again."),
        ("combine the remainders", "Remainders add and subtract just like the numbers they came from.", "A negative total still needs a remainder from 0 up: add the divisor."),
        ("multiply the remainders", "Remainders add and multiply just like the numbers they came from.", "If the product reaches the divisor, take the remainder again."),
        ("find a common denominator", "You can only add or subtract fractions cut into the same size pieces. The lowest common multiple keeps the numbers small.", "Don't add the denominators: h/6 + 2h/9 isn't 3h/15."),
        ("rewrite each fraction", "Multiplying the top and bottom by the same number makes an equivalent fraction: the same value, written differently.", "Multiply the top as well as the bottom."),
        ("add the numerators", "With the same denominator the pieces are the same size, so you just count them.", "The denominator stays as it is."),
        ("use a common denominator", "Writing everything over one denominator turns it into a single fraction.", "Multiply each numerator by whatever its denominator was missing."),
        ("simplify", "Cancelling a factor that's on the top and the bottom doesn't change the value.", "Only cancel factors that multiply everything, never terms that are added."),
        ("brackets first", "Brackets come first in the order of operations (BIDMAS).", nil),
        ("powers and roots", "Powers and roots come before ×, ÷, + and −.", "−3² is −9; (−3)² is 9."),
        ("multiply and divide", "× and ÷ come before + and −, working from left to right.", "2 + 3 × 4 is 14, not 20."),
        ("add and subtract", "+ and − come last, from left to right.", nil),
        ("expand the brackets", "Everything inside a bracket is multiplied by what's outside it (the distributive law).", "Multiply every term inside, and watch the signs: −2(x − 1) = −2x + 2."),
        ("multiply out", "Every term in one bracket meets every term in the other.", "(a + b)² isn't a² + b²: you'd lose the 2ab."),
        ("write out the power", "A squared bracket is the bracket multiplied by itself.", "(a + b)² isn't a² + b²."),
        ("collect like terms", "Terms with exactly the same letters and powers can be added, like apples with apples.", "x² and x aren't like terms."),
        ("subtract the equations", "Taking one equation from the other removes the letter whose coefficients match.", "Subtract every term, including the right-hand side."),
        ("add the equations", "Adding the equations removes the letter whose coefficients are opposites.", nil),
        ("subtract", "Doing the same to both sides keeps the equation balanced.", "A term changes sign when it moves across the =."),
        ("add ", "Doing the same to both sides keeps the equation balanced.", "A term changes sign when it moves across the =."),
        ("collect the", "Gather the unknown on one side and the numbers on the other.", nil),
        ("divide both sides", "Dividing both sides by the same number keeps them equal and leaves the unknown on its own.", "Divide every term, on both sides."),
        ("multiply both sides", "Multiplying both sides by the same number keeps them equal.", nil),
        ("flip both sides", "If 1/a = 1/b then a = b.", nil),
        ("raise both sides", "Raising both sides to the same power keeps them equal.", nil),
        ("rearrange to equal zero", "With zero on one side you can factorise, or use the formula.", nil),
        ("take out", "A factor shared by every term can come outside a bracket.", "Divide every term by it, not just the first."),
        ("factorise", "Writing it as brackets multiplied together shows where it's zero.", "Check by expanding the brackets again."),
        ("set each", "If things multiply to zero, at least one of them is zero (the zero product rule).", nil),
        ("use the quadratic formula", "The formula solves any ax² + bx + c = 0, even one that won't factorise.", "Put negative numbers in brackets: with b = −3, b² is 9."),
        ("work out the discriminant", "b² − 4ac decides it: positive gives two real solutions, zero gives one, negative gives none.", nil),
        ("the discriminant is negative", "No real number squares to a negative, so the solutions are complex numbers.", nil),
        ("put the numbers in", "The ± gives both solutions at once: one with +, one with −.", nil),
        ("use the factor theorem", "If f(a) = 0, then (x − a) is a factor, and dividing it out leaves a smaller polynomial.", "Try small whole numbers that divide the constant term."),
        ("find the other roots numerically", "What's left has no neat roots, so they're found to many decimal places.", nil),
        ("take the square root", "Squaring hides the sign, so the positive and the negative root both work.", "Don't forget the ±."),
        ("take logs", "A logarithm brings a power down: if aˣ = b, then x = log b ÷ log a.", nil),
        ("raise e", "eˣ undoes ln.", nil),
        ("raise 10", "10ˣ undoes log.", nil),
        ("use the inverse", "The inverse function gives one angle, the principal value.", "There's usually a second angle in one turn."),
        ("find every solution", "Sine and cosine repeat every 360°, and most values are reached twice in each turn.", nil),
        ("solve numerically", "Some equations can't be rearranged. The answers are where the two sides' graphs cross.", nil),
        ("remove the modulus", "|A| = b means A is b or −b.", "Check both answers in the original equation."),
        ("clear the fractions", "Multiplying both sides by the denominator gets rid of the fractions.", "An answer can't make a denominator zero."),
        ("check", "Putting the answer back into the question shows it really works.", nil),
        ("differentiate term by term", "The derivative of a sum is the sum of the derivatives.", nil),
        ("differentiate again", "The second derivative shows how the gradient itself is changing.", nil),
        ("power rule", "Multiply by the power, then take one off the power: xⁿ becomes nxⁿ⁻¹.", nil),
        ("use the product rule", "When two functions of x multiply, each takes a turn being differentiated: u′v + uv′.", "It isn't u′ × v′."),
        ("use the quotient rule", "For u over v: (u′v − uv′) ÷ v². The order on top matters.", "Square the whole bottom."),
        ("use the chain rule", "For a function of a function: differentiate the outside, keep the inside, then multiply by the inside's derivative.", "Don't forget to multiply by the inside's derivative."),
        ("integrate term by term", "Integrate each term on its own: add one to the power, then divide by the new power.", "Don't forget + C."),
        ("integrate by parts", "∫u dv = uv − ∫v du. Choose u so it gets simpler when it's differentiated.", "Choose ln x, or a polynomial, as u."),
        ("substitute u", "Swapping the inside for u turns it into an integral you know.", "Change dx into du as well."),
        ("split into partial fractions", "A fraction with factors on the bottom splits into simpler fractions added together.", nil),
        ("integrate each part", "Each simple fraction has a standard integral.", nil),
        ("put in the limits", "A definite integral is the antiderivative at the top limit minus the antiderivative at the bottom limit.", "Top minus bottom, not the other way round."),
        ("integrate numerically", "The area is found by adding up very thin slices.", nil),
        ("expand the brackets first", "Multiplied out, each term can be integrated on its own.", nil),
        ("number the equations", "Numbering them makes it clear which equation each step uses.", nil),
        ("write them in the same form", "Lining up the letters makes it easy to add or subtract them.", nil),
        ("match the", "When one letter has the same coefficient in both, adding or subtracting removes it.", "Multiply every term, including the right-hand side."),
        ("eliminate", "Taking multiples of one equation from another removes one unknown at a time.", nil),
        ("rearrange (", "Making one letter the subject means it can be swapped into the other equation.", nil),
        ("substitute into", "Swapping it in leaves one equation with one unknown.", "Put the whole expression in brackets."),
        ("substitute back", "Putting the value you found into an equation gives the other unknown.", nil),
        ("substitute", "Replace each letter with its value, in brackets if it's negative.", "−3² is −9, but (−3)² is 9."),
        ("solve for", "One equation in one unknown is solved as usual.", nil),
        ("write it as maths", "A letter for each unknown turns the words into an equation.", nil),
        ("standard integral", "This is one of the integrals worth knowing by heart.", nil),
    ]

    static func why(_ step: Step) -> String? {
        guide(step)?.why
    }

    static func watchOut(_ step: Step) -> String? {
        guide(step)?.watchOut
    }

    private static func guide(_ step: Step) -> (prefix: String, why: String, watchOut: String?)? {
        let title = step.title.lowercased()
        return guides.first { title.hasPrefix($0.prefix) }
    }

    // MARK: Each answer checked

    static func checks(_ solution: Solution) -> [AnswerCheck] {
        guard case .solve(let equations, _) = solution.problem.kind else { return [] }
        if let sets = solution.answerSets {
            return sets.map { set in
                var values: [String: Expr] = [:]
                for line in set {
                    if case .symbol(let name) = line.parts.first, let value = line.parts.last { values[name] = value }
                }
                var holds = true
                let lines = equations.map { equation -> MathLine in
                    let left = substituting(equation.left, values), right = substituting(equation.right, values)
                    let ok = same(left, right)
                    holds = holds && ok
                    return MathLine(left, Simplify.run(right), relation: ok ? "=" : "≠")
                }
                return AnswerCheck(answer: set.map(\.text).joined(separator: ", "), lines: lines, holds: holds)
            }
        }
        guard equations.count == 1 else { return [] }
        let equation = equations[0]
        return solution.answers.compactMap { line in
            guard case .symbol(let name) = line.parts.first, let value = line.parts.last else { return nil }
            let left = equation.left.substituting(name, with: value)
            let right = equation.right.substituting(name, with: value)
            let ok = same(left, right)
            return AnswerCheck(answer: line.text,
                               lines: [MathLine(left, Simplify.run(left)), MathLine(right, Simplify.run(right))],
                               holds: ok)
        }
    }

    private static func substituting(_ expr: Expr, _ values: [String: Expr]) -> Expr {
        values.reduce(expr) { $0.substituting($1.key, with: $1.value) }
    }

    private static func same(_ a: Expr, _ b: Expr) -> Bool {
        guard let x = a.evaluate(), let y = b.evaluate() else { return false }
        return abs(x - y) < 1e-6 * max(1, abs(x))
    }
}

private extension Expr {
    var isBracket: Bool {
        if case .add = self { return true }
        return false
    }

    /// Every function used in it.
    var functions: Set<MathFunction> {
        switch self {
        case .number, .symbol, .constant: []
        case .add(let parts), .multiply(let parts): parts.reduce(into: Set<MathFunction>()) { $0.formUnion($1.functions) }
        case .power(let base, let exponent): base.functions.union(exponent.functions)
        case .function(let function, let argument): Set([function]).union(argument.functions)
        }
    }

    func hasVariableExponent(_ x: String) -> Bool {
        switch self {
        case .power(let base, let exponent): exponent.contains(x) || base.hasVariableExponent(x)
        case .add(let parts), .multiply(let parts): parts.contains { $0.hasVariableExponent(x) }
        case .function(_, let argument): argument.hasVariableExponent(x)
        default: false
        }
    }
}
