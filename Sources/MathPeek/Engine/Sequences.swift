import Foundation

/// Sequences: questions asked in words about an nth term ("The nth term is an² + bn. The 2nd
/// term is 2 …"), and finding the nth term of a list of numbers.
enum Sequences {
    private static let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
                                   "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10]
    private static let number = #"-?\d+(?:\.\d+)?(?:/\d+)?"#
    private static let place = #"(\d+)\s*(?:st|nd|rd|th)|(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)"#

    /// Every match of a pattern, as its captured groups.
    private static func matches(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }

    /// 2 from "2nd" or "second".
    private static func position(_ digits: String?, _ word: String?) -> Int? {
        digits.flatMap(Int.init) ?? word.flatMap { ordinals[$0.lowercased()] }
    }

    /// Reads a question about a sequence. Nil if it isn't one MathPeek knows how to read.
    static func problem(_ input: String) -> Problem? {
        guard input.range(of: #"\bterms?\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = Parser.normalize(input)
        let nth = #"\bn\s*-?\s*th\s+term"#
        let stop = #"(?=\s*(?:,|;|\.(?:\s|$)|\bwhere\b|\bfind\b|\bwork\b|$))"#

        // "The nth term of a sequence is an² + bn", "a sequence with nth term 3n + 2"
        let definitions = matches(nth + #"(?:\s+of\s+(?:a|the|this)\s+(?:\w+\s+)?sequence)?\s+(?:is given by|is|=)\s*(.+?)"# + stop, in: text)
            + matches(#"\b(?:has|with)\s+"# + nth + #"\s+(.+?)"# + stop, in: text)
        if let written = definitions.first?.first ?? nil, let rule = Parser.expression(written), rule.contains("n") {
            let letters = rule.symbols.subtracting(["n"]).sorted()

            // "The 2nd term is 2", "the fifth term is 35"
            var given: [(place: Int, value: Expr)] = []
            for found in matches(#"\b(?:"# + place + #")\s+term\s+(?:of the sequence\s+)?(?:is|=|equals)\s*("# + number + ")", in: text) {
                guard let k = position(found[0], found[1]), let value = found[2].flatMap(Parser.expression) else { continue }
                given.append((k, value))
            }
            if !given.isEmpty, !letters.isEmpty {
                // Fewer terms than letters can't pin the letters down: part of the question
                // is missing, cut off at the end of a line perhaps.
                guard given.count >= letters.count else { return nil }
                // Each term gives an equation in the letters.
                var equations: [Equation] = []
                var lines: [MathLine] = []
                for (k, value) in given {
                    let substituted = rule.substituting("n", with: .integer(k))
                    let tidy = Simplify.run(substituted)
                    equations.append(Equation(left: tidy, right: value))
                    lines.append(Format.text(substituted) == Format.text(tidy) ? MathLine(tidy, value) : MathLine(substituted, tidy, value))
                }
                let places = given.map { "n = \($0.place)" }.joined(separator: given.count == 2 ? " and " : ", ")
                var problem = Problem(kind: .solve(equations, unknowns: letters), text: display, usesDecimals: false, angles: nil)
                problem.lead = [Step("Put the term numbers into the nth term", "The nth term is \(Format.text(rule)). Put in \(places).", lines)]
                return problem
            }
            guard letters.isEmpty else { return nil }

            // "Find the 10th term"
            let asked = matches(#"\b(?:find|work out|calculate|what is|write down|determine)\b[^.?]*?\b(?:"# + place + #")\s+term\b(?!\s+(?:is\s+\d|=))"#, in: text)
            if let found = asked.first, let k = position(found[0], found[1]) {
                return Problem(kind: .substitute(rule, values: ["n": .integer(k)]), text: display, usesDecimals: false, angles: nil)
            }
            // "Which term is 52?", "Is 52 a term of the sequence?"
            let which = matches(#"\bwhich\s+term\b[^.?]*?(?:is|equals|has (?:a |the )?value(?: of)?)\s*("# + number + ")", in: text)
                + matches(#"\bis\s+("# + number + #")\s+a\s+term\b"#, in: text)
            if let value = (which.first?.first ?? nil).flatMap(Parser.expression) {
                var problem = Problem(kind: .solve([Equation(left: rule, right: value)], unknowns: ["n"]), text: display, usesDecimals: false, angles: nil)
                problem.wantsTermNumber = true
                return problem
            }
            return nil
        }

        // "Find the nth term of 3, 7, 11, 15", "What is the next term: 2, 6, 18, 54?"
        let plain = input.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
        guard text.range(of: nth + #"|\bnext\s+(?:two\s+|three\s+)?terms?\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let list = matches("(" + number + #"(?:\s*,\s*"# + number + "){2,})", in: plain).first?.first ?? nil else { return nil }
        let terms = list.split(separator: ",").compactMap { exact($0.trimmingCharacters(in: .whitespaces)) }
        guard terms.count >= 3, terms.count == list.split(separator: ",").count else { return nil }
        return Problem(kind: .sequence(terms), text: display, usesDecimals: false, angles: nil)
    }

    /// A number in a list as an exact fraction: 0.5 is 1/2, so the differences come out exactly.
    private static func exact(_ text: String) -> Expr? {
        let negative = text.hasPrefix("-")
        let digits = negative ? String(text.dropFirst()) : text
        let parts = digits.split(separator: "/", maxSplits: 1).map(String.init)
        func decimal(_ string: String) -> Rational? {
            let pieces = string.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count <= 2, let whole = Int(pieces.joined()), pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
            var scale = 1
            for _ in 0..<(pieces.count == 2 ? pieces[1].count : 0) { scale *= 10 }
            return Rational.make(whole, scale)
        }
        guard let top = decimal(parts[0]) else { return nil }
        var value = top
        if parts.count == 2 {
            guard let bottom = decimal(parts[1]), let quotient = top / bottom else { return nil }
            value = quotient
        }
        return .number(.exact(negative ? value.negated : value))
    }

    /// The nth term of a list of numbers: linear if they go up by the same amount each time,
    /// quadratic if the differences do, geometric if each is the same multiple of the last.
    static func nthTerm(_ terms: [Expr], _ problem: Problem) -> Solution? {
        let values = terms.compactMap { $0.number?.rational }
        guard values.count == terms.count, values.count >= 3 else { return nil }
        let n = Expr.symbol("n")
        let listed = Expr.symbol(values.map { Format.number(.exact($0)) }.joined(separator: ", ") + ", …")
        func number(_ value: Rational) -> Expr { .number(.exact(value)) }
        func differences(_ list: [Rational]) -> [Rational]? {
            let result = zip(list.dropFirst(), list).compactMap { $0 - $1 }
            return result.count == list.count - 1 ? result : nil
        }
        func show(_ list: [Rational]) -> String { list.map { Format.number(.exact($0)) }.joined(separator: ", ") }
        func finish(_ rule: Expr, _ steps: [Step]) -> Solution {
            let next = Simplify.run(rule.substituting("n", with: .integer(values.count + 1)))
            return Solution(problem: problem, question: MathLine(listed), task: "Find the nth term", answers: [MathLine(rule)],
                            steps: steps, note: "The next term is \(Format.text(next)).")
        }
        guard let first = differences(values) else { return nil }

        // Linear: the same step each time.
        if Set(first).count == 1, let d = first.first {
            guard let start = values[0] - d else { return nil }
            let rule = Simplify.run(.add([.multiply([number(d), n]), number(start)]))
            var steps = [Step("Find the differences", "Each term is \(Format.number(.exact(d))) more than the one before: the differences are \(show(first)).")]
            steps.append(Step("Start with \(Format.text(Simplify.run(.multiply([number(d), n]))))",
                              "A sequence that goes up by \(Format.number(.exact(d))) each time is based on the \(Format.number(.exact(d))) times table."))
            if !start.isZero {
                let table = (1...min(values.count, 4)).compactMap { (Rational($0) * d).map { Format.number(.exact($0)) } }
                steps.append(Step("Compare with the sequence",
                                  "\(table.joined(separator: ", ")) against \(show(Array(values.prefix(4)))): each term is \(Format.number(.exact(start.numerator < 0 ? start.negated : start))) \(start.numerator < 0 ? "less" : "more").",
                                  [MathLine(rule)]))
            }
            return finish(rule, steps)
        }

        // Quadratic: the differences of the differences are the same.
        if let second = differences(first), second.count >= 2, Set(second).count == 1, let dd = second.first, !dd.isZero,
           let a = dd / Rational(2) {
            // Take an² away from each term; what's left goes up by the same amount each time.
            var left: [Rational] = []
            for (index, value) in values.enumerated() {
                guard let square = Rational((index + 1) * (index + 1)) * a, let rest = value - square else { return nil }
                left.append(rest)
            }
            guard let steps2 = differences(left), Set(steps2).count == 1, let b = steps2.first, let c = left[0] - b else { return nil }
            let squared = Simplify.run(.multiply([number(a), .power(n, .two)]))
            let rule = Simplify.run(.add([squared, .multiply([number(b), n]), number(c)]))
            var steps = [
                Step("Find the differences", "First differences: \(show(first)). Second differences: \(show(second))."),
                Step("Halve the second difference", "The second differences are all \(Format.number(.exact(dd))), so the sequence is quadratic and starts with \(Format.text(squared)).",
                     [MathLine(squared)]),
            ]
            if !(b.isZero && c.isZero) {
                let rest = Simplify.run(.add([.multiply([number(b), n]), number(c)]))
                steps.append(Step("Take \(Format.text(squared)) away from each term", "What's left is \(show(left)), which has nth term \(Format.text(rest)).",
                                  [MathLine(rule)]))
            }
            return finish(rule, steps)
        }

        // Geometric: the same multiple each time.
        if values.allSatisfy({ !$0.isZero }) {
            let ratios = zip(values.dropFirst(), values).compactMap { $0 / $1 }
            if ratios.count == values.count - 1, Set(ratios).count == 1, let r = ratios.first, r != Rational(1) {
                let rule = Expr.multiply([number(values[0]), .power(number(r), .add([n, .minusOne]))])
                let shown: Expr = values[0] == Rational(1) ? .power(number(r), .add([n, .minusOne])) : rule
                let steps = [
                    Step("Find how the terms change", "Each term is \(Format.number(.exact(r))) times the one before, so the sequence is geometric."),
                    Step("Start from the first term", "The first term is \(Format.number(.exact(values[0]))), multiplied by \(Format.number(.exact(r))) once for each step after it.",
                         [MathLine(shown)]),
                ]
                let next = (values[values.count - 1] * r).map { Format.number(.exact($0)) } ?? ""
                return Solution(problem: problem, question: MathLine(listed), task: "Find the nth term", answers: [MathLine(shown)],
                                steps: steps, note: "The next term is \(next).")
            }
        }
        return nil
    }
}
