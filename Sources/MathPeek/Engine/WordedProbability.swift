import Foundation

/// Chances asked in words: one, two or three taken from a bag, with and without replacement, a Venn diagram or a tree described in words, the same thing tried
/// again and again, numbers picked and added, how many times something is expected to happen, and counting: one of each, codes of letters or digits.
/// Tried after `Worded.problem`, on the same text: the lines of the question the pointer is
/// in, joined by line breaks. Nil unless the whole of the question is understood.
enum WordedProbability {
    static func problem(_ input: String) -> Problem? {
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let question = read(display), question.text.count <= 700 else { return nil }
        let text = question.text
        // A part that asks for a drawing, a reason or a box to tick isn't asking for a chance;
        // and with two parts' questions in the text there's no telling which is meant.
        guard !has(refusal, text), every(asking, in: text).count == 1 else { return nil }
        let kinds: [(Question) -> Found?] = [expected, fromTable, eachOf, changing, fromOne, severalTaken, unknownCount, twoStages, twoDice, inGroups, guess, venn, fromChances, twoUnknowns, arrangements, codes, digitCodes, combined, sameTwice, twoWay, letterTable, relativeFrequency, choices, separate, eachRolls, letters, coinTimes, groupChances, twoSets, onePick, remaining, howMany, again, fairGo]
        for kind in kinds {
            guard let found = kind(question) else { continue }
            // Every number in the question's sentences has to have been used. (A kind may
            // also have used numbers from a table, which aren't in the sentences.)
            var left = numbers(in: text)
            for used in found.used {
                if let at = left.firstIndex(where: { same($0, used) }) { left.remove(at: at) }
            }
            guard left.isEmpty else { return nil }
            // Answers to circle: the answer has to be one of them.
            if !question.choices.isEmpty {
                guard let size = found.size, question.choices.contains(where: { abs($0 - size) < 1e-9 }) else { return nil }
            }
            var problem = found.problem
            problem.text = display
            return problem
        }
        return nil
    }

    // MARK: Reading the question

    private struct Question {
        /// The question's sentences on one line, with the margin, the marks and the answer line taken out.
        var text: String
        /// Numbers standing on a line of their own after the marks: answers to circle.
        var choices: [Double]
        /// Every line, short ones and lone numbers too (a table's labels and counts), without the marks and the answer line.
        var lines: [String]
    }

    /// A kind's answer, the numbers from the question it used, and its size where it's a number.
    private struct Found {
        var problem: Problem
        var used: [String]
        var size: Double?
    }

    private static let refusal = #"\bcomplete (?:the|this|these)\b|\bdraw\b|\bsketch\b|\bshow that\b|\bexplain\b|\btick\b|\bgive (?:a|one|two|your) reasons?\b|\bis (?:he|she|it|they|this) (?:correct|right)\b|\bshade\b|\bdescribe\b|\brepresent (?:this|the)\b"#
    private static let asking = #"\b(?:work out|write down|find|calculate|what is|circle) (?:an estimate (?:for|of) )?(?:the |how many )?(?:total )?(?:probability|expected|value|number|chance|relative frequency|times)|\bhow many [a-z]+ (?:does|do|will|would|should|did) [a-z]+ expect|\bhow many of the possible\b|\bwhich (?:one )?is more likely\b|\bhow many different\b|\bnumber of different\b|\bhow many times is\b|\bhow many of [a-z]+'s codes\b|\bhow many (?:possible )?codes (?:are|can)\b|\bin how many (?:different )?ways\b|\bhow many [a-z]+ [a-z]+ are (?:there )?in the\b"#
    private static let number = #"\d+(?:\.\d+)?(?: ?/ ?\(?\d+\)?)?%?"#

