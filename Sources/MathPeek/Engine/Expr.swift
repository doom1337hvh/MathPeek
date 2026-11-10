import Foundation

enum MathConstant: String, Hashable, Sendable {
    case pi
    case e
}

enum MathFunction: String, Hashable, Sendable, CaseIterable {
    case sin, cos, tan, sec, csc, cot
    case asin, acos, atan
    case sinh, cosh, tanh
    case ln, log, abs

    /// Trigonometric functions take angles, so degrees matter.
    var takesAngle: Bool { [.sin, .cos, .tan, .sec, .csc, .cot].contains(self) }
    var givesAngle: Bool { [.asin, .acos, .atan].contains(self) }
}

enum AngleUnit: String, Sendable, CaseIterable {
    case degrees
    case radians
}

/// Settings a calculation runs with, set for the duration of one problem.
enum MathSettings {
    @TaskLocal static var angles: AngleUnit = .degrees
}

/// A mathematical expression. Subtraction is adding −1 × something, and division is
/// multiplying by something to the power −1, so the simplifier has fewer cases.
indirect enum Expr: Hashable, Sendable {
    case number(Number)
    case symbol(String)
    case constant(MathConstant)
    case add([Expr])
    case multiply([Expr])
    case power(Expr, Expr)
    case function(MathFunction, Expr)

    static let zero = Expr.number(.zero)
    static let one = Expr.number(.one)
    static let minusOne = Expr.number(.minusOne)
    static let two = Expr.integer(2)
    static let half = Expr.fraction(1, 2)
    static let pi = Expr.constant(.pi)

    static func integer(_ value: Int) -> Expr { .number(.integer(value)) }

    static func fraction(_ top: Int, _ bottom: Int) -> Expr {
        Rational.make(top, bottom).map { .number(.exact($0)) } ?? .number(.real(Double(top) / Double(bottom)))
    }

    static func + (a: Expr, b: Expr) -> Expr { .add([a, b]) }
    static func - (a: Expr, b: Expr) -> Expr { .add([a, .multiply([.minusOne, b])]) }
    static func * (a: Expr, b: Expr) -> Expr { .multiply([a, b]) }
    static func / (a: Expr, b: Expr) -> Expr { .multiply([a, .power(b, .minusOne)]) }
    static prefix func - (a: Expr) -> Expr { .multiply([.minusOne, a]) }
    func raised(_ exponent: Expr) -> Expr { .power(self, exponent) }
    func squareRoot() -> Expr { .power(self, .half) }

    // MARK: Questions about an expression

    var number: Number? {
        if case .number(let value) = self { return value }
        return nil
    }

    var isZero: Bool { number?.isZero == true }
    var isOne: Bool { number?.isOne == true }

    /// The letters in it.
    var symbols: Set<String> {
        switch self {
        case .number, .constant: []
        case .symbol(let name): [name]
        case .add(let parts), .multiply(let parts): parts.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }
        case .power(let base, let exponent): base.symbols.union(exponent.symbols)
        case .function(_, let argument): argument.symbols
        }
    }

    func contains(_ symbol: String) -> Bool {
        switch self {
        case .number, .constant: false
        case .symbol(let name): name == symbol
        case .add(let parts), .multiply(let parts): parts.contains { $0.contains(symbol) }
        case .power(let base, let exponent): base.contains(symbol) || exponent.contains(symbol)
        case .function(_, let argument): argument.contains(symbol)
        }
    }

    var containsFunction: Bool {
        switch self {
        case .number, .constant, .symbol: false
        case .add(let parts), .multiply(let parts): parts.contains { $0.containsFunction }
        case .power(let base, let exponent): base.containsFunction || exponent.containsFunction
        case .function: true
        }
    }

    func substituting(_ symbol: String, with value: Expr) -> Expr {
        switch self {
        case .number, .constant: self
        case .symbol(let name): name == symbol ? value : self
        case .add(let parts): .add(parts.map { $0.substituting(symbol, with: value) })
        case .multiply(let parts): .multiply(parts.map { $0.substituting(symbol, with: value) })
        case .power(let base, let exponent):
            .power(base.substituting(symbol, with: value), exponent.substituting(symbol, with: value))
        case .function(let function, let argument): .function(function, argument.substituting(symbol, with: value))
        }
    }

    /// Its value as a decimal, with `values` for its letters. Nil if a letter has no value or
    /// it's undefined there.
    func evaluate(_ values: [String: Double] = [:]) -> Double? {
        let result: Double?
        switch self {
        case .number(let value): result = value.double
        case .symbol(let name): result = values[name]
        case .constant(.pi): result = .pi
        case .constant(.e): result = M_E
        case .add(let parts):
            var sum = 0.0
            for part in parts {
                guard let value = part.evaluate(values) else { return nil }
                sum += value
            }
            result = sum
        case .multiply(let parts):
            var product = 1.0
            for part in parts {
                guard let value = part.evaluate(values) else { return nil }
                product *= value
            }
            result = product
        case .power(let base, let exponent):
            guard let b = base.evaluate(values), let e = exponent.evaluate(values) else { return nil }
            // Odd roots of negative numbers are real: (−8)^(1/3) = −2.
            if b < 0, let rational = exponent.number?.rational, !rational.isInteger, rational.denominator % 2 == 1 {
                let magnitude = pow(-b, e)
                result = rational.numerator % 2 == 0 ? magnitude : -magnitude
            } else {
                result = pow(b, e)
            }
        case .function(let function, let argument):
            guard let x = argument.evaluate(values) else { return nil }
            result = Self.apply(function, x)
        }
        guard let result, result.isFinite else { return nil }
        return result
    }

    static func apply(_ function: MathFunction, _ x: Double) -> Double {
        let toRadians = MathSettings.angles == .degrees ? Double.pi / 180 : 1
        let fromRadians = 1 / toRadians
        switch function {
        case .sin: return Foundation.sin(x * toRadians)
        case .cos: return Foundation.cos(x * toRadians)
        case .tan: return Foundation.tan(x * toRadians)
        case .sec: return 1 / Foundation.cos(x * toRadians)
        case .csc: return 1 / Foundation.sin(x * toRadians)
        case .cot: return 1 / Foundation.tan(x * toRadians)
        case .asin: return Foundation.asin(x) * fromRadians
        case .acos: return Foundation.acos(x) * fromRadians
        case .atan: return Foundation.atan(x) * fromRadians
        case .sinh: return Foundation.sinh(x)
        case .cosh: return Foundation.cosh(x)
        case .tanh: return Foundation.tanh(x)
        case .ln: return Foundation.log(x)
        case .log: return Foundation.log10(x)
        case .abs: return Swift.abs(x)
        }
    }

    // MARK: Order, for writing terms the way people do

    /// The degree of a term in its letters, so x² comes before x, and x before numbers.
    var degree: Double {
        switch self {
        case .number: 0
        case .constant: 0
        case .symbol: 1
        case .add(let parts): parts.map(\.degree).max() ?? 0
        case .multiply(let parts): parts.map(\.degree).reduce(0, +)
        case .power(let base, let exponent): base.degree * (exponent.number?.double ?? 1)
        case .function: 0.5
        }
    }

    /// A rough key for sorting: letters alphabetically, functions after letters.
    var sortName: String {
        switch self {
        case .number: "~"
        case .constant(let constant): "#" + constant.rawValue
        case .symbol(let name): name
        case .add(let parts): "(" + parts.map(\.sortName).joined(separator: "+")
        case .multiply(let parts): parts.map(\.sortName).filter { $0 != "~" }.joined(separator: "*")
        case .power(let base, _): base.sortName
        case .function(let function, let argument): "{" + function.rawValue + argument.sortName
        }
    }
}
