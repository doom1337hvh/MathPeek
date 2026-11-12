import Foundation

/// Number work asked in words: recurring decimals as fractions, surds, fractional and negative powers, estimating, sums in standard form, highest common factors and lowest common multiples in a story, interest and depreciation, three-way ratios, shares and ratios that change, average speeds and times, bounds, estimates by rounding, offers in shops.
/// Tried after `Worded.problem`, on the same text: the lines of the question the pointer is
/// in, joined by line breaks. Nil unless the whole of the question is understood.
enum WordedNumber {
    static func problem(_ input: String) -> Problem? {
        let lines = cleaned(input)
        guard !lines.isEmpty else { return nil }
        let text = lines.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard text.count <= 700, !has(refusal, text) else { return nil }
        let kinds: [() -> Problem?] = [
            { closest(lines) }, { threeWayRatio(text) }, { inTermsOf(text) }, { linkedRatios(text) }, { recurringDecimal(text) }, { recurringFraction(text) },
            { yearsToReach(text) }, { growth(text) }, { unknownRate(text) }, { roundedRoot(text) }, { togetherAgain(text) },
            { ordered(lines) }, { linkedProfits(text) }, { twoSavings(text) }, { countIncrease(text) }, { evenedOut(text) },
            { sameRate(text) }, { missingPrice(text) }, { perKilogram(text) }, { shareEach(text) }, { bandedTax(text) },
            { fractionOf(text) }, { recipe(text) }, { percentChain(text) }, { ratioAfterChange(text) }, { ratioForm(text) }, { shareFromOne(text) }, { bounds(text) }, { cheaper(text) }, { journey(text) }, { nextStretch(text) },
            { stages(text) }, { backToStart(text) }, { beforeChange(text) }, { percentOfNumber(text) }, { percentOfPart(text) }, { combinedPercent(text) },
            { proportionPercent(text) }, { percentChange(text) }, { ratioWithDifference(text) },
            { dayChain(text) }, { rateFromOneYear(text) }, { mixLimit(text) }, { taxOnInterest(text) }, { percentThenRatio(text) }, { percentFromMultiplier(text) },
            { safeLoad(text) }, { earnedFromTax(text) }, { whoseMore(text) }, { bestValue(text) }, { certainEnough(text) },
            { moreThanBefore(text) }, { bagsProfit(text) }, { costRatio(text) }, { rateTime(text) }, { simpleInterest(text) },
            { decimalAsFraction(text) }, { wholeJourneySpeed(text) }, { mostWithShare(lines) }, { estimatedCost(text) }, { estimatedMass(text) },
            { midpointValue(text) }, { partThenRatios(text) }, { sharesAfterGiving(text) },
            { pooledShare(text) }, { dilutedCups(text) }, { formulaGap(text) }, { bestOffer(text) }, { earliestArrival(text) },
            { roundedSum(text) }, { nestedRatios(text) }, { sharedByFacts(text) }, { markNeeded(text) }, { addedToRatio(text) }, { simpleMatchesCompound(text) }, { beforeWithdrawals(text) },
            { speedBounds(text) }, { twoLegSpeed(text) }, { sameSpeedStage(text) }, { timeAtSpeed(text) },
            { ratioOneChanges(text) }, { simpleInterestRate(text) }, { payChange(text) },
            { restOfJourneySpeed(text) },
        ]
        for kind in kinds {
            if var problem = kind() {
                problem.text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                return problem
            }
        }
        return nil
    }

    // MARK: Reading the question

    private static let refusal = #"\bshow that\b|\bprove\b|\bexplain\b|\bgive (?:a|one|two|your) reasons?\b|\btick\b|\bis (?:he|she|they|it|this|that) (?:correct|right)\b|\bdraw\b|\bsketch\b|\bmatch each\b"#

