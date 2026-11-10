import Foundation

/// Why a sum couldn't be worked out.
enum MathsProblem: Error, Sendable {
    case divideByZero
    case notReal
    case tooBig

    var message: String {
        switch self {
        case .divideByZero: "Can't divide by zero"
        case .notReal: "Not a real number"
        case .tooBig: "Too big to work out"
        }
    }
}

/// A sum found in some text, and its answer.
struct Calculation: Sendable {
    /// The sum as read, tidied up: "12 × (3 + 4.5)".
    let text: String
    let answer: Result<Double, MathsProblem>
}

/// MathPeek's own small calculator. It only ever computes numbers: there is nothing in it
/// that could run code or fail badly on odd input, unlike NSExpression.
///
/// It understands + − × ÷ * / ^, percentages (`50 + 10%` is 55, `15% of 80` is 12, as on a
/// calculator), √, ² and ³, parentheses (a missing closing one is added), `2(3 + 4)`, thousands
/// separators, and the things text recognition tends to produce: a unicode minus, × read as
/// x, a trailing =.
enum Maths {
    /// Finds the sums in a line of text, with the range of characters each came from, so the
    /// one nearest the pointer can be chosen.
    static func findSums(in line: String) -> [(calculation: Calculation, range: Range<Int>)] {
        let characters = normalizedCharacters(line)
        var found: [(Calculation, Range<Int>)] = []
        var start: Int?
        for index in 0...characters.count {
            let isMaths = index < characters.count && runCharacters.contains(characters[index])
            if isMaths, start == nil {
                start = index
            } else if !isMaths, let first = start {
                start = nil
                // An = ends one sum and starts the next: "3 + 4 = 7" holds one sum and an answer.
                var pieceStart = first
                for split in first...index where split == index || characters[split] == "=" {
                    let piece = String(characters[pieceStart..<split])
                    for part in pieces(normalizedPiece(piece)) {
                        if let calculation = calculatePiece(part) {
                            found.append((calculation, pieceStart..<split))
                        }
                    }
                    pieceStart = split + 1
                }
            }
        }
        return found
    }

    // MARK: Cleaning up text

    /// What a sum can be made of once `normalizedCharacters` has run: the rest of a line
    /// separates sums.
    private static let runCharacters: Set<Character> = Set("0123456789 .,+-*/^%()√²³=$£€¥")

    /// Turns the many ways a sum is written into one, keeping every character in place (so the
    /// result lines up with the text recognised on screen).
    static func normalizedCharacters(_ text: String) -> [Character] {
        var characters = Array(text)
        let count = characters.count
        func previous(_ index: Int) -> Character? {
            var i = index - 1
            while i >= 0, characters[i] == " " { i -= 1 }
            return i >= 0 ? characters[i] : nil
        }
        func next(_ index: Int) -> Character? {
            var i = index + 1
            while i < count, characters[i] == " " { i += 1 }
            return i < count ? characters[i] : nil
        }
        for index in 0..<count {
            switch characters[index] {
            case "×", "✕", "✖", "∗", "⋅", "·", "•": characters[index] = "*"
            case "÷", "∕", "⁄": characters[index] = "/"
            case "−", "–", "—", "‒", "﹣", "－": characters[index] = "-"
            case "＋": characters[index] = "+"
            case "[", "{", "（": characters[index] = "("
            case "]", "}", "）": characters[index] = ")"
            case "\u{00A0}", "\u{2009}", "\u{202F}", "\t": characters[index] = " "
            default: break
            }
        }
        for index in 0..<count {
            let character = characters[index]
            let before = previous(index), after = next(index)
            // "12 x 3": text recognition often reads × as the letter x.
            if character == "x" || character == "X" {
                if let before, before.isNumber || before == ")" || before == "%",
                   let after, after.isNumber || after == "(" || after == "." || after == "√" {
                    characters[index] = "*"
                }
            }
            // Text recognition reads √ as V: "V144".
            if character == "V", index + 1 < count, characters[index + 1].isNumber || characters[index + 1] == "(",
               index == 0 || " +-*/^(".contains(characters[index - 1]) {
                characters[index] = "√"
            }
            // A letter O or l inside a number is a 0 or 1 misread.
            if "Oo".contains(character) || "lI|".contains(character) {
                let left = index > 0 ? characters[index - 1] : nil
                let right = index + 1 < count ? characters[index + 1] : nil
                let digitBeside = (left?.isNumber ?? false) || (right?.isNumber ?? false)
                let letterBeside = (left?.isLetter ?? false) || (right?.isLetter ?? false)
                if digitBeside && !letterBeside {
                    characters[index] = "Oo".contains(character) ? "0" : "1"
                }
            }
        }
        // "15% of 80" is 15% × 80.
        for index in 0..<count where characters[index] == "%" {
            var i = index + 1
            while i < count, characters[i] == " " { i += 1 }
            if i + 1 < count, characters[i].lowercased() == "o", characters[i + 1].lowercased() == "f",
               i + 2 == count || !characters[i + 2].isLetter {
                characters[i] = " "
                characters[i + 1] = "*"
            }
        }
        return characters
    }

