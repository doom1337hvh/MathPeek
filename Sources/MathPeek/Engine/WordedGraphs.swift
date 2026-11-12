import Foundation

/// Graphs and coordinates asked in words: midpoints, gradients, the line through two points, parallel and perpendicular lines, a graph moved or reflected, where curves and lines meet.
/// Tried after `Worded.problem`, on the same text: the lines of the question the pointer is
/// in, joined by line breaks. Nil unless the whole of the question is understood.
enum WordedGraphs {
    static func problem(_ input: String) -> Problem? {
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let question = read(display), question.text.count <= 700 else { return nil }
        // Two lines' gradients compared, a "show that" among them: the check is the answer.
        if let found = compared(question) {
            // A misread taken back is only trusted where the question's own claim comes out true.
            guard !question.guessed || found.confirmsClaim else { return nil }
            var problem = Problem(kind: .worded(question: found.answer.question, answers: found.answer.lines), text: display, usesDecimals: false)
            problem.lead = found.answer.steps
            return problem
        }
        guard !question.guessed else { return nil }
        // A question that asks for a proof, a reason or a drawing isn't asking for the number its words would give.
        guard !has(refusal, question.text) else { return nil }
        let kinds: [(Question) -> Answer?] = [crossing, lineEquation, liesOn, meeting, divided, spaced, midpointEnd, gradient, length, unknownCoordinate, tangent, valueAt, circleEquation, coefficient, quadraticFromAxes, lettersFixed, axisChoice]
        var found: [Answer] = []
        for kind in kinds { if let answer = kind(question) { found.append(answer) } }
        // Two kinds that each think they're asked: the area holds more than one question.
        guard found.count == 1, var answer = found.first else { return nil }
        // Every point and every line in the question has to have been used.
        let points = Set(question.pairs.map(\.point))
        guard points.isSubset(of: answer.usedPoints), question.equations.count == answer.usedEquations else { return nil }
        // Answers to choose from: the one worked out has to be among them.
        if !question.choicePairs.isEmpty || !question.choiceLines.isEmpty {
            guard let picked = answer.pick(question) else { return nil }
            answer = picked
        }
        var problem = Problem(kind: .worded(question: answer.question, answers: answer.lines), text: display, usesDecimals: false)
        problem.lead = answer.steps
        return problem
    }

    // MARK: Exact fractions

    /// A fraction that stays exact. One that overflowed is invalid, and so is all that's worked out from it.
    private struct F: Hashable {
        let n: Int
        let d: Int

        init(_ n: Int, _ d: Int = 1) {
            guard d != 0, n != .min, d != .min, abs(n) < 1 << 40, abs(d) < 1 << 40 else { self.n = 0; self.d = 0; return }
            let g = F.gcd(abs(n), abs(d))
            let sign = d < 0 ? -1 : 1
            self.n = sign * n / max(g, 1)
            self.d = sign * d / max(g, 1)
        }

        static let invalid = F(0, 0)
        var isValid: Bool { d != 0 }
        var isZero: Bool { isValid && n == 0 }
        var isInteger: Bool { isValid && d == 1 }
        var double: Double { Double(n) / Double(d) }

        static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

        private static func make(_ n: (Int, Bool), _ d: (Int, Bool)) -> F { n.1 || d.1 ? .invalid : F(n.0, d.0) }

        static func + (a: F, b: F) -> F {
            guard a.isValid, b.isValid else { return .invalid }
            let left = a.n.multipliedReportingOverflow(by: b.d), right = b.n.multipliedReportingOverflow(by: a.d)
            guard !left.overflow, !right.overflow else { return .invalid }
            return make(left.partialValue.addingReportingOverflow(right.partialValue), a.d.multipliedReportingOverflow(by: b.d))
        }
        static prefix func - (a: F) -> F { a.isValid ? F(-a.n, a.d) : .invalid }
        static func - (a: F, b: F) -> F { a + -b }
        static func * (a: F, b: F) -> F {
            guard a.isValid, b.isValid else { return .invalid }
            return make(a.n.multipliedReportingOverflow(by: b.n), a.d.multipliedReportingOverflow(by: b.d))
        }
        static func / (a: F, b: F) -> F {
            guard a.isValid, b.isValid, b.n != 0 else { return .invalid }
            return a * F(b.d, b.n)
        }

        /// "3", "-2.5", "7/2".
        static func parse(_ text: String) -> F? {
            let plain = text.replacingOccurrences(of: " ", with: "")
            if let slash = plain.firstIndex(of: "/") {
                guard let top = parse(String(plain[..<slash])), let bottom = parse(String(plain[plain.index(after: slash)...])), !bottom.isZero else { return nil }
                let value = top / bottom
                return value.isValid ? value : nil
            }
            guard plain.range(of: #"^-?\d{1,7}(?:\.\d{1,6})?$"#, options: .regularExpression) != nil else { return nil }
            let negative = plain.hasPrefix("-")
            let digits = negative ? String(plain.dropFirst()) : plain
            let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
            guard let whole = Int(parts[0]) else { return nil }
            var value = F(whole)
            if parts.count == 2, let tail = Int(parts[1]) { value = value + F(tail, Int(pow(10, Double(parts[1].count)))) }
            return negative ? -value : value
        }

        init?(_ number: Number) {
            guard let rational = number.rational else { return nil }
            self.init(rational.numerator, rational.denominator)
            guard isValid else { return nil }
        }

        var expr: Expr { d == 1 ? .integer(n) : .fraction(n, d) }

        /// Written the way a coordinate is: whole, a decimal where it ends within three places, a fraction otherwise.
        var written: String {
            if d == 1 { return n < 0 ? "−\(-n)" : "\(n)" }
            var rest = d
            for p in [2, 5] { while rest % p == 0 { rest /= p } }
            if rest == 1, d <= 1000 {
                var text = String(format: "%.3f", double)
                while text.hasSuffix("0") { text.removeLast() }
                return text.replacingOccurrences(of: "-", with: "−")
            }
            // Not "/": in a symbol that's drawn as a fraction.
            return Format.text(expr).replacingOccurrences(of: "/", with: "∕")
        }

        /// The square root, if it's a fraction too.
        var root: F? {
            guard isValid, n >= 0 else { return nil }
            func whole(_ v: Int) -> Int? {
                let r = Int(Double(v).squareRoot().rounded())
                return r * r == v ? r : nil
            }
            guard let top = whole(n), let bottom = whole(d) else { return nil }
            return F(top, bottom)
        }
    }

    private struct Point: Hashable {
        var x: F
        var y: F
        var written: String { "(\(x.written), \(y.written))" }
        /// With fractions, the way answers to choose from are written when they have them.
        var asFractions: String { "(\(x.d == 1 ? x.written : Format.text(x.expr)), \(y.d == 1 ? y.written : Format.text(y.expr)))".replacingOccurrences(of: "/", with: "∕") }
        var isValid: Bool { x.isValid && y.isValid }
    }

    // MARK: Reading the question

    private struct Pair {
        var point: Point
        /// The letter it's called by, if it has one: "A (2, 7)".
        var name: String?
        var at: Int
    }

    private struct Equation {
        var left: Expr
        var right: Expr
        var source: String
        var at: Int
        /// The equation as left − right = 0.
        var zero: Expr { Simplify.run(left - right) }
    }

    private struct Question {
        var text: String
        var pairs: [Pair]
        var equations: [Equation]
        var choicePairs: [Point]
        var choiceLines: [Equation]
        var named: [String: Point]
        /// What the answer's form is asked to be: "y = mx + c".
        var form: String?
        /// The answers to choose from are written with fractions.
        var choicesInFractions = false
        /// A 5 read as S was taken back for a 5 ("Sy − 10x + 4 = 0"): only good enough where the question's own claim checks it.
        var guessed = false
    }

    private static let refusal = #"\bshow that\b|\bprove\b|\bexplain\b|\bgive (?:a|one|two|your) reasons?\b|\btick\b|\bdraw\b|(?<!\ba )\bsketch\b(?! of\b)|\bplot\b|\bshade\b|\bconstruct\b|\bdescribe\b|\bestimates?\b|\bus(?:e|ing) the (?:graphs?|grids?|diagrams?)\b|\bon the grid\b|\bcomplete the\b|\bmark (?:the|with|a)\b|\blabel\b"#

    private static let number = #"-?\d+(?:\.\d+)?(?:/\d+)?"#
    private static let pair = #"\(\s*(\#(number))\s*,\s*(\#(number))\s*\)"#

