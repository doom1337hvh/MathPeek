import Foundation

/// Exam questions asked in words that always mean the same sum: "Work out 20% of 14 000",
/// "Write 0.85 as a fraction", "the number that is 5 less than −2", "Work out the median",
/// "Which of these values of x gives the greatest value of y?". Each becomes a problem the
/// engine works out, with the steps that turn the words into the sum put in front.
enum Worded {
    static func problem(_ input: String) -> Problem? {
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let question = read(display) else { return nil }
        let text = question.text
        guard text.count <= 900 else { return nil }
        var found = choice(text, display) ?? table(text) ?? formulaBounds(text, question) ?? bounds(text, display)
        // A question that asks for a reason, a proof, a drawing or a box to tick isn't asking
        // for the number its words would give.
        if found == nil, !has(refusal, text) {
            let kinds: [() -> Problem?] = [
                { proportion(text, single: true) }, { functions(text) }, { further(text, question) }, { chosen(text) }, { chances(text) }, { more(text, question) }, { extra(text, question) }, { breadth(text, question) },
                { picked(text, question) }, { sums(text) }, { standardForm(text) }, { primeFactors(text) },
                { sequence(text, question) }, { ratioForms(text) }, { labelled(text, question) }, { ratio(text, question) }, { statistic(text, question) },
                { conversion(text, question) }, { units(text) }, { measures(text) }, { percentages(text, money: question.money) }, { costs(text, question) },
                { combos(question) }, { shorts(text, question) },
                { shapes(text) }, { points(text) }, { algebra(text) }, { estimate(text, question) }, { angles(text) },
                { share(text) }, { rate(text) }, { factors(text) }, { rounding(text) }, { phrase(text) },
            ]
            // (One the engine can't answer would only stand in the way of the kinds and the solvers tried after it.)
            for kind in kinds {
                if let problem = kind(), isAnswerable(problem) { found = problem; break }
            }
        }
        guard var problem = found, isAnswerable(problem) else { return nil }
        // "Give the units of your answer": a number on its own isn't the answer then. (The kinds that know their units give them.)
        if has(unitsAsked, text), case .evaluate = problem.kind { return nil }
        problem = finished(problem, text)
        guard isOffered(problem, text) else { return nil }
        problem.text = display
        return problem
    }