    /// The tidying that changes a piece's length: currency signs, superscripts, ** for powers,
    /// thousands separators. Uses this Mac's decimal separator.
    private static func normalizedPiece(_ characters: [Character]) -> String {
        normalizedPiece(String(characters))
    }

    private static func normalizedPiece(_ text: String) -> String {
        var text = text
        for sign in ["$", "£", "€", "¥"] {
            text = text.replacingOccurrences(of: sign, with: "")
        }
        text = text.replacingOccurrences(of: "²", with: "^2")
            .replacingOccurrences(of: "³", with: "^3")
            .replacingOccurrences(of: "**", with: "^")
            .replacingOccurrences(of: "=", with: "")
        if Locale.current.decimalSeparator == "," {
            // 1.234,5: dots group thousands and the comma is the decimal point.
            text = text.replacingOccurrences(of: #"(?<=\d)\.(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(?<=\d),(?=\d)"#, with: ".", options: .regularExpression)
        } else {
            text = text.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        }
        return text
    }

    /// Any comma left separates things in a list, so each part is a sum of its own.
    private static func pieces(_ text: String) -> [String] {
        text.split(separator: ",").map { tidyEnds(String($0)) }.filter { !$0.isEmpty }
    }

    /// Drops what can't start or end a sum, such as a full stop after it or an unmatched
    /// bracket from the sentence around it.
    private static func tidyEnds(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed && !text.isEmpty {
            changed = false
            let opens = text.filter { $0 == "(" }.count
            let closes = text.filter { $0 == ")" }.count
            if let first = text.first, "*/^%).".contains(first) && !(first == "." && text.dropFirst().first?.isNumber == true)
                || (first == "(" && opens > closes) {
                text.removeFirst()
                changed = true
            } else if let last = text.last, "+-*/^(√.".contains(last) || (last == ")" && closes > opens) {
                text.removeLast()
                changed = true
            }
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func calculatePiece(_ text: String) -> Calculation? {
        guard var parser = Parser(text) else { return nil }
        do {
            let value = try parser.parse()
            guard parser.operations > 0 else { return nil }
            guard value.isFinite else {
                return Calculation(text: parser.pretty, answer: .failure(value.isNaN ? .notReal : .tooBig))
            }
            return Calculation(text: parser.pretty, answer: .success(value == 0 ? 0 : value))
        } catch let problem as MathsProblem {
            return Calculation(text: parser.pretty, answer: .failure(problem))
        } catch {
            return nil
        }
    }

    // MARK: Showing answers

    /// The answer as shown: grouped thousands, a proper minus sign, at most 10 decimals, no
    /// floating-point noise (0.1 + 0.2 is 0.3), and scientific notation when it's huge or tiny.
    /// `forCopying` leaves out the grouping and uses a plain hyphen, so it pastes anywhere.
    static func format(_ value: Double, forCopying: Bool = false) -> String {
        let rounded = Double(String(format: "%.12g", value)) ?? value
        let formatter = NumberFormatter()
        formatter.locale = .current
        let grouped = !forCopying
        formatter.minusSign = forCopying ? "-" : "−"
        let magnitude = abs(rounded)
        if magnitude >= 1e15 || (magnitude > 0 && magnitude < 1e-9) {
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = 9
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 10
            formatter.usesGroupingSeparator = grouped
        }
        return formatter.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? "\(rounded)"
    }
}

/// Recursive descent over a tidied sum. Grammar, loosest first:
///
///     sum     = term (("+" | "-") term)*
///     term    = signed (("*" | "/" | nothing before "(" or "√") signed)*
///     signed  = ("-" | "+") signed | power
///     power   = postfix ("^" signed)?
///     postfix = primary "%"*
///     primary = number | "(" sum ")" | "√" postfix
private struct Parser {
    private enum Token: Equatable {
        case number(Double, String)
        case symbol(Character)
    }

    private struct SyntaxError: Error {}

    /// A value, and if it's a bare percentage ("10%"), the percentage, so that `50 + 10%`
    /// can mean 10% of 50.
    private struct Value {
        var number: Double
        var percent: Double?
    }

    private var tokens: [Token]
    private var position = 0
    /// How many operations the sum has; a lone number has none.
    private(set) var operations = 0

    init?(_ text: String) {
        var tokens: [Token] = []
        var characters = Array(text)[...]
        while let character = characters.first {
            if character == " " {
                characters.removeFirst()
            } else if character.isASCII && character.isNumber || character == "." {
                var digits = ""
                while let next = characters.first, next.isASCII && next.isNumber || next == "." {
                    digits.append(next)
                    characters.removeFirst()
                }
                guard digits.filter({ $0 == "." }).count <= 1, digits != ".",
                      let value = Double(digits.hasPrefix(".") ? "0" + digits : digits) else { return nil }
                tokens.append(.number(value, digits))
            } else if "+-*/^%()√".contains(character) {
                tokens.append(.symbol(character))
                characters.removeFirst()
            } else {
                return nil
            }
        }
        guard !tokens.isEmpty else { return nil }
        self.tokens = tokens
    }

    /// The sum written out neatly, with proper × ÷ − signs.
    var pretty: String {
        var text = ""
        var previous: Token?
        for token in tokens {
            switch token {
            case .number(_, let digits):
                text += Self.grouped(digits)
            case .symbol(let symbol):
                let afterValue: Bool
                switch previous {
                case .number?, .symbol(")")?, .symbol("%")?: afterValue = true
                default: afterValue = false
                }
                switch symbol {
                case "*": text += " × "
                case "/": text += " ÷ "
                case "+": text += afterValue ? " + " : "+"
                case "-": text += afterValue ? " − " : "−"
                default: text.append(symbol)
                }
            }
            previous = token
        }
        return text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// A number as written, with this Mac's thousands and decimal separators put back:
    /// "1250.75" is shown as "1,250.75".
    private static func grouped(_ digits: String) -> String {
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        var whole = String(parts[0])
        let separator = Locale.current.groupingSeparator ?? ","
        var index = whole.count - 3
        while index > 0 {
            whole.insert(contentsOf: separator, at: whole.index(whole.startIndex, offsetBy: index))
            index -= 3
        }
        guard parts.count > 1 else { return whole }
        return whole + (Locale.current.decimalSeparator ?? ".") + parts[1]
    }

    mutating func parse() throws -> Double {
        position = 0
        operations = 0
        let value = try sum()
        guard position == tokens.count else { throw SyntaxError() }
        return value.number
    }

    private var current: Token? { position < tokens.count ? tokens[position] : nil }

    private mutating func take(_ symbol: Character) -> Bool {
        guard current == .symbol(symbol) else { return false }
        position += 1
        return true
    }

    private mutating func sum() throws -> Value {
        var left = try term()
        while true {
            let isPlus: Bool
            if take("+") { isPlus = true } else if take("-") { isPlus = false } else { return left }
            operations += 1
            let right = try term()
            // Calculator percentages: 50 + 10% adds 10% of 50.
            let amount = right.percent.map { left.number * $0 / 100 } ?? right.number
            left = Value(number: isPlus ? left.number + amount : left.number - amount)
        }
    }

    private mutating func term() throws -> Value {
        var left = try signed()
        while true {
            // implicitMultiplication: 2(3 + 4), (1 + 2)(3 + 4), 2√9, (2)3
            if take("*") || implicitMultiplication() {
                operations += 1
                let right = try signed().number
                left = Value(number: left.number * right)
            } else if take("/") {
                operations += 1
                let right = try signed().number
                guard right != 0 else { throw MathsProblem.divideByZero }
                left = Value(number: left.number / right)
            } else {
                return left
            }
        }
    }

    private func implicitMultiplication() -> Bool {
        guard position > 0, let next = current else { return false }
        switch next {
        case .symbol("("), .symbol("√"): return true
        case .number: return tokens[position - 1] == .symbol(")")
        default: return false
        }
    }

    private mutating func signed() throws -> Value {
        if take("-") {
            let value = try signed()
            return Value(number: -value.number, percent: value.percent.map { -$0 })
        }
        if take("+") { return try signed() }
        return try power()
    }

    private mutating func power() throws -> Value {
        let base = try postfix()
        guard take("^") else { return base }
        operations += 1
        let exponent = try signed().number
        return Value(number: pow(base.number, exponent))
    }

    private mutating func postfix() throws -> Value {
        var value = try primary()
        while take("%") {
            value = Value(number: value.number / 100, percent: value.percent == nil ? value.number : nil)
        }
        return value
    }

    private mutating func primary() throws -> Value {
        switch current {
        case .number(let value, _)?:
            position += 1
            return Value(number: value)
        case .symbol("(")?:
            position += 1
            let value = try sum()
            // A missing closing bracket at the very end is added, as calculators do.
            guard take(")") || current == nil else { throw SyntaxError() }
            return Value(number: value.number)
        case .symbol("√")?:
            position += 1
            operations += 1
            let value = try postfix().number
            guard value >= 0 else { throw MathsProblem.notReal }
            return Value(number: value.squareRoot())
        default:
            throw SyntaxError()
        }
    }
}
