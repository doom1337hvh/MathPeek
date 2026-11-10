import Foundation

struct Equation: Hashable, Sendable {
    var left: Expr
    var right: Expr
}

/// What to do with what was read.
enum ProblemKind: Sendable {
    /// Numbers only: work it out.
    case evaluate(Expr)
    case simplify(Expr)
    case expand(Expr)
    case factorise(Expr)
    /// Equations, and which letters to find (empty: work it out).
    case solve([Equation], unknowns: [String])
    case differentiate(Expr, variable: String, order: Int)
    case integrate(Expr, variable: String, from: Expr?, to: Expr?)
    /// A formula and values for its letters: 3x + 2 when x = 4.
    case substitute(Expr, values: [String: Expr])
}

struct Problem: Sendable {
    var kind: ProblemKind
    /// The problem as one line of text, which the learning view lets you edit.
    var text: String
    /// Whether the numbers were written as decimals, so the answer should be too.
    var usesDecimals: Bool
    /// Degrees or radians, if the problem says (° or π).
    var angles: AngleUnit?
    /// The answer already written after =, as in "12 × 7.5 = 90", to check.
    var writtenAnswer: Expr?
}

/// Reads a problem written as text: "12 × (3 + 4.5)", "h/6 + 2h/9", "solve x² − 5x + 6 = 0",
/// "d/dx x² sin x", "∫ 2x dx from 0 to 3", "3x + 2 when x = 4". Nil if it isn't maths.
enum Parser {
    static func problem(_ input: String) -> Problem? {
        var text = normalize(input)
        guard !text.isEmpty else { return nil }
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesDecimals = text.range(of: #"\d\.\d"#, options: .regularExpression) != nil
        let angles: AngleUnit? = text.contains("°") ? .degrees : (text.contains("π") || text.contains("pi") ? .radians : nil)
        func make(_ kind: ProblemKind) -> Problem {
            Problem(kind: kind, text: display, usesDecimals: usesDecimals, angles: angles)
        }

        // The instruction, if there is one.
        var command = ""
        let commands = ["solve", "simplify", "expand", "factorise", "factorize", "factor", "differentiate",
                        "derivative of", "integrate", "integral of", "evaluate", "calculate", "work out",
                        "find the value of", "find", "what is"]
        for word in commands where text.lowercased().hasPrefix(word + " ") || text.lowercased().hasPrefix(word + ":") {
            command = word
            text = String(text.dropFirst(word.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            break
        }
        text = text.replacingOccurrences(of: #"^the\s+"#, with: "", options: .regularExpression)

        // "… when x = 4, y = 2"
        if let range = text.range(of: #"\s+(when|if|where|for)\s+[a-zA-Zα-ω]\s*=.*$"#, options: .regularExpression) {
            let assignments = text[range].replacingOccurrences(of: #"^\s+(when|if|where|for)\s+"#, with: "", options: .regularExpression)
            text = String(text[..<range.lowerBound])
            var values: [String: Expr] = [:]
            for assignment in assignments.split(whereSeparator: { $0 == "," || $0 == ";" }) {
                let sides = assignment.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard sides.count == 2, sides[0].count == 1, let value = expression(sides[1]) else { return nil }
                values[sides[0]] = value
            }
            guard let formula = expression(text), !values.isEmpty else { return nil }
            return make(.substitute(formula, values: values))
        }

        // "solve … for x"
        var unknowns: [String] = []
        if let range = text.range(of: #"\s+for\s+[a-zA-Zα-ω](\s*(,|and)\s*[a-zA-Zα-ω])*$"#, options: .regularExpression) {
            let list = text[range].replacingOccurrences(of: #"^\s+for\s+"#, with: "", options: .regularExpression)
            unknowns = list.replacingOccurrences(of: "and", with: ",").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count == 1 }
            text = String(text[..<range.lowerBound])
        }
        // "… with respect to x"
        var respectTo: String?
        if let range = text.range(of: #"\s*(with respect to|wrt|w\.r\.t\.)\s*[a-zA-Z]$"#, options: .regularExpression) {
            respectTo = text[range].last.map(String.init)
            text = String(text[..<range.lowerBound])
        }

        // Integrals: "∫ … dx", "∫ … dx from a to b", "integrate …"
        if text.hasPrefix("∫") || command == "integrate" || command == "integral of" {
            var body = text.hasPrefix("∫") ? String(text.dropFirst()) : text
            var from: Expr?, to: Expr?
            if let range = body.range(of: #"\s+(from|between)\s+.+\s+(to|and)\s+.+$"#, options: .regularExpression) {
                let limits = body[range].replacingOccurrences(of: #"^\s+(from|between)\s+"#, with: "", options: .regularExpression)
                let parts = limits.components(separatedBy: CharacterSet.whitespaces).joined(separator: " ")
                    .components(separatedBy: #" to "#)
                let pair = parts.count == 2 ? parts : limits.components(separatedBy: " and ")
                guard pair.count == 2, let a = expression(pair[0]), let b = expression(pair[1]) else { return nil }
                (from, to) = (a, b)
                body = String(body[..<range.lowerBound])
            } else if let range = body.range(of: #"^_\(?([^\^\s)]+)\)?\^\(?([^\s)]+)\)?"#, options: .regularExpression) {
                // ∫_0^3
                let limits = body[range].dropFirst()
                let parts = limits.split(separator: "^", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
                guard parts.count == 2, let a = expression(parts[0]), let b = expression(parts[1]) else { return nil }
                (from, to) = (a, b)
                body = String(body[range.upperBound...])
            }
            var variable = respectTo
            if let range = body.range(of: #"\s*d\s*([a-zA-Zθ])\s*$"#, options: .regularExpression) {
                variable = String(body[range].last!)
                body = String(body[..<range.lowerBound])
            }
            guard let integrand = expression(body) else { return nil }
            let chosen = variable ?? mainVariable(integrand.symbols) ?? "x"
            return make(.integrate(integrand, variable: chosen, from: from, to: to))
        }

        // Derivatives: "d/dx …", "d²y/dx²", "differentiate …"
        var order = 1
        var derivativeOf: String?
        if let range = text.range(of: #"^d(\^?2|²)?\s*[a-zA-Z]?\s*/\s*d\s*([a-zA-Z])(\^?2|²)?"#, options: .regularExpression) {
            let head = String(text[range])
            if head.contains("2") || head.contains("²") { order = 2 }
            derivativeOf = head.filter(\.isLetter).last.map(String.init)
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if derivativeOf != nil || command == "differentiate" || command == "derivative of" {
            // "y = x² + 1, dy/dx" style is handled by statements below; here the expression follows.
            if let expr = expression(text) {
                let variable = derivativeOf ?? respectTo ?? mainVariable(expr.symbols) ?? "x"
                return make(.differentiate(expr, variable: variable, order: order))
            }
        }

        // Statements: equations or expressions, one per line or separated by ; or a comma.
        let statements = text.split(whereSeparator: { $0 == ";" || $0 == "\n" })
            .flatMap { piece -> [Substring] in
                piece.contains("=") && piece.filter({ $0 == "=" }).count > 1
                    ? piece.split(separator: ",") : [piece]
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !statements.isEmpty else { return nil }

        // "y = x³ + 2x" followed by "dy/dx", or "f(x) = …" followed by "f'(x)".
        if statements.count == 2, let definition = definition(statements[0]),
           statements[1].range(of: #"^(d\s*[a-zA-Z]\s*/\s*d\s*[a-zA-Z]|[a-zA-Z]'(\([a-zA-Z]\))?)$"#, options: .regularExpression) != nil {
            return make(.differentiate(definition.body, variable: definition.variable ?? mainVariable(definition.body.symbols) ?? "x", order: 1))
        }

        var equations: [Equation] = []
        var lone: Expr?
        for statement in statements {
            if let definition = definition(statement), statements.count == 1, definition.variable != nil {
                return make(.simplify(definition.body))
            }
            let sides = statement.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
            if sides.count == 1 {
                guard let expr = expression(sides[0]), statements.count == 1 else { return nil }
                lone = expr
            } else {
                // "12 × 3 =" or "x + 1 = ?" asks for the left side.
                let right = sides.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                if right.isEmpty || right == "?" {
                    guard let expr = expression(sides[0]) else { return nil }
                    lone = expr
                    continue
                }
                guard sides.count == 2, let left = expression(sides[0]), let rightExpr = expression(right) else { return nil }
                // Numbers on both sides: the right is an answer to check, not an equation to solve.
                if statements.count == 1, left.symbols.isEmpty, rightExpr.symbols.isEmpty {
                    var problem = make(.evaluate(left))
                    problem.writtenAnswer = rightExpr
                    return problem
                }
                equations.append(Equation(left: left, right: rightExpr))
            }
        }
        if let lone {
            switch command {
            case "expand": return make(.expand(lone))
            case "factorise", "factorize", "factor": return make(.factorise(lone))
            case "solve": return make(.solve([Equation(left: lone, right: .zero)], unknowns: unknowns))
            default: return make(lone.symbols.isEmpty ? .evaluate(lone) : .simplify(lone))
            }
        }
        guard !equations.isEmpty else { return nil }
        // "y = 2x + 3" just defines y: tidy up its right-hand side.
        if equations.count == 1, command.isEmpty, unknowns.isEmpty, case .symbol(let name) = equations[0].left,
           !equations[0].right.contains(name), equations[0].right.symbols.count >= 1 {
            return make(.simplify(equations[0].right))
        }
        return make(.solve(equations, unknowns: unknowns))
    }

    /// "f(x) = x² + 1" or "y = …": the body, and the letter it's in.
    private static func definition(_ statement: String) -> (body: Expr, variable: String?)? {
        if let match = statement.range(of: #"^[a-zA-Z]\s*\(\s*[a-zA-Z]\s*\)\s*="#, options: .regularExpression) {
            let head = statement[match]
            let variable = head.filter(\.isLetter).dropFirst().first.map(String.init)
            guard let body = expression(String(statement[match.upperBound...])) else { return nil }
            return (body, variable)
        }
        if let match = statement.range(of: #"^[a-zA-Z]\s*="#, options: .regularExpression) {
            guard let body = expression(String(statement[match.upperBound...])) else { return nil }
            return (body, nil)
        }
        return nil
    }

    /// The letter to work in: x if it's there, then t, θ, and so on.
    static func mainVariable(_ symbols: Set<String>) -> String? {
        for preferred in ["x", "t", "θ", "y", "z", "n", "u", "v"] where symbols.contains(preferred) { return preferred }
        return symbols.sorted().first
    }

    // MARK: Expressions

    /// Parses one expression, or nil.
    static func expression(_ text: String) -> Expr? {
        guard let tokens = Tokenizer.tokens(normalize(text)), !tokens.isEmpty else { return nil }
        var parser = ExpressionParser(tokens: tokens)
        guard let expr = try? parser.parseAll() else { return nil }
        return expr
    }

    /// Cyrillic letters that text recognition sometimes reads instead of Latin ones: х for x.
    static let lookalikes: [Character: Character] = [
        "х": "x", "у": "y", "а": "a", "е": "e", "о": "o", "с": "c", "р": "p", "к": "k", "м": "m", "т": "t",
        "н": "h", "в": "b", "і": "i", "ј": "j", "Х": "X", "У": "Y", "А": "A", "В": "B", "Е": "E", "С": "C",
        "З": "3", "з": "3",
    ]

    /// Writes the many ways maths is typed or read in one way.
    static func normalize(_ input: String) -> String {
        var text = input
        let replacements: [(String, String)] = [
            ("×", "*"), ("✕", "*"), ("✖", "*"), ("∗", "*"), ("⋅", "*"), ("·", "*"),
            ("÷", "/"), ("∕", "/"), ("⁄", "/"),
            ("−", "-"), ("–", "-"), ("—", "-"), ("‒", "-"), ("﹣", "-"), ("－", "-"), ("＋", "+"),
            ("[", "("), ("]", ")"), ("{", "("), ("}", ")"),
            ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "),
            ("**", "^"), ("⁻¹", "^-1"), ("⁻²", "^-2"), ("½", "(1/2)"), ("¼", "(1/4)"), ("¾", "(3/4)"),
            ("≠", "!="), ("′", "'"), ("ʹ", "'"), ("’", "'"),
        ]
        for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
        text = String(text.map { lookalikes[$0] ?? $0 })
        let superscripts: [Character: String] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5",
                                                 "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "ⁿ": "n", "ˣ": "x"]
        let subscripts: [Character: String] = ["₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5",
                                               "₆": "6", "₇": "7", "₈": "8", "₉": "9"]
        var result = ""
        var inSuperscript = false, inSubscript = false
        for character in text {
            if let digit = superscripts[character] {
                if !inSuperscript { result += "^(" }
                result += digit
                inSuperscript = true
                continue
            }
            if inSuperscript { result += ")"; inSuperscript = false }
            if let digit = subscripts[character] {
                if !inSubscript { result += "_" }
                result += digit
                inSubscript = true
                continue
            }
            inSubscript = false
            result.append(character)
        }
        if inSuperscript { result += ")" }
        // Thousands separators: 1,234,567
        result = result.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Tokens

enum Token: Equatable {
    case number(Rational?, Double, String)
    case symbol(String)
    case constant(MathConstant)
    case function(MathFunction)
    case root(Int)
    case sqrtWord
    case expWord
    case op(Character)
}

enum Tokenizer {
    static let functionNames: [(String, MathFunction?)] = [
        ("arcsin", .asin), ("arccos", .acos), ("arctan", .atan), ("asin", .asin), ("acos", .acos), ("atan", .atan),
        ("sinh", .sinh), ("cosh", .cosh), ("tanh", .tanh), ("cosec", .csc),
        ("sin", .sin), ("cos", .cos), ("tan", .tan), ("sec", .sec), ("csc", .csc), ("cot", .cot),
        ("ln", .ln), ("log", .log), ("abs", .abs), ("sqrt", nil), ("exp", nil), ("pi", nil),
    ]

    static func tokens(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == " " { index += 1; continue }
            if character.isASCII && character.isNumber || (character == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                var digits = ""
                while index < characters.count, characters[index].isASCII && characters[index].isNumber || characters[index] == "." {
                    digits.append(characters[index])
                    index += 1
                }
                guard digits.filter({ $0 == "." }).count <= 1, let value = Double(digits.hasPrefix(".") ? "0" + digits : digits)
                else { return nil }
                // Decimals stay decimals (4.5, not 9/2); whole numbers are exact.
                tokens.append(.number(digits.contains(".") ? nil : Rational.parse(digits), value, digits))
                continue
            }
            if character.isLetter {
                var word = ""
                while index < characters.count, characters[index].isLetter {
                    word.append(characters[index])
                    index += 1
                }
                guard let split = splitWord(word) else { return nil }
                tokens += split
                continue
            }
            switch character {
            case "π": tokens.append(.constant(.pi))
            case "√": tokens.append(.root(2))
            case "∛": tokens.append(.root(3))
            case "∜": tokens.append(.root(4))
            case "+", "-", "*", "/", "^", "(", ")", "%", "!", "°", "|", "'", "_", ",":
                tokens.append(.op(character))
            default:
                return nil
            }
            index += 1
        }
        return tokens
    }

    /// "sinx" is sin x, "xy" is x × y, "2pi" is 2π.
    private static func splitWord(_ word: String) -> [Token]? {
        var tokens: [Token] = []
        var rest = Substring(word)
        while !rest.isEmpty {
            if let (name, function) = functionNames.first(where: { rest.lowercased().hasPrefix($0.0) }) {
                switch name {
                case "pi": tokens.append(.constant(.pi))
                case "sqrt": tokens.append(.sqrtWord)
                case "exp": tokens.append(.expWord)
                default: tokens.append(.function(function!))
                }
                rest = rest.dropFirst(name.count)
                continue
            }
            let letter = String(rest.first!)
            tokens.append(letter == "e" ? .constant(.e) : .symbol(letter))
            rest = rest.dropFirst()
        }
        return tokens
    }
}

// MARK: - Expression grammar

/// Loosest first:
///
///     sum     = term (("+" | "-") term)*
///     term    = signed (("*" | "/" | nothing) signed)*
///     signed  = ("-" | "+") signed | power
///     power   = postfix ("^" signed)?
///     postfix = primary ("%" | "!" | "°")*
///     primary = number | letter | constant | "(" sum ")" | "|" sum "|"
///             | function ["^" n] argument | "√" postfix | "sqrt" | "exp"
struct ExpressionParser {
    struct SyntaxError: Error {}

    private let tokens: [Token]
    private var position = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    /// A value, and if it's a bare percentage, the percentage: so 50 + 10% can mean 10% of 50.
    private struct Value {
        var expr: Expr
        var percent: Expr?
    }

    mutating func parseAll() throws -> Expr {
        let value = try sum()
        guard position == tokens.count else { throw SyntaxError() }
        return value.expr
    }

    private var current: Token? { position < tokens.count ? tokens[position] : nil }

    private mutating func take(_ symbol: Character) -> Bool {
        guard current == .op(symbol) else { return false }
        position += 1
        return true
    }

    private mutating func sum() throws -> Value {
        var left = try term()
        while true {
            let isPlus: Bool
            if take("+") { isPlus = true } else if take("-") { isPlus = false } else { return left }
            let right = try term()
            // Calculator percentages: 50 + 10% adds 10% of 50.
            let amount = right.percent.map { Expr.multiply([$0, .power(.integer(100), .minusOne), left.expr]) } ?? right.expr
            left = Value(expr: isPlus ? left.expr + amount : left.expr - amount)
        }
    }

    private mutating func term() throws -> Value {
        var left = try signed()
        while true {
            if take("*") || startsImplicitFactor() {
                let right = try signed()
                left = Value(expr: left.expr * right.expr)
            } else if take("/") {
                let right = try signed()
                left = Value(expr: left.expr / right.expr)
            } else {
                return left
            }
        }
    }

    /// 2x, 3(x + 1), (x + 1)(x − 1), x sin x, 2√3, 2π
    private func startsImplicitFactor() -> Bool {
        guard position > 0, let next = current else { return false }
        let previous = tokens[position - 1]
        switch next {
        case .symbol, .constant, .function, .root, .sqrtWord, .expWord, .op("("):
            return true
        case .number:
            if case .op(")") = previous { return true }
            return false
        default:
            return false
        }
    }

    private mutating func signed() throws -> Value {
        if take("-") {
            let value = try signed()
            return Value(expr: -value.expr, percent: value.percent.map { -$0 })
        }
        if take("+") { return try signed() }
        return try power()
    }

    private mutating func power() throws -> Value {
        let base = try postfix()
        guard take("^") else { return base }
        let exponent = try signed()
        return Value(expr: base.expr.raised(exponent.expr))
    }

    private mutating func postfix() throws -> Value {
        var value = try primary()
        while true {
            if take("%") {
                value = Value(expr: value.expr / .integer(100), percent: value.percent == nil ? value.expr : nil)
            } else if take("!") {
                guard let n = Simplify.run(value.expr).number?.integer, n >= 0, n <= 170 else { throw SyntaxError() }
                value = Value(expr: .number(factorial(n)))
            } else if take("°") {
                continue
            } else {
                return value
            }
        }
    }

    private func factorial(_ n: Int) -> Number {
        var result = Number.one
        for k in stride(from: 2, through: max(n, 1), by: 1) { result = result * .integer(k) }
        return result
    }

    private mutating func primary() throws -> Value {
        guard let token = current else { throw SyntaxError() }
        position += 1
        switch token {
        case .number(let rational, let value, _):
            return Value(expr: .number(rational.map(Number.exact) ?? .real(value)))
        case .symbol(let name):
            return Value(expr: .symbol(name))
        case .constant(let constant):
            return Value(expr: .constant(constant))
        case .op("("):
            let value = try sum()
            // A missing closing bracket at the very end is added, as calculators do.
            guard take(")") || current == nil else { throw SyntaxError() }
            return Value(expr: value.expr)
        case .op("|"):
            let value = try sum()
            guard take("|") else { throw SyntaxError() }
            return Value(expr: .function(.abs, value.expr))
        case .root(let n):
            let value = try postfix()
            return Value(expr: value.expr.raised(.fraction(1, n)))
        case .sqrtWord:
            return Value(expr: try argument().raised(.half))
        case .expWord:
            return Value(expr: Expr.constant(.e).raised(try argument()))
        case .function(let function):
            // sin²x, sin^2 x
            var exponent: Expr?
            if take("^") {
                guard case .number(let rational, let value, _)? = current else { throw SyntaxError() }
                position += 1
                exponent = .number(rational.map(Number.exact) ?? .real(value))
            }
            // log₂ 8
            var base: Expr?
            if function == .log, take("_") {
                guard case .number(let rational, let value, _)? = current else { throw SyntaxError() }
                position += 1
                base = .number(rational.map(Number.exact) ?? .real(value))
            }
            let x = try argument()
            var result: Expr = .function(function, x)
            if let base { result = .function(.ln, x) / .function(.ln, base) }
            if let exponent { result = result.raised(exponent) }
            return Value(expr: result)
        default:
            throw SyntaxError()
        }
    }

    /// What a function applies to: (…) or, without brackets, the next factors up to another
    /// function or an operator: sin 2x is sin(2x), but sin x cos x is sin(x) × cos(x).
    private mutating func argument() throws -> Expr {
        if current == .op("(") {
            position += 1
            let value = try sum()
            guard take(")") || current == nil else { throw SyntaxError() }
            // sin(x)² means (sin x)², handled by the caller's power.
            return value.expr
        }
        var factors = [try power().expr]
        while let next = current {
            switch next {
            case .symbol, .constant, .number:
                factors.append(try power().expr)
            default:
                return factors.count == 1 ? factors[0] : .multiply(factors)
            }
        }
        return factors.count == 1 ? factors[0] : .multiply(factors)
    }
}