    private static func read(_ display: String) -> Question? {
        var raw = display
        for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "), ("\u{FFFC}", " "),
                           ("⩽", "≤"), ("⩾", "≥"), ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""), ("×", "*"), ("÷", "/")] { raw = raw.replacingOccurrences(of: from, with: to) }
        let raised: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
        var plain = "", inPower = false
        for character in raw {
            if let digit = raised[character] {
                if !inPower { plain += "^("; inPower = true }
                plain.append(digit)
            } else {
                if inPower { plain += ")"; inPower = false }
                plain.append(character)
            }
        }
        if inPower { plain += ")" }
        raw = plain.replacingOccurrences(of: #"\^\((\d)\)"#, with: "^$1", options: .regularExpression)
        // Letters from other alphabets read for ones that look the same.
        let alike: [Character: Character] = ["а": "a", "А": "A", "В": "B", "в": "b", "С": "C", "с": "c", "Е": "E", "е": "e", "Н": "H", "К": "K", "к": "k", "М": "M", "О": "O", "о": "o", "Р": "P", "р": "p",
                                              "Т": "T", "Х": "X", "х": "x", "У": "Y", "у": "y", "ѕ": "s", "і": "i", "ј": "j", "З": "3", "з": "3", "п": "n"]
        raw = String(raw.map { alike[$0] ?? $0 })
        var lines: [String] = []
        for piece in raw.components(separatedBy: "\n") {
            var line = piece.trimmingCharacters(in: .whitespaces)
            // The margin's "Do not write outside the box", read in pieces, and other words round the question.
            if line.range(of: #"^(?:do not(?: write)?|outsid.?(?: the)?(?: box)?|the box|box|b[oо][:;]?|write|not drawn|accurately|not drawn accurately|turn over.*|pmt)$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if line.range(of: #"^\d{1,2}$|^\d{1,2} ?\([a-z]\)(?: ?\([ivx]+\))?$|^\([a-z]\)$"#, options: .regularExpression) != nil { continue }
            if line.range(of: #"^Answer\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            line = line.replacingOccurrences(of: #"^\d{1,2}\s*(?:\([a-z]\)\s*)?(?:\([ivx]+\)\s*)?(?=[A-Z(])"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"[\[|I]\s*\d+\s*mark[se]?l?s?\s*[\]|1lI]?"#, with: " ", options: [.regularExpression, .caseInsensitive])
            if !line.isEmpty { lines.append(line) }
        }
        // The text twice: run together, and with its line breaks kept for finding equations (one doesn't run on into the next line's).
        func tidied(_ joined: String) -> String {
            var t = joined.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            // A nought read as a capital O inside a pair of coordinates.
            t = t.replacingOccurrences(of: #"\(\s*O\s*,"#, with: "(0,", options: .regularExpression)
            t = t.replacingOccurrences(of: #",\s*O\s*\)"#, with: ", 0)", options: .regularExpression)
            // "x − y = O": a nought on its own after an equals sign.
            t = t.replacingOccurrences(of: #"=\s*O(?![A-Za-z])"#, with: "= 0", options: .regularExpression)
            return t
        }
        var text = tidied(lines.joined(separator: " ")), lined = tidied(lines.joined(separator: "\n"))
        // A 5 read as a capital S, stuck to x or y: "Sy − 10x + 4 = 0".
        let five = #"(?<![A-Za-z])S(?=[xy](?![A-Za-z]))"#
        let guessed = text.range(of: five, options: .regularExpression) != nil
        if guessed {
            text = text.replacingOccurrences(of: five, with: "5", options: .regularExpression)
            lined = lined.replacingOccurrences(of: five, with: "5", options: .regularExpression)
        }
        // Any other capital stuck to x or y ("Zy − 3x = 1"): an equation would be read with a term cut off.
        guard text.range(of: #"(?<![A-Za-z])[A-Z][xy](?![A-Za-z])\s*[-+=]"#, options: .regularExpression) == nil else { return nil }
        // The form the answer is to be given in isn't an equation of the question's.
        var form: String?
        let formPattern = #"(?i)\b(?:give|giving|write|writing) (?:your answer|it|the equation) in the form\s+(.+?)(?=$|\.\s|\s(?:Circle|Work|Find|Write)\b)"#
        if let range = text.range(of: formPattern, options: .regularExpression) {
            form = String(text[range]).replacingOccurrences(of: #"(?i)^.*?in the form\s+"#, with: "", options: .regularExpression).replacingOccurrences(of: " ", with: "")
            // Words after the form ("y = mx + c 12 ma rbol", "ax + by + c = 0 where a, b and c are integers").
            for known in ["y=mx+c", "ax+by+c=0"] where form!.lowercased().hasPrefix(known) { form = known }
            text.replaceSubrange(range, with: " ")
        }
        if let range = lined.range(of: formPattern.replacingOccurrences(of: "$|", with: "$|\n|"), options: [.regularExpression]) { lined.replaceSubrange(range, with: " ") }
        guard text.count >= 12 else { return nil }

        // Where the answers to choose from start: after the sentence that says to circle one.
        var choicesFrom = text.endIndex
        if let circle = text.range(of: #"(?i)\bcircle (?:the|your)\b[^.?]*[.?]?"#, options: [.regularExpression, .backwards]) { choicesFrom = circle.upperBound }
        let cut = text.distance(from: text.startIndex, to: choicesFrom)

        var pairs: [Pair] = [], choicePairs: [Point] = []
        var named: [String: Point] = [:]
        for match in matches(pair, in: text) {
            guard let x = F.parse(match.groups[1]), let y = F.parse(match.groups[2]) else { return nil }
            let point = Point(x: x, y: y)
            if match.at >= cut { choicePairs.append(point); continue }
            // The letter just before it: "A (2, 7)", "B is (4, -9)", "the coordinates of A are (2, 7)", "is the point".
            let before = String(text[..<text.index(text.startIndex, offsetBy: match.at)])
            var name: String?
            if let found = groups(#"(?:^|[^A-Za-z])((?-i:[A-Z]))\s*(?:is|=|is the point|is at|has coordinates|are)?\s*$"#, in: before) { name = found[1] }
            if name == nil, let found = groups(#"coordinates of ((?-i:[A-Z])) are\s*$"#, in: before) { name = found[1] }
            if let name {
                if let known = named[name], known != point { return nil }
                named[name] = point
            }
            pairs.append(Pair(point: point, name: name, at: match.at))
        }
        var equations: [Equation] = [], choiceLines: [Equation] = []
        var linedCut = lined.endIndex
        if let circle = lined.range(of: #"(?i)\bcircle (?:the|your)\b[^.?\n]*[.?]?"#, options: [.regularExpression, .backwards]) { linedCut = circle.upperBound }
        let linedAt = lined.distance(from: lined.startIndex, to: linedCut)
        for equation in findEquations(in: lined) {
            // "y = x + 6x − 2": nobody writes two terms alike; a power was lost in the reading.
            guard !hasLikeTerms(equation.source) else { return nil }
            // A form written out ("y = mx + c", "ax + by + c = 0") isn't one of the question's equations.
            if ["y=mx+c", "ax+by+c=0", "y=ax^2+bx+c"].contains(equation.source.replacingOccurrences(of: " ", with: "").lowercased()) { continue }
            if equation.at >= linedAt { choiceLines.append(equation) } else { equations.append(equation) }
        }
        return Question(text: text, pairs: pairs, equations: equations, choicePairs: choicePairs, choiceLines: choiceLines, named: named, form: form,
                        choicesInFractions: String(text[choicesFrom...]).contains("/"), guessed: guessed)
    }

    /// Two terms alike on one side of an equation written without brackets ("x + 6x − 2"): never how a question writes it.
    private static func hasLikeTerms(_ source: String) -> Bool {
        let raised = source.replacingOccurrences(of: #"(?<![\^.])([xy])(\d)(?![\d.])"#, with: "$1^$2", options: .regularExpression)
        for side in raised.components(separatedBy: "=") where !side.contains("(") {
            var seen = Set<String>()
            for term in side.components(separatedBy: CharacterSet(charactersIn: "+-")) {
                let key = term.filter { !" .*/^0123456789".contains($0) }
                let power = term.range(of: #"\^\d+"#, options: .regularExpression).map { String(term[$0]) } ?? ""
                let name = key.isEmpty && term.trimmingCharacters(in: .whitespaces).isEmpty ? nil : key + power
                guard let name else { continue }
                if !seen.insert(name).inserted { return true }
            }
        }
        return false
    }

    /// Every equation written in the text: "y = 3x - 6", "x^2 + y^2 = 53", "2y = 10x + 4".
    private static func findEquations(in text: String) -> [Equation] {
        let characters = Array(text)
        func allowed(_ index: Int) -> Bool {
            let c = characters[index]
            if c.isNumber || " .^+-()/*".contains(c) { return true }
            guard c.isLetter else { return false }
            // A letter on its own, not part of a word; or a letter times x ("kx", "bx"), or xy.
            guard c.isLowercase else { return false }
            var start = index, end = index
            while start > 0, characters[start - 1].isLetter { start -= 1 }
            while end + 1 < characters.count, characters[end + 1].isLetter { end += 1 }
            if start == end { return true }
            let word = String(characters[start...end])
            return word.range(of: #"^(?:[abcdkmnpqt]x|xy)$"#, options: .regularExpression) != nil
        }
        var found: [Equation] = []
        for (index, character) in characters.enumerated() where character == "=" {
            var start = index, end = index + 1
            while start > 0, allowed(start - 1) { start -= 1 }
            while end < characters.count, allowed(end) { end += 1 }
            var left = String(characters[start..<index])
            // The last equation's right side, in a row of them: only the last term is this one's left side.
            if start > 0, characters[start - 1] == "=", let last = left.range(of: #"[-+]?\s*\d*\s*[a-z](?:\^\d)?\s*$"#, options: .regularExpression) { left = String(left[last]) }
            left = left.trimmingCharacters(in: CharacterSet(charactersIn: " +-*/(."))
            var right = String(characters[(index + 1)..<end])
            // The next equation's left side, in a row of them: "y = 3x - 2 y = 5x".
            if end < characters.count, characters[end] == "=" {
                right = right.replacingOccurrences(of: #"\s+[-+]?\s*\d*\s*[a-z](?:\^\d)?\s*$"#, with: "", options: .regularExpression)
            }
            right = right.trimmingCharacters(in: CharacterSet(charactersIn: " +*/.)"))
            // A bracket left open at the start or the end belongs to the words round it.
            func balanced(_ s: String) -> String {
                var t = s
                while t.filter({ $0 == ")" }).count > t.filter({ $0 == "(" }).count, let last = t.lastIndex(of: ")") { t.remove(at: last); t = t.trimmingCharacters(in: .whitespaces) }
                while t.filter({ $0 == "(" }).count > t.filter({ $0 == ")" }).count, let first = t.firstIndex(of: "(") { t.remove(at: first); t = t.trimmingCharacters(in: .whitespaces) }
                return t
            }
            left = balanced(left); right = balanced(right)
            // A power that dropped onto the line: x2 is x², y2 is y².
            func raise(_ s: String) -> String { s.replacingOccurrences(of: #"(?<![\^.])([xy])(\d)(?![\d.])"#, with: "$1^$2", options: .regularExpression) }
            guard !left.isEmpty, !right.isEmpty, let l = Parser.expression(raise(left)), let r = Parser.expression(raise(right)) else { continue }
            let symbols = l.symbols.union(r.symbols)
            guard !symbols.isEmpty, symbols.contains("x") || symbols.contains("y") else { continue }
            found.append(Equation(left: l, right: r, source: "\(left) = \(right)", at: start))
        }
        return found
    }

    // MARK: Lines and curves

    /// A straight line a x + b y + c = 0.
    private struct Line: Hashable {
        var a: F
        var b: F
        var c: F

        init(a: F, b: F, c: F) { (self.a, self.b, self.c) = (a, b, c) }

        /// Through two different points.
        init?(_ p: Point, _ q: Point) {
            guard p != q else { return nil }
            a = q.y - p.y
            b = p.x - q.x
            c = -(a * p.x + b * p.y)
            guard isValid else { return nil }
        }

        /// Gradient m through a point.
        init(gradient m: F, through p: Point) {
            a = m; b = F(-1); c = p.y - m * p.x
        }

        var isValid: Bool { a.isValid && b.isValid && c.isValid && !(a.isZero && b.isZero) }
        var isVertical: Bool { b.isZero }
        var gradient: F? { isVertical ? nil : -a / b }
        var intercept: F? { isVertical ? nil : -c / b }

        func has(_ p: Point) -> Bool { (a * p.x + b * p.y + c).isZero }

        func same(as other: Line) -> Bool {
            // Proportional coefficients.
            (a * other.b - b * other.a).isZero && (a * other.c - c * other.a).isZero && (b * other.c - c * other.b).isZero
        }

        /// y = mx + c, or x = k.
        var answer: MathLine {
            if let m = gradient, let k = intercept {
                // In the order y = mx + c is written, x term first.
                let slope = Simplify.run(m.expr * .symbol("x"))
                if m.isZero { return MathLine(.symbol("y"), k.expr) }
                return MathLine(.symbol("y"), k.isZero ? slope : .add([slope, k.expr]))
            }
            return MathLine(.symbol("x"), (-c / a).expr)
        }

        var written: String { answer.text }
    }

    /// An equation as a straight line in x and y, if it is one.
    private static func straight(_ equation: Equation) -> Line? {
        let zero = equation.zero
        guard zero.symbols.isSubset(of: ["x", "y"]), !zero.symbols.isEmpty else { return nil }
        func at(_ x: Int, _ y: Int) -> F? {
            let value = Simplify.run(zero.substituting("x", with: .integer(x)).substituting("y", with: .integer(y)))
            return value.number.flatMap(F.init)
        }
        guard let c = at(0, 0), let ax = at(1, 0), let by = at(0, 1), let far = at(2, 3), let other = at(-3, 5) else { return nil }
        let a = ax - c, b = by - c
        // Straight: the same steps everywhere.
        guard far == c + F(2) * a + F(3) * b, other == c + F(-3) * a + F(5) * b else { return nil }
        let line = Line(a: a, b: b, c: c)
        return line.isValid ? line : nil
    }

    /// y = f(x), with f a polynomial: the equation's x-coefficients, constant first.
    private static func curve(_ equation: Equation) -> [F]? {
        var f: Expr
        if equation.left == .symbol("y"), !equation.right.symbols.contains("y") { f = equation.right }
        else if equation.right == .symbol("y"), !equation.left.symbols.contains("y") { f = equation.left }
        else { return nil }
        f = Simplify.run(f)
        guard f.symbols.isSubset(of: ["x"]), let polynomial = Polynomial(f, in: "x") else { return nil }
        var coefficients: [F] = []
        for k in 0...max(polynomial.degree, 0) {
            let r = polynomial.coefficient(k)
            let value = F(r.numerator, r.denominator)
            guard value.isValid else { return nil }
            coefficients.append(value)
        }
        return coefficients
    }

    /// x² + y² = r²: the square of the radius.
    private static func circle(_ equation: Equation) -> F? {
        let zero = equation.zero
        guard zero.symbols == ["x", "y"], let inX = Polynomial(zero.substituting("y", with: .zero), in: "x"), let inY = Polynomial(zero.substituting("x", with: .zero), in: "y"),
              inX.degree == 2, inY.degree == 2, inX.coefficient(1).isZero, inY.coefficient(1).isZero else { return nil }
        let k = F(inX.coefficient(2).numerator, inX.coefficient(2).denominator)
        guard k == F(inY.coefficient(2).numerator, inY.coefficient(2).denominator), !k.isZero else { return nil }
        // No xy term: the value at (1, 1) is what the squares alone give.
        guard let both = Simplify.run(zero.substituting("x", with: .one).substituting("y", with: .one)).number.flatMap(F.init),
              let constant = Simplify.run(zero.substituting("x", with: .zero).substituting("y", with: .zero)).number.flatMap(F.init),
              both == constant + k + k else { return nil }
        let r2 = -constant / k
        return r2.isValid && r2.double > 0 ? r2 : nil
    }

    /// The rational roots of a polynomial of degree 1 or 2, smallest first. Nil if it has roots that aren't fractions.
    private static func roots(_ coefficients: [F]) -> [F]? {
        var c = coefficients
        while let last = c.last, last.isZero { c.removeLast() }
        switch c.count {
        case 2:
            let root = -c[0] / c[1]
            return root.isValid ? [root] : nil
        case 3:
            let disc = c[1] * c[1] - F(4) * c[2] * c[0]
            guard disc.isValid else { return nil }
            if disc.double < 0 { return [] }
            guard let s = disc.root else { return nil }
            let one = (-c[1] - s) / (F(2) * c[2]), two = (-c[1] + s) / (F(2) * c[2])
            guard one.isValid, two.isValid else { return nil }
            return one == two ? [one] : [one, two].sorted { $0.double < $1.double }
        default:
            return nil
        }
    }

    private static func value(_ coefficients: [F], at x: F) -> F {
        coefficients.reversed().reduce(F(0)) { $0 * x + $1 }
    }

    // MARK: The answer

    private struct Answer {
        var question: String
        var lines: [MathLine]
        var steps: [Step]
        var usedPoints: Set<Point>
        var usedEquations: Int
        /// The answer as points or a line, for matching it to the choices.
        var points: [Point] = []
        var line: Line?

        /// The answer picked out of the choices, or nil if it isn't among them.
        func pick(_ question: Question) -> Answer? {
            if let line, !question.choiceLines.isEmpty {
                let offered = question.choiceLines.compactMap { WordedGraphs.straight($0) }
                guard offered.count == question.choiceLines.count, offered.filter({ $0.same(as: line) }).count == 1 else { return nil }
                return self
            }
            if points.count == 1, !question.choicePairs.isEmpty {
                // Some choices may have been misread; the answer has to be one of those read.
                guard question.choicePairs.contains(points[0]) || question.choicePairs.count < 4 else { return nil }
                var picked = self
                if question.choicesInFractions { picked.lines = points.map { MathLine(.symbol($0.asFractions)) } }
                return picked
            }
            return question.choicePairs.isEmpty && question.choiceLines.isEmpty ? self : nil
        }
    }

    private static func pointLine(_ p: Point) -> MathLine { MathLine(.symbol(p.written)) }

    // MARK: Where a graph crosses an axis

    /// "At what point does the graph y = x³ − 1 cross the y axis?", "the coordinates of the y-intercept".
    private static func crossing(_ q: Question) -> Answer? {
        guard let axis = groups(#"\b(?:cross(?:es)?|cuts?|meets?|intersects?|touch(?:es)?) the ([xy])[- ]?axis\b"#, in: q.text)?[1]
                ?? groups(#"\b([xy])[- ]intercepts?\b"#, in: q.text)?[1],
              q.equations.count == 1, q.pairs.isEmpty, every(#"\b[xy][- ]?(?:axis|intercept)"#, in: q.text).count == 1 else { return nil }
        // Asked.swift answers these wordings from the equation text recognition finds, with a graph to go with it.
        let lower = q.text.lowercased()
        guard !["y-intercept", "crosses the y-axis", "cuts the y-axis", "meets the y-axis", "intersects the y-axis",
                "x-intercept", "crosses the x-axis", "cuts the x-axis", "meets the x-axis", "intersects the x-axis"].contains(where: lower.contains) else { return nil }
        let equation = q.equations[0]
        let onY = axis.lowercased() == "y"
        if onY {
            let atZero: F
            if let line = straight(equation) {
                guard !line.isVertical, let c = line.intercept else { return nil }
                atZero = c
            } else if let f = curve(equation) {
                atZero = f[0]
            } else { return nil }
            let point = Point(x: F(0), y: atZero)
            return Answer(question: "where \(equation.source) crosses the y-axis", lines: [pointLine(point)],
                          steps: [Step("Put x = 0", "Every point on the y-axis has x = 0, so put 0 in for x in y = \(Format.text(equationRight(equation))).", [MathLine(.symbol("y"), atZero.expr)])],
                          usedPoints: [], usedEquations: 1, points: [point])
        }
        var crossings: [F]
        if let line = straight(equation) {
            guard !line.a.isZero else { return nil }
            crossings = [-line.c / line.a]
        } else if let f = curve(equation), let found = roots(f), !found.isEmpty {
            crossings = found
        } else { return nil }
        let points = crossings.map { Point(x: $0, y: F(0)) }
        guard points.allSatisfy(\.isValid) else { return nil }
        let working = crossings.map { MathLine(.symbol("x"), $0.expr) }
        return Answer(question: "where \(equation.source) crosses the x-axis", lines: points.map(pointLine),
                      steps: [Step("Put y = 0", "Every point on the x-axis has y = 0, so solve \(Format.text(equationRight(equation))) = 0 for x.", working)],
                      usedPoints: [], usedEquations: 1, points: points)
    }

    private static func equationRight(_ e: Equation) -> Expr { e.left == .symbol("y") ? e.right : (e.right == .symbol("y") ? e.left : e.zero) }

    // MARK: Lines described in words

    /// What's said about a line: points on it, its gradient, its equation, a line it's parallel or perpendicular to.
    private struct Described {
        var points: [Point] = []
        var gradient: F?
        var equation: Line?
        var parallel: [Described] = []
        var perpendicular: [Described] = []
        var words: [String] = []
        var usedEquations = 0
    }

    /// A line referred to by name ("line M"), by two points ("AC", "the line through A and B"), or by its equation.
    private static func reference(_ phrase: String, _ q: Question, depth: Int = 0) -> Described? {
        let phrase = phrase.trimmingCharacters(in: .whitespaces)
        if let equation = q.equations.first(where: { phrase.contains($0.source) || phrase.replacingOccurrences(of: " ", with: "").hasPrefix($0.source.replacingOccurrences(of: " ", with: "")) }), let line = straight(equation) {
            var d = Described(); d.equation = line; d.usedEquations = 1; d.words = ["the line \(line.written)"]
            return d
        }
        if let name = groups(#"^(?:the )?(?:straight )?line ((?-i:[A-Z]))(?![A-Za-z])"#, in: phrase)?[1] {
            return depth < 2 ? named(name, q, depth: depth + 1) : nil
        }
        // "perpendicular to L", where the question calls L a line.
        if let name = groups(#"^((?-i:[A-Z]))(?![A-Za-z])"#, in: phrase)?[1], q.named[name] == nil, has(#"\bline (?-i:\#(name))(?![A-Za-z])"#, q.text) {
            return depth < 2 ? named(name, q, depth: depth + 1) : nil
        }
        if let ends = groups(#"^(?:the )?(?:straight )?(?:line )?(?:segment )?((?-i:[A-Z]))((?-i:[A-Z]))(?![A-Za-z])"#, in: phrase), let p = q.named[ends[1]], let r = q.named[ends[2]] {
            var d = Described(); d.points = [p, r]; d.words = ["\(ends[1])\(ends[2])"]
            return d
        }
        if let ends = groups(#"^(?:the )?(?:straight )?line (?:that )?(?:passing|passes|going|goes)? ?(?:through|joining) (?:the points )?((?-i:[A-Z])) and ((?-i:[A-Z]))(?![A-Za-z])"#, in: phrase), let p = q.named[ends[1]], let r = q.named[ends[2]] {
            var d = Described(); d.points = [p, r]; d.words = ["the line through \(ends[1]) and \(ends[2])"]
            return d
        }
        if let ends = groups(#"^(?:the )?(?:straight )?line (?:that )?(?:passing |passes |going |goes )?(?:through|joining) (?:the points )?\#(pair) and \#(pair)"#, in: phrase),
           let x1 = F.parse(ends[1]), let y1 = F.parse(ends[2]), let x2 = F.parse(ends[3]), let y2 = F.parse(ends[4]) {
            let p = Point(x: x1, y: y1), r = Point(x: x2, y: y2)
            var d = Described(); d.points = [p, r]; d.words = ["the line through \(p.written) and \(r.written)"]
            return d
        }
        return nil
    }

    /// Everything the question says about the line with this name.
    private static func named(_ name: String, _ q: Question, depth: Int) -> Described? {
        var d = Described()
        d.words = ["line \(name)"]
        let n = NSRegularExpression.escapedPattern(for: name)
        let text = q.text
        // "(4, 0) and (6, 10) are points on line M", "(-3, 10) is a point on line L"
        for sentence in sentences(text) {
            if has(#"\b(?:is|are|lies|lie) (?:a )?(?:points? )?on (?:the )?(?:straight )?line (?-i:\#(n))(?![A-Za-z])"#, sentence)
                || (has(#"^(?:the )?(?:straight )?line (?-i:\#(n))(?![A-Za-z])"#, sentence) && has(#"\b(?:passes|goes) through\b"#, sentence)) {
                for match in matches(pair, in: sentence) {
                    guard let x = F.parse(match.groups[1]), let y = F.parse(match.groups[2]) else { return nil }
                    d.points.append(Point(x: x, y: y))
                }
                // Named points: "A and B are points on line L".
                for letter in every(#"(?:^|[^A-Za-z])((?-i:[A-Z]))(?= and | are | is |,)"#, in: sentence).map({ $0[1] }) where letter != name {
                    if let p = q.named[letter] { d.points.append(p) }
                }
            }
            if let m = groups(#"\bline (?-i:\#(n)) has (?:a )?gradient (?:of )?(\#(number))"#, in: sentence)?[1] ?? groups(#"\bgradient of (?:line )?(?-i:\#(n)) is (\#(number))"#, in: sentence)?[1] {
                d.gradient = F.parse(m)
            }
            if has(#"\bline (?-i:\#(n)) has (?:the )?equation\b|\b(?-i:\#(n)) is the line\b"#, sentence),
               let equation = q.equations.first(where: { sentence.contains($0.source) }), let line = straight(equation) {
                d.equation = line; d.usedEquations += 1
            }
            // "L and M are parallel", "L is parallel to M", "L is parallel to the line y = 2x"
            guard depth == 0 else { continue }
            var others = every(#"(?:^|[^A-Za-z])((?-i:[A-Z])) and ((?-i:[A-Z])) are (parallel|perpendicular)"#, in: sentence)
            // "two parallel lines, Line A and Line B"
            others += every(#"\b(parallel|perpendicular) lines,? (?:line )?((?-i:[A-Z])) and (?:line )?((?-i:[A-Z]))(?![A-Za-z])"#, in: sentence).map { [$0[0], $0[2], $0[3], $0[1]] }
            for found in others where found[1] == name || found[2] == name {
                let other = found[1] == name ? found[2] : found[1]
                guard let o = named(other, q, depth: depth + 1) else { return nil }
                if found[3] == "parallel" { d.parallel.append(o) } else { d.perpendicular.append(o) }
            }
            if let found = groups(#"\b(?:line )?(?-i:\#(n)) is (parallel|perpendicular) to (.+)$"#, in: sentence), let o = reference(found[2], q, depth: depth + 1) {
                if found[1] == "parallel" { d.parallel.append(o) } else { d.perpendicular.append(o) }
            }
            // "Line A is perpendicular to line B", asked about B.
            if let found = groups(#"(?:^|[^A-Za-z])((?-i:[A-Z])) is (parallel|perpendicular) to (?:the )?(?:straight )?line (?-i:\#(n))(?![A-Za-z])"#, in: sentence),
               found[1] != name, let o = named(found[1], q, depth: depth + 1) {
                if found[2] == "parallel" { d.parallel.append(o) } else { d.perpendicular.append(o) }
            }
        }
        return d
    }

    /// The gradient of a described line, with the working that finds it.
    private static func slope(_ d: Described, _ steps: inout [Step], used: inout Set<Point>, equations: inout Int) -> F? {
        equations += d.usedEquations
        if let m = d.gradient { return m }
        if let line = d.equation {
            guard let m = line.gradient else { return nil }
            steps.append(Step("Find the gradient", "Written as y = mx + c, \(line.written): the gradient is the number in front of x.", [MathLine(.symbol("m"), m.expr)]))
            return m
        }
        let distinct = Array(Set(d.points))
        if distinct.count >= 2 {
            let p = d.points[0], r = d.points.first { $0 != p }!
            // Every point said to be on it has to be.
            guard let line = Line(p, r), d.points.allSatisfy(line.has) else { return nil }
            used.formUnion(d.points)
            guard let m = line.gradient else { return nil }
            steps.append(Step("Find the gradient of \(d.words.first ?? "the line")", "Change in y over change in x, from \(p.written) to \(r.written).",
                              (r.y - p.y) == F(m.n) && (r.x - p.x) == F(m.d) ? [MathLine(.symbol("m"), m.expr)] : [MathLine(.symbol("m"), (r.y - p.y).expr / (r.x - p.x).expr, m.expr)]))
            return m
        }
        if let other = d.parallel.first, d.parallel.count == 1, d.perpendicular.isEmpty {
            guard let m = slope(other, &steps, used: &used, equations: &equations) else { return nil }
            steps.append(Step("Parallel lines have the same gradient", "", [MathLine(.symbol("m"), m.expr)]))
            return m
        }
        if let other = d.perpendicular.first, d.perpendicular.count == 1, d.parallel.isEmpty {
            guard let m = slope(other, &steps, used: &used, equations: &equations), !m.isZero else { return nil }
            let turned = F(-1) / m
            steps.append(Step("A perpendicular gradient is the negative reciprocal", "Turn \(Format.text(m.expr)) upside down and change its sign: the two gradients multiply to −1.", [MathLine(.symbol("m"), turned.expr)]))
            return turned
        }
        return nil
    }

    /// The line a description gives, with its working.
    private static func resolve(_ d: Described, _ steps: inout [Step], used: inout Set<Point>, equations: inout Int) -> Line? {
        if let line = d.equation, d.points.isEmpty, d.gradient == nil, d.parallel.isEmpty, d.perpendicular.isEmpty {
            equations += d.usedEquations
            return line
        }
        let distinct = Array(Set(d.points))
        if distinct.count >= 2, d.gradient == nil, d.parallel.isEmpty, d.perpendicular.isEmpty, d.equation == nil {
            guard let m = slope(d, &steps, used: &used, equations: &equations) else {
                // Up and down: x is the same all along.
                guard let line = Line(d.points[0], distinct.first { $0 != d.points[0] }!), line.isVertical, d.points.allSatisfy(line.has) else { return nil }
                used.formUnion(d.points)
                return line
            }
            let p = d.points[0]
            let line = Line(gradient: m, through: p)
            steps.append(Step("Put a point in to find c", "y = mx + c goes through \(p.written).", [MathLine(p.y.expr, .symbol("\(Format.text(Simplify.run((m * p.x).expr))) + c")), MathLine(.symbol("c"), (p.y - m * p.x).expr)]))
            return line
        }
        guard distinct.count == 1, let p = distinct.first, let m = slope(d, &steps, used: &used, equations: &equations) else { return nil }
        used.insert(p)
        let c = p.y - m * p.x
        steps.append(Step("Put the point in to find c", "y = mx + c goes through \(p.written), with m = \(m.written).",
                          [MathLine(p.y.expr, .symbol("\(Format.text(Simplify.run((m * p.x).expr))) + c")), MathLine(.symbol("c"), c.expr)]))
        let line = Line(gradient: m, through: p)
        return line.isValid ? line : nil
    }

    private static func isEmpty(_ d: Described) -> Bool { d.points.isEmpty && d.gradient == nil && d.parallel.isEmpty && d.perpendicular.isEmpty && d.equation == nil }

    /// A line as a phrase describes it: "the line through A and (2, 5)", "perpendicular to y = 4x − 5 that passes through (0, 6)".
    /// Nil where it names something the question doesn't give.
    private static func describe(_ phrase: String, _ q: Question) -> Described? {
        var d = Described()
        if let through = groups(#"(?:through|joining) (?:the points? )?(.+?)(?= that\b| which\b| and is\b| and has\b|$)"#, in: phrase)?[1] {
            for letter in every(#"(?:^|[^A-Za-z])((?-i:[A-Z]))(?![A-Za-z])"#, in: through).map({ $0[1] }) {
                if let p = q.named[letter] { d.points.append(p); continue }
                // A point whose letter was misread ("The point 4 has coordinates (3, −5)"): the one pair with no name, if it's the only one.
                let loose = Set(q.pairs.filter { $0.name == nil }.map(\.point))
                guard loose.count == 1, let p = loose.first, matches(pair, in: through).isEmpty else { return nil }
                d.points.append(p)
            }
            for match in matches(pair, in: through) {
                guard let x = F.parse(match.groups[1]), let y = F.parse(match.groups[2]) else { return nil }
                d.points.append(Point(x: x, y: y))
            }
        }
        if let m = groups(#"\bgradient (?:of |is |= ?)?(\#(number))(?![\d.]*\s?[a-z])"#, in: phrase)?[1] { d.gradient = F.parse(m) }
        if let found = groups(#"\b(parallel|perpendicular) to (.+?)(?= that\b| which\b| and\b| through\b| passing\b|$)"#, in: phrase) {
            guard let o = reference(found[2], q) else { return nil }
            if found[1] == "parallel" { d.parallel.append(o) } else { d.perpendicular.append(o) }
        }
        return d
    }

    // MARK: The equation of a line

    /// "Work out the equation of line L", "the equation of the line perpendicular to AC that passes through C".
    private static func lineEquation(_ q: Question) -> Answer? {
        guard every(#"\bequation of\b"#, in: q.text).count == 1, q.form == nil || q.form!.lowercased() == "y=mx+c" else { return nil }
        var d: Described
        var name: String
        if let found = groups(#"\bequation of (?:the )?(?:straight )?line ((?-i:[A-Z]))(?![A-Za-z])"#, in: q.text) {
            name = "line \(found[1])"
            guard let described = named(found[1], q, depth: 0) else { return nil }
            d = described
        } else if let found = groups(#"\bequation of ((?:the|this) (?:straight )?line[^.?]*)"#, in: q.text) {
            name = "the line"
            guard var described = describe(found[1], q) else { return nil }
            // Nothing in the sentence itself: the line is described before the question ("A straight line passes through
            // the point (8, 1) and is perpendicular to the line y = 4x − 2. Find the equation of the line").
            if isEmpty(described), let ask = q.text.range(of: #"(?i)\b(?:work out|find|write down|calculate|determine|give)\b[^.?]*?\bequation of (?:the|this) (?:straight )?line"#, options: .regularExpression) {
                let before = String(q.text[..<ask.lowerBound])
                if let start = before.range(of: #"(?i)\b(?:a|the) (?:straight )?line (?:that )?(?:passes|goes|passing|going) through\b"#, options: .regularExpression),
                   let earlier = describe(String(before[start.lowerBound...]), q), !isEmpty(earlier) {
                    described = earlier
                }
            }
            // The straight line the question starts with ("A straight line passes through A, B and C").
            if isEmpty(described) {
                guard q.pairs.count >= 2, has(#"\b(?:a|the) straight line (?:passes|goes) through\b"#, q.text) else { return nil }
                described.points = q.pairs.map(\.point)
            }
            d = described
        } else { return nil }
        var steps: [Step] = []
        var used = Set<Point>()
        var equations = 0
        guard let line = resolve(d, &steps, used: &used, equations: &equations), line.isValid else { return nil }
        used.formUnion(d.points)
        steps.append(Step("Write the equation", "", [line.answer]))
        return Answer(question: "equation of \(name)", lines: [line.answer], steps: steps, usedPoints: used, usedEquations: equations, line: line)
    }

    // MARK: Does a point lie on a line

    private static func liesOn(_ q: Question) -> Answer? {
        guard let found = groups(#"\b(?:does|is) (?:the point )?([A-Z]|\#(pair)) (?:lie )?on (.+?)(?:\?|$)"#, in: q.text) else { return nil }
        let point: Point
        if found[1].count == 1 {
            guard let p = q.named[found[1]] else { return nil }
            point = p
        } else {
            guard let x = F.parse(found[2]), let y = F.parse(found[3]) else { return nil }
            point = Point(x: x, y: y)
        }
        guard let d = reference(found[4], q) else { return nil }
        var steps: [Step] = []
        var used = Set<Point>()
        var equations = 0
        guard let line = resolve(d, &steps, used: &used, equations: &equations) else { return nil }
        used.formUnion(d.points)
        used.insert(point)
        let lies = line.has(point)
        let label = found[1].count == 1 ? "\(found[1]) \(point.written)" : point.written
        if let m = line.gradient, let c = line.intercept {
            let y = m * point.x + c
            steps.append(Step("Write the line's equation", "", [line.answer]))
            steps.append(Step("Put in x = \(point.x.written)", lies ? "It gives y = \(point.y.written), the point's own y." : "It gives y = \(y.written), not \(point.y.written).",
                              [MathLine(.symbol("y"), .symbol("\(m.written) × (\(point.x.written)) \(c.double < 0 ? "−" : "+") \((c.double < 0 ? -c : c).written)"), y.expr)]))
        } else {
            steps.append(Step("The line goes straight up and down", "", [line.answer]))
        }
        let words = lies ? "Yes: \(label) is on the line \(line.written)" : "No: on the line \(line.written), x = \(point.x.written) gives y = \(((line.gradient ?? F(0)) * point.x + (line.intercept ?? F(0))).written)"
        return Answer(question: "does \(label) lie on \(d.words.first ?? "the line")", lines: [MathLine(.symbol(words))], steps: steps, usedPoints: used, usedEquations: equations)
    }

    // MARK: Two lines compared: parallel or perpendicular

    /// "Show that these two lines are parallel", "Are the lines y = 2x + 1 and 4x + 2y = 7 perpendicular?": two lines given
    /// by their equations and nothing else, their gradients compared. A claim to show that doesn't come out true gives nothing.
    private static func compared(_ q: Question) -> (answer: Answer, confirmsClaim: Bool)? {
        let relation = #"([pn]arallel|perpendicular)"#
        let claim = groups(#"\b(?:show|prove)(?: that)?\b[^.?]*?\b(?:is|are)\s+(?:both\s+)?\#(relation)\b"#, in: q.text)
        let asked = claim == nil ? groups(#"\b(?:are|is)\b[^.?]*?\b\#(relation)\b[^.?]*\?"#, in: q.text)
            ?? groups(#"\b(?:decide|determine|find out) (?:whether|if)\b[^.?]*?\b(?:is|are)\s+\#(relation)\b"#, in: q.text) : nil
        guard let words = claim ?? asked else { return nil }
        let isParallel = words[1].lowercased().hasSuffix("arallel")
        // Two lines and nothing more: no points, nothing to choose from, nothing else asked.
        guard q.equations.count == 2, q.pairs.isEmpty, q.choicePairs.isEmpty, q.choiceLines.isEmpty, q.form == nil,
              !has(#"\b(?:work out|find the|calculate|write down|coordinates|intersect|meet|cross|cuts?)\b"#, q.text.replacingOccurrences(of: #"(?i)\bfind out\b"#, with: "", options: .regularExpression)),
              !has(refusal, q.text.replacingOccurrences(of: #"(?i)\b(?:show|prove)(?: that)?\b"#, with: "", options: .regularExpression)),
              let one = straight(q.equations[0]), let two = straight(q.equations[1]), !one.same(as: two) else { return nil }
        func fraction(_ f: F) -> String { (f.d == 1 ? f.written : Format.text(f.expr)).replacingOccurrences(of: "/", with: "∕").replacingOccurrences(of: "-", with: "−") }
        var steps: [Step] = []
        for (equation, line) in [(q.equations[0], one), (q.equations[1], two)] {
            let given = MathLine(equation.left, equation.right)
            let written = given.text
            if let m = line.gradient {
                let rearranged = equation.left != .symbol("y") || line.written != "y = \(Format.text(equation.right))"
                steps.append(Step(rearranged ? "Rearrange \(written) into y = mx + c" : "Read off the gradient of \(written)",
                                  "In y = mx + c, m is the gradient: the number in front of x.",
                                  rearranged ? [given, line.answer, MathLine(.symbol("m"), m.expr)] : [MathLine(.symbol("m"), m.expr)]))
            } else {
                steps.append(Step("\(line.written) goes straight up and down", "", [line.answer]))
            }
        }
        let holds: Bool
        let reason: String
        switch (one.gradient, two.gradient) {
        case let (m1?, m2?):
            if isParallel {
                holds = m1 == m2
                reason = holds ? "both gradients are \(fraction(m1))" : "the gradients are \(fraction(m1)) and \(fraction(m2))"
                steps.append(Step("Compare the gradients", "Parallel lines have the same gradient.", []))
            } else {
                let product = m1 * m2
                holds = product == F(-1)
                reason = "\(fraction(m1)) × \(m2.double < 0 ? "(\(fraction(m2)))" : fraction(m2)) = \(fraction(product))" + (holds ? "" : ", not −1")
                steps.append(Step("Multiply the gradients", "Perpendicular lines have gradients that multiply to −1.", [MathLine(.symbol("m₁ × m₂"), product.expr)]))
            }
        case (nil, nil):
            holds = isParallel
            reason = "both lines go straight up and down"
        case let (nil, m?), let (m?, nil):
            holds = !isParallel && m.isZero
            reason = m.isZero ? "one line goes straight up and down and the other straight across" : "one line goes straight up and down and the other doesn't"
        }
        let name = isParallel ? "parallel" : "perpendicular"
        let shown: String
        if claim != nil {
            // Shown to be false: something was misread.
            guard holds else { return nil }
            shown = isParallel ? "The lines are parallel: \(reason)" : "The lines are perpendicular: \(reason)"
        } else {
            shown = holds ? "Yes: \(reason)" : "No: \(reason)"
        }
        let answer = Answer(question: "are the lines \(name)", lines: [MathLine(.symbol(shown))], steps: steps, usedPoints: [], usedEquations: 2)
        return (answer, claim != nil)
    }

    // MARK: Circles: the tangent at a point, and the circle's equation

    /// What the question says of its circle: the centre, and the square of the radius if its equation is given.
    private struct Circle {
        var centre: Point
        var r2: F?
        var usedEquations = 0
        var usedPoints: Set<Point> = []
        var words: String
    }

    private static func circleOf(_ q: Question) -> Circle? {
        let origin = Point(x: F(0), y: F(0))
        let circles = q.equations.compactMap { e in circle(e).map { (e, $0) } }
        guard circles.count <= 1 else { return nil }
        if let (e, r2) = circles.first {
            var c = Circle(centre: origin, r2: r2, usedEquations: 1, words: MathLine(e.left, e.right).text)
            // A centre given as well has to be the origin.
            if q.pairs.contains(where: { $0.point == origin }) {
                guard has(#"\bcentre (?:is )?(?:at )?(?:the point )?(?:with coordinates )?(?:o )?\(\s*0\s*,\s*0\s*\)"#, q.text) else { return nil }
                c.usedPoints.insert(origin)
            }
            return c
        }
        guard has(#"\bcircle\b"#, q.text) else { return nil }
        if let found = groups(#"\bcentre (?:of (?:the|a) circle )?(?:is )?(?:at )?(?:the point )?(?:with coordinates )?\#(pair)"#, in: q.text),
           let x = F.parse(found[1]), let y = F.parse(found[2]) {
            let p = Point(x: x, y: y)
            return Circle(centre: p, usedPoints: [p], words: "the circle with centre \(p.written)")
        }
        // "a circle, centre O", "centre the origin": O is the origin unless the question places it.
        if has(#"\bcentre,? (?:o|the origin)\b"#, q.text), q.named["O"] == nil {
            return Circle(centre: origin, words: "the circle with centre O (0, 0)")
        }
        return nil
    }

    /// "Work out the equation of the tangent to the circle at P", "the gradient of the tangent at (−5, 2)",
    /// "The tangent at (4, 8) intersects the x-axis at P. Work out the x-coordinate of P", "Alex says that the tangent …
    /// crosses the x-axis at the point (−8, 0). Is Alex correct?"
    private static func tangent(_ q: Question) -> Answer? {
        guard has(#"\btangent\b"#, q.text), let circle = circleOf(q) else { return nil }
        guard q.form == nil || ["y=mx+c", "ax+by+c=0"].contains(q.form!.lowercased()) else { return nil }
        // What's asked.
        enum Ask { case equation, gradient, crossing(axis: String, letter: String?), claim(axis: String, point: Point, who: String) }
        var asks: [Ask] = []
        if has(#"\bequation of (?:the|a) tangent\b"#, q.text) { asks.append(.equation) }
        if has(#"\bgradient of the tangent\b"#, q.text), !has(#"\bhas a gradient\b"#, q.text) { asks.append(.gradient) }
        if let found = groups(#"\b(\w+) says\b[^.?]*?\btangent\b[^.?]*?\b(?:crosses|meets|intersects|cuts) the ([xy])[- ]?axis at (?:the point )?\#(pair)"#, in: q.text),
           has(#"\bcorrect\s*\?"#, q.text), let x = F.parse(found[3]), let y = F.parse(found[4]) {
            asks.append(.claim(axis: found[2].lowercased(), point: Point(x: x, y: y), who: found[1]))
        } else if let found = groups(#"\btangent\b[^.?]*?\b(?:crosses|meets|intersects|cuts) the ([xy])[- ]?axis at (?:the point )?(?:((?-i:[A-Z]))(?![A-Za-z])|\(\s*([a-z])\s*,\s*0\s*\)|\(\s*0\s*,\s*([a-z])\s*\))"#, in: q.text) {
            let axis = found[1].lowercased()
            let letter = !found[3].isEmpty ? found[3] : (!found[4].isEmpty ? found[4] : nil)
            if let letter, has(#"\bvalue of \#(letter)\b"#, q.text) { asks.append(.crossing(axis: axis, letter: letter)) }
            else if !found[2].isEmpty, has(#"\b(?:\#(axis)-coordinate|coordinates) of (?-i:\#(found[2]))\b"#, q.text) { asks.append(.crossing(axis: axis, letter: nil)) }
        }
        guard asks.count == 1, let ask = asks.first else { return nil }
        // The point of contact.
        let name = groups(#"\btangent (?:to (?:the circle|[A-Z]) )?at (?:the point )?((?-i:[A-Z]))(?![A-Za-z])"#, in: q.text)?[1]
        var steps: [Step] = []
        var used = circle.usedPoints
        var claimPoint: Point?
        if case .claim(_, let point, _) = ask { claimPoint = point }
        let candidates = Set(q.pairs.map(\.point)).subtracting(circle.usedPoints).subtracting(claimPoint.map { [$0] } ?? [])
        let p: Point
        if candidates.count == 1, let given = candidates.first {
            p = given
        } else if candidates.isEmpty, let r2 = circle.r2, circle.centre == Point(x: F(0), y: F(0)),
                  let found = groups(#"\bhas (?:an? )?(x|y)[- ]?coordinate (?:of )?(\#(number))\b"#, in: q.text), let k = F.parse(found[2]) {
            let isX = found[1].lowercased() == "x"
            let rest = r2 - k * k
            guard rest.isValid, rest.double >= 0, let root = rest.root else { return nil }
            var other = root
            if !root.isZero {
                let sides = isX ? (#"\bbelow the x[- ]?axis\b"#, #"\babove the x[- ]?axis\b"#) : (#"\b(?:to the )?left of the y[- ]?axis\b"#, #"\b(?:to the )?right of the y[- ]?axis\b"#)
                let negative = has(sides.0, q.text), positive = has(sides.1, q.text)
                guard negative != positive else { return nil }
                if negative { other = -root }
            }
            p = isX ? Point(x: k, y: other) : Point(x: other, y: k)
            let known = isX ? "x" : "y", unknown = isX ? "y" : "x"
            steps.append(Step("Find \(name ?? "the point")'s other coordinate", "It's on the circle, so put \(known) = \(k.written) into \(circle.words).",
                              [MathLine(.symbol("\(unknown)²"), .symbol("\(r2.written) − \(k.double < 0 ? "(\(k.written))" : k.written)²"), rest.expr),
                               MathLine(.symbol(unknown), other.expr)]))
        } else { return nil }
        guard p.isValid, p != circle.centre else { return nil }
        // On the circle, where its equation says what that is.
        if let r2 = circle.r2 { guard (p.x - circle.centre.x) * (p.x - circle.centre.x) + (p.y - circle.centre.y) * (p.y - circle.centre.y) == r2 else { return nil } }
        used.insert(p)
        if let claimPoint { used.insert(claimPoint) }
        let c = circle.centre
        let label = name.map { "\($0) \(p.written)" } ?? p.written
        // Perpendicular to the radius from the centre to the point.
        let dx = p.x - c.x, dy = p.y - c.y
        let line = Line(a: dx, b: dy, c: -(dx * p.x + dy * p.y))
        guard line.isValid else { return nil }
        let centreWords = c == Point(x: F(0), y: F(0)) ? "The centre is (0, 0)" : "The centre is \(c.written)"
        if dx.isZero {
            steps.append(Step("The radius to \(label) goes straight up and down", "The tangent is at right angles to it: straight across.", [line.answer]))
        } else if dy.isZero {
            steps.append(Step("The radius to \(label) goes straight across", "The tangent is at right angles to it: straight up and down.", [line.answer]))
        } else {
            let radius = dy / dx, m = -dx / dy
            let shown = dy.isInteger && dx.isInteger && dx.n == radius.d && dy.n == radius.n ? [MathLine(.symbol("m"), radius.expr)] : [MathLine(.symbol("m"), dy.expr / dx.expr, radius.expr)]
            steps.append(Step("Find the gradient of the radius to \(label)", "\(centreWords): change in y over change in x.", shown))
            steps.append(Step("The tangent is perpendicular to the radius", "Turn \(Format.text(radius.expr)) upside down and change its sign: the two gradients multiply to −1.",
                              [MathLine(.symbol("m"), m.expr)]))
            if case .gradient = ask {} else {
                let k = p.y - m * p.x
                steps.append(Step("Put \(label) in to find c", "y = mx + c goes through \(p.written).",
                                  [MathLine(p.y.expr, .symbol("\(Format.text(Simplify.run((m * p.x).expr))) + c")), MathLine(.symbol("c"), k.expr)]))
            }
        }
        switch ask {
        case .equation:
            var answer = line.answer
            if q.form?.lowercased() == "ax+by+c=0" {
                guard let whole = integers(line), let expr = Parser.expression(whole) else { return nil }
                answer = MathLine(expr, .zero)
                steps.append(Step("Write it as ax + by + c = 0", "Take everything to one side and clear the fractions.", [MathLine(line.answer.parts[0], line.answer.parts[1]), answer]))
            } else {
                steps.append(Step("Write the equation", "", [answer]))
            }
            return Answer(question: "equation of the tangent at \(label)", lines: [answer], steps: steps, usedPoints: used, usedEquations: circle.usedEquations, line: line)
        case .gradient:
            guard let m = line.gradient else { return nil }
            return Answer(question: "gradient of the tangent at \(label)", lines: [MathLine(m.expr)], steps: steps, usedPoints: used, usedEquations: circle.usedEquations)
        case .crossing(let axis, let letter):
            steps.append(Step("Write the tangent's equation", "", [line.answer]))
            let value: F
            if axis == "x" {
                guard !line.a.isZero else { return nil }
                value = -line.c / line.a
                steps.append(Step("Put y = 0", "On the x-axis, y is 0.", [MathLine(.symbol("x"), value.expr)]))
            } else {
                guard !line.b.isZero else { return nil }
                value = -line.c / line.b
                steps.append(Step("Put x = 0", "On the y-axis, x is 0.", [MathLine(.symbol("y"), value.expr)]))
            }
            guard value.isValid else { return nil }
            let answer = letter.map { MathLine(.symbol($0), value.expr) } ?? MathLine(value.expr)
            return Answer(question: "where the tangent at \(label) crosses the \(axis)-axis", lines: [answer], steps: steps, usedPoints: used, usedEquations: circle.usedEquations)
        case .claim(let axis, let point, let who):
            guard (axis == "x" ? point.y : point.x).isZero else { return nil }
            steps.append(Step("Write the tangent's equation", "", [line.answer]))
            let value: F
            if axis == "x" { guard !line.a.isZero else { return nil }; value = -line.c / line.a } else { guard !line.b.isZero else { return nil }; value = -line.c / line.b }
            guard value.isValid else { return nil }
            let crosses = axis == "x" ? Point(x: value, y: F(0)) : Point(x: F(0), y: value)
            steps.append(Step(axis == "x" ? "Put y = 0" : "Put x = 0", "That's where it crosses the \(axis)-axis.", [MathLine(.symbol(axis), value.expr)]))
            let words = crosses == point ? "Yes: the tangent crosses the \(axis)-axis at \(point.written)" : "No: the tangent crosses the \(axis)-axis at \(crosses.asFractions), not \(point.written)"
            return Answer(question: "is \(who) correct", lines: [MathLine(.symbol(words))], steps: steps, usedPoints: used, usedEquations: circle.usedEquations)
        }
    }

    /// a x + b y + c = 0 with whole numbers, no common factor, x's number positive.
    private static func integers(_ line: Line) -> String? {
        var lcm = 1
        for f in [line.a, line.b, line.c] { guard f.isValid else { return nil }; lcm = lcm / F.gcd(lcm, f.d) * f.d }
        var a = line.a.n * (lcm / line.a.d), b = line.b.n * (lcm / line.b.d), c = line.c.n * (lcm / line.c.d)
        let g = F.gcd(F.gcd(abs(a), abs(b)), abs(c))
        guard g > 0 else { return nil }
        (a, b, c) = (a / g, b / g, c / g)
        if a < 0 || (a == 0 && b < 0) { (a, b, c) = (-a, -b, -c) }
        var text = ""
        func term(_ k: Int, _ letter: String) {
            guard k != 0 else { return }
            let size = abs(k) == 1 && !letter.isEmpty ? "" : "\(abs(k))"
            text += text.isEmpty ? (k < 0 ? "-" : "") + size + letter : (k < 0 ? " - " : " + ") + size + letter
        }
        term(a, "x"); term(b, "y"); term(c, "")
        return text.isEmpty ? nil : text
    }

    /// "The point (−5, 2) lies on the circumference of a circle, centre (0, 0). Find the equation of the circle."
    private static func circleEquation(_ q: Question) -> Answer? {
        guard has(#"\b(?:find|work out|write down) the equation of the circle\b"#, q.text), q.equations.isEmpty,
              let circle = circleOf(q), circle.centre == Point(x: F(0), y: F(0)) else { return nil }
        let points = Set(q.pairs.map(\.point)).subtracting(circle.usedPoints)
        guard points.count == 1, let p = points.first, p != circle.centre else { return nil }
        let r2 = p.x * p.x + p.y * p.y
        guard r2.isValid else { return nil }
        let answer = MathLine(.symbol("x² + y²"), r2.expr)
        let step = Step("Find r²", "A circle centred on (0, 0) is x² + y² = r², and \(p.written) is on it: put it in.",
                        [MathLine(.symbol("r²"), .symbol("\(p.x.double < 0 ? "(\(p.x.written))" : p.x.written)² + \(p.y.double < 0 ? "(\(p.y.written))" : p.y.written)²"), r2.expr)])
        return Answer(question: "equation of the circle", lines: [answer], steps: [step, Step("Write the equation", "", [answer])],
                      usedPoints: circle.usedPoints.union([p]), usedEquations: 0)
    }

    // MARK: A letter in a line's equation, from a parallel or perpendicular line

    /// "The equation of line L1 is y = 2x − 5. The equation of line L2 is 6y + kx − 12 = 0. L1 is perpendicular to L2. Find the value of k."
    private static func coefficient(_ q: Question) -> Answer? {
        guard q.equations.count == 2, q.pairs.isEmpty, let found = groups(#"\b(?:find|work out|calculate) (?:the value of )?([a-z])\b"#, in: q.text),
              let relation = groups(#"\b(?:are|is) (parallel|perpendicular)\b"#, in: q.text)?[1].lowercased(),
              every(#"\b(?:parallel|perpendicular)\b"#, in: q.text).count == 1 else { return nil }
        let letter = found[1]
        guard letter != "x", letter != "y" else { return nil }
        let known = q.equations.first { straight($0) != nil }, other = q.equations.first { $0.zero.symbols == ["x", "y", letter] }
        guard let known, let other, let line = straight(known), let m = line.gradient else { return nil }
        let zero = other.zero
        func at(_ x: Int, _ y: Int) -> Expr { Simplify.run(zero.substituting("x", with: .integer(x)).substituting("y", with: .integer(y))) }
        let a = Simplify.run(at(1, 0) - at(0, 0)), b = Simplify.run(at(0, 1) - at(0, 0))
        // Straight for every value of the letter: no x² or xy.
        guard Simplify.run(at(2, 3) - at(0, 0) - .integer(2) * a - .integer(3) * b) == .zero else { return nil }
        let wanted = relation == "parallel" ? m : (m.isZero ? F.invalid : F(-1) / m)
        guard wanted.isValid else { return nil }
        // −a/b = wanted, so a + wanted × b = 0.
        let condition = Simplify.run(a + wanted.expr * b)
        guard let poly = Polynomial(condition, in: letter), poly.degree == 1 else { return nil }
        let value = F(-poly.coefficient(0).numerator, poly.coefficient(0).denominator) / F(poly.coefficient(1).numerator, poly.coefficient(1).denominator)
        guard value.isValid, let bValue = Simplify.run(b.substituting(letter, with: value.expr)).number.flatMap(F.init), !bValue.isZero else { return nil }
        let gradientOther = Simplify.run(Expr.integer(-1) * a / b)
        let steps = [
            Step("Find the gradient of \(MathLine(known.left, known.right).text)", "In y = mx + c, m is the gradient.", [MathLine(.symbol("m"), m.expr)]),
            Step(relation == "parallel" ? "Parallel lines have the same gradient" : "Perpendicular gradients multiply to −1",
                 "So the other line's gradient is \(Format.text(wanted.expr)).", [MathLine(.symbol("m"), wanted.expr)]),
            Step("Find the gradient of \(MathLine(other.left, other.right).text)", "Rearranged into y = mx + c, the number in front of x.", [MathLine(.symbol("m"), gradientOther)]),
            Step("Make them equal and solve", "", [MathLine(gradientOther, wanted.expr), MathLine(.symbol(letter), value.expr)]),
        ]
        return Answer(question: "value of \(letter)", lines: [MathLine(.symbol(letter), value.expr)], steps: steps, usedPoints: [], usedEquations: 2)
    }

    // MARK: A quadratic from where it crosses the axes

    /// "A quadratic curve intersects the axes at (−3, 0), (3, 0) and (0, 18). Work out the equation of the curve."
    private static func quadraticFromAxes(_ q: Question) -> Answer? {
        guard has(#"\bquadratic\b"#, q.text), has(#"\b(?:work out|find|write down) (?:an |the )?equation of the (?:curve|graph)\b"#, q.text), q.equations.isEmpty else { return nil }
        let points = Array(Set(q.pairs.map(\.point)))
        let onX = points.filter { $0.y.isZero && !$0.x.isZero }, onY = points.filter { $0.x.isZero && !$0.y.isZero }
        guard points.count == 3, onX.count == 2, onY.count == 1 else { return nil }
        let r1 = onX[0].x, r2 = onX[1].x, k = onY[0].y
        let product = r1 * r2
        guard !product.isZero else { return nil }
        let a = k / product
        let coefficients = [a * product, -a * (r1 + r2), a]
        guard coefficients.allSatisfy(\.isValid) else { return nil }
        let poly = Polynomial(coefficients.map { Rational.make($0.n, $0.d)! }, variable: "x")
        let answer = MathLine(.symbol("y"), Simplify.run(poly.expr))
        func bracket(_ r: F) -> String { r.double < 0 ? "(x + \((-r).written))" : "(x − \(r.written))" }
        let steps = [
            Step("Write it from where it crosses the x-axis", "y is 0 at x = \(r1.written) and x = \(r2.written), so the curve is y = a\(bracket(r1))\(bracket(r2)).", []),
            Step("Find a from the y-intercept", "At x = 0, y = \(k.written).", [MathLine(k.expr, .symbol("a × \(product.double < 0 ? "(\(product.written))" : product.written)")), MathLine(.symbol("a"), a.expr)]),
            Step("Multiply out", "", [answer]),
        ]
        return Answer(question: "equation of the curve", lines: [answer], steps: steps, usedPoints: Set(points), usedEquations: 0)
    }

    // MARK: y = x² + bx + c with its letters fixed by points on it

    /// "Here is a sketch of y = x² + bx + c. The curve intersects the x-axis at (5, 0) and the y-axis at (0, −10).
    /// Work out the x-coordinate of the turning point."
    private static func lettersFixed(_ q: Question) -> Answer? {
        guard q.equations.count == 1, let e = q.equations.first, e.left == .symbol("y") else { return nil }
        let letters = e.right.symbols.subtracting(["x"]).sorted()
        guard !letters.isEmpty, letters.count <= 2, !e.right.symbols.contains("y") else { return nil }
        let wantsTurning = has(#"\bturning point\b"#, q.text)
        let wantsX = has(#"\bx-coordinate of the turning point\b"#, q.text)
        let wantsLetters = has(#"\b(?:work out|find) the values? of \#(letters[0])\b"#, q.text)
        guard wantsTurning != wantsLetters else { return nil }
        let points = Array(Set(q.pairs.map(\.point)))
        guard points.count == letters.count else { return nil }
        // Each point gives an equation in the letters; linear in them.
        var rows: [[F]] = []
        for p in points {
            let at = Simplify.run(e.right.substituting("x", with: p.x.expr) - p.y.expr)
            var row: [F] = []
            func value(_ ex: Expr) -> F? { Simplify.run(ex).number.flatMap(F.init) }
            var base = at
            for l in letters { base = base.substituting(l, with: .zero) }
            guard let constant = value(base) else { return nil }
            for l in letters {
                var only = at
                for other in letters where other != l { only = only.substituting(other, with: .zero) }
                guard let one = value(only.substituting(l, with: .one)), let two = value(only.substituting(l, with: .integer(2))), two - one == one - constant else { return nil }
                row.append(one - constant)
            }
            row.append(-constant)
            rows.append(row)
        }
        var solved: [F]
        if letters.count == 1 {
            guard !rows[0][0].isZero else { return nil }
            solved = [rows[0][1] / rows[0][0]]
        } else {
            let det = rows[0][0] * rows[1][1] - rows[0][1] * rows[1][0]
            guard !det.isZero else { return nil }
            solved = [(rows[0][2] * rows[1][1] - rows[0][1] * rows[1][2]) / det, (rows[0][0] * rows[1][2] - rows[0][2] * rows[1][0]) / det]
        }
        guard solved.allSatisfy(\.isValid) else { return nil }
        var f = e.right
        for (l, v) in zip(letters, solved) { f = f.substituting(l, with: v.expr) }
        f = Simplify.run(f)
        guard let poly = Polynomial(f, in: "x"), poly.degree == 2 else { return nil }
        let found = zip(letters, solved).map { MathLine(.symbol($0.0), $0.1.expr) }
        var steps = [Step("Put each point into y = \(Format.text(e.right))", "Each one gives an equation in \(letters.joined(separator: " and ")).", found),
                     Step("So the curve is", "", [MathLine(.symbol("y"), f)])]
        if wantsLetters {
            return Answer(question: "values of \(letters.joined(separator: " and "))", lines: found, steps: steps, usedPoints: Set(points), usedEquations: 1)
        }
        let a = F(poly.coefficient(2).numerator, poly.coefficient(2).denominator), b = F(poly.coefficient(1).numerator, poly.coefficient(1).denominator)
        let x = -b / (F(2) * a)
        let y = value((0...2).map { F(poly.coefficient($0).numerator, poly.coefficient($0).denominator) }, at: x)
        guard x.isValid, y.isValid else { return nil }
        steps.append(Step("The turning point is halfway between the roots", "Its x is −b ÷ 2a.", [MathLine(.symbol("x"), x.expr)]))
        if wantsX { return Answer(question: "x-coordinate of the turning point", lines: [MathLine(.symbol("x"), x.expr)], steps: steps, usedPoints: Set(points), usedEquations: 1) }
        steps.append(Step("Put it in to find y", "", [MathLine(.symbol("y"), y.expr)]))
        let point = Point(x: x, y: y)
        return Answer(question: "turning point", lines: [pointLine(point)], steps: steps, usedPoints: Set(points), usedEquations: 1, points: [point])
    }

    // MARK: The line parallel to an axis, among choices

    /// "Circle the equation of the line that is parallel to the x-axis. y = −5  x = 3  x − y = 0  x + y = 0"
    private static func axisChoice(_ q: Question) -> Answer? {
        guard let axis = groups(#"\b(?:circle|which (?:of these )?is) the equation of (?:the|a) (?:straight )?line (?:that is )?parallel to the ([xy])[- ]?axis\b"#, in: q.text)?[1].lowercased(),
              q.equations.isEmpty, q.choiceLines.count >= 2 else { return nil }
        // Every choice read as an equation.
        guard let circleAt = q.text.range(of: #"(?i)\bcircle (?:the|your)\b[^.?]*[.?]?"#, options: [.regularExpression, .backwards]),
              q.text[circleAt.upperBound...].filter({ $0 == "=" }).count == q.choiceLines.count else { return nil }
        let lines = q.choiceLines.map(straight)
        guard lines.allSatisfy({ $0 != nil }) else { return nil }
        let fits = zip(q.choiceLines, lines.map { $0! }).filter { axis == "x" ? $0.1.a.isZero : $0.1.b.isZero }
        guard fits.count == 1, let pick = fits.first else { return nil }
        let answer = MathLine(pick.0.left, pick.0.right)
        let step = Step(axis == "x" ? "A line parallel to the x-axis is y = a number" : "A line parallel to the y-axis is x = a number", "", [answer])
        return Answer(question: "line parallel to the \(axis)-axis", lines: [answer], steps: [step], usedPoints: [], usedEquations: 0, line: pick.1)
    }

    // MARK: y from x, on a graph's equation

    /// "The graph of y = x² + 6x − 2 is shown below. … Calculate y when x = 1." The equation of the graph, the x = k of
    /// the question, and nothing else (but the same expression = 0, where the question names its roots).
    private static func valueAt(_ q: Question) -> Answer? {
        guard let found = groups(#"\b(?:calculate|work out|find|what is) (?:the value of )?y when x ?= ?(\#(number))(?!\d|\.\d)"#, in: q.text),
              let k = F.parse(found[1]), every(#"\bwhen [a-z] ?="#, in: q.text).count == 1 else { return nil }
        let graphs = q.equations.compactMap { e in curve(e).map { (equation: e, f: $0) } }.filter { $0.f.count >= 2 }
        guard graphs.count == 1, let graph = graphs.first else { return nil }
        var sawX = false
        for e in q.equations where e.at != graph.equation.at {
            let zero = e.zero
            if zero.symbols == ["x"], let line = straight(e), line.isVertical, (-line.c / line.a) == k { sawX = true; continue }
            // "The roots of the equation x² + 6x − 2 = 0": the same expression.
            if zero.symbols == ["x"], let polynomial = Polynomial(zero, in: "x") {
                let c = (0...max(polynomial.degree, 0)).map { F(polynomial.coefficient($0).numerator, polynomial.coefficient($0).denominator) }
                if c.count == graph.f.count, let ratio = c.last.map({ $0 / graph.f.last! }), ratio.isValid, !ratio.isZero, zip(c, graph.f).allSatisfy({ $0 == ratio * $1 }) { continue }
            }
            return nil
        }
        guard sawX else { return nil }
        let y = value(graph.f, at: k)
        guard y.isValid else { return nil }
        let written = MathLine(graph.equation.left, graph.equation.right).text
        let f = graph.equation.left == .symbol("y") ? graph.equation.right : graph.equation.left
        let step = Step("Put x = \(k.written) into \(written)", "", [MathLine(.symbol("y"), f.substituting("x", with: k.expr), y.expr)])
        return Answer(question: "y when x = \(k.written)", lines: [MathLine(.symbol("y"), y.expr)], steps: [step], usedPoints: [], usedEquations: q.equations.count)
    }

    // MARK: Where lines and curves meet

    private static func meeting(_ q: Question) -> Answer? {
        guard has(#"\b(?:intersect|intersects|intersecting|intersection|meet|meets|meeting|cross|crosses)\b"#, q.text), !has(#"\b[xy][- ]?axis\b"#, q.text),
              q.equations.count == 2, has(#"\bcoordinates\b|\bwhere\b|\bsolve\b|\bwork out\b|\bfind\b"#, q.text) else { return nil }
        let first = q.equations[0], second = q.equations[1]
        // A line with one letter still to find from a point on it ("y = 3x + p, A is (2, 7)").
        func fixed(_ e: Equation, _ known: [Point]) -> (Equation, String, F)? {
            let extra = e.zero.symbols.subtracting(["x", "y"])
            guard extra.count == 1, let letter = extra.first, known.count == 1, let p = known.first else { return nil }
            let atP = Simplify.run(e.zero.substituting("x", with: p.x.expr).substituting("y", with: p.y.expr))
            guard let poly = Polynomial(atP, in: letter), poly.degree == 1 else { return nil }
            let value = F(-poly.coefficient(0).numerator, poly.coefficient(0).denominator) / F(poly.coefficient(1).numerator, poly.coefficient(1).denominator)
            guard value.isValid else { return nil }
            var changed = e
            changed.left = Simplify.run(e.left.substituting(letter, with: value.expr))
            changed.right = Simplify.run(e.right.substituting(letter, with: value.expr))
            return (changed, letter, value)
        }
        let known = q.pairs.map(\.point)
        var steps: [Step] = []
        var a = first, b = second
        if let found = fixed(a, known) {
            steps.append(Step("Find \(found.1)", "\(known[0].written) is on \(a.source), so put it in.", [MathLine(.symbol(found.1), found.2.expr)]))
            a = found.0
        } else if let found = fixed(b, known) {
            steps.append(Step("Find \(found.1)", "\(known[0].written) is on \(b.source), so put it in.", [MathLine(.symbol(found.1), found.2.expr)]))
            b = found.0
        }
        // The line, and what it crosses.
        guard let l = straight(a) ?? straight(b) else { return nil }
        let other = straight(a) != nil ? b : a
        var found: [Point] = []
        if let k = straight(other), straight(a) != nil, straight(b) != nil {
            let det = l.a * k.b - l.b * k.a
            guard !det.isZero else { return nil }
            let x = (l.b * k.c - k.b * l.c) / det, y = (k.a * l.c - l.a * k.c) / det
            found = [Point(x: x, y: y)]
            steps.append(Step("Solve the two equations together", "Where the lines meet, both are true at once.", [MathLine(.symbol("x"), x.expr), MathLine(.symbol("y"), y.expr)]))
        } else if let f = curve(other), !l.isVertical, let m = l.gradient, let c = l.intercept {
            // f(x) = mx + c
            var g = f
            while g.count < 2 { g.append(F(0)) }
            g[0] = g[0] - c; g[1] = g[1] - m
            guard let xs = roots(g), !xs.isEmpty else { return nil }
            found = xs.map { Point(x: $0, y: m * $0 + c) }
            steps.append(Step("Set the two equal", "Where they meet, both give the same y.", [MathLine(Polynomial(g.map { Rational.make($0.n, $0.d)! }, variable: "x").expr, .zero)]))
            steps.append(Step("Solve, and find each y from the line", "", xs.map { MathLine(.symbol("x"), $0.expr) }))
        } else if let r2 = circle(other), !l.isVertical, let m = l.gradient, let c = l.intercept {
            // x² + (mx + c)² = r²
            let g = [c * c - r2, F(2) * m * c, F(1) + m * m]
            guard let xs = roots(g), !xs.isEmpty else { return nil }
            found = xs.map { Point(x: $0, y: m * $0 + c) }
            steps.append(Step("Put the line into the circle", "Swap y for \(Format.text(Simplify.run(m.expr * .symbol("x") + c.expr))) in x² + y² = \(r2.written).",
                              [MathLine(Polynomial(g.map { Rational.make($0.n, $0.d)! }, variable: "x").expr, .zero)]))
            steps.append(Step("Solve, and find each y from the line", "", xs.map { MathLine(.symbol("x"), $0.expr) }))
        } else if !l.isVertical, let m = l.gradient, let c = l.intercept, other.zero.symbols.isSubset(of: ["x", "y"]), other.zero.symbols.contains("y") {
            // Any other curve in x and y ("y² = 6x² − 25x − 8"): put the line in for y.
            let line = Simplify.run(m.expr * .symbol("x") + c.expr)
            guard let poly = Polynomial(Simplify.run(other.zero.substituting("y", with: line)), in: "x"), poly.degree == 1 || poly.degree == 2 else { return nil }
            let g = (0...poly.degree).map { F(poly.coefficient($0).numerator, poly.coefficient($0).denominator) }
            guard let xs = roots(g), !xs.isEmpty else { return nil }
            found = xs.map { Point(x: $0, y: m * $0 + c) }
            steps.append(Step("Put the line into the other equation", "Swap y for \(Format.text(line)) in \(MathLine(other.left, other.right).text).",
                              [MathLine(poly.expr, .zero)]))
            steps.append(Step("Solve, and find each y from the line", "", xs.map { MathLine(.symbol("x"), $0.expr) }))
        } else { return nil }
        guard found.allSatisfy(\.isValid) else { return nil }
        // One of them already known: the other is asked for.
        var asked = found
        if !known.isEmpty {
            guard known.count == 1, found.contains(known[0]), found.count == 2 else { return nil }
            asked = found.filter { $0 != known[0] }
        }
        return Answer(question: "where \(first.source) and \(second.source) meet", lines: asked.map(pointLine), steps: steps,
                      usedPoints: Set(known), usedEquations: 2, points: asked)
    }

    // MARK: A point dividing a line in a ratio

    private static func divided(_ q: Question) -> Answer? {
        var a: String, b: String, c: String, m: F, n: F
        if let found = groups(#"(?:^|[^A-Za-z])((?-i:[A-Z]))((?-i:[A-Z])) ?: ?((?-i:[A-Z]))((?-i:[A-Z])) ?= ?(\d+(?:\.\d+)?) ?: ?(\d+(?:\.\d+)?)"#, in: q.text), found[2] == found[3],
           let first = F.parse(found[5]), let second = F.parse(found[6]) {
            (a, b, c, m, n) = (found[1], found[2], found[4], first, second)
        } else if let found = groups(#"(?:^|[^A-Za-z])((?-i:[A-Z])) divides (?:the line )?(?:segment )?((?-i:[A-Z]))((?-i:[A-Z])) in the ratio (\d+(?:\.\d+)?) ?: ?(\d+(?:\.\d+)?)"#, in: q.text),
                  let first = F.parse(found[4]), let second = F.parse(found[5]) {
            (a, b, c, m, n) = (found[2], found[1], found[3], first, second)
        } else { return nil }
        guard !m.isZero, !n.isZero, has(#"\bcoordinates of (?:the )?(?:point )?[A-Z]\b|\bwhere is\b|\bfind (?:the point )?[A-Z]\b"#, q.text) else { return nil }
        let pa = q.named[a], pb = q.named[b], pc = q.named[c]
        var steps: [Step] = []
        let point: Point, asked: String
        if let pa, let pc, pb == nil {
            let t = m / (m + n)
            point = Point(x: pa.x + t * (pc.x - pa.x), y: pa.y + t * (pc.y - pa.y))
            asked = b
            steps.append(Step("\(b) is \(m.written) part\(m == F(1) ? "" : "s") of \((m + n).written) along from \(a) to \(c)", "So go \(t.written) of the way.", []))
            steps.append(Step("Go that far along each coordinate", "From \(pa.written) to \(pc.written).",
                              [MathLine(.symbol("x"), .add([pa.x.expr, .multiply([t.expr, (pc.x - pa.x).expr])]), point.x.expr), MathLine(.symbol("y"), .add([pa.y.expr, .multiply([t.expr, (pc.y - pa.y).expr])]), point.y.expr)]))
        } else if let pa, let pb, pc == nil {
            let t = n / m
            point = Point(x: pb.x + t * (pb.x - pa.x), y: pb.y + t * (pb.y - pa.y))
            asked = c
            steps.append(Step("\(b)\(c) is \(t.written) times \(a)\(b)", "Go on from \(b) by \(t.written) of the step from \(a) to \(b).",
                              [MathLine(.symbol("x"), point.x.expr), MathLine(.symbol("y"), point.y.expr)]))
        } else if let pb, let pc, pa == nil {
            let t = m / n
            point = Point(x: pb.x - t * (pc.x - pb.x), y: pb.y - t * (pc.y - pb.y))
            asked = a
            steps.append(Step("\(a)\(b) is \(t.written) times \(b)\(c)", "Go back from \(b) by \(t.written) of the step from \(b) to \(c).",
                              [MathLine(.symbol("x"), point.x.expr), MathLine(.symbol("y"), point.y.expr)]))
        } else { return nil }
        guard point.isValid, has(#"\bcoordinates of (?:the )?(?:point )?\#(asked)\b|\bfind (?:the point )?\#(asked)\b"#, q.text) else { return nil }
        let used = Set([pa, pb, pc].compactMap { $0 })
        return Answer(question: "coordinates of \(asked)", lines: [pointLine(point)], steps: steps, usedPoints: used, usedEquations: 0, points: [point])
    }


    // MARK: A point on a line with one coordinate to find

    /// "A straight line is perpendicular to the straight line through (2, 8) and (6, 15) and passes through (0, 9) and (x, 17). Work out the value of x."
    private static func unknownCoordinate(_ q: Question) -> Answer? {
        let open = every(#"\(\s*((?-i:[a-z]))\s*,\s*(\#(number))\s*\)|\(\s*(\#(number))\s*,\s*((?-i:[a-z]))\s*\)"#, in: q.text)
        guard open.count == 1 else { return nil }
        let found = open[0]
        let isX = !found[1].isEmpty
        let letter = isX ? found[1] : found[4]
        guard let known = F.parse(isX ? found[2] : found[3]),
              has(#"\b(?:work out|find|calculate|what is) (?:the value of )?(?-i:\#(letter))\b"#, q.text),
              has(#"\b(?:passes|goes|pass|go) through\b|\blies? on\b|\bis on (?:the|this) (?:straight )?line\b"#, q.text),
              has(#"\b(?:straight )?line\b"#, q.text) else { return nil }
        var d = Described()
        d.words = ["the line"]
        var inReference = Set<Point>()
        if let relation = groups(#"\b(parallel|perpendicular) to (.+?)(?= and (?:it )?(?:passes|goes)\b| and (?:has|is)\b| that\b| which\b|\.\s|,(?=\s*[A-Za-z])|$)"#, in: q.text) {
            guard let o = reference(relation[2], q) else { return nil }
            inReference = Set(o.points)
            if relation[1].lowercased() == "parallel" { d.parallel.append(o) } else { d.perpendicular.append(o) }
        }
        if let m = groups(#"\bgradient (?:of |is |= ?)?(\#(number))(?![\d./]*[a-z(])"#, in: q.text)?[1] { d.gradient = F.parse(m) }
        // The line's own points: the rest.
        d.points = q.pairs.map(\.point).filter { !inReference.contains($0) }
        guard !d.points.isEmpty || d.gradient != nil else { return nil }
        var steps: [Step] = []
        var used = inReference
        var equations = 0
        guard let line = resolve(d, &steps, used: &used, equations: &equations), line.isValid else { return nil }
        used.formUnion(d.points)
        let value: F
        if isX {
            guard !line.a.isZero else { return nil }
            value = -(line.b * known + line.c) / line.a
            steps.append(Step("Write the line's equation", "", [line.answer]))
            steps.append(Step("Put in y = \(known.written)", "Then find x.", [MathLine(.symbol(letter), value.expr)]))
        } else {
            guard !line.b.isZero else { return nil }
            value = -(line.a * known + line.c) / line.b
            steps.append(Step("Write the line's equation", "", [line.answer]))
            steps.append(Step("Put in x = \(known.written)", "", [MathLine(.symbol(letter), value.expr)]))
        }
        guard value.isValid else { return nil }
        return Answer(question: "value of \(letter)", lines: [MathLine(.symbol(letter), value.expr)], steps: steps, usedPoints: used, usedEquations: equations)
    }

    // MARK: Points equally spaced along a line

    /// "A, B, C, D and E are points on a straight line. A, B, C and D are equally spaced. AD : DE = 2 : 1. Work out the coordinates of E."
    private static func spaced(_ q: Question) -> Answer? {
        guard has(#"\bon (?:a|the) (?:same )?straight line\b|\bstraight line\b"#, q.text) else { return nil }
        var order: [String]
        if let list = groups(#"((?:(?-i:[A-Z]), )*(?-i:[A-Z])),? and ((?-i:[A-Z])) are equally spaced"#, in: q.text) {
            order = list[1].components(separatedBy: ", ") + [list[2]]
        } else if let chain = groups(#"(?:^|[^A-Za-z])((?-i:[A-Z]{2})(?: ?= ?(?-i:[A-Z]{2}))+)(?![A-Za-z])"#, in: q.text) {
            // "AB = BC = CD": each piece starts where the last one ended.
            let pieces = chain[1].components(separatedBy: "=").map { Array($0.trimmingCharacters(in: .whitespaces)) }
            guard pieces.allSatisfy({ $0.count == 2 }) else { return nil }
            order = [String(pieces[0][0])]
            for (index, piece) in pieces.enumerated() {
                guard index == 0 || piece[0] == pieces[index - 1][1] else { return nil }
                order.append(String(piece[1]))
            }
        } else { return nil }
        guard order.count >= 3, Set(order).count == order.count else { return nil }
        // Where each point is, in steps from the first.
        var at: [String: F] = [:]
        for (index, letter) in order.enumerated() { at[letter] = F(index) }
        var steps: [Step] = []
        let ratios = every(#"(?:^|[^A-Za-z])((?-i:[A-Z]))((?-i:[A-Z])) ?: ?((?-i:[A-Z]))((?-i:[A-Z])) ?= ?(\d+(?:\.\d+)?) ?: ?(\d+(?:\.\d+)?)"#, in: q.text)
        var pending = ratios.filter { $0[2] == $0[3] }
        guard pending.count == ratios.count else { return nil }
        var progress = true
        while progress, !pending.isEmpty {
            progress = false
            for (index, r) in pending.enumerated() {
                guard let m = F.parse(r[5]), let n = F.parse(r[6]), !m.isZero, !n.isZero else { return nil }
                let x = r[1], y = r[2], z = r[4]
                if let tx = at[x], let ty = at[y], at[z] == nil {
                    let tz = ty + n / m * (ty - tx)
                    at[z] = tz
                    steps.append(Step("Use \(x)\(y) : \(y)\(z) = \(r[5]) : \(r[6])", "\(x)\(y) is \((ty - tx).written) step\((ty - tx) == F(1) ? "" : "s"), so \(y)\(z) is \(n.written)/\(m.written) of that: \(z) is \(tz.written) steps along.".replacingOccurrences(of: "/", with: "∕"), []))
                } else if let ty = at[y], let tz = at[z], at[x] == nil {
                    let tx = ty - m / n * (tz - ty)
                    at[x] = tx
                    steps.append(Step("Use \(x)\(y) : \(y)\(z) = \(r[5]) : \(r[6])", "\(y)\(z) is \((tz - ty).written) step\((tz - ty) == F(1) ? "" : "s"), so \(x) is \(tx.written) steps along.", []))
                } else { continue }
                pending.remove(at: index)
                progress = true
                break
            }
        }
        guard pending.isEmpty else { return nil }
        // Two points with known coordinates fix the line; the asked one is found from them.
        let known = at.keys.filter { q.named[$0] != nil }.sorted { at[$0]!.double < at[$1]!.double }
        guard known.count >= 2, let first = known.first, let p = q.named[first], let tp = at[first] else { return nil }
        let second = known[1]
        guard let r = q.named[second], let tr = at[second], tr != tp else { return nil }
        let step = Point(x: (r.x - p.x) / (tr - tp), y: (r.y - p.y) / (tr - tp))
        func position(_ t: F) -> Point { Point(x: p.x + (t - tp) * step.x, y: p.y + (t - tp) * step.y) }
        // Any other point given has to fit.
        for letter in known.dropFirst(2) { guard let given = q.named[letter], let t = at[letter], position(t) == given else { return nil } }
        let unknown = at.keys.filter { q.named[$0] == nil && has(#"\bcoordinates of (?:the )?(?:point )?(?-i:\#($0))\b|\bfind (?:the point )?(?-i:\#($0))\b"#, q.text) }
        guard unknown.count == 1, let asked = unknown.first, let ta = at[asked] else { return nil }
        let point = position(ta)
        guard point.isValid, step.isValid else { return nil }
        steps.insert(Step("One step along the line", "\(first) to \(second) is \((tr - tp).written) step\((tr - tp) == F(1) ? "" : "s"), so one step is \(step.written).", []), at: 0)
        let k = ta - tp
        steps.append(Step("Go \(k.written) steps from \(first)", "",
                          [MathLine(.symbol(asked), .symbol("(\(p.x.written) + \(k.written) × \(signed(step.x)), \(p.y.written) + \(k.written) × \(signed(step.y)))"), .symbol(point.written))]))
        let used = Set(known.compactMap { q.named[$0] })
        return Answer(question: "coordinates of \(asked)", lines: [pointLine(point)], steps: steps, usedPoints: used, usedEquations: 0, points: [point])
    }

    private static func signed(_ f: F) -> String { f.double < 0 ? "(\(f.written))" : f.written }

    // MARK: The other end, from a midpoint

    private static func midpointEnd(_ q: Question) -> Answer? {
        guard let found = groups(#"(?:^|[^A-Za-z])((?-i:[A-Z])) is the midpoint of (?:the line )?(?:segment )?((?-i:[A-Z]))((?-i:[A-Z]))(?![A-Za-z])"#, in: q.text) else { return nil }
        let mid = found[1], one = found[2], two = found[3]
        guard let pm = q.named[mid] else { return nil }
        let known: String, asked: String
        if q.named[one] != nil, q.named[two] == nil { (known, asked) = (one, two) }
        else if q.named[two] != nil, q.named[one] == nil { (known, asked) = (two, one) }
        else { return nil }
        guard has(#"\bcoordinates of (?:the )?(?:point )?\#(asked)\b|\bfind (?:the point )?\#(asked)\b"#, q.text), let pk = q.named[known] else { return nil }
        let point = Point(x: F(2) * pm.x - pk.x, y: F(2) * pm.y - pk.y)
        guard point.isValid else { return nil }
        return Answer(question: "coordinates of \(asked)", lines: [pointLine(point)],
                      steps: [Step("Go as far again", "\(mid) is halfway, so \(asked) is as far beyond \(mid) as \(known) is before it: double \(mid) and take away \(known).",
                                   [MathLine(.symbol("x"), .add([.multiply([.integer(2), pm.x.expr]), .multiply([.minusOne, pk.x.expr])]), point.x.expr), MathLine(.symbol("y"), .add([.multiply([.integer(2), pm.y.expr]), .multiply([.minusOne, pk.y.expr])]), point.y.expr)])],
                      usedPoints: [pm, pk], usedEquations: 0, points: [point])
    }

    // MARK: The gradient of a line through two points

    private static func gradient(_ q: Question) -> Answer? {
        let ask = #"\b(?:work out|find|calculate|what is|write down|circle) the gradient of (.+?)(?:\.|\?|$)"#
        guard every(ask, in: q.text).count == 1, !has(#"\b(?:work out|find|write down|give|state) (?:an |the )?equation of\b"#, q.text),
              let found = groups(ask, in: q.text) else { return nil }
        var phrase = found[1].replacingOccurrences(of: #"^(?:the )?(?:straight )?(?:line )?(?:segment )?(?:that )?(?:passing |passes |going |goes )?(?:through |joining |between |from )?(?:the points )?"#, with: "", options: .regularExpression)
        phrase = phrase.trimmingCharacters(in: .whitespaces)
        let ends = matches(pair, in: phrase)
        var p: Point, r: Point
        if ends.count == 2, let x1 = F.parse(ends[0].groups[1]), let y1 = F.parse(ends[0].groups[2]), let x2 = F.parse(ends[1].groups[1]), let y2 = F.parse(ends[1].groups[2]) {
            (p, r) = (Point(x: x1, y: y1), Point(x: x2, y: y2))
        } else if let letters = groups(#"^((?-i:[A-Z]))(?: and | to )?((?-i:[A-Z]))(?![A-Za-z])"#, in: phrase), let a = q.named[letters[1]], let b = q.named[letters[2]] {
            (p, r) = (a, b)
        } else if let letter = groups(#"^line ((?-i:[A-Z]))(?![A-Za-z])"#, in: found[1].replacingOccurrences(of: "the ", with: ""))?[1], let d = named(letter, q, depth: 0) {
            if Set(d.points).count == 2, d.parallel.isEmpty, d.perpendicular.isEmpty, d.gradient == nil, d.equation == nil {
                (p, r) = (d.points[0], d.points.first { $0 != d.points[0] }!)
            } else {
                // "Line A is perpendicular to line B. The gradient of line A is −2. Work out the gradient of line B."
                guard d.points.isEmpty, d.equation == nil, d.gradient == nil else { return nil }
                var steps: [Step] = []
                var used = Set<Point>()
                var equations = 0
                guard let m = slope(d, &steps, used: &used, equations: &equations), m.isValid else { return nil }
                return Answer(question: "gradient of line \(letter)", lines: [MathLine(m.expr)], steps: steps, usedPoints: used, usedEquations: equations)
            }
        } else if phrase.isEmpty || phrase.lowercased() == "line", q.equations.count == 1, let line = straight(q.equations[0]), let m = line.gradient {
            // "The equation of a straight line is 2y = 3x + 5. Circle the gradient of the line."
            let e = q.equations[0]
            if let circle = q.text.range(of: #"(?i)\bcircle (?:the|your)\b[^.?]*[.?]?"#, options: [.regularExpression, .backwards]) {
                // Numbers to choose from: the gradient has to be one of them.
                let offered = every(#"-?\d+(?:\.\d+)?(?:\s*/\s*\d+)?"#, in: String(q.text[circle.upperBound...])).compactMap { F.parse($0[0]) }
                guard offered.isEmpty || offered.contains(m) else { return nil }
            }
            let written = MathLine(e.left, e.right).text
            let rearranged = e.left != .symbol("y") || line.written != "y = \(Format.text(e.right))"
            let step = Step(rearranged ? "Rearrange \(written) into y = mx + c" : "Read off the gradient of \(written)", "In y = mx + c, m is the gradient: the number in front of x.",
                            rearranged ? [MathLine(e.left, e.right), line.answer, MathLine(.symbol("m"), m.expr)] : [MathLine(.symbol("m"), m.expr)])
            return Answer(question: "gradient of the line", lines: [MathLine(m.expr)], steps: [step], usedPoints: [], usedEquations: 1)
        } else { return nil }
        guard p.x != r.x else { return nil }
        let m = (r.y - p.y) / (r.x - p.x)
        guard m.isValid else { return nil }
        return Answer(question: "gradient", lines: [MathLine(m.expr)],
                      steps: [Step("Gradient is the change in y over the change in x", "From \(p.written) to \(r.written).", [MathLine(.symbol("m"), (r.y - p.y).expr / (r.x - p.x).expr, m.expr)])],
                      usedPoints: [p, r], usedEquations: 0)
    }

    // MARK: The length of a line between two points

    private static func length(_ q: Question) -> Answer? {
        guard let found = groups(#"\b(?:length of (?:the )?(?:straight )?(?:line )?(?:segment )?|distance (?:between|from) )((?-i:[A-Z])) ?(?:and |to )?((?-i:[A-Z]))(?![A-Za-z])"#, in: q.text),
              let p = q.named[found[1]], let r = q.named[found[2]], p != r, has(#"\b(?:work out|find|calculate|what is)\b"#, q.text) else { return nil }
        let dx = r.x - p.x, dy = r.y - p.y
        let square = dx * dx + dy * dy
        guard square.isValid else { return nil }
        let size: Expr
        if let root = square.root { size = root.expr } else { size = Simplify.run(.power(square.expr, .half)) }
        var lines = [MathLine(size)]
        // Rounded as asked.
        if let asked = groups(#"(\d) (decimal places?|significant figures?)"#, in: q.text), let places = Int(asked[1]), square.root == nil {
            let value = square.double.squareRoot()
            let isDecimal = asked[2].hasPrefix("d")
            let scale = isDecimal ? pow(10, Double(places)) : pow(10, Double(places) - 1 - floor(log10(value)))
            lines = [MathLine(.number(.real((value * scale).rounded() / scale)))]
        }
        return Answer(question: "length of \(found[1])\(found[2])", lines: lines,
                      steps: [Step("Use Pythagoras", "Across \(dx.written), up \(dy.written): the line is the hypotenuse.",
                                   [MathLine(.symbol("\(found[1])\(found[2])²"), .add([.power(dx.expr, .two), .power(dy.expr, .two)]), square.expr), MathLine(.symbol("\(found[1])\(found[2])"), size)])],
                      usedPoints: [p, r], usedEquations: 0)
    }

    // MARK: Pieces

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func every(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    /// Each match with its groups and where it starts, in characters.
    private static func matches(_ pattern: String, in text: String) -> [(groups: [String], at: Int)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text) else { return nil }
            let groups = (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            return (groups, text.distance(from: text.startIndex, to: whole.lowerBound))
        }
    }

    /// The text cut into sentences.
    private static func sentences(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.?])\s+|\?"#, with: "\n", options: .regularExpression).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }.filter { !$0.isEmpty }
    }
}