    /// The question's lines, with the signs made plain and what isn't part of the question
    /// left out: the margin's "Do not write outside the box", the question's number, the marks,
    /// the answer line.
    private static func cleaned(_ input: String) -> [String] {
        var raw = input
        for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "),
                           ("’", "'"), ("‘", "'"), ("⩽", "≤"), ("⩾", "≥"), ("…", "...")] { raw = raw.replacingOccurrences(of: from, with: to) }
        // Letters from other alphabets read for ones that look the same.
        let alike: [Character: Character] = ["а": "a", "А": "A", "В": "B", "в": "b", "С": "C", "с": "c", "Е": "E", "е": "e", "К": "K", "к": "k",
                                              "М": "M", "О": "O", "о": "o", "Р": "P", "р": "p", "Т": "T", "Х": "X", "х": "x", "У": "Y", "у": "y", "З": "3", "з": "3", "т": "m"]
        raw = String(raw.map { alike[$0] ?? $0 })
        // £12 570 is one amount.
        raw = raw.replacingOccurrences(of: #"£ ?(\d{1,3}) (\d{3})(?!\d|\.\d)"#, with: "£$1$2", options: .regularExpression)
        let pieces = raw.components(separatedBy: "\n")
        // Lone numbers after the question's last words are answers to choose from; before, a question's number.
        let lastWords = pieces.lastIndex { $0.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil && $0.range(of: #"\bmarks?\b|^\s*answer\b"#, options: [.regularExpression, .caseInsensitive]) == nil } ?? -1
        var lines: [String] = []
        for (index, piece) in pieces.enumerated() {
            var line = piece.trimmingCharacters(in: .whitespaces)
            // Other boards' marks: "(Total for Question 2 is 5 marks)", "(3)", "[3]".
            line = line.replacingOccurrences(of: #"\(?Total for Question \d{1,2} is \d{1,2} marks?\)?"#, with: " ", options: [.regularExpression, .caseInsensitive])
            line = line.replacingOccurrences(of: #"(?:^|\s)[(\[]\d{1,2}[)\]]$"#, with: "", options: .regularExpression)
            // "[3]" with its closing bracket read as a 1: "[31".
            line = line.replacingOccurrences(of: #"(?:^|\s)\[\d[1lI|]$"#, with: "", options: .regularExpression)
            // The marks, however they were read: "[3 marks]", "I2 marks1", "Г3 marks1".
            line = line.replacingOccurrences(of: #"[\[(IlГ|]?\s?\d{1,2}\s?marks?\s?[\])1lI|]*"#, with: " ", options: [.regularExpression, .caseInsensitive])
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // The line drawn for the answer, read as dashes: "1----1", "______".
            if line.range(of: #"[-_.]{3,}"#, options: .regularExpression) != nil, line.range(of: #"[A-Za-z]"#, options: .regularExpression) == nil { continue }
            // The question's number and part on a line of their own: "25", "7 (a)", "(b)".
            if line.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil, index > lastWords { lines.append(line); continue }
            if line.range(of: #"^(?:\d{1,2})?\s?(?:\([a-z]\))?(?:\s?\([ivx]+\))?$"#, options: .regularExpression) != nil { continue }
            // The margin, read in pieces, and the space for the answer.
            if line.range(of: #"^(?:do not(?: write)?|outside(?: the)?(?: box)?|the box|box|bo[:;›s]?|write|answer\b.*|turn over.*|IB/M/.*)$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            // A worksheet's heading for a question: "Question 14:".
            line = line.replacingOccurrences(of: #"^Q(?:uestion)? ?\d{1,2} ?[:.)] ?(?=\S)"#, with: "", options: [.regularExpression, .caseInsensitive])
            // A question's number in front of its first words: "15 Mirek invests", "7 (a) The cube root".
            line = line.replacingOccurrences(of: #"^\d{1,2}\s+(?:\([a-z]\)\s*)?(?:\([ivx]+\)\s*)?(?=[A-Z]|£\d+(?:\.\d+)? is )"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\d{1,2}\s?\([a-z]\)\s*"#, with: "", options: .regularExpression)
            // "25 a is three quarters of c", as a page's own text has it.
            if index == 0 { line = line.replacingOccurrences(of: #"^\d{1,2}\s+(?=[a-z] )"#, with: "", options: .regularExpression) }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    // MARK: Closest in value

    /// "8300 = 100 × 83. Circle the number that is closest in value to √8300", with the
    /// numbers to choose from under it. The value of a sum of numbers is the sum itself, so
    /// anything else written above (a hint) isn't needed.
    private static func closest(_ lines: [String]) -> Problem? {
        guard let at = lines.firstIndex(where: { has(#"\b(?:closest|nearest) (?:in value )?to\b"#, $0) }),
              let asked = groups(#"\b(?:closest|nearest) (?:in value )?to\b:? ?(.*)$"#, in: lines[at]) else { return nil }
        var written = asked[1].trimmingCharacters(in: CharacterSet(charactersIn: " ?."))
        var rest = Array(lines[(at + 1)...])
        if written.isEmpty, let next = rest.first { written = next.trimmingCharacters(in: CharacterSet(charactersIn: " ?.")); rest.removeFirst() }
        // The sum asked about: numbers only.
        guard written.range(of: #"^[\d.,()√^+\-×x*÷/ ²³∛π]+$"#, options: .regularExpression) != nil, written.contains(where: \.isNumber),
              let target = Parser.expression(written.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "x", with: "×")),
              target.symbols.isEmpty, let size = Simplify.run(target).evaluate() ?? target.evaluate(), size.isFinite else { return nil }
        // The choices: the lines after it that are nothing but numbers.
        var choices: [(text: String, size: Double)] = []
        for line in rest {
            let tokens = line.split(separator: " ").map(String.init)
            guard !tokens.isEmpty, tokens.allSatisfy({ $0.range(of: #"^-?\d+(?:\.\d+)?(?:/\d+)?$"#, options: .regularExpression) != nil }) else { return nil }
            for token in tokens {
                guard let value = Parser.expression(token)?.evaluate() else { return nil }
                choices.append((token, value))
            }
        }
        guard choices.count >= 3, Set(choices.map(\.text)).count == choices.count else { return nil }
        let ranked = choices.sorted { abs($0.size - size) < abs($1.size - size) }
        let best = ranked[0], gap = abs(best.size - size)
        // A tie can't be settled, and with a choice possibly missed the nearest has to be clearly so.
        guard abs(ranked[1].size - size) > gap * 1.5 + 1e-9 else { return nil }
        if choices.count == 3 { guard gap <= abs(size) * 0.1 else { return nil } }
        var lead: [Step] = []
        let shown = Format.text(target)
        if case .power(let inside, let half) = target, half == Expr.half, let n = Simplify.run(inside).number?.double, n > 0, n == n.rounded(), n < 1e12 {
            // A square root: the square numbers either side of it.
            let below = Int(n.squareRoot()), above = below + 1
            lead.append(Step("Find the square numbers either side", "\(Int(n)) lies between \(below * below) and \(above * above).",
                             [MathLine(.power(.integer(below), .two), .integer(below * below)), MathLine(.power(.integer(above), .two), .integer(above * above)),
                              MathLine(target, number(size), relation: "≈")]))
        } else {
            lead.append(Step("Work out its size", "", [MathLine(target, number(size), relation: "≈")]))
        }
        let listed = choices.map(\.text)
        lead.append(Step("Pick the nearest", "Of \(listed.dropLast().joined(separator: ", ")) and \(listed.last!), the one nearest to \(Format.text(number(size))) is \(best.text)."))
        guard let answer = Parser.expression(best.text) else { return nil }
        return told("the number closest to \(shown)", [MathLine(answer)], lead)
    }

    // MARK: A ratio of three

    /// "a is three quarters of c. 6b = 5c. Work out the ratio a : b : c": each letter as a
    /// fraction of one of them, then the fractions made whole.
    private static func threeWayRatio(_ text: String) -> Problem? {
        guard let ask = groups(#"\bratio (?-i:([A-Za-z])) ?: ?(?-i:([A-Za-z])) ?: ?(?-i:([A-Za-z]))(?![A-Za-z0-9])"#, in: text) else { return nil }
        let names = [ask[1], ask[2], ask[3]]
        guard Set(names).count == 3 else { return nil }
        guard let (facts, rest) = letterFacts(text.replacingOccurrences(of: ask[0], with: " ")) else { return nil }
        // Two facts, about the three letters asked for, and no other numbers.
        guard facts.count == 2, facts.allSatisfy({ names.contains($0.x) && names.contains($0.y) && $0.x != $0.y && $0.k.top > 0 }),
              rest.range(of: #"\d"#, options: .regularExpression) == nil, has(#"\b(?:work out|find|write down|what is|give)\b"#, text) else { return nil }
        // The letter both facts share is the one the others are written in terms of.
        let mentioned = facts.flatMap { [$0.x, $0.y] }
        guard let base = names.first(where: { name in mentioned.filter { $0 == name }.count == 2 }) else { return nil }
        var size: [String: Fraction] = [base: Fraction(1)]
        for fact in facts {
            if fact.y == base { size[fact.x] = fact.k } else if fact.x == base { size[fact.y] = Fraction(1) / fact.k } else { return nil }
        }
        guard names.allSatisfy({ size[$0] != nil }) else { return nil }
        let parts = names.map { size[$0]! }
        let scale = parts.reduce(1) { lcm($0, $1.bottom) }
        var whole = parts.map { $0.top * (scale / $0.bottom) }
        let common = whole.reduce(0) { gcd($0, $1) }
        guard common > 0 else { return nil }
        whole = whole.map { $0 / common }
        let others = names.filter { $0 != base }
        let written = others.map { MathLine(.symbol($0), Simplify.run(size[$0]!.expr * .symbol(base))) }
        let fractions = MathLine(parts: parts.map(\.expr), relation: ":")
        let multiplier = scale / common
        var lead = [Step("Write \(others[0]) and \(others[1]) in terms of \(base)", facts.map(\.said).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", and ") + ".", written),
                    Step("Put them side by side", "\(names.joined(separator: " : ")), taking \(base) as 1.", [fractions])]
        if multiplier != 1 || parts.contains(where: { $0.bottom != 1 }) {
            lead.append(Step("Make them whole numbers", "Multiply each by \(multiplier), then they have no common factor left.", [MathLine(parts: whole.map { .integer($0) }, relation: ":")]))
        }
        return told(names.joined(separator: " : "), [MathLine(parts: whole.map { .integer($0) }, relation: ":")], lead)
    }

    /// "Given 4x = 3y and y : z = 1 : 2, find x in terms of z": two facts linking three
    /// letters through the one they share.
    private static func inTermsOf(_ text: String) -> Problem? {
        guard let ask = groups(#"\b(?:find|write|express|give|work out) (?-i:([a-z])) in terms of (?-i:([a-z]))\b"#, in: text), ask[1] != ask[2],
              let (facts, rest) = letterFacts(text.replacingOccurrences(of: ask[0], with: " ")), facts.count == 2,
              rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let (x, z) = (ask[1], ask[2])
        // The shared letter is in both facts; the asked letters one each.
        let first = facts.first { $0.x == x || $0.y == x }, second = facts.first { $0.x == z || $0.y == z }
        guard let first, let second, first.said != second.said, first.k.top > 0, second.k.top > 0 else { return nil }
        let shared = first.x == x ? first.y : first.x
        guard shared != x, shared != z, second.x == shared || second.y == shared else { return nil }
        // x as a multiple of the shared letter, then the shared letter as a multiple of z.
        let xPerShared = first.x == x ? first.k : Fraction(1) / first.k
        let sharedPerZ = second.x == shared ? second.k : Fraction(1) / second.k
        let k = xPerShared * sharedPerZ
        let answer = MathLine(.symbol(x), Simplify.run(k.expr * .symbol(z)))
        return told("\(x) in terms of \(z)", [answer],
                    [Step("Write \(x) in terms of \(shared)", first.said.trimmingCharacters(in: .whitespaces) + ".", [MathLine(.symbol(x), Simplify.run(xPerShared.expr * .symbol(shared)))]),
                     Step("Write \(shared) in terms of \(z)", second.said.trimmingCharacters(in: .whitespaces) + ".", [MathLine(.symbol(shared), Simplify.run(sharedPerZ.expr * .symbol(z)))]),
                     Step("Put one into the other", "", [answer])])
    }

    /// Facts that say one letter is a number of times another, x = k·y, and what's left of the
    /// text once they're taken out. Nil if one can't be read as a number.
    private static func letterFacts(_ text: String) -> (facts: [(x: String, y: String, k: Fraction, said: String)], rest: String)? {
        var rest = text
        var facts: [(x: String, y: String, k: Fraction, said: String)] = []
        let letter = #"(?-i:([A-Za-z]))"#
        // "a is three quarters of c", "b is twice a", "a is 3/4 of c", "c is 1.5 times b"
        for found in every("(?<![A-Za-z])\(letter) is (?:equal to )?(\(spokenFraction)|\\d+(?:\\.\\d+)?|\\(?\\d+\\)?/\\(?\\d+\\)?|\\d+ ?%|twice|double|half|treble|triple|(?:one|two|three|four|five|six|seven|eight|nine|ten) times|\\d+ times) ?(?:of |times |as (?:big|large|much|many) as )?\(letter)(?![A-Za-z])", in: rest) {
            guard let k = multiple(found[2]) else { return nil }
            facts.append((found[1], found[3], k, found[0]))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // "6b = 5c", "a = 3/4 c", "4a = 3c"
        for found in every("(?<![A-Za-z0-9.])(\\d+(?:\\.\\d+)?)? ?\(letter) ?= ?(\\d+(?:\\.\\d+)?|\\(?\\d+\\)?/\\(?\\d+\\)?)? ?\(letter)(?![A-Za-z0-9(^])", in: rest) {
            let p = found[1].isEmpty ? Fraction(1) : multiple(found[1]), q = found[3].isEmpty ? Fraction(1) : multiple(found[3])
            guard let p, let q, p.top != 0 else { return nil }
            facts.append((found[2], found[4], q / p, found[0]))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // "a : b = 2 : 3"
        for found in every("(?<![A-Za-z])\(letter) ?: ?\(letter) ?= ?(\\d+) ?: ?(\\d+)(?![\\d:])", in: rest) {
            guard let p = Int(found[3]), let q = Int(found[4]), p > 0, q > 0 else { return nil }
            facts.append((found[1], found[2], Fraction(p, q), found[0]))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        return (facts, rest)
    }

    private static let spokenFraction = #"(?:(?:a|an|one|two|three|four|five|six|seven|eight|nine|ten)[ -])?(?:half|halves|thirds?|quarters?|fourths?|fifths?|sixths?|sevenths?|eighths?|ninths?|tenths?)"#

    /// "three quarters", "twice", "3/4", "(3)/(4)", "1.5", "75%" as a number of times.
    private static func multiple(_ words: String) -> Fraction? {
        let said = words.lowercased().trimmingCharacters(in: .whitespaces)
        let counts = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
        let parts = ["half": 2, "halves": 2, "third": 3, "quarter": 4, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10]
        switch said {
        case "twice", "double": return Fraction(2)
        case "treble", "triple": return Fraction(3)
        case "half": return Fraction(1, 2)
        default: break
        }
        if let found = groups(#"^(?:([a-z]+)[ -])?([a-z]+?)s?$"#, in: said), let bottom = parts[found[2]] ?? parts[found[2] + "s"] {
            let top = found[1].isEmpty ? 1 : counts[found[1]]
            return top.map { Fraction($0, bottom) }
        }
        if let found = groups(#"^([a-z]+|\d+) times$"#, in: said) { return (counts[found[1]] ?? Int(found[1])).map { Fraction($0) } }
        if let found = groups(#"^\(?(\d+)\)?/\(?(\d+)\)?$"#, in: said), let top = Int(found[1]), let bottom = Int(found[2]), bottom > 0 { return Fraction(top, bottom) }
        if let found = groups(#"^(\d+(?:\.\d+)?) ?%$"#, in: said) { return decimal(found[1]).map { $0 / Fraction(100) } }
        return decimal(said)
    }

    // MARK: Recurring decimals

    /// "Convert 27/11 to a recurring decimal."
    private static func recurringDecimal(_ text: String) -> Problem? {
        guard let found = groups(#"\b(?:convert|write|change|express) (?:(\d+) )?\(?(\d+)\)? ?/ ?\(?(\d+)\)? (?:to|as|into) a recurring decimal\b"#, in: text),
              let top = Int(found[2]), let bottom = Int(found[3]), bottom > 1, top >= 0, top < 1_000_000 else { return nil }
        let whole = found[1].isEmpty ? 0 : (Int(found[1]) ?? -1)
        guard whole >= 0, text.replacingOccurrences(of: found[0], with: " ").range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let numerator = whole * bottom + top
        // Long division, noting each remainder: when one comes back, the digits since then repeat.
        var digits: [Int] = [], seen: [Int: Int] = [:]
        var remainder = numerator % bottom
        while remainder != 0, seen[remainder] == nil, digits.count < 60 {
            seen[remainder] = digits.count
            remainder *= 10
            digits.append(remainder / bottom)
            remainder %= bottom
        }
        guard remainder != 0, let start = seen[remainder] else { return nil }
        let front = numerator / bottom
        let fixed = digits[..<start].map(String.init).joined(), repeating = digits[start...].map(String.init)
        let dotted = repeating.count == 1 ? repeating[0] + "\u{0307}" : repeating[0] + "\u{0307}" + repeating.dropFirst().dropLast().joined() + repeating.last! + "\u{0307}"
        let answer = "\(front).\(fixed)\(dotted)"
        let longhand = "\(front).\(fixed)" + String(repeating: repeating.joined(), count: max(2, 6 / repeating.count)) + "…"
        let fraction = Expr.fraction(numerator, bottom)
        return told("\(numerator)/\(bottom) as a recurring decimal",
                    [MathLine(.symbol(answer))],
                    [Step("Divide \(numerator) by \(bottom)", "The remainders come back round, so the digits repeat for ever.", [MathLine(fraction, .symbol(longhand))]),
                     Step("Put dots over the part that repeats", repeating.count == 1 ? "A dot goes over the digit that repeats." : "Dots go over the first and last digits of the part that repeats: \(repeating.joined()).",
                          [MathLine(.symbol(answer))])])
    }

    /// "Convert 0.15̇ to a fraction", with the dots over the digits that repeat.
    private static func recurringFraction(_ text: String) -> Problem? {
        guard let found = groups("\\b(?:convert|write|change|express) (\\d+)\\.([\\d\u{0307}]+) (?:to|as|into) a fraction\\b", in: text),
              found[2].unicodeScalars.contains("\u{0307}"), text.replacingOccurrences(of: found[0], with: " ").range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Which digits carry a dot.
        var digits: [Character] = [], dots: [Int] = []
        for scalar in found[2].unicodeScalars {
            if scalar == "\u{0307}" { guard !digits.isEmpty else { return nil }; dots.append(digits.count - 1) } else { digits.append(Character(scalar)) }
        }
        guard (1...2).contains(dots.count), dots.last == digits.count - 1, let whole = Int(found[1]) else { return nil }
        let start = dots[0]
        let fixed = String(digits[..<start]), repeating = String(digits[start...])
        guard let all = Int(fixed + repeating), let front = Int(fixed.isEmpty ? "0" : fixed) else { return nil }
        let m = fixed.count, k = repeating.count
        let high = Int(pow(10, Double(m + k))), low = Int(pow(10, Double(m)))
        let difference = all - front, scale = high - low
        let x = Expr.symbol("x")
        let longhand = "\(whole).\(fixed)\(String(repeating: repeating, count: max(2, 6 / k)))…"
        let exact = Fraction(whole * scale + difference, scale)
        var lead = [Step("Call the number x", "", [MathLine(x, .symbol(longhand))]),
                    Step("Line up the repeating parts", low == 1 ? "Multiply by \(high): the digits after the point are then the same as x's, so they go when x is taken away." : "Multiply by \(high) and by \(low): the digits after the point are then the same, so they go when one is taken from the other.",
                             [MathLine(.integer(high) * x, .symbol("\(whole * high + all).\(String(repeating: repeating, count: max(2, 6 / k)))…")),
                              MathLine(.integer(low) * x, .symbol("\(whole * low + front).\(String(repeating: repeating, count: max(2, 6 / k)))…")),
                              MathLine(.integer(scale) * x, .integer(whole * scale + difference))]),
                        Step("Divide by \(scale)", "", [MathLine(x, Expr.integer(whole * scale + difference) / .integer(scale))])]
        if exact.bottom != scale { lead.append(Step("Simplify", "Divide the top and bottom by \(scale / exact.bottom).", [MathLine(x, exact.expr)])) }
        return told("\(found[1]).\(found[2]) as a fraction", [MathLine(exact.expr)], lead)
    }

    // MARK: Interest and depreciation over whole years

    /// "Mirek invests £6000 at a compound interest rate of 1.5% per year. He wants to earn more
    /// than £1000 interest. Work out the least time, in whole years, that this will take."
    private static func yearsToReach(_ text: String) -> Problem? {
        let money = #"£ ?(\d+(?:\.\d+)?)"#
        let yearly = #"(?:per year|per annum|a year|each year|every year|p\.?a\.?)"#
        guard has(#"\b(?:least|smallest|minimum|fewest) (?:time|number of (?:whole |full |complete )?years|(?:whole |full |complete )?years)\b|\bhow many (?:whole |full |complete )?years\b"#, text),
              let rate = groups("(?:compound interest(?: rate)? (?:of|at)|at a compound interest rate of|interest rate of|(increases?|rises?|grows?|decreases?|depreciates?|falls?|loses?) (?:in value )?(?:by|at)|at) (\\d+(?:\\.\\d+)?) ?% (?:compound interest )?\(yearly)", in: text),
              let r = Double(rate[2]), r > 0, r < 100 else { return nil }
        let down = has("^(?:decrease|depreciate|fall|lose)", rate[1])
        guard !has(#"\bsimple interest\b"#, text) else { return nil }
        // The amount at the start, and what it has to reach.
        let amounts = every(money, in: text)
        guard amounts.count == 2, let start = Double(amounts[0][1]), start > 0, let goal = Double(amounts[1][1]), goal > 0 else { return nil }
        let goalText = NSRegularExpression.escapedPattern(for: amounts[1][0])
        enum Aim { case interestAbove, worthAbove, worthBelow }
        let aim: Aim
        let strict: Bool
        if let found = groups("\\b(more than|over|at least) \(goalText) (?:in )?interest\\b", in: text) ?? groups("\\binterest of (more than|over|at least) \(goalText)", in: text) {
            guard !down else { return nil }
            aim = .interestAbove; strict = found[1].lowercased() != "at least"
        } else if let found = groups("\\b(?:worth|be|reach|value (?:is|of)|have|has|total(?: of)?)? ?(more than|over|at least|exceed|exceeds) \(goalText)", in: text) {
            guard !down, goal > start else { return nil }
            aim = .worthAbove; strict = found[1].lowercased() != "at least"
        } else if let found = groups("\\b(less than|below|under|at most) \(goalText)", in: text) {
            guard down, goal < start else { return nil }
            aim = .worthBelow; strict = found[1].lowercased() != "at most"
        } else { return nil }
        // Every number is one of the three.
        let rest = text.replacingOccurrences(of: rate[0], with: " ").replacingOccurrences(of: amounts[0][0], with: " ").replacingOccurrences(of: amounts[1][0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let multiplier = down ? 1 - r / 100 : 1 + r / 100
        let target = aim == .interestAbove ? start + goal : goal
        func done(_ value: Double) -> Bool {
            let value = (value * 100).rounded() / 100
            switch aim {
            case .interestAbove, .worthAbove: return strict ? value > target : value >= target
            case .worthBelow: return strict ? value < target : value <= target
            }
        }
        var years = 0, value = start
        while !done(value), years < 500 { years += 1; value *= multiplier }
        guard years >= 1, years < 500 else { return nil }
        func after(_ n: Int) -> MathLine {
            MathLine(Expr.number(.real(start)) * .power(.number(.real(multiplier)), .integer(n)), number2(start * pow(multiplier, Double(n))), relation: "≈")
        }
        var lead = [Step("Find the multiplier for one year", "\(down ? "Going down" : "Going up") by \(text2(r))% is multiplying by \(text2(multiplier)).", [])]
        if aim == .interestAbove {
            lead.append(Step("Work out what it has to grow to", "More than £\(text2(goal)) interest on £\(text2(start)) means more than £\(text2(target)) altogether.", []))
        }
        let word = aim == .worthBelow ? "below" : "past"
        lead.append(Step("Try whole years", years == 1 ? "After 1 year it is already \(word) £\(text2(target))." : "After \(years - 1) years it isn't \(word) £\(text2(target)) yet; after \(years) years it is.",
                         years == 1 ? [after(1)] : [after(years - 1), after(years)]))
        return told("least number of whole years", [MathLine(.integer(years), suffix: years == 1 ? "year" : "years")], lead)
    }

    // MARK: Rounding

    /// "k is a whole number between 40 and 50. The cube root of k is 3, to the nearest whole
    /// number. Work out the largest possible value of k."
    private static func roundedRoot(_ text: String) -> Problem? {
        guard let found = groups(#"\bthe (square|cube) root of (?-i:([A-Za-z])) is (\d+)(?:,)? (?:correct )?to the nearest (?:whole number|integer)\b"#, in: text),
              let asked = groups("\\b(largest|greatest|biggest|highest|smallest|least|lowest) possible value of (?-i:\(found[2]))\\b", in: text),
              has("(?<![A-Za-z])(?-i:\(found[2])) ?is (?:a|an) (?:whole number|integer|positive integer)", text), let n = Int(found[3]), n >= 1 else { return nil }
        let power = found[1].lowercased() == "square" ? 2.0 : 3.0
        var rest = text.replacingOccurrences(of: found[0], with: " ")
        var range: (low: Int, high: Int)?
        if let between = groups("(?<![A-Za-z])(?-i:\(found[2])) ?is (?:a|an) (?:whole number|integer|positive integer) between (\\d+) and (\\d+)", in: text), let low = Int(between[1]), let high = Int(between[2]), low < high {
            range = (low, high)
            rest = rest.replacingOccurrences(of: between[0], with: " ")
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let lower = Double(n) - 0.5, upper = Double(n) + 0.5
        let bottom = pow(lower, power), top = pow(upper, power)
        let largest = asked[1].lowercased().range(of: #"^(?:largest|greatest|biggest|highest)$"#, options: .regularExpression) != nil
        // The root rounds up at n + 0.5, so the top end isn't included; the bottom end is.
        let answer = largest ? (top == top.rounded() ? Int(top) - 1 : Int(top.rounded(.down))) : Int(bottom.rounded(.up))
        if let range { guard answer > range.low, answer < range.high else { return nil } }
        let root = power == 2 ? "√" : "∛", letter = found[2]
        let raise = power == 2 ? "Square" : "Cube"
        return told("\(asked[1].lowercased()) possible value of \(letter)", [MathLine(.symbol(letter), .integer(answer))], [
            Step("Write down the bounds of the \(found[1].lowercased()) root", "\(n) to the nearest whole number means from \(text2(lower)) up to, but not including, \(text2(upper)).",
                 [MathLine(parts: [number(lower), .symbol("\(root)\(letter)"), number(upper)], relation: "≤").replacingSecond("<")]),
            Step("\(raise) them", "", [MathLine(parts: [number(bottom), .symbol(letter), number(top)], relation: "≤").replacingSecond("<")]),
            Step(largest ? "Take the largest whole number below \(text2(top))" : "Take the smallest whole number from \(text2(bottom))",
                 range.map { "It is between \($0.low) and \($0.high) as well." } ?? "", [MathLine(.symbol(letter), .integer(answer))]),
        ])
    }

    // MARK: Lowest common multiple in a story

    /// "A bell rings every 12 minutes and a light flashes every 18 minutes. They both happen at
    /// 9 am. When do they next happen at the same time?"
    private static func togetherAgain(_ text: String) -> Problem? {
        let unit = #"(seconds?|minutes?|hours?|days?)"#
        let found = every("\\bevery (\\d+) \(unit)", in: text)
        guard found.count == 2, Set(found.map { singular($0[2]) }).count == 1,
              has(#"\b(?:next|again)\b.*\b(?:same time|together)\b|\b(?:same time|together) again\b|\bnext (?:time )?(?:both|all|they)\b"#, text),
              let a = Int(found[0][1]), let b = Int(found[1][1]), a > 0, b > 0, a != b else { return nil }
        var rest = text
        for item in found { rest = rest.replacingOccurrences(of: item[0], with: " ") }
        let unitName = singular(found[0][2])
        // A clock time they start together at, if there is one.
        let clock = groups(#"\b(\d{1,2})(?:[:.](\d{2}))? ?(am|pm|a\.m\.|p\.m\.)(?![a-z])"#, in: rest) ?? groups(#"\b(\d{1,2})[:.](\d{2})\b"#, in: rest)
        if let clock { rest = rest.replacingOccurrences(of: clock[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let common = lcm(a, b)
        func multiples(_ n: Int) -> String { (1...max(1, common / n)).map { String($0 * n) }.joined(separator: ", ") }
        var lead = [Step("List the multiples of each", "", [MathLine(.symbol("\(a):"), .symbol(multiples(a)), relation: ""), MathLine(.symbol("\(b):"), .symbol(multiples(b)), relation: "")]),
                    Step("Find the lowest common multiple", "\(common) is the first number in both lists.", [MathLine(.symbol("LCM"), .integer(common))])]
        if let clock, unitName == "minute" || unitName == "hour" {
            guard var hour = Int(clock[1]), let minute = Int(clock[2].isEmpty ? "0" : clock[2]), hour <= 23, minute < 60 else { return nil }
            let half = clock.count > 3 ? clock[3].lowercased().replacingOccurrences(of: ".", with: "") : ""
            if half == "pm", hour < 12 { hour += 12 }
            if half == "am", hour == 12 { hour = 0 }
            let total = hour * 60 + minute + common * (unitName == "hour" ? 60 : 1)
            let end = (total / 60) % 24, endMinute = total % 60
            let shown = half.isEmpty ? String(format: "%02d:%02d", end, endMinute)
                                     : "\(end % 12 == 0 ? 12 : end % 12)\(endMinute == 0 ? "" : String(format: ".%02d", endMinute)) \(end < 12 ? "am" : "pm")"
            lead.append(Step("Add it to the start", "\(common) \(unitName)s after \(clock[0]).", []))
            return told("when they are next together", [MathLine(.symbol(shown))], lead)
        }
        return told("when they are next together", [MathLine(.symbol("after \(common) \(unitName)s"))], lead)
    }

    // MARK: Numbers in order

    /// "Write these numbers in descending order", with the numbers on the lines under it. Also
    /// "Write the following in order of size, smallest first. 0.2, 2⁻², 2 × 10⁻². Show how you
    /// decide."
    private static func ordered(_ lines: [String]) -> Problem? {
        guard let at = lines.firstIndex(where: { has(#"\b(?:write|put|arrange|list) (?:these|the following|the) (?:numbers|values|amounts)\b.*\b(?:in )?(ascending|descending) order\b|\border of size\b"#, $0) }) else { return nil }
        let descending = has("descending|largest first|biggest first|greatest first", lines[at])
        guard descending != has("ascending|smallest first|lowest first", lines[at]) else { return nil }
        // Under the numbers: how to answer, the answer line's label, the marks misread ("T31").
        var listed = Array(lines[(at + 1)...])
        while let last = listed.last, has(#"^(?:show how you decide|(?:you must )?show (?:all )?your working|smallest|largest|[T\[]\d[1lI\]])\.?$"#, last) { listed.removeLast() }
        var items: [(text: String, expr: Expr, size: Double)] = []
        for line in listed {
            // A line of plain numbers is several; a line with a sign in it is one sum.
            let tokens = line.split(separator: " ").map(String.init)
            let pieces = tokens.count > 1 && tokens.allSatisfy({ $0.range(of: #"^-?\d+(?:\.\d+)?(?:/\d+)?$"#, options: .regularExpression) != nil }) ? tokens : [line]
            for piece in pieces {
                let plain = piece.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "x", with: "×")
                // A sign straight before a point ("9.56×.310") is a power misread, not a number.
                guard plain.range(of: #"^[-\d.×*÷/^()√]+$"#, options: .regularExpression) != nil, plain.range(of: #"(?:^|[×*÷/^(])\.|\.\."#, options: .regularExpression) == nil,
                      let expr = Parser.expression(plain), expr.symbols.isEmpty,
                      let size = expr.evaluate(), size.isFinite else { return nil }
                items.append((Format.text(expr), expr, size))
            }
        }
        // The question's number, read on a line of its own under the words, isn't one of them.
        if let first = items.first, first.text.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil,
           items.dropFirst().contains(where: { $0.text.range(of: #"^\d{1,2}$"#, options: .regularExpression) == nil }) { items.removeFirst() }
        guard items.count >= 3, Set(items.map(\.size)).count == items.count else { return nil }
        let sorted = items.sorted { descending ? $0.size > $1.size : $0.size < $1.size }
        let lines = items.map { MathLine($0.expr, number($0.size), relation: abs($0.size * 10000 - ($0.size * 10000).rounded()) < 1e-6 ? "=" : "≈") }
        return told("in \(descending ? "descending" : "ascending") order", [MathLine(.symbol(sorted.map(\.text).joined(separator: ", ")))],
                    [Step("Work out each one", "", lines.filter { $0.parts.count == 2 && Format.text($0.parts[0]) != Format.text($0.parts[1]) }),
                     Step(descending ? "Largest first" : "Smallest first", "", [MathLine(.symbol(sorted.map { Format.text(number($0.size)) }.joined(separator: descending ? " > " : " < ")))])])
    }

    // MARK: Shares of a ratio

    /// "Rana sells 192 cakes in the ratio small : medium : large = 7 : 6 : 11. The profit for one
    /// medium cake is twice the profit for one small cake. … Her total profit is £532.48. Work out
    /// the profit for one small cake."
    private static func linkedProfits(_ text: String) -> Problem? {
        guard let split = groups(#"\b(?:sells|sold|makes|made|buys|bought|has) (\d+) ([a-z]+) in the ratio ([a-z]+) ?: ?([a-z]+)(?: ?: ?([a-z]+))? ?= ?(\d+) ?: ?(\d+)(?: ?: ?(\d+))?(?![\d:])"#, in: text),
              let total = Int(split[1]), let asked = groups(#"\bwork out the (profit|price|cost|value) (?:for|of) (?:one|a|an|each) ([a-z]+)\b"#, in: text),
              let money = groups("\\btotal \(asked[1]) (?:is|was) £(\\d+(?:\\.\\d+)?)", in: text), let sum = Double(money[1]) else { return nil }
        let names = [split[3], split[4], split[5]].filter { !$0.isEmpty }
        let parts = [split[6], split[7], split[8]].filter { !$0.isEmpty }.compactMap(Int.init)
        guard names.count == parts.count, names.count >= 2, Set(names).count == names.count, names.contains(asked[2]) else { return nil }
        let base = asked[2]
        var each: [String: Fraction] = [base: Fraction(1)]
        var rest = text.replacingOccurrences(of: split[0], with: " ").replacingOccurrences(of: money[0], with: " ")
        for found in every("\\bthe \(asked[1]) (?:for|of) (?:one|a|an|each) ([a-z]+) [a-z]* ?is ((?:[a-z]+|\\d+) times|twice|half|double) the \(asked[1]) (?:for|of) (?:one|a|an|each) \(base)\\b", in: text) {
            guard let k = multiple(found[2]), names.contains(found[1]), each[found[1]] == nil else { return nil }
            each[found[1]] = k
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard names.allSatisfy({ each[$0] != nil }), rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let whole = parts.reduce(0, +)
        guard whole > 0, total % whole == 0 else { return nil }
        let counts = parts.map { total / whole * $0 }
        let weights = zip(names, counts).map { name, count in Double(count) * Double(each[name]!.top) / Double(each[name]!.bottom) }
        let units = weights.reduce(0, +)
        guard units > 0 else { return nil }
        let one = sum / units
        let thing = split[2]
        return told("\(asked[1]) for one \(base) \(singular(thing))", [MathLine(.symbol(pounds(one)))], [
            Step("Share out the \(total) \(thing)", "\(whole) parts, so one part is \(total / whole).", zip(names, counts).map { MathLine(.symbol($0), .integer($1)) }),
            Step("Write the total \(asked[1]) in terms of one \(base)", "Call the \(asked[1]) for one \(base) p.",
                 [MathLine(parts: zip(names, counts).map { name, count in Simplify.run(.integer(count) * each[name]!.expr * .symbol("p")) }, relation: "+"),
                  MathLine(Simplify.run(.number(.real(units)) * .symbol("p")), .number(.real(sum)))]),
            Step("Divide", "", [MathLine(.symbol("p"), .symbol(pounds(one)))]),
        ])
    }

    /// "Ed and Fay shared £330 in the ratio 7 : 4. Ed gives Fay some of his money. Fay now has
    /// the same amount as Ed. How much does Ed give Fay?"
    private static func evenedOut(_ text: String) -> Problem? {
        guard let found = groups(#"(?-i:\b([A-Z][a-z]+)) and (?-i:([A-Z][a-z]+)) (?:share|shared|split) £(\d+(?:\.\d+)?) in the ratio (\d+) ?: ?(\d+)(?![\d:])"#, in: text),
              let giving = groups("\\b(\(found[1])|\(found[2])) gives (\(found[1])|\(found[2])) some", in: text), giving[1] != giving[2],
              has("\\b\(giving[2]) now has the same(?: amount)? as \(giving[1])\\b", text), has(#"\bhow m"#, text),
              let total = Double(found[3]), let a = Int(found[4]), let b = Int(found[5]), a + b > 0 else { return nil }
        let rest = text.replacingOccurrences(of: found[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let first = total * Double(a) / Double(a + b), second = total * Double(b) / Double(a + b)
        let giver = giving[1] == found[1] ? first : second, taker = giving[1] == found[1] ? second : first
        guard giver > taker else { return nil }
        let given = (giver - taker) / 2
        return told("how much \(giving[1]) gives \(giving[2])", [MathLine(.symbol(pounds(given)))], [
            Step("Share \(pounds(total)) in the ratio \(a) : \(b)", "\(a + b) parts, so one part is \(pounds(total / Double(a + b))).",
                 [MathLine(.symbol(found[1]), .symbol(pounds(first))), MathLine(.symbol(found[2]), .symbol(pounds(second)))]),
            Step("Find the equal amount", "With the same amount each, both have half of \(pounds(total)).", [MathLine(.symbol("each"), .symbol(pounds(total / 2)))]),
            Step("Find what \(giving[1]) gives", "\(giving[1]) goes from \(pounds(giver)) down to \(pounds(total / 2)).", [MathLine(.symbol(pounds(giver) + " − " + pounds(total / 2)), .symbol(pounds(given)))]),
        ])
    }

    /// "Amol received £6660 from selling the 3000 sandwiches. meat : cheese : vegan = 9 : 4 : 7.
    /// The price of a meat sandwich is £2.39 … Work out the price of a vegan sandwich."
    private static func missingPrice(_ text: String) -> Problem? {
        guard let income = groups(#"\b(?:received|receives|took|takes|made|makes|got) £(\d+(?:\.\d+)?) (?:from|for) selling (?:the |all )?(\d+) ([a-z]+)"#, in: text),
              let ratio = groups(#"\b([a-z]+) ?: ?([a-z]+)(?: ?: ?([a-z]+))? ?= ?(\d+) ?: ?(\d+)(?: ?: ?(\d+))?(?![\d:])"#, in: text),
              let asked = groups(#"\bwork out the price of (?:a|an|one) ([a-z]+)\b"#, in: text),
              let money = Double(income[1]), let total = Int(income[2]) else { return nil }
        let names = [ratio[1], ratio[2], ratio[3]].filter { !$0.isEmpty }, parts = [ratio[4], ratio[5], ratio[6]].filter { !$0.isEmpty }.compactMap(Int.init)
        guard names.count == parts.count, names.count >= 2, Set(names).count == names.count, names.contains(asked[1]) else { return nil }
        var rest = text.replacingOccurrences(of: income[0], with: " ").replacingOccurrences(of: ratio[0], with: " ")
        var price: [String: Double] = [:]
        for found in every(#"\bthe price of (?:a|an|one) ([a-z]+) [a-z]* ?is £(\d+(?:\.\d+)?)"#, in: text) {
            guard names.contains(found[1]), found[1] != asked[1], price[found[1]] == nil, let size = Double(found[2]) else { return nil }
            price[found[1]] = size
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard price.count == names.count - 1, rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let whole = parts.reduce(0, +)
        guard whole > 0, total % whole == 0 else { return nil }
        let counts = Dictionary(uniqueKeysWithValues: zip(names, parts.map { total / whole * $0 }))
        let known = names.filter { $0 != asked[1] }.map { (name: $0, money: Double(counts[$0]!) * price[$0]!) }
        let left = money - known.map(\.money).reduce(0, +)
        guard left > 0, let many = counts[asked[1]], many > 0 else { return nil }
        let each = left / Double(many)
        return told("price of a \(asked[1]) \(singular(income[3]))", [MathLine(.symbol(pounds(each)))], [
            Step("Share out the \(total) \(income[3])", "\(whole) parts, so one part is \(total / whole).", names.map { MathLine(.symbol($0), .integer(counts[$0]!)) }),
            Step("Take away the money from the others", "", known.map { MathLine(.symbol("\(counts[$0.name]!) × \(pounds(price[$0.name]!))"), .symbol(pounds($0.money))) }
                 + [MathLine(.symbol(([pounds(money)] + known.map { pounds($0.money) }).joined(separator: " − ")), .symbol(pounds(left)))]),
            Step("Divide by the number of \(asked[1]) \(income[3])", "", [MathLine(.symbol("\(pounds(left)) ÷ \(many)"), .symbol(pounds(each)))]),
        ])
    }

    /// "Jing has £2450. money saved : money given to brothers = 2 : 5. She gives each of her four
    /// brothers the same amount. Does each brother receive more than £430?"
    private static func shareEach(_ text: String) -> Problem? {
        guard let start = groups(#"\bhas £(\d+(?:\.\d+)?)"#, in: text),
              let ratio = groups(#"\b([a-z]+(?: [a-z]+){0,4}) ?: ?([a-z]+(?: [a-z]+){0,4}) ?= ?(\d+) ?: ?(\d+)(?![\d:])"#, in: text),
              let people = groups(#"\beach of (?:her|his|their|the) ([a-z]+|\d+) ([a-z]+) the same amount\b"#, in: text),
              let asked = groups(#"\bdoes each ([a-z]+) (?:receive|get) more than £(\d+(?:\.\d+)?)"#, in: text),
              let total = Double(start[1]), let a = Int(ratio[3]), let b = Int(ratio[4]), let count = counted(people[1]), count > 0,
              let line = Double(asked[2]), singular(people[2]) == asked[1].lowercased() else { return nil }
        // The part of the ratio that goes to them.
        let theirs = [ratio[1], ratio[2]].map { $0.lowercased().contains(people[2].lowercased()) }
        guard theirs.filter({ $0 }).count == 1 else { return nil }
        let rest = text.replacingOccurrences(of: start[0], with: " ").replacingOccurrences(of: ratio[0], with: " ").replacingOccurrences(of: asked[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let share = total * Double(theirs[0] ? a : b) / Double(a + b), each = share / Double(count)
        return told("does each \(asked[1]) receive more than \(pounds(line))", [MathLine(.symbol((each > line ? "Yes" : "No") + ", \(pounds(each)) each"))], [
            Step("Share \(pounds(total)) in the ratio \(a) : \(b)", "\(a + b) parts, and the \(people[2]) get \(theirs[0] ? a : b) of them.", [MathLine(.symbol("\(pounds(total)) × \(theirs[0] ? a : b) ÷ \(a + b)"), .symbol(pounds(share)))]),
            Step("Split it \(count) ways", "", [MathLine(.symbol("\(pounds(share)) ÷ \(count)"), .symbol(pounds(each)))]),
            Step("Compare", "\(pounds(each)) is \(each > line ? "more" : "not more") than \(pounds(line)).", []),
        ])
    }

    // MARK: Percentages

    /// "Three friends arrive at a party. Their arrival increases the number of people at the party
    /// by 20%. In total, how many people are now at the party?"
    private static func countIncrease(_ text: String) -> Problem? {
        guard let came = groups(#"^(?:the )?(\d+|[a-z]+) ([a-z]+) (?:arrive|arrives|join|joins|come|comes|are added|is added|move in|moves in)\b"#, in: text) ?? groups(#"\. (\d+|[a-z]+) ([a-z]+) (?:arrive|arrives|join|joins|come|comes|are added|move in)\b"#, in: text),
              let added = counted(came[1]), added > 0,
              let rise = groups(#"\b(?:increases|increased|raises|raised) the number of ([a-z]+) [a-z ]*?by (\d+(?:\.\d+)?) ?%"#, in: text),
              has(#"\bhow many ([a-z]+ )?(?:are |is )?(?:now|there now|in total)\b|\bin total, how many\b|\bhow many [a-z]+ are now\b"#, text),
              let rate = Double(rise[2]), rate > 0 else { return nil }
        let rest = text.replacingOccurrences(of: came[0], with: " ").replacingOccurrences(of: rise[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let before = Double(added) * 100 / rate
        guard before == before.rounded() else { return nil }
        let now = Int(before) + added
        return told("how many \(rise[1]) now", [MathLine(.integer(now))], [
            Step("The \(added) new \(came[2]) are \(text2(rate))% of the number before", "So 1% is \(text2(Double(added) / rate)), and 100% is \(Int(before)).", [MathLine(.symbol("before"), .integer(Int(before)))]),
            Step("Add the newcomers", "", [MathLine(.symbol("\(Int(before)) + \(added)"), .integer(now))]),
        ])
    }

    /// "£5.60 for 1.68 kg. To get the required increase it can increase the price to £5.88 or
    /// reduce the mass of powder in the box by x%. Work out the value of x to 2 decimal places."
    private static func perKilogram(_ text: String) -> Problem? {
        guard let raised = groups(#"\bincrease the price to £(\d+(?:\.\d+)?)"#, in: text),
              let cut = groups(#"\breduce the (?:mass|weight|amount|volume) (?:of [a-z ]+?)?(?:in [a-z ]+? )?by (?-i:([a-z])) ?%"#, in: text),
              let asked = groups("\\bwork out the value of (?-i:\(cut[1]))(?: (?:to|correct to) (\\d) decimal places?)?", in: text),
              let after = Double(raised[1]) else { return nil }
        var rest = text.replacingOccurrences(of: raised[0], with: " ").replacingOccurrences(of: asked[0], with: " ")
        let prices = every(#"£(\d+(?:\.\d+)?)"#, in: rest), masses = every(#"(\d+(?:\.\d+)?) ?(kg|g|ml|litres?)\b"#, in: rest)
        guard prices.count == 1, masses.count == 1, let before = Double(prices[0][1]), let mass = Double(masses[0][1]), after > before, mass > 0 else { return nil }
        rest = rest.replacingOccurrences(of: prices[0][0], with: " ").replacingOccurrences(of: masses[0][0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let rate = after / mass, newMass = before / rate, x = (mass - newMass) / mass * 100
        let places = Int(asked[1]) ?? 2
        let shown = String(format: "%.\(places)f", x)
        let unit = masses[0][2]
        return told("value of \(cut[1])", [MathLine(.symbol(cut[1]), .symbol(shown))], [
            Step("Find the new price per \(unit)", "With the price raised to \(pounds(after)).", [MathLine(.symbol("\(pounds(after)) ÷ \(text2(mass))"), .symbol(pounds(rate)))]),
            Step("Find the mass that gives the same rate at the old price", "", [MathLine(.symbol("\(pounds(before)) ÷ \(pounds(rate))"), .symbol("\(text2(newMass)) \(unit)"))]),
            Step("Write the cut as a percentage of the mass", "", [MathLine(.symbol("(\(text2(mass)) − \(text2(newMass))) ÷ \(text2(mass)) × 100"), .symbol(shown))]),
        ])
    }

    /// Two taxes, each a rate on what is earned above an amount: one paid gives the salary, the
    /// salary gives the other.
    private static func bandedTax(_ text: String) -> Problem? {
        let band = #"(?-i:([A-Z][a-z]+(?: [A-Z][a-z]+)*)) 0 ?% of the first £(\d+(?:\.\d+)?) of (?:her|his|their|your|the|a) (?:annual |yearly )?(?:salary|income|pay|earnings) (\d+(?:\.\d+)?) ?% of the rest of (?:her|his|their|your|the|a) (?:annual |yearly )?(?:salary|income|pay|earnings)"#
        let bands = every(band, in: text)
        guard bands.count == 2, bands[0][1] != bands[1][1],
              let paid = groups(#"\bpaid £(\d+(?:\.\d+)?) (?-i:([A-Z][a-z]+(?: [A-Z][a-z]+)*))"#, in: text),
              let asked = groups(#"\bhow much (?-i:([A-Z][a-z]+(?: [A-Z][a-z]+)*)) did (?:she|he|they|you|[A-Z][a-z]+) pay\b"#, in: text),
              let given = bands.first(where: { $0[1] == paid[2] }), let wanted = bands.first(where: { $0[1] == asked[1] }), given[1] != wanted[1],
              let amount = Double(paid[1]), let free1 = Double(given[2]), let rate1 = Double(given[3]), let free2 = Double(wanted[2]), let rate2 = Double(wanted[3]), rate1 > 0 else { return nil }
        var rest = text.replacingOccurrences(of: paid[0], with: " ")
        for item in bands { rest = rest.replacingOccurrences(of: item[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let above = amount / (rate1 / 100), salary = free1 + above
        guard salary > free2 else { return nil }
        let other = (salary - free2) * rate2 / 100
        return told("\(asked[1]) paid", [MathLine(.symbol(pounds(other)))], [
            Step("Find the part taxed by \(given[1])", "\(pounds(amount)) is \(text2(rate1))% of the salary above \(pounds(free1)).", [MathLine(.symbol("\(pounds(amount)) ÷ \(text2(rate1 / 100))"), .symbol(pounds(above)))]),
            Step("Find the salary", "", [MathLine(.symbol("\(pounds(free1)) + \(pounds(above))"), .symbol(pounds(salary)))]),
            Step("Work out the \(asked[1])", "\(text2(rate2))% of the salary above \(pounds(free2)).", [MathLine(.symbol("(\(pounds(salary)) − \(pounds(free2))) × \(text2(rate2 / 100))"), .symbol(pounds(other)))]),
        ])
    }

    /// "Save £150 per month for 2 years; 2.5% interest is added to the total amount saved", and
    /// "Invest £3500; compound interest is added at 3% per year". After 2 years, how much more is
    /// one worth than the other?
    private static func twoSavings(_ text: String) -> Problem? {
        guard let asked = groups(#"\bafter (\d+) years?, how much more is (?:investment |plan |account |option )?(?-i:([A-Z])) worth than (?:investment |plan |account |option )?(?-i:([A-Z]))\b"#, in: text),
              let monthly = groups(#"\bsaves? £(\d+(?:\.\d+)?) (?:per|a|each|every) month for (\d+) years?\b"#, in: text),
              let bonus = groups(#"\b(\d+(?:\.\d+)?) ?% interest is added to the total(?: amount saved)?\b"#, in: text),
              let lump = groups(#"\binvests? £(\d+(?:\.\d+)?)"#, in: text),
              let compound = groups(#"\bcompound interest is added at (\d+(?:\.\d+)?) ?% (?:per|a|each) year\b"#, in: text),
              let years = Int(asked[1]), let each = Double(monthly[1]), let months = Int(monthly[2]), months == years,
              let extra = Double(bonus[1]), let start = Double(lump[1]), let rate = Double(compound[1]) else { return nil }
        var rest = text
        for item in [asked[0], monthly[0], bonus[0], lump[0], compound[0]] { rest = rest.replacingOccurrences(of: item, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Each plan's words come after its own label, or (as read off a page) just before the second label.
        let labels = every(#"\b(?:investment|plan|account|option) (?-i:([A-Z]))\b"#, in: text.replacingOccurrences(of: asked[0], with: " ")).map { $0[1] }
        guard Set(labels).count == 2, Set(labels) == Set([asked[2], asked[3]]), let second = text.range(of: #"\b(?:investment|plan|account|option) "# + labels.last!, options: [.regularExpression, .caseInsensitive]),
              let monthlyAt = text.range(of: monthly[0]), let lumpAt = text.range(of: lump[0]) else { return nil }
        let monthlyIsSecond = monthlyAt.lowerBound > second.lowerBound, lumpIsSecond = lumpAt.lowerBound > second.lowerBound
        guard monthlyIsSecond != lumpIsSecond else { return nil }
        let first = labels.first(where: { $0 != labels.last! })!
        let saved = each * 12 * Double(years) * (1 + extra / 100), grown = start * pow(1 + rate / 100, Double(years))
        let worth = [monthlyIsSecond ? labels.last! : first: saved, lumpIsSecond ? labels.last! : first: grown]
        guard let more = worth[asked[2]], let less = worth[asked[3]] else { return nil }
        let difference = (more * 100).rounded() / 100 - (less * 100).rounded() / 100
        guard difference > 0 else { return nil }
        let monthlyName = monthlyIsSecond ? labels.last! : first, lumpName = lumpIsSecond ? labels.last! : first
        return told("how much more \(asked[2]) is worth than \(asked[3])", [MathLine(.symbol(pounds(difference)))], [
            Step("Work out \(monthlyName)", "\(years * 12) months of \(pounds(each)), then \(text2(extra))% added.", [MathLine(.symbol("\(pounds(each)) × \(years * 12) × \(text2(1 + extra / 100))"), .symbol(pounds(saved)))]),
            Step("Work out \(lumpName)", "Multiply by \(text2(1 + rate / 100)) for each of the \(years) years.", [MathLine(.symbol("\(pounds(start)) × \(text2(1 + rate / 100))\(years == 1 ? "" : (years == 2 ? "²" : (years == 3 ? "³" : "^\(years)")))"), .symbol(pounds(grown)))]),
            Step("Find the difference", "", [MathLine(.symbol("\(pounds(more)) − \(pounds(less))"), .symbol(pounds(difference)))]),
        ])
    }

    // MARK: Rates, fractions and estimates

    /// "He takes 8 minutes to type a report of 416 words. How long does it take him to type an
    /// essay of 1534 words? Give your answer in minutes and seconds."
    private static func sameRate(_ text: String) -> Problem? {
        guard let known = groups(#"\btakes? (\d+(?:\.\d+)?) (seconds|minutes|hours) to ([a-z]+) (?:a|an|the) [a-z ]*?of (\d+(?:\.\d+)?) ([a-z]+)"#, in: text),
              let asked = groups("\\bhow long (?:does|will|would) it take (?:him|her|them|it|you|[A-Z][a-z]+) to \(known[3]) (?:a|an|the) [a-z ]*?of (\\d+(?:\\.\\d+)?) \(known[5])\\b", in: text),
              let time = Double(known[1]), let had = Double(known[4]), let wanted = Double(asked[1]), had > 0, time > 0 else { return nil }
        let rest = text.replacingOccurrences(of: known[0], with: " ").replacingOccurrences(of: asked[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let unit = known[2].lowercased(), taken = time * wanted / had
        var answer = "\(text2(taken)) \(unit)"
        var lead = [Step("Find the rate", "\(text2(had)) \(known[5]) in \(text2(time)) \(unit).", [MathLine(.symbol("\(text2(had)) ÷ \(text2(time))"), .symbol("\(text2(had / time)) \(known[5]) per \(singular(unit))"))]),
                    Step("Divide by the rate", "", [MathLine(.symbol("\(text2(wanted)) ÷ \(text2(had / time))"), .symbol(answer))])]
        let smaller = ["hours": "minutes", "minutes": "seconds"][unit]
        if let smaller, has("\\bin \(unit) and \(smaller)\\b", text) {
            let whole = Int(taken.rounded(.down)), part = (taken - Double(whole)) * 60
            guard abs(part - part.rounded()) < 1e-6 else { return nil }
            answer = "\(whole) \(unit) \(Int(part.rounded())) \(smaller)"
            lead.append(Step("Turn the part \(singular(unit)) into \(smaller)", "\(text2(taken - Double(whole))) of a \(singular(unit)) is \(Int(part.rounded())) \(smaller).", [MathLine(.symbol(answer))]))
        }
        return told("how long it takes", [MathLine(.symbol(answer))], lead)
    }

    /// "the floor area of the living room is 26 m². the floor area of the kitchen is 16.4 m².
    /// Express the area of the living room as a fraction of the area of the kitchen."
    private static func fractionOf(_ text: String) -> Problem? {
        guard let asked = groups(#"\bexpress the ([a-z]+(?: [a-z]+)?) of the ([a-z]+(?: [a-z]+){0,2}) as a fraction of the ([a-z]+(?: [a-z]+)?) of the ([a-z]+(?: [a-z]+){0,2}?)(?=[ .,]|$)"#, in: text) else { return nil }
        let facts = every(#"\bthe ([a-z]+(?: [a-z]+){0,2}) of the ([a-z]+(?: [a-z]+){0,2}) is (\d+(?:\.\d+)?) ?([a-z]+(?:\^2|\^3|²|³)?)?"#, in: text)
        func find(_ quantity: String, _ thing: String) -> [String]? {
            let matching = facts.filter { $0[1].lowercased().hasSuffix(quantity.lowercased()) && $0[2].lowercased() == thing.lowercased() }
            return matching.count == 1 ? matching[0] : nil
        }
        guard facts.count == 2, let top = find(asked[1], asked[2]), let bottom = find(asked[3], asked[4]), top[0] != bottom[0], top[4] == bottom[4],
              let a = decimal(top[3]), let b = decimal(bottom[3]), a.top > 0, b.top > 0 else { return nil }
        var rest = text.replacingOccurrences(of: asked[0], with: " ")
        for item in facts { rest = rest.replacingOccurrences(of: item[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let exact = a / b
        // Clear the decimals first, then simplify.
        let places = max(top[3].split(separator: ".").dropFirst().first?.count ?? 0, bottom[3].split(separator: ".").dropFirst().first?.count ?? 0)
        let scale = Int(pow(10, Double(places)))
        let topWhole = a.top * (scale / a.bottom), bottomWhole = b.top * (scale / b.bottom)
        var lead = [Step("Write one over the other", "", [MathLine(.symbol("\(top[3]) ÷ \(bottom[3])"))])]
        if scale > 1 { lead.append(Step("Make them whole numbers", "Multiply the top and bottom by \(scale).", [MathLine(Expr.integer(topWhole) / .integer(bottomWhole))])) }
        lead.append(Step("Simplify", "Divide the top and bottom by \(topWhole / exact.top).", [MathLine(exact.expr)]))
        return told("\(asked[1]) of the \(asked[2]) as a fraction of the \(asked[3]) of the \(asked[4])", [MathLine(exact.expr)], lead)
    }

    /// "three", "4" as a number.
    private static func counted(_ word: String) -> Int? {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                     "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]
        return words[word.lowercased()] ?? Int(word)
    }

    /// £45, £437.50, £1.28.
    private static func pounds(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? "£\(Int(rounded))" : String(format: "£%.2f", rounded)
    }

    // MARK: Ratios linked through what they share

    /// "The ratio of blue counters to green counters is 3:2. The ratio of green counters to
    /// yellow counters is 2:5. Write down the ratio of blue to green to yellow counters": the
    /// ratios scaled so that what they share matches. Asked for as a ratio, as a fraction or a
    /// percentage of them all, as the smallest possible total, or as the angles of a shape.
    /// With lettered parts, every part is answered or nothing is.
    private static func linkedRatios(_ input: String) -> Problem? {
        // Other ways of saying a ratio: "the number of houses and the number of flats are in the
        // ratio 7 : 4", "men : children = 11 : 3", "D : E = 3 : 5".
        var text = input.replacingOccurrences(of: #"\b(?:the )?(?:number of )?([a-z]+(?: [a-z]+)?) and (?:the )?(?:number of )?([a-z]+(?: [a-z]+)?) (?:are|were) in the ratio (\d+) ?: ?(\d+)(?!\d|:|\.\d)"#,
                                              with: "the ratio of $1 to $2 is $3 : $4", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"(?<![:=] )\b(?:the )?(?:number of )?([A-Za-z]+(?: [a-z]+)?) ?: ?(?:the )?(?:number of )?([A-Za-z]+(?: [a-z]+)?) ?= ?(\d+) ?: ?(\d+)(?!\d|:|\.\d)"#,
                                         with: "the ratio of $1 to $2 is $3 : $4", options: [.regularExpression])
        text = text.replacingOccurrences(of: #"\bratio ([A-Za-z]+) ?: ?([A-Za-z]+) ?: ?([A-Za-z]+)\b(?! ?=)"#, with: "ratio of $1 to $2 to $3", options: [.regularExpression])
        text = text.replacingOccurrences(of: #"\bratio ([A-Za-z]+) ?: ?([A-Za-z]+)\b(?! ?[=:])"#, with: "ratio of $1 to $2", options: [.regularExpression])
        text = text.replacingOccurrences(of: #"\.? ?Give your answer in its simplest form\.?"#, with: ".", options: [.regularExpression, .caseInsensitive])
        guard has(#"\bratio of\b"#, text) else { return nil }
        // "For the empty jars, small : medium = 3 : 4": the ratios are about some of them only,
        // so they can't give a share of them all.
        let scoped = has(#"\bfor the [a-z]+ [a-z]+,? (?:the )?(?:ratio of |number of |[a-z]+ ?:)"#, input)
        let name = #"([A-Za-z' ]+?)"#, end = #"(?!\d|:|\.\d)"#
        var rest = text
        // A count that is known: "There are 50 bungalows in the village."
        var given: (name: String, count: Int)?
        if let found = groups(#"\bthere (?:are|were) (\d+) (?!more\b|fewer\b|less\b)([A-Za-z' ]+?)(?: in (?:the |a |this )?[a-z]+)?\s*[.,]"#, in: rest), let n = Int(found[1]), n > 0 {
            given = (found[2], n)
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // Or a difference: "There are 15 more meerkats than antelope."
        var gap: (more: String, less: String, count: Int)?
        if given == nil, let found = groups(#"\bthere (?:are|were) (\d+) more ([A-Za-z' ]+?) than ([A-Za-z' ]+?)\s*[.,]"#, in: rest), let n = Int(found[1]), n > 0 {
            gap = (found[2], found[3], n)
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // Or how many there are altogether: "the total number of almonds, cashews and peanuts is 1025",
        // "There is a total of 250 men, women and children on a train."
        var altogether: (count: Int, listed: String)?
        if given == nil, gap == nil, let found = groups(#"\bthe total number of ([A-Za-z', ]+?) (?:is|was) (\d+)\s*[.,]"#, in: rest), let n = Int(found[2]), n > 0 {
            altogether = (n, found[1])
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        } else if given == nil, gap == nil, let found = groups(#"\bthere (?:is|are|was|were) a total of (\d+) ([A-Za-z', ]+?)\s*\."#, in: rest), let n = Int(found[1]), n > 0 {
            altogether = (n, found[2])
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        var facts: [(names: [String], sizes: [Int], said: String)] = []
        for found in every("\\bratio of (?:the )?\(name) to (?:the )?\(name) to (?:the )?\(name) (?:is|was|are|were|=) (\\d+) ?: ?(\\d+) ?: ?(\\d+)\(end)", in: rest) {
            facts.append(([found[1], found[2], found[3]], [found[4], found[5], found[6]].compactMap { Int($0) }, found[0]))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        for found in every("\\bratio of (?:the )?\(name) to (?:the )?\(name) (?:is|was|are|were|=) (\\d+) ?: ?(\\d+)\(end)", in: rest) {
            facts.append(([found[1], found[2]], [found[3], found[4]].compactMap { Int($0) }, found[0]))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard facts.count >= 2, facts.allSatisfy({ fact in fact.sizes.count == fact.names.count && fact.sizes.allSatisfy { $0 > 0 && $0 < 10000 } }) else { return nil }

        // What each part asks, at the end of the part.
        enum Ask { case ratio([String]), share(String, percent: Bool), smallest, spread(Int), count(String), total, percentOf(String, String) }
        let known = given != nil || gap != nil || altogether != nil
        let close = #"(?: in (?:the |a |an )?[A-Za-z ]+)?\s*[.?]?\s*$"#
        func ask(_ part: String) -> (ask: Ask, said: String)? {
            if let found = groups("\\bratio of (?:the )?\(name) to (?:the )?\(name) to (?:the )?\(name)\(close)", in: part) { return (.ratio([found[1], found[2], found[3]]), found[0]) }
            if let found = groups("\\bratio of (?:the )?\(name) to (?:the )?\(name)\(close)", in: part) { return (.ratio([found[1], found[2]]), found[0]) }
            if let found = groups("\\bwhat (fraction|percentage|proportion) of (?:the |all the )?[A-Za-z' ]+? (?:are|is|were|was) \(name)\\s*[.?]?\\s*$", in: part) {
                return (.share(found[2], percent: found[1].lowercased() == "percentage"), found[0])
            }
            if let found = groups("\\b(?:calculate|work out|find|what is|write down) the (fraction|percentage|proportion) of (?:the |all the )?[A-Za-z' ]+? (?:that|which|who) (?:are|is|were|was) \(name)\\s*[.?]?\\s*$", in: part) {
                return (.share(found[2], percent: found[1].lowercased() == "percentage"), found[0])
            }
            if known, let found = groups("\\bhow many \(name) (?:are|were|is|was) there(?: in (?:the |a |this )?[a-z]+)?\\s*[.?]?\\s*$", in: part) ?? groups("\\b(?:work out|find|calculate) the number of \(name)(?: in (?:the |a |this )?[a-z]+)?\\s*[.?]?\\s*$", in: part)
                ?? groups("\\bhow many \(name) (?:are|were) (?:on|in|at) (?:the |a |this )?[a-z]+\\s*[.?]?\\s*$", in: part) { return (.count(found[1]), found[0]) }
            if let found = groups("\\b(?:write|express|work out|find|give) (?:the number of )?\(name) as a percentage of (?:the number of )?\(name)\\s*[.?]?\\s*$", in: part) { return (.percentOf(found[1], found[2]), found[0]) }
            if known, let found = groups(#"\b(?:find|work out|calculate|what is) the total (?:population|number)\b[A-Za-z' ]*\s*[.?]?\s*$|\bhow many [A-Za-z' ]+ (?:are there )?(?:altogether|in total)\s*[.?]?\s*$"#, in: part) { return (.total, found[0]) }
            if let found = groups(#"\b(?:smallest|least|lowest) possible (?:total )?number of [A-Za-z' ]+?(?: (?:that|which) [A-Za-z' ]+)?\s*[.?]?\s*$"#, in: part) { return (.smallest, found[0]) }
            if let found = groups(#"\bdifference (?:in size )?between (?:the )?(?:sizes? of )?(?:the )?largest and (?:the )?smallest angles?(?: in [A-Za-z ]+)?\s*[.?]?\s*$"#, in: part) {
                let corners = ["triangle": 3, "quadrilateral": 4, "pentagon": 5, "hexagon": 6].filter { has("\\b\($0.key)\\b", text) }
                guard corners.count == 1, let shape = corners.first else { return nil }
                return (.spread(shape.value), found[0])
            }
            return nil
        }
        let parts = lettered(rest)
        let segments = parts.isEmpty ? [(label: "", text: rest)] : parts
        var asks: [(label: String, ask: Ask)] = []
        for segment in segments {
            guard let found = ask(segment.text.trimmingCharacters(in: .whitespaces)) else { return nil }
            asks.append((segment.label, found.ask))
            rest = rest.replacingOccurrences(of: found.said, with: " ")
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }

        // Each name by the word that sets it apart: "blue counters" is blue, "those taught
        // German" is German. (The word the names share is the rarest in none of them.)
        let stop: Set<String> = ["the", "a", "an", "of", "number", "those", "that", "size", "total", "amount", "to", "in"]
        func words(_ name: String) -> [String] {
            name.replacingOccurrences(of: #"'s\b|'"#, with: " ", options: .regularExpression)
                .split(whereSeparator: { !$0.isLetter }).map(String.init)
                .map { $0.count == 1 && $0.first!.isUppercase ? $0 : singular($0) }
                .filter { !stop.contains($0) }
        }
        var askedNames: [String] = []
        for item in asks {
            switch item.ask {
            case .ratio(let names): askedNames += names
            case .share(let name, _), .count(let name): askedNames.append(name)
            case .percentOf(let a, let b): askedNames += [a, b]
            default: break
            }
        }
        var frequency: [String: Int] = [:]
        for name in facts.flatMap(\.names) + askedNames + (given.map { [$0.name] } ?? []) + (gap.map { [$0.more, $0.less] } ?? []) { for word in Set(words(name)) { frequency[word, default: 0] += 1 } }
        // Only a word the ratios use can be a key: "section D" is D.
        let used = Set(facts.flatMap(\.names).flatMap(words) + (given.map { words($0.name) } ?? []) + (gap.map { words($0.more) + words($0.less) } ?? []))
        func key(_ name: String) -> String? {
            let known = words(name).filter(used.contains)
            return (known.isEmpty ? words(name) : known).min { (frequency[$0] ?? 0) < (frequency[$1] ?? 0) }
        }

        // Sizes, one fact at a time from the first: each fact scaled to agree with what's known.
        var keyed: [[(key: String, size: Int)]] = []
        for fact in facts {
            var row: [(key: String, size: Int)] = []
            for (name, size) in zip(fact.names, fact.sizes) {
                guard let key = key(name) else { return nil }
                row.append((key, size))
            }
            guard Set(row.map(\.key)).count == row.count else { return nil }
            keyed.append(row)
        }
        var order: [String] = []
        for row in keyed { for item in row where !order.contains(item.key) { order.append(item.key) } }
        var size: [String: Fraction] = [keyed[0][0].key: Fraction(keyed[0][0].size)]
        var done = Set<Int>(), changed = true
        while changed {
            changed = false
            for (index, row) in keyed.enumerated() where !done.contains(index) {
                guard let known = row.first(where: { size[$0.key] != nil }) else { continue }
                let one = size[known.key]! / Fraction(known.size)
                for item in row {
                    let value = one * Fraction(item.size)
                    if let had = size[item.key] { guard had == value else { return nil } } else { size[item.key] = value }
                }
                done.insert(index); changed = true
            }
        }
        guard done.count == keyed.count else { return nil }
        func whole(_ keys: [String]) -> [Int] {
            let values = keys.map { size[$0]! }
            let scale = values.reduce(1) { lcm($0, $1.bottom) }
            let scaled = values.map { $0.top * (scale / $0.bottom) }
            let common = max(scaled.reduce(0) { gcd($0, $1) }, 1)
            return scaled.map { $0 / common }
        }
        let all = whole(order), total = all.reduce(0, +)
        guard total > 0 else { return nil }
        // A total has to be of just the things the ratios are about: each of them named in it, and nothing else.
        if let altogether {
            let listed = altogether.listed.replacingOccurrences(of: #" (?:on|in|at) (?:the |a |this )?[a-z]+$"#, with: "", options: .regularExpression)
                .components(separatedBy: ", ").flatMap { $0.components(separatedBy: " and ") }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard listed.count == order.count, order.allSatisfy({ key in listed.contains { words($0).contains(key) } }) else { return nil }
        }

        var lead = [Step("Make what they share match", facts.map { $0.said.trimmingCharacters(in: .whitespaces) }.joined(separator: ". ") + ". Scale each ratio so that the shared item is the same size in both.",
                         [MathLine(parts: all.map { .integer($0) }, relation: ":", suffix: "(" + order.joined(separator: " : ") + ")")])]
        var answers: [(label: String, line: MathLine)] = []
        for item in asks {
            switch item.ask {
            case .ratio(let names):
                let keys = names.compactMap(key)
                guard keys.count == names.count, Set(keys).count == keys.count, keys.allSatisfy({ size[$0] != nil }) else { return nil }
                answers.append((item.label, MathLine(parts: whole(keys).map { .integer($0) }, relation: ":")))
            case .share(let name, let percent):
                guard !scoped, let key = key(name), let part = order.firstIndex(of: key) else { return nil }
                let share = Fraction(all[part], total)
                if percent {
                    let value = share.double * 100
                    lead.append(Step("Work out the percentage", "\(all[part]) out of \(total), times 100.", []))
                    answers.append((item.label, MathLine(.symbol(Format.text(number2(value)) + "%"))))
                } else {
                    lead.append(Step("Write it as a fraction", "\(all[part]) out of \(total) altogether.", []))
                    answers.append((item.label, MathLine(share.expr)))
                }
            case .count, .total:
                // All of them counted: one part of the whole-number ratio, then the parts asked for.
                if let counted = altogether {
                    guard case .count(let name) = item.ask, let want = key(name), let index = order.firstIndex(of: want), counted.count % total == 0 else { return nil }
                    let part = counted.count / total
                    lead.append(Step("Find one part", "\(total) parts altogether, so one part is \(counted.count) ÷ \(total) = \(part).", []))
                    lead.append(Step("Multiply by the parts asked for", "", [MathLine(.symbol("\(part) × \(all[index])"), .integer(part * all[index]))]))
                    answers.append((item.label, MathLine(.integer(part * all[index]))))
                    continue
                }
                // How much one part is, from the count known or the difference known.
                var one: Fraction
                if let given, let have = key(given.name), let a = size[have] {
                    one = Fraction(given.count) / a
                    lead.append(Step("Find one part", "\(given.count) \(given.name) is \(Format.text(a.expr)) parts.", []))
                } else if let gap, let more = key(gap.more), let less = key(gap.less), let a = size[more], let b = size[less], (a - b).top > 0 {
                    one = Fraction(gap.count) / (a - b)
                    lead.append(Step("Find one part", "\(gap.count) more \(gap.more) than \(gap.less) is \(Format.text((a - b).expr)) parts.", []))
                } else { return nil }
                var value: Fraction
                if case .count(let name) = item.ask {
                    guard let want = key(name), let b = size[want] else { return nil }
                    value = one * b
                } else { value = one * order.reduce(Fraction(0)) { $0 + size[$1]! } }
                guard value.bottom == 1, value.top > 0 else { return nil }
                answers.append((item.label, MathLine(.integer(value.top))))
            case .percentOf(let a, let b):
                guard let ka = key(a), let kb = key(b), ka != kb, let x = size[ka], let y = size[kb] else { return nil }
                let value = (x / y).double * 100
                guard abs(value * 100 - (value * 100).rounded()) < 1e-6 else { return nil }
                answers.append((item.label, MathLine(.symbol(Format.text(number2(value)) + "%"))))
            case .smallest:
                lead.append(Step("Add the parts", "The smallest possible number is one of each share: \(all.map(String.init).joined(separator: " + ")).", []))
                answers.append((item.label, MathLine(.integer(total))))
            case .spread(let corners):
                guard order.count == corners else { return nil }
                let angles = all.map { Fraction((corners - 2) * 180 * $0, total) }
                let largest = angles.max { $0.double < $1.double }!, smallest = angles.min { $0.double < $1.double }!
                let gap = largest - smallest
                lead.append(Step("Share out the angle sum", "The angles of the shape add up to \((corners - 2) * 180)°.", [MathLine(parts: angles.map(\.expr), relation: ",", suffix: "°")]))
                answers.append((item.label, MathLine(gap.expr, suffix: "°")))
            }
        }
        if answers.count == 1 { return told("the ratio", [answers[0].line], lead) }
        let joined = answers.map { "(\($0.label)) \($0.line.text)" }.joined(separator: ",  ")
        return told("the ratio", [MathLine(.symbol(joined))], lead)
    }

    /// The parts of a question, "(a) … (b) …", each with what's written in it.
    private static func lettered(_ text: String) -> [(label: String, text: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)\(([a-h])\)\s"#) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var parts: [(label: String, text: String)] = []
        for (index, match) in matches.enumerated() {
            guard let label = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) else { return [] }
            let next = index + 1 < matches.count ? Range(matches[index + 1].range, in: text)?.lowerBound : text.endIndex
            guard let next, next >= whole.upperBound else { return [] }
            parts.append((String(text[label]), String(text[whole.upperBound..<next])))
        }
        return parts
    }

    // MARK: The same percentage change, again and again

    private static let period = #"(year|hour|minute|month|week|day|second)s?"#
    /// "10 ", "three " or nothing, before a period: every 10 years, every three months, each year.
    private static let howMany = #"(?:(\d+|[a-z]+) )?"#

    private struct Change {
        var down: Bool, percent: Double, every: Int, unit: String, said: String
        var multiplier: Double { down ? 1 - percent / 100 : 1 + percent / 100 }
    }

    /// "decreases by 9% every 10 years", "Each year … increases by 22%", "compound interest of
    /// 5% per year", "4% of the water is lost every minute", "Each year … a 6% pay rise".
    private static func change(_ text: String) -> Change? {
        let size = #"(\d+(?:\.\d+)?)"#
        let verb = #"(increas|decreas|ris|fall|fell|grow|grew|appreciat|depreciat|los|reduc|drop)[a-z]*"#
        let whose = #"(?: of (?:its|their|the) [a-z]+(?: at the start of (?:that|each|the) [a-z ]+?(?:year|hour|minute|month|week|day)s?)?)?"#
        func made(_ verb: String, _ percent: String, _ count: String, _ unit: String, _ said: String) -> Change? {
            guard let p = Double(percent), p > 0, p < 100, let every = count.isEmpty ? 1 : counted(count), every >= 1 else { return nil }
            return Change(down: has(#"^(?:decreas|fall|fell|depreciat|los|reduc|drop|cut|remov)"#, verb), percent: p, every: every, unit: unit.lowercased(), said: said)
        }
        if let found = groups("\\b\(verb) (?:in value )?(?:by |at (?:a rate of )?)?\(size) ?%\(whose) (?:each|every|per|a) \(howMany)\(period)\\b", in: text) {
            return made(found[1], found[2], found[3], found[4], found[0])
        }
        if let found = groups("\\b(?:each|every) \(howMany)\(period),? (?:[A-Za-z']+ ){0,8}?\(verb) (?:in value )?(?:by |at )?\(size) ?%\(whose)", in: text) {
            return made(found[3], found[4], found[1], found[2], found[0])
        }
        if let found = groups("\\b\(size) ?% of (?:the |its )?[a-z]+ (?:is|are) (lost|gained|removed|added) (?:each|every|per|a) \(howMany)\(period)\\b", in: text) {
            return made(found[2].lowercased(), found[1], found[3], found[4], found[0])
        }
        if let found = groups("\\b(?:each|every) \(howMany)\(period),? (?:[A-Za-z']+ ){0,8}?(?:a|an) \(size) ?% (?:pay )?(rise|increase|decrease|cut|reduction)\\b", in: text) {
            return made(found[4].lowercased(), found[3], found[1], found[2], found[0])
        }
        if let found = groups("\\bcompound interest(?: rate)? (?:of|at) (?:a rate of )?\(size) ?% (?:each|every|per|a) (year|annum)\\b", in: text) {
            return made("increase", found[1], "", "year", found[0])
        }
        if let found = groups("\\b\(size) ?% (?:per (?:year|annum) )?compound interest(?:,? (?:paid|added) (?:yearly|annually|each year)| per (?:year|annum))?", in: text) {
            return made("increase", found[1], "", "year", found[0])
        }
        return nil
    }

    private static let measureUnit = #"(litres?|millilitres?|ml|mm|cm|km|m|kg|g|tonnes?)"#
    /// "£100,000", "500 litres", "40cm", "18000".
    private static let quantity = #"(£ ?)?(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)(?: ?\#(measureUnit)\b)?"#

    /// How many of the base unit (m, g, ml) one of these is.
    private static func unitSize(_ unit: String) -> (kind: String, size: Double)? {
        switch singular(unit) {
        case "mm": return ("length", 0.001)
        case "cm": return ("length", 0.01)
        case "m": return ("length", 1)
        case "km": return ("length", 1000)
        case "g": return ("mass", 1)
        case "kg": return ("mass", 1000)
        case "tonne": return ("mass", 1_000_000)
        case "ml", "millilitre": return ("volume", 1)
        case "litre": return ("volume", 1000)
        default: return nil
        }
    }

    /// Words after a number that make it something other than an amount: "3 years", "4 years old".
    private static let notAmount = #"(?:(?:years?|hours?|minutes?|months?|weeks?|days?|seconds?|old|times|marks?|per|percent|cent)\b|%)"#
    /// A second change, or one written another way, that a sum with one multiplier would leave out.
    private static let secondChange = #"\b(?:increas|decreas|depreciat|appreciat|reduc)[a-z]*|\b(?:rises?|rose|risen|falls?|fell|fallen|grows?|grew|grown|loses?|losing|lost|gains?|gained|drops?|dropped)\b|\bgo(?:es)? (?:up|down)\b|\bwent (?:up|down)\b|\bper ?cent\b|°/o|\bfurther\b|\b(?:in|for|during) the (?:first|second|third|fourth|fifth|next|following|last) (?:year|month|week|day|hour)\b|\b(?:each|every) (?:year|month|week|day|hour) after\b|\bafter that\b"#

    /// A plain number is a count only when the words say so: "18000 living", "5000 bees",
    /// "there were 18000", "was 24,000,000". Never "3 years", "4 years old", or a number on its own.
    private static func isCount(_ said: String, in text: String) -> Bool {
        let n = NSRegularExpression.escapedPattern(for: said)
        guard !has("(?<![\\d.,])\(n) ?\(notAmount)", text) else { return false }
        return has("(?<![\\d.,£])\(n) (?!\(notAmount))[A-Za-z]{3,}", text)
            || has("\\b(?:is|was|were|are|be|of|had|has) (?:now |about |approximately |around |roughly )?\(n)(?![\\d,]|\\.\\d)", text)
    }

    /// "£4000 … compound interest of 5% per year … the total after two years", "decreases by
    /// 9% every 10 years. In 1950 there were 18000 … how many less in 2020", "After how many
    /// complete years will it be at least 3m", "What percentage is left after twenty minutes".
    private static func growth(_ text: String) -> Problem? {
        guard every("%", in: text).count == 1, !has(#"\bsimple interest\b"#, text), let change = change(text) else { return nil }
        var rest = text.replacingOccurrences(of: change.said, with: " ")
        // "1 000 000", "1000 000": one number written in groups of three.
        rest = rest.replacingOccurrences(of: #"\b(\d{1,4})((?: \d{3})+)(?![\d.,])"#, with: "$1$2", options: .regularExpression)
        while let found = groups(#"\b(\d+) (\d{3})(?![\d.,])"#, in: rest), found[1].count <= 4 || found[1].count % 3 == 1 {
            rest = rest.replacingOccurrences(of: found[0], with: found[1] + found[2])
        }
        // Going back to what it was at the start is another question; so is comparing two.
        guard !has(#"\b(?:original|originally|initial|initially|to begin with|when (?:it was )?new)\b|\bhow much did\b|\bdifference\b|\boffer\b|\bcompare\b|\bbetter\b"#, rest) else { return nil }

        // Dates and years: "on 1st April 2014", "In 1950".
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        var dates: [(month: Int, day: Int)] = []
        for found in every(#"\b(\d{1,2})(?:st|nd|rd|th)? (January|February|March|April|May|June|July|August|September|October|November|December) ((?:1[6-9]|20)\d\d)\b"#, in: rest) {
            guard let day = Int(found[1]), let month = months.firstIndex(of: found[2].lowercased()), let year = Int(found[3]) else { return nil }
            dates.append((year * 12 + month, day))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        var years: [Int] = []
        for found in every(#"\b(?:in|by|from|until|to|since) ((?:1[6-9]|20)\d\d)\b"#, in: rest) {
            guard let year = Int(found[1]) else { return nil }
            years.append(year)
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // How long: "for two years", "after 8 hours", "in 5 years time", "two years ago".
        var spans: [Int] = [], ago = false
        for found in every("\\b(?:for|after|in|over|within|at the end of) (?:the (?:first |next )?)?(\\d+|[a-z]+) \(period)(?: time| later)?\\b", in: rest) {
            guard let n = counted(found[1]), found[2].lowercased() == change.unit else { continue }
            spans.append(n)
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        for found in every("\\b(\\d+|[a-z]+) \(period) (ago|later)\\b", in: rest) {
            guard let n = counted(found[1]), found[2].lowercased() == change.unit else { continue }
            spans.append(n)
            if found[3].lowercased() == "ago" { ago = true }
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // What it has to reach: "at least 3m", "exceed £30000", "less than 1000", "double".
        let limit = groups("\\b(at least|more than|over|exceeds?|greater than|less than|below|under|fewer than|at most) \(quantity)", in: rest)
        if let limit {
            // "more than 3 years" is a time, not what it has to reach.
            guard !has("\(NSRegularExpression.escapedPattern(for: limit[0])) \(notAmount)", rest) else { return nil }
            rest = rest.replacingOccurrences(of: limit[0], with: " ")
        }
        let times = groups(#"\b(double|treble|triple|halve)\b|\bhalf (?:its|of its) (?:original )?value\b"#, in: rest)
        // Only the one change: a second one ("then by 10% each year after that", "a further 5
        // per cent") would be left out of the sum.
        let asked = rest.replacingOccurrences(of: #"\bwhat percentage of (?:the )?[a-z]+ (?:is|will be|has been) (?:left|remaining|lost)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        guard !has(secondChange, asked) else { return nil }
        // What it starts at: the one amount left, and only when it's sure to be the amount.
        let amounts = every(quantity, in: rest)
        guard amounts.count <= 1 else { return nil }
        let start = amounts.first
        if let start {
            guard !start[1].isEmpty || !start[3].isEmpty || isCount(start[0], in: rest) else { return nil }
            rest = rest.replacingOccurrences(of: start[0], with: " ")
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let startValue = start.flatMap { Double($0[2].replacingOccurrences(of: ",", with: "")) }
        let isMoney = !(start?[1].isEmpty ?? true), unit = start.flatMap { $0[3].isEmpty ? nil : $0[3] }
        let m = change.multiplier, step = change.every
        let rateWords = "\(change.down ? "Going down" : "Going up") by \(text2(change.percent))% is multiplying by \(text2(m))."
        let perWord = step == 1 ? change.unit : "\(step) \(change.unit)s"

        func shown(_ value: Double) -> MathLine {
            if isMoney { return MathLine(.symbol(pounds(value))) }
            if let unit { return MathLine(number2(value), suffix: unit) }
            // A count of people, animals or things is a whole number.
            return MathLine(.integer(Int(value.rounded())))
        }

        // How long until it gets there.
        if has(#"\bhow many (?:complete |whole |full )?(?:years?|hours?|minutes?|months?|weeks?|days?)\b|\bafter how many\b|\bhow long\b|\b(?:what|which) year\b"#, rest) {
            guard spans.isEmpty, dates.isEmpty else { return nil }
            var target: Double, strict: Bool, above: Bool, base = startValue ?? 1
            if let limit {
                guard let start, let size = startValue, size > 0, var goal = Double(limit[3].replacingOccurrences(of: ",", with: "")) else { return nil }
                guard start[1].isEmpty == limit[2].isEmpty else { return nil }
                switch (start[3].isEmpty, limit[4].isEmpty) {
                case (true, true): break
                case (false, false):
                    guard let a = unitSize(start[3]), let b = unitSize(limit[4]), a.kind == b.kind else { return nil }
                    goal = goal * b.size / a.size
                default: return nil
                }
                let relation = limit[1].lowercased()
                above = !has(#"less|below|under|fewer|at most"#, relation)
                strict = !relation.hasPrefix("at ")
                target = goal; base = size
            } else if let times {
                guard startValue == nil else { return nil }
                let word = times[0].lowercased()
                above = !word.hasPrefix("half") && word != "halve"
                target = word == "double" ? 2 : (word == "treble" || word == "triple" ? 3 : 0.5)
                strict = false; base = 1
            } else { return nil }
            guard above != change.down else { return nil }
            func reached(_ value: Double) -> Bool {
                let value = isMoney ? (value * 100).rounded() / 100 : value
                return above ? (strict ? value > target : value >= target) : (strict ? value < target : value <= target)
            }
            var n = 0, value = base
            while !reached(value), n < 1000 { n += 1; value *= m }
            guard n >= 1, n < 1000 else { return nil }
            let elapsed = n * step
            func after(_ k: Int) -> MathLine {
                MathLine(Expr.number(.real(base)) * .power(.number(.real(m)), .integer(k)), number2(base * pow(m, Double(k))), relation: "≈")
            }
            let lead = [Step("Find the multiplier for each \(perWord)", rateWords, []),
                        Step("Keep multiplying", n == 1 ? "After one \(perWord) it's already there." : "After \(n - 1) lots it isn't there yet; after \(n) it is.", n == 1 ? [after(1)] : [after(n - 1), after(n)])]
            if has(#"\b(?:what|which) year\b"#, rest) {
                guard years.count == 1, change.unit == "year" else { return nil }
                return told("which year", [MathLine(.integer(years[0] + elapsed))], lead)
            }
            guard years.isEmpty else { return nil }
            return told("how long", [MathLine(.integer(elapsed), suffix: change.unit + (elapsed == 1 ? "" : "s"))], lead)
        }

        // After a set time.
        guard limit == nil, times == nil else { return nil }
        var length: Int?
        if !spans.isEmpty {
            guard Set(spans).count == 1, years.isEmpty, dates.isEmpty else { return nil }
            length = spans[0]
        } else if dates.count == 2 {
            guard dates[0].day == dates[1].day, years.isEmpty else { return nil }
            let gap = dates[1].month - dates[0].month
            switch change.unit {
            case "month": length = gap
            case "year": length = gap % 12 == 0 ? gap / 12 : nil
            default: length = nil
            }
        } else if years.count == 2, dates.isEmpty, change.unit == "year" {
            length = years[1] - years[0]
        }
        guard let length, length > 0, length % step == 0 else { return nil }
        let n = length / step
        guard n >= 1, n <= 200 else { return nil }
        let after = pow(m, Double(n))
        var lead = [Step("Find the multiplier for each \(perWord)", rateWords, [])]
        if n > 1 || step > 1 { lead.append(Step("Count the changes", "\(length) \(change.unit)s is \(n) lot\(n == 1 ? "" : "s") of \(perWord).", [])) }
        if let found = groups(#"\bwhat percentage of (?:the )?[a-z]+ (?:is|will be|has been) (left|remaining|lost)\b"#, in: rest) {
            guard startValue == nil else { return nil }
            let left = after * 100, lost = 100 - left
            let isLost = found[1].lowercased() == "lost"
            lead.append(Step("Multiply \(n) times", "100% × \(text2(m))\(n == 1 ? "" : "^\(n)") is what's left.", [MathLine(.symbol("left"), number2(left), relation: "≈", suffix: "%")]))
            if isLost { lead.append(Step("Take it from 100%", "", [MathLine(.symbol("lost"), number2(lost), relation: "≈", suffix: "%")])) }
            return told("percentage \(isLost ? "lost" : "left")", [MathLine(.symbol(Format.text(number2(isLost ? lost : left)) + "%"))], lead)
        }
        guard let size = startValue, size > 0 else { return nil }
        let value = size * after
        let worked = MathLine(Expr.number(.real(size)) * .power(.number(.real(m)), .integer(n)), number2(value), relation: "≈")
        lead.append(Step("Multiply \(n) time\(n == 1 ? "" : "s")", "", [worked]))
        if has(#"\bhow much interest\b|\b(?:work out|calculate|find) the (?:total )?(?:amount of )?interest\b"#, rest) {
            guard isMoney, !change.down else { return nil }
            lead.append(Step("Take away what was put in", "", []))
            return told("interest", [shown(value - size)], lead)
        }
        if let found = groups(#"\bhow many (less|fewer|more)\b"#, in: rest) {
            guard (found[1].lowercased() == "more") != change.down else { return nil }
            lead.append(Step("Find the difference", "", []))
            return told("how many \(found[1].lowercased())", [shown(abs(value - size))], lead)
        }
        guard has(#"\b(?:calculate|work out|find|what (?:is|was|will be)|how (?:much|tall|high|long|heavy|many|big))\b"#, rest),
              !has(#"\bhow (?:much|many) (?:less|fewer|more)\b|\bpercentage\b|\bfraction\b"#, rest) else { return nil }
        _ = ago
        return told("the amount", [shown(value)], lead)
    }

    /// "The population increases by x% each year. In 2014 it was 24,000,000. Three years
    /// later it was 26,996,736. Find x."
    private static func unknownRate(_ text: String) -> Problem? {
        let text = grouped(text)
        let interest = groups("\\b(?:paying|pays|paid|at|of|gets|earns|with) (?-i:([a-z])) ?% (?:per (?:year|annum) |each year |a year )?compound interest\\b|\\bcompound interest (?:of|at) (?:a rate of )?(?-i:([a-z])) ?% (?:per (?:year|annum)|each year|a year)\\b", in: text)
        guard let found = groups("\\b(increas|decreas|ris|fall|grow|appreciat|depreciat|los|reduc)[a-z]* (?:in value )?by (?-i:([a-z])) ?% (?:each|every|per|a) year\\b", in: text)
                ?? interest.map({ [$0[0], "increase", $0[1].isEmpty ? $0[2] : $0[1]] }),
              has("\\b(?:find|work out|calculate|what is) (?:the value of )?(?-i:\(found[2]))\\b", text), !has(#"\bsimple interest\b"#, text) else { return nil }
        let letter = found[2], down = has(#"^(?:decreas|fall|depreciat|los|reduc)"#, found[1])
        var rest = text.replacingOccurrences(of: found[0], with: " ")
        var span: Int?
        if let later = groups(#"\b(\d+|[a-z]+) years? later\b"#, in: rest), let n = counted(later[1]) {
            span = n
            rest = rest.replacingOccurrences(of: later[0], with: " ")
        }
        // "for 2 years … At the end of 2 years": the same time, said twice.
        for found in every(#"\b(?:for|after|at the end of|over) (?:the )?(\d+|[a-z]+) years?\b"#, in: rest) {
            guard let n = counted(found[1]) else { continue }
            guard span == nil || span == n else { return nil }
            span = n
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        let years = every(#"\b(?:in|by|from|until|to|since) ((?:1[6-9]|20)\d\d)\b"#, in: rest)
        for year in years { rest = rest.replacingOccurrences(of: year[0], with: " ") }
        if span == nil, years.count == 2, let a = Int(years[0][1]), let b = Int(years[1][1]) { span = b - a }
        let amounts = every(quantity, in: rest)
        guard let span, span >= 1, span <= 100, amounts.count == 2, amounts[0][1] == amounts[1][1], amounts[0][3] == amounts[1][3],
              let a = Double(amounts[0][2].replacingOccurrences(of: ",", with: "")), let b = Double(amounts[1][2].replacingOccurrences(of: ",", with: "")), a > 0, b > 0 else { return nil }
        guard amounts.allSatisfy({ !$0[1].isEmpty || !$0[3].isEmpty || isCount($0[0], in: rest) }) else { return nil }
        for amount in amounts { rest = rest.replacingOccurrences(of: amount[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(secondChange, rest) else { return nil }
        let m = pow(b / a, 1 / Double(span))
        let x = down ? (1 - m) * 100 : (m - 1) * 100
        guard x > 0, x < 100 else { return nil }
        let rounded = (x * 100).rounded() / 100
        // Exact, or the amounts are to the penny and the rounded rate gives that penny.
        let money = !amounts[0][1].isEmpty
        let exact = abs(x - rounded) < 1e-6 || (money && pounds(a * pow(down ? 1 - rounded / 100 : 1 + rounded / 100, Double(span))) == pounds(b))
        let answer = MathLine(.symbol(letter), number2(x), relation: exact ? "=" : "≈")
        return told(letter, [answer],
                    [Step("Divide to find the overall multiplier", "\(amounts[1][0]) ÷ \(amounts[0][0]).", [MathLine(.symbol("multiplier"), number(b / a), relation: exact ? "=" : "≈")]),
                     Step("Take the \(span == 2 ? "square" : (span == 3 ? "cube" : "\(span)th")) root", "That many years of the same multiplier.", [MathLine(.symbol("one year"), number(m), relation: exact ? "=" : "≈")]),
                     Step("Turn it into a percentage", "\(down ? "Going down" : "Going up") by \(Format.text(number2(x)))% each year.", [answer])])
    }

    // MARK: Percentages: back to the start, of a percentage, one after another

    /// Digits written in groups of three: "384 000", "25 000". Not a list of numbers.
    private static func grouped(_ text: String) -> String {
        var text = text
        while let found = groups(#"(?<!\d )(?<![\d.,])(\d{1,3})((?: \d{3})+)(?![\d,]|\.\d| ?\d)"#, in: text) {
            text = text.replacingOccurrences(of: found[0], with: found[1] + found[2].replacingOccurrences(of: " ", with: ""))
        }
        return text
    }

    private static let percent = #"(\d+(?:\.\d+)?) ?%"#
    private static let upWords = #"^(?:more|higher|greater|bigger|larger|dearer|increase|rise|rises|rose|up|increased|raised|added|plus)$"#

    /// An answer of the same sort as what was given: pounds to the penny, a count as a whole
    /// number, a measure as it comes out. Nil when a count or measure doesn't come out exactly.
    private static func amount(_ v: Double, money: Bool, count: Bool, unit: String = "") -> MathLine? {
        guard v.isFinite, v > 0 else { return nil }
        if money { return MathLine(.symbol(pounds(v))) }
        if count {
            guard abs(v - v.rounded()) < 1e-6 * max(1, v) else { return nil }
            return MathLine(.integer(Int(v.rounded())), suffix: unit.isEmpty ? nil : unit)
        }
        let scaled = v * 10000
        guard abs(scaled - scaled.rounded()) < 1e-6 * max(1, scaled) else { return nil }
        return MathLine(number(v), suffix: unit.isEmpty ? nil : unit)
    }

    /// The words that pick a thing out: "his profit in 2017" → profit, 2017.
    private static func keyWords(_ phrase: String) -> [String] {
        let stop: Set<String> = ["the", "a", "an", "of", "in", "on", "at", "his", "her", "their", "its", "she", "he", "they", "it", "was", "is", "were",
                                 "did", "does", "spent", "made", "had", "has", "for", "this", "that", "these", "those", "than", "and", "to", "by"]
        return phrase.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !stop.contains($0) && ($0.count >= 3 || $0.first!.isNumber) }
    }

    /// The question asked at the end: "How many were sold last year?", "Work out Ed's profit in 2017."
    private static let askVerb = #"(?:how (?:much|many)|work out|calculate|find|what (?:is|was|were|will be))"#

    /// "This is 20% more than last year. How many were sold last year?", "This was a decrease
    /// of 20% on his profit in 2017", "a reading which is 12% higher than the actual pressure".
    private static func backToStart(_ input: String) -> Problem? {
        let text = grouped(input)
        guard every("%", in: text).count == 1 else { return nil }
        let stopAhead = #"(?=[.?]|(?-i: (?:How|What|Work|Calculate|Find|Give)\b)|$)"#
        var up: Bool, p: Double, then: String, said: String
        if let found = groups("\\b(?:this|that|it|which|these|they) (?:is|was|are|were) (?:a |an )?\(percent) (more|less|fewer|higher|lower|greater|bigger|smaller|larger|cheaper|dearer) than ([^.?]{2,60}?)\(stopAhead)", in: text),
           let v = Double(found[1]) {
            up = has(upWords, found[2]); p = v; then = found[3]; said = found[0]
        } else if let found = groups("\\b(?:this|that|it|which) (?:is|was) (?:a|an) (increase|decrease|reduction|rise|fall|drop) of \(percent) (?:on|from|compared with) ([^.?]{2,60}?)\(stopAhead)", in: text),
                  let v = Double(found[2]) {
            up = has(upWords, found[1]); p = v; then = found[3]; said = found[0]
        } else { return nil }
        guard p > 0, up || p < 100 else { return nil }
        var rest = text.replacingOccurrences(of: said, with: " ")
        // The question asks for what it was compared with.
        let keys = keyWords(then)
        guard !keys.isEmpty, let ask = every("\\b\(askVerb)\\b[^.?]*", in: rest).last?[0], keys.allSatisfy({ has("\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", ask) }),
              !has(#"\bhow (?:much|many) (?:more|less|fewer)\b|\bpercentage\b|\bdifference\b"#, ask) else { return nil }
        // Years are names, not amounts: "in 2016".
        rest = rest.replacingOccurrences(of: #"\b(?:in|on|during|of|from|since|until|to|by|for) (?:the year )?(?:19|20)\d\d\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        let amounts = every(#"(£ ?)?(?<![\d.,])(\d+(?:\.\d+)?)(?: ?\#(measureUnit)\b)?"#, in: rest)
        guard amounts.count == 1, let a = Double(amounts[0][2]), a > 0 else { return nil }
        let given = amounts[0]
        guard !given[1].isEmpty || !given[3].isEmpty || isCount(given[0], in: rest) || has("\\b(?:shows?|reads?|is|was|of) \(NSRegularExpression.escapedPattern(for: given[0]))(?![\\d,]|\\.\\d)", rest) else { return nil }
        let money = !given[1].isEmpty
        let count = !money && given[3].isEmpty && !given[2].contains(".") && has(#"\bhow many\b"#, ask)
        let m = up ? 1 + p / 100 : 1 - p / 100
        guard let answer = amount(a / m, money: money, count: count, unit: given[3]) else { return nil }
        return told("before the change", [answer],
                    [Step("Find the multiplier", "\(text2(p))% \(up ? "more" : "less") is multiplying by \(text2(m)).", []),
                     Step("Divide to go back", "\(given[0]) ÷ \(text2(m)).", [answer])])
    }

    /// "A voucher takes 15% off the bill. After using the voucher, the bill is £27.20. How much
    /// was the bill before", "20% VAT is added … pay a total of £600. What is the price with no
    /// VAT", "This 20% increase adds £240 to the price. Work out the price before the increase."
    private static func beforeChange(_ input: String) -> Problem? {
        let text = grouped(input)
        guard every("%", in: text).count <= 2, let ask = every("\\b\(askVerb)\\b[^.?]*", in: text).last?[0],
              has(#"\b(?:before|original(?:ly)?|no VAT|without (?:the )?VAT|excluding VAT|normal price|full price|usual price)\b"#, ask) else { return nil }
        var up: Bool, p: Double, said: String
        if let found = groups("\\b(?:takes?|took|gives?|gets?) \(percent) off\\b", in: text), let v = Double(found[1]) {
            up = false; p = v; said = found[0]
        } else if let found = groups("\\b\(percent) (VAT|tax|service charge) (?:is|was|has been) added\\b|\\bplus (VAT) (?:at|of) \(percent)", in: text), let v = Double(found[1].isEmpty ? found[4] : found[1]) {
            up = true; p = v; said = found[0]
        } else if let found = groups("\\b(reduced|decreased|increased|raised|cut|marked up|marked down|goes up|goes down|went up|went down|rises|rose|falls|fell|increases|decreases) (?:in price )?by \(percent)", in: text), let v = Double(found[2]) {
            up = has(#"^(?:increased|raised|marked up|goes up|went up|rises|rose|increases)$"#, found[1]); p = v; said = found[0]
        } else if let found = groups("\\b(?:a|an) \(percent) (discount|reduction|increase|rise|pay rise)\\b", in: text), let v = Double(found[1]) {
            up = has(#"increase|rise"#, found[2]); p = v; said = found[0]
        } else { return nil }
        guard p > 0, up || p < 100 else { return nil }
        var rest = text.replacingOccurrences(of: said, with: " ")
        // The same percentage named again: "This 20% increase adds £240".
        rest = rest.replacingOccurrences(of: "\\b(?:this|the) \(NSRegularExpression.escapedPattern(for: text2(p))) ?% (?=increase|decrease|reduction|discount|rise|VAT)", with: "this ", options: [.regularExpression, .caseInsensitive])
        guard !rest.contains("%") else { return nil }
        let amounts = every(#"(£ ?)?(?<![\d.,])(\d+(?:\.\d+)?)"#, in: rest)
        guard amounts.count == 1, let a = Double(amounts[0][2]), a > 0 else { return nil }
        let given = amounts[0], money = !given[1].isEmpty
        let escaped = NSRegularExpression.escapedPattern(for: given[0])
        // What the change itself is worth: "This increase adds £240", "saves £12".
        if has("\\b(?:this |the )?(?:increase|decrease|reduction|discount|rise|VAT|saving) (?:adds|added|takes off|took off|saves|saved|is|was|is worth|comes to) \(escaped)(?![\\d,]|\\.\\d)|\\b(?:saves|saving of|discount of|reduction of) \(escaped)(?![\\d,]|\\.\\d)", rest) {
            guard let answer = amount(a / (p / 100), money: money, count: false) else { return nil }
            return told("before the change", [answer],
                        [Step("\(given[0]) is \(text2(p))% of the price before", "So 1% is \(given[0]) ÷ \(text2(p)).", []),
                         Step("Multiply by 100", "", [answer])])
        }
        // Otherwise the amount must be what it came to after the change.
        guard has("\\b(?:after|now|then|pays?|paid|costs?|total of|sale price|price is|is|was|comes to|shows?) [^.?]{0,40}?\(escaped)(?![\\d,]|\\.\\d)", rest),
              !has("\\b(?:before|original(?:ly)?|normal|usual|full|was) [^.?]{0,20}\(escaped)", rest.replacingOccurrences(of: ask, with: " ")) else { return nil }
        let m = up ? 1 + p / 100 : 1 - p / 100
        guard let answer = amount(a / m, money: money, count: false) else { return nil }
        return told("before the change", [answer],
                    [Step("Find the multiplier", "\(up ? "Adding" : "Taking off") \(text2(p))% is multiplying by \(text2(m)).", []),
                     Step("Divide to go back", "\(given[0]) ÷ \(text2(m)).", [answer])])
    }

    /// "70% of a number is 350. Work out 120% of the number."
    private static func percentOfNumber(_ text: String) -> Problem? {
        guard let fact = groups("\\b\(percent) of (?:a|an|the|this|some) ([a-z]+) (?:is|was|=) (£ ?)?(\\d+(?:\\.\\d+)?)(?![\\d,]|\\.\\d)", in: text),
              let p = Double(fact[1]), let a = Double(fact[4]), p > 0 else { return nil }
        var rest = text.replacingOccurrences(of: fact[0], with: " ")
        let noun = NSRegularExpression.escapedPattern(for: fact[2])
        let money = !fact[3].isEmpty
        if let ask = groups("\\b(?:work out|find|calculate|what is) \(percent) of (?:the|this|that) (?:same )?\(noun)\\b", in: rest), let q = Double(ask[1]) {
            rest = rest.replacingOccurrences(of: ask[0], with: " ")
            guard rest.range(of: #"\d"#, options: .regularExpression) == nil, let answer = amount(a / p * q, money: money, count: false) else { return nil }
            return told("\(text2(q))% of the \(fact[2])", [answer],
                        [Step("Find 1%", "\(fact[3])\(fact[4]) ÷ \(text2(p)).", [MathLine(.symbol("1%"), number(a / p))]),
                         Step("Multiply by \(text2(q))", "", [answer])])
        }
        guard has("\\b(?:work out|find|calculate|what is) (?:the|this) \(noun)\\b", rest), rest.range(of: #"\d"#, options: .regularExpression) == nil,
              let answer = amount(a / p * 100, money: money, count: false) else { return nil }
        return told("the \(fact[2])", [answer], [Step("Find 1%", "", [MathLine(.symbol("1%"), number(a / p))]), Step("Multiply by 100", "", [answer])])
    }

    /// "70% of the people said yes. 80% of the people who said yes wanted a large screen. What
    /// percentage of the people asked wanted a large screen?"
    private static func percentOfPart(_ text: String) -> Problem? {
        guard let first = groups("\\b\(percent) of (?:the |all (?:the )?)?([a-z]+) ([a-z]+(?: [a-z]+)?)[.,;]", in: text),
              let second = groups("\\b\(percent) of (?:the |these |those )?(?:[a-z]+ )?(?:who|that|which) \(NSRegularExpression.escapedPattern(for: first[3]))\\b ([a-z ]+?)[.,;]", in: text),
              let p = Double(first[1]), let q = Double(second[1]), p > 0, p <= 100, q > 0, q <= 100,
              let ask = groups("\\bwhat percentage of (?:the |all (?:the )?)?\(NSRegularExpression.escapedPattern(for: first[2]))\\b[^.?]*", in: text) else { return nil }
        let rest = text.replacingOccurrences(of: first[0], with: " ").replacingOccurrences(of: second[0], with: " ").replacingOccurrences(of: ask[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, keyWords(second[2]).contains(where: { has("\\b\($0)\\b", ask[0]) }) else { return nil }
        let share = p * q / 100
        return told("percentage of all", [MathLine(.symbol(Format.text(number2(share)) + "%"))],
                    [Step("Take \(text2(q))% of \(text2(p))%", "", [MathLine(.symbol("\(text2(p / 100)) × \(text2(q / 100))"), number(p * q / 10000))]),
                     Step("Write it as a percentage", "", [])])
    }

    /// "Amrit's income is 32% more than Bethan's income. Their combined income is £54 868.
    /// Calculate Amrit's income."
    private static func combinedPercent(_ input: String) -> Problem? {
        let text = grouped(input)
        guard every("%", in: text).count == 1,
              let fact = groups("\\b((?-i:[A-Z][a-z]+))'s ([a-z]+) (?:is|was) \(percent) (more|less|higher|lower|greater|bigger|smaller) than ((?-i:[A-Z][a-z]+))'s\\b(?: \\2)?", in: text),
              let p = Double(fact[3]), p > 0, p < 100 || has(upWords, fact[4]) else { return nil }
        var rest = text.replacingOccurrences(of: fact[0], with: " ")
        guard let total = groups("\\b(?:combined|total|together)\\b[^.?]*? (£ ?)?(\\d+(?:\\.\\d+)?)(?![\\d,]|\\.\\d)", in: rest), let t = Double(total[2]) else { return nil }
        rest = rest.replacingOccurrences(of: total[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let m = has(upWords, fact[4]) ? 1 + p / 100 : 1 - p / 100
        let other = t / (1 + m), first = t - other
        let money = !total[1].isEmpty
        let asked = [fact[1], fact[5]].filter { has("\\b\(askVerb) \($0)'s\\b", rest) }
        guard asked.count == 1, let answer = amount(asked[0] == fact[1] ? first : other, money: money, count: false) else { return nil }
        return told("\(asked[0])'s \(fact[2])", [answer],
                    [Step("Write both in terms of \(fact[5])'s", "\(fact[1])'s is \(text2(m)) times \(fact[5])'s, so together they are \(text2(1 + m)) times \(fact[5])'s.", []),
                     Step("Divide the total", "", [MathLine(.symbol("\(fact[5])'s"), .symbol(money ? pounds(other) : text2(other)))]),
                     Step("Find \(asked[0])'s", "", [answer])])
    }

    /// "y is directly proportional to the square of x. Find the percentage increase in y when x
    /// is increased by 15%."
    private static func proportionPercent(_ text: String) -> Problem? {
        guard let fact = groups(#"\b(?-i:([a-z])) is (directly|inversely) proportional to (?:the )?(?:(square root|cube root|square|cube) of )?(?-i:([a-z]))(?:\^?([23²³]))?\b"#, in: text),
              let ask = groups("\\bpercentage (increase|decrease|change) in (?-i:\(fact[1])) when (?-i:\(fact[4])) is (increased|decreased) by \(percent)", in: text),
              let p = Double(ask[3]), p > 0, ask[2].lowercased() == "increased" || p < 100 else { return nil }
        let rest = text.replacingOccurrences(of: fact[0], with: " ").replacingOccurrences(of: ask[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        var k: Double = 1
        switch fact[3].lowercased() {
        case "square": k = 2
        case "cube": k = 3
        case "square root": k = 0.5
        case "cube root": k = 1.0 / 3
        default: k = ["2": 2, "²": 2, "3": 3, "³": 3][fact[5]] ?? 1
        }
        if fact[2].lowercased() == "inversely" { k = -k }
        let mx = ask[2].lowercased() == "increased" ? 1 + p / 100 : 1 - p / 100
        let my = pow(mx, k)
        let change = (my - 1) * 100
        let said = ask[1].lowercased()
        guard said == "change" || (said == "increase") == (change > 0), abs(change) > 1e-9 else { return nil }
        let shown = abs(change)
        let rounded = (shown * 100).rounded() / 100
        let exact = abs(shown - rounded) < 1e-9
        // "Percentage change" doesn't say which way, so the answer does.
        let way = said == "change" ? (change > 0 ? "increase of " : "decrease of ") : ""
        return told("percentage \(change > 0 ? "increase" : "decrease")", [MathLine(.symbol(way + Format.text(exact ? number2(shown) : sigFigs(shown, 3)) + "%"))],
                    [Step("Find the multiplier for \(fact[4])", "", [MathLine(.symbol(fact[4]), number(mx), suffix: "times as big")]),
                     Step("\(fact[1]) changes by that \(k == 1 ? "" : "to the power \(Format.text(number(k)))")", "", [MathLine(.symbol(fact[1]), number(my), relation: exact ? "=" : "≈", suffix: "times as big")]),
                     Step("Turn it into a percentage", "", [])])
    }

    private static func sigFigs(_ v: Double, _ figures: Int) -> Expr {
        guard v != 0 else { return .integer(0) }
        let power = Int(floor(log10(abs(v)))) - figures + 1
        let rounded = (v / pow(10, Double(power))).rounded() * pow(10, Double(power))
        return power >= 0 ? .integer(Int(rounded)) : .number(.real((rounded * pow(10, Double(-power))).rounded() / pow(10, Double(-power))))
    }

    /// "The price of petrol decreases from £1.32 per litre to £1.02 per litre. Calculate the
    /// percentage decrease", "He buys a card for £1.20 and sells it for £1.68. Calculate his
    /// percentage profit."
    private static func percentChange(_ text: String) -> Problem? {
        var a: Double, b: Double, said: String, kind: String
        if let found = groups(#"\b(increases?|decreases?|rises?|falls?|goes (?:up|down)|went (?:up|down)|changes?|rose|fell|dropped|drops?)(?: in price| in value)? from (£ ?)?(\d+(?:\.\d+)?)(?: ([a-z]+(?: [a-z]+)?))? to (£ ?)?(\d+(?:\.\d+)?)(?: ([a-z]+(?: [a-z]+)?))?\b"#, in: text),
           let x = Double(found[3]), let y = Double(found[6]), found[2].isEmpty == found[5].isEmpty {
            guard found[4].isEmpty || found[7].isEmpty || found[4].lowercased() == found[7].lowercased() else { return nil }
            a = x; b = y; said = found[0]; kind = found[1].lowercased()
        } else if let found = groups(#"\b(?:buys?|bought|pays?|paid) [^.?]{0,40}?(?:for )?£ ?(\d+(?:\.\d+)?) and (?:then )?(?:sells?|sold) (?:it |them |each [a-z]+ )?(?:for )?£ ?(\d+(?:\.\d+)?)"#, in: text),
                  let x = Double(found[1]), let y = Double(found[2]) {
            a = x; b = y; said = found[0]; kind = "profit"
        } else { return nil }
        guard a > 0, b > 0, a != b else { return nil }
        let rest = text.replacingOccurrences(of: said, with: " ")
        guard let ask = groups(#"\bpercentage (increase|decrease|change|profit|loss|reduction)\b"#, in: rest), rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let up = b > a, askWord = ask[1].lowercased()
        if kind == "profit" { guard (askWord == "profit") == up, askWord == "profit" || askWord == "loss" else { return nil } }
        else {
            guard askWord != "profit", askWord != "loss", askWord == "change" || (askWord == "increase") == up else { return nil }
            if has(#"^(?:increase|rise|rose|goes up|went up)"#, kind) { guard up else { return nil } }
            if has(#"^(?:decrease|fall|fell|drop|goes down|went down)"#, kind) { guard !up else { return nil } }
        }
        let change = abs(b - a) / a * 100
        let rounded = (change * 100).rounded() / 100
        let exact = abs(change - rounded) < 1e-9
        let shown: Expr = exact ? number2(change) : sigFigs(change, 3)
        let way = askWord == "change" ? (up ? "increase of " : "decrease of ") : ""
        return told("percentage \(askWord)", [MathLine(.symbol(way + Format.text(shown) + "%"))],
                    [Step("Find the change", "", [MathLine(.symbol("change"), number(abs(b - a)))]),
                     Step("Divide by where it started", "", [MathLine(.symbol("\(text2(abs(b - a))) ÷ \(text2(a)) × 100"), shown, relation: exact ? "=" : "≈", suffix: "%")])])
    }

    /// "Joe and Kyle share an amount of money in the ratio 7 : n. Joe gets 35% of the money.
    /// Work out the value of n", "History : French = 7 : 2. The time for History is 20 hours more
    /// than for French. Work out the total time."
    private static func ratioWithDifference(_ input: String) -> Problem? {
        let text = grouped(input)
        let name = #"((?-i:[A-Z][a-z]+))"#
        if let ratio = groups("\\b\(name) and \(name) share [a-z ]*?in the ratio (\\d+) ?: ?(?-i:([a-z]))\\b", in: text),
           let fact = groups("\\b(\(ratio[1])|\(ratio[2])) (?:gets|receives|is given|has) \(percent) of\\b", in: text),
           has("\\b(?:work out|find|calculate|what is) (?:the value of )?(?-i:\(ratio[4]))\\b", text), let a = Double(ratio[3]), let p = Double(fact[2]), p > 0, p < 100 {
            let rest = text.replacingOccurrences(of: ratio[0], with: " ").replacingOccurrences(of: fact[0], with: " ")
            guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
            let first = fact[1] == ratio[1]
            // first: a / (a + n) = p, so n = a(100 − p)/p; second: n / (a + n) = p, so n = ap/(100 − p).
            let n = first ? a * (100 - p) / p : a * p / (100 - p)
            guard abs(n - n.rounded()) < 1e-9 || abs(n * 100 - (n * 100).rounded()) < 1e-6 else { return nil }
            return told(ratio[4], [MathLine(.symbol(ratio[4]), number(n))],
                        [Step("\(fact[1])'s part is \(text2(p))% of all", first ? "\(text2(a)) parts are \(text2(p))%, so 1% is \(text2(a / p)) parts." : "", []),
                         Step("The rest is \(text2(100 - p))%", "", [MathLine(.symbol(ratio[4]), number(n))])])
        }
        // "History : French = 7 : 2", "in the ratio 7 : 2", and one is N more than the other.
        guard let ratio = groups(#"\b([A-Z][a-z]+) ?: ?([A-Z][a-z]+) ?= ?(\d+) ?: ?(\d+)(?!\d|:|\.\d)"#, in: text),
              let a = Double(ratio[3]), let b = Double(ratio[4]), a > 0, b > 0, a != b else { return nil }
        var rest = text.replacingOccurrences(of: ratio[0], with: " ")
        let x = NSRegularExpression.escapedPattern(for: ratio[1]), y = NSRegularExpression.escapedPattern(for: ratio[2])
        guard let more = groups("\\b(?:for )?(\(x)|\(y)) is (£ ?)?(\\d+(?:\\.\\d+)?) ?([a-z]+)? (more|less|fewer) than (?:for )?(\(x)|\(y))\\b", in: rest),
              more[1].lowercased() != more[6].lowercased(), let d = Double(more[3]), d > 0 else { return nil }
        rest = rest.replacingOccurrences(of: more[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let bigger = more[5].lowercased() == "more" ? more[1] : more[6]
        guard (bigger.lowercased() == ratio[1].lowercased()) == (a > b) else { return nil }
        let part = d / abs(a - b), money = !more[2].isEmpty, unit = more[4]
        func shown(_ v: Double) -> MathLine? { amount(v, money: money, count: false, unit: unit) }
        let lead = [Step("The difference is \(text2(abs(a - b))) parts", "", [MathLine(.symbol("1 part"), .symbol(money ? pounds(part) : text2(part)), suffix: unit.isEmpty ? nil : unit)])]
        if has(#"\b(?:total|altogether|in all|together)\b"#, rest), let answer = shown(part * (a + b)) {
            return told("the total", [answer], lead + [Step("Multiply by all \(text2(a + b)) parts", "", [answer])])
        }
        let asked = [ratio[1], ratio[2]].filter { has("\\b\(askVerb)\\b[^.?]*\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", rest) }
        guard asked.count == 1, let answer = shown(part * (asked[0] == ratio[1] ? a : b)) else { return nil }
        return told(asked[0], [answer], lead + [Step("Multiply", "", [answer])])
    }

    /// Matches with where they are: (start, end) offsets in UTF-16 and the groups.
    private static func located(_ pattern: String, in text: String) -> [(start: Int, end: Int, groups: [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (match.range.location, match.range.location + match.range.length,
             (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" })
        }
    }

    /// Changes one after another, each used as many times as it says: "decreases by 25% in the
    /// first year 12% in each of the next 4 years", "reduced by 30% … then reduced by r%",
    /// "increase by 3% this year and then by 8% next year".
    private static func stages(_ input: String) -> Problem? {
        let text = grouped(input)
        guard !has(#"\bsimple interest\b|\bwhich (?:bank|account|offer)\b|\bcompare\b|\bbetter\b|\bdifference\b"#, text) else { return nil }
        let marks = located(#"(?:(\d+(?:\.\d+)?)|\b(?-i:([a-z]))) ?%"#, in: text)
        guard marks.count >= 2, marks.count <= 4 else { return nil }
        let verb = #"\b(increas|decreas|reduc|rais|rise|rises|rising|rose|fall|falls|fell|grow|grew|cut|drop|los|lost|depreciat|appreciat|goes up|goes down|went up|went down)[a-z]*"#
        let utf = text.utf16
        func piece(_ from: Int, _ to: Int) -> String {
            String(utf[utf.index(utf.startIndex, offsetBy: from)..<utf.index(utf.startIndex, offsetBy: to)]) ?? ""
        }
        struct Stage { var up: Bool; var rate: Double?; var letter: String?; var times: Int?; var rest: Bool }
        var stages: [Stage] = [], overall: (up: Bool, rate: Double)?
        var used: [(Int, Int)] = []
        var direction: Bool?
        for (i, mark) in marks.enumerated() {
            let clauseStart = i == 0 ? 0 : marks[i - 1].end
            let before = piece(clauseStart, mark.start)
            let sentence = before.components(separatedBy: CharacterSet(charactersIn: ".?")).last ?? before
            let nextStart = i + 1 < marks.count ? marks[i + 1].start : utf.count
            var after = piece(mark.end, nextStart)
            if let cut = after.firstIndex(where: { ".?".contains($0) }) { after = String(after[..<cut]) }
            used.append((mark.start, mark.end))
            // "This 20% increase adds £240": a change named again, not another one.
            guard !has(#"\b(?:this|that|the|these|those) $"#, before) else { return nil }
            if has(#"\boverall\b"#, sentence) {
                guard let verbFound = every(verb, in: sentence).last?[1], let rate = Double(mark.groups[1]), overall == nil else { return nil }
                overall = (!has("^(?:decreas|reduc|fall|fell|drop|cut|los|depreciat|goes down|went down)", verbFound), rate)
                continue
            }
            if let found = every(verb, in: sentence).last?[1] {
                direction = !has("^(?:decreas|reduc|fall|fell|drop|cut|los|depreciat|goes down|went down)", found)
            } else if has(#"^ ?(?:per (?:year|annum) )?compound interest\b"#, after) {
                direction = true
            } else if direction == nil || has(#"[A-Za-z]{3,}"#, sentence.replacingOccurrences(of: #"\b(?:and|then|by|in|the|first|year|after|that|this|next|each|of)\b"#, with: "", options: [.regularExpression, .caseInsensitive])) {
                // A percentage that isn't a change, or one whose way isn't said.
                return nil
            }
            guard let up = direction else { return nil }
            var stage = Stage(up: up, rate: Double(mark.groups[1]), letter: mark.groups[2].isEmpty ? nil : mark.groups[2], times: nil, rest: false)
            if let rate = stage.rate { guard rate > 0, up || rate < 100 else { return nil } }
            // How many times: "in the first year", "in each of the next 4 years", "each year for
            // the next two years", "this year", "next year", "each year after that".
            let afterStart = mark.end
            if let found = located(#"^\W*(?:(?:in|for|during) )?(?:the )?first (?:year|month|week|day|hour)\b|^\W*(?:this|next|the following|the second|the third) (?:year|month|week)\b"#, in: after).first {
                stage.times = 1; used.append((afterStart + found.start, afterStart + found.end))
            } else if let found = located(#"\b(?:in|for|during|over) (?:each of )?the next (\d+|[a-z]+) (?:year|month|week|day|hour)s?\b|\b(?:each|every|per|a) (?:year|month|week|day|hour) for (?:the next )?(\d+|[a-z]+) (?:year|month|week|day|hour)s?\b"#, in: after).first,
                      let n = counted(found.groups[1].isEmpty ? found.groups[2] : found.groups[1]), n >= 1 {
                stage.times = n; used.append((afterStart + found.start, afterStart + found.end))
            } else if let found = located(#"\b(?:each|every|per|a|for each (?:extra|further|other)) (?:year|month|week|day|hour)(?: after that| after| thereafter| from then on)?\b"#, in: after).first {
                stage.rest = true; used.append((afterStart + found.start, afterStart + found.end))
            } else if i > 0, has(#"\bfirst (?:year|month)\b"#, before), stages.isEmpty {
                stage.times = 1
            }
            if let found = located(#"\b(?:at the end of|after) the first (?:year|month|week|day|hour)\b"#, in: before).last {
                stage.times = stage.times ?? 1; used.append((clauseStart + found.start, clauseStart + found.end))
            }
            stages.append(stage)
        }
        guard stages.count >= 2 || (stages.count == 1 && overall != nil) else { return nil }
        guard stages.filter({ $0.letter != nil }).count <= 1 else { return nil }

        // The time asked about: "after 5 years", "at the end of the three years".
        var total: Int?
        for found in located(#"\b(?:after|at the end of|by the end of|for|over|in) (?:the )?(\d+|[a-z]+) (?:year|month|week|day|hour)s?(?: ago)?\b"#, in: text) {
            guard let n = counted(found.groups[1]), !used.contains(where: { $0.0 <= found.start && found.end <= $0.1 }),
                  !used.contains(where: { found.start < $0.1 && $0.0 < found.end }) else { continue }
            guard total == nil || total == n else { return nil }
            total = n; used.append((found.start, found.end))
        }
        // How many times each is used.
        let known = stages.compactMap(\.times).reduce(0, +)
        let open = stages.filter { $0.times == nil && $0.rest }.count
        if open > 0 {
            guard open == 1, let total, total > known else { return nil }
            for index in stages.indices where stages[index].times == nil && stages[index].rest { stages[index].times = total - known }
        }
        for index in stages.indices where stages[index].times == nil {
            guard total == nil || stages.count == 1 else { return nil }
            stages[index].times = 1
        }
        let span = stages.compactMap(\.times).reduce(0, +)
        if let total { guard span == total else { return nil } }
        guard span <= 50 else { return nil }

        // A limit to compare with: "more than 100 000".
        var limit: (value: Double, above: Bool)?
        if let found = located(#"\b(more than|over|greater than|less than|fewer than|under|below) (£ ?)?(\d+(?:\.\d+)?)\b"#, in: text).last, let v = Double(found.groups[3]),
           found.start > marks.last!.end {
            limit = (v, !has("^(?:less|fewer|under|below)", found.groups[1])); used.append((found.start, found.end))
        }
        // The amounts: one before the changes, or one after them.
        var start: (value: Double, said: String, money: Bool)?, end: (value: Double, said: String, money: Bool)?
        for found in located(#"(£ ?)?(?<![\d.,])(\d+(?:\.\d+)?)(?![\d.,]*%)"#, in: text) {
            guard !used.contains(where: { $0.0 <= found.start && found.end <= $0.1 }) else { continue }
            guard let v = Double(found.groups[2]), v > 0 else { return nil }
            let value = (value: v, said: found.groups[0], money: !found.groups[1].isEmpty)
            if found.end <= marks.first!.start { guard start == nil else { return nil }; start = value }
            else if found.start >= marks.last!.end { guard end == nil else { return nil }; end = value }
            else { return nil }
        }
        if let s = start, !s.money { guard isCount(s.said, in: text) else { return nil } }
        if let e = end, !e.money { guard isCount(e.said, in: text) || has("\\b(?:is|was|of|be) \(NSRegularExpression.escapedPattern(for: e.said))", text) else { return nil } }

        var lines: [MathLine] = []
        func m(_ s: Stage, _ r: Double) -> Double { s.up ? 1 + r / 100 : 1 - r / 100 }
        for s in stages {
            let shown = s.letter.map { "(1 \(s.up ? "+" : "−") \($0)/100)" } ?? text2(m(s, s.rate ?? 0))
            lines.append(MathLine(.symbol("\(s.up ? "up" : "down") \(s.letter ?? text2(s.rate ?? 0))%\(s.times! > 1 ? ", \(s.times!) times" : "")"), .symbol(s.times! > 1 ? "\(shown)^\(s.times!)" : shown)))
        }
        let lead = [Step("Write each change as a multiplier", "Each one is used as many times as it happens.", lines)]
        let product = stages.reduce(1.0) { $0 * ($1.letter == nil ? pow(m($1, $1.rate!), Double($1.times!)) : 1) }
        let money = start?.money ?? end?.money ?? false
        let count = !money

        // One rate not known.
        if let unknown = stages.first(where: { $0.letter != nil }), let letter = unknown.letter {
            guard has("\\b(?:find|work out|calculate|what is) (?:the value of )?(?-i:\(letter))\\b", text) else { return nil }
            var wanted: Double
            if let overall, start == nil, end == nil { wanted = overall.up ? 1 + overall.rate / 100 : 1 - overall.rate / 100 }
            else if let start, let end, overall == nil { wanted = end.value / start.value }
            else { return nil }
            let k = pow(wanted / product, 1 / Double(unknown.times!))
            let r = unknown.up ? (k - 1) * 100 : (1 - k) * 100
            guard r > 0, r < 100 || unknown.up else { return nil }
            let rounded = (r * 100).rounded() / 100
            let exact = abs(r - rounded) < 1e-6
            let answer = MathLine(.symbol(letter), number2(r), relation: exact ? "=" : "≈")
            return told(letter, [answer], lead + [Step("Divide to find what's left for \(letter)", "", [MathLine(.symbol("multiplier"), number(k), relation: exact ? "=" : "≈")]), Step("Turn it into a percentage", "", [answer])])
        }
        guard overall == nil else { return nil }
        let worked = MathLine(.symbol("all the changes"), number(product), relation: "≈", suffix: "times")
        // Forward: from the start to the end.
        if let start, end == nil {
            let value = start.value * product
            let ask = every("\\b\(askVerb)\\b[^.?]*|\\bis (?:the|it|this)\\b[^.?]*\\?", in: text).last?[0] ?? ""
            if let limit {
                guard has(#"^is\b"#, ask) else { return nil }
                let yes = limit.above ? value > limit.value : value < limit.value
                let shown = money ? pounds(value) : "\(Int(value.rounded()))"
                guard abs(value - limit.value) > 0.5 else { return nil }
                return told("yes or no", [MathLine(.symbol("\(yes ? "Yes" : "No"), \(shown)"))],
                            lead + [Step("Multiply", "", [worked, MathLine(.symbol(start.said), .symbol(shown), relation: "→")])])
            }
            guard has(#"\b(?:value|worth|price|number|amount|total|population|cost)\b"#, ask), !has(#"\b(?:before|original|when (?:new|bought)|ago)\b"#, ask) else { return nil }
            let answer = money ? MathLine(.symbol(pounds(value))) : MathLine(.integer(Int(value.rounded())))
            return told("after the changes", [answer], lead + [Step("Multiply by them all", "", [worked]), Step("Multiply the start by that", "", [answer])])
        }
        // Back: from the end to the start.
        if let end, start == nil, limit == nil {
            guard has(#"\b(?:before|original(?:ly)?|when (?:she |he |they |it was |it was )?(?:new|bought)|bought it|at the start|start of|ago|invested|in the first place)\b"#,
                      every("\\b\(askVerb)\\b[^.?]*", in: text).last?[0] ?? "") else { return nil }
            guard let answer = amount(end.value / product, money: money, count: count && !end.said.contains(".")) else { return nil }
            return told("before the changes", [answer], lead + [Step("Multiply them together", "", [worked]), Step("Divide to go back", "\(end.said) ÷ \(text2(product)).", [answer])])
        }
        return nil
    }


    /// "On Tuesday, Helen delivered 20% more parcels than on Monday. On Wednesday, Helen
    /// delivered 50% fewer parcels than on Tuesday. On Wednesday, Helen delivered 72 parcels.
    /// Calculate the number of parcels that Helen delivered on Monday."
    private static func dayChain(_ input: String) -> Problem? {
        let text = grouped(input)
        let when = #"((?-i:[A-Z][a-z]+|(?:19|20)\d\d))"#
        let facts = every("\\b(?:on|in) \(when),? [^.?%]*?\\b\(percent) (more|fewer|less|higher|lower|greater) ([a-z]+(?: [a-z]+)?) than (?:on|in) \(when)\\b", in: text)
        guard facts.count >= 2 else { return nil }
        var rest = text
        for fact in facts { rest = rest.replacingOccurrences(of: fact[0], with: " ") }
        let noun = facts[0][4].lowercased()
        guard facts.allSatisfy({ $0[4].lowercased() == noun }) else { return nil }
        guard let known = groups("\\b(?:on|in) \(when),? [^.?%]*?\\b(\\d+) \(NSRegularExpression.escapedPattern(for: noun))\\b", in: rest), let value = Double(known[2]), value > 0 else { return nil }
        rest = rest.replacingOccurrences(of: known[0], with: " ")
        guard let ask = groups("\\b(?:how many|number of) \(NSRegularExpression.escapedPattern(for: noun))\\b[^.?]*?\\b(?:on|in) \(when)\\b", in: rest) else { return nil }
        rest = rest.replacingOccurrences(of: ask[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Each day as a multiple of the one known.
        var size: [String: Double] = [known[1]: 1]
        var pending = facts, lines: [MathLine] = []
        while !pending.isEmpty {
            guard let index = pending.firstIndex(where: { size[$0[1]] != nil || size[$0[5]] != nil }), let p = Double(pending[index][2]) else { return nil }
            let fact = pending.remove(at: index)
            let m = has(upWords, fact[3]) ? 1 + p / 100 : 1 - p / 100
            guard m > 0 else { return nil }
            if let base = size[fact[5]] {
                guard size[fact[1]] == nil else { return nil }
                size[fact[1]] = base * m
            } else { size[fact[5]] = size[fact[1]]! / m }
            lines.append(MathLine(.symbol(fact[1]), .symbol("\(text2(m)) × \(fact[5])")))
        }
        guard let k = size[ask[1]] else { return nil }
        let answer = value * k
        guard let line = amount(answer, money: false, count: true) else { return nil }
        return told("\(noun) on \(ask[1])", [line],
                    [Step("Write each as a multiplier", "", lines),
                     Step("Work from \(known[1])", "\(ask[1]) is \(text2(k)) times \(known[1]).", [line])])
    }

    /// "£2448 is invested at a rate of compound interest. One year after the investment there is
    /// £2496.96 in the account. How much is in the account four years after the investment?"
    private static func rateFromOneYear(_ input: String) -> Problem? {
        let text = grouped(input)
        guard has(#"\bcompound interest\b"#, text), !text.contains("%"),
              let found = groups(#"£ ?(\d+(?:\.\d+)?) is invested\b[^.?]*[.]? ?One year (?:after|later)[^.?£]*?£ ?(\d+(?:\.\d+)?)"#, in: text),
              let a = Double(found[1]), let b = Double(found[2]), b > a else { return nil }
        var rest = text.replacingOccurrences(of: found[0], with: " ")
        guard let ask = groups(#"\bhow much\b[^.?]*?\b(\d+|[a-z]+) years (?:after|later)\b"#, in: rest), let n = counted(ask[1]), n >= 2, n <= 50 else { return nil }
        rest = rest.replacingOccurrences(of: ask[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let m = b / a
        let answer = MathLine(.symbol(pounds(a * pow(m, Double(n)))))
        return told("after \(n) years", [answer],
                    [Step("Find the multiplier for one year", "£\(text2(b)) ÷ £\(text2(a)).", [MathLine(.symbol("multiplier"), number(m))]),
                     Step("Multiply \(n) times", "", [MathLine(Expr.number(.real(a)) * .power(.number(.real(m)), .integer(n)), .symbol(pounds(a * pow(m, Double(n)))), relation: "≈")])])
    }

    /// "Purple paint is made by mixing red paint and blue paint in the ratio 5 : 2. Yan has 30
    /// litres of red paint and 9 litres of blue paint. What is the maximum amount of purple paint
    /// he can make?"
    private static func mixLimit(_ text: String) -> Problem? {
        guard let mix = groups(#"\bmade by mixing ([a-z]+)(?: [a-z]+)? and ([a-z]+)(?: [a-z]+)? in the ratio (\d+(?:\.\d+)?) ?: ?(\d+(?:\.\d+)?)(?!\d|:|\.\d)"#, in: text),
              let a = Double(mix[3]), let b = Double(mix[4]), a > 0, b > 0 else { return nil }
        let unit = #"(litres?|ml|millilitres?|kg|g|grams?|tonnes?|cups?|tins?)"#
        guard let have = groups("\\bhas (\\d+(?:\\.\\d+)?) \(unit) of \(NSRegularExpression.escapedPattern(for: mix[1]))\\b(?: [a-z]+)? and (\\d+(?:\\.\\d+)?) \(unit) of \(NSRegularExpression.escapedPattern(for: mix[2]))\\b", in: text),
              singular(have[2].lowercased()) == singular(have[4].lowercased()), let x = Double(have[1]), let y = Double(have[3]), x > 0, y > 0 else { return nil }
        let rest = text.replacingOccurrences(of: mix[0], with: " ").replacingOccurrences(of: have[0], with: " ")
        guard has(#"\b(?:maximum|most|greatest|largest) (?:amount|volume|quantity|mass) of\b"#, rest), rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Whichever runs out first.
        let fromFirst = x / a, fromSecond = y / b
        let part = min(fromFirst, fromSecond)
        let total = part * (a + b)
        guard let answer = amount(total, money: false, count: false, unit: have[2]) else { return nil }
        let short = fromFirst < fromSecond ? mix[1] : mix[2]
        return told("the most", [answer],
                    [Step("See which runs out first", "\(text2(x)) of \(mix[1]) is enough for \(text2(fromFirst)) lots of the ratio; \(text2(y)) of \(mix[2]) is enough for \(text2(fromSecond)).", []),
                     Step("Use all the \(short)", "\(text2(part)) lots of \(text2(a + b)) parts.", [answer])])
    }

    /// "Marie invests £8000 for one year … pays tax on this interest at a rate of 20%. She pays
    /// £28.80 tax. Work out the percentage interest rate for the account."
    private static func taxOnInterest(_ input: String) -> Problem? {
        let text = grouped(input)
        guard let invest = groups(#"\binvests £ ?(\d+(?:\.\d+)?)(?: in an? [a-z ]+?)? for one year\b"#, in: text),
              let tax = groups("\\btax on (?:this|the) interest at a rate of \(percent)", in: text),
              let paid = groups(#"\bpays £ ?(\d+(?:\.\d+)?) (?:in )?tax\b"#, in: text),
              let a = Double(invest[1]), let p = Double(tax[1]), let t = Double(paid[1]), a > 0, p > 0, t > 0 else { return nil }
        let rest = text.replacingOccurrences(of: invest[0], with: " ").replacingOccurrences(of: tax[0], with: " ").replacingOccurrences(of: paid[0], with: " ")
        guard has(#"\bpercentage interest rate\b|\binterest rate\b"#, rest), rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let interest = t / (p / 100), rate = interest / a * 100
        guard abs(rate * 100 - (rate * 100).rounded()) < 1e-6 else { return nil }
        return told("interest rate", [MathLine(.symbol(Format.text(number2(rate)) + "%"))],
                    [Step("Find the interest", "£\(text2(t)) is \(text2(p))% of it.", [MathLine(.symbol("interest"), .symbol(pounds(interest)))]),
                     Step("As a percentage of £\(text2(a))", "", [])])
    }

    /// "Last year a family recycled 800 kg of household waste. 57% of this waste was paper and
    /// glass. weight of paper recycled : weight of glass recycled = 12 : 7. Calculate the weight
    /// of glass the family recycled."
    private static func percentThenRatio(_ text: String) -> Problem? {
        guard let whole = groups(#"\b(\d+(?:\.\d+)?) ?(kg|g|tonnes?|litres?|ml|m|km|cm)? (?:of )?([a-z]+(?: [a-z]+)?)\b"#, in: text),
              let share = groups("\\b\(percent) of (?:this|the|these|that) [a-z]+ (?:was|were|is|are) ([a-z]+) and ([a-z]+)\\b", in: text),
              let ratio = groups("\\b(?:(?:the )?[a-z]+ of )?\(NSRegularExpression.escapedPattern(for: share[2]))(?: [a-z]+)? ?: ?(?:(?:the )?[a-z]+ of )?\(NSRegularExpression.escapedPattern(for: share[3]))(?: [a-z]+)? ?= ?(\\d+) ?: ?(\\d+)(?!\\d|:|\\.\\d)", in: text),
              let total = Double(whole[1]), let p = Double(share[1]), let a = Double(ratio[1]), let b = Double(ratio[2]), p > 0, p <= 100, a > 0, b > 0 else { return nil }
        var rest = text.replacingOccurrences(of: ratio[0], with: " ").replacingOccurrences(of: share[0], with: " ")
        rest = rest.replacingOccurrences(of: whole[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let asked = [share[2], share[3]].filter { has("\\b(?:weight|mass|amount|volume|number|length) of \(NSRegularExpression.escapedPattern(for: $0))\\b", rest) || has("\\bhow much \(NSRegularExpression.escapedPattern(for: $0))\\b", rest) }
        guard asked.count == 1 else { return nil }
        let both = total * p / 100
        let value = both * (asked[0] == share[2] ? a : b) / (a + b)
        guard let answer = amount(value, money: false, count: false, unit: whole[2]) else { return nil }
        return told(asked[0], [answer],
                    [Step("Find \(text2(p))% of \(text2(total))\(whole[2].isEmpty ? "" : " " + whole[2])", "That's the \(share[2]) and \(share[3]) together.", [MathLine(.symbol("\(share[2]) and \(share[3])"), number(both))]),
                     Step("Share it in the ratio \(text2(a)) : \(text2(b))", "", [answer])])
    }

    /// "In a sale, the normal price of a coat is reduced by R%. Given that sale price = 0.7 ×
    /// normal price, find the value of R."
    private static func percentFromMultiplier(_ text: String) -> Problem? {
        guard let cut = groups(#"\b(reduced|increased|decreased|raised|cut) by (?-i:([A-Za-z])) ?%"#, in: text),
              let given = groups(#"\b([a-z]+ price|new [a-z]+|[a-z]+ value) ?= ?(\d+(?:\.\d+)?) ?[×x*] ?(?:the )?(normal price|original price|old price|[a-z]+ price|original value|old value)\b"#, in: text),
              let k = Double(given[2]), k > 0,
              has("\\b(?:find|work out|calculate|what is) (?:the value of )?(?-i:\(cut[2]))\\b", text) else { return nil }
        let rest = text.replacingOccurrences(of: cut[0], with: " ").replacingOccurrences(of: given[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let up = has(#"^(?:increased|raised)$"#, cut[1])
        guard up == (k > 1), k != 1 else { return nil }
        let r = abs(k - 1) * 100
        return told(cut[2], [MathLine(.symbol(cut[2]), number2(r))],
                    [Step("The multiplier is \(text2(k))", "\(up ? "Adding" : "Taking off") \(cut[2])% leaves \(text2(k * 100))%.", []),
                     Step("Find \(cut[2])", "", [MathLine(.symbol(cut[2]), number2(r))])])
    }

    /// "The van can safely carry 1375 kg. Jack has already loaded 1200 kg to the nearest 50 kg.
    /// A table has mass 140 kg to the nearest 10 kg. Can the table safely be added?"
    private static func safeLoad(_ text: String) -> Problem? {
        guard let limit = groups(#"\bcan (?:safely )?(?:carry|hold|take|lift) (?:a maximum of |up to )?(\d+(?:\.\d+)?) ?(kg|g|tonnes?|people|litres?)\b"#, in: text),
              let cap = Double(limit[1]) else { return nil }
        let unit = NSRegularExpression.escapedPattern(for: limit[2])
        let loads = every("\\b(\\d+(?:\\.\\d+)?) ?\(unit)(?: of [a-z]+)? (?:to|correct to) the nearest (\\d+(?:\\.\\d+)?) ?\(unit)\\b", in: text)
        guard loads.count == 2, has(#"\bcan (?:the|it|this|they|he|she) [a-z ]*(?:safely )?be added\b|\bis it safe\b|\bsafe to\b"#, text) else { return nil }
        var rest = text.replacingOccurrences(of: limit[0], with: " ")
        for load in loads { rest = rest.replacingOccurrences(of: load[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        var most = 0.0
        var lines: [MathLine] = []
        for load in loads {
            guard let v = Double(load[1]), let n = Double(load[2]), n > 0 else { return nil }
            most += v + n / 2
            lines.append(MathLine(.symbol("most for \(load[1]) \(limit[2])"), number(v + n / 2), suffix: limit[2]))
        }
        guard abs(most - cap) > 1e-9 else { return nil }
        let yes = most < cap
        return told("is it safe", [MathLine(.symbol(yes ? "Yes: at most \(text2(most)) \(limit[2])" : "No: it could be \(text2(most)) \(limit[2])"))],
                    [Step("Take each at its upper bound", "Half the rounding either side.", lines),
                     Step("Compare with \(text2(cap)) \(limit[2])", yes ? "Even the most it could be is under the limit." : "The most it could be is over the limit.", [])])
    }

    /// "You pay 0% on the first £12 500 you earn, 20% on the next £37 500 you earn, 40% on the
    /// next £112 500 you earn. One year, Kim paid £9260 income tax. Work out how much she earned."
    private static func earnedFromTax(_ input: String) -> Problem? {
        let text = grouped(input)
        let bands = every("\\b\(percent) on the (first|next) £ ?(\\d+(?:\\.\\d+)?)\\b(?: (?:you|of what you|of your) earn)?", in: text)
        guard bands.count >= 2, bands[0][2].lowercased() == "first", bands.dropFirst().allSatisfy({ $0[2].lowercased() == "next" }),
              let paid = groups(#"\bpaid £ ?(\d+(?:\.\d+)?) (?:in )?(?:income )?tax\b"#, in: text), let t = Double(paid[1]), t > 0,
              has(#"\bhow much (?:she|he|they|you) earned\b|\bwork out (?:her|his|their) (?:earnings|income|salary|pay)\b"#, text) else { return nil }
        var rest = text.replacingOccurrences(of: paid[0], with: " ")
        for band in bands { rest = rest.replacingOccurrences(of: band[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        var earned = 0.0, owed = t, lines: [MathLine] = []
        for band in bands {
            guard let p = Double(band[1]), let size = Double(band[3]), size > 0 else { return nil }
            let full = size * p / 100
            if owed <= full + 1e-9 {
                guard p > 0 else { continue }
                let part = owed / (p / 100)
                earned += part; owed = 0
                lines.append(MathLine(.symbol("\(text2(p))% of \(pounds(part))"), .symbol(pounds(part * p / 100))))
                break
            }
            earned += size; owed -= full
            lines.append(MathLine(.symbol("\(text2(p))% of \(pounds(size))"), .symbol(pounds(full))))
        }
        guard owed < 1e-6 else { return nil }
        let answer = MathLine(.symbol(pounds(earned)))
        return told("earned", [answer], [Step("Fill each band in turn until the tax is used up", "", lines), Step("Add the earnings", "", [answer])])
    }


    /// "Tamsin buys a house with a value of £150 000. The value of Tamsin's house increases by 4%
    /// each year. Rachel buys a house with a value of £160 000 … 1.5% each year. At the end of 2
    /// years, whose house has the greater value?"
    private static func whoseMore(_ input: String) -> Problem? {
        let text = grouped(input)
        let name = #"((?-i:[A-Z][a-z]+))"#
        let owned = every("\\b\(name) (?:buys|bought|has|invests|owns) [^.?£%]*?£ ?(\\d+(?:\\.\\d+)?)", in: text)
        let changes = every("\\b\(name)'s [a-z]+ (?:increases|decreases|goes up|goes down|rises|falls)(?: in value)? by \(percent) (?:each|every|per|a) year\\b", in: text)
        guard owned.count == 2, changes.count == 2, Set(owned.map { $0[1] }).count == 2, Set(owned.map { $0[1] }) == Set(changes.map { $0[1] }),
              let span = groups(#"\b(?:at the end of|after) (\d+|[a-z]+) years\b"#, in: text), let n = counted(span[1]),
              has(#"\b(?:whose|which|who)\b[^.?]*\b(?:greater|greatest|more|most|higher|larger|bigger)\b"#, text) else { return nil }
        var rest = text.replacingOccurrences(of: span[0], with: " ")
        for item in owned { rest = rest.replacingOccurrences(of: item[0], with: " ") }
        for item in changes { rest = rest.replacingOccurrences(of: item[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        var values: [(String, Double)] = [], lines: [MathLine] = []
        for item in owned {
            guard let start = Double(item[2]), let change = changes.first(where: { $0[1] == item[1] }), let p = Double(change[2]) else { return nil }
            let down = has("\\b(?:decreases|goes down|falls)\\b", change[0])
            let multiplier = down ? 1 - p / 100 : 1 + p / 100
            let value = start * pow(multiplier, Double(n))
            values.append((item[1], value))
            lines.append(MathLine(.symbol("\(item[1])'s"), .symbol("\(pounds(start)) × \(text2(multiplier))^\(n) = \(pounds(value))")))
        }
        guard abs(values[0].1 - values[1].1) >= 0.01 else { return nil }
        let best = values[0].1 > values[1].1 ? values[0] : values[1], other = values[0].1 > values[1].1 ? values[1] : values[0]
        return told("whose is worth more", [MathLine(.symbol("\(best.0)'s: \(pounds(best.1)) (\(other.0)'s \(pounds(other.1)))"))],
                    [Step("Work out each after \(n) years", "", lines)])
    }

    /// "700g for £7.70, 3kg for £32.40, 5kg for £53.90. Which pack is the best value for money?"
    private static func bestValue(_ text: String) -> Problem? {
        guard has(#"\bbest value\b|\bbetter value\b"#, text) else { return nil }
        let offers = every(#"\b(\d+(?:\.\d+)?) ?(kg|g|grams?|kilograms?|litres?|l|ml|millilitres?)\b(?: (?:pack|bag|box|bottle|tin|jar|tub))?(?: (?:for|costs?|is|at|=|:))? ?£ ?(\d+(?:\.\d+)?)"#, in: text)
        guard offers.count >= 2, offers.count <= 5 else { return nil }
        var rest = text
        for offer in offers { rest = rest.replacingOccurrences(of: offer[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        var each: [(said: String, cost: Double)] = [], kinds = Set<String>()
        for offer in offers {
            guard let size = Double(offer[1]), let price = Double(offer[3]), size > 0, price > 0 else { return nil }
            let unit = offer[2].lowercased()
            let base: (kind: String, size: Double)
            switch unit {
            case "g", "gram", "grams": base = ("mass", 1)
            case "kg", "kilogram", "kilograms": base = ("mass", 1000)
            case "ml", "millilitre", "millilitres": base = ("volume", 1)
            default: base = ("volume", 1000)
            }
            kinds.insert(base.kind)
            each.append(("\(offer[1])\(offer[2])", price / (size * base.size / 1000)))
        }
        guard kinds.count == 1 else { return nil }
        let unit = kinds.first == "mass" ? "kg" : "litre"
        let sorted = each.sorted { $0.cost < $1.cost }
        // Too close to call to the penny-and-a-bit: say nothing.
        guard sorted[1].cost - sorted[0].cost > 0.0005 else { return nil }
        func per(_ v: Double) -> String { "£" + String(format: "%.3f", v).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression).replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression) }
        return told("best value", [MathLine(.symbol("The \(sorted[0].said) pack: \(per(sorted[0].cost)) per \(unit)"))],
                    [Step("Work out the price per \(unit) of each", "", each.map { MathLine(.symbol($0.said), .symbol(per($0.cost)), suffix: "per \(unit)") }),
                     Step("The cheapest per \(unit) is the best value", "", [])])
    }

    /// "Each panel has a length of 1.8 m, correct to 1 decimal place. The garden is 42 m, correct
    /// to the nearest metre. The minimum number of panels to be certain there are enough", and
    /// "7.5 litres of soup, correct to the nearest 0.5 litre … 300 ml portions, correct to the
    /// nearest 10 ml. 24 people. Does he definitely have enough?"
    private static func certainEnough(_ text: String) -> Problem? {
        let measure = #"(\d+(?:\.\d+)?) ?(mm|cm|m|km|ml|litres?|l|g|kg)\b"#
        let accuracy = #",? (?:correct )?to (?:the nearest (\d+(?:\.\d+)?) ?(mm|cm|m|metres?|km|ml|millilitres?|litres?|l|g|grams?|kg)|the nearest (mm|cm|m|metre|km|ml|millilitre|litre|g|gram|kg|whole number)|(\d+|one|two|three) decimal places?|(\d+|one|two|three) significant figures?)\b"#
        let facts = located("\\b\(measure)[^.?]{0,40}?\(accuracy)", in: text)
        guard facts.count == 2 else { return nil }
        var rest = text
        for fact in facts { rest = rest.replacingOccurrences(of: fact.groups[0], with: " ") }
        func size(_ unit: String) -> (kind: String, size: Double)? {
            switch unit.lowercased() {
            case "mm": return ("length", 0.001)
            case "cm": return ("length", 0.01)
            case "m", "metre", "metres": return ("length", 1)
            case "km": return ("length", 1000)
            case "ml", "millilitre", "millilitres": return ("volume", 0.001)
            case "l", "litre", "litres": return ("volume", 1)
            case "g", "gram", "grams": return ("mass", 0.001)
            case "kg": return ("mass", 1)
            default: return nil
            }
        }
        // Each in the base unit, with its half-step either way.
        var items: [(value: Double, half: Double, kind: String)] = []
        for fact in facts {
            let g = fact.groups
            guard let v = Double(g[1]), let u = size(g[2]) else { return nil }
            var step: Double
            if let n = Double(g[3]), let s = size(g[4]) { guard s.kind == u.kind else { return nil }; step = n * s.size / u.size }
            else if !g[5].isEmpty { guard g[5] != "whole number", let s = size(g[5]), s.kind == u.kind else { return nil }; step = s.size / u.size }
            else if let d = counted(g[6]) { step = pow(10, -Double(d)) }
            else { return nil }
            items.append((v * u.size, step * u.size / 2, u.kind))
        }
        guard items[0].kind == items[1].kind else { return nil }
        let whole = items[0].value >= items[1].value ? items[0] : items[1], piece = items[0].value >= items[1].value ? items[1] : items[0]
        func shown(_ v: Double) -> String { text2(v) }
        if has(#"\b(?:minimum|least|smallest) number of [a-z]+\b[^.?]*\b(?:certain|sure)\b"#, rest) {
            guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
            let most = whole.value + whole.half, least = piece.value - piece.half
            guard least > 0 else { return nil }
            let count = Int((most / least - 1e-9).rounded(.up))
            return told("least number to be certain", [MathLine(.integer(count))],
                        [Step("Take the longest the whole could be and the shortest each piece could be", "", [MathLine(.symbol("\(shown(most)) ÷ \(shown(least))"), number(most / least), relation: "≈")]),
                         Step("Round up", "A part of one won't do.", [MathLine(.integer(count))])])
        }
        guard let people = groups(#"\b(\d+) (?:people|guests|children|students|customers)\b"#, in: rest), let n = Double(people[1]), n > 0,
              has(#"\bdefinitely\b|\bcertainly\b|\bbe sure\b|\bfor certain\b"#, rest) else { return nil }
        rest = rest.replacingOccurrences(of: people[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let least = whole.value - whole.half, most = n * (piece.value + piece.half)
        guard abs(least - most) > 1e-9 else { return nil }
        let yes = least > most
        let unit = ["length": "m", "volume": "litres", "mass": "kg"][whole.kind] ?? ""
        return told("definitely enough", [MathLine(.symbol(yes ? "Yes: at least \(shown(least)) \(unit), at most \(shown(most)) \(unit) needed" : "No: \(shown(n)) could need \(shown(most)) \(unit), but there could be only \(shown(least)) \(unit)"))],
                    [Step("The least there could be", "", [MathLine(.symbol("least"), number(least))]),
                     Step("The most \(shown(n)) could need", "", [MathLine(.symbol("most"), number(most))])])
    }


    /// "Jack sent 15% more text messages in March than in February. Jack sent 460 text messages
    /// in March. How many more texts did Jack send in March than in February?"
    private static func moreThanBefore(_ input: String) -> Problem? {
        let text = grouped(input)
        let when = #"((?-i:[A-Z][a-z]+|(?:19|20)\d\d))"#
        guard every("%", in: text).count == 1,
              let fact = groups("\\b\(percent) (more|fewer|less) ([a-z]+(?: [a-z]+)?) (?:in|on) \(when) than (?:in|on) \(when)\\b", in: text),
              let p = Double(fact[1]), p > 0, p < 100 || has(upWords, fact[2]) else { return nil }
        var rest = text.replacingOccurrences(of: fact[0], with: " ")
        let noun = NSRegularExpression.escapedPattern(for: fact[3])
        guard let known = groups("\\b(\\d+) \(noun) (?:in|on) \(when)\\b", in: rest), let v = Double(known[1]), v > 0,
              known[2] == fact[4] || known[2] == fact[5] else { return nil }
        rest = rest.replacingOccurrences(of: known[0], with: " ")
        let m = has(upWords, fact[2]) ? 1 + p / 100 : 1 - p / 100
        // fact[4] is m times fact[5].
        let later = known[2] == fact[4] ? v : v * m, earlier = known[2] == fact[5] ? v : v / m
        guard let line = amount(later, money: false, count: true), let base = amount(earlier, money: false, count: true) else { return nil }
        let lead = [Step("\(fact[4]) is \(text2(m)) times \(fact[5])", "", [MathLine(.symbol(fact[5]), base.parts[0]), MathLine(.symbol(fact[4]), line.parts[0])])]
        if let ask = groups("\\bhow many (more|fewer|less) [a-z]+\\b[^.?]*\\b(?:in|on) \(when) than (?:in|on) \(when)\\b", in: rest) {
            rest = rest.replacingOccurrences(of: ask[0], with: " ")
            guard rest.range(of: #"\d"#, options: .regularExpression) == nil, Set([ask[2], ask[3]]) == Set([fact[4], fact[5]]) else { return nil }
            let gap = abs(later - earlier)
            return told("how many \(ask[1].lowercased())", [MathLine(.integer(Int(gap.rounded())))], lead + [Step("Take one from the other", "", [])])
        }
        guard let ask = groups("\\bhow many [a-z]+\\b[^.?]*\\b(?:in|on) \(when)\\b", in: rest), ask[1] != known[2], ask[1] == fact[4] || ask[1] == fact[5] else { return nil }
        rest = rest.replacingOccurrences(of: ask[0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        return told("in \(ask[1])", [ask[1] == fact[4] ? line : base], lead)
    }

    /// "Renee buys 5 kg of sweets. She pays £10 for the sweets. She puts 250 g of sweets into each
    /// bag. She sells each bag of sweets for 65p. Work out her percentage profit."
    private static func bagsProfit(_ text: String) -> Problem? {
        let unit = #"(kg|g|grams?|kilograms?|litres?|ml)"#
        guard let bought = groups("\\bbuys (\\d+(?:\\.\\d+)?) ?\(unit) of ([a-z]+)", in: text),
              let paid = groups(#"\bpays £ ?(\d+(?:\.\d+)?)"#, in: text),
              let each = groups("\\bputs (\\d+(?:\\.\\d+)?) ?\(unit) of [a-z]+ into each ([a-z]+)", in: text),
              let sells = groups(#"\bsells each [a-z]+(?: of [a-z]+)? for (?:£ ?(\d+(?:\.\d+)?)|(\d+) ?p\b)"#, in: text),
              has(#"\bsells all\b"#, text), let ask = groups(#"\bpercentage (profit|loss)\b"#, in: text) else { return nil }
        var rest = text
        for found in [bought, paid, each, sells] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        func grams(_ v: Double, _ u: String) -> Double { has("^(?:kg|kilograms?|litres?)$", u) ? v * 1000 : v }
        guard let q = Double(bought[1]), let c = Double(paid[1]), let s = Double(each[1]), q > 0, c > 0, s > 0,
              (has("^(?:kg|kilograms?|g|grams?)$", bought[2])) == (has("^(?:kg|kilograms?|g|grams?)$", each[2])) else { return nil }
        let price = sells[1].isEmpty ? (Double(sells[2]) ?? 0) / 100 : (Double(sells[1]) ?? 0)
        let bags = grams(q, bought[2]) / grams(s, each[2])
        guard price > 0, abs(bags - bags.rounded()) < 1e-9 else { return nil }
        let income = bags.rounded() * price, change = (income - c) / c * 100
        guard (ask[1].lowercased() == "profit") == (change > 0) else { return nil }
        let shown = abs(change)
        let exact = abs(shown * 100 - (shown * 100).rounded()) < 1e-6
        return told("percentage \(ask[1].lowercased())", [MathLine(.symbol(Format.text(exact ? number2(shown) : sigFigs(shown, 3)) + "%"))],
                    [Step("Count the \(each[3])s", "", [MathLine(.symbol("\(each[3])s"), .integer(Int(bags.rounded())))]),
                     Step("Work out the money taken", "", [MathLine(.symbol("taken"), .symbol(pounds(income)))]),
                     Step("Compare with the \(pounds(c)) paid", "", [])])
    }

    /// "20 straight lines cost £12. cost of one straight line : cost of one arc = 2 : 3. A pattern
    /// is made using 20 straight lines and 16 arcs. Work out the total cost."
    private static func costRatio(_ text: String) -> Problem? {
        guard let known = groups(#"\b(\d+) ([a-z]+(?: [a-z]+)?) cost £ ?(\d+(?:\.\d+)?)"#, in: text),
              let ratio = groups(#"\bcost of (?:one|1|a|an) ([a-z]+(?: [a-z]+)?) ?: ?cost of (?:one|1|a|an) ([a-z]+(?: [a-z]+)?) ?= ?(\d+) ?: ?(\d+)(?!\d|:|\.\d)"#, in: text),
              let made = groups(#"\busing (\d+) ([a-z]+(?: [a-z]+)?) and (\d+) ([a-z]+(?: [a-z]+)?)\b"#, in: text),
              has(#"\btotal cost\b"#, text) else { return nil }
        var rest = text
        for found in [known, ratio, made] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        func same(_ a: String, _ b: String) -> Bool { singular(a.lowercased()) == singular(b.lowercased()) }
        guard let n = Double(known[1]), let c = Double(known[3]), let a = Double(ratio[3]), let b = Double(ratio[4]), n > 0, a > 0, b > 0,
              let x = Double(made[1]), let y = Double(made[3]), same(known[2], ratio[1]) || same(known[2], ratio[2]) else { return nil }
        let one = c / n
        let first = same(known[2], ratio[1]) ? one : one * a / b, second = same(known[2], ratio[1]) ? one * b / a : one
        let costs: [String: Double] = [singular(ratio[1].lowercased()): first, singular(ratio[2].lowercased()): second]
        guard let cx = costs[singular(made[2].lowercased())], let cy = costs[singular(made[4].lowercased())], made[2] != made[4] else { return nil }
        let total = x * cx + y * cy
        return told("total cost", [MathLine(.symbol(pounds(total)))],
                    [Step("Find the cost of one \(singular(known[2]))", "", [MathLine(.symbol(singular(known[2])), .symbol(pounds(one)))]),
                     Step("Use the ratio for the other", "", [MathLine(.symbol(singular(ratio[1])), .symbol(pounds(first))), MathLine(.symbol(singular(ratio[2])), .symbol(pounds(second)))]),
                     Step("Add up", "", [MathLine(.symbol("\(text2(x)) × \(pounds(cx)) + \(text2(y)) × \(pounds(cy))"), .symbol(pounds(total)))])])
    }

    /// "Lava flows at a constant rate of 11.9 m³/s. How many days does it take for 67 205 600 m³
    /// to flow? Give your answer correct to the nearest day", "A machine can dig, on average, 2 cm
    /// of tunnel each minute. It operates 24 hours each day. How many days should it take to dig
    /// a tunnel of length 3.5 km? Give your answer to the nearest day."
    private static func rateTime(_ input: String) -> Problem? {
        var text = grouped(input).replacingOccurrences(of: #"m(?: ?\^ ?| )?3\b"#, with: "m³", options: .regularExpression)
        // "67205 600 m³": one amount, spaced wrongly.
        text = text.replacingOccurrences(of: #"(?<![\d.])(\d{1,6}) (\d{3})(?= ?(?:mm|cm|m|km|ml|litre))"#, with: "$1$2", options: .regularExpression)
        let unit = #"(cm³|m³|mm|cm|km|m|ml|litres?)"#
        let per = #"(?: ?/ ?| per | each | every | a )(s|sec|second|min|minute|h|hr|hour|day)\b"#
        guard let rate = groups("\\b(\\d+(?:\\.\\d+)?) ?\(unit)(?: of [a-z]+)?\(per)", in: text),
              let ask = groups(#"\bhow many (seconds|minutes|hours|days)\b"#, in: text),
              let round = groups(#"\b(?:to|correct to) the nearest (second|minute|hour|day)\b"#, in: text), ask[1].hasPrefix(round[1]) else { return nil }
        var rest = text.replacingOccurrences(of: rate[0], with: " ")
        guard let size = groups("\\b(\\d+(?:\\.\\d+)?) ?\(unit)(?![A-Za-z0-9³])", in: rest) else { return nil }
        rest = rest.replacingOccurrences(of: size[0], with: " ")
        // "It operates 24 hours each day": the only other number allowed.
        var hoursPerDay = 24.0
        if let found = groups(#"\boperates (\d+) hours (?:each|every|a|per) day\b"#, in: rest), let h = Double(found[1]), h > 0, h <= 24 {
            hoursPerDay = h; rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        func base(_ u: String) -> (kind: String, size: Double)? {
            switch u { case "mm": return ("l", 0.001); case "cm": return ("l", 0.01); case "m": return ("l", 1); case "km": return ("l", 1000)
            case "cm³", "ml": return ("v", 1e-6); case "m³": return ("v", 1); case "litre", "litres": return ("v", 0.001); default: return nil }
        }
        guard let r = Double(rate[1]), let q = Double(size[1]), r > 0, q > 0, let ru = base(rate[2]), let qu = base(size[2]), ru.kind == qu.kind else { return nil }
        let seconds: [String: Double] = ["s": 1, "sec": 1, "second": 1, "min": 60, "minute": 60, "h": 3600, "hr": 3600, "hour": 3600, "day": 3600 * hoursPerDay]
        guard let each = seconds[rate[3].lowercased()] else { return nil }
        let total = q * qu.size / (r * ru.size) * each
        let target: Double = ["seconds": 1, "minutes": 60, "hours": 3600, "days": 3600 * hoursPerDay][ask[1].lowercased()]!
        let value = total / target
        guard value >= 0.5 else { return nil }
        let rounded = Int(value.rounded())
        return told(ask[1].lowercased(), [MathLine(.integer(rounded), suffix: ask[1].lowercased())],
                    [Step("Divide the amount by the rate", "In the same units.", [MathLine(.symbol("time"), number2(value), relation: "≈", suffix: ask[1].lowercased())]),
                     Step("Round to the nearest \(round[1])", "", [])])
    }


    /// "Alex invests £4500 at a rate of 7.5% per year simple interest. (a) Find the value of the
    /// investment at the end of 4 years. (b) At the end of t years, the value of the investment is
    /// over £13 500 for the first time. Find the value of t."
    private static func simpleInterest(_ input: String) -> Problem? {
        let text = grouped(input)
        guard every("%", in: text).count == 1, !has(#"\bcompound\b"#, text),
              let found = groups("\\binvests? £ ?(\\d+(?:\\.\\d+)?)(?: [a-z ]+?)? at (?:a rate of )?\(percent) (?:per (?:year|annum)|a year|each year) simple interest\\b|\\binvests? £ ?(\\d+(?:\\.\\d+)?)(?: [a-z ]+?)? at \(percent) simple interest (?:per (?:year|annum)|a year|each year)\\b", in: text),
              let a = Double(found[1].isEmpty ? found[3] : found[1]), let r = Double(found[1].isEmpty ? found[4] : found[2]), a > 0, r > 0 else { return nil }
        let rest = text.replacingOccurrences(of: found[0], with: " ")
        let yearly = a * r / 100
        let parts = lettered(rest)
        let segments = parts.isEmpty ? [(label: "", text: rest)] : parts
        var answers: [(label: String, line: MathLine)] = []
        var lead = [Step("Work out one year's interest", "\(text2(r))% of \(pounds(a)).", [MathLine(.symbol("each year"), .symbol(pounds(yearly)))])]
        for segment in segments {
            var part = segment.text
            if let span = groups(#"\b(?:at the end of|after|for) (\d+|[a-z]+) years?\b"#, in: part), let n = counted(span[1]) {
                part = part.replacingOccurrences(of: span[0], with: " ")
                guard part.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
                if has(#"\b(?:how much|total|amount of) interest\b|\binterest (?:does|will|did)\b"#, part) {
                    answers.append((segment.label, MathLine(.symbol(pounds(yearly * Double(n))))))
                } else if has(#"\b(?:value|worth|total|amount)\b"#, part) {
                    answers.append((segment.label, MathLine(.symbol(pounds(a + yearly * Double(n))))))
                    lead.append(Step("Add \(n) years of it", "", [MathLine(.symbol("\(pounds(a)) + \(n) × \(pounds(yearly))"), .symbol(pounds(a + yearly * Double(n))))]))
                } else { return nil }
            } else if let goal = groups(#"\b(?:over|more than|at least|exceeds?) £ ?(\d+(?:\.\d+)?)"#, in: part), let target = Double(goal[1]), target > a,
                      let letter = groups(#"\b(?:find|work out) (?:the value of )?(?-i:([a-z]))\b"#, in: part) {
                part = part.replacingOccurrences(of: goal[0], with: " ")
                guard part.replacingOccurrences(of: #"\bfor the first time\b"#, with: "", options: [.regularExpression, .caseInsensitive]).range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
                let strict = !has(#"^at least"#, goal[0])
                var t = Int(((target - a) / yearly).rounded(.down))
                while strict ? a + yearly * Double(t) <= target + 1e-9 : a + yearly * Double(t) < target - 1e-9 { t += 1 }
                answers.append((segment.label, MathLine(.symbol(letter[1]), .integer(t))))
                lead.append(Step("Find the first whole year past \(pounds(target))", "", [MathLine(.symbol("after \(t) years"), .symbol(pounds(a + yearly * Double(t))))]))
            } else { return nil }
        }
        guard !answers.isEmpty else { return nil }
        if answers.count == 1 { return told("simple interest", [answers[0].line], lead) }
        return told("simple interest", [MathLine(.symbol(answers.map { "(\($0.label)) \($0.line.text)" }.joined(separator: ",  ")))], lead)
    }

    // MARK: A recipe scaled up

    /// "Deon needs 50 g of sugar to make 15 biscuits. She also needs three times as much flour
    /// as sugar … Deon is going to make 60 biscuits. (a) Work out the amount of flour she needs.
    /// … She buys the butter in 250 g packs. (b) How many packs of butter does Deon need to buy?"
    private static func recipe(_ text: String) -> Problem? {
        let unit = #"(g|kg|ml|litres?|grams?|kilograms?|millilitres?)"#
        guard let base = groups("\\b(\\d+(?:\\.\\d+)?) ?\(unit) of ([a-z]+) (?:to make|for|makes) (\\d+) ([a-z]+)\\b", in: text),
              let amount = Double(base[1]), let made = Int(base[4]), made > 0 else { return nil }
        var rest = text.replacingOccurrences(of: base[0], with: " ")
        let thing = singular(base[5])
        var size: [String: Double] = [singular(base[3]): amount]
        var said = ["\(base[1]) \(base[2]) of \(base[3]) for \(made) \(base[5])"]
        for found in every(#"\b(twice|half|(?:\d+(?:\.\d+)?|[a-z]+) times) as much ([a-z]+) as ([a-z]+)\b"#, in: rest) {
            let word = found[1].lowercased()
            let k: Double? = word == "twice" ? 2 : (word == "half" ? 0.5 : word.split(separator: " ").first.flatMap { counted(String($0)).map(Double.init) ?? Double($0) })
            guard let k, k > 0, let of = size[singular(found[3])], size[singular(found[2])] == nil else { return nil }
            size[singular(found[2])] = of * k
            said.append(found[0])
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        var wanted: Int?
        for found in every(#"\bto make (\d+) ([a-z]+)\b"#, in: rest) {
            guard let n = Int(found[1]), n > 0, singular(found[2]) == thing, wanted == nil || wanted == n else { return nil }
            wanted = n
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard let wanted, wanted != made else { return nil }
        let pack = groups("\\bbuys? (?:the |all the )?([a-z]+) in (\\d+(?:\\.\\d+)?) ?\(unit) (packs|bags|bottles|tins|boxes|jars|cartons|blocks)\\b", in: rest)
        if let pack { rest = rest.replacingOccurrences(of: pack[0], with: " ") }
        let scale = Double(wanted) / Double(made)
        func needed(_ name: String) -> Double? { size[singular(name)].map { $0 * scale } }

        let parts = lettered(rest)
        let segments = parts.isEmpty ? [(label: "", text: rest)] : parts
        var answers: [(label: String, line: MathLine)] = []
        var lead = [Step("Scale up the recipe", said.joined(separator: "; ") + ". \(wanted) \(base[5]) is \(text2(scale)) times as many.", [])]
        for segment in segments {
            let asks = every(#"\bhow many (packs|bags|bottles|tins|boxes|jars|cartons|blocks) of ([a-z]+)\b"#, in: segment.text)
            if asks.count == 1, let pack, asks[0][1].lowercased() == pack[4].lowercased(), singular(asks[0][2]) == singular(pack[1]),
               let need = needed(asks[0][2]), singular(pack[3]) == singular(base[2]), let each = Double(pack[2]), each > 0 {
                let count = Int((need / each - 1e-9).rounded(.up))
                lead.append(Step("Count the \(pack[4])", "\(text2(need)) \(base[2]) of \(asks[0][2]) in \(pack[2]) \(pack[3]) \(pack[4]): round up, as part of one won't do.", [MathLine(.symbol("\(text2(need)) ÷ \(pack[2])"), number(need / each), relation: "=")]))
                answers.append((segment.label, MathLine(.integer(count))))
                rest = rest.replacingOccurrences(of: asks[0][0], with: " ")
                continue
            }
            let amounts = every(#"\b(?:work out|find|calculate) the (?:amount|mass|weight|quantity) of ([a-z]+)\b|\bhow much ([a-z]+) (?:does|do|will|is|would)\b"#, in: segment.text)
            guard amounts.count == 1, asks.isEmpty else { return nil }
            let name = amounts[0][1].isEmpty ? amounts[0][2] : amounts[0][1]
            guard let need = needed(name) else { return nil }
            lead.append(Step("The \(name)", "", [MathLine(number2(need), suffix: base[2])]))
            answers.append((segment.label, MathLine(number2(need), suffix: base[2])))
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !answers.isEmpty else { return nil }
        if answers.count == 1 { return told("how much", [answers[0].line], lead) }
        return told("how much", [MathLine(.symbol(answers.map { "(\($0.label)) \($0.line.text)" }.joined(separator: ",  ")))], lead)
    }

    // MARK: One percentage after another

    /// "The volume of sphere Q is 50% more than the volume of sphere P. The volume of sphere R
    /// is 50% more than the volume of sphere Q. Find the volume of sphere P as a fraction of the
    /// volume of sphere R."
    private static func percentChain(_ text: String) -> Problem? {
        let thing = #"(?:the )?([a-z]+) of (?:the )?(?:[a-z]+ )?(?-i:([A-Z]))\b"#
        guard let ask = groups("\\b(?:find|work out|write|express|give) \(thing) as a (fraction|percentage) of \(thing)", in: text) else { return nil }
        var rest = text.replacingOccurrences(of: ask[0], with: " ")
        var size: [String: Fraction] = [:]
        var lines: [MathLine] = []
        let facts = every("\(thing) is (\\d+(?:\\.\\d+)?) ?% (more|greater|larger|bigger|higher|less|smaller|lower) than \(thing)", in: rest)
        guard facts.count >= 2, facts.allSatisfy({ $0[1].lowercased() == ask[1].lowercased() && $0[5].lowercased() == ask[1].lowercased() }) else { return nil }
        for fact in facts { rest = rest.replacingOccurrences(of: fact[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Each as a multiple of the first one known.
        var pending = facts
        size[facts[0][6]] = Fraction(1)
        while !pending.isEmpty {
            guard let index = pending.firstIndex(where: { size[$0[2]] != nil || size[$0[6]] != nil }), let p = decimal(pending[index][3]) else { return nil }
            let fact = pending.remove(at: index)
            let up = !has("^(?:less|smaller|lower)$", fact[4])
            let factor = up ? (Fraction(100) + p) / Fraction(100) : (Fraction(100) - p) / Fraction(100)
            guard factor.top > 0 else { return nil }
            if let base = size[fact[6]] {
                let value = base * factor
                if let had = size[fact[2]] { guard had == value else { return nil } } else { size[fact[2]] = value }
            } else if let made = size[fact[2]] {
                size[fact[6]] = made / factor
            }
            lines.append(MathLine(.symbol(fact[2]), Simplify.run(factor.expr * .symbol(fact[6]))))
        }
        guard let top = size[ask[2]], let bottom = size[ask[5]], ask[2] != ask[5] else { return nil }
        let share = top / bottom
        let lead = [Step("Write each percentage as a multiplier", "", lines),
                    Step("Divide", "\(ask[2]) ÷ \(ask[5]).", [MathLine(share.expr)])]
        if ask[3].lowercased() == "percentage" {
            return told("\(ask[2]) as a percentage of \(ask[5])", [MathLine(.symbol(Format.text(number2(share.double * 100)) + "%"))], lead)
        }
        return told("\(ask[2]) as a fraction of \(ask[5])", [MathLine(share.expr)], lead)
    }

    // MARK: A ratio after both change by the same amount

    /// "The ratio of Marta's hourly pay to Khalid's hourly pay is 6 : 5. Both get an increase of
    /// £1.50 … The ratio … after this increase is 13 : 11. Work out the hourly pay before the
    /// increase for Marta and for Khalid."
    private static func ratioAfterChange(_ text: String) -> Problem? {
        let ratio = #"\bratio of (?:the )?([A-Za-z' ]+?) to (?:the )?([A-Za-z' ]+?)(?: after (?:this|the) [a-z]+)? (?:is|was|becomes|will be|=) (\d+) ?: ?(\d+)(?!\d|:|\.\d)"#
        let ratios = every(ratio, in: text)
        guard ratios.count == 2, ratios[0][1].lowercased() == ratios[1][1].lowercased(), ratios[0][2].lowercased() == ratios[1][2].lowercased(),
              let p = Int(ratios[0][3]), let q = Int(ratios[0][4]), let r = Int(ratios[1][3]), let s = Int(ratios[1][4]), p > 0, q > 0, r > 0, s > 0 else { return nil }
        var rest = text
        for found in ratios { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        var change: (money: Bool, size: Double, said: String)?
        if let found = groups(#"\b(?:both|each)\b[A-Za-z' ]*? (?:get|gets|receive|receives|are given|is given) (?:an? )?(?:increase|rise|pay rise|raise) of (£ ?)?(\d+(?:\.\d+)?)"#, in: rest) ?? groups(#"\b(?:both|each)\b[A-Za-z' ]*? (?:get|gets|receive|receives|are given|is given|win|wins|save|saves) (?:another |an extra )?(£ ?)?(\d+(?:\.\d+)?)(?: more)?\b"#, in: rest), let d = Double(found[2]) {
            change = (!found[1].isEmpty, d, found[0])
        } else if let found = groups(#"\b(?:both|each)\b[A-Za-z' ]*? (?:spend|spends|lose|loses|give away|gives away|pay|pays) (£ ?)?(\d+(?:\.\d+)?)\b"#, in: rest), let d = Double(found[2]) {
            change = (!found[1].isEmpty, -d, found[0])
        }
        guard let change, change.size != 0 else { return nil }
        rest = rest.replacingOccurrences(of: change.said, with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let before = has(#"\bbefore\b|\boriginal(?:ly)?\b|\bat first\b|\bto start with\b"#, rest)
        guard before || has(#"\bafter\b|\bnow\b"#, rest), has(#"\b(?:work out|find|calculate|how much|how many|what (?:is|was|were))\b"#, rest) else { return nil }
        // s(pk + d) = r(qk + d), so k = d(r − s) / (sp − rq).
        let bottom = s * p - r * q
        guard bottom != 0 else { return nil }
        let k = change.size * Double(r - s) / Double(bottom)
        guard k > 0 else { return nil }
        let first = Double(p) * k + (before ? 0 : change.size), second = Double(q) * k + (before ? 0 : change.size)
        guard first > 0, second > 0 else { return nil }
        func nice(_ v: Double) -> Bool { change.money ? abs(v * 100 - (v * 100).rounded()) < 1e-6 : abs(v - v.rounded()) < 1e-9 }
        guard nice(first), nice(second) else { return nil }
        func who(_ name: String) -> String {
            if let owner = groups(#"^([A-Za-z]+)'s\b"#, in: name.trimmingCharacters(in: .whitespaces)) { return owner[1] }
            return name.trimmingCharacters(in: .whitespaces)
        }
        func shown(_ v: Double) -> String { change.money ? pounds(v) : text2(v) }
        let answer = "\(who(ratios[0][1])) \(shown(first)), \(who(ratios[0][2])) \(shown(second))"
        let d = change.money ? pounds(abs(change.size)) : text2(abs(change.size))
        return told(before ? "before" : "after", [MathLine(.symbol(answer))],
                    [Step("Call them \(p)k and \(q)k", "Then \(change.size > 0 ? "adding" : "taking away") \(d) gives the new ratio.", [MathLine(.symbol("(\(p)k \(change.size > 0 ? "+" : "−") \(text2(abs(change.size)))) : (\(q)k \(change.size > 0 ? "+" : "−") \(text2(abs(change.size))))"), .symbol("\(r) : \(s)"))]),
                     Step("Cross-multiply and solve", "\(s)(\(p)k \(change.size > 0 ? "+" : "−") \(text2(abs(change.size)))) = \(r)(\(q)k \(change.size > 0 ? "+" : "−") \(text2(abs(change.size)))).", [MathLine(.symbol("k"), number(k))]),
                     Step(before ? "Multiply out" : "Multiply out and add the change", "", [MathLine(.symbol(answer))])])
    }

    // MARK: A ratio in the form 1 : n

    /// "The ratio 50 grams to 1 kilogram can be written in the form 1 : n. Find n." Both in the
    /// same unit first, using any conversion the question gives ("3 teaspoons is equivalent to
    /// 1 tablespoon").
    private static func ratioForm(_ text: String) -> Problem? {
        guard let form = groups(#"\b(?:in|as) the form (?:of )?(1 ?: ?n|n ?: ?1)\b"#, in: text) else { return nil }
        var rest = text.replacingOccurrences(of: form[0], with: " ")
        let amount = #"(\d+(?:\.\d+)?|\(?\d+\)?/\(?\d+\)?|\d+ \d+/\d+)"#
        let unitWord = #"([a-z]+)"#
        func value(_ written: String) -> Double? {
            let plain = written.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            if let mixed = groups(#"^(\d+) (\d+)/(\d+)$"#, in: plain), let w = Double(mixed[1]), let t = Double(mixed[2]), let b = Double(mixed[3]), b > 0 { return w + t / b }
            if let fraction = groups(#"^(\d+)/(\d+)$"#, in: plain), let t = Double(fraction[1]), let b = Double(fraction[2]), b > 0 { return t / b }
            return Double(plain)
        }
        // Conversions given in the question.
        var given: [(a: String, b: String, k: Double)] = []
        for found in every("\\b\(amount) \(unitWord) (?:is|are) (?:equivalent|equal) to \(amount) \(unitWord)\\b|\\b\(amount) \(unitWord) ?= ?\(amount) \(unitWord)\\b", in: rest) {
            let parts = found[1].isEmpty ? Array(found[5...8]) : Array(found[1...4])
            guard let x = value(parts[0]), let y = value(parts[2]), x > 0, y > 0 else { return nil }
            given.append((singular(parts[1]), singular(parts[3]), y / x))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        // The size of a unit in another, from what's standard and what's given.
        let standard: [String: (kind: String, size: Double)] = [
            "mg": ("mass", 0.001), "milligram": ("mass", 0.001), "g": ("mass", 1), "gram": ("mass", 1), "kg": ("mass", 1000), "kilogram": ("mass", 1000), "tonne": ("mass", 1_000_000),
            "mm": ("length", 0.001), "millimetre": ("length", 0.001), "cm": ("length", 0.01), "centimetre": ("length", 0.01), "m": ("length", 1), "metre": ("length", 1), "km": ("length", 1000), "kilometre": ("length", 1000),
            "ml": ("volume", 1), "millilitre": ("volume", 1), "cl": ("volume", 10), "centilitre": ("volume", 10), "l": ("volume", 1000), "litre": ("volume", 1000),
            "second": ("time", 1), "minute": ("time", 60), "hour": ("time", 3600), "day": ("time", 86400), "week": ("time", 604800),
            "p": ("money", 1), "penny": ("money", 1), "pence": ("money", 1), "pound": ("money", 100),
        ]
        func inUnit(_ from: String, _ to: String) -> Double? {
            if from == to { return 1 }
            if let a = standard[from], let b = standard[to], a.kind == b.kind { return a.size / b.size }
            for item in given {
                if item.a == from, item.b == to { return item.k }
                if item.a == to, item.b == from { return 1 / item.k }
            }
            return nil
        }
        // The two amounts: "the ratio 50 grams to 1 kilogram", or named ones: "3/4 of a teaspoon
        // of salt and 1 tablespoon of baking powder … the ratio of salt to baking powder".
        var first: (Double, String)?, second: (Double, String)?
        if let found = groups("\\bratio (?:of )?\(amount) \(unitWord) to \(amount) \(unitWord)\\b", in: rest) {
            guard let a = value(found[1]), let b = value(found[3]) else { return nil }
            first = (a, singular(found[2])); second = (b, singular(found[4]))
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        } else if let names = groups(#"\bratio of (?:the )?([a-z]+(?: [a-z]+)?) to (?:the )?([a-z]+(?: [a-z]+)?)\b"#, in: rest) {
            rest = rest.replacingOccurrences(of: names[0], with: " ")
            let uses = every("\\b\(amount) (?:of an? )?\(unitWord) of ([a-z]+(?: [a-z]+)?)\\b", in: rest)
            // (By the first word: "baking powder" can lose its second word at the end of a line.)
            func lead(_ name: String) -> String { name.lowercased().split(separator: " ").first.map(String.init) ?? "" }
            guard lead(names[1]) != lead(names[2]) else { return nil }
            for use in uses {
                guard let v = value(use[1]) else { return nil }
                let named = lead(use[3])
                if named == lead(names[1]), first == nil { first = (v, singular(use[2])) }
                else if named == lead(names[2]), second == nil { second = (v, singular(use[2])) }
                else { return nil }
                rest = rest.replacingOccurrences(of: use[0], with: " ")
            }
        }
        guard let first, let second, first.0 > 0, second.0 > 0, let scale = inUnit(second.1, first.1) else { return nil }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, has(#"\b(?:find|work out|what is|write down)\b"#, rest) else { return nil }
        let a = first.0, b = second.0 * scale
        let oneToN = form[1].hasPrefix("1")
        let n = oneToN ? b / a : a / b
        guard abs(n * 10000 - (n * 10000).rounded()) < 1e-6 else { return nil }
        let unitShown = first.1 + (a == 1 ? "" : "s")
        return told("n", [MathLine(.symbol("n"), number(n))],
                    [Step("Put both in \(first.1)s", "", [MathLine(.symbol("\(text2(a)) : \(text2(b))"), relation: "", suffix: unitShown)]),
                     Step("Divide both by \(text2(oneToN ? a : b))", "", [MathLine(.symbol(oneToN ? "1 : \(text2(n))" : "\(text2(n)) : 1"))])])
    }

    // MARK: A share, found from one part

    /// "Delia, Edwin and Freya share some money in the ratio 5 : 7 : 8. Freya's share is £1600.
    /// How much money did they share?"
    private static func shareFromOne(_ text: String) -> Problem? {
        // The names with the ratio, or a sentence before it: "Azmi, Beth and Callum share a flat. … They share the rent in the ratio 2 : 3 : 3."
        var split = groups(#"\b((?-i:[A-Z][a-z]+)(?:, (?-i:[A-Z][a-z]+))*) and ((?-i:[A-Z][a-z]+)) (?:also )?share [a-z ]*?in the ratio (\d+) ?: ?(\d+)(?: ?: ?(\d+))?(?!\d|:|\.\d)"#, in: text)
        var said = split.map { [$0[0]] } ?? []
        if split == nil, let people = groups(#"\b((?-i:[A-Z][a-z]+)(?:, (?-i:[A-Z][a-z]+))*) and ((?-i:[A-Z][a-z]+)) share (?:a|an|the) [a-z]+(?: [a-z]+)?\."#, in: text),
           let ratio = groups(#"\bthey share [a-z ]*?in the ratio (\d+) ?: ?(\d+)(?: ?: ?(\d+))?(?!\d|:|\.\d)"#, in: text) {
            split = [people[0], people[1], people[2], ratio[1], ratio[2], ratio[3]]
            said = [people[0], ratio[0]]
        }
        guard let split else { return nil }
        let names = split[1].components(separatedBy: ", ") + [split[2]]
        let sizes = [split[3], split[4], split[5]].compactMap { Int($0) }
        guard names.count == sizes.count, Set(names).count == names.count, sizes.allSatisfy({ $0 > 0 }) else { return nil }
        var rest = text
        for item in said { rest = rest.replacingOccurrences(of: item, with: " ") }
        let total = sizes.reduce(0, +)
        // One part known: "Freya's share is £1600", "Freya gets £1600", or "Ed gets £30 more than Fay".
        var one: Double?, money = false
        if let found = groups(#"\b((?-i:[A-Z][a-z]+))(?:'s share is| gets| receives| is given) (£ ?)?(\d+(?:\.\d+)?) more than ((?-i:[A-Z][a-z]+))\b"#, in: rest),
           let i = names.firstIndex(of: found[1]), let j = names.firstIndex(of: found[4]), let v = Double(found[3]), sizes[i] > sizes[j] {
            one = v / Double(sizes[i] - sizes[j]); money = !found[2].isEmpty
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        } else if let found = groups(#"\b((?-i:[A-Z][a-z]+))(?:'s share is| gets| receives| is given| pays) (£ ?)?(\d+(?:\.\d+)?)\b"#, in: rest),
                  let i = names.firstIndex(of: found[1]), let v = Double(found[3]) {
            one = v / Double(sizes[i]); money = !found[2].isEmpty
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        } else if let found = groups(#"\bthe (?:monthly |weekly |yearly |annual |total )?(?:rent|bill|cost|prize|profit|amount) is £ ?(\d+(?:\.\d+)?)"#, in: rest), let v = Double(found[1]) {
            // All of it known: "The monthly rent is £760."
            one = v / Double(total); money = true
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard let one, one > 0, rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        func shown(_ v: Double) -> String { money ? pounds(v) : text2(v) }
        let lead = [Step("Find one part", "", [MathLine(.symbol("1 part"), .symbol(shown(one)))])]
        if has(#"\bhow much (?:money )?(?:did|do|will) they (?:share|have)\b|\bhow much (?:money )?(?:was|is) shared\b|\b(?:work out|find|what (?:is|was)) the total\b"#, rest) {
            return told("the total", [MathLine(.symbol(shown(one * Double(total))))], lead + [Step("Multiply by the \(total) parts", "", [])])
        }
        let asked = names.filter { has("\\bhow much (?:money )?(?:does|did|will) \($0) (?:get|receive|have|pay)\\b|\\bhow much (?:money )?\($0) (?:gets|receives|has|will get)\\b|\\b(?:work out|find) \($0)'s share\\b", rest) }
        guard asked.count == 1, let i = names.firstIndex(of: asked[0]) else { return nil }
        return told("\(asked[0])'s share", [MathLine(.symbol(shown(one * Double(sizes[i]))))], lead + [Step("Multiply by \(asked[0])'s \(sizes[i]) parts", "", [])])
    }

    // MARK: Bounds

    /// "The area of a rectangle is 56 m², correct to the nearest m². The length of the rectangle
    /// is 9.2 m, correct to the nearest 0.1 m. Calculate the smallest possible width." Each
    /// measurement's bounds, then the bounds that give the smallest or largest result. Also
    /// "A lift can travel at a maximum speed of 9.83 m/s, correct to 3 significant figures. The
    /// lift travels a distance of 174 m, correct to the nearest metre. Work out the shortest
    /// possible time."
    private static func bounds(_ text: String) -> Problem? {
        let measure = #"(area|length|width|distance|time|speed|mass|volume|density|force|pressure)"#
        let unit = #"([a-z]+(?:\^?[23²³])?(?: ?/ ?[a-z]+)?)"#
        let places = #"(\d+|one|two|three|four) (decimal places?|significant figures?|d\.?p\.?|s\.?f\.?)"#
        let accuracy = "(\\d+(?:\\.\\d+)?) ?\(unit)?,? (?:correct |accurate )?to (?:the nearest (\\d+(?:\\.\\d+)?)? ?\(unit)?|\(places))"
        // "the area of a rectangle is 56 m², correct to …", "a distance of 174 m, correct to …"
        // "travels 430 km, correct to …", "The distance is 9600 km, correct to …", "His average speed is 57.3 km/h, correct to …"
        let facts = every("\\bthe \(measure) of (?:the |a |an )?[a-z]+ (?:is|was) \(accuracy)", in: text)
            + every("\\b(?:a|an|the) (?:maximum |average |constant |steady |total )?\(measure) of \(accuracy)", in: text)
            + every("\\b(?:the|his|her|its|their) (?:average |maximum |mean )?\(measure) (?:is|was) \(accuracy)", in: text)
            + every("\\b(?:travels|travelled|drives|drove|runs|ran|cycles|cycled|walks|walked|flies|flew) \(accuracy)", in: text).map { [$0[0], "distance"] + $0[1...] }
        guard facts.count == 2, facts[0][1].lowercased() != facts[1][1].lowercased() else { return nil }
        var rest = text
        for fact in facts { rest = rest.replacingOccurrences(of: fact[0], with: " ") }
        guard let ask = groups("\\b(smallest|least|lowest|minimum|shortest|largest|greatest|highest|maximum|longest) possible (?:value (?:of|for) )?(?:the )?(?:flight |journey |travel )?\(measure)\\b|\\b(lower|upper) bound (?:of|for) (?:the )?\(measure)\\b", in: rest) else { return nil }
        rest = rest.replacingOccurrences(of: ask[0], with: " ")
        let rounding = groups("\\bgive your answer (?:correct )?to \(places)", in: rest)
        if let rounding { rest = rest.replacingOccurrences(of: rounding[0], with: " ") }
        // A time "in hours and minutes, correct to the nearest minute".
        let toMinute = groups(#"\bgive your answer (?:in hours and minutes,? )?(?:correct )?to the nearest minute\b"#, in: rest)
        if let toMinute { rest = rest.replacingOccurrences(of: toMinute[0], with: " ") }
        // (Any other way the answer is to be given isn't understood.)
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgive your answers?\b"#, rest) else { return nil }
        let smallest = ask[1].isEmpty ? ask[3].lowercased() == "lower" : has("^(?:smallest|least|lowest|minimum|shortest)$", ask[1])
        // "174 m to the nearest metre": the nearest one of the unit it is measured in, not of another.
        func base(_ unit: String) -> String { unit.replacingOccurrences(of: #"\^?[23²³]$"#, with: "", options: .regularExpression).lowercased() }
        for fact in facts where !fact[5].isEmpty && !fact[3].isEmpty && !["whole", "integer", "unit"].contains(fact[5].lowercased()) {
            guard unitWord(base(fact[5])) == unitWord(base(fact[3])), fact[5].contains("/") == fact[3].contains("/") else { return nil }
        }
        let target = (ask[2].isEmpty ? ask[4] : ask[2]).lowercased()

        // Half the accuracy each way.
        func half(_ fact: [String]) -> Double? {
            guard let value = Double(fact[2]) else { return nil }
            if !fact[6].isEmpty {
                guard let n = counted(fact[6]), n >= 0, n <= 6 else { return nil }
                if fact[7].lowercased().hasPrefix("d") { return 0.5 * pow(10, -Double(n)) }
                guard n >= 1, value > 0 else { return nil }
                return 0.5 * pow(10, floor(log10(value)) - Double(n) + 1)
            }
            if fact[4].isEmpty { return 0.5 }
            return Double(fact[4]).map { $0 / 2 }
        }
        let relations: [(target: String, a: String, b: String, product: Bool)] = [
            ("area", "length", "width", true), ("width", "area", "length", false), ("length", "area", "width", false),
            ("distance", "speed", "time", true), ("speed", "distance", "time", false), ("time", "distance", "speed", false),
            ("mass", "density", "volume", true), ("density", "mass", "volume", false), ("volume", "mass", "density", false),
            ("force", "pressure", "area", true), ("pressure", "force", "area", false), ("area", "force", "pressure", false),
        ]
        let given = facts.map { $0[1].lowercased() }
        guard let relation = relations.first(where: { $0.target == target && Set([$0.a, $0.b]) == Set(given) }),
              let a = facts.first(where: { $0[1].lowercased() == relation.a }), let b = facts.first(where: { $0[1].lowercased() == relation.b }),
              let av = Double(a[2]), let bv = Double(b[2]), let ah = half(a), let bh = half(b), av - ah > 0, bv - bh > 0 else { return nil }
        // The units must fit together: an area in m² with a length in m.
        let short = ["second": "s", "minute": "min", "hour": "h", "metre": "m", "kilometre": "km", "mile": "mile", "gram": "g", "kilogram": "kg"]
        var shownUnit: String?
        switch (relation.target, relation.product) {
        case ("area", true), ("width", false), ("length", false):
            guard !a[3].isEmpty, !b[3].isEmpty, base(a[3]) == base(b[3]) else { return nil }
            shownUnit = relation.target == "area" ? base(a[3]) + "²" : base(a[3])
        case ("time", false):
            // Metres ÷ metres per second is seconds.
            let pieces = (b[3].lowercased() == "mph" ? "miles/h" : b[3]).split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2, !a[3].isEmpty, !a[3].contains("/"), unitWord(pieces[0]) == unitWord(a[3]) else { return nil }
            shownUnit = short[singular(pieces[1])] ?? pieces[1]
        case (_, false) where !a[3].isEmpty && !b[3].isEmpty && !a[3].contains("/") && !b[3].contains("/"):
            shownUnit = "\(short[singular(a[3])] ?? a[3])/\(short[singular(b[3])] ?? b[3])"
        default:
            shownUnit = nil
        }
        let (aLow, aHigh, bLow, bHigh) = (av - ah, av + ah, bv - bh, bv + bh)
        let usedA = smallest ? aLow : aHigh
        let usedB = relation.product ? (smallest ? bLow : bHigh) : (smallest ? bHigh : bLow)
        let value = relation.product ? usedA * usedB : usedA / usedB
        var answer = value, written: String?
        if let rounding {
            guard let n = counted(rounding[1]) else { return nil }
            if rounding[2].lowercased().hasPrefix("d") {
                let scale = pow(10, Double(n)); answer = (value * scale).rounded() / scale
            } else {
                guard n >= 1 else { return nil }
                let power = Double(n) - 1 - floor(log10(abs(value)))
                let scale = pow(10, power); answer = (value * scale).rounded() / scale
                // Trailing zeros count: 8.20 to 3 significant figures.
                if power > 0 { written = String(format: "%.\(Int(power))f", answer) }
            }
        } else if !isExact(value) {
            // No rounding asked for: 3 significant figures.
            let power = 2 - floor(log10(abs(value)))
            let scale = pow(10, power); answer = (value * scale).rounded() / scale
            if power > 0 { written = String(format: "%.\(Int(power))f", answer) }
        }
        let word = smallest ? "lower" : "upper"
        if toMinute != nil {
            // Hours into hours and minutes; half a minute either way is too close to call.
            let minutes = value * 60
            guard rounding == nil, relation.target == "time", shownUnit == "h", abs(minutes - minutes.rounded(.down) - 0.5) > 1e-6 else { return nil }
            let whole = Int(minutes.rounded())
            written = "\(whole / 60) hours \(whole % 60) minutes"
            shownUnit = nil
        }
        func bound(_ x: Double) -> String { text2(x) }
        // (As words, not a number: "correct to 3 significant figures" is about what was measured, and the
        // answer mustn't be rounded again by it.)
        let shown = Expr.symbol(written ?? Format.text(number(answer)))
        return told("\(smallest ? "smallest" : "largest") possible \(target)", [MathLine(shown, relation: "=", suffix: shownUnit)],
                    [Step("Find the bounds", "Half of what each is correct to, either side.",
                          [MathLine(.symbol("\(bound(aLow)) ≤ \(relation.a) < \(bound(aHigh))")), MathLine(.symbol("\(bound(bLow)) ≤ \(relation.b) < \(bound(bHigh))"))]),
                     Step("Pick the bounds", relation.product ? "For the \(smallest ? "smallest" : "largest") product, use both \(word) bounds."
                                                              : "For the \(smallest ? "smallest" : "largest") quotient, divide the \(word) bound of the \(relation.a) by the \(smallest ? "upper" : "lower") bound of the \(relation.b).",
                          [MathLine(.symbol("\(bound(usedA)) \(relation.product ? "×" : "÷") \(bound(usedB))"), number(value), relation: abs(value - answer) < 1e-12 ? "=" : "≈")])]
                    + (toMinute == nil ? [] : [Step("Turn the hours into hours and minutes", "\(text2(value - value.rounded(.down))) of an hour × 60, to the nearest minute.", [MathLine(shown)])]))
    }

    // MARK: Cheaper in one place than another

    /// "In Spain, Sam pays 27 euros for 18 litres of petrol. In Wales, Leo pays £40.80 for 8
    /// gallons of the same type of petrol. 1 euro = £0.85. 4.5 litres = 1 gallon. Sam thinks
    /// that petrol is cheaper in Spain than in Wales. Is Sam correct?"
    private static func cheaper(_ text: String) -> Problem? {
        let money = #"(£ ?)?(\d+(?:\.\d+)?) ?(euros?|dollars?|pounds?)?"#
        let amount = #"(\d+(?:\.\d+)?) ?(litres?|gallons?|pints?|kg|kilograms?|g|grams?|ml|millilitres?)"#
        // Groups: 1 place, 2 £, 3 price, 4 currency, 5 quantity, 6 unit.
        let buys = every("\\b(?:in|at) ((?-i:[A-Z][a-z]+)),? (?-i:[A-Z][a-z]+) (?:pays|paid|spends|spent) \(money) for \(amount) of\\b", in: text)
        guard buys.count == 2, buys[0][1] != buys[1][1],
              let claim = groups(#"\b([a-z]+) is (cheaper|more expensive|dearer) in ((?-i:[A-Z][a-z]+)) than in ((?-i:[A-Z][a-z]+))\b"#, in: text),
              let asked = groups(#"\bis ((?-i:[A-Z][a-z]+)) (?:correct|right)\b"#, in: text),
              Set([claim[3], claim[4]]) == Set([buys[0][1], buys[1][1]]) else { return nil }
        var rest = text.replacingOccurrences(of: claim[0], with: " ").replacingOccurrences(of: asked[0], with: " ")
        for buy in buys { rest = rest.replacingOccurrences(of: buy[0], with: " ") }
        // "1 euro = £0.85" (a currency in pounds), "4.5 litres = 1 gallon" (a unit in another).
        var inPounds: [String: Double] = ["pound": 1]
        var inUnit: [String: [String: Double]] = [:]
        for found in every(#"\b(\d+(?:\.\d+)?) ?([a-z]+) ?= ?(£ ?)?(\d+(?:\.\d+)?) ?([a-z]+)?\b"#, in: rest) {
            guard let x = Double(found[1]), let y = Double(found[4]), x > 0, y > 0 else { return nil }
            let a = singular(found[2])
            if !found[3].isEmpty { inPounds[a] = y / x } else {
                guard !found[5].isEmpty else { return nil }
                let b = singular(found[5])
                inUnit[a, default: [:]][b] = y / x
                inUnit[b, default: [:]][a] = x / y
            }
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Each as pounds for one of the first's unit.
        let unit = singular(buys[0][6])
        var cost: [String: Double] = [:]
        var lines: [MathLine] = []
        for buy in buys {
            guard let price = Double(buy[3]), let quantity = Double(buy[5]), quantity > 0 else { return nil }
            let currency = buy[2].isEmpty ? (buy[4].isEmpty ? "" : singular(buy[4])) : "pound"
            let here = singular(buy[6])
            guard let rate = inPounds[currency] else { return nil }
            let factor: Double
            if here == unit { factor = 1 } else {
                guard let k = inUnit[here]?[unit] else { return nil }
                factor = k
            }
            let each = price * rate / (quantity * factor)
            cost[buy[1]] = each
            lines.append(MathLine(.symbol(buy[1]), .symbol("£" + String(format: "%.3f", each).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)), relation: "≈", suffix: "per \(unit)"))
        }
        guard let first = cost[claim[3]], let second = cost[claim[4]], first != second else { return nil }
        let isCheaper = claim[2].lowercased() == "cheaper"
        let right = isCheaper ? first < second : first > second
        func shown(_ v: Double) -> String { "£" + String(format: "%.3f", v).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression) }
        let answer = "\(right ? "Yes" : "No"): \(claim[3]) \(shown(first)) per \(unit), \(claim[4]) \(shown(second)) per \(unit)"
        return told("is \(asked[1]) correct", [MathLine(.symbol(answer))],
                    [Step("Put both in pounds for one \(unit)", "Change the money with the exchange rate, and the amount with the conversion.", lines),
                     Step("Compare", "\(claim[1].capitalized) costs \(first < second ? "less" : "more") in \(claim[3]).", [])])
    }

    // MARK: A journey in stages

    /// "Charlie is driving 293 miles home. He leaves at 9.00 am, travels the first 176 miles at
    /// an average speed of 48 mph, drives the rest of the way at an average speed of 65 mph.
    /// Will he be home by 2.30 pm?"
    private static func journey(_ text: String) -> Problem? {
        let speed = #"(?:an )?average speed of (\d+(?:\.\d+)?) ?(mph|miles per hour|km/h|kilometres per hour)"#
        guard let total = groups(#"\b(?:driving|drives|travelling|travels|walking|walks|cycling|cycles|going|goes) (\d+(?:\.\d+)?) ?(miles|km|kilometres)\b"#, in: text),
              let first = groups("\\bthe first (\\d+(?:\\.\\d+)?) ?(miles|km|kilometres) at \(speed)", in: text),
              let second = groups("\\bthe rest of the (?:way|journey) at \(speed)", in: text),
              let start = groups(#"\bleaves (?:home )?at (\d{1,2})[.:](\d{2}) ?(am|pm)\b"#, in: text),
              let ask = groups(#"\b(?:be (?:home|there|back)|arrive(?: home| there)?|get (?:home|there)) (?:by|before) (\d{1,2})[.:](\d{2}) ?(am|pm)\b"#, in: text),
              let whole = Double(total[1]), let part = Double(first[1]), let v1 = Double(first[3]), let v2 = Double(second[1]),
              whole > part, part > 0, v1 > 0, v2 > 0, total[2].lowercased().prefix(1) == first[2].lowercased().prefix(1) else { return nil }
        var rest = text
        for found in [total, first, second, start, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        func minutes(_ clock: [String]) -> Int? {
            guard let h = Int(clock[1]), let m = Int(clock[2]), (1...12).contains(h), m < 60 else { return nil }
            return (h % 12 + (clock[3].lowercased() == "pm" ? 12 : 0)) * 60 + m
        }
        guard let leave = minutes(start), let deadline = minutes(ask) else { return nil }
        let hours = part / v1 + (whole - part) / v2
        let taken = hours * 60
        let arrive = Double(leave) + taken
        // Too close to call to the minute: say nothing.
        guard abs(arrive - Double(deadline)) >= 1 else { return nil }
        let shown = Int(arrive.rounded())
        func clock(_ m: Int) -> String {
            let h = (m / 60) % 24, mm = m % 60
            return "\(h % 12 == 0 ? 12 : h % 12).\(String(format: "%02d", mm)) \(h < 12 ? "am" : "pm")"
        }
        let length = Int(taken.rounded())
        let answer = "\(arrive < Double(deadline) ? "Yes" : "No"), at \(clock(shown))"
        return told("home by \(clock(deadline))", [MathLine(.symbol(answer))],
                    [Step("Time for each stage", "Time = distance ÷ speed.",
                          [MathLine(.symbol("\(text2(part)) ÷ \(text2(v1))"), number(part / v1), relation: "≈", suffix: "hours"),
                           MathLine(.symbol("\(text2(whole - part)) ÷ \(text2(v2))"), number((whole - part) / v2), relation: "≈", suffix: "hours")]),
                     Step("Add them", "", [MathLine(.symbol("\(length / 60) hours \(length % 60) minutes"))]),
                     Step("Add it to the start", "From \(clock(leave)): \(clock(shown)), \(arrive < Double(deadline) ? "before" : "after") \(clock(deadline)).", [])])
    }

    // MARK: How far in the next few seconds

    /// "d is directly proportional to the square of t. The ball drops 45 metres in the first 3
    /// seconds. How far does the ball drop in the next 7 seconds?"
    private static func nextStretch(_ text: String) -> Problem? {
        guard let link = groups(#"\b(?-i:([a-z])) is (?:directly )?proportional to (?:the (square|cube) of )?(?-i:([a-z]))\b"#, in: text), link[1] != link[3],
              let known = groups(#"\b(\d+(?:\.\d+)?) ?(metres|m|cm|km|miles) in the first (\d+(?:\.\d+)?) ?(seconds|minutes|hours)\b"#, in: text),
              let ask = groups(#"\bhow far [a-z ]*?in the next (\d+(?:\.\d+)?) ?(seconds|minutes|hours)\b"#, in: text),
              known[4].lowercased() == ask[2].lowercased(),
              let d = Double(known[1]), let t = Double(known[3]), let more = Double(ask[1]), d > 0, t > 0, more > 0 else { return nil }
        var rest = text
        for found in [link, known, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let power = link[2].lowercased() == "square" ? 2.0 : (link[2].lowercased() == "cube" ? 3.0 : 1.0)
        let k = d / pow(t, power)
        let end = t + more
        let far = k * (pow(end, power) - pow(t, power))
        let p = Int(power)
        let term = p == 1 ? link[3] : "\(link[3])\(p == 2 ? "²" : "³")"
        return told("how far in the next \(ask[1]) \(ask[2])", [MathLine(number(far), suffix: known[2])],
                    [Step("Find k", "\(link[1]) = k\(term), and \(link[1]) = \(known[1]) when \(link[3]) = \(known[3]).", [MathLine(.symbol("k"), number(k))]),
                     Step("Distance by the end", "The next \(ask[1]) \(ask[2]) end at \(link[3]) = \(text2(end)).", [MathLine(.symbol(link[1]), number(k * pow(end, power)))]),
                     Step("Take away the first part", "\(text2(k * pow(end, power))) − \(known[1]).", [MathLine(number(far), suffix: known[2])])])
    }

    // MARK: A decimal as a fraction

    /// "Write 1.52 as an improper fraction in its simplest form."
    private static func decimalAsFraction(_ text: String) -> Problem? {
        guard let found = groups(#"\b(?:write|express|convert|change|give) (\d+)\.(\d{1,6}) (?:as|to|into) (?:a|an) (improper fraction|mixed number|fraction)(?: in (?:its|the) (?:simplest|lowest) (?:form|terms))?"#, in: text),
              let whole = Int(found[1]), let after = Int(found[2]), after > 0 else { return nil }
        // Nothing else in the question but how to give the answer.
        var rest = text.replacingOccurrences(of: found[0], with: " ")
        rest = rest.replacingOccurrences(of: #"\bgive your answer in (?:its|the) (?:simplest|lowest) (?:form|terms)\b|\byou must show (?:all )?your working\b|\bshow (?:all )?your working\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        guard rest.range(of: #"[A-Za-z0-9]"#, options: .regularExpression) == nil else { return nil }
        let places = found[2].count, scale = Int(pow(10, Double(places))), top = whole * scale + after
        let exact = Fraction(top, scale), common = gcd(top, scale), form = found[3].lowercased()
        // An improper fraction or a mixed number is more than 1.
        if form != "fraction" { guard exact.top > exact.bottom else { return nil } }
        let written = "\(found[1]).\(found[2])"
        var lead = [Step("Write it over \(scale)", "\(places) decimal place\(places == 1 ? "" : "s"), so the bottom is \(scale).", [MathLine(.symbol(written), Expr.integer(top) / .integer(scale))])]
        if common > 1 { lead.append(Step("Simplify", "Divide the top and bottom by \(common).", [MathLine(exact.expr)])) }
        guard form == "mixed number" else { return told("\(written) as \(form == "fraction" ? "a" : "an") \(form)", [MathLine(exact.expr)], lead) }
        let mixed = "\(exact.top / exact.bottom) \(exact.top % exact.bottom)/\(exact.bottom)"
        lead.append(Step("Take out the whole number", "\(exact.top) ÷ \(exact.bottom) is \(exact.top / exact.bottom) remainder \(exact.top % exact.bottom).", [MathLine(.symbol(mixed))]))
        return told("\(written) as a mixed number", [MathLine(.symbol(mixed))], lead)
    }

    // MARK: Average speed for a whole journey

    /// "Tasha drove 198 miles. Her average speed for the first 3 hours was 45 miles per hour.
    /// Her average speed for the rest of the journey was 31.5 miles per hour. Work out her
    /// average speed for the whole journey."
    private static func wholeJourneySpeed(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        let per = #"(mph|miles per hour|miles an hour|km/h|km per hour|kilometres per hour|kilometres an hour)"#
        let whose = #"(?:her|his|their|its|the|(?-i:[A-Z][a-z]+)'s)"#
        let trip = #"(?:journey|trip|drive|ride|walk|flight|way)"#
        guard let ask = groups("\\b(?:work out|calculate|find|what (?:is|was)) \(whose) average speed for (?:the|her|his|their) (?:whole|entire|complete|total) \(trip)\\b", in: text),
              let total = groups("\\b(?:drove|drives|travelled|travels|cycled|cycles|walked|walks|ran|runs|rode|rides|flew|flies|sailed|sails) (?:a (?:total )?distance of |a total of )?\(n) ?(miles|km|kilometres)\\b", in: text) else { return nil }
        // The first stage, by its time or its distance, and the rest: groups are amount, unit, speed, speed's unit.
        let firstShapes = ["\\baverage speed for the first \(n) ?(hours?|miles|km|kilometres) (?:was|is) \(n) ?\(per)",
                           "\\bfor the first \(n) ?(hours?|miles|km|kilometres),? \(whose) average speed (?:was|is) \(n) ?\(per)",
                           "\\bthe first \(n) ?(hours?|miles|km|kilometres) at (?:an average speed of|a speed of|an average of) \(n) ?\(per)"]
        let restShapes = ["\\baverage speed for the (?:rest|remainder) of (?:the|her|his|their) \(trip) (?:was|is) \(n) ?\(per)",
                          "\\bfor the (?:rest|remainder) of (?:the|her|his|their) \(trip),? \(whose) average speed (?:was|is) \(n) ?\(per)",
                          "\\bthe (?:rest|remainder) of (?:the|her|his|their) \(trip) at (?:an average speed of|a speed of|an average of) \(n) ?\(per)"]
        guard let first = firstShapes.compactMap({ groups($0, in: text) }).first, let second = restShapes.compactMap({ groups($0, in: text) }).first,
              let whole = Double(total[1]), let amount = Double(first[1]), let v1 = Double(first[3]), let v2 = Double(second[1]), whole > 0, amount > 0, v1 > 0, v2 > 0 else { return nil }
        var rest = text
        for found in [ask, total, first, second] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        let rounding = roundingAsked(rest)
        if let rounding { rest = rest.replacingOccurrences(of: rounding.said, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgive your answers?\b"#, rest) else { return nil }
        // Miles go with miles per hour, kilometres with kilometres per hour.
        func miles(_ unit: String) -> Bool { unit.lowercased().hasPrefix("m") }
        let inMiles = miles(total[2])
        guard miles(first[4]) == inMiles, miles(second[2]) == inMiles else { return nil }
        let byTime = first[2].lowercased().hasPrefix("hour")
        if !byTime { guard miles(first[2]) == inMiles else { return nil } }
        let t1 = byTime ? amount : amount / v1, d1 = byTime ? amount * v1 : amount
        let left = whole - d1
        guard left > 1e-9 else { return nil }
        let t2 = left / v2, speed = whole / (t1 + t2)
        guard let shown = roundedAnswer(speed, rounding) else { return nil }
        let unit = inMiles ? "mph" : "km/h", far = inMiles ? "miles" : "km"
        let firstStep = byTime ? Step("Distance in the first \(text2(t1)) hours", "Distance = speed × time.", [MathLine(.symbol("\(text2(v1)) × \(text2(t1))"), number(d1), suffix: far)])
                               : Step("Time for the first \(text2(d1)) \(far)", "Time = distance ÷ speed.", [MathLine(.symbol("\(text2(d1)) ÷ \(text2(v1))"), number(t1), relation: isExact(t1) ? "=" : "≈", suffix: "hours")])
        return told("average speed for the whole journey", [MathLine(shown.expr, suffix: unit)],
                    [firstStep,
                     Step("Time for the rest", "\(text2(whole)) − \(text2(d1)) = \(text2(left)) \(far) left. Time = distance ÷ speed.",
                          [MathLine(.symbol("\(text2(left)) ÷ \(text2(v2))"), number(t2), relation: isExact(t2) ? "=" : "≈", suffix: "hours")]),
                     Step("Divide the whole distance by the whole time", "Average speed = total distance ÷ total time.",
                          [MathLine(.symbol("\(text2(whole)) ÷ (\(text2(t1)) + \(text2(t2)))"), shown.expr, relation: shown.exact ? "=" : "≈", suffix: unit)])])
    }

    /// "Claudine cycled a distance of 53 km in 2.7 hours. The distance is measured correct to
    /// the nearest km. The time is given correct to 1 decimal place. Calculate the lower and
    /// upper bounds of her average speed. Give your answers correct to 2 decimal places."
    private static func speedBounds(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        let accuracy = #"(?:measured |given )?(?:correct |accurate )?to (?:the nearest (\d+(?:\.\d+)?)? ?([a-z]+)|(\d|one|two|three) (decimal places?|significant figures?))"#
        guard let went = groups("\\b(?:cycled|cycles|ran|runs|drove|drives|walked|walks|travelled|travels|swam|flew) (?:a distance of )?\(n) ?(km|miles|m|metres) in \(n) ?(hours?|minutes?|seconds?)\\b", in: text),
              let far = groups("\\bthe distance is \(accuracy)", in: text), let long = groups("\\bthe time is \(accuracy)", in: text),
              let ask = groups(#"\b(?:calculate|work out|find) the lower and upper bounds? (?:of|for) (?:her|his|their|the|its) average speed\b"#, in: text),
              let rounding = groups(#"\bgive your answers? (?:correct )?to (\d|one|two|three) (decimal places?|significant figures?)"#, in: text),
              let d = Double(went[1]), let t = Double(went[3]), d > 0, t > 0, let figures = counted(rounding[1]), figures >= 1 else { return nil }
        var rest = text
        for found in [went, far, long, ask, rounding] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Half of what each is correct to.
        func half(_ fact: [String], _ value: Double, _ unit: String) -> Double? {
            if !fact[3].isEmpty {
                guard let places = counted(fact[3]) else { return nil }
                return fact[4].lowercased().hasPrefix("d") ? 0.5 * pow(10, -Double(places)) : (places >= 1 ? 0.5 * pow(10, floor(log10(value)) - Double(places) + 1) : nil)
            }
            guard unitWord(fact[2]) == unitWord(unit) else { return nil }
            return fact[1].isEmpty ? 0.5 : Double(fact[1]).map { $0 / 2 }
        }
        guard let dh = half(far, d, went[2]), let th = half(long, t, went[4]), d - dh > 0, t - th > 0 else { return nil }
        let low = (d - dh) / (t + th), high = (d + dh) / (t - th)
        let decimalPlaces = rounding[2].lowercased().hasPrefix("d")
        func shown(_ value: Double) -> String? {
            let places = decimalPlaces ? figures : figures - 1 - Int(floor(log10(value)))
            let scale = pow(10, Double(places))
            guard abs(value * scale - (value * scale).rounded(.down) - 0.5) > 1e-6 else { return nil }
            let rounded = (value * scale).rounded() / scale
            return places > 0 ? String(format: "%.\(places)f", rounded) : String(Int(rounded))
        }
        guard let lowShown = shown(low), let highShown = shown(high) else { return nil }
        let time = ["hour": "h", "minute": "min", "second": "s"][singular(went[4])] ?? went[4], unit = "\(unitWord(went[2]) == "mile" ? "miles" : unitWord(went[2]))/\(time)"
        return told("lower and upper bounds of the average speed", [MathLine(.symbol("lower \(lowShown) \(unit), upper \(highShown) \(unit)"))],
                    [Step("Find the bounds", "Half of what each is correct to, either side.",
                          [MathLine(.symbol("\(text2(d - dh)) ≤ distance < \(text2(d + dh))")), MathLine(.symbol("\(text2(t - th)) ≤ time < \(text2(t + th))"))]),
                     Step("Lower bound of the speed", "The least distance in the most time.", [MathLine(.symbol("\(text2(d - dh)) ÷ \(text2(t + th))"), .symbol(lowShown), relation: "≈", suffix: unit)]),
                     Step("Upper bound of the speed", "The most distance in the least time.", [MathLine(.symbol("\(text2(d + dh)) ÷ \(text2(t - th))"), .symbol(highShown), relation: "≈", suffix: unit)])])
    }

    /// "Beth drives 200 miles in 4 hours. She drives the first 18 miles at an average speed of
    /// 36 mph. Work out her average speed for the rest of the journey." (Not in the list of
    /// kinds yet: see the note there.)
    static func restOfJourneySpeed(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        let per = #"(mph|miles per hour|miles an hour|km/h|km per hour|kilometres per hour|kilometres an hour)"#
        guard let total = groups("\\b(?:drives|drove|travels|travelled|cycles|cycled|walks|walked|runs|ran|rides|rode) \(n) ?(miles|km|kilometres) in \(n) ?hours?\\b", in: text),
              let first = groups("\\bthe first \(n) ?(miles|km|kilometres) at (?:an average speed of|a speed of|an average of) \(n) ?\(per)", in: text),
              let ask = groups(#"\b(?:work out|calculate|find|what (?:is|was)) (?:her|his|their|its|the|(?-i:[A-Z][a-z]+)'s) average speed for the (?:rest|remainder) of the (?:journey|trip|drive|ride|walk|way)\b"#, in: text),
              let whole = Double(total[1]), let hours = Double(total[3]), let d1 = Double(first[1]), let v1 = Double(first[3]), whole > d1, d1 > 0, v1 > 0, hours > 0 else { return nil }
        var rest = text
        for found in [total, first, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        let rounding = roundingAsked(rest)
        if let rounding { rest = rest.replacingOccurrences(of: rounding.said, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgive your answers?\b"#, rest) else { return nil }
        func miles(_ unit: String) -> Bool { unit.lowercased().hasPrefix("m") }
        let inMiles = miles(total[2])
        guard miles(first[2]) == inMiles, miles(first[4]) == inMiles else { return nil }
        let t1 = d1 / v1, left = whole - d1, t2 = hours - t1
        guard t2 > 1e-9, let shown = roundedAnswer(left / t2, rounding) else { return nil }
        let unit = inMiles ? "mph" : "km/h", far = inMiles ? "miles" : "km"
        return told("average speed for the rest of the journey", [MathLine(shown.expr, suffix: unit)],
                    [Step("Time for the first \(text2(d1)) \(far)", "Time = distance ÷ speed.", [MathLine(.symbol("\(text2(d1)) ÷ \(text2(v1))"), number(t1), relation: isExact(t1) ? "=" : "≈", suffix: "hours")]),
                     Step("What is left", "", [MathLine(.symbol("\(text2(whole)) − \(text2(d1))"), number(left), suffix: far), MathLine(.symbol("\(text2(hours)) − \(text2(t1))"), number(t2), relation: isExact(t2) ? "=" : "≈", suffix: "hours")]),
                     Step("Divide the distance left by the time left", "", [MathLine(.symbol("\(text2(left)) ÷ \(text2(t2))"), shown.expr, relation: shown.exact ? "=" : "≈", suffix: unit)])])
    }

    /// "Olly drove 56 km from Liverpool to Manchester. He then drove 61 km from Manchester to
    /// Sheffield. Olly's average speed from Liverpool to Manchester was 70 km/h. Olly took 75
    /// minutes to drive from Manchester to Sheffield. Work out Olly's average speed for his
    /// total drive from Liverpool to Sheffield."
    private static func twoLegSpeed(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#, place = #"(?-i:([A-Z][a-z]+))"#
        let legs = every("\\b(?:drove|travelled|cycled|walked|ran|rode|flew|sailed) \(n) ?(km|miles|kilometres) from \(place) to \(place)", in: text)
        guard legs.count == 2, legs[0][4] == legs[1][3], legs[0][3] != legs[1][4], legs[0][2].lowercased().prefix(1) == legs[1][2].lowercased().prefix(1),
              let ask = groups("\\baverage speed for (?:his|her|their|the) (?:total|whole|entire) (?:drive|journey|trip|ride|walk|flight) from \(legs[0][3]) to \(legs[1][4])\\b", in: text) else { return nil }
        var rest = text.replacingOccurrences(of: ask[0], with: " ")
        for leg in legs { rest = rest.replacingOccurrences(of: leg[0], with: " ") }
        let inMiles = legs[0][2].lowercased().hasPrefix("m")
        var hours: [Double] = [], lines: [MathLine] = []
        for leg in legs {
            guard let far = Double(leg[1]), far > 0 else { return nil }
            let route = "from \(leg[3]) to \(leg[4])"
            let speed = groups("\\baverage speed \(route) (?:was|is) \(n) ?(mph|miles per hour|km/h|kilometres per hour)", in: rest)
            let took = groups("\\btook \(n) ?(minutes|hours?) to (?:drive|travel|cycle|walk|run|ride|fly|sail|get|go) \(route)", in: rest)
            // One or the other for each leg.
            guard (speed == nil) != (took == nil) else { return nil }
            if let speed {
                guard let v = Double(speed[1]), v > 0, speed[2].lowercased().hasPrefix("m") == inMiles else { return nil }
                hours.append(far / v)
                lines.append(MathLine(.symbol("\(leg[3]) to \(leg[4]): \(text2(far)) ÷ \(text2(v))"), number(far / v), relation: isExact(far / v) ? "=" : "≈", suffix: "hours"))
                rest = rest.replacingOccurrences(of: speed[0], with: " ")
            } else if let took {
                guard let t = Double(took[1]), t > 0 else { return nil }
                let inHours = took[2].lowercased().hasPrefix("h") ? t : t / 60
                hours.append(inHours)
                lines.append(MathLine(.symbol("\(leg[3]) to \(leg[4]): \(text2(t)) \(took[2].lowercased())"), number(inHours), relation: isExact(inHours) ? "=" : "≈", suffix: "hours"))
                rest = rest.replacingOccurrences(of: took[0], with: " ")
            }
        }
        let rounding = roundingAsked(rest)
        if let rounding { rest = rest.replacingOccurrences(of: rounding.said, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgive your answers?\b"#, rest), let d1 = Double(legs[0][1]), let d2 = Double(legs[1][1]) else { return nil }
        let whole = d1 + d2, time = hours[0] + hours[1]
        guard let shown = roundedAnswer(whole / time, rounding) else { return nil }
        let unit = inMiles ? "mph" : "km/h"
        return told("average speed for the whole journey", [MathLine(shown.expr, suffix: unit)],
                    [Step("Find the time for each part in hours", "Time = distance ÷ speed, and 60 minutes is 1 hour.", lines),
                     Step("Divide the whole distance by the whole time", "Average speed = total distance ÷ total time.",
                          [MathLine(.symbol("(\(text2(d1)) + \(text2(d2))) ÷ (\(text2(hours[0])) + \(text2(hours[1])))"), shown.expr, relation: shown.exact ? "=" : "≈", suffix: unit)])])
    }

    /// "A car journey is in two stages. Stage 1: the car travels 110 miles in 2 hours. Stage 2:
    /// the car travels 44 miles at the same average speed as Stage 1. Work out the time for
    /// Stage 2. Give your answer in minutes."
    private static func sameSpeedStage(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        guard let first = groups("\\bstage 1:? (?:the )?[a-z]+ travels \(n) ?(miles|km|kilometres) in \(n) ?(hours?|minutes?)\\b", in: text),
              let second = groups("\\bstage 2:? (?:the )?[a-z]+ travels \(n) ?(miles|km|kilometres) at the same (?:average )?speed as stage 1\\b", in: text),
              let ask = groups(#"\b(?:work out|calculate|find) the time (?:for|of|taken for) stage 2\b"#, in: text),
              let form = groups(#"\bgive your answer in (minutes|hours)\b"#, in: text),
              let d1 = Double(first[1]), let t1 = Double(first[3]), let d2 = Double(second[1]), d1 > 0, t1 > 0, d2 > 0,
              first[2].lowercased().prefix(1) == second[2].lowercased().prefix(1) else { return nil }
        var rest = text
        for found in [first, second, ask, form] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        // "A car journey is in two stages": the stages' own numbers are names.
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let given = first[4].lowercased().hasPrefix("h") ? "hours" : "minutes", wanted = form[1].lowercased()
        let time = d2 / d1 * t1 * (given == wanted ? 1 : (given == "hours" ? 60 : 1.0 / 60))
        guard isExact(time) else { return nil }
        let far = first[2].lowercased()
        return told("the time for Stage 2", [MathLine(number(time), suffix: time == 1 ? singular(wanted) : wanted)],
                    [Step("Find the speed in Stage 1", "Speed = distance ÷ time.", [MathLine(.symbol("\(text2(d1)) ÷ \(text2(t1))"), number(d1 / t1), relation: isExact(d1 / t1) ? "=" : "≈", suffix: "\(far) per \(singular(given))")]),
                     Step("Find the time for Stage 2 at that speed", "Time = distance ÷ speed.", [MathLine(.symbol("\(text2(d2)) ÷ \(text2(d1 / t1))"), number(d2 / d1 * t1), relation: isExact(d2 / d1 * t1) ? "=" : "≈", suffix: given)])]
                    + (given == wanted ? [] : [Step("Change it into \(wanted)", "", [MathLine(number(time), suffix: wanted)])]))
    }

    /// "Arron ran a distance of 5 km at an average speed of 2.2 m/s. How long did Arron run for?
    /// Give your answer in minutes and seconds, to the nearest second."
    private static func timeAtSpeed(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        guard let went = groups("\\b(?:ran|runs|cycled|cycles|drove|drives|walked|walks|travelled|travels|swam|swims|rode|rides) (?:a distance of )?\(n) ?(km|kilometres|m|metres|miles) at (?:an average speed of|a speed of|a constant speed of|a steady speed of) \(n) ?(m ?/ ?s|metres per second|km ?/ ?h|kilometres per hour|mph|miles per hour)", in: text),
              let ask = groups(#"\bhow long did (?:he|she|they|it|(?-i:[A-Z][a-z]+)) (?:run|cycle|drive|walk|travel|swim|ride)(?: for)?\b|\bhow long (?:did|does) (?:the|this) (?:journey|run|ride|walk|drive) take\b"#, in: text),
              let form = groups(#"\bgive your answer in (minutes and seconds|hours and minutes),? (?:correct )?to the nearest (second|minute)\b"#, in: text),
              let d = Double(went[1]), let v = Double(went[3]), d > 0, v > 0 else { return nil }
        var rest = text
        for found in [went, ask, form] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Everything in metres and seconds.
        let far = went[2].lowercased(), per = went[4].lowercased().replacingOccurrences(of: " ", with: "")
        let metres = far.hasPrefix("k") ? d * 1000 : (far.hasPrefix("mi") ? nil : d)
        let seconds: Double
        if per.hasPrefix("m/s") || per.hasPrefix("metres") {
            guard let metres else { return nil }
            seconds = metres / v
        } else if per.hasPrefix("k") {
            guard far.hasPrefix("k") else { return nil }
            seconds = d / v * 3600
        } else {
            guard far.hasPrefix("mi") else { return nil }
            seconds = d / v * 3600
        }
        let bySeconds = form[1].lowercased() == "minutes and seconds"
        guard bySeconds == (form[2].lowercased() == "second") else { return nil }
        let small = bySeconds ? seconds : seconds / 60
        // Half a second (or minute) either way is too close to call.
        guard abs(small - small.rounded(.down) - 0.5) > 1e-6 else { return nil }
        let whole = Int(small.rounded())
        let answer = bySeconds ? "\(whole / 60) minutes \(whole % 60) seconds" : "\(whole / 60) hours \(whole % 60) minutes"
        let sameUnits = (per.hasPrefix("m/s") || per.hasPrefix("metres")) && far.hasPrefix("k")
        return told("how long", [MathLine(.symbol(answer))],
                    (sameUnits ? [Step("Put the distance in metres", "", [MathLine(.symbol("\(text2(d)) km"), .symbol("\(text2(d * 1000)) m"))])] : [])
                    + [Step("Divide the distance by the speed", "Time = distance ÷ speed.",
                            [MathLine(.symbol("\(text2(sameUnits ? d * 1000 : d)) ÷ \(text2(v))"), number(sameUnits ? seconds : d / v), relation: "≈", suffix: sameUnits ? "seconds" : "hours")]),
                       Step("Change it into \(form[1].lowercased())", "To the nearest \(form[2].lowercased()).", [MathLine(.symbol(answer))])])
    }

    // MARK: How many can each have a share

    /// "To reach round 2, a student must receive at least 4/15 of the votes. What is the largest
    /// possible number of students that can reach round 2?", with or without numbers to choose
    /// from under it.
    private static func mostWithShare(_ lines: [String]) -> Problem? {
        // Lone numbers at the end are the answers to choose from.
        var body = lines, choices: [Int] = []
        while let last = body.last, last.range(of: #"^\d+(?: +\d+)*$"#, options: .regularExpression) != nil {
            choices = last.split(separator: " ").compactMap { Int($0) } + choices
            body.removeLast()
        }
        let text = body.joined(separator: " ")
        guard let need = groups(#"\b(?:must|has to|have to|needs? to) (?:receive|get|win|have|gain) (at least|more than|over) (?:\(?(\d+)\)? ?/ ?\(?(\d+)\)?|(\d+(?:\.\d+)?) ?%) of (?:all )?(?:of )?the votes\b"#, in: text),
              let ask = groups(#"\b(?:largest|greatest|maximum|highest) (?:possible )?number of (students|people|candidates|pupils|players|teams) (?:that|who|which) (?:can|could)\b"#, in: text) else { return nil }
        var rest = text.replacingOccurrences(of: need[0], with: " ").replacingOccurrences(of: ask[0], with: " ")
        // "Round 2" is a name, not an amount.
        rest = rest.replacingOccurrences(of: #"\bround \d\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let share: Fraction
        if need[4].isEmpty {
            guard let top = Int(need[2]), let bottom = Int(need[3]), top > 0, bottom > 0 else { return nil }
            share = Fraction(top, bottom)
        } else {
            guard let percent = decimal(need[4]), percent.top > 0 else { return nil }
            share = percent / Fraction(100)
        }
        guard share.top <= share.bottom, share.bottom < 100_000 else { return nil }
        // k shares can't come to more than all the votes; "more than" a share each leaves no room for the last.
        let atLeast = need[1].lowercased() == "at least"
        let fits = share.bottom / share.top
        let most = atLeast || share.bottom % share.top != 0 ? fits : fits - 1
        guard most >= 1 else { return nil }
        if !choices.isEmpty { guard choices.contains(most), Set(choices).count == choices.count else { return nil } }
        let who = ask[1].lowercased()
        let enough = Fraction(most) * share, tooMany = Fraction(most + 1) * share
        return told("largest possible number of \(who)", [MathLine(.integer(most))],
                    [Step("The shares can't add up to more than all the votes", "Each of the \(who) has \(need[1].lowercased()) \(Format.text(share.expr)) of the votes.", []),
                     Step("See how many shares fit", "\(most) fit, \(most + 1) would need \(tooMany == Fraction(1) ? "every vote, with none over" : "more than all the votes").",
                          [MathLine(.symbol("\(most) × \(Format.text(share.expr))"), enough.expr), MathLine(.symbol("\(most + 1) × \(Format.text(share.expr))"), tooMany.expr)])])
    }

    // MARK: Estimates

    /// A number to 1 significant figure: 513 is 500, 0.81 is 0.8.
    private static func oneFigure(_ value: Double) -> Double {
        guard value > 0 else { return value }
        let scale = pow(10, floor(log10(value)))
        return ((value / scale).rounded() * scale * 1e9).rounded() / 1e9
    }

    /// "Sophie drives a distance of 513 kilometres. She pays 0.81 euros for every 10 kilometres
    /// she drives. Work out an estimate for the total amount that Sophie pays."
    private static func estimatedCost(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        let unit = #"(kilometres?|km|miles?|litres?|kg|kilograms?|minutes?|hours?|units?)"#
        guard let ask = groups(#"\b(?:work out|find|calculate) an estimate (?:for|of) the (?:total )?(?:amount|cost)\b"#, in: text),
              let rate = groups("\\b(?:pays?|paid|costs?|charges?|charged) (£ ?)?\(n) ?(euros?|dollars?)? (?:for|per) (?:every |each )?(?:\(n) )?\(unit)\\b", in: text),
              rate[1].isEmpty != rate[3].isEmpty else { return nil }
        var rest = text.replacingOccurrences(of: ask[0], with: " ").replacingOccurrences(of: rate[0], with: " ")
        let amounts = every("\\b\(n) ?\(unit)\\b", in: rest)
        guard amounts.count == 1, singular(unitWord(amounts[0][2])) == singular(unitWord(rate[5])) else { return nil }
        rest = rest.replacingOccurrences(of: amounts[0][0], with: " ")
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil,
              let amount = Double(amounts[0][1]), let price = Double(rate[2]), let each = Double(rate[4].isEmpty ? "1" : rate[4]), amount > 0, price > 0, each > 0 else { return nil }
        let (a, p, e) = (oneFigure(amount), oneFigure(price), oneFigure(each))
        // Rounding has to change something, or it isn't an estimate.
        guard a != amount || p != price || e != each else { return nil }
        let estimate = a / e * p
        guard isExact(estimate) else { return nil }
        let pound = !rate[1].isEmpty, currency = pound ? "" : (singular(rate[3]) == "euro" ? "euros" : "dollars")
        func money(_ v: Double) -> String { pound ? pounds(v) : "\(text2(v)) \(currency)" }
        let name = amounts[0][2].lowercased()
        return told("an estimate for the total", [MathLine(.symbol(money(estimate)))],
                    [Step("Round each number to 1 significant figure", "",
                          [MathLine(.symbol(amounts[0][1]), number(a), relation: "≈"), MathLine(.symbol(rate[2]), number(p), relation: "≈")] + (e != each ? [MathLine(.symbol(rate[4]), number(e), relation: "≈")] : [])),
                     Step(e == 1 ? "Multiply" : "Find how many lots of \(text2(e)) \(name)", e == 1 ? "" : "\(text2(a)) ÷ \(text2(e)) = \(text2(a / e)), each costing \(money(p)).",
                          [MathLine(.symbol("\(text2(a / e)) × \(text2(p))"), .symbol(money(estimate)))])])
    }

    /// "km" for "kilometres", so that the two ways of writing a unit match.
    private static func unitWord(_ unit: String) -> String {
let short = ["kilometre": "km", "kilogram": "kg", "litre": "l", "metre": "m", "gram": "g", "centimetre": "cm", "millimetre": "mm", "millilitre": "ml", "second": "s", "hour": "h"]
        return short[singular(unit)] ?? singular(unit)
    }

    /// "A bronze ornament has a volume of 198 cm³. The density of bronze is 8.9 g/cm³. By
    /// rounding each value correct to one significant figure, work out an estimate for the mass
    /// of the bronze ornament."
    private static func estimatedMass(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        // The raised 3 comes through as a 3, a star, a degree sign, a question mark or nothing.
        let cubed = #"(?: ?\^ ?3|3(?!\d|\.\d)|³|[*°?])?"#
        guard let ask = groups(#"\bby rounding each (?:value|number|measurement|of these values) (?:correct )?to (?:one|1) significant figure, (?:work out|find|calculate) an estimate (?:for|of) the mass of\b"#, in: text),
              let volume = groups("\\bvolume of \(n) ?(mm|cm|m)(?![a-z])\(cubed)", in: text),
              let density = groups("\\bdensity of [a-z ]+? is \(n) ?(g|kg) ?/ ?(mm|cm|m)(?![a-z])\(cubed)", in: text),
              volume[2].lowercased() == density[3].lowercased() else { return nil }
        var rest = text
        for found in [ask, volume, density] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil,
              let v = Double(volume[1]), let d = Double(density[1]), v > 0, d > 0 else { return nil }
        let (rv, rd) = (oneFigure(v), oneFigure(d))
        guard rv != v || rd != d, isExact(rv * rd) else { return nil }
        let unit = density[2].lowercased()
        // (As words, not a number: "to one significant figure" is about the values, not the answer.)
        return told("an estimate for the mass", [MathLine(.symbol(text2(rv * rd)), suffix: unit)],
                    [Step("Round each value to 1 significant figure", "", [MathLine(.symbol(volume[1]), number(rv), relation: "≈"), MathLine(.symbol(density[1]), number(rd), relation: "≈")]),
                     Step("Multiply", "Mass = density × volume.", [MathLine(.symbol("\(text2(rd)) × \(text2(rv))"), number(rv * rd), suffix: unit)])])
    }

    // MARK: A midpoint on a number line

    /// "P = 1.2̇ and Q = 1 2/3. Q is the midpoint of PR. Find the value of R. Give your answer
    /// as a mixed number in its simplest form." The recurring decimal comes as the reader
    /// writes it, rec(1.,2).
    private static func midpointValue(_ text: String) -> Problem? {
        let value = #"(rec\(\d*\.\d*,\d+\)|\d+ \d+ ?/ ?\d+|\d+ ?/ ?\d+|\d+(?:\.\d+)?)"#
        guard let mid = groups(#"(?-i:(?<![A-Za-z])([A-Z])) is the mid-?point of (?-i:([A-Z])([A-Z]))(?![A-Za-z])"#, in: text), Set([mid[1], mid[2], mid[3]]).count == 3,
              let ask = groups(#"\b(?:find|work out|calculate|what is) the value of (?-i:([A-Z]))(?![A-Za-z])"#, in: text) else { return nil }
        let facts = every("(?-i:(?<![A-Za-z])([A-Z])) ?= ?\(value)(?![\\d/]|\\.\\d)", in: text)
        guard facts.count == 2, facts[0][1] != facts[1][1], Set([facts[0][1], facts[1][1], ask[1]]) == Set([mid[1], mid[2], mid[3]]) else { return nil }
        var rest = text
        for found in [mid, ask] + facts { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        let form = groups(#"\bgive your answer as (?:a|an) (mixed number|improper fraction|fraction)(?: in (?:its|the) (?:simplest|lowest) (?:form|terms))?"#, in: rest)
        if let form { rest = rest.replacingOccurrences(of: form[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Each value as a fraction, and as it was written.
        func read(_ said: String) -> (exact: Fraction, shown: String)? {
            if let found = groups(#"^rec\((\d*)\.(\d*),(\d+)\)$"#, in: said) {
                let fixed = found[2], repeating = found[3]
                guard fixed.count + repeating.count <= 8, let whole = Int(found[1].isEmpty ? "0" : found[1]), let front = Int(fixed.isEmpty ? "0" : fixed), let cycle = Int(repeating) else { return nil }
                let low = Int(pow(10, Double(fixed.count))), nines = Int(pow(10, Double(repeating.count))) - 1
                let dotted = repeating.count == 1 ? repeating + "\u{0307}" : String(repeating.first!) + "\u{0307}" + repeating.dropFirst().dropLast() + String(repeating.last!) + "\u{0307}"
                return (Fraction(whole) + Fraction(front, low) + Fraction(cycle, low * nines), "\(whole).\(fixed)\(dotted)")
            }
            if let found = groups(#"^(\d+) (\d+) ?/ ?(\d+)$"#, in: said), let whole = Int(found[1]), let top = Int(found[2]), let bottom = Int(found[3]), bottom > 1, top < bottom {
                return (Fraction(whole) + Fraction(top, bottom), "\(whole) \(top)/\(bottom)")
            }
            if let found = groups(#"^(\d+) ?/ ?(\d+)$"#, in: said), let top = Int(found[1]), let bottom = Int(found[2]), bottom > 0 { return (Fraction(top, bottom), "\(top)/\(bottom)") }
            return decimal(said).map { ($0, said) }
        }
        var known: [String: (exact: Fraction, shown: String)] = [:]
        for fact in facts {
            guard let value = read(fact[2]) else { return nil }
            known[fact[1]] = value
        }
        let wanted = ask[1], middle = mid[1]
        let answer: Fraction, rule: Step
        if wanted == middle {
            guard let a = known[mid[2]], let b = known[mid[3]] else { return nil }
            answer = (a.exact + b.exact) / Fraction(2)
            rule = Step("Find halfway between them", "The midpoint is half of their sum.", [MathLine(.symbol(wanted), .symbol("(\(Format.text(a.exact.expr)) + \(Format.text(b.exact.expr))) ÷ 2"), answer.expr)])
        } else {
            let other = wanted == mid[2] ? mid[3] : mid[2]
            guard let m = known[middle], let end = known[other] else { return nil }
            answer = Fraction(2) * m.exact - end.exact
            rule = Step("Go as far past \(middle) as \(other) is before it", "\(middle) is halfway, so \(wanted) = 2 × \(middle) − \(other).",
                        [MathLine(.symbol(wanted), .symbol("2 × \(Format.text(m.exact.expr)) − \(Format.text(end.exact.expr))"), answer.expr)])
        }
        var lead: [Step] = []
        let changed = facts.compactMap { fact -> MathLine? in
            guard let value = known[fact[1]], value.shown != Format.text(value.exact.expr) else { return nil }
            return MathLine(.symbol(fact[1]), .symbol(value.shown), value.exact.expr)
        }
        if !changed.isEmpty { lead.append(Step("Write each as a fraction", "", changed)) }
        lead.append(rule)
        let wantsMixed = form?[1].lowercased() == "mixed number"
        if wantsMixed, answer.bottom > 1, answer.top > answer.bottom {
            let mixed = "\(answer.top / answer.bottom) \(answer.top % answer.bottom)/\(answer.bottom)"
            lead.append(Step("Write it as a mixed number", "\(answer.top) ÷ \(answer.bottom) is \(answer.top / answer.bottom) remainder \(answer.top % answer.bottom).", [MathLine(.symbol(wanted), .symbol(mixed))]))
            return told("the value of \(wanted)", [MathLine(.symbol(wanted), .symbol(mixed))], lead)
        }
        // Given as decimals and not told how to answer: a decimal, when it is one.
        let plain = facts.allSatisfy { $0[2].range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil }
        if form == nil, plain, answer.bottom > 1, isExact(answer.double) { return told("the value of \(wanted)", [MathLine(.symbol(wanted), number(answer.double))], lead) }
        return told("the value of \(wanted)", [MathLine(.symbol(wanted), answer.expr)], lead)
    }

    // MARK: A fraction of them, then a ratio within those

    /// "Kasim has some small jars, some medium jars and some large jars. He has a total of 400
    /// jars. 3/8 of the 400 jars are empty. For the empty jars, number of small jars : number of
    /// medium jars = 3 : 4, number of medium jars : number of large jars = 1 : 2. Work out the
    /// percentage of Kasim's jars that are empty small jars."
    private static func partThenRatios(_ text: String) -> Problem? {
        guard let total = groups(#"\b(?:has|have|there (?:are|were)) a total of (\d+) ([a-z]+)\b"#, in: text), let all = Int(total[1]), all > 0 else { return nil }
        let thing = total[2].lowercased()
        // The part the ratios are about: "3/8 of the 400 jars are empty", "For the empty jars,".
        guard let part = groups("(?:\\(?(\\d+)\\)? ?/ ?\\(?(\\d+)\\)?|(\\d+(?:\\.\\d+)?) ?%) of (?:the|his|her|their|these|(?-i:[A-Z][a-z]+)'s) (?:(\\d+) )?\(thing) (?:are|were) ([a-z]+)\\b", in: text),
              part[4].isEmpty || Int(part[4]) == all else { return nil }
        let kind = part[5].lowercased()
        guard let scope = groups("\\bfor the \(kind) \(thing),?", in: text) else { return nil }
        let share: Fraction
        if part[3].isEmpty {
            guard let top = Int(part[1]), let bottom = Int(part[2]), top > 0, bottom > top else { return nil }
            share = Fraction(top, bottom)
        } else {
            guard let percent = decimal(part[3]), percent.top > 0, percent.double < 100 else { return nil }
            share = percent / Fraction(100)
        }
        // The kinds there are, and the ratios between them.
        guard let listed = groups("\\bsome ([a-z]+) \(thing),? (?:some ([a-z]+) \(thing),? )?and some ([a-z]+) \(thing)\\b", in: text) else { return nil }
        let names = [listed[1], listed[2], listed[3]].filter { !$0.isEmpty }.map { $0.lowercased() }
        let ratios = every("\\b(?:the )?(?:number of )?([a-z]+) \(thing) ?: ?(?:the )?(?:number of )?([a-z]+) \(thing) ?= ?(\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text)
        guard Set(names).count == names.count, ratios.count == names.count - 1,
              let ask = groups("\\b(?:work out|calculate|find) the (percentage|fraction|number) of (?:(?-i:[A-Z][a-z]+)'s |the |all the |all of the |his |her |their )?\(thing) that are \(kind) ([a-z]+) \(thing)\\b", in: text),
              names.contains(ask[2].lowercased()) else { return nil }
        var rest = text
        for found in [total, part, scope, listed, ask] + ratios { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        var size: [String: Fraction] = [:]
        for (index, ratio) in ratios.enumerated() {
            let (a, b) = (ratio[1].lowercased(), ratio[2].lowercased())
            guard let p = Int(ratio[3]), let q = Int(ratio[4]), p > 0, q > 0, a != b, names.contains(a), names.contains(b) else { return nil }
            if index == 0 { size[a] = Fraction(p); size[b] = Fraction(q); continue }
            // The second ratio shares one kind with the first, and brings in the other.
            if let had = size[a], size[b] == nil { size[b] = had * Fraction(q, p) } else if let had = size[b], size[a] == nil { size[a] = had * Fraction(p, q) } else { return nil }
        }
        guard names.allSatisfy({ size[$0] != nil }) else { return nil }
        let scale = names.reduce(1) { lcm($0, size[$1]!.bottom) }
        var parts = names.map { size[$0]!.top * (scale / size[$0]!.bottom) }
        let common = max(parts.reduce(0) { gcd($0, $1) }, 1)
        parts = parts.map { $0 / common }
        let sum = parts.reduce(0, +)
        // Whole numbers of them all the way, or the question has been misread.
        let chosen = share * Fraction(all)
        guard chosen.bottom == 1, chosen.top % sum == 0, let at = names.firstIndex(of: ask[2].lowercased()) else { return nil }
        let one = chosen.top / sum, count = one * parts[at]
        let overall = Fraction(count, all)
        let wanted = ask[1].lowercased()
        let answer: MathLine, last: Step
        switch wanted {
        case "number":
            answer = MathLine(.integer(count))
            last = Step("Count the \(kind) \(names[at]) \(thing)", "", [MathLine(.symbol("\(parts[at]) × \(one)"), .integer(count))])
        case "fraction":
            answer = MathLine(overall.expr)
            last = Step("Write the \(kind) \(names[at]) \(thing) as a fraction of all \(all)", "\(parts[at]) × \(one) = \(count) of them.", [MathLine(Expr.integer(count) / .integer(all), overall.expr)])
        default:
            let percent = overall.double * 100
            guard abs(percent * 100 - (percent * 100).rounded()) < 1e-6 else { return nil }
            answer = MathLine(.symbol(Format.text(number2(percent)) + "%"))
            last = Step("Write the \(kind) \(names[at]) \(thing) as a percentage of all \(all)", "\(parts[at]) × \(one) = \(count) of them.", [MathLine(.symbol("\(count) ÷ \(all) × 100"), .symbol(Format.text(number2(percent)) + "%"))])
        }
        var lead = [Step("Find how many are \(kind)", "", [MathLine(.symbol("\(Format.text(share.expr)) × \(all)"), .integer(chosen.top))])]
        if ratios.count > 1 {
            lead.append(Step("Make the ratios match", "Scale them so that the kind they share is the same size in both.", [MathLine(parts: parts.map { .integer($0) }, relation: ":", suffix: "(" + names.joined(separator: " : ") + ")")]))
        }
        lead.append(Step("Share out the \(chosen.top) \(kind) \(thing)", "\(sum) parts, so one part is \(one).", []))
        lead.append(last)
        return told("\(wanted) of the \(thing) that are \(kind) \(names[at])", [answer], lead)
    }

    // MARK: Shares after giving some away

    /// "Andy, Luke and Tina share some sweets in the ratio 1 : 6 : 14. Tina gives 3/7 of her
    /// sweets to Andy. Tina then gives 12½% of the rest of her sweets to Luke. Tina says, "Now
    /// all three of us have the same number of sweets." Is Tina correct?"
    private static func sharesAfterGiving(_ text: String) -> Problem? {
        let person = #"(?-i:([A-Z][a-z]+))"#
        guard let split = groups("\\b\(person), \(person) and \(person) (?:share|shared|split|divide|divided) (?:some |a number of |a bag of |a box of |a packet of )?([a-z]+) in the ratio (\\d+) ?: ?(\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text),
              has(#"\ball three (?:of us |of them )?(?:now )?have the same (?:number|amount)\b|\b(?:we|they) (?:now )?all have the same (?:number|amount)\b"#, text),
              let ask = groups("\\bis \(person) (?:correct|right)\\b", in: text) else { return nil }
        let names = [split[1], split[2], split[3]], thing = split[4]
        guard Set(names).count == 3, names.contains(ask[1]) else { return nil }
        let amount = #"(\(?\d+\)? ?/ ?\(?\d+\)?|\d+ \d+ ?/ ?\d+ ?%|\d+(?:\.\d+)? ?%)"#
        // Groups: 1 who gives, 2 "then", 3 how much, 4 and 5 "the rest of", "remaining", 6 who gets it.
        let gifts = every("\\b\(person) (then |now |also )?gives \(amount) of (the rest of |the remainder of |what is left of )?(?:her|his|their) (remaining )?\(thing) to \(person)", in: text)
        guard !gifts.isEmpty, gifts.count <= 4 else { return nil }
        var rest = text.replacingOccurrences(of: split[0], with: " ")
        for gift in gifts { rest = rest.replacingOccurrences(of: gift[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgives?\b|\bgave\b"#, rest) else { return nil }
        var hold: [String: Fraction] = [:]
        for (name, size) in zip(names, [split[5], split[6], split[7]]) {
            guard let parts = Int(size), parts > 0 else { return nil }
            hold[name] = Fraction(parts)
        }
        func line(_ holding: [String: Fraction]) -> MathLine { MathLine(.symbol(names.map { "\($0) \(Format.text(holding[$0]!.expr))" }.joined(separator: ", ")), suffix: "parts") }
        var lead = [Step("Start with the ratio as parts", "", [line(hold)])]
        var gaveBefore = Set<String>()
        for gift in gifts {
            let (giver, receiver) = (gift[1], gift[6])
            guard names.contains(giver), names.contains(receiver), giver != receiver else { return nil }
            // After a first gift, "of her sweets" could mean what she had or what she has: it has to say "the rest".
            let ofRest = !gift[4].isEmpty || !gift[5].isEmpty
            guard ofRest == gaveBefore.contains(giver) else { return nil }
            let fraction: Fraction
            if let found = groups(#"^\(?(\d+)\)? ?/ ?\(?(\d+)\)?$"#, in: gift[3]), let top = Int(found[1]), let bottom = Int(found[2]), top > 0, bottom > top {
                fraction = Fraction(top, bottom)
            } else if let found = groups(#"^(\d+) (\d+) ?/ ?(\d+) ?%$"#, in: gift[3]), let whole = Int(found[1]), let top = Int(found[2]), let bottom = Int(found[3]), bottom > top, top > 0 {
                fraction = (Fraction(whole) + Fraction(top, bottom)) / Fraction(100)
            } else if let found = groups(#"^(\d+(?:\.\d+)?) ?%$"#, in: gift[3]), let percent = decimal(found[1]), percent.top > 0 {
                fraction = percent / Fraction(100)
            } else { return nil }
            guard fraction.top < fraction.bottom, let had = hold[giver], let other = hold[receiver] else { return nil }
            let given = had * fraction
            hold[giver] = had - given
            hold[receiver] = other + given
            gaveBefore.insert(giver)
            lead.append(Step("\(giver) gives \(gift[3].trimmingCharacters(in: .whitespaces)) of \(Format.text(had.expr)) parts to \(receiver)",
                             "\(Format.text(fraction.expr)) × \(Format.text(had.expr)) = \(Format.text(given.expr)) part\(given == Fraction(1) ? "" : "s").", [line(hold)]))
        }
        let same = names.allSatisfy { hold[$0] == hold[names[0]] }
        let answer = same ? "Yes: \(Format.text(hold[names[0]]!.expr)) parts each" : "No: " + names.map { "\($0) \(Format.text(hold[$0]!.expr))" }.joined(separator: ", ") + " parts"
        lead.append(Step("Compare", same ? "All three now have the same." : "They don't all have the same.", []))
        return told("is \(ask[1]) correct", [MathLine(.symbol(answer))], lead)
    }

    // MARK: Two collections put together

    /// "Sasha's collection: 1638 stamps in the ratio UK : EU : Other = 9 : 3 : 2. Taylor's
    /// collection: 660 stamps, 8 : 1 : 2. They claim that at least 2/3 of all the stamps come
    /// from the UK. Are they correct?" The table's cells come in any order, so each number goes
    /// with the ratio whose parts divide it; if both ways round would do, nothing is said.
    private static func pooledShare(_ text: String) -> Problem? {
        let label = #"(?-i:([A-Z][A-Za-z]*))"#
        guard let claim = groups("\\b(at least|more than|less than|at most) \\(?(\\d+)\\)? ?/ ?\\(?(\\d+)\\)? of all (?:of )?the ([a-z]+) (?:come from|are from|came from|are) (?:the )?\(label)(?![A-Za-z])", in: text),
              has(#"\b(?:are they|is (?-i:[A-Z][a-z]+)) (?:correct|right)\b"#, text),
              let top = Int(claim[2]), let bottom = Int(claim[3]), top > 0, bottom > top else { return nil }
        // The names of the parts, in the order the ratios give them.
        let headers = every("(?<![A-Za-z])\(label) ?: ?\(label) ?: ?\(label)(?![A-Za-z:])", in: text)
        guard let names = headers.first.map({ Array($0[1...3]) }), Set(names).count == 3, headers.allSatisfy({ Array($0[1...3]) == names }),
              let at = names.firstIndex(of: claim[5]) else { return nil }
        var rest = text.replacingOccurrences(of: claim[0], with: " ")
        let ratios = every(#"(?<![\d:.])(\d+) ?: ?(\d+) ?: ?(\d+)(?![\d:]|\.\d)"#, in: rest)
        for ratio in ratios { rest = rest.replacingOccurrences(of: ratio[0], with: " ") }
        let totals = every(#"(?<![\d.,/])(\d+)(?![\d.,/])"#, in: rest).compactMap { Int($0[1]) }
        guard ratios.count == 2, totals.count == 2, totals.allSatisfy({ $0 > 0 }) else { return nil }
        let parts = ratios.map { [$0[1], $0[2], $0[3]].compactMap { Int($0) } }
        guard parts.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0 > 0 } }) else { return nil }
        let sums = parts.map { $0.reduce(0, +) }
        // Whole numbers of them: only one way round can be right.
        let straight = totals[0] % sums[0] == 0 && totals[1] % sums[1] == 0, crossed = totals[0] % sums[1] == 0 && totals[1] % sums[0] == 0
        guard straight != crossed else { return nil }
        let paired = straight ? [(totals[0], 0), (totals[1], 1)] : [(totals[0], 1), (totals[1], 0)]
        var count = 0, lines: [MathLine] = []
        for (total, index) in paired {
            let here = total / sums[index] * parts[index][at]
            count += here
            lines.append(MathLine(.symbol("\(total) ÷ \(sums[index]) × \(parts[index][at])"), .integer(here)))
        }
        let whole = totals[0] + totals[1]
        // Compared in whole numbers: count/whole against top/bottom.
        let left = count * bottom, right = top * whole
        let words = claim[1].lowercased()
        let correct: Bool
        switch words {
        case "at least": correct = left >= right
        case "more than": correct = left > right
        case "less than": correct = left < right
        default: correct = left <= right
        }
        let line = Fraction(top * whole, bottom)
        let needed = line.bottom == 1 ? "\(line.top)" : text2(line.double)
        return told("is the claim correct", [MathLine(.symbol("\(correct ? "Yes" : "No"): \(count) of the \(whole) \(claim[4]) (\(top)/\(bottom) of \(whole) is \(needed))"))],
                    [Step("Find the \(claim[5]) \(claim[4]) in each collection", "Divide by the number of parts, then multiply by the \(claim[5]) part. (\(paired[0].0) goes with \(parts[paired[0].1].map(String.init).joined(separator: " : ")): its parts divide it exactly.)", lines),
                     Step("Add them, and add up all the \(claim[4])", "", [MathLine(.symbol("\(claim[5])"), .integer(count)), MathLine(.symbol("all"), .integer(whole))]),
                     Step("Compare with \(top)/\(bottom) of them all", "\(top)/\(bottom) of \(whole) is \(needed), and \(count) is \(count * bottom == top * whole ? "equal to that" : (left > right ? "more" : "less")).", [])])
    }

    // MARK: A drink mixed from cordial

    /// "A bottle contains 1 3/4 litres of cordial. To make orange squash, 1 part of this cordial
    /// is mixed with 7 parts of water. Cups that can hold 1/6 of a litre are completely filled
    /// with this orange squash. Work out the maximum number of cups that can be filled from the
    /// bottle of cordial."
    private static func dilutedCups(_ text: String) -> Problem? {
        let value = #"(\d+ \d+ ?/ ?\(?\d+\)?|\(?\d+\)? ?/ ?\(?\d+\)?|\d+(?:\.\d+)?)"#
        let volume = #"(litres?|l|ml|millilitres?)"#
        let cup = #"(cups|glasses|mugs|beakers|jugs|bottles)"#
        guard let have = groups("\\bcontains \(value) ?\(volume) of ([a-z]+)\\b", in: text),
              let mix = groups("\\b(\\d+) parts? of (?:this |the )?\(have[3]) (?:is|are) mixed with (\\d+) parts? of ([a-z]+)\\b", in: text),
              let holds = groups("\\b\(cup) that (?:can )?(?:each )?hold \(value) ?(?:of a )?\(volume)\\b", in: text),
              let ask = groups("\\b(?:maximum|greatest|largest) number of \(holds[1]) that can be (?:completely )?filled\\b", in: text) else { return nil }
        var rest = text
        for found in [have, mix, holds, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        func read(_ said: String) -> Fraction? {
            let plain = said.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            if let found = groups(#"^(\d+) (\d+) ?/ ?(\d+)$"#, in: plain), let whole = Int(found[1]), let top = Int(found[2]), let bottom = Int(found[3]), bottom > top, top > 0 { return Fraction(whole) + Fraction(top, bottom) }
            if let found = groups(#"^(\d+) ?/ ?(\d+)$"#, in: plain), let top = Int(found[1]), let bottom = Int(found[2]), bottom > 0, top > 0 { return Fraction(top, bottom) }
            return decimal(plain)
        }
        func litres(_ unit: String) -> Fraction { unit.lowercased().hasPrefix("l") ? Fraction(1) : Fraction(1, 1000) }
        guard let amount = read(have[1]), let each = read(holds[2]), let a = Int(mix[1]), let b = Int(mix[2]), a > 0, b > 0, amount.top > 0, each.top > 0 else { return nil }
        let cordial = amount * litres(have[2]), size = each * litres(holds[3])
        let drink = cordial * Fraction(a + b, a)
        let cups = drink / size
        let whole = cups.top / cups.bottom
        guard whole >= 1, whole < 100_000 else { return nil }
        let name = holds[1].lowercased()
        return told("maximum number of \(name)", [MathLine(.integer(whole))],
                    [Step("Find how much drink the \(have[3]) makes", "\(a) part\(a == 1 ? "" : "s") of \(have[3]) with \(b) of \(mix[3]) is \(a + b) parts, so the drink is \(Format.text(Fraction(a + b, a).expr)) times the \(have[3]).",
                          [MathLine(.symbol("\(Format.text(cordial.expr)) × \(Format.text(Fraction(a + b, a).expr))"), drink.expr, suffix: "litres")]),
                     Step("Divide by what one of the \(name) holds", cups.bottom == 1 ? "" : "Only full \(name) count, so round down.",
                          [MathLine(.symbol("\(Format.text(drink.expr)) ÷ \(Format.text(size.expr))"), cups.bottom == 1 ? .integer(whole) : cups.expr)])])
    }

    // MARK: A formula used twice

    /// "The number of hours, H, that some machines take to make 5000 bottles is given by
    /// H = 72/n where n is the number of machines. On Monday, 6 machines made 5000 bottles. On
    /// Tuesday, 9 machines made 5000 bottles. How much more time did they take on Monday?"
    private static func formulaGap(_ text: String) -> Problem? {
        guard let formula = groups(#"(?-i:(?<![A-Za-z])([A-Z])) ?= ?\(?(\d+(?:\.\d+)?)\)? ?/ ?\(?(?-i:([a-z]))\)?(?![A-Za-z0-9^])"#, in: text),
              let measured = groups("\\bthe number of (hours|minutes|days|seconds|weeks), (?-i:\(formula[1])),", in: text),
              let meaning = groups("\\b(?-i:\(formula[3])) is the number of ([a-z]+)\\b", in: text),
              has(#"\bhow much (?:more time|longer)\b|\bhow many more (?:hours|minutes|days|seconds|weeks)\b"#, text),
              let k = Double(formula[2]), k > 0 else { return nil }
        let thing = meaning[1]
        let days = every("\\bon (?-i:([A-Z][a-z]+)),? (\\d+) \(thing)\\b", in: text)
        guard days.count == 2, days[0][1] != days[1][1], let first = Double(days[0][2]), let second = Double(days[1][2]), first > 0, second > 0, first != second else { return nil }
        var rest = text
        for found in [formula, measured, meaning] + days { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        // What they make is the same amount each time: "5000 bottles", said for the formula and for each day.
        let made = every(#"\b(?:make|made|makes|produce|produced|fill|filled) (\d+) ([a-z]+)\b"#, in: rest)
        guard made.count == 3 || made.isEmpty, Set(made.map { $0[1] + " " + $0[2].lowercased() }).count <= 1 else { return nil }
        for item in made { rest = rest.replacingOccurrences(of: item[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let (a, b) = (k / first, k / second)
        guard isExact(a), isExact(b) else { return nil }
        let unit = measured[1].lowercased(), gap = abs(a - b)
        return told("how much more time", [MathLine(number(gap), suffix: gap == 1 ? singular(unit) : unit)],
                    [Step("Put each number of \(thing) into the formula", "\(formula[1]) = \(formula[2]) ÷ \(formula[3]).",
                          [MathLine(.symbol("\(days[0][1]): \(formula[2]) ÷ \(days[0][2])"), number(a), suffix: unit), MathLine(.symbol("\(days[1][1]): \(formula[2]) ÷ \(days[1][2])"), number(b), suffix: unit)]),
                     Step("Take one from the other", "", [MathLine(.symbol("\(text2(max(a, b))) − \(text2(min(a, b)))"), number(gap), suffix: gap == 1 ? singular(unit) : unit)])])
    }

    // MARK: The same thing on offer in several shops

    /// "Three shops sell the same lip balm stick. Shop A: £2.39 each. Shop B: £3.08 each, buy
    /// one, get one half price. Shop C: pack of 4, was £11.40, now 1/6 off. Which shop is the
    /// best value for 8 sticks and what is the total cost in that shop?" Each shop's offer has
    /// to come straight after its own name; offers read out of their boxes in another order
    /// can't be told apart, and nothing is said.
    private static func bestOffer(_ text: String) -> Problem? {
        guard let ask = groups(#"\bwhich (shop|store|supermarket) (?:is|gives|offers|has) (?:the )?(?:best value|better value|cheapest|cheaper) for (\d+) ([a-z]+(?: [a-z]+)?)\b"#, in: text),
              let wanted = Int(ask[2]), wanted > 0, wanted <= 1000, let asked = text.range(of: ask[0]) else { return nil }
        let before = String(text[..<asked.lowerBound]), after = String(text[asked.upperBound...])
        guard after.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Each shop's name, and what is written between it and the next.
        let labels = located("\\b\(ask[1]) (?-i:([A-Z]))\\b", in: before)
        guard (2...4).contains(labels.count), Set(labels.map { $0.groups[1] }).count == labels.count,
              (before as NSString).substring(to: labels[0].start).range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let length = (before as NSString).length
        var totals: [(name: String, cost: Double, working: String)] = []
        for (index, label) in labels.enumerated() {
            let end = index + 1 < labels.count ? labels[index + 1].start : length
            var offer = (before as NSString).substring(with: NSRange(location: label.end, length: end - label.end))
            func take(_ pattern: String) -> [String]? {
                guard let found = groups(pattern, in: offer) else { return nil }
                offer = offer.replacingOccurrences(of: found[0], with: " ")
                return found
            }
            let pack = take(#"\bpacks? of (\d+)\b"#).flatMap { Int($0[1]) }
            let half = take(#"\bbuy (?:one|1),? get (?:one|1) half price\b"#) != nil
            let free = take(#"\bbuy (?:one|1),? get (?:one|1) free\b"#) != nil
            let threeForTwo = take(#"\b(?:3|three) for (?:the price of )?(?:2|two)\b"#) != nil
            let was = take(#"\bwas £ ?(\d+(?:\.\d+)?)"#).flatMap { Double($0[1]) }
            var off: Fraction?
            if let found = take(#"\b(?:now )?\(?(\d+)\)? ?/ ?\(?(\d+)\)? off\b"#), let top = Int(found[1]), let bottom = Int(found[2]), top > 0, bottom > top { off = Fraction(top, bottom) }
            else if let found = take(#"\b(?:now )?(\d+(?:\.\d+)?) ?% off\b"#), let percent = decimal(found[1]), percent.top > 0, percent.double < 100 { off = percent / Fraction(100) }
            let each = take(#"(?:\bnow )?£ ?(\d+(?:\.\d+)?)(?: (?:each|per pack|a pack|per \w+))?"#).flatMap { Double($0[1]) }
            // Nothing else may be written there, and there is one price.
            guard offer.range(of: #"[A-Za-z0-9£%]"#, options: .regularExpression) == nil,
                  let price = was ?? each, (was == nil) != (each == nil), price > 0, was == nil || off != nil else { return nil }
            guard [half, free, threeForTwo].filter({ $0 }).count <= 1, pack == nil || !(half || free || threeForTwo) else { return nil }
            let name = "\(ask[1].capitalized) \(label.groups[1])"
            let reduced = off.map { price * (1 - $0.double) } ?? price
            let priced = off.map { "\(pounds(price)) × \(Format.text((Fraction(1) - $0).expr))" } ?? pounds(price)
            var cost: Double, working: String
            if let pack {
                guard pack > 0, wanted % pack == 0 else { return nil }
                cost = Double(wanted / pack) * reduced
                working = "\(wanted / pack) × \(priced)"
            } else if half || free {
                let pairs = wanted / 2, single = wanted % 2
                cost = Double(pairs) * reduced * (half ? 1.5 : 1) + Double(single) * reduced
                working = "\(pairs) × \(half ? "(\(priced) + \(pounds(reduced / 2)))" : priced)" + (single == 1 ? " + \(priced)" : "")
                guard pairs > 0 else { return nil }
            } else if threeForTwo {
                let threes = wanted / 3, single = wanted % 3
                guard threes > 0 else { return nil }
                cost = Double(threes * 2 + single) * reduced
                working = "\(threes * 2 + single) × \(priced)"
            } else {
                cost = Double(wanted) * reduced
                working = "\(wanted) × \(priced)"
            }
            // Whole pennies, or the shop's rounding isn't known.
            guard abs(cost * 100 - (cost * 100).rounded()) < 1e-6 else { return nil }
            totals.append((name, (cost * 100).rounded() / 100, working))
        }
        let sorted = totals.sorted { $0.cost < $1.cost }
        guard sorted[1].cost - sorted[0].cost > 0.005 else { return nil }
        func money(_ value: Double) -> String { String(format: "£%.2f", value) }
        return told("best value for \(wanted) \(ask[3])", [MathLine(.symbol("\(sorted[0].name), \(money(sorted[0].cost))"))],
                    [Step("Work out the cost of \(wanted) in each \(ask[1].lowercased())", "", totals.map { MathLine(.symbol("\($0.name): \($0.working)"), .symbol(money($0.cost))) }),
                     Step("Pick the cheapest", "\(sorted[0].name) costs the least.", [])])
    }

    // MARK: The earliest time to arrive

    /// "Ryan makes a journey of 200 miles. 1/10 of the journey is on roads with a speed limit of
    /// 40 miles per hour. 40% of the journey is on roads with a speed limit of 50 miles per
    /// hour. The remainder of the journey takes a time of 1 hour 30 minutes. Ryan leaves home at
    /// 08 50 and does not exceed the speed limits. Find the earliest time that Ryan could arrive."
    private static func earliestArrival(_ text: String) -> Problem? {
        let n = #"(\d+(?:\.\d+)?)"#
        guard let total = groups("\\bjourney of \(n) ?(miles|km|kilometres)\\b", in: text),
              let left = groups(#"\bthe (?:remainder|rest) of the journey takes (?:a time of )?(?:(\d+) hours?)?(?: ?(?:and )?(\d+) minutes?)?"#, in: text), !(left[1].isEmpty && left[2].isEmpty),
              let leave = groups(#"\bleaves (?:home |work |school )?at (\d{1,2})([ :.]?)(\d{2})(?: ?(am|pm))?(?![\d:.])"#, in: text),
              let ask = groups(#"\bearliest time\b[a-z ]*?\b(?:arrive|get|reach|be)\b"#, in: text),
              has(#"\bdoes not exceed the speed limits?\b|\bat the speed limits?\b"#, text),
              let whole = Double(total[1]), whole > 0 else { return nil }
        let stages = every("(?:\\(?(\\d+)\\)? ?/ ?\\(?(\\d+)\\)?|\(n) ?%) of the journey is on (?:a )?(?:roads?|motorways?) with a speed limit of \(n) ?(mph|miles per hour|km/h|kilometres per hour)", in: text)
        guard !stages.isEmpty, stages.count <= 4 else { return nil }
        var rest = text
        for found in [total, left, leave, ask] + stages { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let inMiles = total[2].lowercased().hasPrefix("m")
        var minutes = Double((Int(left[1]) ?? 0) * 60 + (Int(left[2]) ?? 0)), share = Fraction(0)
        var lines: [MathLine] = []
        for stage in stages {
            let part: Fraction
            if stage[3].isEmpty {
                guard let top = Int(stage[1]), let bottom = Int(stage[2]), top > 0, bottom > top else { return nil }
                part = Fraction(top, bottom)
            } else {
                guard let percent = decimal(stage[3]), percent.top > 0 else { return nil }
                part = percent / Fraction(100)
            }
            guard let limit = Double(stage[4]), limit > 0, stage[5].lowercased().hasPrefix("m") == inMiles else { return nil }
            let far = part.double * whole, taken = far / limit * 60
            // Whole minutes, or the time of arrival can't be given to the minute.
            guard abs(taken - taken.rounded()) < 1e-6 else { return nil }
            share = share + part
            minutes += taken.rounded()
            lines.append(MathLine(.symbol("\(text2(far)) ÷ \(text2(limit))"), .symbol("\(text2(far / limit)) hours = \(Int(taken.rounded())) minutes")))
        }
        // Some of the journey is left for "the remainder".
        guard share.top < share.bottom, let hour = Int(leave[1]), let minute = Int(leave[3]), minute < 60 else { return nil }
        let half = leave[4].lowercased()
        guard half.isEmpty ? hour <= 23 : (1...12).contains(hour) else { return nil }
        let start = (half.isEmpty ? hour : hour % 12 + (half == "pm" ? 12 : 0)) * 60 + minute
        let end = start + Int(minutes)
        guard end < 24 * 60 else { return nil }
        let (h, m) = (end / 60, end % 60)
        let shown = half.isEmpty ? String(format: "%02d\(leave[2].isEmpty ? "" : leave[2])%02d", h, m) : "\(h % 12 == 0 ? 12 : h % 12)\(leave[2])\(String(format: "%02d", m)) \(h < 12 ? "am" : "pm")"
        let long = Int(minutes)
        return told("the earliest time of arrival", [MathLine(.symbol(shown))],
                    [Step("Find the time for each part at its speed limit", "The earliest arrival is with every part driven at its limit. Time = distance ÷ speed.", lines),
                     Step("Add the time for the rest", "", [MathLine(.symbol("total"), .symbol("\(long / 60) hours \(long % 60) minutes"))]),
                     Step("Add it to the time of leaving", "", [MathLine(.symbol(shown))])])
    }

    // MARK: The largest sum of rounded numbers

    /// "Three whole numbers are each rounded to the nearest 10. The sum of the rounded numbers
    /// is 70. Work out the maximum possible sum for the original three numbers."
    private static func roundedSum(_ text: String) -> Problem? {
        let sizes = ["10": 10, "100": 100, "1000": 1000, "ten": 10, "hundred": 100, "thousand": 1000]
        guard let facts = groups(#"\b(two|three|four|five|six|\d) (?:whole numbers|integers|positive integers|positive whole numbers) are each rounded to the nearest (10|100|1000|ten|hundred|thousand)\b"#, in: text),
              let sum = groups(#"\bthe sum of the rounded numbers is (\d+)\b"#, in: text),
              let ask = groups(#"\b(?:maximum|largest|greatest|biggest) possible sum (?:for|of) the (?:original )?(?:(two|three|four|five|six|\d) )?(?:original )?numbers\b"#, in: text),
              let many = counted(facts[1]), many >= 2, let step = sizes[facts[2].lowercased()], let total = Int(sum[1]), total % step == 0,
              ask[1].isEmpty || counted(ask[1]) == many else { return nil }
        var rest = text
        for found in [facts, sum, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // A whole number can be up to one less than half the step above what it rounds to.
        let above = step / 2 - 1, most = total + many * above
        // (As words, not a number: "to the nearest 10" is about the numbers, not the answer.)
        return told("maximum possible sum", [MathLine(.symbol("\(most)"))],
                    [Step("Find how far above its rounded value a number can be", "A whole number rounds down to the nearest \(step) when it is up to \(above) more: \(step + above) rounds to \(step), \(step + above + 1) rounds to \(step * 2).", []),
                     Step("Add that on for each of the \(many) numbers", "", [MathLine(.symbol("\(total) + \(many) × \(above)"), .integer(most))])])
    }

    // MARK: A ratio, and a ratio inside each part

    /// "The ratio of the number of white shapes to the number of black shapes is 3 : 7. The
    /// ratio of the number of white circles to the number of white squares is 4 : 5. The ratio
    /// of the number of black circles to the number of black squares is 2 : 5. Work out what
    /// fraction of all the shapes are circles."
    private static func nestedRatios(_ text: String) -> Problem? {
        let ratios = every(#"\bthe ratio of the number of ([a-z]+) ([a-z]+) to the number of ([a-z]+) ([a-z]+) is (\d+) ?: ?(\d+)(?![\d:]|\.\d)"#, in: text).map { $0.map { $0.lowercased() } }
        guard ratios.count == 3 else { return nil }
        // One ratio splits them all two ways (white shapes, black shapes); the other two split each of those.
        let outer = ratios.filter { $0[2] == $0[4] && $0[1] != $0[3] }, inner = ratios.filter { $0[1] == $0[3] && $0[2] != $0[4] }
        guard outer.count == 1, inner.count == 2, let top = outer.first else { return nil }
        let thing = top[2], groupsOf = [top[1], top[3]]
        guard let ask = groups("\\bwhat (fraction|percentage) of (?:all )?(?:of )?the \(thing) are ([a-z]+)\\b", in: text),
              Set(inner.map { $0[1] }) == Set(groupsOf), Set([inner[0][2], inner[0][4]]) == Set([inner[1][2], inner[1][4]]) else { return nil }
        let wanted = ask[2].lowercased()
        guard [inner[0][2], inner[0][4]].contains(wanted) else { return nil }
        var rest = text.replacingOccurrences(of: ask[0], with: " ")
        for ratio in every(#"\bthe ratio of the number of ([a-z]+) ([a-z]+) to the number of ([a-z]+) ([a-z]+) is (\d+) ?: ?(\d+)(?![\d:]|\.\d)"#, in: text) { rest = rest.replacingOccurrences(of: ratio[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, let a = Int(top[5]), let b = Int(top[6]), a > 0, b > 0 else { return nil }
        var share = Fraction(0), lines: [MathLine] = []
        for (name, size) in [(top[1], a), (top[3], b)] {
            guard let split = inner.first(where: { $0[1] == name }), let p = Int(split[5]), let q = Int(split[6]), p > 0, q > 0 else { return nil }
            let part = Fraction(size, a + b), within = Fraction(split[2] == wanted ? p : q, p + q)
            share = share + part * within
            lines.append(MathLine(.symbol("\(name) \(wanted): \(Format.text(part.expr)) × \(Format.text(within.expr))"), (part * within).expr))
        }
        let percent = ask[1].lowercased() == "percentage"
        if percent { guard isExact(share.double * 100) else { return nil } }
        let answer = percent ? MathLine(.symbol(text2(share.double * 100) + "%")) : MathLine(share.expr)
        return told("\(ask[1].lowercased()) of the \(thing) that are \(wanted)", [answer],
                    [Step("Write each kind of \(wanted) as a fraction of all the \(thing)", "The fraction of the \(thing) that are \(top[1]) or \(top[3]), times the fraction of those that are \(wanted).", lines),
                     Step("Add them", "", [MathLine(.symbol(lines.map { Format.text($0.parts[1]) }.joined(separator: " + ")), share.expr)] + (percent ? [answer] : []))])
    }

    // MARK: Money shared between several people

    /// "£360 is shared between Abby, Ben, Chloe and Denesh. The ratio of the amount Abby gets to
    /// the amount Ben gets is 2 : 7. Chloe and Denesh each get 1.5 times the amount Abby gets.
    /// Work out the amount of money that Ben gets."
    private static func sharedByFacts(_ text: String) -> Problem? {
        let person = #"(?-i:([A-Z][a-z]+))"#
        guard let start = groups("£ ?(\\d+(?:\\.\\d+)?) is (?:shared|divided|split) (?:between|among|by) \(person), \(person)(?:, \(person))? and \(person)\\b", in: text),
              let total = Double(start[1]), total > 0,
              let ask = groups("\\b(?:work out|find|calculate) (?:the amount(?: of money)?|how much(?: money)?) (?:that )?\(person) gets\\b", in: text) ?? groups("\\bhow much(?: money)? does \(person) get\\b", in: text) else { return nil }
        let names = [start[2], start[3], start[4], start[5]].filter { !$0.isEmpty }
        guard Set(names).count == names.count, names.contains(ask[1]) else { return nil }
        var rest = text.replacingOccurrences(of: start[0], with: " ").replacingOccurrences(of: ask[0], with: " ")
        var size: [String: Fraction] = [:]
        guard let ratio = groups("\\bthe ratio of the amount \(person) gets to the amount \(person) gets is (\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: rest),
              let p = Int(ratio[3]), let q = Int(ratio[4]), p > 0, q > 0, ratio[1] != ratio[2], names.contains(ratio[1]), names.contains(ratio[2]) else { return nil }
        size[ratio[1]] = Fraction(p); size[ratio[2]] = Fraction(q)
        rest = rest.replacingOccurrences(of: ratio[0], with: " ")
        var said: [String] = []
        let times = "(\\d+(?:\\.\\d+)?|[a-z]+) times|twice|half|double|\(spokenFraction) of"
        for found in every("\\b\(person)(?: and \(person))? (?:each )?gets? (\(times)) the amount \(person) gets\\b", in: rest) {
            let base = found[found.count - 1]
            let words = found[3].replacingOccurrences(of: #" of$"#, with: "", options: .regularExpression)
            guard let k = groups(#"^(\d+(?:\.\d+)?) times$"#, in: words).flatMap({ decimal($0[1]) }) ?? multiple(words), k.top > 0, let known = size[base] else { return nil }
            for name in [found[1], found[2]] where !name.isEmpty {
                guard names.contains(name), size[name] == nil else { return nil }
                size[name] = known * k
            }
            said.append(found[0])
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard names.allSatisfy({ size[$0] != nil }), rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let sum = names.reduce(Fraction(0)) { $0 + size[$1]! }
        let one = total / sum.double, answer = one * size[ask[1]]!.double
        guard abs(answer * 100 - (answer * 100).rounded()) < 1e-6 else { return nil }
        return told("how much \(ask[1]) gets", [MathLine(.symbol(pounds(answer)))],
                    [Step("Write everyone's share as parts", ([ratio[0]] + said).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ". ") + ".",
                          [MathLine(.symbol(names.map { "\($0) \(Format.text(size[$0]!.expr))" }.joined(separator: ", ")), suffix: "parts")]),
                     Step("Find one part", "\(Format.text(sum.expr)) parts altogether.", [MathLine(.symbol("\(pounds(total)) ÷ \(Format.text(sum.expr))"), .symbol(pounds(one)))]),
                     Step("Multiply by \(ask[1])'s parts", "", [MathLine(.symbol("\(Format.text(size[ask[1]]!.expr)) × \(pounds(one))"), .symbol(pounds(answer)))])])
    }

    // MARK: The mark needed on the last paper

    /// "Paper 1 is marked out of 60. Paper 2 is marked out of 40. Paper 3 is marked out of 100.
    /// A student scored 65% on Paper 1 and 70% on Paper 2. Find the mark they need to get on
    /// Paper 3 to achieve 64% of the total marks."
    private static func markNeeded(_ text: String) -> Problem? {
        let papers = every(#"\bpaper (\d) is marked out of (\d+)\b"#, in: text)
        let scores = every(#"(\d+(?:\.\d+)?) ?% on paper (\d)\b"#, in: text)
        guard papers.count >= 2, papers.count <= 4, scores.count == papers.count - 1, has(#"\bscored\b|\bgot\b|\bgets\b|\bscores\b"#, text),
              let ask = groups(#"\bthe mark (?:they|he|she|the student) needs? (?:to get |to score )?on paper (\d) to (?:achieve|get|score|gain) (\d+(?:\.\d+)?) ?% of the total marks?\b"#, in: text) ?? groups(#"\bthe mark (?:they|he|she|the student) needs? (?:to get |to score )?on paper (\d) to (?:achieve|get|score|gain) (\d+(?:\.\d+)?) ?% overall\b"#, in: text),
              let aim = Double(ask[2]), aim > 0, aim <= 100 else { return nil }
        var out: [String: Double] = [:]
        for paper in papers { guard out[paper[1]] == nil, let most = Double(paper[2]), most > 0 else { return nil }; out[paper[1]] = most }
        let whole = out.values.reduce(0, +)
        var rest = text.replacingOccurrences(of: ask[0], with: " ")
        for found in papers + scores { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        // "…to form the total mark out of 200": it has to be the sum.
        if let stated = groups(#"\btotal mark out of (\d+)\b"#, in: rest) {
            guard Double(stated[1]) == whole else { return nil }
            rest = rest.replacingOccurrences(of: stated[0], with: " ")
        }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, let last = out[ask[1]] else { return nil }
        var got = 0.0, lines: [MathLine] = []
        for score in scores {
            guard let percent = Double(score[1]), percent >= 0, percent <= 100, score[2] != ask[1], let most = out[score[2]] else { return nil }
            let marks = percent / 100 * most
            got += marks
            lines.append(MathLine(.symbol("Paper \(score[2]): \(text2(percent))% of \(text2(most))"), number(marks)))
        }
        guard Set(scores.map { $0[2] }).count == scores.count else { return nil }
        let target = aim / 100 * whole, needed = target - got
        // A whole number of marks that the paper can give.
        guard abs(needed - needed.rounded()) < 1e-6, needed >= 0, needed <= last + 1e-9 else { return nil }
        return told("the mark needed on Paper \(ask[1])", [MathLine(.integer(Int(needed.rounded())))],
                    [Step("Find the marks already scored", "", lines),
                     Step("Find the marks needed altogether", "\(text2(aim))% of the total, \(text2(whole)).", [MathLine(.symbol("\(text2(aim))% of \(text2(whole))"), number(target))]),
                     Step("Take away the marks already scored", "", [MathLine(.symbol(([text2(target)] + lines.map { Format.text($0.parts[1]) }).joined(separator: " − ")), .integer(Int(needed.rounded())))])])
    }

    // MARK: Adding to both parts of a ratio

    /// "A bag contains 35 balls. Each ball is either red or green. The ratio of red balls to
    /// green balls is 3 : 2. Work out the smallest number of balls of each colour that have to
    /// be added to the bag so that the ratio of red balls to green balls becomes 7 : 3."
    private static func addedToRatio(_ text: String) -> Problem? {
        guard let start = groups(#"\bcontains (\d+) ([a-z]+)\b"#, in: text), let total = Int(start[1]), total > 0 else { return nil }
        let thing = start[2]
        guard let now = groups("\\bthe ratio of ([a-z]+) \(thing) to ([a-z]+) \(thing) is (\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text),
              let ask = groups("\\bsmallest number of \(thing) of each (?:colour|kind|type|sort) that (?:have to|must|need to|needs to|has to) be added\\b[a-z ]*?\\bso that the ratio of \(now[1]) \(thing) to \(now[2]) \(thing) (?:becomes|is|will be|changes to) (\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text),
              let p = Int(now[3]), let q = Int(now[4]), let r = Int(ask[1]), let s = Int(ask[2]), p > 0, q > 0, r > 0, s > 0, now[1].lowercased() != now[2].lowercased() else { return nil }
        var rest = text
        for found in [start, now, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, total % (p + q) == 0 else { return nil }
        let first = total / (p + q) * p, second = total / (p + q) * q
        // The new ratio's parts in whole numbers, with at least as many of each as there are now.
        let (rr, ss) = (r / gcd(r, s), s / gcd(r, s))
        let k = max((first + rr - 1) / rr, (second + ss - 1) / ss)
        let (addFirst, addSecond) = (k * rr - first, k * ss - second)
        // Something has to be added.
        guard addFirst + addSecond > 0 else { return nil }
        return told("the smallest number of each to add", [MathLine(.symbol("\(addFirst) \(now[1].lowercased()), \(addSecond) \(now[2].lowercased())"))],
                    [Step("Find how many of each there are now", "\(p + q) parts, so one part is \(total / (p + q)).", [MathLine(.symbol(now[1].lowercased()), .integer(first)), MathLine(.symbol(now[2].lowercased()), .integer(second))]),
                     Step("Find the smallest numbers in the ratio \(rr) : \(ss) that are no fewer", "\(k) lots of \(rr) : \(ss), since \(k - 1) lots would be too few.", [MathLine(parts: [.integer(k * rr), .integer(k * ss)], relation: ":")]),
                     Step("Take away what is there already", "", [MathLine(.symbol("\(k * rr) − \(first)"), .integer(addFirst)), MathLine(.symbol("\(k * ss) − \(second)"), .integer(addSecond))])])
    }

    // MARK: A ratio before and after one part changes

    /// "The ratio of Sundip's money to Emma's money is 3 : 5. Emma spends £450 of her money. The
    /// ratio of Sundip's money to Emma's money is now 2 : 3. Find how much money Sundip has."
    /// Also "the ratio of red counters to yellow counters is 3 : 4. If 3 of the red counters are
    /// removed, the ratio is 3 : 5. How many yellow counters are there?" Only the part that
    /// didn't change is answered: the other has two sizes, and which is meant isn't said.
    private static func ratioOneChanges(_ text: String) -> Problem? {
        let person = #"(?-i:([A-Z][a-z]+))"#
        var first: String, second: String, before: [String], after: [String], changed: String, delta: Double, money: Bool, said: [String]
        if let b = groups("\\bthe ratio of \(person)'s money to \(person)'s money is (\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text),
           let a = groups("\\bthe ratio of \(b[1])'s money to \(b[2])'s money is now (\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text),
           let change = groups("\\b(\(b[1])|\(b[2])) (spends|gives away|loses|is given|gets|receives|earns|saves) (?:another |a further |an extra )?£ ?(\\d+(?:\\.\\d+)?)", in: text), let amount = Double(change[3]) {
            (first, second, before, after, changed, money) = (b[1], b[2], [b[3], b[4]], [a[1], a[2]], change[1], true)
            delta = ["spends", "gives away", "loses"].contains(change[2].lowercased()) ? -amount : amount
            said = [b[0], a[0], change[0]]
        } else if let b = groups(#"\bthe ratio of ([a-z]+) ([a-z]+) to ([a-z]+) \2 is (\d+) ?: ?(\d+)(?![\d:]|\.\d)"#, in: text),
                  let change = groups("\\b(\\d+) (?:of the |more |extra )?(\(b[1])|\(b[3])) \(b[2]) (?:are|is) (removed|taken out|taken away|added)\\b[a-z ]*?,? (?:then )?the ratio of \(b[1]) \(b[2]) to \(b[3]) \(b[2]) (?:is|becomes|is now) (\\d+) ?: ?(\\d+)(?![\\d:]|\\.\\d)", in: text),
                  let amount = Double(change[1]) {
            (first, second, before, after, changed, money) = (b[1].lowercased(), b[3].lowercased(), [b[4], b[5]], [change[4], change[5]], change[2].lowercased(), false)
            delta = change[3].lowercased() == "added" ? amount : -amount
            said = [b[0], change[0]]
        } else { return nil }
        guard first != second, let a = Int(before[0]), let b = Int(before[1]), let p = Int(after[0]), let q = Int(after[1]), a > 0, b > 0, p > 0, q > 0 else { return nil }
        var rest = text
        for item in said { rest = rest.replacingOccurrences(of: item, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        // Which is asked for: only the one that stayed the same.
        let still = changed == first ? second : first
        let asked = money ? has("\\bhow much (?:money )?(?:does |did )?\(still) (?:has|have|had)\\b", rest) : has("\\bhow many \(still) [a-z]+ (?:are|were) (?:there|in)\\b", rest)
        guard asked else { return nil }
        // a k and b k at first; the changed one moves by delta, and the ratio becomes p : q.
        let k: Double = changed == second ? Double(p) * delta / Double(q * a - p * b) : Double(q) * delta / Double(p * b - q * a)
        guard k.isFinite, k > 0 else { return nil }
        let one = k, answer = one * Double(changed == first ? b : a), other = one * Double(changed == first ? a : b)
        guard other + delta > 0, abs(answer * 100 - (answer * 100).rounded()) < 1e-6, money || abs(answer - answer.rounded()) < 1e-6 && abs(other - other.rounded()) < 1e-6 else { return nil }
        func shown(_ v: Double) -> String { money ? pounds(v) : text2(v) }
        let x = Expr.symbol("x")
        let changedParts = changed == first ? a : b
        return told(money ? "how much \(still) has" : "how many \(still)", [MathLine(.symbol(shown(answer)))],
                    [Step("Call one part of the first ratio x", "\(first) \(a)x and \(second) \(b)x. After the change \(changed) is \(changedParts)x \(delta < 0 ? "−" : "+") \(text2(abs(delta))).", []),
                     Step("Use the new ratio", "\(first) : \(second) is now \(p) : \(q), so \(q) × \(first) = \(p) × \(second).", [MathLine(x, number(one))]),
                     Step("Multiply by \(still)'s parts", "", [MathLine(.symbol("\(changed == first ? b : a) × \(text2(one))"), .symbol(shown(answer)))])])
    }

    // MARK: The rate of simple interest

    /// "Gustavo invests £520 for 6 years in a bank account paying simple interest. At the end of
    /// 6 years, the amount in the bank account is £629.20. Calculate the annual rate of interest."
    private static func simpleInterestRate(_ text: String) -> Problem? {
        guard let start = groups(#"\binvests £ ?(\d+(?:\.\d+)?) for (\d+) years in (?:a|an) [a-z ]*?account paying simple interest\b"#, in: text),
              let end = groups(#"\bat the end of (\d+) years,? the amount in the [a-z ]*?account is £ ?(\d+(?:\.\d+)?)"#, in: text),
              let ask = groups(#"\b(?:calculate|work out|find) the (?:annual |yearly )?(?:rate of (?:simple )?interest|interest rate)\b"#, in: text),
              let p = Double(start[1]), let years = Int(start[2]), Int(end[1]) == years, years >= 1, let amount = Double(end[2]), amount > p, p > 0 else { return nil }
        var rest = text
        for found in [start, end, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        let rounding = roundingAsked(rest)
        if let rounding { rest = rest.replacingOccurrences(of: rounding.said, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgive your answers?\b"#, rest) else { return nil }
        let interest = amount - p, yearly = interest / Double(years), rate = yearly / p * 100
        guard let shown = roundedAnswer(rate, rounding) else { return nil }
        return told("the annual rate of interest", [MathLine(.symbol(Format.text(shown.expr) + "%"))],
                    [Step("Find the interest", "", [MathLine(.symbol("\(pounds(amount)) − \(pounds(p))"), .symbol(pounds(interest)))]),
                     Step("Find the interest for one year", "Simple interest is the same each year.", [MathLine(.symbol("\(pounds(interest)) ÷ \(years)"), .symbol(pounds(yearly)))]),
                     Step("Write it as a percentage of \(pounds(p))", "", [MathLine(.symbol("\(pounds(yearly)) ÷ \(pounds(p)) × 100"), .symbol(Format.text(shown.expr) + "%"), relation: shown.exact ? "=" : "≈")])])
    }

    // MARK: Pay after a rise or a cut

    /// "Jamie was paid £14.00 per hour. Jamie receives a pay increase of 20%. Work out how much
    /// Jamie is now paid per hour."
    private static func payChange(_ text: String) -> Problem? {
        let period = #"(hour|day|week|month|year)"#
        guard let was = groups("\\b(?:was|is) paid £ ?(\\d+(?:\\.\\d+)?) (?:per|an|a|each) \(period)\\b", in: text),
              let change = groups(#"\b(?:receives|received|gets|got|is given|was given|has) a pay (increase|rise|decrease|cut|reduction) of (\d+(?:\.\d+)?) ?%"#, in: text),
              let ask = groups("\\bhow much (?:(?-i:[A-Z][a-z]+)|he|she|they) (?:is|are) now paid (?:per|an|a|each) \(was[2])\\b", in: text),
              let pay = Double(was[1]), let percent = Double(change[2]), pay > 0, percent > 0 else { return nil }
        var rest = text
        for found in [was, change, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let up = ["increase", "rise"].contains(change[1].lowercased())
        guard up || percent < 100 else { return nil }
        let multiplier = up ? 1 + percent / 100 : 1 - percent / 100, now = pay * multiplier
        // To the penny, or it isn't an amount of pay.
        guard abs(now * 100 - (now * 100).rounded()) < 1e-6 else { return nil }
        func money(_ v: Double) -> String { String(format: "£%.2f", v) }
        return told("the pay now", [MathLine(.symbol(money(now)))],
                    [Step("Find the multiplier", "100% \(up ? "+" : "−") \(text2(percent))% = \(text2(multiplier * 100))%.", [MathLine(.symbol("multiplier"), number(multiplier))]),
                     Step("Multiply the pay by it", "", [MathLine(.symbol("\(money(pay)) × \(text2(multiplier))"), .symbol(money(now)))])])
    }

    // MARK: Simple interest to match compound interest

    /// "Kay invests £1500 in an account paying 3% compound interest per year. Neil invests £1500
    /// in an account paying r% simple interest per year. At the end of the 5th year, both
    /// accounts contain the same amount of money. Calculate r. Give your answer correct to 1
    /// decimal place."
    private static func simpleMatchesCompound(_ text: String) -> Problem? {
        let yearly = #"(?:per year|per annum|a year|each year)"#
        guard let compound = groups("\\binvests £ ?(\\d+(?:\\.\\d+)?) in an account paying (\\d+(?:\\.\\d+)?) ?% compound interest \(yearly)", in: text),
              let simple = groups("\\binvests £ ?(\\d+(?:\\.\\d+)?) in an account paying (?-i:([a-z])) ?% simple interest \(yearly)", in: text),
              let time = groups(#"\bat the end of (?:the )?(\d+)(?:st|nd|rd|th) year\b|\bafter (\d+) years\b|\bat the end of (\d+) years\b"#, in: text),
              has(#"\b(?:both )?(?:contain|have|hold) the same amount\b|\bthe same amount of money\b"#, text),
              let ask = groups("\\b(?:calculate|work out|find)(?: the value of)? (?-i:\(simple[2]))(?![A-Za-z])", in: text),
              let p = Double(compound[1]), let c = Double(compound[2]), let q = Double(simple[1]), let years = Int(time[1] + time[2] + time[3]),
              p > 0, q > 0, c > 0, c < 100, years >= 1, years <= 50 else { return nil }
        var rest = text
        for found in [compound, simple, time, ask] { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        let rounding = roundingAsked(rest)
        if let rounding { rest = rest.replacingOccurrences(of: rounding.said, with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil, !has(#"\bgive your answers?\b"#, rest) else { return nil }
        let worth = p * pow(1 + c / 100, Double(years)), interest = worth - q
        let rate = interest / Double(years) / q * 100
        guard rate > 0, let shown = roundedAnswer(rate, rounding) else { return nil }
        let letter = simple[2]
        return told("the value of \(letter)", [MathLine(.symbol(letter), .symbol(Format.text(shown.expr)))],
                    [Step("Find what the compound interest account holds after \(years) years", "Multiply by \(text2(1 + c / 100)) for each year.", [MathLine(.symbol("\(pounds(p)) × \(text2(1 + c / 100))^\(years)"), .symbol(String(format: "£%.2f", worth)), relation: "≈")]),
                     Step("Find the simple interest that gives the same", "\(String(format: "£%.2f", worth)) − \(pounds(q)) over \(years) years.", [MathLine(.symbol("\(String(format: "£%.2f", interest)) ÷ \(years)"), .symbol(String(format: "£%.2f", interest / Double(years))), relation: "≈", suffix: "a year")]),
                     Step("Write it as a percentage of \(pounds(q))", "", [MathLine(.symbol(letter), .symbol(Format.text(shown.expr)), relation: shown.exact ? "=" : "≈")])])
    }

    // MARK: What was invested, worked back through withdrawals

    /// "At the start of 2022 Kim invested some money. The account paid 3.5% compound interest
    /// each year. At the end of 2022 interest was added to the account then Kim took £750 from
    /// the account. At the end of 2023 interest was added then Kim took £1000. There was then
    /// £2937.14 in the account. Work out how much money Kim invested at the start of 2022."
    private static func beforeWithdrawals(_ text: String) -> Problem? {
        guard let start = groups(#"\bat the start of (\d{4}),? (?-i:([A-Z][a-z]+)) invested some money\b"#, in: text),
              let rate = groups(#"\b(?:paid|pays) (\d+(?:\.\d+)?) ?% compound interest (?:each|per|every|a) year\b"#, in: text),
              let end = groups(#"\bthere was then £ ?(\d+(?:\.\d+)?) in the account\b"#, in: text),
              let ask = groups("\\bhow much(?: money)? \(start[2]) invested at the start of \(start[1])\\b", in: text),
              let year = Int(start[1]), let r = Double(rate[1]), r > 0, r < 100, let final = Double(end[1]) else { return nil }
        let taken = every("\\bat the end of (\\d{4}),? interest was added to the account,? (?:and )?then \(start[2]) took £ ?(\\d+(?:\\.\\d+)?) (?:from|out of) the account\\b", in: text)
        guard !taken.isEmpty, taken.count <= 5 else { return nil }
        // A withdrawal at the end of each year, one after another from the year it started.
        for (index, item) in taken.enumerated() { guard Int(item[1]) == year + index else { return nil } }
        var rest = text
        for found in [start, rate, end, ask] + taken { rest = rest.replacingOccurrences(of: found[0], with: " ") }
        guard rest.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }
        let multiplier = 1 + r / 100
        var amount = final, lines: [MathLine] = []
        for item in taken.reversed() {
            guard let out = Double(item[2]), out > 0 else { return nil }
            let before = (amount + out) / multiplier
            lines.append(MathLine(.symbol("Start of \(item[1]): (\(String(format: "£%.2f", amount)) + \(pounds(out))) ÷ \(text2(multiplier))"), .symbol(String(format: "£%.2f", before))))
            amount = before
        }
        // It comes back to a whole number of pence, or something was misread.
        guard abs(amount * 100 - (amount * 100).rounded()) < 0.05 else { return nil }
        return told("how much \(start[2]) invested", [MathLine(.symbol(pounds(amount)))],
                    [Step("Work back a year at a time", "Add back what was taken out, then divide by \(text2(multiplier)) to undo the interest.", lines),
                     Step("That is the amount at the start of \(start[1])", "", [MathLine(.symbol(pounds(amount)))])])
    }

    // MARK: Pieces

    /// "Give your answer correct to 3 significant figures", "to 1 decimal place": what was said, and how to round.
    private static func roundingAsked(_ text: String) -> (said: String, figures: Int, decimal: Bool)? {
        guard let found = groups(#"\bgive your answer (?:correct )?to (\d|one|two|three|four) (decimal places?|significant figures?|d\.?p\.?|s\.?f\.?)\.?"#, in: text),
              let count = counted(found[1]), (1...6).contains(count) else { return nil }
        return (found[0], count, found[2].lowercased().hasPrefix("d"))
    }

    /// A value as it should be shown: exact when it is, rounded as the question asks when it
    /// asks, otherwise to 3 significant figures.
    private static func roundedAnswer(_ value: Double, _ rounding: (said: String, figures: Int, decimal: Bool)?) -> (expr: Expr, exact: Bool)? {
        guard value.isFinite, value > 0 else { return nil }
        if rounding == nil, isExact(value) { return (number(value), true) }
        let places: Int
        if let rounding, rounding.decimal { places = rounding.figures } else {
            places = (rounding?.figures ?? 3) - 1 - Int(floor(log10(value)))
        }
        let scale = pow(10, Double(places)), rounded = (value * scale).rounded() / scale
        // On the edge of rounding either way: too close to call.
        guard abs(abs(value * scale - (value * scale).rounded(.down)) - 0.5) > 1e-6 else { return nil }
        let written = places > 0 ? String(format: "%.\(places)f", rounded) : String(Int(rounded))
        return (.symbol(written), abs(rounded - value) < 1e-9)
    }

    /// True of a value with no more than 4 decimal places.
    private static func isExact(_ value: Double) -> Bool { abs(value * 10000 - (value * 10000).rounded()) < 1e-6 }

    private struct Fraction: Equatable {
        var top: Int, bottom: Int
        init(_ top: Int, _ bottom: Int = 1) {
            let sign = bottom < 0 ? -1 : 1, common = max(WordedNumber.gcd(abs(top), abs(bottom)), 1)
            self.top = sign * top / common
            self.bottom = sign * bottom / common
        }
        static func / (a: Fraction, b: Fraction) -> Fraction { Fraction(a.top * b.bottom, a.bottom * b.top) }
        static func * (a: Fraction, b: Fraction) -> Fraction { Fraction(a.top * b.top, a.bottom * b.bottom) }
        static func + (a: Fraction, b: Fraction) -> Fraction { Fraction(a.top * b.bottom + b.top * a.bottom, a.bottom * b.bottom) }
        static func - (a: Fraction, b: Fraction) -> Fraction { Fraction(a.top * b.bottom - b.top * a.bottom, a.bottom * b.bottom) }
        var double: Double { Double(top) / Double(bottom) }
        var expr: Expr { bottom == 1 ? .integer(top) : .fraction(top, bottom) }
    }

    private static func decimal(_ text: String) -> Fraction? {
        guard let found = groups(#"^(\d+)(?:\.(\d{1,6}))?$"#, in: text), let whole = Int(found[1]) else { return nil }
        let places = found[2].count, scale = Int(pow(10, Double(places)))
        return Fraction(whole * scale + (Int(found[2]) ?? 0), scale)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
    private static func lcm(_ a: Int, _ b: Int) -> Int { a / max(gcd(a, b), 1) * b }

    private static func singular(_ word: String) -> String {
        let word = word.lowercased()
        if word.range(of: #"(?:ch|sh|x|ss)es$"#, options: .regularExpression) != nil { return String(word.dropLast(2)) }
        return word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : word
    }

    /// A number as maths: whole where it is, otherwise to 4 decimal places.
    private static func number(_ value: Double) -> Expr { CircleDiagram.number(value) }
    /// Money and the like: to 2 decimal places.
    private static func number2(_ value: Double) -> Expr {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? .integer(Int(rounded)) : .number(.real(rounded))
    }
    private static func text2(_ value: Double) -> String { Format.text(number(value)) }

    private static func told(_ question: String, _ answers: [MathLine], _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .worded(question: question, answers: answers), text: "", usesDecimals: false)
        problem.lead = lead
        return problem
    }

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? { every(pattern, in: text).first }

    private static func every(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}

private extension MathLine {
    /// "2.5 ≤ ∛k < 3.5": the second relation differs from the first.
    func replacingSecond(_ relation: String) -> MathLine {
        guard parts.count == 3 else { return self }
        var line = MathLine(parts[0], .symbol("\(Format.text(parts[1])) \(relation) \(Format.text(parts[2]))"), relation: self.relation)
        line.suffix = suffix
        return line
    }
}
