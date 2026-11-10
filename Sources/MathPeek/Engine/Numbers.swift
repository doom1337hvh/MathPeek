import Foundation

/// An exact fraction, always in lowest terms with a positive denominator. Arithmetic returns
/// nil when it would overflow, and the caller falls back to a decimal.
struct Rational: Hashable, Sendable, Comparable {
    let numerator: Int
    let denominator: Int

    init(_ integer: Int) {
        numerator = integer
        denominator = 1
    }

    private init(reduced numerator: Int, _ denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    static func make(_ numerator: Int, _ denominator: Int) -> Rational? {
        guard denominator != 0, numerator != .min, denominator != .min else { return nil }
        let divisor = gcd(abs(numerator), abs(denominator))
        var top = numerator / divisor, bottom = denominator / divisor
        if bottom < 0 { top = -top; bottom = -bottom }
        return Rational(reduced: top, bottom)
    }

    /// A decimal as written, like "4.5", exactly: 9/2.
    static func parse(_ digits: String) -> Rational? {
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Int(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        guard parts.count == 2, !parts[1].isEmpty else { return Rational(whole) }
        let fraction = String(parts[1])
        guard fraction.count <= 15, let decimals = Int(fraction) else { return nil }
        let scale = Int(pow(10, Double(fraction.count)))
        guard let scaled = multiply(whole, scale), let top = add(scaled, decimals) else { return nil }
        return make(top, scale)
    }

    var isInteger: Bool { denominator == 1 }
    var isZero: Bool { numerator == 0 }
    var double: Double { Double(numerator) / Double(denominator) }
    var negated: Rational { Rational(reduced: -numerator, denominator) }

    static func + (a: Rational, b: Rational) -> Rational? {
        guard let left = multiply(a.numerator, b.denominator), let right = multiply(b.numerator, a.denominator),
              let top = add(left, right), let bottom = multiply(a.denominator, b.denominator) else { return nil }
        return make(top, bottom)
    }

    static func - (a: Rational, b: Rational) -> Rational? { a + b.negated }

    static func * (a: Rational, b: Rational) -> Rational? {
        guard let top = multiply(a.numerator, b.numerator), let bottom = multiply(a.denominator, b.denominator)
        else { return nil }
        return make(top, bottom)
    }

    static func / (a: Rational, b: Rational) -> Rational? {
        guard !b.isZero else { return nil }
        return a * Rational(reduced: b.numerator < 0 ? -b.denominator : b.denominator, abs(b.numerator))
    }

    func power(_ exponent: Int) -> Rational? {
        if exponent < 0 {
            guard let positive = power(-exponent) else { return nil }
            return Rational(1) / positive
        }
        var result = Rational(1)
        for _ in 0..<min(exponent, 4096) {
            guard let next = result * self else { return nil }
            result = next
        }
        return exponent > 4096 ? nil : result
    }

    static func < (a: Rational, b: Rational) -> Bool { a.double < b.double }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }

    static func lcm(_ a: Int, _ b: Int) -> Int? {
        multiply(a / gcd(a, b), b)
    }

    static func multiply(_ a: Int, _ b: Int) -> Int? {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? nil : result
    }

    static func add(_ a: Int, _ b: Int) -> Int? {
        let (result, overflow) = a.addingReportingOverflow(b)
        return overflow ? nil : result
    }

    /// The whole-number `root`th root of `value`, if it has one.
    static func exactRoot(_ value: Int, _ root: Int) -> Int? {
        guard root > 0 else { return nil }
        if value < 0 {
            guard root % 2 == 1, let positive = exactRoot(-value, root) else { return nil }
            return -positive
        }
        let guess = Int(pow(Double(value), 1 / Double(root)).rounded())
        for candidate in max(guess - 1, 0)...(guess + 1) {
            var product = 1
            var overflowed = false
            for _ in 0..<root {
                guard let next = multiply(product, candidate) else { overflowed = true; break }
                product = next
            }
            if !overflowed && product == value { return candidate }
        }
        return nil
    }
}

/// A number in a calculation: exact while it can be, a decimal once it can't (after an
/// overflow, or a square root or sine that isn't a nice value).
enum Number: Hashable, Sendable {
    case exact(Rational)
    case real(Double)

    static let zero = Number.exact(Rational(0))
    static let one = Number.exact(Rational(1))
    static let minusOne = Number.exact(Rational(-1))

    static func integer(_ value: Int) -> Number { .exact(Rational(value)) }

    var double: Double {
        switch self {
        case .exact(let rational): rational.double
        case .real(let value): value
        }
    }

    var rational: Rational? {
        if case .exact(let rational) = self { return rational }
        return nil
    }

    var integer: Int? {
        if case .exact(let rational) = self, rational.isInteger { return rational.numerator }
        if case .real(let value) = self, value == value.rounded(), abs(value) < 1e15 { return Int(value) }
        return nil
    }

    var isZero: Bool { double == 0 }
    var isOne: Bool { double == 1 }
    var isNegative: Bool { double < 0 }
    var isExact: Bool { rational != nil }

    var negated: Number {
        switch self {
        case .exact(let rational): .exact(rational.negated)
        case .real(let value): .real(-value)
        }
    }

    static func + (a: Number, b: Number) -> Number {
        if let x = a.rational, let y = b.rational, let sum = x + y { return .exact(sum) }
        return .real(a.double + b.double)
    }

    static func - (a: Number, b: Number) -> Number { a + b.negated }

    static func * (a: Number, b: Number) -> Number {
        if let x = a.rational, let y = b.rational, let product = x * y { return .exact(product) }
        return .real(a.double * b.double)
    }

    /// Nil when dividing by zero.
    static func / (a: Number, b: Number) -> Number? {
        guard !b.isZero else { return nil }
        if let x = a.rational, let y = b.rational, let quotient = x / y { return .exact(quotient) }
        return .real(a.double / b.double)
    }

    /// `base ^ exponent` as a number, or nil when it should stay as it is: a surd like 2^(1/2),
    /// or something undefined like 0^-1 or (-1)^(1/2).
    static func power(_ base: Number, _ exponent: Number) -> Number? {
        if let b = base.rational, let e = exponent.rational {
            if e.isInteger {
                if b.isZero && e.numerator < 0 { return nil }
                if let exact = b.power(e.numerator) { return .exact(exact) }
                let value = pow(b.double, e.double)
                return value.isFinite ? .real(value) : nil
            }
            // A fractional power is exact only for perfect powers, like 8^(2/3) = 4.
            guard let top = Rational.exactRoot(b.numerator, e.denominator),
                  let bottom = Rational.exactRoot(b.denominator, e.denominator),
                  let root = Rational.make(top, bottom), let exact = root.power(e.numerator) else { return nil }
            return .exact(exact)
        }
        let value = pow(base.double, exponent.double)
        return value.isFinite ? .real(value) : nil
    }
}
