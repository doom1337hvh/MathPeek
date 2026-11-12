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
    /// What's left over when a whole number is divided by another: 2^2026 + 3^2026 mod 13.
    case remainder(Expr, modulus: Int)
    /// The first terms of a sequence, to find its nth term.
    case sequence([Expr])
    /// A diagram read from a picture, and the angle or side of it to find.
    case diagram(Diagram, find: String)
    /// A question in words whose answer isn't one sum: a table of values, shares of a ratio.
    /// The working is in the problem's lead.
    case worded(question: String, answers: [MathLine])
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
    /// Steps that come before the working: how a question in words became this maths.
    var lead: [Step] = []
    /// The answer is the number of a term in a sequence: a positive whole number.
    var wantsTermNumber = false
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

        // Questions in words about sequences: "The nth term is an² + bn. The 2nd term is 2 …"
        if let sequence = WordProblems.problem(input) { return sequence }

        // x² : (3x + 5) = 1 : 2: two ratios that are equal, so multiply across.
        if text.contains(":"), let regex = try? NSRegularExpression(pattern: #"^(?:solve |given that |given )?([^:=]+):([^:=]+)=([^:=]+):([^:=?]+?)[.? ]*$"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let sides = (1...4).compactMap { Range(match.range(at: $0), in: text).flatMap { expression(String(text[$0])) } }
            // (With one unknown: "a : b = 4 : 3" says how two amounts compare, and isn't an equation to solve.)
            if sides.count == 4, sides.reduce(Set<String>(), { $0.union($1.symbols) }).count == 1 {
                let left = Expr.multiply([sides[0], sides[3]]), right = Expr.multiply([sides[1], sides[2]])
                var problem = make(.solve([Equation(left: left, right: right)], unknowns: []))
                problem.lead = [Step("Multiply across", "Two ratios that are equal: a : b = c : d means a × d = b × c.", [MathLine(left, right)])]
                return problem
            }
        }

        // "2^10 mod 7", "the remainder when 2^10 is divided by 7"
        if let parts = remainderParts(text), let dividend = expression(parts.dividend),
           let modulus = Int(parts.modulus), modulus >= 2 {
            return make(.remainder(dividend, modulus: modulus))
        }

        // A full stop or question mark at the end isn't maths.
        while let last = text.last, "?. ".contains(last) { text.removeLast() }
        // "2 sin x = −1 for 0° ≤ x ≤ 360°": the range a trig equation is to be solved over,
        // where it's the one the answers are given in anyway. (Any other range is left, and
        // the equation with it: its answers would be other ones.)
        if text.range(of: #"\b(?:sin|cos|tan)\b"#, options: .regularExpression) != nil,
           let range = text.range(of: #"\s*,?\s*(?:for|where|in the range|given that)?\s*0 ?°?\s*(?:≤|<|⩽|<=)\s*[a-zθ] ?°?\s*(?:≤|<|⩽|<=)\s*360 ?°?$"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }

        // Words that lead up to the problem ("What is", "Find the"), then the instruction, if
        // there is one, then words that go with it ("fully", "and simplify").
        func take(_ words: [String]) -> String? {
            let lower = text.lowercased()
            for word in words where lower == word || lower.hasPrefix(word + " ") || lower.hasPrefix(word + ":") {
                text = String(text.dropFirst(word.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                return word
            }
            return nil
        }
        let leadIns = ["rationalise the denominator and simplify", "rationalize the denominator and simplify", "rationalise the denominator of", "rationalize the denominator of",
                       "rationalise the denominator", "rationalize the denominator", "rationalise", "rationalize",
                       "find the value of", "what is the value of", "work out the value of", "calculate the value of",
                       "what is", "what's", "find", "calculate", "work out", "evaluate", "compute", "determine",
                       "write down", "please", "the value of", "the", "hence"]
        while take(leadIns) != nil {}
        var command = take(["solve", "simplify", "expand and simplify", "expand", "factorise", "factorize", "factor",
                            "differentiate", "derivative of", "integrate", "integral of"]) ?? ""
        if command == "expand and simplify" { command = "expand" }
        if !command.isEmpty {
            while take(["fully", "completely", "the following", "the expression", "the simultaneous equations",
                        "simultaneous equations", "simultaneously", "the pair of equations", "the equations", "the equation",
                        "equations", "the brackets", "and simplify", "the", "each of", "these"]) != nil {}
        }
        var unknowns: [String] = []
        // "Solve for x: 5x − 2 = 13"
        if command == "solve", let range = text.range(of: #"^for\s+[a-zA-Zα-ω]\s*[:,]\s*"#, options: .regularExpression) {
            unknowns = [String(text[range].dropFirst(3).first { $0.isLetter }!)]
            text = String(text[range.upperBound...])
        }

        // "f(x) = 3x + 2. Find f(4)", "Given that f(x) = x² − 3, find x when f(x) = 6"
        if let regex = try? NSRegularExpression(pattern: #"^(?:given\s+(?:that\s+)?)?([a-zA-Z])\s*\(\s*([a-zA-Z])\s*\)\s*=\s*(.+?)[.;,]\s+(.+)$"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let nameRange = Range(match.range(at: 1), in: text), let variableRange = Range(match.range(at: 2), in: text),
           let bodyRange = Range(match.range(at: 3), in: text), let restRange = Range(match.range(at: 4), in: text),
           let body = expression(String(text[bodyRange])) {
            let name = NSRegularExpression.escapedPattern(for: String(text[nameRange])), variable = String(text[variableRange])
            let rest = String(text[restRange]).replacingOccurrences(
                of: #"^(?i)(find|work out|calculate|evaluate|what is|write down|solve|hence)\s+(the value of\s+)?(\#(variable)\s+(when|if|given that)\s+)?"#,
                with: "", options: .regularExpression)
            let call = "^" + name + #"\s*\((.+)\)"#
            if rest.range(of: call + "$", options: .regularExpression) != nil,
               let open = rest.firstIndex(of: "("), let value = expression(String(rest[rest.index(after: open)...].dropLast())) {
                return make(.substitute(body, values: [variable: value]))
            }
            if let equals = rest.range(of: call + #"\s*=\s*"#, options: .regularExpression),
               let value = expression(String(rest[equals.upperBound...])) {
                return make(.solve([Equation(left: body, right: value)], unknowns: [variable]))
            }
        }

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
            // "y when x = 10" has no x to put 10 into: it's the end of a longer question.
            guard let formula = expression(text), !values.isEmpty, !formula.symbols.isDisjoint(with: values.keys) else { return nil }
            return make(.substitute(formula, values: values))
        }

        // "solve … for x"
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
        if let range = text.range(of: #"^d(\^?\(?2\)?|²)?\s*[a-zA-Z]?\s*/\s*d\s*([a-zA-Z])(\^?\(?2\)?|²)?"#, options: .regularExpression) {
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
                // Several equations on a line, with commas or "and" between them.
                guard piece.filter({ $0 == "=" }).count > 1 else { return [piece] }
                return piece.replacingOccurrences(of: #"\s+and\s+"#, with: ",", options: .regularExpression)
                    .split(separator: ",").map { Substring($0) }
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

    /// A question about a remainder, however it's worded: what's divided, what by, and where
    /// in the text the question is.
    static func remainderParts(_ text: String) -> (dividend: String, modulus: String, range: Range<String.Index>)? {
        let patterns = [
            #"remainder\s+(?:on|after|from|when)\s+dividing\s+(.+?)\s+by\s+(\d+)"#,
            #"remainder\s+(?:when|if|of)?\s*(.+?),?\s+(?:is\s+|are\s+|was\s+)?divided\s+by\s+(\d+)"#,
            #"(?:when|if)\s+(.+?)\s+is\s+divided\s+by\s+(\d+)[^.;]*?remainder"#,
            #"(?:^|(?<=[\s¦:]))([^¦a-zA-Z]*[\d)][^¦]*?)\s*\(?\s*\bmod(?:ulo)?\s+(\d+)\s*\)?"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(match.range, in: text), let dividend = Range(match.range(at: 1), in: text),
                  let modulus = Range(match.range(at: 2), in: text) else { continue }
            let trimmed = text[dividend].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",:")))
            guard !trimmed.isEmpty else { continue }
            return (trimmed, String(text[modulus]), whole)
        }
        return nil
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
        "З": "3", "з": "3", "п": "π", "П": "π", "І": "I", "Ι": "I", "О": "O", "Т": "T", "Р": "P", "Н": "H", "К": "K", "М": "M",
        "ѕ": "s", "ԁ": "d", "ı": "i",
    ]

    /// Writes the many ways maths is typed or read in one way.
    static func normalize(_ input: String) -> String {
        var text = input
        // "3/4 ÷ 2/5" is one fraction divided by another, not 3 ÷ 4 ÷ 2 ÷ 5: beside a
        // division sign, a number over a number is kept together.
        if text.contains("÷") {
            // (A mixed number first: 2 1/3 ÷ 1 1/4 is two and a third divided by one and a quarter,
            // not 2 times a third.)
            text = text.replacingOccurrences(of: #"(?<![\d/.^])(\d+)\s+(\d+)\s*/\s*(\d+)(?![\d.])"#, with: "($1+$2/$3)", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?<![\d.)/^])(\d+)\s?/\s?(\d+)(?![\d.(/^]|\s?[a-zA-Z(])"#, with: "($1/$2)", options: .regularExpression)
            // 4√6 ÷ 2√2 is 4√6 over 2√2, and 6x ÷ 2x is 6x over 2x: a number written against
            // a root or a letter is one thing to divide by.
            text = text.replacingOccurrences(of: #"÷\s*(\d+(?:\.\d+)?\s?√\s?(?:\d+(?:\.\d+)?|\([^()]*\))|\d+(?:\.\d+)?(?!sin|cos|tan|log|ln|pi)(?:[a-zA-Z](?:\^\d+|[²³])?){1,3})(?![\w(^√²³])"#,
                                                with: "÷($1)", options: .regularExpression)
        }
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
        // (A Cyrillic п is π, unless the sum is about n: "(6п)/(n² + 5)" has an n misread.)
        if text.range(of: #"(?<![a-zA-Z])n(?![a-zA-Z])"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: "п", with: "n")
        }
        text = String(text.map { lookalikes[$0] ?? $0 })
        // A recurring decimal, as the reader writes one: rec(0.1,5) is 0.1555…, the exact
        // fraction it stands for.
        if text.contains("rec("), let regex = try? NSRegularExpression(pattern: #"rec\((\d*)\.(\d*),(\d+)\)"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let whole = Range(match.range, in: text), let before = Range(match.range(at: 1), in: text), let fixed = Range(match.range(at: 2), in: text),
                      let recurring = Range(match.range(at: 3), in: text), text[fixed].count + text[recurring].count <= 15,
                      let units = Int(text[before].isEmpty ? "0" : String(text[before])), let still = Int(text[fixed].isEmpty ? "0" : String(text[fixed])),
                      let turning = Int(text[recurring]) else { continue }
                let shift = Int(pow(10, Double(text[fixed].count))), nines = Int(pow(10, Double(text[recurring].count))) - 1
                text.replaceSubrange(whole, with: "(\((units * shift + still) * nines + turning)/\(shift * nines))")
            }
        }
        // 80 000 000 is eighty million: a big number is written in groups of three with gaps
        // between (and reading closes some of the gaps: "80 000000"). Only in a sum, where
        // a row of separate numbers wouldn't be.
        if text.range(of: #"[+*/=^%]|\d ?- ?\d|\bof\b"#, options: .regularExpression) != nil {
            for _ in 0..<6 {
                let joined = text.replacingOccurrences(of: #"(?<![\d.,/^])(\d{1,3}(?:\d{3})*) ((?:\d{3})+)(?![\d./])"#, with: "$1$2", options: .regularExpression)
                if joined == text { break }
                text = joined
            }
        }
        // Words that stand for maths: 15% of 80, the square root of 81, 5 squared.
        let phrases: [(String, String)] = [
            (#"(?i)\b(the\s+)?square\s+root\s+of\s+"#, "√"), (#"(?i)\b(the\s+)?cube\s+root\s+of\s+"#, "∛"),
            (#"(?i)\s+squared\b"#, "^2"), (#"(?i)\s+cubed\b"#, "^3"),
            // 25% of 280 is one amount, whatever it's then divided into or multiplied by.
            (#"(?i)(?<![\d.])(\d+(?:\.\d+)?)\s*%\s+of\s+(\d+(?:\.\d+)?)(?![\d.]|\s*[\^²³])"#, "($1% * $2)"),
            (#"(?i)(?<=[\d%)])\s+of\s+(?=[\d(√])"#, " * "),
            // Increase 60 by 20% is 60 + 20%.
            (#"(?i)\bincrease\s+(\d+(?:\.\d+)?)\s+by\s+(\d+(?:\.\d+)?\s*%)"#, "$1 + $2"),
            (#"(?i)\b(?:decrease|reduce)\s+(\d+(?:\.\d+)?)\s+by\s+(\d+(?:\.\d+)?\s*%)"#, "$1 - $2"),
            // Mixed numbers: 2 1/2 is 2 + 1/2.
            (#"(?<![\d/.^])(\d+)\s+(\d+)\s*/\s*(\d+)(?![\d.])"#, "($1+$2/$3)"),
        ]
        for (pattern, replacement) in phrases {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
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
            if character == "π" {
                tokens.append(.constant(.pi))
                index += 1
                continue
            }
            if character.isLetter {
                var word = ""
                while index < characters.count, characters[index].isLetter, characters[index] != "π" {
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
    /// Short words that are words, never letters multiplied together. ("at", "an" and "by"
    /// aren't here: v = u + at, an² + bn and ax + by are maths.)
    private static let plainWords: Set<String> = ["of", "or", "on", "the", "and", "for", "are", "was", "not", "but", "all", "can", "has", "had",
                                                  "its", "out", "how", "why", "who", "use", "per", "you", "your", "from", "with"]

    private static func splitWord(_ word: String) -> [Token]? {
        guard !plainWords.contains(word.lowercased()) else { return nil }
        var tokens: [Token] = []
        var rest = Substring(word)
        var letters = 0
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
            // xyz is x × y × z, but a longer run of letters is a word, not maths.
            letters += 1
            if letters > 3 { return nil }
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
            if take("-") {
                let value = try postfix()
                return Value(expr: (-value.expr).raised(.fraction(1, n)))
            }
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
                let bracketed = take("(")
                guard case .number(let rational, let value, _)? = current else { throw SyntaxError() }
                position += 1
                if bracketed { guard take(")") else { throw SyntaxError() } }
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
