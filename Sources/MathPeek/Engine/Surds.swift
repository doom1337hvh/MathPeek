import Foundation

/// A number made of fractions and square roots, kept exact: so many of each root, where what's
/// under a root is a whole number with no square factor (1 for the part with no root).
/// 7 + √5 is one 1 and one √5; 6√15 is six √15s.
struct Surd: Equatable {
    var terms: [Int: Rational] = [:]

    init() {}

    init(_ amount: Rational, root: Int = 1) {
        if !amount.isZero { terms[root] = amount }
    }

    /// The number, if there's no root left in it.
    var rational: Rational? { terms.isEmpty ? Rational(0) : (terms.count == 1 ? terms[1] : nil) }

    /// The largest whole number whose square divides `value`, and what's left.
    static func squareFactor(of value: Int) -> (outside: Int, inside: Int) {
        var outside = 1, inside = value
        var factor = 2
        while factor * factor <= inside {
            while inside % (factor * factor) == 0 {
                inside /= factor * factor
                outside *= factor
            }
            factor += 1
        }
        return (outside, inside)
    }

    /// √(p/q), which is √(pq)/q.
    static func root(of value: Rational) -> Surd? {
        guard value.numerator >= 0 else { return nil }
        guard let product = Rational.multiply(value.numerator, value.denominator), product < 1_000_000_000 else { return nil }
        if product == 0 { return Surd() }
        let (outside, inside) = squareFactor(of: product)
        guard let amount = Rational.make(outside, value.denominator) else { return nil }
        return Surd(amount, root: inside)
    }

    func adding(_ other: Surd) -> Surd? {
        var result = self
        for (root, amount) in other.terms {
            guard let sum = (result.terms[root] ?? Rational(0)) + amount else { return nil }
            result.terms[root] = sum.isZero ? nil : sum
        }
        return result
    }

    func multiplied(by other: Surd) -> Surd? {
        var result = Surd()
        for (m, a) in terms {
            for (n, b) in other.terms {
                // √m × √n, with what they share taken out whole: √6 × √10 is 2√15.
                let shared = Rational.gcd(m, n)
                guard let inside = Rational.multiply(m / shared, n / shared), let product = a * b, let amount = product * Rational(shared),
                      let sum = result.adding(Surd(amount, root: inside)) else { return nil }
                result = sum
            }
        }
        return result
    }

    /// The same with the sign of its last root changed: what a denominator of two parts is
    /// multiplied by to clear its roots.
    var conjugate: Surd? {
        guard terms.count == 2, let last = terms.keys.max(), let first = terms.keys.min(), let amount = terms[last], let other = terms[first] else { return nil }
        var result = self
        // (√5 − 1 goes with √5 + 1, not −1 − √5.)
        if amount.numerator > 0, other.numerator < 0 { result.terms[first] = other.negated } else { result.terms[last] = amount.negated }
        return result
    }

    var reciprocal: Surd? {
        let parts = terms.sorted { $0.key < $1.key }
        switch parts.count {
        case 1:
            // 1/(c√n) is √n/(cn).
            guard let bottom = parts[0].value * Rational(parts[0].key), let amount = Rational(1) / bottom else { return nil }
            return Surd(amount, root: parts[0].key)
        case 2:
            // (a√m + b√n)(a√m − b√n) is a²m − b²n: no roots.
            guard let conjugate, let bottom = multiplied(by: conjugate)?.rational, !bottom.isZero, let scale = Rational(1) / bottom else { return nil }
            return conjugate.multiplied(by: Surd(scale))
        default:
            return nil
        }
    }

    func power(_ exponent: Int) -> Surd? {
        guard abs(exponent) <= 12 else { return nil }
        if exponent < 0 { return reciprocal?.power(-exponent) }
        var result = Surd(Rational(1))
        for _ in 0..<exponent {
            guard let next = result.multiplied(by: self) else { return nil }
            result = next
        }
        return result
    }

    /// The value of an expression made of numbers, square roots, +, −, × and ÷; nil for
    /// anything else.
    init?(_ expr: Expr) {
        switch expr {
        case .number(let number):
            guard let value = number.rational else { return nil }
            self.init(value)
        case .add(let parts):
            var sum = Surd()
            for part in parts {
                guard let value = Surd(part), let next = sum.adding(value) else { return nil }
                sum = next
            }
            self = sum
        case .multiply(let parts):
            var product = Surd(Rational(1))
            for part in parts {
                guard let value = Surd(part), let next = product.multiplied(by: value) else { return nil }
                product = next
            }
            self = product
        case .power(let base, let exponent):
            guard let index = exponent.number?.rational, let under = Surd(base) else { return nil }
            if index.isInteger {
                guard let value = under.power(index.numerator) else { return nil }
                self = value
            } else {
                guard index.denominator == 2, let plain = under.rational, let root = Surd.root(of: plain), let value = root.power(index.numerator) else { return nil }
                self = value
            }
        default:
            return nil
        }
    }

