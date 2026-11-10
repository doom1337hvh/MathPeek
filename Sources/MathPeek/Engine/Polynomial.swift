import Foundation

/// A polynomial in one letter with exact fraction coefficients, for cancelling, factorising
/// and finding roots.
struct Polynomial: Equatable {
    /// coefficients[k] is the coefficient of x^k. No trailing zeros.
    private(set) var coefficients: [Rational]
    let variable: String

    init(_ coefficients: [Rational], variable: String) {
        var trimmed = coefficients
        while let last = trimmed.last, last.isZero { trimmed.removeLast() }
        self.coefficients = trimmed
        self.variable = variable
    }

    /// Nil unless `expr`, multiplied out, is a polynomial in `variable` with exact numbers.
    init?(_ expr: Expr, in variable: String) {
        guard let form = PolynomialForm(expr, in: variable) else { return nil }
        var coefficients: [Rational] = []
        for k in 0...max(form.degree, 0) {
            guard case .number(.exact(let value)) = Simplify.run(form.coefficient(k)) else { return nil }
            coefficients.append(value)
        }
        self.init(coefficients, variable: variable)
    }

    var degree: Int { coefficients.count - 1 }
    var isZero: Bool { coefficients.isEmpty }
    var leading: Rational { coefficients.last ?? Rational(0) }

    func coefficient(_ k: Int) -> Rational { k < coefficients.count ? coefficients[k] : Rational(0) }

    var expr: Expr {
        let x = Expr.symbol(variable)
        let terms = coefficients.enumerated().reversed().compactMap { k, c -> Expr? in
            guard !c.isZero else { return nil }
            return Expr.multiply([.number(.exact(c)), Simplify.power(x, .integer(k))])
        }
        return Simplify.run(.add(terms))
    }

    func evaluate(_ x: Double) -> Double {
        coefficients.reversed().reduce(0) { $0 * x + $1.double }
    }

    func evaluate(_ x: Rational) -> Rational? {
        var result = Rational(0)
        for c in coefficients.reversed() {
            guard let product = result * x, let sum = product + c else { return nil }
            result = sum
        }
        return result
    }

    var derivative: Polynomial {
        let derived = coefficients.enumerated().dropFirst().compactMap { k, c in c * Rational(k) }
        return Polynomial(derived, variable: variable)
    }

    /// Long division: self = quotient × divisor + remainder.
    func divided(by divisor: Polynomial) -> (Polynomial, Polynomial)? {
        guard !divisor.isZero else { return nil }
        var remainder = coefficients
        var quotient = [Rational](repeating: Rational(0), count: max(degree - divisor.degree + 1, 1))
        while remainder.count >= divisor.coefficients.count, let last = remainder.last {
            let shift = remainder.count - divisor.coefficients.count
            guard let factor = last / divisor.leading else { return nil }
            quotient[shift] = factor
            for (k, c) in divisor.coefficients.enumerated() {
                guard let product = c * factor, let difference = remainder[k + shift] - product else { return nil }
                remainder[k + shift] = difference
            }
            remainder.removeLast()
            while let top = remainder.last, top.isZero { remainder.removeLast() }
        }
        return (Polynomial(quotient, variable: variable), Polynomial(remainder, variable: variable))
    }

    /// The greatest common divisor, with leading coefficient 1.
    static func gcd(_ a: Polynomial, _ b: Polynomial) -> Polynomial {
        var (x, y) = (a, b)
        while !y.isZero {
            guard let (_, remainder) = x.divided(by: y) else { break }
            (x, y) = (y, remainder)
        }
        guard !x.isZero, let scale = Rational(1) / x.leading else { return x }
        return Polynomial(x.coefficients.compactMap { $0 * scale }, variable: x.variable)
    }

