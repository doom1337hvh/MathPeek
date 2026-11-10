import Foundation

/// Puts expressions in a tidy standard form: numbers worked out exactly, like terms collected
/// (2x + 3x = 5x), like factors combined (x·x² = x³), surds simplified (√12 = 2√3), and the
/// exact values of things like sin 30° or ln e.
enum Simplify {
    static func run(_ expr: Expr) -> Expr {
        switch expr {
        case .number, .symbol, .constant: expr
        case .add(let terms): add(terms.map(run))
        case .multiply(let factors): multiply(factors.map(run))
        case .power(let base, let exponent): power(run(base), run(exponent))
        case .function(let function, let argument): apply(function, run(argument))
        }
    }

    // MARK: Sums

    /// Adds terms that are already simplified, collecting like terms.
    static func add(_ terms: [Expr]) -> Expr {
        var flat: [Expr] = []
        for term in terms {
            if case .add(let inner) = term { flat += inner } else { flat.append(term) }
        }
        var constant = Number.zero
        var order: [Expr] = []
        var coefficients: [Expr: Number] = [:]
        for term in flat {
            if case .number(let value) = term {
                constant = constant + value
                continue
            }
            let (coefficient, rest) = splitCoefficient(term)
            if coefficients[rest] == nil { order.append(rest) }
            coefficients[rest, default: .zero] = coefficients[rest, default: .zero] + coefficient
        }
        var result: [Expr] = []
        for rest in order {
            let coefficient = coefficients[rest]!
            guard !coefficient.isZero else { continue }
            result.append(multiply([.number(coefficient), rest]))
        }
        result = sortedTerms(result)
        if !constant.isZero || result.isEmpty { result.append(.number(constant)) }
        return result.count == 1 ? result[0] : .add(result)
    }

    /// 3x²y is 3 and x²y.
    static func splitCoefficient(_ term: Expr) -> (Number, Expr) {
        guard case .multiply(let factors) = term, case .number(let coefficient) = factors.first else {
            return (.one, term)
        }
        let rest = Array(factors.dropFirst())
        return (coefficient, rest.count == 1 ? rest[0] : .multiply(rest))
    }

    static func sortedTerms(_ terms: [Expr]) -> [Expr] {
        terms.sorted { a, b in
            if a.degree != b.degree { return a.degree > b.degree }
            return a.sortName < b.sortName
        }
    }

    // MARK: Products

    /// Multiplies factors that are already simplified, combining powers of the same thing.
    static func multiply(_ factors: [Expr]) -> Expr {
        var flat: [Expr] = []
        for factor in factors {
            if case .multiply(let inner) = factor { flat += inner } else { flat.append(factor) }
        }
        var coefficient = Number.one
        var order: [Expr] = []
        var exponents: [Expr: Expr] = [:]
        for factor in flat {
            if case .number(let value) = factor {
                coefficient = coefficient * value
                continue
            }
            let (base, exponent) = asPower(factor)
            if let existing = exponents[base] {
                exponents[base] = add([existing, exponent])
            } else {
                order.append(base)
                exponents[base] = exponent
            }
        }
        if coefficient.isZero { return .zero }
        var result: [Expr] = []
        for base in order {
            let combined = power(base, exponents[base]!)
            switch combined {
            case .number(let value):
                coefficient = coefficient * value
            case .multiply(let inner):
                // A surd with a whole part, like 2√3.
                for part in inner {
                    if case .number(let value) = part { coefficient = coefficient * value } else { result.append(part) }
                }
            default:
                result.append(combined)
            }
        }
        if coefficient.isZero { return .zero }
        result = sortedFactors(result)
        if !coefficient.isOne || result.isEmpty { result.insert(.number(coefficient), at: 0) }
        return result.count == 1 ? result[0] : .multiply(result)
    }

    static func asPower(_ expr: Expr) -> (Expr, Expr) {
        if case .power(let base, let exponent) = expr { return (base, exponent) }
        return (expr, .one)
    }

