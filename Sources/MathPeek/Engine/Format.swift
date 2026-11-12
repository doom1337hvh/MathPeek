import Foundation

/// Writes expressions out the way people write them: 7h/18, x² + 2x + 1, 2√3, sin 30°.
/// `latex` gives the same in LaTeX, for copying into documents.
enum Format {
    // MARK: Plain text

    static func text(_ expr: Expr) -> String {
        switch expr {
        case .number(let value):
            return number(value)
        case .symbol(let name):
            return name
        case .constant(.pi):
            return "π"
        case .constant(.e):
            return "e"
        case .add(let rawTerms):
            var terms = rawTerms
            // −3 + √29 and −1 + 2i, the way they're usually written.
            func isSurdOrImaginary(_ term: Expr) -> Bool {
                if term.contains("i") { return true }
                let factors: [Expr] = if case .multiply(let parts) = term { parts } else { [term] }
                return factors.contains { if case .power(.number, let e) = $0, e.number?.rational?.isInteger == false { true } else { false } }
            }
            if terms.allSatisfy({ $0.symbols.subtracting(["i"]).isEmpty }), terms.contains(where: isSurdOrImaginary),
               let index = terms.lastIndex(where: { $0.number != nil }) {
                terms.insert(terms.remove(at: index), at: 0)
            } else if signedText(terms[0]).0, let positive = terms.firstIndex(where: { !signedText($0).0 }) {
                // x − 3 rather than −3 + x
                terms.insert(terms.remove(at: positive), at: 0)
            }
            var result = ""
            for (index, term) in terms.enumerated() {
                let (negative, body) = signedText(term)
                if index == 0 {
                    result = negative ? "−" + body : body
                } else {
                    result += negative ? " − " + body : " + " + body
                }
            }
            return result
        case .multiply:
            let (negative, body) = signedText(expr)
            return negative ? "−" + body : body
        case .power(let base, let exponent):
            if let e = exponent.number, e.isNegative {
                return "1/" + wrapped(Simplify.power(base, .number(e.negated)), forDenominator: true)
            }
            return powerText(base, exponent)
        case .function(let function, let argument):
            return functionText(function, argument)
        }
    }

