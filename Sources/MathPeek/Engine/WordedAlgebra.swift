import Foundation

/// Algebra asked in words: an equation made from a description and solved, two unknowns from two facts, whole-number answers to inequalities, sequences, iteration, expressions to match or choose between,
/// a formula or a proportion used with the values given, a statement to pick out as always true.
/// Tried after `Worded.problem`, on the same text: the lines of the question the pointer is
/// in, joined by line breaks. Nil unless the whole of the question is understood.
enum WordedAlgebra {
    static func problem(_ input: String) -> Problem? {
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Where the area holds more than one part ("6 (a) …", "Answer", "6 (b) …"), each part
        // is a question of its own, with the lines above the first part shared by all of them.
        // Only one of them may give an answer: words from one part never go with the numbers of another.
        let rows = display.split(whereSeparator: \.isNewline).map(String.init)
        var parts: [(lines: [String], closed: Bool)] = [([], false)]
        for row in rows {
            let plain = row.trimmingCharacters(in: .whitespaces)
            if has(#"^\d{0,2} ?\([a-z]\)(?! ?=)"#, plain) {
                parts.append(([row], false))
            } else if has(#"^answer(?:\b|_)"#, plain) {
                parts[parts.count - 1].closed = true
                parts.append(([], false))
            } else {
                parts[parts.count - 1].lines.append(row)
            }
        }
        parts = parts.filter { !$0.lines.isEmpty || $0.closed }
        guard parts.filter({ !$0.lines.isEmpty }).count > 1 else { return solve(display) }
        let shared = parts[0].closed || !(parts.count > 1 && has(#"^\d{0,2} ?\([a-z]\)(?! ?=)"#, parts[1].lines.first?.trimmingCharacters(in: .whitespaces) ?? "")) ? [] : parts[0].lines
        let questions = (shared.isEmpty ? parts : Array(parts.dropFirst())).filter { !$0.lines.isEmpty }.map { (shared + $0.lines).joined(separator: "\n") }
        let answered = questions.compactMap { solve($0) }
        guard answered.count == 1, var problem = answered.first else { return nil }
        problem.text = display
        return problem
    }

    private static func solve(_ display: String) -> Problem? {
        let lines = cleaned(display)
        guard !lines.isEmpty else { return nil }
        let text = lines.joined(separator: " ")
        guard text.count <= 700, !has(refusal, text) else { return nil }
        let kinds: [() -> Problem?] = [
            { triangular(text) }, { fibonacci(lines, text) }, { geometric(lines, text) }, { addedSequences(lines, text) },
            { ratio(lines, text) }, { valueGiven(lines, text) }, { chosenSubject(lines, text) }, { inequality(lines, text) },
            { simultaneousInTermsOf(lines, text) }, { describedChoice(lines, text) }, { termsWith(lines, text, display) }, { consecutive(lines, text) },
            { proportionalRatio(text) }, { sharedTotal(text) }, { ruleChoice(lines, text) }, { definedLetters(lines, text) },
            { functions(lines, text) }, { iteration(text) }, { rootInInterval(text) }, { factorisableCoefficient(text) },
            { sequenceUnknowns(lines, text) }, { linkedAmounts(text) }, { ratioAfterChange(text) }, { equivalentChoice(lines) },
            { identity(lines, text) }, { constantsFromValues(lines, text) }, { integerConditions(lines, text) }, { termsInWords(lines, text) }, { ratioWithLetter(lines, text) }, { chainedRatio(text) },
            { recurrence(lines, text) }, { signStatement(lines, text) }, { formulaTwice(text) }, { proportionValue(lines, text) },
            { rationaliseLetter(lines, text) }, { orderedExpressions(lines, text) }, { kinematics(lines, text) }, { grownFrom(lines, text) },
            { conversionFormula(text) }, { termsCombined(lines, text) }, { sumOfTwoBefore(lines, text) }, { circledFact(lines, text) },
        ]
        for kind in kinds {
            if var problem = kind() {
                problem.text = display
                return problem
            }
        }
        return nil
    }

    // MARK: Reading the question

    /// Asking for a reason, a proof or a drawing isn't asking for the number the words would give.
    private static let refusal = #"\bshow that\b|\bprove\b|\bexplain\b|\bgive (?:a|one|two|your) reasons?\b|\btick\b|\bdraw\b|\bsketch\b|\bplot\b|\bshade\b|\bdescribe\b|\bconstruct\b|\bis (?:he|she|it|this|that) (?:correct|right)\b"#

    /// What is left round a question that isn't part of it: the margin note, the question's
    /// number, the marks, the answer line.
    private static let noise = #"^(?:do not(?: write)?|outside(?: the)?|bo[:.]?|b[oо0]x|answer(?:\b|_).*|\[\d+ marks?\]|\(?\d+ marks?\]?|\d{1,2}\.?|\(\d\)|.{0,2}\d{1,2} marks?.{0,2}|\(total for question \d+ is \d+ marks?\)|\d{1,2} ?\([a-z]\)|\([a-z]\)|turn over\b.*|ib/m/.*|\*\d+\*|[_.…\-| ]+|[a-z] ?= ?[._… ]*|r-+1?)$"#

    /// The question's lines with dashes, look-alike letters and signs made plain, and the lines
    /// that aren't part of the question left out.
    private static func cleaned(_ display: String) -> [String] {
        var lines: [String] = []
        for raw in display.split(whereSeparator: \.isNewline) {
            var line = String(raw)
            for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("‒", "-"), ("﹣", "-"), ("⩽", "≤"), ("⩾", "≥"), ("<=", "≤"), (">=", "≥"),
                               ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "), ("\u{FFFC}", " "), ("’", "'")] {
                line = line.replacingOccurrences(of: from, with: to)
            }
            line = String(line.map { character in
                // Look-alike letters, but not the ones that stand for numbers or π here.
                guard let plain = Parser.lookalikes[character], plain.isLetter, plain != "π" else { return character }
                return plain
            })
            // The marks: "[3 marks]", or OCR's "[2]".
            line = line.replacingOccurrences(of: #"\s*\[\d+ marks?\]\s*|\s*\[\d{1,2}\]\s*"#, with: " ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\d{1,2}\s*\([a-z]\)\s+(?!=)"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\d{1,2}\.?\s+(?=[A-Z][a-z])"#, with: "", options: .regularExpression)
            // (And before a letter that the sentence is about: "|20 n is an integer such that…".)
            line = line.replacingOccurrences(of: #"^\|?\d{1,2}\s+(?=[a-z] is (?:an?|the) )"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || has(noise, line) { continue }
            lines.append(line)
        }
        return lines
    }

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The groups of the first match: the whole match first.
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

    private static let number = #"-?\d+(?:\.\d+)?"#

    /// Every number written in the text, as written (a minus sign only where it is one).
    private static func numbers(in text: String) -> [String] {
        every(#"(?<![\w.])-?\d+(?:\.\d+)?|(?<=[a-zA-Z^(])\d+(?:\.\d+)?"#, in: text).map { $0[0] }
    }

    private static func rational(_ written: String) -> Rational? {
        let digits = written.hasPrefix("-") ? String(written.dropFirst()) : written
        guard let value = Rational.parse(digits) else { return nil }
        return written.hasPrefix("-") ? value.negated : value
    }

    private static func exact(_ value: Rational) -> Expr { .number(.exact(value)) }
    /// A whole number as it is, anything else as a decimal (money, measures).
    private static func decimal(_ value: Rational) -> Expr { value.isInteger ? exact(value) : CircleDiagram.number(value.double) }
    private static func shown(_ value: Rational) -> String { Format.number(.exact(value)) }

    /// The terms of a sequence: a row of numbers on one line of its own, or after "starts" or
    /// "begins" at the end of a line. Only a row read as one line: numbers read on lines of
    /// their own may be out of order. A gap (`___`) in the row is kept as nil.
    private static func row(_ lines: [String]) -> [Rational?]? {
        var found: [[Rational?]] = []
        let item = #"(?:-?\d+(?:\.\d+)?|_{2,}|…|\.{3,})"#
        for line in lines {
            var run: String?
            if has("^\(item)(?:[ ,]+\(item))+$", line) {
                run = line
            } else if let after = groups(#"\b(?:starts|begins|starts with|begins with|is|are)[ :]+((?:-?\d+(?:\.\d+)?[ ,]+)+-?\d+(?:\.\d+)?)$"#, in: line) {
                run = after[1]
            }
            guard let run else { continue }
            let pieces = run.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            let terms = pieces.map { has(#"^-?\d"#, $0) ? rational($0) : nil }
            guard terms.contains(where: { $0 != nil }) else { continue }
            if zip(pieces, terms).contains(where: { has(#"^-?\d"#, $0.0) && $0.1 == nil }) { return nil }
            found.append(terms)
        }
        return found.count == 1 ? found[0] : nil
    }

    /// A question whose answer was worked out here, in the steps that go with it.
    private static func told(_ question: String, _ answers: [MathLine], _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .worded(question: question, answers: answers), text: "", usesDecimals: false)
        problem.lead = lead
        return problem
    }

    // MARK: Sequences

    /// "The 47th triangular number is 1128. The 48th triangular number is 1176. Work out the
    /// 49th triangular number."
    private static func triangular(_ text: String) -> Problem? {
        guard has(#"\btriangular numbers?\b"#, text),
              let asked = groups(#"(?:work out|find|write down|what is|calculate) the (\d+)(?:st|nd|rd|th) triangular number"#, in: text),
              let n = Int(asked[1]), n >= 1, n <= 100_000 else { return nil }
        func triangle(_ k: Int) -> Int { k * (k + 1) / 2 }
        var used = [asked[1]]
        var known: [Int: Int] = [:]
        for given in every(#"\bthe (\d+)(?:st|nd|rd|th) triangular number (?:is|=) (\d+)\b"#, in: text) {
            guard let k = Int(given[1]), let value = Int(given[2]), k <= 100_000, triangle(k) == value else { return nil }
            known[k] = value
            used += [given[1], given[2]]
        }
        // Every number in the question is one of those.
        guard Set(numbers(in: text)).isSubset(of: Set(used)), known[n] == nil else { return nil }
        var problem: Problem
        if let before = known[n - 1] {
            problem = Problem(kind: .evaluate(.add([.integer(before), .integer(n)])), text: "", usesDecimals: false)
            problem.lead = [Step("Add on the next number", "Each triangular number is the one before add one more: the \(ordinal(n)) is the \(ordinal(n - 1)) add \(n).",
                                 [MathLine(.symbol("\(ordinal(n)) triangular number"), .add([.integer(before), .integer(n)]))])]
        } else {
            let sum = Expr.multiply([.integer(n), .integer(n + 1), .power(.two, .minusOne)])
            problem = Problem(kind: .evaluate(sum), text: "", usesDecimals: false)
            problem.lead = [Step("Use the rule", "The nth triangular number is n(n + 1)/2. Put n = \(n) in.",
                                 [MathLine(.symbol("\(ordinal(n)) triangular number"), sum)])]
        }
        return problem
    }

    private static func ordinal(_ n: Int) -> String {
        let ending = (11...13).contains(n % 100) ? "th" : (n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th")
        return "\(n)\(ending)"
    }

    /// How many next terms are asked for, if any.
    private static func nextCount(_ text: String) -> Int? {
        guard let asked = groups(#"(?:work out|write down|find|what (?:is|are)|give) the next (two |three |2 |3 )?(?:terms?|numbers?)"#, in: text) else { return nil }
        let word = asked[1].trimmingCharacters(in: .whitespaces).lowercased()
        return word.isEmpty ? 1 : (word == "two" || word == "2" ? 2 : 3)
    }

    /// "A Fibonacci-type sequence starts 3 −8. The sequence is continued by adding the previous
    /// two terms. Work out the next two terms."
    private static func fibonacci(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"fibonacci|\badd(?:ing)? (?:together )?the (?:previous|last) two terms\b|\bsum of the (?:previous|last) two terms\b"#, text),
              let count = nextCount(text), let row = row(lines), row.count >= 2, row.count <= 10 else { return nil }
        let terms = row.compactMap { $0 }
        guard terms.count == row.count, numbers(in: text).count == terms.count else { return nil }
        // Terms after the first two have to keep to the rule already.
        for index in terms.indices.dropFirst(2) {
            guard let sum = terms[index - 2] + terms[index - 1], sum == terms[index] else { return nil }
        }
        var all = terms
        var working: [MathLine] = []
        for _ in 0..<count {
            let a = all[all.count - 2], b = all[all.count - 1]
            guard let next = a + b else { return nil }
            working.append(MathLine(.add([exact(a), exact(b)]), exact(next)))
            all.append(next)
        }
        let next = Array(all.suffix(count))
        let lead = [Step("Add the two terms before", "Each term is the two before it added together.", working)]
        return told("next \(count == 1 ? "term" : "\(count) terms")", [MathLine(.symbol(next.map(shown).joined(separator: count == 2 ? " and " : ", ")))], lead)
    }

    /// "A geometric progression starts 4 16. Work out the next term." "Write the missing term
    /// in the geometric progression. 1 4 16 ___ 256"
    private static func geometric(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bgeometric (?:progression|sequence)\b"#, text), let row = row(lines), row.count >= 2, row.count <= 10 else { return nil }
        let given = row.compactMap { $0 }
        guard numbers(in: text).count == given.count, given.allSatisfy({ !$0.isZero }) else { return nil }
        let blanks = row.indices.filter { row[$0] == nil }
        func times(_ r: Rational) -> String {
            if !r.isInteger, let inverse = Rational(1) / r, inverse.isInteger { return "divided by \(shown(inverse))" }
            return "multiplied by \(shown(r))"
        }
        if let count = nextCount(text) {
            guard blanks.isEmpty, let r = given[1] / given[0] else { return nil }
            for index in given.indices.dropFirst(2) { guard let step = given[index - 1] * r, step == given[index] else { return nil } }
            var last = given[given.count - 1], next: [Rational] = [], working: [MathLine] = []
            for _ in 0..<count {
                guard let value = last * r else { return nil }
                working.append(MathLine(.multiply([exact(last), exact(r)]), exact(value)))
                next.append(value)
                last = value
            }
            let lead = [Step("Find what each term is multiplied by", "In a geometric progression each term is the one before \(times(r)): \(shown(given[1])) ÷ \(shown(given[0])) = \(shown(r)).", []),
                        Step("Carry on", "", working)]
            return told("next \(count == 1 ? "term" : "\(count) terms")", [MathLine(.symbol(next.map(shown).joined(separator: count == 2 ? " and " : ", ")))], lead)
        }
        guard has(#"\bmissing (?:term|number)\b"#, text) else { return nil }
        // The missing term: where the row has a gap, or the one place a term was left out.
        var full: [Rational]?
        if blanks.count == 1 {
            let at = blanks[0]
            var candidates: [[Rational]] = []
            for (i, j) in [(0, 1), (row.count - 2, row.count - 1)] where row[i] != nil && row[j] != nil {
                guard let r = row[j]! / row[i]!, let first = (0..<i).reduce(Optional(row[i]!), { value, _ in value.flatMap { $0 / r } }) else { continue }
                var list: [Rational] = [first]
                for _ in 1..<row.count { guard let value = list.last! * r else { break }; list.append(value) }
                if list.count == row.count, row.indices.allSatisfy({ $0 == at || row[$0] == list[$0] }) { candidates.append(list) }
            }
            guard let one = candidates.first, candidates.allSatisfy({ $0 == one }) else { return nil }
            full = one
        } else if blanks.isEmpty, given.count >= 3 {
            var results: [[Rational]] = []
            for gap in 1..<given.count {
                var list = given
                guard let r = gap == 1 ? (given[2] / given[1]) : (given[1] / given[0]), let missing = given[gap - 1] * r else { continue }
                list.insert(missing, at: gap)
                let fits = list.indices.dropFirst().allSatisfy { index in (list[index - 1] * r).map { $0 == list[index] } ?? false }
                if fits { results.append(list) }
            }
            guard results.count == 1 else { return nil }
            full = results[0]
        }
        guard let full, full.count >= 3, let r = full[1] / full[0] else { return nil }
        let missingIndex = blanks.first ?? given.indices.first { full[$0] != given[$0] } ?? full.count - 1
        guard missingIndex > 0, missingIndex < full.count else { return nil }
        let value = full[missingIndex]
        let lead = [Step("Find what each term is multiplied by", "In a geometric progression each term is the one before \(times(r)).", []),
                    Step("Fill the gap", "The term after \(shown(full[missingIndex - 1])) is \(shown(full[missingIndex - 1])) × \(shown(r)), and \(shown(value)) × \(shown(r)) gives the term after it, \(missingIndex + 1 < full.count ? shown(full[missingIndex + 1]) : shown((value * r) ?? value)).",
                         [MathLine(.multiply([exact(full[missingIndex - 1]), exact(r)]), exact(value))])]
        return told("missing term", [MathLine(exact(value))], lead)
    }

    /// "The nth terms of two linear sequences, A and B, are added to give the nth term of a new
    /// sequence. The new sequence starts 8 13 18 23. The nth term of sequence A is n + 1.
    /// Work out the nth term of sequence B."
    private static func addedSequences(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\badded\b"#, text), !has(#"\bsubtract|\btake away|\bmultipl"#, text),
              let asked = groups(#"(?:work out|find|write down|give) (?:an expression for )?the nth term of sequence ([A-Z])\b"#, in: text) else { return nil }
        var known: (name: String, rule: Expr)?
        for line in lines {
            guard let given = groups(#"^the nth term of sequence ([A-Z]) is (.+?)\.?$"#, in: line) else { continue }
            guard known == nil, let rule = Parser.expression(given[2]), rule.symbols == ["n"] else { return nil }
            known = (given[1].uppercased(), rule)
        }
        guard let known, known.name != asked[1].uppercased(), let row = row(lines) else { return nil }
        let terms = row.compactMap { $0 }
        guard terms.count == row.count, terms.count >= 3, let step = terms[1] - terms[0] else { return nil }
        for index in terms.indices.dropFirst() { guard terms[index] - terms[index - 1] == step else { return nil } }
        // The known rule has to be linear too.
        let k0 = Simplify.run(known.rule.substituting("n", with: .zero)), k1 = Simplify.run(known.rule.substituting("n", with: .one)),
            k2 = Simplify.run(known.rule.substituting("n", with: .two))
        guard let a0 = k0.number?.rational, let a1 = k1.number?.rational, let a2 = k2.number?.rational, a2 - a1 == a1 - a0 else { return nil }
        // Every number is in the terms or the rule.
        let ruleNumbers = numbers(in: lines.first { has(#"^the nth term of sequence [A-Z] is"#, $0) } ?? "")
        guard numbers(in: text).count == terms.count + ruleNumbers.count, let start = terms[0] - step else { return nil }
        let n = Expr.symbol("n")
        let whole = Simplify.run(.add([.multiply([exact(step), n]), exact(start)]))
        let answer = Simplify.run(Simplify.expand(.add([whole, .multiply([.minusOne, known.rule])])))
        guard answer.symbols.isSubset(of: ["n"]) else { return nil }
        let other = asked[1].uppercased()
        let lead = [Step("Find the nth term of the new sequence", "It goes up by \(shown(step)) each time, so it starts \(shown(step))n, and \(shown(step)) × 1 has to become \(shown(terms[0])).",
                         [MathLine(.symbol("new sequence"), whole)]),
                    Step("Take away sequence \(known.name)", "The new sequence is \(known.name) add \(other), so \(other) is the new sequence take away \(known.name).",
                         [MathLine(.symbol(other), .add([whole, .multiply([.minusOne, known.rule])]), answer)])]
        return told("nth term of sequence \(other)", [MathLine(answer)], lead)
    }

    // MARK: Letters linked by facts

    private static let fractionWords: [String: Int] = ["half": 2, "halves": 2, "third": 3, "thirds": 3, "quarter": 4, "quarters": 4, "fifth": 5, "fifths": 5,
                                                       "sixth": 6, "sixths": 6, "seventh": 7, "sevenths": 7, "eighth": 8, "eighths": 8, "ninth": 9, "ninths": 9, "tenth": 10, "tenths": 10]
    private static let countWords: [String: Int] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9]

    /// "three quarters", "2/5", "40%": a fraction in words or figures.
    private static func fraction(_ words: String) -> Rational? {
        let plain = words.lowercased().trimmingCharacters(in: .whitespaces)
        if let figures = groups(#"^(\d+) ?/ ?(\d+)$"#, in: plain), let top = Int(figures[1]), let bottom = Int(figures[2]) { return Rational.make(top, bottom) }
        if let percent = groups(#"^(\d+(?:\.\d+)?) ?%$"#, in: plain), let value = Rational.parse(percent[1]) { return value / Rational(100) }
        if plain == "half" || plain == "a half" || plain == "one half" { return Rational.make(1, 2) }
        if let named = groups(#"^([a-z]+) ([a-z]+)$"#, in: plain), let top = countWords[named[1]], let bottom = fractionWords[named[2]] { return Rational.make(top, bottom) }
        return nil
    }

    private static func multiple(_ words: String) -> Rational? {
        let plain = words.lowercased().trimmingCharacters(in: .whitespaces)
        if plain == "twice" || plain == "double" { return Rational(2) }
        if plain == "half" { return Rational.make(1, 2) }
        if let times = groups(#"^(\d+(?:\.\d+)?|[a-z]+) times$"#, in: plain) { return Rational.parse(times[1]) ?? countWords[times[1]].map { Rational($0) } }
        return nil
    }

    /// A fact linking two letters as "first = factor × second".
    private struct Link { var first: String; var second: String; var factor: Rational }

    /// A line that links two of the letters: "a is three quarters of c", "a is twice b",
    /// "6b = 5c", "a : b = 2 : 3". Nil if it isn't one.
    private static func link(_ line: String, letters: Set<String>) -> Link? {
        let plain = line.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if let said = groups(#"^([a-z]) is (.+?) of ([a-z])$"#, in: plain), let f = fraction(said[2]) {
            return Link(first: said[1].lowercased(), second: said[3].lowercased(), factor: f)
        }
        if let said = groups(#"^([a-z]) is (twice|double|half|(?:\d+(?:\.\d+)?|[a-z]+) times) ([a-z])$"#, in: plain), let f = multiple(said[2]) {
            return Link(first: said[1].lowercased(), second: said[3].lowercased(), factor: f)
        }
        if let said = groups(#"^([a-z]) ?: ?([a-z]) ?= ?(\d+(?:\.\d+)?) ?: ?(\d+(?:\.\d+)?)$"#, in: plain),
           let p = Rational.parse(said[3]), let q = Rational.parse(said[4]), let f = p / q {
            return Link(first: said[1].lowercased(), second: said[2].lowercased(), factor: f)
        }
        // An equation in two of the letters, with no number on its own: 6b = 5c.
        let sides = plain.split(separator: "=", omittingEmptySubsequences: false)
        guard sides.count == 2, let left = Parser.expression(String(sides[0])), let right = Parser.expression(String(sides[1])) else { return nil }
        let difference = Expr.add([left, .multiply([.minusOne, right])])
        let used = difference.symbols
        guard used.count == 2, used.isSubset(of: letters) else { return nil }
        let names = used.sorted()
        func at(_ x: Int, _ y: Int) -> Rational? { Simplify.run(difference.substituting(names[0], with: .integer(x)).substituting(names[1], with: .integer(y))).number?.rational }
        // p·x + q·y = 0, checked at another point so that it is that and nothing more.
        guard let zero = at(0, 0), zero.isZero, let p = at(1, 0), let q = at(0, 1), !p.isZero, !q.isZero,
              let check = at(3, 7), let expected = (p * Rational(3)).flatMap({ a in (q * Rational(7)).flatMap { a + $0 } }), check == expected,
              let f = (q.negated / p) else { return nil }
        return Link(first: names[0], second: names[1], factor: f)
    }

    /// "a is three quarters of c. 6b = 5c. Work out the ratio a : b : c"
    private static func ratio(_ lines: [String], _ text: String) -> Problem? {
        guard let asked = groups(#"\bratio ([a-z](?: ?: ?[a-z]){1,4})\b"#, in: text) else { return nil }
        let order = asked[1].filter(\.isLetter).map { String($0).lowercased() }
        let letters = Set(order)
        guard letters.count == order.count else { return nil }
        var links: [Link] = []
        var used: [String] = []
        for line in lines where !has(#"\bratio\b|\bsimplest form\b|\bintegers?\b"#, line) {
            if let found = link(line, letters: letters) {
                guard letters.contains(found.first), letters.contains(found.second), found.first != found.second, found.factor > Rational(0) else { return nil }
                links.append(found)
                used += numbers(in: line)
            } else if !numbers(in: line).isEmpty {
                return nil
            }
        }
        guard links.count == letters.count - 1 else { return nil }
        // Everything in terms of the letter the facts share most.
        let base = order.max { a, b in links.filter { $0.first == a || $0.second == a }.count < links.filter { $0.first == b || $0.second == b }.count }!
        var values: [String: Rational] = [base: Rational(1)]
        for _ in 0..<letters.count {
            for item in links {
                if let known = values[item.second], values[item.first] == nil { values[item.first] = known * item.factor }
                else if let known = values[item.first], values[item.second] == nil { values[item.second] = known / item.factor }
            }
        }
        guard values.count == letters.count, order.allSatisfy({ values[$0] != nil }) else { return nil }
        for item in links { guard let second = values[item.second], (second * item.factor) == values[item.first] else { return nil } }
        // Whole numbers: times by the lowest common multiple of the bottoms, then cancel.
        var scale = 1
        for value in values.values { guard let next = Rational.lcm(scale, value.denominator) else { return nil }; scale = next }
        var whole = order.map { values[$0]!.numerator * (scale / values[$0]!.denominator) }
        let divisor = whole.reduce(0) { Rational.gcd($0, abs($1)) }
        guard divisor > 0 else { return nil }
        whole = whole.map { $0 / divisor }
        let baseWhole = whole[order.firstIndex(of: base)!]
        let inTerms = order.filter { $0 != base }.map { letter in MathLine(.symbol(letter), Simplify.run(.multiply([exact(values[letter]!), .symbol(base)]))) }
        let lead = [Step("Write each letter in terms of \(base)", "Turn each fact round so that it says how big the letter is compared with \(base).", inTerms),
                    Step("Make them whole numbers", "Take \(base) = \(baseWhole), the smallest value that makes every one a whole number.",
                         order.indices.map { MathLine(.symbol(order[$0]), .integer(whole[$0])) })]
        let names = order.joined(separator: " : ")
        return told(names, [MathLine(.symbol(names), .symbol(whole.map(String.init).joined(separator: " : ")))], lead)
    }

    // MARK: Equations given, then used

    /// The letter's value from an equation that is linear in it: nil if it isn't.
    private static func solved(_ equation: Expr, for letter: String) -> Expr? {
        let at0 = Simplify.run(equation.substituting(letter, with: .zero)), at1 = Simplify.run(equation.substituting(letter, with: .one))
        let slope = Simplify.run(.add([at1, .multiply([.minusOne, at0])]))
        guard !slope.isZero, !slope.contains(letter), !at0.contains(letter) else { return nil }
        // Linear: the same at other values of everything.
        let others = equation.symbols.subtracting([letter]).sorted()
        for trial in 0..<3 {
            var values: [String: Double] = [:]
            for (index, name) in others.enumerated() { values[name] = 1.3 + Double(index) * 0.7 + Double(trial) * 1.1 }
            for x in [2.5, -1.75] {
                var all = values
                all[letter] = x
                guard let whole = equation.evaluate(all), let s = slope.evaluate(values), let c = at0.evaluate(values),
                      abs(whole - (s * x + c)) <= 1e-9 * max(1, abs(whole)) else { return nil }
            }
        }
        return Simplify.run(.multiply([.minusOne, at0, .power(slope, .minusOne)]))
    }

    /// Two expressions with the same value whatever the letters are.
    private static func same(_ a: Expr, _ b: Expr) -> Bool {
        let names = a.symbols.union(b.symbols).sorted()
        for trial in 0..<4 {
            var values: [String: Double] = [:]
            for (index, name) in names.enumerated() { values[name] = 1.7 + Double(index) * 0.9 + Double(trial) * 1.3 }
            guard let x = a.evaluate(values), let y = b.evaluate(values), x.isFinite, y.isFinite,
                  abs(x - y) <= 1e-9 * max(1, abs(x)) else { return false }
        }
        return true
    }

    /// An equation line: one "=" with maths both sides. "x" between letters or numbers, spaced, is a times sign.
    private static func equation(_ line: String, timesX: Bool) -> (left: Expr, right: Expr)? {
        var plain = line.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if timesX { plain = plain.replacingOccurrences(of: #"(?<=[\w)]) x (?=[\w(])"#, with: " × ", options: .regularExpression) }
        let sides = plain.split(separator: "=", omittingEmptySubsequences: false)
        guard sides.count == 2, !has(#"[a-z]{3,}"#, plain), let left = Parser.expression(String(sides[0])), let right = Parser.expression(String(sides[1])) else { return nil }
        return (left, right)
    }

    /// "Given that a × 60 = b, work out the value of 4b/a"
    private static func valueGiven(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bgiven (?:that )?"#, text), has(#"(?:work out|find|calculate|write down|what is) the value of\b"#, text) else { return nil }
        // What to work out: after "value of", or a lone expression on a line of its own (a
        // fraction read above or below its sentence).
        var target: Expr?
        var targetLine: String?
        for line in lines {
            if let after = groups(#"the value of (.+?)\.?$"#, in: line), let expr = Parser.expression(after[1]), !expr.symbols.isEmpty {
                guard target == nil else { return nil }
                target = expr
                targetLine = after[1]
            }
        }
        if target == nil {
            let lone = lines.filter { !$0.contains("=") && !has(#"[a-z]{3,}"#, $0) && !$0.filter(\.isLetter).isEmpty }
            guard lone.count == 1, let expr = Parser.expression(lone[0]), !expr.symbols.isEmpty else { return nil }
            target = expr
            targetLine = lone[0]
        }
        guard let target, let targetLine else { return nil }
        let timesX = !target.contains("x")
        // The equation: a line of its own, or the words "given that" up to what's asked.
        let equations = lines.compactMap { line -> (String, (left: Expr, right: Expr))? in
            var bare = line.replacingOccurrences(of: #"(?i)^.*?\bgiven (?:that )?"#, with: "", options: .regularExpression)
            if let cut = bare.range(of: #",|\b(?:work out|find|calculate|write down|what)\b"#, options: [.regularExpression, .caseInsensitive]) {
                bare = String(bare[..<cut.lowerBound])
            }
            return equation(bare, timesX: timesX).map { (bare, $0) }
        }
        guard equations.count == 1, let (equationLine, given) = equations.first else { return nil }
        let difference = Expr.add([given.left, .multiply([.minusOne, given.right])])
        // Every number is in the equation or what's asked.
        guard numbers(in: text).count == numbers(in: equationLine).count + numbers(in: targetLine).count else { return nil }
        for letter in target.symbols.intersection(difference.symbols).sorted(by: { a, b in a > b }) {
            guard let value = solved(difference, for: letter) else { continue }
            let put = Simplify.run(target.substituting(letter, with: value))
            guard let result = put.number, put.symbols.isEmpty else { continue }
            let lead = [Step("Use what you're given", "Write \(letter) in terms of the other letter\(difference.symbols.count > 2 ? "s" : "").",
                             [MathLine(given.left, given.right), MathLine(.symbol(letter), value)]),
                        Step("Put it into \(Format.text(target))", "The letters cancel, leaving a number.",
                             [MathLine(target, target.substituting(letter, with: value), .number(result))])]
            return told("value of \(Format.text(target))", [MathLine(.number(result))], lead)
        }
        return nil
    }

    /// "a × b⁴ = c. Circle the correct expression for a." with the choices under it.
    private static func chosenSubject(_ lines: [String], _ text: String) -> Problem? {
        guard let asked = groups(#"\b(?:circle|choose|write down|which is) the (?:correct )?expression for ([a-z])\b"#, in: text) else { return nil }
        let letter = asked[1].lowercased()
        guard let askedAt = lines.firstIndex(where: { has(#"expression for [a-z]\b"#, $0) }) else { return nil }
        let equations = lines.compactMap { line -> (left: Expr, right: Expr)? in
            guard let found = equation(line, timesX: letter != "x") else { return nil }
            return found
        }
        guard equations.count == 1, let given = equations.first else { return nil }
        let difference = Expr.add([given.left, .multiply([.minusOne, given.right])])
        guard difference.contains(letter), let value = solved(difference, for: letter) else { return nil }
        // The choices: lines after the question that are maths, with no "=".
        let after = lines[(askedAt + 1)...].filter { !$0.contains("=") && !has(#"[a-z]{3,}"#, $0) }
        let choices = after.compactMap { Parser.expression($0) }
        let matching = choices.filter { same($0, value) }
        guard matching.count <= 1 else { return nil }
        // Every choice read and none of them is it: something was misread.
        if matching.isEmpty, !after.isEmpty, choices.count == after.count { return nil }
        let shown = matching.first.map(Simplify.run) ?? value
        let lead = [Step("Make \(letter) the subject", "Do the same to both sides until \(letter) is on its own.",
                         [MathLine(given.left, given.right), MathLine(.symbol(letter), shown)])]
            + (matching.isEmpty ? [] : [Step("Find it among the choices", "Only one of them is the same as \(Format.text(value)) whatever the letters are.")])
        return told("expression for \(letter)", [MathLine(.symbol(letter), shown)], lead)
    }

    // MARK: Round 2

    /// Coefficients of a linear expression in `x` and `y`: a·x + b·y + c, checked at other values. Nil if it isn't linear.
    private static func linearIn(_ f: Expr, _ x: String, _ y: String) -> (a: Expr, b: Expr, c: Expr)? {
        func tidy(_ e: Expr) -> Expr { Simplify.run(Simplify.expand(e)) }
        func at(_ u: Expr, _ v: Expr) -> Expr { tidy(f.substituting(x, with: u).substituting(y, with: v)) }
        let c = at(.zero, .zero)
        let a = tidy(.add([at(.one, .zero), .multiply([.minusOne, c])]))
        let b = tidy(.add([at(.zero, .one), .multiply([.minusOne, c])]))
        guard !a.contains(x), !a.contains(y), !b.contains(x), !b.contains(y), !c.contains(x), !c.contains(y) else { return nil }
        let others = f.symbols.subtracting([x, y]).sorted()
        for trial in 0..<3 {
            var values: [String: Double] = [:]
            for (index, name) in others.enumerated() { values[name] = 1.9 + Double(index) * 0.6 + Double(trial) * 0.8 }
            for (u, v) in [(2.5, -1.25), (-3.0, 4.5)] {
                var all = values
                all[x] = u
                all[y] = v
                guard let whole = f.evaluate(all), let av = a.evaluate(values), let bv = b.evaluate(values), let cv = c.evaluate(values),
                      abs(whole - (av * u + bv * v + cv)) <= 1e-9 * max(1, abs(whole)) else { return nil }
            }
        }
        return (a, b, c)
    }

    /// "Solve the simultaneous equations 2x + 3y = 5p, y = 2x + p, where p is a constant.
    /// Give your answers in terms of p."
    private static func simultaneousInTermsOf(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bsimultaneous\b"#, text), let constant = groups(#"\bin terms of ([a-z])\b"#, in: text)?[1].lowercased() else { return nil }
        let equations = lines.compactMap { line -> (String, (left: Expr, right: Expr))? in
            equation(line.replacingOccurrences(of: #"(?i)^solve(?: the simultaneous equations)?:?\s*"#, with: "", options: .regularExpression), timesX: false).map { (line, $0) }
        }
        guard equations.count == 2 else { return nil }
        let differences = equations.map { Expr.add([$0.1.left, .multiply([.minusOne, $0.1.right])]) }
        let unknowns = differences.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }.subtracting([constant]).sorted()
        guard unknowns.count == 2,
              numbers(in: text).count == equations.reduce(0, { $0 + numbers(in: $1.0).count }) else { return nil }
        let x = unknowns[0], y = unknowns[1]
        guard let first = linearIn(differences[0], x, y), let second = linearIn(differences[1], x, y) else { return nil }
        // a₁x + b₁y = −c₁, a₂x + b₂y = −c₂: Cramer's rule.
        let det = Simplify.run(Simplify.expand(.add([.multiply([first.a, second.b]), .multiply([.minusOne, second.a, first.b])])))
        guard !det.isZero, det.symbols.isEmpty else { return nil }
        let xValue = Simplify.run(Simplify.expand(.multiply([.add([.multiply([second.c, first.b]), .multiply([.minusOne, first.c, second.b])]), .power(det, .minusOne)])))
        let yValue = Simplify.run(Simplify.expand(.multiply([.add([.multiply([first.c, second.a]), .multiply([.minusOne, second.c, first.a])]), .power(det, .minusOne)])))
        guard xValue.symbols.isSubset(of: [constant]), yValue.symbols.isSubset(of: [constant]) else { return nil }
        // They fit both equations.
        for difference in differences {
            guard same(Simplify.run(difference.substituting(x, with: xValue).substituting(y, with: yValue)), .zero) else { return nil }
        }
        let lead = [Step("Solve them as if \(constant) were a number", "Treat \(constant) as a known number and eliminate one letter, as with any pair of simultaneous equations.",
                         equations.map { MathLine($0.1.left, $0.1.right) }),
                    Step("Find \(x) and \(y)", "", [MathLine(.symbol(x), xValue), MathLine(.symbol(y), yValue)])]
        return told("\(x) and \(y) in terms of \(constant)", [MathLine(.symbol("\(x) = \(Format.text(xValue)), \(y) = \(Format.text(yValue))"))], lead)
    }

    private static let numberWords: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "twenty": 20]

    private static func count(_ word: String) -> Int? { Int(word) ?? numberWords[word.lowercased()] }

    /// Choices written in a row: split where one expression ends and the next starts (two
    /// things side by side with no sign between them, outside brackets).
    private static func choices(_ line: String) -> [String] {
        let tokens = line.split(separator: " ").map(String.init)
        var pieces: [String] = [], current: [String] = [], depth = 0
        func isSign(_ token: String) -> Bool { ["+", "-", "×", "*", "÷", "/", "="].contains(token) }
        for token in tokens {
            if let last = current.last, depth == 0, !isSign(last), !isSign(token), !last.hasSuffix("+") && !last.hasSuffix("-"), !token.hasPrefix("+") {
                pieces.append(current.joined(separator: " "))
                current = []
            }
            current.append(token)
            depth += token.filter { $0 == "(" }.count - token.filter { $0 == ")" }.count
        }
        if !current.isEmpty { pieces.append(current.joined(separator: " ")) }
        return pieces
    }

    /// "Amy has x beads. Billy has three more beads than Amy. Carly has four times as many beads
    /// as Billy. Circle the expression for the number of beads that Carly has." with the choices.
    private static func describedChoice(_ lines: [String], _ text: String) -> Problem? {
        guard let asked = groups(#"\bexpression for the (?:total )?number of ([a-z]+) (?:that )?([A-Z][a-z]+) has\b"#, in: text) else { return nil }
        let thing = asked[1].lowercased()
        var known: [String: Expr] = [:]
        var steps: [MathLine] = []
        var askedAt: Int?
        for (index, line) in lines.enumerated() {
            let plain = line.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            if has(#"\bexpression for\b"#, plain) { askedAt = index; break }
            if let base = groups(#"^([A-Z][a-z]+) has ([a-z]) \#(thing)$"#, in: plain) {
                known[base[1]] = .symbol(base[2])
                steps.append(MathLine(.symbol(base[1]), .symbol(base[2])))
            } else if let more = groups(#"^([A-Z][a-z]+) has (\w+) (more|fewer|less) (?:\#(thing) )?than ([A-Z][a-z]+)$"#, in: plain),
                      let k = count(more[2]), let other = known[more[4]] {
                let value = Expr.add([other, .integer(more[3].lowercased() == "more" ? k : -k)])
                known[more[1]] = value
                steps.append(MathLine(.symbol(more[1]), value))
            } else if let times = groups(#"^([A-Z][a-z]+) has (twice|double|half|(\w+) times) as many (?:\#(thing) )?as ([A-Z][a-z]+)$"#, in: plain),
                      let other = known[times[4]] {
                let factor: Expr
                switch times[2].lowercased() {
                case "twice", "double": factor = .two
                case "half": factor = .half
                default:
                    guard let k = count(times[3]) else { return nil }
                    factor = .integer(k)
                }
                let value = Expr.multiply([factor, other])
                known[times[1]] = value
                steps.append(MathLine(.symbol(times[1]), value))
            } else if has(#"\b\#(thing)\b"#, plain) {
                return nil
            }
        }
        guard let askedAt, let value = known[asked[2]], numbers(in: lines[..<askedAt].joined(separator: " ")).isEmpty else { return nil }
        // The choices: the lines after the question.
        let written = lines[(askedAt + 1)...].filter { !has(#"[a-z]{3,}"#, $0) && !has(#"^\d{1,2}$"#, $0) }.flatMap { choices($0) }
        let parsed = written.compactMap { Parser.expression($0) }
        let matching = parsed.filter { same($0, value) }
        guard matching.count <= 1 else { return nil }
        if matching.isEmpty, !written.isEmpty, parsed.count == written.count { return nil }
        let shown = matching.first ?? value
        var lead = [Step("Write each one as an expression", "Start from the one given as a letter and follow the words.", steps)]
        if !matching.isEmpty { lead.append(Step("Find it among the choices", "Only one of them is the same as \(Format.text(value)).")) }
        return told("number of \(thing) \(asked[2]) has", [MathLine(shown)], lead)
    }

    private static func isPrime(_ n: Int) -> Bool {
        guard n >= 2 else { return false }
        var d = 2
        while d * d <= n { if n % d == 0 { return false }; d += 1 }
        return true
    }

    /// "The nth term of a sequence is 12n − 5. Work out the numbers in the sequence that have
    /// two digits and are not prime."
    private static func termsWith(_ lines: [String], _ text: String, _ display: String) -> Problem? {
        // The list of conditions runs over several lines: only answer when the end of the question (its marks or answer line) is in view.
        guard display.range(of: #"(?im)\[\d+ marks?\]|^answer\b"#, options: .regularExpression) != nil else { return nil }
        guard let rule = groups(#"\bnth term of (?:a|the|this) sequence is ([0-9n+\-*×^ ()]+?)(?=\.? (?:work|write|find|list|which)\b|\.?$)"#, in: text),
              let expr = Parser.expression(rule[1]), expr.symbols == ["n"],
              let conditions = groups(#"\b(?:work out|write down|find|list) (?:all )?the (?:numbers|terms) in the sequence that (.+?)\.?$"#, in: text)?[1].lowercased() else { return nil }
        var rest = " " + conditions + " "
        var digits: Int?
        var wantPrime: Bool?
        var parity: Int?
        if let found = groups(#" (?:have|are) (one|two|three|four|1|2|3|4)(?: |-)digits? (?:numbers )?"#, in: rest) {
            digits = count(found[1]); rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        if let found = groups(#" (?:are|is) (not )?(?:a )?prime(?: numbers?)? "#, in: rest) {
            wantPrime = found[1].isEmpty; rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        if let found = groups(#" (?:are|is) (odd|even)(?: numbers?)? "#, in: rest) {
            parity = found[1] == "even" ? 0 : 1; rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        guard let digits, rest.replacingOccurrences(of: #"\band\b|,"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces).isEmpty,
              numbers(in: text).count == numbers(in: rule[1]).count + (has(#"\d(?: |-)digit"#, conditions) ? 1 : 0) else { return nil }
        let low = Int(pow(10, Double(digits - 1))), high = Int(pow(10, Double(digits))) - 1
        // The terms go up in equal steps, so the ones in range are a run of n.
        guard let first = Simplify.run(expr.substituting("n", with: .one)).number?.integer,
              let second = Simplify.run(expr.substituting("n", with: .two)).number?.integer, second > first,
              let third = Simplify.run(expr.substituting("n", with: .integer(3))).number?.integer, third - second == second - first else { return nil }
        var found: [Int] = [], inRange: [Int] = []
        var n = 1
        while n < 100_000 {
            guard let value = Simplify.run(expr.substituting("n", with: .integer(n))).number?.integer else { return nil }
            if value > high { break }
            if value >= low {
                inRange.append(value)
                if (wantPrime.map { isPrime(value) == $0 } ?? true) && (parity.map { abs(value % 2) == $0 } ?? true) { found.append(value) }
            }
            n += 1
        }
        guard !found.isEmpty, found.count <= 30 else { return nil }
        let shownList = found.map(String.init).joined(separator: found.count == 2 ? " and " : ", ")
        var lead = [Step("List the terms with \(digits) digit\(digits == 1 ? "" : "s")", "Put n = 1, 2, 3, … into \(Format.text(expr)).", [MathLine(.symbol(inRange.map(String.init).joined(separator: ", ")))])]
        if let wantPrime { lead.append(Step(wantPrime ? "Keep the prime ones" : "Cross out the prime ones", "A prime number has exactly two factors, 1 and itself.")) }
        if let parity { lead.append(Step("Keep the \(parity == 0 ? "even" : "odd") ones", "")) }
        return told("terms of \(Format.text(expr))", [MathLine(.symbol(shownList))], lead)
    }

    /// The maths at the end of some words: the longest run of words at the end that reads as an
    /// expression in one letter.
    private static func lastExpression(_ words: String) -> Expr? {
        let tokens = words.split(separator: " ").map(String.init)
        for start in tokens.indices {
            let piece = tokens[start...].joined(separator: " ")
            if let expr = Parser.expression(piece), expr.symbols.count == 1, !has(#"[a-z]{2,}"#, piece) { return expr }
        }
        return nil
    }

    /// "9k + 7 and 2k² + 3 are consecutive integers. 9k + 7 is the smaller integer. Work out the
    /// value of the next consecutive integer."
    private static func consecutive(_ lines: [String], _ text: String) -> Problem? {
        guard let pair = groups(#"([^.]+?) and ([^.]+?) are consecutive (?:integers|whole numbers)\b"#, in: text),
              let a = lastExpression(pair[1]), let b = Parser.expression(pair[2]) else { return nil }
        let letters = a.symbols.union(b.symbols)
        guard letters.count == 1, let k = letters.first else { return nil }
        // Which is the smaller.
        var smaller: Expr?
        if let said = groups(#"(?:^|\. |integers?\.? )([^.]+?) is the (smaller|smallest|larger|largest|bigger|biggest)(?: (?:integer|number|one))?\b"#, in: text),
           let named = Parser.expression(said[1]) {
            let isA = same(named, a), isB = same(named, b)
            guard isA != isB else { return nil }
            let wantsSmall = said[2].lowercased().hasPrefix("small")
            smaller = (isA == wantsSmall) ? a : b
        }
        guard let smaller else { return nil }
        let larger = same(smaller, a) ? b : a
        // larger − smaller − 1 = 0, at most a quadratic in k.
        let f = Expr.add([larger, .multiply([.minusOne, smaller]), .minusOne])
        func at(_ value: Int) -> Rational? { Simplify.run(f.substituting(k, with: .integer(value))).number?.rational }
        guard let f0 = at(0), let f1 = at(1), let fm = at(-1), let f2 = at(2),
              let half = Rational.make(1, 2), let sum = f1 + fm, let qa = (sum * half).flatMap({ $0 - f0 }), let diff = f1 - fm, let qb = diff * half,
              let check = (qa * Rational(4)).flatMap({ x in (qb * Rational(2)).flatMap { x + $0 } }).flatMap({ $0 + f0 }), check == f2 else { return nil }
        var roots: [Rational] = []
        if qa.isZero {
            guard !qb.isZero, let root = f0.negated / qb else { return nil }
            roots = [root]
        } else {
            guard let bb = qb * qb, let ac = (qa * f0).flatMap({ $0 * Rational(4) }), let disc = bb - ac, disc >= Rational(0) else { return nil }
            guard let top = Rational.exactRoot(disc.numerator, 2), let bottom = Rational.exactRoot(disc.denominator, 2), let root = Rational.make(top, bottom),
                  let twoA = qa * Rational(2) else { return nil }
            roots = [(qb.negated + root).flatMap { $0 / twoA }, (qb.negated - root).flatMap { $0 / twoA }].compactMap { $0 }
        }
        // Only a value of k that makes them whole numbers.
        let fitting = Set(roots).filter { r in
            [smaller, larger].allSatisfy { Simplify.run($0.substituting(k, with: exact(r))).number?.rational?.isInteger ?? false }
        }
        guard fitting.count == 1, let value = fitting.first,
              let low = Simplify.run(smaller.substituting(k, with: exact(value))).number?.integer,
              let high = Simplify.run(larger.substituting(k, with: exact(value))).number?.integer, high == low + 1 else { return nil }
        let rejected = roots.filter { $0 != value }.map(shown)
        var lead = [Step("The larger is one more than the smaller", "", [MathLine(larger, .add([smaller, .one])), MathLine(Simplify.run(Simplify.expand(f)), .zero)]),
                    Step("Solve for \(k)", rejected.isEmpty ? "" : "\(k) = \(rejected.joined(separator: " or ")) doesn't make them whole numbers.", [MathLine(.symbol(k), exact(value))]),
                    Step("Put \(k) = \(shown(value)) in", "", [MathLine(smaller, .integer(low)), MathLine(larger, .integer(high))])]
        if has(#"\bnext (?:consecutive )?(?:integer|whole number|number)\b"#, text) {
            lead.append(Step("The next integer is one more", "", [MathLine(.add([.integer(high), .one]), .integer(high + 1))]))
            return told("next consecutive integer", [MathLine(.integer(high + 1))], lead)
        }
        if has(#"\bvalue of \#(k)\b"#, text) { return told("value of \(k)", [MathLine(.symbol(k), exact(value))], Array(lead.prefix(2))) }
        if has(#"\b(?:the|both|two) (?:integers|whole numbers|numbers)\b"#, text), has(#"\b(?:work out|find|write down)\b"#, text) {
            return told("the two integers", [MathLine(.symbol("\(low) and \(high)"))], lead)
        }
        return nil
    }

    /// "G is directly proportional to the square root of H. G : H = 3 : 2 when H = 16.
    /// Work out G : H when H = 100"
    private static func proportionalRatio(_ text: String) -> Problem? {
        guard let rule = groups(#"\b([A-Za-z]) is (directly |inversely )?proportional to (the square root of |the square of |the cube of |the cube root of )?([A-Za-z])\b"#, in: text) else { return nil }
        let g = rule[1], h = rule[4], inverse = rule[2].lowercased().hasPrefix("inverse")
        let pattern = "\\b\(g) ?: ?\(h) ?= ?(\\d+(?:\\.\\d+)?) ?: ?(\\d+(?:\\.\\d+)?),? when \(h) ?= ?(\\d+(?:\\.\\d+)?)\\b"
        guard g != h, let given = groups(pattern, in: text),
              let asked = groups("\\b(?:work out|find|what is) \(g) ?: ?\(h) when \(h) ?= ?(\\d+(?:\\.\\d+)?)\\b", in: text),
              let p = Rational.parse(given[1]), let q = Rational.parse(given[2]), let h0 = Rational.parse(given[3]), let h1 = Rational.parse(asked[1]),
              !q.isZero, numbers(in: text).count == 4 else { return nil }
        let power: Expr
        switch rule[3].lowercased().trimmingCharacters(in: .whitespaces) {
        case "the square root of": power = .half
        case "the square of": power = .two
        case "the cube of": power = .integer(3)
        case "the cube root of": power = .fraction(1, 3)
        default: power = .one
        }
        guard let g0 = (h0 * p).flatMap({ $0 / q }) else { return nil }
        let H = Expr.symbol(h)
        let shape = Expr.power(H, power)
        let general: Expr = inverse ? .multiply([.symbol("k"), .power(shape, .minusOne)]) : .multiply([.symbol("k"), shape])
        let k = Simplify.run(inverse ? .multiply([exact(g0), shape.substituting(h, with: exact(h0))]) : .multiply([exact(g0), .power(shape.substituting(h, with: exact(h0)), .minusOne)]))
        guard k.number != nil else { return nil }
        let g1Expr = Simplify.run(general.substituting("k", with: k).substituting(h, with: exact(h1)))
        guard let g1 = g1Expr.number?.rational, g1 > Rational(0) else { return nil }
        // G : H in whole numbers.
        guard let scale = Rational.lcm(g1.denominator, h1.denominator) else { return nil }
        let left = g1.numerator * (scale / g1.denominator), right = h1.numerator * (scale / h1.denominator)
        let divisor = Rational.gcd(abs(left), abs(right))
        guard divisor > 0 else { return nil }
        let lead = [Step("Find \(g) when \(h) = \(shown(h0))", "\(g) : \(h) = \(shown(p)) : \(shown(q)), so \(g) is \(shown(p)) ÷ \(shown(q)) of \(h).",
                         [MathLine(.symbol(g), .multiply([exact(h0), exact((p / q)!)]), exact(g0))]),
                    Step("Write it as an equation", "\(g) is \(inverse ? "inversely" : "directly") proportional to \(Format.text(shape)).",
                         [MathLine(.symbol(g), general), MathLine(.symbol("k"), k)]),
                    Step("Find \(g) when \(h) = \(shown(h1))", "", [MathLine(.symbol(g), g1Expr)]),
                    Step("Write \(g) : \(h) in its simplest form", "", [MathLine(.symbol("\(g) : \(h)"), .symbol("\(shown(g1)) : \(shown(h1))"), .symbol("\(left / divisor) : \(right / divisor)"))])]
        return told("\(g) : \(h)", [MathLine(.symbol("\(left / divisor) : \(right / divisor)"))], lead)
    }

    /// "Rana sells 192 cakes in the ratio small : medium : large = 7 : 6 : 11. The profit for one
    /// medium cake is twice the profit for one small cake. The profit for one large cake is three
    /// times the profit for one small cake. Her total profit is £532.48. Work out the profit for
    /// one small cake."
    private static func sharedTotal(_ text: String) -> Problem? {
        guard let split = groups(#"\b(\d+) ([a-z]+) in the ratio ([a-z]+(?: ?: ?[a-z]+)+) ?= ?(\d+(?: ?: ?\d+)+)"#, in: text),
              let total = Int(split[1]) else { return nil }
        let names = split[3].split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let parts = split[4].split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard names.count == parts.count, Set(names).count == names.count, parts.allSatisfy({ $0 > 0 }) else { return nil }
        let sum = parts.reduce(0, +)
        guard total % sum == 0 else { return nil }
        let counts = parts.map { $0 * total / sum }
        let item = #"(?:one|each|a|an) ([a-z]+)(?: [a-z]+)?"#
        guard let asked = groups(#"\bwork out the ([a-z]+) (?:for|on|of|from) \#(item)\b"#, in: text) else { return nil }
        let measure = asked[1].lowercased(), base = asked[2].lowercased()
        guard let baseIndex = names.firstIndex(of: base),
              let totalValue = groups(#"\btotal \#(measure) (?:is|was|=) £?(\d+(?:\.\d+)?)\b"#, in: text).flatMap({ Rational.parse($0[1]) }) else { return nil }
        var factors: [String: Rational] = [base: Rational(1)]
        for said in every(#"\bthe \#(measure) (?:for|on|of|from) \#(item) is (twice|double|half|(\w+) times) the \#(measure) (?:for|on|of|from) \#(item)"#, in: text) {
            let first = said[1].lowercased(), second = said[4].lowercased()
            guard names.contains(first), let known = factors[second] else { return nil }
            let factor: Rational
            switch said[2].lowercased() {
            case "twice", "double": factor = Rational(2)
            case "half": factor = Rational.make(1, 2)!
            default:
                guard let k = count(said[3]) else { return nil }
                factor = Rational(k)
            }
            guard let value = known * factor else { return nil }
            factors[first] = value
        }
        // Every kind has its value, and the numbers are all used.
        guard names.allSatisfy({ factors[$0] != nil }), numbers(in: text).count == 2 + parts.count else { return nil }
        var weight = Rational(0)
        for (index, name) in names.enumerated() { guard let next = (factors[name]! * Rational(counts[index])).flatMap({ weight + $0 }) else { return nil }; weight = next }
        guard !weight.isZero, let value = totalValue / weight else { return nil }
        let p = Expr.symbol("p")
        let numberLines = names.indices.map { MathLine(.symbol(names[$0]), .multiply([.integer(total), .fraction(parts[$0], sum)]), .integer(counts[$0])) }
        let pieces = names.indices.map { Expr.multiply([.integer(counts[$0]), exact(factors[names[$0]]!), p]) }
        let lead = [Step("Share out the \(split[2])", "\(total) in the ratio \(parts.map(String.init).joined(separator: " : ")): \(sum) parts in all.", numberLines),
                    Step("Write the total as an equation", "Call the \(measure) for one \(base) p; the others are multiples of it.",
                         [MathLine(.add(pieces), decimal(totalValue)), MathLine(Simplify.run(.multiply([exact(weight), p])), decimal(totalValue))]),
                    Step("Solve it", "", [MathLine(p, .multiply([decimal(totalValue), .power(exact(weight), .minusOne)]), decimal(value))])]
        return told("\(measure) for one \(base)", [MathLine(decimal(value))], lead)
    }

    /// "The next term of a sequence is made by adding the previous two terms. Which of these
    /// sequences follows this rule?" with the sequences as rows.
    private static func ruleChoice(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\badd(?:ing)? (?:together )?the (?:previous|last) two terms\b"#, text),
              has(#"\bwhich (?:of these )?(?:sequences?|one) (?:follows|obeys|uses|fits)\b"#, text) else { return nil }
        guard let askedAt = lines.firstIndex(where: { has(#"\bwhich (?:of these )?(?:sequences?|one)\b"#, $0) }) else { return nil }
        var rows: [[Rational]] = []
        for line in lines[(askedAt + 1)...] where has(#"^-?\d+(?:\.\d+)?(?: +-?\d+(?:\.\d+)?){2,}$"#, line) {
            let terms = line.split(separator: " ").compactMap { rational(String($0)) }
            rows.append(terms)
        }
        guard rows.count >= 3 else { return nil }
        func keeps(_ row: [Rational]) -> Bool {
            row.count >= 4 && row.indices.dropFirst(2).allSatisfy { index in (row[index - 2] + row[index - 1]).map { sum in sum == row[index] } ?? false }
        }
        let right = rows.filter(keeps)
        guard right.count == 1, let row = right.first else { return nil }
        let working = row.indices.dropFirst(2).map { MathLine(.add([exact(row[$0 - 2]), exact(row[$0 - 1])]), exact(row[$0])) }
        let lead = [Step("Check each one", "Each term has to be the two before it added together. Only one row keeps to that all the way.", working)]
        return told("the sequence that follows the rule", [MathLine(.symbol(row.map(shown).joined(separator: "  ")))], lead)
    }

    /// "A, B and C are numbers. B: 7/4 of A. C: A increased by 150%. Work out C as a fraction of B."
    private static func definedLetters(_ lines: [String], _ text: String) -> Problem? {
        guard let asked = groups(#"\b(?:work out|write|express|give) ([A-Z]) as a fraction of ([A-Z])\b"#, in: text) else { return nil }
        var defined: [String: (factor: Rational, of: String)] = [:]
        var used: [String] = []
        for line in lines {
            let plain = line.trimmingCharacters(in: CharacterSet(charactersIn: " .")).replacingOccurrences(of: #"^([A-Z]) ?(?:=|:|is) ?"#, with: "$1 ", options: .regularExpression)
            if let said = groups(#"^([A-Z]) (.+?) of ([A-Z])$"#, in: plain), let f = fraction(said[2]) {
                defined[said[1]] = (f, said[3]); used += numbers(in: plain)
            } else if let said = groups(#"^([A-Z]) ([A-Z]) (increased|decreased) by (\d+(?:\.\d+)?) ?%$"#, in: plain), let percent = Rational.parse(said[4]),
                      let change = percent / Rational(100), let f = said[3] == "increased" ? Rational(1) + change : Rational(1) - change {
                defined[said[1]] = (f, said[2]); used += numbers(in: plain)
            } else if let said = groups(#"^([A-Z]) ([A-Z]) (multiplied|divided) by (\d+(?:\.\d+)?)$"#, in: plain), let n = Rational.parse(said[4]),
                      let f = said[3] == "multiplied" ? Optional(n) : Rational(1) / n {
                defined[said[1]] = (f, said[2]); used += numbers(in: plain)
            }
        }
        let top = asked[1], bottom = asked[2]
        guard let a = defined[top], let b = defined[bottom], a.of == b.of, a.of != top, a.of != bottom,
              numbers(in: text).count == used.count, let value = a.factor / b.factor else { return nil }
        let base = a.of
        let lead = [Step("Write \(top) and \(bottom) in terms of \(base)", "",
                         [MathLine(.symbol(top), Simplify.run(.multiply([exact(a.factor), .symbol(base)]))), MathLine(.symbol(bottom), Simplify.run(.multiply([exact(b.factor), .symbol(base)])))]),
                    Step("Divide", "\(top) as a fraction of \(bottom) is \(top) ÷ \(bottom); the \(base)s cancel.",
                         [MathLine(.multiply([exact(a.factor), .power(exact(b.factor), .minusOne)]), exact(value))])]
        return told("\(top) as a fraction of \(bottom)", [MathLine(exact(value))], lead)
    }

    // MARK: Functions

    /// The lines of a question about functions written plainly: "f (x)" as f(x), "f g(2)" as
    /// fg(2), and × or X as the letter x where the functions are written of × ("g(×) = 2x + 4").
    private static func functionLines(_ lines: [String], _ text: String) -> [String] {
        let timesIsX = has(#"(?<![A-Za-z])[fgh] ?\( ?[×X] ?\)"#, text)
        return lines.map { line in
            // (The question's number before a rule: "18 f(x) = x² + 6x".)
            var plain = line.replacingOccurrences(of: #"^\d{1,2}\.? (?=[fgh] ?\()"#, with: "", options: .regularExpression)
            if timesIsX { plain = plain.replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: "X", with: "x") }
            plain = plain.replacingOccurrences(of: #"(?<![A-Za-z])([fgh]{1,3}) \("#, with: "$1(", options: .regularExpression)
            plain = plain.replacingOccurrences(of: #"(?<![A-Za-z])([fgh]) ([fgh]{1,2})\("#, with: "$1$2(", options: .regularExpression)
            // One letter of gf(3) read raised above the other: g^f(3).
            plain = plain.replacingOccurrences(of: #"(?<![A-Za-z])([fgh])\^([fgh]) ?\("#, with: "$1$2(", options: .regularExpression)
            plain = plain.replacingOccurrences(of: #"\( ?([^()]*?) ?\)"#, with: "($1)", options: .regularExpression)
            return plain
        }
    }

    /// Whether a function's rule looks read in full. A small power lost leaves a digit straight
    /// after a letter ("x2 + 3") or like terms side by side that no one would write ("x + 6x"
    /// for x² + 6x).
    private static func isWhole(_ written: String) -> Bool {
        guard !has(#"[a-z]\d"#, written) else { return false }
        var depth = 0, term = "", terms: [String] = []
        for character in written {
            if character == "(" { depth += 1 } else if character == ")" { depth -= 1 }
            if depth == 0, character == "+" || character == "-", !term.trimmingCharacters(in: .whitespaces).isEmpty {
                terms.append(term)
                term = ""
            }
            term.append(character)
        }
        terms.append(term)
        let powers = terms.compactMap { Parser.expression($0).flatMap { Polynomial($0, in: "x") }.flatMap { $0.coefficients.count == $0.degree + 1 && $0.coefficients.dropLast().allSatisfy(\.isZero) ? $0.degree : nil } }
        return Set(powers).count == powers.count
    }

    /// A linear expression px + q written over one whole number: (3x − 1)/2.
    private static func overOneNumber(_ expr: Expr, _ letter: String) -> Expr {
        guard let line = Polynomial(expr, in: letter), line.degree == 1 else { return Simplify.run(expr) }
        let p = line.coefficient(1), q = line.coefficient(0)
        guard let d = Rational.lcm(p.denominator, q.denominator), d > 1, let top1 = p * Rational(d), let top0 = q * Rational(d) else { return line.expr }
        return .multiply([Polynomial([top0, top1], variable: letter).expr, .power(.integer(d), .minusOne)])
    }

    /// An expression multiplied out where it's a polynomial, simplified where it isn't.
    private static func multipliedOut(_ expr: Expr, _ letter: String) -> Expr {
        Polynomial(expr, in: letter)?.expr ?? Simplify.run(expr)
    }

    /// Exact solutions of an equation in one letter: nil unless it's a polynomial whose real
    /// solutions are all fractions (and there is at least one).
    private static func exactRoots(_ difference: Expr, _ letter: String) -> [Rational]? {
        guard let polynomial = Polynomial(difference, in: letter), (1...6).contains(polynomial.degree) else { return nil }
        let roots = polynomial.rationalRoots
        guard !roots.isEmpty, roots.count == polynomial.realRoots.count else { return nil }
        return roots
    }

    /// "f(x) = 3x − 1, g(x) = 2x + 4. Calculate the value of fg(2)": functions defined in the
    /// question, then evaluated, composed, inverted, put into an equation, or with an unknown
    /// number in them found from a value.
    private static func functions(_ raw: [String], _ text: String) -> Problem? {
        guard has(#"(?<![A-Za-z])[fgh] ?\( ?[x×X] ?\) ?="#, text) else { return nil }
        var lines = functionLines(raw, text)
        // g is often read as 8 (or 9): "8(x) = 4x". Taken as g's rule only where the question
        // names g among its functions, no line gives g's rule, and just one line is like that.
        let named = Set(lines.filter { has(#"\bfunctions?\b"#, $0) && !$0.contains("=") }
            .flatMap { every(#"(?<![A-Za-z])([fgh]) ?\([x×]\)"#, in: $0).map { $0[1].lowercased() } })
        let lookalike = lines.indices.filter { has(#"^[89]\(x\) ?="#, lines[$0]) }
        if named.contains("g"), lookalike.count == 1, !lines.contains(where: { has(#"(?<![A-Za-z])g\(x\) ?="#, $0) }) {
            lines[lookalike[0]] = "g" + lines[lookalike[0]].dropFirst()
        }
        var definitions: [String: Expr] = [:], unreadable: Set<String> = []
        var leftOver: [String] = [], asked: [String] = []
        let queryWords = #"\b(?:solve|find|calculate|work out|express|write|simplify|evaluate|given that|what is)\b"#
        for line in lines {
            let found = every(#"(?<![A-Za-z])([fgh])\(x\) ?= ?(.+?) ?(?:,|;|\band\b(?= ?[fgh]\()|$)"#, in: line)
            guard !found.isEmpty, !has(queryWords, line) else {
                asked.append(line)
                continue
            }
            var rest = line
            for match in found {
                rest = rest.replacingOccurrences(of: match[0], with: " ")
                let name = match[1].lowercased()
                guard definitions[name] == nil, !unreadable.contains(name) else { return nil }
                let written = match[2].trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                if !has(#"[fgh]\("#, written), isWhole(written), let rule = Parser.expression(written), rule.symbols.contains("x"),
                   rule.symbols.allSatisfy({ has("^[a-z]$", $0) }) {
                    definitions[name] = rule
                } else {
                    unreadable.insert(name)
                }
            }
            leftOver.append(rest)
        }
        guard !definitions.isEmpty else { return nil }
        let constants = definitions.values.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }.subtracting(["x"])
        guard constants.count <= 1 else { return nil }
        let question = asked.joined(separator: " ")
        // fg(2) is f(g(2)): the function nearest the bracket first.
        func apply(_ names: String, _ argument: Expr) -> Expr? {
            var value = argument
            for name in names.reversed() {
                guard let rule = definitions[String(name)] else { return nil }
                value = rule.substituting("x", with: value)
            }
            return value
        }
        func composed(_ names: String) -> String {
            names.count == 1 ? "" : "\(names)(…) means \(names.map { "\($0)(" }.joined())…\(String(repeating: ")", count: names.count)): work from the inside out."
        }
        var results: [(used: String, problem: Problem)] = []

        // The inverse: f⁻¹(x).
        if let match = groups(#"\b(?:find|work out|write down|what is|calculate)\s+(?:an expression for\s+)?([fgh]) ?(?:\^ ?\(? ?- ?1 ?\)?|⁻¹|- ?1|- ?'|-) ?\(x\)\.?$"#, in: question),
           constants.isEmpty, let rule = definitions[match[1].lowercased()],
           let back = solved(.add([rule, .multiply([.minusOne, .symbol("y")])]), for: "x") {
            let name = match[1].lowercased()
            let inverse = overOneNumber(back.substituting("y", with: .symbol("x")), "x")
            if same(rule.substituting("x", with: inverse), .symbol("x")) {
                let lead = [Step("Write y = \(name)(x) and make x the subject", "Do the same to both sides until x is on its own.",
                                 [MathLine(.symbol("y"), rule), MathLine(.symbol("x"), overOneNumber(back, "y"))]),
                            Step("Swap the letters", "The inverse takes y back to x: write it with x as the letter.",
                                 [MathLine(.symbol("\(name)⁻¹(x)"), inverse)])]
                results.append((match[0], told("\(name)⁻¹(x)", [MathLine(.symbol("\(name)⁻¹(x)"), inverse)], lead)))
            }
        }

        // An unknown number in a function, from a value: "Given that gf(2) = 34, work out the value of k".
        if let constant = constants.first,
           let given = groups(#"\bgiven (?:that )?([fgh]{1,3})\((-?\d+(?:\.\d+)?)\) ?= ?(-?\d+(?:\.\d+)?)"#, in: question),
           let wanted = groups(#"\b(?:the value of|find|work out|calculate)\s+([a-z])\.?$"#, in: question), wanted[1].lowercased() == constant,
           let at = rational(given[2]), let value = rational(given[3]), let worked = apply(given[1].lowercased(), exact(at)),
           let roots = exactRoots(.add([worked, .multiply([.minusOne, exact(value)])]), constant) {
            let names = given[1].lowercased()
            let lead = [Step("Write \(names)(\(shown(at))) in terms of \(constant)", composed(names).trimmingCharacters(in: .whitespaces),
                             [MathLine(.symbol("\(names)(\(shown(at)))"), worked, multipliedOut(worked, constant))]),
                        Step("Make it equal \(shown(value)) and solve", "",
                             [MathLine(multipliedOut(worked, constant), exact(value))] + roots.map { MathLine(.symbol(constant), exact($0)) })]
            results.append((given[0] + " " + wanted[0], told("value of \(constant)", roots.map { MathLine(.symbol(constant), exact($0)) }, lead)))
        }

        // An equation: "Solve f(x) = 17", "Solve fg(x) = gf(x)", "Solve f⁻¹(x) = gh(x)", "the values of a such that f(a) = g(a)".
        let inverseMark = #"(?:\^ ?\(? ?- ?1 ?\)?|⁻¹)"#
        let side = #"(?:[fgh]{1,3}\([a-z]\)|[fgh] ?\#(inverseMark) ?\([a-z]\)|-?\d+(?:\.\d+)?)"#
        let equations = every(#"(?:\bsolve(?: the equation)?\s+(\#(side) ?= ?\#(side))|(?<![\w(])([fgh]{1,3}\([a-z]\) ?= ?[fgh]{1,3}\([a-z]\)))\.?$"#, in: question)
        if constants.isEmpty, equations.count == 1, case let written = equations[0][1].isEmpty ? equations[0][2] : equations[0][1] {
            let sides = written.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            var worked: [Expr] = [], letters: Set<String> = []
            for piece in sides {
                if let call = groups(#"^([fgh]{1,3})\(([a-z])\)$"#, in: piece) {
                    letters.insert(call[2].lowercased())
                    guard let value = apply(call[1].lowercased(), .symbol(call[2].lowercased())) else { worked = []; break }
                    worked.append(value)
                } else if let call = groups(#"^([fgh]) ?\#(inverseMark) ?\(([a-z])\)$"#, in: piece) {
                    // The inverse of a rule that's linear in x, checked by putting it back in.
                    letters.insert(call[2].lowercased())
                    guard let rule = definitions[call[1].lowercased()], let back = solved(.add([rule, .multiply([.minusOne, .symbol("y")])]), for: "x"),
                          same(rule.substituting("x", with: back), .symbol("y")) else { worked = []; break }
                    worked.append(back.substituting("y", with: .symbol(call[2].lowercased())))
                } else if let number = rational(piece) {
                    worked.append(exact(number))
                }
            }
            if worked.count == 2, letters.count == 1, let letter = letters.first,
               let roots = exactRoots(.add([worked[0], .multiply([.minusOne, worked[1]])]), letter) {
                let lead = [Step("Write out each side", "Put each function's rule in, working from the inside out.",
                                 [MathLine(multipliedOut(worked[0], letter), multipliedOut(worked[1], letter))]),
                            Step("Solve the equation", "", roots.map { MathLine(.symbol(letter), exact($0)) })]
                results.append((equations[0][0], told("solve \(written)", roots.map { MathLine(.symbol(letter), exact($0)) }, lead)))
            }
        }

        // A value: "Calculate the value of fg(2)", "Find f(7)".
        if constants.isEmpty, let match = groups(#"\b(?:the value of|find|calculate|work out|write down|what is|evaluate)\s+([fgh]{1,3})\((-?\d+(?:\.\d+)?)\)\.?$"#, in: question),
           let at = rational(match[2]), let worked = apply(match[1].lowercased(), exact(at)),
           case .number(.exact(let value)) = Simplify.run(worked) {
            let names = match[1].lowercased()
            var steps: [MathLine] = []
            var inside = exact(at)
            for name in names.reversed() {
                guard let next = apply(String(name), inside) else { return nil }
                let result = Simplify.run(next)
                steps.append(MathLine(.symbol("\(name)(\(Format.text(inside)))"), next, result))
                inside = result
            }
            let lead = [Step("Put \(shown(at)) into the rule", composed(names).trimmingCharacters(in: .whitespaces), steps)]
            results.append((match[0], told("\(names)(\(shown(at)))", [MathLine(exact(value))], lead)))
        }

        // Inverse values and sums of values: "Find g⁻¹(4)", "Work out the value of f⁻¹(3) + f(−0.5)".
        let call = #"([fgh]{1,3})( ?(?:\^ ?\(? ?- ?1 ?\)?|⁻¹|- ?1|- ?'|-))? ?\((-?\d+(?:\.\d+)?)\)"#
        if constants.isEmpty, results.isEmpty,
           let match = groups(#"\b(?:the value of|find|calculate|work out|write down|what is|evaluate)\s+((?:[-+×*/÷() ]|\d|\.|[fgh⁻¹^'])+)\.?$"#, in: question),
           has(call, match[1]), has(#"⁻¹|\^|-'|[+×*/÷]|\) ?-"#, match[1]) || every(call, in: match[1]).count > 1 {
            var written = match[1]
            var steps: [MathLine] = []
            for found in every(call, in: match[1]) {
                guard let at = rational(found[3]) else { return nil }
                let names = found[1].lowercased()
                var value: Rational
                if !found[2].isEmpty {
                    // An inverse: the x that the function takes to this value.
                    guard names.count == 1, let rule = definitions[names], let x = solved(.add([rule, exact(at.negated)]), for: "x"),
                          case .number(.exact(let back)) = Simplify.run(x) else { return nil }
                    value = back
                    steps.append(MathLine(.symbol("\(names)⁻¹(\(shown(at)))"), exact(back)))
                } else {
                    guard let worked = apply(names, exact(at)), case .number(.exact(let v)) = Simplify.run(worked) else { return nil }
                    value = v
                    steps.append(MathLine(.symbol("\(names)(\(shown(at)))"), exact(v)))
                }
                written = written.replacingOccurrences(of: found[0], with: "(\(shown(value)))")
            }
            if let sum = Parser.expression(written), sum.symbols.isEmpty, case .number(.exact(let total)) = Simplify.run(sum) {
                let shownTotal = has(#"\d\.\d"#, match[1]) ? decimal(total) : exact(total)
                let lead = [Step("Work out each value", "For an inverse, find the x that the function takes to that number.", steps),
                            Step("Put them together", "", [MathLine(.symbol(match[1].trimmingCharacters(in: .whitespaces)), shownTotal)])]
                results.append((match[0], told(match[1].trimmingCharacters(in: .whitespaces), [MathLine(shownTotal)], lead)))
            }
        }

        // An expression: "Find fg(x)", "Express f(2x − 1) in the form ax² + bx + c".
        if constants.isEmpty, let match = groups(#"\b(?:find|work out|write down|express|simplify|write)\s+(?:an expression for\s+)?([fgh]{1,3})\(([^()]*(?:\([^()]*\))?[^()]*)\)(?:\s+in the form\s+(.+?))?\.?$"#, in: question),
           let argument = Parser.expression(match[2]), argument.symbols == ["x"], match[1].count > 1 || argument != .symbol("x"),
           let worked = apply(match[1].lowercased(), argument) {
            let names = match[1].lowercased()
            let result = multipliedOut(worked, "x")
            let form = match[3]
            // The form asked for says how high the power is: ax² + bx + c is a quadratic.
            let fits = form.isEmpty || Polynomial(result, in: "x").map { $0.degree == (has(#"x ?(?:\^ ?2|²)"#, form) ? 2 : 1) } == true
            if fits, same(result, worked) {
                let label = "\(names)(\(Format.text(argument)))"
                let lead = [Step("Put \(Format.text(argument)) in for x", composed(names).trimmingCharacters(in: .whitespaces),
                                 [MathLine(.symbol(label), worked)]),
                            Step("Multiply out and collect like terms", "", [MathLine(.symbol(label), result)])]
                results.append((match[0], told(label, [MathLine(.symbol(label), result)], lead)))
            }
        }

        guard results.count == 1, let (used, problem) = results.first else { return nil }
        // Every number is in a function's rule or in what's asked.
        var rest = (leftOver + [question]).joined(separator: " ")
        rest = rest.replacingOccurrences(of: used, with: " ")
        if let given = groups(#"\bgiven (?:that )?[fgh]{1,3}\(-?\d+(?:\.\d+)?\) ?= ?-?\d+(?:\.\d+)?"#, in: rest) { rest = rest.replacingOccurrences(of: given[0], with: " ") }
        guard numbers(in: rest).isEmpty else { return nil }
        return problem
    }

    // MARK: Unknowns from facts

    /// Answers that go together, on one line: "a = 6, b = −15" (separate lines would read as "or").
    private static func together(_ pairs: [(String, Expr)]) -> MathLine {
        pairs.count == 1 ? MathLine(.symbol(pairs[0].0), pairs[0].1) : MathLine(.symbol(pairs.map { "\($0.0) = \(Format.text($0.1))" }.joined(separator: ", ")))
    }

    /// A square set of linear equations, solved exactly: each row the coefficients, then the
    /// number on the other side. Nil unless there is exactly one solution.
    private static func solveLinear(_ rows: [[Rational]]) -> [Rational]? {
        var m = rows
        let n = m.count
        guard n > 0, m.allSatisfy({ $0.count == n + 1 }) else { return nil }
        for column in 0..<n {
            guard let pivot = (column..<n).first(where: { !m[$0][column].isZero }) else { return nil }
            m.swapAt(column, pivot)
            for row in 0..<n where row != column && !m[row][column].isZero {
                guard let factor = m[row][column] / m[column][column] else { return nil }
                for k in column...n {
                    guard let product = factor * m[column][k], let difference = m[row][k] - product else { return nil }
                    m[row][k] = difference
                }
            }
        }
        let values = (0..<n).compactMap { m[$0][n] / m[$0][$0] }
        return values.count == n ? values : nil
    }

    /// The coefficients of an expression that is linear in `letters`, then its number part. Nil if it isn't linear.
    private static func linearRow(_ expr: Expr, _ letters: [String]) -> [Rational]? {
        func at(_ values: [Rational]) -> Rational? {
            var put = expr
            for (letter, value) in zip(letters, values) { put = put.substituting(letter, with: exact(value)) }
            guard case .number(.exact(let result)) = Simplify.run(put) else { return nil }
            return result
        }
        let zero = letters.map { _ in Rational(0) }
        guard let constant = at(zero) else { return nil }
        var row: [Rational] = []
        for index in letters.indices {
            var unit = zero
            unit[index] = Rational(1)
            guard let value = at(unit), let coefficient = value - constant else { return nil }
            row.append(coefficient)
        }
        // Linear: the same at another point.
        let trial = letters.indices.map { Rational($0 * 3 + 2) }
        guard let whole = at(trial) else { return nil }
        var expected = constant
        for (c, v) in zip(row, trial) {
            guard let term = c * v, let sum = expected + term else { return nil }
            expected = sum
        }
        return whole == expected ? row + [constant] : nil
    }

    private static let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
                                   "eleventh": 11, "twelfth": 12, "fifteenth": 15, "twentieth": 20, "fiftieth": 50, "hundredth": 100]

    private static func ordinalName(_ k: Int) -> String {
        let suffix = (11...13).contains(k % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][k % 10] ?? "th"
        return "\(k)\(suffix)"
    }

    private static func position(_ word: String) -> Int? {
        ordinals[word.lowercased()] ?? groups(#"^(\d{1,3})(?:st|nd|rd|th)$"#, in: word).flatMap { Int($0[1]) }
    }

    /// "The nth term of a sequence is given by an² + bn. The third term is 9 and the sixth term
    /// is 126. Find the value of a and the value of b." Or the term the facts lead to.
    private static func sequenceUnknowns(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bnth term\b"#, text) else { return nil }
        let ordinal = #"(\d{1,3}(?:st|nd|rd|th)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|fifteenth|twentieth|fiftieth|hundredth)"#
        // The rule: after "is given by", or a line of its own.
        var rules: [String] = []
        for line in lines {
            if let after = groups(#"\bnth term (?:of (?:a|the|another|this) (?:quadratic )?sequence )?(?:is|can be written as|has the form|is of the form)(?: given by)? (.+?)(?: where\b.*)?\.?$"#, in: line), has("n", after[1]), !has(#"[a-z]{3,}"#, after[1]) {
                rules.append(after[1])
            } else if has(#"^[a-z0-9^²³+\-*/ ()]+$"#, line), has("n", line), !has(#"[a-z]{3,}"#, line) {
                rules.append(line)
            }
        }
        guard rules.count == 1, let rule = Parser.expression(rules[0].replacingOccurrences(of: "²", with: "^2").replacingOccurrences(of: "³", with: "^3")),
              rule.symbols.contains("n") else { return nil }
        let unknowns = rule.symbols.subtracting(["n"]).sorted()
        guard (1...3).contains(unknowns.count), unknowns.allSatisfy({ $0.count == 1 }) else { return nil }
        var facts = every(#"\b(?:the )?\#(ordinal) term(?: of (?:the|this) sequence)? is (-?\d+(?:\.\d+)?)"#, in: text)
        // Or the terms written in a row: the first ones give the equations, the rest must fit.
        var known: [(k: Int, value: Rational)] = facts.compactMap { f in position(f[1]).flatMap { k in rational(f[2]).map { (k, $0) } } }
        var check: [(k: Int, value: Rational)] = []
        if facts.isEmpty, let terms = row(lines), terms.count >= unknowns.count, terms.allSatisfy({ $0 != nil }),
           let rowLine = lines.first(where: { numbers(in: $0).count == terms.count && has(#"^[-\d ,.]+$"#, $0) }) {
            let all = terms.enumerated().map { (k: $0.offset + 1, value: $0.element!) }
            known = Array(all.prefix(unknowns.count))
            check = Array(all.dropFirst(unknowns.count))
            facts = [[rowLine, ordinalName(1), ""]]
        }
        guard known.count == unknowns.count else { return nil }
        var rows: [[Rational]] = []
        var given: [MathLine] = []
        for fact in known {
            guard let row = linearRow(rule.substituting("n", with: .integer(fact.k)), unknowns), let right = fact.value - row.last! else { return nil }
            rows.append(Array(row.dropLast()) + [right])
            given.append(MathLine(Simplify.run(rule.substituting("n", with: .integer(fact.k))), exact(fact.value)))
        }
        guard let values = solveLinear(rows) else { return nil }
        for extra in check {
            var put = rule.substituting("n", with: .integer(extra.k))
            for (letter, value) in zip(unknowns, values) { put = put.substituting(letter, with: exact(value)) }
            guard case .number(.exact(let v)) = Simplify.run(put), v == extra.value else { return nil }
        }
        var found = rule
        for (letter, value) in zip(unknowns, values) { found = found.substituting(letter, with: exact(value)) }
        let foundRule = Polynomial(found, in: "n")?.expr ?? Simplify.run(found)
        var lead = [Step("Put each term's position in for n", "The \(known.map { "\(ordinalName($0.k)) term" }.joined(separator: " and ")) give \(unknowns.count == 1 ? "an equation" : "equations") in \(unknowns.joined(separator: " and ")).", given),
                    Step("Solve \(unknowns.count == 1 ? "it" : "them together")", "", zip(unknowns, values).map { MathLine(.symbol($0), exact($1)) })]
        // What's asked: the letters, or a term.
        var used = facts.map(\.[0])
        if let term = groups(#"\b(?:find|work out|write down|calculate|what is) the \#(ordinal) term\b"#, in: text), let k = position(term[1]),
           case .number(.exact(let value)) = Simplify.run(found.substituting("n", with: .integer(k))) {
            used.append(term[0])
            guard numbers(in: used.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }.replacingOccurrences(of: rules[0], with: " ")).isEmpty else { return nil }
            lead.append(Step("Find the \(term[1]) term", "", [MathLine(.symbol("nth term"), foundRule), MathLine(.symbol("\(term[1]) term"), exact(value))]))
            return told("\(term[1]) term", [MathLine(exact(value))], lead)
        }
        guard askedLetters(text) == Set(unknowns),
              numbers(in: used.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }.replacingOccurrences(of: rules[0], with: " ")).isEmpty else { return nil }
        return told("values of \(unknowns.joined(separator: " and "))", [together(zip(unknowns, values).map { ($0, exact($1)) })], lead)
    }

    /// "Bennie is 7 years older than Ayesha. Chloe is twice as old as Bennie. The sum of their
    /// three ages is 57. Work out the ages of Ayesha, Bennie and Chloe." Ages or amounts that
    /// people have, linked by sentences, with their total.
    private static func linkedAmounts(_ text: String) -> Problem? {
        let sentences = text.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: #"[.?!](?!\d)"#, with: "\u{1}", options: .regularExpression)
            .replacingOccurrences(of: #" (?=(?:Work out|Find|Calculate|How (?:many|much|old))\b)"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let name = #"([A-Z][a-z]+)"#
        var names: [String] = []
        func index(_ person: String) -> Int {
            if let at = names.firstIndex(of: person) { return at }
            names.append(person)
            return names.count - 1
        }
        // Each relation as: this person = factor × that person + amount.
        var links: [(person: Int, factor: Rational, other: Int, amount: Rational, written: String)] = []
        var total: (value: Rational, written: String)?
        var asked: [String] = []
        var isAges = false, isMoney = false
        var ratioAsked: (first: String, second: String, letter: String, written: String)?
        func times(_ word: String) -> Rational? {
            switch word.lowercased() {
            case "twice", "double": return Rational(2)
            case "half": return Rational.make(1, 2)
            case "three times", "treble", "triple": return Rational(3)
            default: return groups(#"^(\w+) times$"#, in: word).flatMap { count($0[1]) }.map { Rational($0) }
            }
        }
        for sentence in sentences {
            if let older = groups(#"^\#(name) is (\d+|\w+) years? (older|younger) than \#(name)$"#, in: sentence), let k = count(older[2]) {
                isAges = true
                links.append((index(older[1]), Rational(1), index(older[4]), Rational(older[3].lowercased() == "older" ? k : -k), sentence))
            } else if let old = groups(#"^\#(name) is (twice|double|half|three times|\w+ times) as old as \#(name)$"#, in: sentence), let factor = times(old[2]) {
                isAges = true
                links.append((index(old[1]), factor, index(old[3]), Rational(0), sentence))
            } else if let more = groups(#"^\#(name) has (£?)(\d+(?:\.\d+)?|\w+)(?: \w+)? (more|fewer|less)(?: \w+)? than \#(name)$"#, in: sentence),
                      let k = rational(more[3]) ?? count(more[3]).map({ Rational($0) }) {
                if !more[2].isEmpty { isMoney = true }
                links.append((index(more[1]), Rational(1), index(more[5]), more[4].lowercased() == "more" ? k : k.negated, sentence))
            } else if let many = groups(#"^\#(name) has (twice|double|half|three times|\w+ times) as (?:many|much)(?: \w+)? as \#(name)$"#, in: sentence),
                      let factor = times(many[2]) {
                links.append((index(many[1]), factor, index(many[3]), Rational(0), sentence))
            } else if let sum = groups(#"^(?:the (?:sum|total) of their (?:\w+ )?(?:ages|amounts?|money) is|their (?:\w+ )?ages add up to|(?:altogether|in total),? they have|they have) (£?)(\d+(?:\.\d+)?)(?: \w+)?(?: (?:altogether|in total))?$"#, in: sentence),
                      let value = rational(sum[2]), total == nil {
                if !sum[1].isEmpty { isMoney = true }
                total = (value, sentence)
            } else if let question = groups(#"^(?:work out|find|calculate|what are) (?:the (?:ages?|amounts?) of|how (?:old|much|many \w+) (?:each of )?)(.+)$"#, in: sentence) {
                asked = every(#"\b([A-Z][a-z]+)\b"#, in: question[1]).map { $0[1] }.filter { $0.first!.isUppercase }
            } else if let one = groups(#"^how old is \#(name)$"#, in: sentence) ?? groups(#"^(?:work out|find|calculate) the number of \w+ (?:that )?\#(name) has$"#, in: sentence)
                        ?? groups(#"^how many \w+ (?:does|did) \#(name) have$"#, in: sentence) {
                asked = [one[1]]
            } else if numbers(in: sentence).isEmpty, has(#"^(?:[A-Z][a-z]+, )*[A-Z][a-z]+ and [A-Z][a-z]+ (?:are|were|have|each have)\b"#, sentence) {
                // Who's in it: "Rick, Selma and Tony are playing a game with counters."
                continue
            } else if let base = groups(#"^\#(name) has (?:some|a number of|x) \w+$"#, in: sentence) {
                _ = index(base[1])
            } else if let pair = groups(#"^the number of \w+ \#(name) has ?: ?the number of \w+ \#(name) has ?= ?1 ?: ?([a-z])$"#, in: sentence) {
                ratioAsked = (pair[1], pair[2], pair[3].lowercased(), sentence)
            } else if let letter = groups(#"^(?:work out|find) the value of ([a-z])$"#, in: sentence), ratioAsked?.letter == letter[1].lowercased() {
                asked = [ratioAsked!.first]
            } else {
                return nil
            }
        }
        guard let total, !links.isEmpty, !asked.isEmpty, names.count == links.count + 1, Set(asked).isSubset(of: Set(names)) else { return nil }
        // One equation for each link, and the total.
        var rows: [[Rational]] = []
        for link in links {
            var row = names.map { _ in Rational(0) } + [link.amount]
            row[link.person] = Rational(1)
            guard let minus = (row[link.other] - link.factor) else { return nil }
            row[link.other] = minus
            rows.append(row)
        }
        rows.append(names.map { _ in Rational(1) } + [total.value])
        guard let values = solveLinear(rows), values.allSatisfy({ $0 > Rational(0) }), isMoney || values.allSatisfy(\.isInteger) else { return nil }
        // Every number is in a link or the total.
        let rest = (links.map(\.written) + [total.written] + [ratioAsked?.written ?? "#"]).reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }
        guard numbers(in: rest).isEmpty else { return nil }
        func amount(_ value: Rational) -> Expr { isMoney ? .symbol("£" + (value.isInteger ? shown(value) : String(format: "%.2f", value.double))) : exact(value) }
        let baseIndex = (0..<names.count).first { i in !links.contains { $0.person == i } } ?? 0
        let base = names[baseIndex]
        // Everyone in terms of x, following the links out from the one no sentence describes.
        var inTermsOfX: [Int: Expr] = [baseIndex: .symbol("x")]
        for _ in 0..<names.count {
            for link in links {
                if inTermsOfX[link.person] == nil, let other = inTermsOfX[link.other] {
                    inTermsOfX[link.person] = Simplify.run(.add([.multiply([exact(link.factor), other]), exact(link.amount)]))
                } else if inTermsOfX[link.other] == nil, let person = inTermsOfX[link.person], let back = Rational(1) / link.factor {
                    inTermsOfX[link.other] = Simplify.run(.multiply([exact(back), .add([person, exact(link.amount.negated)])]))
                }
            }
        }
        var lead: [Step]
        if inTermsOfX.count == names.count {
            let sum = Polynomial(.add(names.indices.map { inTermsOfX[$0]! }), in: "x")?.expr ?? .symbol("x")
            lead = [Step("Write everyone in terms of \(base)", "Call \(base)'s \(isAges ? "age" : "amount") x and follow the sentences.",
                         names.indices.map { MathLine(.symbol(names[$0]), inTermsOfX[$0]!) }),
                    Step("The total gives an equation", "Add them up and make it equal \(shown(total.value)).",
                         [MathLine(sum, exact(total.value)), MathLine(.symbol("x"), exact(values[baseIndex]))]),
                    Step("Work out each one", "", names.indices.map { MathLine(.symbol(names[$0]), amount(values[$0])) })]
        } else {
            lead = [Step("Write the sentences as equations and solve them", "", links.map { MathLine(.symbol($0.written)) }),
                    Step("Work out each one", "", names.indices.map { MathLine(.symbol(names[$0]), amount(values[$0])) })]
        }
        if let ratioAsked, let i = names.firstIndex(of: ratioAsked.first), let j = names.firstIndex(of: ratioAsked.second) {
            // "Rick's : Tony's = 1 : p": p is Tony's over Rick's.
            guard let p = values[j] / values[i] else { return nil }
            lead.append(Step("Write it as 1 : \(ratioAsked.letter)", "Divide both sides of \(shown(values[i])) : \(shown(values[j])) by \(shown(values[i])).",
                             [MathLine(.symbol(ratioAsked.letter), decimal(p))]))
            return told("value of \(ratioAsked.letter)", [MathLine(.symbol(ratioAsked.letter), decimal(p))], lead)
        }
        return told(isAges ? "ages" : "amounts", [together(asked.map { person in (person, amount(values[names.firstIndex(of: person)!])) })], lead)
    }

    /// "The ratio of Marta's hourly pay to Khalid's hourly pay is 6 : 5. Both get an increase of
    /// £1.50. The ratio after this increase is 13 : 11. Work out the hourly pay before the increase."
    private static func ratioAfterChange(_ text: String) -> Problem? {
        let plain = text.replacingOccurrences(of: "’", with: "'")
        let ratios = every(#"\bratio of (?:([A-Z][a-z]+)'s )?(.*?) to (?:([A-Z][a-z]+)'s )?(.*?) (?:\w+ )*?is (\d+) ?: ?(\d+)"#, in: plain)
        guard ratios.count == 2, has(#"\b(?:both|each)\b"#, plain),
              let change = groups(#"\b(?:an? )?(increase|rise|decrease|reduction|cut) (?:in \w+(?: \w+)? )?of (£?)(\d+(?:\.\d+)?)"#, in: plain),
              let k0 = rational(change[3]), let p = Int(ratios[0][5]), let q = Int(ratios[0][6]), let r = Int(ratios[1][5]), let s = Int(ratios[1][6]),
              !ratios[0][1].isEmpty, !ratios[0][3].isEmpty, ratios[0][1] == ratios[1][1], ratios[0][3] == ratios[1][3], ratios[0][1] != ratios[0][3] else { return nil }
        let k = ["increase", "rise"].contains(change[1].lowercased()) ? k0 : k0.negated
        // (pt + k) : (qt + k) = r : s, so t(sp − rq) = k(r − s).
        let bottom = Rational(s * p - r * q)
        guard !bottom.isZero, let top = k * Rational(r - s), let t = top / bottom, t > Rational(0),
              let before1 = Rational(p) * t, let before2 = Rational(q) * t, let after1 = before1 + k, let after2 = before2 + k,
              after1 > Rational(0), after2 > Rational(0) else { return nil }
        // Every number is in the ratios or the change.
        let rest = ([ratios[0][0], ratios[1][0], change[0]]).reduce(plain) { $0.replacingOccurrences(of: $1, with: " ") }
        guard numbers(in: rest).isEmpty else { return nil }
        let isMoney = !change[2].isEmpty
        func amount(_ value: Rational) -> Expr { isMoney ? .symbol("£" + (value.isInteger ? shown(value) : String(format: "%.2f", value.double))) : (value.isInteger ? exact(value) : decimal(value)) }
        // What's asked, in the question's own sentence: the amounts before the change, or after it.
        guard let question = every(#"\b(?:work out|find|calculate|what (?:is|was|were|are))\b[^.?]*"#, in: plain).last?[0] else { return nil }
        let wantsBefore = has(#"\b(?:before|originally|at first|to start with)\b"#, question), wantsAfter = has(#"\b(?:after|now)\b"#, question)
        guard wantsBefore != wantsAfter else { return nil }
        let first = ratios[0][1], second = ratios[0][3]
        let changeText = k0.isInteger ? shown(k0) : String(format: "%g", k0.double)
        let lead = [Step("Write them as \(p)t and \(q)t", "Before the change they're in the ratio \(p) : \(q), so call them \(p)t and \(q)t.",
                         [MathLine(.symbol("(\(p)t \(k > Rational(0) ? "+" : "−") \(changeText)) : (\(q)t \(k > Rational(0) ? "+" : "−") \(changeText))"), .symbol("\(r) : \(s)"))]),
                    Step("Cross-multiply and solve", "\(s)(\(p)t \(k > Rational(0) ? "+" : "−") \(changeText)) = \(r)(\(q)t \(k > Rational(0) ? "+" : "−") \(changeText))",
                         [MathLine(.symbol("t"), exact(t))]),
                    Step(wantsAfter ? "Work out each one after the change" : "Work out each one", "",
                         [MathLine(.symbol(first), amount(wantsAfter ? after1 : before1)), MathLine(.symbol(second), amount(wantsAfter ? after2 : before2))])]
        return told(wantsAfter ? "after the change" : "before the change",
                    [together([(first, amount(wantsAfter ? after1 : before1)), (second, amount(wantsAfter ? after2 : before2))])], lead)
    }

    /// "Circle the expression that is equivalent to 3x²/(6x² + 3)", with the choices under it
    /// (and the expression read above the sentence, as it often is).
    private static func equivalentChoice(_ lines: [String]) -> Problem? {
        guard let askedAt = lines.firstIndex(where: { has(#"\b(?:circle|choose|which is|write down) (?:the )?(?:e[x×]pression|one) (?:that is )?equivalent to\b"#, $0) }) else { return nil }
        func isMaths(_ line: String) -> Bool { !has(#"[a-z]{3,}"#, line) && !has(#"^\d{1,2}$"#, line) && !line.contains("=") }
        var targets: [String] = []
        if let after = groups(#"equivalent to:? (.+?)\.?$"#, in: lines[askedAt]) { targets.append(after[1]) }
        targets += lines[..<askedAt].filter(isMaths)
        var after = lines[(askedAt + 1)...].filter(isMaths)
        // Printed beside the sentence, the expression can come out just after it, before the choices.
        if targets.isEmpty, after.count >= 3 { targets = [after.removeFirst()] }
        guard targets.count == 1, let target = Parser.expression(targets[0]), !target.symbols.isEmpty else { return nil }
        let written = after.flatMap { choices($0) }
        let parsed = written.compactMap { Parser.expression($0) }
        // Every choice read, and one, only one, the same whatever the letters are.
        guard written.count >= 2, parsed.count == written.count else { return nil }
        let matching = parsed.filter { same($0, target) }
        guard matching.count == 1, let chosen = matching.first, Set(chosen.symbols) == Set(target.symbols) else { return nil }
        let lead = [Step("Simplify \(Format.text(target)) or test each choice", "Only one choice has the same value as \(Format.text(target)) whatever \(target.symbols.sorted().joined(separator: " and ")) is.",
                         [MathLine(target, chosen)])]
        return told("equivalent expression", [MathLine(chosen)], lead)
    }

    // MARK: Factorising with an unknown

    /// "A quadratic expression, 3x² + ax + 10, can be factorised. Find all possible values for a."
    /// Factorised means into two brackets with whole numbers: (px + q)(rx + s).
    private static func factorisableCoefficient(_ text: String) -> Problem? {
        guard has(#"\bcan be factori[sz]ed\b|\bfactori[sz]es\b"#, text),
              let asked = groups(#"\b(?:all )?(?:the )?(?:possible )?values? (?:for|of) ([a-z])\b"#, in: text)?[1].lowercased(),
              let found = groups(#"(?<![\w.])(\d*) ?x(?:\^ ?2|²) ?([+-]) ?([a-z]) ?x ?([+-]) ?(\d+)(?![\d.])"#, in: text),
              found[3].lowercased() == asked, let a = found[1].isEmpty ? 1 : Int(found[1]), let c0 = Int(found[5]),
              (1...100).contains(a), (1...1000).contains(c0) else { return nil }
        let c = found[4] == "-" ? -c0 : c0
        // Every number is in the expression (or the question's own number).
        let plain = text.replacingOccurrences(of: #"(?i)^question \d+:?"#, with: "", options: .regularExpression)
        guard numbers(in: plain.replacingOccurrences(of: found[0], with: " ")).isEmpty else { return nil }
        var values = Set<Int>()
        for p in 1...a where a % p == 0 {
            let r = a / p
            for q in 1...c0 where c0 % q == 0 {
                for signed in [q, -q] { values.insert(p * (c / signed) + signed * r) }
            }
        }
        let positiveOnly = has(#"\bpositive\b"#, text) && !has(#"\bnegative\b"#, text)
        let negativeOnly = has(#"\bnegative\b"#, text) && !has(#"\bpositive\b"#, text)
        let kept = values.filter { positiveOnly ? $0 > 0 : negativeOnly ? $0 < 0 : true }.sorted { abs($0) != abs($1) ? abs($0) < abs($1) : $0 < $1 }
        guard !kept.isEmpty, kept.count <= 24 else { return nil }
        let both = !positiveOnly && !negativeOnly && kept.allSatisfy { kept.contains(-$0) }
        let listed = both ? kept.filter { $0 > 0 }.map { $0 == 0 ? "0" : "±\($0)" } : kept.map { Format.number(.integer($0)) }
        let pairs = (1...c0).filter { c0 % $0 == 0 }.map { "\($0) × \(c / $0)" }
        let lead = [Step("Write it as two brackets", "(px + q)(rx + s) multiplies out to prx² + (ps + qr)x + qs, so pr = \(a) and qs = \(c), and \(asked) is ps + qr.",
                         [MathLine(.symbol("\(a == 1 ? "" : String(a))x² + \(asked)x \(c < 0 ? "−" : "+") \(c0)"), .symbol("(px + q)(rx + s)"))]),
                    Step("Try every way of making \(a) and \(c)", "Pairs for qs: \(pairs.joined(separator: ", ")), and each the other way round with the signs swapped. Each gives a value of \(asked).",
                         [MathLine(.symbol(asked), .symbol(listed.joined(separator: ", ")))])]
        return told("possible values of \(asked)", [MathLine(.symbol(asked), .symbol(listed.joined(separator: ", ")))], lead)
    }

    // MARK: Iteration

    private static let iterationCounts: [String: Int] = ["once": 1, "twice": 2, "three times": 3, "four times": 4, "five times": 5, "six times": 6]

    /// A decimal to 5 places, as an iteration's values are written.
    private static func fivePlaces(_ value: Double) -> Expr {
        let rounded = (value * 100_000).rounded() / 100_000
        if abs(rounded - rounded.rounded()) < 1e-12 { return .integer(Int(rounded.rounded())) }
        return .number(.real(rounded))
    }

    private static func subscripted(_ n: Int) -> String {
        "x" + String(n).map { ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"][Int(String($0))!] }.joined()
    }

    /// "Starting with x₀ = 2, use the iteration formula xₙ₊₁ = ∛(7 − xₙ) three times to find an
    /// estimate for a solution of x³ + x = 7", "Using xₙ₊₁ = …, with x₀ = 1, find the values of x₁, x₂ and x₃".
    /// Where the equation is given, the formula has to fit it: a formula misread fits it only by chance.
    private static func iteration(_ text: String) -> Problem? {
        // xₙ₊₁ as written, or with its n lost after "iteration formula": "X+1 =".
        guard let formula = groups(#"\bx ?(?:n ?\+ ?1|_\{?n ?\+ ?1\}?|ₙ₊₁) ?= ?(.+?)(?= (?:twice|once|(?:two|three|four|five|six|\d+) times|with|to find|starting|and find|find)\b|,|$)"#, in: text)
                ?? groups(#"\biteration formula x ?\+ ?1 ?= ?(.+?)(?= (?:twice|once|(?:two|three|four|five|six|\d+) times|with|to find|starting|and find|find)\b|,|$)"#, in: text) else { return nil }
        let written = formula[1].lowercased().replacingOccurrences(of: #"x ?n(?![a-z])|x_\{?n\}?|xₙ"#, with: "x", options: .regularExpression)
        let literal = Parser.expression(written).flatMap { $0.symbols == ["x"] ? $0 : nil }
        guard let start = (groups(#"\bx ?(?:0|o|₀|_\{?0\}?) ?= ?(-?\d+(?:\.\d+)?)"#, in: text) ?? groups(#"\bstarting with x ?= ?(-?\d+(?:\.\d+)?)"#, in: text)).flatMap({ rational($0[1]) }) else { return nil }
        // How many times: "three times", "twice", or the values asked for, "x₁, x₂ and x₃".
        var times: Int?, listAll = false
        if let asked = groups(#"\bvalues? of ((?:x ?_?\{?\d\}?|x[₁-₉])(?: ?,? ?(?:and )?(?:x ?_?\{?\d\}?|x[₁-₉]))*)"#, in: text) {
            let indices = every(#"x ?_?\{?(\d)\}?|x([₁-₉])"#, in: asked[1]).compactMap { match -> Int? in
                if !match[1].isEmpty { return Int(match[1]) }
                return ["₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"].firstIndex(of: match[2]).map { $0 + 1 }
            }
            guard let last = indices.last, indices == Array(1...last) else { return nil }
            times = last
            listAll = true
        }
        for (words, n) in iterationCounts where has("\\b\(words)\\b", text) {
            guard times == nil || times == n else { return nil }
            times = n
        }
        if times == nil, let digits = groups(#"\b(\d) times\b"#, in: text) { times = Int(digits[1]) }
        guard let times, (1...8).contains(times) else { return nil }
        // The equation it's for, where one is given: one of its solutions has to stay put under the formula.
        var rule: Expr
        if let equation = groups(#"\b(?:solution|root|roots) (?:of|to) (?:the equation )?(.+?=.+?)(?=\.| in the\b| between\b|,|$)"#, in: text) {
            let sides = equation[1].split(separator: "=").map(String.init)
            guard sides.count == 2, let left = Parser.expression(sides[0]), let right = Parser.expression(sides[1]),
                  let polynomial = Polynomial(.add([left, .multiply([.minusOne, right])]), in: "x") else { return nil }
            func fits(_ formula: Expr) -> Bool {
                polynomial.realRoots.contains { root in formula.evaluate(["x": root]).map { abs($0 - root) < 1e-6 } ?? false }
            }
            if let literal, fits(literal) {
                rule = literal
            } else {
                // What reading loses: a cube root's small 3, leaving √ or a stray mark ("√(ỷ7 − xn)");
                // the line over what's under a root sign at the end ("√ 3xn + 11"); a small power
                // on xₙ ("(Xn)/9" for xₙ³/9, "(xỉ)/2"). Read that way only when exactly one such
                // reading, and not what was read, fits the equation.
                let unmarked = written.replacingOccurrences(of: #"(?<=√\()[^\x00-\x7F√∛](?=\d)|(?<=x)[^\x00-\x7F√∛]"#, with: "", options: .regularExpression)
                let covered = unmarked.replacingOccurrences(of: #"√ ?([^()]+)$"#, with: "√($1)", options: .regularExpression)
                var readings = [written, unmarked, covered].flatMap { [$0, $0.replacingOccurrences(of: "√", with: "∛")] }
                for reading in readings where reading.filter({ $0 == "x" }).count == 1 {
                    readings += (2...4).map { reading.replacingOccurrences(of: "x", with: "(x^\($0))") }
                }
                var fitting: [Expr] = []
                for reading in readings {
                    guard let formula = Parser.expression(reading), formula.symbols == ["x"], fits(formula),
                          !fitting.contains(where: { same($0, formula) }) else { continue }
                    fitting.append(formula)
                }
                guard fitting.count == 1, let meant = fitting.first else { return nil }
                rule = meant
            }
        } else {
            guard let literal else { return nil }
            rule = literal
        }
        var values = [start.double]
        for _ in 0..<times {
            guard let next = rule.evaluate(["x": values.last!]), next.isFinite else { return nil }
            values.append(next)
        }
        let lines = (1...times).map { MathLine(.symbol(subscripted($0)), rule.substituting("x", with: fivePlaces(values[$0 - 1])), fivePlaces(values[$0])) }
        let lead = [Step("Put x₀ = \(shown(start)) into the formula", "Each answer goes back in to give the next one. Keep every digit on the calculator (the Ans key) as you go.", lines)]
        let answers = [together((listAll ? Array(1...times) : [times]).map { (subscripted($0), fivePlaces(values[$0])) })]
        return told(listAll ? "values of x₁ to \(subscripted(times))" : "\(subscripted(times)) after \(times) iteration\(times == 1 ? "" : "s")", answers, lead)
    }

    /// "Find, to 2 decimal places, the root of x³ − 2x² + 19 = 0 in the interval (−3, −2)",
    /// where no formula is given to use a set number of times.
    private static func rootInInterval(_ text: String) -> Problem? {
        guard has(#"\b(?:root|solution)\b"#, text), !has(#"\b(?:twice|once|times)\b|\bx ?(?:n ?\+ ?1|ₙ₊₁)"#, text),
              let interval = groups(#"\binterval \( ?(-?\d+(?:\.\d+)?) ?, ?(-?\d+(?:\.\d+)?) ?\)"#, in: text),
              let low = rational(interval[1])?.double, let high = rational(interval[2])?.double, low < high,
              let placesWord = groups(#"\b(\d|one|two|three|four) decimal places?\b"#, in: text)?[1], let places = count(placesWord), places <= 6 else { return nil }
        let written = every(#"\b(?:equation|of) ((?:[-\dx^+().*/ ])+?= ?-?\d+(?:\.\d+)?)"#, in: text).map { $0[1] }
        let polynomials = written.compactMap { equation -> Polynomial? in
            let sides = equation.split(separator: "=").map(String.init)
            guard sides.count == 2, let left = Parser.expression(sides[0]), let right = Parser.expression(sides[1]) else { return nil }
            return Polynomial(.add([left, .multiply([.minusOne, right])]), in: "x")
        }
        guard !polynomials.isEmpty, polynomials.count == written.count, let polynomial = polynomials.first,
              polynomials.allSatisfy({ $0 == polynomial }), polynomial.degree >= 2 else { return nil }
        let inside = polynomial.realRoots.filter { $0 > low && $0 < high }
        guard inside.count == 1, let root = inside.first else { return nil }
        let scale = pow(10, Double(places))
        let rounded = (root * scale).rounded() / scale
        // Not so near a halfway point that the last place is in doubt.
        guard abs(root * scale - (root * scale).rounded(.down) - 0.5) > 1e-6 else { return nil }
        let answer = Expr.number(.real(rounded))
        let lead = [Step("Find the root between \(Format.number(.real(low))) and \(Format.number(.real(high)))", "Iterating a rearrangement of the equation, or a calculator's solve, gives x = \(String(format: "%.6f", root))…",
                         [MathLine(.symbol("x"), .number(.real((root * 1e6).rounded() / 1e6)))]),
                    Step("Round to \(places) decimal place\(places == 1 ? "" : "s")", "", [MathLine(.symbol("x"), answer)])]
        return told("root to \(places) d.p.", [MathLine(.symbol("x"), answer)], lead)
    }

    // MARK: Round 4: breadth

    /// Expressions that must each be zero, solved for the unknowns one at a time (or together where
    /// they're all linear). Nil unless there is exactly one exact solution. `positive` are letters
    /// the question says are positive.
    private static func solveAll(_ equations: [Expr], _ unknowns: [String], positive: Set<String> = []) -> [String: Rational]? {
        guard !unknowns.isEmpty else { return nil }
        var known: [String: Rational] = [:]
        if equations.count >= unknowns.count, let rows = Optional(equations.compactMap { linearRow($0, unknowns) }), rows.count == equations.count {
            // All linear: the first independent ones, checked against the rest below.
            for start in 0...(rows.count - unknowns.count) {
                let square = Array(rows[start..<(start + unknowns.count)]).map { Array($0.dropLast()) + [$0.last!.negated] }
                if let values = solveLinear(square) {
                    for (u, v) in zip(unknowns, values) { known[u] = v }
                    break
                }
            }
        }
        func put(_ e: Expr) -> Expr {
            var result = e
            for (k, v) in known { result = result.substituting(k, with: exact(v)) }
            return Simplify.run(result)
        }
        // A linear guess that doesn't fit every equation is dropped (a power of a letter can pass for linear at 0 and 1).
        if !known.isEmpty, !equations.allSatisfy({ if case .number(.exact(let r)) = put($0) { return r.isZero }; return false }) { known = [:] }
        var progressed = true
        while known.count < unknowns.count, progressed {
            progressed = false
            for e in equations {
                let free = put(e)
                let open = free.symbols.intersection(unknowns)
                guard open.count == 1, let u = open.first, free.symbols == [u], var roots = exactRoots(free, u) else { continue }
                if positive.contains(u) { roots = roots.filter { $0 > Rational(0) } }
                guard roots.count == 1 else { return nil }
                known[u] = roots[0]
                progressed = true
                break
            }
        }
        guard known.count == unknowns.count else { return nil }
        for e in equations {
            guard case .number(.exact(let r)) = put(e), r.isZero else { return nil }
        }
        return known
    }

    /// The letters a question asks for: "the values of a and b", "find c and d", "the value of k".
    private static func askedLetters(_ text: String) -> Set<String> {
        var found = Set<String>()
        for match in every(#"(?<!all )\b(?:values?|value) of ([a-z])(?: ?, ?([a-z]))?(?:,? and (?:the value of )?([a-z]))?\b"#, in: text) {
            for g in match.dropFirst() where g.count == 1 { found.insert(g.lowercased()) }
        }
        for match in every(#"\b(?:find|work out|calculate) ([a-z])(?: ?, ?([a-z]))?(?: and ([a-z]))?\b(?! ?[(=])"#, in: text) {
            for g in match.dropFirst() where g.count == 1 { found.insert(g.lowercased()) }
        }
        return found
    }

    /// "Work out the values of a and b in the identity 5(7x + 8) + 3(2x + b) ≡ ax + 13", and
    /// "The only solution to x² + bx + c = 0 is x = 5. Work out the values of b and c."
    private static func identity(_ lines: [String], _ text: String) -> Problem? {
        let isIdentity = text.contains("≡") || has(#"\bidentity\b|\bfor all values of x\b"#, text)
        let only = groups(#"\bthe only solution (?:to|of) (.+?=.+?) is x ?= ?(-?\d+(?:\.\d+)?)\b"#, in: text)
        guard isIdentity || only != nil else { return nil }
        var written: String?
        if let only { written = only[1] } else {
            let candidates = lines.compactMap { line -> String? in
                let maths = line.replacingOccurrences(of: #"(?i)^.*?\b(?:identity|given that|that)\b:?\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"(?i)\s*(?:\bfor all values of [a-z]\b|,|\bfind\b|\bwork out\b).*$"#, with: "", options: .regularExpression)
                let plain = maths.replacingOccurrences(of: "≡", with: "=").trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                guard plain.filter({ $0 == "=" }).count == 1, !has(#"[a-z]{3,}"#, plain) else { return nil }
                return plain
            }
            guard candidates.count == 1 else { return nil }
            written = candidates[0]
        }
        guard let written else { return nil }
        let sides = written.replacingOccurrences(of: "≡", with: "=").split(separator: "=").map(String.init)
        guard sides.count == 2, let left = Parser.expression(sides[0]), let right = Parser.expression(sides[1]) else { return nil }
        var difference = Expr.add([left, .multiply([.minusOne, right])])
        let unknowns = difference.symbols.subtracting(["x"]).sorted()
        guard (1...4).contains(unknowns.count), unknowns.allSatisfy({ $0.count == 1 }), difference.symbols.contains("x") else { return nil }
        if let only, let k = rational(only[2]) {
            // The only solution: the quadratic is its x² coefficient times (x − k)².
            guard let form = PolynomialForm(difference, in: "x"), form.degree == 2 else { return nil }
            let square = Expr.power(.add([.symbol("x"), exact(k.negated)]), .integer(2))
            difference = .add([difference, .multiply([.minusOne, form.coefficient(2), square])])
        }
        guard let form = PolynomialForm(difference, in: "x") else { return nil }
        let equations = (0...max(form.degree, 0)).map { Simplify.run(form.coefficient($0)) }.filter { !$0.isZero }
        // (An italic b is often read as 6: "the values of a and 6".)
        var askedText = text
        if unknowns.contains("b"), let misread = groups(#"\bvalues of ([a-z]) and 6\b"#, in: text) {
            askedText = askedText.replacingOccurrences(of: misread[0], with: "values of \(misread[1]) and b")
        }
        let asked = askedLetters(askedText)
        guard asked.isEmpty || asked == Set(unknowns), let values = solveAll(equations, unknowns) else { return nil }
        // Every number is in the identity (or the only solution).
        let rest = askedText.replacingOccurrences(of: only?[0] ?? written, with: " ").replacingOccurrences(of: written.replacingOccurrences(of: "=", with: "≡"), with: " ")
        guard numbers(in: rest).isEmpty else { return nil }
        let pairs = unknowns.map { ($0, exact(values[$0]!)) }
        let lead = [Step(only != nil ? "One solution means a repeated root" : "Match the coefficients",
                         only != nil ? "With x = \(only![2]) the only solution, the quadratic is a multiple of (x − \(only![2]))². Match the coefficients of each power of x." : "Multiply out both sides. For it to be true for every x, each power of x must have the same coefficient on both sides.",
                         equations.map { MathLine($0, .zero) }),
                    Step("Solve for the letters", "", pairs.map { MathLine(.symbol($0.0), $0.1) })]
        return told("values of \(unknowns.joined(separator: " and "))", [together(pairs)], lead)
    }

    /// "y = x² + px + r passes through (0, 4), (1, 3) and (8, w). Work out w." and
    /// "g(x) = a × bˣ where a and b are constants. g(0) = 8 and g(3) = 343. Work out g(1)."
    private static func constantsFromValues(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bconstants?\b|\bpasses through\b|\bgoes through\b|\bwhere [a-z] and [a-z] are (?:numbers|integers)\b"#, text) else { return nil }
        // The rule: y = … or f(x) = …
        let rules = lines.filter { !has(#"\bwhen\b"#, $0) }.compactMap { groups(#"(?:^|[\s:])(y|[fgh]\(x\)) ?= ?([^,=]+?)(?= where\b| for\b| and\b|\.(?!\d)|,|$)"#, in: $0) }
        guard rules.count == 1, let rule = rules.first,
              let formula = Parser.expression(rule[2].replacingOccurrences(of: "×", with: "*")) else { return nil }
        let name = rule[1].lowercased()
        let constants = formula.symbols.subtracting(["x"]).sorted()
        guard formula.symbols.contains("x"), (1...3).contains(constants.count), constants.allSatisfy({ $0.count == 1 && $0 != "y" }) else { return nil }
        var equations: [Expr] = [], used: [String] = [rule[0]]
        var wanted: (letter: String, at: Rational)?
        var wantedValue: Rational?
        if name == "y" {
            // "y = 10 when x = 1", and what's asked: "the value of y when x = 3".
            if let asked = groups(#"\bvalue of y when x ?= ?(-?\d+(?:\.\d+)?)"#, in: text), let x = rational(asked[1]) {
                used.append(asked[0]); wantedValue = x
            }
            for given in every(#"\by ?= ?(-?\d+(?:\.\d+)?) when x ?= ?(-?\d+(?:\.\d+)?)"#, in: text) {
                guard let y = rational(given[1]), let x = rational(given[2]) else { return nil }
                used.append(given[0])
                equations.append(.add([formula.substituting("x", with: exact(x)), exact(y.negated)]))
            }
            for point in every(#"\((-?\d+(?:\.\d+)?) ?, ?(-?\d+(?:\.\d+)?|[a-z])\)"#, in: text) {
                guard let x = rational(point[1]) else { return nil }
                used.append(point[0])
                if let y = rational(point[2]) { equations.append(.add([formula.substituting("x", with: exact(x)), exact(y.negated)])) }
                else { guard wanted == nil else { return nil }; wanted = (point[2].lowercased(), x) }
            }
        } else {
            let f = String(name.prefix(1))
            for given in every(#"\b\#(f)\((-?\d+(?:\.\d+)?)\) ?= ?(-?\d+(?:\.\d+)?)"#, in: text) {
                guard let x = rational(given[1]), let y = rational(given[2]) else { return nil }
                used.append(given[0])
                equations.append(.add([formula.substituting("x", with: exact(x)), exact(y.negated)]))
            }
            if let asked = groups(#"\b(?:value of|find|work out|calculate) \#(f)\((-?\d+(?:\.\d+)?)\)\.?$"#, in: text), let x = rational(asked[1]) {
                used.append(asked[0]); wantedValue = x
            }
        }
        guard equations.count >= constants.count else { return nil }
        let positive = Set(constants.filter { has("\\b\($0) ?> ?0\\b|\\b\($0) is positive\\b", text) })
        guard let values = solveAll(equations, constants, positive: positive) else { return nil }
        var found = formula
        for (k, v) in values { found = found.substituting(k, with: exact(v)) }
        found = Simplify.run(found)
        let rest = used.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }
        guard numbers(in: rest).isEmpty else { return nil }
        var lead = [Step("Put in the values you know", "Each one gives an equation in the constants.", equations.map { MathLine(Simplify.run($0), .zero) }),
                    Step("Solve for the constants", "", constants.map { MathLine(.symbol($0), exact(values[$0]!)) })]
        if let wanted, has("\\bvalue of \(wanted.letter)\\b|\\bfind \(wanted.letter)\\b|\\bwork out \(wanted.letter)\\b", text) {
            guard case .number(.exact(let w)) = Simplify.run(found.substituting("x", with: exact(wanted.at))) else { return nil }
            lead.append(Step("Put x = \(shown(wanted.at)) into the equation", "", [MathLine(.symbol("y"), found), MathLine(.symbol(wanted.letter), exact(w))]))
            return told("value of \(wanted.letter)", [MathLine(.symbol(wanted.letter), exact(w))], lead)
        }
        if let at = wantedValue {
            guard case .number(.exact(let v)) = Simplify.run(found.substituting("x", with: exact(at))) else { return nil }
            let label = name == "y" ? "y when x = \(shown(at))" : "\(name.prefix(1))(\(shown(at)))"
            // Decimals in, a decimal out.
            let value = has(#"\d\.\d"#, text) ? decimal(v) : exact(v)
            lead.append(Step("Work out \(label)", "", [MathLine(.symbol(label), value)]))
            return told(label, [MathLine(value)], lead)
        }
        let asked = askedLetters(text)
        guard !asked.isEmpty, asked == Set(constants) else { return nil }
        return told("values of \(constants.joined(separator: " and "))", [together(constants.map { ($0, exact(values[$0]!)) })], lead)
    }

    /// Whether π or e is written in it.
    private static func hasConstant(_ expr: Expr) -> Bool {
        switch expr {
        case .constant: true
        case .number, .symbol: false
        case .add(let parts), .multiply(let parts): parts.contains(where: hasConstant)
        case .power(let base, let exponent): hasConstant(base) || hasConstant(exponent)
        case .function(_, let argument): hasConstant(argument)
        }
    }

    /// Whole-number values from several inequalities, in one or two letters: "x is an integer.
    /// −4 < x ⩽ 2 and 2 ⩽ x + 3 < 9. Work out all the possible values of x", "the greatest possible value of y − x".
    private static func integerConditions(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bintegers?\b|\bwhole numbers?\b"#, text) else { return nil }
        var conditions: [(sides: [Expr], relations: [String], written: String)] = []
        for line in lines {
            for piece in line.components(separatedBy: " and ") {
                let maths = piece.replacingOccurrences(of: #"(?i)^.*?\b(?:where|if|and|that)\b:?\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                guard maths.range(of: "[<>≤≥]", options: .regularExpression) != nil, !has(#"[a-z]{3,}"#, maths) else { continue }
                var sides: [Expr] = [], relations: [String] = []
                for part in every(#"([^<>≤≥]+)([<>≤≥]|$)"#, in: maths) where !part[1].trimmingCharacters(in: .whitespaces).isEmpty {
                    // (An n read as Cyrillic п comes out as π: not something to count whole numbers with.)
                    guard let side = Parser.expression(part[1].trimmingCharacters(in: .whitespaces)), !hasConstant(side) else { return nil }
                    sides.append(side)
                    if !part[2].isEmpty { relations.append(part[2]) }
                }
                guard sides.count == relations.count + 1, (1...2).contains(relations.count) else { return nil }
                conditions.append((sides, relations, maths))
            }
        }
        let letters = conditions.reduce(into: Set<String>()) { $0.formUnion($1.sides.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }) }.sorted()
        guard conditions.count >= (letters.count == 1 ? 2 : 1), (1...2).contains(letters.count) else { return nil }
        func holds(_ values: [String: Double]) -> Bool {
            conditions.allSatisfy { c in
                let v = c.sides.compactMap { $0.evaluate(values) }
                guard v.count == c.sides.count else { return false }
                return zip(c.relations.indices, c.relations).allSatisfy { i, r in
                    switch r { case "<": v[i] < v[i + 1] - 1e-9; case ">": v[i] > v[i + 1] + 1e-9; case "≤": v[i] <= v[i + 1] + 1e-9; default: v[i] >= v[i + 1] - 1e-9 }
                }
            }
        }
        func search(within limit: Int) -> [[Int]] {
            var found: [[Int]] = []
            if letters.count == 1 {
                for a in -limit...limit where holds([letters[0]: Double(a)]) { found.append([a]) }
            } else {
                for a in -limit...limit { for b in -limit...limit where holds([letters[0]: Double(a), letters[1]: Double(b)]) { found.append([a, b]) } }
            }
            return found
        }
        let limit = letters.count == 1 ? 500 : 60
        let points = search(within: limit)
        guard !points.isEmpty else { return nil }
        let bounded = !points.contains(where: { $0.contains { abs($0) == limit } })
        guard numbers(in: conditions.reduce(text) { $0.replacingOccurrences(of: $1.written, with: " ") }).isEmpty else { return nil }
        let lead = [Step("Take each inequality in turn", "Work out what each one allows, then keep only the whole numbers that fit all of them.",
                         conditions.map { MathLine(.symbol($0.written)) })]
        if let extreme = groups(#"\b(greatest|largest|biggest|highest|least|smallest|lowest) possible value of (.+?)\.?$"#, in: text),
           let target = Parser.expression(extreme[2]), target.symbols.isSubset(of: Set(letters)) {
            let values = points.compactMap { p -> Double? in
                var all: [String: Double] = [:]
                for (l, v) in zip(letters, p) { all[l] = Double(v) }
                return target.evaluate(all)
            }
            let big = ["greatest", "largest", "biggest", "highest"].contains(extreme[1].lowercased())
            guard let best = big ? values.max() : values.min(), abs(best - best.rounded()) < 1e-9 else { return nil }
            // Open on the other side is fine; the best mustn't move when the search is wider.
            if !bounded {
                let wider = search(within: limit * 2).compactMap { p -> Double? in
                    var all: [String: Double] = [:]
                    for (l, v) in zip(letters, p) { all[l] = Double(v) }
                    return target.evaluate(all)
                }
                guard let again = big ? wider.max() : wider.min(), abs(again - best) < 1e-9 else { return nil }
            }
            return told("\(extreme[1]) value of \(Format.text(target))", [MathLine(.integer(Int(best.rounded())))], lead)
        }
        guard bounded, letters.count == 1, has(#"\b(?:all|list|possible|which)\b.*\bvalues?\b"#, text), points.count <= 30 else { return nil }
        let listed = points.map { Format.number(.integer($0[0])) }.joined(separator: ", ")
        return told("values of \(letters[0])", [MathLine(.symbol(listed))], lead + [Step("List them", "", [MathLine(.symbol(letters[0]), .symbol(listed))])])
    }

    /// Sequences given by some of their terms in words: "The 5th term of a linear sequence is 17.
    /// The 6th term is 21. Work out the 100th term." Also a row of terms written in letters,
    /// "a + 2b, a + 6b, a + 10b … The 2nd term has value 8", and three consecutive terms of an
    /// arithmetic or geometric sequence written as expressions.
    private static func termsInWords(_ lines: [String], _ text: String) -> Problem? {
        let ordinal = #"(\d{1,3}(?:st|nd|rd|th)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|fifteenth|twentieth|fiftieth|hundredth)"#
        // Three consecutive terms written as expressions.
        // (The question's number can come first: "20 x − 4, x + 2 and 3x + 1 are …".)
        let unnumbered = text.replacingOccurrences(of: #"^\d{1,2} (?=[a-z]\b)"#, with: "", options: .regularExpression)
        if let three = groups(#"^(.+?),\s*(.+?) and (.+?) are (?:three )?consecutive terms of an? (arithmetic|geometric) (?:sequence|progression)"#, in: unnumbered),
           let a = Parser.expression(three[1]), let b = Parser.expression(three[2]), let c = Parser.expression(three[3]) {
            let letters = a.symbols.union(b.symbols).union(c.symbols)
            guard letters.count == 1, let letter = letters.first else { return nil }
            let isArithmetic = three[4].lowercased() == "arithmetic"
            let equation: Expr = isArithmetic ? .add([b, .multiply([.minusOne, a]), .multiply([.minusOne, c]), b])
                                              : .add([.multiply([b, b]), .multiply([.minusOne, a, c])])
            guard let roots = exactRoots(equation, letter),
                  has("\\b(?:value|values) of \(letter)\\b|\\bfind \(letter)\\b", text),
                  numbers(in: unnumbered.replacingOccurrences(of: three[0], with: " ")).isEmpty else { return nil }
            // The terms mustn't be zero in a geometric sequence.
            let kept = roots.filter { r in isArithmetic || [a, b, c].allSatisfy { Simplify.run($0.substituting(letter, with: exact(r))).number?.isZero == false } }
            guard !kept.isEmpty, kept.count == 1 || has(#"\bpossible values\b|\bvalues of\b"#, text) else { return nil }
            let lead = [Step(isArithmetic ? "The differences are equal" : "The ratios are equal",
                             isArithmetic ? "(second − first) = (third − second)" : "second ÷ first = third ÷ second, so second² = first × third",
                             [MathLine(isArithmetic ? .add([b, .multiply([.minusOne, a])]) : .multiply([b, b]), isArithmetic ? .add([c, .multiply([.minusOne, b])]) : .multiply([a, c]))]),
                        Step("Solve", "", kept.map { MathLine(.symbol(letter), exact($0)) })]
            return told("value of \(letter)", kept.map { MathLine(.symbol(letter), exact($0)) }, lead)
        }
        let facts = every(#"\b(?:the )?\#(ordinal) term(?: of (?:the|this|a|an) (?:linear |arithmetic )?(?:sequence|progression))? (?:is|has value|has a value of|=) (-?\d+(?:\.\d+)?)"#, in: text)
        guard !facts.isEmpty else { return nil }
        // A row of terms in letters.
        var row: [Expr]?
        var rowText: String?
        for line in lines where !has(#"[a-z]{3,}"#, line.replacingOccurrences(of: #"(?i)^.*\b(?:starts|begins)\b:?"#, with: "", options: .regularExpression)) {
            let body = line.replacingOccurrences(of: #"(?i)^.*\b(?:starts|begins)\b:?\s*"#, with: "", options: .regularExpression).replacingOccurrences(of: #"[.…]+\s*"#, with: " ", options: .regularExpression)
            let pieces = choices(body.replacingOccurrences(of: ",", with: " ")).filter { !$0.isEmpty }
            let exprs = pieces.compactMap { Parser.expression($0) }
            guard pieces.count >= 3, exprs.count == pieces.count, exprs.allSatisfy({ !$0.symbols.isEmpty }) else { continue }
            guard row == nil else { return nil }
            row = exprs; rowText = body
        }
        if let row, let rowText {
            let unknowns = row.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }.sorted()
            guard unknowns.count <= 3, facts.count == unknowns.count else { return nil }
            // The terms go up by the same amount: term n = first + (n − 1) × difference.
            let step = Simplify.run(Simplify.expand(.add([row[1], .multiply([.minusOne, row[0]])])))
            for i in 1..<(row.count - 1) {
                guard same(.add([row[i + 1], .multiply([.minusOne, row[i]])]), step) else { return nil }
            }
            var equations: [Expr] = []
            for fact in facts {
                guard let k = position(fact[1]), let v = rational(fact[2]) else { return nil }
                equations.append(.add([row[0], .multiply([.integer(k - 1), step]), exact(v.negated)]))
            }
            guard askedLetters(text) == Set(unknowns), let values = solveAll(equations, unknowns),
                  numbers(in: facts.map(\.[0]).reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }.replacingOccurrences(of: rowText, with: " ")).isEmpty else { return nil }
            let pairs = unknowns.map { ($0, exact(values[$0]!)) }
            let lead = [Step("Write the terms you're told about", "The terms go up by \(Format.text(step)) each time, so the kth term is the first plus (k − 1) × \(Format.text(step)).",
                             equations.map { MathLine(Simplify.run($0), .zero) }),
                        Step("Solve them together", "", pairs.map { MathLine(.symbol($0.0), $0.1) })]
            return told("values of \(unknowns.joined(separator: " and "))", [together(pairs)], lead)
        }
        // Two terms of a linear sequence.
        guard facts.count == 2, has(#"\blinear\b|\barithmetic\b"#, text), !has(#"\bnth term (?:of (?:the|a|this) sequence )?is\b"#, text),
              let k1 = position(facts[0][1]), let k2 = position(facts[1][1]), k1 != k2,
              let v1 = rational(facts[0][2]), let v2 = rational(facts[1][2]),
              let rise = v2 - v1, let d = rise / Rational(k2 - k1), let start = v1 - (d * Rational(k1 - 1))! else { return nil }
        var used = facts.map(\.[0])
        let nth = Polynomial([start - d ?? Rational(0), d], variable: "n")
        let lead0 = Step("Find the difference", "From the \(facts[0][1]) term to the \(facts[1][1]) term is \(k2 - k1) step\(abs(k2 - k1) == 1 ? "" : "s"), so each step is \(shown(d)).",
                         [MathLine(.symbol("difference"), exact(d)), MathLine(.symbol("nth term"), nth.expr)])
        if let term = groups(#"\b(?:find|work out|write down|calculate|what is) the \#(ordinal) term\b"#, in: text), let k = position(term[1]), let value = nth.evaluate(Rational(k)) {
            used.append(term[0])
            guard numbers(in: used.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty else { return nil }
            return told("\(term[1]) term", [MathLine(exact(value))], [lead0, Step("Put n = \(k) into it", "", [MathLine(.symbol("\(term[1]) term"), exact(value))])])
        }
        if has(#"\bnth term\b"#, text), numbers(in: used.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty {
            return told("nth term", [MathLine(nth.expr)], [lead0])
        }
        return nil
    }

    /// Ratios with a letter in them: "x : y = 7 : 4, x + y = 88. Work out x − y"; "Joe and Kyle
    /// share an amount in the ratio 7 : n. Joe gets 35% of the money. Work out n."; "The ratio of
    /// fiction to non-fiction books is 2 : 3. Heidi removes 2 fiction books. The ratio is then 5 : 8."
    private static func ratioWithLetter(_ lines: [String], _ text: String) -> Problem? {
        let plain = text.replacingOccurrences(of: "’", with: "'")
        // x : y = 7 : 4 and a sum or difference.
        if let ratio = groups(#"\b([a-z]) ?: ?([a-z]) ?= ?(\d+) ?: ?(\d+)\b"#, in: plain), ratio[1] != ratio[2] {
            let x = ratio[1].lowercased(), y = ratio[2].lowercased()
            let facts = lines.filter { !$0.contains(":") && $0.contains("=") && !has(#"[a-z]{3,}"#, $0) }
            guard facts.count == 1, let p = rational(ratio[3]), let q = rational(ratio[4]) else { return nil }
            let sides = facts[0].split(separator: "=").map(String.init)
            guard sides.count == 2, let l = Parser.expression(sides[0]), let r = Parser.expression(sides[1]) else { return nil }
            // x = pt, y = qt.
            let fact = Expr.add([l, .multiply([.minusOne, r])]).substituting(x, with: .multiply([exact(p), .symbol("t")])).substituting(y, with: .multiply([exact(q), .symbol("t")]))
            guard fact.symbols == ["t"], let roots = exactRoots(fact, "t"), roots.count == 1, let t = roots.first,
                  let target = (groups(#"\bvalue of (.+?)\.?$"#, in: plain) ?? groups(#"\b(?:work out|find|calculate) (.+?)\.?$"#, in: plain)).flatMap({ Parser.expression($0[1]) }),
                  target.symbols.isSubset(of: [x, y]), !target.symbols.isEmpty,
                  case .number(.exact(let value)) = Simplify.run(target.substituting(x, with: exact((p * t)!)).substituting(y, with: exact((q * t)!))),
                  numbers(in: plain.replacingOccurrences(of: ratio[0], with: " ").replacingOccurrences(of: facts[0], with: " ")).isEmpty else { return nil }
            let lead = [Step("Write \(x) and \(y) as parts", "\(x) : \(y) = \(shown(p)) : \(shown(q)), so \(x) = \(shown(p))t and \(y) = \(shown(q))t.",
                             [MathLine(.symbol("t"), exact(t)), MathLine(.symbol(x), exact((p * t)!)), MathLine(.symbol(y), exact((q * t)!))]),
                        Step("Work out \(Format.text(target))", "", [MathLine(target, exact(value))])]
            return told("value of \(Format.text(target))", [MathLine(exact(value))], lead)
        }
        // Shared in a ratio with a letter in it, and one share as a fraction or percentage of the total.
        if let share = groups(#"^(.+?) share (?:an amount of |some )?(?:money|\w+)?.*? in the ratio ((?:\d+|[a-z]) ?: ?(?:\d+|[a-z])(?: ?: ?(?:\d+|[a-z]))?)\b"#, in: plain) {
            let names = every(#"\b([A-Z][a-z]+)\b"#, in: share[1]).map { $0[1] }.filter { $0.first!.isUppercase && $0 != "The" }
            let parts = share[2].split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            let letters = parts.filter { Int($0) == nil }
            guard names.count == parts.count, letters.count == 1, let letter = letters.first?.lowercased(),
                  let fact = groups(#"\b([A-Z][a-z]+)(?:'s share is| gets| receives| has) (\d+(?:\.\d+)?%|\d+/\d+|\d+ ?÷ ?\d+) of the (?:total|money|amount)"#, in: plain),
                  let who = names.firstIndex(of: fact[1]),
                  let fraction = fact[2].hasSuffix("%") ? rational(String(fact[2].dropLast())).flatMap({ $0 / Rational(100) }) : Parser.expression(fact[2]).flatMap({ Simplify.run($0).number?.rational }),
                  has("\\bvalue of \(letter)\\b|\\bfind \(letter)\\b|\\bwork out \(letter)\\b", plain) else { return nil }
            let total = Expr.add(parts.map { Int($0).map { Expr.integer($0) } ?? .symbol(letter) })
            let mine = Int(parts[who]).map { Expr.integer($0) } ?? .symbol(letter)
            let equation = Expr.add([mine, .multiply([.minusOne, exact(fraction), total])])
            guard let roots = exactRoots(equation, letter), roots.count == 1, let value = roots.first, value > Rational(0),
                  numbers(in: plain.replacingOccurrences(of: share[2], with: " ").replacingOccurrences(of: fact[0], with: " ")).isEmpty else { return nil }
            let lead = [Step("Write \(fact[1])'s share as a fraction of the total", "\(fact[1]) has \(parts[who]) of the \(parts.joined(separator: " + ")) parts.",
                             [MathLine(.multiply([mine, .power(total, .minusOne)]), exact(fraction))]),
                        Step("Solve for \(letter)", "", [MathLine(.symbol(letter), exact(value))])]
            return told("value of \(letter)", [MathLine(.symbol(letter), exact(value))], lead)
        }
        // A ratio, then a number of one kind taken away or added, then the new ratio.
        let ratios = every(#"\bratio of (.+?) to (.+?) (?:\w+ )*?is (?:then |now )?(\d+) ?: ?(\d+)"#, in: plain)
        guard ratios.count == 2, ratios[0][1].lowercased() == ratios[1][1].lowercased(), ratios[0][2].lowercased() == ratios[1][2].lowercased(),
              let change = groups(#"\b(removes|takes out|takes away|sells|gives away|eats|adds|puts in|buys|puts|gets) (\d+) (?:more )?(.+?)(?: (?:from|to|into|in)\b.*)?$"#, in: plain.components(separatedBy: CharacterSet(charactersIn: ".\n")).first { has(#"\b(?:removes|takes out|takes away|sells|gives away|eats|adds|puts in|buys|puts|gets) \d+"#, $0) } ?? ""),
              let k0 = rational(change[2]), let p = Int(ratios[0][3]), let q = Int(ratios[0][4]), let r = Int(ratios[1][3]), let s = Int(ratios[1][4]) else { return nil }
        let first = ratios[0][1].lowercased(), second = ratios[0][2].lowercased(), thing = change[3].lowercased()
        let onFirst = thing.hasPrefix(first) || first.hasPrefix(thing.split(separator: " ").first.map(String.init) ?? "#")
        let onSecond = thing.hasPrefix(second) || second.hasPrefix(thing.split(separator: " ").first.map(String.init) ?? "#")
        guard onFirst != onSecond else { return nil }
        let k = ["adds", "puts in", "buys", "puts", "gets"].contains(change[1].lowercased()) ? k0 : k0.negated
        // (pt + k) : qt = r : s, or pt : (qt + k) = r : s.
        let t = Expr.symbol("t")
        let left = onFirst ? Expr.add([.multiply([.integer(p), t]), exact(k)]) : .multiply([.integer(p), t])
        let right = onSecond ? Expr.add([.multiply([.integer(q), t]), exact(k)]) : .multiply([.integer(q), t])
        guard let roots = exactRoots(.add([.multiply([.integer(s), left]), .multiply([.integer(-r), right])]), "t"), roots.count == 1,
              let tv = roots.first, tv > Rational(0), tv.isInteger,
              let question = groups(#"\bhow many (.+?)(?: are| were| is| was| does| did| has| have)\b(.*)$"#, in: plain) else { return nil }
        let asked = question[1].lowercased()
        let askedFirst = asked.hasPrefix(first) || first.hasPrefix(asked.split(separator: " ").first.map(String.init) ?? "#")
        let askedSecond = asked.hasPrefix(second) || second.hasPrefix(asked.split(separator: " ").first.map(String.init) ?? "#")
        let after = has(#"\b(?:now|then|after|left)\b"#, question[2])
        let inTotal = has(#"\b(?:in total|altogether|total)\b"#, question[2])
        var value: Rational?
        if askedFirst != askedSecond {
            value = Rational(askedFirst ? p : q) * tv
            if after, (askedFirst && onFirst) || (askedSecond && onSecond) { value = value.flatMap { $0 + k } }
        } else if !askedFirst, inTotal {
            // "How many books are left on the bookcase in total?"
            value = (Rational(p + q) * tv).flatMap { after ? $0 + k : $0 }
        }
        guard let value, value >= Rational(0),
              numbers(in: [ratios[0][0], ratios[1][0], change[0]].reduce(plain) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty else { return nil }
        let lead = [Step("Call them \(p)t and \(q)t", "Before the change they're in the ratio \(p) : \(q).",
                         [MathLine(.symbol("(\(Format.text(left))) : (\(Format.text(right)))"), .symbol("\(r) : \(s)"))]),
                    Step("Cross-multiply and solve", "", [MathLine(.multiply([.integer(s), left]), .multiply([.integer(r), right])), MathLine(.symbol("t"), exact(tv))]),
                    Step("Work out how many \(asked)", "", [MathLine(exact(value))])]
        return told("number of \(asked)", [MathLine(exact(value))], lead)
    }

    /// "The ratio of jellies to mints is n : 2. The ratio of mints to toffees is 5 : 3n. Work out
    /// the ratio of jellies to toffees." The letter cancels.
    private static func chainedRatio(_ text: String) -> Problem? {
        let part = #"([0-9a-z ]+?)"#
        let ratios = every(#"\bratio of (\w+) to (\w+) is \#(part) ?: ?\#(part)(?=[.,]|$| [A-Z]| work\b)"#, in: text)
        guard ratios.count == 2, let asked = groups(#"\b(?:work out|find|write down) the ratio of (\w+) to (\w+)"#, in: text) else { return nil }
        let a = ratios[0], b = ratios[1]
        guard a[2].lowercased() == b[1].lowercased(), asked[1].lowercased() == a[1].lowercased(), asked[2].lowercased() == b[2].lowercased(),
              let p = Parser.expression(a[3]), let q = Parser.expression(a[4]), let r = Parser.expression(b[3]), let t = Parser.expression(b[4]) else { return nil }
        let letters = p.symbols.union(q.symbols).union(r.symbols).union(t.symbols)
        guard letters.count == 1 else { return nil }
        // first : last = p·r : q·t, which must be the same whatever the letter is.
        let quotient = Simplify.run(.multiply([p, r, .power(.multiply([q, t]), .minusOne)]))
        guard quotient.symbols.isEmpty, case .number(.exact(let k)) = quotient, k > Rational(0),
              numbers(in: [a[0], b[0]].reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty else { return nil }
        let ratio = "\(k.numerator) : \(k.denominator)"
        let lead = [Step("Make the \(a[2]) parts match", "Multiply the first ratio by \(b[3]) and the second by \(a[4]), so \(a[2]) is \(Format.text(Simplify.run(.multiply([q, r])))) in both.",
                         [MathLine(.symbol("\(a[1]) : \(a[2]) : \(b[2])"), .symbol("\(Format.text(Simplify.run(.multiply([p, r])))) : \(Format.text(Simplify.run(.multiply([q, r])))) : \(Format.text(Simplify.run(.multiply([q, t]))))"))]),
                    Step("Cancel the letter", "", [MathLine(.symbol("\(asked[1]) : \(asked[2])"), .symbol(ratio))])]
        return told("ratio of \(asked[1]) to \(asked[2])", [MathLine(.symbol(ratio))], lead)
    }

    // MARK: Round 5: read right, no sum made

    private static let smallDigits: [Character] = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]

    /// A letter with its small number: A₂.
    private static func term(_ letter: String, _ n: Int) -> String {
        letter + String(String(n).compactMap { $0.wholeNumberValue.map { smallDigits[$0] } })
    }

    /// Small letters and numbers written on the line, the way they are read: Aₙ₊₁ as An+1, A₀ as A0.
    private static func flattened(_ line: String) -> String {
        var plain = line
        for (index, small) in smallDigits.enumerated() { plain = plain.replacingOccurrences(of: String(small), with: String(index)) }
        for (from, to) in [("ₙ", "n"), ("₊", "+"), ("ₜ", "t"), ("_{", ""), ("}", ""), ("_", "")] { plain = plain.replacingOccurrences(of: from, with: to) }
        return plain
    }

    /// Decimals written as fractions, so that a sum is worked out exactly: 1.02 as (102/100).
    private static func exactDecimals(_ written: String) -> String {
        var result = written
        for found in every(#"(?<![\d.])(\d+)\.(\d+)(?!\d|\.\d)"#, in: written) where found[2].count <= 9 {
            result = result.replacingOccurrences(of: found[0], with: "(\(found[1])\(found[2])/1\(String(repeating: "0", count: found[2].count)))")
        }
        return result
    }

    /// A value as it's written in an answer: a whole number as it is, a decimal that ends as that
    /// decimal, anything else as a fraction.
    private static func tidy(_ value: Rational) -> Expr {
        if value.isInteger { return exact(value) }
        var bottom = value.denominator
        for prime in [2, 5] { while bottom % prime == 0 { bottom /= prime } }
        guard bottom == 1, value.denominator <= 1_000_000, abs(value.double) < 1e9 else { return exact(value) }
        return .number(.real(value.double))
    }

    /// An amount of money: £1358.60.
    private static func pounds(_ value: Rational) -> Expr {
        .symbol("£" + (value.isInteger ? shown(value) : String(format: "%.2f", value.double)))
    }

    /// "Rick borrows £1500 from a bank. He pays back £100 each month. This iterative formula works
    /// out the amount he still owes at the end of each month. Aₙ₊₁ = 1.02 × Aₙ − 100, A₀ = 1500.
    /// Work out the amount he still owes at the end of the 2nd month." A rule that makes each
    /// term from the one before, in a letter of its own, carried on to the term asked for.
    /// (xₙ₊₁ used to solve an equation is `iteration`.)
    private static func recurrence(_ lines: [String], _ text: String) -> Problem? {
        let plain = lines.map(flattened)
        // The rule, on a line of its own: "An +1=1.02 x An − 100", the small n + 1 read on the line.
        let rules = plain.compactMap { groups(#"^([A-Za-z]) ?([nt]) ?\+ ?1 ?= ?(.+?)\.?$"#, in: $0) }
        guard rules.count == 1, let found = rules.first, found[1].lowercased() != "x" else { return nil }
        let letter = found[1], counter = found[2]
        let termPattern = "(?<![A-Za-z])\(letter) ?\(counter)(?![A-Za-z])"
        var written = found[3].replacingOccurrences(of: #"(?<=[\w)]) [x×] (?=[\w(])"#, with: " × ", options: .regularExpression)
        guard every(termPattern, in: written).count == 1 else { return nil }
        // The term before is called q, whatever its letter.
        written = written.replacingOccurrences(of: termPattern, with: "q", options: [.regularExpression, .caseInsensitive])
        // (A digit straight after the term is a power that has dropped onto the line: not read.)
        guard !has(#"[a-pr-z]|q\d"#, written), let shownRule = Parser.expression(written), shownRule.symbols == ["q"],
              let rule = Parser.expression(exactDecimals(written)), rule.symbols == ["q"] else { return nil }
        // Where it starts: A₀ = 1500 (the 0 often read as o), or A₁.
        let joined = plain.joined(separator: " ")
        let starts = every("(?<![A-Za-z])\(letter) ?([0o1]) ?= ?(-?\\d+(?:\\.\\d+)?)(?!\\d|\\.\\d)", in: joined)
        guard starts.count == 1, let first = starts.first, let startValue = rational(first[2]) else { return nil }
        let startIndex = first[1] == "1" ? 1 : 0
        // What's asked: a term by its number, or (counting from A₀) the amount after so many months.
        // ("Find a 2-digit number" isn't asking for a₂: the letters that are also words keep their number close.)
        let gap = ["a", "i"].contains(letter.lowercased()) ? "" : " ?"
        let direct = every("\\b(?:work out|find|calculate|write down|what is)(?: the value of)? \(letter)\(gap)(\\d)(?![\\w-]|\\.\\d)", in: joined)
        let unit = #"(month|year|week|day|hour|minute)"#
        let timed = every(#"\b(?:work out|find|calculate|how much|how many|what)\b[^.?]*?\b(?:at the end of|by the end of|after)(?: the)? (\d{1,2})(?:st|nd|rd|th) \#(unit)\b"#, in: joined)
            + every(#"\b(?:work out|find|calculate|how much|how many|what)\b[^.?]*?\bafter (\d{1,2}|one|two|three|four|five|six) \#(unit)s?\b"#, in: joined)
        guard direct.count + timed.count == 1 else { return nil }
        var k: Int, askedText: String, period: String?
        if let asked = direct.first {
            guard let number = Int(asked[1]) else { return nil }
            k = number; askedText = asked[0]
        } else {
            let asked = timed[0]
            // Only where the rule goes from one month to the next and A₀ is the start.
            guard startIndex == 0, let number = count(asked[1]), has("\\b(?:each|every|per) \(asked[2])\\b", joined) else { return nil }
            k = number; askedText = asked[0]; period = asked[2].lowercased()
        }
        guard k > startIndex, k - startIndex <= 12 else { return nil }
        // Every other number is one the rule or the start already has (the story says them again),
        // or the percentage that the rule's multiplier stands for.
        let ruleNumbers = numbers(in: found[3]).compactMap(rational)
        var rest = [found[0], first[0], askedText].reduce(joined) { $0.replacingOccurrences(of: $1, with: " ") }
        for percent in every(#"(\d+(?:\.\d+)?) ?%"#, in: rest) {
            guard let p = rational(percent[1]), let change = p / Rational(100), let up = Rational(1) + change, let down = Rational(1) - change,
                  ruleNumbers.contains(where: { $0 == up || $0 == down }) else { return nil }
            rest = rest.replacingOccurrences(of: percent[0], with: " ")
        }
        for other in numbers(in: rest) {
            guard let value = rational(other), ruleNumbers.contains(where: { $0 == value }) || value == startValue else { return nil }
        }
        var values = [startValue]
        var working: [MathLine] = []
        for index in (startIndex + 1)...k {
            guard case .number(.exact(let next)) = Simplify.run(rule.substituting("q", with: exact(values[values.count - 1]))) else { return nil }
            working.append(MathLine(.symbol(term(letter, index)), shownRule.substituting("q", with: tidy(values[values.count - 1])), tidy(next)))
            values.append(next)
        }
        let value = values[values.count - 1]
        let lead = [Step("Put \(term(letter, startIndex)) = \(Format.text(tidy(startValue))) into the formula", "Each answer goes back into the formula to give the next one.", working)]
        guard let period else { return told(term(letter, k), [MathLine(.symbol(term(letter, k)), tidy(value))], lead) }
        // An amount of money gets its £; a number of things has to come out whole.
        let isMoney = joined.contains("£")
        guard isMoney || !has(#"\bhow many\b|\bnumber of\b"#, askedText) || value.isInteger else { return nil }
        return told("after \(k) \(period)\(k == 1 ? "" : "s")", [MathLine(isMoney ? pounds(value) : tidy(value))], lead)
    }

    /// "a > 0 and b < 0. Circle the correct statement.  a − b < 0   −b/a < 0   1/a < 0   b³ < 0"
    /// The one statement that is true for every value the letters are allowed.
    private static func signStatement(_ lines: [String], _ text: String) -> Problem? {
        guard let askedAt = lines.firstIndex(where: {
            has(#"\b(?:circle|choose|select|write down|which is)\b.*\b(?:correct|true) (?:statement|inequality)\b|\bwhich (?:of these |one of these )?(?:statements?|inequalit(?:y|ies)) (?:is|must be) (?:always )?(?:correct|true)\b"#, $0)
        }) else { return nil }
        // What the letters are allowed: "a > 0 and b < 0", "0 < x < 1".
        var low: [String: Double] = [:], high: [String: Double] = [:]
        var conditions: [String] = []
        for line in lines[..<askedAt] {
            // (The question's number can come first: "16 a > 0 and b < 0".)
            let pieces = line.lowercased().replacingOccurrences(of: #"^\d{1,2} (?=[a-z] ?[<>≤≥])|^(?:it is )?given (?:that )?|^where |^if |[.,]$"#, with: "", options: .regularExpression)
                .components(separatedBy: " and ").flatMap { $0.components(separatedBy: ",") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for piece in pieces {
                if let one = groups(#"^([a-z]) ?([<>≤≥]) ?(-?\d+(?:\.\d+)?)$"#, in: piece), let bound = rational(one[3])?.double {
                    if one[2] == ">" || one[2] == "≥" { low[one[1]] = max(low[one[1]] ?? -.infinity, bound) } else { high[one[1]] = min(high[one[1]] ?? .infinity, bound) }
                } else if let two = groups(#"^(-?\d+(?:\.\d+)?) ?[<≤] ?([a-z]) ?[<≤] ?(-?\d+(?:\.\d+)?)$"#, in: piece), let a = rational(two[1])?.double, let b = rational(two[3])?.double, a < b {
                    low[two[2]] = max(low[two[2]] ?? -.infinity, a); high[two[2]] = min(high[two[2]] ?? .infinity, b)
                } else if piece.range(of: #"[\d<>≤≥=]"#, options: .regularExpression) != nil {
                    return nil
                } else {
                    continue
                }
                conditions.append(piece)
            }
        }
        let letters = Set(low.keys).union(high.keys).sorted()
        guard (1...3).contains(letters.count), letters.allSatisfy({ (low[$0] ?? -.infinity) < (high[$0] ?? .infinity) }) else { return nil }
        // The statements: the lines after the question, down to the next line of words.
        var statements: [(left: Expr, relation: String, right: Expr)] = []
        for line in lines[(askedAt + 1)...] {
            if has(#"[a-z]{3,}"#, line) { break }
            let plain = line.lowercased()
            var pieces = [plain]
            if plain.filter({ "<>≤≥=".contains($0) }).count > 1 {
                // Several on one line, each ending in its number.
                let found = every(#"\G ?([^<>≤≥=]+?[<>≤≥=] ?-?\d+(?:\.\d+)?)(?= |$)"#, in: plain)
                guard found.map(\.[0]).joined().count == plain.count else { return nil }
                pieces = found.map { $0[1] }
            }
            for piece in pieces {
                guard let sides = groups(#"^([^<>≤≥=]+)([<>≤≥=])([^<>≤≥=]+)$"#, in: piece), !has(#"[a-z]\d"#, piece) else { return nil }
                var written = sides[1]
                // (An italic b is often read as 6: "6^3 < 0" among statements about a and b.)
                if letters.contains("b"), !written.contains(where: \.isLetter) { written = written.replacingOccurrences(of: #"(?<![\d.])6(?!\d|\.\d)"#, with: "b", options: .regularExpression) }
                guard let left = Parser.expression(written), let right = Parser.expression(sides[3]),
                      !left.symbols.isEmpty, left.symbols.union(right.symbols).isSubset(of: Set(letters)) else { return nil }
                statements.append((left, sides[2], right))
            }
        }
        guard statements.count >= 3 else { return nil }
        // Every number is in a condition or a statement.
        guard numbers(in: lines[..<askedAt].map { $0.replacingOccurrences(of: #"^\d{1,2} (?=[A-Za-z] ?[<>≤≥])"#, with: "", options: .regularExpression) }.joined(separator: " ")).count
                == numbers(in: conditions.joined(separator: " ")).count,
              numbers(in: lines[askedAt]).isEmpty else { return nil }
        // Values to try: close to each end of what's allowed, small, about 1, large.
        func samples(_ letter: String) -> [Double] {
            let steps = [0.001, 0.25, 0.5, 1, 1.7, 3, 10, 1000]
            switch (low[letter], high[letter]) {
            case let (a?, b?): return [0.001, 0.1, 0.37, 0.5, 0.63, 0.9, 0.999].map { a + (b - a) * $0 }
            case let (a?, nil): return steps.map { a + $0 }
            case let (nil, b?): return steps.map { b - $0 }
            default: return []
            }
        }
        var points: [[String: Double]] = [[:]]
        for letter in letters { points = points.flatMap { point in samples(letter).map { var next = point; next[letter] = $0; return next } } }
        var always: [Int] = []
        for (index, statement) in statements.enumerated() {
            var allTrue = true
            for point in points {
                guard let l = statement.left.evaluate(point), let r = statement.right.evaluate(point), l.isFinite, r.isFinite else { return nil }
                // (Small numbers stay small when cubed: the margin goes by their size.)
                let margin = 1e-9 * max(abs(l), abs(r))
                let holds: Bool
                switch statement.relation {
                case "<": holds = l < r - margin
                case ">": holds = l > r + margin
                case "≤": holds = l <= r + margin
                case "≥": holds = l >= r - margin
                default: holds = abs(l - r) <= margin
                }
                if !holds { allTrue = false; break }
            }
            if allTrue { always.append(index) }
        }
        guard always.count == 1, let chosen = always.first else { return nil }
        // Numbers to show it with: whole ones that fit.
        var example: [String: Rational] = [:]
        for letter in letters {
            switch (low[letter], high[letter]) {
            case let (a?, b?): example[letter] = Rational.parse(String(format: "%.4f", (a + b) / 2))
            case let (a?, nil): example[letter] = Rational(Int(a.rounded(.down)) + 2)
            case let (nil, b?): example[letter] = Rational(Int(b.rounded(.up)) - 3)
            default: break
            }
        }
        guard example.count == letters.count else { return nil }
        func put(_ expr: Expr) -> Expr { Simplify.run(letters.reduce(expr) { $0.substituting($1, with: exact(example[$1]!)) }) }
        var tried: [MathLine] = []
        for statement in statements {
            for side in [statement.left, statement.right] where !side.symbols.isEmpty && !tried.contains(MathLine(side, put(side))) { tried.append(MathLine(side, put(side))) }
        }
        let answer = statements[chosen]
        let allowed = conditions.map { $0.replacingOccurrences(of: #" ?([<>≤≥]) ?"#, with: " $1 ", options: .regularExpression).replacingOccurrences(of: "-", with: "−") }.joined(separator: " and ")
        let lead = [Step("Try numbers that fit", "Take \(letters.map { "\($0) = \(shown(example[$0]!))" }.joined(separator: " and ")) and work out each expression.", tried),
                    Step("Check it's always so", "Only one statement stays true for every \(allowed).", [MathLine(answer.left, answer.right, relation: answer.relation)])]
        return told("the correct statement", [MathLine(answer.left, answer.right, relation: answer.relation)], lead)
    }

    /// The text as sentences: cut at a full stop or question mark that ends one.
    private static func sentences(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.?!])\s+(?=[A-Z(])"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let timeUnits = #"(hours?|minutes?|seconds?|days?|weeks?|months?|years?)"#

    /// "The number of hours, H, that some machines take to make 5000 bottles is given by H = 72/n
    /// where n is the number of machines. On Monday, 6 machines made 5000 bottles. On Tuesday,
    /// 9 machines made 5000 bottles. … How much more time?" A formula used for two cases that
    /// are told the same way, and the difference between its two answers.
    private static func formulaTwice(_ text: String) -> Problem? {
        guard let formula = groups(#"(?<![A-Za-z])([A-Za-z]) ?= ?(.+?),? where ([a-z]) is the number of ([a-z]+)\b"#, in: text),
              !has(#"[a-z]\d"#, formula[2]), let rule = Parser.expression(exactDecimals(formula[2])), rule.symbols == [formula[3].lowercased()], let shownRule = Parser.expression(formula[2]) else { return nil }
        let output = formula[1], input = formula[3].lowercased(), thing = formula[4].lowercased()
        guard output.lowercased() != input,
              has(#"\bhow (?:much|many) (?:more|less|longer|fewer)\b|\bwhat is the difference\b|\b(?:work out|find|calculate) the difference\b"#, text) else { return nil }
        // The two cases: sentences that each give a number of the things, and are otherwise the same after their first words.
        let all = sentences(text.replacingOccurrences(of: formula[0], with: " "))
        var cases: [(label: String, value: Rational, rest: String)] = []
        for sentence in all {
            let found = every("(?<![\\d.])(\\d+(?:\\.\\d+)?) \(thing)\\b", in: sentence)
            guard !found.isEmpty else { continue }
            guard found.count == 1, let value = rational(found[0][1]),
                  let split = groups(#"^(?:(?:On|In|At|For|During) )?(?:the )?([A-Z]?[a-z]+(?: \d+)?),? "#, in: sentence.replacingOccurrences(of: found[0][0], with: "\u{2}")) else { return nil }
            let rest = String(sentence.replacingOccurrences(of: found[0][0], with: "\u{2}").dropFirst(split[0].count))
            guard rest.contains("\u{2}") else { return nil }
            cases.append((split[1], value, rest))
        }
        guard cases.count == 2, cases[0].rest == cases[1].rest, cases[0].label != cases[1].label, cases[0].value != cases[1].value else { return nil }
        // Every other number is said the same way in both cases (5000 bottles), or is in the formula.
        let common = Set(numbers(in: cases[0].rest))
        let others = numbers(in: all.filter { every("(?<![\\d.])(\\d+(?:\\.\\d+)?) \(thing)\\b", in: $0).isEmpty }.joined(separator: " "))
        guard Set(others).isSubset(of: common) else { return nil }
        var results: [Rational] = []
        for item in cases {
            guard case .number(.exact(let value)) = Simplify.run(rule.substituting(input, with: exact(item.value))) else { return nil }
            results.append(value)
        }
        guard let difference = results[0] - results[1], !difference.isZero else { return nil }
        let size = difference > Rational(0) ? difference : difference.negated
        // What the formula gives: "the number of hours, H", "H hours".
        let unit = (groups("\\bnumber of \(timeUnits),? \(output)\\b", in: text) ?? groups("(?<![A-Za-z])\(output) \(timeUnits)\\b", in: text))?[1].lowercased()
        var suffix: String?
        if let unit {
            let single = unit.hasSuffix("s") ? String(unit.dropLast()) : unit
            suffix = size == Rational(1) ? single : single + "s"
        }
        let bigger = results[0] > results[1] ? 0 : 1
        let lead = [Step("Put each number of \(thing) into the formula", "",
                         zip(cases, results).map { MathLine(.symbol("\($0.0.label): \(output)"), shownRule.substituting(input, with: tidy($0.0.value)), tidy($0.1)) }),
                    Step("Take the smaller from the larger", "", [MathLine(.add([tidy(results[bigger]), .multiply([.minusOne, tidy(results[1 - bigger])])]), tidy(size))])]
        return told("difference", [MathLine(tidy(size), suffix: suffix)], lead)
    }

    /// "f is inversely proportional to d². f = 3.5 when d = 8. Find the positive value of d when
    /// f = 10. Give your answer correct to 3 significant figures." A proportion whose pair of
    /// values is on a line of its own, and the value asked for rounded the way it's asked.
    private static func proportionValue(_ lines: [String], _ text: String) -> Problem? {
        let rules = every(#"(?<![A-Za-z])([A-Za-z]) ?is (directly |inversely )?proportional to (the square root of |the square of |the cube of |the cube root of )?(√ ?)?([A-Za-z])(?: ?\^ ?\(?(\d)\)?|([²³])|([23])(?!\d|\.\d))?(?![A-Za-z^])"#, in: text)
        guard rules.count == 1, var rule = rules.first, every(#"proportional|\bvaries\b|∝"#, in: text).count == 1 else { return nil }
        // (Where the same lines also ask for the equation, there are two questions here and no telling which is meant.)
        guard !has(#"\b(?:an equation|a formula|an expression) (?:connecting|linking|for|in terms of)\b"#, text) else { return nil }
        // (A power that has dropped onto the line, "proportional to d2": a number straight after the letter there can only be its power.)
        if !rule[8].isEmpty { rule[6] = rule[8] }
        let y = rule[1], x = rule[5], inverse = rule[2].lowercased().hasPrefix("inverse")
        guard y != x, y.lowercased() != x.lowercased() else { return nil }
        // The power of x: "the square of d", "√d", "d^2".
        let words = rule[3].lowercased().trimmingCharacters(in: .whitespaces)
        let written = rule[6].isEmpty ? (rule[7] == "²" ? 2 : rule[7] == "³" ? 3 : 1) : (Int(rule[6]) ?? 0)
        guard (1...3).contains(written), [!words.isEmpty, !rule[4].isEmpty, written != 1].filter({ $0 }).count <= 1 else { return nil }
        var power = Rational(written)
        switch words {
        case "the square root of": power = Rational.make(1, 2)!
        case "the square of": power = Rational(2)
        case "the cube of": power = Rational(3)
        case "the cube root of": power = Rational.make(1, 3)!
        default: if !rule[4].isEmpty { power = Rational.make(1, 2)! }
        }
        // (The question's number before the first line: "12 f is inversely proportional to…".)
        let text = text.replacingOccurrences(of: #"^\d{1,2} (?=[A-Za-z] ?is\b)"#, with: "", options: .regularExpression)
        let value = #"(-?\d+(?:\.\d+)?)"#
        // The pair that fixes it: "f = 3.5 when d = 8", "when d = 8, f = 3.5".
        // (The letters as the rule writes them: a capital is another letter.)
        let pairs = every("(?<![A-Za-z])(?-i:\(y)) ?= ?\(value),? when (?-i:\(x)) ?= ?\(value)(?!\\d|\\.\\d)", in: text).map { (y: $0[1], x: $0[2], all: $0[0]) }
            + every("\\bwhen (?-i:\(x)) ?= ?\(value),? (?-i:\(y)) ?= ?\(value)(?!\\d|\\.\\d)", in: text).map { (y: $0[2], x: $0[1], all: $0[0]) }
        // What's asked: one letter's value at a value of the other.
        let asking = #"\b(?:find|work out|calculate|what is)(?: the)?( positive| negative)?(?: value of)? "#
        var asked = every("\(asking)(?-i:(\(x)|\(y))) when (?-i:(\(x)|\(y))) ?= ?\(value)(?!\\d|\\.\\d)", in: text)
        if asked.isEmpty {
            // The letters said in words: "The mass of an ornament is m grams. The height of the ornament is h centimetres. …
            // Work out the mass of an ornament of height 12 centimetres."
            var names: [String: String] = [:]
            for named in every(#"\bthe ([a-z]+) of (?:a|an|the) [a-z ]+? is (?-i:([A-Za-z])) [a-z]+\b"#, in: text) where named[2] == x || named[2] == y {
                guard names[named[1].lowercased()] == nil, !names.values.contains(named[2]) else { return nil }
                names[named[1].lowercased()] = named[2]
            }
            if names.count == 2 {
                let either = names.keys.sorted().joined(separator: "|")
                asked = every("\\b(?:work out|find|calculate) the (\(either)) of (?:a|an|the) [a-z ]+? (?:of|with|that has an?|when (?:the|its)) (\(either))(?: of| is| =)? ?\(value)(?: [a-z]+)?(?!\\d|\\.\\d)", in: text)
                    .compactMap { found in
                        guard let wanted = names[found[1].lowercased()], let given = names[found[2].lowercased()] else { return nil }
                        return [found[0], "", wanted, given, found[3]]
                    }
            }
        }
        guard asked.count == 1, let question = asked.first, question[2] != question[3] else { return nil }
        let given = pairs.filter { !question[0].contains($0.all) }
        guard given.count == 1, let pair = given.first, let y0 = rational(pair.y), let x0 = rational(pair.x), let target = rational(question[4]),
              x0 > Rational(0), !y0.isZero else { return nil }
        // Every number is in the rule, the pair or the question (or says how to round).
        var rest = [rule[0], pair.all, question[0]].reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }
        var figures: Int?, places: Int?
        if let rounding = groups(#"\b(?:correct )?to (\d|one|two|three|four) (significant figures?|decimal places?|s\.?f\.?|d\.?p\.?)"#, in: rest), let n = count(rounding[1]) {
            if rounding[2].lowercased().hasPrefix("s") { figures = n } else { places = n }
            rest = rest.replacingOccurrences(of: rounding[0], with: " ")
        }
        guard numbers(in: rest).isEmpty else { return nil }
        // y = k × xᵖ (or k ÷ xᵖ): k from the pair.
        let X = Expr.symbol(x), shape = Expr.power(X, exact(power))
        let general: Expr = inverse ? .multiply([.symbol("k"), .power(shape, .minusOne)]) : .multiply([.symbol("k"), shape])
        let at0 = Simplify.run(shape.substituting(x, with: exact(x0)))
        guard case .number(.exact(let scale)) = at0, !scale.isZero, let k = inverse ? y0 * scale : y0 / scale else { return nil }
        let exactFormula = Simplify.run(general.substituting("k", with: exact(k)))
        let formula = Simplify.run(general.substituting("k", with: tidy(k)))
        var lead = [Step("Write it as an equation", "\(y) is \(inverse ? "inversely" : "directly") proportional to \(Format.text(shape)), so there's a number k that links them.", [MathLine(.symbol(y), general)]),
                    Step("Find k", "Put in \(x) = \(Format.text(tidy(x0))) and \(y) = \(Format.text(tidy(y0))).", [MathLine(.symbol("k"), tidy(k))]),
                    Step("Write the formula", "", [MathLine(.symbol(y), formula)])]
        func rounded(_ number: Double) -> Expr? {
            var scaleBy = 1.0
            if let figures {
                guard number != 0 else { return nil }
                scaleBy = pow(10, Double(figures - 1) - floor(log10(abs(number))))
            } else if let places { scaleBy = pow(10, Double(places)) }
            let scaled = number * scaleBy
            // Not so near a halfway point that the last figure is in doubt.
            guard abs(abs(scaled - scaled.rounded(.down)) - 0.5) > 1e-6 else { return nil }
            return CircleDiagram.number(scaled.rounded() / scaleBy)
        }
        let wantsRounding = figures != nil || places != nil
        let how = figures.map { "\($0) significant figure\($0 == 1 ? "" : "s")" } ?? places.map { "\($0) decimal place\($0 == 1 ? "" : "s")" } ?? ""
        if question[2] == y {
            // Straight in: y at the x given.
            guard target > Rational(0), question[1].isEmpty, case .number(.exact(let result)) = Simplify.run(exactFormula.substituting(x, with: exact(target))) else { return nil }
            let answer = wantsRounding ? rounded(result.double) : tidy(result)
            guard let answer else { return nil }
            lead.append(Step("Put \(x) = \(Format.text(tidy(target))) in", wantsRounding && answer != tidy(result) ? "Round to \(how)." : "", [MathLine(.symbol(y), formula.substituting(x, with: tidy(target)), answer)]))
            return told("\(y) when \(x) = \(Format.text(tidy(target)))", [MathLine(.symbol(y), answer)], lead)
        }
        // The other way: xᵖ = k ÷ y (or y ÷ k), then the root.
        guard !target.isZero, let raised = inverse ? k / target : target / k, raised > Rational(0) else { return nil }
        // An even power has two answers: only where the question says which.
        let isEven = power.isInteger && power.numerator % 2 == 0
        let sign = question[1].trimmingCharacters(in: .whitespaces).lowercased()
        guard isEven ? !sign.isEmpty : sign != "negative" else { return nil }
        guard let inverted = Rational(1) / power else { return nil }
        let root = Simplify.run(.power(exact(raised), exact(inverted)))
        guard let size = root.evaluate(), size.isFinite, size > 0 else { return nil }
        let signedSize = sign == "negative" ? -size : size
        var answer: Expr
        if wantsRounding {
            guard let value = rounded(signedSize) else { return nil }
            answer = value
        } else if case .number(.exact(let whole)) = root {
            answer = tidy(sign == "negative" ? whole.negated : whole)
        } else {
            answer = sign == "negative" ? Simplify.run(.multiply([.minusOne, root])) : root
        }
        lead.append(Step("Put \(y) = \(Format.text(tidy(target))) in and solve", (isEven ? "Take the \(sign) root. " : "") + (wantsRounding ? "Round to \(how)." : ""),
                         [MathLine(tidy(target), formula), MathLine(shape, tidy(raised)), MathLine(.symbol(x), answer)]))
        return told("\(x) when \(y) = \(Format.text(tidy(target)))", [MathLine(.symbol(x), answer)], lead)
    }

    /// "Given that a is a prime number, rationalise the denominator of 1/(√a + 1). Give your
    /// answer in its simplest form." A root of a letter on the bottom, with or without a number
    /// added to it: top and bottom are multiplied by the bottom with its middle sign changed.
    private static func rationaliseLetter(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\brationali[sz]e the denominator\b"#, text) else { return nil }
        // The fraction: after "denominator of", or on a line of its own.
        var written: String?
        if let after = groups(#"\brationali[sz]e the denominator of:? (.+?)(?=\.? (?:give|write|express|simplify|leave)\b|\.?$)"#, in: text), Parser.expression(after[1]) != nil {
            written = after[1]
        } else {
            let lone = lines.filter { !has(#"[a-z]{3,}"#, $0) && $0.contains("√") }
            guard lone.count == 1 else { return nil }
            written = lone[0]
        }
        guard let written, let expr = Parser.expression(written), expr.symbols.count == 1, let a = expr.symbols.first, a.count == 1,
              numbers(in: text).count == numbers(in: written).count else { return nil }
        let (top, bottom) = Simplify.numeratorAndDenominator(Simplify.run(expr))
        guard let t = Simplify.run(top).number?.rational, t.isInteger, !t.isZero else { return nil }
        // The bottom: p√a, or p√a + q, in whole numbers.
        let root = Expr.power(.symbol(a), .half)
        var p: Int?, q: Int?
        let terms: [Expr] = if case .add(let parts) = bottom { parts } else { [bottom] }
        for term in terms {
            if let number = term.number?.rational {
                guard q == nil, number.isInteger, !number.isZero else { return nil }
                q = number.numerator
            } else {
                let (coefficient, rest) = Simplify.splitCoefficient(term)
                guard p == nil, rest == root, let number = coefficient.rational, number.isInteger, !number.isZero else { return nil }
                p = number.numerator
            }
        }
        guard let p else { return nil }
        func times(_ k: Int, _ e: Expr) -> Expr { k == 1 ? e : (k == -1 ? .multiply([.minusOne, e]) : .multiply([.integer(k), e])) }
        var answer: Expr, lead: [Step]
        if let q {
            // t/(p√a + q) × (p√a − q)/(p√a − q) = t(p√a − q)/(p²a − q²), then cancel.
            let c = Rational.gcd(abs(p), abs(q))
            var p1 = p / c, q1 = q / c
            let g = Rational.gcd(abs(t.numerator), c)
            var t1 = t.numerator / g
            let c1 = c / g
            // Written so that the root's own sign is a plus: (2 + √a)/(4 − a) for 1/(2 − √a).
            let rootFirst = p1 > 0
            if !rootFirst { p1 = -p1; q1 = -q1; t1 = -t1 }
            guard let pp = Rational.multiply(p1, p1), let qq = Rational.multiply(q1, q1) else { return nil }
            let conjugate = Simplify.run(.add([times(p1, root), .integer(-q1)]))
            var newBottom = Simplify.run(.add([times(pp, .symbol(a)), .integer(-qq)]))
            // (A minus sign in front goes into the bottom instead: 4 − k.)
            if t1 < 0 { t1 = -t1; newBottom = .add([.integer(qq), times(-pp, .symbol(a))]) }
            // (Shown the way it's done by hand: the bottom as it's written, with the middle sign changed.)
            let shownConjugate = Simplify.run(p > 0 ? .add([times(p, root), .integer(-q)]) : .add([.integer(q), times(-p, root)]))
            answer = .multiply([times(t1, conjugate), .power(times(c1, newBottom), .minusOne)])
            if t1 == 1 { answer = .multiply([conjugate, .power(times(c1, newBottom), .minusOne)]) }
            lead = [Step("Multiply the top and bottom by \(Format.text(shownConjugate))", "It's the bottom with the sign in the middle changed, so the roots cancel when the brackets are multiplied out.",
                         [MathLine(.multiply([bottom, shownConjugate]), Simplify.run(Simplify.expand(.multiply([bottom, shownConjugate]))))]),
                    Step("Write the fraction", c != 1 ? "Cancel anything the top and bottom share." : "", [MathLine(expr, answer)])]
        } else {
            // t/(p√a) × √a/√a = t√a/(pa), then cancel.
            let g = Rational.gcd(abs(t.numerator), abs(p))
            var t1 = t.numerator / g, p1 = p / g
            if p1 < 0 { t1 = -t1; p1 = -p1 }
            answer = .multiply([times(t1, root), .power(times(p1, .symbol(a)), .minusOne)])
            lead = [Step("Multiply the top and bottom by \(Format.text(root))", "\(Format.text(root)) × \(Format.text(root)) = \(a), so the root on the bottom goes.", [MathLine(expr, answer)])]
        }
        // It has to be the same number as the fraction, whatever the letter is.
        guard same(answer, expr) else { return nil }
        return told("rationalise \(Format.text(expr))", [MathLine(answer)], lead)
    }

    /// "Four numbers are written, in ascending order, as algebraic expressions: a, a + b, a + 2b,
    /// 3a − b. The mean of these four numbers is 27. The range of these four numbers is 24. Find
    /// the value of a and the value of b."
    private static func orderedExpressions(_ lines: [String], _ text: String) -> Problem? {
        let kind = #"(mean|range|median|sum|total)"#
        let facts = every(#"\bthe \#(kind) (?:of (?:these|the|all|all the) (?:(?:three|four|five|six|\d) )?(?:numbers|expressions|values|terms) )?is (-?\d+(?:\.\d+)?)(?!\d|\.\d)"#, in: text)
        guard !facts.isEmpty else { return nil }
        // The expressions: a row of them on a line of their own.
        var rows: [(exprs: [Expr], line: String)] = []
        for line in lines where !has(#"[a-z]{3,}"#, line) && !line.contains("=") {
            let pieces = choices(line.replacingOccurrences(of: ",", with: " ")).filter { !$0.isEmpty }
            let exprs = pieces.compactMap { Parser.expression($0) }
            guard pieces.count >= 3, exprs.count == pieces.count, exprs.contains(where: { !$0.symbols.isEmpty }) else { continue }
            // (A digit straight after a letter is a power that has dropped onto the line: not read.)
            guard !has(#"[a-z]\d"#, line) else { return nil }
            rows.append((exprs, line))
        }
        guard rows.count == 1, let row = rows.first?.exprs, let rowLine = rows.first?.line, row.count <= 8 else { return nil }
        if let said = groups(#"\b(three|four|five|six|seven|eight|\d) (?:numbers|expressions|values|terms)\b"#, in: text) { guard count(said[1]) == row.count else { return nil } }
        let unknowns = row.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }.sorted()
        guard (1...3).contains(unknowns.count), unknowns.allSatisfy({ $0.count == 1 }), facts.count == unknowns.count else { return nil }
        // The smallest and largest are only known where the question says they're in order.
        let ascending = has(#"\b(?:ascending|increasing) order\b|\bin order of size\b|\bin order,? (?:from )?(?:the )?smallest\b|\bsmallest first\b|\bfrom smallest to largest\b"#, text)
        let n = row.count
        var equations: [Expr] = [], working: [Step] = []
        var seen = Set<String>()
        for fact in facts {
            guard let value = rational(fact[2]), seen.insert(fact[1].lowercased()).inserted else { return nil }
            switch fact[1].lowercased() {
            case "mean":
                guard let total = value * Rational(n) else { return nil }
                let sum = Simplify.run(Simplify.expand(.add(row)))
                equations.append(.add([sum, exact(total.negated)]))
                working.append(Step("Write the mean as an equation", "The \(n) expressions add up to \(n) × \(shown(value)).", [MathLine(sum, exact(total))]))
            case "sum", "total":
                let sum = Simplify.run(Simplify.expand(.add(row)))
                equations.append(.add([sum, exact(value.negated)]))
                working.append(Step("Write the total as an equation", "", [MathLine(sum, exact(value))]))
            case "range":
                guard ascending else { return nil }
                let spread = Simplify.run(Simplify.expand(.add([row[n - 1], .multiply([.minusOne, row[0]])])))
                equations.append(.add([spread, exact(value.negated)]))
                working.append(Step("Write the range as an equation", "The range is the largest take away the smallest: the last expression take away the first.", [MathLine(spread, exact(value))]))
            default:
                guard ascending else { return nil }
                let middle = n % 2 == 1 ? row[n / 2] : Expr.multiply([.half, .add([row[n / 2 - 1], row[n / 2]])])
                let median = Simplify.run(Simplify.expand(middle))
                equations.append(.add([median, exact(value.negated)]))
                working.append(Step("Write the median as an equation", n % 2 == 1 ? "The median is the middle expression." : "The median is halfway between the two middle expressions.", [MathLine(median, exact(value))]))
            }
        }
        guard askedLetters(text) == Set(unknowns), let values = solveAll(equations, unknowns) else { return nil }
        // Every number is in the row or a fact.
        guard numbers(in: facts.map(\.[0]).reduce(text.replacingOccurrences(of: rowLine, with: " ")) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty else { return nil }
        // With the letters found the numbers have to be in the order the question says.
        var numbersFound: [Rational] = []
        for expr in row {
            guard case .number(.exact(let value)) = Simplify.run(unknowns.reduce(expr) { $0.substituting($1, with: exact(values[$1]!)) }) else { return nil }
            numbersFound.append(value)
        }
        if ascending { guard zip(numbersFound, numbersFound.dropFirst()).allSatisfy({ $0 < $1 || $0 == $1 }) else { return nil } }
        let pairs = unknowns.map { ($0, tidy(values[$0]!)) }
        let lead = working + [Step(unknowns.count == 1 ? "Solve it" : "Solve them together", "", pairs.map { MathLine(.symbol($0.0), $0.1) }),
                              Step("Check", "The numbers are \(numbersFound.map { Format.text(tidy($0)) }.joined(separator: ", "))\(ascending ? ", in order as they should be" : "").")]
        return told("values of \(unknowns.joined(separator: " and "))", [together(pairs)], lead)
    }

    /// "A particle has an initial velocity of 0 m/s. The particle accelerates uniformly at 3 m/s²
    /// for 4 seconds. Find the distance travelled by the particle in the 4 seconds." Three of
    /// u, v, a, t and s given in words, the fourth asked for, with the formulas v = u + at and
    /// v² = u² + 2as used the way the question gives them.
    private static func kinematics(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bkinematics\b"#, text) || (has(#"\buniform(?:ly)?\b|\bconstant(?:ly)?\b"#, text) && has(#"\b(?:accelerat|decelerat)"#, text)) else { return nil }
        // The formulas the question prints are lines of letters: not part of the story.
        func isFormula(_ line: String) -> Bool { line.contains("=") && !has(#"[a-z]{3,}"#, line) && has(#"^[a-zA-Zư0-9^²½+\-=/(). ]+$"#, line) && !has(#"\d ?[a-z]/"#, line) }
        let printed = lines.filter(isFormula).map { $0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "ư", with: "u").replacingOccurrences(of: "^2", with: "²") }
        let story = lines.filter { !isFormula($0) }.joined(separator: " ")
        let number = #"(\d+(?:\.\d+)?)"#, speed = #"(?:m/s|ms\^?\(?-1\)?|metres per second)(?![\w^²/])"#
        var known: [String: Rational] = [:], used: [String] = []
        func take(_ name: String, _ pattern: String, _ value: (([String]) -> Rational?)) -> Bool {
            for match in every(pattern, in: story) {
                // (Said twice, it has to be the same both times.)
                guard let amount = value(match), known[name] == nil || known[name] == amount else { return false }
                known[name] = amount
                used.append(match[0])
            }
            return true
        }
        // "After 20 seconds the particle has a velocity of 11 m/s": the time and the velocity then.
        if let later = groups(#"\bafter \#(number) seconds,? (?:the [a-z]+|it) has a (?:velocity|speed) of \#(number) ?\#(speed)"#, in: story),
           let time = rational(later[1]), let end = rational(later[2]) {
            known["t"] = time; known["v"] = end
            used.append(later[0])
        }
        guard take("u", #"\binitial (?:velocity|speed) (?:of|is|=) \#(number) ?\#(speed)"#, { rational($0[1]) }),
              take("u", #"\b(?:starts?|starting|accelerates(?: uniformly)?|moves off) from rest\b|\binitially at rest\b"#, { _ in Rational(0) }),
              take("v", #"\b(?:final (?:velocity|speed) (?:of|is|=)|(?:reaches|to) a (?:velocity|speed) of|until (?:its|the) (?:velocity|speed) is) \#(number) ?\#(speed)"#, { rational($0[1]) }),
              take("a", #"\b(accelerates|decelerates)(?: uniformly| constantly)?(?: from rest)? at(?: a(?: constant| uniform)? rate of)? \#(number) ?m/s(?: ?\^ ?\(?2\)?|²|2)?(?![\w^/])"#,
                   { m in rational(m[2]).map { m[1].lowercased() == "decelerates" ? $0.negated : $0 } }),
              take("a", #"\b(?:constant|uniform) acceleration of \#(number) ?m/s(?: ?\^ ?\(?2\)?|²|2)?(?![\w^/])"#, { rational($0[1]) }),
              take("t", #"\bfor \#(number) (?:seconds|s)\b"#, { rational($0[1]) }),
              take("s", #"\b(?:travels|covers|moves)(?: a distance of)? \#(number) ?(?:m|metres)\b"#, { rational($0[1]) }) else { return nil }
        // What's asked for.
        let asked = every(#"\b(?:find|work out|calculate)(?: the)? (distance|final velocity|final speed|velocity|speed|acceleration|time)\b[^.?]*"#, in: story)
        guard asked.count == 1, let question = asked.first else { return nil }
        let wanted: String
        switch question[1].lowercased() {
        case "distance": wanted = "s"
        case "acceleration": wanted = "a"
        case "time": wanted = "t"
        default: wanted = "v"
        }
        guard known.count == 3, known[wanted] == nil else { return nil }
        // Every number is one of those; the question may say the time again ("in the 4 seconds").
        var rest = used.reduce(story) { $0.replacingOccurrences(of: $1, with: " ") }
        if let t = known["t"] { rest = rest.replacingOccurrences(of: "\\b(?:in|after|during) (?:the |these )?\(shown(t)) seconds\\b", with: " ", options: [.regularExpression, .caseInsensitive]) }
        guard numbers(in: rest.replacingOccurrences(of: #"^\d{1,2} (?=[A-Za-z])"#, with: "", options: .regularExpression)).isEmpty else { return nil }
        func n(_ value: Rational) -> Expr { tidy(value) }
        let u = known["u"], v = known["v"], a = known["a"], t = known["t"], s = known["s"]
        let half = Rational.make(1, 2)!
        var answer: Rational?, lead: [Step] = []
        switch (wanted, u, v, a, t, s) {
        case let ("s", u?, nil, a?, t?, nil):
            guard let at = a * t, let end = u + at, let ut = u * t, let tt = t * t, let att = (a * tt).flatMap({ $0 * half }), let distance = ut + att else { return nil }
            answer = distance
            let givesBoth = printed.contains("v=u+at") && printed.contains(where: { has(#"^v²=.²\+2as$"#, $0) })
            if givesBoth, !printed.contains(where: { $0.hasPrefix("s=") }), !a.isZero {
                // With only v = u + at and v² = u² + 2as to use: the final velocity first.
                lead = [Step("Find the final velocity", "Use v = u + at with u = \(shown(u)), a = \(Format.text(n(a))) and t = \(Format.text(n(t))).",
                             [MathLine(.symbol("v"), .add([n(u), .multiply([n(a), n(t)])]), n(end))]),
                        Step("Use v² = u² + 2as", "Put in v = \(Format.text(n(end))), u = \(shown(u)) and a = \(Format.text(n(a))), then solve for s.",
                             [MathLine(.power(n(end), .two), .add([.power(n(u), .two), .multiply([.two, n(a), .symbol("s")])])), MathLine(.symbol("s"), n(distance))])]
            } else {
                lead = [Step("Use s = ut + ½at²", "Put in u = \(shown(u)), a = \(Format.text(n(a))) and t = \(Format.text(n(t))).",
                             [MathLine(.symbol("s"), .add([.multiply([n(u), n(t)]), .multiply([.half, n(a), .power(n(t), .two)])]), n(distance))])]
            }
        case let ("v", u?, nil, a?, t?, nil):
            guard let at = a * t, let end = u + at else { return nil }
            answer = end
            lead = [Step("Use v = u + at", "", [MathLine(.symbol("v"), .add([n(u), .multiply([n(a), n(t)])]), n(end))])]
        case let ("a", u?, v?, nil, t?, nil):
            guard !t.isZero, let change = v - u, let rate = change / t else { return nil }
            answer = rate
            lead = [Step("Use v = u + at", "Put in the numbers and solve for a.", [MathLine(n(v), .add([n(u), .multiply([n(t), .symbol("a")])])), MathLine(.symbol("a"), n(rate))])]
        case let ("t", u?, v?, a?, nil, nil):
            guard !a.isZero, let change = v - u, let time = change / a, time > Rational(0) else { return nil }
            answer = time
            lead = [Step("Use v = u + at", "Put in the numbers and solve for t.", [MathLine(n(v), .add([n(u), .multiply([n(a), .symbol("t")])])), MathLine(.symbol("t"), n(time))])]
        case let ("s", u?, v?, a?, nil, nil):
            guard !a.isZero, let vv = v * v, let uu = u * u, let top = vv - uu, let distance = (top / a).flatMap({ $0 * half }) else { return nil }
            answer = distance
            lead = [Step("Use v² = u² + 2as", "Put in the numbers and solve for s.",
                         [MathLine(.power(n(v), .two), .add([.power(n(u), .two), .multiply([.two, n(a), .symbol("s")])])), MathLine(.symbol("s"), n(distance))])]
        case let ("s", u?, v?, nil, t?, nil):
            guard !t.isZero, let sum = u + v, let distance = (sum * t).flatMap({ $0 * half }), let change = v - u, let rate = change / t else { return nil }
            answer = distance
            if printed.contains("v=u+at"), printed.contains(where: { $0.hasPrefix("s=ut+") }) {
                // With v = u + at and s = ut + ½at² to use: the acceleration first.
                lead = [Step("Find the acceleration", "Use v = u + at with v = \(Format.text(n(v))), u = \(Format.text(n(u))) and t = \(Format.text(n(t))).",
                             [MathLine(n(v), .add([n(u), .multiply([n(t), .symbol("a")])])), MathLine(.symbol("a"), n(rate))]),
                        Step("Use s = ut + ½at²", "", [MathLine(.symbol("s"), .add([.multiply([n(u), n(t)]), .multiply([.half, n(rate), .power(n(t), .two)])]), n(distance))])]
            } else {
                lead = [Step("Use s = ½(u + v)t", "The average of the two velocities, times the time.", [MathLine(.symbol("s"), .multiply([.half, .add([n(u), n(v)]), n(t)]), n(distance))])]
            }
        default:
            return nil
        }
        guard let answer, wanted == "a" || answer > Rational(0) || answer.isZero else { return nil }
        let unit = ["s": "m", "v": "m/s", "a": "m/s²", "t": "seconds"][wanted]
        return told(question[1].lowercased(), [MathLine(tidy(answer), suffix: unit)], lead)
    }

    /// "The number of bees, P, in a colony is given by the formula P = abˣ where x is the number
    /// of months after the start of July. At the start of July, there were 25 000 bees in the
    /// colony. After one month, there were 23 500 bees. Find the value of a and the value of b."
    /// Also with dates: "On 1st November 2015 there were 4200 trees… On 1st November 2016, only
    /// 3948… N = arᵗ where N is the number of trees still alive t years after 1st November 2015.
    /// Write down the value of a."
    private static func grownFrom(_ lines: [String], _ text: String) -> Problem? {
        // The formula, on a line of its own: a × bˣ in letters.
        let formulas = lines.compactMap { groups(#"^(?-i:([A-Za-z])) ?= ?([a-z]) ?[×*]? ?([a-z]) ?\^ ?\(?([a-z])\)?\.?$"#, in: $0) }
        guard formulas.count == 1, let formula = formulas.first else { return nil }
        let output = formula[1], a = formula[2].lowercased(), b = formula[3].lowercased(), x = formula[4].lowercased()
        let asked = askedLetters(text)
        guard Set([output.lowercased(), a, b, x]).count == 4, !asked.isEmpty, asked.isSubset(of: [a, b]) else { return nil }
        // What x counts, and from when: "x is the number of months after the start of July", "t years after 1st November 2015".
        let counting = lines.compactMap { groups("^where (?:\(x) is the number of|.+? \(x)) (months|years|weeks|days|hours|minutes) (?:after|since|from) (.+?)\\.?$", in: $0) }
        guard counting.count == 1, let counted = counting.first else { return nil }
        let unit = String(counted[1].lowercased().dropLast())
        // (A date's small "st" can be read raised, or cut short: 1^(st), 1s.)
        let day = #"\d{1,2}(?:\^?\(?[a-z]{1,2}\)?)?"#
        let origin = counted[2].replacingOccurrences(of: "^(\(day)) ", with: "", options: .regularExpression)
        guard has(#"^(?:the )?(?:start|beginning|end) of (?:the year )?(?:\d{4}|[A-Za-z]+)$|^[A-Za-z]+ \d{4}$"#, origin) else { return nil }
        let year = groups(#"\b(\d{4})$"#, in: origin).flatMap { Int($0[1]) }
        // The same time in another year, where the origin names a year.
        let other = NSRegularExpression.escapedPattern(for: origin).replacingOccurrences(of: #"\d{4}$"#, with: #"(\\d{4})"#, options: .regularExpression)
        // (Thousands may be written with a gap: 23 500.)
        let amount = #"(?<![\d.])(\d{1,3}(?:[ ,]\d{3})+|\d+(?:\.\d+)?)(?!\d|\.\d)"#
        func value(_ written: String) -> Rational? { rational(written.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")) }
        // The amounts: each in a sentence that says when, and has no other number.
        var amounts: [Int: Rational] = [:], used = [formula[0], counted[0]]
        for sentence in lines.flatMap({ sentences($0) }) where sentence != formula[0] && sentence != counted[0] && sentence.contains(where: \.isNumber) {
            var k: Int?, rest = sentence
            if let after = groups("^after (one|two|three|four|five|six|\\d{1,2}) \(unit)s?\\b", in: sentence), let n = count(after[1]) {
                k = n; rest = rest.replacingOccurrences(of: after[0], with: " ")
            } else if let at = groups("^(?:on|at|in|by) (?:\(day) )?\(other)(?![\\d.])", in: sentence) {
                if let year { guard at.count > 1, let then = Int(at[1]), unit == "year" || then == year else { return nil }; k = then - year } else { k = 0 }
                rest = rest.replacingOccurrences(of: at[0], with: " ")
            }
            guard let k, (0...12).contains(k), amounts[k] == nil, let found = groups(amount, in: rest), let size = value(found[1]), size > Rational(0),
                  numbers(in: rest.replacingOccurrences(of: found[0], with: " ")).isEmpty else { continue }
            amounts[k] = size
            used.append(sentence)
        }
        // Every number is in the formula's line, the line that says what x counts, or one of those sentences.
        guard let first = amounts[0], amounts.count <= 2, numbers(in: used.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty else { return nil }
        // a is the amount at the start (b⁰ = 1); b is what it's multiplied by each time.
        let A = Expr.symbol(a), B = Expr.symbol(b)
        let start = counted[2].replacingOccurrences(of: #"\^\(([a-z]{1,2})\)"#, with: "$1", options: .regularExpression)
        var lead = [Step("Put \(x) = 0 in", "\(x) counts from \(start), so the amount then is \(a) × \(b)⁰, and \(b)⁰ = 1.", [MathLine(.symbol(output), .multiply([A, .power(B, .zero)]), A), MathLine(A, tidy(first))])]
        var found: [(String, Expr)] = asked.contains(a) ? [(a, tidy(first))] : []
        if asked.contains(b) {
            guard let later = amounts.first(where: { $0.key > 0 }), let ratio = later.value / first else { return nil }
            var rate = ratio
            if later.key > 1 {
                guard let top = Rational.exactRoot(ratio.numerator, later.key), let bottom = Rational.exactRoot(ratio.denominator, later.key), let root = Rational.make(top, bottom) else { return nil }
                rate = root
            }
            lead.append(Step("Put \(x) = \(later.key) in", "", [MathLine(.multiply([tidy(first), later.key == 1 ? B : .power(B, .integer(later.key))]), tidy(later.value)), MathLine(B, tidy(rate))]))
            found.append((b, tidy(rate)))
        }
        return told("value\(found.count == 1 ? "" : "s") of \(found.map(\.0).joined(separator: " and "))", [together(found)], lead)
    }

    /// "x km/h = y mph. Use 8 km/h = 5 mph to write a formula for y in terms of x."
    private static func conversionFormula(_ text: String) -> Problem? {
        let unit = #"([A-Za-z]+(?:/[A-Za-z]+)?[²³]?)"#
        guard let pair = groups(#"(?<![A-Za-z])(?-i:([a-z])) ?\#(unit) ?= ?(?-i:([a-z])) ?\#(unit)(?![A-Za-z/])"#, in: text),
              let wanted = groups(#"\b(?:write|work out|find|give)(?: down)? (?:a|the) formula for (?-i:([a-z])) in terms of (?-i:([a-z]))\b"#, in: text) else { return nil }
        let first = pair[1], firstUnit = pair[2], second = pair[3], secondUnit = pair[4]
        guard first != second, firstUnit.lowercased() != secondUnit.lowercased(), Set([wanted[1], wanted[2]]) == Set([first, second]) else { return nil }
        // The fact to use: "8 km/h = 5 mph", either way round.
        let number = #"(\d+(?:\.\d+)?)"#
        func fact(_ a: String, _ b: String) -> [String]? {
            groups("(?<![\\d.])\(number) ?\(NSRegularExpression.escapedPattern(for: a)) ?= ?\(number) ?\(NSRegularExpression.escapedPattern(for: b))(?![A-Za-z/])", in: text)
        }
        var amounts: (first: Rational, second: Rational)?, used = ""
        if let found = fact(firstUnit, secondUnit), let p = rational(found[1]), let q = rational(found[2]) { amounts = (p, q); used = found[0] }
        else if let found = fact(secondUnit, firstUnit), let q = rational(found[1]), let p = rational(found[2]) { amounts = (p, q); used = found[0] }
        guard let amounts, amounts.first > Rational(0), amounts.second > Rational(0),
              numbers(in: text.replacingOccurrences(of: used, with: " ")).isEmpty else { return nil }
        // p of the first unit is q of the second: second = (q ÷ p) × first.
        let toSecond = wanted[1] == second
        guard let factor = toSecond ? amounts.second / amounts.first : amounts.first / amounts.second else { return nil }
        let from = toSecond ? first : second, to = toSecond ? second : first
        let fromUnit = toSecond ? firstUnit : secondUnit, toUnit = toSecond ? secondUnit : firstUnit
        let formula = Simplify.run(.multiply([exact(factor), .symbol(from)]))
        let lead = [Step("Find what 1 \(fromUnit) is", "\(used.replacingOccurrences(of: " ?= ?", with: " = ", options: .regularExpression)), so 1 \(fromUnit) is \(shown(factor)) \(toUnit).", []),
                    Step("Write the formula", "\(from) \(fromUnit) is \(from) times as much.", [MathLine(.symbol(to), formula)])]
        return told("formula for \(to)", [MathLine(.symbol(to), formula)], lead)
    }

    /// "The nth term of a sequence is n(n − 4)/√(n + 3). Work out the sum of the 1st and 6th terms."
    private static func termsCombined(_ lines: [String], _ text: String) -> Problem? {
        let ordinal = #"(\d{1,3}(?:st|nd|rd|th)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)"#
        guard has(#"\bnth term\b"#, text),
              let asked = groups(#"\b(?:work out|find|calculate) the (sum|difference|product) (?:of|between) the \#(ordinal) (?:term )?and (?:the )?\#(ordinal) terms?\b"#, in: text),
              let i = position(asked[2]), let j = position(asked[3]), i != j, i >= 1, j >= 1 else { return nil }
        // The rule: after "the nth term … is", or (a fraction read above its sentence) on a line of its own.
        var written: String?
        if let after = groups(#"\bnth term (?:of (?:a|the|this) sequence )?is (?:given by )?(.+?)(?=\.? (?:work out|find|calculate)\b|\.?$)"#, in: text),
           let expr = Parser.expression(after[1]), expr.symbols == ["n"] {
            written = after[1]
        } else {
            let lone = lines.filter { !has(#"[a-z]{2,}"#, $0) && $0.contains("n") && !$0.contains("=") }
            guard lone.count == 1 else { return nil }
            written = lone[0]
        }
        guard let written, !has(#"[a-z]\d"#, written), let rule = Parser.expression(exactDecimals(written)), rule.symbols == ["n"], !hasConstant(rule),
              numbers(in: text.replacingOccurrences(of: asked[0], with: " ")).count == numbers(in: written).count else { return nil }
        guard case .number(.exact(let a)) = Simplify.run(rule.substituting("n", with: .integer(i))),
              case .number(.exact(let b)) = Simplify.run(rule.substituting("n", with: .integer(j))) else { return nil }
        let kind = asked[1].lowercased()
        let result: Rational?
        switch kind {
        case "sum": result = a + b
        case "product": result = a * b
        default: result = a > b ? a - b : b - a
        }
        guard let result else { return nil }
        let combined: Expr = kind == "sum" ? .add([exact(a), exact(b)]) : kind == "product" ? .multiply([exact(a), exact(b)])
            : .add([exact(a > b ? a : b), .multiply([.minusOne, exact(a > b ? b : a)])])
        let lead = [Step("Put each term's number in for n", "", [MathLine(.symbol("\(asked[2]) term"), rule.substituting("n", with: .integer(i)), exact(a)),
                                                               MathLine(.symbol("\(asked[3]) term"), rule.substituting("n", with: .integer(j)), exact(b))]),
                    Step(kind == "sum" ? "Add them" : kind == "product" ? "Multiply them" : "Take the smaller from the larger", "", [MathLine(combined, exact(result))])]
        return told("\(kind) of the \(asked[2]) and \(asked[3]) terms", [MathLine(exact(result))], lead)
    }

    /// "After the first two terms, each term is the sum of the previous two terms. The 1st term
    /// is 33. The 2nd term is x. The 4th term is 73. Work out the value of x."
    private static func sumOfTwoBefore(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\b(?:sum of|add(?:ing)?(?: together)?) the (?:previous two|last two|two previous) terms\b|\bfibonacci"#, text) else { return nil }
        let ordinal = #"(\d{1,2}(?:st|nd|rd|th)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)"#
        // Each fact is a sentence of its own: "The 2nd term is x" (not "…is a square number").
        var given: [Int: Expr] = [:], written: [String] = []
        for sentence in lines.flatMap({ sentences($0) }) {
            guard let fact = groups(#"^the \#(ordinal) term(?: of (?:the|this) sequence)? is (-?\d+(?:\.\d+)?|(?-i:[a-z]))\.?$"#, in: sentence), let k = position(fact[1]) else { continue }
            guard given[k] == nil, (1...15).contains(k) else { return nil }
            given[k] = rational(fact[2]).map(exact) ?? .symbol(fact[2])
            written.append(sentence)
        }
        // The first two terms start it off; the terms after them have to be numbers.
        guard let first = given[1], let second = given[2], let last = given.keys.max(), last >= 3,
              given.allSatisfy({ $0.key <= 2 || $0.value.symbols.isEmpty }) else { return nil }
        let unknowns = first.symbols.union(second.symbols).sorted()
        guard !unknowns.isEmpty, given.count - 2 == unknowns.count, askedLetters(text) == Set(unknowns),
              numbers(in: written.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }).isEmpty else { return nil }
        var terms = [first, second]
        for _ in 3...last { terms.append(Simplify.run(Simplify.expand(.add([terms[terms.count - 2], terms[terms.count - 1]])))) }
        let known = given.keys.filter { $0 > 2 }.sorted()
        let equations = known.map { Expr.add([terms[$0 - 1], .multiply([.minusOne, given[$0]!])]) }
        guard let values = solveAll(equations, unknowns) else { return nil }
        let pairs = unknowns.map { ($0, tidy(values[$0]!)) }
        let lead = [Step("Write the terms in order", "Each term is the two before it added together.", terms.indices.map { MathLine(.symbol("\(ordinalName($0 + 1)) term"), terms[$0]) }),
                    Step(known.count == 1 ? "Use the term you're told" : "Use the terms you're told", "", known.map { MathLine(terms[$0 - 1], given[$0]!) }),
                    Step(unknowns.count == 1 ? "Solve it" : "Solve them together", "", pairs.map { MathLine(.symbol($0.0), $0.1) })]
        return told("value\(unknowns.count == 1 ? "" : "s") of \(unknowns.joined(separator: " and "))", [together(pairs)], lead)
    }

    /// "The cross section of a prism has n sides. Circle the expression for the number of edges
    /// of the prism.  2n + 3   2n   3n   n + 2", and "Circle the expression for the range of n
    /// consecutive integers": a fact about n, picked out from the choices.
    private static func circledFact(_ lines: [String], _ text: String) -> Problem? {
        guard let askedAt = lines.firstIndex(where: { has(#"\b(?:circle|choose|write down|which is) the (?:correct )?expression for the\b"#, $0) }) else { return nil }
        var expected: Expr?, letter = "", reason = ""
        if let prism = groups(#"\bcross[- ]section of a prism has (?-i:([a-z])) sides\b"#, in: text),
           let wanted = groups(#"\bexpression for the (?:total )?number of (edges|faces|vertices) of the prism\b"#, in: lines[askedAt]) {
            letter = prism[1]
            let n = Expr.symbol(letter)
            switch wanted[1].lowercased() {
            case "edges": expected = .multiply([.integer(3), n]); reason = "Each end has \(letter) edges, and \(letter) more edges join the two ends."
            case "faces": expected = .add([n, .two]); reason = "There are the 2 ends, and \(letter) faces round the sides."
            default: expected = .multiply([.two, n]); reason = "Each of the 2 ends has \(letter) corners."
            }
        } else if let run = groups(#"\bexpression for the range of (?-i:([a-z])) consecutive (?:integers|whole numbers|numbers)\b"#, in: lines[askedAt]) {
            letter = run[1]
            expected = .add([.symbol(letter), .minusOne])
            reason = "Each one is 1 more than the one before, so the last is \(letter) − 1 more than the first."
        }
        guard let expected, numbers(in: lines[...askedAt].joined(separator: " ")).isEmpty else { return nil }
        // The choices: the lines after the question, down to the next line of words. Every one has to be read.
        var written: [String] = []
        for line in lines[(askedAt + 1)...] {
            if has(#"[a-z]{3,}"#, line) { break }
            // (An n among them is sometimes read as Cyrillic п.)
            written += choices(letter == "n" ? line.replacingOccurrences(of: "п", with: "n") : line)
        }
        let parsed = written.compactMap { Parser.expression($0) }
        guard written.count >= 3, parsed.count == written.count, parsed.allSatisfy({ $0.symbols.isSubset(of: [letter]) && !hasConstant($0) }),
              !written.contains(where: { has(#"[a-z]\d"#, $0) }) else { return nil }
        let matching = parsed.filter { same($0, expected) }
        guard matching.count == 1 else { return nil }
        let lead = [Step("Count them", reason, [MathLine(Simplify.run(expected))])]
        return told("the expression", [MathLine(Simplify.run(matching[0]))], lead)
    }

    // MARK: Inequalities

    private static func flipped(_ relation: String) -> String {
        ["<": ">", ">": "<", "≤": "≥", "≥": "≤"][relation] ?? relation
    }

    /// "Solve 20 − 5x ≤ 30", "n is an integer. −3 < 2n ≤ 7. Write down all the possible values of n."
    private static func inequality(_ lines: [String], _ text: String) -> Problem? {
        let wantsWhole = has(#"\b(?:integers?|whole numbers?)\b"#, text)
        guard has(#"\bsolve\b"#, text) || wantsWhole, !has(#"error interval|nearest|decimal place|significant|rounded|truncated"#, text) else { return nil }
        // The one line with an inequality in it, after the word "solve" if it's on that line.
        var found: [(String, [String], [Expr])] = []
        for line in lines {
            let maths = line.replacingOccurrences(of: #"(?i)^.*?\b(?:solve|where|and|if|satisf(?:y|ies|ying))(?: the inequality)?\b:?\s*"#, with: "", options: .regularExpression)
            guard maths.range(of: "[<>≤≥]", options: .regularExpression) != nil else { continue }
            let pieces = every(#"([^<>≤≥]+)([<>≤≥]|$)"#, in: maths)
            var sides: [Expr] = [], relations: [String] = []
            for piece in pieces where !piece[1].trimmingCharacters(in: .whitespaces).isEmpty {
                guard let side = Parser.expression(piece[1].trimmingCharacters(in: CharacterSet(charactersIn: " ."))), !hasConstant(side) else { return nil }
                sides.append(side)
                if !piece[2].isEmpty { relations.append(piece[2]) }
            }
            guard sides.count == relations.count + 1, (1...2).contains(relations.count) else { return nil }
            found.append((maths, relations, sides))
        }
        guard found.count == 1, let (maths, relations, sides) = found.first else { return nil }
        let written = maths.replacingOccurrences(of: "-", with: "−")
        let letters = sides.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }
        guard letters.count == 1, let x = letters.first else { return nil }
        // The numbers are all in the inequality.
        guard numbers(in: text).count == numbers(in: written).count else { return nil }
        let name = Expr.symbol(x)
        func linear(_ e: Expr) -> (slope: Rational, constant: Rational)? {
            guard let c = Simplify.run(e.substituting(x, with: .zero)).number?.rational,
                  let one = Simplify.run(e.substituting(x, with: .one)).number?.rational, let s = one - c,
                  let three = Simplify.run(e.substituting(x, with: .integer(3))).number?.rational,
                  let expected = (s * Rational(3)).flatMap({ $0 + c }), three == expected else { return nil }
            return (s, c)
        }
        var lead: [Step] = []
        var low: (Rational, Bool)?, high: (Rational, Bool)?
        if relations.count == 1 {
            let difference = Expr.add([sides[0], .multiply([.minusOne, sides[1]])])
            guard let (p, q) = linear(difference), !p.isZero, let bound = q.negated / p else { return nil }
            let relation = p < Rational(0) ? flipped(relations[0]) : relations[0]
            lead.append(Step("Get \(x) on one side and the numbers on the other", "Do the same to both sides, as with an equation.",
                             [MathLine(.multiply([exact(p), name]), exact(q.negated), relation: relations[0])]))
            lead.append(Step("Divide both sides by \(shown(p))", p < Rational(0) ? "Dividing by a negative number turns the inequality sign round." : "",
                             [MathLine(name, exact(bound), relation: relation)]))
            if relation == "<" || relation == "≤" { high = (bound, relation == "≤") } else { low = (bound, relation == "≥") }
            if !wantsWhole { return told("solve \(written)", [MathLine(name, exact(bound), relation: relation)], lead) }
        } else {
            // a < px + q ≤ b: the outsides are numbers, the middle has the letter.
            guard let a = Simplify.run(sides[0]).number?.rational, let b = Simplify.run(sides[2]).number?.rational,
                  let (p, q) = linear(sides[1]), !p.isZero, Set(relations).isSubset(of: ["<", "≤"]) || Set(relations).isSubset(of: [">", "≥"]),
                  let a1 = a - q, let b1 = b - q, let lowEnd = a1 / p, let highEnd = b1 / p else { return nil }
            var rel = relations, ends = (lowEnd, highEnd)
            let middle = Format.text(Simplify.run(.multiply([exact(p), name])))
            if !q.isZero {
                lead.append(Step(q > Rational(0) ? "Take \(shown(q)) from all three parts" : "Add \(shown(q.negated)) to all three parts", "",
                                 [MathLine(.symbol("\(shown(a1)) \(rel[0]) \(middle) \(rel[1]) \(shown(b1))"))]))
            }
            if p < Rational(0) { rel = [flipped(rel[0]), flipped(rel[1])] }
            if p != Rational(1) {
                lead.append(Step("Divide all three parts by \(shown(p))", p < Rational(0) ? "Dividing by a negative number turns the inequality signs round." : "",
                                 [MathLine(.symbol("\(shown(ends.0)) \(rel[0]) \(x) \(rel[1]) \(shown(ends.1))"))]))
            }
            // Written low to high.
            if rel[0] == "<" || rel[0] == "≤" {
                low = (ends.0, rel[0] == "≤"); high = (ends.1, rel[1] == "≤")
            } else {
                high = (ends.0, rel[0] == "≥"); low = (ends.1, rel[1] == "≥"); ends = (ends.1, ends.0)
            }
            if !wantsWhole {
                guard let low, let high else { return nil }
                return told("solve \(written)", [MathLine(.symbol("\(shown(low.0)) \(low.1 ? "≤" : "<") \(x) \(high.1 ? "≤" : "<") \(shown(high.0))"))], lead)
            }
        }
        // Whole numbers: the ones in range, the largest, or the smallest.
        func first(after bound: (Rational, Bool)) -> Int { let floor = Int((bound.0.double).rounded(.down)); return bound.0.isInteger && bound.1 ? floor : floor + 1 }
        func last(before bound: (Rational, Bool)) -> Int { let ceiling = Int((bound.0.double).rounded(.up)); return bound.0.isInteger && bound.1 ? ceiling : ceiling - 1 }
        if has(#"\b(?:largest|greatest|biggest|highest)\b"#, text), let high, low.map({ first(after: $0) <= last(before: high) }) ?? true {
            let value = last(before: high)
            lead.append(Step("Take the largest whole number", "", [MathLine(name, .integer(value))]))
            return told("largest whole-number \(x)", [MathLine(name, .integer(value))], lead)
        }
        if has(#"\b(?:smallest|least|lowest)\b"#, text), let low, high.map({ first(after: low) <= last(before: $0) }) ?? true {
            let value = first(after: low)
            lead.append(Step("Take the smallest whole number", "", [MathLine(name, .integer(value))]))
            return told("smallest whole-number \(x)", [MathLine(name, .integer(value))], lead)
        }
        guard has(#"\b(?:all|list|possible|which)\b.*\bvalues?\b|\bvalues? of [a-z]\b"#, text), let low, let high else { return nil }
        let from = first(after: low), to = last(before: high)
        guard from <= to, to - from <= 30 else { return nil }
        let values = Array(from...to)
        lead.append(Step("List the whole numbers in between", "", [MathLine(name, .symbol(values.map { Format.number(.integer($0)) }.joined(separator: ", ")))]))
        return told("whole-number values of \(x)", [MathLine(.symbol(values.map { Format.number(.integer($0)) }.joined(separator: ", ")))], lead)
    }
}
