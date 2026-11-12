import Foundation

/// Questions asked in words that MathPeek reads itself, with no guessing: the kinds that are
/// always worded the same way. Anything else in words is left to Apple Intelligence.
enum WordProblems {
    /// The question as a problem, or nil if it isn't one of these kinds.
    static func problem(_ text: String) -> Problem? {
        // (Without the heading some worksheets start a question with: "Question 14:".)
        let text = text.replacingOccurrences(of: #"(?m)^\s*Q(?:uestion)? ?\d{1,2} ?[:.)] ?(?=\S)"#, with: "", options: [.regularExpression, .caseInsensitive])
// Two proportions in one question ("P ∝ Q², Q ∝ R") go before the one that reads only the first.
        // (A solver whose problem comes to nothing doesn't stop the next one being tried.)
        func answered(_ problem: Problem?) -> Problem? {
            guard let problem, let solution = Engine.solve(problem, angles: .degrees), !solution.answers.isEmpty || solution.note != nil else { return nil }
            return problem
        }
        // "Find the 6th term" wants a number: the letters of the nth term aren't that answer.
        func sequence() -> Problem? {
            guard let problem = Sequences.problem(text) else { return nil }
            if text.range(of: #"\b(?:find|work out|calculate|what is|write down)\b[^.?]{0,30}\b\d+(?:st|nd|rd|th) term\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               let solution = Engine.solve(problem, angles: .degrees), solution.answers.contains(where: { !($0.parts.last?.symbols.isEmpty ?? true) || $0.parts.count > 1 }) {
                return nil
            }
            return problem
        }
        return (answered(sequence()) ?? answered(Worded.proportions(text)) ?? answered(Proportion.problem(text)) ?? answered(Worded.problem(text)) ?? answered(WordedTopics.problem(text)))
            .map { signed($0, for: text) }
    }

    /// A bare number given the sign its question asks for: £ on an amount of money ("How
    /// much does Harry receive?" → £4500), % on a percentage ("Work out the percentage
    /// decrease" → 12%). The value doesn't change.
    static func signed(_ problem: Problem, for text: String) -> Problem {
        guard let solution = Engine.solve(problem, angles: .degrees), solution.answers.count == 1, solution.answerSets == nil,
              solution.answers[0].suffix == nil, solution.answers[0].parts.count == 1 else { return problem }
        let part = solution.answers[0].parts[0]
        var amount = part.number?.double
        if amount == nil, case .symbol(let written) = part, written.range(of: #"^-?\d+(?:\.\d+)?$"#, options: .regularExpression) != nil { amount = Double(written) }
        guard let amount, amount.isFinite else { return problem }
        // What the question asks for, in its last sentence that asks anything.
        let sentences = text.lowercased().components(separatedBy: CharacterSet(charactersIn: ".?\n")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let asking = sentences.last(where: { $0.range(of: #"\bwork out\b|\bcalculate\b|\bfind\b|\bhow much\b|\bwhat (?:is|was|will|percentage)\b|\bwrite\b"#, options: .regularExpression) != nil }) else { return problem }
        func has(_ pattern: String, _ words: String) -> Bool { words.range(of: pattern, options: .regularExpression) != nil }
        var written: String?
        if has(#"\bpercentage (?:increase|decrease|change|profit|loss|reduction|error|of)\b|\bwhat percentage\b|\bas a percentage\b|\bper ?cent\b"#, asking),
           !has(#"\b(?:value|price|cost|amount|number) (?:after|before|when|of the)\b"#, asking) {
            written = Format.text(.number(.real(amount))) + "%"
        } else if text.contains("£"),
                  has(#"\bhow much(?! (?:time|longer|further|faster|slower|heavier|lighter|taller|shorter|water|milk|paint|fuel|petrol|flour|sugar|butter|rice|juice|more (?:time|water)))\b|\b(?:price|cost|costs|value|profit|loss|pay|paid|pays|receives?|share|wages?|salary|bill|charge|fare|interest|worth|deposit|savings|change)\b"#, asking),
                  !has(#"\bhow many\b|\bpercentage\b|\bper ?cent\b|\bratio\b|\bnumber of\b|\byears?\b|\bmonths?\b|\bweeks?\b|\bdays?\b|\bhours?\b|\bfraction\b|\bprobability\b|\brate\b|\bin pence\b|\bvalue of [a-z]\b"#, asking),
                  amount >= 0 {
            written = abs(amount - amount.rounded()) < 1e-9 ? "£\(Int(amount.rounded()))" : "£" + String(format: "%.2f", amount)
        }
        guard let written else { return problem }
        var signed = Problem(kind: .worded(question: solution.question.text.replacingOccurrences(of: "/", with: "∕"), answers: [MathLine(.symbol(written))]),
                             text: problem.text, usesDecimals: problem.usesDecimals)
        signed.lead = solution.steps
        return signed
    }
}

/// Proportion: "y is directly proportional to x. When x = 4, y = 12. Find y when x = 10."
enum Proportion {
    static func problem(_ input: String) -> Problem? {
        guard input.range(of: #"proportional|\bvaries\b"#, options: [.regularExpression, .caseInsensitive]) != nil || input.contains("∝") else { return nil }
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = Parser.normalize(input)
            .replacingOccurrences(of: #"(?i)the\s+square\s+of\s+([a-zA-Z])\b"#, with: "$1^2", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)the\s+cube\s+of\s+([a-zA-Z])\b"#, with: "$1^3", options: .regularExpression)
            // A power that has dropped onto the line, "proportional to x2" or "to d 2": a
            // number after the letter there can only be its power.
            .replacingOccurrences(of: #"(?i)(proportional\s+to\s+√?\s*[a-zA-Z])\s?([23])(?![\d^]|\.\d)"#, with: "$1^$2", options: .regularExpression)
        // "y is inversely proportional to x^2", "y ∝ √x"
        let pattern = #"\b([a-zA-Z])\s*(?:(?:is|varies)\s+(directly\s+|inversely\s+)?(?:proportional\s+to|as)|∝)\s*(√?\s*[a-zA-Z](?:\s*\^\s*\(?\d\)?)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let subjectRange = Range(match.range(at: 1), in: text), let ofRange = Range(match.range(at: 3), in: text),
              let whole = Range(match.range, in: text), let shape = Parser.expression(String(text[ofRange])),
              shape.symbols.count == 1, let x = shape.symbols.first else { return nil }
        let y = String(text[subjectRange])
        guard y != x else { return nil }
        // One proportion only: with a second one, or an answer wanted in terms of another
        // letter, the first by itself answers a different question.
        guard regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) == 1,
              (try? NSRegularExpression(pattern: #"proportional|\bvaries\b|∝"#, options: [.caseInsensitive]))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) == 1 else { return nil }
        if let wanted = try? NSRegularExpression(pattern: #"in terms of ([a-zA-Z])\b"#, options: [.caseInsensitive]),
           let match = wanted.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let letter = Range(match.range(at: 1), in: text),
           String(text[letter]) != x { return nil }
        let inverse = Range(match.range(at: 2), in: text).map { text[$0].lowercased().hasPrefix("inverse") } ?? false

        // The values given, in the order they're written: "when x = 4, y = 12 … when x = 10".
        let after = String(text[whole.upperBound...])
        guard let values = try? NSRegularExpression(pattern: #"\b([a-zA-Z])\s*(?:=|is)\s*(-?\d+(?:\.\d+)?(?:/\d+)?)"#) else { return nil }
        var given: [(letter: String, value: Expr)] = []
        for found in values.matches(in: after, range: NSRange(after.startIndex..., in: after)) {
            guard let letter = Range(found.range(at: 1), in: after), let number = Range(found.range(at: 2), in: after),
                  let value = Parser.expression(String(after[number])) else { continue }
            let name = String(after[letter])
            if name == x || name == y { given.append((name, value)) }
        }
        guard let x0 = given.first(where: { $0.letter == x })?.value, let y0 = given.first(where: { $0.letter == y })?.value else { return nil }
        let k = Expr.symbol("k")
        let general: Expr = inverse ? .multiply([k, .power(shape, .minusOne)]) : .multiply([k, shape])
        let filled = general.substituting(x, with: x0)
        let scale = shape.substituting(x, with: x0)
        let constant = Simplify.run(inverse ? .multiply([y0, scale]) : .multiply([y0, .power(scale, .minusOne)]))
        guard constant.number != nil else { return nil }
        let formula = Simplify.run(general.substituting("k", with: constant))
        let lead = [
            Step("Write it as an equation", "\(y) is \(inverse ? "inversely " : "")proportional to \(Format.text(shape)), so there's a number k that links them.",
                 [MathLine(.symbol(y), general)]),
            Step("Find k", "Put in \(x) = \(Format.text(x0)) and \(y) = \(Format.text(y0)).",
                 [MathLine(y0, filled), MathLine(k, constant)]),
            Step("Write the formula", "", [MathLine(.symbol(y), formula)]),
        ]

        // What's asked for: the other letter, at the value given after the first pair.
        let firstX = given.firstIndex(where: { $0.letter == x })!, firstY = given.firstIndex(where: { $0.letter == y })!
        let asked = given.enumerated().first { $0.offset > max(firstX, firstY) }?.element
        var problem: Problem
        if let asked, asked.letter == x {
            problem = Problem(kind: .substitute(formula, values: [x: asked.value]), text: display, usesDecimals: false, angles: nil)
        } else if let asked {
            problem = Problem(kind: .solve([Equation(left: formula, right: asked.value)], unknowns: [x]), text: display, usesDecimals: false, angles: nil)
        } else {
            return nil
        }
        problem.lead = lead
        return problem
    }
}