    /// Roots that are fractions, found with the rational root theorem: p/q where p divides
    /// the constant term and q the leading coefficient.
    var rationalRoots: [Rational] {
        guard degree >= 1 else { return [] }
        // Whole-number coefficients first.
        let denominators = coefficients.map(\.denominator)
        var scale = 1
        for denominator in denominators {
            guard let next = Rational.lcm(scale, denominator) else { return [] }
            scale = next
        }
        let integers = coefficients.compactMap { ($0 * Rational(scale))?.numerator }
        guard integers.count == coefficients.count else { return [] }
        var roots: [Rational] = []
        if integers[0] == 0 { roots.append(Rational(0)) }
        let constant = integers.first { $0 != 0 } ?? 0
        let leading = integers.last ?? 1
        guard constant != 0, abs(constant) < 10_000_000, abs(leading) < 10_000_000 else { return roots }
        for p in Self.divisors(abs(constant)) {
            for q in Self.divisors(abs(leading)) {
                for sign in [1, -1] {
                    guard let candidate = Rational.make(sign * p, q), !roots.contains(candidate),
                          let value = evaluate(candidate), value.isZero else { continue }
                    roots.append(candidate)
                }
            }
        }
        return roots.sorted()
    }

    private static func divisors(_ n: Int) -> [Int] {
        guard n > 0 else { return [1] }
        var result: [Int] = []
        var d = 1
        while d * d <= n {
            if n % d == 0 {
                result.append(d)
                if d != n / d { result.append(n / d) }
            }
            d += 1
        }
        return result
    }

    /// The real roots, as decimals, found between the turning points.
    var realRoots: [Double] {
        guard degree >= 1 else { return [] }
        if degree == 1 { return [-coefficient(0).double / coefficient(1).double] }
        // Cauchy's bound: every root is within this distance of 0.
        let bound = 1 + coefficients.dropLast().map { abs($0.double / leading.double) }.max()!
        var points = derivative.realRoots.filter { abs($0) <= bound }
        points = ([-bound] + points.sorted() + [bound])
        var roots: [Double] = []
        for (a, b) in zip(points, points.dropFirst()) where b > a {
            let fa = evaluate(a), fb = evaluate(b)
            if abs(fa) < 1e-12 { roots.append(a); continue }
            guard fa * fb < 0 else { continue }
            var (low, high) = (a, b)
            for _ in 0..<200 {
                let middle = (low + high) / 2
                if evaluate(middle) * fa < 0 { high = middle } else { low = middle }
            }
            roots.append((low + high) / 2)
        }
        if abs(evaluate(bound)) < 1e-12 { roots.append(bound) }
        var distinct: [Double] = []
        for root in roots.sorted() where !distinct.contains(where: { abs($0 - root) < 1e-9 }) {
            distinct.append(root)
        }
        return distinct
    }
}

/// An expression multiplied out and grouped by powers of one letter, whose coefficients can
/// hold other letters: ax² + bx + c. For solving equations with letters in them.
struct PolynomialForm {
    let variable: String
    private(set) var coefficients: [Int: Expr]

    var degree: Int { coefficients.keys.max() ?? 0 }

    func coefficient(_ k: Int) -> Expr { coefficients[k] ?? .zero }

    init?(_ expr: Expr, in variable: String) {
        self.variable = variable
        let expanded = Simplify.expand(expr)
        let terms: [Expr] = if case .add(let parts) = expanded { parts } else { [expanded] }
        var coefficients: [Int: [Expr]] = [:]
        for term in terms {
            let factors: [Expr] = if case .multiply(let parts) = term { parts } else { [term] }
            var power = 0
            var rest: [Expr] = []
            for factor in factors {
                if factor == .symbol(variable) {
                    power += 1
                } else if case .power(.symbol(variable), let exponent) = factor,
                          let n = exponent.number?.integer, n > 0 {
                    power += n
                } else if factor.contains(variable) {
                    return nil
                } else {
                    rest.append(factor)
                }
            }
            coefficients[power, default: []].append(Simplify.multiply(rest))
        }
        var simplified: [Int: Expr] = [:]
        for (power, parts) in coefficients {
            let sum = Simplify.add(parts)
            if !sum.isZero { simplified[power] = sum }
        }
        self.coefficients = simplified
    }
}