    /// Where a question asks for more than one of a kind's answers, the one to give: the last, when each is a lettered part of its own
    /// ("(a) … (b) …": the whole question is only tried for a later part, and the app drops an answer that doesn't depend on the part
    /// pointed at). With (i) and (ii) inside one part, or no labels, there is no telling, and nothing is given.
    private static func chosenAsk(_ text: String, _ asks: [String]) -> Int? {
        var places: [(index: Int, at: String.Index)] = []
        for (index, pattern) in asks.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) { places.append((index, range.lowerBound)) }
            }
        }
        guard !places.isEmpty else { return nil }
        if Set(places.map(\.index)).count == 1 { return places[0].index }
        places.sort { $0.at < $1.at }
        // Each ask's own part letter, with no (i), (ii) between them.
        var labels: [String] = []
        for place in places {
            let before = String(text[..<place.at])
            guard let label = every(#"\(([a-h])\)"#, in: before).last?[1] else { return nil }
            if let roman = before.range(of: #"\((?:i{1,3}|iv|v)\)"#, options: [.regularExpression, .backwards]),
               let letter = before.range(of: "(\(label))", options: .backwards), roman.lowerBound > letter.lowerBound { return nil }
            labels.append(label)
        }
        guard Set(labels).count == labels.count else { return nil }
        return places[places.count - 1].index
    }

    /// Whether the engine gives an answer to a problem made here.
    private static func isAnswerable(_ problem: Problem) -> Bool {
        guard let solution = Engine.solve(problem, angles: problem.angles ?? .degrees) else { return false }
        return !solution.answers.isEmpty || solution.note != nil
    }

    // MARK: Reading the question

    /// The question's words made plain.
    private struct Question {
        /// All of it on one line, with the signs and spaces exam papers use made plain.
        var text: String
        /// The same, with the pound signs left in.
        var money: String
        /// Lists of numbers standing on lines of their own, each one in the order it's written.
        var lists: [[String]]
        /// Its lines, top to bottom, without the pound signs.
        var lines: [String]
    }

    private static let unitsAsked = #"\b(?:give|state|include|write)(?: the)? units\b"#

    private static let refusal = #"\bshow that\b|\bprove\b|\bexplain\b|\bgive (?:a|one|two|your) reasons?\b|\btick\b|\bis (?:he|she|it|this|that|[a-z]+|(?:his|her|their) (?:method|answer|working)) (?:correct|right)\b|\bare they correct\b|\bcriticis|\bmistakes?\b|\bdraw\b|\bsketch\b|\bplot\b|\bshade\b|\bdescribe\b|\bconstruct\b|\bmatch each\b|\bcomplete (?:the|this|these|each) (?!error interval|statement\b|job\b|work\b|task\b|race\b|journey\b|marathon\b|course\b)|\bone has been done\b|\bestimate the (?!value of)|\buse the (?:graph|chart|diagram|table|histogram)\b"#

    private static func read(_ display: String) -> Question? {
        var raw = display
        for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "), ("\u{FFFC}", " "),
                           ("º", "°"), ("⩽", "≤"), ("⩾", "≥"), ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\"")] { raw = raw.replacingOccurrences(of: from, with: to) }
        // Raised digits are powers: 10⁻³ is 10^(-3).
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
        // Letters from other alphabets that were read for ones that look the same: Cyrillic а for a, В for B.
        let alike: [Character: Character] = ["а": "a", "А": "A", "В": "B", "в": "b", "С": "C", "с": "c", "Е": "E", "е": "e", "Н": "H", "К": "K", "к": "k", "М": "M", "О": "O", "о": "o", "Р": "P", "р": "p",
                                              "Т": "T", "Х": "X", "х": "x", "У": "Y", "у": "y", "ѕ": "s", "і": "i", "ј": "j", "ԁ": "d", "д": "g", "З": "3", "з": "3", "п": "n", "П": "π", "л": "π", "†": "t", "и": "u"]
        raw = String(raw.map { alike[$0] ?? $0 })
        // A letter o between two digits is a nought: "185o00".
        raw = raw.replacingOccurrences(of: #"(?<=\d)[oO](?=\d)"#, with: "0", options: .regularExpression)
        // A capital I inside a small-letter word is an l: "goId".
        raw = raw.replacingOccurrences(of: #"(?<=[a-z])I(?=[a-z])"#, with: "l", options: .regularExpression)
        // The numbers of the questions with parts in view: "9 (a)" means a lone 9 on a line is the question's number too.
        let numbered = Set(every(#"(?m)^\s*(\d{1,2}) ?\([a-z]\)"#, in: raw).map { $0[1] })
        var lines: [String] = []
        for (index, piece) in raw.components(separatedBy: "\n").enumerated() {
            var line = piece.trimmingCharacters(in: .whitespaces)
            // The margin's "Do not write outside the box", read in pieces.
            if line.range(of: #"^(?:do not(?: write)?|outside(?: the)?(?: box)?|the box|box|bo:?|write)$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if numbered.contains(line) { continue }
            // Other boards' page furniture: "(Total for Question 7 is 2 marks)", "Turn over", a bar code's number, "© OCR 2023".
            if line.range(of: #"^\(?Total for [A-Za-z]{6,9} \d+ is \d+ marks?\)?$|^Turn over\b.{0,3}$|^\*?P ?\d[\dA-Z ]{6,}\*?$|^© ?OCR\b.*$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            // A ruled line read as a bar in front of the words.
            line = line.replacingOccurrences(of: #"^\|+ ?"#, with: "", options: .regularExpression)
            // The space left for the answer: "x =", "a = b = c =", "x= _".
            if line.range(of: #"^(?:[A-Za-z] ?= ?[_. ]*){1,4}$"#, options: .regularExpression) != nil { continue }
            // "Write" is often read without its r.
            line = line.replacingOccurrences(of: #"^Wite\b"#, with: "Write", options: .regularExpression)
            // A question's number at the start of a line ("10 (a) Work out…") isn't one of its numbers.
            line = line.replacingOccurrences(of: #"^\d{1,2}\s*(?:\([a-z]\)\s*)?(?:\([ivx]+\)\s*)?(?=[A-Z])"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\d{1,2} ?\([a-z]\)(?: ?\([ivx]+\))?$"#, with: "", options: .regularExpression)
            if index == 0 { line = line.replacingOccurrences(of: #"^\d{1,2}$|^\d{1,2} (?=\d[\d.,]* [a-z])|^\d{1,2} +(?=\([a-z] ?[-+]|\d+[a-z]\d? ?[-+])"#, with: "", options: .regularExpression) }
            // The marks, and the space left for the answer.
            line = line.replacingOccurrences(of: #"\[\d+ marks?\]"#, with: "", options: [.regularExpression, .caseInsensitive])
            if line.range(of: #"^Answer\b"#, options: .regularExpression) != nil { continue }
            line = grouped(line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces))
            if !line.isEmpty { lines.append(line) }
        }
        // 0.000 97 is one number.
        lines = lines.map { $0.replacingOccurrences(of: #"(?<![\d.])(0\.000) (\d{1,3})(?!\d|\.\d)"#, with: "$1$2", options: .regularExpression) }
        let money = lines.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let text = money.replacingOccurrences(of: "£", with: "").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Lines that are nothing but numbers, one after another, are one list.
        var lists: [[String]] = []
        var run: [String] = []
        for line in lines + [""] {
            let tokens = line.replacingOccurrences(of: "£", with: "").replacingOccurrences(of: #"[,…]|\.{2,}"#, with: " ", options: .regularExpression).split(separator: " ").map(String.init)
            if !tokens.isEmpty, tokens.allSatisfy({ $0.range(of: "^\(number)$", options: .regularExpression) != nil }) {
                run += tokens
            } else {
                if run.count >= 3 { lists.append(run) }
                run = []
            }
        }
        return Question(text: text, money: money, lists: lists, lines: lines.map { $0.replacingOccurrences(of: "£", with: "") })
    }

    /// 14 000 is fourteen thousand, and 2 200 000 is one number. A row of numbers (140 168 205 192)
    /// stays a row: there only a 000 belongs to the number before it.
    private static func grouped(_ line: String) -> String {
        let tokens = line.split(separator: " ").map(String.init)
        func digits(_ token: String) -> (front: String, digits: String, back: String)? {
            guard let parts = groups(#"^([£(]*)(\d+)([.,;:?)]*)$"#, in: token) else { return nil }
            return (parts[1], parts[2], parts[3])
        }
        let isRow = tokens.count >= 3 && tokens.allSatisfy { $0.range(of: #"^-?\d+(?:\.\d+)?$"#, options: .regularExpression) != nil }
        var out: [String] = []
        var index = 0
        while index < tokens.count {
            // A run of whole numbers with only spaces between them.
            var run: [(front: String, digits: String, back: String)] = []
            var next = index
            while next < tokens.count, let part = digits(tokens[next]), next == index || part.front.isEmpty {
                run.append(part)
                next += 1
                if !part.back.isEmpty { break }
            }
            guard run.count >= 2 else { out.append(tokens[index]); index += 1; continue }
            func isGroup(_ text: String) -> Bool { text.count >= 3 && text.count % 3 == 0 }
            func canLead(_ text: String) -> Bool { text.count <= 3 && (text == "0" || !text.hasPrefix("0")) && text != "0" }
            if !isRow, run.count <= 3, canLead(run[0].digits), run.dropFirst().allSatisfy({ isGroup($0.digits) }) {
                out.append(run[0].front + run.map(\.digits).joined() + run[run.count - 1].back)
            } else {
                var merged: [String] = []
                var open = false
                for (place, part) in run.enumerated() {
                    if part.digits == "000", open, !merged.isEmpty {
                        merged[merged.count - 1] += "000"
                    } else {
                        merged.append((place == 0 ? part.front : "") + part.digits)
                        open = canLead(part.digits)
                    }
                }
                merged[merged.count - 1] += run[run.count - 1].back
                out += merged
            }
            index = next
        }
        return out.joined(separator: " ")
    }

    /// After the question is turned into a sum: the answer rounded or written the way it's asked for.
    private static func finished(_ problem: Problem, _ text: String) -> Problem {
        guard case .evaluate(let expr) = problem.kind, let size = amount(expr) else { return problem }
        if has(#"answer in standard form"#, text), size > 0 {
            return told(Format.text(expr), [MathLine(.symbol(standard(size)))],
                        problem.lead + [Step("Work it out", "", [MathLine(expr, plain(size))]), Step("Write it in standard form", standardWords)])
        }
        if let asked = groups(#"answer (?:correct )?to (\d) (decimal places?|significant figures?)"#, in: text), let places = Int(asked[1]) {
            let isDecimal = asked[2].lowercased().hasPrefix("d")
            guard size != 0 || isDecimal, let rounded = roundedValue(size, places: places, significant: !isDecimal) else { return problem }
            var changed = made(plain(rounded), decimals: true, problem.lead + [Step("Work it out", "", [MathLine(expr, plain(size))]),
                                                                        Step("Round it", "The answer is asked for to \(places) \(isDecimal ? "decimal place" : "significant figure")\(places == 1 ? "" : "s").")])
            changed.angles = problem.angles
            return changed
        }
        return problem
    }

    private static func roundedValue(_ size: Double, places: Int, significant: Bool) -> Double? {
        if significant {
            guard size != 0, places >= 1 else { return nil }
            let scale = pow(10, Double(places) - 1 - floor(log10(abs(size))))
            return (size * scale).rounded(.toNearestOrAwayFromZero) / scale
        }
        let scale = pow(10, Double(places))
        return (size * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    /// "Circle your answer" comes with the answers to choose from: one worked out here that
    /// isn't among them means the question wasn't read right.
    private static func isOffered(_ problem: Problem, _ text: String) -> Bool {
        guard text.range(of: #"\bcircle\b"#, options: [.regularExpression, .caseInsensitive]) != nil, case .evaluate(let expr) = problem.kind,
              let size = amount(expr), let run = groups("((?:\(number)[ ,]+){2,}\(number))[ .°%a-z0-9^/]{0,12}$", in: text)?[1] else { return true }
        let offered = all(number, in: run).compactMap { value($0).flatMap(amount) }
        return offered.contains { abs($0 - size) < 1e-9 * max(1, abs(size)) }
    }

    // MARK: Pieces

    private static let number = #"-?\d+(?:\.\d+)?(?:/\d+)?"#

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func all(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func value(_ text: String) -> Expr? { Parser.expression(text.replacingOccurrences(of: " ", with: "")) }

    /// A decimal as the fraction it is: 0.85 as 85 over 100.
    private static func exact(_ text: String) -> Expr? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count <= 9, let top = Int(parts[0] + parts[1]) else { return value(text) }
        return .multiply([.integer(top), .power(.integer(Int(pow(10, Double(parts[1].count)))), .minusOne)])
    }

    private static func amount(_ expr: Expr) -> Double? { Simplify.run(expr).number?.double ?? (expr.symbols.subtracting(["π"]).isEmpty ? expr.evaluate() : nil) }

    private static func made(_ expr: Expr, decimals: Bool, _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: decimals)
        problem.lead = lead
        return problem
    }

    private static func whole(_ value: Double) -> Expr { CircleDiagram.number(value) }

    /// A number as it's written: whole where it is, a decimal otherwise, with no rounding noise.
    private static func plain(_ value: Double) -> Expr {
        let tidy = Double(String(format: "%.10g", value)) ?? value
        if abs(tidy - tidy.rounded()) < 1e-9, abs(tidy) < 1e15 { return .integer(Int(tidy.rounded())) }
        return .number(.real(tidy))
    }

    private static func written(_ value: Double) -> String { Format.text(plain(value)) }

    /// A sum as it's written in a question: 150 ÷ 5, 3 × (-6).
    private static func sum(_ text: String) -> Expr? { Parser.expression(Parser.normalize(text)) }

    /// Every match of a pattern, as its captured groups.
    private static func every(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether the question asks for something to be worked out, rather than telling a story.
    private static func asks(_ text: String) -> Bool { has(#"\b(?:work out|find|calculate|write down|what is|what's|circle|how (?:much|many|long|far))\b"#, text) }

    private static let counts = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]

    /// 5 from "5" or "five".
    private static func count(_ text: String) -> Int? { Int(text) ?? counts[text.lowercased()] }

    private static func raisedDigits(_ n: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { digits[$0] ?? $0 })
    }

    /// A number in standard form: 6 × 10⁻³.
    private static func standard(_ value: Double) -> String {
        var power = Int(floor(log10(abs(value))))
        var front = Double(String(format: "%.10g", value / pow(10, Double(power)))) ?? 1
        if abs(front) >= 10 { front /= 10; power += 1 }
        return "\(written(front)) × 10\(raisedDigits(power))"
    }

    private static let standardWords = "Standard form is a number from 1 up to 10, times a power of ten. Move the point until one digit that isn't nought is in front of it, and count the places: that's the power."

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    /// Whether a circle's or a sphere's answer is to be left with π in it: "in terms of π", or answers to
    /// choose from that have π. With every length a number, "in terms of" one letter can only be π, however it was read.
    private static func wantsPi(_ text: String) -> Bool { has(#"in terms of (?:π|pi\b|[a-zA-Z]\b)|\dπ"#, text) }

    private static func primes(of n: Int) -> [Int] {
        var rest = n, factor = 2
        var parts: [Int] = []
        while rest > 1, factor * factor <= rest {
            if rest % factor == 0 { parts.append(factor); rest /= factor } else { factor += 1 }
        }
        if rest > 1 { parts.append(rest) }
        return parts
    }

    private static func isPrime(_ n: Int) -> Bool { n >= 2 && primes(of: n) == [n] }

    /// Pounds and pence: £3.85, £18.
    private static func pounds(_ value: Double) -> String {
        abs(value - value.rounded()) < 1e-9 ? "£\(Int(value.rounded()))" : "£" + String(format: "%.2f", value)
    }

    // MARK: Units

    /// A unit's kind and its size in the smallest of its kind: "kilometres" is a length of 1 000 000 mm.
    private static func unit(_ word: String) -> (kind: String, size: Double)? {
        let table: [(String, String, Double)] = [
            (#"mm|millimetres?"#, "length", 1), (#"cm|centimetres?"#, "length", 10), (#"m|metres?"#, "length", 1000), (#"km|kilometres?"#, "length", 1_000_000),
            (#"mg|milligrams?"#, "mass", 1), (#"g|grams?"#, "mass", 1000), (#"kg|kilograms?"#, "mass", 1_000_000), (#"tonnes?"#, "mass", 1_000_000_000),
            (#"ml|millilitres?"#, "capacity", 1), (#"cl|centilitres?"#, "capacity", 10), (#"l|litres?"#, "capacity", 1000),
            (#"seconds?|secs?"#, "time", 1), (#"minutes?|mins?"#, "time", 60), (#"hours?|hrs?"#, "time", 3600), (#"days?"#, "time", 86400), (#"weeks?"#, "time", 604_800),
            (#"p|pence"#, "money", 1), (#"£|pounds? sterling"#, "money", 100),
        ]
        let name = word.lowercased()
        for (pattern, kind, size) in table where name.range(of: "^(?:\(pattern))$", options: .regularExpression) != nil { return (kind, size) }
        return nil
    }

    private static let unitWord = #"(?:mm|cm|km|mg|kg|ml|cl|millimetres?|centimetres?|kilometres?|metres?|milligrams?|kilograms?|grams?|tonnes?|millilitres?|centilitres?|litres?|seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|pence|m|g|l|p)"#

    /// A unit's name without its plural: "kilometres" and "kilometre" are the same.
    private static func single(_ word: String) -> String {
        let name = word.lowercased().trimmingCharacters(in: .whitespaces)
        if name == "feet" { return "foot" }
        if name.hasSuffix("ches") || name.hasSuffix("xes") { return String(name.dropLast(2)) }
        return name.count > 2 && name.hasSuffix("s") && !name.hasSuffix("ss") ? String(name.dropLast()) : name
    }

    /// A question whose answer was worked out here, in the steps that go with it.
    private static func told(_ question: String, _ answers: [MathLine], _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .worded(question: question, answers: answers), text: "", usesDecimals: false)
        problem.lead = lead
        return problem
    }

    // MARK: A table of values

    /// "Complete the table of values for y = 2^x", with the row of x values under it.
    private static func table(_ text: String) -> Problem? {
        guard let start = groups(#"table of values for ([a-z]) ?= ?"#, in: text), let whole = text.range(of: start[0], options: .caseInsensitive) else { return nil }
        let y = start[1].lowercased()
        var rest = String(text[whole.upperBound...])
        // The formula runs to the marks, or to where the table's first row starts.
        var formula = rest
        for stop in [#" ?\["#, #" [a-z] -?\d"#, #"\. "#, #" [A-Za-z]{2,}"#, #"(?<=[*×]) "#] {
            if let cut = formula.range(of: stop, options: .regularExpression) { formula = String(formula[..<cut.lowerBound]) }
        }
        formula = formula.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        // A small raised x is read as a star: 2* is 2 to the power x.
        let stars = formula.replacingOccurrences(of: #"(\d) ?[*×]$"#, with: "$1^x", options: .regularExpression)
        let length = formula.count
        formula = stars
        guard !formula.isEmpty, var expr = Parser.expression(formula) ?? Parser.expression(raised(formula)), expr.symbols.count == 1, let x = expr.symbols.first else { return nil }
        rest = String(rest.dropFirst(length))
        // The values of x: the table's top row, or "for values of x from −1 to 3" when the
        // table's single digits weren't read.
        var inputs: [Expr] = []
        if let row = groups("\\b\(x) ((?:\(number) ?){3,})", in: rest) {
            inputs = all(number, in: row[1]).compactMap(value)
        } else if let span = groups("values of \(x) from (-?\\d+) to (-?\\d+)", in: text), let low = Int(span[1]), let high = Int(span[2]), high > low, high - low <= 11 {
            inputs = (low...high).map { .integer($0) }
        }
        guard inputs.count >= 3, inputs.count <= 12 else { return nil }
        func outputs(_ expr: Expr) -> [Expr]? {
            let values = inputs.map { Simplify.run(expr.substituting(x, with: $0)) }
            return values.allSatisfy({ $0.number != nil }) ? values : nil
        }
        // The values already in the table have to be among the ones this gives. A power
        // read as a product, 2x for 2^x, doesn't give them; the power does.
        let given = groups("\\b\(y) ((?:\(number) ?)+)", in: rest).map { all(number, in: $0[1]).compactMap { value($0).flatMap(amount) } } ?? []
        func fits(_ values: [Expr]) -> Bool { given.allSatisfy { size in values.contains { abs(($0.number?.double ?? .nan) - size) < 1e-9 } } }
        var values = outputs(expr)
        if values.map(fits) != true, let power = groups(#"^(\d+) ?\^? ?([a-z])$"#, in: formula), let base = value(power[1]) {
            let raised = Expr.power(base, .symbol(power[2]))
            if let other = outputs(raised), fits(other) { expr = raised; values = other }
        }
        // x2 + 2x is x² + 2x with its power dropped onto the line, if that's what gives the values in the table.
        if values.map(fits) != true, !given.isEmpty, let lifted = Parser.expression(raised(formula)), lifted.symbols == [x], let other = outputs(lifted), fits(other) { expr = lifted; values = other }
        guard let values, fits(values) else { return nil }
        let lines = zip(inputs, values).map { MathLine(.symbol("\(x) = \(Format.text($0)):  \(y)"), $1) }
        return told("\(y) = \(Format.text(expr))", [MathLine(.symbol(y), .symbol(values.map(Format.text).joined(separator: ", ")))],
                    [Step("Put each value of \(x) in", "Work out \(y) = \(Format.text(expr)) for each \(x) in the table.", lines)])
    }

    // MARK: Which of these values

    /// "y = 1/x. Which of these values of x gives the greatest value of y? 0.1 0.5 2 10"
    private static func choice(_ text: String, _ display: String) -> Problem? {
        // "y =" with nothing after it on its line is the front of a fraction written over two
        // lines, and what's above and below the bar isn't known.
        guard display.range(of: #"(?m)=[ \t]*$"#, options: .regularExpression) == nil else { return nil }
        guard let asked = groups(#"which of these(?: values)? (?:of )?([a-z]) gives the (greatest|largest|biggest|highest|smallest|least|lowest) value of ([a-z])"#, in: text),
              let whole = text.range(of: asked[0], options: .caseInsensitive) else { return nil }
        let x = asked[1].lowercased(), y = asked[3].lowercased()
        let wantsMost = ["greatest", "largest", "biggest", "highest"].contains(asked[2].lowercased())
        // The formula: y = … somewhere before the question.
        let before = String(text[..<whole.lowerBound])
        guard let formula = groups("\\b\(y) ?= ?([^.?!]*?[\(x)\\d)][^.?!]*?)(?:\\.? *$|\\.? +[A-Z])", in: before + " A")?[1],
              let expr = Parser.expression(formula.trimmingCharacters(in: .whitespaces)), expr.symbols == [x] else { return nil }
        // The values to choose from: the numbers after the question.
        let after = String(text[whole.upperBound...])
        let choices = all(number, in: after).compactMap { text -> (Expr, Double)? in
            guard let expr = value(text), let size = amount(expr) else { return nil }
            return (expr, size)
        }
        guard choices.count >= 2, choices.count <= 8 else { return nil }
        var lines: [MathLine] = []
        var results: [(choice: Expr, size: Double)] = []
        for (choice, _) in choices {
            let put = Simplify.run(expr.substituting(x, with: choice))
            guard let size = put.number?.double, size.isFinite else { continue }
            results.append((choice, size))
            lines.append(MathLine(.symbol("\(x) = \(Format.text(choice)):  \(y)"), put))
        }
        guard results.count == choices.count, let best = (wantsMost ? results.max { $0.size < $1.size } : results.min { $0.size < $1.size }) else { return nil }
        var problem = Problem(kind: .solve([Equation(left: .symbol(x), right: best.choice)], unknowns: [x]), text: "", usesDecimals: false)
        problem.lead = [Step("Try each value", "Put each value of \(x) into \(y) = \(Format.text(expr)).", lines),
                        Step("Pick the \(wantsMost ? "greatest" : "smallest")", "The \(wantsMost ? "greatest" : "smallest") value of \(y) is \(Format.text(Worded.whole(best.size))), which comes from \(x) = \(Format.text(best.choice)).")]
        return problem
    }

    // MARK: Ratios

    /// "Oscar and Nikita share some money in the ratio 8 : 5. Oscar has £27 more than
    /// Nikita. How much do they have altogether?" One thing is given (the total, one
    /// share, or how much more one has), which is so many parts; the rest follows.
    private static func ratio(_ text: String, _ question: Question) -> Problem? {
        guard let found = groups(#"ratio (\d+(?:\.\d+)?) ?: ?(\d+(?:\.\d+)?)(?: ?: ?(\d+(?:\.\d+)?))?"#, in: text) else { return nil }
        let parts = [found[1], found[2], found[3]].compactMap { Double($0) }
        guard parts.count >= 2, parts.allSatisfy({ $0 > 0 }) else { return nil }
        // Who the parts belong to, in the order they're named.
        var names: [String] = []
        if let people = groups(#"\b([A-Z][a-z]+)(?:, ([A-Z][a-z]+))? and ([A-Z][a-z]+)\b[^.?]*?ratio"#, in: text) {
            names = [people[1], people[2], people[3]].filter { !$0.isEmpty }
        }
        if names.count != parts.count { names = [] }
        func part(_ name: String) -> Int? { names.firstIndex { $0.lowercased() == name.lowercased() } }
        let sum = parts.reduce(0, +)
        // What's given, as an amount and how many parts it is.
        var given: (amount: Double, parts: Double, words: String)?
        if let more = groups("([A-Z][a-z]+) (?:has|gets|receives|got|is given) (\(number)) more than ([A-Z][a-z]+)", in: text),
           let a = part(more[1]), let b = part(more[3]), let amount = Double(more[2]), parts[a] > parts[b] {
            given = (amount, parts[a] - parts[b], "\(more[1]) has \(Format.text(whole(parts[a] - parts[b]))) more parts than \(more[3])")
        } else if let one = groups("([A-Z][a-z]+) (?:has|gets|receives|got|is given) (\(number))\\b(?! more)", in: text), let a = part(one[1]), let amount = Double(one[2]) {
            given = (amount, parts[a], "\(one[1]) has \(Format.text(whole(parts[a]))) parts")
        } else if let total = groups("(?:share|shares|shared|divide|divides|divided|split|splits) (\(number))", in: text), let amount = Double(total[1]) {
            given = (amount, sum, "There are \(Format.text(whole(sum))) parts altogether")
        }
        guard let given, given.parts > 0 else { return nil }
        // What's asked for.
        var wanted: (parts: Double, words: String)?
        if text.range(of: #"altogether|in total|total amount|how much money (?:is|was) there"#, options: [.regularExpression, .caseInsensitive]) != nil {
            wanted = (sum, "all \(Format.text(whole(sum))) parts")
        } else if let who = groups(#"how (?:much|many)[^.?]*? (?:does|did|will) ([A-Z][a-z]+) (?:get|have|receive)"#, in: text), let a = part(who[1]) {
            wanted = (parts[a], "\(who[1])'s \(Format.text(whole(parts[a]))) parts")
        }
        let one = Expr.multiply([whole(given.amount), .power(whole(given.parts), .minusOne)])
        let onePart = Step("Find one part", "\(given.words), and that's \(Format.text(whole(given.amount))).", [MathLine(.symbol("1 part"), one, plain(given.amount / given.parts))])
        if wanted == nil, given.parts == sum {
            let isMoney = has("(?:share|shares|shared|divide|divides|divided|split|splits) £", question.money)
            func show(_ value: Double) -> String { isMoney ? pounds(value) : written(value) }
            let shares = parts.map { given.amount / sum * $0 }
            // "Work out the larger share."
            if let which = groups(#"\b(larger|largest|bigger|biggest|greater|greatest|smaller|smallest|lesser|least) (?:share|amount|part)\b"#, in: text)?[1].lowercased(), Set(parts).count == parts.count {
                let most = !["smaller", "smallest", "lesser", "least"].contains(which)
                let size = most ? parts.max()! : parts.min()!
                return made(.multiply([one, whole(size)]), decimals: true, [onePart, Step("Multiply up", "The \(most ? "larger" : "smaller") share is \(written(size)) parts.")])
            }
            // "Share £180 in the ratio 1 : 9", with nothing else asked: every share.
            if has(#"^(?:share|divide|split)\b"#, text), !has(#"\bhow (?:much|many)\b|\bwork out\b|\bfind\b|\bwhat\b"#, text) {
                let lines = zip(parts, shares).map { MathLine(.symbol("\(written($0)) part\($0 == 1 ? "" : "s")"), plain($1)) }
                return told("\(written(given.amount)) in the ratio \(parts.map(written).joined(separator: " : "))",
                            [MathLine(.symbol(shares.map(show).joined(separator: shares.count == 2 ? " and " : ", ")))],
                            [onePart, Step("Multiply up", "Each share is its number of parts.", lines)])
            }
        }
        // "Ed gives Fay some of his money. Fay now has the same amount as Ed. How much does Ed give Fay?"
        if wanted == nil, let gift = groups(#"([A-Z][a-z]+) gives ([A-Z][a-z]+) some\b[^?]*?\bnow (?:has|have) the same\b[^?]*?how much does ([A-Z][a-z]+) give ([A-Z][a-z]+)"#, in: text),
           gift[1].lowercased() == gift[3].lowercased(), gift[2].lowercased() == gift[4].lowercased(), let from = part(gift[1]), let to = part(gift[2]), parts[from] > parts[to], parts.count == 2 {
            let gap = whole(parts[from] - parts[to])
            return made(.multiply([one, gap, .power(.two, .minusOne)]), decimals: true,
                        [onePart, Step("Find how much more \(gift[1]) has", "\(gift[1]) has \(Format.text(gap)) more parts than \(gift[2]).", [MathLine(.multiply([one, gap]), Simplify.run(.multiply([one, gap])))]),
                         Step("Give half of it", "Giving half of the difference leaves them level.")])
        }
        guard let wanted else { return nil }
        return made(.multiply([one, whole(wanted.parts)]), decimals: true, [onePart, Step("Multiply up", "The answer is \(wanted.words).")])
    }

    // MARK: A list of numbers

    /// The numbers of the list a question is about: the only run of numbers on lines of their
    /// own, or the run that follows words that introduce a list.
    private static func listed(_ text: String, _ question: Question, intro: String = #"list of|here (?:are|is)|the following|numbers are|these numbers|ages are|marks are|scores are|times are"#) -> [Double]? {
        var tokens: [String]
        if question.lists.count == 1 {
            tokens = question.lists[0]
        } else if question.lists.isEmpty, let start = text.range(of: intro, options: [.regularExpression, .caseInsensitive]),
                  let run = all("(?:\(number)[ ,]+){3,}\(number)", in: String(text[start.upperBound...])).max(by: { $0.count < $1.count }) {
            tokens = all(number, in: run)
        } else {
            return nil
        }
        // 21 500 23 750 might be two numbers or four: not known.
        let lengths = tokens.map { $0.filter(\.isNumber).count }
        if tokens.count >= 4, tokens.count % 2 == 0, stride(from: 0, to: tokens.count, by: 2).allSatisfy({ lengths[$0] <= 2 && !tokens[$0].contains(".") && lengths[$0 + 1] == 3 && !tokens[$0 + 1].contains(".") }) { return nil }
        let sizes = tokens.compactMap { value($0).flatMap(amount) }
        return sizes.count == tokens.count && sizes.count >= 3 && sizes.count <= 40 ? sizes : nil
    }

    /// "Here is a list of numbers. 5 6 1 3 5 … Work out the median."
    private static func statistic(_ text: String, _ question: Question) -> Problem? {
        guard !has(#"frequency|\btable\b|chart|diagram|graph|\bplot\b|tally|pictogram|grouped|class interval"#, text) else { return nil }
        // "The range of a set of numbers is 15. The smallest number is -2. Work out the largest number."
        let end = #"(?!\d|\.\d)(?: ?[a-z%°]+)?(?:\.|,|(?-i: [A-Z])|$)"#
        if let spread = groups("\\brange (?:of [a-z ]+? )?(?:is|was) (\(number))\(end)", in: text),
           let one = groups("\\b(smallest|lowest|least|largest|highest|greatest|biggest) [a-z]+ (?:is|was) (\(number))\(end)", in: text),
           let asked = groups(#"(?:work out|find|what (?:is|was)|write down|calculate) the (smallest|lowest|least|largest|highest|greatest|biggest)\b"#, in: text),
           let range = value(spread[1]), let known = value(one[2]) {
            let knownIsSmall = ["smallest", "lowest", "least"].contains(one[1].lowercased()), wantsSmall = ["smallest", "lowest", "least"].contains(asked[1].lowercased())
            guard knownIsSmall != wantsSmall else { return nil }
            return made(wantsSmall ? known - range : known + range, decimals: true,
                        [Step("Use what the range is", "The range is the largest take away the smallest, so the \(wantsSmall ? "smallest is the largest take away" : "largest is the smallest add") the range.")])
        }
        // "Four numbers have a mean of 10. Three of the numbers are 5 8 9. Work out the other number."
        if let all = groups("\\b(\\d+|[a-z]+) numbers have a mean of (\(number))", in: text), let total = count(all[1]),
           let some = groups("\\b(\\d+|[a-z]+) of the numbers are ((?:\(number)(?:,| and| )+)+\(number))", in: text), let known = count(some[1]), known == total - 1,
           has(#"(?:work out|find|what is|calculate) the (?:other|missing|last|fourth|fifth|sixth) number"#, text), let mean = value(all[2]) {
            let sizes = Worded.all(number, in: some[2]).compactMap { value($0).flatMap(amount) }
            guard sizes.count == known else { return nil }
            return missing(mean: mean, total: total, sizes: sizes)
        }
        // "For all five days, the mean attendance is 90", with four of them listed.
        if let whole = groups("\\bfor all (\\d+|[a-z]+) [a-z]+,? the mean [a-z ]*?(?:is|was) (\(number))", in: text) ?? groups("\\bmean [a-z ]*?(?:for|of) all (\\d+|[a-z]+) [a-z]+ (?:is|was) (\(number))", in: text),
           let total = count(whole[1]), let mean = value(whole[2]), question.lists.count == 1, has(#"\b(?:work out|find|calculate|what (?:is|was))\b"#, text),
           let sizes = listed(text, question), sizes.count == total - 1 {
            return missing(mean: mean, total: total, sizes: sizes)
        }
        // What's asked for has to be the mean (or median, mode, range) itself, of a list that's all there.
        guard let asked = groups(#"(?:work out|find|calculate|write down|what is|circle) the (inter-?quartile range|lower quartile|upper quartile|median|mean|mode|modal (?:value|number)|range)\b(?! of (?:each|the masses|[a-z]+'s))"#, in: text)?[1].lowercased(),
              !has(#"\b(?:is|are) now\b|\bextra\b|\banother\b|\bremoved\b|\bis added\b|\bjoins\b|\bleaves\b|\breplaced\b|\bmissing\b|\bnew\b"#, text),
              let sizes = listed(text, question) else { return nil }
        let sorted = sizes.sorted()
        // (Numbers evenly spaced along a scale, 0 10 20 … 150, are an axis, not the data. And
        // what a box plot, histogram or chart shows isn't in the words.)
        let gaps = zip(sorted.dropFirst(), sorted).map { $0 - $1 }
        if sorted.count >= 6, let step = gaps.first, step > 0, gaps.allSatisfy({ abs($0 - step) < 1e-9 }) { return nil }
        if has(#"\bbox plot\b|\bhistogram\b|\bcumulative frequency\b|\bscatter\b|\bbar chart\b|\bpie chart\b|\bfrequency polygon\b"#, text) { return nil }
        let listed = sorted.map(written).joined(separator: ", ")
        switch asked {
        case "mean":
            let sum = Expr.add(sizes.map(plain))
            return made(.multiply([sum, .power(.integer(sizes.count), .minusOne)]), decimals: true,
                        [Step("Add them up and share out", "The mean is the total divided by how many numbers there are: \(sizes.count) here.")])
        case "median":
            let middle = sorted.count / 2
            let lead = Step("Put them in order", "The median is the middle one. With an even number of them, it's halfway between the middle two.", [MathLine(.symbol(listed))])
            return sorted.count % 2 == 1 ? made(plain(sorted[middle]), decimals: true, [lead])
                : made(.multiply([.add([plain(sorted[middle - 1]), plain(sorted[middle])]), .power(.two, .minusOne)]), decimals: true, [lead])
        case "mode", "modal value", "modal number":
            let counts = Dictionary(grouping: sorted, by: { $0 }).mapValues(\.count)
            guard let most = counts.values.max(), most >= 2, counts.filter({ $0.value == most }).count == 1, let mode = counts.first(where: { $0.value == most })?.key else { return nil }
            return made(plain(mode), decimals: true, [Step("Count each number", "The mode is the one that comes up most: \(written(mode)) is there \(most) times.", [MathLine(.symbol(listed))])])
        case "range":
            return made(.add([plain(sorted[sorted.count - 1]), .multiply([.minusOne, plain(sorted[0])])]), decimals: true,
                        [Step("Find the biggest and the smallest", "The range is the biggest take away the smallest.", [MathLine(.symbol(listed))])])
        default:
            // Quartiles, where they fall on numbers of the list: 7, 11, 15… numbers.
            guard (sorted.count + 1) % 4 == 0 else { return nil }
            let quarter = (sorted.count + 1) / 4
            let low = sorted[quarter - 1], high = sorted[3 * quarter - 1]
            let lead = Step("Put them in order", "With \(sorted.count) numbers, the lower quartile is number \(quarter) and the upper quartile is number \(3 * quarter).",
                            [MathLine(.symbol(listed)), MathLine(.symbol("lower quartile"), plain(low)), MathLine(.symbol("upper quartile"), plain(high))])
            if asked == "lower quartile" { return made(plain(low), decimals: true, [lead]) }
            if asked == "upper quartile" { return made(plain(high), decimals: true, [lead]) }
            return made(.add([plain(high), .multiply([.minusOne, plain(low)])]), decimals: true,
                        [lead, Step("Take the lower from the upper", "The inter-quartile range is the upper quartile take away the lower quartile.")])
        }
    }

    /// The number that's left out, from the mean of all of them.
    private static func missing(mean: Expr, total: Int, sizes: [Double]) -> Problem {
        let all = Expr.multiply([mean, .integer(total)])
        return made(.add([all, .multiply([.minusOne, .add(sizes.map(plain))])]), decimals: true,
                    [Step("Find the total", "The mean times how many there are is the total of all \(total).", [MathLine(all, Simplify.run(all))]),
                     Step("Take away the ones that are known", "What's left is the missing one.")])
    }

    // MARK: Fractions, decimals and percentages

    /// "Write 0.85 as a fraction in its simplest form", "Write 3/8 as a decimal", "Write 0.35 as a percentage".
    private static func conversion(_ text: String, _ question: Question) -> Problem? {
        // "Work out 80p as a fraction of £1", "Write 2 weeks as a fraction of 8 days"
        if let found = groups("(£)?(\(number)) ?(\(unitWord))?\\b as a fraction of (£)?(\(number)) ?(\(unitWord))?\\b", in: question.money),
           var top = exact(found[2]), var bottom = exact(found[5]), amount(bottom) ?? 0 > 0 {
            let first = found[1].isEmpty ? found[3] : "£", second = found[4].isEmpty ? found[6] : "£"
            var lead = [Step("Write one over the other", "Then cancel down.")]
            if single(first) != single(second) {
                // Different units: both in the smaller one.
                guard let a = unit(first), let b = unit(second), a.kind == b.kind else { return nil }
                let small = min(a.size, b.size)
                top = top * plain(a.size / small)
                bottom = bottom * plain(b.size / small)
                lead.insert(Step("Use the same unit for both", "", [MathLine(.symbol("\(found[1])\(found[2]) \(found[3])"), Simplify.run(top)), MathLine(.symbol("\(found[4])\(found[5]) \(found[6])"), Simplify.run(bottom))]), at: 0)
            }
            return made(top / bottom, decimals: false, lead)
        }
        // "the floor area of the living room is 26 m². … of the kitchen is 16.4 m². Express the area of the living room as a fraction of the area of the kitchen."
        if let asked = groups(#"(?:express|write|give) the ([a-z ]+?) as a fraction of the ([a-z ]+?)(?:\.|$| give| circle)"#, in: text), let whole = text.range(of: asked[0], options: .caseInsensitive) {
            let before = String(text[..<whole.lowerBound])
            /// The amount the words end with: "area of the living room" is found by "living room is 26".
            func stated(_ phrase: String) -> (size: Expr, unit: String)? {
                let words = phrase.split(separator: " ").map(String.init)
                for length in stride(from: min(3, words.count), through: 1, by: -1) {
                    let key = NSRegularExpression.escapedPattern(for: words.suffix(length).joined(separator: " "))
                    let found = every("\\b\(key) (?:is|=|was) (\\d+(?:\\.\\d+)?) ?([a-z]+(?:\\^?\\d)?)?", in: before)
                    if found.count == 1, let size = exact(found[0][1]) { return (size, found[0][2].lowercased()) }
                    if found.count > 1 { return nil }
                }
                return nil
            }
            guard let top = stated(asked[1]), let bottom = stated(asked[2]), top.unit == bottom.unit, amount(bottom.size) ?? 0 > 0 else { return nil }
            return made(top.size / bottom.size, decimals: false, [Step("Write one over the other", "\(Format.text(top.size)) over \(Format.text(bottom.size)), both in the same unit."), Step("Get rid of the decimal and cancel down", "Multiply top and bottom by 10 until both are whole numbers, then divide both by what goes into both.")])
        }
        guard let found = groups("(?:write|express|convert|change) (\(number))(%)? (?:as|to|into) an? (fraction|decimal|percentage)(?! of)", in: text),
              let given = found[3].lowercased() == "fraction" ? exact(found[1]) : value(found[1]) else { return nil }
        let isPercent = !found[2].isEmpty
        let start: Expr = isPercent ? .multiply([given, .power(.integer(100), .minusOne)]) : given
        let hundred = Step("A percentage is out of 100", "", [MathLine(.symbol(found[1] + "%"), .multiply([given, .power(.integer(100), .minusOne)]))])
        switch found[3].lowercased() {
        case "fraction":
            return made(start, decimals: false, isPercent ? [hundred] : [Step("Write it over a power of ten", "Each decimal place is a tenth, a hundredth, a thousandth. Then cancel down.")])
        case "decimal":
            return made(start, decimals: true, isPercent ? [hundred] : [Step("Divide the top by the bottom", "A fraction is a division.")])
        default:
            guard !isPercent else { return nil }
            return made(.multiply([given, .integer(100)]), decimals: true, [Step("Multiply by 100", "A percentage is how many hundredths.")])
        }
    }

    // MARK: Numbers picked out of a list

    private static func isSquare(_ n: Int) -> Bool {
        guard n >= 0 else { return false }
        let root = Int(Double(n).squareRoot().rounded())
        return root * root == n
    }

    private static func isCube(_ n: Int) -> Bool {
        let root = Int(cbrt(Double(n)).rounded())
        return root * root * root == n
    }

    private static func fits(_ kind: String, _ n: Int, _ of: Int?) -> Bool {
        switch kind {
        case "multiple": if let of, of != 0 { return n % of == 0 && n != 0 } else { return false }
        case "factor": if let of { return n > 0 && of % n == 0 } else { return false }
        case "prime": return isPrime(n)
        case "square": return n > 0 && isSquare(n)
        case "cube": return n > 0 && isCube(n)
        case "triangular": return n > 0 && isSquare(8 * n + 1)
        case "odd": return n % 2 != 0
        case "even": return n % 2 == 0
        default: return false
        }
    }

    /// "Circle the cube number. 9 10000 333 729", "Write down the number from the card that is a factor of 40"
    private static func picked(_ text: String, _ question: Question) -> Problem? {
        // "Write down all the prime numbers between 40 and 50"
        if let found = groups(#"(?:write down|list|find|work out) (?:all )?(?:of )?the (prime|square|cube|triangular) numbers between (\d+) and (\d+)"#, in: text),
           let low = Int(found[2]), let high = Int(found[3]), low < high, high - low <= 200 {
            let kind = found[1].lowercased()
            // Whether "between" takes in the ends only matters if an end is one of them.
            guard !fits(kind, low, nil), !fits(kind, high, nil) else { return nil }
            let chosen = (low...high).filter { fits(kind, $0, nil) }
            guard !chosen.isEmpty else { return nil }
            return told("\(kind) numbers between \(low) and \(high)", [MathLine(.symbol(chosen.map(String.init).joined(separator: ", ")))],
                        [Step("Check each number from \(low) to \(high)", kind == "prime" ? "A prime number has no factors but 1 and itself." : "Keep the ones that are \(kind) numbers.")])
        }
        // "Circle the largest number." with the four to choose from.
        if let found = groups(#"circle the (largest|greatest|biggest|highest|smallest|least|lowest) (?:number|value|decimal)\.? ((?:\#(number) ?){2,})$"#, in: text), !text.contains("%") {
            let offered = all(number, in: found[2])
            let sizes = offered.compactMap { value($0).flatMap(amount) }
            guard offered.count == 4, sizes.count == 4, Set(sizes).count == 4 else { return nil }
            let most = ["largest", "greatest", "biggest", "highest"].contains(found[1].lowercased())
            let best = most ? sizes.max()! : sizes.min()!
            guard let index = sizes.firstIndex(of: best), let chosen = value(offered[index]) else { return nil }
            return made(chosen, decimals: offered[index].contains("."), [Step("Line them up", "Write them with the same number of decimal places, then compare digit by digit from the left.", [MathLine(.symbol(sizes.sorted().map(written).joined(separator: " < ")))])])
        }
        let kinds = #"(?:(multiple|factor) of (\d+)|(prime|square|cube|triangular|odd|even) number)"#
        guard let asked = groups(#"(circle|write down|find|choose) (?:the|a|an) (prime|square|cube|triangular) number\b(?! of| that| which| less| more| between| from| in)"#, in: text).map({ [$0[0], $0[1], "", "", $0[2]] })
                ?? groups(#"(circle|write down|find|choose) (?:the|a|an) number (?:from the (?:list|card|box)(?: above)? )?(?:that|which) is (?:a |an )?\#(kinds)"#, in: text)
                ?? groups(#"(which) (?:of these numbers|number(?: in the list| from the list| on the card)?) is (?:a |an )?\#(kinds)"#, in: text),
              let whole = text.range(of: asked[0], options: .caseInsensitive) else { return nil }
        let kind = (asked[2].isEmpty ? asked[4] : asked[2]).lowercased()
        let of = Int(asked[3])
        // The numbers to pick from: the four after "Circle…", or the list the question is about.
        var offered: [Double]
        if asked[1].lowercased() == "circle" {
            let after = all(number, in: String(text[whole.upperBound...]))
            offered = after.compactMap { value($0).flatMap(amount) }
            guard after.count == 4, offered.count == 4 else { return nil }
        } else {
            guard let list = listed(text, question, intro: #"list of|here (?:are|is)|the following|numbers are|these numbers|\bcard\b"#) else { return nil }
            offered = list
        }
        let chosen = offered.filter { abs($0 - $0.rounded()) < 1e-9 && abs($0) < 1e9 && fits(kind, Int($0.rounded()), of) }
        guard Set(chosen).count == 1, let answer = chosen.first else { return nil }
        let what = of.map { "a \(kind) of \($0)" } ?? "a \(kind) number"
        let why: String
        switch kind {
        case "multiple": why = "A multiple of \(of ?? 0) is in the \(of ?? 0) times table."
        case "factor": why = "A factor of \(of ?? 0) divides into it with nothing left over."
        case "prime": why = "A prime number has no factors but 1 and itself."
        case "square": why = "A square number is a whole number times itself: \(written(answer)) = \(Int(answer.squareRoot().rounded())) × \(Int(answer.squareRoot().rounded()))."
        case "cube": why = "A cube number is a whole number times itself, times itself again: \(written(answer)) = \(Int(cbrt(answer).rounded()))³."
        case "triangular": why = "The triangular numbers are 1, 3, 6, 10, 15, 21, 28, 36, 45… adding one more each time."
        default: why = ""
        }
        return made(plain(answer), decimals: true, [Step("Check each number", "\(why) Of \(offered.map(written).joined(separator: ", ")), only \(written(answer)) is \(what).")])
    }

    // MARK: Sums asked for in words

    private static func sums(_ text: String) -> Problem? {
        // "Circle the answer to 150 ÷ 5". A minus sign with a space only before it starts the next number.
        if let found = groups(#"the answer to (-?\d+(?:\.\d+)?(?:(?: [-+] | ?[×÷*/] ?)\(?-?\d+(?:\.\d+)?\)?)+)"#, in: text), let expr = sum(found[1]), expr.symbols.isEmpty {
            return made(expr, decimals: found[1].contains("."), [])
        }
        // "A number is divided by 8. The answer is 43 remainder 5. Work out the number."
        if let found = groups(#"number is divided by (\d+)\.? the answer is (\d+) remainder (\d+)"#, in: text), has(#"(?:work out|find|what is|what was) the number"#, text),
           let by = Int(found[1]), let times = Int(found[2]), let left = Int(found[3]), left < by {
            return made(.add([.multiply([.integer(by), .integer(times)]), .integer(left)]), decimals: false,
                        [Step("Undo the division", "\(times) lots of \(by), and the \(left) left over.")])
        }
        // "Work out the multiple of 60 that is closest to 400"
        if let found = groups(#"(?:work out|find|write down|circle) the multiple of (\d+) that is (?:closest|nearest) to (\d+)(?!\d|\.\d)"#, in: text), let of = Int(found[1]), let target = Int(found[2]), of > 0 {
            let below = target / of * of, above = below + of
            guard target - below != above - target else { return nil }
            let nearest = target - below < above - target ? below : above
            return made(.integer(nearest), decimals: false, [Step("Find the multiples either side", "\(below) and \(above) are the multiples of \(of) either side of \(target), and \(nearest) is nearer.")])
        }
        // "Circle the reciprocal of 8⁵": the same number to the opposite power.
        if let found = groups(#"(?:work out|write down|circle|find|what is)(?: the value of)? the reciprocal of (\d+)\^\(?(-?\d+)\)?(?!\d|\.\d|/| ?[×÷*/+^]| ?x ?[\d(])"#, in: text), let base = Int(found[1]), let power = Int(found[2]), base > 1, power != 0 {
            return told("reciprocal of \(base)\(raisedDigits(power))", [MathLine(.symbol("\(base)\(raisedDigits(-power))"))],
                        [Step("Turn it over", "The reciprocal is 1 divided by it, and 1 ÷ \(base)\(raisedDigits(power)) is \(base) to the power \(-power): a minus sign on a power means one over.")])
        }
        // "Circle the reciprocal of 4"
        if let found = groups(#"(?:work out|write down|circle|find|what is)(?: the value of)? the reciprocal of (\#(number))(?!\d|\^|\.\d| ?[×÷*/+^]| - \d| ?x ?[\d(])"#, in: text), let n = exact(found[1]), let size = amount(n), size != 0 {
            return made(.power(n, .minusOne), decimals: false, [Step("Turn it over", "The reciprocal of a number is 1 divided by it.")])
        }
        // "Circle the value of the digit 7 in 9.17"
        if let found = groups(#"value of the (?:digit )?(\d)(?: digit)? in (?:the number )?(\d+(?:\.\d+)?)(?![\d.]*\d| ?[×÷*/+^-])"#, in: text), found[1] != "0",
           found[2].filter({ String($0) == found[1] }).count == 1, let digit = Double(found[1]) {
            let parts = found[2].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            var power: Int
            if let place = parts[0].firstIndex(of: Character(found[1])) {
                power = parts[0].distance(from: place, to: parts[0].endIndex) - 1
            } else if parts.count == 2, let place = parts[1].firstIndex(of: Character(found[1])) {
                power = -(parts[1].distance(from: parts[1].startIndex, to: place) + 1)
            } else {
                return nil
            }
            let names = [-4: "ten-thousandths", -3: "thousandths", -2: "hundredths", -1: "tenths", 0: "units", 1: "tens", 2: "hundreds", 3: "thousands", 4: "ten thousands", 5: "hundred thousands", 6: "millions"]
            guard let name = names[power] else { return nil }
            return made(plain(digit * pow(10, Double(power))), decimals: true, [Step("Find its place", "The \(found[1]) in \(found[2]) is in the \(name) place, so it's \(found[1]) \(name).")])
        }
        // "Circle the fraction that is equal to 0.12"
        if let found = groups(#"fraction (?:that is |which is )?(?:equal|equivalent) to (\d+\.\d+)( ?%)?(?!\d|\.\d)"#, in: text), let n = exact(found[1]) {
            let isPercent = !found[2].isEmpty
            return made(isPercent ? n / .integer(100) : n, decimals: false,
                        [Step(isPercent ? "A percentage is out of 100" : "Write it over a power of ten", isPercent ? "Then get rid of the decimal on top, and cancel down." : "Each decimal place is a tenth, a hundredth, a thousandth. Then cancel down.")])
        }
        // "Find the exact value of tan 30° × sin 60°" (the × is often read as the letter x)
        let trig = #"(?:sin|cos|tan) ?\(?\d+(?:\.\d+)? ?°\)?"#
        if let found = groups("(?:value of|work out|write down) (\(trig)(?: ?[×x*÷/+] ?\(trig)| - \(trig))+)(?! ?[×÷*/+^-]| ?x\\b)", in: text) {
            var written = found[1].lowercased().replacingOccurrences(of: #"(sin|cos|tan) ?\(?(\d+(?:\.\d+)?) ?°\)?"#, with: "$1($2)", options: .regularExpression)
            for (from, to) in [(" ", ""), ("x", "*"), ("×", "*"), ("÷", "/")] { written = written.replacingOccurrences(of: from, with: to) }
            guard let expr = Parser.expression(written) else { return nil }
            var problem = made(expr, decimals: false, [])
            problem.angles = .degrees
            return problem
        }
        // "Circle the value of sin 90°" (and nothing more after it that belongs to the sum)
        if let found = groups(#"(?:value of|work out|write down) (sin|cos|tan) ?\(?(\d+(?:\.\d+)?) ?°\)?(?! ?[×÷*/+^-]| ?x\b)"#, in: text), let expr = Parser.expression("\(found[1].lowercased())(\(found[2]))") {
            var problem = made(expr, decimals: false, [])
            problem.angles = .degrees
            return problem
        }
        return nil
    }

    // MARK: Standard form and prime factors

    private static func standardForm(_ text: String) -> Problem? {
        // "Write 3.2 × 10^4 as an ordinary number"
        if let found = groups(#"(?:write|express|give) (\d+(?:\.\d+)?) ?[×x*] ?10\^?\(?(-?\d+)\)? as an ordinary number"#, in: text), let front = Double(found[1]), let power = Int(found[2]), abs(power) <= 12 {
            return made(plain(front * pow(10, Double(power))), decimals: true,
                        [Step("Move the point", "Multiplying by 10 to the power \(power) moves the digits \(abs(power)) place\(abs(power) == 1 ? "" : "s") to the \(power < 0 ? "right, making the number smaller" : "left, making the number bigger").")])
        }
        guard has("standard form", text) else { return nil }
        // "Write 0.00097 in standard form"
        if let found = groups(#"(?:write|express|give) (\d+(?:\.\d+)?) in standard form"#, in: text), let size = Double(found[1]), size > 0 {
            return told(found[1], [MathLine(.symbol(standard(size)))], [Step("Write it in standard form", standardWords)])
        }
        // "Work out 80000000 ÷ 200. Give your answer in standard form."
        if let found = groups(#"(?:work out|calculate|find) (?:the value of )?(.+?)\.? give your answer in standard form"#, in: text) {
            // A power of ten whose power has dropped onto the line: × 105 is × 10^5.
            var written = found[1].replacingOccurrences(of: #"([×x*] ?10)(-?\d{1,2})(?!\d|\.\d)"#, with: "$1^($2)", options: .regularExpression)
            written = written.replacingOccurrences(of: #"\)(-?\d)$"#, with: ")^($1)", options: .regularExpression)
            guard written.range(of: #"^[-\d.,() ×x*÷/+^]+$"#, options: .regularExpression) != nil, let expr = sum(written.replacingOccurrences(of: "x", with: "×")), expr.symbols.isEmpty,
                  let size = amount(expr), size > 0, size.isFinite else { return nil }
            let read = written == found[1] ? "" : "Read as \(written.replacingOccurrences(of: "^(", with: "^").replacingOccurrences(of: ")", with: "")): the power of ten is written small and raised. "
            return told(found[1], [MathLine(.symbol(standard(size)))], [Step("Work it out", read, [MathLine(expr, plain(size))]), Step("Write it in standard form", standardWords)])
        }
        return nil
    }

    /// "Write 42 as a product of its prime factors."
    private static func primeFactors(_ text: String) -> Problem? {
        guard let found = groups(#"(?:write|express|give) (\d+) as (?:a|the) product of (?:its )?(?:prime factors|primes)|product of (?:the )?prime factors of (\d+)"#, in: text),
              let n = Int(found[1].isEmpty ? found[2] : found[1]), n >= 2, n < 1_000_000_000 else { return nil }
        let parts = primes(of: n)
        var lines: [MathLine] = []
        var rest = n
        for prime in parts {
            lines.append(MathLine(.symbol("\(rest) ÷ \(prime)"), .integer(rest / prime)))
            rest /= prime
        }
        var product = parts.map(String.init).joined(separator: " × ")
        if has("index form|using powers|using indices|index notation", text) {
            let counted = Dictionary(grouping: parts, by: { $0 }).mapValues(\.count)
            product = counted.keys.sorted().map { counted[$0]! > 1 ? "\($0)\(raisedDigits(counted[$0]!))" : "\($0)" }.joined(separator: " × ")
        }
        return told("\(n)", [MathLine(.symbol(product))],
                    [Step("Divide by the smallest prime that goes in, again and again", parts.count == 1 ? "\(n) is a prime number already." : "The primes divided by, multiplied together, make \(n).", lines)])
    }

    // MARK: Bounds of a formula

    /// "D = u²/(2a). u = 26.2 correct to 3 significant figures. a = 4.3 correct to 2 significant figures. Calculate the upper bound
    /// for the value of D."
    private static func formulaBounds(_ text: String, _ question: Question) -> Problem? {
        guard let asked = groups(#"(?:calculate|work out|find) the (upper|lower) bound (?:for|of) (?:the value of )?(?-i:([A-Za-z]))\b(?! ?=)"#, in: text),
              !has(#"\bshow that\b|\bprove\b|\bexplain\b"#, text) else { return nil }
        let target = asked[2], wantsUpper = asked[1].lowercased() == "upper"
        // Each letter's rounded value, and the least and most it can be.
        var ranges: [String: (low: Double, high: Double, said: String)] = [:]
        for found in every(#"(?<![A-Za-z])(?-i:([A-Za-z])) ?= ?(\d+(?:\.\d+)?) ?(?:\#(unitWord)\b)?,? (?:when |correct |rounded |measured |given )*to (?:the nearest (whole number|integer|ten|hundred|thousand|tenth|hundredth)|(\d) (decimal places?|significant figures?))"#, in: text) {
            guard let size = Double(found[2]), size > 0, ranges[found[1]] == nil, found[1] != target else { return nil }
            var step: Double
            if let places = Int(found[4]) {
                let decimals = found[2].contains(".") ? found[2].split(separator: ".")[1].count : 0
                if found[5].lowercased().hasPrefix("d") {
                    guard decimals <= places else { return nil }
                    step = pow(10, -Double(places))
                } else {
                    // The figures given are the ones it's correct to: 0.05 to 1, 26.2 to 3.
                    let figures = found[2].replacingOccurrences(of: ".", with: "").drop(while: { $0 == "0" }).count
                    guard places >= 1, figures <= places else { return nil }
                    step = pow(10, floor(log10(size)) - Double(places) + 1)
                }
            } else {
                guard let named = ["whole number": 1.0, "integer": 1, "ten": 10, "hundred": 100, "thousand": 1000, "tenth": 0.1, "hundredth": 0.01][found[3].lowercased()] else { return nil }
                step = named
            }
            guard abs((size / step).rounded() - size / step) < 1e-9 else { return nil }
            ranges[found[1]] = (size - step / 2, size + step / 2, found[2])
        }
        // The formula: the line that starts with the letter asked about.
        guard !ranges.isEmpty, ranges.count <= 4,
              let line = question.lines.first(where: { $0.range(of: "^(?:\(target)) ?= ?(?!\\d+(?:\\.\\d+)? ?(?:correct|to the|rounded))", options: .regularExpression) != nil }),
              let equals = line.firstIndex(of: "=") else { return nil }
        // (A letter e would be taken for the number e: it goes in under another name.)
        var written = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        if let e = ranges["e"], !has(#"sin|cos|tan|sec|det"#, written) {
            written = written.replacingOccurrences(of: "e", with: "ε")
            ranges["ε"] = e
            ranges["e"] = nil
        }
        guard let formula = sum(raised(written)), formula.symbols.subtracting(["π"]) == Set(ranges.keys) else { return nil }
        func shownName(_ name: String) -> String { name == "ε" ? "e" : name }
        // Every way of taking each letter at its least, its middle and its most: the biggest and smallest have to be at the ends.
        let names = ranges.keys.sorted()
        func worth(_ picks: [Int]) -> Double? {
            var expr = formula
            for (name, pick) in zip(names, picks) {
                let range = ranges[name]!
                expr = expr.substituting(name, with: .number(.real(pick == 0 ? range.low : (pick == 2 ? range.high : (range.low + range.high) / 2))))
            }
            return amount(expr).flatMap { $0.isFinite ? $0 : nil }
        }
        var best: (picks: [Int], size: Double)?
        var picks = [Int](repeating: 0, count: names.count)
        var done = false
        while !done {
            guard let size = worth(picks) else { return nil }
            if best == nil || (wantsUpper ? size > best!.size : size < best!.size) { best = (picks, size) }
            var place = 0
            while place < picks.count { if picks[place] < 2 { picks[place] += 1; break } else { picks[place] = 0; place += 1 } }
            done = place == picks.count
        }
        guard let best, !best.picks.contains(1) else { return nil }
        let intervals = names.map { MathLine(.symbol("\(Worded.written(ranges[$0]!.low)) ≤ \(shownName($0)) < \(Worded.written(ranges[$0]!.high))")) }
        let chosen = zip(names, best.picks).map { "\(shownName($0)) = \(Worded.written($1 == 0 ? ranges[$0]!.low : ranges[$0]!.high))" }.joined(separator: ", ")
        let how = zip(names, best.picks).map { "\(shownName($0)) at its \($1 == 0 ? "least" : "most")" }.joined(separator: " and ")
        return made(plain(best.size), decimals: true,
                    [Step("Find the least and most each number can be", "Go half of the last place it's rounded to each way.", intervals),
                     Step("Pick the ends that make \(target) \(wantsUpper ? "biggest" : "smallest")", "\(target) = \(Format.text(formula.substituting("ε", with: .symbol("e")))) is \(wantsUpper ? "biggest" : "smallest") with \(how).", [MathLine(.symbol(chosen))]),
                     Step("Put them in", "", [MathLine(.symbol(target), plain(best.size))])])
    }

    // MARK: Error intervals and bounds

    /// "The length of a fence panel is 160 cm to the nearest 10 cm. Complete the error interval."
    private static func bounds(_ text: String, _ display: String) -> Problem? {
        guard let asked = groups(#"error interval|\b(upper|lower) bound|\b(least|smallest|minimum|lowest|greatest|largest|maximum|highest) possible"#, in: text),
              !has(#"\barea\b|\btotal\b|altogether|\bsum\b|difference|\bboth\b|\bshow that\b|\bprove\b|\bexplain\b|\breasons?\b|degree of accuracy|\bby considering\b"#, text) else { return nil }
        // A bound that is itself given rounded ("The lower bound for D is 78.6003 correct to 6 significant figures") isn't a measurement,
        // and a bound asked for a letter worked out from others is `formulaBounds`'s.
        guard !has(#"\bbound\b[a-z ]*? (?-i:[A-Za-z] )?(?:is|=) ?\d"#, text), !has(#"\bbound (?:for|of) (?:the value of )?(?-i:[A-Za-z])\b(?! ?=)"#, text) else { return nil }
        // "A number, n, is rounded to 2 decimal places. The result is 4.76. Write down the error interval for n."
        if let said = groups(#"\b(?:a|the) number,? (?-i:([A-Za-z])),? is (?:rounded|given|written|correct)(?: correct)? to (\d) (decimal places?|significant figures?)\.? the result is (\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: text),
           every(#"\d ?(?:decimal places?|significant figures?)"#, in: text).count == 1 {
            if has(#"error interval"#, text) { return bounds("\(said[4]) rounded to \(said[2]) \(said[3]). error interval", "≤ \(said[1]) <") }
            // "Write down the least possible value of N." (There is no greatest: the top end isn't reached.)
            if has("(?:least|smallest|lowest|minimum) possible value of (?-i:\(said[1]))\\b", text), !has(#"greatest|largest|highest|maximum"#, text) {
                return bounds("\(said[4]) rounded to \(said[2]) \(said[3]). lower bound", "")
            }
            return nil
        }
        // "each side of a regular pentagon is 8.4 cm … the error interval for the perimeter": every side, that many times.
        var sides = 1.0
        if has("perimeter", text) {
            guard has(#"error interval for the perimeter"#, text), let shape = groups(#"each side of a regular ([a-z]+)"#, in: text), let count = polygons[shape[1].lowercased()] else { return nil }
            sides = Double(count)
        }
        let counted = #"people|students|pupils|fans|tickets|passengers|cars|visitors|spectators|books|trees"#
        let pattern = #"(\d+(?:\.\d+)?) ?(\#(unitWord))?\b( (?:\#(counted)))?,? (?:when |correct |rounded |measured |given )*to (?:the nearest (?:(\d+(?:\.\d+)?) ?)?(\#(unitWord)\b|whole number|integer|unit|ten|hundred|thousand|tenth|hundredth)?|(\d) (decimal places?|significant figures?|d\.?p\.?|s\.?f\.?))"#
        let found = every(pattern, in: text)
        guard found.count == 1, let size = Double(found[0][1]) else { return nil }
        let measure = found[0]
        // A bound asked for by name ("the upper bound of the space remaining") has to be of the thing that was measured.
        if let named = groups(#"\b(?:upper|lower) bound (?:of|for) (?:the |its |his |her )?([a-z]{3,})\b"#, in: text), !["value", "number", "measurement", "this", "that"].contains(named[1].lowercased()),
           let whole = text.range(of: measure[0], options: .caseInsensitive), !has("\\b\(named[1])\\b", String(text[..<whole.lowerBound])) { return nil }
        var step: Double
        if let places = Int(measure[6]) {
            let decimals = measure[1].contains(".") ? measure[1].split(separator: ".")[1].count : 0
            if measure[7].lowercased().hasPrefix("d") {
                guard decimals <= places else { return nil }
                step = pow(10, -Double(places))
            } else {
                guard size > 0, places >= 1 else { return nil }
                step = pow(10, floor(log10(size)) - Double(places) + 1)
            }
        } else {
            let names = ["whole number": 1.0, "integer": 1, "unit": 1, "ten": 10, "hundred": 100, "thousand": 1000, "tenth": 0.1, "hundredth": 0.01]
            let word = measure[5].lowercased()
            if let named = names[word] {
                guard measure[4].isEmpty else { return nil }
                step = named
            } else if !word.isEmpty {
                // "to the nearest 10 cm": in the unit the measurement is in.
                guard measure[2].isEmpty || single(measure[2]) == single(word) || (unit(measure[2]).map { a in unit(word).map { a.kind == $0.kind && a.size == $0.size } ?? false } ?? false) else { return nil }
                step = measure[4].isEmpty ? 1 : Double(measure[4]) ?? 0
            } else {
                guard let stated = Double(measure[4]) else { return nil }
                step = stated
            }
        }
        // What's given has to be a rounded number already.
        guard step > 0, abs((size / step).rounded() - size / step) < 1e-9 else { return nil }
        var low = size - step / 2, high = size + step / 2
        if sides > 1 {
            (low, high) = (low * sides, high * sides)
            return told("perimeter", [MathLine(.symbol("\(written(low)) ≤ perimeter < \(written(high))"))],
                        [Step("Find the least and most one side can be", "It's rounded to the nearest \(written(step)), and half of that is \(written(step / 2)): from \(written(size - step / 2)) up to \(written(size + step / 2))."),
                         Step("Multiply by the number of sides", "All \(written(sides)) sides are the same, so the perimeter is \(written(sides)) times as much at each end.")])
        }
        let lead = Step("Go half the rounding unit each way", "It's rounded to the nearest \(written(step)), and half of that is \(written(step / 2)).",
                        [MathLine(.symbol("smallest"), .symbol("\(measure[1]) − \(written(step / 2))"), plain(low)), MathLine(.symbol("largest"), .symbol("\(measure[1]) + \(written(step / 2))"), plain(high))])
        if asked[0].lowercased() == "error interval" {
            // The letter it's called: from the interval's own blank, or "the error interval for length L".
            let name = groups(#"[≤⩽] ?([A-Za-z]+) ?<"#, in: display)?[1] ?? groups(#"error interval for (?:the )?(?:[a-z]+,? )?(?-i:([A-Za-z]))(?![A-Za-z])"#, in: text)?[1] ?? "x"
            return told("\(measure[1]) to the nearest \(written(step))", [MathLine(.symbol("\(written(low)) ≤ \(name) < \(written(high))"))],
                        [lead, Step("Write the interval", "\(written(low)) is included. \(written(high)) isn't: it would round up.")])
        }
        let wantsUpper = has(#"\bupper bound|\b(?:greatest|largest|maximum|highest) possible"#, text), wantsLower = has(#"\blower bound|\b(?:least|smallest|minimum|lowest) possible"#, text)
        // Things that are counted come in whole numbers: 8400 people to the nearest 100 is at most 8449.
        let isCounted = !measure[3].isEmpty || (measure[2].isEmpty && has(#"\battendance\b|\bpopulation\b|\bnumber of (?:\#(counted))\b"#, text))
        if isCounted, wantsUpper != wantsLower, has(#"(?:least|smallest|minimum|lowest|greatest|largest|maximum|highest) possible"#, text) {
            let most = abs(high - high.rounded()) < 1e-9 ? high - 1 : high.rounded(.down), least = (low - 1e-9).rounded(.up)
            return made(plain(wantsUpper ? most : least), decimals: false,
                        [lead, Step("Keep to whole numbers", wantsUpper ? "\(written(high)) itself would round up, and there can only be a whole number: the most is \(written(most))." : "\(written(low)) rounds up to \(measure[1]), so the least is \(written(least)).")])
        }
        // Without a unit or anything counted, "the greatest possible" could be either.
        if has(#"(?:greatest|largest|maximum|highest) possible"#, text), measure[2].isEmpty, !has(#"\bupper bound"#, text) { return nil }
        if wantsUpper && wantsLower {
            return told("\(measure[1]) to the nearest \(written(step))", [MathLine(.symbol("lower bound"), plain(low)), MathLine(.symbol("upper bound"), plain(high))], [lead])
        }
        return made(plain(wantsUpper ? high : low), decimals: true, [lead])
    }

    // MARK: Sequences

    /// The next terms of a sequence that goes up or down in equal steps, by equal multiplying, or
    /// by steps that themselves change in equal steps.
    private static func following(_ sizes: [Double], count: Int, isGeometric: Bool) -> (terms: [Double], rule: String)? {
        guard sizes.count >= 3, let last = sizes.last else { return nil }
        func same(_ list: [Double]) -> Bool { list.allSatisfy { abs($0 - list[0]) < 1e-9 } }
        let steps = zip(sizes.dropFirst(), sizes).map { $0 - $1 }
        if same(steps), steps[0] != 0 {
            return ((1...count).map { last + steps[0] * Double($0) }, "Each term is the one before \(steps[0] > 0 ? "add \(written(steps[0]))" : "take away \(written(-steps[0]))").")
        }
        if sizes.allSatisfy({ $0 != 0 }) {
            let ratios = zip(sizes.dropFirst(), sizes).map { $0 / $1 }
            if same(ratios), ratios[0] != 1, sizes.count >= 4 || isGeometric {
                let ratio = ratios[0]
                let how = abs(ratio) < 1 && abs(1 / ratio - (1 / ratio).rounded()) < 1e-9 ? "divided by \(written(1 / ratio))" : "times \(written(ratio))"
                return ((1...count).map { last * pow(ratio, Double($0)) }, "Each term is the one before \(how).")
            }
        }
        if sizes.count >= 4 {
            let second = zip(steps.dropFirst(), steps).map { $0 - $1 }
            if same(second), second[0] != 0 {
                var terms: [Double] = [], step = steps[steps.count - 1], term = last
                for _ in 0..<count { step += second[0]; term += step; terms.append(term) }
                return (terms, "The steps between terms are \(steps.map(written).joined(separator: ", ")): they change by \(written(second[0])) each time, so the next step is \(written(steps[steps.count - 1] + second[0])).")
            }
        }
        return nil
    }

    private static func sequence(_ text: String, _ question: Question) -> Problem? {
        guard has(#"\bsequence\b|\bterms?\b|\bprogression\b|\btriangular numbers\b"#, text) else { return nil }
        // "A linear sequence has 2nd term = 6 and 5th term = 18. Work out the nth term."
        let given = every(#"\b(\d+)(?:st|nd|rd|th) term (?:=|is|has value) ?(\#(number))(?!\d|\.\d|[a-z(]| ?[-+*×/^])"#, in: text)
        if has(#"\b(?:linear|arithmetic) (?:sequence|progression)\b"#, text), given.count == 2, question.lists.isEmpty, !has(#"term ?[-+×*]|\bsum\b|\bproduct\b"#, text),
           let k = Int(given[0][1]), let m = Int(given[1][1]), k != m, let a = value(given[0][2]), let b = value(given[1][2]) {
            let step = Simplify.run((b - a) / .integer(m - k))
            let start = Simplify.run(a - step * .integer(k))
            let rule = Simplify.run(step * .symbol("n") + start)
            let lead = [Step("Find the step from one term to the next", "From term \(k) to term \(m) is \(abs(m - k)) step\(abs(m - k) == 1 ? "" : "s"), and the terms go from \(given[0][2]) to \(given[1][2]).",
                             [MathLine(.symbol("step"), (b - a) / .integer(m - k), step)]),
                        Step("Find the number that goes with it", "The nth term is \(Format.text(step)) lots of n, add or take away a number. Term \(k) is \(given[0][2]), and \(Format.text(step)) × \(k) is \(Format.text(Simplify.run(step * .integer(k)))).",
                             [MathLine(.symbol("nth term"), rule)])]
            if has(#"(?:work out|find|write down|write|give) (?:an expression for )?the nth term"#, text) { return told("nth term", [MathLine(rule)], lead) }
            if let which = groups(#"(?:work out|find|write down|calculate) the (\d+)(?:st|nd|rd|th) term"#, in: text), let place = Int(which[1]), place != k, place != m {
                return made(rule.substituting("n", with: .integer(place)), decimals: false, lead + [Step("Put n = \(place) in", "")])
            }
            return nil
        }
        // The terms: the one list on a line of its own, or the numbers straight after "sequence".
        var terms: [String]?
        // After "Circle…" come the answers to choose from, not the terms.
        let circled = text.range(of: #"\bcircle\b"#, options: [.regularExpression, .caseInsensitive])
        if let circled {
            terms = groups(#"(?:sequence|progression|terms|triangular numbers)(?: [a-z]+){0,4}[ .:]+((?:\#(number)[ ,]+){2,}\#(number))"#, in: String(text[..<circled.lowerBound])).map { all(number, in: $0[1]) }
        } else if question.lists.count == 1 {
            terms = question.lists[0]
        } else if question.lists.isEmpty, let run = groups(#"(?:sequence|progression|terms|triangular numbers)(?: [a-z]+){0,4}[ .:]+((?:\#(number)[ ,]+){2,}\#(number))"#, in: text)?[1] {
            terms = all(number, in: run)
        }
        guard let terms, terms.count >= 3, terms.count <= 12 else { return nil }
        let sizes = terms.compactMap { value($0).flatMap(amount) }
        guard sizes.count == terms.count else { return nil }
        // "Write down the next number in the sequence"
        if let asked = groups(#"(?:write down|work out|find|what is|circle) the next (two |three )?(?:numbers?|terms?|triangular numbers?)"#, in: text) {
            let wanted = asked[1].isEmpty ? 1 : (asked[1].lowercased().hasPrefix("two") ? 2 : 3)
            guard let (next, rule) = following(sizes, count: wanted, isGeometric: has("geometric", text)) else { return nil }
            let lead = [Step("Find the rule", rule, [MathLine(.symbol(sizes.map(written).joined(separator: ", ")))])]
            return wanted == 1 ? made(plain(next[0]), decimals: true, lead) : told("next \(wanted) terms", [MathLine(.symbol(next.map(written).joined(separator: wanted == 2 ? " and " : ", ")))], lead)
        }
        // "Work out an expression for the nth term."
        if has(#"(?:work out|find|write down|write|circle|give) (?:an |the )?(?:expression(?:,? in terms of n,?)? for )?(?:the )?nth term"#, text), !has(#"nth term (?:is|=|of [a-z ]+ is)"#, text) {
            // (−1 is read as −1 × 1: made one number, as the engine's sequences want.)
            let exact = terms.compactMap { exact($0).map(Simplify.run) }
            guard exact.count == terms.count else { return nil }
            return Problem(kind: .sequence(exact), text: "", usesDecimals: false)
        }
        return nil
    }

    // MARK: Ratios written another way

    private static func ratioForms(_ text: String) -> Problem? {
        let piece = #"(\d+(?:\.\d+)?) ?(?:(\#(unitWord))\b|([a-z])\b)?"#
        // "Write the ratio 5 : 4 in the form n : 1", "56 centimetres : 2.73 metres … in the form 1 : n"
        let shape = #"(?: is written| as a ratio| written)? in the form (n ?: ?1|1 ?: ?n)\b"#
        var match = groups("(?<![\\d.:])(?<!: )\(piece) ?: ?\(piece)\(shape)", in: text)
        // "number of beech : number of maple = 1.6 : 1 … Write number of beech : number of maple in the form 1 : n"
        if match == nil, let named = groups("\\b(?:write|express|give) ([a-z][a-z ]*?) ?: ?([a-z][a-z ]*?)\(shape)", in: text),
           let stated = groups("\\b\(NSRegularExpression.escapedPattern(for: named[1])) ?: ?\(NSRegularExpression.escapedPattern(for: named[2])) ?(?:=|is) ?(\\d+(?:\\.\\d+)?) ?: ?(\\d+(?:\\.\\d+)?)(?!\\d|\\.\\d| ?:)", in: text) {
            match = [stated[0], stated[1], "", "", stated[2], "", "", named[3]]
        }
        if let found = match, var first = value(found[1]), var second = value(found[4]) {
            let form = ["", found[7]]
            let units = [found[2], found[5]], letters = [found[3], found[6]]
            guard letters[0].lowercased() == letters[1].lowercased() else { return nil }
            var lead: [Step] = []
            if single(units[0]) != single(units[1]) {
                guard let a = unit(units[0]), let b = unit(units[1]), a.kind == b.kind else { return nil }
                let small = min(a.size, b.size)
                first = Simplify.run(first * plain(a.size / small))
                second = Simplify.run(second * plain(b.size / small))
                lead.append(Step("Use the same unit for both", "", [MathLine(.symbol("ratio"), .symbol("\(Format.text(first)) : \(Format.text(second))"))]))
            }
            guard let a = amount(first), let b = amount(second), a > 0, b > 0 else { return nil }
            let nFirst = form[1].lowercased().hasPrefix("n")
            let n = nFirst ? a / b : b / a
            // A decimal where it ends, a fraction where it doesn't.
            let ends = abs(n * 1_000_000 - (n * 1_000_000).rounded()) < 1e-6
            let shown = ends ? written(n) : Format.text(Simplify.run(nFirst ? first / second : second / first))
            lead.append(Step("Divide both sides by the same number", "To make the \(nFirst ? "second" : "first") number 1, divide both by \(Format.text(nFirst ? second : first)).", [MathLine(.symbol("n"), ends ? plain(n) : Simplify.run(nFirst ? first / second : second / first))]))
            return told("\(Format.text(first)) : \(Format.text(second))", [MathLine(.symbol(nFirst ? "\(shown) : 1" : "1 : \(shown)"))], lead)
        }
        // "Write the ratio 12 : 18 in its simplest form"
        if let found = groups(#"(?:simplify|write|give|express)(?: fully)?(?: the ratio)? (\d+) ?: ?(\d+)(?: ?: ?(\d+))?(?: as a ratio)?(?: in (?:its|their) simplest form)?"#, in: text),
           has(#"simplest form|\bsimplify\b"#, text), !has(#"in the form"#, text) {
            let parts = [found[1], found[2], found[3]].compactMap { Int($0) }.filter { $0 > 0 }
            guard parts.count >= 2, parts.count == (found[3].isEmpty ? 2 : 3) else { return nil }
            let common = parts.dropFirst().reduce(parts[0], gcd)
            return told(parts.map(String.init).joined(separator: " : "), [MathLine(.symbol(parts.map { String($0 / common) }.joined(separator: " : ")))],
                        [Step("Divide every part by the same number", common == 1 ? "Nothing but 1 goes into all of them: it's in its simplest form already." : "The biggest number that goes into all of them is \(common).")])
        }
        return nil
    }

    /// Ratios with a name for each part: "tea : coffee : hot chocolate = 3 : 5 : 2. 2600 hot drinks
    /// are sold. How many coffees are sold?", "The ratio of green : red is 4 : 3. What fraction of
    /// the pens are green?"
    private static func labelled(_ text: String, _ question: Question) -> Problem? {
        let word = #"[a-z][a-z' ]*?"#
        let sizes = #" ?(?:=|is|are) ?(\d+) ?: ?(\d+)(?: ?: ?(\d+))?(?!\d|\.\d| ?:)"#
        var match = groups(#"\bratio (?:of )?(\#(word)) ?: ?(\#(word))(?: ?: ?(\#(word)))?\#(sizes)"#, in: text)
        // The ratio on a line of its own: "students wearing glasses : students not wearing glasses = 3 : 8"
        if match == nil {
            let lines = question.lines.compactMap { groups(#"^(?:• ?)?(\#(word)) ?: ?(\#(word))(?: ?: ?(\#(word)))?\#(sizes)$"#, in: $0) }
            if lines.count == 1 { match = lines[0] }
        }
        guard let found = match, let whole = text.range(of: found[0].replacingOccurrences(of: "• ", with: "").replacingOccurrences(of: "•", with: ""), options: .caseInsensitive) else { return nil }
        let names = [found[1], found[2], found[3]].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let parts = [found[4], found[5], found[6]].compactMap { Double($0) }
        guard names.count == parts.count, Set(names).count == names.count, parts.allSatisfy({ $0 > 0 }), names.allSatisfy({ $0.split(separator: " ").count <= 5 }) else { return nil }
        let sum = parts.reduce(0, +)
        let rest = String(text[whole.upperBound...])
        /// Which names a sentence mentions, as whole words, with or without an s.
        func named(in sentence: String) -> [Int] {
            // "students wearing glasses" and "students not wearing glasses": told apart by the "not".
            if names.count == 2, let with = names.firstIndex(where: { $0.contains(" not ") }), names[with].replacingOccurrences(of: " not ", with: " ") == names[1 - with] {
                let words = names[1 - with].split(separator: " ").map { single(String($0)) }
                let said = sentence.lowercased().replacingOccurrences(of: "?", with: "").split(separator: " ").map { single(String($0)) }
                guard let last = words.last, said.contains(last) else { return [] }
                return [has(#"\bnot\b|n't\b"#, sentence) ? with : 1 - with]
            }
            return names.indices.filter { has("\\b\(NSRegularExpression.escapedPattern(for: single(names[$0])))(?:s|es)?\\b", sentence) }
        }
        // "What fraction of the pens are green?"
        if let asked = groups(#"what fraction of [^?.]*"#, in: rest)?[0] {
            let mentioned = named(in: asked)
            guard mentioned.count == 1 else { return nil }
            return made(plain(parts[mentioned[0]]) / plain(sum), decimals: false,
                        [Step("Count the parts", "There are \(written(sum)) parts altogether, and \(names[mentioned[0]]) is \(written(parts[mentioned[0]])) of them.")])
        }
        // "2600 hot drinks are sold. How many coffees are sold?"
        if let asked = groups(#"how many ([a-z ]+?) (?:are|were|is|was|does|do|did|will)\b"#, in: rest) {
            let wanted = named(in: asked[1])
            let numbers = every(#"(?<![\d.:])(\#(number))((?: [a-z]+){0,3})"#, in: rest)
            guard wanted.count == 1, numbers.count == 1, let size = Double(numbers[0][1]), size > 0 else { return nil }
            // The one number given is one name's amount, or else all of them together.
            let owners = named(in: numbers[0][2])
            guard owners.count <= 1, owners != wanted else { return nil }
            let base = owners.first.map { parts[$0] } ?? sum
            let answer = size / base * parts[wanted[0]]
            guard abs(answer - answer.rounded()) < 1e-9 else { return nil }
            let one = plain(size) / plain(base)
            return made(one * plain(parts[wanted[0]]), decimals: true,
                        [Step("Find one part", owners.isEmpty ? "There are \(written(sum)) parts altogether, and that's \(written(size))." : "\(names[owners[0]].capitalized) is \(written(base)) parts, and that's \(written(size)).", [MathLine(.symbol("1 part"), one, plain(size / base))]),
                         Step("Multiply up", "\(names[wanted[0]].capitalized) is \(written(parts[wanted[0]])) parts.")])
        }
        return nil
    }

    // MARK: Changing units

    /// "Convert 1400 grams to kilograms", "Convert 32 kilometres to miles. Use 8 kilometres = 5 miles"
    private static func units(_ text: String) -> Problem? {
        // "Complete the statement. 2 metres = centimetres"
        if has("complete the statement", text), let blank = groups(#"(\d+(?:\.\d+)?) (\#(unitWord)) ?= ?(\#(unitWord))\b(?! ?=)"#, in: text), every(#"(\d+(?:\.\d+)?) (\#(unitWord)) ?="#, in: text).count == 1,
           let size = value(blank[1]), let a = unit(blank[2]), let b = unit(blank[3]), a.kind == b.kind, a.kind != "money", a.size != b.size {
            let bigger = a.size > b.size
            let factor = bigger ? a.size / b.size : b.size / a.size
            return made(bigger ? size * plain(factor) : size / plain(factor), decimals: true,
                        [Step("Use how many of one make the other", "1 \(bigger ? single(blank[2]) : single(blank[3])) is \(written(factor)) \(bigger ? blank[3] : blank[2]), so \(bigger ? "multiply" : "divide") by \(written(factor)).")])
        }
        // "How many hours are there in 5 days?"
        if let asked = groups(#"how many (\#(unitWord)) are (?:there )?in (\d+(?:\.\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten) (\#(unitWord))\b(?! ?(?:and|\d))"#, in: text),
           let size = ["a", "an"].contains(asked[2].lowercased()) ? Expr.one : (count(asked[2]).map { Expr.integer($0) } ?? value(asked[2])),
           let to = unit(asked[1]), let from = unit(asked[3]), to.kind == from.kind, from.kind != "money", from.size > to.size {
            return made(size * plain(from.size / to.size), decimals: true, [Step("Use how many of one make the other", "1 \(single(asked[3])) is \(written(from.size / to.size)) \(asked[1]), so multiply by \(written(from.size / to.size)).")])
        }
        guard let found = groups(#"(?:convert|change) (\d+(?:\.\d+)?(?: \d+/\d+)?) ([a-z]+(?: [a-z]+)?) (?:in)?to ([a-z]+(?: [a-z]+)?)"#, in: text) else { return nil }
        // 3 1/2 is three and a half.
        let pieces = found[1].split(separator: " ").map(String.init)
        guard let whole = value(pieces[0]), let size = pieces.count == 2 ? value(pieces[1]).map({ Simplify.run(whole + $0) }) : whole else { return nil }
        /// A unit's name as it may be meant: both its words, or only the first ("miles use").
        func names(_ phrase: String) -> [String] {
            let words = phrase.lowercased().split(separator: " ").map(String.init)
            return words.count == 2 && ["use", "using", "give", "answer", "you", "in", "and", "to", "write", "circle", "show", "is", "are"].contains(words[1]) ? [single(words[0])] : [single(phrase)]
        }
        let from = names(found[2]), to = names(found[3])
        // What's stated: "8 kilometres = 5 miles".
        let stated = every(#"(\d+(?:\.\d+)?) ([a-z]+(?: [a-z]+)?) ?= ?(\d+(?:\.\d+)?) ([a-z]+(?: [a-z]+)?)"#, in: text).compactMap { rate -> (a: Expr, from: [String], b: Expr, to: [String], words: String)? in
            guard let a = exact(rate[1]), let b = exact(rate[3]), amount(a) ?? 0 > 0, amount(b) ?? 0 > 0 else { return nil }
            return (a, names(rate[2]), b, names(rate[4]), "\(rate[1]) \(names(rate[2])[0]) = \(rate[3]) \(names(rate[4]).last ?? "")")
        }
        func same(_ a: [String], _ b: [String]) -> Bool { a.contains { b.contains($0) } }
        /// How many of `to` one of `from` is, from one stated fact.
        func link(_ from: [String], _ to: [String]) -> (factor: Expr, words: String)? {
            for rate in stated {
                if same(rate.from, from), same(rate.to, to) { return (rate.b / rate.a, rate.words) }
                if same(rate.to, from), same(rate.from, to) { return (rate.a / rate.b, rate.words) }
            }
            return nil
        }
        if !stated.isEmpty {
            if let direct = link(from, to) {
                return made(size * direct.factor, decimals: true, [Step("Use what's given", "\(direct.words), so 1 \(from[0]) is \(Format.text(Simplify.run(direct.factor))) of the other.")])
            }
            // Through a unit both facts share: gallons to cubic feet to cubic metres.
            for middle in stated.flatMap({ [$0.from, $0.to] }) where !same(middle, from) && !same(middle, to) {
                if let first = link(from, middle), let second = link(middle, to) {
                    return made(size * first.factor * second.factor, decimals: true, [Step("Go through \(middle[0])", "\(first.words), and \(second.words).")])
                }
            }
            return nil
        }
        // Metric units and time, which need nothing stated.
        for name in [found[3], to[0]] {
            guard let a = unit(found[2]), let b = unit(name) ?? unit(name + "s"), a.kind == b.kind, a.kind != "money", a.size != b.size, !has(#"square|cubic|\^|²|³"#, found[0]) else { continue }
            let bigger = a.size > b.size
            let factor = bigger ? a.size / b.size : b.size / a.size
            return made(bigger ? size * plain(factor) : size / plain(factor), decimals: true,
                        [Step("Use how many of one make the other", "1 \(bigger ? single(found[2]) : single(name)) is \(written(factor)) \(bigger ? name : found[2]), so \(bigger ? "multiply" : "divide") by \(written(factor)).")])
        }
        return nil
    }

    // MARK: Density and pressure

    private static func measures(_ text: String) -> Problem? {
        let ask = #"(?:work out|calculate|find|circle|what is)"#
        if has(#"\bdensity\b"#, text), !has("population", text), let asked = groups("\(ask) the (mass|volume|density)\\b", in: text)?[1].lowercased() {
            let volumes = every(#"\bvolume(?: of| is|=)? ?(\#(number)) ?(mm|cm|m)\^?3"#, in: text)
            let masses = every(#"\bmass(?: of| is|=)? ?(\#(number)) ?(kg|g|kilograms?|grams?)\b"#, in: text)
            let densities = every(#"\bdensity(?: of(?: the)? [a-z]+)?(?: of| is|=)? ?(\#(number)) ?(kg|g)/(mm|cm|m)\^?3"#, in: text)
            func weight(_ word: String) -> String { word.lowercased().hasPrefix("k") ? "kg" : "g" }
            switch asked {
            case "mass":
                guard volumes.count == 1, densities.count == 1, masses.isEmpty, volumes[0][2].lowercased() == densities[0][3].lowercased(),
                      let volume = value(volumes[0][1]), let density = value(densities[0][1]) else { return nil }
                let lead = Step("Mass is density times volume", "Each \(volumes[0][2])³ has a mass of \(densities[0][1]) \(densities[0][2]), and there are \(volumes[0][1]) of them. The answer is in \(densities[0][2]).")
                if has(unitsAsked, text), let size = amount(density * volume) { return told("\(densities[0][1]) × \(volumes[0][1])", [MathLine(.symbol("\(written(size)) \(densities[0][2].lowercased())"))], [lead]) }
                return made(density * volume, decimals: true, [lead])
            case "volume":
                guard masses.count == 1, densities.count == 1, volumes.isEmpty, weight(masses[0][2]) == densities[0][2].lowercased(),
                      let mass = value(masses[0][1]), let density = value(densities[0][1]), amount(density) ?? 0 > 0 else { return nil }
                // (In the unit the question asks for: m³ to litres is × 1000, cm³ to litres ÷ 1000,
                // cm³ and millilitres are the same. Any other change of unit isn't made here.)
                let cube = densities[0][3].lowercased()
                var volume = mass / density
                var steps = [Step("Volume is mass divided by density", "Each \(densities[0][3])³ has a mass of \(densities[0][1]) \(densities[0][2]). The answer is in \(densities[0][3])³.")]
                if let wanted = groups(#"\bin (litres|millilitres|ml|cm ?\^?3|cm³|m ?\^?3|m³|mm ?\^?3|mm³)\b"#, in: text)?[1].lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "^", with: "") {
                    switch (cube, wanted) {
                    case ("m", "litres"):
                        volume = volume * .integer(1000)
                        steps.append(Step("Change m³ to litres", "1 m³ is 1000 litres, so multiply by 1000."))
                    case ("cm", "litres"):
                        volume = volume / .integer(1000)
                        steps.append(Step("Change cm³ to litres", "1 litre is 1000 cm³, so divide by 1000."))
                    case ("cm", "ml"), ("cm", "millilitres"), ("cm", "cm3"), ("cm", "cm³"), ("m", "m3"), ("m", "m³"), ("mm", "mm3"), ("mm", "mm³"):
                        break
                    default:
                        return nil
                    }
                }
                return made(volume, decimals: true, steps)
            default:
                guard masses.count == 1, volumes.count == 1, densities.isEmpty, let mass = value(masses[0][1]), let volume = value(volumes[0][1]), amount(volume) ?? 0 > 0 else { return nil }
                return made(mass / volume, decimals: true, [Step("Density is mass divided by volume", "The answer is in \(weight(masses[0][2]))/\(volumes[0][2])³.")])
            }
        }
        // "A force of 40 Newtons is applied to an area of 3.2 square metres. Work out the pressure."
        if has("\(ask) the pressure\\b", text) {
            let forces = every(#"\bforce of (\#(number)) ?(?:newtons?|n)\b"#, in: text), areas = every(#"\barea of (\#(number)) ?(square metres|square centimetres|m\^?2|cm\^?2)"#, in: text)
            guard forces.count == 1, areas.count == 1, let force = value(forces[0][1]), let area = value(areas[0][1]), amount(area) ?? 0 > 0 else { return nil }
            let square = areas[0][2].lowercased().contains("c") ? "cm²" : "m²"
            let lead = [Step("Pressure is force divided by area", "The answer is in newtons per \(square == "m²" ? "square metre" : "square centimetre") (N/\(square)).", [MathLine(force / area, Simplify.run(force / area))])]
            if has(unitsAsked, text), let size = amount(force / area) { return told("\(forces[0][1]) ÷ \(areas[0][1])", [MathLine(.symbol("\(written(size)) N/\(square)"))], lead) }
            return made(force / area, decimals: true, [lead[0]])
        }
        return nil
    }

    // MARK: Percentage change

    private static func percentages(_ text: String, money: String? = nil) -> Problem? {
        let hundred = Expr.integer(100)
        // "Work out the percentage increase from 80 to 280"
        if let found = groups(#"(?:work out|find|calculate|write down|what is) the percentage (increase|decrease|change|reduction|profit|loss) from (\#(number)) to (\#(number))(?!\d|\.\d| ?%)"#, in: text),
           let before = value(found[2]), let after = value(found[3]), let a = amount(before), let b = amount(after), a > 0 {
            let down = ["decrease", "reduction", "loss"].contains(found[1].lowercased())
            guard found[1].lowercased() == "change" || (down ? b < a : b > a) else { return nil }
            let change = down ? before - after : after - before
            return made(change / before * hundred, decimals: true,
                        [Step("Find the change", "From \(found[2]) to \(found[3]).", [MathLine(change, Simplify.run(change))]),
                         Step("Write it as a percentage of where it started", "Divide by \(found[2]), the amount before, and multiply by 100.")])
        }
        let up = #"increase[sd]?|rises?|rose|goes up|went up|grows?|grew"#, fall = #"decrease[sd]?|reduce[sd]?|falls?|fell|drops?|dropped|goes down|went down|depreciates?"#
        // "The cost of a ticket increases by 10% to £19.25. Work out the original cost."
        if let found = groups("\\b(\(up)|\(fall))(?: in (?:price|value|cost))? by (\(number)) ?% to (\(number))", in: text) ?? groups("\\b(\(up)|\(fall))d? by (\(number)) ?%\\.? (?:it|the [a-z]+)(?: now)? (?:is|costs) now (\(number))", in: text),
           has(#"\b(?:work out|find|calculate|what was|what is) (?:the |its )?(?:original|price before|cost before|value before|[a-z]+ before)"#, text), every(#"\d ?%"#, in: text).count == 1,
           let rate = value(found[2]), let after = value(found[3]) {
            let down = has("^(?:\(fall))$", found[1])
            let multiplier = down ? Expr.one - rate / hundred : Expr.one + rate / hundred
            guard let size = amount(multiplier), size > 0 else { return nil }
            return made(after / multiplier, decimals: true,
                        [Step("Find the multiplier", "\(down ? "Going down" : "Going up") by \(found[2])% is multiplying by \(written(size)).", [MathLine(.symbol("original × \(written(size))"), after)]),
                         Step("Undo it", "Divide by \(written(size)) to get back to the original.")])
        }
        // "The mass is 2200000 kg. This value is a 12% reduction from the original mass. Work out the original mass."
        if let found = groups("(\(number)) ?[a-z]*\\.? this (?:[a-z]+ )?is an? (\(number)) ?% (reduction|decrease|increase|rise) (?:from|on|of|in) the original", in: text),
           has(#"\b(?:work out|find|calculate|what was|what is) the original"#, text), every(#"\d ?%"#, in: text).count == 1, let after = value(found[1]), let rate = value(found[2]) {
            let down = ["reduction", "decrease"].contains(found[3].lowercased())
            let multiplier = down ? Expr.one - rate / hundred : Expr.one + rate / hundred
            guard let size = amount(multiplier), size > 0 else { return nil }
            return made(after / multiplier, decimals: true,
                        [Step("Find the multiplier", "\(down ? "A reduction" : "An increase") of \(found[2])% is multiplying by \(written(size)).", [MathLine(.symbol("original × \(written(size))"), after)]),
                         Step("Undo it", "Divide by \(written(size)) to get back to the original.")])
        }
        // "The value of a car decreases by 12.1% per year. Work out the number of full years until the car loses more than half its value."
        if let found = groups("\\b(?:\(fall)|reduce|decrease|fall|depreciate)[a-z]* (?:in value )?by (\(number)) ?% (?:each|every|per|a) year", in: text),
           has(#"number of (?:full |complete |whole )?years (?:until|before) [a-z\- ]*?(?:loses more than half|is worth less than half|has lost more than half|is less than half)"#, text),
           every(#"\d ?%"#, in: text).count == 1, let rate = value(found[1]).flatMap(amount), rate > 0, rate < 100 {
            var left = 1.0, years = 0
            var lines: [MathLine] = []
            while left >= 0.5, years < 200 {
                years += 1
                left *= 1 - rate / 100
                if years <= 12 { lines.append(MathLine(.symbol("after \(years) year\(years == 1 ? "" : "s")"), .symbol("\(written((left * 10000).rounded() / 100))% left"))) }
            }
            guard left < 0.5 else { return nil }
            return made(.integer(years), decimals: false, [Step("Multiply by \(written(1 - rate / 100)) for each year", "Going down by \(found[1])% leaves \(written(100 - rate))% each time. Keep going until less than half is left.", lines)])
        }
        // "…reduce by 4% each year. There are now 1000000… Work out the number after five years."
        // Only when its three numbers are the only ones: the amount now, the rate and the years.
        if let found = groups("\\b(\(up)|\(fall)|increase|reduce|decrease|rise|fall|grow|depreciate)[a-z]* (?:in value )?by (\(number)) ?% (?:each|every|per|a) year", in: text) ?? groups("\\b(compound) interest[a-z ]*? (?:at|of) (?:a rate of )?(\(number)) ?% (?:per year|per annum|a year|each year)", in: text),
           let years = groups(#"\b(?:after|for|in) (\d+|[a-z]+) years\b"#, in: text), let time = count(years[1]), time >= 1, time <= 50,
           asks(text), !has(#"\bmore than\b|\bless than\b|\bat least\b|\bhow many years\b|\bhow long\b|\bdifference\b|\boffer\b|\bsimple interest\b|\bhow (?:much|many) (?:more|less|fewer)\b|\binvestment [A-Z]\b"#, text), let rate = value(found[2]) {
            // (The same number of years said again, "at the end of 2 years", is still the years.)
            var numbers = all(number, in: text.replacingOccurrences(of: found[0], with: " ").replacingOccurrences(of: years[0], with: " ")
                .replacingOccurrences(of: "\\b\(years[1]) years\\b", with: " ", options: [.regularExpression, .caseInsensitive]))
            numbers.removeAll { $0 == "0" }
            guard numbers.count == 1, let start = value(numbers[0]), amount(start) ?? 0 > 0 else { return nil }
            // (The interest on its own is a different sum: the amount at the end take away the amount at the start.)
            guard !has(#"\b(?:work out|calculate|find|how much) (?:the )?(?:total )?(?:amount of )?(?:compound )?interest\b|\binterest (?:[a-z]+ )?(?:will |would )?(?:have )?(?:earn|paid|pay|receive|gain|get)|\bin interest\b"#, text) else { return nil }
            let down = has("^(?:\(fall)|reduce|decrease|fall|depreciate)", found[1])
            let multiplier = down ? Expr.one - rate / hundred : Expr.one + rate / hundred
            guard let size = amount(multiplier), size > 0 else { return nil }
            let expr = start * .power(multiplier, .integer(time))
            let lead = [Step("Find the multiplier for one year", "\(down ? "Going down" : "Going up") by \(found[2])% is multiplying by \(written(size)).", []),
                        Step("Do it once for each year", "\(time) years is multiplying by \(written(size)) \(time) times: \(numbers[0]) × \(written(size))\(raisedDigits(time)).")]
            // Money is given to the penny, unless the question says how to round it.
            if let money, has("£ ?\(numbers[0])(?!\\d|\\.\\d)", money), let total = amount(expr),
               !has(#"\bto the nearest\b|decimal places?|significant figures?"#, text) || has(#"\bto the nearest (?:penny|pence|1p)\b"#, text) {
                let rounded = (total * 100).rounded(.toNearestOrAwayFromZero) / 100
                let isExact = abs(total * 100 - (total * 100).rounded()) < 1e-7
                return told(found[0], [MathLine(.symbol(pounds(rounded)))], lead + [Step("Work it out", "", [MathLine(expr, plain(total))])] + (isExact ? [] : [Step("Round to the nearest penny", "Money has two decimal places.")]))
            }
            return made(expr, decimals: true, lead)
        }
        return nil
    }

    // MARK: Costs and recipes

    private static func costs(_ text: String, _ question: Question) -> Problem? {
        let price = #"(?:£(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?) ?p\b)"#
        // "4 apples cost £2.20. Work out the cost of 7 of these apples."
        let howMany = #"(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
        if let known = groups(#"\b\#(howMany) ([a-z]+(?: [a-z]+)?) costs? \#(price)"#, in: question.money),
           let asked = groups(#"(?:work out|find|calculate|what is) the (?:total )?(?:cost|price) of \#(howMany) (?:of (?:these|the) )?([a-z]+(?: [a-z]+)?)"#, in: text) ?? groups(#"how much (?:do|does|will|would) \#(howMany) (?:of (?:these|the) )?([a-z]+(?: [a-z]+)?) cost"#, in: text),
           every(price, in: question.money).count == 1, !has(#"%|\boffer\b|\bdiscount\b|\bfree\b|\beach\b|\bextra\b|\bprofit\b|\band\b"#, text),
           let had = count(known[1]), had > 0, let wanted = count(asked[1]), wanted > 0, wanted != had {
            // The same thing both times: "apples" and "of these apples".
            let first = known[2].split(separator: " ").map { single(String($0)) }, second = asked[2].split(separator: " ").map { single(String($0)) }
            guard let noun = first.last, second.contains(noun) || second.first == first.first else { return nil }
            let inPence = known[3].isEmpty
            guard let total = Double(inPence ? known[4] : known[3]) else { return nil }
            let known = [known[0], String(had), known[2], known[3], known[4]]
            let each = total / Double(had), answer = each * Double(wanted)
            func show(_ size: Double) -> String { inPence ? (size < 100 ? "\(written(size))p" : pounds(size / 100)) : pounds(size) }
            return told("\(wanted) \(known[2])", [MathLine(.symbol(show(answer)))],
                        [Step("Find the cost of one", "\(had) cost \(show(total)), so divide by \(had).", [MathLine(.symbol("1 costs"), .symbol(inPence ? "\(written(each))p" : (each < 1 ? "\(written(each * 100))p" : "£" + String(format: "%.4g", each))))]),
                         Step("Multiply up", "\(wanted) cost \(wanted) times as much.")])
        }
        // "Lentil soup for 4 people: Lentils 170 g… How many grams of lentils are needed to make this soup for 10 people?"
        if let asked = groups(#"how (?:many|much) (?:(\#(unitWord)) of )?([a-z]+)(?: (?:is|are|will be|would be))? needed (?:to make [a-z ]+? )?for (\d+) ([a-z]+)"#, in: text),
           let whole = text.range(of: asked[0], options: .caseInsensitive), let wanted = Double(asked[3]), wanted > 0 {
            let before = String(text[..<whole.lowerBound])
            let thing = NSRegularExpression.escapedPattern(for: asked[4])
            let made = every("\\b(?:for|serves|makes|to make) (\\d+) \(thing)\\b", in: before)
            let lines = every("\\b\(NSRegularExpression.escapedPattern(for: asked[2])) (\(number)) ?(\(unitWord))?\\b", in: before)
            guard made.count == 1, lines.count == 1, let base = Double(made[0][1]), base > 0, let size = value(lines[0][1]) else { return nil }
            // Asked for in the unit the list gives.
            if !asked[1].isEmpty {
                guard let a = unit(asked[1]), let b = unit(lines[0][2]), a.kind == b.kind, a.size == b.size else { return nil }
            }
            return Worded.made(size / plain(base) * plain(wanted), decimals: true,
                               [Step("Find the amount for one", "\(lines[0][1]) \(lines[0][2]) is for \(made[0][1]) \(asked[4]), so divide by \(made[0][1]).", [MathLine(size / plain(base), Simplify.run(size / plain(base)))]),
                                Step("Multiply up", "For \(asked[3]) \(asked[4]), multiply by \(asked[3]).")])
        }
        return nil
    }

    // MARK: Shapes from their measurements

    private static func shapes(_ text: String) -> Problem? {
        let ask = #"(?:work out|calculate|find|circle|what is)"#
        let length = #"(?:of )?(\d+(?:\.\d+)?) ?(?:mm|cm|m|km)?\b"#
        // In terms of π if that's asked for, or if the answers to choose from are.
        let exactly = wantsPi(text)
        func answer(_ written: String, _ lead: [Step]) -> Problem? {
            guard let expr = sum(written), expr.symbols.subtracting(["π"]).isEmpty else { return nil }
            return made(expr, decimals: !exactly, lead)
        }
        // "the volume, in cm3, of a cylinder with radius 5 cm and height 8 cm"
        if let found = groups("\(ask) the volume\\b[^.?]*?\\bcylinder (?:with|of|that has|which has|has) (?:a )?(radius|height) \(length),? and (?:a )?(radius|height) \(length)", in: text),
           found[1].lowercased() != found[3].lowercased() {
            let radius = found[1].lowercased() == "radius" ? found[2] : found[4], height = found[1].lowercased() == "radius" ? found[4] : found[2]
            return answer("π*\(radius)^2*\(height)", [Step("Volume of a cylinder", "The area of the circle at its end, π × radius², times its height.", [MathLine(.symbol("π × \(radius)² × \(height)"))])])
        }
        // "the volume of a sphere with diameter 20 cm"
        if let found = groups("\(ask) the (volume|surface area) of (?:a|the) sphere (?:with|of|that has|which has) (?:a )?(radius|diameter) \(length)", in: text), let size = Double(found[3]) {
            let radius = written(found[2].lowercased() == "radius" ? size : size / 2)
            let half = found[2].lowercased() == "radius" ? "" : "The radius is half the diameter: \(radius). "
            if found[1].lowercased() == "volume" {
                return answer("4/3*π*\(radius)^3", [Step("Volume of a sphere", half + "The volume is 4/3 × π × radius³.", [MathLine(.symbol("4/3 × π × \(radius)³"))])])
            }
            return answer("4*π*\(radius)^2", [Step("Surface area of a sphere", half + "The surface area is 4 × π × radius².", [MathLine(.symbol("4 × π × \(radius)²"))])])
        }
        // "the area of a circle with radius 6 cm"
        if let found = groups("\(ask) the (area|circumference) of (?:a|the) circle (?:with|of|that has|which has) (?:a )?(radius|diameter) \(length)", in: text), let size = Double(found[3]) {
            let radius = written(found[2].lowercased() == "radius" ? size : size / 2)
            let half = found[2].lowercased() == "radius" ? "" : "The radius is half the diameter: \(radius). "
            if found[1].lowercased() == "area" {
                return answer("π*\(radius)^2", [Step("Area of a circle", half + "The area is π × radius².", [MathLine(.symbol("π × \(radius)²"))])])
            }
            return answer("2*π*\(radius)", [Step("Circumference of a circle", half + "The circumference is 2 × π × radius, which is π × diameter.", [MathLine(.symbol("2 × π × \(radius)"))])])
        }
        // "the volume of a cube with side length 4 cm"
        if let found = groups("\(ask) the (volume|surface area) of (?:a|the) cube (?:with|of|that has|which has) (?:sides?|edges?|side length|edge length)(?: of length)? \(length)", in: text) {
            return found[1].lowercased() == "volume"
                ? answer("\(found[2])^3", [Step("Volume of a cube", "Side × side × side.", [MathLine(.symbol("\(found[2])³"))])])
                : answer("6*\(found[2])^2", [Step("Surface area of a cube", "Six square faces, each side × side.", [MathLine(.symbol("6 × \(found[2])²"))])])
        }
        // "A cuboid measures 4 cm by 5 cm by 6 cm. Work out its volume."
        if has("\(ask) (?:the|its) volume\\b", text), let found = groups(#"\bcuboid\b[^.?]*? (\d+(?:\.\d+)?) ?(?:mm|cm|m)? by (\d+(?:\.\d+)?) ?(?:mm|cm|m)? by (\d+(?:\.\d+)?) ?(?:mm|cm|m)?\b"#, in: text) {
            return answer("\(found[1])*\(found[2])*\(found[3])", [Step("Volume of a cuboid", "Length × width × height.", [MathLine(.symbol("\(found[1]) × \(found[2]) × \(found[3])"))])])
        }
        return nil
    }

    // MARK: Points and lines

    private static func points(_ text: String) -> Problem? {
        let pair = #"\(\s?(\#(number)) ?, ?(\#(number))\s?\)"#
        /// A coordinate as a decimal where it ends (3.5), a fraction where it doesn't.
        func coordinate(_ value: Expr) -> String {
            let tidy = Simplify.run(value)
            if let size = amount(tidy), abs(size * 1000 - (size * 1000).rounded()) < 1e-9 { return written(size) }
            return Format.text(tidy)
        }
        func shown(_ x: Expr, _ y: Expr) -> String { "(\(coordinate(x)), \(coordinate(y)))" }
        // "P is (4, 9) and Q is (-2, 1). Circle the midpoint of PQ."
        if let asked = groups(#"\bmidpoint of (?:the line (?:segment )?)?([A-Z])([A-Z])\b"#, in: text) {
            var ends: [(Expr, Expr)] = []
            for letter in [asked[1], asked[2]] {
                let found = every("\\b\(letter) ?(?:is|=|has coordinates|is the point|is at)? ?\(pair)", in: text)
                guard found.count == 1, let x = value(found[0][1]), let y = value(found[0][2]) else { return nil }
                ends.append((x, y))
            }
            let x = (ends[0].0 + ends[1].0) / .two, y = (ends[0].1 + ends[1].1) / .two
            return told("midpoint of \(asked[1])\(asked[2])", [MathLine(.symbol(shown(x, y)))],
                        [Step("Go halfway along and halfway up", "The midpoint's coordinates are the means of the two x's and of the two y's.", [MathLine(.symbol("x"), x, Simplify.run(x)), MathLine(.symbol("y"), y, Simplify.run(y))])])
        }
        // "A straight line has gradient 5 and passes through the point (3, 7)": its equation.
        if has(#"equation of (?:the|this|a) (?:straight )?line"#, text), let slope = groups(#"\bgradient (?:of |is |= ?)?(\#(number))(?![\d.]*x)"#, in: text),
           let through = groups("(?:passes|goes) through (?:the point )?(?:[A-Z] ?)?\(pair)", in: text), every(#"\bgradient\b"#, in: text).count == 1,
           let m = value(slope[1]), let a = value(through[1]), let b = value(through[2]) {
            let c = Simplify.run(b - m * a)
            let line = Simplify.run(m * .symbol("x") + c)
            return told("gradient \(slope[1]) through (\(through[1]), \(through[2]))", [MathLine(.symbol("y"), line)],
                        [Step("Start from y = mx + c", "The gradient is m, so y = \(Format.text(Simplify.run(m * .symbol("x")))) + c."),
                         Step("Put the point in to find c", "x = \(through[1]) and y = \(through[2]).", [MathLine(b, .symbol("\(Format.text(Simplify.run(m * a))) + c")), MathLine(.symbol("c"), c)])])
        }
        // "A circle has centre O and passes through (0, 6). Write down the equation of the circle."
        if has(#"(?:write down|work out|find|give|what is) the equation of (?:the|this) circle"#, text), has(#"\bcircle\b[^.]*?\bcentre (?:O\b|the origin|\(0, ?0\))"#, text), every(#"\bcircle\b"#, in: text).count <= 4 {
            var square: Expr?
            var how = ""
            if let through = groups("(?:passes|goes) through (?:the point )?(?:[A-Z] ?)?\(pair)", in: text), every(pair, in: text.replacingOccurrences(of: "(0, 0)", with: "")).count == 1, let a = value(through[1]), let b = value(through[2]) {
                square = Simplify.run(a * a + b * b)
                how = "The radius is the distance from the centre to (\(through[1]), \(through[2])), so its square is \(through[1])² + \(through[2])²."
            } else if let radius = groups(#"\bradius (?:of |is |= ?)?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: text), every(pair, in: text.replacingOccurrences(of: "(0, 0)", with: "")).isEmpty, every(#"\bradius\b"#, in: text).count == 1, let r = exact(radius[1]) {
                square = Simplify.run(r * r)
                how = "The radius is \(radius[1]), and its square is \(Format.text(Simplify.run(r * r)))."
            }
            if let square, amount(square) ?? 0 > 0 {
                return told("circle, centre the origin", [MathLine(.symbol("x² + y²"), square)], [Step("A circle round the origin is x² + y² = r²", how)])
            }
        }
        // "the gradient of the line through (1, 2) and (5, 10)"
        if let found = groups("(?:work out|find|calculate|what is) the gradient of the (?:straight )?line (?:segment )?(?:that )?(?:through|joining|passing through|passes through|between|from) (?:the points )?(?:[A-Z] ?)?\(pair) (?:and|to) (?:[A-Z] ?)?\(pair)", in: text),
           let x1 = value(found[1]), let y1 = value(found[2]), let x2 = value(found[3]), let y2 = value(found[4]), amount(x2 - x1) != 0 {
            return made((y2 - y1) / (x2 - x1), decimals: false, [Step("Gradient is the change in y over the change in x", "From (\(found[1]), \(found[2])) to (\(found[3]), \(found[4])).")])
        }
        /// A line's equation as ax + by + c = 0.
        func line(_ equation: String) -> (a: Expr, b: Expr, c: Expr)? {
            let sides = raised(equation).split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2, !sides[0].isEmpty, !sides[1].isEmpty, let left = sum(sides[0]), let right = sum(sides[1]), left.symbols.union(right.symbols).isSubset(of: ["x", "y"]),
                  !left.symbols.union(right.symbols).isEmpty else { return nil }
            func at(_ x: Int, _ y: Int) -> Expr { Simplify.run((left - right).substituting("x", with: .integer(x)).substituting("y", with: .integer(y))) }
            let c = at(0, 0), a = Simplify.run(at(1, 0) - c), b = Simplify.run(at(0, 1) - c)
            // Straight: the same steps everywhere.
            guard c.number != nil, a.number != nil, b.number != nil, let far = amount(at(2, 3)), let straight = amount(c + .two * a + .integer(3) * b), abs(far - straight) < 1e-9 else { return nil }
            return (a, b, c)
        }
        let stop = #"(?=$|\.(?: |$)| \d+ \(| work| write| circle| find| answer| give)"#
        // "Work out the gradient of the line 2y = 10x"
        if let found = groups("(?:work out|find|write down|what is|circle) the gradient of the (?:straight )?line (?:with equation )?(.+?=.+?)\(stop)", in: text), let line = line(found[1]), !line.b.isZero {
            return made(-line.a / line.b, decimals: false, [Step("Write it as y = mx + c", "Get y on its own. The gradient is the number in front of x.", [MathLine(.symbol("y"), Simplify.run(-line.a / line.b * .symbol("x") - line.c / line.b))])])
        }
        // "Write down the coordinates of the y-intercept of the line y = 3x + 8", "…the point where the line crosses the x-axis"
        if let found = groups("\\b([xy])-intercept of the (?:straight )?line (?:with equation )?(.+?=.+?)\(stop)", in: text).map({ [$0[1], $0[2]] })
            ?? groups("equation of (?:a|the) (?:straight )?line is (.+?=.+?) (?:work out|find|write down|circle) the (?:coordinates of the )?point where (?:the line|it) crosses the ([xy])-axis", in: text).map({ [$0[2], $0[1]] }),
           has(#"\b(?:work out|find|write down|what is|what are|circle)\b"#, text), let line = line(found[1]) {
            let onY = found[0].lowercased() == "y"
            guard !(onY ? line.b : line.a).isZero else { return nil }
            let cut = Simplify.run(-line.c / (onY ? line.b : line.a))
            return told(found[1], [MathLine(.symbol(onY ? "(0, \(coordinate(cut)))" : "(\(coordinate(cut)), 0)"))],
                        [Step(onY ? "Put x = 0" : "Put y = 0", "The line crosses the \(onY ? "y" : "x")-axis where \(onY ? "x" : "y") is nought.", [MathLine(.symbol(onY ? "y" : "x"), cut)])])
        }
        // "Circle the point that is on the line 4x + y = 7", with four points to choose from.
        if let found = groups(#"circle the point (?:that|which) (?:is|lies) on the (?:line|curve|graph)(?: with equation)? (.+?=.+?) (\(.*)$"#, in: text) {
            let sides = raised(found[1]).split(separator: "=").map(String.init)
            let offered = every(pair, in: found[2])
            guard sides.count == 2, let left = sum(sides[0]), let right = sum(sides[1]), left.symbols.union(right.symbols).isSubset(of: ["x", "y"]), offered.count == 4 else { return nil }
            var lines: [MathLine] = []
            var on: [[String]] = []
            for point in offered {
                guard let x = value(point[1]), let y = value(point[2]) else { return nil }
                let a = Simplify.run(left.substituting("x", with: x).substituting("y", with: y)), b = Simplify.run(right.substituting("x", with: x).substituting("y", with: y))
                guard let sizeA = amount(a), let sizeB = amount(b) else { return nil }
                let fits = abs(sizeA - sizeB) < 1e-9
                if fits { on.append(point) }
                lines.append(MathLine(.symbol("(\(point[1]), \(point[2]))"), a, relation: ":", suffix: fits ? "✓" : nil))
            }
            guard on.count == 1 else { return nil }
            return told(found[1], [MathLine(.symbol("(\(on[0][1].replacingOccurrences(of: "-", with: "−")), \(on[0][2].replacingOccurrences(of: "-", with: "−")))"))],
                        [Step("Put each point's x and y into the equation", "The point on it is the one that makes both sides equal: \(Format.text(left)) has to come to \(Format.text(right)).", lines)])
        }
        return nil
    }

    // MARK: Algebra asked for in words

    /// A power that has dropped onto the line: x2 is x², (x - 3)2 is (x - 3)².
    private static func raised(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<![A-Za-z]{2})([a-z])(\d)(?!\d|\.\d)"#, with: "$1^$2", options: .regularExpression)
            .replacingOccurrences(of: #"\)(\d)(?!\d|\.\d)"#, with: ")^$1", options: .regularExpression)
    }

    private static func algebra(_ text: String) -> Problem? {
        // "Work out the value of 2(a² + 3a) when a = 4"
        if let found = groups(#"(?:work out|find|calculate|evaluate) the value of (.+?) when ([a-z]) ?= ?(\#(number))(?:,? (?:and )?([a-z]) ?= ?(\#(number)))?(?![\d.]*[a-z(])"#, in: text),
           let expr = sum(raised(found[1])), let first = value(found[3]) {
            var values = [found[2]: first]
            if !found[4].isEmpty { values[found[4]] = value(found[5]) }
            guard expr.symbols == Set(values.keys) else { return nil }
            return Problem(kind: .substitute(expr, values: values), text: "", usesDecimals: text.range(of: #"\d\.\d"#, options: .regularExpression) != nil)
        }
        // "Rearrange y = 3x - 2 to make x the subject."
        var formula: (equation: String, letter: String)?
        if let found = groups(#"rearrange (?:the formula )?(.+?=.+?) to make ([a-z]) the subject"#, in: text) { formula = (found[1], found[2]) }
        else if let found = groups(#"make ([a-z]) the subject of (?:the formula )?(.+?=[^.]+?)(?:\.|$| circle| give| answer)"#, in: text) { formula = (found[2], found[1]) }
        // "Rearrange this formula to make t the subject. s = ½at²": the formula on the line after.
        // (Not when it's read ending in the letter itself: a power at the end of a line is what's lost in reading, and
        // "s = 1/2at" for s = ½at² would be a different question.)
        else if let found = groups(#"rearrange (?:this|the|the following) formula to make ([a-z]) the subject\.? ((?-i:[A-Za-z]) ?= ?[-+*/^(). \dA-Za-z×÷π√]+?)(?= ?(?:\[|\([a-z]\) ?\.|\.{2,}|$))"#, in: text),
                !found[2].trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(found[1].lowercased()) { formula = (found[2].trimmingCharacters(in: .whitespaces), found[1]) }
        if let formula {
            let sides = raised(formula.equation).split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard sides.count == 2, !sides[0].isEmpty, !sides[1].isEmpty, let left = sum(sides[0]), let right = sum(sides[1]),
                  left.contains(formula.letter) != right.contains(formula.letter) else { return nil }
            let problem = Problem(kind: .solve([Equation(left: left, right: right)], unknowns: [formula.letter]), text: "", usesDecimals: false)
            guard let solution = Engine.solve(problem, angles: .degrees), let first = solution.answers.first?.parts.last else { return nil }
            var answer = first
            var root: [Step] = []
            if solution.answers.count == 2, let second = solution.answers[1].parts.last {
                // The letter was squared, which gives a root and the same with its sign changed. The letters of a
                // formula stand for sizes, so the positive root is the one wanted.
                func isNegative(_ expr: Expr) -> Bool { Format.text(expr).hasPrefix("−") || Format.text(expr).hasPrefix("-") }
                guard Simplify.run(first + second).isZero, isNegative(first) != isNegative(second) else { return nil }
                answer = isNegative(first) ? second : first
                root = [Step("Take the square root", "\(formula.letter)² is on its own, so \(formula.letter) is its square root. A formula's letters stand for sizes, so take the positive root.")]
            } else if solution.answers.count != 1 { return nil }
            guard !answer.contains(formula.letter) else { return nil }
            // The same answer written the shortest way.
            let ways = root.isEmpty ? [answer, Simplify.run(Simplify.together(answer)), Simplify.run(Simplify.expand(answer))] : [answer]
            let tidy = ways.min { Format.text($0).count < Format.text($1).count } ?? answer
            return told(formula.equation, [MathLine(.symbol(formula.letter), tidy)],
                        [Step("Get \(formula.letter)\(root.isEmpty ? "" : "²") on its own", "Undo what's done to \(formula.letter), one thing at a time, doing the same to both sides.", [MathLine(left, right)])] + root)
        }
        // "Write x² + 12x + 50 in the form (x + a)² + b" (as read, the three words may have run together: "intheform")
        if let found = groups(#"(.+?)(?: can be written| is written| written)? ?in ?the ?for[mn]? ?([a-z] ?)?\(([a-z]) ?[-+] ?[a-z]\)\^?2? ?[-+] ?[a-z]"#, in: text),
           let quadratic = { () -> Polynomial? in
               // The quadratic is the end of what comes before: the most of it that is one.
               let words = found[1].split(separator: " ").map(String.init).suffix(14)
               for start in words.indices {
                   let written = words[start...].joined(separator: " ")
                   if let expr = sum(raised(written)), let quadratic = Polynomial(expr, in: found[3]), quadratic.degree == 2 { return quadratic }
               }
               return nil
           }() {
            let expr = quadratic.expr
            let a = Expr.number(.exact(quadratic.coefficient(2))), b = Expr.number(.exact(quadratic.coefficient(1))), c = Expr.number(.exact(quadratic.coefficient(0)))
            guard !found[2].isEmpty || a.isOne else { return nil }
            let inside = Simplify.run(b / (.two * a)), outside = Simplify.run(c - b * b / (.integer(4) * a))
            guard let p = amount(inside), let q = amount(outside) else { return nil }
            func signed(_ value: Expr, _ size: Double) -> String { size < 0 ? " − \(Format.text(Simplify.run(-value)))" : " + \(Format.text(value))" }
            let front = a.isOne ? "" : Format.text(a)
            let form = "\(front)(\(found[3])\(p == 0 ? "" : signed(inside, p)))²\(q == 0 ? "" : signed(outside, q))"
            return told(Format.text(expr), [MathLine(.symbol(form))],
                        [Step("Halve the number in front of \(found[3])", a.isOne ? "Half of \(Format.text(b)) is \(Format.text(inside)): that goes in the bracket." : "Take \(Format.text(a)) out first. Then half of \(Format.text(Simplify.run(b / a))) is \(Format.text(inside)): that goes in the bracket."),
                         Step("Put the number right", "The bracket squared gives \(Format.text(Simplify.run(a * inside * inside))) on the end, and \(Format.text(c)) is wanted, so add \(Format.text(outside)).")])
        }
        // "A curve has the equation y = (x - 3)² - 8. Write down the coordinates of the turning point."
        // With more than one curve ("The minimum point of y = x² is at (0, 0). Write down the coordinates of
        // the minimum point of y = x² + 2"), the one named straight after "point of".
        if has(#"coordinates of the (?:turning|minimum|maximum) point|coordinates of the vertex"#, text) {
            let curve = #"y ?= ?([-+*/^(). \dx×÷]*[\dx)])(?![a-z(^])"#
            var written = groups("coordinates of the (?:turning|minimum|maximum) point of (?:the (?:curve|graph)(?: with equation)? )?\(curve)", in: text)?[1]
            if written == nil {
                let all = Set(every("(?<![a-z])\(curve)", in: text).map { $0[1].replacingOccurrences(of: " ", with: "") })
                if all.count == 1 { written = all.first }
            }
            guard let written, let expr = sum(raised(written)), expr.symbols == ["x"], let quadratic = Polynomial(expr, in: "x"), quadratic.degree == 2 else { return nil }
            let a = Expr.number(.exact(quadratic.coefficient(2))), b = Expr.number(.exact(quadratic.coefficient(1))), c = Expr.number(.exact(quadratic.coefficient(0)))
            let x = Simplify.run(-b / (.two * a)), y = Simplify.run(c - b * b / (.integer(4) * a))
            return told("y = \(Format.text(expr))", [MathLine(.symbol("(\(Format.text(x)), \(Format.text(y)))"))],
                        [Step("Find where the squared bracket is nought", "Written as a bracket squared plus a number, y is \(Format.text(a))(x − \(Format.text(x)))² + \(Format.text(y)). The bracket squared is never less than nought, and it is nought when x = \(Format.text(x))."),
                         Step("Read off the point", "Then y = \(Format.text(y)).")])
        }
        // "Circle the two roots of (x - 5)(x + 3) = 0"
        if let found = groups(#"(?:circle|write down|find|work out) the (?:two )?(?:roots|solutions) of (.+?)= ?0(?!\d|\.\d)"#, in: text), let left = sum(raised(found[1])), left.symbols.count == 1 {
            return Problem(kind: .solve([Equation(left: left, right: .zero)], unknowns: []), text: "", usesDecimals: false)
        }
        // "Circle the list of all the integers that satisfy -2 < x ≤ 4"
        // (The list is the answer only where the list is what's asked: not the largest of
        // them, how many there are, or something worked out from them.)
        if has(#"\bintegers?\b|\bwhole numbers?\b"#, text), has(#"\b(?:list|write down|circle|work out|find)\b"#, text),
           !has(#"\blargest\b|\bsmallest\b|\bgreatest\b|\bleast\b|\bbiggest\b|\bmaximum\b|\bminimum\b|\bsum of\b|\bproduct of\b|\btotal\b|\bhow many\b|\bprobability\b|\bmean\b|\bmedian\b|\bdifference\b|\bvalue of [a-z] ?[-+*/^]"#, text),
           let found = groups(#"(\#(number)) ?(<|≤) ?(\d*)([a-z]) ?(<|≤) ?(\#(number))(?!\d|\.\d| ?[<≤/])"#, in: text), every(#"[<≤>≥]"#, in: text).count == 2,
           // (⩽ is often read as <, which drops a number from the list. With one of the two read as ≤, the other is as printed.)
           found[2] == "≤" || found[5] == "≤",
           let low = value(found[1]).flatMap(amount), let high = value(found[6]).flatMap(amount), let times = found[3].isEmpty ? 1 : Double(found[3]), times > 0 {
            let from = low / times, to = high / times
            var first = Int(from.rounded(.up)), last = Int(to.rounded(.down))
            if found[2] == "<", Double(first) == from { first += 1 }
            if found[5] == "<", Double(last) == to { last -= 1 }
            guard first <= last, last - first < 15 else { return nil }
            let list = (first...last).map { written(Double($0)) }.joined(separator: ", ")
            return told(found[0], [MathLine(.symbol(found[4]), .symbol(list))],
                        [Step("Find where the whole numbers start and stop", "\(found[2] == "<" ? "<" : "≤") on the left \(found[2] == "<" ? "leaves its number out" : "takes its number in"), and \(found[5] == "<" ? "<" : "≤") on the right \(found[5] == "<" ? "leaves its number out" : "takes its number in").")])
        }
        return nil
    }

    // MARK: Estimating

    /// "By rounding each number to 1 significant figure, estimate the value of 1.98 × 3.82 + 6.75²"
    private static func estimate(_ text: String, _ question: Question) -> Problem? {
        guard let how = groups(#"rounding (?:each|every|all)(?: of the)? numbers? to (?:(1|one) significant figure|the nearest (10|ten|100|hundred|whole number|integer))"#, in: text),
              let found = groups(#"estimate (?:the value of|the answer to|an answer to)? ?(.+?)(?= you must| give| show| circle|$)"#, in: text) else { return nil }
        let nearest = ["10": 10.0, "ten": 10, "100": 100, "hundred": 100, "whole number": 1, "integer": 1][how[2].lowercased()]
        func round(_ size: Double) -> Double {
            if let nearest { return (size / nearest).rounded(.toNearestOrAwayFromZero) * nearest }
            return roundedValue(size, places: 1, significant: true) ?? size
        }
        let written = found[1].trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard written.range(of: #"^[-\d.() ×x*÷/+^√]+$"#, options: .regularExpression) != nil, written.range(of: #"[×x*÷/+]| - "#, options: .regularExpression) != nil,
              let regex = try? NSRegularExpression(pattern: #"(?<![\^\d.])\d+(?:\.\d+)?"#) else { return nil }
        // A number with more figures than the rest that ends in 2 or 3 may be a square or a cube
        // whose power has dropped onto the line (6.75² read as 6.752): then it isn't known.
        let figures = regex.matches(in: written, range: NSRange(written.startIndex..., in: written)).compactMap { Range($0.range, in: written).map { String(written[$0]) } }
            .map { (text: $0, count: $0.replacingOccurrences(of: ".", with: "").drop(while: { $0 == "0" }).count) }
        if let longest = figures.max(by: { $0.count < $1.count }), longest.count >= 4, figures.filter({ $0.count >= longest.count }).count == 1,
           longest.text.hasSuffix("2") || longest.text.hasSuffix("3") { return nil }
        // Each number to 1 significant figure; a power stays as it is.
        var rounded = ""
        var at = written.startIndex
        for match in regex.matches(in: written, range: NSRange(written.startIndex..., in: written)) {
            guard let range = Range(match.range, in: written), let size = Double(written[range]) else { return nil }
            rounded += written[at..<range.lowerBound]
            rounded += size == 0 ? "0" : Worded.written(round(size))
            at = range.upperBound
        }
        rounded += written[at...]
        guard let expr = sum(rounded.replacingOccurrences(of: "x", with: "×")), expr.symbols.isEmpty, amount(expr) != nil else { return nil }
        return made(expr, decimals: true, [Step("Round each number \(nearest == nil ? "to 1 significant figure" : "to the nearest \(how[2])")", "", [MathLine(.symbol(written)), MathLine(.symbol(rounded))])])
    }

    // MARK: Angles of polygons, and bearings

    private static func angles(_ text: String) -> Problem? {
        let sides = ["triangle": 3, "quadrilateral": 4, "pentagon": 5, "hexagon": 6, "heptagon": 7, "octagon": 8, "nonagon": 9, "decagon": 10, "dodecagon": 12]
        let ask = #"(?:work out|calculate|find|what is|write down|circle)"#
        // "What is the size of an exterior angle of a regular decagon?"
        if let found = groups("\(ask) the size of (?:an?|each|one) (exterior|interior) angle(?: of (?:a|the) regular ([a-z]+)(?: with (\\d+) sides)?)?", in: text) {
            var count = sides[found[2].lowercased()] ?? Int(found[3])
            // "Part of a regular polygon is shown. Assume that the polygon is an octagon."
            if count == nil, found[2].isEmpty, let assumed = groups(#"\bregular polygon\b.*\bpolygon is an? ([a-z]+)"#, in: text) { count = sides[assumed[1].lowercased()] }
            guard let count, count >= 3, count <= 360 else { return nil }
            let outside = Expr.integer(360) / .integer(count)
            let lead = Step("Exterior angles add up to 360°", "A regular polygon with \(count) sides has \(count) equal exterior angles.", [MathLine(.symbol("exterior angle"), outside, Simplify.run(outside))])
            if found[1].lowercased() == "exterior" { return made(outside, decimals: true, [lead]) }
            return made(.integer(180) - outside, decimals: true, [lead, Step("Interior and exterior angles make a straight line", "So the interior angle is 180° take away the exterior angle.")])
        }
        // "Work out the sum of the interior angles of a hexagon."
        if let found = groups("\(ask) the sum of the interior angles of (?:a|an|any)(?: regular)? (?:([a-z]+)|polygon with (\\d+) sides)", in: text), let count = sides[found[1].lowercased()] ?? Int(found[2]), count >= 3 {
            return made(.integer(180) * .integer(count - 2), decimals: false, [Step("Split it into triangles", "A polygon with \(count) sides splits into \(count - 2) triangles, each with angles adding to 180°.")])
        }
        // "The bearing of A from B is 310°. Circle the bearing of B from A."
        if let given = groups(#"\bbearing of ([A-Z]) from ([A-Z]) is (\d{1,3}) ?°?"#, in: text), let asked = groups("\(ask) the bearing of ([A-Z]) from ([A-Z])", in: text),
           asked[1].uppercased() == given[2].uppercased(), asked[2].uppercased() == given[1].uppercased(), let bearing = Int(given[3]), bearing < 360 {
            let back = (bearing + 180) % 360
            return told("bearing of \(asked[1].uppercased()) from \(asked[2].uppercased())", [MathLine(.symbol(String(format: "%03d°", back)))],
                        [Step("Turn right round", "Going back the other way is a half turn: \(bearing < 180 ? "add" : "take away") 180°.", [MathLine(.symbol("\(bearing)° \(bearing < 180 ? "+" : "−") 180°"), .symbol("\(back)°"))])])
        }
        return nil
    }

    // MARK: Two things bought together

    /// "4 chocolate bars and 3 packets of mints cost £4.70. 5 chocolate bars and 1 packet of mints
    /// cost £4.50. Work out the cost of a chocolate bar and the cost of a packet of mints."
    private static func combos(_ question: Question) -> Problem? {
        let text = question.money
        let howMany = #"(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten)"#
        let thing = #"([a-z]+(?: [a-z]+){0,3}?)"#
        let size = #"(?:£(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?) ?(p|g|kg|grams|kilograms)\b)"#
        let found = every("\\b\(howMany) \(thing)(?: and \(howMany) \(thing))? (?:costs?|have a total (?:mass|cost|weight) of|has a (?:mass|cost|weight) of|weighs?) \(size)", in: text)
        guard found.count == 2, !has(#"%|\boffer\b|\bdiscount\b|\bfree\b|\bextra\b|\bprofit\b|\bchange\b"#, text) else { return nil }
        /// "packets of mints" and "packet of mints" are the same thing; so are "hotdogs" and "hot dog".
        func key(_ name: String) -> String { name.lowercased().split(separator: " ").map { single(String($0)) }.joined() }
        func number(_ word: String) -> Double? { ["a", "an"].contains(word.lowercased()) ? 1 : count(word).map(Double.init) }
        var names: [String] = [], shown: [String: String] = [:]
        var rows: [(parts: [String: Double], total: Double)] = []
        var units = Set<String>()
        for statement in found {
            var parts: [String: Double] = [:]
            for (howMany, name) in [(statement[1], statement[2]), (statement[3], statement[4])] where !name.isEmpty {
                guard let howMany = number(howMany), howMany > 0, parts[key(name)] == nil else { return nil }
                parts[key(name)] = howMany
                if !names.contains(key(name)) { names.append(key(name)); shown[key(name)] = howMany == 1 ? name : name.split(separator: " ").map(String.init).enumerated().map { $0.offset == 0 && name.contains(" of ") || $0.offset == name.split(separator: " ").count - 1 && !name.contains(" of ") ? single($0.element) : $0.element }.joined(separator: " ") }
            }
            // Pounds as pence, kilograms as grams.
            guard let total = Double(statement[5].isEmpty ? statement[6] : statement[5]) else { return nil }
            let unit = statement[5].isEmpty ? (statement[7].lowercased().hasPrefix("k") ? "kg" : (statement[7].lowercased() == "p" ? "p" : "g")) : "£"
            units.insert(unit == "£" || unit == "p" ? "money" : "mass")
            rows.append((parts, unit == "£" ? total * 100 : (unit == "kg" ? total * 1000 : total)))
        }
        guard names.count == 2, units.count == 1 else { return nil }
        let a = rows[0].parts[names[0]] ?? 0, b = rows[0].parts[names[1]] ?? 0, c = rows[1].parts[names[0]] ?? 0, d = rows[1].parts[names[1]] ?? 0
        let bottom = a * d - b * c
        guard bottom != 0 else { return nil }
        let first = (rows[0].total * d - b * rows[1].total) / bottom, second = (a * rows[1].total - rows[0].total * c) / bottom
        guard first > 0, second > 0 else { return nil }
        let isMoney = units.contains("money")
        func show(_ size: Double) -> String { isMoney ? (size < 100 ? "\(written(size))p" : pounds(size / 100)) : "\(written(size)) g" }
        let values = [names[0]: first, names[1]: second]
        // What's asked for: one of them, or both.
        guard let asked = groups(#"(?:work out|find|calculate) the (?:cost|price|mass|weight) of (?:a|an|one|1|each) ([a-z ]+?)(?: and the (?:cost|price|mass|weight) of (?:a|an|one|1|each) ([a-z ]+?))?(?:\.|$)"#, in: question.text) else { return nil }
        let wanted = [asked[1], asked[2]].filter { !$0.isEmpty }.map(key)
        guard wanted.allSatisfy({ values[$0] != nil }), Set(wanted).count == wanted.count else { return nil }
        func line(_ row: (parts: [String: Double], total: Double)) -> MathLine {
            MathLine(.symbol(names.compactMap { name in row.parts[name].map { "\(written($0)) × \(shown[name] ?? name)" } }.joined(separator: " + ")), .symbol(show(row.total)))
        }
        let lead = [Step("Write what's known as two sums", "", [line(rows[0]), line(rows[1])]),
                    Step("Find one, then the other", b == 0 || c == 0 || a == 0 || d == 0 ? "One of them gives the \(isMoney ? "cost" : "mass") of one thing straight away. Put that into the other." : "Multiply them up until both have the same number of one thing, and take one from the other: that leaves only the other thing.",
                         names.map { MathLine(.symbol("1 \(shown[$0] ?? $0)"), .symbol(show(values[$0]!))) })]
        let answers = wanted.map { MathLine(.symbol(wanted.count == 1 ? show(values[$0]!) : "\(shown[$0] ?? $0) \(show(values[$0]!))")) }
        return told(found.map { $0[0] }.joined(separator: "; "), wanted.count == 1 ? answers : [MathLine(.symbol(wanted.map { "\(shown[$0] ?? $0) \(show(values[$0]!))" }.joined(separator: ", ")))], lead)
    }

    // MARK: Functions, scales, chances and other short questions

    private static func shorts(_ text: String, _ question: Question) -> Problem? {
        let ask = #"(?:work out|find|calculate|write down|what is|circle)"#
        // "f(x) = x - 3, g(x) = 4x - 7. Work out the value of fg(6)"
        if let asked = groups(#"(?:work out|find|calculate|evaluate|circle)(?: the value of)? ([fgh]{1,2})\((-?\d+(?:\.\d+)?)\)(?! ?[+×*/=^]| - |-| ?x ?[\d(])"#, in: text), var current = value(asked[2]) {
            let written = every(#"\b([fgh])\(x\) ?= ?(.+?)(?= and [fgh]\(x\) ?=| [fgh]\(x\) ?=| work out| find| calculate| evaluate| circle| solve| show|\.(?: |$)|$)"#, in: text)
            var bodies: [String: Expr] = [:]
            for rule in written {
                guard let body = sum(raised(rule[2])), body.symbols.isSubset(of: ["x"]), bodies[rule[1].lowercased()] == nil else { return nil }
                bodies[rule[1].lowercased()] = body
            }
            var lines: [MathLine] = []
            for name in asked[1].lowercased().reversed() {
                guard let body = bodies[String(name)] else { return nil }
                let next = Simplify.run(body.substituting("x", with: current))
                guard next.symbols.isEmpty else { return nil }
                lines.append(MathLine(.symbol("\(name)(\(Format.text(current)))"), next))
                current = next
            }
            return made(current, decimals: false, [Step(asked[1].count == 2 ? "Work from the inside out" : "Put the number in for x", asked[1].count == 2 ? "\(asked[1])(\(asked[2])) means \(asked[1].suffix(1)) first, then \(asked[1].prefix(1)) of what that gives." : "", lines)])
        }
        // "A map has a scale of 1 : 20000. Two churches are 15 cm apart on the map. Work out the actual distance, in kilometres."
        if let scale = groups(#"\bscale (?:of |is )?1 ?: ?(\d+)(?!\d|\.\d)"#, in: text), let times = Double(scale[1]), times > 1,
           has(#"\bactual\b|\breal\b|\brepresented\b|\breal life\b"#, text) {
            let onMap = every(#"(\d+(?:\.\d+)?) ?(cm|mm|centimetres|millimetres)\b(?: apart| long)? on the (?:map|plan|drawing|model)"#, in: text)
            guard onMap.count == 1, let size = Double(onMap[0][1]), let from = unit(onMap[0][2]),
                  let wanted = groups(#"(?:answer in|how many) (kilometres|metres|centimetres|km|m|cm)\b"#, in: text), let to = unit(wanted[1]) else { return nil }
            let real = size * times
            return made(plain(real * from.size / to.size), decimals: true,
                        [Step("Multiply by the scale", "Every \(onMap[0][2]) on the map is \(scale[1]) \(onMap[0][2]) for real.", [MathLine(.symbol("\(onMap[0][1]) × \(scale[1])"), .symbol("\(Worded.written(real)) \(onMap[0][2])"))]),
                         Step("Change the units", "\(Worded.written(real)) \(onMap[0][2]) in \(wanted[1]).")])
        }
        // "P(lands on 6) = 0.38. The dice is rolled 150 times. How many times would you expect the dice not to land on 6?"
        if let chance = groups(#"\bP\(([a-z0-9 ]+)\) ?= ?(0?\.\d+)(?!\d|\.\d)"#, in: text), every(#"\bP\("#, in: text).count == 1, let times = groups(#"\b(?:rolled|thrown|spun|flipped|tossed|played) (\d+) times"#, in: text),
           let asked = groups(#"how many times would you expect [^?.]*|(?:work out|find|circle|what is) the expected number of [^?.]*"#, in: text), let p = exact(chance[2]), let n = value(times[1]) {
            // The same thing that the probability is of, with "not" or without.
            func stems(_ words: String) -> [String] { words.lowercased().split(separator: " ").map { single(String($0)) }.filter { !["the", "a", "it", "to", "dice", "coin", "spinner", "not", "doe", "will"].contains($0) } }
            let event = stems(chance[1]), said = stems(asked[0])
            guard !event.isEmpty, event.allSatisfy(said.contains) else { return nil }
            let isNot = has(#"\bnot\b|n't\b"#, asked[0])
            let each = isNot ? Expr.one - p : p
            return made(each * n, decimals: true,
                        [Step(isNot ? "Find the chance of it not happening" : "Use the chance of it happening", isNot ? "The chances of it happening and not happening add up to 1." : "", [MathLine(.symbol(isNot ? "P(not \(chance[1]))" : "P(\(chance[1]))"), Simplify.run(each))]),
                         Step("Multiply by how many times", "Out of \(times[1]) goes, that fraction of them is expected.")])
        }
        // "Write 18 out of 30 as a fraction in its simplest form."
        if let found = groups(#"(?:write|express|give) (\d+) out of (\d+) as a (fraction|percentage|decimal)"#, in: text), let top = value(found[1]), let bottom = value(found[2]), amount(bottom) ?? 0 > 0 {
            switch found[3].lowercased() {
            case "fraction": return made(top / bottom, decimals: false, [Step("Write one over the other", "Then cancel down.")])
            case "decimal": return made(top / bottom, decimals: true, [Step("Divide the first by the second", "")])
            default: return made(top / bottom * .integer(100), decimals: true, [Step("Write it as a fraction, then a percentage", "Divide the first by the second, and multiply by 100.")])
            }
        }
        // "Between which two consecutive integers does the square root of 210 lie?"
        if let found = groups(#"between which two consecutive (?:integers|whole numbers) does the (square|cube) root of (\d+) lie"#, in: text), let n = Int(found[2]), n > 0, n < 1_000_000_000 {
            let isSquare = found[1].lowercased() == "square"
            var low = Int((isSquare ? Double(n).squareRoot() : cbrt(Double(n))).rounded(.down))
            func raise(_ k: Int) -> Int { isSquare ? k * k : k * k * k }
            while raise(low) > n { low -= 1 }
            while raise(low + 1) <= n { low += 1 }
            guard raise(low) != n else { return nil }
            return told("\(found[1]) root of \(n)", [MathLine(.symbol("\(low) and \(low + 1)"))],
                        [Step("Find the \(found[1]) numbers either side", "\(n) is between them, so its \(found[1]) root is between \(low) and \(low + 1).",
                              [MathLine(.symbol("\(low)\(isSquare ? "²" : "³")"), .integer(raise(low))), MathLine(.symbol("\(low + 1)\(isSquare ? "²" : "³")"), .integer(raise(low + 1)))])])
        }
        // "A sector has radius 12 cm and angle 60°. Work out the length of the arc."
        if let found = groups(#"\bsector (?:has|with|of) (?:a )?radius (?:of )?(\d+(?:\.\d+)?) ?(?:mm|cm|m)? and (?:an? )?(?:angle|centre angle|central angle) (?:of )?(\d+(?:\.\d+)?) ?°"#, in: text),
           let asked = groups("\(ask) the (length of the arc|arc length|area of the sector|area)", in: text) {
            let exactly = wantsPi(text)
            let isArc = asked[1].lowercased().contains("arc")
            guard let expr = sum(isArc ? "\(found[2])/360*2*π*\(found[1])" : "\(found[2])/360*π*\(found[1])^2") else { return nil }
            return made(expr, decimals: !exactly,
                        [Step("Find the fraction of the circle", "The angle is \(found[2])° out of 360°."),
                         Step(isArc ? "Take that fraction of the circumference" : "Take that fraction of the circle's area", isArc ? "The circumference is 2 × π × radius." : "The area of the whole circle is π × radius².",
                              [MathLine(.symbol(isArc ? "\(found[2])/360 × 2 × π × \(found[1])" : "\(found[2])/360 × π × \(found[1])²"))])])
        }
        // "Each bottle costs 75p. Work out the greatest number of bottles that can be bought with £5"
        let price = #"(?:£(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?) ?p\b)"#
        if let each = groups(#"\b(?:each|one|a) ([a-z]+) costs \#(price)"#, in: question.money),
           let have = groups(#"(?:greatest|largest|maximum) number of ([a-z]+) that can be bought (?:with|for) \#(price)"#, in: question.money),
           single(each[1]) == single(have[1]), every(price, in: question.money).count == 2,
           let cost = Double(each[2].isEmpty ? each[3] : each[2]).map({ each[2].isEmpty ? $0 : $0 * 100 }), let money = Double(have[2].isEmpty ? have[3] : have[2]).map({ have[2].isEmpty ? $0 : $0 * 100 }), cost > 0 {
            let most = (money / cost + 1e-9).rounded(.down)
            return made(plain(most), decimals: false,
                        [Step("See how many times the cost goes into the money", "\(Worded.written(money))p ÷ \(Worded.written(cost))p is \(Worded.written(money / cost)).", []),
                         Step("Round down", "Part of one can't be bought, and \(Worded.written(most)) cost \(Worded.written(most * cost))p.")])
        }
        // "Write the temperatures in order, starting with the coldest." -5 3 -7 -1
        if has(#"\b(?:write|put|list|arrange)\b[^.?]*\bin (?:ascending |descending )?order\b"#, text) {
            let up = has(#"starting with the (?:smallest|lowest|least|coldest)|from (?:the )?(?:smallest|lowest|least|coldest)|(?:smallest|lowest|coldest) first|\bascending\b"#, text)
            let down = has(#"starting with the (?:largest|biggest|highest|greatest|warmest|hottest)|from (?:the )?(?:largest|biggest|highest|greatest|warmest|hottest)|(?:largest|biggest|highest|hottest) first|\bdescending\b"#, text)
            guard up != down, question.lists.count == 1, question.lists[0].count <= 12 else { return nil }
            let pairs = question.lists[0].compactMap { token in value(token).flatMap(amount).map { (token, $0) } }
            guard pairs.count == question.lists[0].count, Set(pairs.map(\.1)).count == pairs.count else { return nil }
            let sorted = pairs.sorted { up ? $0.1 < $1.1 : $0.1 > $1.1 }.map { $0.0.replacingOccurrences(of: "-", with: "−") }
            return told(question.lists[0].joined(separator: " "), [MathLine(.symbol(sorted.joined(separator: ", ")))],
                        [Step("Compare them", pairs.contains { $0.1 < 0 } ? "Negative numbers are smaller the bigger they look: −7 is less than −5." : "Line up the decimal points and compare digit by digit from the left.")])
        }
        // "T = 5P - W. Work out the value of T when P = 4 and W = 2"
        if let asked = groups(#"(?:work out|find|calculate) the value of ([A-Za-z]) when ([A-Za-z]) ?= ?(- ?\d+(?:\.\d+)?|\#(number))(?: and ([A-Za-z]) ?= ?(- ?\d+(?:\.\d+)?|\#(number)))?(?!\d|\.\d)"#, in: text) {
            var values: [String: Expr] = [:]
            for (letter, size) in [(asked[2], asked[3]), (asked[4], asked[5])] where !letter.isEmpty {
                guard let size = value(size), values[letter] == nil, letter != asked[1] else { return nil }
                values[letter] = size
            }
            let letters = Set(values.keys).union([asked[1]])
            // The one formula that joins exactly these letters.
            var formulas: [(left: Expr, right: Expr, text: String)] = []
            for found in every(#"(?<![A-Za-z])([A-Za-z]) ?= ?([^=]+?)(?= [A-Za-z] ?=|\.(?: |$)|$| work out| find| calculate| when| where| and [A-Za-z] ?=)"#, in: text) {
                guard let right = sum(raised(found[2])), !right.symbols.isEmpty, right.symbols.union([found[1]]) == letters, !right.symbols.contains(found[1]) else { continue }
                if !formulas.contains(where: { $0.text == found[0] }) { formulas.append((.symbol(found[1]), right, found[0])) }
            }
            guard formulas.count == 1, let formula = formulas.first else { return nil }
            var left = formula.left, right = formula.right
            for (letter, size) in values { left = left.substituting(letter, with: size); right = right.substituting(letter, with: size) }
            let lead = [Step("Put the numbers into the formula", formula.text, [MathLine(Simplify.run(left), right)])]
            if left == .symbol(asked[1]) { return made(right, decimals: has(#"\d\.\d"#, text), lead) }
            var problem = Problem(kind: .solve([Equation(left: left, right: right)], unknowns: [asked[1]]), text: "", usesDecimals: false)
            problem.lead = lead
            return problem
        }
        return nil
    }

    // MARK: Proportion with more than one relation, and its equation

    /// "P is directly proportional to Q. When P = 8, Q = 2. R is inversely proportional to Q².
    /// When R = 10, Q = 3. Work out the value of R when P = 0.5", and "Work out an equation
    /// connecting d and v". (One relation with a value to find is `Proportion`'s.)
    static func proportions(_ input: String) -> Problem? {
        guard let question = read(input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        var problem = proportion(question.text, single: false)
        problem?.text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return problem
    }

    private static func proportion(_ text: String, single: Bool) -> Problem? {
        let pattern = #"\b([A-Za-z]) ?is (directly |inversely )?proportional to (the square of |the cube of |the square root of |the cube root of )?([√∛]\(?)?([A-Za-z])\)?(?:\^?\(?(\d)\)?)?(?=$|[ ,;:]|\.(?: |$))"#
        // (What a relation ends on has to end cleanly: "x?" is an x whose power wasn't read, and the count below then stops it.)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // Every relation in the question has to be understood: one left out gives an answer in the wrong letter.
        guard !matches.isEmpty, matches.count <= 3, every(#"\bproportional\b"#, in: text).count == matches.count else { return nil }
        // Values given once for all the relations, after the last of them: "Given that h = 10 and t = 144 when p = 6".
        var shared = Range(matches[matches.count - 1].range, in: text).map { String(text[$0.upperBound...]) } ?? ""
        if let asking = shared.range(of: #"\b(?:work out|find|calculate|write)\b"#, options: [.regularExpression, .caseInsensitive]) { shared = String(shared[..<asking.lowerBound]) }
        struct Relation { var y: String; var x: String; var power: Expr; var constant: Expr; var shown: Expr }
        var relations: [Relation] = []
        var lead: [Step] = []
        for (index, match) in matches.enumerated() {
            func piece(_ group: Int) -> String { Range(match.range(at: group), in: text).map { String(text[$0]) } ?? "" }
            let y = piece(1), x = piece(5)
            guard y != x, let whole = Range(match.range, in: text) else { return nil }
            var power: Expr = .one
            switch piece(3).lowercased().trimmingCharacters(in: .whitespaces) {
            case "the square of": power = .two
            case "the cube of": power = .integer(3)
            case "the square root of": power = .half
            case "the cube root of": power = Expr.one / .integer(3)
            default:
                if piece(4).hasPrefix("√") { power = .half } else if piece(4).hasPrefix("∛") { power = Expr.one / .integer(3) } else if let digit = Int(piece(6)) { power = .integer(digit) }
            }
            // One way of saying the power, not two.
            guard [piece(3), piece(4), piece(6)].filter({ !$0.isEmpty }).count <= 1 else { return nil }
            if piece(2).lowercased().hasPrefix("inverse") { power = Simplify.run(-power) }
            // Its pair of values: the first of each letter after it, before the next relation.
            let end = index + 1 < matches.count ? Range(matches[index + 1].range, in: text)!.lowerBound : text.endIndex
            var after = String(text[whole.upperBound..<end])
            func given(_ letter: String) -> Expr? {
                groups("(?<![A-Za-z])(?-i:\(letter)) ?= ?(\(number))(?!\\d|\\.\\d)", in: after).flatMap { exact($0[1]) }
            }
            // With no values of its own, the ones given for all of them: each letter once.
            if index + 1 < matches.count, given(y) == nil, given(x) == nil {
                guard [y, x].allSatisfy({ every("(?<![A-Za-z])(?-i:\($0)) ?= ?\(number)", in: shared).count == 1 }) else { return nil }
                after = shared
            }
            var y0 = given(y), x0 = given(x)
            // "G : H = 3 : 2 when H = 16": G is 3/2 of 16.
            if let ratio = groups("(?<![A-Za-z])(?-i:\(y)) ?: ?(?-i:\(x)) ?= ?(\\d+(?:\\.\\d+)?) ?: ?(\\d+(?:\\.\\d+)?) when (?-i:\(x)) ?= ?(\(number))(?!\\d|\\.\\d)", in: after),
               let top = exact(ratio[1]), let bottom = exact(ratio[2]), let size = exact(ratio[3]), amount(bottom) ?? 0 > 0 {
                x0 = size
                y0 = Simplify.run(top / bottom * size)
            }
            guard let y0, let x0, amount(x0) ?? 0 > 0 else { return nil }
            _ = (y0, x0)
            let constant = Simplify.run(y0 / .power(x0, power))
            guard constant.number != nil, amount(constant) ?? 0 != 0 else { return nil }
            let shown = Simplify.run(constant * .power(.symbol(x), power))
            relations.append(Relation(y: y, x: x, power: power, constant: constant, shown: shown))
            let inverse = amount(power) ?? 0 < 0
            lead.append(Step("Write \(y) in terms of \(x)", "\(y) is \(inverse ? "inversely " : "")proportional to \(Format.text(Simplify.run(.power(.symbol(x), inverse ? Simplify.run(-power) : power)))), so \(y) = k \(inverse ? "÷" : "×") \(Format.text(Simplify.run(.power(.symbol(x), inverse ? Simplify.run(-power) : power)))). Put in \(y) = \(Format.text(y0)) and \(x) = \(Format.text(x0)) to find k.",
                             [MathLine(.symbol("k"), constant), MathLine(.symbol(y), shown)]))
        }
        // What each letter stands for: "The mass of an ornament is m grams. The height of the ornament is h centimetres."
        var letters: [String: String] = [:]
        for found in every(#"\bthe ([a-z]+) of [a-z ]+? is (?-i:([A-Za-z])) [a-z]+"#, in: text) { letters[found[1].lowercased()] = found[2] }
        // "Work out the mass of an ornament of height 12 centimetres": the letters by their names.
        var byName: [String]?
        if let named = groups("(?:work out|find|calculate) the ([a-z]+) of [a-z ]+? (?:of|with|when the|that has|which has)(?: an?| the)? ?([a-z]+)(?: is| of)? (\(number))(?!\\d|\\.\\d)", in: text),
           let target = letters[named[1].lowercased()], let known = letters[named[2].lowercased()] { byName = ["", target, known, named[3]] }
        // "Find a formula for h in terms of t", with p between them: one formula put into the other.
        if relations.count >= 2, let wanted = groups(#"(?:work out|find|write down|write|give) (?:an equation|a formula|an expression) for (?-i:([A-Za-z])) in terms of (?-i:([A-Za-z]))(?![A-Za-z])"#, in: text), wanted[1] != wanted[2],
           let whole = text.range(of: wanted[0], options: .caseInsensitive) {
            guard byName == nil, !has(#"\b(?:work out|find|calculate|how (?:much|many|far|long))\b"#, String(text[whole.upperBound...])) else { return nil }
            // Each letter as a number times a power of the letter asked for.
            var known: [String: (constant: Expr, power: Expr)] = [wanted[2]: (.one, .one)]
            for _ in relations {
                for relation in relations {
                    if let x = known[relation.x], known[relation.y] == nil {
                        let constant = Simplify.run(relation.constant * .power(x.constant, relation.power))
                        guard constant.number != nil else { return nil }
                        known[relation.y] = (constant, Simplify.run(x.power * relation.power))
                    } else if let y = known[relation.y], known[relation.x] == nil {
                        guard amount(relation.power) ?? 0 != 0, amount(y.constant / relation.constant) ?? 0 > 0 else { return nil }
                        let turned = Simplify.run(Expr.one / relation.power)
                        let constant = Simplify.run(.power(y.constant / relation.constant, turned))
                        guard constant.number != nil else { return nil }
                        known[relation.x] = (constant, Simplify.run(y.power * turned))
                    }
                }
            }
            guard let found = known[wanted[1]], relations.contains(where: { $0.y == wanted[1] || $0.x == wanted[1] }) else { return nil }
            let shown = Simplify.run(found.constant * .power(.symbol(wanted[2]), found.power))
            let between = Set(relations.flatMap { [$0.y, $0.x] }).subtracting([wanted[1], wanted[2]]).sorted()
            return told("\(wanted[1]) in terms of \(wanted[2])", [MathLine(.symbol(wanted[1]), shown)],
                        lead + [Step("Put one formula into the other", "Swap \(between.joined(separator: " and ")) for what \(between.count == 1 ? "it is" : "they are") in terms of \(wanted[2]), so only \(wanted[2]) is left.", [MathLine(.symbol(wanted[1]), shown)])])
        }
        // A formula asked for in a letter that none of the relations has can't be given.
        if let named = groups(#"(?:an equation|a formula|an expression)(?: connecting| linking| for) (?-i:([A-Za-z]))(?: and| in terms of) (?-i:([A-Za-z]))(?![A-Za-z])"#, in: text),
           !(relations.count == 1 && Set([named[1], named[2]]) == Set([relations[0].y, relations[0].x])) { return nil }
        // "Work out an equation connecting d and v", when that is all that's asked.
        if relations.count == 1, let equation = groups(#"(?:work out|find|write down|write|give) (?:an equation|a formula|an expression)(?: connecting| linking| for) "#, in: text),
           let whole = text.range(of: equation[0], options: .caseInsensitive) {
            // (With another part's question after it, which of the two is pointed at isn't known here.)
            guard byName == nil, !has(#"\b(?:work out|find|calculate|how (?:much|many|far|long))\b"#, String(text[whole.upperBound...])) else { return nil }
            return told("\(relations[0].y) and \(relations[0].x)", [MathLine(.symbol(relations[0].y), relations[0].shown)], lead)
        }
        // "Work out G : H when H = 100": the ratio of the two at that value.
        if relations.count == 1, let asked = groups("(?:work out|find) (?-i:\(relations[0].y)) ?: ?(?-i:\(relations[0].x)) when (?-i:\(relations[0].x)) ?= ?(\(number))(?!\\d|\\.\\d)", in: text),
           let x = exact(asked[1]), amount(x) ?? 0 > 0 {
            let y = Simplify.run(relations[0].constant * .power(x, relations[0].power))
            guard case .number(.exact(let ratio)) = Simplify.run(y / x), ratio.numerator > 0 else { return nil }
            return told("\(relations[0].y) : \(relations[0].x)", [MathLine(.symbol("\(ratio.numerator) : \(ratio.denominator)"))],
                        lead + [Step("Find \(relations[0].y) when \(relations[0].x) = \(asked[1])", "", [MathLine(.symbol(relations[0].y), y)]),
                                Step("Write the ratio in its simplest form", "", [MathLine(.symbol("\(Format.text(y)) : \(asked[1])"), .symbol("\(ratio.numerator) : \(ratio.denominator)"))])])
        }
        // "Work out the value of R when P = 0.5": from one letter to the next along the relations.
        // (One relation with a value to find is `Proportion`'s, which is tried first; it comes here when its sentences were cut short.)
        guard relations.count >= (single || byName != nil ? 1 : 2), let asked = byName ?? groups("(?:work out|find|calculate) (?:the value of )?([A-Za-z]) when ([A-Za-z]) ?= ?(\(number))(?!\\d|\\.\\d)", in: text),
              let start = exact(asked[3]), asked[1] != asked[2] else { return nil }
        var known: [String: Expr] = [asked[2]: start]
        var lines: [MathLine] = []
        for _ in 0..<relations.count {
            for relation in relations {
                if let x = known[relation.x], known[relation.y] == nil {
                    let y = Simplify.run(relation.constant * .power(x, relation.power))
                    guard y.number != nil else { return nil }
                    known[relation.y] = y
                    lines.append(MathLine(.symbol(relation.y), y))
                } else if let y = known[relation.y], known[relation.x] == nil {
                    // Back from y to x: positive values, as lengths, times and amounts are.
                    guard let size = amount(y / relation.constant), size > 0, let power = amount(relation.power), power != 0 else { return nil }
                    let x = Simplify.run(.power(y / relation.constant, Simplify.run(Expr.one / relation.power)))
                    known[relation.x] = x.number != nil ? x : plain(pow(size, 1 / power))
                    lines.append(MathLine(.symbol(relation.x), known[relation.x]!))
                }
            }
        }
        guard let answer = known[asked[1]] else { return nil }
        return made(answer, decimals: false, lead + [Step("Go from \(asked[2]) to \(asked[1])", "Start with \(asked[2]) = \(asked[3]) and use each formula in turn.", lines)])
    }

    // MARK: Picking the right one of the choices

    private static func chosen(_ text: String) -> Problem? {
        // "Circle the number that is in standard form. 0.25 × 10⁴  6 × 10⁷  38 × 10⁻³  4 × 10^½"
        if let asked = groups(#"(?:circle|write down|choose) the (?:one |number )?(?:that is |which is )?(?:written )?in standard form|which (?:of these )?(?:numbers? )?is (?:written )?in standard form"#, in: text),
           let whole = text.range(of: asked[0], options: .caseInsensitive) {
            let offered = every(#"(-?\d+(?:\.\d+)?) ?[×x*] ?10\^?\(?(-?\d+(?:[./]\d+)?)\)?"#, in: String(text[whole.upperBound...]))
            let right = offered.filter { choice in
                guard let front = Double(choice[1]), choice[2].range(of: #"^-?\d+$"#, options: .regularExpression) != nil else { return false }
                return abs(front) >= 1 && abs(front) < 10
            }
            guard offered.count >= 2, right.count == 1, let front = Double(right[0][1]), let power = Int(right[0][2]) else { return nil }
            return told("in standard form", [MathLine(.symbol("\(written(front)) × 10\(raisedDigits(power))"))],
                        [Step("Check each one", "Standard form is a number from 1 up to 10, times a whole-number power of ten. Only \(written(front)) × 10\(raisedDigits(power)) is: the others start with a number that is too small or too big, or have a power that isn't a whole number.")])
        }
        // "Circle the calculation that increases 240 by 7.5%. 240 × 1.0705  240 × 1.705  240 × 1.075  240 × 1.75"
        if let asked = groups(#"calculation (?:that|which) (increases|decreases|reduces) (\d+(?:\.\d+)?) by (\d+(?:\.\d+)?) ?%"#, in: text), let whole = text.range(of: asked[0], options: .caseInsensitive),
           let size = Double(asked[2]), let rate = Double(asked[3]) {
            let up = asked[1].lowercased() == "increases"
            let multiplier = up ? 1 + rate / 100 : 1 - rate / 100
            let offered = every(#"(\d+(?:\.\d+)?) ?[×x*] ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: String(text[whole.upperBound...]))
            let right = offered.filter { Double($0[1]) == size && abs((Double($0[2]) ?? -1) - multiplier) < 1e-12 }
            guard offered.count >= 2, right.count == 1 else { return nil }
            return told(asked[0], [MathLine(.symbol("\(right[0][1]) × \(right[0][2])"))],
                        [Step("Find the multiplier", "\(up ? "Increasing" : "Decreasing") by \(asked[3])% is multiplying by 1 \(up ? "plus" : "take away") \(asked[3]) hundredths, which is \(written(multiplier)).")])
        }
        // "Which of these is the equation of a straight line? y = 6x²  y = x − 6  y = x² + 6  y = 6/x"
        if let asked = groups(#"which of these is the equation of a (straight line|circle)\??(?: circle your answer\.?)?(.*)$"#, in: text) {
            // One equation ends and the next starts where two terms stand side by side with no sign between.
            var equations: [String] = [], current = ""
            for token in raised(asked[2]).split(separator: " ").map(String.init) {
                let isSign = token.range(of: #"^[-+×*÷/=]$"#, options: .regularExpression) != nil
                let lastIsSign = current.isEmpty || current.range(of: #"[-+×*÷/=]$"#, options: .regularExpression) != nil
                if !isSign, !lastIsSign, token.range(of: #"^[-+×*÷/=]"#, options: .regularExpression) == nil { equations.append(current); current = token } else { current += (current.isEmpty ? "" : " ") + token }
            }
            equations.append(current)
            let wantsLine = asked[1].lowercased() != "circle"
            var right: [String] = [], read = 0
            for equation in equations {
                let sides = equation.split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                guard sides.count == 2, !sides[0].isEmpty, !sides[1].isEmpty, let left = sum(sides[0]), let other = sum(sides[1]),
                      left.symbols.union(other.symbols).isSubset(of: ["x", "y"]), !left.symbols.union(other.symbols).isEmpty else { continue }
                read += 1
                func at(_ x: Int, _ y: Int) -> Double? { amount((left - other).substituting("x", with: .integer(x)).substituting("y", with: .integer(y))) }
                guard let c = at(0, 0), let px = at(1, 0), let py = at(0, 1), let far = at(2, 3), let back = at(-1, 2), let mx = at(-1, 0), let my = at(0, -1), let corner = at(1, 1) else { continue }
                let a = px - c, b = py - c
                let isLine = (a != 0 || b != 0) && abs(far - (c + 2 * a + 3 * b)) < 1e-9 && abs(back - (c - a + 2 * b)) < 1e-9
                let isCircle = a != 0 && abs(a - b) < 1e-9 && abs(mx - px) < 1e-9 && abs(my - py) < 1e-9 && abs(corner - (c + 2 * a)) < 1e-9 && c / a < 0
                if wantsLine ? isLine : isCircle { right.append("\(Format.text(left)) = \(Format.text(other))") }
            }
            guard read >= 2, right.count == 1 else { return nil }
            return told(asked[0], [MathLine(.symbol(right[0]))],
                        [Step("Look at the powers", wantsLine ? "A straight line has x and y to the power 1 only: no x², no 1/x." : "A circle round the origin is x² + y² = r²: both squared, both added, equal to a positive number.")])
        }
        // "1/6, 1/7, 1/8 and 1/9 are four fractions. How many of these fractions convert to a recurring decimal?"
        if let asked = groups(#"how many of (?:these|the)(?: fractions)? (?:convert to|are|give|can be written as|become) (?:a )?recurring decimals?"#, in: text), let whole = text.range(of: asked[0], options: .caseInsensitive) {
            let fractions = every(#"(?<![\d/.])(\d+)/(\d+)(?!\d|[/.]\d)"#, in: String(text[..<whole.lowerBound]))
            guard fractions.count >= 2, fractions.count <= 8 else { return nil }
            if let stated = groups(#"\bare (\d+|[a-z]+) fractions"#, in: text), let howMany = count(stated[1]) { guard howMany == fractions.count else { return nil } }
            var lines: [MathLine] = []
            var recurring = 0
            for fraction in fractions {
                guard let top = Int(fraction[1]), let bottom = Int(fraction[2]), bottom > 0 else { return nil }
                let rest = primes(of: bottom / gcd(top, bottom)).filter { $0 != 2 && $0 != 5 }
                if !rest.isEmpty { recurring += 1 }
                lines.append(MathLine(.symbol("\(top)/\(bottom)"), .symbol(rest.isEmpty ? "ends" : "recurs (a \(rest[0]) in the bottom)"), relation: ":"))
            }
            return made(.integer(recurring), decimals: false, [Step("Look at the bottom of each fraction", "In its simplest form, a fraction ends as a decimal only if its bottom is made of 2s and 5s. Any other prime in the bottom makes it recur.", lines)])
        }
        // "Which of these is a geometric progression? 2, 4, 6, 8, 10 …"
        if let asked = groups(#"which of these is (?:a|an) (geometric|arithmetic) (?:progression|sequence)\??(?: circle your answer\.?)?(.*)$"#, in: text) {
            let lists = all("\(number)(?:, ?\(number)){2,}", in: asked[2])
            var right: [String] = []
            for list in lists {
                let sizes = all(number, in: list).compactMap { value($0).flatMap(amount) }
                guard sizes.count >= 3 else { return nil }
                let steps = zip(sizes.dropFirst(), sizes).map { $0 - $1 }
                let isArithmetic = steps.allSatisfy { abs($0 - steps[0]) < 1e-9 } && steps[0] != 0
                let ratios = sizes.allSatisfy { $0 != 0 } ? zip(sizes.dropFirst(), sizes).map { $0 / $1 } : []
                let isGeometric = !ratios.isEmpty && ratios.allSatisfy { abs($0 - ratios[0]) < 1e-9 } && ratios[0] != 1
                if asked[1].lowercased() == "geometric" ? isGeometric : isArithmetic { right.append(list) }
            }
            guard lists.count >= 2, right.count == 1 else { return nil }
            let isGeometric = asked[1].lowercased() == "geometric"
            return told(asked[0], [MathLine(.symbol(right[0].replacingOccurrences(of: "-", with: "−")))],
                        [Step("Check how each one goes on", isGeometric ? "A geometric progression multiplies by the same number each time." : "An arithmetic progression adds the same number each time.")])
        }
        // "y is 1 1/2 times x. Circle the ratio y : x", "The value of y is 20% more than the value of x. Circle the ratio x : y"
        if let asked = groups(#"\bratio (?:that is equivalent to |which is equivalent to )?([a-z]) ?: ?([a-z])\b"#, in: text), let whole = text.range(of: asked[0], options: .caseInsensitive) {
            var first = "", second = "", times: Expr?   // first = times × second
            if let found = groups(#"(?<![a-z])(\d*)([a-z]) ?is ?(\d+ \d+/\d+|\d+/\d+|\d+(?:\.\d+)?|two|three|four|five|six|seven|eight|nine|ten) times (?:bigger than |as big as |larger than |as large as |as much as )?(\d*)([a-z])\b"#, in: text) {
                var size: Expr?
                let pieces = found[3].split(separator: " ").map(String.init)
                if pieces.count == 2, let whole = exact(pieces[0]), let part = exact(pieces[1]) { size = whole + part } else { size = count(found[3]).map { Expr.integer($0) } ?? exact(found[3]) }
                guard let size, let front = found[1].isEmpty ? Expr.one : exact(found[1]), let back = found[4].isEmpty ? Expr.one : exact(found[4]) else { return nil }
                (first, second, times) = (found[2], found[5], Simplify.run(size * back / front))
            } else if let found = groups(#"(?:value of )?(?<![a-z])([a-z]) is (\d+(?:\.\d+)?) ?% (more|greater|bigger|larger|less|smaller) than (?:the value of )?([a-z])\b"#, in: text), let rate = exact(found[2]) {
                let up = ["more", "greater", "bigger", "larger"].contains(found[3].lowercased())
                (first, second, times) = (found[1], found[4], Simplify.run(up ? Expr.one + rate / .integer(100) : Expr.one - rate / .integer(100)))
            }
            guard let times, case .number(.exact(let rational)) = times, rational.numerator > 0, first != second,
                  Set([asked[1].lowercased(), asked[2].lowercased()]) == Set([first.lowercased(), second.lowercased()]) else { return nil }
            // first : second = top : bottom
            let forward = asked[1].lowercased() == first.lowercased()
            let left = forward ? rational.numerator : rational.denominator, right = forward ? rational.denominator : rational.numerator
            // With ratios to choose from, it has to be one of them.
            let offered = every(#"(\d+) ?: ?(\d+)(?!\d|\.\d)"#, in: String(text[whole.upperBound...]))
            if offered.count >= 2 { guard offered.contains(where: { (Int($0[1]) ?? 0) * right == (Int($0[2]) ?? 0) * left && Int($0[1]) != 0 }) else { return nil } }
            return told(asked[0], [MathLine(.symbol("\(left) : \(right)"))],
                        [Step("Give \(second) a size and find \(first)", "If \(second) is \(rational.denominator), \(first) is \(Format.text(times)) times that, which is \(rational.numerator).", [MathLine(.symbol("\(first) : \(second)"), .symbol("\(rational.numerator) : \(rational.denominator)"))])])
        }
        return nil
    }

    // MARK: Chances over two goes

    private static func chances(_ text: String) -> Problem? {
        var chance: Expr?, event = "", what = "", inDecimals = false
        // "P(6) = 3/5", "P(gold) = 0.05": one thing with its chance, tried twice with the chance staying the same.
        if let stated = groups(#"\bP\(([a-z0-9 ]+)\) ?= ?(\d+/\d+|0?\.\d+)(?!\d|[./]\d)"#, in: text), every(#"\bP\("#, in: text).count == 1,
           has(#"\btwice\b|\ba second\b|\btwo (?:cards|counters|balls|discs|spins|throws|rolls|times)\b"#, text), has(#"\breplace[sd]?\b|\bdice\b|\bspinner\b|\bcoin\b"#, text), !has(#"without replac|not replaced|does not replace"#, text) {
            chance = exact(stated[2])
            inDecimals = stated[2].contains(".")
            let words = ["1": "one", "2": "two", "3": "three", "4": "four", "5": "five", "6": "six"]
            event = words[stated[1]] ?? stated[1].lowercased()
            what = stated[1]
        }
        // "Two ordinary fair dice are rolled … both dice land on a number less than 3"
        var which = ""
        if chance == nil, has(#"\b(?:two|2) (?:ordinary |fair |six-sided )*(?:ordinary|fair) (?:six-sided )?dice\b"#, text),
           let asked = groups(#"probability that (both|exactly one of the|only one of the|at least one of the|neither of the) dice lands? on (?:a |an )?(number (less|greater|more) than (\d)|(even|odd|prime|square) number|(six|6))"#, in: text) {
            let faces = (1...6).filter { face in
                if !asked[3].isEmpty, let limit = Int(asked[4]) { return asked[3].lowercased() == "less" ? face < limit : face > limit }
                switch asked[5].lowercased() {
                case "even": return face % 2 == 0
                case "odd": return face % 2 == 1
                case "prime": return isPrime(face)
                case "square": return isSquare(face)
                default: return face == 6
                }
            }
            guard !faces.isEmpty, faces.count < 6 else { return nil }
            chance = Expr.integer(faces.count) / .integer(6)
            which = asked[1].lowercased()
            what = asked[2]
        } else if let p = chance {
            // What's asked about the two goes.
            guard let asked = groups(#"probability (?:of|that) [^?.]*"#, in: text.replacingOccurrences(of: #"\bP\([^)]*\) ?= ?[\d./]+"#, with: "", options: .regularExpression))?[0].lowercased(),
                  asked.split(separator: " ").contains(where: { single(String($0)) == single(event) }), amount(p) ?? 2 < 1 else { return nil }
            if has(#"\bat least one\b"#, asked) { which = "at least one" }
            else if has(#"\bexactly one\b|\bonly one\b"#, asked) { which = "exactly one" }
            else if has(#"\bneither\b|\bno \b"#, asked) { which = "neither" }
            else if has(#"\bboth\b|\btwo\b|\b2\b"#, asked) { which = "both" }
            else { return nil }
        }
        guard let p = chance, !which.isEmpty else { return nil }
        let q = Simplify.run(Expr.one - p)
        let lead = Step("Find the chance for one go", "P(\(what)) = \(Format.text(Simplify.run(p))), so the chance of it not happening is \(Format.text(q)). The two goes don't change each other, so their chances multiply.")
        switch which.split(separator: " ").first.map(String.init) ?? "" {
        case "both": return made(p * p, decimals: inDecimals, [lead, Step("Both", "It has to happen the first time and the second time.")])
        case "at": return made(Expr.one - q * q, decimals: inDecimals, [lead, Step("At least one", "That's everything except neither: 1 take away the chance of it not happening twice.")])
        case "exactly", "only": return made(.two * p * q, decimals: inDecimals, [lead, Step("Exactly one", "It happens the first time and not the second, or the other way round: two ways, each with the same chance.")])
        default: return made(q * q, decimals: inDecimals, [lead, Step("Neither", "It has to not happen the first time and not happen the second time.")])
        }
    }

    // MARK: More sums in words

    private static let polygons = ["triangle": 3, "quadrilateral": 4, "square": 4, "pentagon": 5, "hexagon": 6, "heptagon": 7, "octagon": 8, "nonagon": 9, "decagon": 10, "dodecagon": 12]

    /// "six million five thousand two hundred" as 6005200.
    private static func spoken(_ words: String) -> Int? {
        let small = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
                     "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        var total = 0, current = 0, any = false
        for word in words.lowercased().replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init) where word != "and" {
            if let size = small[word] { current += size }
            else if word == "hundred" { guard current > 0 else { return nil }; current *= 100 }
            else if word == "thousand" || word == "million" { guard current > 0 else { return nil }; total += current * (word == "thousand" ? 1000 : 1_000_000); current = 0 }
            else { return nil }
            any = true
        }
        return any ? total + current : nil
    }

    private static func more(_ text: String, _ question: Question) -> Problem? {
        let pair = #"\(\s?(\#(number)) ?, ?(\#(number))\s?\)"#
        let ask = #"(?:work out|find|calculate|write down|what is|what are)"#
        // "3/5 of a number is 162. Work out the number."
        if let found = groups(#"(\d+/\d+|\d+(?:\.\d+)? ?%) of (?:a|the|my|her|his) number is (\#(number))(?!\d|\.\d)"#, in: text), has("\(ask) the number\\b", text), let total = exact(found[2]) {
            let isPercent = found[1].hasSuffix("%")
            guard let part = isPercent ? exact(String(found[1].dropLast()).trimmingCharacters(in: .whitespaces)).map({ $0 / .integer(100) }) : value(found[1]), amount(part) ?? 0 > 0 else { return nil }
            return made(total / part, decimals: false, [Step("Undo the \(isPercent ? "percentage" : "fraction")", "\(found[1]) of the number is \(found[2]), so the number is \(found[2]) divided by \(found[1]).")])
        }
        // "Write the number six million five thousand two hundred in standard form."
        if let found = groups(#"(?:write|express) (?:the number )?((?:[a-z]+[- ])+?[a-z]+) in (standard form|figures|digits)"#, in: text), let size = spoken(found[1]), size > 0 {
            let lead = Step("Write it in figures", "", [MathLine(.symbol(found[1]), .integer(size))])
            return found[2].lowercased() == "standard form" ? told(found[1], [MathLine(.symbol(standard(Double(size))))], [lead, Step("Write it in standard form", standardWords)]) : made(.integer(size), decimals: false, [lead])
        }
        // "£500 into an account that pays compound interest. At least £560 after 3 years. Work out to 1 decimal place the minimum annual interest rate."
        if has("compound interest", text), has(#"minimum (?:annual )?(?:interest )?rate"#, text), let start = groups(#"\b(?:puts?|invests?|deposits?|saves?) (\#(number)) (?:in|into)\b"#, in: text),
           let goal = groups(#"at least (\#(number)) [a-z ]*?after (\d+|[a-z]+) years"#, in: text), let places = groups(#"to (\d) decimal places?"#, in: text).flatMap({ Int($0[1]) }),
           let from = Double(start[1]), let to = Double(goal[1]), let years = count(goal[2]), from > 0, to > from, years >= 1 {
            let rate = (pow(to / from, 1 / Double(years)) - 1) * 100
            let scale = pow(10, Double(places))
            // The least rate that gets there: rounded up, since rounding down falls short.
            let enough = (rate * scale - 1e-9).rounded(.up) / scale
            return made(plain(enough), decimals: true,
                        [Step("Find the multiplier for one year", "\(start[1]) × multiplier\(raisedDigits(years)) has to reach \(goal[1]), so the multiplier is the \(years == 2 ? "square" : (years == 3 ? "cube" : "\(years)th")) root of \(goal[1]) ÷ \(start[1]).", [MathLine(.symbol("multiplier"), plain(pow(to / from, 1 / Double(years))))]),
                         Step("Write it as a rate, rounding up", "That's \(written((rate * 10000).rounded() / 10000))% a year. Rounding down wouldn't reach \(goal[1]), so the least rate to \(places) decimal place\(places == 1 ? "" : "s") is \(written(enough))%.")])
        }
        // Points with their letters: "A (-5, 9)", "C is (3, -7)".
        var named: [String: (x: Expr, y: Expr)] = [:]
        var clashing = Set<String>()
        for found in every("(?<![A-Za-z])(?-i:([A-Z])) ?(?:is|=|is the point|has coordinates)? ?\(pair)", in: text) {
            guard let x = value(found[2]), let y = value(found[3]) else { continue }
            if let before = named[found[1]], before.x != x || before.y != y { clashing.insert(found[1]) }
            named[found[1]] = (x, y)
        }
        for name in clashing { named[name] = nil }
        func coordinate(_ value: Expr) -> String {
            let tidy = Simplify.run(value)
            if let size = amount(tidy), abs(size * 1000 - (size * 1000).rounded()) < 1e-9 { return written(size) }
            return Format.text(tidy)
        }
        // "A(-5, 9), B and C(3, -7) are on a straight line. AB : BC = 1 : 3. Work out the coordinates of B."
        if let ratio = groups(#"(?-i:\b([A-Z])([A-Z]) ?: ?([A-Z])([A-Z])) ?= ?(\d+) ?: ?(\d+)(?!\d|\.\d| ?:)"#, in: text), ratio[2] == ratio[3], ratio[1] != ratio[4],
           has("coordinates of (?:point )?(?-i:\(ratio[2]))\\b", text), has(#"straight line|line segment|\bline\b"#, text), let from = named[ratio[1]], let to = named[ratio[4]], named[ratio[2]] == nil,
           let near = Int(ratio[5]), let far = Int(ratio[6]), near > 0, far > 0 {
            let part = Expr.integer(near) / .integer(near + far)
            let x = from.x + part * (to.x - from.x), y = from.y + part * (to.y - from.y)
            return told("\(ratio[1])\(ratio[2]) : \(ratio[3])\(ratio[4]) = \(near) : \(far)", [MathLine(.symbol("(\(coordinate(x)), \(coordinate(y)))"))],
                        [Step("See how far along \(ratio[2]) is", "\(ratio[1])\(ratio[2]) is \(near) part\(near == 1 ? "" : "s") out of \(near + far), so \(ratio[2]) is \(near)/\(near + far) of the way from \(ratio[1]) to \(ratio[4])."),
                         Step("Go that far across and up", "", [MathLine(.symbol("x"), x, Simplify.run(x)), MathLine(.symbol("y"), y, Simplify.run(y))])])
        }
        // "Work out the equation of the line perpendicular to AC that passes through C."
        if let asked = groups(#"equation of the (?:straight )?line (perpendicular|parallel) to (?-i:([A-Z])([A-Z])) (?:that|which) (?:passes|goes) through (?-i:([A-Z]))\b"#, in: text),
           let a = named[asked[2]], let b = named[asked[3]], let through = named[asked[4]], amount(b.x - a.x) ?? 0 != 0 {
            let slope = Simplify.run((b.y - a.y) / (b.x - a.x))
            let isPerpendicular = asked[1].lowercased() == "perpendicular"
            guard !isPerpendicular || !slope.isZero else { return nil }
            let m = isPerpendicular ? Simplify.run(-Expr.one / slope) : slope
            let c = Simplify.run(through.y - m * through.x)
            return told(asked[0], [MathLine(.symbol("y"), Simplify.run(m * .symbol("x") + c))],
                        [Step("Find the gradient of \(asked[2])\(asked[3])", "The change in y over the change in x.", [MathLine(.symbol("gradient"), slope)]),
                         Step(isPerpendicular ? "Turn it over and change its sign" : "Keep the same gradient", isPerpendicular ? "Perpendicular gradients multiply to −1, so this line's gradient is \(Format.text(m))." : "Parallel lines have the same gradient."),
                         Step("Put the point in to find c", "y = \(Format.text(m))x + c goes through (\(coordinate(through.x)), \(coordinate(through.y))).", [MathLine(.symbol("c"), c)])])
        }
        // "P(-1, 4) is a point on a circle, centre O. Work out the equation of the tangent to the circle at P."
        if has(#"equation of the tangent"#, text), has(#"\bcentre (?-i:O)\b|\bcentre the origin\b|\bcentre \(0, ?0\)"#, text), every(#"\bcircle\b"#, in: text).count <= 3,
           let at = groups(#"(?:tangent[a-z ]*? at|tangent to the circle at)(?: the)?(?: point)? (?-i:([A-Z]))\b"#, in: text) ?? (named.count == 1 ? [named.keys.first!, named.keys.first!] : nil),
           let point = named[at[1]], named.count == 1, !point.y.isZero {
            let radius = point.x.isZero ? nil : Simplify.run(point.y / point.x)
            let m = Simplify.run(-point.x / point.y)
            let c = Simplify.run(point.y - m * point.x)
            return told("tangent at (\(coordinate(point.x)), \(coordinate(point.y)))", [MathLine(.symbol("y"), Simplify.run(m * .symbol("x") + c))],
                        [Step("Find the gradient of the radius", "From the centre (0, 0) to (\(coordinate(point.x)), \(coordinate(point.y))).", radius.map { [MathLine(.symbol("gradient of radius"), $0)] } ?? []),
                         Step("The tangent is at right angles to the radius", "Its gradient is the radius's turned over with the sign changed: \(Format.text(m))."),
                         Step("Put the point in to find c", "", [MathLine(.symbol("c"), c)])])
        }
        // "The 3.8 m³ of concrete is made into the shape of a cylinder. The base has radius 0.5 metres. Work out the height of the cylinder."
        if has("\(ask) the height of the cylinder", text), has(#"\bcylinder\b"#, text) {
            let volumes = every(#"(\d+(?:\.\d+)?) ?(mm|cm|m)\^?3"#, in: text), radii = every(#"\b(radius|diameter) (?:of |is |= ?)?(\d+(?:\.\d+)?) ?(mm|cm|m|millimetres|centimetres|metres)\b"#, in: text)
            guard Set(volumes.map { $0[1] + $0[2] }).count == 1, radii.count == 1, let volume = Double(volumes[0][1]), var radius = Double(radii[0][2]), let a = unit(volumes[0][2]), let b = unit(radii[0][3]), a.size == b.size else { return nil }
            if radii[0][1].lowercased() == "diameter" { radius /= 2 }
            guard let expr = sum("\(written(volume))/(π*\(written(radius))^2)") else { return nil }
            return made(expr, decimals: true, [Step("Volume of a cylinder is π × radius² × height", "So the height is the volume divided by π × radius².", [MathLine(.symbol("\(written(volume)) ÷ (π × \(written(radius))²)"))])])
        }
        // "Solids X and Y are similar. X has volume 64 cm³. Y has volume 343 cm³. The surface area of X is 176 cm². Work out the surface area of Y."
        if let pairOf = groups(#"(?-i:\b([A-Z]) and ([A-Z])) are (?:mathematically )?similar"#, in: text), let asked = groups("\(ask) the (volume|surface area|area|height|length|width|radius) of (?-i:([A-Z]))\\b", in: text) {
            let kinds = ["volume": 3.0, "surface area": 2, "area": 2, "height": 1, "length": 1, "width": 1, "radius": 1]
            var known: [String: [String: Double]] = [:]   // solid → kind → size
            for found in every(#"(?-i:\b([A-Z])) has (?:a |an )?(volume|surface area|area|height|length|width|radius)(?: of)? (\d+(?:\.\d+)?)"#, in: text) + every(#"\bthe (volume|surface area|area|height|length|width|radius) of (?-i:([A-Z])) is (\d+(?:\.\d+)?)"#, in: text).map({ [$0[0], $0[2], $0[1], $0[3]] }) {
                guard let size = Double(found[3]), size > 0, known[found[1], default: [:]][found[2].lowercased()] == nil else { return nil }
                known[found[1], default: [:]][found[2].lowercased()] = size
            }
            let wanted = asked[1].lowercased(), target = asked[2]
            let other = target == pairOf[1] ? pairOf[2] : pairOf[1]
            guard [pairOf[1], pairOf[2]].contains(target), known[target]?[wanted] == nil, let base = known[other]?[wanted],
                  let shared = kinds.keys.first(where: { known[target]?[$0] != nil && known[other]?[$0] != nil }), let mine = known[target]?[shared], let theirs = known[other]?[shared],
                  let sharedPower = kinds[shared], let wantedPower = kinds[wanted] else { return nil }
            let scale = pow(mine / theirs, 1 / sharedPower)
            let answer = base * pow(scale, wantedPower)
            return made(plain((answer * 1e8).rounded() / 1e8), decimals: true,
                        [Step("Find how many times longer \(target) is", "The \(shared)s are \(written(theirs)) and \(written(mine)). \(sharedPower == 3 ? "Volumes go by the cube of the lengths, so take the cube root of their ratio." : (sharedPower == 2 ? "Areas go by the square of the lengths, so take the square root of their ratio." : "Divide one by the other."))", [MathLine(.symbol("lengths"), .symbol("× \(written((scale * 1e8).rounded() / 1e8))"))]),
                         Step("Scale the \(wanted)", wantedPower == 3 ? "Volumes are multiplied by that cubed." : (wantedPower == 2 ? "Areas are multiplied by that squared." : "Lengths are multiplied by that."), [MathLine(.symbol("\(written(base)) × \(written((scale * 1e8).rounded() / 1e8))\(wantedPower == 1 ? "" : raisedDigits(Int(wantedPower)))"))])])
        }
        // "a and b are different prime numbers. a³ × b² = 200. Work out the value of a⁴ × b"
        if let letters = groups(#"(?<![a-z])([a-z]) and ([a-z]) are (?:different |distinct )?prime numbers"#, in: text), letters[1] != letters[2],
           let stated = groups("(?<![a-z])\(letters[1])\\^?(\\d)? ?[×x*] ?\(letters[2])\\^?(\\d)? ?= ?(\\d+)(?!\\d|\\.\\d)", in: text),
           let asked = groups("\(ask) the value of \(letters[1])\\^?(\\d)? ?[×x*] ?\(letters[2])\\^?(\\d)?(?!\\d|\\.\\d|[a-z^])", in: text), let size = Int(stated[3]), size > 1 {
            let powers = [Int(stated[1]) ?? 1, Int(stated[2]) ?? 1]
            let counted = Dictionary(grouping: primes(of: size), by: { $0 }).mapValues(\.count)
            // Which prime is which: told apart by their powers.
            guard counted.count == 2, powers[0] != powers[1], let a = counted.first(where: { $0.value == powers[0] })?.key, let b = counted.first(where: { $0.value == powers[1] })?.key, a != b else { return nil }
            let wanted = [Int(asked[1]) ?? 1, Int(asked[2]) ?? 1]
            return made(.power(.integer(a), .integer(wanted[0])) * .power(.integer(b), .integer(wanted[1])), decimals: false,
                        [Step("Write \(size) as a product of primes", "", [MathLine(.integer(size), .symbol("\(a)\(raisedDigits(powers[0])) × \(b)\(raisedDigits(powers[1]))"))]),
                         Step("Match the powers", "So \(letters[1]) = \(a) and \(letters[2]) = \(b).")])
        }
        // "He takes 8 minutes to type a report of 416 words. How long does it take him to type an essay of 1534 words?" (at a constant rate)
        if has(#"\bconstant\b|\bsame rate\b|\bsteady\b"#, text), let known = groups(#"\btakes (\d+(?:\.\d+)?) (seconds|minutes|hours) to [a-z ]+? of (\d+(?:\.\d+)?) ([a-z]+)\b"#, in: text),
           let asked = groups(#"how long (?:does|will|would) it take [a-z ]+? of (\d+(?:\.\d+)?) ([a-z]+)\b"#, in: text), single(known[4]) == single(asked[2]),
           every(#"\btakes \d"#, in: text).count == 1, let time = Double(known[1]), let amountDone = Double(known[3]), let wanted = Double(asked[1]), amountDone > 0 {
            let took = time * wanted / amountDone
            let lead = [Step("Find the time for one", "\(known[3]) \(known[4]) take \(known[1]) \(known[2]), so divide by \(known[3]).", [MathLine(.symbol("\(known[1]) ÷ \(known[3])"), plain(time / amountDone))]),
                        Step("Multiply up", "\(asked[1]) \(asked[2]) take \(asked[1]) times as long: \(written(took)) \(known[2]).")]
            // "Give your answer in minutes and seconds."
            if let form = groups(#"answer in (hours|minutes) and (minutes|seconds)"#, in: text), form[1].lowercased() == known[2].lowercased() {
                let big = took.rounded(.down), small = ((took - big) * 60 * 1000).rounded() / 1000
                return told(asked[0], [MathLine(.symbol("\(written(big)) \(form[1]) \(written(small)) \(form[2])"))], lead + [Step("Write the part of a \(single(form[1])) in \(form[2])", "\(written(took - big)) of a \(single(form[1])) is \(written(small)) \(form[2]).")])
            }
            guard !has(#"answer in (?:hours|minutes) and"#, text) else { return nil }
            return made(plain(took), decimals: true, lead)
        }
        // "Three friends arrive at a party. Their arrival increases the number of people at the party by 20%. In total, how many people are now at the party?"
        if let found = groups(#"\b(\d+|[a-z]+) (?:friends|people|students|guests|children|adults|members|players|pupils) (?:arrive|join)\b[^.]*?\.? their arrival increases the number of [a-z ]+? by (\d+(?:\.\d+)?) ?%"#, in: text),
           has(#"how many [a-z ]+? now\b|in total, how many\b"#, text), let arrived = count(found[1]), let rate = Double(found[2]), rate > 0, every(#"\d ?%"#, in: text).count == 1 {
            let before = Double(arrived) * 100 / rate
            guard abs(before - before.rounded()) < 1e-9 else { return nil }
            return made(plain(before + Double(arrived)), decimals: false,
                        [Step("Find how many were there before", "The \(arrived) who arrive are \(found[2])% of the number before, so that number is \(arrived) ÷ \(found[2]) × 100.", [MathLine(.symbol("\(arrived) ÷ \(found[2]) × 100"), plain(before))]),
                         Step("Add the ones who arrived", "")])
        }
        // "Larrs swims 50 metres in 40 seconds at a constant speed. He swims 1.5 kilometres at the same speed. How many minutes does he swim for?"
        let travel = #"(\d+(?:\.\d+)?) ?(metres|kilometres|miles|km|m) in (\d+(?:\.\d+)?) ?(seconds?|minutes?|hours?)"#
        if has(#"\bsame (?:constant )?speed\b"#, text), every(travel, in: text).count == 1, let first = groups(travel, in: text), let wanted = groups(#"how many (seconds|minutes|hours)\b"#, in: text),
           let whole = text.range(of: first[0], options: .caseInsensitive) {
            let later = every(#"\b(?:swims|runs|walks|travels|drives|cycles|rides|jogs) (\d+(?:\.\d+)?) ?(metres|kilometres|miles|km|m)\b(?! in \d)"#, in: String(text[whole.upperBound...]))
            guard later.count == 1, let far = Double(first[1]), let time = Double(first[3]), let next = Double(later[0][1]), far > 0,
                  let farUnit = unit(first[2]), let nextUnit = unit(later[0][2]), let timeUnit = unit(first[4]), let wantedUnit = unit(wanted[1]) else { return nil }
            // Miles only go with miles.
            guard (single(first[2]) == single(later[0][2])) || (first[2].lowercased().hasPrefix("mile") == false && later[0][2].lowercased().hasPrefix("mile") == false) else { return nil }
            let times = next * nextUnit.size / (far * farUnit.size)
            let answer = time * times * timeUnit.size / wantedUnit.size
            return made(plain((answer * 1e8).rounded() / 1e8), decimals: true,
                        [Step("See how many times further it is", "\(later[0][1]) \(later[0][2]) is \(written(times)) lots of \(first[1]) \(first[2]).", []),
                         Step("It takes that many times as long", "\(written(times)) × \(first[3]) \(first[4]) is \(written(time * times)) \(first[4]), which is \(written((answer * 1e8).rounded() / 1e8)) \(wanted[1]).")])
        }
        return nil
    }

    // MARK: Counting, chains of percentages and other stories

    private static func extra(_ text: String, _ question: Question) -> Problem? {
        let ask = #"(?:work out|find|calculate|write down|what is|what are)"#
        // "Lamp A flashes every 20 seconds. Lamp B flashes every 45 seconds. Lamp C flashes every 120 seconds. The three lamps start
        // flashing at the same time. How many times in one hour will the three lamps flash at the same time?"
        let gaps = every(#"\bevery (\d+) (seconds?|minutes?|hours?)\b"#, in: text)
        if gaps.count >= 2, gaps.count <= 4, gaps.count == every(#"\bevery\b"#, in: text).count, has(#"\bstart[a-z]* [a-z ]*?(?:at the same time|together)\b"#, text),
           let asked = groups(#"how many times in (\d+|[a-z]+) (seconds?|minutes?|hours?|days?) will [a-z ]+? (?:at the same time|together)\b"#, in: text),
           let lots = ["a", "an"].contains(asked[1].lowercased()) ? 1 : count(asked[1]), let span = unit(asked[2]) {
            var sizes: [Int] = []
            for gap in gaps {
                guard let size = Int(gap[1]), size > 0, let its = unit(gap[2]) else { return nil }
                sizes.append(size * Int(its.size))
            }
            let together = sizes.reduce(1) { $0 / gcd($0, $1) * $1 }
            let whole = lots * Int(span.size)
            guard together > 0, whole >= together else { return nil }
            // In the unit the question uses, when it uses one.
            let names = Set(gaps.map { single($0[2]) })
            let per = names.count == 1 ? Int(unit(gaps[0][2])?.size ?? 1) : 1
            let name = names.count == 1 ? single(gaps[0][2]) + "s" : "seconds"
            let numbers = sizes.map { String($0 / per) }
            return made(.integer(whole / together), decimals: false,
                        [Step("Find when they next happen together", "That's the lowest common multiple of \(numbers.dropLast().joined(separator: ", ")) and \(numbers[numbers.count - 1]): the smallest number all of them go into.",
                              [MathLine(.symbol("LCM"), .integer(together / per))]),
                         Step("See how many of those fit", "\(asked[1].capitalized) \(asked[2]) is \(whole / per) \(name), and they happen together every \(together / per) \(name).",
                              [MathLine(.symbol("\(whole / per) ÷ \(together / per)"), plain(Double(whole) / Double(together)))] ) ] + (whole % together == 0 ? [] : [Step("Keep the whole ones", "Only whole lots of \(together / per) \(name) count.")]))
        }
        // "Jerry bought a house. Jerry sold the house to Mia. He made a profit of 20%. Mia sold the house for £162 000. She made a loss
        // of 10%. Work out how much Jerry paid for the house."
        if let first = groups(#"(?-i:\b([A-Z][a-z]+)) bought (?:a|an|the|some) ([a-z]+)\b"#, in: text),
           let sale = groups("(?-i:\\b\(first[1])) sold (?:the|this|his|her) \(first[2]) to (?-i:([A-Z][a-z]+))\\W+(?:he|she|they|(?-i:\(first[1]))) made a (profit|loss) of (\\d+(?:\\.\\d+)?) ?%", in: text), sale[1] != first[1],
           let resale = groups("(?-i:\\b\(sale[1])) sold (?:the|this|his|her) \(first[2]) for (\\d+(?:\\.\\d+)?)\\W+(?:he|she|they|(?-i:\(sale[1]))) made a (profit|loss) of (\\d+(?:\\.\\d+)?) ?%", in: text),
           has("how much (?-i:\(first[1])) paid for (?:the|this|his|her) \(first[2])", text), every(#"\d ?%"#, in: text).count == 2,
           let price = exact(resale[1]), let firstRate = exact(sale[3]), let secondRate = exact(resale[3]), amount(firstRate) ?? 100 < 100, amount(secondRate) ?? 100 < 100 {
            func multiplier(_ rate: Expr, _ word: String) -> Expr { Simplify.run(word.lowercased() == "profit" ? Expr.one + rate / .integer(100) : Expr.one - rate / .integer(100)) }
            let second = multiplier(secondRate, resale[2]), one = multiplier(firstRate, sale[2])
            let between = Simplify.run(price / second)
            func percent(_ rate: Expr, _ word: String) -> String { Format.text(Simplify.run(word.lowercased() == "profit" ? .integer(100) + rate : .integer(100) - rate)) }
            return made(price / second / one, decimals: true,
                        [Step("Find what \(sale[1]) paid", "\(sale[1]) made a \(resale[2].lowercased()) of \(resale[3])%, so \(resale[1]) is \(percent(secondRate, resale[2]))% of what \(sale[1]) paid. Divide by \(written(amount(second) ?? 1)).",
                              [MathLine(.symbol("\(resale[1]) ÷ \(written(amount(second) ?? 1))"), between)]),
                         Step("Find what \(first[1]) paid", "\(first[1]) made a \(sale[2].lowercased()) of \(sale[3])%, so \(Format.text(between)) is \(percent(firstRate, sale[2]))% of what \(first[1]) paid. Divide by \(written(amount(one) ?? 1)).")])
        }
        // "There are 16 hockey teams in a league. Each team played two matches against each of the other teams. Work out the total number of matches played."
        if let found = groups(#"\beach (team|player) (?:plays|played|will play|is to play|has to play) (?:(\d+|[a-z]+) (?:match|matches|game|games) against )?(?:each of the other|every other|each other|all of the other|all the other)(?: (?:teams?|players?))?( once| twice)?\b"#, in: text),
           has(#"\bnumber of (?:matches|games)\b|\bhow many (?:matches|games)\b"#, text), !has(#"\bhome\b|\baway\b|\bknockout\b|\bgroups?\b|\brounds?\b"#, text) {
            let sizes = every("\\b(\\d+) (?:[a-z]+ )?\(found[1])s\\b", in: text)
            guard sizes.count == 1, let n = Int(sizes[0][1]), n >= 2, n <= 1000 else { return nil }
            var times = 1
            if !found[2].isEmpty {
                guard found[3].isEmpty, let said = ["a", "one"].contains(found[2].lowercased()) ? 1 : count(found[2]), said >= 1 else { return nil }
                times = said
            } else if found[3].lowercased() == " twice" { times = 2 }
            // The only numbers in it are the ones used.
            guard every(#"\d+"#, in: text).count == 1 + (Int(found[2]) == nil ? 0 : 1) else { return nil }
            let pairs = Expr.integer(n) * .integer(n - 1) / .two
            return made(times == 1 ? pairs : pairs * .integer(times), decimals: false,
                        [Step("Count the pairs of \(found[1])s", "Each of the \(n) \(found[1])s meets the \(n - 1) others. \(n) × \(n - 1) counts every pair twice, once from each side, so halve it.",
                              [MathLine(.symbol("\(n) × \(n - 1) ÷ 2"), .integer(n * (n - 1) / 2))])] + (times == 1 ? [] : [Step(times == 2 ? "Each pair plays twice" : "Each pair plays \(times) times", "", [MathLine(.symbol("\(n * (n - 1) / 2) × \(times)"), .integer(n * (n - 1) / 2 * times))])]))
        }
        // "surface area of shape A : surface area of shape B = 3 : 4. The volume of shape B is 10 cm³. Work out the volume of shape A."
        // (Only similar shapes can be asked this.)
        let measure = #"(volume|surface area|area|height|length|width|radius)"#, thing = #"(?:(?:shape|solid|cone|cylinder|prism|pyramid|cuboid|sphere|vase|container|bottle|statue|model) )?"#
        if let ratio = groups("\\b\(measure) of \(thing)(?-i:([A-Z])) ?: ?\(measure) of \(thing)(?-i:([A-Z])) ?= ?(\\d+(?:\\.\\d+)?) ?: ?(\\d+(?:\\.\\d+)?)(?!\\d|\\.\\d| ?:)", in: text),
           ratio[1].lowercased() == ratio[3].lowercased(), ratio[2] != ratio[4], every(#"\d ?: ?\d"#, in: text).count == 1,
           let asked = groups("\(ask) the \(measure) of \(thing)(?-i:([A-Z]))\\b", in: text), [ratio[2], ratio[4]].contains(asked[2]) {
            let powers = ["volume": 3.0, "surface area": 2, "area": 2, "height": 1, "length": 1, "width": 1, "radius": 1]
            let other = asked[2] == ratio[2] ? ratio[4] : ratio[2]
            let stated = every("\\bthe \(measure) of \(thing)(?-i:([A-Z])) is (\\d+(?:\\.\\d+)?)", in: text)
            guard stated.count == 1, stated[0][1].lowercased() == asked[1].lowercased(), stated[0][2] == other, let base = Double(stated[0][3]), base > 0,
                  let mine = Double(asked[2] == ratio[2] ? ratio[5] : ratio[6]), let theirs = Double(asked[2] == ratio[2] ? ratio[6] : ratio[5]), mine > 0, theirs > 0,
                  let ratioPower = powers[ratio[1].lowercased()], let wantedPower = powers[asked[1].lowercased()] else { return nil }
            let scale = pow(mine / theirs, 1 / ratioPower)
            let answer = base * pow(scale, wantedPower)
            let tidyScale = written((scale * 1e8).rounded() / 1e8)
            return made(plain((answer * 1e8).rounded() / 1e8), decimals: true,
                        [Step("Find how the lengths compare", "The \(ratio[1].lowercased())s are in the ratio \(written(mine)) : \(written(theirs)). \(ratioPower == 3 ? "Volumes go by the cube of the lengths, so take the cube root." : (ratioPower == 2 ? "Areas go by the square of the lengths, so take the square root." : "Divide one by the other."))",
                              [MathLine(.symbol("lengths of \(asked[2])"), .symbol("× \(tidyScale)"))]),
                         Step("Scale the \(asked[1].lowercased())", wantedPower == 3 ? "Volumes are multiplied by that cubed." : (wantedPower == 2 ? "Areas are multiplied by that squared." : "Lengths are multiplied by that."),
                              [MathLine(.symbol("\(written(base)) × \(tidyScale)\(wantedPower == 1 ? "" : raisedDigits(Int(wantedPower)))"))])])
        }
        // "Complete this statement by writing the missing power in the box. 784 = 2▢ × 7²": the box is lost, or read as a letter.
        if has(#"\bmissing (?:power|index)\b"#, text),
           let found = groups(#"(?<![\d.^])(\d+) ?= ?(\d+)(\^[A-Za-z□?_]|\^\(?(\d+)\)?)? ?[×x*] ?(\d+)(\^[A-Za-z□?_]|\^\(?(\d+)\)?)?(?: ?\[\d\])?\s*$"#, in: text),
           let total = Int(found[1]), let a = Int(found[2]), let b = Int(found[5]), a >= 2, b >= 2, a != b, total >= 2, found[4].isEmpty != found[7].isEmpty {
            // The one with its power written, and the one without.
            let known = found[4].isEmpty ? b : a, base = found[4].isEmpty ? a : b
            guard let power = Int(found[4].isEmpty ? found[7] : found[4]), power >= 1, power <= 20 else { return nil }
            var rest = total
            for _ in 0..<power { guard rest % known == 0 else { return nil }; rest /= known }
            var missing = 0, left = rest
            while left > 1, left % base == 0 { left /= base; missing += 1 }
            guard left == 1, missing >= 1 else { return nil }
            return made(.integer(missing), decimals: false,
                        [Step("Divide by the part that's known", "\(known)\(raisedDigits(power)) is \(total / rest).", [MathLine(.symbol("\(total) ÷ \(total / rest)"), .integer(rest))]),
                         Step("Write what's left as a power of \(base)", "\(rest) is \(Array(repeating: String(base), count: missing).joined(separator: " × ")).", [MathLine(.integer(rest), .symbol("\(base)\(raisedDigits(missing))"))])])
        }
        // "A ball falls d metres in t seconds. d is directly proportional to the square of t. The ball drops 45 metres in the first
        // 3 seconds. How far does the ball drop in the next 7 seconds?"
        if every(#"\bproportional\b"#, in: text).count == 1,
           let relation = groups(#"(?<![A-Za-z])(?-i:([a-z])) is directly proportional to (the square of |the cube of )?(?-i:([a-z]))(?:\^?([23]))?(?=$|[ ,;:]|\.(?: |$))"#, in: text), relation[1] != relation[3],
           relation[2].isEmpty || relation[4].isEmpty,
           let named = groups("\\b[a-z]+s (?-i:\(relation[1])) (metres|centimetres|kilometres|miles|m|cm|km) in (?-i:\(relation[3])) (seconds|minutes|hours)\\b", in: text),
           let first = groups("\\b[a-z]+s (\\d+(?:\\.\\d+)?) \(named[1]) in the first (\\d+(?:\\.\\d+)?) \(named[2])\\b", in: text),
           let next = groups("\\bhow far (?:does|will|did) [a-z ]+? in the next (\\d+(?:\\.\\d+)?) \(named[2])\\b", in: text),
           every(#"\bin the (?:first|next|last)\b"#, in: text).count == 2,
           let far = exact(first[1]), let time = exact(first[2]), let more = exact(next[1]), amount(time) ?? 0 > 0, amount(more) ?? 0 > 0 {
            let power: Expr = relation[2].lowercased().hasPrefix("the square") || relation[4] == "2" ? .two : (relation[2].lowercased().hasPrefix("the cube") || relation[4] == "3" ? .integer(3) : .one)
            let y = relation[1], x = relation[3]
            let constant = Simplify.run(far / .power(time, power)), end = Simplify.run(time + more)
            let total = Simplify.run(constant * .power(end, power))
            guard constant.number != nil, total.number != nil else { return nil }
            let raisedX = Format.text(Simplify.run(.power(.symbol(x), power)))
            return made(total - far, decimals: false,
                        [Step("Write \(y) in terms of \(x)", "\(y) is proportional to \(raisedX), so \(y) = k × \(raisedX). Put in \(y) = \(first[1]) and \(x) = \(first[2]) to find k.",
                              [MathLine(.symbol("k"), constant), MathLine(.symbol(y), Simplify.run(constant * .power(.symbol(x), power)))]),
                         Step("Find \(y) at the end of the next \(next[1]) \(named[2])", "That is \(first[2]) + \(next[1]) = \(Format.text(end)) \(named[2]) from the start.", [MathLine(.symbol(y), total)]),
                         Step("Take away the first \(first[1]) \(named[1])", "")])
        }
        // "Charlie is driving 293 miles home. He leaves at 9.00 am, travels the first 176 miles at an average speed of 48 mph, drives the
        // rest of the way at an average speed of 65 mph. Will he be home by 2.30 pm?"
        let clock = #"(\d{1,2})([.:])(\d{2}) ?(am|pm)"#, moving = #"(?:travels|drives|cycles|walks|runs|rides|sails|flies)"#, speed = #"(\d+(?:\.\d+)?) ?(mph|miles per hour|km/h|kilometres per hour)"#
        if let deadline = groups("\\bwill (?:he|she|they|it|(?-i:[A-Z][a-z]+)) (?:be|get|arrive|reach)(?: [a-z]+){0,3}? (by|before) \(clock)", in: text),
           let total = groups(#"\b(?:driving|travelling|cycling|walking|a journey of|drives|travels|cycles|walks) (\d+(?:\.\d+)?) (miles|km|kilometres)\b"#, in: text),
           let leaving = groups("\\b(?:leaves|sets off|starts)(?: [a-z]+)? at \(clock)", in: text),
           let first = groups("\\b\(moving) the first (\\d+(?:\\.\\d+)?) (miles|km|kilometres) at an average speed of \(speed)", in: text),
           let rest = groups("\\b\(moving) the rest(?: of the (?:way|journey|distance))? at an average speed of \(speed)", in: text),
           every(#"average speed"#, in: text).count == 2, every(clock, in: text).count == 2 {
            func isMiles(_ word: String) -> Bool { word.lowercased().hasPrefix("m") }
            func minutes(_ hour: String, _ minute: String, _ half: String) -> Double? {
                guard let h = Int(hour), let m = Int(minute), (1...12).contains(h), m < 60 else { return nil }
                return Double((h % 12 + (half.lowercased() == "pm" ? 12 : 0)) * 60 + m)
            }
            guard isMiles(total[2]) == isMiles(first[2]), isMiles(first[4]) == isMiles(first[2]), isMiles(rest[2]) == isMiles(first[2]),
                  let whole = Double(total[1]), let near = Double(first[1]), let fast = Double(first[3]), let later = Double(rest[1]), whole > near, near > 0, fast > 0, later > 0,
                  let start = minutes(leaving[1], leaving[3], leaving[4]), let limit = minutes(deadline[2], deadline[4], deadline[5]) else { return nil }
            let one = near / fast * 60, two = (whole - near) / later * 60
            let arrival = start + one + two
            // Too close to the time asked about to call once it's rounded to a minute.
            let isWhole = abs(arrival - arrival.rounded()) < 1e-6
            guard arrival < 24 * 60, isWhole || abs(arrival - limit) >= 1 else { return nil }
            func span(_ size: Double) -> String {
                let all = Int(size.rounded()), hours = all / 60, left = all % 60
                return [hours > 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : "", left > 0 || hours == 0 ? "\(left) minute\(left == 1 ? "" : "s")" : ""].filter { !$0.isEmpty }.joined(separator: " ")
            }
            func time(_ size: Double) -> String {
                let all = Int(size.rounded()), hour = all / 60, minute = all % 60
                return "\(hour % 12 == 0 ? 12 : hour % 12)\(deadline[3])\(minute < 10 ? "0" : "")\(minute) \(hour >= 12 ? "pm" : "am")"
            }
            let isInTime = deadline[1].lowercased() == "by" ? arrival <= limit + 1e-6 : arrival < limit - 1e-6
            let unit = isMiles(first[2]) ? "miles" : "km"
            return told(deadline[0], [MathLine(.symbol("\(isInTime ? "Yes" : "No"), at \(time(arrival))"))],
                        [Step("Find the time for the first \(first[1]) \(unit)", "Time is distance ÷ speed.", [MathLine(.symbol("\(first[1]) ÷ \(first[3])"), .symbol(span(one)))]),
                         Step("Find the time for the rest", "\(total[1]) − \(first[1]) = \(written(whole - near)) \(unit) are left.", [MathLine(.symbol("\(written(whole - near)) ÷ \(rest[1])"), .symbol(span(two)))]),
                         Step("Add them to the leaving time", "\(span(one + two)) after \(leaving[1])\(leaving[2])\(leaving[3]) \(leaving[4].lowercased()) is \(time(arrival)), which is \(arrival <= limit + 1e-6 ? (abs(arrival - limit) < 1e-6 ? "exactly" : "before") : "after") \(deadline[2])\(deadline[3])\(deadline[4]) \(deadline[5].lowercased()).")])
        }
        // "A box of washing powder, 1.68 kg, £5.60. To get more money per kg the company can increase the price to £5.88 or reduce
        // the mass of powder in the box by x%. Work out the value of x." (The same money per kg either way.)
        if has(#"\bper (?:kg|kilogram|g|gram|litre|ml|metre)\b"#, text), let raise = groups(#"\bincrease the price to £ ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: question.money),
           let cut = groups(#"\b(?:reduce|decrease|cut) the (mass|weight|amount|volume|size|number)\b[a-z ]*? by (?-i:([a-z])) ?%"#, in: text),
           has("(?:work out|find|calculate) the value of (?-i:\(cut[2]))\\b", text), every(#"\d ?%"#, in: text).isEmpty {
            let prices = every(#"£ ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: question.money).map { $0[1] }
            guard prices.count == 2, let now = prices.first(where: { $0 != raise[1] }), let old = exact(now), let new = exact(raise[1]),
                  let oldSize = amount(old), let newSize = amount(new), oldSize > 0, newSize > oldSize else { return nil }
            let factor = Simplify.run(new / old)
            let answer = (Expr.one - old / new) * .integer(100)
            // "the value of x to 2 decimal places"
            var rounding: [Step] = []
            var shown = answer
            if let places = groups(#"\bto (\d) decimal places?\b"#, in: text).flatMap({ Int($0[1]) }), let size = amount(answer), let rounded = roundedValue(size, places: places, significant: false) {
                shown = plain(rounded)
                rounding = [Step("Work it out", "", [MathLine(answer, plain(size))]), Step("Round it", "The answer is asked for to \(places) decimal place\(places == 1 ? "" : "s").")]
            }
            return made(shown, decimals: true,
                        [Step("See how much the price would go up", "From £\(now) to £\(raise[1]) is the price multiplied by \(raise[1]) ÷ \(now).", [MathLine(.symbol("\(raise[1]) ÷ \(now)"), factor)]),
                         Step("Get the same from a smaller \(cut[1].lowercased())", "The money for each kg goes up by the same amount if the price stays at £\(now) and the \(cut[1].lowercased()) is divided by \(Format.text(factor)). That leaves \(now) ÷ \(raise[1]) of it.",
                              [MathLine(.symbol("\(now) ÷ \(raise[1])"), plain(oldSize / newSize))]),
                         Step("Write the cut as a percentage", "\(cut[2]) is what's taken off, as a percentage: (1 − \(now) ÷ \(raise[1])) × 100.")] + rounding)
        }
        // "B is 7/4 of A. C is A increased by 150%. Work out C as a fraction of B." (Set out in a table, the first name is often lost.)
        if let wanted = groups(#"(?:work out|find|write|express) (?-i:([A-Z])) as a fraction of (?-i:([A-Z]))\b"#, in: text), wanted[1] != wanted[2] {
            let parts = every(#"(?:(?<![A-Za-z])(?-i:([A-Z])) ?(?:=|is)? ?)?(?:(\d+/\d+|\d+(?:\.\d+)? ?%) of (?-i:([A-Z]))(?![A-Za-z])|(?-i:([A-Z])) (increased|decreased|reduced) by (\d+(?:\.\d+)?) ?%)"#, in: text)
            guard parts.count == 2 else { return nil }
            var sizes: [String: Expr] = [:]
            var words: [String: String] = [:]
            var unnamed: [(Expr, String)] = []
            var bases = Set<String>()
            for part in parts {
                var size: Expr?
                var said = ""
                if !part[2].isEmpty {
                    bases.insert(part[3])
                    size = part[2].hasSuffix("%") ? exact(String(part[2].dropLast()).trimmingCharacters(in: .whitespaces)).map { $0 / .integer(100) } : value(part[2])
                    said = "\(part[2]) of \(part[3])"
                } else if let rate = exact(part[6]) {
                    bases.insert(part[4])
                    size = part[5].lowercased() == "increased" ? Expr.one + rate / .integer(100) : Expr.one - rate / .integer(100)
                    said = "\(part[4]) \(part[5].lowercased()) by \(part[6])%"
                }
                guard let size, amount(size) ?? 0 > 0 else { return nil }
                let tidy = Simplify.run(size)
                if part[1].isEmpty { unnamed.append((tidy, said)) } else {
                    guard sizes[part[1]] == nil else { return nil }
                    sizes[part[1]] = tidy
                    words[part[1]] = said
                }
            }
            // Both are measured against the same third number, and at most one has lost its name.
            guard bases.count == 1, let base = bases.first, ![wanted[1], wanted[2]].contains(base), unnamed.count <= 1, Set(sizes.keys).isSubset(of: [wanted[1], wanted[2]]) else { return nil }
            if let (size, said) = unnamed.first, let left = [wanted[1], wanted[2]].first(where: { sizes[$0] == nil }) {
                sizes[left] = size
                words[left] = said
            }
            guard let top = sizes[wanted[1]], let bottom = sizes[wanted[2]], amount(bottom) ?? 0 > 0 else { return nil }
            return made(top / bottom, decimals: false,
                        [Step("Write each as a multiple of \(base)", "\(wanted[2]) is \(words[wanted[2]] ?? ""), and \(wanted[1]) is \(words[wanted[1]] ?? "").",
                              [MathLine(.symbol(wanted[2]), Simplify.run(bottom * .symbol(base))), MathLine(.symbol(wanted[1]), Simplify.run(top * .symbol(base)))]),
                         Step("Divide \(wanted[1]) by \(wanted[2])", "\(base) cancels, which leaves one multiplier divided by the other.")])
        }
        return nil
    }

    // MARK: More stories, from other boards' papers

    private static func breadth(_ text: String, _ question: Question) -> Problem? {
        // "y is directly proportional to the square of x. Find the percentage decrease in y when x is decreased by 30%."
        if every(#"\bproportional\b"#, in: text).count == 1,
           let relation = groups(#"(?<![A-Za-z])(?-i:([A-Za-z])) ?is (directly |inversely )?proportional to (the square of |the cube of |the square root of |the cube root of )?(?-i:([A-Za-z]))(?:\^?([23]))?(?=$|[ ,;:]|\.(?: |$))"#, in: text),
           relation[1] != relation[4], relation[3].isEmpty || relation[5].isEmpty,
           let asked = groups("(?:find|work out|calculate|write down) the percentage (increase|decrease|change) in (?-i:\(relation[1])) when (?-i:\(relation[4])) is (increased|decreased|reduced) by (\\d+(?:\\.\\d+)?) ?%", in: text),
           every(#"\d ?%"#, in: text).count == 1, let rate = Double(asked[3]), rate > 0, rate < 100 || asked[2].lowercased() == "increased" {
            var power = 1.0
            switch relation[3].lowercased().trimmingCharacters(in: .whitespaces) {
            case "the square of": power = 2
            case "the cube of": power = 3
            case "the square root of": power = 0.5
            case "the cube root of": power = 1.0 / 3
            default: power = Double(relation[5]) ?? 1
            }
            if relation[2].lowercased().hasPrefix("inverse") { power = -power }
            let across = asked[2].lowercased() == "increased" ? 1 + rate / 100 : 1 - rate / 100
            let factor = pow(across, power)
            let change = ((factor - 1) * 100 * 1e8).rounded() / 1e8
            guard change != 0, asked[1].lowercased() == "change" || (asked[1].lowercased() == "increase") == (change > 0) else { return nil }
            let y = relation[1], x = relation[4]
            let lead = [Step("See what \(x) is multiplied by", "\(asked[2].capitalized) by \(asked[3])% is multiplying by \(written(across)).", []),
                        Step("Do the same to \(y) as the proportion says", "\(y) goes with \(x) to the power \(written((power * 1e6).rounded() / 1e6)), so \(y) is multiplied by \(written(across)) to that power.",
                             [MathLine(.symbol("multiplier for \(y)"), plain((factor * 1e8).rounded() / 1e8))]),
                        Step("Write the change as a percentage", change < 0 ? "Less than 1 is a decrease: 1 take away the multiplier, as a percentage." : "More than 1 is an increase: the multiplier take away 1, as a percentage.")]
            if asked[1].lowercased() == "change" { return told(asked[0], [MathLine(.symbol("\(change < 0 ? "decrease" : "increase") of \(written(abs(change)))%"))], lead) }
            return made(plain(abs(change)), decimals: true, lead)
        }
        // "It takes 14 hours for 5 identical pumps to fill a water tank. How many hours would it take 4 of these pumps to fill another
        // water tank of the same size?"
        let who = #"(?:people|workers|men|women|builders|painters|machines|pumps|taps|printers|pipes|cleaners|decorators|gardeners|bricklayers|plumbers)"#
        if let found = groups("\\bit takes (\\d+(?:\\.\\d+)?) (hours?|days?|minutes?|weeks?) for (\\d+) (?:identical )?\(who) to [a-z ]+?\\.? how (?:many (hours|days|minutes|weeks)|long) (?:would|will|does|should) it take (\\d+) (?:of these |of the )?(?:identical )?\(who)\\b", in: text),
           every(#"\d+(?:\.\d+)?"#, in: text).count == 3, found[4].isEmpty || single(found[4]) == single(found[2]),
           let time = Double(found[1]), let had = Double(found[3]), let others = Double(found[5]), others > 0, had > 0 {
            let unit = found[2].hasSuffix("s") ? found[2] : found[2] + "s"
            return made(plain(time) * plain(had) / plain(others), decimals: true,
                        [Step("Find the work for one", "\(found[3]) taking \(found[1]) \(unit) is the same as one taking \(written(time * had)) \(unit) alone.", [MathLine(.symbol("\(found[1]) × \(found[3])"), plain(time * had))]),
                         Step("Share it out", "With \(found[5]), each does a share of it, so it takes that long divided by \(found[5]).")])
        }
        // Reverse percentages. "20% VAT is added to the price. Jules then has to pay a total of £600. What is the price with no VAT added?"
        let amounts = every(#"£ ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: question.money).map { $0[1] }
        let rates = every(#"(\d+(?:\.\d+)?) ?%"#, in: text).map { $0[1] }
        if let vat = groups(#"\b(\d+(?:\.\d+)?) ?% VAT is added\b"#, in: text), has(#"\b(?:price|cost)\b[a-z ]*? (?:with no|without|before|excluding|not including)(?: the| any)? VAT\b"#, text),
           !has(#"\bplus VAT\b|\bdeposit\b|\bmonthly\b|\binstalments?\b"#, text), Set(rates).count == 1, Set(amounts).count == 1, let total = exact(amounts[0]), let rate = exact(vat[1]) {
            let multiplier = Simplify.run(Expr.one + rate / .integer(100))
            return made(total / multiplier, decimals: true,
                        [Step("See what the total is of the price", "Adding \(vat[1])% makes it \(Format.text(Simplify.run(.integer(100) + rate)))% of the price, which is the price × \(written(amount(multiplier) ?? 1)).", []),
                         Step("Undo it", "Divide the total by \(written(amount(multiplier) ?? 1)).")])
        }
        // "The price of a holiday increases by 20%. This 20% increase adds £240 to the price. Work out the price before the increase."
        if let change = groups(#"\bthis (\d+(?:\.\d+)?) ?% (increase|decrease|reduction|discount|rise|fall) (?:adds|takes|is|saves|removes) £ ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: question.money),
           has(#"\b(?:price|cost|value|amount)\b[a-z ]*? before the (?:increase|decrease|reduction|discount|rise|fall|sale)\b"#, text), Set(rates).count == 1, Set(amounts).count == 1,
           let part = exact(change[3]), let rate = exact(change[1]), amount(rate) ?? 0 > 0 {
            return made(part / (rate / .integer(100)), decimals: true,
                        [Step("See what the £\(change[3]) is", "It is \(change[1])% of the price before.", []),
                         Step("Find the whole of it", "\(change[1])% is \(change[3]), so divide by \(change[1]) to get 1% and multiply by 100.")])
        }
        // "At the end of the first year the value had decreased by 12.5%. The value then decreased by 10% each year for the next two years.
        // At the end of the three years, the value was £17010. Work out the value when Jane bought it."
        if let first = groups(#"\bfirst year\b[a-z ,]*? (increased|decreased|fallen|risen|gone up|gone down) by (\d+(?:\.\d+)?) ?%"#, in: text),
           let later = groups(#"\bthen (increased|decreased|fell|rose|went up|went down) by (\d+(?:\.\d+)?) ?% (?:each|every|per|a) year for the next (\d+|[a-z]+) years"#, in: text),
           let end = groups(#"\b(?:value|price|worth)\b[a-z ]*? (?:was|is) £ ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: question.money),
           has(#"\b(?:value|price|worth)\b[a-z ]*? when [a-z ]+? bought|\boriginal (?:value|price)\b|\b(?:value|price)\b[a-z ]*? at the start\b|\bhow much [a-z ]+? paid\b"#, text),
           rates.count == 2, Set(amounts).count == 1, let years = count(later[3]), years >= 1, years <= 20,
           let final = exact(end[1]), let one = exact(first[2]), let two = exact(later[2]) {
            func multiplier(_ rate: Expr, _ word: String) -> Expr { Simplify.run(has(#"^(?:increased|risen|gone up|rose|went up)$"#, word) ? Expr.one + rate / .integer(100) : Expr.one - rate / .integer(100)) }
            let a = multiplier(one, first[1]), b = multiplier(two, later[1])
            guard let aSize = amount(a), let bSize = amount(b), aSize > 0, bSize > 0 else { return nil }
            return made(final / (a * .power(b, .integer(years))), decimals: true,
                        [Step("Write each year's change as a multiplier", "The first year is × \(written(aSize)). Each of the next \(years) years is × \(written(bSize)).", [MathLine(.symbol("\(written(aSize)) × \(written(bSize))\(raisedDigits(years))"), plain(aSize * pow(bSize, Double(years))))]),
                         Step("Undo them", "The value at the start times that is \(end[1]), so divide \(end[1]) by it.")])
        }
        // "The value of a car, £V, is given by V = 16500 × 0.82ⁿ where n is the number of years after it is bought from new. Write down the
        // value of the car when new", "…the annual percentage decrease", "…the value at the start of 2020".
        let growth = every(#"(?<![A-Za-z])(?-i:([A-Z])) ?= ?(\d+(?:\.\d+)?) ?[×x*] ?(\d+\.\d+)\^\(?(?-i:([a-z]))\)?(?![A-Za-z\d^])"#, in: text)
        if growth.count == 1, let start = Double(growth[0][2]), let base = Double(growth[0][3]), start > 0, base > 0, base != 1, base < 3 {
            let letter = growth[0][4]
            let thing = #"(?:value|price|population|number|mass|amount|height|cost)"#
            // What the letter counts from: "the number of years after the start of 2016".
            let origin = groups("(?-i:\(letter)) is the (?:number of|age of [a-z ]+ in)(?: complete)? years(?: after (?:the start of |1st January |the beginning of )?(\\d{4}))?", in: text)
            let rate = ((abs(base - 1) * 100) * 1e8).rounded() / 1e8
            let rateAsk = #"(?:write down|work out|find|state) the (?:(?:annual|yearly) percentage (?:increase|decrease)|percentage (?:increase|decrease) (?:per|each|every|a) year)"#
            let startAsk = "(?:write down|work out|find|state) the \(thing)\\b[a-z ]*? (?:when new|when (?:it (?:is|was) )?(?:first )?bought|at the start\\b(?! of \\d)" + (origin.map { $0[1].isEmpty ? "" : "|(?:at the start of|on 1st January|at the beginning of) \($0[1])\\b" } ?? "") + ")"
            let laterAsk = "(?:calculate|work out|find) the (?:predicted |expected )?\(thing)\\b[a-z ]*? (?:(?:at the start of|on 1st January|at the beginning of) (?!\(origin?[1] ?? "0000")\\b)\\d{4}\\b|after \\d+ years\\b)"
            guard let which = chosenAsk(text, [rateAsk, startAsk, laterAsk]) else { return nil }
            if which == 0, let asked = groups(#"(?:write down|work out|find|state) the (?:(?:annual|yearly) percentage (increase|decrease)|percentage (increase|decrease) (?:per|each|every|a) year)"#, in: text) {
                let word = (asked[1] + asked[2]).lowercased()
                guard (word == "increase") == (base > 1) else { return nil }
                return made(plain(rate), decimals: true,
                            [Step("Look at what is multiplied each year", "Each year the \(growth[0][1]) is multiplied by \(growth[0][3]).", []),
                             Step("Write it as a percentage change", base > 1 ? "\(growth[0][3]) is 1 and \(written(base - 1)) more: an increase of \(written(rate))%." : "\(growth[0][3]) is \(written(1 - base)) short of 1: a decrease of \(written(rate))%.")])
            }
            if which == 1 {
                return made(plain(start), decimals: false,
                            [Step("Put \(letter) = 0 in", "At the start no years have gone by, and anything to the power 0 is 1.", [MathLine(.symbol("\(growth[0][2]) × \(growth[0][3])⁰"), plain(start))])])
            }
            // A later year, or a number of years.
            var years: Int?
            if let origin, let from = Int(origin[1]), let later = groups("(?:calculate|work out|find) the (?:predicted |expected )?\(thing)\\b[a-z ]*? (?:at the start of|on 1st January|at the beginning of) (\\d{4})\\b", in: text), let to = Int(later[1]), to > from { years = to - from }
            else if let after = groups("(?:calculate|work out|find) the (?:predicted |expected )?\(thing)\\b[a-z ]*? after (\\d+) years\\b", in: text) { years = Int(after[1]) }
            if which == 2, let years, years >= 1, years <= 60 {
                return made(plain(start) * .power(plain(base), .integer(years)), decimals: true,
                            [Step("Find \(letter)", "\(years) year\(years == 1 ? "" : "s") have gone by, so \(letter) = \(years).", []),
                             Step("Put it into the formula", "", [MathLine(.symbol(growth[0][1]), .symbol("\(growth[0][2]) × \(growth[0][3])\(raisedDigits(years))"))])])
            }
        }
        // "The scale 1 cm represents 25 m can be written in the form 1 : k. Find the value of k."
        if let scale = groups(#"\b1 ?cm represents (\d+(?:\.\d+)?) ?(m|km|metres|kilometres)\b"#, in: text), let form = groups(#"in the form 1 ?: ?(?-i:([a-z]))\b"#, in: text),
           has("(?:find|work out|write down) the value of (?-i:\(form[1]))\\b", text), every(#"\brepresents\b"#, in: text).count == 1, let size = Double(scale[1]), size > 0 {
            let inCm = scale[2].lowercased().hasPrefix("k") ? 100_000.0 : 100.0
            return made(plain(size * inCm), decimals: false,
                        [Step("Write both in centimetres", "There are \(written(inCm)) cm in a \(scale[2].lowercased().hasPrefix("k") ? "kilometre" : "metre"), so \(scale[1]) \(scale[2]) is \(written(size * inCm)) cm.", [MathLine(.symbol("1 cm : \(written(size * inCm)) cm"))])])
        }
        // Percentage profit. "He buys a card for £1.20 and sells it for £1.68", "She buys a box of 60 candles for £125. She sells the candles for £2.25 each."
        if let asked = groups(#"(?:calculate|work out|find) (?:his|her|their|the) percentage (profit|loss)\b"#, in: text), rates.isEmpty {
            var cost: Double?, income: Double?
            var lines: [MathLine] = []
            if let pair = groups(#"\bbuys? [a-z" ]+? for £ ?(\d+(?:\.\d+)?) and sells? (?:it|them|this) for £ ?(\d+(?:\.\d+)?)(?!\d|\.\d| each)"#, in: question.money), amounts.count == 2 {
                cost = Double(pair[1]); income = Double(pair[2])
            } else if let box = groups(#"\bbuys? (?:a|one) (?:box|pack|bag|crate|case|tray) of (\d+) ([a-z]+) for £ ?(\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: question.money),
                      let each = groups("\\bsells? (?:the|each of the|all (?:of )?the) \(box[2]) for £ ?(\\d+(?:\\.\\d+)?) each\\b", in: question.money), amounts.count == 2,
                      let howMany = Double(box[1]), let price = Double(each[1]) {
                cost = Double(box[3]); income = howMany * price
                lines.append(MathLine(.symbol("\(box[1]) × \(each[1])"), plain((howMany * price * 100).rounded() / 100)))
            }
            if let cost, let income, cost > 0, (asked[1].lowercased() == "profit") == (income > cost), income != cost {
                let change = abs(income - cost)
                return made(plain((change * 100).rounded() / 100) / plain(cost) * .integer(100), decimals: true,
                            (lines.isEmpty ? [] : [Step("Find what the sales bring in", "", lines)]) +
                            [Step("Find the \(asked[1].lowercased())", "", [MathLine(.symbol("\(written((max(income, cost) * 100).rounded() / 100)) − \(written((min(income, cost) * 100).rounded() / 100))"), plain((change * 100).rounded() / 100))]),
                             Step("Write it as a percentage of the cost", "The \(asked[1].lowercased()) over what was paid, times 100.")])
            }
        }
        // "In 2017 a chocolate bar had a mass of 250 g. In 2018 the mass was reduced to 220 g. Work out the percentage decrease in the mass."
        if let asked = groups(#"(?:calculate|work out|find) the percentage (decrease|increase|reduction|change) in the ([a-z]+)\b"#, in: text), rates.isEmpty,
           let before = groups("\\b(?:had|has) an? \(asked[2]) of (\\d+(?:\\.\\d+)?) ?([a-z]+)\\b", in: text),
           let after = groups("\\b\(asked[2])\\b[a-z ]*? (?:was|is) (?:reduced|increased|decreased|changed) to (\\d+(?:\\.\\d+)?) ?([a-z]+)\\b", in: text),
           single(before[2]) == single(after[2]), let old = Double(before[1]), let new = Double(after[1]), old > 0, new != old,
           asked[1].lowercased() == "change" || (asked[1].lowercased() == "increase") == (new > old) {
            return made(plain(abs(new - old)) / plain(old) * .integer(100), decimals: true,
                        [Step("Find the change", "", [MathLine(.symbol("\(written(max(old, new))) − \(written(min(old, new)))"), plain(abs(new - old)))]),
                         Step("Write it as a percentage of what it was", "The change over \(before[1]), times 100.")])
        }
        // "Ed's profit in 2018 was £360. This was a decrease of 20% on his profit in 2017. Work out Ed's profit in 2017."
        if let change = groups(#"\bthis (?:was|is) an? (increase|decrease|rise|fall|reduction) of (\d+(?:\.\d+)?) ?% on (?:his|her|their|its|the) [a-z" ]+? in (\d{4})\b"#, in: text),
           has("(?:work out|find|calculate) [a-z'\" ]+? in \(change[3])\\b", text), rates.count == 1, Set(amounts).count == 1, let now = exact(amounts[0]), let rate = exact(change[2]), amount(rate) ?? 100 < 100 || change[1].lowercased() == "increase" {
            let isUp = ["increase", "rise"].contains(change[1].lowercased())
            let multiplier = Simplify.run(isUp ? Expr.one + rate / .integer(100) : Expr.one - rate / .integer(100))
            guard amount(multiplier) ?? 0 > 0 else { return nil }
            return made(now / multiplier, decimals: true,
                        [Step("See what £\(amounts[0]) is of the \(change[3]) figure", "\(isUp ? "An increase" : "A decrease") of \(change[2])% leaves \(Format.text(Simplify.run(isUp ? .integer(100) + rate : .integer(100) - rate)))% of it, which is × \(written(amount(multiplier) ?? 1)).", []),
                         Step("Undo it", "Divide £\(amounts[0]) by \(written(amount(multiplier) ?? 1)).")])
        }
        // "It takes 40 minutes to fill a garden pond using water from 5 identical hose pipes. Work out how many minutes it would take to fill
        // the same garden pond using 2 of these hose pipes."
        if let found = groups(#"\bit takes (\d+(?:\.\d+)?) (hours?|days?|minutes?|weeks?) to [a-z ]+? using (?:water from )?(\d+) (?:identical )?[a-z]+(?: [a-z]+)?\b[^?]*?\bhow (?:many (minutes|hours|days|weeks)|long) it would take to [a-z ]+? using (\d+) of these\b"#, in: text),
           every(#"\d+(?:\.\d+)?"#, in: text).count == 3, found[4].isEmpty || single(found[4]) == single(found[2]),
           let time = Double(found[1]), let had = Double(found[3]), let others = Double(found[5]), others > 0, had > 0 {
            let unit = found[2].hasSuffix("s") ? found[2] : found[2] + "s"
            return made(plain(time) * plain(had) / plain(others), decimals: true,
                        [Step("Find the time with one", "\(found[3]) take \(found[1]) \(unit), so one alone takes \(found[3]) times as long.", [MathLine(.symbol("\(found[1]) × \(found[3])"), plain(time * had))]),
                         Step("Share it out", "With \(found[5]) it takes that long divided by \(found[5]).")])
        }
        // "Arron ran a distance of 5 km at an average speed of 2.2 m/s. How long did Arron run for? Give your answer in minutes and seconds, to the nearest second."
        if let run = groups(#"\ba distance of (\d+(?:\.\d+)?) ?(km|m|kilometres|metres) at an average speed of (\d+(?:\.\d+)?) ?m/s\b"#, in: text), has(#"\bhow long\b"#, text),
           has(#"answer in minutes and seconds"#, text), every(#"average speed"#, in: text).count == 1, let far = Double(run[1]), let speed = Double(run[3]), speed > 0 {
            let metres = run[2].lowercased().hasPrefix("k") ? far * 1000 : far
            let seconds = (metres / speed).rounded(.toNearestOrAwayFromZero)
            let minutes = Int(seconds) / 60, left = Int(seconds) % 60
            return told(run[0], [MathLine(.symbol("\(minutes) minutes \(left) seconds"))],
                        [Step("Put the distance in metres", "The speed is in metres per second.", [MathLine(.symbol("\(written(metres)) m"))]),
                         Step("Time is distance ÷ speed", "", [MathLine(.symbol("\(written(metres)) ÷ \(run[3])"), .symbol("\(written((metres / speed * 100).rounded() / 100)) seconds"))]),
                         Step("Write it in minutes and seconds", "\(written(seconds)) seconds, to the nearest second, is \(minutes) lots of 60 with \(left) left over.")])
        }
        // "Here are the first four terms of a quadratic sequence. 0 9 22 39. The nth term can be written as an² + bn + c. Find the values of a, b and c."
        if has(#"\ban\^?2 ?\+ ?bn ?\+ ?c\b"#, text), has(#"(?:find|work out) the values? of a, ?b,? and c\b"#, text), question.lists.count == 1 {
            let terms = question.lists[0].compactMap { Int($0) }
            guard terms.count == question.lists[0].count, terms.count >= 4, terms.count <= 8 else { return nil }
            let first = zip(terms.dropFirst(), terms).map { $0 - $1 }, second = zip(first.dropFirst(), first).map { $0 - $1 }
            guard Set(second).count == 1, let twice = second.first, twice != 0, twice % 2 == 0 else { return nil }
            let a = twice / 2, b = first[0] - 3 * a, c = terms[0] - a - b
            return told("an² + bn + c", [MathLine(.symbol("a = \(a), b = \(b), c = \(c)".replacingOccurrences(of: "-", with: "−")))],
                        [Step("Find the differences, and their differences", "The second differences are all \(twice), and a is half of that.", [MathLine(.symbol("first"), .symbol(first.map(String.init).joined(separator: ", "))), MathLine(.symbol("second"), .symbol(second.map(String.init).joined(separator: ", ")))]),
                         Step("Take \(a)n² away from each term", "What's left goes up in equal steps, which gives b and c.", [MathLine(.symbol("left"), .symbol(terms.enumerated().map { String($1 - a * ($0 + 1) * ($0 + 1)) }.joined(separator: ", ")))])])
        }
        // "Lava flows at a constant rate of 11.9 m³/s. How many days does it take for 67 205 600 m³ of lava to flow? Give your answer to the nearest day."
        let volume = #"(m\^3|cm\^3|mm\^3|litres?|ml|millilitres?|gallons?)"#
        if let flow = groups("\\bat a (?:constant |steady )?rate of (\\d+(?:\\.\\d+)?) ?\(volume) ?(?:/|per) ?(s|sec|seconds?|min|minutes?|h|hours?)\\b", in: text),
           let asked = groups("\\bhow many (seconds|minutes|hours|days) (?:does|will|would|did) it take (?:for|to [a-z]+) (\\d+(?:\\.\\d+)?) ?\(volume)", in: text),
           single(flow[2]) == single(asked[3]), every("\\d ?\(volume)", in: text).count == 2,
           let rate = Double(flow[1]), rate > 0, let much = Double(asked[2]), let wanted = unit(asked[1]),
           let per = unit(["s": "seconds", "sec": "seconds", "min": "minutes", "h": "hours"][flow[3].lowercased()] ?? flow[3]) {
            let inRate = much / rate, time = inRate * per.size / wanted.size
            let name = ["s": "seconds", "sec": "seconds", "min": "minutes", "h": "hours"][flow[3].lowercased()] ?? (flow[3].hasSuffix("s") ? flow[3] : flow[3] + "s")
            var lead = [Step("Divide the amount by the rate", "\(asked[2]) ÷ \(flow[1]) is the time in \(name).", [MathLine(.symbol("\(asked[2]) ÷ \(flow[1])"), plain((inRate * 1e6).rounded() / 1e6))])]
            if per.size != wanted.size { lead.append(Step("Change it to \(asked[1])", "There are \(written(wanted.size / per.size)) \(name) in a \(single(asked[1])).", [MathLine(.symbol("÷ \(written(wanted.size / per.size))"), plain((time * 1e6).rounded() / 1e6))])) }
            if has("to the nearest (?:whole )?(?:number of )?\(single(asked[1]))|nearest whole number", text) {
                return made(plain(time.rounded(.toNearestOrAwayFromZero)), decimals: false, lead + [Step("Round it", "To the nearest \(single(asked[1])).")])
            }
            guard !has(#"\bto the nearest\b"#, text) else { return nil }
            return made(plain((time * 1e8).rounded() / 1e8), decimals: true, lead)
        }
        // "The distance was 3.9 × 10⁷ km. The signal travelled at a speed of 3 × 10⁵ km per second. How long did the signal take?"
        let big = #"(\d+(?:\.\d+)?) ?[×x*] ?10\^\(?(-?\d+)\)?"#
        if let far = groups("\\bdistance\\b[a-z ]*? (?:was|is|of) \(big) ?(km|kilometres|m|metres|miles)\\b", in: text),
           let fast = groups("\\bspeed of \(big) ?(km|kilometres|m|metres|miles) per (second|minute|hour)\\b", in: text),
           has(#"\bhow long (?:did|does|will|would) [a-z ]+? take\b"#, text), single(far[3]) == single(fast[3]),
           Set(every("\\bspeed of \(big)", in: text).map { $0[0].lowercased() }).count == 1, every("\\bdistance\\b[a-z ]*? (?:was|is|of) \(big)", in: text).count == 1,
           let a = Double(far[1]), let p = Int(far[2]), let b = Double(fast[1]), let q = Int(fast[2]), b > 0, abs(p) < 30, abs(q) < 30 {
            let time = a / b * pow(10, Double(p - q))
            let tidy = (time * 1e6).rounded() / 1e6
            return told(far[0], [MathLine(.symbol("\(written(tidy)) \(fast[4])\(tidy == 1 ? "" : "s")"))],
                        [Step("Time is distance ÷ speed", "", [MathLine(.symbol("(\(far[1]) × 10\(raisedDigits(p))) ÷ (\(fast[1]) × 10\(raisedDigits(q)))"))]),
                         Step("Divide the numbers, and take one power from the other", "\(far[1]) ÷ \(fast[1]) = \(written(a / b)), and 10\(raisedDigits(p)) ÷ 10\(raisedDigits(q)) = 10\(raisedDigits(p - q)).", [MathLine(.symbol("\(written(a / b)) × 10\(raisedDigits(p - q))"), plain(tidy))])])
        }
        // "Jessica runs for 15 minutes at an average speed of 6 miles per hour. She then runs for 40 minutes at an average speed of 9 miles per
        // hour. It takes Amy 45 minutes to run the same total distance. Work out Amy's average speed."
        let leg = #"\bfor (\d+(?:\.\d+)?) (minutes|hours) at an average speed of (\d+(?:\.\d+)?) ?(miles per hour|mph|km/h|kilometres per hour|km per hour)"#
        let legs = every(leg, in: text)
        if legs.count >= 2, legs.count <= 4, every(#"average speed of \d"#, in: text).count == legs.count, Set(legs.map { $0[4].lowercased().hasPrefix("m") }).count == 1 {
            var distance = 0.0, hours = 0.0
            var lines: [MathLine] = []
            for found in legs {
                guard let time = Double(found[1]), let speed = Double(found[3]), time > 0, speed > 0 else { return nil }
                let inHours = found[2].lowercased() == "minutes" ? time / 60 : time
                distance += speed * inHours
                hours += inHours
                lines.append(MathLine(.symbol("\(found[3]) × \(found[2].lowercased() == "minutes" ? "\(found[1])/60" : found[1])"), plain((speed * inHours * 1e8).rounded() / 1e8)))
            }
            let unit = legs[0][4].lowercased().hasPrefix("m") ? "miles" : "km"
            let lead = [Step("Find how far each part is", "Distance is speed × time, with the time in hours.", lines),
                        Step("Add them", "", [MathLine(.symbol("total"), .symbol("\(written((distance * 1e8).rounded() / 1e8)) \(unit)"))])]
            // Someone else covering the same distance in a time of their own.
            if let other = groups(#"\bit takes (?-i:([A-Z][a-z]+)) (\d+(?:\.\d+)?) (minutes|hours) to [a-z]+ the same (?:total )?distance\b"#, in: text),
               has("(?:work out|find|calculate) (?-i:\(other[1]))'s average speed", text), let time = Double(other[2]), time > 0 {
                let inHours = other[3].lowercased() == "minutes" ? time / 60 : time
                return made(plain((distance / inHours * 1e8).rounded() / 1e8), decimals: true,
                            lead + [Step("Divide by \(other[1])'s time", "\(other[2]) \(other[3]) is \(written((inHours * 1e6).rounded() / 1e6)) hours. Speed is distance ÷ time.")])
            }
            // The average speed over all of it.
            if has(#"(?:work out|find|calculate) [a-z' ]*?average speed for the (?:whole|total|entire) (?:journey|run|ride|drive|trip|distance)"#, text), !has(#"\bit takes\b"#, text) {
                return made(plain((distance / hours * 1e8).rounded() / 1e8), decimals: true,
                            lead + [Step("Divide by the total time", "\(written((hours * 1e6).rounded() / 1e6)) hours in all. Speed is distance ÷ time.")])
            }
            return nil
        }
        // "There are 30 students in a class. A teacher is going to choose at random 2 of the students. Work out the number of different pairs."
        if has(#"\bnumber of different pairs\b|\bhow many different pairs\b"#, text),
           let group = groups(#"\b(\d+) (students|people|players|children|members|pupils|teachers|friends|runners)\b"#, in: text), let n = Int(group[1]), n >= 2, n <= 100_000,
           every(#"\d+"#, in: text).count == 1 + every(#"\b2 of\b"#, in: text).count, has(#"\b(?:2|two) of\b|\bpairs? of\b"#, text) {
            return made(.integer(n) * .integer(n - 1) / .two, decimals: false,
                        [Step("Count the ways to pick two, one after the other", "\(n) for the first and \(n - 1) for the second.", [MathLine(.symbol("\(n) × \(n - 1)"), .integer(n * (n - 1)))]),
                         Step("Halve it", "That counts each pair twice, once in each order.")])
        }
        // "Here are the first four terms of a sequence. 2/5 5/10 8/17 11/26. Find the next term." The tops make one sequence and the bottoms another.
        if has(#"\bsequence\b|\bterms\b"#, text) {
            let piece = #"\(?(\d+)\)?/\(?(\d+)\)?"#
            var tops: [Int] = [], bottoms: [Int] = []
            for line in question.lines {
                let found = every("(?<![\\d/^])\(piece)(?![\\d/^])", in: line)
                // Lines that are nothing but fractions.
                guard !found.isEmpty, line.replacingOccurrences(of: piece, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " ,.…")).isEmpty else { continue }
                tops += found.compactMap { Int($0[1]) }
                bottoms += found.compactMap { Int($0[2]) }
            }
            let which = chosenAsk(text, [#"(?:find|work out|write down) the next term"#, #"(?:find|work out|write down)(?: an expression for)? the nth term"#])
            let wantsNext = which == 0
            if tops.count >= 4, tops.count == bottoms.count, tops.count <= 8, which != nil {
                /// A sequence that goes up in equal steps, or whose steps do: its rule a·n² + b·n + c in whole numbers.
                func rule(_ terms: [Int]) -> (a: Int, b: Int, c: Int)? {
                    let first = zip(terms.dropFirst(), terms).map { $0 - $1 }, second = zip(first.dropFirst(), first).map { $0 - $1 }
                    guard Set(second).count == 1, let twice = second.first, twice % 2 == 0 else { return nil }
                    let a = twice / 2, b = first[0] - 3 * a
                    return (a, b, terms[0] - a - b)
                }
                guard let top = rule(tops), let bottom = rule(bottoms) else { return nil }
                func term(_ rule: (a: Int, b: Int, c: Int), _ n: Int) -> Int { rule.a * n * n + rule.b * n + rule.c }
                func expr(_ rule: (a: Int, b: Int, c: Int)) -> Expr { Simplify.run(.integer(rule.a) * .power(.symbol("n"), .two) + .integer(rule.b) * .symbol("n") + .integer(rule.c)) }
                let lead = [Step("Take the tops and the bottoms as two sequences", "", [MathLine(.symbol("tops"), .symbol(tops.map(String.init).joined(separator: ", "))), MathLine(.symbol("bottoms"), .symbol(bottoms.map(String.init).joined(separator: ", ")))]),
                            Step("Find each one's rule", "", [MathLine(.symbol("top"), expr(top)), MathLine(.symbol("bottom"), expr(bottom))])]
                let next = tops.count + 1
                guard term(bottom, next) != 0 else { return nil }
                if wantsNext { return told("next term", [MathLine(.symbol("\(term(top, next))/\(term(bottom, next))"))], lead + [Step("Put n = \(next) into each", "")]) }
                return told("nth term", [MathLine(.multiply([expr(top), .power(expr(bottom), .minusOne)]))], lead + [Step("Put one over the other", "")])
            }
        }
        return nil
    }

    // MARK: Inequalities, identities and other algebra asked for in words

    private static func further(_ text: String, _ question: Question) -> Problem? {
        let maths = #"[-+*/^(). \da-z×÷]"#
        // "Solve -3x > 6", "Solve 2x² > 12 - 5x"
        if let found = groups("\\bsolve (?:the inequality )?(\(maths)+?) ?(<|>|≤|≥) ?(\(maths)+?)(?=$| ?\\[| answer| give| you| circle|\\.(?: |$))", in: text),
           let left = sum(raised(found[1])), let right = sum(raised(found[3])), left.symbols.union(right.symbols).count == 1, let letter = left.symbols.union(right.symbols).first,
           let side = Polynomial(Simplify.run(left - right), in: letter), side.degree == 1 || side.degree == 2 {
            let signs = ["<": "<", ">": ">", "≤": "≤", "≥": "≥"], turned = ["<": ">", ">": "<", "≤": "≥", "≥": "≤"]
            let lead = side.leading
            // Everything on one side: (that side) sign 0.
            let sign = lead.numerator > 0 ? signs[found[2]]! : turned[found[2]]!
            func shown(_ value: Rational) -> String { Format.text(.number(.exact(value))) }
            if side.degree == 1 {
                guard let cut = (Rational(0) - side.coefficient(0)).flatMap({ $0 / lead }) else { return nil }
                return told("\(Format.text(left)) \(found[2]) \(Format.text(right))", [MathLine(.symbol("\(letter) \(sign) \(shown(cut))"))],
                            [Step("Get \(letter) on its own", "Do the same to both sides, as with an equation." + (lead.numerator < 0 ? " Dividing or multiplying both sides by a negative number turns the sign round." : ""))])
            }
            // A quadratic: where it crosses nought, and which side of those it is above or below.
            let roots = side.rationalRoots.sorted { $0 < $1 }
            guard roots.count == 2, roots[0] != roots[1] else { return nil }
            let outside = sign == ">" || sign == "≥", strict = sign == "<" || sign == ">"
            let answer = outside ? "\(letter) \(strict ? "<" : "≤") \(shown(roots[0])) or \(letter) \(strict ? ">" : "≥") \(shown(roots[1]))" : "\(shown(roots[0])) \(strict ? "<" : "≤") \(letter) \(strict ? "<" : "≤") \(shown(roots[1]))"
            return told("\(Format.text(left)) \(found[2]) \(Format.text(right))", [MathLine(.symbol(answer))],
                        [Step("Put everything on one side", "", [MathLine(.symbol("\(Format.text(side.expr)) \(found[2]) 0"))]),
                         Step("Find where it equals nought", "\(letter) = \(shown(roots[0])) and \(letter) = \(shown(roots[1]))."),
                         Step("Pick the side", (lead.numerator > 0) == outside ? "The curve is above nought outside those two values." : "The curve is below nought between those two values.")])
        }
        // "(a - 3)x² + 2b ≡ 5x² + 12. Work out the values of a and b."
        // ("Given that x² − 6x + 1 = (x − a)² − b for all values of x, find the value of a and the value of b" is the same question.)
        let stated = text.replacingOccurrences(of: #"\bgiven that ?"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let asked = groups(#"(?:work out|find) the values? of ([a-z])(?:, ([a-z]))?(?:,? and (?:the value of )?([a-z]))?\b"#, in: text), !has(#"one possible|a possible|possible set|possible values"#, text),
           let found = groups("(\(maths)+?) ?≡ ?(\(maths)+?)(?= work| find|$|\\.(?: |$)| where| \\[|,? for all | for every )", in: stated)
            ?? (text.contains("≡") || [asked[1], asked[2], asked[3]].filter({ !$0.isEmpty }).count < 2 ? nil : groups("(\(maths)+?) ?= ?(\(maths)+?)(?= work| find|$|\\.(?: |$)| where| \\[|,? for all | for every )", in: stated)),
           let left = sum(raised(found[1])), let right = sum(raised(found[2])) {
            var unknowns = [asked[1], asked[2], asked[3]].filter { !$0.isEmpty }
            // "for all values of x": every other letter in it is one to find, however the letters asked for were read (b as h).
            if let every = groups(#"for all values of ([a-z])\b"#, in: text)?[1] {
                let inIt = left.symbols.union(right.symbols).subtracting([every])
                if !Set(unknowns).isSubset(of: inIt), inIt.count == unknowns.count, !Set(unknowns).isDisjoint(with: inIt) { unknowns = inIt.sorted() }
            }
            let others = left.symbols.union(right.symbols).subtracting(unknowns)
            // (Read with = for ≡, it is an identity only if the other letter is on both sides.)
            guard text.contains("≡") || (others.count == 1 && left.contains(others.first!) && right.contains(others.first!)) else { return nil }
            guard others.count == 1, let letter = others.first, Set(unknowns).isSubset(of: left.symbols.union(right.symbols)), let form = PolynomialForm(Simplify.run(left - right), in: letter) else { return nil }
            // Each power of the letter has to match on its own.
            var equations: [Equation] = []
            var lines: [MathLine] = []
            for power in stride(from: form.degree, through: 0, by: -1) {
                let part = Simplify.run(form.coefficient(power))
                if part.isZero { continue }
                guard !part.symbols.isEmpty, part.symbols.isSubset(of: Set(unknowns)) else { return nil }
                equations.append(Equation(left: part, right: .zero))
                lines.append(MathLine(.symbol(power == 0 ? "numbers" : (power == 1 ? letter : "\(letter)\(raisedDigits(power))")), part, .zero, relation: ":"))
            }
            // One at a time: each has one letter not yet known.
            var known: [String: Expr] = [:]
            for _ in 0..<equations.count {
                for equation in equations {
                    var side = equation.left
                    for (name, size) in known { side = side.substituting(name, with: size) }
                    side = Simplify.run(side)
                    guard side.symbols.count == 1, let name = side.symbols.first, let line = Polynomial(side, in: name), line.degree == 1,
                          let size = (Rational(0) - line.coefficient(0)).flatMap({ $0 / line.leading }) else { continue }
                    known[name] = .number(.exact(size))
                }
            }
            guard unknowns.allSatisfy({ known[$0] != nil }) else { return nil }
            // Every one has to hold with those values.
            for equation in equations {
                var side = equation.left
                for (name, size) in known { side = side.substituting(name, with: size) }
                guard Simplify.run(side).isZero else { return nil }
            }
            return told("\(Format.text(left)) ≡ \(Format.text(right))", [MathLine(.symbol(unknowns.map { "\($0) = \(Format.text(known[$0]!))" }.joined(separator: ", ")))],
                        [Step("Match each power of \(letter)", "\(text.contains("≡") ? "≡ means the" : "The") two sides are the same for every \(letter), so what goes with each power of \(letter) has to be the same on both sides. Each line below has to come to nought.", lines)])
        }
        // "The expression for the number of squares in Pattern n is n² + 4. Work out the least value of n for which the number is greater than 500"
        if let asked = groups(#"\b(least|smallest|lowest|greatest|largest|biggest) value of ([a-z]) for which [^.?]*? is (greater than|more than|bigger than|at least|less than|smaller than|fewer than|at most) (\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: text),
           let whole = text.range(of: asked[0], options: .caseInsensitive), let limit = Double(asked[4]) {
            let letter = asked[2].lowercased()
            let before = String(text[..<whole.lowerBound])
            let rules = every("\\b(?:is|=) ?([-+*/^(). \\d\(letter)×÷]*\(letter)[-+*/^(). \\d\(letter)×÷]*?)(?= work| find|\\.(?: |$)|$| \\[)", in: before)
            guard rules.count == 1, let rule = sum(raised(rules[0][1])), rule.symbols == [letter] else { return nil }
            func size(_ n: Int) -> Double? { amount(rule.substituting(letter, with: .integer(n))) }
            func holds(_ n: Int) -> Bool? {
                guard let value = size(n) else { return nil }
                switch asked[3].lowercased() {
                case "greater than", "more than", "bigger than": return value > limit
                case "at least": return value >= limit
                case "less than", "smaller than", "fewer than": return value < limit
                default: return value <= limit
                }
            }
            let wantsLeast = ["least", "smallest", "lowest"].contains(asked[1].lowercased())
            let goesUp = ["greater than", "more than", "bigger than", "at least"].contains(asked[3].lowercased())
            // "Least … greater than" and "greatest … less than" are the ones with an answer, for something that keeps growing.
            guard wantsLeast == goesUp, let first = size(1), let far = size(100_000), far > first else { return nil }
            var answer: Int?
            if wantsLeast {
                answer = (1...100_000).first { holds($0) == true }
            } else {
                guard holds(1) == true, let over = (1...100_000).first(where: { holds($0) != true }) else { return nil }
                answer = over - 1
            }
            guard let answer, let at = size(answer), let beside = size(wantsLeast ? answer - 1 : answer + 1) ?? Optional(0) else { return nil }
            return made(.integer(answer), decimals: false,
                        [Step("Try values of \(letter) round where it crosses \(asked[4])", "\(Format.text(rule)) has to be \(asked[3]) \(asked[4]).",
                              [MathLine(.symbol("\(letter) = \(wantsLeast ? answer - 1 : answer + 1)"), plain(beside)), MathLine(.symbol("\(letter) = \(answer)"), plain(at))])])
        }
        // "The graph y = x² is reflected in the x axis. Write down the equation of the graph after this transformation."
        if let found = groups(#"\by ?= ?([-+*/^(). \dx×÷]*[\dx)]) is reflected in the ([xy])[- ]axis"#, in: text), has(#"equation of the (?:graph|curve)|write down the equation|work out the equation"#, text),
           let curve = sum(raised(found[1])), curve.symbols == ["x"] {
            let inX = found[2].lowercased() == "x"
            let after = Simplify.run(inX ? -curve : curve.substituting("x", with: -Expr.symbol("x")))
            return told("y = \(Format.text(curve)) reflected in the \(found[2])-axis", [MathLine(.symbol("y"), after)],
                        [Step(inX ? "Every y changes sign" : "Every x changes sign", inX ? "A reflection in the x-axis turns each point's height upside down, so y becomes −y." : "A reflection in the y-axis swaps left and right, so x becomes −x.")])
        }
        // "A different cylinder has radius 3r and height 2h. How many times bigger is its volume?" (the first has radius r and height h)
        if let found = groups(#"\b(cylinder|cone) has radius (\d+(?:\.\d+)?)r and height (\d+(?:\.\d+)?)h\b"#, in: text), has(#"how many times (?:bigger|greater|larger|as big|as large|the volume)"#, text),
           has(#"\bradius r\b"#, text), has(#"\bheight h\b"#, text), let across = Double(found[2]), let up = Double(found[3]) {
            // What it's compared with has to be the same kind of solid: a cone has the ⅓ that a cylinder hasn't.
            if let against = groups(#"than the volume of (?:the )?(?:(cylinder|cone) )?(?-i:([A-Z]))\b"#, in: text) {
                let kind = groups("\\b(?:a|the) ([a-z]+),? (?-i:\(against[2]))\\b", in: text)?[1] ?? against[1]
                guard kind.lowercased() == found[1].lowercased() else { return nil }
            } else {
                guard !has(found[1].lowercased() == "cylinder" ? #"\bcone\b"# : #"\bcylinder\b"#, text) else { return nil }
            }
            return made(plain(across * across * up), decimals: false,
                        [Step("See what each change does to the volume", "The volume goes by radius² × height. The radius is \(found[2]) times as big, which multiplies the volume by \(written(across * across)); the height is \(found[3]) times as big, which multiplies it by \(found[3]).")])
        }
        // "To the nearest pound, Jon has £9. To the nearest 50p, Ellie has £6.50. Work out the maximum possible total."
        if let asked = groups(#"\b(maximum|greatest|largest|minimum|least|smallest) possible total"#, in: text) {
            let amounts = every(#"to the nearest (pound|£1|penny|£(\d+)|(\d+) ?p)\b,? [a-z]+ has £(\d+(?:\.\d+)?)"#, in: question.money)
            guard amounts.count >= 2, amounts.count == every(#"to the nearest"#, in: text).count else { return nil }
            let wantsMost = ["maximum", "greatest", "largest"].contains(asked[1].lowercased())
            var total = 0.0
            var lines: [MathLine] = []
            for amount in amounts {
                // Money comes in whole pennies.
                let step: Double = amount[1].lowercased() == "pound" || amount[1] == "£1" ? 100 : (amount[2].isEmpty ? Double(amount[3]) ?? 0 : (Double(amount[2]) ?? 0) * 100)
                guard step >= 2, let size = Double(amount[4]).map({ ($0 * 100).rounded() }) else { return nil }
                let end = wantsMost ? size + (step / 2).rounded(.up) - 1 : size - (step / 2).rounded(.down)
                total += end
                lines.append(MathLine(.symbol("£\(amount[4]) to the nearest \(amount[1])"), .symbol(pounds(end / 100))))
            }
            return told(asked[0], [MathLine(.symbol(String(format: "£%.2f", total / 100)))],
                        [Step("Find the \(wantsMost ? "most" : "least") each could be", wantsMost ? "Half the rounding amount more would round up, so it's a penny less than that." : "Half the rounding amount less still rounds up to it.", lines),
                         Step("Add them", "")])
        }
        // "A bowl is a hemisphere with radius 12 cm. Water is poured in at 325 cm³ per second for 8 seconds. Does the water fill more than 70% of the bowl?"
        if let bowl = groups(#"\b(?:is|are) a hemisphere (?:of|with) radius (\d+(?:\.\d+)?) ?cm\b"#, in: text), let flow = groups(#"\brate of (\d+(?:\.\d+)?) ?cm\^?3 per (second|minute)"#, in: text),
           every(#"\bradius\b"#, in: text).count <= 2, let radius = Double(bowl[1]), let rate = Double(flow[1]), rate > 0 {
            let volume = 2.0 / 3.0 * Double.pi * pow(radius, 3)
            let first = Step("Find the volume of the hemisphere", "Half of a sphere: ½ × 4/3 × π × radius³.", [MathLine(.symbol("2/3 × π × \(bowl[1])³"), plain((volume * 10).rounded() / 10), relation: "≈")])
            if let time = groups("\\bfor (\\d+(?:\\.\\d+)?) \(flow[2])s?\\b", in: text), let asked = groups(#"\bdoes [a-z ]+? fill (more|less) than (\d+(?:\.\d+)?) ?% of"#, in: text), let seconds = Double(time[1]), let share = Double(asked[2]) {
                let filled = rate * seconds / volume * 100
                guard abs(filled - share) > 0.05 else { return nil }
                let yes = asked[1].lowercased() == "more" ? filled > share : filled < share
                return told(asked[0], [MathLine(.symbol("\(yes ? "Yes" : "No"): \(written((filled * 10).rounded() / 10))% is filled"))],
                            [first, Step("Find how much goes in", "\(flow[1]) cm³ each \(flow[2]) for \(time[1]) \(flow[2])s.", [MathLine(.symbol("\(flow[1]) × \(time[1])"), plain(rate * seconds))]),
                             Step("Write it as a percentage of the hemisphere", "", [MathLine(.symbol("\(written(rate * seconds)) ÷ \(written((volume * 10).rounded() / 10)) × 100"), plain((filled * 10).rounded() / 10), relation: "≈")])])
            }
            if let asked = groups(#"\bdoes it take (less|more) than (a quarter of an hour|half an hour|an hour|(\d+(?:\.\d+)?) (minutes|seconds|hours))"#, in: text) {
                // The time in the rate's own unit, and what it's set against in the same.
                let per = flow[2].lowercased() == "second" ? 1.0 : 60.0
                let against: Double
                switch asked[2].lowercased() {
                case "a quarter of an hour": against = 900
                case "half an hour": against = 1800
                case "an hour": against = 3600
                default: guard let size = Double(asked[3]), let kind = unit(asked[4]) else { return nil }; against = size * kind.size
                }
                let took = volume / rate * per
                guard abs(took - against) > against * 0.001 else { return nil }
                let yes = asked[1].lowercased() == "less" ? took < against : took > against
                let inMinutes = against >= 60
                let shown = inMinutes ? "\(written((took / 60 * 10).rounded() / 10)) minutes" : "\(written((took * 10).rounded() / 10)) seconds"
                return told(asked[0], [MathLine(.symbol("\(yes ? "Yes" : "No"): it takes \(shown)"))],
                            [first, Step("Divide by the rate", "\(flow[1]) cm³ go in each \(flow[2]).", [MathLine(.symbol("\(written((volume * 10).rounded() / 10)) ÷ \(flow[1])"), plain((volume / rate * 10).rounded() / 10), relation: "≈", suffix: "\(flow[2])s")]),
                             Step("Compare", "\(asked[2].capitalized) is \(written(against / (inMinutes ? 60 : 1))) \(inMinutes ? "minutes" : "seconds").")])
            }
        }
        // "a : b = 4 : 3. Circle the correct statement. b is 4/7 of a …"
        if has("correct statement", text), let ratio = groups(#"(?<![a-z])([a-z]) ?: ?([a-z]) ?= ?(\d+) ?: ?(\d+)(?!\d|\.\d| ?:)"#, in: text), let first = Int(ratio[3]), let second = Int(ratio[4]), first > 0, second > 0, ratio[1] != ratio[2] {
            let statements = every(#"(?<![a-z])([a-z]) ?is (\d+)/(\d+) of ([a-z])\b"#, in: text)
            let right = statements.filter { said in
                guard let top = Int(said[2]), let bottom = Int(said[3]), bottom > 0 else { return false }
                // "b is 3/4 of a" says b ÷ a = 3/4.
                if said[1].lowercased() == ratio[2].lowercased(), said[4].lowercased() == ratio[1].lowercased() { return top * first == bottom * second }
                if said[1].lowercased() == ratio[1].lowercased(), said[4].lowercased() == ratio[2].lowercased() { return top * second == bottom * first }
                return false
            }
            guard statements.count >= 2, right.count == 1 else { return nil }
            return told(ratio[0], [MathLine(.symbol("\(right[0][1]) is \(right[0][2])/\(right[0][3]) of \(right[0][4])"))],
                        [Step("Write one as a fraction of the other", "For every \(first) of \(ratio[1]) there are \(second) of \(ratio[2]), so \(ratio[2]) is \(second)/\(first) of \(ratio[1]), and \(ratio[1]) is \(first)/\(second) of \(ratio[2]).")])
        }
        return nil
    }

    // MARK: Functions written f(x)

    /// "f(x) = 5 - x and g(x) = 3x + 7": Simplify f(2x) + g(x - 1); Solve gh(x) = 24; Solve g⁻¹(x) = 2x.
    private static func functions(_ text: String) -> Problem? {
        let stop = #"(?= and [fgh]\(x\) ?=| [fgh918] ?\((?:x|×)\) ?=| work out| find| calculate| evaluate| circle| solve| show| simplify| write|\.(?: |$)|$| \[)"#
        var bodies: [String: Expr] = [:]
        var spare: Expr?   // a rule whose letter was read as a digit: 9 or 8 for g, 1 for f
        // (Not "Solve f(x) = 17", which asks; and a part's letter after a rule, "f(x) = 4x − 7 (a)", isn't in it.)
        // (Where the x in the brackets is read as ×, so is the x after it: "8(×) = 4×".)
        for rule in every("(?<![a-z0-9.^(-])(?<!solve )(?<!equation )([fgh918]) ?\\((x|×)\\) ?= ?(.+?)\(stop)", in: text).map({ [$0[0], $0[1], $0[2] == "×" ? $0[3].replacingOccurrences(of: "×", with: "x") : $0[3]] }) {
            let isDigit = rule[1] == "9" || rule[1] == "1" || rule[1] == "8"
            guard let body = sum(raised(rule[2].replacingOccurrences(of: "°", with: "").replacingOccurrences(of: #" ?\((?:[a-h]|[ivx]+)\)$"#, with: "", options: .regularExpression))), body.symbols.isSubset(of: ["x"]) else { if isDigit { continue } else { return nil } }
            if isDigit { guard spare == nil else { return nil }; spare = body; continue }
            guard bodies[rule[1].lowercased()] == nil else { return nil }
            bodies[rule[1].lowercased()] = body
        }
        guard !bodies.isEmpty || spare != nil else { return nil }
        // The letters the question uses: fg(6), gh(x), f(2x).
        let used = Set(every(#"(?<![a-z])([fgh]{1,2}) ?(?:\^ ?\(?-1\)?|-1)? ?\("#, in: text).flatMap { $0[1].lowercased().map(String.init) })
        let missing = used.subtracting(bodies.keys)
        guard missing.count <= (spare == nil ? 0 : 1) else { return nil }
        /// The rule for a letter; the one read as a digit stands for the only letter used that has no rule.
        func body(_ name: String) -> Expr? {
            if let known = bodies[name] { return known }
            if let spare, missing == [name] { return spare }
            return nil
        }
        /// fg(x): g first, then f of what that gives.
        func composed(_ names: String, of inside: Expr) -> Expr? {
            var current = inside
            for name in names.lowercased().reversed() {
                guard let rule = body(String(name)) else { return nil }
                current = rule.substituting("x", with: current)
            }
            return current
        }
        let end = #"(?=$| ?\[| answer| give| you| circle|\.(?: |$)| [a-z] ?=$)"#
        // "f(x) = sin(x − 90°). Circle the value of f(0°)"
        if let asked = groups(#"(?:work out|find|calculate|evaluate|circle)(?: the value of)? ([fgh])\((-?\d+(?:\.\d+)?) ?°\)(?! ?[+×*/=^]| - |-| ?x ?[\d(])"#, in: text), let start = value(asked[2]), let rule = body(asked[1].lowercased()), rule.containsFunction {
            var problem = made(rule.substituting("x", with: start), decimals: false, [Step("Put the angle in for x", "\(asked[1])(x) = \(Format.text(rule)), with x = \(asked[2])°.")])
            problem.angles = .degrees
            return problem
        }
        // "Work out the value of fg(6)"
        if let asked = groups(#"(?:work out|find|calculate|evaluate|circle)(?: the value of)? ([fgh]{1,2})\((-?\d+(?:\.\d+)?)\)(?! ?[+×*/=^]| - |-| ?x ?[\d(])"#, in: text), let start = value(asked[2]) {
            var current = start
            var lines: [MathLine] = []
            for name in asked[1].lowercased().reversed() {
                guard let rule = body(String(name)) else { return nil }
                let next = Simplify.run(rule.substituting("x", with: current))
                guard next.symbols.isEmpty else { return nil }
                lines.append(MathLine(.symbol("\(name)(\(Format.text(current)))"), next))
                current = next
            }
            return made(current, decimals: false, [Step(asked[1].count == 2 ? "Work from the inside out" : "Put the number in for x", asked[1].count == 2 ? "\(asked[1])(\(asked[2])) means \(asked[1].suffix(1)) first, then \(asked[1].prefix(1)) of what that gives." : "", lines)])
        }
        // "Solve g⁻¹(x) = 2x": the same as x = g(2x).
        if let found = groups("\\bsolve ([fgh]) ?(?:\\^ ?\\(?-1\\)?|-1) ?\\(x\\) ?= ?([-+*/^(). \\dx×÷]+?)\(end)", in: text), let other = sum(raised(found[2])), let rule = body(found[1].lowercased()) {
            var problem = Problem(kind: .solve([Equation(left: rule.substituting("x", with: other), right: .symbol("x"))], unknowns: ["x"]), text: "", usesDecimals: false)
            problem.lead = [Step("Undo the inverse", "\(found[1])⁻¹(x) = \(Format.text(other)) says that \(found[1]) takes \(Format.text(other)) back to x, so \(found[1])(\(Format.text(other))) = x.", [MathLine(Simplify.run(rule.substituting("x", with: other)), .symbol("x"))])]
            return problem
        }
        // "Solve gh(x) = 24"
        if let found = groups("\\bsolve (?:the equation )?([fgh]{1,2}) ?\\(x\\) ?= ?([-+*/^(). \\dx×÷]+?)\(end)", in: text), let other = sum(raised(found[2])), let left = composed(found[1], of: .symbol("x")) {
            var problem = Problem(kind: .solve([Equation(left: Simplify.run(left), right: other)], unknowns: ["x"]), text: "", usesDecimals: false)
            problem.lead = [Step("Write \(found[1])(x) out", found[1].count == 2 ? "\(found[1])(x) means \(found[1].suffix(1)) first, then \(found[1].prefix(1)) of what that gives." : "", [MathLine(.symbol("\(found[1])(x)"), Simplify.run(left))])]
            return problem
        }
        // "Simplify f(2x) + g(x - 1)", "Work out an expression for fg(x)"
        if let found = groups("\\b(?:simplify|expand|work out an expression for|write an expression for|find an expression for) ((?:[-+*/^(). \\dx×÷]|[fgh]{1,2}\\()+?)\(end)", in: text), found[1].range(of: #"[fgh]\("#, options: .regularExpression) != nil {
            // Each f(…) is swapped for a letter, and the letter for the rule with the bracket's contents put in.
            var written = found[1]
            var parts: [String: Expr] = [:]
            let spares = ["α", "β", "γ", "δ"]
            for spareName in spares {
                guard let call = groups(#"([fgh]{1,2})\(([^()]*)\)"#, in: written), let whole = written.range(of: call[0]) else { break }
                guard let inside = sum(raised(call[2])), inside.symbols.isSubset(of: Set(["x"]).union(spares)) else { return nil }
                var filled = inside
                for (name, size) in parts { filled = filled.substituting(name, with: size) }
                guard let value = composed(call[1], of: filled) else { return nil }
                parts[spareName] = value
                written.replaceSubrange(whole, with: spareName)
            }
            guard written.range(of: #"[fgh]\("#, options: .regularExpression) == nil, var expr = sum(written) else { return nil }
            for _ in 0..<parts.count { for (name, size) in parts { expr = expr.substituting(name, with: size) } }
            guard expr.symbols.isSubset(of: ["x"]) else { return nil }
            let tidy = Simplify.run(Simplify.expand(expr))
            return told(found[1], [MathLine(tidy)], [Step("Put what's in each bracket in for x", bodies.keys.sorted().map { "\($0)(x) = \(Format.text(bodies[$0]!))" }.joined(separator: ", ") + ".", [MathLine(expr, tidy)])])
        }
        return nil
    }

    // MARK: Sharing and rates

    /// "2 people … take 6 hours … how long will it take 3 people": more people, less time.
    private static func share(_ text: String) -> Problem? {
        // "15 workers can complete a job in 8 days. How many more workers are needed to complete the job in 6 days?"
        let who = #"(?:people|workers|men|women|builders|painters|machines|pumps|taps)"#
        if let first = groups(#"\b(\d+) \#(who) (?:can |will |could )?(?:complete|do|build|finish|paint|dig|make)[a-z ]*? in (\d+(?:\.\d+)?) (hours?|days?|minutes?|weeks?)"#, in: text),
           let second = groups(#"how many (more |extra )?\#(who) are needed to (?:complete|do|build|finish|paint|dig|make)[a-z ]*? in (\d+(?:\.\d+)?) (hours?|days?|minutes?|weeks?)"#, in: text),
           single(first[3]) == single(second[3]), let people = Double(first[1]), let time = Double(first[2]), let wanted = Double(second[2]), wanted > 0 {
            let needed = people * time / wanted
            guard abs(needed - needed.rounded()) < 1e-9 else { return nil }
            let isMore = !second[1].isEmpty
            var lead = [Step("Find the work for one", "\(first[1]) taking \(first[2]) \(first[3]) is \(written(people * time)) lots of one worker for one \(single(first[3])).", [MathLine(.multiply([plain(people), plain(time)]), plain(people * time))]),
                        Step("Share it over the time there is", "In \(second[2]) \(second[3]) that needs \(written(people * time)) ÷ \(second[2]) = \(written(needed)).")]
            if isMore { lead.append(Step("Take away the ones there already", "\(written(needed)) are needed and \(first[1]) are there.")) }
            return made(isMore ? plain(needed) - plain(people) : plain(needed), decimals: false, lead)
        }
        guard let first = groups(#"(\d+) (?:people|workers|men|women|builders|painters|machines|pumps|taps)[^.?]*?\btake(?:s)? (\d+(?:\.\d+)?) (hours?|days?|minutes?|weeks?)"#, in: text),
              let whole = text.range(of: first[0], options: .caseInsensitive),
              let second = groups(#"(\d+) (?:people|workers|men|women|builders|painters|machines|pumps|taps)"#, in: String(text[whole.upperBound...])),
              text.range(of: #"how long|how many (?:hours|days|minutes|weeks)"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let people = Double(first[1]), let time = Double(first[2]), let others = Double(second[1]), others > 0 else { return nil }
        let unit = first[3].hasSuffix("s") ? first[3] : first[3] + "s"
        return made(.multiply([.multiply([Worded.whole(people), Worded.whole(time)]), .power(Worded.whole(others), .minusOne)]), decimals: true,
                    [Step("Find the work for one", "\(first[1]) taking \(first[2]) \(unit) is the same as one taking \(Format.text(Worded.whole(people * time))) \(unit) alone.",
                          [MathLine(.multiply([Worded.whole(people), Worded.whole(time)]), Worded.whole(people * time))]),
                     Step("Share it out", "With \(second[1]), each does a share of it, so it takes that long divided by \(second[1]).")])
    }

    /// "A car travels 3.5 miles in 5 minutes. Work out the average speed in miles per hour."
    private static func rate(_ text: String) -> Problem? {
        let journey = #"(\d+(?:\.\d+)?) ?(miles|km|kilometres|metres|m) in (\d+(?:\.\d+)?) ?(hours?|minutes?|seconds?)"#
        // One journey at one speed: not one in stages.
        guard has(#"average speed|speed of"#, text), every(journey, in: text).count == 1, let found = groups(journey, in: text),
              !has(#"\bfirst\b|\brest\b|\bthen\b|\bstage\b|\breturn\b|\bstops?\b|\bwhole\b|\bremaining\b|\bnext\b|\bboth\b|\beach\b"#, text),
              let distance = value(found[1]), var time = value(found[3]), amount(time) ?? 0 > 0 else { return nil }
        var words = "\(found[1]) \(found[2]) in \(found[3]) \(found[4])."
        // "in miles per hour": the time in hours.
        if let asked = groups(#"\b(?:in|as) (miles|km|kilometres|metres|m) per (hour|minute|second)\b|\b(mph|km/h|m/s)\b"#, in: text) {
            let per = asked[3].isEmpty ? asked[2].lowercased() : ["mph": "hour", "km/h": "hour", "m/s": "second"][asked[3].lowercased()] ?? ""
            let far = asked[3].isEmpty ? asked[1].lowercased() : ["mph": "miles", "km/h": "km", "m/s": "m"][asked[3].lowercased()] ?? ""
            func length(_ word: String) -> String { ["kilometres": "km", "metres": "m"][word] ?? word }
            guard length(far) == length(found[2].lowercased()), let have = unit(found[4]), let want = unit(per), have.kind == "time", want.kind == "time" else { return nil }
            if have.size != want.size {
                time = time * plain(have.size) / plain(want.size)
                words += " \(found[3]) \(found[4]) is \(Format.text(Simplify.run(time))) of a\(per == "hour" ? "n" : "") \(per)."
            }
        }
        if has(unitsAsked, text), let size = amount(distance / time) {
            let asked = groups(#"\b(?:in|as) (miles|km|kilometres|metres|m) per (hour|minute|second)\b|\b(mph|km/h|m/s)\b"#, in: text)
            let unit = asked.map { $0[3].isEmpty ? "\($0[1]) per \($0[2])" : $0[3] } ?? "\(found[2]) per \(single(found[4]))"
            return told(found[0], [MathLine(.symbol("\(written(size)) \(unit)"))], [Step("Speed is distance divided by time", words)])
        }
        return made(distance / time, decimals: true, [Step("Speed is distance divided by time", words)])
    }

    // MARK: Factors and multiples

    /// "the highest common factor (HCF) of 24 and 36", "the lowest common multiple of 6 and 8"
    private static func factors(_ text: String) -> Problem? {
        // "A = 2² × 3⁴ × 7, B = 3² × 7². Find the highest common factor (HCF) of A and B."
        let commonAsks = [#"(?:highest common factor|\bHCF\b)[^.\d]{0,12}? of (?-i:[A-Z]) and (?-i:[A-Z])\b"#, #"(?:lowest common multiple|least common multiple|\bLCM\b)[^.\d]{0,12}? of (?-i:[A-Z]) and (?-i:[A-Z])\b"#]
        // (Where the numbers aren't given that way, the question is left to the kind below.)
        func fromPrimes() -> Problem? {
            guard let which = chosenAsk(text.replacingOccurrences(of: #" ?\((?:HCF|LCM)\)"#, with: "", options: [.regularExpression, .caseInsensitive]), commonAsks),
                  let asked = groups(which == 0 ? #"(highest common factor|\bHCF\b)[^.\d]{0,12}? of (?-i:([A-Z])) and (?-i:([A-Z]))\b"# : #"(lowest common multiple|least common multiple|\bLCM\b)[^.\d]{0,12}? of (?-i:([A-Z])) and (?-i:([A-Z]))\b"#, in: text), asked[2] != asked[3] else { return nil }
            var powers: [String: [Int: Int]] = [:]
            for found in every(#"(?<![A-Za-z])(?-i:([A-Z])) ?= ?((?:\d+(?:\^\(?\d+\)?)? ?[×x*] ?)+\d+(?:\^\(?\d+\)?)?)(?!\d|\^| ?[×x*+/-])"#, in: text) where [asked[2], asked[3]].contains(found[1]) {
                guard powers[found[1]] == nil else { return nil }
                var map: [Int: Int] = [:]
                for piece in every(#"(\d+)(?:\^\(?(\d+)\)?)?"#, in: found[2]) {
                    guard let base = Int(piece[1]), isPrime(base), let power = piece[2].isEmpty ? 1 : Int(piece[2]), power >= 1, power <= 30 else { return nil }
                    map[base, default: 0] += power
                }
                powers[found[1]] = map
            }
            guard let a = powers[asked[2]], let b = powers[asked[3]] else { return nil }
            let wantsFactor = asked[1].lowercased().contains("factor") || asked[1].uppercased() == "HCF"
            var result: [Int: Int] = [:]
            for prime in Set(a.keys).union(b.keys) {
                let power = wantsFactor ? min(a[prime] ?? 0, b[prime] ?? 0) : max(a[prime] ?? 0, b[prime] ?? 0)
                if power > 0 { result[prime] = power }
            }
            var size = 1.0
            for (prime, power) in result { size *= pow(Double(prime), Double(power)) }
            guard size < 1e15 else { return nil }
            func product(_ map: [Int: Int]) -> String { map.isEmpty ? "1" : map.keys.sorted().map { "\($0)\(map[$0]! == 1 ? "" : raisedDigits(map[$0]!))" }.joined(separator: " × ") }
            return made(plain(size), decimals: false,
                        [Step("Line up the primes", "", [MathLine(.symbol(asked[2]), .symbol(product(a))), MathLine(.symbol(asked[3]), .symbol(product(b)))]),
                         Step(wantsFactor ? "Take each prime the fewest times it appears in both" : "Take each prime the most times it appears in either",
                              wantsFactor ? "A prime that is missing from one of them is left out." : "", [MathLine(.symbol(wantsFactor ? "HCF" : "LCM"), .symbol(product(result)))])])
        }
        if let problem = fromPrimes() { return problem }
        guard let found = groups(#"(highest common factor|lowest common multiple|least common multiple|\bHCF\b|\bLCM\b)[^\d]{0,12}(\d+)(?:,| and) (\d+)(?:(?:,| and) (\d+))?(?!\d|\.\d| ?[×÷*/+^]| - \d| ?x ?[\d(])"#, in: text) else { return nil }
        let numbers = [found[2], found[3], found[4]].compactMap { Int($0) }.filter { $0 > 0 && $0 < 1_000_000 }
        guard numbers.count >= 2 else { return nil }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        func primes(_ n: Int) -> String {
            var rest = n, factor = 2
            var parts: [String] = []
            while rest > 1 {
                if rest % factor == 0 { parts.append(String(factor)); rest /= factor } else { factor += 1 }
            }
            return parts.joined(separator: " × ")
        }
        let wantsFactor = found[1].lowercased().contains("factor") || found[1].uppercased() == "HCF"
        let lines = numbers.map { MathLine(.symbol("\($0) = \(primes($0))")) }
        if wantsFactor {
            return made(.integer(numbers.dropFirst().reduce(numbers[0], gcd)), decimals: false,
                        [Step("Write each as a product of primes", "The highest common factor is made of the primes they all share.", lines)])
        }
        let multiple = numbers.dropFirst().reduce(numbers[0]) { $0 / gcd($0, $1) * $1 }
        return made(.integer(multiple), decimals: false, [Step("Write each as a product of primes", "The lowest common multiple has each prime as many times as the number that has it most.", lines)])
    }

    // MARK: Rounding

    /// "Round 3.4567 to 2 decimal places", "to 3 significant figures", "to the nearest 10"
    private static func rounding(_ text: String) -> Problem? {
        guard let found = groups("(?:round|write|give) (\(number)) (?:correct )?to (?:the nearest (whole number|integer|ten|hundred|thousand|\\d+)|(\\d+) (decimal places?|d\\.?p\\.?|significant figures?|s\\.?f\\.?))", in: text),
              let size = value(found[1]).flatMap(amount) else { return nil }
        var rounded = size
        var how = ""
        if !found[2].isEmpty {
            let names = ["whole number": 1.0, "integer": 1, "ten": 10, "hundred": 100, "thousand": 1000]
            guard let unit = names[found[2].lowercased()] ?? Double(found[2]), unit > 0 else { return nil }
            rounded = (size / unit).rounded(.toNearestOrAwayFromZero) * unit
            how = "Look at the digit after the place you're rounding to: 5 or more rounds up."
        } else if let places = Int(found[3]), places >= 0, places <= 8 {
            if found[4].lowercased().hasPrefix("d") {
                let scale = pow(10, Double(places))
                rounded = (size * scale).rounded(.toNearestOrAwayFromZero) / scale
                how = "Keep \(places) digit\(places == 1 ? "" : "s") after the point. The next digit decides: 5 or more rounds up."
            } else {
                guard size != 0, places >= 1 else { return nil }
                let scale = pow(10, Double(places) - 1 - floor(log10(abs(size))))
                rounded = (size * scale).rounded(.toNearestOrAwayFromZero) / scale
                how = "Count \(places) digit\(places == 1 ? "" : "s") from the first that isn't a nought. The next digit decides: 5 or more rounds up."
            }
        }
        guard !how.isEmpty else { return nil }
        return made(whole(rounded), decimals: true, [Step("Round it", how)])
    }

    // MARK: Sums in words

    /// "the number that is 5 less than −2", "20% of 14000", "3/5 of 40", "increase 80 by 15%", "12 as a percentage of 60"
    private static func phrase(_ text: String) -> Problem? {
        func two(_ pattern: String) -> (Expr, Expr, [String])? {
            guard let found = groups(pattern, in: text), let a = value(found[1]), let b = value(found[2]) else { return nil }
            return (a, b, found)
        }
        let hundred = Expr.power(.integer(100), .minusOne)
        let said = "(?:\\bis|\\bwork out|\\bfind|\\bwrite down|\\bcalculate|\\bwhat is) "
        if asks(text), let (a, b, found) = two("\(said)(\(number)) (?:less|fewer|smaller|lower) than (\(number))(?! ?(?:times|%|[a-z(]))") {
            return made(.add([b, .multiply([.minusOne, a])]), decimals: true, [Step("Write it as a sum", "\(found[1]) less than \(found[2]) means start at \(found[2]) and take \(found[1]) away.")])
        }
        if asks(text), let (a, b, found) = two("\(said)(\(number)) (?:more|greater|bigger|higher) than (\(number))(?! ?(?:times|%|[a-z(]))") {
            return made(.add([b, a]), decimals: true, [Step("Write it as a sum", "\(found[1]) more than \(found[2]) means start at \(found[2]) and add \(found[1]).")])
        }
        // The sum is all there is: nothing in front of its numbers or after them that belongs to a longer sum
        // ("30% of 60 + 25% of 80", "3 × 5 as a percentage of 60").
        let before = #"(?<![×÷*/+^=] )(?<![×÷*/+^=\d.])(?<!- )(?<!\d x )"#, after = #"(?!\d|\.\d| ?[×÷*/+^]| - \d| ?x ?[\d(√])"#
        if let (a, b, _) = two("(?:increase|raise) \(before)(\(number)) by (\(number)) ?%\(after)") {
            return made(.multiply([a, .add([.one, .multiply([b, hundred])])]), decimals: true, [Step("Find the multiplier", "Increasing by a percentage is multiplying by 1 plus that many hundredths.")])
        }
        if let (a, b, _) = two("(?:decrease|reduce|lower) \(before)(\(number)) by (\(number)) ?%\(after)") {
            return made(.multiply([a, .add([.one, .multiply([.minusOne, b, hundred])])]), decimals: true, [Step("Find the multiplier", "Decreasing by a percentage is multiplying by 1 take away that many hundredths.")])
        }
        // (Asked for outright: the words that ask come straight before the sum, so a story that only mentions "20% of 50" isn't answered with it.)
        let direct = #"(?:\b(?:work out|find|calculate|what is|what's|write down|write|express|circle|give)(?: the value of| the answer to)?:? )"#
        if let (a, b, _) = two("\(direct)\(before)(\(number)) as a percentage of (\(number))\(after)") {
            return made(.multiply([a, .power(b, .minusOne), .integer(100)]), decimals: true, [Step("Write it as a fraction, then a percentage", "Divide the first by the second, and multiply by 100.")])
        }
        if every(#"\d ?% of\b"#, in: text).count == 1, let (a, b, found) = two("\(direct)\(before)(\(number)) ?% of (\(number))\(after)") {
            return made(.multiply([.multiply([a, hundred]), b]), decimals: true, [Step("Write it as a sum", "\(found[1])% is \(found[1]) hundredths, and \"of\" means multiply.")])
        }
        if every(#"\d/\d+ of\b"#, in: text).count == 1, let (a, b, _) = two("\(direct)\(before)(\\d+/\\d+) of (-?\\d+(?:\\.\\d+)?)\(after)") {
            return made(.multiply([a, b]), decimals: false, [Step("Write it as a sum", "\"Of\" means multiply: divide by the bottom of the fraction and multiply by the top.")])
        }
        return nil
    }
}