    private static func read(_ display: String) -> Question? {
        var raw = display
        for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("’", "'"), ("‘", "'"), ("⩽", "≤"), ("⩾", "≥"), ("\u{FFFC}", " ")] {
            raw = raw.replacingOccurrences(of: from, with: to)
        }
        // Letters from other alphabets read for ones that look the same.
        let alike: [Character: Character] = ["а": "a", "А": "A", "В": "B", "в": "b", "С": "C", "с": "c", "Е": "E", "е": "e", "Н": "H", "К": "K", "М": "M", "О": "O", "о": "o",
                                              "Р": "P", "р": "p", "Т": "T", "т": "m", "Х": "X", "х": "x", "У": "Y", "у": "y", "і": "i", "З": "3", "з": "3"]
        raw = String(raw.map { alike[$0] ?? $0 })
        var lines: [String] = [], all: [String] = [], choices: [Double] = [], afterMarks = false, sawWords = false
        for piece in raw.components(separatedBy: "\n") {
            var line = piece.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if line.range(of: #"\[\d+ marks?\]|^[I\[]\d+ mark|\[\d{1,2}\]$"#, options: [.regularExpression, .caseInsensitive]) != nil { afterMarks = true; continue }
            // A row of numbers after the marks is the answers to choose from.
            if afterMarks, line.range(of: #"^\d+(?:\.\d+)?(?: \d+(?:\.\d+)?)+$"#, options: .regularExpression) != nil {
                choices += line.split(separator: " ").compactMap { Double($0) }
                continue
            }
            if line.range(of: #"^answer\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            // Edexcel's marks, "(Total for Question 16 is 6 marks)", the page's code and margin.
            if line.range(of: #"^\((?:\d{1,2}|total for question \d+ is \d+ marks?)\)$|^\*?P ?\d{4}|\bturn over\b|\bdo not write in this area\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            // A question's number and a part's letter, on their own or at the start of the line.
            line = line.replacingOccurrences(of: #"^(?:\d{1,2} ){0,2}(?:\(?[a-h]\) ?)?(?=[A-Z])"#, with: "", options: .regularExpression)
            // The question's number before a sentence that starts with a number: "20 50 people were asked".
            if !sawWords { line = line.replacingOccurrences(of: #"^\d{1,2} (?=\d+ [a-z]+ [a-z]+ [a-z]+)"#, with: "", options: .regularExpression) }
            if line.range(of: #"[A-Za-z]{2,}"#, options: .regularExpression) != nil, line.split(separator: " ").count >= 3 { sawWords = true }
            if !line.isEmpty { all.append(line) }
            if line.range(of: #"^(?:\d{1,2} ?)?(?:\(?[a-h]\))?$"#, options: .regularExpression) != nil { continue }
            // Margin notes and the labels of a diagram: a word or two with no number in them,
            // and nothing a sentence needs.
            // ("n boys" stays: a letter for a number of things.)
            if line.range(of: #"\d"#, options: .regularExpression) == nil, line.split(separator: " ").count <= 2, !line.hasSuffix("."), !line.hasSuffix("?"),
               line.range(of: #"^[a-z] [a-z]{3,}$"#, options: .regularExpression) == nil { continue }
            lines.append(line)
        }
        var text = lines.joined(separator: " ")
        // "probabilitv", "nrobability"
        // (Not a word in capitals, which may be one whose letters are counted: "the word PROBABILITY".)
        text = text.replacingOccurrences(of: #"\b[pn]r[o0][bh]ab[il1]+[it1]+[tvy]\b"#, with: "probability", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\b[PN]r[o0][bh]ab[il1]+[it1]+[tvy]\b"#, with: "Probability", options: .regularExpression)
        // A stray stroke inside a word: "W/ork out".
        text = text.replacingOccurrences(of: #"\b([A-Z])/(?=[a-z]{2,})"#, with: "$1", options: .regularExpression)
        // A fraction read as 7/(20).
        text = text.replacingOccurrences(of: #"\((\d+)\) ?/ ?\((\d+)\)"#, with: "$1/$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\d+) ?/ ?\((\d+)\)"#, with: "$1/$2", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard text.range(of: #"\bprobabilit|\bexpect|\bchance|\brelative frequenc|\bnumber of (?:different|possible)\b|\bhow many of the possible\b|\bmore likely\b|\bhow many different\b|\bdifferent pairs\b|\bchosen at random\b|\bpossible codes\b|\bcodes are (?:not )?possible\b|\bin how many (?:different )?ways\b|\b\d-digit codes?\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return Question(text: text, choices: choices, lines: all)
    }

    // MARK: How many times it's expected

    /// "The probability of Heads when a biased coin is thrown is 0.6. The coin is thrown 500
    /// times. Circle the expected number of Tails."
    private static func expected(_ question: Question) -> Found? {
        let text = question.text
        guard let stated = groups(#"\bprobability (?:of (?:getting |scoring |a |an )?|that (?:it|the [a-z]+|an? [a-z]+) (?:lands? on |shows? |is )(?:a |an )?)([a-z0-9]+(?: [a-z]+)?) (?:(?:when|on|for|with) [^.]*? )?is (\#(number))(?![\d/])"#, in: text)
                ?? groups(#"\bP\(([a-z0-9 ]+)\) ?= ?(\#(number))"#, in: text)
                ?? groups(#"\brelative frequency of ([a-z0-9]+) is (\#(number))(?![\d/])"#, in: text),
              let p = chance(stated[2]),
              let times = groups(#"\b(?:throws|spins|rolls|tosses|flips|thrown|spun|rolled|tossed|flipped|played|taken|picked|chosen|done|repeated)(?: (?:it|the [a-z]+|an? [a-z]+))? (\d+) times\b"#, in: text),
              let trials = Int(times[1]), trials > 0,
              let asked = groups(#"\bexpected number of ([a-z0-9]+)|\bhow many times (?:would|should|will|do|does) [^?]*?expect [^?]*?(?:to (?:get|land on|score|show) |of )(?:a |an )?([a-z0-9]+)|\bhow many times (?:did )?(?:it|the [a-z]+) (?:landed|lands|land|showed|shows|show) on (?:a |an )?([a-z0-9]+)"#, in: text) else { return nil }
        let event = stated[1].lowercased(), wanted = [asked[1], asked[2], asked[3]].first { !$0.isEmpty }!.lowercased()
        var chanceOf = p, steps: [Step] = []
        let pText = stated[2]
        if single(event) == single(wanted) || event.split(separator: " ").contains(where: { single(String($0)) == single(wanted) }) {
            steps.append(Step("Find the chance", "P(\(stated[1])) = \(pText)"))
        } else if Set([single(event), single(wanted)]) == ["head", "tail"] {
            // A coin lands one way or the other.
            chanceOf = Fraction(1, 1) - p
            steps.append(Step("Find the chance of \(wanted)", "A coin lands on heads or tails, so the two chances add up to 1.",
                              [MathLine(.symbol("P(\(wanted))"), Expr.one - written(pText, p), shown(chanceOf, like: pText))]))
        } else {
            return nil
        }
        steps.append(Step("Multiply by the number of goes", "The expected number is the chance times the number of times it's done."))
        let expr = shown(chanceOf, like: pText) * .integer(trials)
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: pText.contains("."))
        problem.lead = steps
        return Found(problem: problem, used: [stated[2], String(trials)], size: (chanceOf * Fraction(trials, 1)).double)
    }

    // MARK: One from each of two

    /// "Bag A contains 1 green disc and 4 yellow discs. Bag B contains 3 green discs and 7
    /// yellow discs. One disc is picked at random from each bag. Work out the probability that
    /// both discs are green."
    private static func eachOf(_ question: Question) -> Found? {
        let text = question.text
        let holders = every(#"\b([A-Z][a-z]* [A-Z0-9])\b contains? ((?:(?:\d+|[a-z]+) [a-z]+ [a-z]+(?:, | and )?){2,4})"#, in: text)
        guard holders.count == 2, has(#"\bfrom each\b"#, text) else { return nil }
        var used: [String] = []
        var contents: [[(colour: String, count: Int)]] = []
        for holder in holders {
            guard let items = counted(holder[2]) else { return nil }
            contents.append(items)
            used += items.compactMap { item in holder[2].range(of: #"\b\#(item.count)\b"#, options: .regularExpression) != nil ? String(item.count) : nil }
        }
        guard let asked = groups(#"probability (?:that )?(?:both|the two) (?:[a-z]+ )?(?:are|is) ([a-z]+)|probability (?:that )?(?:neither|none) (?:[a-z]+ )?(?:of the [a-z]+ )?is ([a-z]+)|probability (?:that )?(?:the )?(?:two )?(?:[a-z]+ )?are (?:the )?(same|different) colou?rs?|probability (?:that )?at least one (?:[a-z]+ )?(?:of the [a-z]+ )?is ([a-z]+)"#, in: text) else { return nil }
        let first = contents[0], second = contents[1]
        func p(_ items: [(colour: String, count: Int)], _ colour: String) -> Fraction? {
            let total = items.reduce(0) { $0 + $1.count }
            guard total > 0, let found = items.first(where: { single($0.colour) == single(colour) }) else { return nil }
            return Fraction(found.count, total)
        }
        let totals = [first, second].map { $0.reduce(0) { $0 + $1.count } }
        var expr: Expr, size: Fraction, how: String
        if !asked[1].isEmpty || !asked[2].isEmpty || !asked[4].isEmpty {
            let colour = [asked[1], asked[2], asked[4]].first { !$0.isEmpty }!.lowercased()
            guard let a = p(first, colour), let b = p(second, colour) else { return nil }
            if !asked[1].isEmpty {
                expr = a.expr * b.expr; size = a * b
                how = "Both have to be \(colour): the chance from the first times the chance from the second."
            } else if !asked[2].isEmpty {
                let (na, nb) = (Fraction(1, 1) - a, Fraction(1, 1) - b)
                expr = na.expr * nb.expr; size = na * nb
                how = "Neither can be \(colour): the chance of not \(colour) from the first times the chance of not \(colour) from the second."
            } else {
                let (na, nb) = (Fraction(1, 1) - a, Fraction(1, 1) - b)
                expr = Expr.one - na.expr * nb.expr; size = Fraction(1, 1) - na * nb
                how = "At least one is everything except neither: 1 take away the chance that neither is \(colour)."
            }
        } else {
            let colours = first.map(\.colour).filter { colour in second.contains { single($0.colour) == single(colour) } }
            guard colours.count == first.count, colours.count == second.count else { return nil }
            let terms = colours.compactMap { colour -> (Expr, Fraction)? in
                guard let a = p(first, colour), let b = p(second, colour) else { return nil }
                return (a.expr * b.expr, a * b)
            }
            let same = Expr.add(terms.map(\.0)), sameSize = terms.reduce(Fraction(0, 1)) { $0 + $1.1 }
            if asked[3].lowercased() == "same" {
                expr = same; size = sameSize
                how = "Both \(colours.joined(separator: ", or both ")): add the chance of each."
            } else {
                expr = Expr.one - same; size = Fraction(1, 1) - sameSize
                how = "Different colours is everything except the same colour: 1 take away the chance of both \(colours.joined(separator: ", or both "))."
            }
        }
        let lead = [Step("Find the chances for each", "Out of \(totals[0]) in the first and \(totals[1]) in the second. The two picks don't change each other, so their chances multiply."),
                    Step("Put them together", how)]
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: size.double)
    }

    // MARK: Some taken from one

    /// "A bag contains 8 balls. 3 are red and 5 are blue. 2 balls are taken from the bag at
    /// random without replacement. Work out the probability that there are at least 2 red
    /// balls still in the bag."
    private static func fromOne(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bfrom each\b|\b[A-Z][a-z]* [A-Z0-9] contains?\b|\breplaced by\b"#, text), let bag = contents(text) else { return nil }
        let items = bag.items
        var used = bag.used
        // How many are taken, and whether they go back.
        var howMany = "", back = false
        // How they're taken is said before the question; "picks two red counters" in the question isn't it.
        let setup = text.range(of: #"\b(?:work out|find|calculate|write down|what is) the probability\b"#, options: [.regularExpression, .caseInsensitive]).map { String(text[..<$0.lowerBound]) } ?? text
        if let taken = groups(#"\b(\d+|two|three|both) [a-z]+ (?:are|is) (?:taken|picked|chosen|removed|drawn|selected)[^.]*?\b(with|without) replacement|\b(\d+|two|three) [a-z]+ (?:are|is) (?:taken|picked|chosen|removed|drawn|selected)[^.]*?\b(and not replaced|and replaced)"#, in: setup) {
            howMany = taken[1].isEmpty ? taken[3] : taken[1]
            back = taken[2].lowercased() == "with" || taken[4].lowercased() == "and replaced"
        } else if let first = groups(#"\b(?:takes|picks|chooses|selects) an? [a-z]+ at random(?: from the [a-z]+)? and (?:then )?(eats|keeps|replaces|puts back) it\b"#, in: setup),
                  has(#"\b(?:then )?(?:takes|picks|chooses|selects) (?:another|a second) [a-z]+ at random\b"#, setup) {
            howMany = "two"; back = ["replaces", "puts back"].contains(first[1].lowercased())
        } else if let taken = groups(#"\b(?:takes|picks|chooses|selects|draws) (?:at random )?(two|2) (?:of (?:the|these) )?[a-z]+(?: at random)?(?: from the [a-z]+)?(?:,? (with|without) replacement)?"#, in: setup),
                  !has(#"\b(?:replaces|puts it back|put back|then (?:takes|picks|chooses))\b"#, setup) {
            // Two taken together: one isn't back before the other.
            howMany = taken[1]; back = taken[2].lowercased() == "with"
        } else {
            return nil
        }
        guard let k = count(howMany), k == 2 else { return nil }
        if howMany.first?.isNumber == true { used.append(howMany) }
        let n = items.reduce(0) { $0 + $1.count }
        guard n >= 2 else { return nil }

        // The same colour, different colours, or one of each of the two there are.
        if let asked = groups(#"probability (?:that )?(?:the )?(?:two )?(?:[a-z]+ )?(?:(?:he|she|they) (?:chooses|picks|takes) )?(?:are|have|is) (?:the )?(same|different) (?:colou?rs?|flavours?|types?|kinds?)\b|probability (?:that )?(?:[A-Z][a-z]+ |he |she |they )?(?:takes|picks|chooses|gets) one (?:[a-z]+ )?of each (?:colou?r|type|flavour|kind)\b"#, in: text) {
            let n = items.reduce(0) { $0 + $1.count }
            guard n >= 2 else { return nil }
            let second = back ? n : n - 1
            let pairs = items.map { item in Fraction(item.count * (back ? item.count : item.count - 1), n * second) }
            let same = pairs.reduce(Fraction(0, 1), +)
            var expr: Expr, size: Fraction, how: String
            let sameExpr = Expr.add(items.map { Expr.integer($0.count) / .integer(n) * (Expr.integer(back ? $0.count : $0.count - 1) / .integer(second)) })
            let order = back ? "It goes back, so the second is out of \(n) again." : "It isn't put back, so the second is out of \(n - 1)."
            if asked[1].lowercased() == "same" {
                expr = sameExpr; size = same; how = "Both \(items.map(\.colour).joined(separator: ", or both ")): add the chance of each. \(order)"
            } else {
                // One of each is different colours only when there are just two colours.
                guard asked[1].lowercased() == "different" || items.count == 2 else { return nil }
                expr = Expr.one - sameExpr; size = Fraction(1, 1) - same
                how = "Different is everything except the same: 1 take away the chance of both \(items.map(\.colour).joined(separator: ", or both ")). \(order)"
            }
            var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
            problem.lead = [Step("What's in it", items.map { "\($0.count) \($0.colour)" }.joined(separator: ", ") + ", \(n) in all."), Step("Work out the chance", how)]
            return Found(problem: problem, used: used, size: size.double)
        }
        // "picks two black cards": both that colour.
        let both = groups(#"probability (?:that )?(?:[A-Z][a-z]+ |he |she |they )?(?:takes|picks|chooses|gets) (?:two|2) ([a-z]+) [a-z]+(?:\.|\?|$)"#, in: text)
        if let both, both[1].lowercased() != "of" {
            guard items.contains(where: { single($0.colour) == single(both[1]) }) else { return nil }
        }
        // What's asked: about the ones taken, or the ones left.
        let left = #"(?:still in|left in|remaining in|that remain in|in) the [a-z]+"#
        var colour = "", event: (Int) -> Bool, saying: String
        if let asked = groups(#"probability (?:that )?(?:there (?:is|are) )?(at least|at most|exactly|no|only) ?(\d+|one|two)? ([a-z]+) [a-z]+ \#(left)"#, in: text) {
            // About what's left in it: turned round to what was taken.
            colour = asked[3].lowercased()
            guard let have = items.first(where: { single($0.colour) == single(colour) })?.count, !back else { return nil }
            let m = asked[1].lowercased() == "no" ? 0 : (count(asked[2]) ?? -1)
            guard m >= 0 else { return nil }
            if !asked[2].isEmpty, asked[2].first?.isNumber == true { used.append(asked[2]) }
            switch asked[1].lowercased() {
            case "at least": event = { have - $0 >= m }; saying = "at least \(m) \(colour) left means at most \(max(have - m, 0)) \(colour) taken"
            case "at most": event = { have - $0 <= m }; saying = "at most \(m) \(colour) left means at least \(max(have - m, 0)) \(colour) taken"
            case "exactly", "only": event = { have - $0 == m }; saying = "exactly \(m) \(colour) left means \(have - m) \(colour) taken"
            default: event = { have - $0 == 0 }; saying = "no \(colour) left means all \(have) \(colour) taken"
            }
        } else if let both, items.contains(where: { single($0.colour) == single(both[1]) }) {
            colour = both[1].lowercased(); event = { $0 == 2 }; saying = "both \(colour)"
        } else if let asked = groups(#"probability (?:that )?(?:both|the two|the 2) (?:[a-z]+ )?are ([a-z]+)|probability (?:that )?(?:neither|none) (?:of the [a-z]+ )?(?:[a-z]+ )?is ([a-z]+)|probability (?:that )?at least one (?:of the [a-z]+ )?(?:[a-z]+ )?is ([a-z]+)|probability (?:that )?exactly one (?:of the [a-z]+ )?(?:[a-z]+ )?is ([a-z]+)|probability (?:of|that there is) (?:taking |getting |picking )?(?:one|1) ([a-z]+) [a-z]+ and (?:one|1) ([a-z]+) [a-z]+"#, in: text) {
            if !asked[1].isEmpty { colour = asked[1]; event = { $0 == 2 }; saying = "both \(colour)" }
            else if !asked[2].isEmpty { colour = asked[2]; event = { $0 == 0 }; saying = "neither \(colour)" }
            else if !asked[3].isEmpty { colour = asked[3]; event = { $0 >= 1 }; saying = "at least one \(colour)" }
            else if !asked[4].isEmpty { colour = asked[4]; event = { $0 == 1 }; saying = "exactly one \(colour)" }
            else {
                // One of each of two colours: only when those are the only two there are.
                guard items.count == 2, Set([single(asked[5]), single(asked[6])]) == Set(items.map { single($0.colour) }) else { return nil }
                colour = asked[5]; event = { $0 == 1 }; saying = "one of each colour"
            }
            colour = colour.lowercased()
        } else {
            return nil
        }
        guard let have = items.first(where: { single($0.colour) == single(colour) })?.count else { return nil }
        let other = n - have
        let second = back ? n : n - 1
        // The chance that j of the colour are among the two taken.
        func ways(_ j: Int) -> (Expr, Fraction)? {
            switch j {
            case 2:
                let (a, b) = (Fraction(have, n), Fraction(back ? have : have - 1, second))
                return have >= 2 || (back && have >= 1) ? (a.expr * b.expr, a * b) : nil
            case 0:
                let (a, b) = (Fraction(other, n), Fraction(back ? other : other - 1, second))
                return other >= 2 || (back && other >= 1) ? (a.expr * b.expr, a * b) : nil
            default:
                let (a, b) = (Fraction(have, n), Fraction(other, second))
                return have >= 1 && other >= 1 ? (.two * a.expr * b.expr, Fraction(2, 1) * a * b) : nil
            }
        }
        let wanted = (0...2).filter(event), rest = (0...2).filter { !event($0) }
        let possible = { (js: [Int]) in js.compactMap(ways) }
        var expr: Expr, size: Fraction, how: String
        let order = back ? "It goes back, so the second pick is out of \(n) again." : "It isn't put back, so the second pick is out of \(n - 1)."
        if possible(wanted).isEmpty {
            expr = .zero; size = Fraction(0, 1); how = "That can't happen with \(have) \(colour) out of \(n), so the chance is 0."
        } else if possible(rest).isEmpty {
            expr = .one; size = Fraction(1, 1); how = "With only 2 taken and \(have) \(colour) to start with, this always happens: it's certain."
        } else if possible(rest).count < possible(wanted).count {
            let terms = possible(rest)
            expr = Expr.one - (terms.count == 1 ? terms[0].0 : .add(terms.map(\.0))); size = Fraction(1, 1) - terms.reduce(Fraction(0, 1)) { $0 + $1.1 }
            how = "It's easier to take away the chance of it not happening from 1."
        } else {
            let terms = possible(wanted)
            expr = terms.count == 1 ? terms[0].0 : .add(terms.map(\.0)); size = terms.reduce(Fraction(0, 1)) { $0 + $1.1 }
            how = terms.count > 1 ? "Add the chances of the ways it can happen. One of each can come in either order, so it counts twice." : (wanted == [1] ? "One of each can come in either order, so it counts twice." : "Multiply the chances for the first and the second pick.")
        }
        let lead = [Step("Say what has to happen", "There are \(have) \(colour) and \(other) others, \(n) in all. \(saying.prefix(1).uppercased() + saying.dropFirst()). \(order)"),
                    Step("Work out the chance", how)]
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: size.double)
    }

    // MARK: Three or more taken from one

    /// "There are only 4 red counters, 3 yellow counters and 1 green counter in a bag. Tony takes
    /// at random three counters from the bag. Work out the probability that there are now more
    /// yellow counters than red counters in the bag." Also "all three are red", "the same colour",
    /// "different colours", "exactly two are red", the first one's colour given, and three people
    /// who each take one and put it back.
    private static func severalTaken(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bfrom each\b|\b[A-Z][a-z]* [A-Z0-9] contains?\b|\breplaced by\b"#, text) else { return nil }
        // What's in it.
        var items: [(colour: String, count: Int)], used: [String]
        if let bag = contents(text) {
            items = bag.items; used = bag.used
        } else if let list = groups(#"\b(?:contains?|there are|has) only ((?:(?:\d+|[a-z]+) [a-z]+ [a-z]+(?:, | and |,? and )?){2,5})"#, in: text), let found = counted(list[1]) {
            items = found; used = every(#"(\d+) [a-z]+ [a-z]+"#, in: list[1]).map(\.[1])
        } else {
            return nil
        }
        let total = items.reduce(0) { $0 + $1.count }
        guard items.count >= 2, items.count <= 5, items.allSatisfy({ $0.count >= 1 }), total <= 60 else { return nil }
        func index(_ colour: String) -> Int? { items.firstIndex { single($0.colour) == single(colour) } }
        // How they're taken is said before the question.
        let setup = text.range(of: #"\b(?:work out|find|calculate|write down|what is) the probability\b"#, options: [.regularExpression, .caseInsensitive]).map { String(text[..<$0.lowerBound]) } ?? text
        let kept = has(#"\bwithout replacement\b|\b(?:does not|doesn't|do not|not) put\b|\bnot replaced\b|\b(?:eats|keeps) (?:it|them)\b"#, setup)
        let putBack = has(#"\bwith replacement\b|\bput(?:s|ting)? (?:it|them|the [a-z]+|each [a-z]+) back\b|\breplaces (?:it|them|the [a-z]+)\b|\band replaced\b"#,
                          setup.replacingOccurrences(of: #"\b(?:does not|doesn't|do not|not) put (?:it|them|the [a-z]+|each [a-z]+) back\b"#, with: "", options: [.regularExpression, .caseInsensitive]))
        guard !(putBack && kept) else { return nil }
        var k = 0, back = false
        let takers = every(#"\b[A-Z][a-z]+ (?:then )?(?:takes|picks|chooses) an? [a-z]+ at random\b"#, in: setup)
        if let taken = groups(#"\b(?:takes|picks|chooses|selects|draws) (?:at random )?(\d|two|three|four) (?:of (?:the|these) )?[a-z]+\b|\b(\d|two|three|four) (?:of the )?[a-z]+ (?:are|is) (?:taken|picked|chosen|removed|drawn|selected)\b"#, in: setup),
           let size = count(taken[1].isEmpty ? taken[2] : taken[1]) {
            // Several taken, together or one after the other: none goes back unless it says so.
            guard !putBack, takers.isEmpty else { return nil }
            k = size
            let shown = taken[1].isEmpty ? taken[2] : taken[1]
            if shown.first?.isNumber == true { used.append(shown) }
        } else if takers.count >= 2 {
            // "Marnie takes a disc at random before putting it back in the bag. Nick then takes a disc … Olly then takes a disc at random."
            let returns = every(#"\b(?:before putting|and puts|then puts|puts) (?:it|the [a-z]+) back\b"#, in: setup).count
            guard !kept, returns == takers.count || returns == takers.count - 1 else { return nil }
            k = takers.count; back = true
        } else {
            return nil
        }
        guard k >= 2, k <= 4, back || k <= total else { return nil }
        // "All 20 discs are in the bag": said again at the start of a part.
        if let again = groups(#"\ball (\d+) [a-z]+ are in the [a-z]+\b"#, in: setup) { guard Int(again[1]) == total else { return nil }; used.append(again[1]) }
        // The first one's colour given: "Reggie's first disc is blue."
        var first: Int?
        if let given = groups(#"\b(?:[A-Z][a-z]+'s|the|his|her) first [a-z]+ is ([a-z]+)\b"#, in: setup) {
            guard let at = index(given[1]), !back, k >= 3 else { return nil }
            first = at
        }
        // What's asked, as a test on how many of each colour are taken.
        let size = #"(?:\d|two|three|four)"#
        var event: ([Int]) -> Bool, saying: String, ofLeft = false
        if let asked = groups(#"probability (?:that )?there (?:are|will be) (?:now |then )?(more|fewer|less) ([a-z]+) [a-z]+ than ([a-z]+) [a-z]+ (?:left |remaining |still )?in the [a-z]+"#, in: text) {
            // About what's left in it: turned round to what was taken.
            guard let a = index(asked[2]), let b = index(asked[3]), a != b, !back, first == nil else { return nil }
            let more = asked[1].lowercased() == "more"
            event = { taken in more ? items[a].count - taken[a] > items[b].count - taken[b] : items[a].count - taken[a] < items[b].count - taken[b] }
            saying = "\(more ? "more" : "fewer") \(items[a].colour) than \(items[b].colour) left"; ofLeft = true
        } else if let asked = groups(#"probability (?:that )?(?:[A-Z][a-z]+|he|she|they) (?:takes?|picks?|gets?|chooses?|has|have) (more|fewer|less) ([a-z]+) [a-z]+ than ([a-z]+) [a-z]+(?:\.|\?|$)"#, in: text) {
            guard let a = index(asked[2]), let b = index(asked[3]), a != b else { return nil }
            let more = asked[1].lowercased() == "more"
            event = { more ? $0[a] > $0[b] : $0[a] < $0[b] }
            saying = "\(more ? "more" : "fewer") \(items[a].colour) than \(items[b].colour) taken"
        } else if let asked = groups(#"probability (?:that )?(?:all (\#(size)) (?:of the )?(?:[a-z]+ )?|they all |the (\#(size)) [a-z]+ )(?:(?:that )?(?:are )?(?:taken|picked|chosen) )?(?:are|take|pick|get|have) (?:all )?(?:an? |the )?(same colou?r|different colou?rs|[a-z]+)(?: [a-z]+)?(?:\.|\?|$)"#, in: text) {
            let said = asked[1].isEmpty ? asked[2] : asked[1]
            if !said.isEmpty { guard count(said) == k else { return nil }; if said.first?.isNumber == true { used.append(said) } }
            let what = asked[3].lowercased()
            if what.hasPrefix("same") { event = { $0.contains(k) }; saying = "all \(k) the same colour" }
            else if what.hasPrefix("different") {
                // Each a colour of its own: as many colours as are taken, or it says less than it seems.
                guard items.count == k else { return nil }
                event = { $0.allSatisfy { $0 == 1 } }; saying = "one of each colour"
            } else {
                guard let a = index(what) else { return nil }
                event = { $0[a] == k }; saying = "all \(k) \(items[a].colour)"
            }
        } else if let asked = groups(#"probability (?:that )?(exactly|at least|at most) (\#(size)|one) (?:of the (?:\#(size) )?[a-z]+ )?(?:[a-z]+ )?(?:is|are) ([a-z]+)(?:\.|\?|$)"#, in: text) {
            guard let m = count(asked[2]), m <= k, let a = index(asked[3]) else { return nil }
            if asked[2].first?.isNumber == true { used.append(asked[2]) }
            switch asked[1].lowercased() {
            case "exactly": event = { $0[a] == m }
            case "at least": event = { $0[a] >= m }
            default: event = { $0[a] <= m }
            }
            saying = "\(asked[1].lowercased()) \(m) \(items[a].colour)"
        } else {
            return nil
        }
        // (Two taken, and what colours they are, is the kind above's.)
        guard k >= 3 || saying.contains(" than ") else { return nil }
        // Every way the ones taken can be made up, as how many of each colour.
        // (With the first one's colour given, that one is out of the bag and the rest are taken from what's left.)
        var inBag = items.map(\.count)
        var draws = k
        if let first { inBag[first] -= 1; draws -= 1 }
        let n = inBag.reduce(0, +)
        guard draws >= 1, back || draws <= n else { return nil }
        var ways: [[Int]] = []
        func build(_ at: Int, _ left: Int, _ so: [Int]) {
            if at == inBag.count - 1 {
                if back ? inBag[at] > 0 || left == 0 : left <= inBag[at] { ways.append(so + [left]) }
                return
            }
            for take in 0...left where back ? (inBag[at] > 0 || take == 0) : take <= inBag[at] { build(at + 1, left - take, so + [take]) }
        }
        build(0, draws, [])
        func factorial(_ m: Int) -> Int { m <= 1 ? 1 : (2...m).reduce(1, *) }
        // One way's chance: one order's chance, times how many orders it can come in.
        func chance(of way: [Int]) -> (expr: Expr, size: Fraction) {
            var factors: [Expr] = [], size = Fraction(1, 1), gone = 0
            for (colour, many) in way.enumerated() where many > 0 {
                for j in 0..<many {
                    let top = back ? inBag[colour] : inBag[colour] - j, bottom = back ? n : n - gone
                    factors.append(.integer(top) / .integer(bottom)); size = size * Fraction(top, bottom); gone += 1
                }
            }
            let orders = way.reduce(factorial(draws)) { $0 / factorial($1) }
            size = size * Fraction(orders, 1)
            return (orders == 1 ? (factors.count == 1 ? factors[0] : .multiply(factors)) : .multiply([.integer(orders)] + factors), size)
        }
        func whole(_ way: [Int]) -> [Int] { first.map { at in way.enumerated().map { $0.offset == at ? $0.element + 1 : $0.element } } ?? way }
        func name(_ way: [Int]) -> String {
            way.enumerated().filter { $0.element > 0 }.map { "\($0.element) \(items[$0.offset].colour)" }.joined(separator: ", ")
        }
        let wanted = ways.filter { event(whole($0)) }, others = ways.filter { !event(whole($0)) }
        let bag = Step("What's in it", items.map { "\($0.count) \($0.colour)" }.joined(separator: ", ") + ": \(total) in all. "
                       + (back ? "Each one goes back, so every pick is out of \(total)." : "None goes back, so each pick is out of one fewer.")
                       + (first.map { " The first is \(items[$0].colour), which leaves \(n) for the other \(draws)." } ?? ""))
        var problem: Problem, value: Fraction
        if wanted.isEmpty || others.isEmpty {
            value = Fraction(wanted.isEmpty ? 0 : 1, 1)
            problem = Problem(kind: .evaluate(wanted.isEmpty ? .zero : .one), text: "", usesDecimals: false)
            problem.lead = [bag, Step("Work out the chance", wanted.isEmpty ? "That can't happen, so the chance is 0." : "That always happens, so the chance is 1.")]
        } else {
            // Whichever is shorter to add up: the ways it happens, or the ways it doesn't, taken from 1.
            let direct = wanted.count <= others.count
            let terms = (direct ? wanted : others).map { (way: $0, chance: chance(of: $0)) }
            guard terms.count <= 8 else { return nil }
            let sum = terms.reduce(Fraction(0, 1)) { $0 + $1.chance.size }
            value = direct ? sum : Fraction(1, 1) - sum
            let added: Expr = terms.count == 1 ? terms[0].chance.expr : .add(terms.map(\.chance.expr))
            problem = Problem(kind: .evaluate(direct ? added : Expr.one - added), text: "", usesDecimals: false)
            let list = terms.map { name($0.way) }.joined(separator: "; or ")
            let need = "For \(saying), the \(draws)\(first == nil ? "" : " others") taken have to be: \(wanted.map(name).joined(separator: "; or "))."
            problem.lead = [bag,
                            Step("What has to be taken", ofLeft || first != nil || wanted.count > 1 ? need : "\(saying.prefix(1).uppercased() + saying.dropFirst())."),
                            Step(direct ? "The chance of each" : "The chance of each way it doesn't happen",
                                 (direct ? "" : "It's shorter to work out the ways it doesn't happen (\(list)) and take them from 1. ")
                                 + "Multiply along one order, then times by how many orders it can come in.",
                                 terms.map { MathLine(.symbol(name($0.way)), $0.chance.expr, $0.chance.size.expr) })]
        }
        return Found(problem: problem, used: used, size: value.double)
    }

    // MARK: How many there are, from a chance

    /// "In a class there are n boys, a total of 25 students. Two of the students are chosen at
    /// random. The probability that both students are boys is 7/20. Work out the value of n."
    private static func unknownCount(_ question: Question) -> Found? {
        let text = question.text
        guard let letter = groups(#"\bwork out the value of ([a-z])\b|\bfind (?:the value of )?([a-z])\b"#, in: text).map({ $0[1].isEmpty ? $0[2] : $0[1] }),
              let named = groups(#"\b\#(letter) ([a-z]+)\b"#, in: text)?[1].lowercased(), named.count >= 3,
              let total = groups(#"\b(?:a )?total of (\d+) ([a-z]+)|\b(\d+) ([a-z]+) (?:altogether|in total)"#, in: text),
              let size = Int(total[1].isEmpty ? total[3] : total[1]), size >= 2,
              has(#"\b(?:two|2) (?:of the )?[a-z]+ (?:are|is) (?:chosen|picked|selected|taken)\b"#, text),
              let stated = groups(#"probability (?:that )?both [a-z]+ (?:are|is) ([a-z]+) is (\#(number))(?![\d/])"#, in: text),
              single(stated[1]) == single(named), let p = chance(stated[2]) else { return nil }
        // n/T × (n − 1)/(T − 1) = p, for a whole number n from 2 to T.
        let pairs = Fraction(size * (size - 1), 1) * p
        guard pairs.denominator == 1 else { return nil }
        let product = pairs.numerator
        let roots = (2...size).filter { $0 * ($0 - 1) == product }
        guard roots.count == 1, let n = roots.first else { return nil }
        let x = Expr.symbol(letter)
        let lead = [
            Step("Write the chance of both", "The first is one of \(letter) out of \(size). It isn't put back, so the second is one of \(letter) − 1 out of \(size - 1).",
                 [MathLine(x / .integer(size) * ((x - .one) / .integer(size - 1)), p.expr)]),
            Step("Clear the fractions", "Multiply both sides by \(size) × \(size - 1) = \(size * (size - 1)).",
                 [MathLine(x * (x - .one), .integer(product)), MathLine(.power(x, .two) - x - .integer(product), .zero)]),
            Step("Solve it", "Factorise. \(letter) is a number of \(named), so it can't be negative.",
                 [MathLine((x - .integer(n)) * (x + .integer(n - 1)), .zero), MathLine(x, .integer(n))]),
        ]
        var problem = Problem(kind: .worded(question: "Find \(letter)", answers: [MathLine(x, .integer(n))]), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: [String(size), stated[2]], size: Double(n))
    }

    // MARK: One thing, then another if the first comes out a certain way

    /// "A fair spinner has five equal sections numbered 1, 2, 3, 4 and 5. A fair six-sided dice
    /// has five red faces and one green face. The spinner is spun. If the spinner shows an even
    /// number, the dice is thrown. Work out the probability of getting an even number and the colour green."
    private static func twoStages(_ question: Question) -> Found? {
        let text = question.text
        guard let first = groups(#"\bfair ([a-z]+) has (\d+|[a-z]+) equal (?:sections|parts|sectors) numbered ((?:\d+(?:, | and |,? and ))+\d+)"#, in: text),
              let sections = count(first[2]),
              let second = groups(#"\bfair (?:(\d+|[a-z]+)-sided )?([a-z]+) has ((?:(?:\d+|[a-z]+) [a-z]+ faces?(?:, | and )?){2,4})"#, in: text),
              let faces = counted(second[3], noun: "faces?") else { return nil }
        let numbers = every(#"\d+"#, in: first[3]).compactMap { Int($0[0]) }
        guard numbers.count == sections else { return nil }
        let sides = faces.reduce(0) { $0 + $1.count }
        if !second[1].isEmpty { guard count(second[1]) == sides else { return nil } }
        // The condition for going on, and what's asked: the same kind of number, and a colour.
        guard let condition = groups(#"\bif the \#(first[1]) (?:shows|lands on) an? ([a-z]+) number\b"#, in: text)?[1].lowercased(),
              let asked = groups(#"probability of (?:getting )?an? ([a-z]+) number and (?:the colou?r |a )?([a-z]+)\b"#, in: text),
              asked[1].lowercased() == condition, let shown = faces.first(where: { single($0.colour) == single(asked[2]) }) else { return nil }
        let kinds: [String: (Int) -> Bool] = ["even": { $0 % 2 == 0 }, "odd": { $0 % 2 == 1 }, "prime": { n in n > 1 && (2..<n).allSatisfy { n % $0 != 0 } },
                                             "square": { n in { let r = Int(Double(n).squareRoot().rounded()); return r * r == n }() }]
        guard let test = kinds[condition] else { return nil }
        let hits = numbers.filter(test)
        guard !hits.isEmpty else { return nil }
        let a = Fraction(hits.count, sections), b = Fraction(shown.count, sides)
        let lead = [
            Step("The \(first[1])", "\(hits.count) of its \(sections) sections \(hits.count == 1 ? "is" : "are") \(condition) (\(hits.map(String.init).joined(separator: ", "))).", [MathLine(.symbol("P(\(condition))"), a.expr)]),
            Step("The \(second[2])", "It is only used after an \(condition) number. \(shown.count) of its \(sides) faces \(shown.count == 1 ? "is" : "are") \(shown.colour).", [MathLine(.symbol("P(\(shown.colour))"), b.expr)]),
            Step("Both", "Multiply along the branches: \(condition), then \(shown.colour)."),
        ]
        var problem = Problem(kind: .evaluate(a.expr * b.expr), text: "", usesDecimals: false)
        problem.lead = lead
        var used = numbers.map(String.init)
        if first[2].first?.isNumber == true { used.append(first[2]) }
        if second[1].first?.isNumber == true { used.append(second[1]) }
        used += faces.compactMap { item in second[3].range(of: #"\b\#(item.count)\b"#, options: .regularExpression) != nil ? String(item.count) : nil }
        return Found(problem: problem, used: used, size: (a * b).double)
    }

    // MARK: Two dice

    /// "Two ordinary fair dice are rolled. Work out the probability that both dice land on a number less than 3"
    private static func twoDice(_ question: Question) -> Found? {
        let text = question.text
        guard has(#"\b(?:two|2) (?:ordinary |fair |six-sided )*(?:ordinary|fair) (?:six-sided )?dice\b"#, text),
              let asked = groups(#"probability (?:that )?(both|exactly one of the|only one of the|at least one of the|neither of the) dice lands? on (?:a |an )?(?:number (less|greater|more) than (\d)|(even|odd|prime|square) number|(six|6))"#, in: text) else { return nil }
        let faces = (1...6).filter { face in
            if !asked[2].isEmpty, let limit = Int(asked[3]) { return asked[2].lowercased() == "less" ? face < limit : face > limit }
            switch asked[4].lowercased() {
            case "even": return face % 2 == 0
            case "odd": return face % 2 == 1
            case "prime": return [2, 3, 5].contains(face)
            case "square": return [1, 4].contains(face)
            default: return face == 6
            }
        }
        guard !faces.isEmpty, faces.count < 6 else { return nil }
        let p = Fraction(faces.count, 6), q = Fraction(1, 1) - p
        let what = asked[2].isEmpty ? (asked[4].isEmpty ? "a six" : "an \(asked[4].lowercased()) number") : "a number \(asked[2].lowercased()) than \(asked[3])"
        var lead = [Step("One dice", "\(faces.count) of the 6 faces (\(faces.map(String.init).joined(separator: ", "))) are \(what). The two dice don't change each other, so their chances multiply.",
                         [MathLine(.symbol("P"), p.expr)])]
        let expr: Expr, size: Fraction
        switch asked[1].lowercased().split(separator: " ").first.map(String.init) ?? "" {
        case "both": expr = p.expr * p.expr; size = p * p; lead.append(Step("Both", "It has to happen on the first and on the second."))
        case "at": expr = Expr.one - q.expr * q.expr; size = Fraction(1, 1) - q * q; lead.append(Step("At least one", "Everything except neither: 1 take away the chance of it happening on neither."))
        case "neither": expr = q.expr * q.expr; size = q * q; lead.append(Step("Neither", "It has to not happen on the first and not on the second."))
        default: expr = .two * p.expr * q.expr; size = Fraction(2, 1) * p * q; lead.append(Step("Exactly one", "On the first and not the second, or the other way round: two ways with the same chance."))
        }
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = lead
        var used = ["2"].filter { _ in text.range(of: #"\b2 (?:ordinary|fair|six-sided)"#, options: .regularExpression) != nil }
        if !asked[3].isEmpty { used.append(asked[3]) }
        if asked[5] == "6" { used.append("6") }
        return Found(problem: problem, used: used, size: size.double)
    }

    /// What's in a bag: "A bag contains 8 balls. 3 are red and 5 are blue." or "A bag contains 3
    /// red balls and 5 blue balls.", with the numbers that said so.
    private static func contents(_ text: String) -> (items: [(colour: String, count: Int)], used: [String])? {
        if let total = groups(#"\bcontains? (\d+|[a-z]+) ([a-z]+)\. (?:Of these,? )?((?:(?:\d+|[a-z]+) (?:are|is) [a-z]+(?:, | and )?){2,4})"#, in: text) {
            let pieces = every(#"(\d+|[a-z]+) (?:are|is) ([a-z]+)"#, in: total[3])
            let items = pieces.compactMap { piece in count(piece[1]).map { (colour: piece[2].lowercased(), count: $0) } }
            guard items.count == pieces.count, let whole = count(total[1]), whole == items.reduce(0, { $0 + $1.count }) else { return nil }
            return (items, [total[1]] + pieces.map(\.[1]))
        }
        if let list = groups(#"\b(?:contains?|there are) ((?:(?:\d+|[a-z]+) [a-z]+ [a-z]+(?:, | and )?){2,4})"#, in: text), let found = counted(list[1]) {
            return (found, every(#"(\d+) [a-z]+ [a-z]+"#, in: list[1]).map(\.[1]))
        }
        // How many in all, then how many of each up to where one is taken: "There are 9 counters in a
        // bag. 7 of the counters are green. 2 of the counters are blue.", "Adam has 10 sweets in a bag.
        // 5 are cherry sweets, 4 are lemon sweets and 1 is an orange sweet."
        guard let all = groups(#"\b(?:contains?|there are|has) (?:a [a-z]+ of )?(\d+) ([a-z]+)\b"#, in: text), let whole = Int(all[1]), whole >= 2,
              let start = text.range(of: all[0]) else { return nil }
        var rest = String(text[start.upperBound...])
        if let stop = rest.range(of: #"\b(?:takes|picks|chooses|selects|draws|taken|picked|chosen|selected|drawn|at random)\b"#, options: [.regularExpression, .caseInsensitive]) { rest = String(rest[..<stop.lowerBound]) }
        let noun = NSRegularExpression.escapedPattern(for: single(all[2]))
        let pieces = every(#"(\d+) (?:of the [a-z]+ )?(?:are|is) (?:an? )?([a-z]+)"#, in: rest)
        if pieces.count >= 2 {
            let items = pieces.compactMap { piece in Int(piece[1]).map { (colour: piece[2].lowercased(), count: $0) } }
            guard Set(items.map { single($0.colour) }).count == items.count, items.reduce(0, { $0 + $1.count }) == whole else { return nil }
            return (items, [all[1]] + pieces.map(\.[1]))
        }
        // "The discs are either blue or yellow in the ratio 4 : 1."
        if let ratio = groups(#"\b(?:either )?([a-z]+) or ([a-z]+) in the ratio (\d+) ?: ?(\d+)\b"#, in: rest), let a = Int(ratio[3]), let b = Int(ratio[4]), a + b > 0, whole % (a + b) == 0 {
            let unit = whole / (a + b)
            return ([(ratio[1].lowercased(), a * unit), (ratio[2].lowercased(), b * unit)], [all[1], ratio[3], ratio[4]])
        }
        // "Each card is either red or black. One-third of the cards in the pack are red."
        if let pair = groups(#"\beither ([a-z]+) or ([a-z]+)\b"#, in: rest),
           let part = groups(#"\b(one-third|one third|two-thirds|two thirds|one-quarter|one quarter|three-quarters|three quarters|half|one-fifth|one fifth|(\d+)/(\d+)) of the \#(noun)(?:e?s)?(?: in the [a-z]+)? (?:are|is) ([a-z]+)\b"#, in: rest) {
            let named: [String: Fraction] = ["one-third": Fraction(1, 3), "one third": Fraction(1, 3), "two-thirds": Fraction(2, 3), "two thirds": Fraction(2, 3), "one-quarter": Fraction(1, 4), "one quarter": Fraction(1, 4),
                                             "three-quarters": Fraction(3, 4), "three quarters": Fraction(3, 4), "half": Fraction(1, 2), "one-fifth": Fraction(1, 5), "one fifth": Fraction(1, 5)]
            guard let share = named[part[1].lowercased()] ?? (Int(part[2]).flatMap { top in Int(part[3]).map { Fraction(top, $0) } }), share.numerator < share.denominator else { return nil }
            let colours = [pair[1].lowercased(), pair[2].lowercased()], which = part[4].lowercased()
            guard let at = colours.firstIndex(of: which) else { return nil }
            let size = Fraction(whole, 1) * share
            guard size.denominator == 1 else { return nil }
            var items = [(colour: colours[0], count: 0), (colour: colours[1], count: 0)]
            items[at].count = size.numerator; items[1 - at].count = whole - size.numerator
            return (items, [all[1]] + (part[2].isEmpty ? [] : [part[2], part[3]]))
        }
        return nil
    }

    // MARK: A bag that changes after each one taken

    /// "A bag contains 30 discs. 10 are red and 20 are blue. One disc is taken out at random and
    /// replaced by two of the other colour. Another disc is then taken out at random and replaced
    /// by two of the other colour. Another disc is then taken out at random. Work out the
    /// probability that all three discs taken out are red."
    private static func changing(_ question: Question) -> Found? {
        let text = question.text
        guard has(#"\breplaced by\b"#, text), let bag = contents(text), bag.items.count == 2 else { return nil }
        let draws = every(#"\b(?:one|another|a) [a-z]+ is (?:then )?(?:taken|picked|chosen|removed|drawn)(?: out)?(?: of the [a-z]+)? at random(?: and (?:(not replaced)|(?:replaced|put back)(?: by (\d+|one|two|three|four|five) (?:of the other colou?r|[a-z]+ of the other colou?r))?))?"#, in: text)
        guard draws.count >= 2, draws.count <= 4,
              let asked = groups(#"probability that (?:all (\d+|two|three|four) |both )(?:of the )?[a-z]+ (?:taken(?: out)?|picked|chosen|drawn|removed)? ?(?:are|were) ([a-z]+)"#, in: text),
              (asked[1].isEmpty ? 2 : count(asked[1])) == draws.count else { return nil }
        let colour = asked[2].lowercased()
        guard var mine = bag.items.first(where: { single($0.colour) == single(colour) })?.count,
              var others = bag.items.first(where: { single($0.colour) != single(colour) })?.count else { return nil }
        var used = bag.used
        var expr: Expr? = nil, size = Fraction(1, 1), lines: [String] = []
        for (index, draw) in draws.enumerated() {
            let total = mine + others
            guard mine > 0 else { return nil }
            let p = Fraction(mine, total)
            lines.append("\(mine) of the \(total) are \(colour)")
            let term = Expr.integer(mine) / .integer(total)
            expr = expr.map { $0 * term } ?? term
            size = size * p
            // What happens to the one taken, before the next.
            mine -= 1
            if index < draws.count - 1 {
                if !draw[2].isEmpty {
                    guard let added = count(draw[2]) else { return nil }
                    if draw[2].first?.isNumber == true { used.append(draw[2]) }
                    others += added
                } else if draw[1].isEmpty {
                    // Put back with nothing added.
                    guard has(#"\b(?:replaced|put back)\b"#, draw[0]) else { return nil }
                    mine += 1
                }
            }
        }
        guard let product = expr else { return nil }
        let lead = [Step("Follow the bag", "Each \(colour) one taken out goes, and what's said to be put in its place is added, so the counts change from one go to the next: \(lines.joined(separator: ", then ")).", []),
                    Step("All \(colour)", "Multiply the chances of \(colour) each time.")]
        var problem = Problem(kind: .evaluate(product), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: size.double)
    }

    // MARK: From a table of results

    /// "Today, she made 120 calls. The table shows the results. [Not answered 33, Answered but
    /// sale not made 81, Answered and sale made 6] … Rosie will make 500 calls. How many sales
    /// does she expect to make?", and "Write down the relative frequency that a call was not answered."
    private static func fromTable(_ question: Question) -> Found? {
        let text = question.text
        guard let start = question.lines.firstIndex(where: { has(#"\btable (?:shows|below|gives)\b"#, $0) }) else { return nil }
        // The table's lines: up to the next sentence.
        var cells: [String] = []
        for line in question.lines[(start + 1)...] {
            if line.hasSuffix(".") || line.hasSuffix("?") || line.split(separator: " ").count >= 6 || has(asking, line) { break }
            if has(#"^(?:frequency|results?|outcomes?|number of|total|type|colou?r)\b"#, line) { continue }
            cells.append(line)
        }
        // A label, then its count. A count before any label, or two counts together, means the
        // table was read out of order: no telling which count is whose.
        var rows: [(label: String, count: Int?)] = []
        var countsUsed: [String] = []
        for cell in cells {
            if let lone = Int(cell) {
                guard let last = rows.last, last.count == nil else { return nil }
                rows[rows.count - 1].count = lone
                countsUsed.append(cell)
            } else if let both = groups(#"^([A-Za-z][A-Za-z ,'-]*?) (\d+)$"#, in: cell), let size = Int(both[2]) {
                rows.append((both[1], size)); countsUsed.append(both[2])
            } else if cell.range(of: #"\d"#, options: .regularExpression) == nil {
                rows.append((cell, nil))
            } else {
                return nil
            }
        }
        guard rows.count >= 2 else { return nil }
        // How many there were in all.
        let stated = groups(#"\b(?:made|did|asked|recorded|surveyed|threw|rolled|spun|had|carried out|tested) (\d+) ([a-z]+)"#, in: text)
        let missing = rows.indices.filter { rows[$0].count == nil }
        var total: Int, filled = ""
        if missing.isEmpty {
            total = rows.reduce(0) { $0 + $1.count! }
            if let stated { guard Int(stated[1]) == total else { return nil } }
        } else {
            // One count not read: only the last, and only when the total is given.
            guard missing == [rows.count - 1], let stated, let whole = Int(stated[1]) else { return nil }
            let known = rows.dropLast().reduce(0) { $0 + $1.count! }
            guard whole > known else { return nil }
            rows[rows.count - 1].count = whole - known
            total = whole
            filled = "The counts add up to \(whole), so \(rows.last!.label.lowercased()) is \(whole) − \(rows.dropLast().map { String($0.count!) }.joined(separator: " − ")) = \(whole - known)."
        }
        func words(_ phrase: String) -> Set<String> {
            Set(phrase.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { !["a", "an", "the", "was", "were", "is", "are", "be", "and", "but", "it"].contains($0) }.map(single))
        }
        let negative: Set<String> = ["not", "no", "n't"]
        var used = countsUsed + (stated.map { [$0[1]] } ?? [])
        if let asked = groups(#"\brelative frequency (?:that|of) (?:a |an |the )?([a-z ]+?)(?:\.|\?|$)"#, in: text) {
            // "a call was not answered": what happened to it, not what it was.
            let key = words(groups(#"^[a-z]+ (?:was|were|is|are) (.+)$"#, in: asked[1])?[1] ?? asked[1])
            let exact = rows.filter { words($0.label) == key }
            guard exact.count == 1, let row = exact.first, let size = row.count else { return nil }
            var problem = Problem(kind: .evaluate(Expr.integer(size) / .integer(total)), text: "", usesDecimals: false)
            problem.lead = (filled.isEmpty ? [] : [Step("Fill in the table", filled)]) + [Step("Relative frequency", "How many times it happened out of how many tries: \(size) out of \(total).")]
            return Found(problem: problem, used: used, size: Double(size) / Double(total))
        }
        guard let asked = groups(#"\bhow many ([a-z]+) (?:does|do|will|would|should) [a-z]+ expect"#, in: text),
              let more = groups(#"\b(?:will|is going to|plans to) (?:make|do|ask|roll|throw|spin|carry out|test|have) (?:another )?(\d+) ([a-z]+)|\b(\d+) more ([a-z]+)"#, in: text),
              let goes = Int(more[1].isEmpty ? more[3] : more[1]), goes > 0 else { return nil }
        let thing = single(asked[1])
        let matching = rows.filter { row in
            let label = words(row.label)
            return label.contains(thing) && label.isDisjoint(with: negative)
        }
        guard matching.count == 1, let row = matching.first, let size = row.count else { return nil }
        used.append(String(goes))
        let expr = Expr.integer(size) / .integer(total) * .integer(goes)
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = (filled.isEmpty ? [] : [Step("Fill in the table", filled)]) + [
            Step("Estimate the chance", "\(row.label) happened \(size) times out of \(total), so the relative frequency is \(size)/\(total)."),
            Step("Multiply by the number of goes", "The expected number is that times \(goes)."),
        ]
        return Found(problem: problem, used: used, size: Double(size) / Double(total) * Double(goes))
    }

    // MARK: Two groups described in words

    /// "A school year has 78 students. 28 wear glasses. 1/4 of the students who wear glasses are
    /// left-handed. 30% of the students who do not wear glasses are left-handed. A left-handed
    /// student is chosen at random. Work out the probability that the student wears glasses."
    /// Or "42 are male and 44 are female. 1/3 of the male teachers have blue eyes. 1/4 of the female
    /// teachers have blue eyes. One teacher who has blue eyes is chosen at random. … the probability that the teacher is male."
    private static func inGroups(_ question: Question) -> Found? {
        let text = question.text
        let share = #"(\d+/\d+|\d+(?:\.\d+)?%)"#
        var names: [String] = [], who: [String] = [], sizes: [Int] = [], parts: [(Fraction, String)] = [], used: [String] = [], property = ""
        guard let all = groups(#"\bhas (\d+) ([a-z]+)\b"#, in: text), let total = Int(all[1]) else { return nil }
        used.append(all[1])
        if let one = groups(#"(?:^|\. )(\d+) ([a-z]+(?: [a-z]+){0,3})\. "#, in: text),
           let first = groups(#"\#(share) of the [a-z]+ who \#(NSRegularExpression.escapedPattern(for: one[2])) (?:are|is|have|has) ([a-z][a-z-]*(?: [a-z]+)?)"#, in: text),
           let second = groups(#"\#(share) of the [a-z]+ who (?:do not|don't|does not) \#(NSRegularExpression.escapedPattern(for: verbBase(one[2]))) (?:are|is|have|has) ([a-z][a-z-]*(?: [a-z]+)?)"#, in: text),
           let inside = Int(one[1]), inside < total, let f = chance(first[1]), let g = chance(second[1]), alike(first[2], second[2]) {
            names = [one[2].lowercased(), "not " + one[2].lowercased()]
            who = ["who " + verbBase(one[2].lowercased()), "who don't " + verbBase(one[2].lowercased())]
            sizes = [inside, total - inside]
            parts = [(f, first[1]), (g, second[1])]
            property = longer(first[2], second[2])
            used += [one[1], first[1], second[1]]
        } else if let pair = groups(#"\b(\d+) are ([a-z]+) and (\d+) are ([a-z]+)\b"#, in: text), let x = Int(pair[1]), let y = Int(pair[3]), x + y == total,
                  let first = groups(#"\#(share) of the \#(pair[2]) [a-z]+ (?:are|is|have|has|wear) ([a-z][a-z-]*(?: [a-z]+)?)"#, in: text),
                  let second = groups(#"\#(share) of the \#(pair[4]) [a-z]+ (?:are|is|have|has|wear) ([a-z][a-z-]*(?: [a-z]+)?)"#, in: text),
                  let f = chance(first[1]), let g = chance(second[1]), alike(first[2], second[2]) {
            names = [pair[2].lowercased(), pair[4].lowercased()]
            who = ["who are " + names[0], "who are " + names[1]]
            sizes = [x, y]
            parts = [(f, first[1]), (g, second[1])]
            property = longer(first[2], second[2])
            used += [pair[1], pair[3], first[1], second[1]]
        } else {
            return nil
        }
        // How many in each group have it: whole numbers, or it was misread.
        var having: [Int] = []
        for (index, part) in parts.enumerated() {
            let amount = part.0 * Fraction(sizes[index], 1)
            guard amount.denominator == 1 else { return nil }
            having.append(amount.numerator)
        }
        let both = having[0] + having[1]
        guard both > 0 else { return nil }
        let they = has(#"\b(?:have|has) \#(NSRegularExpression.escapedPattern(for: property))"#, text) ? "who have \(property)" : "who are \(property)"
        let counting = Step("Count each group", "\(parts[0].1) of the \(sizes[0]) \(who[0]) is \(having[0]); \(parts[1].1) of the \(sizes[1]) \(who[1]) is \(having[1]). That's \(both) \(they) in all.",
                            [MathLine(.integer(having[0]) + .integer(having[1]), .integer(both))])
        // Chosen from those with the property: the chance they're in the first group (or the second).
        if let chosen = groups(#"\b(?:an?|one) ([a-z][a-z-]*) [a-z]+ is chosen at random|\bone [a-z]+ who (?:has|have|is|are) ([a-z][a-z -]*?) is chosen at random"#, in: text),
           alike(chosen[1].isEmpty ? chosen[2] : chosen[1], property),
           let target = groups(#"probability (?:that )?the [a-z]+ ([a-z][a-z ]*?)(?:\.|\?|$)"#, in: text)?[1].lowercased() {
            let which: Int
            let plain = target.replacingOccurrences(of: #"^(?:is|was) "#, with: "", options: .regularExpression)
            let negated = groups(#"^(?:does not|doesn't|do not|don't) (.+)$"#, in: plain)?[1]
            if negated == nil, sameWords(plain, names[0]) { which = 0 }
            else if names[1].hasPrefix("not ") ? negated.map({ sameWords($0, names[0]) }) ?? false : sameWords(plain, names[1]) { which = 1 }
            else { return nil }
            var problem = Problem(kind: .evaluate(Expr.integer(having[which]) / .integer(both)), text: "", usesDecimals: false)
            problem.lead = [counting, Step("Out of those", "Only the \(both) \(they) can be chosen, and \(having[which]) of them are the ones \(who[which]).")]
            return Found(problem: problem, used: used, size: Double(having[which]) / Double(both))
        }
        return nil
    }

    /// The verb as it's said after "do not": "wear glasses" for "wears glasses".
    private static func verbBase(_ phrase: String) -> String {
        var words = phrase.split(separator: " ").map(String.init)
        guard let first = words.first else { return phrase }
        if first.hasSuffix("ies"), first.count > 4 { words[0] = String(first.dropLast(3)) + "y" }
        else if first.hasSuffix("es"), ["has"].contains(first) == false, first.count > 3, first.dropLast(2).hasSuffix("sh") || first.dropLast(2).hasSuffix("ch") { words[0] = String(first.dropLast(2)) }
        else if first == "has" { words[0] = "have" }
        else if first.hasSuffix("s"), !first.hasSuffix("ss") { words[0] = String(first.dropLast()) }
        return words.joined(separator: " ")
    }

    /// The same words, give or take an s on a verb: "wears glasses" and "wear glasses".
    private static func sameWords(_ a: String, _ b: String) -> Bool {
        verbBase(a.lowercased()) == verbBase(b.lowercased())
    }

    /// The same property, one perhaps cut short in the reading: "left-hande" and "left-handed".
    private static func alike(_ a: String, _ b: String) -> Bool {
        let (x, y) = (a.lowercased(), b.lowercased())
        let short = x.count <= y.count ? x : y, long = x.count <= y.count ? y : x
        return short.count >= 5 && long.hasPrefix(short) && long.count - short.count <= 2
    }

    private static func longer(_ a: String, _ b: String) -> String { a.count >= b.count ? a.lowercased() : b.lowercased() }

    // MARK: Guessing a digit

    /// "Each digit is a number from 0 to 9 … The code starts 5 4 1. Amy knows the last digit is odd
    /// but not 7. She chooses a different odd number at random. What is the probability that she
    /// chooses the correct number?"
    private static func guess(_ question: Question) -> Found? {
        let text = question.text
        guard let range = groups(#"\bdigits? (?:is|are) (?:a number|numbers) from (\d) to (\d)\b"#, in: text),
              let low = Int(range[1]), let high = Int(range[2]), low < high,
              let known = groups(#"\b(?:last|first|second|third|fourth|missing) digit is (odd|even|prime)(?: but not (\d))?"#, in: text),
              has(#"\bchooses (?:a |an )?(?:different )?(?:odd |even |prime )?(?:number|digit) at random\b"#, text),
              has(#"probability (?:that )?(?:she|he|they) (?:chooses|picks|gets) the (?:correct|right) (?:number|digit)"#, text) else { return nil }
        let test: (Int) -> Bool
        switch known[1].lowercased() {
        case "odd": test = { $0 % 2 == 1 }
        case "even": test = { $0 % 2 == 0 }
        default: test = { [2, 3, 5, 7].contains($0) }
        }
        let ruledOut = Int(known[2])
        let left = (low...high).filter { test($0) && $0 != ruledOut }
        guard !left.isEmpty else { return nil }
        // The digits it has, and how many there are, don't change which last digit it could be.
        var used = [range[1], range[2]] + (known[2].isEmpty ? [] : [known[2]])
        if let size = groups(#"\bhas (\d) digits\b"#, in: text) { used.append(size[1]) }
        if let start = groups(#"\bstarts ((?:\d ?)+)"#, in: text) { used += every(#"\d"#, in: start[1]).map(\.[0]) }
        var problem = Problem(kind: .evaluate(Expr.one / .integer(left.count)), text: "", usesDecimals: false)
        problem.lead = [Step("List what it could be", "\(known[1].capitalized) digits from \(low) to \(high)\(ruledOut.map { " other than \($0)" } ?? ""): \(left.map(String.init).joined(separator: ", ")). That's \(left.count), and only one is right.")]
        return Found(problem: problem, used: used, size: 1 / Double(left.count))
    }

    // MARK: A Venn diagram described in words

    /// "50 people were asked if they speak French or German or Spanish. Of these people, 31 speak
    /// French, 2 speak French, German and Spanish, 4 speak French and Spanish but not German, 7
    /// speak German and Spanish, 8 do not speak any of the languages, all 10 people who speak
    /// German speak at least one other language. Two of the 50 people are chosen at random. Work
    /// out the probability that they both only speak Spanish." Also one chosen, and "given that".
    private static func venn(_ question: Question) -> Found? {
        let text = question.text
        guard let everyone = groups(#"\b(\d+) ([a-z]+) (?:were|are|was) asked\b|\basks (\d+) ([a-z]+)\b|\bsurveyed (\d+) ([a-z]+)\b"#, in: text) else { return nil }
        let totalText = [everyone[1], everyone[3], everyone[5]].first { !$0.isEmpty } ?? ""
        guard let total = Int(totalText), total > 0 else { return nil }
        // The three sets: a list of names, each of them said again somewhere else.
        let name = #"(?:type|set|group|club) [A-Z0-9]\b|[A-Z][a-z]+"#
        var names: [String] = [], shownNames: [String] = []
        for list in everyExact(#"(\#(name))(?:,|, or| or) (\#(name))(?:,|, or| or|, and| and) (\#(name))"#, in: text) {
            let found = [list[1], list[2], list[3]].map { $0.lowercased() }
            guard Set(found).count == 3,
                  found.allSatisfy({ every(#"\b\#(NSRegularExpression.escapedPattern(for: $0))\b"#, in: text).count >= 2 }) else { continue }
            names = found; shownNames = [list[1], list[2], list[3]]
            break
        }
        guard names.count == 3 else { return nil }
        let full = 7
        func mentions(_ phrase: String) -> [Int] {
            names.indices.filter { has(#"\b\#(NSRegularExpression.escapedPattern(for: names[$0]))\b"#, phrase) }
        }
        // Which parts of the diagram a phrase means, by which sets each is inside.
        func regions(_ phrase: String) -> [Int]? {
            let lower = phrase.lowercased()
            // A name that isn't one of the sets ("type 4" for type A) means it was misread.
            if everyExact(#"\b(?:(?:type|set|group|club) [A-Za-z0-9]\b|[A-Z][a-z]+)"#, in: phrase).contains(where: { !names.contains($0[0].lowercased()) }) { return nil }
            if has(#"\b(?:do not|don't|does not|did not)\b[^,]*\bany\b|\bnone of\b|\bneither\b"#, lower) { return [0] }
            if has(#"\ball three\b"#, lower) { return [full] }
            let parts = lower.components(separatedBy: "but not")
            guard parts.count <= 2 else { return nil }
            let positive = mentions(parts[0]), negative = parts.count == 2 ? mentions(parts[1]) : []
            guard !positive.isEmpty, Set(positive).isDisjoint(with: negative), parts.count == 1 || !negative.isEmpty else { return nil }
            // Anything else that would change which ones are meant.
            if has(#"\b(?:not|n't|no|nor|or|except|least|most|exactly|more|less|fewer|than|other|either)\b"#, parts[0]) { return nil }
            let only = has(#"\bonly\b"#, parts[0])
            let inside = positive.reduce(0) { $0 | 1 << $1 }, outside = negative.reduce(0) { $0 | 1 << $1 }
            return (0...full).filter { only ? $0 == inside : ($0 & inside == inside && $0 & outside == 0) }
        }
        // What's said about how many: one line each, after the line with how many were asked.
        var facts: [(masks: [Int], count: Int)] = [(Array(0...full), total)]
        var used = [totalText]
        guard let start = question.lines.firstIndex(where: { has(#"\b(?:asked|asks|surveyed)\b"#, $0) }) else { return nil }
        var said = 0
        for line in question.lines[(start + 1)...] {
            if has(#"\bat random\b"#, line) { break }
            guard let fact = groups(#"^(all )?(\d+) (.+?)[.,]?$"#, in: line), let size = Int(fact[2]) else {
                if said > 0 { break } else { continue }
            }
            let phrase = fact[3]
            if !fact[1].isEmpty {
                // "all 20 who use type C also use at least one of type A and type B"
                guard let all = groups(#"^(?:[a-z]+ )?who (.+?) (?:also )?(?:[a-z]+ )?at least one (?:other|of)\b"#, in: phrase) else { return nil }
                let named = mentions(all[1])
                guard named.count == 1 else { return nil }
                facts.append(((0...full).filter { $0 & (1 << named[0]) != 0 }, size))
                facts.append(([1 << named[0]], 0))
            } else {
                guard let masks = regions(phrase) else { return nil }
                facts.append((masks, size))
            }
            used.append(fact[2])
            said += 1
        }
        guard said >= 4 else { return nil }
        let rows = facts.map { fact in (0...full).map { fact.masks.contains($0) ? Fraction(1, 1) : Fraction(0, 1) } + [Fraction(fact.count, 1)] }
        guard let solved = solveLinear(rows, unknowns: full + 1) else { return nil }
        var counts: [Int] = []
        for value in solved {
            guard let value, value.denominator == 1, value.numerator >= 0 else { return nil }
            counts.append(value.numerator)
        }
        func label(_ mask: Int) -> String {
            switch mask {
            case 0: return "none"
            case full: return "all three"
            default:
                let inside = names.indices.filter { mask & (1 << $0) != 0 }.map { shownNames[$0] }
                return inside.joined(separator: " and ") + " only"
            }
        }
        let filled = Step("Fill in the Venn diagram", "Start from the middle and work out: " + (0...full).reversed().map { "\(label($0)) \(counts[$0])" }.joined(separator: ", ") + ". These add up to \(total).")
        let tail = #"(.+?)(?:\.|\?|$)"#
        var expr: Expr, size: Double, step: Step
        if let given = groups(#"\bgiven that (?:this|the|they|he|she) (?:[a-z]+ )?(.+?), (?:\([a-z]\) )?(?:work out |find |write down )?the probability (?:that )?(?:this|the|they|he|she) (?:[a-z]+ )?(?:also )?\#(tail)"#, in: text),
           has(#"\b(?:one|a) (?:of the )?[a-z]+ (?:is|was) (?:chosen|picked|selected) at random\b"#, text),
           let condition = regions(given[1]), let event = regions(given[2]) {
            let within = condition.reduce(0) { $0 + counts[$1] }, both = condition.filter(event.contains).reduce(0) { $0 + counts[$1] }
            guard within > 0 else { return nil }
            expr = Expr.integer(both) / .integer(within); size = Double(both) / Double(within)
            step = Step("Only those it's given", "It's one of the \(within) who \(verbBase(given[1])), and \(both) of them \(verbBase(given[2])).")
        } else if let two = groups(#"\b(?:two|2) of the (?:(\d+) )?[a-z]+ are (?:chosen|picked|selected) at random\b"#, in: text),
                  let asked = groups(#"\bprobability (?:that )?(?:they |the two [a-z]+ |both [a-z]+ )?(?:both |each )?\#(tail)"#, in: text),
                  let event = regions(asked[1]) {
            if !two[1].isEmpty { guard Int(two[1]) == total else { return nil }; used.append(two[1]) }
            let n = event.reduce(0) { $0 + counts[$1] }
            guard !has(#"\bwith replacement\b"#, text) else { return nil }
            expr = Expr.integer(n) / .integer(total) * (Expr.integer(n - 1) / .integer(total - 1)); size = Double(n * (n - 1)) / Double(total * (total - 1))
            step = Step("Both of them", "\(n) of the \(total) \(asked[1]). The first is one of \(n) out of \(total); the second is a different one, one of \(n - 1) out of \(total - 1).")
        } else if has(#"\b(?:one|a) (?:of the )?[a-z]+ (?:is|was) (?:chosen|picked|selected) at random\b"#, text), !has(#"\bgiven\b"#, text),
                  let asked = groups(#"\bprobability (?:that )?(?:this|the|they|he|she) (?:[a-z]+ )?\#(tail)"#, in: text), let event = regions(asked[1]) {
            let n = event.reduce(0) { $0 + counts[$1] }
            expr = Expr.integer(n) / .integer(total); size = Double(n) / Double(total)
            step = Step("Out of everyone", "\(n) of the \(total) \(verbBase(asked[1])).")
        } else {
            return nil
        }
        if let two = groups(#"\b(\d+) of the \d+ [a-z]+ are (?:chosen|picked|selected)"#, in: text) { used.append(two[1]) }
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = [filled, step]
        return Found(problem: problem, used: used, size: size)
    }

    // MARK: How many there are, from the chances

    /// "A bag only contains red marbles, blue marbles and yellow marbles. The probability of
    /// picking a red marble is 2/5. There are nine yellow marbles. The probability of picking a
    /// blue marble is three times as likely as picking a yellow marble. Work out the total number
    /// of marbles in the bag." The chances can be in a table.
    private static func fromChances(_ question: Question) -> Found? {
        let text = question.text
        // The kinds there are: "only contains red marbles, blue marbles and yellow marbles", "The counters are red or white or blue or yellow".
        var colours: [String] = [], plural = ""
        if let list = groups(#"\b(?:only|there are|contains?) (?:only )?(?:contains? |has |have )?([a-z]+) ([a-z]+)((?:, [a-z]+ \2)*),? (?:and|or) ([a-z]+) \2\b"#, in: text) {
            plural = list[2].lowercased()
            colours = ([list[1]] + every(#", ([a-z]+) "#, in: list[3] + " ").map(\.[1]) + [list[4]]).map { $0.lowercased() }
        } else if let list = groups(#"\bonly ([a-z]+)((?:, [a-z]+)+),? (?:and|or) ([a-z]+) ([a-z]+)\b"#, in: text) {
            // "only red, white and blue counters"
            plural = list[4].lowercased()
            colours = ([list[1]] + every(#", ([a-z]+)"#, in: list[2]).map(\.[1]) + [list[3]]).map { $0.lowercased() }
        } else if let list = groups(#"\bthe ([a-z]+) are ([a-z]+)((?:,? or [a-z]+|, [a-z]+)+)(?:\.|$| [A-Z])"#, in: text) {
            plural = list[1].lowercased()
            colours = ([list[2]] + every(#"(?:,? or |, )([a-z]+)"#, in: list[3]).map(\.[1])).map { $0.lowercased() }
        }
        guard Set(colours).count == colours.count, colours.count >= 2,
              !colours.contains(where: { ["only", "the", "some", "and", "or", "all", "in", "a"].contains($0) }) else { return nil }
        let thing = single(plural)
        let noun = "\(NSRegularExpression.escapedPattern(for: thing))(?:e?s)?"
        let picking = #"(?:(?:taking|picking|getting|choosing|selecting|drawing) )?(?:at random )?(?:an? )?"#
        let times = #"(twice|three times|four times|five times|half|(\d+) times)"#
        let theOne = #"the \#(noun)(?: [a-z]+){0,2} (?:will be|is)"#
        func multiple(_ word: String) -> Fraction? {
            switch word.lowercased() {
            case "twice": return Fraction(2, 1)
            case "three times": return Fraction(3, 1)
            case "four times": return Fraction(4, 1)
            case "five times": return Fraction(5, 1)
            case "half": return Fraction(1, 2)
            default: return Int(word.split(separator: " ").first ?? "").map { Fraction($0, 1) }
            }
        }
        func index(_ colour: String) -> Int? { colours.firstIndex(of: colour.lowercased()) }
        let k = colours.count
        func row(_ entries: [(Int, Fraction)], _ value: Fraction) -> [Fraction] {
            var row = Array(repeating: Fraction(0, 1), count: k + 1)
            for (at, by) in entries { row[at] = row[at] + by }
            row[k] = value
            return row
        }
        var rows: [[Fraction]] = [Array(repeating: Fraction(1, 1), count: k) + [Fraction(1, 1)]]
        var used: [String] = [], told: [String] = []
        // Chances said in words.
        for found in every(#"\bprobability (?:of \#(picking)([a-z]+) \#(noun)(?: (?:from|in|out of) the [a-z]+)?|that \#(theOne) ([a-z]+)) is (\#(number))(?![\d/])"#, in: text) {
            guard let at = index(found[1].isEmpty ? found[2] : found[1]), let p = chance(found[3]) else { return nil }
            rows.append(row([(at, Fraction(1, 1))], p)); used.append(found[3]); told.append("P(\(colours[at])) = \(found[3])")
        }
        // One as likely as another, or as many.
        let likely = every(#"\bprobability of \#(picking)([a-z]+) \#(noun) is \#(times) as likely as \#(picking)([a-z]+) \#(noun)"#, in: text).map { ($0[1], $0[2], $0[3], $0[4]) }
            + every(#"\bprobability that \#(theOne) ([a-z]+) is \#(times) the probability that \#(theOne) ([a-z]+)"#, in: text).map { ($0[1], $0[2], $0[3], $0[4]) }
            + every(#"\b\#(times) as many ([a-z]+) \#(noun) as ([a-z]+) \#(noun)"#, in: text).map { ($0[3], $0[1], $0[2], $0[4]) }
        for (a, word, digits, b) in likely {
            guard let i = index(a), let j = index(b), i != j, let m = multiple(word) else { return nil }
            rows.append(row([(i, Fraction(1, 1)), (j, Fraction(0, 1) - m)], Fraction(0, 1))); if !digits.isEmpty { used.append(digits) }
            told.append("P(\(colours[i])) = \(word.lowercased()) P(\(colours[j]))")
        }
        for same in every(#"\bthe number of ([a-z]+) \#(noun)(?: in the [a-z]+)? is (?:the same as|equal to) the number of ([a-z]+) \#(noun)"#, in: text) {
            guard let i = index(same[1]), let j = index(same[2]), i != j else { return nil }
            rows.append(row([(i, Fraction(1, 1)), (j, Fraction(-1, 1))], Fraction(0, 1))); told.append("P(\(colours[i])) = P(\(colours[j]))")
        }
        // A ratio of two of them: "number of blue discs : number of white discs = 3 : 5", "The ratio of red counters to white counters is 2 : 1".
        let ratios = every(#"\bnumber of ([a-z]+) \#(noun) ?: ?(?:the )?number of ([a-z]+) \#(noun) ?= ?(\d+) ?: ?(\d+)\b"#, in: text)
            + every(#"\bratio of (?:the number of )?([a-z]+) \#(noun) to (?:the number of )?([a-z]+) \#(noun) is (\d+) ?: ?(\d+)\b"#, in: text)
        for ratio in ratios {
            guard let i = index(ratio[1]), let j = index(ratio[2]), i != j, let a = Int(ratio[3]), let b = Int(ratio[4]), a > 0, b > 0 else { return nil }
            rows.append(row([(i, Fraction(b, 1)), (j, Fraction(-a, 1))], Fraction(0, 1))); used += [ratio[3], ratio[4]]
            told.append("\(colours[i]) : \(colours[j]) = \(a) : \(b)")
        }
        // Chances in a table: colours, then "Probability" and its values. Which value is which
        // colour: all of them in the table's order, or the colours the sentence names in its order.
        var readings: [[(Int, String)]] = [[]]
        if let start = question.lines.firstIndex(where: { has(#"\btable shows (?:each of )?the probabilit"#, $0) }) {
            var labels: [Int] = [], values: [String] = [], inValues = false
            for line in question.lines[(start + 1)...] {
                if has(#"^probability$"#, line) { inValues = true; continue }
                if let at = index(line), !inValues { labels.append(at); continue }
                if inValues, line.range(of: #"^\d*\.?\d+(?:/\d+)?$"#, options: .regularExpression) != nil { values.append(line); continue }
                if has(#"^colou?r$"#, line) { continue }
                break
            }
            let named = every(#"\b(?:of \#(picking)([a-z]+) \#(noun)|will be ([a-z]+))\b"#, in: question.lines[start]).compactMap { index($0[1].isEmpty ? $0[2] : $0[1]) }
            if values.isEmpty {
            } else if values.count == colours.count, labels.count == colours.count {
                readings = [Array(zip(labels, values))]
            } else if values.count == named.count, Set(named).count == named.count {
                // Named in the sentence: in its order first, and any other order to check that
                // only one way of reading them gives whole numbers.
                readings = permutations(named).map { Array(zip($0, values)) }
            } else {
                return nil
            }
            used += values
        }
        // How many of one of them, or how many in all; and what's asked: a count or a chance.
        let stated = every(#"\b(?:there (?:are|is)|(?:the [a-z]+ )?contains) (\#(amount)) ([a-z]+) \#(noun)\b"#, in: text)
        let allStated = every(#"\bthere are (\d+) \#(noun)\b"#, in: text)
        guard stated.count <= 1, allStated.count <= 1, stated.count + allStated.count <= 1 else { return nil }
        var have: Int?, at: Int?
        if let one = stated.first {
            guard let size = count(one[1]), size > 0, let which = index(one[2]) else { return nil }
            have = size; at = which
            if one[1].first?.isNumber == true { used.append(one[1]) }
        }
        let everything = allStated.first.flatMap { Int($0[1]) }
        if let everything { used.append(String(everything)) }
        var wanted: [Int] = [], wantsTotal = false, wantsChance = false
        if let asked = groups(#"\b(?:work out|find|calculate|write down) the (total )?number of (?:([a-z]+) )?\#(noun)\b"#, in: text) {
            wantsTotal = !asked[1].isEmpty || asked[2].isEmpty
            if !wantsTotal { guard let which = index(asked[2]) else { return nil }; wanted = [which] }
            guard have != nil || (everything != nil && !wantsTotal) else { return nil }
        } else if let asked = groups(#"\bprobability (?:that )?(?:the \#(noun) (?:is|will be)|[A-Z][a-z]+ (?:takes|picks|gets|chooses|selects)) (?:an? )?(?:either )?([a-z]+)(?: \#(noun))?(?: or (?:an? )?([a-z]+)(?: \#(noun))?)?(?:\.|\?|$)"#, in: text) {
            guard let first = index(asked[1]) else { return nil }
            wanted = [first]
            if !asked[2].isEmpty { guard let second = index(asked[2]), second != first else { return nil }; wanted.append(second) }
            wantsChance = true
        } else {
            return nil
        }
        var results: [(found: Found, value: Fraction)] = []
        for reading in readings {
            var all = rows, saying = told
            for (colour, value) in reading {
                guard let p = chance(value) else { return nil }
                all.append(row([(colour, Fraction(1, 1))], p)); saying.append("P(\(colours[colour])) = \(value)")
            }
            guard let chances = solveLinear(all, unknowns: k) else { continue }
            guard chances.allSatisfy({ $0.map { $0.numerator >= 0 } ?? true }) else { continue }
            var whole: Fraction?, lead: [Step] = []
            if let have, let at {
                guard let p = chances[at], !p.isZero else { continue }
                whole = Fraction(have, 1) / p
                lead.append(Step("Find the chance of \(colours[at])", "The chances of \(colours.joined(separator: ", ")) add up to 1. " + saying.joined(separator: ", ") + ".",
                                 [MathLine(.symbol("P(\(colours[at]))"), p.expr)]))
                lead.append(Step("Find how many in all", "\(have) \(colours[at]) \(plural) are \(p.numerator)/\(p.denominator) of them all, so there are \(have) ÷ \(p.numerator)/\(p.denominator) = \(whole!.numerator)."))
                if let everything { guard whole == Fraction(everything, 1) else { continue } }
            } else if let everything {
                whole = Fraction(everything, 1)
                lead.append(Step("The chances", "The chances of \(colours.joined(separator: ", ")) add up to 1. " + saying.joined(separator: ", ") + "."))
            } else {
                lead.append(Step("The chances", "The chances of \(colours.joined(separator: ", ")) add up to 1. " + saying.joined(separator: ", ") + "."))
            }
            if let whole {
                // Every count that's fixed has to come out whole, or it was misread.
                guard whole.denominator == 1, chances.allSatisfy({ $0.map { (whole * $0).denominator == 1 } ?? true }) else { continue }
            }
            var expr: Expr, value: Fraction
            if wantsTotal, let have, let at, let p = chances[at], let whole {
                expr = Expr.integer(have) / p.expr; value = whole
            } else if wantsChance {
                let parts = wanted.compactMap { chances[$0] }
                guard parts.count == wanted.count else { continue }
                value = parts.dropFirst().reduce(parts[0], +)
                // Given as decimals, answered as one.
                expr = used.contains(where: { $0.contains(".") }) ? (Parser.expression(decimal(value)) ?? value.expr) : value.expr
                lead.append(Step("Find the chance asked for", wanted.map { "P(\(colours[$0])) = \(chances[$0]!.numerator)/\(chances[$0]!.denominator)" }.joined(separator: ", ") + (wanted.count > 1 ? ". Add them: it's one or the other." : ".")))
            } else if let which = wanted.first, let q = chances[which], let whole {
                expr = .integer(whole.numerator) * q.expr; value = whole * q
                lead.append(Step("Find how many are \(colours[which])", "P(\(colours[which])) = \(q.numerator)/\(q.denominator) of the \(whole.numerator)."))
            } else {
                continue
            }
            var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
            problem.lead = lead
            results.append((Found(problem: problem, used: used, size: value.double), value))
        }
        guard let first = results.first, results.allSatisfy({ $0.value == first.value }) else { return nil }
        return first.found
    }

    private static func permutations(_ items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[Int]] in
            var rest = items; let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    // MARK: A table of counts with a letter in it

    /// "The table shows information about some CDs. [Rock 2, Pop x, Jazz 2x + 5] A CD is chosen at
    /// random. The probability it is rock is 1/20. Work out the probability it is jazz."
    private static func letterTable(_ question: Question) -> Found? {
        let text = question.text
        guard let start = question.lines.firstIndex(where: { has(#"\btable shows\b"#, $0) }),
              let given = groups(#"\bprobability (?:that )?it is (?:an? )?([a-z]+) is (\#(number))(?![\d/])"#, in: text), let p = chance(given[2]), p.numerator > 0,
              let asked = groups(#"\b(?:work out|find|calculate|write down) the probability (?:that )?it is (?:an? )?([a-z]+)\b"#, in: text) else { return nil }
        // Labels, then "Number of …", then a count for each: a number, a letter, or a letter's multiple plus or minus a number.
        var labels: [String] = [], counts: [(a: Int, b: Int, shown: String)] = [], letter: String?, inCounts = false
        for line in question.lines[(start + 1)...] {
            let plain = line.replacingOccurrences(of: " ", with: "")
            if has(#"^(?:type|kind|colou?r)$"#, line) { continue }
            if has(#"^number of\b"#, line) { inCounts = true; continue }
            if !inCounts {
                guard line.range(of: #"^[A-Za-z][a-z]+$"#, options: .regularExpression) != nil else { break }
                labels.append(line.lowercased()); continue
            }
            guard let term = groups(#"^(?:(\d*)([a-z]))?(?:([+-]?)(\d+))?$"#, in: plain), !plain.isEmpty else { break }
            if !term[2].isEmpty {
                if let letter, letter != term[2] { return nil }
                letter = term[2]
            }
            let a = term[2].isEmpty ? 0 : (Int(term[1]) ?? 1)
            let b = term[4].isEmpty ? 0 : (term[3] == "-" ? -1 : 1) * Int(term[4])!
            if !term[2].isEmpty, term[3].isEmpty, !term[4].isEmpty { return nil }
            counts.append((a, b, line))
            if counts.count == labels.count { break }
        }
        guard let letter, labels.count >= 2, counts.count == labels.count, Set(labels).count == labels.count,
              let at = labels.firstIndex(of: given[1].lowercased()), let wanted = labels.firstIndex(of: asked[1].lowercased()) else { return nil }
        // count / total = p, with total the sum of every count: one equation in the letter.
        let A = counts.reduce(0) { $0 + $1.a }, B = counts.reduce(0) { $0 + $1.b }
        let slope = Fraction(counts[at].a, 1) - p * Fraction(A, 1), constant = p * Fraction(B, 1) - Fraction(counts[at].b, 1)
        guard !slope.isZero else { return nil }
        let x = constant / slope
        guard x.denominator == 1, x.numerator > 0, counts.allSatisfy({ $0.a * x.numerator + $0.b > 0 }) else { return nil }
        let value = { (c: (a: Int, b: Int, shown: String)) in c.a * x.numerator + c.b }
        let total = A * x.numerator + B
        var used = [given[2]]
        for count in counts { used += every(#"(?<![\w.])\d+(?![\w])"#, in: count.shown).map(\.[0]) }
        let lead = [Step("Find \(letter)", "There are \(counts.map(\.shown).joined(separator: " + ")) in all. \(labels[at].capitalized) is \(counts[at].shown) of them, and that's \(given[2]) of them all, so \(letter) = \(x.numerator)."),
                    Step("Find the chance of \(labels[wanted])", "\(value(counts[wanted])) of the \(total) are \(labels[wanted]).")]
        var problem = Problem(kind: .evaluate(Expr.integer(value(counts[wanted])) / .integer(total)), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: Double(value(counts[wanted])) / Double(total))
    }

    // MARK: Two unknown counts, from two chances

    /// "There are only r red counters and g green counters in a bag. … The probability that the
    /// counter is green is 3/7. … 2 more red counters and 3 more green counters are put in the
    /// bag. … The probability that the counter is green is 6/13. Find the number of red counters
    /// and the number of green counters that were in the bag originally."
    private static func twoUnknowns(_ question: Question) -> Found? {
        let text = question.text
        guard let pair = groups(#"\b([a-z]) ([a-z]+) ([a-z]+) and ([a-z]) ([a-z]+) \3\b"#, in: text) else { return nil }
        let letters = [pair[1], pair[4]], colours = [pair[2].lowercased(), pair[5].lowercased()]
        guard letters[0] != letters[1], !letters.contains(where: { ["a", "i"].contains($0.lowercased()) }), colours[0] != colours[1],
              !has(#"\bnot (?:put back|replaced|returned)\b"#, text) else { return nil }
        let noun = "\(NSRegularExpression.escapedPattern(for: single(pair[3])))(?:e?s)?"
        guard has(#"\bfind the number of [a-z]+ \#(noun)[^.]*? and the number of [a-z]+ \#(noun)|\b(?:work out|find) the values? of [a-z] and [a-z]\b"#, text) else { return nil }
        // In the order they're said: the chances, and the counters put in or taken out between them.
        var events: [(at: Int, change: [Int]?, colour: Int?, p: String)] = []
        func position(_ pattern: String, _ each: ([String], Int) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                each((0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }, match.range.location)
            }
        }
        var used: [String] = [], bad = false
        position(#"\bprobability (?:that )?(?:the \#(noun) (?:is|will be) |of (?:(?:taking|picking|getting) )?(?:an? )?)([a-z]+)(?: \#(noun))? is (\#(number))(?![\d/])"#) { found, at in
            guard let which = colours.firstIndex(of: found[1].lowercased()) else { bad = true; return }
            events.append((at, nil, which, found[2])); used.append(found[2])
        }
        for (pattern, sign) in [(#"\b(\#(amount)) more ([a-z]+) \#(noun)(?: and (\#(amount)) more ([a-z]+) \#(noun))? (?:are|is) (?:put|added|placed)\b"#, 1),
                                (#"\b(\#(amount)) ([a-z]+) \#(noun)(?: and (\#(amount)) ([a-z]+) \#(noun))? (?:are|is) (?:taken out|removed)\b"#, -1)] {
            position(pattern) { found, at in
                var change = [0, 0]
                for (amount, colour) in [(found[1], found[2]), (found[3], found[4])] where !amount.isEmpty {
                    guard let size = count(amount), let which = colours.firstIndex(of: colour.lowercased()) else { bad = true; return }
                    change[which] += sign * size
                    if amount.first?.isNumber == true { used.append(amount) }
                }
                events.append((at, change, nil, ""))
            }
        }
        guard !bad else { return nil }
        events.sort { $0.at < $1.at }
        var change = [0, 0], rows: [[Fraction]] = [], said: [(colour: Int, p: Fraction, change: [Int])] = []
        for event in events {
            if let step = event.change { change = [change[0] + step[0], change[1] + step[1]]; continue }
            guard let which = event.colour, let p = chance(event.p), p.numerator > 0 else { return nil }
            // (letter + change) × bottom = top × (both + changes)
            var row = [Fraction(0, 1) - Fraction(p.numerator, 1), Fraction(0, 1) - Fraction(p.numerator, 1)]
            row[which] = row[which] + Fraction(p.denominator, 1)
            row.append(Fraction(p.numerator * (change[0] + change[1]) - p.denominator * change[which], 1))
            rows.append(row); said.append((which, p, change))
        }
        guard rows.count == 2, let solved = solveLinear(rows, unknowns: 2), let a = solved[0], let b = solved[1],
              a.denominator == 1, b.denominator == 1, a.numerator > 0, b.numerator > 0 else { return nil }
        let x = Expr.symbol(letters[0]), y = Expr.symbol(letters[1])
        func with(_ e: Expr, _ n: Int) -> Expr { n == 0 ? e : (n > 0 ? e + .integer(n) : e - .integer(-n)) }
        let equations = said.map { s in MathLine(with([x, y][s.colour], s.change[s.colour]) / with(x + y, s.change[0] + s.change[1]), s.p.expr) }
        let lead = [Step("Write each chance with the letters", "The chance of \(colours[said[0].colour]) is how many \(colours[said[0].colour]) there are out of how many in all, before and after the change.", equations),
                    Step("Solve them together", "Multiply out each one to clear the fractions, then solve the two equations.")]
        // Solved as simultaneous equations, with the fractions cleared.
        let cleared = said.map { s in Equation(left: .integer(s.p.denominator) * with([x, y][s.colour], s.change[s.colour]), right: .integer(s.p.numerator) * with(x + y, s.change[0] + s.change[1])) }
        var problem = Problem(kind: .solve(cleared, unknowns: letters), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: nil)
    }

    // MARK: How many ways

    /// "There are three dials on a combination lock. Each dial can be set to one of the numbers
    /// 1, 2, 3, 4, 5 … Work out the number of different three digit numbers that can be set",
    /// and "How many of the possible three digit numbers have three different digits?"
    private static func arrangements(_ question: Question) -> Found? {
        let text = question.text
        guard let things = groups(#"\bthere are (two|three|four|five|six|\d) ([a-z]+)\b"#, in: text), let k = count(things[1]), k >= 2,
              let options = groups(#"\beach \#(NSRegularExpression.escapedPattern(for: single(things[2]))) can be (?:set|turned) to one of the (?:numbers|digits) (\d(?:, \d)+(?:,? (?:and|or) \d)?|\d to \d)\b"#, in: text) else { return nil }
        var used: [String] = [], n: Int
        if let range = groups(#"^(\d) to (\d)$"#, in: options[1]), let low = Int(range[1]), let high = Int(range[2]), high > low {
            n = high - low + 1; used += [range[1], range[2]]
        } else {
            let items = every(#"\d"#, in: options[1]).map(\.[0])
            guard Set(items).count == items.count else { return nil }
            n = items.count; used += items
        }
        let size = #"(two|three|four|five|six|\d)[ -]digit"#
        // An example given of one way it can be set.
        if let example = groups(#"\bthe \#(size) number (\d+) is one\b"#, in: text) {
            guard count(example[1]) == k, example[2].count == k else { return nil }
            used.append(example[2])
        }
        var expr: Expr, value: Int, how: String
        if let asked = groups(#"\bhow many of the possible \#(size) numbers (?:have|use) (?:\w+ )?different digits\b"#, in: text) {
            guard count(asked[1]) == k, n >= k else { return nil }
            let factors = (0..<k).map { n - $0 }
            expr = .multiply(factors.map { .integer($0) }); value = factors.reduce(1, *)
            how = "The first can be any of \(n), the next any of the \(n - 1) left, and so on: no digit used twice."
        } else if let asked = groups(#"\b(?:work out|find|write down) the number of (?:different |possible )+\#(size) numbers\b"#, in: text) {
            guard count(asked[1]) == k else { return nil }
            expr = .multiply(Array(repeating: .integer(n), count: k)); value = Int(pow(Double(n), Double(k)))
            how = "Each of the \(k) \(things[2].lowercased()) can be set \(n) ways, whatever the others are set to."
        } else {
            return nil
        }
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = [Step("Multiply the choices", how)]
        return Found(problem: problem, used: used, size: Double(value))
    }

    // MARK: One taken from a bag

    /// "A bag contains 5 red counters and 3 blue counters. A counter is taken at random. Work out
    /// the probability that the counter is blue." Also "is not blue", "is red or blue", and one
    /// person chosen from "12 boys and 18 girls".
    private static func onePick(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bfrom each\b|\breplace|\banother\b|\bsecond\b|\bboth\b|\btwice\b|\bagain\b|\bthen\b|\b(?:two|three|2|3) (?:of the )?[a-z]+ (?:are|is) (?:taken|chosen|picked)\b|\b(?:takes|picks|chooses) (?:two|three|2|3)\b|\bprobability [^.?]* is \d"#, text) else { return nil }
        var items: [(colour: String, count: Int)] = [], used: [String] = []
        if let people = groups(#"\bthere are (\d+) ([a-z]+) and (\d+) ([a-z]+) in (?:a|the|an) [a-z]+(?: [a-z]+)?\."#, in: text), let a = Int(people[1]), let b = Int(people[3]), people[2].lowercased() != people[4].lowercased() {
            items = [(people[2].lowercased(), a), (people[4].lowercased(), b)]; used = [people[1], people[3]]
        } else if let bag = contents(text) {
            items = bag.items; used = bag.used
        } else if let some = groups(#"\b(?:contains?|there are|has) (\d+) ([a-z]+)\b[^.]*\. (\d+) (?:of the [a-z]+ )?(?:are|is) ([a-z]+)\."#, in: text), let all = Int(some[1]), let part = Int(some[3]), part <= all,
                  every(#"\b\d+ (?:of the [a-z]+ )?(?:are|is) [a-z]+\b"#, in: text).count == 1 {
            // "A box contains 20 pens. 8 of the pens are black.": that kind, and the rest.
            items = [(some[4].lowercased(), part), ("not " + some[4].lowercased(), all - part)]; used = [some[1], some[3]]
        } else {
            return nil
        }
        let total = items.reduce(0) { $0 + $1.count }
        guard total >= 2, items.allSatisfy({ $0.count >= 0 }),
              has(#"\b(?:an?|one) (?:of the )?[a-z]+ is (?:taken|picked|chosen|selected|drawn|removed)(?: out)?(?: of the [a-z]+| from the [a-z]+)? at random\b|\b(?:takes|picks|chooses|selects|draws) (?:at random )?(?:an?|one) (?:of the )?[a-z]+\b"#, text) else { return nil }
        func index(_ word: String) -> Int? { items.firstIndex { single($0.colour) == single(word) } }
        // "the counter is blue", "the counter is not blue", "the counter is red or blue", "taking a blue counter", "the student is a girl".
        guard let asked = groups(#"probability (?:that )?(?:the|this) [a-z]+ (?:is|will be) (not )?(?:an? )?([a-z]+)(?: or (?:an? )?([a-z]+))?(?: [a-z]+)?(?:\.|\?|$)|probability (?:of (?:taking|picking|getting|choosing|selecting) |that (?:[A-Z][a-z]+|he|she|they) (?:takes|picks|gets|chooses|selects) )(?:an? )?([a-z]+) [a-z]+(?:\.|\?|$)"#, in: text) else { return nil }
        var wanted: [Int] = []
        for word in [asked[2], asked[3], asked[4]] where !word.isEmpty {
            guard let at = index(word), !wanted.contains(at) else { return nil }
            wanted.append(at)
        }
        // ("Not red or blue" could be read two ways.)
        guard !wanted.isEmpty, asked[1].isEmpty || wanted.count == 1 else { return nil }
        let isNot = !asked[1].isEmpty
        let some = wanted.reduce(0) { $0 + items[$1].count }, hits = isNot ? total - some : some
        let names = wanted.map { items[$0].colour }.joined(separator: " or ")
        var problem = Problem(kind: .evaluate(Expr.integer(hits) / .integer(total)), text: "", usesDecimals: false)
        problem.lead = [Step("Count them all", items.map { "\($0.count) \($0.colour)" }.joined(separator: ", ") + ": \(total) in all, each as likely to be taken as any other."),
                        Step("Count the ones asked for", isNot ? "\(some) are \(names), so \(total) − \(some) = \(hits) are not." : "\(hits) \(hits == 1 ? "is" : "are") \(names).")]
        return Found(problem: problem, used: used, size: Double(hits) / Double(total))
    }

    // MARK: The chance it doesn't happen, and the one chance not given

    /// "The probability that a train is late is 0.15. Work out the probability that the train is
    /// not late." Also "A spinner can land on red, blue or green. The probability that it lands on
    /// red is 0.5. The probability that it lands on blue is 0.2. Work out the probability that it
    /// lands on green."
    private static func remaining(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bif\b|\bgiven\b|\bthen\b|\btwice\b|\bboth\b|\btimes\b|\beach\b|\bindependent\b"#, text) else { return nil }
        let stated = every(#"\bprobability (?:that |of )([^.?]+?) is (\d*\.\d+|\d+/\d+)(?=[\s.,]|$)"#, in: text)
        guard !stated.isEmpty, stated.count <= 5,
              let asked = groups(#"\b(?:work out|find|calculate|write down|what is) the probability (?:that |of )([^.?]+?)(?:\.|\?|$)"#, in: text)?[1].lowercased() else { return nil }
        let filler: Set<String> = ["a", "an", "the", "it", "will", "be", "is", "does", "do", "that", "this", "he", "she", "they"]
        func words(_ phrase: String) -> [String] {
            phrase.lowercased().replacingOccurrences(of: "n't", with: " not").split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !filler.contains($0) }.map { verbBase($0) }
        }
        let chances = stated.compactMap { chance($0[2]) }
        guard chances.count == stated.count else { return nil }
        let like = stated[0][2]
        let sum = chances.reduce(Fraction(0, 1), +)
        let left = Fraction(1, 1) - sum
        guard left.numerator > 0 else { return nil }
        let wanted = words(asked)
        if stated.count == 1 {
            // The same thing with "not" in it, or without the "not" it had.
            let said = words(stated[0][1])
            let (plainSaid, plainWanted) = (said.filter { $0 != "not" }, wanted.filter { $0 != "not" })
            guard plainSaid == plainWanted, !plainSaid.isEmpty, said.contains("not") != wanted.contains("not") else { return nil }
            var problem = Problem(kind: .evaluate(Expr.one - written(like, chances[0])), text: "", usesDecimals: like.contains("."))
            problem.lead = [Step("Take it from 1", "It happens or it doesn't, so the two chances add up to 1.")]
            return Found(problem: problem, used: [like], size: left.double)
        }
        // Everything it can be, listed: each but one has its chance given, and that one is asked for.
        guard let list = groups(#"\b(?:can (?:only )?(?:land on|be|show)|(?:is|are) either|(?:is|are)|lands on) ((?:[a-z0-9]+, )+[a-z0-9]+,? or [a-z0-9]+)\b"#, in: text) else { return nil }
        let outcomes = list[1].lowercased().replacingOccurrences(of: #",? or |, "#, with: "\u{1}", options: .regularExpression).components(separatedBy: "\u{1}")
        guard outcomes.count == stated.count + 1, Set(outcomes).count == outcomes.count else { return nil }
        func named(_ phrase: String) -> [String] { outcomes.filter { has("\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", phrase) } }
        var given: [String] = []
        for one in stated {
            let which = named(one[1])
            guard which.count == 1, !given.contains(which[0]), !has(#"\bnot\b|\bn't\b|\bor\b"#, one[1]) else { return nil }
            given.append(which[0])
        }
        let missing = outcomes.filter { !given.contains($0) }
        guard missing.count == 1, named(asked) == missing, !has(#"\bnot\b|\bn't\b|\bor\b"#, asked) else { return nil }
        let parts = stated.map { written($0[2], chance($0[2])!) }
        var problem = Problem(kind: .evaluate(Expr.one - (parts.count == 1 ? parts[0] : .add(parts))), text: "", usesDecimals: like.contains("."))
        problem.lead = [Step("Use what they add up to", "It has to be one of \(outcomes.joined(separator: ", ")), so their chances add up to 1. Take the others from 1.")]
        var used = stated.map { $0[2] }
        used += outcomes.filter { $0.first?.isNumber == true }
        return Found(problem: problem, used: used, size: left.double)
    }

    // MARK: How many to expect

    /// "The probability that a seed grows is 0.85. 200 seeds are planted. Work out an estimate for
    /// the number of seeds that grow." Also "A fair dice is rolled 300 times. How many times would
    /// you expect it to land on a six?", and how many of one colour from its chance and how many there are.
    private static func howMany(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bif\b|\bgiven\b|\bthen\b|\bboth\b|\brelative frequenc"#, text),
              let ask = groups(#"\b(?:how many|(?:work out|find|calculate|write down)(?: an estimate (?:for|of))? the (?:expected )?number of)\b([^.?]*)"#, in: text)?[1].lowercased() else { return nil }
        // A fair dice or coin: its chance isn't given, it's known.
        if has(#"\bfair\b|\bordinary\b"#, text), let times = groups(#"\b(?:is|are) (?:rolled|thrown|tossed|flipped|spun) (\d+) times\b|\b(?:rolls|throws|tosses|flips|spins) (?:the|an?) (?:fair |ordinary )*(?:six-sided )?(?:dice|coin) (\d+) times\b"#, in: text),
           let n = Int(times[1].isEmpty ? times[2] : times[1]), has(#"\bexpect"#, ask) || has(#"\bexpect"#, text) {
            var p: Fraction?, what = ""
            if has(#"\bfair (?:six-sided |ordinary )?dice\b|\bordinary (?:fair )?(?:six-sided )?dice\b"#, text), !has(#"\bcoin\b|\bspinner\b|\btwo\b|\bbiased\b"#, text) {
                guard let target = groups(#"\b(?:land on|lands on|landing on|show|shows|get|gets|getting|score|scores|roll|rolls|rolling|throw|throws|throwing) (?:an? )?(?:(six|6)|(even|odd|prime|square) number|number (greater|more|less) than (\d)|multiple of (\d))\b"#, in: ask) else { return nil }
                let faces = (1...6).filter { face in
                    if !target[1].isEmpty { return face == 6 }
                    if !target[2].isEmpty { return ["even": face % 2 == 0, "odd": face % 2 == 1, "prime": [2, 3, 5].contains(face), "square": [1, 4].contains(face)][target[2]] ?? false }
                    if !target[3].isEmpty, let limit = Int(target[4]) { return target[3] == "less" ? face < limit : face > limit }
                    if let m = Int(target[5]), m > 0 { return face % m == 0 }
                    return false
                }
                guard !faces.isEmpty, faces.count < 6 else { return nil }
                p = Fraction(faces.count, 6); what = "\(faces.count) of the 6 faces (\(faces.map(String.init).joined(separator: ", ")))"
                var used = [String(n)] + [target[4], target[5]].filter { !$0.isEmpty } + (target[1] == "6" ? ["6"] : [])
                if text.range(of: #"\b6-sided"#, options: .regularExpression) != nil { used.append("6") }
                var problem = Problem(kind: .evaluate(p!.expr * .integer(n)), text: "", usesDecimals: false)
                problem.lead = [Step("The chance each time", "A fair dice: \(what), so \(faces.count)/6."), Step("Times the number of goes", "The expected number is the chance times how many times it's done.")]
                return Found(problem: problem, used: used, size: p!.double * Double(n))
            }
            if has(#"\bfair coin\b"#, text), !has(#"\bdice\b|\bspinner\b|\btwo\b|\bbiased\b"#, text), has(#"\b(?:heads?|tails?)\b"#, ask), !has(#"\bnot\b|\bor\b|\band\b"#, ask) {
                var problem = Problem(kind: .evaluate(Expr.one / .two * .integer(n)), text: "", usesDecimals: false)
                problem.lead = [Step("The chance each time", "A fair coin lands on heads or tails with the same chance, 1/2."), Step("Times the number of goes", "The expected number is the chance times how many times it's done.")]
                return Found(problem: problem, used: [String(n)], size: Double(n) / 2)
            }
            return nil
        }
        // One chance given, and one number of things it's the chance for.
        let stated = every(#"\bprobability (?:that |of )([^.?]+?) is (\d*\.\d+|\d+/\d+|\d+(?:\.\d+)?%)(?=[\s.,]|$)"#, in: text)
        guard stated.count == 1, let p = chance(stated[0][2]), p.numerator > 0 else { return nil }
        let subject = stated[0][1].lowercased()
        let sizes = numbers(in: text).filter { $0 != stated[0][2] }
        guard sizes.count == 1, let n = Int(sizes[0]), n > 0 else { return nil }
        // What's counted has to be what the chance is of: every word of the question that says so is in the sentence that gave it.
        let filler: Set<String> = ["a", "an", "the", "of", "to", "in", "that", "will", "would", "should", "does", "do", "did", "you", "she", "he", "they", "expect", "expected", "are", "is", "be", "there", "these", "this", "them", "it",
                                   "times", "many", "how", "number", "estimate", "for", "bag", "box", "on", "at", "all", "altogether"]
        func stems(_ phrase: String) -> [String] { phrase.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { !filler.contains($0) }.map { single(verbBase($0)) } }
        let about = stems(ask), said = Set(stems(subject) + stems(subject).map { $0.hasSuffix("e") ? String($0.dropLast()) : $0 })
        guard !about.isEmpty, !has(#"\bnot\b|\bn't\b|\bor\b"#, ask), !has(#"\bnot\b|\bn't\b|\bor\b"#, subject),
              about.allSatisfy({ said.contains($0) || said.contains($0.hasSuffix("e") ? String($0.dropLast()) : $0) }) else { return nil }
        // And the number is how many of them there are, or how many times it's done.
        let noun = about.first { word in has("\\b\(n) (?:[a-z]+ )?\(NSRegularExpression.escapedPattern(for: word))", text) }
        guard noun != nil || has("\\b\(n) (?:times|goes|games|turns)\\b", text) else { return nil }
        let value = p * Fraction(n, 1)
        guard value.denominator == 1 else { return nil }
        var problem = Problem(kind: .evaluate(shown(p, like: stated[0][2]) * .integer(n)), text: "", usesDecimals: stated[0][2].contains("."))
        problem.lead = [Step("Take that share of them", "The chance is \(stated[0][2]), so about that share of the \(n) is expected.")]
        return Found(problem: problem, used: [stated[0][2], sizes[0]], size: value.double)
    }

    // MARK: The same thing tried again and again

    /// "The probability that Ann wins a game is 0.4. She plays the game twice. Work out the
    /// probability that she wins both games." Also three times, "exactly twice", "at least one of
    /// three days", "none".
    private static func again(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bif\b|\bgiven\b|\bwithout replacement\b|\bnot replaced\b|\bdepends\b"#, text) else { return nil }
        let stated = every(#"\bprobability (?:that |of )([^.?]+?) is (\d*\.\d+|\d+/\d+)(?=[\s.,]|$)"#, in: text)
        guard stated.count == 1, let p = chance(stated[0][2]), p.numerator > 0, p.numerator < p.denominator,
              let asked = groups(#"\b(?:work out|find|calculate|write down|what is) the probability (?:that |of )([^.?]+?)(?:\.|\?|$)"#, in: text)?[1].lowercased() else { return nil }
        let subject = stated[0][1].lowercased()
        // How many times it's tried: "twice", "three times", "both games", "one of three days".
        let amounts = ["twice": 2, "two": 2, "2": 2, "three": 3, "3": 3, "four": 4, "4": 4, "both": 2]
        var tries: Set<Int> = [], used = [stated[0][2]]
        // (Said before the question; failing that, in it: "exactly twice" there is how often it happens, not how often it's tried.)
        var setup = text.replacingOccurrences(of: stated[0][0], with: "")
        if let start = setup.range(of: #"\b(?:work out|find|calculate|write down|what is) the probability\b"#, options: [.regularExpression, .caseInsensitive]) {
            let before = String(setup[..<start.lowerBound])
            setup = has(#"\b(?:twice|(?:two|three|four|\d) times)\b"#, before) ? before : before + " " + asked.replacingOccurrences(of: #"\b(?:exactly|only|just|at least|at most) (?:once|one|twice|two|three)\b(?! of)"#, with: "", options: .regularExpression)
        }
        for found in every(#"\b(?:(twice)|(two|three|four|\d) (?:times|games|days|goes|turns|throws|spins|matches|shots|attempts|penalties|[a-z]+s)|(both) [a-z]+s)\b"#, in: setup) {
            let word = [found[1], found[2], found[3]].first { !$0.isEmpty }!.lowercased()
            guard let n = amounts[word] else { return nil }
            tries.insert(n)
            if word.first?.isNumber == true { used.append(word) }
        }
        guard tries.count == 1, let n = tries.first else { return nil }
        // What's asked is the same thing happening, some number of times.
        let filler: Set<String> = ["a", "an", "the", "it", "will", "be", "is", "on", "any", "each", "every", "day", "of", "to", "that", "these", "this", "in", "all", "both", "two", "three", "four", "times", "twice", "once", "exactly",
                                   "at", "least", "most", "one", "none", "neither", "only", "just", "she", "he", "they", "her", "his", "their", "next", "does", "do", "not", "game", "time", "throw", "spin", "go", "turn"]
        func stems(_ phrase: String) -> Set<String> { Set(phrase.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { !filler.contains($0) && !filler.contains(single($0)) }.map { single(verbBase($0)) }) }
        let said = stems(subject), wanted = stems(asked)
        guard !said.isEmpty, !wanted.isEmpty, wanted.isSubset(of: said), !has(#"\bor\b"#, asked), !has(#"\bnot\b|\bn't\b"#, subject) else { return nil }
        let q = Fraction(1, 1) - p
        func choose(_ n: Int, _ r: Int) -> Int { (0..<r).reduce(1) { $0 * (n - $1) / ($1 + 1) } }
        func exactly(_ k: Int) -> Fraction { (0..<k).reduce(Fraction(choose(n, k), 1)) { f, _ in f * p }.times(q, n - k) }
        let like = stated[0][2]
        func term(_ k: Int) -> Expr {
            let factors = Array(repeating: shown(p, like: like), count: k) + Array(repeating: shown(q, like: like), count: n - k)
            let orders = choose(n, k)
            return orders == 1 ? (factors.count == 1 ? factors[0] : .multiply(factors)) : .multiply([.integer(orders)] + factors)
        }
        var ks: [Int], how: String
        let wordK = ["once": 1, "one": 1, "twice": 2, "two": 2, "three": 3]
        if has(#"\bat least (?:one|once)\b"#, asked) { ks = Array(1...n); how = "At least once is everything except never: 1 take away the chance it doesn't happen at all." }
        else if let exact = groups(#"\b(?:exactly|only|just) (once|one|twice|two|three)\b"#, in: asked), let k = wordK[exact[1]], k <= n { ks = [k]; how = "It happens \(k) time\(k == 1 ? "" : "s") and doesn't the other \(n - k): \(choose(n, k)) order\(choose(n, k) == 1 ? "" : "s") it can come in." }
        else if has(#"\b(?:none|neither|never|no )\b|\bnot\b[^.]*\b(?:any|either|at all)\b"#, asked) { ks = [0]; how = "It doesn't happen any of the \(n) times." }
        else if has(#"\b(?:both|all (?:two|three|four|\d)?|every|each of the)\b|\b(?:twice|three times|four times)\b"#, asked), !has(#"\bnot\b|\bn't\b"#, asked) { ks = [n]; how = "It happens every one of the \(n) times." }
        else { return nil }
        if let said = groups(#"\b(?:all|of|the) (two|three|four|\d) "#, in: asked), let m = amounts[said[1]] { guard m == n else { return nil } }
        let value = ks.reduce(Fraction(0, 1)) { $0 + exactly($1) }
        let expr: Expr = ks.count == 1 ? term(ks[0]) : Expr.one - term(0)
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: like.contains("."))
        problem.lead = [Step("Each time", "The chance is \(like) each time, and \(decimal(q).isEmpty ? "" : (like.contains(".") ? decimal(q) : "\(q.numerator)/\(q.denominator)")) that it doesn't happen, whatever happened before."),
                        Step("Put the \(n) together", how)]
        return Found(problem: problem, used: used, size: value.double)
    }

    // MARK: One go with something fair

    /// "A fair six-sided dice is rolled. Write down the probability that it lands on a number
    /// greater than 4." Also a letter chosen from a word ("the letter is B", "is a vowel"), fair
    /// coins ("Two fair coins are thrown … two heads"), and a fair spinner with so many of its
    /// equal sections one colour, spun once or many times ("the expected number of times it lands on red").
    private static func fairGo(_ question: Question) -> Found? {
        let text = question.text
        guard !has(#"\bbiased\b|\bif\b|\bgiven\b|\bthen\b|\breplace"#, text),
              let asked = groups(#"\b(?:work out|find|calculate|write down|what is) the (?:probability|expected number)\b([^.?]*)"#, in: text)?[1].lowercased() else { return nil }
        func found(_ expr: Expr, _ size: Double, _ used: [String], _ steps: [Step]) -> Found {
            var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
            problem.lead = steps
            return Found(problem: problem, used: used, size: size)
        }
        // A letter of a word.
        if let word = groupsExact(#"\b(?:from|of|in) the word ([A-Z]{3,})\b"#, in: text)?[1], has(#"\ba letter is (?:chosen|picked|selected|taken) at random\b|\bone of the letters\b[^.]* at random\b|\b(?:chooses|picks|takes) (?:a|one) (?:letter|of the letters)\b"#, text) {
            guard let what = groupsExact(#"probability that the letter is (not )?(?:the letter )?(?:an? )?([A-Z]|vowel|consonant)(?:\.|\?|$)"#, in: text) else { return nil }
            let vowels = Set("AEIOU")
            let hits = word.filter { what[2] == "vowel" ? vowels.contains($0) : (what[2] == "consonant" ? !vowels.contains($0) : String($0) == what[2]) }.count
            let count = what[1].isEmpty ? hits : word.count - hits
            // (A letter that isn't in the word at all is more likely misread than asked.)
            guard hits > 0 else { return nil }
            return found(.integer(count) / .integer(word.count), Double(count) / Double(word.count), [],
                         [Step("Count the letters", "\(word) has \(word.count) letters, each as likely to be chosen as any other."),
                          Step("Count the ones asked for", "\(hits) of them \(hits == 1 ? "is" : "are") \(what[2].count == 1 ? what[2] : what[2] + "s")" + (what[1].isEmpty ? "." : ", so \(count) are not."))])
        }
        // Fair coins: how many heads (or tails) out of two, three or four.
        if let coins = groups(#"\b(two|three|four|2|3|4) (?:fair )+coins are (?:thrown|tossed|flipped|spun)\b|\ba fair coin is (?:thrown|tossed|flipped|spun) (twice|three times|four times)\b"#, in: text), !has(#"\bdice\b|\bspinner\b"#, text) {
            let said = (coins[1] + coins[2]).lowercased()
            guard let n = ["two": 2, "2": 2, "twice": 2, "three": 3, "3": 3, "three times": 3, "four": 4, "4": 4, "four times": 4][said] else { return nil }
            var used = coins[1].first?.isNumber == true ? [coins[1]] : [String]()
            let counts = ["no": 0, "one": 1, "a": 1, "two": 2, "three": 3, "four": 4, "1": 1, "2": 2, "3": 3, "4": 4]
            var ks: [Int]
            if let exact = groups(#"\b(?:of (?:getting |throwing )?|that (?:[a-z ]+? )??(?:gets?|shows?|lands? on|are|is) )(exactly |at least |at most )?(no|one|a|two|three|four|\d) (head|tail)s?(?:\.|\?|$| and (no|one|a|two|three|four|\d) (head|tail)s?(?:\.|\?|$))"#, in: asked), let k = counts[exact[2]], k <= n {
                if exact[2].first?.isNumber == true { used.append(exact[2]) }
                if !exact[4].isEmpty {
                    // "two heads and one tail": the two have to be the whole of it.
                    guard let other = counts[exact[4]], exact[5] != exact[3], k + other == n, exact[1].isEmpty else { return nil }
                    if exact[4].first?.isNumber == true { used.append(exact[4]) }
                }
                switch exact[1].trimmingCharacters(in: .whitespaces) {
                case "at least": ks = Array(k...n)
                case "at most": ks = Array(0...k)
                default:
                    // "two heads" from two coins is both; from three it would be unclear whether exactly two is meant.
                    guard !exact[1].isEmpty || !exact[4].isEmpty || k == n || k == 0 else { return nil }
                    ks = [k]
                }
            } else if has(#"\b(?:both|all)\b[a-z ]*\b(?:heads|tails)\b"#, asked) { ks = [n] }
            else { return nil }
            func choose(_ n: Int, _ r: Int) -> Int { (0..<r).reduce(1) { $0 * (n - $1) / ($1 + 1) } }
            let ways = ks.reduce(0) { $0 + choose(n, $1) }, all = Int(pow(2.0, Double(n)))
            return found(.integer(ways) / .integer(all), Double(ways) / Double(all), used,
                         [Step("Every way they can land", "Each coin lands one of 2 ways, so there are \(Array(repeating: "2", count: n).joined(separator: " × ")) = \(all) ways, all as likely as each other."),
                          Step("Count the ones asked for", "\(ways) of the \(all).")])
        }
        // A fair dice, rolled once; or a fair spinner with so many of its equal sections one colour.
        var p: Fraction?, how = "", used: [String] = []
        if has(#"\ba(?:n ordinary)? fair (?:six-sided |6-sided |ordinary )?dice is (?:rolled|thrown)(?: once)?\."#, text), !has(#"\btwice\b|\btimes\b|\btwo\b|\bcoin\b|\bspinner\b|\bagain\b"#, text) {
            guard let target = groups(#"\b(?:lands? on|shows?|of getting|of rolling|of throwing|scores?|is) (?:an? )?(?:(six|6)|(even|odd|prime|square) number|number (greater|more|less) than (\d)|(multiple|factor) of (\d+))(?:\.|\?|$)"#, in: asked) else { return nil }
            let faces = (1...6).filter { face in
                if !target[1].isEmpty { return face == 6 }
                if !target[2].isEmpty { return ["even": face % 2 == 0, "odd": face % 2 == 1, "prime": [2, 3, 5].contains(face), "square": [1, 4].contains(face)][target[2]] ?? false }
                if !target[3].isEmpty, let limit = Int(target[4]) { return target[3] == "less" ? face < limit : face > limit }
                if let m = Int(target[6]), m > 0 { return target[5] == "multiple" ? face % m == 0 : m % face == 0 }
                return false
            }
            guard !faces.isEmpty, faces.count < 6 else { return nil }
            p = Fraction(faces.count, 6); how = "\(faces.count) of the 6 faces (\(faces.map(String.init).joined(separator: ", ")))"
            used = [target[4], target[6]].filter { !$0.isEmpty } + (target[1] == "6" ? ["6"] : []) + (text.range(of: #"\b6-sided"#, options: .regularExpression) != nil ? ["6"] : [])
        } else if let spinner = groups(#"\bfair spinner has (\d+|[a-z]+) equal (?:sections|parts|sectors)\. (\d+|[a-z]+) of the (?:sections|parts|sectors) (?:are|is) ([a-z]+)\."#, in: text),
                  let all = count(spinner[1]), let some = count(spinner[2]), some >= 1, some < all, !has(#"\bdice\b|\bcoin\b|\btwice\b"#, text),
                  has("\\b(?:lands? on|landing on|shows?|of getting|is) \(spinner[3].lowercased())(?:\\.|\\?|$)", asked), !has(#"\bnot\b|\bor\b"#, asked) {
            p = Fraction(some, all); how = "\(some) of the \(all) equal sections"
            used = [spinner[1], spinner[2]].filter { $0.first?.isNumber == true }
        }
        guard let p, !has(#"\bnot\b|\bor\b|\band\b"#, asked) else { return nil }
        if has(#"\bexpected number\b"#, text) {
            // Done many times: the expected number.
            guard let times = groups(#"\b(?:rolled|thrown|spun) (\d+) times\b"#, in: text), let n = Int(times[1]) else { return nil }
            return found(p.expr * .integer(n), p.double * Double(n), used + [times[1]],
                         [Step("The chance each time", "\(how.prefix(1).uppercased() + how.dropFirst()), so \(p.numerator)/\(p.denominator)."), Step("Times the number of goes", "The expected number is the chance times how many times it's done.")])
        }
        guard !has(#"\btimes\b"#, text) else { return nil }
        return found(p.expr, p.double, used, [Step("Count the ones asked for", "\(how.prefix(1).uppercased() + how.dropFirst()), each as likely as any other.")])
    }

    // MARK: Codes made of digits

    /// "Fatima is choosing a 4-digit code. Each digit is a whole number from 0 to 9. She decides
    /// all her digits will be odd numbers, no digits will be repeated. How many different codes
    /// can she make?" Also two people, one with odd digits and one with even: how many more codes.
    private static func digitCodes(_ question: Question) -> Found? {
        let text = question.text
        guard let size = groups(#"\b(\d|three|four|five|six)-digit codes?\b"#, in: text), let k = count(size[1]), k >= 2, k <= 6 else { return nil }
        var used = every(#"\b(\d)-digit codes?\b"#, in: text).map(\.[1])
        // The digits there are to use.
        var digits = Array(0...9)
        if let range = groups(#"\beach digit is a (?:whole )?number from (\d) to (\d)\b"#, in: text), let low = Int(range[1]), let high = Int(range[2]), low < high {
            digits = Array(low...high); used += [range[1], range[2]]
        }
        if let none = groups(#"\bthe digit (\d) is not used\b"#, in: text), let gone = Int(none[1]) { digits.removeAll { $0 == gone }; used.append(none[1]) }
        // Whether a digit can come twice has to be said.
        let again = has(#"\bdigits (?:may|can) be repeated\b|\bcan have repeated digits\b|\bdigits can be used more than once\b"#, text)
        let once = has(#"\bno digits? (?:will be|is|are|can be|may be) (?:repeated|used more than once)\b|\bdigits (?:cannot|can't|can not|may not) be repeated\b|\b(?:each|every) digit is different\b|\ball (?:the |\w+ )?digits are different\b"#, text)
        guard again != once else { return nil }
        // Who uses which: "all her digits will be odd numbers", "Ali only uses odd digits."
        var makers: [(name: String, kind: String)] = []
        for found in every(#"\b([A-Z][a-z]+) only uses (odd|even) digits\b"#, in: text) { makers.append((found[1], found[2].lowercased())) }
        if let all = groups(#"\ball (?:her|his|their|the) digits (?:will be|are|must be) (odd|even)(?: numbers)?\b"#, in: text) { makers.append(("", all[1].lowercased())) }
        // Anything else said about the code isn't a rule that's known.
        guard !has(#"\bstarts?\b|\bends?\b|\bbegins?\b|\b(?:first|last|second|third|middle) digit\b|\bgreater than\b|\bless than\b|\bmultiple\b|\bprime\b|\bsquare\b|\bchanged\b|\bbetween\b|\bin fact\b"#, text) else { return nil }
        func ways(_ kind: String) -> (count: Int, expr: Expr, digits: [Int])? {
            let mine = digits.filter { kind == "odd" ? $0 % 2 == 1 : (kind == "even" ? $0 % 2 == 0 : true) }
            guard mine.count >= (again ? 1 : k) else { return nil }
            let factors = (0..<k).map { again ? mine.count : mine.count - $0 }
            return (factors.reduce(1, *), .multiply(factors.map { .integer($0) }), mine)
        }
        func said(_ made: (count: Int, expr: Expr, digits: [Int])) -> String {
            "\(made.digits.count) digits to use (\(made.digits.map(String.init).joined(separator: ", "))). " + (again ? "Any of them each time." : "One fewer to choose from each time, as none comes twice.")
        }
        var problem: Problem, value: Int
        if makers.count == 2, makers[0].kind != makers[1].kind, !makers[0].name.isEmpty, !makers[1].name.isEmpty,
           let more = groupsExact(#"\b([A-Z][a-z]+) can make ([a-z]) more codes than ([A-Z][a-z]+)\b"#, in: text), has(#"\b(?:work out|find) the value of \#(more[2])\b"#, text),
           let a = makers.first(where: { $0.name == more[1] }), let b = makers.first(where: { $0.name == more[3] }), a.name != b.name,
           let first = ways(a.kind), let second = ways(b.kind), first.count > second.count {
            value = first.count - second.count
            problem = Problem(kind: .evaluate(first.expr - second.expr), text: "", usesDecimals: false)
            problem.lead = [Step("\(a.name)'s codes", said(first), [MathLine(first.expr, .integer(first.count))]),
                            Step("\(b.name)'s codes", said(second), [MathLine(second.expr, .integer(second.count))]),
                            Step("Take away", "\(more[2]) is how many more \(a.name) can make.")]
        } else if makers.count <= 1, makers.allSatisfy({ $0.name.isEmpty }), has(#"\bhow many (?:different |possible )*codes (?:can|could|are)\b"#, text), let made = ways(makers.first?.kind ?? "") {
            value = made.count
            problem = Problem(kind: .evaluate(made.expr), text: "", usesDecimals: false)
            problem.lead = [Step("Count the choices for each digit", said(made))]
        } else {
            return nil
        }
        return Found(problem: problem, used: used, size: Double(value))
    }

    // MARK: Numbers picked and put together

    /// "Ray has nine cards numbered 1 to 9. Ray takes at random three of these cards. He works out
    /// the sum of the numbers on the three cards. Work out the probability that the result is an
    /// even number." Also a spinner spun twice with the scores added or multiplied, and the
    /// difference of two cards. Every way it can come out is counted.
    private static func combined(_ question: Question) -> Found? {
        let text = question.text
        let things = #"cards|tiles|counters|balls|discs"#
        var values: [Int] = [], used: [String] = [], thing = ""
        // Lines of numbers and nothing else: the cards as they're drawn. (A number alone on a line may be
        // the question's own number, so it's never taken for a card.)
        let drawn = question.lines.filter { $0.range(of: #"^\d+(?: \d+)+$"#, options: .regularExpression) != nil }.flatMap { $0.split(separator: " ").compactMap { Int($0) } }
        if let range = groups(#"\b(\d+|[a-z]+) (?:number )?(\#(things)) numbered (?:from )?(\d+) to (\d+)\b"#, in: text), let low = Int(range[3]), let high = Int(range[4]), low < high, high - low < 30 {
            values = Array(low...high); thing = range[2].lowercased(); used += [range[3], range[4]]
            guard count(range[1]) == values.count else { return nil }
            if range[1].first?.isNumber == true { used.append(range[1]) }
        } else if let list = groups(#"\b(spinner|dice|\#(things))(?: with)?(?: [a-z]+){0,2}? numbered ((?:\d+, )*\d+,? and \d+)\b"#, in: text) {
            values = every(#"\d+"#, in: list[2]).compactMap { Int($0[0]) }; thing = list[1].lowercased(); used += values.map(String.init)
        } else if let these = groups(#"\bthese (\d+|[a-z]+) (?:number(?:ed)? )?(\#(things))\b"#, in: text), let size = count(these[1]) {
            // "Kai has these four number cards." with the numbers in a row under it.
            guard drawn.count == size else { return nil }
            values = drawn; thing = these[2].lowercased()
            if these[1].first?.isNumber == true { used.append(these[1]) }
        } else if let ordinary = groups(#"\btwo (?:ordinary |fair )+(?:(six|6)-sided )?dice\b"#, in: text) {
            // Two ordinary dice: 1 to 6 on each.
            values = Array(1...6); thing = "dice"
            if ordinary[1] == "6" { used.append("6") }
        } else {
            return nil
        }
        guard values.count >= 2, values.count <= 30 else { return nil }
        // The picture of them says the same numbers again, or isn't read at all.
        guard drawn.isEmpty || drawn.sorted() == values.sorted() else { return nil }
        used += drawn.map(String.init)
        // How many are picked, and whether one can come up again.
        var k = 0, back = false
        if let taken = groups(#"\b(?:takes|picks|chooses|selects) (?:at random )?(two|three|2|3) (?:of (?:the|these) )?(?:\#(things))\b"#, in: text), let size = count(taken[1]) {
            guard !["spinner", "dice"].contains(thing), !has(#"\breplaces\b|\bput(?:s)? (?:it|them) back\b"#, text) else { return nil }
            k = size; back = has(#"\bwith replacement\b"#, text)
            if taken[1].first?.isNumber == true { used.append(taken[1]) }
        } else if let spun = groups(#"\b(?:spins|rolls|throws) (?:the|a|this) (?:[a-z-]+ )?(?:spinner|dice) (twice|three times)\b|\b(?:spinner|dice) is (?:spun|rolled|thrown) (twice|three times)\b"#, in: text) {
            guard ["spinner", "dice"].contains(thing), has(#"\bfair\b"#, text) else { return nil }
            k = (spun[1] + spun[2]).lowercased() == "twice" ? 2 : 3; back = true
        } else if thing == "dice", has(#"\b(?:rolls|throws) two (?:ordinary |fair )+(?:[a-z0-9]+-sided )?dice\b|\btwo (?:ordinary |fair )+(?:[a-z0-9]+-sided )?dice are (?:rolled|thrown)\b"#, text) {
            // Two dice rolled together: either can show any of its numbers.
            guard !has(#"\bbiased\b"#, text) else { return nil }
            k = 2; back = true
            if let sides = groups(#"\b(\d+)-sided\b"#, in: text), sides[1] != "6" || !used.contains("6") { guard Int(sides[1]) == values.count else { return nil }; used.append(sides[1]) }
            if let sides = groups(#"\b(four|five|six|eight|ten|twelve)-sided\b"#, in: text) { guard count(sides[1]) == values.count else { return nil } }
        } else {
            return nil
        }
        guard k >= 2, back || k <= values.count else { return nil }
        // What's done with the numbers picked.
        let doing = [has(#"\badds?\b|\bsum\b|\btotal\b"#, text), has(#"\bmultipl(?:y|ies)\b|\bproduct\b"#, text), has(#"\bdifference\b"#, text)]
        guard doing.filter({ $0 }).count == 1, let which = doing.firstIndex(of: true), which < 2 || k == 2 else { return nil }
        let name = ["sum", "product", "difference"][which]
        func result(_ picked: [Int]) -> Int { which == 0 ? picked.reduce(0, +) : (which == 1 ? picked.reduce(1, *) : abs(picked[0] - picked[1])) }
        // What's asked of the result: "is an even number or a factor of 10", "gets an even total", "a difference of 1".
        var said = ""
        if let asked = groups(#"probability that (?:[a-z' ]+? )??(?:the |an? )?(?:result|total|sum|product|difference|answer)(?: of (?:the )?(?:two |three )?(?:numbers|scores))? (?:that )?is (.+?)(?:\.|\?|$)"#, in: text) {
            said = asked[1]
        } else if let asked = groups(#"probability that (?:[a-z' ]+? )??gets? (an? (?:even|odd|prime|square)) (?:total|sum|product|difference|result|answer)(?:\.|\?|$)"#, in: text) {
            said = asked[1] + " number"
        } else if let asked = groups(#"probability that (?:[a-z' ]+? )??gets? a (?:total|sum|product|difference|result) of (\d+)(?:\.|\?|$)"#, in: text) {
            said = asked[1]
        } else {
            return nil
        }
        let asked = ["", said]
        var tests: [(Int) -> Bool] = []
        func isPrime(_ m: Int) -> Bool { m > 1 && (2..<max(m, 2)).allSatisfy { $0 * $0 > m || m % $0 != 0 } }
        for part in asked[1].lowercased().components(separatedBy: " or ") {
            let plain = part.trimmingCharacters(in: .whitespaces)
            if let kind = groups(#"^(?:an? )?(even|odd|prime|square)(?: number)?$"#, in: plain) {
                switch kind[1] {
                case "even": tests.append { $0 % 2 == 0 }
                case "odd": tests.append { $0 % 2 != 0 }
                case "prime": tests.append(isPrime)
                default: tests.append { m in m >= 0 && { let r = Int(Double(m).squareRoot().rounded()); return r * r == m }() }
                }
            } else if let of = groups(#"^(?:an? )?(multiple|factor) of (\d+)$"#, in: plain), let m = Int(of[2]), m > 0 {
                used.append(of[2])
                tests.append(of[1] == "multiple" ? { $0 % m == 0 } : { $0 != 0 && m % $0 == 0 })
            } else if let than = groups(#"^(greater|more|bigger|larger|less|smaller) than (\d+)$"#, in: plain), let m = Int(than[2]) {
                used.append(than[2])
                tests.append(["less", "smaller"].contains(than[1]) ? { $0 < m } : { $0 > m })
            } else if let exact = groups(#"^(?:exactly |equal to )?(\d+)$"#, in: plain), let m = Int(exact[1]) {
                used.append(exact[1])
                tests.append { $0 == m }
            } else {
                return nil
            }
        }
        // Every way the picks can come out: in order where one can come up again, as sets where it can't.
        var outcomes: [[Int]] = []
        func build(_ so: [Int], _ from: Int) {
            if so.count == k { outcomes.append(so.map { values[$0] }); return }
            for index in (back ? 0 : from)..<values.count { build(so + [index], index + 1) }
        }
        build([], 0)
        guard !outcomes.isEmpty, outcomes.count <= 5000 else { return nil }
        let results = outcomes.map(result)
        let hits = results.filter { r in tests.contains { $0(r) } }
        let what = asked[1].lowercased()
        var lead = [Step("Every way it can come out",
                         (back ? "\(values.count) numbers each time, \(k) times: \(Array(repeating: String(values.count), count: k).joined(separator: " × ")) = \(outcomes.count) ways, all as likely as each other."
                               : "\(k) of the \(values.count) \(thing) can be taken in \(outcomes.count) different sets, all as likely as each other.")
                         + (outcomes.count <= 16 ? " The \(name)s: \(results.map(String.init).joined(separator: ", "))." : ""))]
        if which == 0, !back, tests.count == 1, what.contains("even") || what.contains("odd"), outcomes.count > 16 {
            // By how many odd numbers are in the set: an even sum has none of them, or two.
            let odd = values.filter { $0 % 2 != 0 }.count, even = values.count - odd
            func choose(_ n: Int, _ r: Int) -> Int { r < 0 || r > n ? 0 : (0..<r).reduce(1) { $0 * (n - $1) / ($1 + 1) } }
            let wantsEven = what.contains("even")
            let lines = (0...k).filter { ($0 % 2 == 0) == wantsEven && choose(odd, $0) * choose(even, k - $0) > 0 }
                .map { MathLine(.symbol("\($0) odd, \(k - $0) even"), .integer(choose(odd, $0)) * .integer(choose(even, k - $0)), .integer(choose(odd, $0) * choose(even, k - $0))) }
            lead.append(Step("The ones that fit", "A sum is \(wantsEven ? "even" : "odd") when \(wantsEven ? "an even number (none, or two)" : "an odd number (one, or three)") of the numbers in it are odd. There are \(odd) odd and \(even) even \(thing). That's \(hits.count) sets.", lines))
        } else {
            lead.append(Step("The ones that fit", "\(hits.count) of them give a \(name) that is \(what)" + (hits.count <= 12 && Set(hits).count > 1 ? ": \(hits.map(String.init).joined(separator: ", "))." : ".")))
        }
        var problem = Problem(kind: .evaluate(Expr.integer(hits.count) / .integer(outcomes.count)), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: Double(hits.count) / Double(outcomes.count))
    }

    // MARK: The same score twice

    /// "The table shows the probability of each score. [1: 0.4, 2: 0.3, 3: 0.2, 4: 0.1] The student
    /// spins the spinner twice. Calculate the probability that the student gets the same score on
    /// each spin." Which chance goes with which score makes no difference to the answer.
    private static func sameTwice(_ question: Question) -> Found? {
        let text = question.text
        guard has(#"\btable shows the probabilit(?:y|ies) of (?:each|every|getting each) (?:score|number|colou?r|outcome)\b"#, text),
              has(#"\b(?:spins|rolls|throws) (?:the|a|this) (?:[a-z-]+ )?(?:spinner|dice|coin) twice\b|\b(?:spinner|dice|coin) is (?:spun|rolled|thrown) twice\b"#, text),
              let asked = groups(#"probability (?:that )?(?:[a-z' ]+? )??(?:gets?|lands? on|scores?|shows?) (?:the )?(same|different|a different) (?:score|number|colou?r)s?(?: on (?:each|both) (?:spin|roll|throw|spins|rolls|throws)| both times| each time)?(?:\.|\?|$)"#, in: text) else { return nil }
        // The chances: every decimal in the table, as many as there are scores, adding up to 1.
        var chances: [String] = [], labels = 0
        for line in question.lines {
            if let row = groups(#"^probability((?: \d*\.\d+)+)$"#, in: line) { chances += row[1].split(separator: " ").map(String.init) }
            else if line.range(of: #"^\d*\.\d+$"#, options: .regularExpression) != nil { chances.append(line) }
            else if let row = groups(#"^(?:score|number|colou?r|outcome)((?: [A-Za-z0-9]+)+)$"#, in: line) { labels = row[1].split(separator: " ").count }
        }
        // How many scores there are: the table's own row of them, or "numbered 1, 2, 3 and 4".
        var used = chances
        if let list = groups(#"\bnumbered ((?:\d+, )*\d+,? and \d+)\b"#, in: text) {
            let scores = every(#"\d+"#, in: list[1]).map(\.[0])
            guard labels == 0 || labels == scores.count else { return nil }
            labels = scores.count; used += scores
        }
        let parts = chances.compactMap(chance)
        guard parts.count == chances.count, parts.count >= 2, parts.count == labels, parts.reduce(Fraction(0, 1), +) == Fraction(1, 1), parts.allSatisfy({ $0.numerator > 0 }) else { return nil }
        // The scores written out again, in the table's row or the picture of the spinner: each has to be one of the scores.
        if let list = groups(#"\bnumbered ((?:\d+, )*\d+,? and \d+)\b"#, in: text) {
            let scores = Set(every(#"\d+"#, in: list[1]).map(\.[0]))
            for line in question.lines {
                guard let row = groups(#"^(?:score |number |outcome )?(\d+(?: \d+)+)$"#, in: line) else { continue }
                let again = row[1].split(separator: " ").map(String.init)
                guard again.allSatisfy(scores.contains) else { return nil }
                used += again
            }
        }
        let same = parts.reduce(Fraction(0, 1)) { $0 + $1 * $1 }
        let squares = Expr.add(chances.compactMap { Parser.expression($0) }.map { $0 * $0 })
        let wantsSame = asked[1].lowercased() == "same"
        var problem = Problem(kind: .evaluate(wantsSame ? squares : Expr.one - squares), text: "", usesDecimals: true)
        problem.lead = [Step("Each score twice over", "The two spins don't change each other, so the chance of a score both times is its chance times itself.",
                             zip(chances, parts).map { MathLine(.symbol("\($0.0) × \($0.0)"), Parser.expression(decimal($0.1 * $0.1)) ?? ($0.1 * $0.1).expr) }),
                        Step(wantsSame ? "Add them up" : "Take it from 1", wantsSame ? "The same score is the first score twice, or the second twice, and so on." : "Different scores is everything except the same score twice.")]
        return Found(problem: problem, used: used, size: (wantsSame ? same : Fraction(1, 1) - same).double)
    }

    // MARK: Codes from the letters of a word

    /// "A code is three letters, each of which is in the word LOGIC. Vinny assumes that letters in
    /// the code may be used more than once. He works out how many possible codes there are. In
    /// fact, the first two letters are the same and the third is different. How many of Vinny's
    /// codes are not possible?"
    private static func codes(_ question: Question) -> Found? {
        let text = question.text
        // The word may stand on a line of its own.
        let everything = question.lines.joined(separator: " ")
        guard let size = groups(#"\bcode (?:is|has|consists of|is made (?:up )?of) (\d|two|three|four|five) letters\b"#, in: text), let k = count(size[1]), k >= 2, k <= 5,
              let word = groupsExact(#"\bin the word ([A-Z]{3,10})\b"#, in: everything)?[1] else { return nil }
        // Each letter of the word once: with a letter twice there's no telling whether both count.
        let n = Set(word).count
        guard n == word.count, n >= k else { return nil }
        var used: [String] = size[1].first?.isNumber == true ? [size[1]] : []
        // The rules said for the code, each as how many codes it allows.
        typealias Rule = (count: Int, expr: Expr, how: String)
        let orderly = (0..<k).map { n - $0 }
        let known: [(pattern: String, rule: Rule?)] = [
            (#"\b(?:no letter|letters? (?:may|can)(?: not|not) be) (?:(?:is|are|be) )?(?:used more than once|repeated)\b|\ball (?:the |\w+ )?letters are different\b|\beach letter (?:may|can) only be used once\b"#,
             (orderly.reduce(1, *), .multiply(orderly.map { .integer($0) }), "Any of \(n), then any of the \(n - 1) left, and so on")),
            (#"\b(?:letters )?(?:in the code )?(?:may|can) be (?:used more than once|repeated|used again)\b"#,
             (Int(pow(Double(n), Double(k))), .multiply(Array(repeating: .integer(n), count: k)), "Any of the \(n) letters each time, \(k) times over")),
            (#"\b(?:the )?first two letters are the same and the third (?:letter )?is different\b"#,
             k == 3 ? (n * (n - 1), .multiply([.integer(n), .integer(1), .integer(n - 1)]), "Any of \(n) for the first, the same again for the second, and any of the other \(n - 1) for the third") : nil),
            (#"\ball (?:\w+ )?letters are the same\b"#, (n, .integer(n), "One code for each of the \(n) letters")),
        ]
        // Anything else said about which codes there can be isn't a rule that's known.
        let other = #"\bstarts?\b|\bends?\b|\bbegins?\b|\bvowels?\b|\bconsonants?\b|\bmust\b|\b(?:first|last|second|third|middle) letter\b|\bcannot\b|\bcan't\b|\bnot\b|\bdifferent\b|\bsame\b|\border\b"#
        var rules: [Rule] = []
        let sentences = text.replacingOccurrences(of: #"(?<=[.?])\s+"#, with: "\u{1}", options: .regularExpression).components(separatedBy: "\u{1}")
        var mine: Int?
        for sentence in sentences where !has(#"\bhow many\b.*\?$"#, sentence) {
            guard let found = known.first(where: { has($0.pattern, sentence) }) else {
                guard !has(other, sentence) else { return nil }
                continue
            }
            let rest = sentence.replacingOccurrences(of: found.pattern, with: "", options: [.regularExpression, .caseInsensitive])
            guard let rule = found.rule, !has(other, rest) else { return nil }
            // "Vinny assumes that …": whose count it is.
            if has(#"\bassumes\b|\bthinks\b"#, sentence) { guard mine == nil else { return nil }; mine = rules.count }
            rules.append(rule)
        }
        var expr: Expr, value: Int, lead: [Step]
        if has(#"\bhow many of [a-z]+'s codes are not possible\b"#, text) {
            // The ones counted that the real rule doesn't allow.
            guard rules.count == 2, let mine, has(#"\bin fact\b"#, text) else { return nil }
            let (his, real) = (rules[mine], rules[1 - mine])
            guard real.count <= his.count else { return nil }
            expr = his.expr - real.expr; value = his.count - real.count
            lead = [Step("Count the codes assumed", his.how + ".", [MathLine(his.expr, .integer(his.count))]),
                    Step("Count the codes there really are", real.how + ".", [MathLine(real.expr, .integer(real.count))]),
                    Step("Take away", "Every real code is one of those assumed, so the rest of them are not possible.")]
        } else if has(#"\bhow many (?:possible )?codes (?:are|can)\b|\b(?:work out|find) (?:the number of|how many) (?:possible |different )*codes\b"#, text) {
            guard rules.count == 1, let only = rules.first else { return nil }
            expr = only.expr; value = only.count
            lead = [Step("Count the choices for each letter", only.how + ".")]
        } else {
            return nil
        }
        if let again = groups(#"\bthe (\d) letters\b"#, in: text) { used.append(again[1]) }
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = [Step("The letters", "\(word) has \(n) different letters, and a code is \(k) of them in order.")] + lead
        return Found(problem: problem, used: used, size: Double(value))
    }

    // MARK: Two groups and two kinds, counted in words

    /// "120 students in Year 10 and Year 11 sit a test. 61 of the students are in Year 10. 83 of
    /// the students are right-handed. 20 of the students in Year 11 are left-handed. One of the
    /// students in Year 10 and one of the students in Year 11 are chosen at random. Which one is
    /// more likely to be left-handed?"
    private static func twoWay(_ question: Question) -> Found? {
        let text = question.text
        let group = #"[A-Z][a-z]+ \d+|[A-Z][a-z]+"#
        guard let all = groupsExact(#"\b(\d+) ([a-z]+) in (\#(group)) and (\#(group))\b"#, in: text), let total = Int(all[1]),
              let asked = groups(#"\bwhich (?:one )?is more likely to be ([a-z][a-z-]*)"#, in: text),
              has(#"\bone of the [a-z]+ in .+? and one of the [a-z]+ in .+? (?:are|is) (?:chosen|picked|selected) at random\b"#, text) else { return nil }
        let names = [all[3], all[4]], noun = NSRegularExpression.escapedPattern(for: all[2].lowercased()), wanted = asked[1].lowercased()
        guard names[0] != names[1] else { return nil }
        // A word read with one letter wrong is still the word asked about: "lett-handed".
        func near(_ a: String, _ b: String) -> Bool {
            a == b || (a.count == b.count && a.count >= 5 && zip(a, b).filter { $0 != $1 }.count == 1)
        }
        var other: String?
        func kind(_ word: String) -> Int? {
            let lower = word.lowercased()
            if near(lower, wanted) { return 0 }
            // The other kind: the same sort of word ("right-handed" with "left-handed").
            guard let suffix = wanted.split(separator: "-").last, wanted.contains("-"), lower.split(separator: "-").last == suffix, lower.contains("-") else { return nil }
            if let other, other != lower { return nil }
            other = lower
            return 1
        }
        let place = names.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // Cells: group × kind, as 2 × group + kind.
        var rows: [[Fraction]] = [Array(repeating: Fraction(1, 1), count: 4) + [Fraction(total, 1)]]
        var used = [all[1]]
        for found in every(#"\b(\d+) of the \#(noun)(?: in (\#(place)))? (?:are|is) (?:in (\#(place))\b|([a-z][a-z-]+))"#, in: text) {
            guard let size = Int(found[1]) else { return nil }
            var cells: [Int]
            if !found[3].isEmpty {
                guard found[2].isEmpty, let g = names.firstIndex(of: found[3]) else { return nil }
                cells = [2 * g, 2 * g + 1]
            } else {
                guard let k = kind(found[4]) else { return nil }
                if let g = names.firstIndex(of: found[2]) { cells = [2 * g + k] } else { guard found[2].isEmpty else { return nil }; cells = [k, 2 + k] }
            }
            rows.append((0..<4).map { cells.contains($0) ? Fraction(1, 1) : Fraction(0, 1) } + [Fraction(size, 1)])
            used.append(found[1])
        }
        guard rows.count == 4, let solved = solveLinear(rows, unknowns: 4) else { return nil }
        var cells: [Int] = []
        for value in solved {
            guard let value, value.denominator == 1, value.numerator >= 0 else { return nil }
            cells.append(value.numerator)
        }
        // The numbers in the groups' names, each time they're said.
        for name in names {
            for digits in every(#"\d+"#, in: name).map(\.[0]) {
                used += Array(repeating: digits, count: every(#"\b\#(NSRegularExpression.escapedPattern(for: name))\b"#, in: text).count)
                _ = digits
            }
        }
        let sizes = [cells[0] + cells[1], cells[2] + cells[3]]
        guard sizes.allSatisfy({ $0 > 0 }) else { return nil }
        let chances = [Fraction(cells[0], sizes[0]), Fraction(cells[2], sizes[1])]
        guard chances[0] != chances[1] else { return nil }
        let winner = chances[0].double > chances[1].double ? 0 : 1
        let lead = [Step("Fill in the table", "\(names[0]): \(cells[0]) \(wanted), \(cells[1]) not, \(sizes[0]) in all. \(names[1]): \(cells[2]) \(wanted), \(cells[3]) not, \(sizes[1]) in all."),
                    Step("Compare the chances", "In \(names[0]) it's \(cells[0])/\(sizes[0]) = \(String(format: "%.3f", chances[0].double)); in \(names[1]) it's \(cells[2])/\(sizes[1]) = \(String(format: "%.3f", chances[1].double)).")]
        var problem = Problem(kind: .worded(question: "More likely to be \(wanted)", answers: [MathLine(.symbol(names[winner]))]), text: "", usesDecimals: false)
        problem.lead = lead
        return Found(problem: problem, used: used, size: nil)
    }

    // MARK: Relative frequency

    /// "A coin is thrown 50 times. It lands on heads 31 times. Write down the relative frequency it
    /// lands on heads.", "in a batch of 96 phones, 6 were reported as faulty … the relative frequency
    /// of faulty phones", and back the other way: "A coin lands on Tails 200 times. The relative
    /// frequency of Tails is 0.4. Work out the number of times the coin was thrown."
    private static func relativeFrequency(_ question: Question) -> Found? {
        let text = question.text
        let goes = #"(?:thrown|spun|rolled|flipped|tossed)"#
        if let landed = groups(#"\blands on ([a-z]+) (\d+) times\b"#, in: text),
           let rate = groups(#"\brelative frequency of \#(NSRegularExpression.escapedPattern(for: landed[1])) is (\#(number))(?![\d/])"#, in: text),
           has(#"\b(?:work out|find|calculate) the (?:total )?number of times the [a-z]+ was \#(goes)\b"#, text),
           let times = Int(landed[2]), let r = chance(rate[1]), !r.isZero {
            let whole = Fraction(times, 1) / r
            guard whole.denominator == 1 else { return nil }
            var problem = Problem(kind: .evaluate(Expr.integer(times) / r.expr), text: "", usesDecimals: false)
            problem.lead = [Step("Out of how many", "\(landed[1]) came up \(times) times, and that's \(rate[1]) of all the throws, so there were \(times) ÷ \(rate[1]).")]
            return Found(problem: problem, used: [landed[2], rate[1]], size: whole.double)
        }
        // "Jo throws a biased coin 50 times. It lands on heads 32 times. Work out an estimate for the probability that the coin lands on tails."
        if let tries = groups(#"\b(?:throws|spins|flips|tosses) an? (?:biased )?coin (\d+) times\b|\ba (?:biased )?coin is (?:thrown|spun|flipped|tossed) (\d+) times\b"#, in: text), let landed = groups(#"\blands on (heads|tails) (\d+) times\b"#, in: text),
           let asked = groups(#"\bestimate (?:for|of) the probability (?:that (?:the coin|it) (?:will land|lands) on|of(?: getting)?) (heads|tails)\b"#, in: text),
           let n = Int(tries[1].isEmpty ? tries[2] : tries[1]), let k = Int(landed[2]), n > 0, k <= n, !has(#"\bfair\b"#, text) {
            let same = landed[1].lowercased() == asked[1].lowercased(), hits = same ? k : n - k
            var problem = Problem(kind: .evaluate(Expr.integer(hits) / .integer(n)), text: "", usesDecimals: false)
            problem.lead = [Step("How often it happened", same ? "\(asked[1].capitalized) \(k) times out of \(n)." : "\(landed[1].capitalized) \(k) times out of \(n), so \(asked[1].lowercased()) the other \(n) − \(k) = \(hits) times.")]
            return Found(problem: problem, used: [String(n), landed[2]], size: Double(hits) / Double(n))
        }
        var all: String, some: String, what: String
        if let tries = groups(#"\b(?:is|was|are|were) \#(goes) (\d+) times\b"#, in: text), let landed = groups(#"\blands on ([a-z]+) (\d+) times\b"#, in: text),
           has(#"\brelative frequency (?:that )?(?:it lands on|of) \#(NSRegularExpression.escapedPattern(for: landed[1]))\b"#, text) {
            all = tries[1]; some = landed[2]; what = landed[1]
        } else if let batch = groups(#"\bin a [a-z]+ of (\d+) ([a-z]+), (\d+) (?:were|was) (?:reported as |found to be )?([a-z]+)\b"#, in: text),
                  has(#"\brelative frequency of \#(NSRegularExpression.escapedPattern(for: batch[4])) \#(NSRegularExpression.escapedPattern(for: batch[2]))\b"#, text) {
            all = batch[1]; some = batch[3]; what = batch[4]
        } else {
            return nil
        }
        guard let n = Int(all), let k = Int(some), n > 0, k <= n else { return nil }
        var problem = Problem(kind: .evaluate(Expr.integer(k) / .integer(n)), text: "", usesDecimals: false)
        problem.lead = [Step("How often it happened", "\(what) \(k) times out of \(n).")]
        return Found(problem: problem, used: [all, some], size: Double(k) / Double(n))
    }

    // MARK: Choosing one of each

    /// "They choose one of each from 8 faces, 4 bodies, 5 hairstyles. How many different characters
    /// can be made?", "An outfit is 1 shirt, 1 pair of jeans and 1 jacket", "choose at random 2 of
    /// the students … the number of different pairs", and "Two characters are made at random. What
    /// is the probability that they are exactly the same?"
    private static func choices(_ question: Question) -> Found? {
        let text = question.text
        // Pairs from a group.
        if let group = groups(#"\bthere are (\d+) ([a-z]+) in (?:a|the) [a-z]+\b"#, in: text),
           has(#"\bchoose (?:at random )?(?:2|two) of the \#(NSRegularExpression.escapedPattern(for: group[2]))\b"#, text),
           has(#"\b(?:work out |find )?(?:the number of|how many) different pairs\b"#, text), let n = Int(group[1]), n >= 2 {
            var problem = Problem(kind: .evaluate(Expr.integer(n) * .integer(n - 1) / .two), text: "", usesDecimals: false)
            problem.lead = [Step("Count the pairs", "The first can be any of \(n) and the second any of the other \(n - 1), but that counts each pair twice, once in each order.")]
            return Found(problem: problem, used: [group[1]] + (text.range(of: #"\b2 of the"#, options: .regularExpression) != nil ? ["2"] : []), size: Double(n * (n - 1) / 2))
        }
        // A list, one line each: "8 faces", "5 pairs of jeans", "10 main dishes".
        var items: [(count: Int, name: String, shown: String)] = []
        for line in question.lines {
            let plain = line.trimmingCharacters(in: CharacterSet(charactersIn: " .•"))
            if plain.isEmpty || plain.lowercased() == "and" { continue }
            if let item = groups(#"^(?:and )?(\d+) ((?:different |pairs of |main )?[a-z]+(?: [a-z]+)?)\.?$"#, in: plain), let size = Int(item[1]) {
                items.append((size, String(item[2].split(separator: " ").last!).lowercased(), plain))
            } else if items.count >= 2 { break } else { items = [] }
        }
        guard items.count >= 2, items.count <= 4 else { return nil }
        // Which one of each is wanted: "one of each", or every one of them named.
        let says = groups(#"\b(?:choose one of each|one of each from|consists of|is made of|(?:an? [a-z]+ )?is|choose) (?:(?:an?|one|1) [a-z]+(?: [a-z]+){0,2}(?:, | and |,? and )){1,3}(?:an?|one|1) [a-z]+(?: [a-z]+){0,2}"#, in: text)?[0].lowercased()
        let eachOne = has(#"\bone of each\b"#, text)
        if !eachOne {
            guard let says else { return nil }
            for item in items where !has(#"\b\#(NSRegularExpression.escapedPattern(for: String(item.name.prefix(max(3, item.name.count - 3)))))"#, says) { return nil }
        }
        var used = items.map { String($0.count) } + (says.map { every(#"\b(1)\b"#, in: $0).map(\.[1]) } ?? [])
        // The same thing, one or many: "sandwich" and "sandwiches".
        func alike(_ a: String, _ b: String) -> Bool {
            let (x, y) = (a.lowercased(), b.lowercased())
            return x == y || x == y + "s" || x == y + "es" || y == x + "s" || y == x + "es"
        }
        // Some of them away: "One labourer and two plumbers are on holiday."
        var counts = items.map(\.count), away = ""
        if let gone = groups(#"\b(\#(amount)) ([a-z]+)(?: and (\#(amount)) ([a-z]+))? (?:are|is) (?:on holiday|away|absent|off sick|not available|unavailable)\b"#, in: text) {
            for (size, word) in [(gone[1], gone[2]), (gone[3], gone[4])] where !size.isEmpty {
                guard let many = count(size), let at = items.firstIndex(where: { alike($0.name, word) }), many < counts[at] else { return nil }
                counts[at] -= many
                if size.first?.isNumber == true { used.append(size) }
            }
            away = " \(gone[0].prefix(1).uppercased() + gone[0].dropFirst()), which leaves \(counts.map(String.init).joined(separator: ", "))."
        }
        let product = counts.reduce(1, *)
        let factors = Expr.multiply(counts.map { .integer($0) })
        if has(#"\bhow many different\b|\bnumber of different\b|\bin how many (?:different )?ways\b"#, text), !has(#"\bprobability\b"#, text) {
            var problem = Problem(kind: .evaluate(factors), text: "", usesDecimals: false)
            problem.lead = [Step("Multiply the choices", "Any of the \(items.map { $0.shown }.joined(separator: ", ")) can go with any of the others, so multiply." + away)]
            return Found(problem: problem, used: used, size: Double(product))
        }
        // "Two of the sandwiches have cheese in them. Three of the drinks are fizzy. … the probability that the sandwich has cheese in it and the drink is fizzy."
        if away.isEmpty, has(#"\bat random\b"#, text),
           let asked = groups(#"\bprobability that the ([a-z]+) (?:has|have|is|are|contains?) ([a-z ]+?) and the ([a-z]+) (?:has|have|is|are|contains?) ([a-z ]+?)(?:\.|\?|$)"#, in: text) {
            let facts = every(#"\b(\#(amount)) of the ([a-z]+) (?:have|has|are|is|contain) ([a-z ]+?)(?:\.|$)"#, in: text)
            // What it has: the first word that says so ("cheese in them" and "cheese in it").
            func key(_ words: String) -> String { words.lowercased().split(separator: " ").map(String.init).first { $0.count >= 4 && !["have", "them", "that", "with", "this", "some"].contains($0) } ?? "" }
            var parts: [(some: Int, all: Int)] = [], named: [Int] = []
            for (thing, what) in [(asked[1], asked[2]), (asked[3], asked[4])] {
                guard let at = items.firstIndex(where: { alike($0.name, thing) }), !key(what).isEmpty else { return nil }
                let matching = facts.filter { alike($0[2], thing) && key($0[3]) == key(what) }
                guard matching.count == 1, let some = count(matching[0][1]), some >= 1, some <= counts[at] else { return nil }
                if matching[0][1].first?.isNumber == true { used.append(matching[0][1]) }
                parts.append((some, counts[at])); named.append(at)
            }
            // Each fact said is one of the two asked about.
            guard facts.count == 2, Set(named).count == 2 else { return nil }
            let expr = Expr.integer(parts[0].some) / .integer(parts[0].all) * (Expr.integer(parts[1].some) / .integer(parts[1].all))
            var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
            problem.lead = [Step("The chance for each", "\(parts[0].some) of the \(parts[0].all) \(items[named[0]].name) and \(parts[1].some) of the \(parts[1].all) \(items[named[1]].name). What the other one is makes no difference."),
                            Step("Both", "One choice doesn't change the other, so multiply.")]
            return Found(problem: problem, used: used, size: Double(parts[0].some * parts[1].some) / Double(parts[0].all * parts[1].all))
        }
        if has(#"\btwo [a-z]+ are (?:made|chosen|picked) at random\b"#, text), has(#"\bprobability (?:that )?they are (?:exactly )?the same\b"#, text) {
            var problem = Problem(kind: .evaluate(Expr.one / factors), text: "", usesDecimals: false)
            problem.lead = [Step("Count the ways", "There are \(product) different ones, all as likely. Whatever the first is, the second has to be that one: 1 out of \(product).")]
            return Found(problem: problem, used: used, size: 1 / Double(product))
        }
        return nil
    }

    // MARK: Separate events, each with a chance

    /// "The probability that coin A will land on heads is 0.6. The probability that coin B will land
    /// on heads is 0.55 … both coins land on heads." Also one chance on each of two days, "at least
    /// one", "only one", and the other chance worked out from "only one".
    private static func separate(_ question: Question) -> Found? {
        let text = question.text
        // One thing depending on another isn't separate.
        guard !has(#"\bif\b|\bgiven\b|\bthen\b"#, text) else { return nil }
        let value = #"(\d*\.\d+|\d+/\d+|[a-z])"#
        var events: [(subject: String, p: Fraction?, shown: String)] = [], onlyOne: (Fraction, String)?
        for found in every(#"\bprobability (?:that |of )(.+?) is \#(value)(?=[\s.,]|$)"#, in: text) {
            let subject = found[1].lowercased()
            if has(#"\b(?:only|just|exactly) one\b"#, subject) {
                guard onlyOne == nil, let p = chance(found[2]) else { return nil }
                onlyOne = (p, found[2]); continue
            }
            events.append((subject, chance(found[2]), found[2]))
        }
        guard !events.isEmpty, events.count <= 2,
              let asked = groups(#"\b(?:work out|find|calculate|what is|write down) the probability (?:that |of )(.+?)(?:\.|\?|$)"#, in: text)?[1].lowercased()
                ?? (has(#"\b(?:work out|find) the value of [a-z]\b"#, text) ? "" : nil) else { return nil }
        func words(_ s: String) -> [String] { s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0) } }
        let filler: Set<String> = ["the", "a", "an", "will", "be", "is", "on", "any", "day", "of", "to", "that", "both", "these", "two", "one", "at", "least", "only", "just", "exactly", "neither", "none"]
        let how = has(#"^(?:both|all)\b"#, asked) ? "both" : has(#"\bat least one\b"#, asked) ? "least" : has(#"\b(?:only|just|exactly) one\b"#, asked) ? "one" : has(#"^(?:neither|none)\b"#, asked) ? "neither" : ""
        var used = events.compactMap { $0.p == nil ? nil : $0.shown } + (onlyOne.map { [$0.1] } ?? [])
        var p: Fraction, q: Fraction, lead: [Step] = []
        if events.count == 2, onlyOne == nil, let a = events[0].p, let b = events[1].p {
            // Two things, said the same way but for one word ("coin A", "coin B").
            let (x, y) = (words(events[0].subject), words(events[1].subject))
            guard x.count == y.count, zip(x, y).filter({ $0 != $1 }).count == 1 else { return nil }
            let shared = Set(x).intersection(y).subtracting(filler)
            guard !shared.isEmpty, !Set(words(asked)).intersection(shared).isEmpty, !how.isEmpty else { return nil }
            p = a; q = b
            lead.append(Step("The two chances", "P(\(events[0].subject)) = \(events[0].shown) and P(\(events[1].subject)) = \(events[1].shown). One doesn't change the other, so the chances multiply."))
        } else if events.count == 1, onlyOne == nil, let a = events[0].p, has(#"\bon (?:any|each|every) (?:day|[a-z]+)\b"#, events[0].subject),
                  has(#"\b(?:of )?(?:these|the) (?:two|2) [a-z]+s\b|\bboth [a-z]+s\b"#, asked) {
            // The same chance on each of two days.
            let shared = Set(words(events[0].subject)).subtracting(filler)
            guard !Set(words(asked)).intersection(shared).isEmpty, !how.isEmpty else { return nil }
            p = a; q = a
            if let two = groups(#"\b(2) [a-z]+s\b"#, in: asked) { used.append(two[1]) }
            lead.append(Step("Each time", "The chance is \(events[0].shown) each time, whatever happened the time before."))
        } else if let only = onlyOne, events.count == 2 || events.count == 1, let a = events[0].p, how.isEmpty {
            // The other chance from "only one": p(1 − q) + q(1 − p) = r, so q = (r − p) / (1 − 2p).
            guard has(#"\bindependent\b"#, text) || (events.count == 2 && events[1].p == nil) else { return nil }
            let mine = words(events[0].subject), theirs = words(asked)
            let other = events.count == 2 ? words(events[1].subject) : theirs
            guard mine.count == other.count, zip(mine, other).filter({ $0 != $1 }).count == 1 else { return nil }
            if events.count == 2 {
                // "… the second task is x … Work out the value of x."
                guard events[1].p == nil, let letter = groups(#"\bvalue of ([a-z])\b"#, in: text)?[1], letter == events[1].shown else { return nil }
            } else {
                guard mine.count == theirs.count else { return nil }
            }
            let half = Fraction(1, 2)
            guard a != half else { return nil }
            let other2 = (only.0 - a) / (Fraction(1, 1) - Fraction(2, 1) * a)
            guard other2.numerator >= 0, other2.numerator <= other2.denominator else { return nil }
            let step = Step("Only one of the two", "Either the first and not the second, or the second and not the first: \(events[0].shown)(1 − q) + q(1 − \(events[0].shown)) = \(only.1). Solve for q.")
            var problem: Problem
            if events.count == 2 {
                problem = Problem(kind: .worded(question: "Find \(events[1].shown)", answers: [MathLine(.symbol(events[1].shown), Parser.expression(decimal(other2)) ?? other2.expr)]), text: "", usesDecimals: true)
            } else {
                problem = Problem(kind: .evaluate(Parser.expression(decimal(other2)) ?? other2.expr), text: "", usesDecimals: true)
            }
            problem.lead = [step]
            return Found(problem: problem, used: used, size: other2.double)
        } else {
            return nil
        }
        let one = Fraction(1, 1)
        let decimalish = events.contains { $0.shown.contains(".") }
        func shownP(_ f: Fraction) -> Expr { decimalish ? (Parser.expression(decimal(f)) ?? f.expr) : f.expr }
        var expr: Expr, size: Fraction
        switch how {
        case "both": expr = shownP(p) * shownP(q); size = p * q; lead.append(Step("Both", "Multiply the two chances."))
        case "neither": expr = shownP(one - p) * shownP(one - q); size = (one - p) * (one - q); lead.append(Step("Neither", "Multiply the chances of each not happening."))
        case "least": expr = Expr.one - shownP(one - p) * shownP(one - q); size = one - (one - p) * (one - q); lead.append(Step("At least one", "Everything except neither: 1 take away the chance that neither happens."))
        default: expr = shownP(p) * shownP(one - q) + shownP(one - p) * shownP(q); size = p * (one - q) + (one - p) * q; lead.append(Step("Only one", "The first and not the second, or the second and not the first: add the two."))
        }
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: decimalish)
        problem.lead = lead
        return Found(problem: problem, used: used, size: size.double)
    }

    // MARK: Each rolls a dice

    /// "Jacob, Amelie and Reuben each roll a fair six-sided dice. What is the probability that all
    /// three roll a number less than 3?"
    private static func eachRolls(_ question: Question) -> Found? {
        let text = question.text
        guard has(#"\beach (?:roll|throw|rolls|throws) an? (?:ordinary |fair )*(?:six-sided |6-sided )?dice\b"#, text), has(#"\bfair\b|\bordinary\b"#, text),
              let asked = groups(#"probability (?:that )?(?:all|each of the) (two|three|four|2|3|4) (?:of them )?(?:roll|throw|get|score)s? (?:a |an )?(?:number (less|greater|more) than (\d)|(even|odd|prime) number|(six|6))"#, in: text),
              let k = count(asked[1]) ?? Int(asked[1]) else { return nil }
        let faces = (1...6).filter { face in
            if !asked[2].isEmpty, let limit = Int(asked[3]) { return asked[2].lowercased() == "less" ? face < limit : face > limit }
            switch asked[4].lowercased() {
            case "even": return face % 2 == 0
            case "odd": return face % 2 == 1
            case "prime": return [2, 3, 5].contains(face)
            default: return face == 6
            }
        }
        // As many people as dice: "Jacob, Amelie and Reuben" is three.
        if let names = groupsExact(#"^(?:[A-Z][a-z]+, )*[A-Z][a-z]+ and [A-Z][a-z]+ each\b"#, in: text) {
            guard names[0].split(separator: ",").count + 1 == k else { return nil }
        }
        guard !faces.isEmpty, faces.count < 6 else { return nil }
        let p = Fraction(faces.count, 6)
        var problem = Problem(kind: .evaluate(.multiply(Array(repeating: p.expr, count: k))), text: "", usesDecimals: false)
        problem.lead = [Step("One dice", "\(faces.count) of the 6 faces (\(faces.map(String.init).joined(separator: ", "))) will do, so the chance for one is \(faces.count)/6. The dice don't change each other: multiply \(k) of them.")]
        var used: [String] = []
        if asked[1].first?.isNumber == true { used.append(asked[1]) }
        if !asked[3].isEmpty { used.append(asked[3]) }
        if asked[5] == "6" { used.append("6") }
        if text.range(of: #"\b6-sided"#, options: .regularExpression) != nil { used.append("6") }
        return Found(problem: problem, used: used, size: pow(p.double, Double(k)))
    }

    // MARK: Letters of a word

    /// "The word MATHEMATICS is spelt using tiles … 99 children each take a tile at random … put the
    /// tile back … how many times the letter M is expected to be taken"
    private static func letters(_ question: Question) -> Found? {
        let text = question.text
        guard let word = groupsExact(#"\bword ([A-Z]{3,})\b"#, in: text)?[1], let letter = groupsExact(#"\bletter ([A-Z])\b"#, in: text)?[1],
              let times = groups(#"\b(\d+) [a-z]+ each (?:take|pick|choose)s? an? [a-z]+ at random\b|\b(?:taken|picked|chosen) (\d+) times\b"#, in: text),
              has(#"\b(?:put|puts) (?:the|it|each) [a-z]* ?back\b|\breplaced?\b|\bback in\b"#, text), has(#"\bexpected\b|\bexpect\b"#, text),
              let n = Int(times[1].isEmpty ? times[2] : times[1]) else { return nil }
        let hits = word.filter { String($0) == letter }.count
        guard hits > 0 else { return nil }
        let p = Fraction(hits, word.count)
        var problem = Problem(kind: .evaluate(p.expr * .integer(n)), text: "", usesDecimals: false)
        problem.lead = [Step("The chance each time", "\(hits) of the \(word.count) letters of \(word) are \(letter), and the tile goes back each time."), Step("Times the number of goes", "Expected number = \(hits)/\(word.count) × \(n).")]
        return Found(problem: problem, used: [String(n)], size: p.double * Double(n))
    }

    // MARK: A fair coin thrown again and again

    /// "A fair coin is thrown a number of times. The probability that every throw results in Heads is
    /// 1/64. How many times is the coin thrown?"
    private static func coinTimes(_ question: Question) -> Found? {
        let text = question.text
        guard has(#"\bfair coin\b"#, text), has(#"\bhow many times is the coin (?:thrown|tossed|flipped|spun)\b"#, text),
              let stated = groups(#"\bprobability (?:that )?(?:every|each|all the) (?:throw|toss|flip|spin)s? (?:results? in|lands? on|is|are|gives?) (?:a )?(heads|tails)\b is (\d+/\d+)"#, in: text),
              let p = chance(stated[2]), p.numerator == 1 else { return nil }
        var n = 0, d = p.denominator
        while d > 1, d % 2 == 0 { d /= 2; n += 1 }
        guard d == 1, n > 0 else { return nil }
        var problem = Problem(kind: .worded(question: "How many throws", answers: [MathLine(.integer(n))]), text: "", usesDecimals: false)
        problem.lead = [Step("Halve each time", "Each throw is \(stated[1].lowercased()) with chance 1/2, so n throws all \(stated[1].lowercased()) is (1/2)ⁿ = 1/2ⁿ. \(p.denominator) = 2^\(n).")]
        return Found(problem: problem, used: [stated[2]], size: Double(n))
    }

    // MARK: Two groups, each with its own chance

    /// "There are 720 boys and 700 girls in a school. The probability that a boy chosen at random
    /// studies French is 2/3. The probability that a girl chosen at random studies French is 3/5.
    /// Work out the number of students in the school who study French." Also the chance someone
    /// chosen from everyone does (or doesn't).
    private static func groupChances(_ question: Question) -> Found? {
        let text = question.text
        guard let pair = groups(#"\bthere are (\d+) ([a-z]+) and (\d+) ([a-z]+)\b"#, in: text), let x = Int(pair[1]), let y = Int(pair[3]) else { return nil }
        let irregular = ["men": "man", "women": "woman", "children": "child", "people": "person"]
        func one(_ plural: String) -> String { irregular[plural.lowercased()] ?? single(plural) }
        let names = [one(pair[2]), one(pair[4])]
        guard names[0] != names[1] else { return nil }
        // The word "probability" may be cut off at the edge: "…ility that a man chosen at random".
        var shares: [Fraction?] = [nil, nil], property = "", used = [pair[1], pair[3]]
        for found in every(#"(?:\bprobability|[a-z]*(?:ility|ty)) that an? ([a-z]+) chosen at random ([a-z][a-z ]*?) is (\d+/\d+|\d*\.\d+)"#, in: text) {
            guard let which = names.firstIndex(of: found[1].lowercased()), shares[which] == nil, let p = chance(found[3]) else { return nil }
            let said = verbBase(found[2].lowercased())
            if property.isEmpty { property = said } else { guard property == said else { return nil } }
            shares[which] = p; used.append(found[3])
        }
        guard let a = shares[0], let b = shares[1] else { return nil }
        let first = Fraction(x, 1) * a, second = Fraction(y, 1) * b
        guard first.denominator == 1, second.denominator == 1 else { return nil }
        let having = first.numerator + second.numerator, total = x + y
        let counting = Step("Count each group", "\(a.numerator)/\(a.denominator) of the \(x) \(pair[2]) is \(first.numerator); \(b.numerator)/\(b.denominator) of the \(y) \(pair[4]) is \(second.numerator). That's \(having) who \(property).",
                            [MathLine(.integer(first.numerator) + .integer(second.numerator), .integer(having))])
        let prop = NSRegularExpression.escapedPattern(for: property)
        if has(#"\b(?:work out|find|calculate) the number of [a-z]+ (?:in the [a-z]+ )?who \#(prop)\b"#, text) {
            var problem = Problem(kind: .evaluate(.integer(first.numerator) + .integer(second.numerator)), text: "", usesDecimals: false)
            problem.lead = [counting]
            return Found(problem: problem, used: used, size: Double(having))
        }
        if let asked = groups(#"\bprobability (?:that )?(?:an? |the )[a-z]+ (?:chosen at random )?(?:from the (?:whole )?[a-z]+ )?((?:does not|doesn't|do not) )?([a-z][a-z ]*?)(?:\.|\?|$)"#, in: text),
           verbBase(asked[2].lowercased()) == property, has(#"\b(?:an?|one) [a-z]+ (?:is )?chosen at random\b"#, text) {
            let not = !asked[1].isEmpty
            let count = not ? total - having : having
            var problem = Problem(kind: .evaluate(Expr.integer(count) / .integer(total)), text: "", usesDecimals: false)
            problem.lead = [counting, Step("Out of everyone", "\(count) of the \(total) \(not ? "don't" : "do").")]
            return Found(problem: problem, used: used, size: Double(count) / Double(total))
        }
        return nil
    }

    /// What it's chosen from, and what's asked of it: "from those who watch football does not play
    /// a sport", "One of the people who walked is chosen … this person also sailed", "visited France
    /// given that they had also visited Spain".
    private static func conditional(_ text: String) -> ([String], [String])? {
        if let both = groups(#"\bprobability that an? [a-z]+ chosen at random from those who (.+?) ((?:does|do|did|is|are|has|had|also)\b.*?)(?:\.|\?|$)"#, in: text) {
            return ([both[0], both[1]], [both[0], both[2]])
        }
        if let from = groups(#"\bone of the [a-z]+ who (.+?) is chosen at random\b"#, in: text),
           let asked = groups(#"\bprobability that (?:this person|this [a-z]+|they|he|she) (?:also )?(.+?)(?:\.|\?|$)"#, in: text) {
            return (from, asked)
        }
        if let asked = groups(#"\bprobability that (?:this person|this [a-z]+|they|he|she) (?:had |have |has )?(.+?) given that (?:they|he|she) (?:had |have |has )?(?:also )?(.+?)(?:\.|\?|$)"#, in: text) {
            return ([asked[0], asked[2]], [asked[0], asked[1]])
        }
        return nil
    }

    // MARK: Two sets, described in sentences

    /// "In a group of 120 adults, 85 watch football, 78 play a sport and 20 do neither. Find the
    /// probability that an adult chosen at random from those who watch football does not play a
    /// sport." Also "both", "exactly one", "given that", and two chosen.
    private static func twoSets(_ question: Question) -> Found? {
        let text = question.text
        guard let everyone = groups(#"\b(?:group|class|survey) of (\d+) [a-z]+\b|^(\d+) [a-z]+ (?:were|are) asked\b|^(\d+) [a-z]+ (?:attended|travelled|went|took)\b"#, in: text),
              let total = Int([everyone[1], everyone[2], everyone[3]].first { !$0.isEmpty } ?? "") else { return nil }
        var used = [String(total)]
        // Each "N …" said, up to the first sentence about choosing.
        var body: [String] = []
        for line in question.lines {
            if has(#"\b(?:chosen|picked|selected) at random\b|\bcomplete the\b|\brepresent this\b"#, line) { break }
            body.append(line)
        }
        let clauses = body.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ".•;")) }.flatMap { $0.components(separatedBy: ", ") }.flatMap { $0.components(separatedBy: " and ") }
        var sets: [(count: Int, words: [String], said: String)] = [], neither: Int?, both: Int?
        for clause in clauses {
            let plain = clause.trimmingCharacters(in: .whitespaces)
            guard let fact = groups(#"^(\d+) ([a-z][a-z ()-]*)$"#, in: plain), let size = Int(fact[1]) else { continue }
            if size == total, sets.isEmpty, neither == nil, both == nil, has(#"^(?:people|adults|children|students|[a-z]+s) "#, fact[2]) { continue }
            let phrase = fact[2].lowercased().replacingOccurrences(of: #"\([a-z]\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            used.append(fact[1])
            if has(#"\bneither\b|\bnot\b.*\b(?:either|or)\b|\bnone\b"#, phrase) { guard neither == nil else { return nil }; neither = size; continue }
            if has(#"^(?:have |had |use |used |do |did )?both\b"#, phrase) { guard both == nil else { return nil }; both = size; continue }
            guard !has(#"\bnot\b|\bor\b"#, phrase) else { return nil }
            sets.append((size, phrase.split(separator: " ").map(String.init), fact[2]))
        }
        guard sets.count == 2 else { return nil }
        // The words that tell the two apart: "football" and "sport", "train" and "car".
        let stop: Set<String> = ["a", "an", "the", "in", "part", "of"]
        let keys = [Set(sets[0].words).subtracting(sets[1].words).subtracting(stop), Set(sets[1].words).subtracting(sets[0].words).subtracting(stop)]
        guard !keys[0].isEmpty, !keys[1].isEmpty else { return nil }
        func names(_ key: Set<String>, in phrase: String) -> Bool {
            phrase.lowercased().split(whereSeparator: { !$0.isLetter }).contains { word in
                key.contains { $0 == word || ($0.count >= 5 && word.count >= 4 && $0.hasPrefix(String(word.prefix(4))) && String(word).hasPrefix(String($0.prefix(4)))) }
            }
        }
        // Regions: 0 first only, 1 second only, 2 both, 3 neither.
        var rows: [[Fraction]] = [[1, 1, 1, 1].map { Fraction($0, 1) } + [Fraction(total, 1)],
                                  [1, 0, 1, 0].map { Fraction($0, 1) } + [Fraction(sets[0].count, 1)],
                                  [0, 1, 1, 0].map { Fraction($0, 1) } + [Fraction(sets[1].count, 1)]]
        if let neither { rows.append([0, 0, 0, 1].map { Fraction($0, 1) } + [Fraction(neither, 1)]) }
        if let both { rows.append([0, 0, 1, 0].map { Fraction($0, 1) } + [Fraction(both, 1)]) }
        guard let solved = solveLinear(rows, unknowns: 4) else { return nil }
        var counts: [Int] = []
        for value in solved {
            guard let value, value.denominator == 1, value.numerator >= 0 else { return nil }
            counts.append(value.numerator)
        }
        // A phrase as regions: each set named, with "not" before it or not.
        func regions(_ phrase: String) -> [Int]? {
            let lower = phrase.lowercased()
            if has(#"\bexactly one\b|\bonly one\b"#, lower) { return [0, 1] }
            if has(#"\bneither\b"#, lower) { return [3] }
            // "studies both French and Spanish": both of them, where nothing is said not to be.
            if has(#"\bboth\b"#, lower), !has(#"\b(?:not|n't|no|or|neither|only|one)\b"#, lower), (0..<2).allSatisfy({ names(keys[$0], in: lower) }) { return [2] }
            var inside: Set<Int> = [], outside: Set<Int> = []
            for part in lower.components(separatedBy: " but ") {
                // Both named in one part ("football does not play a sport"): no telling which "not" is for.
                guard (0..<2).filter({ names(keys[$0], in: part) }).count <= 1 else { return nil }
                for set in 0..<2 where names(keys[set], in: part) {
                    if has(#"\b(?:not|n't|no)\b"#, part) { outside.insert(set) } else { inside.insert(set) }
                }
            }
            guard !inside.isEmpty || !outside.isEmpty, inside.isDisjoint(with: outside) else { return nil }
            if has(#"\bor\b"#, lower) { return nil }
            let memberships: [[Bool]] = [[true, false], [false, true], [true, true], [false, false]]
            return (0..<4).filter { r in inside.allSatisfy { memberships[r][$0] } && outside.allSatisfy { !memberships[r][$0] } }
        }
        func sum(_ rs: [Int]) -> Int { rs.reduce(0) { $0 + counts[$1] } }
        let fill = Step("Fill in the Venn diagram", "\(sets[0].said) only \(counts[0]), \(sets[1].said) only \(counts[1]), both \(counts[2]), neither \(counts[3]): \(total) in all.")
        let tail = #"(.+?)(?:\.|\?|$)"#
        var expr: Expr, size: Double, step: Step
        if let two = groups(#"\btwo (?:people|[a-z]+) are chosen at random from those who (.+?)\. "#, in: text),
           let asked = groups(#"\bprobability that both (?:these |of these |of them )?(?:[a-z]+ )?(?:also )?\#(tail)"#, in: text),
           let pool = regions(two[1]), let event = regions(asked[1]) {
            let n = sum(pool), m = sum(pool.filter(event.contains))
            guard n >= 2 else { return nil }
            expr = Expr.integer(m) / .integer(n) * (Expr.integer(max(m - 1, 0)) / .integer(n - 1)); size = Double(m * (m - 1)) / Double(n * (n - 1))
            step = Step("Both from the same group", "\(m) of the \(n) who \(two[1]) also \(asked[1]). The second is one of those left.")
        } else if has(#"\btwo of the \d+ [a-z]+ are chosen at random\b"#, text),
                  let asked = groups(#"\bprobability that one of (?:these|them|the) (?:two )?[a-z]* ?(.+?) and the other (.+?)(?:\.|\?|$)"#, in: text),
                  let first = regions(asked[1]), let second = regions(asked[2]), Set(first).isDisjoint(with: second) {
            let a = sum(first), b = sum(second)
            if let two = groups(#"\btwo of the (\d+)\b"#, in: text) { used.append(two[1]) }
            expr = .two * (Expr.integer(a) / .integer(total)) * (Expr.integer(b) / .integer(total - 1)); size = 2 * Double(a * b) / Double(total * (total - 1))
            step = Step("One of each, either way round", "\(a) and \(b) of the \(total). The first can be either kind, so it's twice the chance of one order.")
        } else if let (from, asked) = conditional(text), let pool = regions(from[1]), let event = regions(asked[1]) {
            let n = sum(pool), m = sum(pool.filter(event.contains))
            guard n > 0 else { return nil }
            expr = Expr.integer(m) / .integer(n); size = Double(m) / Double(n)
            step = Step("Only those it's chosen from", "\(n) \(from[1]); \(m) of them \(asked[1]).")
        } else if let asked = groups(#"\bprobability that (?:this person |they |he |she |the [a-z]+ |this [a-z]+ )(?:had |have |has )?(.+?)(?:\.|\?|$)"#, in: text),
                  has(#"\b(?:one|an?) (?:of (?:these|the) (?:\d+ )?)?[a-z]+ (?:is )?chosen at random\b"#, text), let event = regions(asked[1]) {
            let m = sum(event)
            expr = Expr.integer(m) / .integer(total); size = Double(m) / Double(total)
            step = Step("Out of everyone", "\(m) of the \(total).")
        } else {
            return nil
        }
        if let one = groups(#"\bone of these (\d+)\b"#, in: text) { used.append(one[1]) }
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: false)
        problem.lead = [fill, step]
        return Found(problem: problem, used: used, size: size)
    }

    /// Solves equations, each row the numbers each unknown is multiplied by, then what it comes
    /// to. Nil when they can't all be true; otherwise each unknown's value, or nil where the
    /// equations leave it open.
    private static func solveLinear(_ rows: [[Fraction]], unknowns n: Int) -> [Fraction?]? {
        var m = rows, pivots: [Int] = [], r = 0
        for c in 0..<n where r < m.count {
            guard let p = (r..<m.count).first(where: { !m[$0][c].isZero }) else { continue }
            m.swapAt(r, p)
            let lead = m[r][c]
            m[r] = m[r].map { $0 / lead }
            for i in m.indices where i != r && !m[i][c].isZero {
                let f = m[i][c]
                m[i] = zip(m[i], m[r]).map { $0 - f * $1 }
            }
            pivots.append(c); r += 1
        }
        for i in r..<m.count where !m[i][n].isZero { return nil }
        var values = [Fraction?](repeating: nil, count: n)
        for (i, c) in pivots.enumerated() where !(0..<n).contains(where: { $0 != c && !m[i][$0].isZero }) { values[c] = m[i][n] }
        return values
    }

    private static func groupsExact(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func everyExact(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    // MARK: Pieces

    /// A chance written as a fraction, a decimal or a percentage.
    private static func chance(_ text: String) -> Fraction? {
        let plain = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        var found: Fraction?
        if plain.hasSuffix("%"), let whole = fraction(String(plain.dropLast())) { found = whole * Fraction(1, 100) } else { found = fraction(plain) }
        guard let p = found, p.numerator >= 0, p.numerator <= p.denominator else { return nil }
        return p
    }

    private static func fraction(_ text: String) -> Fraction? {
        let parts = text.split(separator: "/")
        if parts.count == 2, let top = Int(parts[0]), let bottom = Int(parts[1]), bottom > 0 { return Fraction(top, bottom) }
        let decimal = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1, decimal.count <= 2, let whole = Int(decimal[0].isEmpty ? "0" : String(decimal[0])) else { return nil }
        guard decimal.count == 2 else { return Fraction(whole, 1) }
        guard decimal[1].count <= 6, let tail = Int(decimal[1]) else { return nil }
        let scale = Int(pow(10, Double(decimal[1].count)))
        return Fraction(whole * scale + tail, scale)
    }

    /// The chance as maths, written the way the question wrote it: 0.4 when it gave 0.6.
    private static func shown(_ p: Fraction, like stated: String) -> Expr {
        stated.contains(".") || stated.hasSuffix("%") ? (Parser.expression(decimal(p)) ?? p.expr) : p.expr
    }

    private static func written(_ stated: String, _ p: Fraction) -> Expr {
        stated.contains(".") ? (Parser.expression(stated) ?? p.expr) : p.expr
    }

    private static func decimal(_ p: Fraction) -> String {
        let value = Double(p.numerator) / Double(p.denominator)
        return String(format: "%.10g", value)
    }

    /// "1 green disc and 4 yellow discs": each colour with how many.
    private static func counted(_ text: String, noun: String = "[a-z]+") -> [(colour: String, count: Int)]? {
        let pieces = every(#"\b(\#(amount)) ([a-z]+) \#(noun)\b"#, in: text)
        guard pieces.count >= 2 else { return nil }
        var items: [(colour: String, count: Int)] = []
        for piece in pieces {
            guard let size = count(piece[1]) else { return nil }
            items.append((piece[2].lowercased(), size))
        }
        // Two of the same colour would be a misreading.
        guard Set(items.map { single($0.colour) }).count == items.count else { return nil }
        return items
    }

    /// How many, in figures or words.
    private static let amount = #"\d+|no|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|an?"#

    private static let words = ["no": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "a": 1, "an": 1, "both": 2]

    private static func count(_ text: String) -> Int? { Int(text) ?? words[text.lowercased()] }

    /// A word without a plural s: "tails" and "tail", "discs" and "disc".
    private static func single(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("ies") { return String(lower.dropLast(3)) + "y" }
        if lower.hasSuffix("es"), lower.dropLast(2).hasSuffix("x") || lower.dropLast(2).hasSuffix("sh") { return String(lower.dropLast(2)) }
        return lower.hasSuffix("s") && !lower.hasSuffix("ss") ? String(lower.dropLast()) : lower
    }

    /// Every number written in the question's sentences.
    private static func numbers(in text: String) -> [String] {
        every(#"(?<![\w.])\d+(?:\.\d+)?(?:/\d+)?%?(?![\w])"#, in: text).map(\.[0]).filter { !$0.isEmpty }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        let tidy = { (s: String) in s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "") }
        if tidy(a) == tidy(b) { return true }
        guard let x = fraction(tidy(a).replacingOccurrences(of: "%", with: "")), let y = fraction(tidy(b).replacingOccurrences(of: "%", with: "")) else { return false }
        return x == y && a.hasSuffix("%") == b.hasSuffix("%")
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

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A fraction kept exact, for chances.
    private struct Fraction: Equatable {
        var numerator: Int
        var denominator: Int

        init(_ numerator: Int, _ denominator: Int) {
            func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? max(abs(a), 1) : gcd(b, a % b) }
            let shared = gcd(numerator, denominator) * (denominator < 0 ? -1 : 1)
            self.numerator = numerator / shared
            self.denominator = denominator / shared
        }

        var double: Double { Double(numerator) / Double(denominator) }
        var expr: Expr { denominator == 1 ? .integer(numerator) : .integer(numerator) / .integer(denominator) }

        static func + (a: Fraction, b: Fraction) -> Fraction { Fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator) }
        static func - (a: Fraction, b: Fraction) -> Fraction { Fraction(a.numerator * b.denominator - b.numerator * a.denominator, a.denominator * b.denominator) }
        static func * (a: Fraction, b: Fraction) -> Fraction { Fraction(a.numerator * b.numerator, a.denominator * b.denominator) }
        static func / (a: Fraction, b: Fraction) -> Fraction { Fraction(a.numerator * b.denominator, a.denominator * b.numerator) }
        var isZero: Bool { numerator == 0 }
        /// Multiplied by another, so many times over.
        func times(_ other: Fraction, _ count: Int) -> Fraction { (0..<max(count, 0)).reduce(self) { f, _ in f * other } }
    }
}