    static func sortedFactors(_ factors: [Expr]) -> [Expr] {
        func rank(_ factor: Expr) -> Int {
            if case .power(_, let exponent) = factor, exponent.number == nil { return 3 }
            return switch asPower(factor).0 {
            case .number: 0
            case .constant: 1
            case .symbol: 2
            case .function: 4
            default: 3
            }
        }
        return factors.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return a.sortName < b.sortName
        }
    }

    // MARK: Powers

    static func power(_ base: Expr, _ exponent: Expr) -> Expr {
        if exponent.isZero { return .one }
        if exponent.isOne { return base }
        if base.isOne { return .one }
        if base.isZero, let e = exponent.number, !e.isNegative { return .zero }
        if case .number(let b) = base, case .number(let e) = exponent {
            if let value = Number.power(b, e) { return .number(value) }
            if let surd = surd(b, e) { return surd }
            return .power(base, exponent)
        }
        // e^(ln x) = x
        if case .constant(.e) = base, case .function(.ln, let argument) = exponent { return argument }
        if case .power(let innerBase, let innerExponent) = base, exponent.number != nil {
            return power(innerBase, multiply([innerExponent, exponent]))
        }
        if case .multiply(let factors) = base, exponent.number != nil {
            return multiply(factors.map { power($0, exponent) })
        }
        return .power(base, exponent)
    }

    /// A root that isn't whole, in simplest form: √12 = 2√3, √(1/2) = √2/2, ∛16 = 2∛2.
    static func surd(_ base: Number, _ exponent: Number) -> Expr? {
        guard let b = base.rational, let e = exponent.rational, !e.isInteger, e.denominator <= 12,
              abs(e.numerator) <= 24 else { return nil }
        let q = e.denominator
        if b.numerator < 0 {
            // Even roots of negative numbers aren't real; odd roots keep the sign.
            guard q % 2 == 1, let positive = surd(.exact(b.negated), exponent) else { return nil }
            guard e.numerator % 2 != 0 else { return positive }
            if case .multiply(let parts) = positive, case .number(let c) = parts[0] {
                return .multiply([.number(c.negated)] + parts.dropFirst())
            }
            return .multiply([.minusOne, positive])
        }
        // b^(p/q) = b^n · b^(r/q) with 0 < r < q.
        var n = e.numerator / q
        var r = e.numerator % q
        if r < 0 { r += q; n -= 1 }
        guard let whole = b.power(n),
              let top = b.numerator.power(r), let bottom = b.denominator.power(r),
              let bottomPower = bottom.power(q - 1), let radicand = Rational.multiply(top, bottomPower)
        else { return nil }
        // (top/bottom)^(1/q) = (top · bottom^(q−1))^(1/q) / bottom
        let (outside, inside) = extractPower(radicand, q)
        guard let outsideOverBottom = Rational.make(outside, bottom), let coefficient = whole * outsideOverBottom
        else { return nil }
        if inside == 1 { return .number(.exact(coefficient)) }
        // Built directly: simplifying this product would come straight back here.
        let root = Expr.power(.integer(inside), .fraction(1, q))
        return coefficient == Rational(1) ? root : .multiply([.number(.exact(coefficient)), root])
    }

    /// value = outside^q · inside, with inside as small as possible.
    private static func extractPower(_ value: Int, _ q: Int) -> (Int, Int) {
        var outside = 1, inside = value, factor = 2
        while factor * factor <= inside && factor < 1_000_000 {
            guard let factorPower = factor.power(q) else { break }
            while inside % factorPower == 0 {
                inside /= factorPower
                outside *= factor
            }
            factor += 1
        }
        return (outside, inside)
    }

    // MARK: Functions

    static func apply(_ function: MathFunction, _ argument: Expr) -> Expr {
        if let exact = exactValue(function, argument) { return exact }
        if case .number(.real(let x)) = argument {
            let value = Expr.apply(function, x)
            if value.isFinite { return .number(.real(value)) }
        }
        if case .number(let x) = argument, !(function == .ln || function == .log || function.takesAngle || function.givesAngle) {
            let value = Expr.apply(function, x.double)
            if value.isFinite { return .number(.real(value)) }
        }
        if function == .abs, case .number(let x) = argument { return .number(x.isNegative ? x.negated : x) }
        return .function(function, argument)
    }

    private static func exactValue(_ function: MathFunction, _ argument: Expr) -> Expr? {
        switch function {
        case .ln:
            if argument.isOne { return .zero }
            if case .constant(.e) = argument { return .one }
            if case .power(.constant(.e), let exponent) = argument { return exponent }
        case .log:
            if case .number(let x) = argument, let integer = x.integer, integer > 0 {
                var value = integer, count = 0
                while value % 10 == 0 { value /= 10; count += 1 }
                if value == 1 { return .integer(count) }
            }
        case .abs:
            if case .number(let x) = argument { return .number(x.isNegative ? x.negated : x) }
        case .sin, .cos, .tan, .sec, .csc, .cot:
            guard let degrees = angleInDegrees(argument) else { return nil }
            return exactTrig(function, degrees)
        case .asin, .acos, .atan:
            return exactInverseTrig(function, argument)
        default:
            break
        }
        return nil
    }

    /// An exact angle in degrees: a number in degree mode, or a rational multiple of π.
    static func angleInDegrees(_ argument: Expr) -> Rational? {
        if case .number(.exact(let value)) = argument, MathSettings.angles == .degrees { return value }
        if argument == .pi { return Rational(180) }
        if case .multiply(let factors) = argument, factors.count == 2,
           case .number(.exact(let k)) = factors[0], factors[1] == .pi {
            return k * Rational(180)
        }
        if argument.isZero { return Rational(0) }
        return nil
    }

    private static let rootTwoOverTwo = Expr.multiply([.half, .power(.two, .half)])
    private static let rootThreeOverTwo = Expr.multiply([.half, .power(.integer(3), .half)])

    private static func exactTrig(_ function: MathFunction, _ degrees: Rational) -> Expr? {
        guard degrees.isInteger else { return nil }
        var angle = degrees.numerator % 360
        if angle < 0 { angle += 360 }
        func sine(_ a: Int) -> Expr? {
            let reference: Int, sign: Int
            switch a {
            case 0...90: (reference, sign) = (a, 1)
            case 91...180: (reference, sign) = (180 - a, 1)
            case 181...270: (reference, sign) = (a - 180, -1)
            default: (reference, sign) = (360 - a, -1)
            }
            let value: Expr
            switch reference {
            case 0: value = .zero
            case 30: value = .half
            case 45: value = rootTwoOverTwo
            case 60: value = rootThreeOverTwo
            case 90: value = .one
            default: return nil
            }
            return sign < 0 ? multiply([.minusOne, value]) : value
        }
        let cosineAngle = (450 - angle) % 360
        switch function {
        case .sin: return sine(angle)
        case .cos: return sine(cosineAngle)
        case .tan, .cot, .sec, .csc:
            guard let s = sine(angle), let c = sine(cosineAngle) else { return nil }
            let (top, bottom): (Expr, Expr) = switch function {
            case .tan: (s, c)
            case .cot: (c, s)
            case .sec: (.one, c)
            default: (.one, s)
            }
            guard !bottom.isZero else { return nil }
            return run(top / bottom)
        default: return nil
        }
    }

    private static func exactInverseTrig(_ function: MathFunction, _ argument: Expr) -> Expr? {
        guard let x = argument.evaluate() else { return nil }
        let candidates = [0, 30, 45, 60, 90, 120, 135, 150, 180, -30, -45, -60, -90]
        for degrees in candidates {
            let radians = Double(degrees) * .pi / 180
            let value: Double = switch function {
            case .asin: Foundation.sin(radians)
            case .acos: Foundation.cos(radians)
            default: Foundation.tan(radians)
            }
            let inRange: Bool = switch function {
            case .acos: degrees >= 0 && degrees <= 180
            case .asin: degrees >= -90 && degrees <= 90
            default: degrees > -90 && degrees < 90
            }
            guard inRange, abs(value - x) < 1e-12 else { continue }
            if MathSettings.angles == .degrees { return .integer(degrees) }
            return multiply([.fraction(degrees, 180), .pi])
        }
        return nil
    }

    // MARK: Expanding brackets

    /// Multiplies out brackets and whole-number powers of sums: (x + 1)² = x² + 2x + 1.
    static func expand(_ expr: Expr) -> Expr {
        switch expr {
        case .add(let terms):
            return add(terms.map(expand))
        case .multiply(let factors):
            var terms: [Expr] = [.one]
            for factor in factors.map(expand) {
                if case .add(let parts) = factor {
                    terms = terms.flatMap { term in parts.map { multiply([term, $0]) } }
                } else {
                    terms = terms.map { multiply([$0, factor]) }
                }
                if terms.count > 4000 { return run(expr) }
            }
            return add(terms)
        case .power(let base, let exponent):
            let inner = expand(base)
            if case .add = inner, let n = exponent.number?.integer, n > 1, n <= 12 {
                return expand(.multiply(Array(repeating: inner, count: n)))
            }
            return power(inner, exponent)
        case .function(let function, let argument):
            return apply(function, expand(argument))
        default:
            return expr
        }
    }

    // MARK: Fractions

    /// Splits a term into its numerator and denominator: 3x/(2y) is 3x and 2y.
    static func numeratorAndDenominator(_ term: Expr) -> (Expr, Expr) {
        let factors: [Expr] = if case .multiply(let parts) = term { parts } else { [term] }
        var top: [Expr] = [], bottom: [Expr] = []
        for factor in factors {
            if case .number(.exact(let value)) = factor, !value.isInteger {
                top.append(.integer(value.numerator))
                bottom.append(.integer(value.denominator))
            } else if case .power(let base, let exponent) = factor, let e = exponent.number, e.isNegative {
                bottom.append(power(base, .number(e.negated)))
            } else {
                top.append(factor)
            }
        }
        return (multiply(top), multiply(bottom))
    }

    /// One fraction over a common denominator, multiplied out and cancelled where it can be:
    /// 1/x + 1/(x+1) = (2x + 1)/(x² + x).
    static func together(_ expr: Expr) -> Expr {
        let simplified = run(expr)
        let terms: [Expr] = if case .add(let parts) = simplified { parts } else { [simplified] }
        let fractions = terms.map(numeratorAndDenominator)
        // The common denominator: each different factor, to its highest power.
        var order: [Expr] = []
        var highest: [Expr: Number] = [:]
        var numericDenominator = 1
        for (_, bottom) in fractions {
            let factors: [Expr] = if case .multiply(let parts) = bottom { parts } else { [bottom] }
            for factor in factors {
                if case .number(let value) = factor, let integer = value.integer {
                    numericDenominator = Rational.lcm(numericDenominator, abs(integer)) ?? numericDenominator
                    continue
                }
                let (base, exponent) = asPower(factor)
                let e = exponent.number ?? .one
                if let existing = highest[base] {
                    if e.double > existing.double { highest[base] = e }
                } else {
                    order.append(base)
                    highest[base] = e
                }
            }
        }
        let denominator = multiply([.integer(numericDenominator)] + order.map { power($0, .number(highest[$0]!)) })
        guard !denominator.isOne else { return expand(simplified) }
        let numerator = expand(add(fractions.map { top, bottom in
            multiply([top, run(denominator / bottom)])
        }))
        let cancelled = cancel(numerator, expand(denominator))
        let (_, newBottom) = numeratorAndDenominator(cancelled)
        if newBottom.degree == expand(denominator).degree {
            return run(.multiply([numerator, .power(denominator, .minusOne)]))
        }
        return cancelled
    }

    /// Cancels what the top and bottom of a fraction have in common.
    static func cancel(_ numerator: Expr, _ denominator: Expr) -> Expr {
        if numerator.isZero { return .zero }
        let variables = numerator.symbols.union(denominator.symbols)
        if variables.count == 1, let variable = variables.first,
           let top = Polynomial(numerator, in: variable), let bottom = Polynomial(denominator, in: variable) {
            let divisor = Polynomial.gcd(top, bottom)
            if divisor.degree > 0, let (newTop, _) = top.divided(by: divisor), let (newBottom, _) = bottom.divided(by: divisor) {
                return run(newTop.expr / newBottom.expr)
            }
        }
        return run(numerator / denominator)
    }
}

private extension Int {
    func power(_ exponent: Int) -> Int? {
        var result = 1
        for _ in 0..<Swift.max(exponent, 0) {
            guard let next = Rational.multiply(result, self) else { return nil }
            result = next
        }
        return result
    }
}