    /// One part written out: 6√15, with what's under the root left as it's given.
    static func term(_ amount: Rational, _ root: Int) -> Expr {
        if root == 1 { return .number(.exact(amount)) }
        let surd = Expr.power(.integer(root), .half)
        return amount == Rational(1) ? surd : .multiply([.number(.exact(amount)), surd])
    }

    /// Written the way an answer is: the roots, then the number, over one denominator.
    var expr: Expr {
        let parts = terms.sorted { $0.key < $1.key }
        guard !parts.isEmpty else { return .zero }
        if parts.count == 1 { return Surd.term(parts[0].value, parts[0].key) }
        let ordered = parts.filter { $0.key != 1 } + parts.filter { $0.key == 1 }
        var bottom = 1
        for part in parts { bottom = Rational.lcm(bottom, part.value.denominator) ?? bottom }
        let scaled = ordered.map { part in (part.value * Rational(bottom)).map { Surd.term($0, part.key) } }
        if bottom == 1 || scaled.contains(where: { $0 == nil }) || scaled.contains(where: { $0?.number?.rational?.isInteger == false }) {
            return .add(ordered.map { Surd.term($0.value, $0.key) })
        }
        return .multiply([.fraction(1, bottom), .add(scaled.compactMap { $0 })])
    }
}

/// Sums with square roots in them, worked out the way they're taught.
enum Surds {
    /// The exact answer to a sum that has a root in it, and the working. `isPlainSum` is for
    /// roots only added or taken away (√44 + √99), which has its own working.
    static func worked(_ expr: Expr) -> (answer: Expr, steps: [Step], isPlainSum: Bool)? {
        guard hasRoot(expr), let value = Surd(expr) else { return nil }
        if isPlainSum(expr) { return (value.expr, [], true) }
        return (value.expr, steps(for: expr, value), false)
    }

    /// Whether there's a square root in it that doesn't come out whole.
    static func hasRoot(_ expr: Expr) -> Bool {
        switch expr {
        case .add(let parts), .multiply(let parts):
            return parts.contains(where: hasRoot)
        case .power(let base, let exponent):
            if let index = exponent.number?.rational, index.denominator == 2, let under = Surd(base)?.rational, under.numerator > 0 {
                return Rational.exactRoot(under.numerator, 2) == nil || Rational.exactRoot(under.denominator, 2) == nil
            }
            return hasRoot(base)
        default:
            return false
        }
    }

    /// A number, a root of a whole number, or a number of them: 3, √5, 2√3.
    private static func isSingle(_ expr: Expr) -> Bool {
        switch expr {
        case .number(let number): return number.rational != nil
        case .power(.number(let under), let exponent): return exponent == .half && (under.integer ?? 0) > 0
        case .multiply(let parts): return parts.allSatisfy(isSingle) && parts.filter { $0.number == nil }.count <= 1
        default: return false
        }
    }

    private static func isPlainSum(_ expr: Expr) -> Bool {
        terms(of: expr).allSatisfy(isSingle)
    }

    /// The parts of a sum, however it was put together.
    private static func terms(of expr: Expr) -> [Expr] {
        if case .add(let parts) = expr { return parts.flatMap(terms) }
        return [expr]
    }

    /// A number of roots as it's written, what's under the root left alone: √8 is one √8.
    private static func written(_ expr: Expr) -> (number: Rational, under: Int)? {
        switch expr {
        case .number(let number):
            return number.rational.map { ($0, 1) }
        case .power(.number(let under), let exponent) where exponent == .half:
            return under.integer.flatMap { $0 > 0 ? (Rational(1), $0) : nil }
        case .multiply(let parts):
            var number = Rational(1), under = 1
            for part in parts {
                guard let piece = written(part), let next = number * piece.number, let inside = Rational.multiply(under, piece.under) else { return nil }
                number = next
                under = inside
            }
            return (number, under)
        default:
            return nil
        }
    }

    /// Whether a root in it has a square number to take out.
    private static func hasSquare(_ expr: Expr) -> Bool {
        switch expr {
        case .add(let parts), .multiply(let parts): return parts.contains(where: hasSquare)
        case .power(.number(let under), let exponent) where exponent == .half: return under.integer.map { $0 > 0 && Surd.squareFactor(of: $0).outside > 1 } ?? false
        case .power(let base, _): return hasSquare(base)
        default: return false
        }
    }

