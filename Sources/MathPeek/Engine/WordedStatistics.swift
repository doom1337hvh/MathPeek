import Foundation

/// Statistics asked in words: a mean from a frequency table or from grouped data, medians and quartiles, a mean that changes when a value is added or taken away,
/// numbers read from a cumulative frequency table, estimates from part of a class, relative frequencies as the trials go on, a stratified sample.
/// A table has to be read whole: where the numbers read don't fill it, or can't be told apart, nothing is given.
/// Tried after `Worded.problem`, on the same text: the lines of the question the pointer is
/// in, joined by line breaks. Nil unless the whole of the question is understood.
enum WordedStatistics {
    static func problem(_ input: String) -> Problem? {
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = cleaned(display)
        guard !lines.isEmpty else { return nil }
        let text = lines.joined(separator: " ")
        guard text.count <= 1200 else { return nil }
        // "Complete the table" is answered only where the table's empty cells are numbers to work out.
        let completing = every(#"\bcomplete the table\b"#, in: text).count
        // "Complete the cumulative frequency table": the running totals of a grouped table.
        let cumulative = every(#"\bcomplete the cumulative frequency table\b"#, in: text).count
        // A table of running totals to read a number from: "Cumulative frequency" heads a column, and nothing is to be drawn from it.
        let running = cumulative == 0 && has(#"\bcumulative frequency\b"#, text) && !has(#"\bcumulative frequency (?:graph|diagram|curve|polygon|chart)\b"#, text)
        var rest = text.replacingOccurrences(of: #"\bcomplete the table\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        if cumulative > 0 || running { rest = rest.replacingOccurrences(of: #"\bcomplete the cumulative frequency table\b|\bcumulative\b"#, with: "", options: [.regularExpression, .caseInsensitive]) }
        guard !has(refusal, rest), asks(in: text) + completing + cumulative == 1 else { return nil }
        var found: Problem?
        if cumulative == 1 {
            found = grouped(lines, text, cumulative: true)
        } else if running {
            // (Its numbers aren't frequencies: no other kind may read them.)
            found = completing == 0 ? runningTotals(lines, text) : nil
        } else if completing == 1 {
            found = probabilities(lines, text, completing: true) ?? listTable(lines, text)
        } else {
            let kinds: [([String], String) -> Problem?] = [{ grouped($0, $1) }, runningRelative, twoRates, valueTable, stratified, fromAverages, missingFromMean, changedMean, sampled, ordered, categories, pie, recaptured,
                                                           { probabilities($0, $1, completing: false) }, relative, restMean, groupMeans]
            for kind in kinds where found == nil { found = kind(lines, text) }
        }
        found?.text = display
        return found
    }

    // MARK: Reading the question

    /// Words that mean the question wants something other than a number worked out.
    private static let refusal = #"\bdraw\b|\bhistogram\b|\bshow that\b|\bexplain\b|\bwhy\b|\btick\b|\breasons?\b|\bcumulative\b|\bplot\b|\bsketch\b|\bcomplete the\b|\bis (?:he|she|it|this|that) (?:right|correct)\b|\bcriticis"#

    /// The sentences that ask for something: there has to be exactly one, or a part the
    /// pointer isn't on is in view and might be the one meant.
    private static func asks(in text: String) -> Int {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // "Saffron wants to work out an estimate for …" tells what the question is about; it doesn't ask.
        // ("190 people were asked how much they spent" says what the table is about.)
        return sentences.filter { !has(#"\bassumptions?\b"#, $0) }.filter { has(#"(?<!\bwants to |\bwant to |\bwanted to |\bis going to |\bare going to |\btrying to |\basked |\brecorded |\bshows |\babout )\b(?:work out|write down|write (?:these|the)|put (?:these|the)|arrange|find|calculate|what is|what was|what were|what percentage|what fraction|how many|how much|which class|which group|circle the|estimate the (?:number|fraction|percentage|proportion|probability)|estimate how many)\b"#, $0) }.count
    }

    /// The question's lines with the signs exam papers use made plain, and without the page's
    /// margin notes, footers and the marks.
    private static func cleaned(_ input: String) -> [String] {
        var raw = input
        let swaps: [(String, String)] = [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "),
                                         ("⩽", "≤"), ("<=", "≤"), ("⩾", "≥"), (">=", "≥"), ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""),
                                         // Letters read in the Cyrillic alphabet that look like Latin ones.
                                         ("х", "x"), ("Х", "X"), ("о", "o"), ("О", "O"), ("а", "a"), ("А", "A"), ("с", "c"), ("С", "C"), ("р", "p"),
                                         ("Р", "P"), ("у", "y"), ("е", "e"), ("Е", "E"), ("В", "B"), ("М", "M"), ("Т", "T"), ("к", "k"), ("З", "3"), ("з", "3")]
        for (from, to) in swaps { raw = raw.replacingOccurrences(of: from, with: to) }
        return raw.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                // A question's number in front of its first line: "8 The table shows …", "15 A bag contains discs."
                .replacingOccurrences(of: #"^\d{1,2}(?: ?\([a-h]\))? (?=[A-Z][a-z]|A [a-z])"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" ?\[\d+ marks?\]"#, with: "", options: .regularExpression)
                // Edexcel's margin and footer: "DO NOT WRITE IN THIS AREA", "(Total for Question 14 is 3 marks)".
                .replacingOccurrences(of: #"(?:DO NOT WRITE )?IN THIS AREA ?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" ?\(Total for Question \d+ is \d+ marks?\)"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespaces)
        }.filter { line in
            !line.isEmpty
                && !has(#"^(?:do not(?: write)?|outside(?: the)?|box|bo:?|turn over.*|answer\b.*|pmt)$"#, line)
                && !has(#"IB/M/|8300/"#, line)
                // The margin note cut short: "Do not v", "Lo not".
                && !has(#"^[•. ]*[DL]o not(?: [a-z]{1,5})?$"#, line)
                // "[3 marks]", and how it is misread: "14 marks1", "IA marbal", "11 markol".
                && !has(#"^[\[\(|]?\s*\S{1,2}\s*mar[a-z]*\W*\S?\]?\|?$"#, line)
                // The marks as Edexcel and OCR print them: "(3)", "[2]".
                && !has(#"^[\[\(]\d{1,2}[\]\)]$"#, line)
        }
    }

    // MARK: Pieces

    private static let number = #"\d+(?:\.\d+)?"#

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

    /// Every number written in a piece of text, in order.
    private static func numbers(in text: String) -> [Double] {
        every(#"(?<![\d.])\d+(?:\.\d+)?"#, in: text).compactMap { Double($0[0]) }
    }

    /// A line that is only a question's number or a part's letter: "14", "13 (b)", "(a)".
    private static func isLabel(_ line: String) -> Bool {
        has(#"^(?:\d{1,2}(?: ?\(?[a-h]{1,2}\)?)?|\(?[a-h]\))$"#, line)
    }

    /// A number as it's written: whole where it is, a decimal otherwise, with no rounding noise.
    private static func plain(_ value: Double) -> Expr {
        let tidy = Double(String(format: "%.10g", value)) ?? value
        if abs(tidy - tidy.rounded()) < 1e-9, abs(tidy) < 1e15 { return .integer(Int(tidy.rounded())) }
        return .number(.real(tidy))
    }

    private static func written(_ value: Double) -> String { Format.text(plain(value)) }

    private static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 * max(1, abs(a), abs(b)) }

    private static let counts = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]

    private static func count(_ word: String) -> Int? { Int(word) ?? counts[word.lowercased()] }

    private static func made(_ expr: Expr, decimals: Bool, _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: decimals)
        problem.lead = lead
        return problem
    }

    private static func told(_ question: String, _ answer: String, _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .worded(question: question, answers: [MathLine(.symbol(answer))]), text: "", usesDecimals: false)
        problem.lead = lead
        return problem
    }

    /// The sum, where the problem is one.
    private static func sum(of problem: Problem) -> Expr? { if case .evaluate(let expr) = problem.kind { return expr }; return nil }

    /// A ÷ B as a sum the engine works out.
    private static func divided(_ top: Expr, by bottom: Expr) -> Expr { .multiply([top, .power(bottom, .minusOne)]) }

    /// The answer rounded, where the question says how.
    private static func rounding(_ problem: Problem, _ value: Double, _ text: String) -> Problem {
        guard let asked = groups(#"\bto (\d|one|two|three) (decimal places?|significant figures?|d\.p\.|s\.f\.)"#, in: text), let places = count(asked[1]) else { return problem }
        let isDecimal = asked[2].lowercased().hasPrefix("d")
        let rounded: Double
        if isDecimal {
            let scale = pow(10, Double(places))
            rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        } else {
            guard value != 0, places >= 1 else { return problem }
            let scale = pow(10, Double(places) - 1 - floor(log10(abs(value))))
            rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        }
        return made(plain(rounded), decimals: true, problem.lead + [Step("Work it out", "", [MathLine(sum(of: problem) ?? plain(value), plain(value))]),
                                                                   Step("Round it", "The answer is asked for to \(places) \(isDecimal ? "decimal place" : "significant figure")\(places == 1 ? "" : "s").")])
    }

    // MARK: A grouped frequency table

    /// One row of a grouped table: its class and how many are in it.
    private struct Row {
        var low: Double
        var high: Double?
        /// Whether the class's own sign at each end includes the end: 10 ≤ d < 20 includes 10.
        var lowSign: String?
        var highSign: String?
        var line: Int
        var frequency: Double?
    }

    /// "Work out an estimate for the mean distance", "Write down the modal class", "Which class
    /// contains the median?", "the probability that the person travels at least 10 miles",
    /// from a table of classes and frequencies.
    private static func grouped(_ given: [String], _ text: String, cumulative: Bool = false) -> Problem? {
        guard has(#"\bfrequency\b|\bnumber of\b|\bhow many\b|\btable\b"#, text) else { return nil }
        // For running totals, only the table above the instruction: the empty table below it has classes of its own.
        var lines = given
        // Where each row of the table to fill in stops: "0 < w ≤ 4", "h ≤ 160".
        var toFill: [Double] = []
        if cumulative {
            guard let cut = given.firstIndex(where: { has(#"\bcomplete the cumulative frequency table\b"#, $0) }) else { return nil }
            lines = Array(given[..<cut])
            toFill = given[(cut + 1)...].compactMap { groups("^(?:(?:\(number)|[Oo])\\s*[<≤]\\s*)?[A-Za-z]\\s*[<≤]\\s*(\(number))(?:\\s+\\d+)?$", in: $0).flatMap { Double($0[1]) } }
        }
        var rows: [Row] = [], choiceLines = Set<Int>()
        for (index, original) in lines.enumerated() {
            // A nought read as the letter O: "O<d<5". A stray mark in front of a class to circle: "_ 170 <h≤ 180".
            let line = original.replacingOccurrences(of: #"^[_•|.]+ (?=\d)"#, with: "", options: .regularExpression).replacingOccurrences(of: #"^[Oo](?=\s*[<≤])"#, with: "0", options: .regularExpression)
            // (The letter between the signs read as a one: "30<1≤35".)
            if let full = groups("^(\(number))\\s*([<≤])\\s*[A-Za-z1]\\s*([<≤])\\s*(\(number))(?:\\s+(\\d+)(?:\\s+(\(number)))?)?$", in: line), let low = Double(full[1]), let high = Double(full[4]),
               full[6].isEmpty || Double(full[6]).map({ same($0, (low + high) / 2) }) == true {
                // (A third number on the line is the class's midpoint, filled in.)
                rows.append(Row(low: low, high: high, lowSign: full[2], highSign: full[3], line: index, frequency: Double(full[5])))
            } else if let torn = groups("^(\(number))\\s*\\S{1,8}?\\s*([<≤])\\s*(\(number))$", in: line), !has(#"[a-z]{2}"#, line),
                      let low = Double(torn[1]), let high = Double(torn[3]) {
                // The middle misread: "10¿«‚X≤15".
                rows.append(Row(low: low, high: high, lowSign: nil, highSign: torn[2], line: index))
            } else if let start = groups("^(\(number))\\s*([<≤])\\s*[A-Za-z]\\s*[<≤]?\\S{0,6}$", in: line), let low = Double(start[1]) {
                // The far end misread: "5<d<1ąłś". It's where the next class starts.
                rows.append(Row(low: low, high: nil, lowSign: start[2], highSign: nil, line: index))
            }
        }
        // Classes to circle, under the question: each is one of the table's own, said again.
        var offered: [(low: Double, high: Double)] = []
        if has(#"\bcircle\b"#, text), let asked = lines.firstIndex(where: { has(#"\bcircle\b|\bwhich class\b|\bin which\b"#, $0) }) {
            for row in rows where row.line > asked && row.frequency == nil {
                guard let high = row.high, rows.contains(where: { $0.line < asked && same($0.low, row.low) && ($0.high.map { same($0, high) } ?? true) }) else { return nil }
                offered.append((row.low, high)); choiceLines.insert(row.line)
            }
            rows.removeAll { $0.line > asked && $0.frequency == nil }
            // (Several on one line, as a page's own text has them.)
            for (index, line) in lines.enumerated() where index > asked {
                let found = every("(\(number))\\s*[<≤]\\s*[A-Za-z]\\s*[<≤]\\s*(\(number))", in: line)
                guard found.count >= 2, line.replacingOccurrences(of: "\\s*\(number)\\s*[<≤]\\s*[A-Za-z]\\s*[<≤]\\s*\(number)\\s*", with: "", options: .regularExpression).isEmpty else { continue }
                offered += found.compactMap { one in Double(one[1]).flatMap { low in Double(one[2]).map { (low, $0) } } }
                choiceLines.insert(index)
            }
        }
        guard rows.count >= 2, rows.count <= 12 else { return nil }
        rows.sort { $0.low < $1.low }
        // A row to fill in that stops where no class read does: the frequency table above was only read in part.
        if cumulative, let start = rows.first?.low {
            let ends = rows.compactMap(\.high) + [start] + rows.dropFirst().map(\.low)
            guard toFill.allSatisfy({ stop in ends.contains { same($0, stop) } }) else { return nil }
        }
        // The classes run on from each other, each starting where the last one stops.
        // (Where the last class stops may be misread, "190 <h≤20łął": that only matters to a question that needs it.)
        var topUnknown = false
        for index in rows.indices {
            if index + 1 < rows.count {
                if rows[index].high == nil { rows[index].high = rows[index + 1].low }
                guard let high = rows[index].high, same(high, rows[index + 1].low) else { return nil }
            } else if rows[index].high == nil, index > 0, let before = rows[index - 1].high {
                topUnknown = true
                rows[index].high = rows[index].low + (before - rows[index - 1].low)
            }
            guard let high = rows[index].high, high > rows[index].low else { return nil }
        }
        let first = rows.map(\.line).min()!, last = rows.map(\.line).max()!

        // The frequencies: numbers on lines of their own among the classes (the first may be
        // just above them), in the order they're read.
        let window = max(0, first - 1)...min(lines.count - 1, last + 1)
        var candidates: [(line: Int, size: Double)] = []
        for index in window where rows.allSatisfy({ $0.line != index }) {
            if has(#"^\d+$"#, lines[index]), let size = Double(lines[index]) { candidates.append((index, size)) }
        }
        // (A midpoint column read as numbers of its own, mixed in with the frequencies, makes the pairing
        // of frequencies with classes unsure: such a table gives nothing.)
        if has(#"\bmid-?points?\b"#, text), candidates.contains(where: { found in rows.contains { row in row.high.map { same(found.size, (row.low + $0) / 2) } ?? false } }) { return nil }
        // What the frequencies should add up to: "Total = 120", "120 students", "100 people were asked".
        var outside: [Double] = []
        for (index, line) in lines.enumerated() where !window.contains(index) || has(#"[a-z]{3}"#, line) {
            guard !isLabel(line), rows.allSatisfy({ $0.line != index }), !choiceLines.contains(index) else { continue }
            outside += numbers(in: line)
        }
        let stated = Set(outside.filter { $0 == $0.rounded() && $0 > 0 })
        let sizes: [Double]
        if rows.allSatisfy({ $0.frequency != nil }) {
            sizes = rows.map { $0.frequency! }
        } else {
            guard rows.allSatisfy({ $0.frequency == nil }) else { return nil }
            var runs: [[Double]] = []
            if candidates.count >= rows.count {
                for start in 0...(candidates.count - rows.count) {
                    let run = candidates[start..<(start + rows.count)].map(\.size)
                    if stated.isEmpty || stated.contains(run.reduce(0, +)) { runs.append(run) }
                }
            }
            if stated.isEmpty {
                // With nothing to check them against, they have to sit one by one beside their classes.
                guard candidates.count == rows.count, zip(rows, candidates).allSatisfy({ $1.line == $0.line + 1 || $1.line == $0.line - 1 }) else { return nil }
            }
            guard runs.count == 1 else { return nil }
            sizes = runs[0]
        }
        for index in rows.indices { rows[index].frequency = sizes[index] }
        let total = sizes.reduce(0, +)
        guard total > 0 else { return nil }
        var used: [Double] = [total]
        func name(_ row: Row) -> String {
            let left = row.lowSign ?? (rows.contains { $0.lowSign == "≤" } ? "≤" : "<")
            let right = row.highSign ?? (rows.contains { $0.highSign == "≤" } ? "≤" : "<")
            let letter = groups(#"[<≤]\s*([A-Za-z])\s*[<≤]"#, in: lines[row.line])?[1] ?? rows.compactMap { groups(#"[<≤]\s*([A-Za-z])\s*[<≤]"#, in: lines[$0.line])?[1] }.first ?? "x"
            return "\(written(row.low)) \(left) \(letter) \(right) \(written(row.high!))"
        }
        // How many are between two values. A class cut by one of them is taken to be spread
        // evenly, so the same share of its frequency is counted: nil where that isn't a whole number of them.
        func portion(_ from: Double, _ to: Double) -> (count: Double, lines: [MathLine])? {
            var count = 0.0, working: [MathLine] = []
            for row in rows {
                let overlap = min(to, row.high!) - max(from, row.low), width = row.high! - row.low
                guard overlap > 1e-9 else { continue }
                let part = overlap / width * row.frequency!
                count += part
                if same(overlap, width) { working.append(MathLine(.symbol(name(row)), plain(row.frequency!))) }
                else { working.append(MathLine(.symbol(name(row)), .multiply([divided(plain(overlap), by: plain(width)), plain(row.frequency!)]), plain(part))) }
            }
            guard !working.isEmpty, abs(count - count.rounded()) < 1e-9 else { return nil }
            return (count.rounded(), working)
        }
        let isEdge = { (value: Double) in rows.contains { same($0.low, value) || same($0.high!, value) } }
        let asking = sentences(lines, prose: true).last(where: { has(#"\b(?:how many|work out|find|calculate|write down|what|estimate)\b"#, $0) }) ?? text
        let table = rows.map { "\(name($0)): \(written($0.frequency!))" }.joined(separator: "; ")

        var answer: Problem?
        let running = rows.reduce(into: (0.0, [Double]())) { $0.0 += $1.frequency!; $0.1.append($0.0) }.1
        if topUnknown, !cumulative, !has(#"\b(?:median|lower quartile|upper quartile)\b"#, text) || has(#"\bestimate\b|\bmean\b"#, text) { return nil }
        if cumulative {
            // Each class's running total, from the top.
            answer = told("cumulative frequencies", running.map(written).joined(separator: ", "),
                          [Step("Add up as you go", "Each cumulative frequency is that class's frequency added to all the ones before it.",
                                rows.indices.map { MathLine(.add(sizes[...$0].map(plain)), plain(running[$0])) })])
        } else if has(#"\bestimate (?:for|of) the mean\b|\bestimated mean\b"#, text) {
            let middles = rows.map { ($0.low + $0.high!) / 2 }
            let products = zip(middles, sizes).map { $0 * $1 }
            let sum = products.reduce(0, +)
            let lead = [Step("Take the middle of each class", "Nobody knows the values inside a class, so each one is taken to be at the class's midpoint.",
                             zip(middles, sizes).map { MathLine(.multiply([plain($0), plain($1)]), plain($0 * $1)) }),
                        Step("Add them up", "The total of midpoint × frequency, and the total frequency.",
                             [MathLine(.add(products.map(plain)), plain(sum)), MathLine(.add(sizes.map(plain)), plain(total))]),
                        Step("Share out", "The estimate of the mean is the first total divided by the second.")]
            answer = rounding(made(divided(plain(sum), by: plain(total)), decimals: true, lead), sum / total, text)
        } else if has(#"\bmodal (?:class|group)\b"#, text) {
            guard let most = sizes.max(), sizes.filter({ $0 == most }).count == 1, let row = rows.first(where: { $0.frequency == most }) else { return nil }
            answer = told("modal class", name(row), [Step("Find the biggest frequency", "The modal class is the one with the most in it: \(written(most)).")])
        } else if let asked = groups(#"\b(?:class|group|interval)\b[a-z ]{0,25}\b(?:contains?|containing|has)\b[a-z ]{0,10}\b(median|lower quartile|upper quartile)\b|\b(median) (?:class|group)\b|\bin which (?:class|group)(?: interval)? is the (median|lower quartile|upper quartile)\b"#, in: text) {
            // Where the median (or a quartile) falls: n/2 and (n + 1)/2 (n/4 and (n + 1)/4, …) have to be in the same class.
            let which = (asked[1] + asked[2] + asked[3]).lowercased()
            let share = which == "median" ? 0.5 : (which == "lower quartile" ? 0.25 : 0.75)
            let low = total * share, high = (total + 1) * share
            var start = 0.0, found: Row?
            for (index, row) in rows.enumerated() {
                if low > start, high <= running[index] { found = row; break }
                if low > start, low <= running[index] { return nil }
                start = running[index]
            }
            guard let row = found, !(topUnknown && row.line == rows[rows.count - 1].line) else { return nil }
            // One of the classes to circle, where there are any.
            guard offered.isEmpty || offered.contains(where: { same($0.low, row.low) && same($0.high, row.high!) }) else { return nil }
            answer = told("class containing the \(which)", name(row),
                          [Step("Find the place", "There are \(written(total)) in all, so the \(which) is about the \(written(high))th value.",
                                [MathLine(.symbol("running totals"), .symbol(running.map(written).joined(separator: ", ")))]),
                           Step("See which class it falls in", "The running totals pass \(written(high)) in \(name(row)).")])
        } else if let span = groups("\\bbetween\\s+£?(\(number))(?:\\s?[a-z]+)?\\s+and\\s+£?(\(number))", in: asking), let from = Double(span[1]), let to = Double(span[2]),
                  has(#"\bfraction\b|\bprobability\b|\bpercentage\b|\bhow many\b|\bnumber of\b"#, asking) {
            // "Work out an estimate for the fraction of these 150 people who were in the shop for between 20 minutes and 40 minutes."
            guard from < to, from >= rows[0].low - 1e-9, to <= rows[rows.count - 1].high! + 1e-9 else { return nil }
            // An end inside a class is only ever an estimate.
            guard (isEdge(from) && isEdge(to)) || has(#"\bestimate\b"#, asking) else { return nil }
            guard let part = portion(from, to) else { return nil }
            used += [from, to]
            let cut = !(isEdge(from) && isEdge(to))
            let pick = Step("Pick out the classes", "Between \(written(from)) and \(written(to))." + (cut ? " A class that is only partly between them is taken to be spread evenly, so that share of its frequency is counted." : ""),
                            part.lines + [MathLine(.symbol("altogether"), plain(part.count))])
            if has(#"\bfraction\b|\bprobability\b"#, asking) {
                answer = made(divided(plain(part.count), by: plain(total)), decimals: false,
                              [pick, Step("Out of all of them", "\(written(part.count)) out of the \(written(total)) altogether.")])
            } else if has(#"\bpercentage\b"#, asking) {
                answer = made(.multiply([divided(plain(part.count), by: plain(total)), .integer(100)]), decimals: true,
                              [pick, Step("As a percentage", "Divide by the \(written(total)) altogether and times by 100.")])
            } else {
                answer = made(plain(part.count), decimals: false, [pick])
            }
        } else if let part = groups("\\b(at least|more than|over|greater than|less than|under|fewer than|at most|no more than)\\s+£?(\(number))", in: text),
                  let edge = Double(part[2]), !isEdge(edge), edge > rows[0].low, edge < rows[rows.count - 1].high!,
                  has(#"\bestimate\b"#, asking), has(#"\bfraction\b|\bprobability\b|\bpercentage\b|\bhow many\b|\bnumber of\b"#, asking) {
            // "Work out an estimate for the number of people who took more than 25 minutes": the class 20 to 30 is cut.
            let word = part[1].lowercased()
            let above = ["at least", "more than", "over", "greater than"].contains(word)
            guard let found = above ? portion(edge, rows[rows.count - 1].high!) : portion(rows[0].low, edge) else { return nil }
            used.append(edge)
            let pick = Step("Pick out the classes", "\(word.prefix(1).uppercased() + word.dropFirst()) \(written(edge)). The class \(written(edge)) is inside is taken to be spread evenly, so that share of its frequency is counted.",
                            found.lines + [MathLine(.symbol("altogether"), plain(found.count))])
            if has(#"\bfraction\b|\bprobability\b"#, asking) {
                answer = made(divided(plain(found.count), by: plain(total)), decimals: false,
                              [pick, Step("Out of all of them", "\(written(found.count)) out of the \(written(total)) altogether.")])
            } else if has(#"\bpercentage\b"#, asking) {
                answer = made(.multiply([divided(plain(found.count), by: plain(total)), .integer(100)]), decimals: true,
                              [pick, Step("As a percentage", "Divide by the \(written(total)) altogether and times by 100.")])
            } else {
                answer = made(plain(found.count), decimals: false, [pick])
            }
        } else if let part = groups("\\b(at least|more than|over|greater than|less than|under|fewer than|at most|no more than)\\s+£?(\(number))", in: text),
                  let edge = Double(part[2]), has(#"\bprobability\b|\bhow many\b|\bpercentage\b"#, text) {
            let word = part[1].lowercased()
            let above = ["at least", "more than", "over", "greater than"].contains(word)
            // Which end of a class the words take in: "at least 10" goes with 10 ≤ d, "more than 10" with 10 < d.
            let wantsLowerIncluded = ["at least", "less than", "under", "fewer than"].contains(word)
            let lowerSeen = rows.compactMap(\.lowSign).contains("≤"), upperSeen = rows.compactMap(\.highSign).contains("≤")
            if wantsLowerIncluded, upperSeen { return nil }
            if !wantsLowerIncluded, lowerSeen { return nil }
            guard rows.contains(where: { same($0.low, edge) }) || rows.contains(where: { same($0.high!, edge) }) else { return nil }
            let chosen = rows.filter { above ? $0.low >= edge - 1e-9 : $0.high! <= edge + 1e-9 }
            guard !chosen.isEmpty, chosen.count < rows.count else { return nil }
            let inside = chosen.map { $0.frequency! }
            let some = inside.reduce(0, +)
            used.append(edge)
            let pick = Step("Pick out the classes", "\(word.prefix(1).uppercased() + word.dropFirst()) \(written(edge)) is \(chosen.map(name).joined(separator: " and ")).",
                            [MathLine(.add(inside.map(plain)), plain(some))])
            if has(#"\bprobability\b"#, text) {
                answer = made(divided(plain(some), by: plain(total)), decimals: false,
                              [pick, Step("Out of all of them", "The probability is how many of them out of the \(written(total)) altogether.")])
            } else if has(#"\bpercentage\b"#, text) {
                answer = made(.multiply([divided(plain(some), by: plain(total)), .integer(100)]), decimals: true,
                              [pick, Step("As a percentage", "Divide by the \(written(total)) altogether and times by 100.")])
            } else {
                answer = made(plain(some), decimals: false, [pick])
            }
        }
        guard var problem = answer else { return nil }
        if let places = groups(#"\bto (\d) (?:decimal places?|significant figures?|d\.p\.|s\.f\.)"#, in: text), let size = Double(places[1]) { used.append(size) }
        // Every number outside the table is the total, or what the question asks about.
        guard outside.allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
        problem.lead.insert(Step("Read the table", "", [MathLine(.symbol(table))]), at: 0)
        return problem
    }

    // MARK: A cumulative frequency table

    /// "190 people were asked how much they spent. [0 < x ≤ 10: 16, 0 < x ≤ 20: 64, 0 < x ≤ 30: 140,
    /// 0 < x ≤ 40: 184, 0 < x ≤ 50: 190] How many people spent more than £20?" Each row counts
    /// everyone up to where it stops, so the answer is one row's number, or the rest of them all.
    private static func runningTotals(_ lines: [String], _ text: String) -> Problem? {
        // Rows: "0 < x ≤ 20" (all starting at the same place) or "x ≤ 20", with the running total on the line or on one beside it.
        var rows: [(high: Double, sign: String, line: Int, total: Double?, low: Double?, letter: String)] = []
        for (index, original) in lines.enumerated() {
            let line = original.replacingOccurrences(of: #"^[Oo](?=\s*[<≤])"#, with: "0", options: .regularExpression)
            if let full = groups("^(\(number))\\s*[<≤]\\s*([A-Za-z])\\s*([<≤])\\s*(\(number))(?:\\s+(\\d+))?$", in: line), let low = Double(full[1]), let high = Double(full[4]) {
                rows.append((high, full[3], index, Double(full[5]), low, full[2]))
            } else if let short = groups("^([A-Za-z])\\s*([<≤])\\s*(\(number))(?:\\s+(\\d+))?$", in: line), let high = Double(short[3]) {
                rows.append((high, short[2], index, Double(short[4]), nil, short[1]))
            }
        }
        guard rows.count >= 2, rows.count <= 12 else { return nil }
        // Read from the top down, each stopping further on than the last, all written the same way.
        guard zip(rows, rows.dropFirst()).allSatisfy({ $0.high < $1.high && $0.line < $1.line && $0.sign == $1.sign }) else { return nil }
        guard rows.allSatisfy({ $0.low == nil }) || rows.allSatisfy({ $0.low != nil && same($0.low!, rows[0].low!) && $0.low! < rows[0].high }) else { return nil }
        let first = rows[0].line, last = rows[rows.count - 1].line
        let window = max(0, first - 1)...min(lines.count - 1, last + 1)
        var totals: [Double] = []
        if rows.allSatisfy({ $0.total != nil }) {
            totals = rows.map { $0.total! }
        } else {
            // One number beside each row, in the rows' order: a number lost, or one too many, and nothing is sure.
            guard rows.allSatisfy({ $0.total == nil }) else { return nil }
            let lone = window.filter { index in rows.allSatisfy { $0.line != index } && has(#"^\d+$"#, lines[index]) }
            guard lone.count == rows.count, zip(rows, lone).allSatisfy({ abs($0.line - $1) == 1 }) else { return nil }
            totals = lone.compactMap { Double(lines[$0]) }
        }
        // Running totals never go down.
        guard totals.count == rows.count, totals[0] >= 0, zip(totals, totals.dropFirst()).allSatisfy({ $0 <= $1 }), let whole = totals.last, whole > 0 else { return nil }
        // Every other number in the question: how many there are in all, and what's asked about.
        var outside: [Double] = []
        for (index, line) in lines.enumerated() where !window.contains(index) || has(#"[a-z]{3}"#, line) {
            guard !isLabel(line), rows.allSatisfy({ $0.line != index }) else { continue }
            outside += numbers(in: line)
        }
        let before = lines[..<first].filter { !isLabel($0) && has(#"[a-z]{3}"#, $0) }.flatMap { numbers(in: $0) }
        guard let ask = sentences(lines, prose: true).last(where: { has(#"\b(?:how many|work out|find|calculate|write down|what)\b"#, $0) }) else { return nil }
        let unit = #"(?:\s?(?:cm|mm|km|kg|m|g|s|minutes?|mins?|seconds?|hours?|years?|miles?|metres?|marks?|%|p))?"#
        var word = "", edgeText = ""
        if let after = groups("\\b(more than|over|greater than|longer than|taller than|heavier than|older than|above|at least|at most|no more than|up to|less than|under|fewer than|shorter than|lighter than|younger than|below)\\s+£?(\(number))\(unit)(?! or (?:more|less|fewer))", in: ask) {
            word = after[1].lowercased(); edgeText = after[2]
        } else if let after = groups("£?(\(number))\(unit) or (more|less|fewer)\\b", in: ask) {
            word = after[2].lowercased() == "more" ? "at least" : "at most"; edgeText = after[1]
        } else { return nil }
        guard let edge = Double(edgeText), let at = rows.firstIndex(where: { same($0.high, edge) }) else { return nil }
        let above = ["more than", "over", "greater than", "longer than", "taller than", "heavier than", "older than", "above", "at least"].contains(word)
        // "More than 20" is everyone not in "x ≤ 20"; "at least 20" is everyone not in "x < 20". The other way round can't be told.
        let needsIncluded = !["at least", "less than", "under", "fewer than", "shorter than", "lighter than", "younger than", "below"].contains(word)
        guard (rows[at].sign == "≤") == needsIncluded else { return nil }
        let upTo = totals[at]
        var used = [edge]
        // How many there are in all has to be said in the words, and be the last row's number: a row lost off the end would go unseen.
        let stated = before.contains { same($0, whole) }
        if stated { used.append(whole) }
        let wantsShare = has(#"\bprobability\b|\bfraction\b|\bpercentage\b|\bper ?cent\b|\bproportion\b"#, ask)
        guard stated || (!above && !wantsShare) else { return nil }
        if let places = groups(#"\bto (\d) (?:decimal places?|significant figures?|d\.p\.|s\.f\.)"#, in: text), let size = Double(places[1]) { used.append(size) }
        guard outside.allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
        let letter = rows[at].letter
        let table = zip(rows, totals).map { "\(letter) \($0.sign) \(written($0.high)): \(written($1))" }.joined(separator: "; ")
        var lead = [Step("Read the table", "Each number counts everyone up to the end of its row.", [MathLine(.symbol(table))])]
        let some = above ? whole - upTo : upTo
        let rest = Expr.add([plain(whole), .multiply([.minusOne, plain(upTo)])])
        let counting = above ? Step("Take away the ones up to \(written(edge))", "\(written(upTo)) of the \(written(whole)) are in \(letter) \(rows[at].sign) \(written(edge)). The rest are \(word) \(written(edge)).")
                             : Step("Find the row", "\(word.prefix(1).uppercased() + word.dropFirst()) \(written(edge)) is the row \(letter) \(rows[at].sign) \(written(edge)): \(written(upTo)).")
        if has(#"\bpercentage\b|\bper ?cent\b"#, ask) || wantsShare {
            var step = counting
            if above { step.lines = [MathLine(rest, plain(some))] }
            lead.append(step)
            if has(#"\bpercentage\b|\bper ?cent\b"#, ask) {
                lead.append(Step("As a percentage", "Divide by the \(written(whole)) altogether and times by 100."))
                return rounding(made(.multiply([divided(plain(some), by: plain(whole)), .integer(100)]), decimals: true, lead), some / whole * 100, text)
            }
            lead.append(Step("Out of all of them", "\(written(some)) out of the \(written(whole)) altogether."))
            return made(divided(plain(some), by: plain(whole)), decimals: false, lead)
        }
        guard has(#"\bhow many\b|\bnumber of\b"#, ask) else { return nil }
        lead.append(counting)
        return made(above ? rest : plain(upTo), decimals: false, lead)
    }

    // MARK: A mean that changes

    /// "The mean mass of a squad of 19 hockey players is 82 kg. A player of mass 93 kg joins
    /// the squad. Work out the mean mass of the squad now." Also a value worked back from the
    /// new mean, and the mean of two groups put together.
    private static func changedMean(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bmean\b"#, text), !has(#"\bfrequency\b|\btable\b|\bratio\b|\bset [a-z]\b|:"#, text) else { return nil }
        let kept = lines.filter { !isLabel($0) }
        var words = ""
        for (index, line) in kept.enumerated() {
            if index > 0 { words += (has(#"[.?!:,]$"#, kept[index - 1]) || !has(#"^[A-Z]"#, line)) ? " " : ". " }
            words += line
        }
        // A sentence that ends with a number and no full stop, run into the next: "is 82 kg A player of mass …".
        words = words.replacingOccurrences(of: #"(\d(?: ?(?:kg|g|cm|m|mm|km|years?|minutes?|seconds?|hours?|points?|marks?))?) (?=(?:A|An|The|One|Two|Three|Each|Another|Work|Find|Calculate|What)\b)"#,
                                           with: "$1. ", options: .regularExpression)
        let sentences = words.components(separatedBy: CharacterSet(charactersIn: ".?")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let unit = #"(?: ?(?:kg|g|cm|m|mm|km|years?|minutes?|seconds?|hours?|points?|marks?|%|£|p))?"#
        // "the mean mass of a squad of 19 hockey players is 82 kg", "12 boys have a mean height of 150 cm"
        var groupsFound: [(size: Double, mean: Double, sentence: Int)] = []
        for (index, sentence) in sentences.enumerated() {
            if let found = groups("\\bmean\\b(?! [a-z ]*\\b(?:now|new)\\b)[a-z' ]{0,40}?\\b(\\d+) ([a-z' ]{1,40}?)\\b(?:is|was|are|were) £?(\(number))\(unit)$", in: sentence) ?? groups("\\bmean\\b[a-z' ]{0,40}?\\b(\\d+) ([a-z' ]{1,40}?)\\b(?:is|was) £?(\(number))\(unit)\\b", in: sentence),
               // ("The mean of 6 other numbers is 11" is a second group; "the other numbers" asked about isn't.)
               !has(#"\b(?:now|new|remaining|other|rest|left|after)\b"#, sentence) || has(#"\b\d+ other [a-z' ]+ (?:is|was|are|were) £?\d"#, sentence), let size = Double(found[1]), let mean = Double(found[3]) {
                groupsFound.append((size, mean, index))
            } else if let found = groups("\\b(\\d+) ([a-z' ]{1,40}?) (?:have|has|had) (?:a|an) mean(?: [a-z]+)? of £?(\(number))\(unit)\\b", in: sentence),
                      !has(#"\b(?:now|new|remaining|other|rest|left|after)\b"#, sentence), let size = Double(found[1]), let mean = Double(found[3]) {
                groupsFound.append((size, mean, index))
            }
        }
        guard let ask = sentences.last(where: { has(#"\b(?:work out|find|calculate|what is|what was)\b"#, $0) }) else { return nil }
        let allNumbers = numbers(in: words)
        func usesAll(_ used: [Double]) -> Bool { allNumbers.allSatisfy { size in used.contains { same($0, size) } } }

        // Two groups put together.
        if groupsFound.count == 2, has(#"\bmean\b"#, ask), has(#"\b(?:all|whole|altogether|combined|together|both)\b"#, ask) {
            let (a, b) = (groupsFound[0], groupsFound[1])
            guard a.size == a.size.rounded(), b.size == b.size.rounded() else { return nil }
            let whole = a.size + b.size
            var used = [a.size, a.mean, b.size, b.mean, whole]
            if let named = groups(#"\ball (\d+)\b"#, in: ask), let size = Double(named[1]) { guard same(size, whole) else { return nil }; used.append(size) }
            guard usesAll(used) else { return nil }
            let first = a.size * a.mean, second = b.size * b.mean
            return made(divided(plain(first + second), by: plain(whole)), decimals: true,
                        [Step("Find each total", "The mean times how many there are is the total.",
                              [MathLine(.multiply([plain(a.size), plain(a.mean)]), plain(first)), MathLine(.multiply([plain(b.size), plain(b.mean)]), plain(second))]),
                         Step("Put them together", "Add the totals, and add how many there are.",
                              [MathLine(.add([plain(first), plain(second)]), plain(first + second)), MathLine(.add([plain(a.size), plain(b.size)]), plain(whole))]),
                         Step("Share out", "The mean of them all is the whole total divided by how many there are altogether.")])
        }

        // One group, with some joining or leaving.
        guard groupsFound.count == 1, let start = groupsFound.first, start.size == start.size.rounded(), start.size >= 2 else { return nil }
        let change = #"\b(joins?|joined|is added|are added|added|enters?|arrives?|comes in|leaves?|left|is removed|are removed|removed|is taken (?:away|out)|are taken (?:away|out)|drops? out|dropped out)\b"#
        let askIndex = sentences.lastIndex(of: ask)
        let moves = sentences.enumerated().filter { $0.offset != start.sentence && $0.offset != askIndex && has(change, $0.element) }
        guard moves.count == 1, let move = moves.first, let verb = groups(change, in: move.element)?[1].lowercased() else { return nil }
        let leaving = has(#"^(?:leaves?|left|is removed|are removed|removed|is taken|are taken|drops? out|dropped out)"#, verb)
        let values = numbers(in: move.element)
        // How many join or leave: one, unless the sentence says.
        var howMany = 1.0
        let counted = groups(#"^(?:then |and )?(two|three|four|five|six|\d+) (?:more |other |new |extra )?[a-z]+s\b"#, in: move.element)
        if let counted, let n = count(counted[1]) { howMany = Double(n) }
        let newSize = start.size + (leaving ? -howMany : howMany)
        guard newSize >= 1 else { return nil }
        let total = start.size * start.mean
        let totalLine = Step("Find the total", "The mean times how many there are is the total.", [MathLine(.multiply([plain(start.size), plain(start.mean)]), plain(total))])
        var used = [start.size, start.mean]
        if let counted, let n = Double(counted[1]) { used.append(n) }

        if has(#"\bmean\b"#, ask), !values.isEmpty {
            // The values that joined or left are given: the new mean is asked for.
            var given = values
            if let counted, let n = Double(counted[1]), let at = given.firstIndex(where: { same($0, n) }) { given.remove(at: at) }
            guard Double(given.count) == howMany || (given.count == 1 && howMany > 1 && has(#"\beach\b"#, move.element)) else { return nil }
            let moved = given.count == 1 ? given[0] * howMany : given.reduce(0, +)
            used += given + [newSize]
            guard usesAll(used) else { return nil }
            let after = leaving ? total - moved : total + moved
            let movedLine: Expr = given.count == 1 && howMany > 1 ? .multiply([plain(given[0]), plain(howMany)]) : .add(given.map(plain))
            return rounding(made(divided(plain(after), by: plain(newSize)), decimals: true,
                                 [totalLine,
                                  Step(leaving ? "Take away what left" : "Add what joined", "",
                                       [MathLine(leaving ? .add([plain(total), .multiply([.minusOne, movedLine])]) : .add([plain(total), movedLine]), plain(after))]),
                                  Step("Share out", "There are \(written(newSize)) now, so divide the new total by \(written(newSize)).")]), after / newSize, text)
        }
        if values.isEmpty, howMany == 1, !has(#"\bmean\b"#, ask) {
            // The new mean is given: the value that joined or left is asked for.
            guard let now = sentences.enumerated().first(where: { $0.offset != start.sentence && $0.offset != move.offset && $0.offset != askIndex && has(#"\bmean\b"#, $0.element) }),
                  let found = groups("\\bmean\\b[a-z' ]{0,50}?\\b(?:is|was|becomes|became|goes (?:up|down) to|(?:in|de)creases to|changes to) (?:now )?£?(\(number))\(unit)\\b", in: now.element),
                  let mean = Double(found[1]) else { return nil }
            used += [mean, newSize]
            guard usesAll(used) else { return nil }
            let after = newSize * mean
            let afterLine = Step("Find the new total", "", [MathLine(.multiply([plain(newSize), plain(mean)]), plain(after))])
            return made(leaving ? .add([plain(total), .multiply([.minusOne, plain(after)])]) : .add([plain(after), .multiply([.minusOne, plain(total)])]), decimals: true,
                        [totalLine, afterLine, Step("Find the difference", leaving ? "What left is the old total take away the new one." : "What joined is the new total take away the old one.")])
        }
        return nil
    }

    // MARK: Numbers in order

    /// "Write these numbers in descending order. 9563 9.56 × 10³ 9.56 × 3¹⁰"
    private static func ordered(_ lines: [String], _ text: String) -> Problem? {
        guard let asked = groups(#"\b(?:in|into) (descending|ascending) order\b|\border(?: of size)?,? (smallest|largest|biggest|lowest|highest) first\b|\bstart(?:ing)? with the (smallest|largest|biggest|lowest|highest)\b"#, in: text),
              let start = lines.firstIndex(where: { has(#"\border\b|\bfirst\b|\bstart(?:ing)? with\b"#, $0) }) else { return nil }
        let word = (asked[1] + asked[2] + asked[3]).lowercased()
        let falling = ["descending", "largest", "biggest", "highest"].contains(word)
        // The numbers: everything after the instruction, and on its line after the instruction's words.
        var rest = [String(lines[start].split(separator: ".", omittingEmptySubsequences: false).dropFirst().joined(separator: "."))]
        rest += lines[(start + 1)...].filter { !isLabel($0) }
        let item = #"-?\d+(?:\.\d+)?(?:\s*\^\s*\(?-?\d+\)?)?(?:\s*[×x*]\s*\d+(?:\.\d+)?(?:\s*\^\s*\(?-?\d+\)?)?)?"#
        var written: [String] = [], ended = false
        for line in rest {
            // Under the numbers: how to set the answer out, and the answer line's dots and words ("Show how you decide.", "... [3]", "smallest").
            if has(#"^(?:show how you decide|(?:you must )?show (?:all )?(?:of )?your working)\.?$"#, line) || has(#"^[. _…,]*(?:\[\d\])?$"#, line)
                || has(#"^(?:smallest|largest|biggest|lowest|highest|least|greatest)$"#, line) {
                ended = ended || !written.isEmpty
                continue
            }
            // (A number below those isn't one of the list for sure.)
            guard !ended else { return nil }
            let pieces = every(item, in: line).map { $0[0] }
            // Nothing else on the line: anything that isn't one of the numbers means it wasn't all read.
            var left = line
            for piece in pieces { if let range = left.range(of: piece) { left.removeSubrange(range) } }
            guard left.trimmingCharacters(in: CharacterSet(charactersIn: " ,;")).isEmpty else { return nil }
            written += pieces
        }
        guard written.count >= 2, written.count <= 8 else { return nil }
        if let said = groups(#"\bthese (two|three|four|five|six|seven|eight) numbers\b"#, in: text), count(said[1]) != written.count { return nil }
        // "9.56 × 103" is a power read flat (10³): a number times one of three or more digits isn't trusted.
        guard !written.contains(where: { has(#"[×x*]\s*\d{3,}(?:\.\d+)?$"#, $0) }) else { return nil }
        var items: [(shown: Expr, size: Double)] = []
        for piece in written {
            let maths = piece.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: #"(?<=\d)\s*x\s*(?=\d)"#, with: "*", options: .regularExpression)
            guard let expr = Parser.expression(maths.replacingOccurrences(of: " ", with: "")), let size = Simplify.run(expr).number?.double ?? expr.evaluate() else { return nil }
            items.append((expr, size))
        }
        // Two the same can't be put in order.
        for (index, one) in items.enumerated() where items[(index + 1)...].contains(where: { same($0.size, one.size) }) { return nil }
        let sorted = items.sorted { falling ? $0.size > $1.size : $0.size < $1.size }
        var problem = Problem(kind: .worded(question: "\(falling ? "descending" : "ascending") order", answers: [MathLine(.symbol(sorted.map { Format.text($0.shown) }.joined(separator: ", ")))]),
                              text: "", usesDecimals: false)
        problem.lead = [Step("Work each one out", "Put them all in the same form to compare them.", items.map { MathLine($0.shown, plain($0.size)) }),
                        Step("Put them in order", falling ? "Largest first." : "Smallest first.")]
        return problem
    }

    // MARK: A table of categories

    /// "Today, she made 120 calls. The table shows the results. Not answered 33 … Write down
    /// the relative frequency that a call was not answered." Also how many to expect out of
    /// a new number, and a probability.
    private static func categories(_ lines: [String], _ text: String) -> Problem? {
        // A sample scaled up to everyone: "She asks a sample of 30 students … how many of the 195 students …".
        let scaling = has(#"\bsamples?\b|\bsurvey\b"#, text) && has(#"\bhow many\b"#, text) && !has(#"\brelative frequency\b|\bprobability\b"#, text)
        guard has(#"\bfrequency\b|\btable\b"#, text), scaling || has(#"\brelative frequency\b|\bexpect\b|\bprobability\b"#, text) else { return nil }
        guard let header = lines.firstIndex(where: { has(#"\bfrequency\b|\bnumber of\b"#, $0) && !has(#"\b(?:write|work|find|what|how|relative)\b"#, $0) }) else { return nil }
        // The table runs from the header to the first line that asks something.
        let end = lines[(header + 1)...].firstIndex(where: { has(#"\b(?:write down|work out|find|calculate|what is|how many|during|using|one [a-z]+ is chosen)\b"#, $0) || has(#"[.?]$"#, $0) && $0.split(separator: " ").count > 5 }) ?? lines.count
        var names: [String] = [], sizes: [Double] = []
        // (A frequency is a number on its own line: only a part's letter is passed over.)
        for line in lines[(header + 1)..<end] where !has(#"^(?:\d{1,2} ?)?\(?[a-h]\)$"#, line) && !has(#"\bfrequency\b"#, line) {
            if let both = groups(#"^([A-Za-z][A-Za-z ,'-]*[a-z])\s+(\d+)$"#, in: line) { names.append(both[1].lowercased()); sizes.append(Double(both[2])!) }
            else if has(#"^\d+$"#, line) { sizes.append(Double(line)!) }
            else if has(#"^[A-Za-z][A-Za-z ,'-]*$"#, line), line.split(separator: " ").count <= 7 { names.append(line.lowercased()) }
            else { return nil }
        }
        guard names.count >= 2, names.count == sizes.count, Set(names).count == names.count else { return nil }
        let total = sizes.reduce(0, +)
        // The total has to be stated, and match: "Today, she made 120 calls."
        let before = lines[..<header].filter { !isLabel($0) }.joined(separator: " ")
        guard numbers(in: before).contains(where: { same($0, total) }) else { return nil }
        guard let ask = groups(#"(?:relative frequency|probability) (?:that|of)\s+(.+?)(?:\.|\?|$)|how many ([a-z ]+?) (?:does|do|will|would|should|can|might)\b[^.?]*\bexpect\b"#, in: text)
                ?? (scaling ? groups(#"()\bhow many\b([^.?]+)"#, in: text) : nil) else { return nil }
        let wanted = Set((ask[1] + " " + ask[2]).lowercased().split(separator: " ").map { stem(String($0)) })
        // The category whose words are all in what's asked ("not answered"), or, for "how many
        // sales", the one with that word and no "not" ("answered and sale made").
        func words(_ name: String) -> Set<String> { Set(name.split(whereSeparator: { !$0.isLetter }).map { stem(String($0)) }) }
        var matches = names.indices.filter { words(names[$0]).isSubset(of: wanted.union(["a", "the", "and", "but", "was", "were", "is"])) }
        if matches.isEmpty, !ask[2].isEmpty {
            matches = names.indices.filter { !words(names[$0]).isDisjoint(with: wanted) && (wanted.contains("not") || !words(names[$0]).contains("not")) }
        }
        guard matches.count == 1, let index = matches.first else { return nil }
        let size = sizes[index]
        let read = Step("Read the table", "", names.indices.map { MathLine(.symbol(names[$0]), plain(sizes[$0])) } + [MathLine(.add(sizes.map(plain)), plain(total))])
        let share = divided(plain(size), by: plain(total))
        var used = [total] + sizes
        if has(#"\bexpect\b"#, text) || scaling {
            // How many out of a new number of tries, or out of everyone the sample stands for.
            let body = lines.filter { !isLabel($0) }.joined(separator: " ")
            let fresh = Array(Set(numbers(in: body).filter { size in !used.contains { same($0, size) } }))
            guard fresh.count == 1, let tries = fresh.first else { return nil }
            used.append(tries)
            guard numbers(in: lines.filter { !isLabel($0) }.joined(separator: " ")).allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
            if scaling {
                // A number of people (or things) from a sample: only where it comes out whole.
                let value = size / total * tries
                guard abs(value - value.rounded()) < 1e-9 else { return nil }
                return made(.multiply([share, plain(tries)]), decimals: false,
                            [read, Step("Scale up the sample", "\(written(size)) out of the \(written(total)) in the sample, so the same share of all \(written(tries)).")])
            }
            return made(.multiply([share, plain(tries)]), decimals: true,
                        [read, Step("Use the relative frequency", "\(written(size)) out of \(written(total)) is the share to expect, so take that share of \(written(tries)).")])
        }
        guard numbers(in: lines.filter { !isLabel($0) }.joined(separator: " ")).allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
        let isRelative = has(#"\brelative frequency\b"#, text)
        return made(share, decimals: isRelative,
                    [read, Step(isRelative ? "Out of all of them" : "Out of all of them", "\(names[index].prefix(1).uppercased() + names[index].dropFirst()) is \(written(size)) out of \(written(total)).")])
    }

    /// A word without its plural: "sales" and "sale" are the same.
    private static func stem(_ word: String) -> String {
        let w = word.lowercased()
        return w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : w
    }

    // MARK: A pie chart

    /// "The pie chart shows information about people at a fair during three days. (Friday 80°,
    /// Thursday 25°.) There were 132 more people on Friday than on Thursday. Work out the
    /// number of people on Saturday." The difference in angle stands for the difference in people.
    private static func pie(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bpie chart\b"#, text) else { return nil }
        // The sectors' names: words standing on lines of their own.
        let named = lines.filter { has(#"^[A-Z][a-z]{2,}$"#, $0) }.map { $0.lowercased() }
        guard let more = groups(#"\b(\d+) (more|fewer|less) ([a-z ]+?) than ([a-z ]+?)(?:\.|,|$)"#, in: text), let gap = Double(more[1]) else { return nil }
        func name(in phrase: String) -> String? {
            let found = named.filter { label in phrase.lowercased().split(separator: " ").contains { stem(String($0)) == stem(label) } }
            return Set(found).count == 1 ? found[0] : nil
        }
        guard var bigger = name(in: more[3]), var smaller = name(in: more[4]), bigger != smaller else { return nil }
        if more[2].lowercased() != "more" { swap(&bigger, &smaller) }
        let angles = every(#"(\d+(?:\.\d+)?) ?°"#, in: text).compactMap { Double($0[1]) }
        guard !angles.isEmpty, angles.reduce(0, +) < 360 else { return nil }
        guard let ask = groups(#"\b(?:work out|find|calculate|how many)\b([^.?]*)"#, in: text)?[1].lowercased() else { return nil }
        let wantsTotal = has(#"\btotal\b|\baltogether\b|\bin all\b"#, ask)
        let asked = wantsTotal ? nil : name(in: ask)
        guard wantsTotal || asked != nil else { return nil }
        let biggerAngle: Double, smallerAngle: Double, askedAngle: Double?
        if angles.count == 1, Set(named).count == 2 || Set([bigger, smaller]).count == 2 && wantsTotal && Set(named).subtracting([bigger, smaller]).count <= 1 {
            // Two sectors, one angle given: the other is what's left of 360°, and the bigger share is the one with more.
            let given = angles[0], other = 360 - given
            guard !same(given, other) else { return nil }
            (biggerAngle, smallerAngle) = (max(given, other), min(given, other))
            askedAngle = asked.map { $0 == bigger ? biggerAngle : ($0 == smaller ? smallerAngle : -1) }
        } else if angles.count == 2, let asked, asked != bigger, asked != smaller,
                  let days = groups(#"\b(three|3) [a-z]+\b"#, in: text).map({ _ in 3 }) ?? (Set(named).count == 3 ? 3 : nil), days == 3 {
            // Three sectors, the two compared have their angles given; the one asked about has what's left.
            (biggerAngle, smallerAngle) = (max(angles[0], angles[1]), min(angles[0], angles[1]))
            guard !same(biggerAngle, smallerAngle) else { return nil }
            askedAngle = 360 - angles[0] - angles[1]
        } else { return nil }
        if let askedAngle { guard askedAngle > 0 else { return nil } }
        // Every number is an angle or the difference.
        let all = numbers(in: lines.filter { !isLabel($0) }.joined(separator: " "))
        guard all.allSatisfy({ size in (angles + [gap, 360]).contains { same($0, size) } }) else { return nil }
        let difference = biggerAngle - smallerAngle
        let each = gap / difference
        var lead = [Step("Find the angle for the difference", "\(bigger.prefix(1).uppercased() + bigger.dropFirst()) has the bigger share of the chart, so its angle is the bigger one.",
                         [MathLine(.add([plain(biggerAngle), .multiply([.minusOne, plain(smallerAngle)])]), plain(difference), suffix: "°")]),
                    Step("Find what 1° stands for", "\(written(difference))° stands for \(written(gap)).", [MathLine(divided(plain(gap), by: plain(difference)), plain(each))])]
        if wantsTotal {
            lead.append(Step("The whole chart", "The whole chart is 360°."))
            return made(.multiply([plain(360), plain(each)]), decimals: true, lead)
        }
        guard let askedAngle else { return nil }
        if angles.count == 2 {
            lead.insert(Step("Find the angle asked about", "The angles make 360° altogether.",
                             [MathLine(.add([plain(360), .multiply([.minusOne, plain(angles[0])]), .multiply([.minusOne, plain(angles[1])])]), plain(askedAngle), suffix: "°")]), at: 2)
        }
        return made(.multiply([plain(askedAngle), plain(each)]), decimals: true, lead)
    }

    // MARK: Relative frequencies of samples

    /// "Four samples of kettles are tested. Each sample has size 200. Here are the relative
    /// frequencies of faulty kettles. Work out the range of the number of faulty kettles."
    private static func sampled(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\brelative frequenc"#, text),
              let sizeFound = groups(#"\bsamples? (?:has|have|of) (?:a )?(?:size )?(?:of )?(\d+)\b|\bsample size (?:is |of )?(\d+)\b|\bsize (\d+)\b"#, in: text),
              let size = Double(sizeFound[1].isEmpty ? (sizeFound[2].isEmpty ? sizeFound[3] : sizeFound[2]) : sizeFound[1]),
              let many = groups(#"\b(two|three|four|five|six|seven|eight|\d+) samples\b"#, in: text), let samples = count(many[1]) else { return nil }
        let body = lines.filter { !isLabel($0) }
        let all = numbers(in: body.joined(separator: " "))
        let fractions = all.filter { $0 < 1 && $0 > 0 }
        guard fractions.count == samples else { return nil }
        let rest = all.filter { $0 >= 1 || $0 == 0 }
        guard rest.allSatisfy({ same($0, size) || same($0, Double(samples)) }) else { return nil }
        let counts = fractions.map { $0 * size }
        let lead = Step("Turn each into a number", "Relative frequency × \(written(size)) is how many there were in that sample.",
                        fractions.map { MathLine(.multiply([plain($0), plain(size)]), plain($0 * size)) })
        if has(#"\brange\b"#, text) {
            guard let most = counts.max(), let least = counts.min() else { return nil }
            return made(.add([plain(most), .multiply([.minusOne, plain(least)])]), decimals: true,
                        [lead, Step("Take the smallest from the biggest", "The range is the biggest number take away the smallest.")])
        }
        if has(#"\b(?:total|altogether|in all)\b"#, text) {
            return made(.add(counts.map(plain)), decimals: true, [lead, Step("Add them up", "")])
        }
        return nil
    }

    // MARK: Relative frequency as the trials go on

    /// "The trial is carried out 100 times. The table shows the relative frequency of a blue disc
    /// after every 25 trials. [25: 0.4, 50: 0.36, 75: 0.4, 100: 0.32] For the trials from the 26th
    /// to the 50th, how many times was a blue disc chosen?" Also the best estimate of the
    /// probability (the one after the most trials), and of how many there are out of a number given.
    private static func runningRelative(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\brelative frequenc"#, text), let every = groups(#"\bafter every (\d+) ([a-z]+)\b"#, in: text), let step = Double(every[1]), step > 0 else { return nil }
        // Each row whole on one line, its numbers in the table's order. Cells read as lines of
        // their own come in no sure order, and there's no telling which number goes with which.
        let totalRows = lines.indices.filter { has(#"^(?:total )?number of [a-z]+(?: \d+){2,}$"#, lines[$0]) }
        let rateRows = lines.indices.filter { has(#"^relative frequency(?: [a-z]+)*(?: (?:0?\.\d+|[01]))+$"#, lines[$0]) }
        guard totalRows.count == 1, rateRows.count == 1 else { return nil }
        let totals = numbers(in: lines[totalRows[0]]), rates = numbers(in: lines[rateRows[0]])
        guard totals.count == rates.count, totals.count >= 2, totals.count <= 12 else { return nil }
        // The totals go up by the step said, and each relative frequency is a whole number of
        // times out of its total, never fewer than the time before nor more than the trials since.
        guard totals.enumerated().allSatisfy({ same($0.element, step * Double($0.offset + 1)) }), rates.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return nil }
        let counts = zip(rates, totals).map { Double(String(format: "%.8g", $0 * $1)) ?? $0 * $1 }
        guard counts.allSatisfy({ abs($0 - $0.rounded()) < 1e-9 }) else { return nil }
        for (index, count) in counts.enumerated() {
            let before = index == 0 ? 0 : counts[index - 1]
            guard count >= before - 1e-9, count - before <= step + 1e-9 else { return nil }
        }
        guard let most = totals.last, let best = rates.last else { return nil }
        // Numbers on lines of their own after the table are answers to circle.
        let choices = lines.indices.filter { $0 > max(totalRows[0], rateRows[0]) && has(#"^\d*\.?\d+(?: \d*\.?\d+)*$"#, lines[$0]) }
        guard choices.isEmpty || has(#"\bcircle\b"#, text) else { return nil }
        let table = [totalRows[0], rateRows[0]] + choices
        let said = lines.indices.filter { !table.contains($0) && !isLabel(lines[$0]) }.map { lines[$0] }
        let words = said.joined(separator: " ")
        var used = [step]
        // How many times it's done in all: the table's last total.
        if let times = groups(#"\b(\d+) times\b"#, in: words), let all = Double(times[1]) { guard same(all, most) else { return nil }; used.append(all) }
        let read = Step("Read the table", "After each \(written(step)) \(every[2]): the relative frequency.", zip(totals, rates).map { MathLine(plain($0), plain($1)) })
        func checked(_ problem: Problem, _ value: Double) -> Problem? {
            guard numbers(in: words).allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
            if !choices.isEmpty { guard choices.flatMap({ numbers(in: lines[$0]) }).contains(where: { same($0, value) }) else { return nil } }
            return problem
        }
        guard let ask = sentences(said).last(where: { has(#"\b(?:how many|work out|find|calculate|write down|what|circle)\b"#, $0) }) else { return nil }
        if let span = groups(#"\bfrom the (\d+)(?:st|nd|rd|th) to the (\d+)(?:st|nd|rd|th)\b"#, in: ask), has(#"\bhow many\b|\bnumber of\b"#, ask),
           let from = Double(span[1]), let to = Double(span[2]), let end = totals.firstIndex(where: { same($0, to) }) {
            // The ones in a stretch of trials: how many by its end, less how many before it began.
            let start = totals.firstIndex { same($0, from - 1) }
            guard start != nil || from == 1, from < to else { return nil }
            used += [from, to]
            let after = Expr.multiply([plain(rates[end]), plain(totals[end])])
            var working = [MathLine(after, plain(counts[end]))]
            var sum = after
            if let start {
                let earlier = Expr.multiply([plain(rates[start]), plain(totals[start])])
                working.insert(MathLine(earlier, plain(counts[start])), at: 0)
                sum = .add([after, .multiply([.minusOne, earlier])])
            }
            let lead = [read, Step("Turn them into numbers of times", "Relative frequency × the number of \(every[2]) so far is how many times it had happened by then.", working)]
                + (start == nil ? [] : [Step("Take away", "The ones in that stretch are those by its end, less those before it began.")])
            return checked(made(sum, decimals: true, lead), counts[end] - (start.map { counts[$0] } ?? 0))
        }
        guard has(#"\bbest estimate\b"#, ask) else { return nil }
        let why = Step("Use the most \(every[2])", "The more \(every[2]), the better the estimate: after \(written(most)) the relative frequency is \(written(best)).")
        if has(#"\bestimate (?:of|for) the probability\b"#, ask) {
            return checked(made(plain(best), decimals: true, [read, why]), best)
        }
        if has(#"\bestimate (?:of|for) the (?:total )?number of\b"#, ask), let all = groups(#"\b(?:total of|there are|contains|has) (\d+) [a-z]+\b"#, in: words), let size = Double(all[1]) {
            // "There is a total of 1000 discs in the bag": that share of them.
            let value = Double(String(format: "%.8g", best * size)) ?? best * size
            guard abs(value - value.rounded()) < 1e-9 else { return nil }
            used.append(size)
            return checked(made(.multiply([plain(best), plain(size)]), decimals: true, [read, why, Step("Take that share", "\(written(best)) of the \(written(size)).")]), value)
        }
        return nil
    }

    // MARK: A frequency table of values

    /// "The table shows the number of goals scored in 20 matches. [Goals: 0, 1, 2, 3. Frequency: 3,
    /// 6, 7, 4] Work out the mean number of goals." Also the median, the mode and the range.
    private static func valueTable(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bfrequency\b|\bnumber of\b"#, text), has(#"\btable\b"#, text), !has(#"[<≤]"#, text),
              let ask = sentences(lines, prose: true).last(where: { has(#"\b(?:work out|find|calculate|write down|what is)\b"#, $0) }),
              let wanted = groups(#"\b(mean|median|mode|modal|range)\b"#, in: ask)?[1].lowercased() else { return nil }
        // Rows of a value and its frequency, or a row of values and a row of frequencies: each row whole on a line.
        var pairs: [(value: Double, size: Double)] = [], table = Set<Int>()
        let across = lines.indices.filter { has(#"^[A-Za-z][A-Za-z ,()]*? \d+(?:\.\d+)?(?: \d+(?:\.\d+)?)+$"#, lines[$0]) && !has(#"\b(?:work out|find|calculate|write|what|how|shows?|the)\b"#, lines[$0]) }
        let down = lines.indices.filter { has(#"^\d+(?:\.\d+)? \d+$"#, lines[$0]) }
        let alone = lines.indices.filter { has(#"^\d+(?:\.\d+)?$"#, lines[$0]) && !isLabel(lines[$0]) }
        if across.count == 2, down.isEmpty, alone.isEmpty, has(#"^frequency\b|^number of\b"#, lines[across[1]]), !has(#"^frequency\b"#, lines[across[0]]) {
            let values = numbers(in: lines[across[0]]), sizes = numbers(in: lines[across[1]])
            guard values.count == sizes.count else { return nil }
            pairs = zip(values, sizes).map { ($0, $1) }; table = Set(across)
        } else if across.isEmpty, down.count >= 2, alone.isEmpty, let first = down.first, let last = down.last, last - first == down.count - 1,
                  let header = lines[..<first].last(where: { has(#"\bfrequency\b|\bnumber of\b"#, $0) }), !has(#"^(?:frequency|number of)\b.* [a-z]+$"#, header) || has(#"\bfrequency$"#, header) {
            // (The frequency is the second column: "Goals Frequency", "Dress size Number of women".)
            pairs = down.map { index in let both = numbers(in: lines[index]); return (both[0], both[1]) }; table = Set(down)
        } else {
            return nil
        }
        guard pairs.count >= 2, pairs.count <= 15, zip(pairs, pairs.dropFirst()).allSatisfy({ $0.value < $1.value }),
              pairs.allSatisfy({ $0.size >= 0 && $0.size == $0.size.rounded() }) else { return nil }
        let total = pairs.reduce(0) { $0 + $1.size }
        guard total > 0 else { return nil }
        // Every other number in the question is how many there are in all.
        var used = [total]
        if let places = groups(#"\bto (\d) (?:decimal places?|significant figures?|d\.p\.|s\.f\.)"#, in: text), let size = Double(places[1]) { used.append(size) }
        let outside = lines.enumerated().filter { !table.contains($0.offset) && !isLabel($0.element) }.flatMap { numbers(in: $0.element) }
        guard outside.allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
        // (And it has to be said: a row lost off the end of the table would go unseen without it.)
        guard outside.contains(where: { same($0, total) }) else { return nil }
        let read = Step("Read the table", "", pairs.map { MathLine(.symbol(written($0.value)), plain($0.size)) })
        switch wanted {
        case "mean":
            let products = pairs.map { $0.value * $0.size }
            let sum = products.reduce(0, +)
            return rounding(made(divided(plain(sum), by: plain(total)), decimals: true,
                                 [read, Step("Multiply each value by its frequency", "That many of them have that value.", pairs.map { MathLine(.multiply([plain($0.value), plain($0.size)]), plain($0.value * $0.size)) }),
                                  Step("Add them up", "The total of value × frequency, and the total frequency.", [MathLine(.add(products.map(plain)), plain(sum)), MathLine(.add(pairs.map { plain($0.size) }), plain(total))]),
                                  Step("Share out", "The mean is the first total divided by the second.")]), sum / total, text)
        case "median":
            // The middle one, or halfway between the middle two, counting through the frequencies.
            func at(_ place: Double) -> Double? {
                var so = 0.0
                for pair in pairs { so += pair.size; if place <= so { return pair.value } }
                return nil
            }
            let middle = (total + 1) / 2
            guard let low = at(middle.rounded(.down)), let high = at(middle.rounded(.up)) else { return nil }
            let running = pairs.reduce(into: (0.0, [Double]())) { $0.0 += $1.size; $0.1.append($0.0) }.1
            return made(plain((low + high) / 2), decimals: true,
                        [read, Step("Find the place", "There are \(written(total)) values, so the median is the \(written(middle))th" + (middle == middle.rounded() ? "." : ": halfway between the \(written(middle.rounded(.down)))th and the \(written(middle.rounded(.up)))th."),
                                    [MathLine(.symbol("running totals"), .symbol(running.map(written).joined(separator: ", ")))]),
                         Step("Count through the table", low == high ? "That value is \(written(low))." : "Those values are \(written(low)) and \(written(high)).")])
        case "mode", "modal":
            guard let most = pairs.map(\.size).max(), pairs.filter({ $0.size == most }).count == 1, let pair = pairs.first(where: { $0.size == most }) else { return nil }
            return made(plain(pair.value), decimals: true, [read, Step("Find the biggest frequency", "The mode is the value there are most of: \(written(most)) of them.")])
        default:
            let there = pairs.filter { $0.size > 0 }
            guard let low = there.first?.value, let high = there.last?.value, low < high else { return nil }
            return made(.add([plain(high), .multiply([.minusOne, plain(low)])]), decimals: true, [read, Step("Take the smallest value from the biggest", "The range is of the values, not the frequencies.")])
        }
    }

    // MARK: The number that's missing, from the mean

    /// "The mean of five numbers is 12. Four of the numbers are 8, 10, 15 and 16. Work out the
    /// fifth number."
    private static func missingFromMean(_ lines: [String], _ text: String) -> Problem? {
        let amount = #"(\d+|three|four|five|six|seven|eight|nine|ten)"#
        guard !has(#"\bfrequency\b|\btable\b|\bmedian\b|\bmode\b|\brange\b"#, text),
              let whole = groups("\\bmean of (?:the )?\(amount) ([a-z]+) is (-?\(number))", in: text), let n = count(whole[1]), n >= 3, let mean = Double(whole[3]),
              let part = groups("\\b\(amount) of the \(whole[2]) are ((?:-?\(number), )*-?\(number),? and -?\(number))", in: text), let some = count(part[1]), some == n - 1,
              has(#"\b(?:work out|find|calculate|what is) the (?:other|last|missing|remaining|fifth|fourth|sixth|third|seventh|eighth|ninth|tenth) (?:number|one)\b"#, text) else { return nil }
        let given = every("-?\(number)", in: part[2]).compactMap { Double($0[0]) }
        guard given.count == some else { return nil }
        var used = given + [mean]
        for word in [whole[1], part[1]] { if let size = Double(word) { used.append(size) } }
        let body = lines.filter { !isLabel($0) }.joined(separator: " ")
        guard numbers(in: body).count == used.count else { return nil }
        let total = Double(n) * mean, known = given.reduce(0, +)
        return made(.add([plain(total), .multiply([.minusOne, plain(known)])]), decimals: true,
                    [Step("Find the total", "The mean times how many there are is what they add up to.", [MathLine(.multiply([.integer(n), plain(mean)]), plain(total))]),
                     Step("Add up the ones you know", "", [MathLine(.add(given.map(plain)), plain(known))]),
                     Step("Take away", "What's left is the other number.")])
    }

    // MARK: A stratified sample

    /// "There are 600 students in a school. 320 are boys and 280 are girls. A sample of 60 students
    /// stratified by gender is taken. Work out the number of girls in the sample." Each group has
    /// the same share of the sample as it has of everyone.
    private static func stratified(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bstratified\b"#, text), let sampled = groups(#"\bsample of (\d+)\b"#, in: text), let size = Double(sampled[1]), size > 0,
              let everyone = groups(#"\bthere are (\d+) ([a-z]+) (?:in|at)\b|\bhas (\d+) ([a-z]+)\b"#, in: text), let total = Double(everyone[1].isEmpty ? everyone[3] : everyone[1]), total > size else { return nil }
        // The groups whose sizes are given: "320 are boys", "240 of the students are in Year 7".
        let found = every(#"\b(\d+) (?:of the [a-z]+ )?(?:are|is) (?:in )?([A-Za-z]+ \d+|[a-z]+)\b"#, in: text)
        var sizes: [(name: String, size: Double)] = []
        for one in found {
            guard let many = Double(one[1]), many < total, !sizes.contains(where: { $0.name == one[2].lowercased() }) else { return nil }
            sizes.append((one[2].lowercased(), many))
        }
        guard !sizes.isEmpty, sizes.reduce(0, { $0 + $1.size }) <= total else { return nil }
        // Given for more than one, they are everyone.
        if sizes.count > 1 { guard same(sizes.reduce(0) { $0 + $1.size }, total) else { return nil } }
        guard let ask = groups(#"\b(?:work out|find|calculate) (?:the number of|how many) ([A-Za-z]+ \d+|[a-z]+)(?: [a-z]+)? (?:(?:that )?(?:should be |are |will be )?in|for) the sample\b|\bhow many ([A-Za-z]+ \d+|[a-z]+)(?: [a-z]+)? (?:should be|are|will be) in the sample\b"#, in: text) else { return nil }
        let wanted = (ask[1] + ask[2]).lowercased()
        guard let group = sizes.first(where: { $0.name == wanted || stem($0.name) == stem(wanted) }) else { return nil }
        // Every number is one of these (a group's own number, "Year 7", is part of its name).
        var plain = lines.filter { !isLabel($0) }.joined(separator: " ")
        for name in sizes.map(\.name) where has(#"\d"#, name) { plain = plain.replacingOccurrences(of: name, with: "", options: .caseInsensitive) }
        let used = [total, size] + sizes.map(\.size)
        guard numbers(in: plain).allSatisfy({ value in used.contains { same($0, value) } }) else { return nil }
        // A number of people: nothing where it doesn't come out whole.
        let value = group.size / total * size
        guard abs(value - value.rounded()) < 1e-9 else { return nil }
        return made(.multiply([divided(self.plain(group.size), by: self.plain(total)), self.plain(size)]), decimals: false,
                    [Step("Find the group's share", "\(written(group.size)) of the \(written(total)) are \(group.name).", [MathLine(divided(self.plain(group.size), by: self.plain(total)))]),
                     Step("Take the same share of the sample", "A stratified sample has each group in the same share as it has of everyone: that share of \(written(size)).")])
    }

    // MARK: Two people's relative frequencies

    /// "Beth and Lynn each spin the same biased coin a number of times. [Number of spins: 125, 80.
    /// Relative frequency of Heads: 0.32, 0.35] How many more Heads did Beth spin than Lynn?"
    /// Which relative frequency goes with which number of spins: the way that gives whole numbers of Heads.
    private static func twoRates(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\brelative frequenc"#, text),
              let ask = groups(#"\bhow many more ([a-z]+) did ([A-Z][a-z]+) (?:spin|throw|roll|get|score|flip|toss) than ([A-Z][a-z]+)\b"#, in: text),
              let pair = groups(#"\b([A-Z][a-z]+) and ([A-Z][a-z]+) each\b"#, in: text), Set([pair[1], pair[2]]) == Set([ask[2], ask[3]]), ask[2] != ask[3] else { return nil }
        // A number alone on a line between "The table shows …" and the question is one of the table's;
        // anywhere else it may be the question's own number.
        guard let from = lines.firstIndex(where: { has(#"\btable\b"#, $0) }), let to = lines.firstIndex(where: { has(#"\bhow many more\b"#, $0) }), from < to else { return nil }
        let body = lines.enumerated().filter { ($0.offset > from && $0.offset < to && has(#"^\d+$"#, $0.element)) || !isLabel($0.element) }.map(\.element)
        let all = numbers(in: body.joined(separator: " "))
        // Two whole numbers of tries and two relative frequencies, and nothing else.
        let rates = all.filter { $0 > 0 && $0 < 1 }, tries = all.filter { $0 >= 1 }
        guard all.count == 4, rates.count == 2, tries.count == 2, tries.allSatisfy({ $0 == $0.rounded() }) else { return nil }
        func times(_ rate: Double, _ size: Double) -> Double? {
            let value = Double(String(format: "%.8g", rate * size)) ?? rate * size
            return abs(value - value.rounded()) < 1e-9 ? value.rounded() : nil
        }
        // Each way round the two could go; a number of times that isn't whole rules a way out.
        var ways: [(counts: [Double], rates: [Double])] = []
        for order in [[rates[0], rates[1]], [rates[1], rates[0]]] {
            if let a = times(order[0], tries[0]), let b = times(order[1], tries[1]) { ways.append(([a, b], order)) }
            if same(rates[0], rates[1]) { break }
        }
        // One way only, or the same difference either way.
        guard let first = ways.first, ways.allSatisfy({ same(abs($0.counts[0] - $0.counts[1]), abs(first.counts[0] - first.counts[1])) }), ways.count == 1 || !same(tries[0], tries[1]) else { return nil }
        guard ways.count == 1 else { return nil }
        let (big, small) = first.counts[0] >= first.counts[1] ? (0, 1) : (1, 0)
        guard first.counts[big] > first.counts[small] else { return nil }
        let lead = [Step("Turn each into a number of \(ask[1].lowercased())", "Relative frequency × the number of tries. (\(written(first.rates[0])) goes with \(written(tries[0])) and \(written(first.rates[1])) with \(written(tries[1])): the other way round doesn't give whole numbers.)",
                         [MathLine(.multiply([plain(first.rates[0]), plain(tries[0])]), plain(first.counts[0])), MathLine(.multiply([plain(first.rates[1]), plain(tries[1])]), plain(first.counts[1]))]),
                    Step("Take the smaller from the bigger", "")]
        return made(.add([plain(first.counts[big]), .multiply([.minusOne, plain(first.counts[small])])]), decimals: true, lead)
    }

    // MARK: Numbers from their averages

    /// "Ping chooses four numbers. The mode of these four numbers is 8, the range is 7 and the mean
    /// is 11. Find Ping's four numbers." Every way the mode can sit among them is tried; only one fits.
    private static func fromAverages(_ lines: [String], _ text: String) -> Problem? {
        guard !has(#"\bfrequency\b|\btable\b|\bmedian\b|\bexpressions?\b"#, text),
              let many = groups(#"\b(three|four|3|4) (?:whole )?(?:numbers|games|scores|tests|marks|rounds|integers)\b"#, in: text), let n = count(many[1]),
              let modeFound = groups("\\b(?:mode|modal [a-z]+)\\b[^.,;]*?\\b(?:is|was) (\(number))\\b", in: text), let mode = Double(modeFound[1]),
              let meanFound = groups("\\bmean\\b[^.,;]*?\\b(?:is|was) (\(number))\\b", in: text), let mean = Double(meanFound[1]),
              let rangeFound = groups("\\brange\\b[^.,;]*?\\b(?:is|was) (\(number))\\b", in: text), let range = Double(rangeFound[1]), range > 0,
              has(#"\b(?:find|work out|write down|what (?:are|were))\b[^.?]*\b(?:numbers|scores|marks|integers)\b"#, text) else { return nil }
        var used = [mode, mean, range]
        if many[1].first?.isNumber == true { used.append(Double(n)) }
        let body = lines.filter { !isLabel($0) }.joined(separator: " ")
        guard numbers(in: body).allSatisfy({ size in used.contains { same($0, size) } }), numbers(in: body).count == used.count else { return nil }
        let total = Double(n) * mean
        // The mode is there more often than anything else: twice with the others all different, or three times.
        var fits: [(list: [Double], how: String)] = []
        if n == 4 {
            let rest = total - 2 * mode
            // The other two either side of the mode, both above it, or both below it.
            let below = (rest - range) / 2
            if below < mode, below + range > mode { fits.append(([below, mode, mode, below + range], "one of the others is below \(written(mode)) and one above, \(written(range)) apart")) }
            let top = mode + range
            if rest - top > mode, rest - top < top { fits.append(([mode, mode, rest - top, top], "\(written(mode)) is the smallest, so the largest is \(written(mode)) + \(written(range)) = \(written(top))")) }
            let bottom = mode - range
            if rest - bottom < mode, rest - bottom > bottom { fits.append(([bottom, rest - bottom, mode, mode], "\(written(mode)) is the largest, so the smallest is \(written(mode)) − \(written(range)) = \(written(bottom))")) }
            let last = total - 3 * mode
            if same(abs(last - mode), range) { fits.append(((last < mode ? [last, mode, mode, mode] : [mode, mode, mode, last]), "\(written(mode)) is there three times")) }
        } else if n == 3 {
            let last = total - 2 * mode
            if same(abs(last - mode), range) { fits.append(((last < mode ? [last, mode, mode] : [mode, mode, last]), "\(written(mode)) is there twice")) }
        } else {
            return nil
        }
        // One way only, and whole numbers.
        guard fits.count == 1, let found = fits.first, found.list.allSatisfy({ abs($0 - $0.rounded()) < 1e-9 }) else { return nil }
        let twice = found.list.filter { same($0, mode) }.count
        let lead = [Step("Use the mode", "\(written(mode)) comes up more often than any other, so it is there at least twice."),
                    Step("Use the mean", "The \(n) of them add up to \(n) × \(written(mean)).", [MathLine(.multiply([.integer(n), plain(mean)]), plain(total)),
                                                                                                 MathLine(.add([plain(total), .multiply([.minusOne, .multiply([.integer(twice), plain(mode)])])]), plain(total - Double(twice) * mode))]),
                    Step("Use the range", "The largest is \(written(range)) more than the smallest. That only works when \(found.how).")]
        return told("the \(n) numbers", found.list.map(written).joined(separator: ", "), lead)
    }

    // MARK: Sentences

    /// The question's sentences, without question numbers and part letters.
    /// With `prose`, a table's cells (a word or a number alone on a line, or junk) are left out.
    private static func sentences(_ lines: [String], prose: Bool = false) -> [String] {
        let body = lines.filter { !isLabel($0) && (!prose || has(#"[A-Za-z]{2,}[^A-Za-z]+[A-Za-z]{2,}"#, $0)) }.joined(separator: " ")
            // A sentence ending in a number with no full stop, run into the next: "is 0.4 Work out …".
            .replacingOccurrences(of: #"(\d(?: ?(?:kg|g|cm|m|mm|km|%))?) (?=(?:Work|Find|Calculate|What|How|Write|Give|Circle|Estimate)\b)"#, with: "$1. ", options: .regularExpression)
        return body.replacingOccurrences(of: #"(?<=[.?!])\s+"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}")
            .map { $0.replacingOccurrences(of: #"^(?:\d{1,2} ?)?\(?[a-h]\)\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A whole word in a sentence, plural or not.
    private static func mentions(_ word: String, _ sentence: String) -> Bool {
        has("\\b\(NSRegularExpression.escapedPattern(for: word))s?\\b", sentence)
    }

    // MARK: Capture and recapture

    /// "On Friday, Saffron catches 180 fish. She puts a tag on each of these fish and puts them
    /// back. On Saturday, she catches 305 fish. She finds that 45 of the 305 fish are tagged.
    /// Work out an estimate for the total number of fish in the lake."
    private static func recaptured(_ lines: [String], _ text: String) -> Problem? {
        let marking = #"\b(?:tag|tags|tagged|mark|marks|marked|ring|rings|ringed|label|labels|labell?ed)\b"#
        guard has(marking, text), has(#"\bestimate\b"#, text) else { return nil }
        let said = sentences(lines)
        guard let askIndex = said.lastIndex(where: { has(#"\b(?:work out|find|calculate)\b"#, $0) && has(#"\bestimate\b"#, $0) }) else { return nil }
        let ask = said[askIndex]
        // The size of the whole population, not how many were marked.
        guard has(#"\b(?:total )?(?:number|size|population)\b|\bhow many\b"#, ask), !has(marking, ask), numbers(in: ask).isEmpty else { return nil }
        let again = #"\b(\d+) of (?:the (\d+)(?: [a-z]+)?|these|them|those)(?: [a-z]+)? (?:are|were|have|had|has)(?: been)?(?: already)? (?:tagged|marked|ringed|labell?ed|a tag|a mark|a ring|a label)\b"#
        let againPlain = #"\b(\d+) (?:[a-z]+ )?(?:are|were|have been|had been|have|had) (?:already )?(?:tagged|marked|ringed|labell?ed|a tag|a mark|a ring|a label)\b"#
        let found = said.enumerated().compactMap { index, sentence -> (Int, [String])? in
            guard index != askIndex, let match = groups(again, in: sentence) ?? groups(againPlain, in: sentence) else { return nil }
            return (index, match)
        }
        guard found.count == 1, let (againIndex, match) = found.first, let back = Double(match[1]) else { return nil }
        var second = match.count > 2 ? Double(match[2]) : nil
        let all = Set(numbers(in: said.enumerated().filter { $0.offset != askIndex }.map(\.element).joined(separator: " ")))
        guard all.count == 3 else { return nil }
        // A sentence that marks: "She tags 180 fish", "She puts a tag on each of these fish".
        let marks = #"\b(?:tags|tagged|marks|marked|rings|ringed|labels|labell?ed|puts? (?:a )?(?:tag|mark|ring|label)s?|gives? (?:each|them|it) (?:a )?(?:tag|mark|ring|label))\b"#
        let catches = #"\b(?:catch|catches|caught|takes?|took|captures?|captured|selects?|selected|picks?|picked|nets?|netted|traps?|trapped)\b"#
        func places(_ value: Double) -> [Int] {
            said.indices.filter { $0 != againIndex && $0 != askIndex && numbers(in: said[$0]).contains { same($0, value) } }
        }
        let markEach = said.indices.filter { $0 != againIndex && has(marks, said[$0]) && numbers(in: said[$0]).isEmpty && has(#"\b(?:each|all|every)\b"#, said[$0]) }
        let first: Double
        if let known = second {
            let left = all.filter { !same($0, back) && !same($0, known) }
            guard left.count == 1, let only = left.first, places(known).allSatisfy({ !has(marks, said[$0]) }) else { return nil }
            guard places(only).contains(where: { has(marks, said[$0]) || has(catches, said[$0]) && !markEach.isEmpty }) else { return nil }
            first = only
        } else {
            let left = all.filter { !same($0, back) }.sorted()
            guard left.count == 2 else { return nil }
            let marked = left.filter { value in places(value).contains { has(marks, said[$0]) } }
            if marked.count == 1 {
                first = marked[0]
            } else if marked.isEmpty, markEach.count == 1, let at = markEach.first {
                // Caught, then "each of these" marked: the catch just before is the first one.
                let before = left.filter { value in places(value).contains { $0 == at - 1 && has(catches, said[$0]) } }
                let after = left.filter { value in places(value).contains { $0 > at && has(catches, said[$0]) } }
                guard before.count == 1, after.count == 1, before[0] != after[0] else { return nil }
                first = before[0]
            } else { return nil }
            second = left.first { !same($0, first) }
            guard let other = second, places(other).contains(where: { has(catches, said[$0]) && !has(marks, said[$0]) }) else { return nil }
        }
        guard let caught = second, back > 0, back < caught, back < first else { return nil }
        let value = first * caught / back
        var lead = [Step("Read the catches", "\(written(first)) were marked and let go. Later \(written(caught)) were caught, and \(written(back)) of those were marked."),
                    Step("Use the same share", "The share marked in the second catch is taken to be the share marked in the whole population, so the whole is \(written(caught)) ÷ \(written(back)) times the \(written(first)) marked.")]
        let sum = divided(.multiply([plain(first), plain(caught)]), by: plain(back))
        guard abs(value - value.rounded()) > 1e-9 else { return made(sum, decimals: false, lead) }
        lead += [Step("Work it out", "", [MathLine(sum, plain(value))]), Step("Round it", "The estimate is a whole number.")]
        return made(plain(value.rounded()), decimals: false, lead)
    }

    // MARK: A table of probabilities

    /// "There are only blue cubes, red cubes and yellow cubes in a box. The table shows the
    /// probability of taking a blue cube (0.2). The number of red cubes is the same as the number
    /// of yellow cubes. Complete the table." Also the number of one kind or of them all, from
    /// "There are 18 blue counters", and a relative frequency missing from a table.
    private static func probabilities(_ lines: [String], _ text: String, completing: Bool) -> Problem? {
        guard has(#"\bprobabilit|\brelative frequenc"#, text), has(#"\btable\b"#, text) else { return nil }
        let said = sentences(lines, prose: true)
        let headers: Set<String> = ["colour", "color", "probability", "score", "relative", "frequency", "outcome", "number", "total", "letter", "result", "type", "flavour", "kind"]
        // The kinds, as the question lists them: "blue cubes, red cubes and yellow cubes", "red or white or blue or yellow", "0, 1, 2 or 3".
        let loneWords = lines.filter { has(#"^[A-Za-z]{3,}$"#, $0) }.map { $0.lowercased() }.filter { !headers.contains($0) }
        var kinds: [String] = [], listedAt: Int?
        for (index, sentence) in said.enumerated() {
            if let scores = groups(#"\b(?:score|scores|land on|lands on|numbered|show)\b[^.?]*?\b(\d+(?:, \d+)*,? (?:or|and) \d+)\b"#, in: sentence) {
                kinds = numbers(in: scores[1]).map(written); listedAt = index; break
            }
            let named = Array(Set(loneWords)).filter { mentions($0, sentence) }
            guard named.count >= 2 else { continue }
            let lower = sentence.lowercased()
            let spots = named.compactMap { word in lower.range(of: "\\b\(word)s?\\b", options: .regularExpression).map { (word, $0) } }.sorted { $0.1.lowerBound < $1.1.lowerBound }
            guard let start = spots.first?.1.lowerBound, let end = spots.last?.1.upperBound else { continue }
            let span = String(lower[start..<end])
            let items = span.replacingOccurrences(of: #"\s*,\s*(?:and |or )?|\s+or\s+|\s+and\s+"#, with: "\u{1}", options: .regularExpression).components(separatedBy: "\u{1}")
            guard items.count == spots.count, zip(items, spots).allSatisfy({ item, spot in named.filter { mentions($0, item) } == [spot.0] }) else { continue }
            // Nothing listed before the first one that wasn't read as a kind.
            guard !has(#"(?:,|\bor|\band)\s*$"#, String(lower[..<start])) else { continue }
            kinds = spots.map(\.0); listedAt = index; break
        }
        guard kinds.count >= 2, let listedAt else { return nil }
        // Every kind standing alone in the table is one of those listed.
        guard Set(loneWords).isSubset(of: Set(kinds)) || has(#"^\d"#, kinds[0]) else { return nil }
        // The table's numbers: decimals on lines of their own.
        let values = lines.filter { has(#"^(?:0?\.\d+\s*)+$"#, $0) }.flatMap { numbers(in: $0) }
        guard !values.isEmpty, values.allSatisfy({ $0 > 0 && $0 < 1 }) else { return nil }
        var used = values
        var skip: Set<Int> = [listedAt]
        if has(#"^\d"#, kinds[0]) { used += kinds.compactMap(Double.init) }
        // A whole number alone in the table is a kind, or the table has a row of counts as well, which isn't this.
        if let start = lines.firstIndex(where: { has(#"[A-Za-z]{2,}[^A-Za-z]+[A-Za-z]{2,}"#, $0) }) {
            guard lines[start...].allSatisfy({ !has(#"^\d+$"#, $0) || kinds.contains($0) }) else { return nil }
        }
        // Which kinds the given numbers are for: "The table shows the probabilities that the counter will be blue or will be yellow."
        var given: [String] = []
        if let shows = said.firstIndex(where: { has(#"\btable shows\b"#, $0) }) {
            given = kinds.filter { mentions($0, said[shows]) }
            skip.insert(shows)
        }
        let askIndex = completing ? said.firstIndex(where: { has(#"\bcomplete the table\b"#, $0) }) : said.lastIndex(where: { has(#"\b(?:work out|find|calculate|what is|how many)\b"#, $0) })
        guard let askIndex else { return nil }
        skip.insert(askIndex)
        // What else is said: one kind as likely as another, or so many times as likely; how many of one kind there are.
        var links: [(String, String, Double)] = []
        var counted: (String, Double)?
        for (index, sentence) in said.enumerated() where !skip.contains(index) {
            let lower = sentence.lowercased()
            func spot(_ kind: String) -> String.Index { lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: kind))s?\\b", options: .regularExpression)?.lowerBound ?? lower.endIndex }
            let named = kinds.filter { mentions($0, sentence) }.sorted { spot($0) < spot($1) }
            if named.count == 1, let found = groups("\\bthere (?:are|is) (\\d+) \(named[0])s?\\b", in: sentence), let size = Double(found[1]) {
                guard counted == nil else { return nil }
                counted = (named[0], size); used.append(size); continue
            }
            if named.count == 2 {
                if has(#"\bsame as\b|\bequal to\b|\bequally likely\b|\bas likely as\b"#, sentence), !has(#"\btimes\b|\btwice\b|\bhalf\b"#, sentence) {
                    links.append((named[0], named[1], 1)); continue
                }
                if let times = groups(#"\b(twice|double|half|three times|four times|five times|(\d+) times)\b"#, in: sentence) {
                    let word = times[1].lowercased()
                    let factor: Double = ["twice": 2, "double": 2, "half": 0.5, "three times": 3, "four times": 4, "five times": 5][word] ?? Double(times[2]) ?? 0
                    guard factor > 0 else { return nil }
                    if !times[2].isEmpty { used.append(factor) }
                    links.append((named[0], named[1], factor)); continue
                }
                return nil
            }
            guard named.count < 2 else { return nil }
        }
        // A number of tries is only needed for how many to expect.
        let tries = said.compactMap { groups(#"\bfor (\d+) (?:turns|times|spins|throws|rolls|goes|trials|games)\b|\b(?:spun|rolled|thrown|flipped|played) (?:\w+ )?(\d+) times\b"#, in: $0) }.compactMap { Double($0[1].isEmpty ? $0[2] : $0[1]) }
        let all = numbers(in: said.joined(separator: " "))
        guard all.allSatisfy({ size in (used + tries).contains { same($0, size) } }) else { return nil }

        // Work it out for each way the given numbers could go with the kinds named (the table's columns may be read out of order).
        let unknown = given.isEmpty ? [] : kinds.filter { !given.contains($0) }
        guard given.isEmpty ? values.count == kinds.count - 1 && links.isEmpty && counted == nil : values.count == given.count && given.count <= 4 else { return nil }
        func orders(_ items: [Double]) -> [[Double]] {
            items.count <= 1 ? [items] : items.indices.flatMap { index -> [[Double]] in
                var rest = items; let one = rest.remove(at: index)
                return orders(rest).map { [one] + $0 }
            }
        }
        var outcomes: [(answer: Problem, key: String)] = []
        for order in (given.isEmpty ? [values] : orders(values)) {
            var known: [String: Double] = [:]
            for (kind, value) in zip(given, order) { known[kind] = value }
            let left = 1 - order.reduce(0, +)
            guard left > -1e-9 else { continue }
            // Each unknown as a multiple of one of them, by the links.
            var solved: [String: Double] = [:]
            if given.isEmpty {
                solved["?"] = left
            } else {
                guard let solution = solve(unknown, known, links, left) else { continue }
                solved = solution
            }
            guard solved.values.allSatisfy({ $0 > 1e-9 && $0 < 1 + 1e-9 }) else { continue }
            let every = known.merging(solved) { a, _ in a }
            var total: Double?
            if let (kind, size) = counted {
                guard let share = every[kind], share > 0 else { continue }
                total = size / share
                guard let all = total, abs(all - all.rounded()) < 1e-6, every.values.allSatisfy({ abs($0 * all - ($0 * all).rounded()) < 1e-6 }) else { continue }
            }
            let ask = said[askIndex]
            let read = Step("Read the table", given.isEmpty ? "The relative frequencies add up to 1." : "The probabilities add up to 1.",
                            given.isEmpty ? [MathLine(.add([plain(1), .multiply([.minusOne, .add(values.map(plain))])]), plain(left))]
                                          : given.map { MathLine(.symbol($0), plain(known[$0]!)) })
            var lead = [read]
            if !links.isEmpty {
                lead.append(Step("Use what's said about the others", links.map { "\($0.0.capitalized) is \($0.2 == 1 ? "as likely as" : "\(written($0.2)) times as likely as") \($0.1)." }.joined(separator: " ") + " Together they make \(written(left)).",
                                 unknown.map { MathLine(.symbol($0), plain(solved[$0]!)) }))
            }
            if completing {
                let answer = given.isEmpty ? written(left) : unknown.map { "\($0) \(written(solved[$0]!))" }.joined(separator: ", ")
                outcomes.append(given.isEmpty ? (made(plain(left), decimals: true, [Step("Find the missing one", "The relative frequencies add up to 1, so the missing one is what's left.")]), answer) : (told("table", answer, lead), answer))
                continue
            }
            let named = kinds.filter { mentions($0, ask) }
            if has(#"\btotal number\b|\bhow many [a-z]+ (?:are )?(?:there )?(?:in the [a-z]+ )?(?:altogether|in total)\b"#, ask), named.isEmpty, let all = total, let (kind, size) = counted {
                lead.append(Step("Find how many altogether", "\(written(size)) \(kind) make \(written(every[kind]!)) of them all."))
                outcomes.append((made(divided(plain(size), by: plain(every[kind]!)), decimals: false, lead), written(all)))
            } else if has(#"\bnumber of\b|\bhow many\b"#, ask), named.count == 1, let all = total, let (kind, size) = counted, let share = every[named[0]] {
                lead.append(Step("Find how many altogether", "\(written(size)) \(kind) make \(written(every[kind]!)) of them all.", [MathLine(divided(plain(size), by: plain(every[kind]!)), plain(all))]))
                lead.append(Step("Take the share", "\(named[0].capitalized) is \(written(share)) of them."))
                outcomes.append((made(.multiply([plain(share), plain(all)]), decimals: false, lead), written(share * all)))
            } else if has(#"\bprobability\b"#, ask), named.count == 1, counted == nil, let share = every[named[0]] {
                outcomes.append((made(plain(share), decimals: true, lead), written(share)))
            }
        }
        // Only one way can be right, or the answer is the same whichever way.
        guard let first = outcomes.first, outcomes.allSatisfy({ $0.key == first.key }) else { return nil }
        return first.answer
    }

    /// The unknown probabilities from the links between them and what they add up to.
    private static func solve(_ unknown: [String], _ known: [String: Double], _ links: [(String, String, Double)], _ left: Double) -> [String: Double]? {
        let size = unknown.count
        guard size >= 1, size <= 6 else { return nil }
        var rows: [[Double]] = [Array(repeating: 1, count: size) + [left]]
        for (a, b, factor) in links {
            var row = Array(repeating: 0.0, count: size + 1)
            // a = factor × b
            if let at = unknown.firstIndex(of: a) { row[at] += 1 } else if let value = known[a] { row[size] -= value } else { return nil }
            if let at = unknown.firstIndex(of: b) { row[at] -= factor } else if let value = known[b] { row[size] += factor * value } else { return nil }
            if row[..<size].allSatisfy({ $0 == 0 }) { guard abs(row[size]) < 1e-9 else { return nil }; continue }
            rows.append(row)
        }
        guard rows.count == size else { return nil }
        // Gaussian elimination.
        for column in 0..<size {
            guard let pivot = (column..<size).max(by: { abs(rows[$0][column]) < abs(rows[$1][column]) }), abs(rows[pivot][column]) > 1e-12 else { return nil }
            rows.swapAt(column, pivot)
            for row in 0..<size where row != column {
                let factor = rows[row][column] / rows[column][column]
                for k in column...size { rows[row][k] -= factor * rows[column][k] }
            }
        }
        var result: [String: Double] = [:]
        for (index, name) in unknown.enumerated() {
            let value = rows[index][size] / rows[index][index]
            result[name] = Double(String(format: "%.10g", value)) ?? value
        }
        return result
    }

    // MARK: A list put in a table

    /// "Here are the ages of the 23 people on coach A. (the ages) Complete the table below:
    /// Median, Lower quartile, Upper quartile, Least age 41, Greatest age 79."
    private static func listTable(_ lines: [String], _ text: String) -> Problem? {
        guard let intro = lines.firstIndex(where: { has(#"\bhere (?:are|is)\b"#, $0) }),
              let stated = groups(#"\bthe (\d+) [a-z]+\b|\b(\d+) [a-z]+\b"#, in: lines[intro]), let count = Int(stated[1].isEmpty ? stated[2] : stated[1]),
              let complete = lines.firstIndex(where: { has(#"\bcomplete the table\b"#, $0) }), complete > intro + 1 else { return nil }
        // Nothing else numbered above the list, apart from the question's number.
        guard lines[..<intro].allSatisfy({ isLabel($0) || numbers(in: $0.replacingOccurrences(of: #"^\d{1,2}\s+"#, with: "", options: .regularExpression)).isEmpty }),
              numbers(in: lines[intro]).count == 1 else { return nil }
        var list: [Double] = []
        for line in lines[(intro + 1)..<complete] {
            guard has(#"^\d+(?:\.\d+)?(?:\s+\d+(?:\.\d+)?)*$"#, line) else { return nil }
            list += numbers(in: line)
        }
        guard list.count == count, count >= 5 else { return nil }
        guard numbers(in: lines[complete]).isEmpty else { return nil }
        // The table: its row names, the numbers filled in already, and the empty cells read as junk.
        let rowNames: [(pattern: String, name: String)] = [(#"^median$"#, "median"), (#"^lower quartile$"#, "lower quartile"), (#"^upper quartile$"#, "upper quartile"),
                                                           (#"^inter-? ?quartile range$"#, "interquartile range"), (#"^range$"#, "range"),
                                                           (#"^(?:least|smallest|lowest|minimum)\b[a-z ]*$"#, "least"), (#"^(?:greatest|largest|highest|biggest|maximum)\b[a-z ]*$"#, "greatest")]
        var rows: [String] = [], filled: [Double] = []
        for line in lines[(complete + 1)...] {
            if let row = rowNames.first(where: { has($0.pattern, line) }) { rows.append(row.name) }
            else if has(#"^\d+(?:\.\d+)?$"#, line) { filled.append(Double(line)!) }
            else if numbers(in: line).isEmpty, !has(#"[a-z]{4}"#, line) { continue }
            else { return nil }
        }
        guard rows.contains(where: { ["median", "lower quartile", "upper quartile", "interquartile range"].contains($0) }), Set(rows).count == rows.count else { return nil }
        let sorted = list.sorted()
        let n = Double(count)
        func at(_ place: Double) -> Double? {
            guard place == place.rounded(), place >= 1, place <= n else { return nil }
            return sorted[Int(place) - 1]
        }
        let middle = (n + 1) / 2
        let median = middle == middle.rounded() ? sorted[Int(middle) - 1] : (sorted[Int(n / 2) - 1] + sorted[Int(n / 2)]) / 2
        let wantsQuartiles = rows.contains { $0.contains("quartile") }
        let lower = at((n + 1) / 4), upper = at(3 * (n + 1) / 4)
        // Quartiles only where they fall on a value: other ways of finding them give other answers.
        if wantsQuartiles { guard lower != nil, upper != nil else { return nil } }
        let found: [String: Double] = ["median": median, "lower quartile": lower ?? .nan, "upper quartile": upper ?? .nan,
                                       "interquartile range": (upper ?? .nan) - (lower ?? .nan), "range": sorted.last! - sorted.first!,
                                       "least": sorted.first!, "greatest": sorted.last!]
        // What's filled in already has to match a row, and is left out of the answer.
        var given = Set<String>()
        for value in filled {
            guard let row = rows.first(where: { !given.contains($0) && ["least", "greatest", "range"].contains($0) && same(found[$0]!, value) })
                    ?? rows.first(where: { !given.contains($0) && same(found[$0]!, value) }) else { return nil }
            given.insert(row)
        }
        let wanted = rows.filter { !given.contains($0) }
        guard !wanted.isEmpty else { return nil }
        let order = ["least", "lower quartile", "median", "upper quartile", "greatest", "range", "interquartile range"]
        let answer = wanted.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }.map { "\($0) \(written(found[$0]!))" }.joined(separator: ", ")
        var lead = [Step("Put them in order", "There are \(count) of them.", [MathLine(.symbol(sorted.map(written).joined(separator: " ")))]),
                    Step("Find the middle", middle == middle.rounded() ? "The median is the \(written(middle))th value." : "The median is halfway between the two middle values.", [MathLine(.symbol("median"), plain(median))])]
        if wantsQuartiles {
            lead.append(Step("Find the quartiles", "The lower quartile is the \(written((n + 1) / 4))th value and the upper quartile the \(written(3 * (n + 1) / 4))th.",
                             [MathLine(.symbol("lower quartile"), plain(lower!)), MathLine(.symbol("upper quartile"), plain(upper!))]))
        }
        return told("table", answer.prefix(1).uppercased() + answer.dropFirst(), lead)
    }

    // MARK: Relative frequency from counts

    /// "A coin is thrown 50 times. It lands on heads 31 times. Write down the relative frequency
    /// it lands on heads." Also how many tries from a relative frequency and a count, and how many
    /// to expect from a relative frequency and a number of tries.
    private static func relative(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\brelative frequency\b"#, text), !has(#"\btable\b|\bgraph\b|\bchart\b|\bafter every\b"#, text) else { return nil }
        let said = sentences(lines)
        guard let askIndex = said.lastIndex(where: { has(#"\b(?:work out|write down|find|calculate|what is|how many)\b"#, $0) }) else { return nil }
        let ask = said[askIndex]
        let facts = said.enumerated().filter { $0.offset != askIndex }.map(\.element)
        let values = numbers(in: facts.joined(separator: " "))
        guard numbers(in: ask).isEmpty || has(#"\b(?:expect|how many)\b"#, ask) else { return nil }
        let tries = #"\b(?:thrown|spun|rolled|flipped|tossed|tested|played|carried out|repeated|batch|sample|samples|picks?|picked|chooses|chosen|takes|taken|asks|asked|times|trials)\b"#
        guard has(tries, text) else { return nil }
        let stop: Set<String> = ["the", "that", "this", "these", "with", "from", "lands", "land", "landed", "will", "would", "write", "down", "work", "relative", "frequency", "they", "were", "was", "are", "is", "it", "of", "on", "landing", "getting", "times", "time", "a", "an", "in", "its", "has", "have", "be", "being"]
        func content(_ phrase: String) -> [String] {
            phrase.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 && !stop.contains($0) }.map(stem)
        }
        // The outcome the question is about: every word of it has to be in the sentence giving its number.
        func matches(_ outcome: [String], _ sentence: String) -> Bool {
            let words = Set(content(sentence))
            return !outcome.isEmpty && outcome.allSatisfy { words.contains($0) || $0 == "not" } && (outcome.contains("not") == has(#"\bnot\b"#, sentence))
        }
        // How many, written as a decimal where it ends and as a fraction where it doesn't.
        func share(_ top: Double, _ bottom: Double) -> Bool {
            var b = Int(bottom.rounded()), t = Int(top.rounded())
            func gcd(_ x: Int, _ y: Int) -> Int { y == 0 ? x : gcd(y, x % y) }
            let g = gcd(t, b); b /= max(g, 1); t /= max(g, 1)
            while b % 2 == 0 { b /= 2 }
            while b % 5 == 0 { b /= 5 }
            return b == 1
        }
        if has(#"\brelative frequency\b"#, ask), let tail = groups(#"\brelative frequency (?:that |of |it |for )?(.+)$"#, in: ask)?[1] {
            // Both counts given: the relative frequency is the one out of the other.
            guard values.count == 2, values.allSatisfy({ $0 == $0.rounded() && $0 > 0 }) else { return nil }
            let count = values.min()!, whole = values.max()!
            guard let countSentence = facts.first(where: { numbers(in: $0).contains { same($0, count) } }),
                  let wholeSentence = facts.first(where: { numbers(in: $0).contains { same($0, whole) } }) else { return nil }
            // What the question asks about, less the words that only describe the tries ("a coin").
            let about = Set(content(wholeSentence))
            let outcome = content(tail).filter { countSentence == wholeSentence || !about.contains($0) }
            guard matches(outcome, countSentence) else { return nil }
            guard facts.contains(where: { has(tries, $0) && numbers(in: $0).contains { same($0, whole) } }) else { return nil }
            return made(divided(plain(count), by: plain(whole)), decimals: share(count, whole),
                        [Step("Out of all the tries", "It happened \(written(count)) times out of \(written(whole)).")])
        }
        // A relative frequency given.
        let givens = facts.filter { has(#"\brelative frequency\b"#, $0) }
        guard givens.count == 1, let given = givens.first, let rate = numbers(in: given).first(where: { $0 > 0 && $0 < 1 }), numbers(in: given).count == 1 else { return nil }
        let outcome = content(groups(#"\brelative frequency (?:of |that |for )?(?:getting |landing on |a |an )?(.+?) (?:is|was)\b"#, in: given)?[1] ?? "")
        let rest = values.filter { !same($0, rate) }
        guard rest.count == 1, let count = rest.first, count == count.rounded(), count > 0 else { return nil }
        if has(#"\b(?:number of times|how many times)\b"#, ask), has(#"\b(?:thrown|spun|rolled|flipped|tossed|played|carried out|repeated)\b"#, ask) {
            // "A coin lands on Tails 200 times. The relative frequency of Tails is 0.4. Work out the number of times the coin was thrown."
            guard let place = facts.first(where: { numbers(in: $0).contains { same($0, count) } }), matches(outcome, place) else { return nil }
            let whole = count / rate
            guard abs(whole - whole.rounded()) < 1e-6 else { return nil }
            return made(divided(plain(count), by: plain(rate)), decimals: false,
                        [Step("Work back from the relative frequency", "\(written(count)) is \(written(rate)) of all the tries, so divide by \(written(rate)).")])
        }
        if has(#"\bhow many\b|\bnumber of\b"#, ask), !has(#"\bthrown|spun|rolled|flipped|tossed\b"#, ask) {
            // "Elena spins the spinner 125 times. The relative frequency of red is 0.32. How many times did it land on red?"
            guard matches(outcome, ask) || outcome.allSatisfy({ content(ask).contains($0) }), !outcome.isEmpty,
                  facts.contains(where: { has(tries, $0) && numbers(in: $0).contains { same($0, count) } }) else { return nil }
            let value = rate * count
            var lead = [Step("Use the relative frequency", "Expect \(written(rate)) of the \(written(count)) to be this.")]
            let sum = Expr.multiply([plain(rate), plain(count)])
            guard abs(value - value.rounded()) > 1e-9 else { return made(sum, decimals: true, lead) }
            lead += [Step("Work it out", "", [MathLine(sum, plain(value))]), Step("Round it", "A number of times is a whole number.")]
            return made(plain(value.rounded()), decimals: false, lead)
        }
        return nil
    }

    // MARK: The mean of the rest

    /// "In a class of 28 students the mean height of the 12 boys is 1.58 metres, the mean height of
    /// all 28 students is 1.52 metres. Work out the mean height of the girls." Also "There are 10 boys
    /// and 20 girls … the mean mark for all the class is 60 …", "the mean weight of 3 of the parcels
    /// is 2 kg. Work out the mean weight of the other 5 parcels."
    private static func restMean(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bmean\b"#, text), !has(#"\btable\b|\bfrequency\b|\bratio\b|:"#, text) else { return nil }
        let body = lines.filter { !isLabel($0) }.joined(separator: " ")
        let unit = #"(?: ?(?:kg|g|cm|m|mm|km|metres?|grams?|kilograms?|years?|minutes?|seconds?|hours?|points?|marks?|%|p))?"#
        let statement = "\\bmean(?: [a-z]+)? (?:of|for) (all )?(?:the )?(?:(\\d+) )?(?:of the )?([a-z]+) (?:is|was|are|were) £?(\(number))\(unit)\\b"
        let found = every(statement, in: body)
        guard found.count == 2 else { return nil }
        guard let ask = groups(#"\b(?:work out|find|calculate|what is)\b[^.?]*?\bmean(?: [a-z]+)? (?:of|for) (?:the )?(other |remaining |rest of the )?(?:(\d+) )?([a-z]+)"#, in: body) else { return nil }
        // How many in each named group: "28 students", "10 boys and 20 girls", "8 parcels".
        var sizes: [String: Double] = [:]
        for match in every(#"\b(\d+) (?:of the )?([a-z]+)\b"#, in: body) {
            guard let size = Double(match[1]) else { continue }
            let word = stem(match[2])
            if let known = sizes[word], !same(known, size) { sizes[word] = -1 } else { sizes[word] = size }
        }
        struct Said { var all: Bool; var size: Double?; var word: String; var mean: Double }
        let both = found.map { Said(all: !$0[1].isEmpty, size: Double($0[2]), word: stem($0[3]), mean: Double($0[4])!) }
        // The whole: the one said of "all", or the bigger of two of the same thing.
        let wholeIndex: Int
        if both[0].all != both[1].all { wholeIndex = both[0].all ? 0 : 1 }
        else if !both[0].all, both[0].word == both[1].word, let a = both[0].size, let b = both[1].size, !same(a, b) { wholeIndex = a > b ? 0 : 1 }
        else { return nil }
        let whole = both[wholeIndex], part = both[1 - wholeIndex]
        let partSize = part.size ?? sizes[part.word].flatMap { $0 > 0 ? $0 : nil }
        let askWord = stem(ask[3]), askSize = Double(ask[2])
        guard let partSize, askWord != part.word || !ask[1].isEmpty else { return nil }
        var wholeSize = whole.size ?? sizes[whole.word].flatMap { $0 > 0 ? $0 : nil }
        if wholeSize == nil, let other = sizes[askWord], other > 0, sizes[part.word] == partSize {
            // "10 boys and 20 girls" and "the mean mark for all the class": the class is both.
            wholeSize = other + partSize
        }
        guard let wholeSize, wholeSize > partSize, partSize >= 1 else { return nil }
        let restSize = wholeSize - partSize
        if let askSize { guard same(askSize, restSize) else { return nil } }
        if let named = sizes[askWord], named > 0, askWord != whole.word, askWord != part.word { guard same(named, restSize) else { return nil } }
        var used = [wholeSize, partSize, restSize, whole.mean, part.mean]
        if let places = groups(#"\bto (\d) (?:decimal places?|significant figures?|d\.p\.|s\.f\.)"#, in: body), let size = Double(places[1]) { used.append(size) }
        guard numbers(in: body).allSatisfy({ size in used.contains { same($0, size) } }) else { return nil }
        let total = wholeSize * whole.mean, some = partSize * part.mean
        return rounding(made(divided(plain(total - some), by: plain(restSize)), decimals: true,
                             [Step("Find each total", "The mean times how many there are is the total.",
                                   [MathLine(.multiply([plain(wholeSize), plain(whole.mean)]), plain(total)), MathLine(.multiply([plain(partSize), plain(part.mean)]), plain(some))]),
                              Step("Take away the part you know", "What's left belongs to the other \(written(restSize)).",
                                   [MathLine(.add([plain(total), .multiply([.minusOne, plain(some)])]), plain(total - some))]),
                              Step("Share out", "Divide by the \(written(restSize)) of them.")]), (total - some) / restSize, text)
    }

    // MARK: A table of groups and their means

    /// "Junior: 30 members, mean height 1.6 m; Senior: 20 members, mean height 2.05 m. Work out the
    /// mean height of all 50 members."
    private static func groupMeans(_ lines: [String], _ text: String) -> Problem? {
        guard has(#"\bmean\b"#, text), has(#"\bnumber\b"#, text),
              let ask = groups(#"\b(?:work out|find|calculate)\b[^.?]*?\bmean(?: [a-z]+)? of (?:all )?(?:the )?(\d+)\b"#, in: text), let stated = Double(ask[1]) else { return nil }
        // A mean is a number with a unit or a decimal point; how many is a whole number standing alone.
        var names: [Int] = [], counts: [(Int, Double)] = [], means: [(Int, Double)] = []
        for (index, line) in lines.enumerated() where names.isEmpty ? !has(#"^[\d.]+"#, line) : true {
            if let found = groups(#"^(\d+\.\d+|\d+) ?(m|cm|kg|g|km|mm|s|minutes|years|marks|points|£)$|^£(\d+(?:\.\d+)?)$"#, in: line), let value = Double(found[1].isEmpty ? found[3] : found[1]) {
                means.append((index, value))
            } else if has(#"^\d+\.\d+$"#, line), let value = Double(line) {
                means.append((index, value))
            } else if has(#"^\d+$"#, line), !isLabel(line) || Double(line)! >= 10, let value = Double(line) {
                counts.append((index, value))
            } else if has(#"^[A-Z][a-z]+(?: [A-Z0-9])?$"#, line), !has(#"^(?:Number|Mean|Members?|Club|Group|Total)$"#, line) {
                names.append(index)
            }
        }
        guard names.count >= 2, counts.count == names.count, means.count == names.count else { return nil }
        // Each row's numbers come after its name and before the name after next, in the order read.
        for k in names.indices {
            let after = names[k], limit = k + 2 < names.count ? names[k + 2] : lines.count
            for item in [counts[k].0, means[k].0] { guard item > after, item < limit else { return nil } }
            if k + 1 < names.count { guard counts[k].0 < names[k + 1] || means[k].0 < names[k + 1] else { return nil } }
        }
        let sizes = counts.map(\.1), values = means.map(\.1)
        guard same(sizes.reduce(0, +), stated) else { return nil }
        // Nothing else numbered in the question.
        let used = sizes + values + [stated]
        let asked = lines.filter { !isLabel($0) && has(#"[a-z]{3}"#, $0) }.joined(separator: " ")
        var allowed = used
        if let places = groups(#"\bto (\d) (?:decimal places?|significant figures?|d\.p\.|s\.f\.)"#, in: asked), let size = Double(places[1]) { allowed.append(size) }
        guard numbers(in: asked).allSatisfy({ size in allowed.contains { same($0, size) } }) else { return nil }
        let totals = zip(sizes, values).map { $0 * $1 }
        let sum = totals.reduce(0, +)
        return rounding(made(divided(plain(sum), by: plain(stated)), decimals: true,
                             [Step("Find each group's total", "The mean times how many there are.", zip(sizes, values).map { MathLine(.multiply([plain($0), plain($1)]), plain($0 * $1)) }),
                              Step("Add them up", "", [MathLine(.add(totals.map(plain)), plain(sum))]),
                              Step("Share out", "Divide by all \(written(stated)) of them.")]), sum / stated, text)
    }
}