    /// Whether the term is negative, and its text without the sign.
    private static func signedText(_ term: Expr) -> (Bool, String) {
        switch term {
        case .number(let value) where value.isNegative:
            return (true, number(value.negated))
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                let rest = value.negated.isOne && factors.count > 1
                    ? Array(factors.dropFirst()) : [Expr.number(value.negated)] + factors.dropFirst()
                if rest.count == 1, case .add = rest[0] { return (true, "(" + text(rest[0]) + ")") }
                return (true, rest.count == 1 ? signedText(rest[0]).1 : productText(rest))
            }
            return (false, productText(factors))
        default:
            return (false, text(term))
        }
    }

    /// A product with a positive coefficient, with anything divided written after a /.
    private static func productText(_ factors: [Expr]) -> String {
        // Working shown before it's simplified can multiply several numbers: 2 × 4, 12 × 7.5 ÷ 3.
        // (A product of numbers inside it counts as one of them: 5 × 5(5 × 5) is 5 × 5 × (5 × 5).)
        let numbers = factors.filter { if case .number = $0 { true } else { isProductOfNumbers($0) } }
        if numbers.count > 1 || (numbers.count == 1 && factors.first?.number == nil) {
            var result = ""
            for (index, factor) in factors.enumerated() {
                if index > 0, case .power(let base, .minusOne) = factor {
                    result += " ÷ " + (isAtomic(base) ? text(base) : "(" + text(base) + ")")
                    continue
                }
                var piece = text(factor)
                if case .add = factor { piece = "(" + piece + ")" }
                if index > 0, isProductOfNumbers(factor) { piece = "(" + piece + ")" }
                if case .number(let value) = factor, value.isNegative || value.rational?.isInteger == false { piece = "(" + piece + ")" }
                result += index == 0 ? piece : " × " + piece
            }
            return result
        }
        var topNumber = "", bottomNumber = ""
        var top: [Expr] = [], bottom: [Expr] = []
        for factor in factors {
            if case .number(let value) = factor {
                if let rational = value.rational {
                    if rational.numerator != 1 { topNumber = String(rational.numerator) }
                    if rational.denominator != 1 { bottomNumber = String(rational.denominator) }
                } else {
                    topNumber = number(value)
                }
            } else if case .power(let base, let exponent) = factor, let e = exponent.number, e.isNegative {
                bottom.append(Simplify.power(base, .number(e.negated)))
            } else {
                top.append(factor)
            }
        }
        let hasDenominator = !bottom.isEmpty || !bottomNumber.isEmpty
        // sin(x)/2, not sin x/2, which reads as sin(x/2).
        var numerator = joined(top, leadingNumber: topNumber, bracketLastFunction: hasDenominator)
        if numerator.isEmpty { numerator = "1" }
        guard hasDenominator else { return numerator }
        let denominatorParts = joined(bottom, leadingNumber: bottomNumber)
        let needsBrackets = bottom.count + (bottomNumber.isEmpty ? 0 : 1) > 1
            || (bottom.count == 1 && bottomNumber.isEmpty && !isAtomic(bottom[0]) && !denominatorParts.hasPrefix("(")
                && !(denominatorParts.hasSuffix(")") && denominatorParts.hasPrefix("(")))
        let simplePower: Bool = if bottom.count == 1, bottomNumber.isEmpty, case .power(let b, _) = bottom[0], isAtomic(b) { true } else { false }
        let denominator = needsBrackets && !simplePower ? "(" + denominatorParts + ")" : denominatorParts
        return numerator + "/" + denominator
    }

    /// Whether it's numbers multiplied together and nothing else: the 5 × 5 in 5 × 5(5 × 5).
    static func isProductOfNumbers(_ expr: Expr) -> Bool {
        if case .multiply(let factors) = expr { return factors.allSatisfy { $0.symbols.isEmpty } }
        return false
    }

    /// Factors written next to each other: 3x²y, 2√3, 3(x + 1), x sin x.
    private static func joined(_ factors: [Expr], leadingNumber: String, bracketLastFunction: Bool = false) -> String {
        var result = leadingNumber
        // Plain arithmetic keeps its × : 12 × (3 + 4.5), but 3(x + 1).
        let arithmetic = factors.allSatisfy { $0.symbols.isEmpty }
        for (index, factor) in factors.enumerated() {
            var piece = text(factor)
            if bracketLastFunction, index == factors.count - 1, case .function(let function, let argument) = factor, function != .abs {
                piece = functionName(function) + "(" + text(argument) + ")"
            }
            if case .add = factor { piece = "(" + piece + ")" }
            if case .function = factor, !result.isEmpty {
                result += " " + piece
                continue
            }
            let numberToPower = { if case .power(.number, let e) = factor, e.number?.rational?.isInteger == true { true } else { false } }()
            if arithmetic, !result.isEmpty, piece.hasPrefix("(") {
                result += " × " + piece
            } else if numberToPower, !result.isEmpty {
                // 6 × 1², not 61²
                result += " × " + piece
            } else if let last = result.last, let first = piece.first, last.isNumber && first.isNumber {
                result += " × " + piece
            } else if let last = result.last, last.isLetter, let first = piece.first, first.isLetter,
                      piece.count > 1, piece.first?.isLowercase == true, !(factor.isSimplePower) {
                result += " " + piece
            } else {
                result += piece
            }
        }
        return result
    }

    private static func powerText(_ base: Expr, _ exponent: Expr) -> String {
        if exponent == .half { return "√" + wrapped(base, forRoot: true) }
        if exponent == .fraction(1, 3) { return "∛" + wrapped(base, forRoot: true) }
        if let n = exponent.number?.integer, n >= 0 {
            return wrapped(base) + superscript(n)
        }
        let exponentText = isAtomic(exponent) ? text(exponent) : "(" + text(exponent) + ")"
        return wrapped(base) + "^" + exponentText
    }

    private static func functionText(_ function: MathFunction, _ argument: Expr) -> String {
        if function == .abs { return "|" + text(argument) + "|" }
        let name = functionName(function)
        if function.takesAngle, MathSettings.angles == .degrees, case .number(let value) = argument, !value.isNegative {
            return name + " " + number(value) + "°"
        }
        if isAtomic(argument) { return name + " " + text(argument) }
        if case .function(.abs, _) = argument { return name + text(argument) }
        return name + "(" + text(argument) + ")"
    }

    static func functionName(_ function: MathFunction) -> String {
        switch function {
        case .asin: "sin⁻¹"
        case .acos: "cos⁻¹"
        case .atan: "tan⁻¹"
        default: function.rawValue
        }
    }

    private static func wrapped(_ expr: Expr, forRoot: Bool = false, forDenominator: Bool = false) -> String {
        if isAtomic(expr) { return text(expr) }
        if forRoot, case .multiply(let factors) = expr, factors.allSatisfy({ isAtomic($0) }) { return text(expr) }
        return "(" + text(expr) + ")"
    }

    static func isAtomic(_ expr: Expr) -> Bool {
        switch expr {
        case .symbol, .constant: true
        case .number(let value): !value.isNegative && (value.rational?.isInteger ?? true)
        default: false
        }
    }

    private static func superscript(_ n: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                              "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { digits[$0] ?? $0 })
    }

    // MARK: Numbers

    static func number(_ value: Number) -> String {
        switch value {
        case .exact(let rational):
            let sign = rational.numerator < 0 ? "−" : ""
            let top = String(abs(rational.numerator))
            return rational.isInteger ? sign + top : sign + top + "/" + String(rational.denominator)
        case .real(let double):
            return decimal(double)
        }
    }

    /// A decimal without floating-point noise: at most 10 decimal places, and scientific
    /// notation when it's huge or tiny.
    static func decimal(_ value: Double, grouped: Bool = false, forCopying: Bool = false) -> String {
        let rounded = Double(String(format: "%.12g", value)) ?? value
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minusSign = forCopying ? "-" : "−"
        let magnitude = abs(rounded)
        if magnitude >= 1e15 || (magnitude > 0 && magnitude < 1e-9) {
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = 9
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 10
            formatter.usesGroupingSeparator = grouped && !forCopying
        }
        return formatter.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? "\(rounded)"
    }

    // MARK: LaTeX

    static func latex(_ expr: Expr) -> String {
        switch expr {
        case .number(let value):
            if let rational = value.rational, !rational.isInteger {
                let sign = rational.numerator < 0 ? "-" : ""
                return sign + "\\frac{\(abs(rational.numerator))}{\(rational.denominator)}"
            }
            return value.rational.map { String($0.numerator) } ?? decimal(value.double, forCopying: true)
        case .symbol(let name):
            return latexSymbol(name)
        case .constant(.pi):
            return "\\pi"
        case .constant(.e):
            return "e"
        case .add(let terms):
            var result = ""
            for (index, term) in terms.enumerated() {
                var body = latex(term)
                let negative = body.hasPrefix("-")
                if negative { body.removeFirst() }
                result += index == 0 ? (negative ? "-" : "") + body : (negative ? " - " : " + ") + body
            }
            return result
        case .multiply(let factors):
            // A minus in front: the sign, then the rest.
            if case .number(let first)? = factors.first, first.isNegative, first.negated.isOne, factors.count > 1 {
                let rest = Array(factors.dropFirst())
                if rest.count == 1, case .add = rest[0] { return "-\\left(\(latex(rest[0]))\\right)" }
                return "-" + (rest.count == 1 ? latex(rest[0]) : latex(.multiply(rest)))
            }
            // Working before it's simplified multiplies several numbers: each is written, with a × between.
            let plain = factors.filter { $0.number != nil || isProductOfNumbers($0) }
            // (And a number in front of something that starts with a number: 3 × 2x, not 32x.)
            let startsWithNumber = factors.contains { if case .multiply(let inner) = $0 { inner.first?.number != nil && !isProductOfNumbers($0) } else { false } }
            if plain.count > 1 || (plain.count == 1 && (isProductOfNumbers(factors[0]) || startsWithNumber)) {
                var result = ""
                for (index, factor) in factors.enumerated() {
                    if index > 0, case .power(let base, let exponent) = factor, exponent == .minusOne {
                        result += " \\div " + (isAtomic(base) ? latex(base) : "\\left(\(latex(base))\\right)")
                        continue
                    }
                    var piece = latex(factor)
                    if case .add = factor { piece = "\\left(\(piece)\\right)" }
                    if index > 0, isProductOfNumbers(factor) { piece = "\\left(\(piece)\\right)" }
                    if index > 0, case .number(let value) = factor, value.isNegative { piece = "\\left(\(piece)\\right)" }
                    result += index == 0 ? piece : " \\times " + piece
                }
                return result
            }
            var negative = false
            var topNumber = "", bottomNumber = ""
            var top: [String] = [], bottom: [String] = []
            for factor in factors {
                if case .number(let value) = factor {
                    negative = value.isNegative
                    if let rational = value.rational {
                        if abs(rational.numerator) != 1 { topNumber = String(abs(rational.numerator)) }
                        if rational.denominator != 1 { bottomNumber = String(rational.denominator) }
                    } else {
                        topNumber = decimal(abs(value.double), forCopying: true)
                    }
                } else if case .power(let base, let exponent) = factor, let e = exponent.number, e.isNegative {
                    bottom.append(latexFactor(Simplify.power(base, .number(e.negated))))
                } else {
                    top.append(latexFactor(factor))
                }
            }
            // 4 × 2³, not 42³: a number in front of something that starts with a digit keeps its ×.
            let times = !topNumber.isEmpty && (top.first?.first?.isNumber ?? false) ? " \\times " : ""
            let numerator = (topNumber + top.joined(separator: " ")).isEmpty ? "1" : topNumber + times + top.joined(separator: " ")
            let sign = negative ? "-" : ""
            if bottom.isEmpty && bottomNumber.isEmpty { return sign + numerator }
            return sign + "\\frac{\(numerator)}{\(bottomNumber + bottom.joined(separator: " "))}"
        case .power(let base, let exponent):
            if exponent == .half { return "\\sqrt{\(latex(base))}" }
            if exponent == .fraction(1, 3) { return "\\sqrt[3]{\(latex(base))}" }
            if let e = exponent.number, e.isNegative {
                return "\\frac{1}{\(latex(Simplify.power(base, .number(e.negated))))}"
            }
            let baseText = isAtomic(base) ? latex(base) : "\\left(\(latex(base))\\right)"
            return baseText + "^{\(latex(exponent))}"
        case .function(let function, let argument):
            if function == .abs { return "\\left|\(latex(argument))\\right|" }
            let name: String = switch function {
            case .asin: "\\sin^{-1}"
            case .acos: "\\cos^{-1}"
            case .atan: "\\tan^{-1}"
            case .sec, .csc, .cot, .sin, .cos, .tan, .sinh, .cosh, .tanh, .ln, .log: "\\" + function.rawValue
            case .abs: ""
            }
            if function.takesAngle, MathSettings.angles == .degrees, case .number = argument {
                return name + " " + latex(argument) + "^\\circ"
            }
            return isAtomic(argument) ? name + " " + latex(argument) : name + "\\left(\(latex(argument))\\right)"
        }
    }

    private static func latexFactor(_ factor: Expr) -> String {
        if case .add = factor { return "\\left(\(latex(factor))\\right)" }
        return latex(factor)
    }

    private static func latexSymbol(_ name: String) -> String {
        let greek: [String: String] = ["θ": "\\theta", "α": "\\alpha", "β": "\\beta", "γ": "\\gamma",
                                       "λ": "\\lambda", "μ": "\\mu", "φ": "\\phi", "ω": "\\omega"]
        return greek[name] ?? name
    }
}

private extension Expr {
    /// x or x² — written straight after other letters.
    var isSimplePower: Bool {
        switch self {
        case .symbol: true
        case .power(.symbol, .number): true
        default: false
        }
    }
}