    /// The factors of a product, on the top and on the bottom.
    private static func factors(of expr: Expr) -> (top: [Expr], bottom: [Expr]) {
        var top: [Expr] = [], bottom: [Expr] = []
        func take(_ expr: Expr, under: Bool) {
            switch expr {
            case .multiply(let parts):
                parts.forEach { take($0, under: under) }
            case .power(let base, let exponent) where exponent.number?.integer.map({ $0 < 0 }) ?? false:
                let count = -(exponent.number?.integer ?? -1)
                for _ in 0..<min(count, 4) { take(base, under: !under) }
            case .power(let base, let exponent) where (exponent.number?.integer ?? 0) > 1 && (exponent.number?.integer ?? 0) <= 4:
                if case .add = base {
                    for _ in 0..<(exponent.number?.integer ?? 1) { take(base, under: under) }
                } else if under { bottom.append(expr) } else { top.append(expr) }
            default:
                if under { bottom.append(expr) } else { top.append(expr) }
            }
        }
        take(expr, under: false)
        return (top, bottom)
    }

    private static func product(_ exprs: [Expr]) -> Surd? {
        var result = Surd(Rational(1))
        for expr in exprs {
            guard let value = Surd(expr), let next = result.multiplied(by: value) else { return nil }
            result = next
        }
        return result
    }

    private static func steps(for expr: Expr, _ value: Surd) -> [Step] {
        let answer = value.expr
        let (top, bottom) = factors(of: expr)
        guard top.count + bottom.count > 1, let above = product(top), let below = product(bottom) else {
            // A sum of parts that each need working out.
            if case .add = expr {
                let each = Expr.add(terms(of: expr).map { Surd($0)?.expr ?? $0 })
                var steps = [Step("Work out each part", "Multiply out or simplify each part by itself first.", [MathLine(expr, each)])]
                if Format.text(each) != Format.text(answer) {
                    steps.append(Step("Collect the roots that are the same", "Roots of the same number add up like letters do, and the whole numbers add up together.", [MathLine(answer)]))
                }
                return steps
            }
            return []
        }
        let topValues = top.compactMap { Surd($0) }, bottomValues = bottom.compactMap { Surd($0) }
        guard topValues.count == top.count, bottomValues.count == bottom.count else { return [] }
        let isSingles = (topValues + bottomValues).allSatisfy { $0.terms.count <= 1 }

        // Numbers and roots only, multiplied and divided: 2√3 × 3√5, 4√6 ÷ 2√2, 6/√3.
        if isSingles {
            func parts(_ exprs: [Expr]) -> (number: Rational, under: Int)? {
                var number = Rational(1), under = 1
                for expr in exprs {
                    guard let piece = written(expr) ?? Surd(expr)?.terms.first.map({ ($0.value, $0.key) }),
                          let next = number * piece.number, let inside = Rational.multiply(under, piece.under) else { return nil }
                    number = next
                    under = inside
                }
                return (number, under)
            }
            guard let up = parts(top), let down = parts(bottom), !down.number.isZero, let number = up.number / down.number else { return [] }
            var steps: [Step] = []
            var current: Expr
            var under: Int
            if down.under == 1 {
                under = up.under
                current = Surd.term(number, under)
                let rootCount = topValues.filter { $0.terms.first?.key != 1 }.count
                if rootCount > 1 || topValues.count > 2 || !bottom.isEmpty, Format.text(expr) != Format.text(current) {
                    steps.append(Step(bottom.isEmpty ? "Multiply the numbers, and multiply what's under the roots" : "Divide the numbers",
                                      bottom.isEmpty ? "√a × √b is √(a × b)." : "", [MathLine(expr, current)]))
                }
            } else if up.under % down.under == 0 {
                under = up.under / down.under
                current = Surd.term(number, under)
                steps.append(Step("Divide the numbers, and divide what's under the roots", "√a ÷ √b is √(a ÷ b).", [MathLine(expr, current)]))
            } else {
                // The root on the bottom doesn't go into the top: multiply both by it.
                let clearing = Expr.power(.integer(down.under), .half)
                guard let inside = Rational.multiply(up.under, down.under), let scaled = number / Rational(down.under) else { return [] }
                under = inside
                let before = Expr.multiply([Surd.term(up.number, up.under), .power(Surd.term(down.number, down.under), .minusOne)])
                let after = Expr.multiply([Surd.term(up.number, inside), .power(.number(.exact((down.number * Rational(down.under)) ?? Rational(1))), .minusOne)])
                steps.append(Step("Multiply the top and the bottom by \(Format.text(clearing))",
                                  "That makes the bottom a whole number, because \(Format.text(clearing)) × \(Format.text(clearing)) is \(down.under). Top and bottom are both multiplied, so the value doesn't change.",
                                  [MathLine(before, after)]))
                current = Surd.term(scaled, under)
            }
            let (outside, inside) = Surd.squareFactor(of: under)
            if outside > 1 {
                let root = Expr.power(.integer(under), .half)
                let simple: Expr = inside == 1 ? .integer(outside) : .multiply([.integer(outside), .power(.integer(inside), .half)])
                steps.append(Step(inside == 1 ? "Work out the root" : "Take the square number out of the root",
                                  inside == 1 ? "" : "Write what's under the root as a square number times what's left: the root of the square number is whole.",
                                  [inside == 1 ? MathLine(root, simple) : MathLine(parts: [root, .power(.multiply([.integer(outside * outside), .integer(inside)]), .half), simple])]))
            }
            // (Not when the root that was just worked out is the whole of the answer.)
            let isShown = outside > 1 && number == Rational(1) && (current.number == nil || inside == 1)
            if (Format.text(current) != Format.text(answer) && !isShown) || steps.isEmpty {
                steps.append(Step("Simplify", "", [MathLine(answer)]))
            }
            return steps
        }

        var steps: [Step] = []
        var upper = above
        // Roots on the bottom in two parts: multiply top and bottom by the same with one sign changed.
        if below.terms.count == 2, below.rational == nil, let conjugate = below.conjugate, let cleared = below.multiplied(by: conjugate),
           let raised = above.multiplied(by: conjugate) {
            let by = conjugate.expr
            steps.append(Step("Multiply the top and the bottom by \(Format.text(by))",
                              "It's the bottom with the sign in the middle changed. That clears the roots from the bottom, because (a + b)(a − b) is a² − b².",
                              [MathLine(.multiply([above.expr, by]), raised.expr), MathLine(.multiply([below.expr, by]), cleared.expr)]))
            upper = raised
            let over = Expr.multiply([raised.expr, .power(cleared.expr, .minusOne)])
            if let whole = cleared.rational, whole != Rational(1), Format.text(over) != Format.text(answer) {
                steps.append(Step("Divide by \(Format.text(.number(.exact(whole))))", "", [MathLine(over, answer)]))
            }
            return steps
        }
        guard below.terms.count <= 1 else { return [] }
        // One root on the bottom under a sum: multiply top and bottom by it.
        if let under = below.terms.first, under.key != 1, let raised = above.multiplied(by: Surd(Rational(1), root: under.key)),
           let cleared = below.multiplied(by: Surd(Rational(1), root: under.key)) {
            let by = Expr.power(.integer(under.key), .half)
            steps.append(Step("Multiply the top and the bottom by \(Format.text(by))",
                              "That makes the bottom a whole number, because \(Format.text(by)) × \(Format.text(by)) is \(under.key). Top and bottom are both multiplied, so the value doesn't change.",
                              [MathLine(.multiply([above.expr, by]), raised.expr), MathLine(.multiply([below.expr, by]), cleared.expr)]))
            let over = Expr.multiply([raised.expr, .power(cleared.expr, .minusOne)])
            if Format.text(over) != Format.text(answer) { steps.append(Step("Simplify", "", [MathLine(over, answer)])) }
            return steps
        }
        // Brackets: each part of one by each part of the other.
        let sums = topValues.filter { $0.terms.count > 1 }
        if top.count == 1 {
            // One sum over a number: its roots made simple, then each part divided.
            if hasSquare(top[0]) {
                steps.append(Step("Take the square number out of each root", "Write what's under the root as a square number times what's left: the root of the square number is whole.",
                                  [MathLine(top[0], above.expr)]))
            }
        } else if !sums.isEmpty {
            var products = [Surd(Rational(1))]
            for value in topValues {
                var next: [Surd] = []
                for done in products {
                    for term in value.terms.sorted(by: { $0.key < $1.key }) {
                        if let made = done.multiplied(by: Surd(term.value, root: term.key)) { next.append(made) }
                    }
                }
                products = next
                if products.count > 16 { return [] }
            }
            // (A bracket that comes to nothing leaves nothing to write out.)
            guard products.count > 1 else { return [] }
            let written = Expr.add(products.map(\.expr))
            let single = sums.count == 1
            steps.append(Step("Multiply out the bracket\(single ? "" : "s")",
                              single ? "Multiply each part inside the bracket by what's outside. √a × √a is a." : "Multiply each part of one bracket by each part of the other. √a × √a is a.",
                              [MathLine(.multiply(top), written)]))
            if Format.text(written) != Format.text(above.expr) {
                steps.append(Step("Collect", "Add the whole numbers together, and the roots of the same number together.", [MathLine(above.expr)]))
            }
            upper = above
        }
        let over = Expr.multiply([upper.expr, .power(below.expr, .minusOne)])
        if !bottom.isEmpty, Format.text(over) != Format.text(answer) {
            steps.append(Step("Divide each part by \(Format.text(below.expr))", "", [MathLine(over, answer)]))
        }
        return steps
    }
}
