import Foundation

/// What the words round a piece of maths ask of it. "A curve has the equation y = (x − 3)² − 8.
/// Write down the coordinates of the turning point" isn't asking for the bracket to be
/// multiplied out, though that's all the maths alone says to do. The answer to what's asked
/// goes first, and the maths worked out as it stands stays as another answer beside it.
enum Asked {
    /// A line read in the area: what it says, how far down it is and how far in from the left.
    typealias Row = (text: String, height: CGFloat, left: CGFloat)

    /// The answers to show for the maths found in an area. `lines` is every line read there,
    /// top to bottom, `heights` is how far down each of `solutions` is, and `pointer` how far
    /// down the pointer is. An answer that only says a number from the question back is left
    /// out, so an empty result means nothing there was really worked out.
    /// `across` is how far in from the left the pointer is and `lefts` where each of `solutions`
    /// starts, for telling apart parts printed side by side: (a), (b) and (c) along one row.
    static func answers(_ solutions: [Solution], at heights: [CGFloat], lefts: [CGFloat]? = nil, primary: Int, lines: [Row], pointer: CGFloat,
                        across: CGFloat? = nil, angles: AngleUnit) -> (solutions: [Solution], primary: Int) {
        guard !lines.isEmpty, solutions.count == heights.count else { return (solutions, primary) }
        let sorted = sort(solutions, at: heights, lefts: lefts, lines: lines, pointer: pointer, across: across, angles: angles)
        // (Not what's asked for a second time: a piece of maths read together with its
        // instruction comes out as the same answer.)
        // Where the questions are numbered, only the one pointed at is answered: a sum in
        // the question underneath isn't this one's answer.
        // (And beside an answer to what's asked, a number written as a power is one of the
        // answers to choose from, not a sum.)
        let unique = sorted.rest.filter { item in
            !item.isLone && (!sorted.isNumbered || item.inQuestion) && !(isPower(item.solution) && !sorted.asked.isEmpty)
                && !sorted.asked.contains { written($0) == written(item.solution) } && !(sorted.isIterating && isEquation(item.solution)) && !sorted.isArgued
        }
        // (The same sum written twice in a question is one answer.)
        // With nothing made of what the words ask, maths found in them is only the answer
        // where a plain instruction is about it ("Work out 3/4 + 1/8", "Solve the equation").
        // Maths quoted in a sentence that asks for something else isn't the question: "The line
        // L has equation y = 3x + 2. Find the equation of the line perpendicular to L…".
        var shown = Set<String>()
        let rest = unique.filter { (!sorted.asked.isEmpty || $0.isInstructed) && shown.insert(written($0.solution)).inserted }
        let result = sorted.asked + rest.map(\.solution)
        if !sorted.asked.isEmpty || result.isEmpty { return (result, 0) }
        if let index = rest.firstIndex(where: { $0.was == primary }) { return (result, index) }
        let nearest = rest.indices.min { abs(rest[$0].height - pointer) < abs(rest[$1].height - pointer) }
        return (result, nearest ?? 0)
    }

    /// The answers to show when the question in words was answered already: that answer, then
    /// the maths of the same question worked out as it stands, each as another answer.
    static func answers(after lead: Solution, _ solutions: [Solution], at heights: [CGFloat], lefts: [CGFloat]? = nil, lines: [Row], pointer: CGFloat,
                        across: CGFloat? = nil, angles: AngleUnit) -> [Solution] {
        guard !lines.isEmpty, solutions.count == heights.count else { return [lead] }
        let sorted = sort(solutions, at: heights, lefts: lefts, lines: lines, pointer: pointer, across: across, angles: angles)
        // The answer given the way the words ask for it ("in terms of π", "to 2 decimal places") goes first.
        // (A bare number where every answer to choose from is a percentage or an angle takes that sign.)
        var lead = lead
        for sign in ["%", "°"] where sorted.words.contains("«\(sign)»") {
            if lead.answers.count == 1, lead.answers[0].suffix == nil, lead.answers[0].parts.count == 1, lead.answers[0].parts[0].number != nil { lead.answers[0].suffix = sign }
        }
        var result = forms(sorted.words, lead, angles) + [lead]
        for solution in sorted.asked + sorted.rest.filter({ $0.inQuestion && !$0.isLone && !isPower($0.solution) && !(sorted.isIterating && isEquation($0.solution)) }).map(\.solution)
        where !result.contains(where: { written($0) == written(solution) }) {
            result.append(solution)
        }
        return result
    }

    /// Whether what was worked out is one whole number to a whole power and nothing else.
    private static func isPower(_ solution: Solution) -> Bool {
        guard case .evaluate(let expr) = solution.problem.kind, case .power(let base, let exponent) = expr else { return false }
        return base.number?.integer != nil && exponent.number?.integer != nil
    }

    /// "Circle the…", "Which of these…": one of several answers is to be picked. (Not the
    /// circle of "the diameter of the circle".)
    private static let choosing = #"\bcircle (?:the|your|one|two|all|a|an)\b|\bwhich (?:of|one|is|expression|equation|number|value|fraction)\b|\bchoose\b|\btick\b|\bselect\b"#

    /// Words that go between an instruction and its maths without changing what's asked:
    /// "Work out the value of", "Solve the simultaneous equations", "use your calculator to".
    private static let connecting: Set<String> = ["the", "value", "values", "of", "each", "following", "these", "this", "equation", "equations", "simultaneous", "expression",
                                                  "expressions", "fully", "completely", "and", "simplify", "an", "estimate", "for", "exact", "answer", "as", "a", "single",
                                                  "fraction", "power", "sum", "product", "below", "inequality", "inequalities", "out", "down", "your", "calculator", "to",
                                                  "use", "in", "its", "simplest", "form", "pair", "is", "what", "now", "then", "hence", "also", "possible", "all", "both", "two",
                                                  "solutions", "solution", "roots", "denominator", "denominators", "calculation", "calculations", "sums", "if",
                                                  "where", "when", "which", "such", "that", "given", "satisfy", "satisfies", "satisfying", "size", "sizes", "angle", "length"]
    private static let instructing = ["work out", "calculate", "evaluate", "simplify", "solve", "factorise", "factorize", "expand", "compute", "find", "determine", "what is",
                                      "write down", "circle", "estimate", "rationalise", "rationalize"]

    /// Instructions whose object can only be the maths itself, however the rest of the
    /// sentence is worded: "Solve this quadratic equation by factorisation."
    private static let strong: Set<String> = ["solve", "simplify", "factorise", "factorize", "expand", "rationalise", "rationalize", "evaluate"]

    /// Whether the last sentence of some words starts with one of those.
    private static func startsStrong(_ words: String) -> Bool {
        guard let sentence = words.lowercased().components(separatedBy: CharacterSet(charactersIn: ".?\n")).last(where: { $0.contains(where: \.isLetter) }) else { return false }
        var tokens = sentence.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",:;()")) }.filter { !$0.isEmpty }
        while let first = tokens.first, first.allSatisfy({ $0.isNumber }) || ["hence", "now", "then", "also", "and"].contains(first) || first.range(of: #"^\(?[a-z]\)$"#, options: .regularExpression) != nil { tokens.removeFirst() }
        return tokens.first.map { strong.contains($0) } ?? false
    }

    /// Whether words end in a plain instruction with only such words after it.
    private static func endsInInstruction(_ words: String) -> Bool {
        let tokens = words.lowercased().split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;()")) }.filter { !$0.isEmpty }
        var index = tokens.count
        // ("Work out the two values of x where": a letter is what the maths is solved for.)
        while index > 0, connecting.contains(tokens[index - 1]) || (tokens[index - 1].count == 1 && tokens[index - 1].first?.isLetter == true) { index -= 1 }
        for verb in instructing {
            let parts = verb.split(separator: " ").map(String.init)
            // (The second word of "work out" or "write down" was stepped over as a connecting word.)
            for stop in index...tokens.count where stop >= parts.count && Array(tokens[(stop - parts.count)..<stop]) == parts { return true }
        }
        return false
    }

    /// "Solve the equation.", "Work out the value of x.", "Find a and b.": an instruction
    /// about maths written somewhere else in the part, and the letters it names.
    private static func plainInstruction(in text: String) -> Set<String>? {
        for sentence in text.lowercased().components(separatedBy: CharacterSet(charactersIn: ".?\n")) {
            var tokens = sentence.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",:;()")) }.filter { !$0.isEmpty }
            if let label = tokens.first, label.count <= 2, label.allSatisfy({ $0.isNumber }) { tokens.removeFirst() }
            if tokens.first == "hence" { tokens.removeFirst() }
            guard let verb = instructing.first(where: { verb in
                let parts = verb.split(separator: " ").map(String.init)
                return tokens.count >= parts.count && Array(tokens.prefix(parts.count)) == parts
            }) else { continue }
            let objects = Array(tokens.dropFirst(verb.split(separator: " ").count))
            func isLetter(_ place: Int) -> Bool {
                let token = objects[place]
                guard token.count == 1, token.first?.isLetter == true else { return false }
                // ("a" is a letter in "find a and b" and "the value of a", not in "find a value".)
                if token != "a" { return true }
                return place == objects.count - 1 || objects[place + 1] == "and" || (place > 0 && ["and", "of"].contains(objects[place - 1]))
            }
            // ("Work out the value of", left hanging, is about the maths that follows it.)
            if let last = objects.last, ["of", "for", "to", "the", "a", "an", "and", "is"].contains(last), !isLetter(objects.count - 1) { continue }
            guard strong.contains(verb) || objects.indices.allSatisfy({ connecting.contains(objects[$0]) || isLetter($0) }) else { continue }
            return Set(objects.indices.filter(isLetter).map { objects[$0] })
        }
        return nil
    }

    /// The words and the maths of a line, in turn: "Given that", "3x + 5 = 20,", "work out the value of", "2x".
    private static func runs(of text: String) -> [(text: String, isMaths: Bool)] {
        var result: [(text: String, isMaths: Bool)] = []
        for token in text.split(separator: " ") {
            // (A recurring decimal as the reader writes it, rec(0.1,5), is a number.)
            let isMaths = (!isWord(token) || token.hasPrefix("rec(")) && token.contains(where: { $0.isNumber || $0.isLetter || "√π".contains($0) })
            if let last = result.last, last.isMaths == isMaths || !token.contains(where: { $0.isNumber || $0.isLetter }) {
                result[result.count - 1].text += " " + token
            } else {
                result.append((String(token), isMaths))
            }
        }
        return result
    }

    /// Whether a piece of maths found among words is what a plain instruction is about.
    private static func isInstructed(_ solution: Solution, on row: Int, rows: [Row], from first: Int, labels: Set<Int>, lettered: Set<Int>, part: String) -> Bool {
        let text = plain(solution.problem.text)
        let lower = text.lowercased()
        // One equation turned round to give a letter in terms of the others is only what's
        // asked where the words ask for that: a subject, a rearrangement, "in terms of".
        if case .solve(let equations, _) = solution.problem.kind, equations.count == 1, solution.answerSets == nil,
           solution.answers.contains(where: { !($0.parts.last?.symbols.isEmpty ?? true) }),
           (part + " " + text).range(of: #"\bsubject\b|\brearrange|\bin terms of\b|\bformula for\b|\bexpress\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            return false
        }
        // Read together with its own instruction: "Solve 5x − 2 = 13".
        if instructing.contains(where: { lower.hasPrefix($0 + " ") }) || ["expand and simplify ", "simplify fully ", "factorise fully "].contains(where: { lower.hasPrefix($0) }) { return true }
        if case .worded = solution.problem.kind { return true }
        guard rows.indices.contains(row) else { return false }
        var line = unlettered(unheaded(rows[row].text))
        if let number = line.range(of: #"^\d{1,2}[.:]? (?=[A-Za-z(])"#, options: .regularExpression) { line = String(line[number.upperBound...]) }
        let pieces = runs(of: line)
        let target = squeezed(text).lowercased()
        let maths = pieces.indices.filter { pieces[$0].isMaths }
        let place = maths.first { index in
            let run = squeezed(pieces[index].text).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:?"))
            return run.count >= 2 && (run.contains(target) || target.contains(run))
        } ?? maths.first
        var before = ""
        if let place, place > 0 {
            // The words before it, with a lone letter among them ("the two values of x where").
            var start = place
            while start > 0, !pieces[start - 1].isMaths || squeezed(pieces[start - 1].text).count <= 2 { start -= 1 }
            before = pieces[start..<place].map(\.text).joined(separator: " ")
        }
        if before.isEmpty {
            // The maths starts its line: the instruction is the line of words above it
            // ("Solve the simultaneous equations", then the two equations).
            // (Other parts of a list aren't the instruction, whatever was made of them: from
            // the start of its own part the search goes straight to the question's opening lines.)
            let starts = lettered.sorted()
            let own = starts.last { $0 <= row }
            var above = row - 1
            while above >= first {
                if let own, above < own, let opening = starts.first, above >= opening {
                    above = opening - 1
                } else if labels.contains(above) || !rows[above].text.split(separator: " ").contains(where: isWord) {
                    above -= 1
                } else {
                    break
                }
            }
            if above >= first {
                let heading = unlettered(unheaded(rows[above].text))
                let words = runs(of: heading)
                if let last = words.last, !last.isMaths { before = last.text }
                // One instruction over a list: "Work out each of the following", "Rationalise
                // the denominators for each of the following".
                let lowered = heading.lowercased()
                if instructing.contains(where: { lowered.hasPrefix($0 + " ") }), lowered.range(of: #"\bfollowing\b|\beach of these\b|\bbelow\b"#, options: .regularExpression) != nil { return true }
            }
        }
        if endsInInstruction(before) || startsStrong(before) { return true }
        // "Convert 0.15 to a fraction", "Write 3.2 × 10⁴ as an ordinary number", "Express 48 as
        // a product of prime factors": the maths, then the way it's to be written.
        var after = ""
        if let place, place + 1 < pieces.count, !pieces[place + 1].isMaths {
            after = pieces[place + 1].text
        } else if rows.indices.contains(row + 1), !labels.contains(row + 1) {
            after = runs(of: rows[row + 1].text).first.flatMap { $0.isMaths ? nil : $0.text } ?? ""
        }
        let verb = before.lowercased().split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;()")) }.last { !connecting.contains($0) } ?? ""
        if ["write", "convert", "express", "change", "give", "round"].contains(verb),
           after.lowercased().range(of: #"^\W*(?:as|to|in|into|correct to)\b"#, options: .regularExpression) != nil { return true }
        // An instruction of its own about the maths above or below it: "Solve the equation."
        guard let letters = plainInstruction(in: part) else { return false }
        if letters.isEmpty { return true }
        // (One that names letters wants those letters, as numbers.)
        let lines = solution.answerSets.map { $0.flatMap { $0 } } ?? solution.answers
        return !lines.isEmpty && lines.allSatisfy { line in
            line.parts.count == 2 && letters.contains(Format.text(line.parts[0])) && (line.parts.last?.symbols.isEmpty ?? false)
        }
    }

    /// One side of a ratio, "(2 × 10³) : (5 × 10⁻¹)", isn't a sum by itself.
    private static func isRatioSide(_ solution: Solution, in line: String) -> Bool {
        let whole = squeezed(line).lowercased(), target = squeezed(plain(solution.problem.text)).lowercased()
        guard !target.isEmpty, let range = whole.range(of: target) else { return false }
        if range.upperBound < whole.endIndex, whole[range.upperBound] == ":" { return true }
        return range.lowerBound > whole.startIndex && whole[whole.index(before: range.lowerBound)] == ":"
    }

    private static func isEquation(_ solution: Solution) -> Bool {
        if case .solve = solution.problem.kind { return true }
        return false
    }

    /// An expression given back as it was read, nothing worked out: a unit off an answer line (m/s).
    /// Or a statement, "S = 1/2", said back as it is.
    private static func isUnchanged(_ solution: Solution) -> Bool {
        let text = plain(solution.problem.text)
        let unit = #"(?:mm|cm|km|m|kg|g|mg|ml|l|s|h|mph|°C?)(?:\^?[23])?"#
        if text.range(of: "^\\s*\(unit)(?:\\s?/\\s?\(unit))?\\s*(?:\\[\\d+\\])?\\s*$", options: .regularExpression) != nil { return true }
        switch solution.problem.kind {
        case .simplify(let expr):
            guard solution.answers.count == 1, let answer = solution.answers[0].parts.last else { return false }
            return squeezed(Format.text(answer)) == squeezed(Format.text(expr))
        case .solve(let equations, _):
            return equations.count == 1 && solution.answerSets == nil && written(solution) == squeezed(text).replacingOccurrences(of: "∕", with: "/")
        default:
            return false
        }
    }

    /// "in the form", which reading sometimes runs together.
    private static let formWords = #"in ?the ?form "#

    /// An answer as it's written, for telling whether two are the same.
    private static func written(_ solution: Solution) -> String {
        squeezed(solution.answerText).replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "∕", with: "/")
    }

    /// The algebra in a piece of text that has words in it too: "y = (x − 3)^2 − 8" out of
    /// "y = (x − 3)^2 − 8 Write down the coordinates of the turning point". Not sums of
    /// numbers alone, which are part of what the words say, and not a form to write an answer in.
    private static func algebra(in text: String) -> [String] {
        var runs: [String] = []
        var current: [Substring] = []
        var isForm = false
        var last: [Substring] = []
        func close() {
            var run = current.joined(separator: " ")
            while let end = run.last, ".,;:?".contains(end) { run.removeLast() }
            if !isForm, run.count >= 3, run.contains(where: \.isLetter), run.contains(where: { $0.isNumber || "=+-^(".contains($0) }) { runs.append(run) }
            current = []
        }
        for token in text.split(separator: " ") {
            if isWord(token) {
                if !current.isEmpty { close() }
                last.append(token)
                continue
            }
            if current.isEmpty { isForm = last.suffix(3).joined().lowercased().hasSuffix("intheform") }
            current.append(token)
            last = []
        }
        if !current.isEmpty { close() }
        return runs
    }

    /// The lines of the question the pointer is in: the part pointed at, with the lines the
    /// question starts with; or all of it when it's those lines that are pointed at. Every
    /// line there is when no question's number is in view.
    /// `whole` is for every part of that question, whichever is pointed at.
    static func pointed(_ lines: [Row], pointer: CGFloat, across: CGFloat? = nil, whole: Bool = false) -> String {
        guard !lines.isEmpty else { return "" }
        let given = lines
        let lines = arranged(lines)
        let layout = layout(lines.map { (text: plain($0.text), height: $0.height, left: $0.left) }, pointer: pointer, across: across)
        var chosen = Set(layout.stem)
        for part in layout.pointed.isEmpty || whole ? layout.parts : layout.pointed { chosen.formUnion(part) }
        return inOrder(chosen.filter { !layout.labels.contains($0) }.map { lines[$0] }, of: given).map { unheaded($0.text) }.joined(separator: "\n")
    }

    /// Lines in the order they were handed over in (the solvers of words were written
    /// against that order), not the order they're arranged in for finding the parts.
    private static func inOrder(_ chosen: [Row], of given: [Row]) -> [Row] {
        var left = chosen
        var result: [Row] = []
        for line in given {
            if let place = left.firstIndex(where: { $0.text == line.text && $0.height == line.height && $0.left == line.left }) {
                result.append(left.remove(at: place))
            }
        }
        return result + left
    }

    /// The lines a question opens with that are further up the page than `above`: what a
    /// worksheet says once over a row of drawings ("Find x for each of the triangles below"),
    /// for the drawing at that place. Nothing where no question's number is in view.
    static func opening(_ lines: [Row], at height: CGFloat, across: CGFloat? = nil, above: CGFloat) -> String {
        guard !lines.isEmpty else { return "" }
        let lines = arranged(lines)
        let layout = layout(lines.map { (text: plain($0.text), height: $0.height, left: $0.left) }, pointer: height, across: across)
        guard layout.isNumbered else { return "" }
        return layout.stem.filter { !layout.labels.contains($0) && lines[$0].height < above }.map { unheaded(lines[$0].text) }.joined(separator: "\n")
    }

    /// The lines of answer choices in the part pointed at, as they were handed in: a line
    /// misread there is one of the answers to pick from, not something the question says.
    static func choiceLines(_ lines: [Row], pointer: CGFloat, across: CGFloat? = nil) -> Set<String> {
        guard !lines.isEmpty else { return [] }
        let arranged = arranged(lines)
        let rows = arranged.map { (text: plain($0.text), height: $0.height, left: $0.left) }
        let layout = layout(rows, pointer: pointer, across: across)
        let parts = layout.pointed.isEmpty ? layout.parts : layout.pointed
        return Set(choiceRows(in: rows, parts: parts, labels: layout.labels) { _ in 0 }.map { arranged[$0].text })
    }

    /// The answers to choose from, on lines of their own under "Circle the…" or "Which of
    /// these…": lines below the sentence, with several things on them or several such lines.
    /// (One piece of maths that only finishes the sentence isn't a choice.) `count` is how
    /// many pieces of maths were found on a line.
    private static func choiceRows(in rows: [Row], parts: [Range<Int>], labels: Set<Int>, count: (Int) -> Int) -> Set<Int> {
        var choices = Set<Int>()
        for part in parts {
            guard let asking = part.first(where: { rows[$0].text.range(of: choosing, options: [.regularExpression, .caseInsensitive]) != nil }) else { continue }
            let below = part.filter { index in
                index > asking && !labels.contains(index) && abs(rows[index].height - rows[asking].height) > 7
                    && !rows[index].text.split(separator: " ").contains(where: isWord) && !isMarks(rows[index].text)
            }
            func isSeveral(_ index: Int) -> Bool {
                let text = rows[index].text
                let numbers = text.split(separator: " ").filter { $0.range(of: #"^-?\d+(?:[./]\(?\d+\)?)?%?$"#, options: .regularExpression) != nil }.count
                return numbers >= 3 || text.filter({ $0 == "=" }).count >= 2 || count(index) >= 2
            }
            if below.count >= 2 || below.contains(where: isSeveral) { choices.formUnion(below) }
        }
        return choices
    }

    /// The lines in reading order: top to bottom, and those level with each other left to right.
    private static func arranged(_ lines: [Row]) -> [Row] {
        let sorted = lines.enumerated().sorted { $0.element.height != $1.element.height ? $0.element.height < $1.element.height : $0.offset < $1.offset }.map(\.element)
        var levels: [[Row]] = [], level: [(offset: Int, element: Row)] = []
        func close() {
            if !level.isEmpty { levels.append(level.sorted { $0.element.left != $1.element.left ? $0.element.left < $1.element.left : $0.offset < $1.offset }.map(\.element)) }
            level = []
        }
        for (offset, line) in sorted.enumerated() {
            if let first = level.first, abs(line.height - first.element.height) > 5 { close() }
            level.append((offset, line))
        }
        close()
        // A row of parts' letters with each part's maths just under it (a fraction is taller
        // than its letter, so it reads as the line below): each letter, then what's under it.
        func isLetter(_ row: Row) -> Bool { plain(row.text).range(of: #"^\([A-Za-z01|]?\)$"#, options: .regularExpression) != nil }
        var result: [Row] = []
        var index = 0
        while index < levels.count {
            let letters = levels[index]
            if letters.count >= 2, letters.allSatisfy(isLetter), index + 1 < levels.count, levels[index + 1][0].height - letters[0].height <= 30,
               !levels[index + 1].contains(where: isLetter) {
                let under = levels[index + 1]
                result += under.filter { $0.left < letters[0].left - 4 }
                for (place, letter) in letters.enumerated() {
                    let end = place + 1 < letters.count ? letters[place + 1].left : .infinity
                    result.append(letter)
                    result += under.filter { $0.left >= letter.left - 4 && $0.left < end - 4 }
                }
                index += 2
            } else {
                result += letters
                index += 1
            }
        }
        return result
    }

    /// A line without the heading some worksheets start a question with: "Question 14:".
    private static func unheaded(_ text: String) -> String {
        guard let heading = text.range(of: #"^\s*Q(?:uestion)? ?\d{1,2} ?[:.)] ?(?=\S)"#, options: [.regularExpression, .caseInsensitive]) else { return text }
        return String(text[heading.upperBound...])
    }

    /// A line without the letter its part starts with: "(e) 3x² + 4x + 1".
    private static func unlettered(_ text: String) -> String {
        guard let label = text.range(of: #"^(?:\d{1,2} ?)?\([A-Za-z01|]\)? ?(?:\([ivx]{1,4}\) ?)?(?=\S)"#, options: .regularExpression) else { return text }
        return String(text[label.upperBound...])
    }

    /// The line at a place: the nearest one down the page and, of those level with it, the
    /// one that starts nearest before that place across it.
    private static func row(in rows: [Row], at height: CGFloat, across: CGFloat?) -> Int {
        guard let nearest = rows.indices.min(by: { abs(rows[$0].height - height) < abs(rows[$1].height - height) }) else { return 0 }
        guard let across else { return nearest }
        let level = rows.indices.filter { abs(rows[$0].height - rows[nearest].height) <= 5 }
        guard level.count > 1 else { return nearest }
        return level.filter { rows[$0].left <= across + 6 }.max { rows[$0].left < rows[$1].left } ?? level.min { rows[$0].left < rows[$1].left } ?? nearest
    }

    /// The answer a solver of words gives for the whole of the question pointed at (a table's
    /// values may be in the next part), unless it gives the same with the part pointed at left
    /// out: that would be the answer to another part.
    static func wholeQuestion(_ lines: [Row], pointer: CGFloat, across: CGFloat? = nil, _ solve: (String) -> Solution?) -> Solution? {
        guard !lines.isEmpty else { return nil }
        let given = lines
        let lines = arranged(lines)
        let layout = layout(lines.map { (text: plain($0.text), height: $0.height, left: $0.left) }, pointer: pointer, across: across)
        guard !layout.pointed.isEmpty, layout.parts.count > 1 else { return nil }
        func text(_ parts: [Range<Int>]) -> String {
            var chosen = Set(layout.stem)
            for part in parts { chosen.formUnion(part) }
            return inOrder(chosen.filter { !layout.labels.contains($0) }.map { lines[$0] }, of: given).map { unheaded($0.text) }.joined(separator: "\n")
        }
        guard let whole = solve(text(layout.parts)) else { return nil }
        if let others = solve(text(layout.parts.filter { !layout.pointed.contains($0) })), written(others) == written(whole) { return nil }
        return whole
    }

    /// How the lines in an area are set out as a question: where the one pointed at starts
    /// and ends, the lines before its first part, its parts ((a), (b)),
    /// and the lines that are only a question's number or a part's letter.
    private static func layout(_ rows: [Row], pointer: CGFloat, across: CGFloat? = nil) -> (first: Int, last: Int, stem: Range<Int>, parts: [Range<Int>], pointed: [Range<Int>], labels: Set<Int>, isNumbered: Bool, lettered: Set<Int>) {
        let pointed = row(in: rows, at: pointer, across: across)
        // The letters parts start with. A long list runs on past (h): (i) is then a letter,
        // not the first of (i), (ii), (iii).
        // (And an l is often read as 1 or I, and an o as 0: after (k) or (n), that's what it is.)
        let lettered = Set(rows.compactMap { groups(#"^(?:\d{1,2} ?)?\(([a-z])\)"#, in: $0.text)?[1].lowercased().first })
        func isLetter(_ letter: Character, _ isClosed: Bool = true) -> Bool {
            // "(f √3 × √3", the end of the bracket not read: only straight after the letter before it.
            if !isClosed {
                guard let value = letter.asciiValue, value > 97, lettered.contains(Character(UnicodeScalar(value - 1))) else { return false }
            }
            switch letter {
            case "i": return lettered.contains("h") || lettered.contains("k")
            case "1", "|": return lettered.contains("k")
            case "0": return lettered.contains("n")
            case "v": return lettered.contains("u")
            case "x": return lettered.contains("w")
            default: return true
            }
        }
        var questions: Set<Int> = [], letters: Set<Int> = [], labels: Set<Int> = []
        // The question's number is often there twice: by its first line, and again with the
        // letter of its first part ("25", then "25 (a)"). Only the first starts the question.
        var numbers: Set<String> = []
        func isNew(_ text: String) -> Bool {
            guard let number = groups(#"^(?:Q(?:uestion)? ?)?(\d{1,2})"#, in: text)?[1] else { return true }
            return numbers.insert(number).inserted
        }
        let margin = (rows.map(\.left).min() ?? 0) + 30
        for (index, row) in rows.enumerated() {
            if startsQuestion(row.text), isNew(row.text) { questions.insert(index) }
            if startsPart(row.text, { isLetter($0, $1) }) { letters.insert(index) }
            // A number or letter standing by itself in the margin is read as a line of its
            // own: it belongs with the first line that's level with it.
            // ("14 (b)" is the next part of question 14, not a new question.)
            let isNumber = row.left <= margin && row.text.range(of: #"^(?:Q(?:uestion)? ?)?\d{1,2}[:.]?(?: ?\(?a\))?(?: ?\(?i\))?$"#, options: [.regularExpression, .caseInsensitive]) != nil
            var isLabel = row.text.range(of: #"^(?:\d{1,2} ?)?\(?[a-h]\)(?: ?\(?[ivx]{1,4}\))?$"#, options: .regularExpression) != nil
            if !isLabel, let letter = groups(#"^\(([a-z01|])\)$"#, in: row.text)?[1].lowercased().first { isLabel = isLetter(letter) }
            func isBare(_ text: String) -> Bool { text.range(of: #"^\([A-Za-z01|]?\)$"#, options: .regularExpression) != nil }
            let level = rows.indices.filter { abs(rows[$0].height - row.height) <= 7 }
            // (A letter that wasn't read, "()", in a row of letters.)
            if !isLabel, row.text == "()", level.contains(where: { $0 != index && isBare(rows[$0].text) }) { isLabel = true }
            guard isNumber || isLabel else { continue }
            labels.insert(index)
            // (Of the lines level with it, the next one along: a letter belongs to what's beside it.
            // In a row of nothing but letters each is its own part's.)
            let first = level.min() ?? index, next = level.filter { $0 > index }.min()
            let isRowOfLetters = level.count > 1 && level.allSatisfy { isBare(rows[$0].text) }
            if isNumber, isNew(row.text) { questions.insert(first) }
            if isLabel { letters.insert(isNumber || (next == nil && !isRowOfLetters) ? first : index) }
        }
        // A question whose number is only seen with its first part's letter ("8 (a)", the "8"
        // by its first line not read or out of the area) starts further up: at the lines that
        // tell what it's about, back to where the question before ended (its marks, its
        // answer line, something it asks).
        for start in questions.sorted() where rows[start].text.range(of: #"^(?:Q(?:uestion)? ?)?\d{1,2}[:.]? ?\(?a\)"#, options: .regularExpression) != nil {
            var top = start
            while top - 1 >= 0, !questions.contains(top - 1), !letters.contains(top - 1), !labels.contains(top - 1),
                  isTold(rows[top - 1].text) || (!rows[top - 1].text.split(separator: " ").contains(where: isWord) && !isMarks(rows[top - 1].text) && !rows[top - 1].text.contains("..")) {
                top -= 1
            }
            // (Only up to a line that starts a sentence.)
            while top < start, rows[top].text.first?.isUppercase != true, rows[top].text.split(separator: " ").contains(where: isWord) { top += 1 }
            if top < start {
                questions.remove(start)
                questions.insert(top)
            }
        }
        var first = 0, last = rows.count
        for index in stride(from: pointed, through: 0, by: -1) where questions.contains(index) { first = index; break }
        for index in rows.indices where index > pointed && questions.contains(index) { last = index; break }
        var starts = (first..<last).filter { letters.contains($0) }
        // What a part is told can be printed above its letter, after the marks of the part
        // before: "(a) Complete the table. (1)  There are 12 blue cubes in the box.  (b) Work
        // out the total number of cubes." Those lines go with the part they lead up to.
        for (number, start) in starts.enumerated() where number > 0 {
            var top = start
            while top - 1 > starts[number - 1], isTold(rows[top - 1].text), !labels.contains(top - 1) { top -= 1 }
            // (From a line that starts a sentence, after one that ended.)
            while top < start, rows[top].text.first?.isUppercase != true { top += 1 }
            guard top < start, top - 1 >= starts[number - 1] else { continue }
            let above = rows[top - 1].text
            if isMarks(above) || above.hasSuffix(".") || above.hasSuffix("?") { starts[number] = top }
        }
        // (A part runs on past its marks: a table to fill in or a row of answers to choose
        // from comes after them.)
        let parts: [Range<Int>] = starts.isEmpty ? [first..<last] : starts.enumerated().map { number, start in
            start..<(number + 1 < starts.count ? starts[number + 1] : last)
        }
        return (first, last, first..<(starts.first ?? first), parts, parts.filter { $0.contains(pointed) }, labels, !questions.isEmpty, letters)
    }

    /// The maths found, sorted for showing: the answers the question's words ask for, and
    /// the rest as it was worked out, each with whether it's in the question pointed at and
    /// whether it's only a number from a sentence said back.
    private static func sort(_ solutions: [Solution], at heights: [CGFloat], lefts: [CGFloat]? = nil, lines: [Row], pointer: CGFloat, across: CGFloat? = nil, angles: AngleUnit)
    -> (asked: [Solution], rest: [(solution: Solution, was: Int, height: CGFloat, inQuestion: Bool, isLone: Bool, isInstructed: Bool)], isNumbered: Bool, words: String, isIterating: Bool, isArgued: Bool) {
        let rows = arranged(lines).map { (text: plain($0.text), height: $0.height, left: $0.left) }
        let lefts = lefts?.count == solutions.count ? lefts : nil
        func place(of index: Int) -> Int { row(in: rows, at: heights[index], across: lefts?[index]) }

        // f(x) = x − 3 on one line is what f means on the others, not an equation to solve.
        let functions = definitions(in: rows.map(\.text))
        var found: [(solution: Solution, row: Int, was: Int)] = []
        for (index, solution) in solutions.enumerated() {
            var solution = solution
            let text = plain(solution.problem.text)
            // f⁻¹(x) is a function turned round, not x divided by f.
            if text.range(of: inverseCall, options: .regularExpression) != nil { continue }
            // f(x) with nothing in view to say what f is can't be worked out: f isn't a number.
            // (Nor is g, where f is said to be a function and what g is wasn't read.)
            if let range = text.range(of: functions.isEmpty ? #"(?<![A-Za-z])[fgh]{1,3} ?\( ?x ?\)"# : #"(?<![A-Za-z])[fgh]{1,3} ?\("#, options: .regularExpression),
               !text[range].filter({ "fgh".contains($0) }).allSatisfy({ functions[$0] != nil }) { continue }
            if !functions.isEmpty, let all = try? NSRegularExpression(pattern: #"(?<![A-Za-z])([fgh]{1,3}) ?\("#),
               all.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains(where: { match in
                   Range(match.range(at: 1), in: text).map { !text[$0].allSatisfy { functions[$0] != nil } } ?? false
               }) { continue }
            if !functions.isEmpty, calls(functions, in: text) {
                if isDefinition(text, of: functions) { continue }
                guard let written = substituted(text, functions), var problem = Parser.problem(written) else { continue }
                let meaning = functions.sorted { $0.key < $1.key }.map { "\($0.key)(\($0.value.variable)) = \(Parser.expression($0.value.body).map(Format.text) ?? $0.value.body)" }.joined(separator: " and ")
                problem.lead = [Step("Put in what the function is", meaning + ".")]
                guard let worked = Engine.solve(problem, angles: angles), !worked.answers.isEmpty || worked.note != nil else { continue }
                solution = worked
            }
            found.append((solution, place(of: index), index))
            // Maths that was read together with the words after it, and answered as the
            // words ask: the maths as it stands is an answer too.
            if case .worded = solution.problem.kind {
                for run in algebra(in: text) where run != text {
                    guard let problem = Parser.problem(run), let plain = Engine.solve(problem, angles: angles), !plain.answers.isEmpty else { continue }
                    if case .worded = problem.kind { continue }
                    found.append((plain, place(of: index), -1))
                }
            }
        }

        // The question the pointer is in, and its parts: (a), (b).
        // Pointing at one part asks for that part; pointing at the question asks for them all.
        let layout = layout(rows, pointer: pointer, across: across)
        if ProcessInfo.processInfo.environment["ASKED_DEBUG"] != nil {
            for (i, r) in rows.enumerated() { print("   row \(i) h=\(Int(r.height)) l=\(Int(r.left)) \(r.text)") }
            print("   pointer \(Int(pointer)) across \(across.map { Int($0) } ?? -1) layout \(layout)")
            for f in found { print("   found row \(f.row): \(f.solution.problem.text) => \(f.solution.answerText)") }
        }
        let stem = layout.stem
        let stemText = stem.filter { !layout.labels.contains($0) }.map { unheaded(rows[$0].text) }.joined(separator: " ")
        let considered = layout.pointed.isEmpty ? layout.parts : layout.pointed
        // The answers to choose from, on lines of their own under "Circle the…" or "Which of
        // these…": one of them worked out as a sum isn't the answer, and
        // nor is what the words ask for (a gradient, a turning point) read off one of them.
        var choices = choiceRows(in: rows, parts: considered, labels: layout.labels) { index in found.filter { $0.row == index && $0.was >= 0 }.count }
        // Someone's working with a mistake in it, printed for the mistake to be found: its
        // lines aren't sums to answer. (The question's own sum is in a sentence, and stays.)
        let told = (stemText + " " + considered.flatMap { $0.map { rows[$0].text } }.joined(separator: " ")).lowercased()
        if told.range(of: #"\b(?:mistake|error)s?\b|\b(?:is|are|was) (?:wrong|incorrect|not correct)\b"#, options: .regularExpression) != nil,
           told.range(of: #"\b(?:working|solution|answer|method|attempt|says|writes|thinks)\b"#, options: .regularExpression) != nil {
            for part in considered + [stem] {
                for index in part where !layout.labels.contains(index) && !unlettered(unheaded(rows[index].text)).split(separator: " ").contains(where: isWord) { choices.insert(index) }
            }
        }
        var asked: [Solution] = []
        var spent = Set<Int>()
        // Two parts read as one line, "(e) 4√80 + 3√45 (f) 6√75 − 2√12": the one pointed at is
        // the maths that starts nearest before the pointer. With nothing to tell them apart
        // by, neither is answered.
        var others = Set<Int>()
        let pointedLine = row(in: rows, at: pointer, across: across)
        if layout.lettered.contains(pointedLine), unlettered(rows[pointedLine].text).range(of: #"\S \([a-z01|]\) ?\S"#, options: .regularExpression) != nil {
            let here = found.indices.filter { found[$0].row == pointedLine && found[$0].was >= 0 }
            var kept: Int?
            if let across, let lefts {
                kept = here.filter { lefts[found[$0].was] <= across + 45 }.max { lefts[found[$0].was] < lefts[found[$1].was] }
            }
            others = Set(found.indices.filter { found[$0].row == pointedLine && $0 != kept })
            if kept == nil { others.insert(-1) }
        }
        for part in considered {
            var text = part.filter { !layout.labels.contains($0) && !choices.contains($0) }
                .map { layout.lettered.contains($0) ? unlettered(rows[$0].text) : ($0 == part.lowerBound ? unheaded(rows[$0].text) : rows[$0].text) }.joined(separator: " ")
            // One instruction over a list of parts, "Factorise each of the following", is what
            // each of them asks.
            if !text.split(separator: " ").contains(where: isWord), !stemText.isEmpty, !text.isEmpty, part != stem { text = stemText + " " + text }
            let own = found.indices.filter { part.contains(found[$0].row) && !others.contains($0) && !choices.contains(found[$0].row) }, above = found.indices.filter { stem.contains(found[$0].row) && !part.contains(found[$0].row) }
            let within = own + above
            // (Which of two parts on the line is meant couldn't be told.)
            if others.contains(-1), part.contains(pointedLine) { continue }
            // Whether it's a curve's equation itself that's pointed at.
            let pointedRow = row(in: rows, at: pointer, across: across)
            let onCurve = part.contains(pointedRow) && rows[pointedRow].text.range(of: #"(?<![A-Za-z])y ?="#, options: .regularExpression) != nil
            // (Whether the part's one sum is what its instruction is about: only then does "to
            // 2 decimal places" or "x is acute" say how its answer is wanted.)
            let isAbout = own.count == 1 && (!rows.contains { wordCount($0.text) >= 3 } || isInstructed(found[own[0]].solution, on: found[own[0]].row, rows: rows, from: layout.first,
                                                                                                       labels: layout.labels, lettered: layout.lettered,
                                                                                                       part: part.filter { !layout.labels.contains($0) }.map { rows[$0].text }.joined(separator: "\n")))
            let result = asks(of: text, stem: stemText, own: own.map { found[$0].solution }, above: above.map { found[$0].solution },
                              pointed: onCurve ? rows[pointedRow].text : nil, isAbout: isAbout, angles: angles)
            for solution in result.solutions where !asked.contains(where: { $0.answerText == solution.answerText && $0.question == solution.question }) {
                asked.append(solution)
            }
            // The form an answer is to be written in was read as maths too: that isn't a problem.
            if let letters = result.form {
                for index in within where symbols(of: found[index].solution).isSuperset(of: letters) { spent.insert(index) }
            }
        }

        // Anywhere in the area, "in the form ax² + bx + c = 0" is a way of writing an answer,
        // not an equation to solve.
        for (index, row) in rows.enumerated() {
            guard let marker = row.text.range(of: formWords, options: [.regularExpression, .caseInsensitive]) else { continue }
            let letters = Set(squeezed(mathsStart(String(row.text[marker.upperBound...]))).filter { $0.isLetter && $0 != "x" && $0 != "y" }.map(String.init))
            guard letters.count >= 2 else { continue }
            for place in found.indices where (found[place].row == index || found[place].row == index + 1) && symbols(of: found[place].solution).isSuperset(of: letters) {
                spent.insert(place)
            }
        }
        // A lone number out of a sentence, shown back as it stands, answers nothing: unless
        // the words ask for it written another way.
        let everything = rows.map(\.text).joined(separator: " ").lowercased()
        let hasWords = rows.contains { wordCount($0.text) >= 3 }
        let wantsNumber = ["simplify", "simplest", "lowest terms", "cancel", "as a decimal", "as a fraction", "as a percentage", "as a mixed", "convert"].contains { everything.contains($0) }
        let rest = found.indices.filter { !spent.contains($0) }.map { index in
            (solution: found[index].solution, was: found[index].was, height: rows[found[index].row].height,
             inQuestion: !others.contains(index) && (stem.contains(found[index].row) || considered.contains { $0.contains(found[index].row) }),
             isLone: hasWords && (isLone(found[index].solution, changed: wantsNumber) || isCircle(found[index].solution) || isTemplate(found[index].solution)
                                  || isUnchanged(found[index].solution) || choices.contains(found[index].row)
                                  || isRatioSide(found[index].solution, in: rows[found[index].row].text)),
             isInstructed: !hasWords || isInstructed(found[index].solution, on: found[index].row, rows: rows, from: layout.first, labels: layout.labels,
                                                     lettered: layout.lettered,
                                                     part: considered.first { $0.contains(found[index].row) }.map { $0.filter { !layout.labels.contains($0) }.map { rows[$0].text }.joined(separator: "\n") }
                                                        ?? considered.flatMap { $0.filter { !layout.labels.contains($0) }.map { rows[$0].text } }.joined(separator: "\n")))
        }
        var words = considered.flatMap { $0.filter { !layout.labels.contains($0) }.map { rows[$0].text } }.joined(separator: " ").lowercased()
        // (A part that's only its maths is asked what the question's first lines say.)
        if !words.split(separator: " ").contains(where: isWord) { words = stemText.lowercased() + " " + words }
        // What the answers to choose from are written in says how the answer is wanted:
        // multiples of π, percentages, degrees.
        let offered = choices.sorted().map { rows[$0].text }.joined(separator: " ")
        if offered.contains("π"), !words.contains("in terms of") { words += " give your answer in terms of π" }
        let items = offered.split(separator: " ").filter { $0.contains(where: \.isNumber) }
        if items.count >= 3, items.allSatisfy({ $0.hasSuffix("%") }) { words += " «%»" }
        if items.count >= 3, items.allSatisfy({ $0.hasSuffix("°") }) { words += " «°»" }
        // "Use the iteration formula three times": the terms it gives are asked for, not the
        // root of the equation, which is a different number until it's rounded.
        let isIterating = (stemText.lowercased() + " " + words).range(of: #"\biterat|\bx ?_?\(?n ?\+ ?1\)?|x₍?ₙ₊₁"#, options: .regularExpression) != nil
        // "Explain why", "Show that", "Give a reason", with nothing to work out besides: maths
        // in the part worked out as it stands isn't the argument that's asked for.
        let isArgued = words.range(of: #"\bexplain\b|\bgive (?:a|one|two|your) reasons?\b|\bshow that\b|\bprove\b"#, options: .regularExpression) != nil
            && words.range(of: #"\bsolve\b|\bwork out\b|\bfind\b|\bcalculate\b|\bsimplify\b|\bfactori[sz]e\b|\bexpand\b|\bhence\b|\bestimate\b|\bwrite down\b"#, options: .regularExpression) == nil
        return (asked, rest, layout.isNumbered, words, isIterating, isArgued)
    }

    // MARK: What a part asks for

    /// The answers a part of a question asks for, from its own words and the maths found in it
    /// or in the lines the question starts with. `form` is the letters of a form the answer was
    /// to be written in, if there was one.
    private static func asks(of text: String, stem: String, own: [Solution], above: [Solution], pointed: String? = nil, isAbout: Bool = true, angles: AngleUnit) -> (solutions: [Solution], form: Set<String>?) {
        let lower = text.lowercased()
        let pool = own + above
        var found: [Solution] = []
        var letters: Set<String>?
        if let written = form(text, stem: stem, pool: pool, angles: angles) {
            if let solution = written.solution { found.append(solution) }
            letters = written.letters
        }
        // (A form that couldn't be made out doesn't stop what else is asked: "a reflection
        // in the y-axis … give your answer in the form y = ax² + bx + c".)
        if found.isEmpty {
            let texts = [text, stem]
            // Two sides that are equal for every x: the letters in them, where the part asks for those.
            let matched = identity(lower, texts, pool, angles)
            if let matched {
                letters = (letters ?? []).union(matched.letters)
                if matched.isAsked { found.append(matched.solution) }
            }
            for solution in [fitted(lower, text, angles), turning(lower, texts, pool, angles), reflected(lower, texts, pool, angles), inverse(text, stem, angles),
                             circle(lower, texts, pool, angles), circleThrough(lower, texts, angles), reciprocal(text, angles),
                             line(lower, texts, pool, angles), command(lower, own, angles), index(lower, own, angles), given(text, stem, angles),
                             ratio(lower, text, angles)] {
                if let solution { found.append(solution) }
            }
        }
        // A curve's equation with nothing asked of it that could be made out, and no sum in
        // the part: what there is to know about the curve.
        if found.isEmpty, own.isEmpty, let solution = instructed(text, angles) { found = [solution] }
        // (Not where there's something to show or explain: the facts aren't the argument.)
        let isArgued = (lower + " " + stem.lowercased()).range(of: #"\bshow that\b|\bprove\b|\bexplain\b|\bgive a reason\b"#, options: .regularExpression) != nil
        // (Nor where one of several answers is to be picked: the answer is one of those.)
        let isChoosing = lower.range(of: choosing, options: .regularExpression) != nil
        // (Nor where the words ask for something that wasn't made out: the equation of a
        // tangent, a description of a transformation. What's known about the curve isn't that.)
        let isAsking = (lower + " " + stem.lowercased()).range(of: #"\b(?:find|work out|write|describe|calculate|state|sketch|draw|determine|complete|solve|estimate|plot|give|how|what|which|why)\b"#, options: .regularExpression) != nil
        if found.isEmpty, own.isEmpty, !isArgued, !isChoosing, !isAsking, let pointed, let facts = facts(of: pointed, angles) { found = facts }
        // How the answer is to be given: between whole numbers, in standard form, rounded.
        // Only of the one sum the part has: a number further up isn't the answer.
        // (A sum the words aren't about still answers "lies between two consecutive integers"
        // and "work out the other value", which name it themselves.)
        if let base = found.first ?? (own.count == 1 && isAbout ? own[0] : nil) {
            found.insert(contentsOf: forms(lower, base, angles), at: 0)
        } else if own.count == 1 {
            for solution in [between(lower, own[0], angles), other(lower, own[0], angles)].compactMap({ $0 }) { found.insert(solution, at: 0) }
        }
        return (found, letters)
    }

    private static func told(_ question: String, _ answers: [MathLine], _ steps: [Step], note: String? = nil, plot: Plot? = nil,
                             _ angles: AngleUnit) -> Solution? {
        // A slash in words would be drawn as a fraction.
        let question = question.replacingOccurrences(of: "/", with: "∕")
        var problem = Problem(kind: .worded(question: question, answers: answers), text: question, usesDecimals: false)
        problem.lead = steps
        guard var solution = Engine.solve(problem, angles: angles) else { return nil }
        solution.note = note
        solution.plot = plot
        if answers.count == 1, answers[0].parts.count == 1, case (_, let decimal?) = Engine.presentNumber(answers[0].parts[0], decimals: false) {
            solution.approximation = decimal
        }
        return solution
    }

    private static func number(_ value: Rational) -> Expr { .number(.exact(value)) }

    /// a(x − p)² + q, written out as it's read.
    private static func square(_ a: Rational, _ p: Rational, _ q: Rational, _ x: String) -> Expr {
        let inner: Expr = p.isZero ? .symbol(x) : .add([.symbol(x), number(p.negated)])
        let squared = Expr.power(inner, .two)
        let scaled: Expr = a == Rational(1) ? squared : .multiply([number(a), squared])
        return q.isZero ? scaled : .add([scaled, number(q)])
    }

    private static func squeezed(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// The curve a question is about: "y = …" in its words, or in the maths that was found.
    private static func curve(in texts: [String], _ pool: [Solution]) -> (y: String, f: Expr, x: String)? {
        for text in texts {
            var rest = text[...]
            while let range = rest.range(of: #"(?<![A-Za-z])y ?= ?"#, options: .regularExpression) {
                rest = rest[range.upperBound...]
                // (As far as it's maths: a row of coordinates to choose from may come straight after it.)
                var tokens = mathsStart(String(rest)).split(separator: " ")
                while !tokens.isEmpty {
                    if let f = Parser.expression(tokens.joined(separator: " ")), f.symbols == ["x"] { return ("y", f, "x") }
                    tokens.removeLast()
                }
            }
        }
        for solution in pool {
            switch solution.problem.kind {
            case .solve(let equations, _) where equations.count == 1:
                if case .symbol(let y) = equations[0].left, equations[0].right.symbols.count == 1, let x = equations[0].right.symbols.first, x != y {
                    return (y, equations[0].right, x)
                }
            case .simplify(let f), .expand(let f), .factorise(let f):
                if f.symbols.count == 1, let x = f.symbols.first { return ("y", f, x) }
            default:
                break
            }
        }
        return nil
    }

    /// The turning point of a quadratic curve, its line of symmetry, or its least or greatest value.
    private static func turning(_ lower: String, _ texts: [String], _ pool: [Solution], _ angles: AngleUnit) -> Solution? {
        let wantsPoint = ["turning point", "minimum point", "maximum point", "vertex", "lowest point", "highest point",
                          "coordinates of the minimum", "coordinates of the maximum"].contains { lower.contains($0) }
        let wantsLine = lower.contains("line of symmetry")
        let least = ["minimum value", "least value", "smallest value"].contains { lower.contains($0) }
        let greatest = ["maximum value", "greatest value", "largest value"].contains { lower.contains($0) }
        // The curve the words name: the one straight after what's asked ("the minimum point of
        // y = x² + 2"), or the last one before it.
        var named: (y: String, f: Expr, x: String)?
        let asks = ["turning point", "minimum point", "maximum point", "vertex", "lowest point", "highest point", "coordinates of the minimum", "coordinates of the maximum",
                    "line of symmetry", "minimum value", "least value", "smallest value", "maximum value", "greatest value", "largest value"]
        if let text = texts.first, let place = asks.compactMap({ text.range(of: $0, options: [.caseInsensitive, .backwards]) }).max(by: { $0.lowerBound < $1.lowerBound }) {
            let after = String(text[place.upperBound...].prefix(60)), before = String(text[..<place.lowerBound])
            if after.range(of: #"^[^.?]{0,24}(?<![A-Za-z])y ?="#, options: .regularExpression) != nil { named = curve(in: [after], []) }
            if named == nil, let last = before.range(of: #"(?<![A-Za-z])y ?= ?"#, options: [.regularExpression, .backwards]) { named = curve(in: [String(before[last.lowerBound...])], []) }
        }
        guard wantsPoint || wantsLine || least || greatest, let curve = named ?? curve(in: texts, pool),
              let quadratic = Polynomial(curve.f, in: curve.x), quadratic.degree == 2 else { return nil }
        let a = quadratic.coefficient(2), b = quadratic.coefficient(1)
        guard let twice = a * Rational(2), let p = b.negated / twice, let q = quadratic.evaluate(p) else { return nil }
        let opensUp = a.numerator > 0
        if (least && !opensUp) || (greatest && opensUp) { return nil }
        let completed = square(a, p, q, curve.x)
        let written = "\(curve.y) = \(Format.text(curve.f))"
        var steps: [Step] = []
        if squeezed(Format.text(curve.f)) != squeezed(Format.text(completed)) {
            steps.append(Step("Complete the square", "", [MathLine(curve.f, completed)]))
        }
        steps.append(Step("Find where the bracket is 0", "A square is never less than 0, so \(curve.y) is \(opensUp ? "smallest" : "biggest") when the bracket is 0.",
                          [MathLine(.symbol(curve.x), number(p)), MathLine(.symbol(curve.y), number(q))]))
        let plot = Engine.plot(of: [(Format.text(curve.f), curve.f)], marks: [p.double])
        let note = opensUp ? "It's a minimum: the curve is U-shaped." : "It's a maximum: the curve is an upside-down U."
        // "The turning point is at (a, 8)": the letter is what's wanted.
        if wantsPoint, let text = texts.first {
            if let found = groups(#"\(([a-z]) ?, ?(-?\d+(?:\.\d+)?)\)"#, in: text), let given = Rational.parse(found[2].replacingOccurrences(of: "-", with: "")),
               (found[2].hasPrefix("-") ? given.negated : given) == q {
                return told("Turning point of \(written)", [MathLine(.symbol(found[1]), number(p))], steps, note: note, plot: plot, angles)
            }
            if let found = groups(#"\((-?\d+(?:\.\d+)?) ?, ?([a-z])\)"#, in: text), let given = Rational.parse(found[1].replacingOccurrences(of: "-", with: "")),
               (found[1].hasPrefix("-") ? given.negated : given) == p {
                return told("Turning point of \(written)", [MathLine(.symbol(found[2]), number(q))], steps, note: note, plot: plot, angles)
            }
        }
        if wantsPoint {
            let point = "(\(Format.text(number(p))), \(Format.text(number(q))))"
            return told("Turning point of \(written)", [MathLine(.symbol(point.replacingOccurrences(of: "/", with: "∕")))], steps, note: note, plot: plot, angles)
        }
        if wantsLine { return told("Line of symmetry of \(written)", [MathLine(.symbol(curve.x), number(p))], steps, plot: plot, angles) }
        return told("\(opensUp ? "Least" : "Greatest") value of \(written)", [MathLine(.symbol(curve.y), number(q))], steps, plot: plot, angles)
    }

    /// What there is to know about the graph of y = …: where a curve crosses the x-axis, its
    /// turning point and where it crosses the y-axis; a straight line's gradient and where it
    /// crosses the y-axis.
    private static func facts(of text: String, _ angles: AngleUnit) -> [Solution]? {
        guard let graph = curve(in: [text], []), let polynomial = Polynomial(graph.f, in: graph.x), polynomial.degree == 1 || polynomial.degree == 2 else { return nil }
        // Terms alike written out apart, y = x + 6x − 2, are a power lost in the reading
        // (x² + 6x − 2): what's known about that line isn't about the curve.
        func terms(_ expr: Expr) -> [Expr] {
            if case .add(let parts) = expr { return parts.flatMap(terms) }
            return [expr]
        }
        guard terms(graph.f).count <= terms(Simplify.run(graph.f)).count else { return nil }
        let written = "\(graph.y) = \(Format.text(graph.f))"
        var found: [Solution] = []
        if polynomial.degree == 2 {
            var roots = Problem(kind: .solve([Equation(left: graph.f, right: .zero)], unknowns: [graph.x]), text: "\(Format.text(graph.f)) = 0", usesDecimals: false)
            roots.lead = [Step("Where the curve crosses the x-axis, \(graph.y) is 0", "")]
            if let solution = Engine.solve(roots, angles: angles), !solution.answers.isEmpty { found.append(solution) }
            if let point = turning("turning point", ["turning point of \(written)"], [], angles) { found.append(point) }
        } else {
            let gradient = polynomial.coefficient(1)
            let step = Step("Read off the gradient", "In y = mx + c, m is the gradient: the number in front of \(graph.x).", [MathLine(.symbol("m"), number(gradient))])
            if let solution = told("Gradient of \(written)", [MathLine(number(gradient))], [step], plot: Engine.plot(of: [(Format.text(graph.f), graph.f)]), angles) { found.append(solution) }
        }
        if let cut = polynomial.evaluate(Rational(0)) {
            let step = Step("On the y-axis, \(graph.x) is 0", "", [MathLine(.symbol(graph.y), number(cut))])
            let point = "(0, \(Format.text(number(cut))))".replacingOccurrences(of: "/", with: "∕")
            if let solution = told("Where \(written) crosses the y-axis", [MathLine(.symbol(point))], [step], plot: Engine.plot(of: [(Format.text(graph.f), graph.f)]), angles) { found.append(solution) }
        }
        return found.isEmpty ? nil : found
    }

    /// "Write x(3x − 9) = 4 in the form ax² + bx + c = 0", "Write 2x² − 12x + 7 in the form
    /// d(x + e)² + f": the answer is the same maths written another way.
    private static func form(_ text: String, stem: String, pool: [Solution], angles: AngleUnit) -> (solution: Solution?, letters: Set<String>)? {
        guard let marker = text.range(of: formWords, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var target = squeezed(mathsStart(String(text[marker.upperBound...]))).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "+^", with: "+")
        while let last = target.last, ".,;".contains(last) { target.removeLast() }
        let before = mathsEnd(String(text[..<marker.lowerBound]))
        let letters = Set(target.filter { $0.isLetter && $0 != "x" && $0 != "y" }.map(String.init))
        guard letters.count >= 2 else { return nil }
        func named(_ values: [(String, Rational)]) -> String { values.map { "\($0.0) = \(Format.text(number($0.1)))" }.joined(separator: ", ") }

        // ax² + bx + c = 0
        if target.hasSuffix("=0"), target.contains("^2") {
            var equation: Equation?
            if let problem = Parser.problem(before), case .solve(let equations, _) = problem.kind, equations.count == 1 { equation = equations[0] }
            if equation == nil {
                for solution in pool {
                    if case .solve(let equations, _) = solution.problem.kind, equations.count == 1, symbols(of: solution) == ["x"] { equation = equations[0]; break }
                }
            }
            guard let equation, let quadratic = Polynomial(Simplify.expand(equation.left - equation.right), in: "x"), quadratic.degree == 2 else { return (nil, letters) }
            // Whole numbers, with x² not negative.
            var scale = Rational(1)
            for power in 0...2 {
                guard let lcm = Rational.lcm(scale.numerator, quadratic.coefficient(power).denominator) else { return (nil, letters) }
                scale = Rational(lcm)
            }
            if quadratic.leading.numerator < 0 { scale = scale.negated }
            var whole: [Rational] = []
            for power in 0...2 {
                guard let value = quadratic.coefficient(power) * scale else { return (nil, letters) }
                whole.append(value)
            }
            let standard = Polynomial(whole, variable: "x").expr
            var steps: [Step] = []
            if Engine.containsBrackets(equation.left) || Engine.containsBrackets(equation.right) {
                steps.append(Step("Multiply out the brackets", "", [MathLine(Simplify.expand(equation.left), Simplify.expand(equation.right))]))
            }
            steps.append(Step("Get everything on one side", "So that the other side is 0.", [MathLine(standard, .zero)]))
            let names = target.filter { $0.isLetter && $0 != "x" }.map(String.init)
            let note = names.count == 3 && Set(names).count == 3 ? named([(names[0], whole[2]), (names[1], whole[1]), (names[2], whole[0])]) : nil
            let question = "\(Format.text(equation.left)) = \(Format.text(equation.right)) as a quadratic equal to 0"
            return (told(question, [MathLine(standard, .zero)], steps, note: note, angles), letters)
        }

        // ax² + bx + c: multiplied out.
        // (The x of ax² is often lost in reading: "a^2 + bx + c".)
        if groups(#"^(?:y=)?[a-z]x?\^2\+[a-z]x[+t][a-z]$"#, in: target) != nil {
            var expression = Parser.expression(before)
            let sums = pool.filter { !symbols(of: $0).isSuperset(of: letters) }
            if expression == nil, sums.count == 1, sums[0].answers.count == 1, sums[0].answers[0].parts.count == 1 { expression = sums[0].answers[0].parts[0] }
            guard let expression, let quadratic = Polynomial(Simplify.expand(Simplify.run(expression)), in: "x"), quadratic.degree == 2 else { return (nil, letters) }
            let names = target.filter { $0.isLetter && $0 != "x" && $0 != "y" }.map(String.init)
            let note = names.count == 3 ? named([(names[0], quadratic.coefficient(2)), (names[1], quadratic.coefficient(1)), (names[2], quadratic.coefficient(0))]) : nil
            let step = Step("Multiply out the brackets", "Then collect the terms.", [MathLine(expression, quadratic.expr)])
            return (told("\(Format.text(expression)) multiplied out", [MathLine(quadratic.expr)], (sums.count == 1 ? sums[0].steps : []) + [step], note: note, angles), letters)
        }

        // a(x + b)² + c
        guard let shape = groups(#"^(?:y=)?([a-z])?\(x([+-])([a-z])\)\^2(?:([+-])([a-z]))?(?:\^[a-z])?$"#, in: target) else { return (nil, letters) }
        var expression = Parser.expression(before)
        if expression == nil, let problem = Parser.problem(before), case .solve(let equations, _) = problem.kind, equations.count == 1, case .symbol = equations[0].left {
            expression = equations[0].right
        }
        if expression == nil || Polynomial(expression!, in: "x")?.degree != 2 {
            expression = curve(in: [stem], pool.filter { symbols(of: $0) == ["x"] })?.f
        }
        guard let expression, let quadratic = Polynomial(expression, in: "x"), quadratic.degree == 2 else { return (nil, letters) }
        let a = quadratic.coefficient(2), b = quadratic.coefficient(1)
        guard let twice = a * Rational(2), let p = b.negated / twice, let q = quadratic.evaluate(p), let over = b / a, let half = over / Rational(2) else { return (nil, letters) }
        // The form has no letter in front of its bracket: only x² on its own fits it.
        if shape[1].isEmpty, a != Rational(1) { return (nil, letters) }
        let completed = square(a, p, q, "x")
        var steps: [Step] = []
        if a != Rational(1) {
            let inside = Expr.add([.power(.symbol("x"), .two), .multiply([number(over), .symbol("x")])])
            steps.append(Step("Take \(Format.text(number(a))) out of the x terms", "", [MathLine(.add([.multiply([number(a), inside]), number(quadratic.coefficient(0))]))]))
        }
        steps.append(Step("Complete the square", "Half of \(Format.text(number(over))) is \(Format.text(number(half))). Squaring the bracket makes \(Format.text(number((half * half) ?? half))) too many, so take that away.",
                          [MathLine(expression, completed)]))
        var values: [(String, Rational)] = []
        if !shape[1].isEmpty { values.append((shape[1], a)) }
        values.append((shape[3], shape[2] == "+" ? p.negated : p))
        if !shape[5].isEmpty { values.append((shape[5], shape[4] == "+" ? q : q.negated)) }
        return (told("\(Format.text(expression)) as a completed square", [MathLine(completed)], steps, note: named(values), angles), letters)
    }

    /// The radius or diameter of the circle x² + y² = r².
    private static func circle(_ lower: String, _ texts: [String], _ pool: [Solution], _ angles: AngleUnit) -> Solution? {
        // Asked for, not just spoken of: "the radii are in the ratio 4 : 5" asks for neither.
        guard let found = groups(#"(?:work out|write down|find|calculate|state|what is|circle|give)\b[^.?]{0,30}?\b(radius|diameter)\b"#, in: lower),
              (lower + texts.joined()).lowercased().contains("circle") else { return nil }
        let wanted = found[1]
        var size: Rational?
        for text in texts where size == nil {
            if let found = groups(#"x ?\^2 ?\+ ?y ?\^2 ?= ?(\d+(?:\.\d+)?)(?![\d.]| ?[a-z(^])"#, in: text) { size = Rational.parse(found[1]) }
        }
        for solution in pool where size == nil { size = circleSize(solution) }
        guard let size, size.numerator > 0 else { return nil }
        let radius = Simplify.power(number(size), .half)
        var steps = [Step("Compare with x² + y² = r²", "That's a circle with its centre at (0, 0) and radius r.", [MathLine(.power(.symbol("r"), .two), number(size))]),
                     Step("Take the square root", "", [MathLine(.symbol("r"), radius)])]
        var value = radius
        if wanted == "diameter" {
            value = Simplify.run(.multiply([.two, radius]))
            steps.append(Step("Double the radius", "", [MathLine(.multiply([.two, radius]), value)]))
        }
        return told("\(wanted.capitalizedFirst) of the circle x² + y² = \(Format.text(number(size)))", [MathLine(value)], steps, angles)
    }

    /// r², if what was solved is the circle x² + y² = r².
    private static func circleSize(_ solution: Solution) -> Rational? {
        guard case .solve(let equations, _) = solution.problem.kind, equations.count == 1, symbols(of: solution) == ["x", "y"],
              let inX = PolynomialForm(equations[0].left - equations[0].right, in: "x"), inX.degree == 2, inX.coefficient(2).isOne, inX.coefficient(1).isZero,
              let inY = Polynomial(inX.coefficient(0), in: "y"), inY.degree == 2, inY.coefficient(2) == Rational(1), inY.coefficient(1).isZero else { return nil }
        return inY.coefficient(0).negated
    }

    /// A circle's equation rearranged for x answers nothing a question asks: it's the
    /// circle that's being spoken of, or one of the equations to choose from.
    private static func isCircle(_ solution: Solution) -> Bool { circleSize(solution) != nil }

    /// y = (x + a)² + b, with letters where numbers go, is a shape to fit, not something to multiply out.
    private static func isTemplate(_ solution: Solution) -> Bool {
        groups(#"^(?:y=)?[a-z]?\(x[+-][a-z]\)\^2(?:[+-][a-z])?$"#, in: squeezed(plain(solution.problem.text))) != nil
    }

    /// "The turning point of y = (x + a)² + b has x-coordinate −2. (3, 1) is another point on
    /// the graph. Work out the y-coordinate of the turning point": the letters, from where
    /// the turning point is and a point the curve goes through.
    private static func fitted(_ lower: String, _ text: String, _ angles: AngleUnit) -> Solution? {
        guard let shape = groups(#"y ?= ?\(x ?([+-]) ?([a-z])\) ?\^ ?2 ?([+-]) ?([a-z])"#, in: text), lower.contains("turning point") || lower.contains("minimum point") else { return nil }
        func value(_ text: String) -> Rational? {
            Rational.parse(text.replacingOccurrences(of: "-", with: "")).map { text.hasPrefix("-") ? $0.negated : $0 }
        }
        let number = #"(-?\d+(?:\.\d+)?)"#
        var across: Rational?, up: Rational?
        var steps: [Step] = []
        let a = shape[2], b = shape[4]
        let written = "y = (x \(shape[1] == "+" ? "+" : "−") \(a))² \(shape[3] == "+" ? "+" : "−") \(b)"
        if let found = groups("(?:turning|minimum) point[^.]{0,40}?\\(\(number) ?, ?\(number)\\)", in: lower) {
            across = value(found[1])
            up = value(found[2])
        } else if let found = groups("x-coordinate (?:of |is |= ?)?\(number)", in: lower) {
            across = value(found[1])
        }
        guard let across else { return nil }
        let first = shape[1] == "+" ? across.negated : across
        steps.append(Step("Find where the bracket is 0", "The turning point is where the bracket is 0, so its x-coordinate gives \(a).", [MathLine(.symbol(a), Asked.number(first))]))
        if up == nil, let found = groups("\\(\(number) ?, ?\(number)\\) is (?:another|a) point", in: lower) ?? groups("(?:passes|goes) through (?:the point )?\\(\(number) ?, ?\(number)\\)", in: lower),
           let m = value(found[1]), let n = value(found[2]), let gap = m - across, let square = gap * gap, let rest = n - square {
            up = rest
            steps.append(Step("Put the other point in", "The curve goes through (\(found[1]), \(found[2])), so those fit its equation.",
                              [MathLine(Asked.number(n), .add([.power(Asked.number(gap), .two), .symbol(shape[3] == "+" ? b : "−" + b)])),
                               MathLine(.symbol(b), Asked.number(shape[3] == "+" ? rest : rest.negated))]))
        }
        guard let up else { return nil }
        let second = shape[3] == "+" ? up : up.negated
        if lower.contains("y-coordinate of the turning point") || lower.contains("y-coordinate of the minimum") {
            return told("y-coordinate of the turning point of \(written)", [MathLine(Asked.number(up))], steps, angles)
        }
        if lower.range(of: "value of \(a)\\b|work out \(a)\\b|find \(a)\\b", options: .regularExpression) != nil, lower.range(of: "\(a) and \(b)") == nil {
            return told("\(a) in \(written)", [MathLine(.symbol(a), Asked.number(first))], steps, angles)
        }
        if lower.range(of: "value of \(b)\\b|work out \(b)\\b|find \(b)\\b", options: .regularExpression) != nil {
            return told("\(b) in \(written)", [MathLine(.symbol(b), Asked.number(second))], steps, angles)
        }
        if lower.contains("\(a) and \(b)") {
            let both = "\(a) = \(Format.text(Asked.number(first))), \(b) = \(Format.text(Asked.number(second)))".replacingOccurrences(of: "/", with: "∕")
            return told("\(a) and \(b) in \(written)", [MathLine(.symbol(both))], steps, angles)
        }
        return nil
    }

    /// "Simplify (2 × 10³) : (5 × 10⁻¹). Give your answer in the form n : 1": both sides
    /// divided by the second (or by the first, for 1 : n).
    private static func ratio(_ lower: String, _ text: String, _ angles: AngleUnit) -> Solution? {
        guard let form = groups(#"in ?the ?form ?(n ?: ?1|1 ?: ?n)\b"#, in: lower)?[1].filter({ $0 != " " }) else { return nil }
        for piece in runs(of: text) where piece.isMaths && piece.text.contains(":") {
            let sides = piece.text.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .,;")) }
            guard sides.count == 2, let left = Parser.expression(sides[0]), let right = Parser.expression(sides[1]), left.symbols.isEmpty, right.symbols.isEmpty,
                  let a = Simplify.run(left).number?.rational, let b = Simplify.run(right).number?.rational, !a.isZero, !b.isZero,
                  let n = form == "n:1" ? a / b : b / a else { continue }
            func written(_ value: Rational) -> String {
                var bottom = value.denominator
                while bottom % 2 == 0 { bottom /= 2 }
                while bottom % 5 == 0 { bottom /= 5 }
                return (bottom == 1 ? Format.decimal(value.double) : Format.text(number(value))).replacingOccurrences(of: "/", with: "∕")
            }
            let answer = form == "n:1" ? "\(written(n)) : 1" : "1 : \(written(n))"
            let by = form == "n:1" ? b : a
            let steps = [Step("Work out each side", "", [MathLine(left, number(a)), MathLine(right, number(b))]),
                         Step("Divide both sides by \(written(by))", "A ratio stays the same when both sides are divided by the same number; this makes the \(form == "n:1" ? "second" : "first") side 1.",
                              [MathLine(.symbol("\(written(a)) : \(written(b))"), .symbol(answer))])]
            return told("\(sides[0]) : \(sides[1]) in the form \(form == "n:1" ? "n : 1" : "1 : n")", [MathLine(.symbol(answer))], steps, angles)
        }
        return nil
    }

    /// "A = 3.2 × 10⁴ and B = 5 × 10³. Work out A × B", "x = 3 and y = −2. Work out the value
    /// of 3x − 2y", "v = u + at. u = 3, a = 2, t = 5. Work out v": letters given as numbers,
    /// then a sum in those letters, or a formula's own letter.
    private static func given(_ text: String, _ stem: String, _ angles: AngleUnit) -> Solution? {
        let all = (stem + " " + text).replacingOccurrences(of: "\n", with: " ")
        guard let assignment = try? NSRegularExpression(pattern: #"(?<![A-Za-z])([A-Za-z]) ?= ?([-−(√]?\d[^,;=A-Za-z]*)"#),
              let formula = try? NSRegularExpression(pattern: #"(?<![A-Za-z])([A-Za-z]) ?= ?([^,;=.]*?[A-Za-z][^,;=.]*?)(?=,| and [A-Za-z] ?=| [A-Za-z] ?=|\. |\.?$|;| [A-Z][a-z])"#) else { return nil }
        var values: [String: Expr] = [:]
        for match in assignment.matches(in: all, range: NSRange(all.startIndex..., in: all)) {
            guard let letter = Range(match.range(at: 1), in: all), let amount = Range(match.range(at: 2), in: all) else { continue }
            // (Not the start of something longer: the 3 of "x = 3y" or "x = 3 − 2y".)
            let raw = String(all[amount])
            if amount.upperBound < all.endIndex, all[amount.upperBound].isLetter,
               let last = raw.last, !last.isWhitespace || raw.trimmingCharacters(in: .whitespaces).last.map({ "+-−×÷*/^(".contains($0) }) ?? false { continue }
            var written = raw.trimmingCharacters(in: .whitespaces)
            // (As far as it's a number: "5 × 10^3" all of it, "3" of "3 Work out".)
            while !written.isEmpty, Parser.expression(written).map({ !$0.symbols.isEmpty || $0.evaluate() == nil }) ?? true { written = String(written.dropLast()).trimmingCharacters(in: .whitespaces) }
            guard let value = Parser.expression(written), values[String(all[letter])] == nil else { continue }
            values[String(all[letter])] = value
        }
        guard !values.isEmpty, let asked = groups(#"(?:work out|calculate|find|evaluate)(?: the)?(?: exact)?(?: value of)? (.+?)(?:\.(?: |$)|$| give | write | you | when | if | for | where )"#, in: text) else { return nil }
        var wanted = asked[1].trimmingCharacters(in: CharacterSet(charactersIn: " .?"))
        guard var expr = Parser.expression(wanted), !expr.symbols.isEmpty else { return nil }
        var lead: [Step] = []
        // A formula's own letter: what the formula says it is.
        if case .symbol(let name) = expr, values[name] == nil {
            for match in formula.matches(in: all, range: NSRange(all.startIndex..., in: all)) {
                guard let letter = Range(match.range(at: 1), in: all), String(all[letter]) == name, let body = Range(match.range(at: 2), in: all),
                      let rule = Parser.expression(String(all[body])), !rule.symbols.isEmpty, !rule.symbols.contains(name) else { continue }
                lead = [Step("Use the formula", "", [MathLine(.symbol(name), rule)])]
                expr = rule
                wanted = name
                break
            }
        }
        guard expr.symbols.isSubset(of: Set(values.keys)), expr.symbols.count >= 1 else { return nil }
        // (Not a letter that's simply given: "x = 3. Work out x" asks nothing.)
        if case .symbol = expr { return nil }
        let used = values.filter { expr.symbols.contains($0.key) }
        var problem = Problem(kind: .substitute(expr, values: used), text: wanted, usesDecimals: all.range(of: #"\d\.\d"#, options: .regularExpression) != nil)
        problem.lead = lead
        guard let solution = Engine.solve(problem, angles: angles), !solution.answers.isEmpty else { return nil }
        return solution
    }

    /// "x² − 6x + 1 = (x − a)² − b for all values of x. Find the value of a and the value of b":
    /// the two sides multiplied out, and the x², the x and the number matched up.
    private static func identity(_ lower: String, _ texts: [String], _ pool: [Solution], _ angles: AngleUnit) -> (solution: Solution, letters: Set<String>, isAsked: Bool)? {
        let all = texts.joined(separator: " ").lowercased()
        guard all.range(of: #"for (?:all|every|any) (?:values? of )?[a-z]\b|\bidentity\b|\bidentical\b|≡"#, options: .regularExpression) != nil
                || all.range(of: #"where [a-z](?:, [a-z])* and [a-z] are (?:integers|constants|numbers|whole numbers)"#, options: .regularExpression) != nil else { return nil }
        for candidate in pool {
            guard case .solve(let equations, _) = candidate.problem.kind, equations.count == 1 else { continue }
            let left = equations[0].left, right = equations[0].right
            let symbols = left.symbols.union(right.symbols)
            guard let x = ["x", "n", "y", "t"].first(where: { left.symbols.contains($0) && right.symbols.contains($0) }) else { continue }
            let unknowns = symbols.subtracting([x]).sorted()
            guard (1...4).contains(unknowns.count), unknowns.allSatisfy({ $0.count == 1 }),
                  let leftParts = coefficients(of: left, in: x), let rightParts = coefficients(of: right, in: x) else { continue }
            let powers = Set(leftParts.keys).union(rightParts.keys).sorted(by: >)
            guard powers.count >= unknowns.count else { continue }
            var matches: [MathLine] = []
            var waiting: [Expr] = []
            for power in powers {
                let a = Simplify.run(leftParts[power] ?? .zero), b = Simplify.run(rightParts[power] ?? .zero)
                if a == b { continue }
                matches.append(MathLine(a, b))
                waiting.append(Simplify.run(a - b))
            }
            // One letter at a time: whichever match has only one letter left in it.
            var values: [String: Expr] = [:]
            var solved: [MathLine] = []
            for _ in unknowns {
                var progressed = false
                for equation in waiting {
                    var filled = equation
                    for (letter, value) in values { filled = filled.substituting(letter, with: value) }
                    filled = Simplify.run(filled)
                    guard filled.symbols.count == 1, let letter = filled.symbols.first, values[letter] == nil else { continue }
                    let problem = Problem(kind: .solve([Equation(left: filled, right: .zero)], unknowns: [letter]), text: "", usesDecimals: false)
                    guard let worked = Engine.solve(problem, angles: angles), worked.answers.count == 1, let value = worked.answers[0].parts.last, value.symbols.isEmpty else { continue }
                    values[letter] = value
                    solved.append(MathLine(.symbol(letter), value))
                    progressed = true
                    break
                }
                if !progressed { break }
            }
            guard values.count == unknowns.count else { continue }
            // Every match has to hold with those values.
            let holds = waiting.allSatisfy { equation in
                var filled = equation
                for (letter, value) in values { filled = filled.substituting(letter, with: value) }
                return Simplify.run(filled).isZero
            }
            guard holds else { continue }
            let named = unknowns.map { "\($0) = \(Format.text(values[$0] ?? .zero))" }.joined(separator: ", ").replacingOccurrences(of: "/", with: "∕")
            var steps: [Step] = []
            let expandedLeft = Simplify.expand(left), expandedRight = Simplify.expand(right)
            if Format.text(expandedRight) != Format.text(right) { steps.append(Step("Multiply out the right-hand side", "", [MathLine(right, expandedRight)])) }
            if Format.text(expandedLeft) != Format.text(left) { steps.append(Step("Multiply out the left-hand side", "", [MathLine(left, expandedLeft)])) }
            steps.append(Step("Match the two sides", "They're equal for every \(x), so each side has the same number of \(x)², the same number of \(x) and the same number by itself.", matches))
            steps.append(Step("Work out the letters", "", solved))
            guard let solution = told("\(unknowns.joined(separator: " and ")) in \(candidate.question.text)", [MathLine(.symbol(named))], steps, angles) else { continue }
            let isAsked = unknowns.contains { lower.range(of: "(?:values? of|find|work out|write down) \($0)\\b", options: .regularExpression) != nil }
            return (solution, Set(unknowns), isAsked)
        }
        return nil
    }

    /// How many of each power of a letter an expression has, once it's multiplied out.
    private static func coefficients(of expr: Expr, in x: String) -> [Int: Expr]? {
        let expanded = Simplify.expand(expr)
        let terms: [Expr] = if case .add(let parts) = expanded { parts } else { [expanded] }
        var found: [Int: [Expr]] = [:]
        for term in terms {
            let factors: [Expr] = if case .multiply(let parts) = term { parts } else { [term] }
            var power = 0
            var rest: [Expr] = []
            for factor in factors {
                if factor == .symbol(x) {
                    power += 1
                } else if case .power(.symbol(x), let exponent) = factor, let count = exponent.number?.integer, count > 0 {
                    power += count
                } else if factor.symbols.contains(x) {
                    return nil
                } else {
                    rest.append(factor)
                }
            }
            found[power, default: []].append(rest.isEmpty ? .one : (rest.count == 1 ? rest[0] : .multiply(rest)))
        }
        return found.mapValues { $0.count == 1 ? $0[0] : .add($0) }
    }

    /// "The circle has centre O and passes through (5, 0). What is its equation?"
    private static func circleThrough(_ lower: String, _ texts: [String], _ angles: AngleUnit) -> Solution? {
        let all = texts.joined(separator: " ").lowercased()
        guard lower.contains("equation"), all.contains("circle"), all.contains("through"),
              all.range(of: #"centre (?:is )?(?:at )?(?:o\b|the origin|\(0, ?0\))|origin"#, options: .regularExpression) != nil,
              let found = groups(#"through (?:the point )?(?:[a-z] ?)?\((-?\d+(?:\.\d+)?) ?, ?(-?\d+(?:\.\d+)?)\)"#, in: all),
              let a = Rational.parse(found[1].replacingOccurrences(of: "-", with: "")), let b = Rational.parse(found[2].replacingOccurrences(of: "-", with: "")),
              let aa = a * a, let bb = b * b, let size = aa + bb, !size.isZero else { return nil }
        let left = Expr.add([.power(.symbol("x"), .two), .power(.symbol("y"), .two)])
        let steps = [Step("A circle with its centre at (0, 0)", "Its equation is x² + y² = r², where r is the radius.", [MathLine(left, .power(.symbol("r"), .two))]),
                     Step("Put the point in", "The point is on the circle, so its x and y fit the equation.",
                          [MathLine(.power(.symbol("r"), .two), .add([.power(number(a), .two), .power(number(b), .two)])), MathLine(.power(.symbol("r"), .two), number(size))])]
        return told("Equation of the circle through (\(found[1]), \(found[2]))", [MathLine(left, number(size))], steps, angles)
    }

    /// "Simplify 2⁵ × 2³": powers of one number multiplied or divided are left as a power of it.
    private static func index(_ lower: String, _ own: [Solution], _ angles: AngleUnit) -> Solution? {
        // (Answers to choose from, each a power, aren't the sum.)
        let own = own.filter { !isPower($0) }
        guard own.count == 1, lower.contains("simplify") || lower.contains("single power") || lower.contains("index form"), !lower.contains("power of"),
              let expr: Expr = { switch own[0].problem.kind { case .evaluate(let e), .simplify(let e): return e; default: return nil } }(),
              case .multiply(let factors) = expr, factors.count >= 2 else { return nil }
        var root: Int?
        var total = 0
        var powers = 0
        for factor in factors {
            var inner = factor, sign = 1
            if case .power(let under, let exponent) = factor, exponent == .minusOne { inner = under; sign = -1 }
            if case .power(let base, let exponent) = inner, let value = base.number?.integer, let index = exponent.number?.integer, value >= 2 {
                guard root == nil || root == value else { return nil }
                root = value
                total += sign * index
                powers += 1
            } else {
                return nil
            }
        }
        guard let root, powers >= 2 else { return nil }
        let answer = Expr.power(.integer(root), .integer(total))
        let step = Step("Add the powers", "Powers of the same number add when they're multiplied, and take away when they're divided.", [MathLine(expr, answer)])
        return told("\(own[0].question.text) as one power", [MathLine(answer)], [step], angles)
    }

    /// "The curve y = 2(x − 1)² − 5 is reflected in the y-axis. Work out its equation."
    private static func reflected(_ lower: String, _ texts: [String], _ pool: [Solution], _ angles: AngleUnit) -> Solution? {
        guard lower.contains("reflect"), let axis = groups(#"in the ([xy])[- ]axis"#, in: lower)?[1], let curve = curve(in: texts, pool), curve.x == "x" else { return nil }
        let turned: Expr = axis == "y" ? curve.f.substituting("x", with: .multiply([.minusOne, .symbol("x")])) : .multiply([.minusOne, curve.f])
        let answer = Simplify.expand(Simplify.run(turned))
        let first = axis == "y"
            ? Step("Change x to −x", "Reflecting in the y-axis swaps left and right, so every x becomes −x.", [MathLine(.symbol("y"), turned)])
            : Step("Change y to −y", "Reflecting in the x-axis swaps up and down, so the whole of it changes sign.", [MathLine(.symbol("y"), turned)])
        var steps = [first]
        if Format.text(answer) != Format.text(turned) { steps.append(Step("Multiply out", "", [MathLine(.symbol("y"), answer)])) }
        return told("y = \(Format.text(curve.f)) reflected in the \(axis)-axis", [MathLine(.symbol("y"), answer)], steps,
                    plot: Engine.plot(of: [(Format.text(curve.f), curve.f), (Format.text(answer), answer)]), angles)
    }

    private static let inverseCall = #"(?<![A-Za-z])([fgh]) ?(?:\^ ?\(? ?- ?1 ?\)?|⁻¹) ?\( ?([a-z]) ?\)"#

    /// "Work out f⁻¹(x)", where what f is has been said: f turned round.
    private static func inverse(_ text: String, _ stem: String, _ angles: AngleUnit) -> Solution? {
        guard let found = groups(inverseCall, in: text), let name = found[1].first, let function = definitions(in: [text, stem])[name],
              let body = Parser.expression(function.body) else { return nil }
        // ("Solve f⁻¹(x) = gh(x)" asks for x, not for what the inverse is.)
        if text.range(of: inverseCall + #" ?= ?[A-Za-z0-9(√-]"#, options: .regularExpression) != nil || text.range(of: #"\bsolve\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let x = function.variable, y = x == "y" ? "t" : "y"
        let problem = Problem(kind: .solve([Equation(left: .symbol(y), right: body)], unknowns: [x]), text: "", usesDecimals: false)
        guard let turned = Engine.solve(problem, angles: angles), turned.answers.count == 1, let rule = turned.answers[0].parts.last else { return nil }
        let turnedRound = rule.substituting(y, with: .symbol(x))
        // (Written the shortest way: 8x + 9, not −8(−x − 9/8).)
        let answer = [turnedRound, Simplify.run(Simplify.expand(turnedRound)), Simplify.run(Simplify.together(turnedRound))].min { Format.text($0).count < Format.text($1).count } ?? turnedRound
        let called = "\(name)⁻¹(\(x))"
        let steps = [Step("Write \(y) for \(name)(\(x))", "", [MathLine(.symbol(y), body)])] + turned.steps.filter { $0.title != "Check" }
            + [Step("Swap the letters", "The inverse takes each answer back to where it came from, so \(x) goes in place of \(y).", [MathLine(.symbol(called), answer)])]
        return told(called, [MathLine(.symbol(called), answer)], steps, angles)
    }

    /// "Write down the reciprocal of 4/7."
    private static func reciprocal(_ text: String, _ angles: AngleUnit) -> Solution? {
        // Of a power: the same number to the opposite power.
        if let found = groups(#"reciprocal of (\d+) ?\^ ?\(?(-?\d+)\)?"#, in: text), let index = Int(found[2]), index != 0 {
            let answer = found[1] + raised(-index)
            let step = Step("Change the sign of the power", "The reciprocal is 1 divided by the number, and 1 over a power is the same number to the opposite power.",
                            [MathLine(.symbol("1∕" + found[1] + raised(index)), .symbol(answer))])
            return told("Reciprocal of \(found[1])\(raised(index))", [MathLine(.symbol(answer))], [step], angles)
        }
        guard let found = groups(#"reciprocal of (-?\d+(?:\.\d+)?)(?: ?/ ?\(?(\d+)\)?)?(?! ?\^)"#, in: text), let top = Rational.parse(found[1].replacingOccurrences(of: "-", with: "")) else { return nil }
        var value = found[1].hasPrefix("-") ? top.negated : top
        if !found[2].isEmpty {
            guard let bottom = Int(found[2]), let fraction = value / Rational(bottom) else { return nil }
            value = fraction
        }
        guard !value.isZero, let flipped = Rational(1) / value else { return nil }
        let step = Step("Turn it upside down", "The reciprocal of a number is 1 divided by it: a fraction's top and bottom swap places.", [MathLine(.multiply([.one, .power(number(value), .minusOne)]), number(flipped))])
        return told("Reciprocal of \(Format.text(number(value)))", [MathLine(number(flipped))], [step], angles)
    }

    /// A straight line's gradient, and where a line or curve crosses the axes.
    private static func line(_ lower: String, _ texts: [String], _ pool: [Solution], _ angles: AngleUnit) -> Solution? {
        let wantsGradient = lower.contains("gradient") && !["perpendicular", "parallel", "tangent", "normal", "curve"].contains { lower.contains($0) }
        let wantsY = ["y-intercept", "crosses the y-axis", "cuts the y-axis", "meets the y-axis", "intersects the y-axis"].contains { lower.contains($0) }
        let wantsX = ["x-intercept", "crosses the x-axis", "cuts the x-axis", "meets the x-axis", "intersects the x-axis"].contains { lower.contains($0) }
        guard wantsGradient || wantsY || wantsX else { return nil }
        var steps: [Step] = []
        var given: String?
        var graph = curve(in: texts, pool).map { (y: $0.y, f: $0.f, x: $0.x) }
        if graph == nil {
            // ax + by = c: made into y = …
            for solution in pool {
                guard case .solve(let equations, _) = solution.problem.kind, equations.count == 1, symbols(of: solution) == ["x", "y"],
                      let inY = PolynomialForm(equations[0].left - equations[0].right, in: "y"), inY.degree == 1, inY.coefficient(1).symbols.isEmpty else { continue }
                let f = Simplify.expand(Simplify.run(-inY.coefficient(0) / inY.coefficient(1)))
                steps.append(Step("Make y the subject", "", [MathLine(equations[0].left, equations[0].right), MathLine(.symbol("y"), f)]))
                graph = ("y", f, "x")
                given = "\(Format.text(equations[0].left)) = \(Format.text(equations[0].right))"
                break
            }
        }
        guard let graph, let polynomial = Polynomial(graph.f, in: graph.x) else { return nil }
        let written = given ?? "\(graph.y) = \(Format.text(graph.f))"
        if wantsGradient {
            guard polynomial.degree <= 1 else { return nil }
            let gradient = polynomial.coefficient(1)
            steps.append(Step("Read off the gradient", "In y = mx + c, m is the gradient: the number in front of \(graph.x).", [MathLine(.symbol("m"), number(gradient))]))
            return told("Gradient of \(written)", [MathLine(number(gradient))], steps, plot: Engine.plot(of: [(Format.text(graph.f), graph.f)]), angles)
        }
        if wantsY, lower.contains("coordinates"), let cut = polynomial.evaluate(Rational(0)) {
            let step = Step("On the y-axis, \(graph.x) is 0", "", [MathLine(.symbol(graph.y), number(cut))])
            let point = "(0, \(Format.text(number(cut))))".replacingOccurrences(of: "/", with: "∕")
            return told("Where \(written) crosses the y-axis", [MathLine(.symbol(point))], steps + [step], plot: Engine.plot(of: [(Format.text(graph.f), graph.f)]), angles)
        }
        if wantsY {
            var problem = Problem(kind: .substitute(graph.f, values: [graph.x: .zero]), text: "\(Format.text(graph.f)) when \(graph.x) = 0", usesDecimals: false)
            problem.lead = steps + [Step("On the y-axis, \(graph.x) is 0", "")]
            return Engine.solve(problem, angles: angles)
        }
        guard polynomial.degree >= 1 else { return nil }
        var problem = Problem(kind: .solve([Equation(left: graph.f, right: .zero)], unknowns: [graph.x]), text: "\(Format.text(graph.f)) = 0", usesDecimals: false)
        problem.lead = steps + [Step("On the x-axis, \(graph.y) is 0", "")]
        return Engine.solve(problem, angles: angles)
    }

    /// "Factorise" or "Expand" on one line and the expression on another.
    private static func command(_ lower: String, _ pool: [Solution], _ angles: AngleUnit) -> Solution? {
        guard pool.count == 1, let first = pool.first, case .simplify(let expr) = first.problem.kind, !expr.symbols.isEmpty else { return nil }
        let wanted: ProblemKind
        if lower.range(of: #"\bfactori[sz]e\b"#, options: .regularExpression) != nil {
            wanted = .factorise(expr)
        } else if lower.contains("expand") || lower.contains("multiply out"), Engine.containsBrackets(expr) {
            wanted = .expand(expr)
        } else {
            return nil
        }
        var problem = first.problem
        problem.kind = wanted
        guard let solution = Engine.solve(problem, angles: angles), !solution.answers.isEmpty, solution.answerText != first.answerText else { return nil }
        return solution
    }

    /// "Factorise", "Expand" or "Solve" with its maths on another line, where the maths by
    /// itself wasn't a sum (an expression that's as simple as it gets has nothing to work out).
    private static func instructed(_ text: String, _ angles: AngleUnit) -> Solution? {
        let lower = text.lowercased()
        guard let word = ["factorise", "factorize", "expand and simplify", "expand", "solve"].first(where: {
            lower.range(of: #"\b\#($0)\b"#, options: .regularExpression) != nil
        }) else { return nil }
        let runs = algebra(in: text)
        // (f(x), g⁻¹(x): what a function is has to be put in first, and that isn't done here.)
        guard runs.count == 1, runs[0].range(of: #"(?<![A-Za-z])[fgh]{1,3} ?(?:\^|⁻¹|\()"#, options: .regularExpression) == nil,
              let problem = Parser.problem(word.capitalizedFirst + " " + runs[0]), let solution = Engine.solve(problem, angles: angles), !solution.answers.isEmpty else { return nil }
        if case .worded = problem.kind { return nil }
        // (Nor is the same thing in another order: what couldn't be factorised stays a sum.)
        if word.hasPrefix("factori"), case .add = solution.answers[0].parts.last { return nil }
        // Left as it was isn't an answer.
        guard squeezed(solution.answerText) != squeezed(solution.question.text) else { return nil }
        return solution
    }

    // MARK: How the answer is to be given

    /// An answer written the way the words ask for it, where that isn't how it stands.
    private static func forms(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> [Solution] {
        // "Find the positive value of d": of two answers, one below zero, only the other is wanted.
        if base.answerSets == nil, base.answers.count == 2, lower.range(of: #"\bpositive (?:value|solution|root|number)\b"#, options: .regularExpression) != nil {
            let kept = base.answers.filter { ($0.parts.last?.evaluate() ?? 0) > 0 }
            if kept.count == 1, base.answers.allSatisfy({ $0.parts.last?.evaluate() != nil }),
               let one = told(base.question.text, kept, base.steps + [Step("Keep the positive value", "The question asks for the positive one.", kept)], angles) {
                return forms(lower.replacingOccurrences(of: "positive", with: " "), one, angles) + [one]
            }
        }
        return [between(lower, base, angles), standardForm(lower, base, angles), power(lower, base, angles), rounded(lower, base, angles),
         inTermsOfPi(lower, base, angles), sharp(lower, base, angles), other(lower, base, angles), mixed(lower, base, angles),
         estimated(lower, base, angles)].compactMap { $0 }
    }

    /// "Give your answer as a mixed number."
    private static func mixed(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        guard lower.contains("as a mixed number"), let found = amount(of: base), let exact = found.exact.number?.rational, !exact.isInteger,
              abs(exact.numerator) > exact.denominator else { return nil }
        let units = abs(exact.numerator) / exact.denominator, left = abs(exact.numerator) % exact.denominator
        let sign: Expr = exact.numerator < 0 ? .integer(-units) : .integer(units)
        // The whole number, then the fraction beside it.
        let answer = MathLine(parts: [sign, .fraction(left, exact.denominator)], relation: "")
        let step = Step("Write it as a mixed number", "\(abs(exact.numerator)) ÷ \(exact.denominator) is \(units) remainder \(left): \(units) whole\(units == 1 ? "" : "s") and \(left) left over.",
                        [MathLine(found.exact, .symbol("\(units) and \(left)∕\(exact.denominator)"))])
        return told("\(base.question.text) as a mixed number", [answer], base.steps + [step], angles)
    }

    /// "Work out an estimate for the value of (19.6 × 30.4) ÷ 0.49": each number rounded to one
    /// significant figure first. A root is only estimated where rounding leaves a square number
    /// under it (to one figure, or failing that two); otherwise there's no one estimate to give.
    private static func estimated(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        // (Of a sum as it's written: "an estimate for the mean" of a table is another thing,
        // and so is anything worked out from words.)
        guard lower.range(of: #"\bestimate\b|\brounding each (?:number|value)"#, options: .regularExpression) != nil, case .evaluate(let expr) = base.problem.kind,
              lower.range(of: #"\bestimate (?:for |of )?the (?:mean|median|range|number|probability|total|area|gradient|speed|distance|time|height|length|cost|population)"#, options: .regularExpression) == nil,
              wordCount(base.problem.text) < 3 else { return nil }
        func near(_ value: Double, _ figures: Int) -> Rational? {
            guard value != 0, value.isFinite else { return Rational(0) }
            let power = Int(log10(abs(value)).rounded(.down)) - (figures - 1)
            let front = Int((abs(value) / pow(10, Double(power))).rounded())
            guard let ten = Rational(10).power(power), let size = Rational(front) * ten else { return nil }
            return value < 0 ? size.negated : size
        }
        var changed = false
        func round(_ expr: Expr, _ figures: Int) -> Expr? {
            switch expr {
            case .number(let value):
                guard let rounded = near(value.double, figures) else { return nil }
                if abs(rounded.double - value.double) > 1e-12 * max(1, abs(value.double)) { changed = true }
                return .number(.exact(rounded))
            case .add(let parts):
                let done = parts.map { round($0, figures) }
                return done.contains { $0 == nil } ? nil : .add(done.compactMap { $0 })
            case .multiply(let parts):
                let done = parts.map { round($0, figures) }
                return done.contains { $0 == nil } ? nil : .multiply(done.compactMap { $0 })
            case .power(let base, let exponent) where exponent == .half:
                // √(63.5 × 101.7) is about √(64 × 100): numbers that leave a square.
                for count in [figures, 2] {
                    guard let inside = round(base, count), let under = Simplify.run(inside).number?.rational, under.numerator >= 0 else { continue }
                    if Rational.exactRoot(under.numerator, 2) != nil, Rational.exactRoot(under.denominator, 2) != nil { return .power(inside, exponent) }
                }
                return nil
            case .power(let base, let exponent):
                // (A power is how many times, not a measurement: it stays.)
                return round(base, figures).map { .power($0, exponent) }
            case .function(let name, let inside):
                // cos 58.7° is about cos 60°.
                return round(inside, figures).map { .function(name, $0) }
            default:
                return nil
            }
        }
        guard let rough = round(expr, 1), changed else { return nil }
        var worked = Simplify.run(rough).number?.rational
        if worked == nil {
            // (With a sine or cosine in it, the sum is worked out the way any sum is.)
            var again = base.problem
            again.kind = .evaluate(rough)
            worked = Engine.solve(again, angles: angles)?.answers.first?.parts.last?.number?.rational
        }
        guard let value = worked else { return nil }
        let answer: Expr = value.isInteger ? number(value) : .number(.real(value.double))
        let steps = [Step("Round each number to 1 significant figure", "An estimate uses numbers that are easy to work with.", [MathLine(expr, rough, relation: "≈")]),
                     Step("Work it out", "", [MathLine(rough, answer)])]
        return told("An estimate for \(base.question.text)", [MathLine(answer)], steps, angles)
    }

    /// "Give your answer in terms of π."
    private static func inTermsOfPi(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        guard lower.range(of: #"in terms of ?(π|pi\b)"#, options: .regularExpression) != nil, let found = amount(of: base), found.double != 0,
              !Format.text(found.exact).contains("π") else { return nil }
        let times = found.double / .pi
        var multiple: Rational?
        for bottom in 1...360 {
            let top = (times * Double(bottom)).rounded()
            if abs(times - top / Double(bottom)) < 1e-7, abs(top) < 1e9 { multiple = Rational.make(Int(top), bottom); break }
        }
        guard let multiple else { return nil }
        let answer: Expr = multiple == Rational(1) ? .pi : .multiply([number(multiple), .pi])
        var line = found.name.map { MathLine($0, answer) } ?? MathLine(answer)
        line.suffix = base.answers[0].suffix
        let step = Step("Leave π as it is", "Dividing by π shows how many π it is.", [MathLine(found.exact, answer)])
        return told("\(base.question.text) in terms of π", [line], base.steps + [step], angles)
    }

    /// "One solution is 78.69°. Work out the other value": the answer that isn't the one given.
    private static func other(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        guard lower.range(of: #"the other (?:value|solution|root|angle|answer)|another (?:value|solution)"#, options: .regularExpression) != nil,
              base.answerSets == nil, base.answers.count == 2 else { return nil }
        let values = base.answers.compactMap { $0.parts.last?.evaluate() }
        guard values.count == 2, let regex = try? NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#) else { return nil }
        let given = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).compactMap { Range($0.range, in: lower).flatMap { Double(lower[$0]) } }
        // The one the question states, to as many places as it states it.
        let stated = values.indices.filter { index in given.contains { abs($0 - values[index]) < 0.006 * max(1, abs(values[index]) / 10) } }
        guard stated.count == 1 else { return nil }
        let kept = [base.answers[1 - stated[0]]]
        let step = Step("Take the one that isn't given", "The question gives one of the two already.", kept)
        return told("\(base.question.text): the other value", kept, base.steps + [step], angles)
    }

    /// "x is acute": the one of two angles that is.
    private static func sharp(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        let wantsAcute = lower.range(of: #"\bacute\b"#, options: .regularExpression) != nil, wantsObtuse = lower.range(of: #"\bobtuse\b"#, options: .regularExpression) != nil
        guard wantsAcute != wantsObtuse, base.answerSets == nil, base.answers.count >= 2 else { return nil }
        let kept = base.answers.filter { line in
            guard let size = line.parts.last?.evaluate() else { return false }
            return wantsAcute ? size > 0 && size < 90 : size > 90 && size < 180
        }
        guard kept.count == 1, base.answers.allSatisfy({ $0.parts.last?.evaluate() != nil }) else { return nil }
        let kind = wantsAcute ? "acute" : "obtuse"
        let step = Step("Take the \(kind) one", wantsAcute ? "An acute angle is less than 90°." : "An obtuse angle is between 90° and 180°.", kept)
        return told("\(base.question.text): the \(kind) angle", kept, base.steps + [step], angles)
    }

    /// The one value an answer comes to, if it's a number.
    private static func amount(of solution: Solution) -> (name: Expr?, exact: Expr, double: Double)? {
        guard solution.answers.count == 1, solution.answerSets == nil, let last = solution.answers[0].parts.last, last.symbols.isEmpty,
              let double = last.evaluate(), double.isFinite else { return nil }
        return (solution.answers[0].parts.count == 2 ? solution.answers[0].parts[0] : nil, last, double)
    }

    private static func whole(_ value: Int) -> String { value < 0 ? "−\(-value)" : "\(value)" }

    /// "… lies between two consecutive integers."
    private static func between(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        guard lower.contains("integer") || lower.contains("whole number"),
              lower.contains("consecutive") || lower.range(of: #"between (which )?two"#, options: .regularExpression) != nil,
              let found = amount(of: base), found.double != found.double.rounded(), abs(found.double) < 1e9 else { return nil }
        let low = Int(found.double.rounded(.down))
        let near = Expr.number(.real((found.double * 1000).rounded() / 1000))
        let step = Step("Find the whole numbers either side", "", [found.name.map { MathLine($0, near, relation: "≈") } ?? MathLine(found.exact, near, relation: "≈")])
        return told("\(base.question.text): between which whole numbers", [MathLine(.symbol("\(whole(low)) and \(whole(low + 1))"))], base.steps + [step], angles)
    }

    /// "Give your answer in standard form."
    private static func standardForm(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        guard lower.contains("standard form"), !["which", "circle the", "ordinary number", "not in standard form"].contains(where: { lower.contains($0) }),
              let found = amount(of: base), found.double != 0 else { return nil }
        let power = Int(log10(abs(found.double)).rounded(.down))
        var front: Expr
        if let exact = found.exact.number?.rational, let ten = Rational(10).power(power), let scaled = exact / ten {
            // Just under a power of ten, the logarithm can round the wrong way.
            guard abs(scaled.double) >= 1, abs(scaled.double) < 10 else { return nil }
            front = scaled.isInteger ? number(scaled) : .number(.real(scaled.double))
        } else {
            front = .number(.real(found.double / pow(10, Double(power))))
        }
        if case .number(.real(let double)) = front { front = .number(.real(Double(String(format: "%.10g", double)) ?? double)) }
        let written = "\(Format.text(front)) × 10\(raised(power))"
        let step = Step("Write it as a number from 1 up to 10, times a power of 10", "The point moves \(abs(power)) place\(abs(power) == 1 ? "" : "s").",
                        [MathLine(found.exact, .symbol(written))])
        return told("\(base.question.text) in standard form", [MathLine(.symbol(written))], base.steps + [step], angles)
    }

    private static func raised(_ power: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(power).map { digits[$0] ?? $0 })
    }

    /// "Give your answer as a power of 2."
    private static func power(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        guard let found = groups(#"as a (?:single )?power of (\d+)"#, in: lower), let root = Int(found[1]), root >= 2, let value = amount(of: base), value.double > 0 else { return nil }
        // A power that isn't whole: the cube root of 16 is 2 to the power 4/3.
        guard let exact = value.exact.number?.rational, exact.numerator > 0 else {
            let index = log(value.double) / log(Double(root))
            for bottom in 2...6 {
                let top = (index * Double(bottom)).rounded()
                guard abs(index - top / Double(bottom)) < 1e-9, let fraction = Rational.make(Int(top), bottom), !fraction.isInteger else { continue }
                let answer = Expr.power(.integer(root), .number(.exact(fraction)))
                let step = Step("Write it as a power of \(root)", "A root is a fraction power: the cube root is the power one third.", [MathLine(value.exact, answer)])
                return told("\(base.question.text) as a power of \(root)", [MathLine(answer)], base.steps + [step], angles)
            }
            return nil
        }
        let index = Int((log(exact.double) / log(Double(root))).rounded())
        guard abs(index) <= 60, Rational(root).power(index) == exact else { return nil }
        let answer = Expr.power(.integer(root), .integer(index))
        let step = Step("Write it as a power of \(root)", "Powers of the same number add when they're multiplied, and take away when they're divided.", [MathLine(value.exact, answer)])
        return told("\(base.question.text) as a power of \(root)", [MathLine(answer)], base.steps + [step], angles)
    }

    /// "Give your answers to 2 decimal places", "to 3 significant figures", "to the nearest 10".
    private static func rounded(_ lower: String, _ base: Solution, _ angles: AngleUnit) -> Solution? {
        // An accuracy that is about the numbers given ("by rounding each value correct to 1 significant
        // figure", "measured correct to the nearest 10") says nothing about how to write the answer.
        var lower = lower
        for told in [#"rounding each [^.\n]*"#, #"\b(?:each|every|all) [^.\n]{0,40}correct to [^.\n]*"#,
                     #"\b(?:measured|rounded|given) [^.\n]{0,30}(?:correct to|to the nearest|to \w+ (?:decimal|significant))[^.\n]*"#] {
            lower = lower.replacingOccurrences(of: told, with: " ", options: .regularExpression)
        }
        let counts = ["one": 1, "two": 2, "three": 3, "four": 4, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5]
        var places: Int?, figures: Int?, described = ""
        if let found = groups(#"(?:to|correct to) (\w+) (?:decimal places?|d\.?p)"#, in: lower), let count = counts[found[1]] {
            places = count
            described = "\(count) decimal place\(count == 1 ? "" : "s")"
        } else if let found = groups(#"(?:to|correct to) (\w+) (?:significant figures?|sig\.? ?figs?|s\.?f)"#, in: lower), let count = counts[found[1]] {
            figures = count
            described = "\(count) significant figure\(count == 1 ? "" : "s")"
        } else if let found = groups(#"to the nearest (whole number|integer|tenth|hundredth|ten|hundred|thousand|10|100|1000)"#, in: lower) {
            places = ["whole number": 0, "integer": 0, "tenth": 1, "hundredth": 2, "ten": -1, "10": -1, "hundred": -2, "100": -2, "thousand": -3, "1000": -3][found[1]]
            described = "the nearest \(found[1])"
        }
        // "Give your solutions as decimals", with no more said: two places.
        if places == nil, figures == nil, lower.range(of: #"\bas (?:a )?decimals?\b"#, options: .regularExpression) != nil {
            places = 2
            described = "2 decimal places"
        }
        guard places != nil || figures != nil, base.answerSets == nil, !base.answers.isEmpty, base.answers.count <= 4 else { return nil }
        // ("As a decimal" with no number of places: a fraction that stops, 1/8, is written out
        // in full, 0.125. Only one that goes on for ever is cut to two places.)
        let isOpen = described == "2 decimal places" && lower.range(of: #"decimal places?|d\.?p"#, options: .regularExpression) == nil
        var lines: [MathLine] = []
        var changed = false
        for answer in base.answers {
            guard let last = answer.parts.last, last.symbols.isEmpty, let double = last.evaluate(), double.isFinite else { return nil }
            if isOpen, let exact = last.number?.rational {
                var bottom = exact.denominator
                while bottom % 2 == 0 { bottom /= 2 }
                while bottom % 5 == 0 { bottom /= 5 }
                if bottom == 1 {
                    let written = Format.decimal(double).replacingOccurrences(of: "-", with: "−")
                    if !exact.isInteger { changed = true }
                    lines.append(answer.parts.count == 2 ? MathLine(answer.parts[0], .symbol(written)) : MathLine(.symbol(written)))
                    continue
                }
                // One that goes round for ever is written with dots over what repeats: 1/3 is 0.3̇.
                if let written = recurring(exact) {
                    changed = true
                    lines.append(answer.parts.count == 2 ? MathLine(answer.parts[0], .symbol(written)) : MathLine(.symbol(written)))
                    continue
                }
                return nil
            }
            var decimals = places ?? 0
            if let figures { decimals = double == 0 ? 0 : figures - 1 - Int(log10(abs(double)).rounded(.down)) }
            let scale = pow(10, Double(decimals))
            let near = (double * scale).rounded() / scale
            if abs(near - double) > 1e-12 * max(1, abs(double)) { changed = true }
            let written = String(format: "%.\(max(decimals, 0))f", near).replacingOccurrences(of: "-", with: "−")
            lines.append(answer.parts.count == 2 ? MathLine(answer.parts[0], .symbol(written)) : MathLine(.symbol(written)))
        }
        // Already as short as that: there's nothing to round.
        guard changed else { return nil }
        let exact = base.answers.count == 1 && base.answers[0].parts.count == 1
            ? [MathLine(base.answers[0].parts[0], lines[0].parts[0], relation: "≈")] : lines
        return told("\(base.question.text) to \(described)", lines, base.steps + [Step("Round to \(described)", "", exact)], angles)
    }

    /// A fraction as a recurring decimal, a dot over the first and last digit that repeat:
    /// 5/6 is 0.83̇, 1/7 is 0.1̇42857̇. Nil where more than six digits repeat.
    private static func recurring(_ value: Rational) -> String? {
        let top = abs(value.numerator), bottom = value.denominator
        guard bottom > 1, top < 1_000_000, bottom < 100_000 else { return nil }
        var digits: [Int] = [], seen: [Int: Int] = [:]
        var rest = top % bottom
        while rest != 0, seen[rest] == nil, digits.count < 40 {
            seen[rest] = digits.count
            rest *= 10
            digits.append(rest / bottom)
            rest %= bottom
        }
        guard rest != 0, let start = seen[rest], digits.count - start <= 6 else { return nil }
        var written = (value.numerator < 0 ? "−" : "") + "\(top / bottom)."
        for (place, digit) in digits.enumerated() {
            written += "\(digit)"
            if place == start || place == digits.count - 1 { written += "\u{0307}" }
        }
        return written
    }

    // MARK: Numbers said back

    /// Whether an answer is only a number from the question: as it was written there, or
    /// (unless `changed` answers count) the same number written another way.
    private static func isLone(_ solution: Solution, changed: Bool) -> Bool {
        let expr: Expr
        switch solution.problem.kind {
        case .evaluate(let found), .simplify(let found): expr = found
        default: return false
        }
        func isWhole(_ expr: Expr) -> Bool { expr.number?.rational?.isInteger ?? false }
        // (1 1/2 on its own is a number too: a mixed number.)
        if plain(solution.problem.text).range(of: #"^-?\d+ \d+ ?/ ?\(?\d+\)?$"#, options: .regularExpression) != nil, solution.answers.count == 1 { return true }
        let isLone: Bool
        switch expr {
        case .number: isLone = true
        case .multiply(let factors) where factors.count == 2:
            if case .power(let bottom, let exponent) = factors[1], exponent == .minusOne { isLone = isWhole(factors[0]) && isWhole(bottom) } else { isLone = false }
        default: isLone = false
        }
        // 80 000 000 ÷ 200 is a sum, and so is a fraction that comes to a whole number.
        guard isLone, solution.answers.count == 1, !solution.problem.text.contains("÷"),
              expr.number != nil || solution.answers[0].parts.last?.number?.rational?.isInteger != true else { return false }
        return !changed || squeezed(solution.answers[0].text) == squeezed(solution.question.text)
    }

    private static func symbols(of solution: Solution) -> Set<String> {
        switch solution.problem.kind {
        case .evaluate(let expr), .simplify(let expr), .expand(let expr), .factorise(let expr): letters(in: expr)
        case .solve(let equations, _): equations.reduce(into: Set<String>()) { $0.formUnion(letters(in: $1.left).union(letters(in: $1.right))) }
        default: []
        }
    }

    /// The letters in a piece of maths. An e is read as the number e, but it's a letter here.
    private static func letters(in expr: Expr) -> Set<String> {
        switch expr {
        case .constant(.e): ["e"]
        case .add(let parts), .multiply(let parts): parts.reduce(into: Set<String>()) { $0.formUnion(letters(in: $1)) }
        case .power(let base, let exponent): letters(in: base).union(letters(in: exponent))
        case .function(_, let argument): letters(in: argument)
        default: expr.symbols
        }
    }

    // MARK: Functions

    /// What each function named in the lines is: "f(x) = x − 3", "g(x) = 4x − 7".
    private static func definitions(in lines: [String]) -> [Character: (variable: String, body: String)] {
        var found: [Character: (variable: String, body: String)] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z])([fgh]) ?\( ?([a-z]) ?\) ?= ?"#) else { return found }
        for line in lines {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let name = Range(match.range(at: 1), in: line).flatMap({ line[$0].first }), found[name] == nil,
                      let variable = Range(match.range(at: 2), in: line).map({ String(line[$0]) }), let whole = Range(match.range, in: line) else { continue }
                var body = mathsStart(String(line[whole.upperBound...]))
                // Up to the next function on the same line.
                if let next = body.range(of: #" ?[fgh] ?\("#, options: .regularExpression) { body = String(body[..<next.lowerBound]) }
                // What it is has its letter in it: f(x) = 5 is an equation to solve.
                guard let expr = Parser.expression(body), expr.symbols == [variable] else { continue }
                found[name] = (variable, body)
            }
        }
        return found
    }

    private static let call = #"(?<![A-Za-z])[fgh]{1,3} ?\("#

    private static func calls(_ functions: [Character: (variable: String, body: String)], in text: String) -> Bool {
        guard let range = text.range(of: call, options: .regularExpression) else { return false }
        return text[range].filter(\.isLetter).allSatisfy { functions[$0] != nil }
    }

    /// Whether a line of maths is where a function is said to be what it is.
    private static func isDefinition(_ text: String, of functions: [Character: (variable: String, body: String)]) -> Bool {
        let tight = squeezed(text)
        guard let name = tight.first, let function = functions[name], tight.hasPrefix("\(name)(\(function.variable))=") else { return false }
        let body = String(tight.dropFirst(5))
        return body == squeezed(function.body) || (Parser.expression(body) != nil && Parser.expression(body) == Parser.expression(function.body))
    }

    /// The maths with each function written out: fg(2) as (4(2) − 7) − 3.
    private static func substituted(_ text: String, _ functions: [Character: (variable: String, body: String)], depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }
        let characters = Array(text)
        var result = ""
        var changed = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if functions[character] != nil, index == 0 || !characters[index - 1].isLetter {
                var names: [Character] = []
                var next = index
                while next < characters.count, functions[characters[next]] != nil { names.append(characters[next]); next += 1 }
                while next < characters.count, characters[next] == " " { next += 1 }
                if next < characters.count, characters[next] == "(" {
                    // To the bracket that closes it.
                    var level = 0
                    var close: Int?
                    for position in next..<characters.count {
                        if characters[position] == "(" { level += 1 }
                        if characters[position] == ")" { level -= 1; if level == 0 { close = position; break } }
                    }
                    if let close {
                        let inner = String(characters[(next + 1)..<close])
                        var value = substituted(inner, functions, depth: depth + 1) ?? inner
                        for name in names.reversed() {
                            guard let function = functions[name] else { return nil }
                            value = put(value, into: function.body, for: function.variable)
                        }
                        result += "(" + value + ")"
                        index = close + 1
                        changed = true
                        continue
                    }
                }
            }
            result.append(character)
            index += 1
        }
        return changed ? result : nil
    }

    /// A function's rule with a value in place of its letter.
    private static func put(_ value: String, into body: String, for variable: String) -> String {
        let words = ["sqrt", "sin", "cos", "tan", "log", "ln"]
        var result = ""
        var rest = body[...]
        while let character = rest.first {
            if let word = words.first(where: { rest.hasPrefix($0) }) {
                result += word
                rest = rest.dropFirst(word.count)
            } else if String(character) == variable {
                result += "(" + value + ")"
                rest = rest.dropFirst()
            } else {
                result.append(character)
                rest = rest.dropFirst()
            }
        }
        return result
    }

    // MARK: Reading the words

    /// A line with the dashes, spaces and raised numbers exam papers use made plain.
    private static func plain(_ text: String) -> String {
        var text = text
        for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("²", "^2"), ("³", "^3")] { text = text.replacingOccurrences(of: from, with: to) }
        // An x read as a times sign: nothing is multiplied by a plus or a bracket's end.
        if text.contains("×") {
            text = text.replacingOccurrences(of: #"(?<=[0-9a-z(])×(?=\s*[+\-=)]|\s*$)"#, with: "x", options: .regularExpression)
        }
        // Letters read as their Cyrillic look-alikes.
        if text.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
            let alike: [Character: Character] = ["а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "ѕ": "s", "і": "i", "ј": "j",
                                                 "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X", "У": "Y"]
            text = String(text.map { alike[$0] ?? $0 })
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(separator: " ").filter { $0.filter(\.isLetter).count >= 2 }.count
    }

    /// Whether a word in a line is a word, not maths: three letters in a row, or a short word.
    private static func isWord(_ token: Substring) -> Bool {
        if token.contains("[") || token.contains("]") { return true }
        guard let run = token.range(of: #"[A-Za-z]{2,}"#, options: .regularExpression) else { return false }
        let letters = token[run].lowercased()
        if ["sin", "cos", "tan", "sqrt", "log", "ln"].contains(where: { letters.hasPrefix($0) }) { return false }
        return letters.count >= 3 || ["of", "in", "is", "to", "at", "as", "by", "on", "or", "an", "be", "if", "so", "it", "no", "we", "do"].contains(letters)
    }

    /// The maths a piece of text starts with, up to where words take over.
    private static func mathsStart(_ text: String) -> String {
        var run = text.split(separator: " ").prefix { !isWord($0) }.joined(separator: " ")
        while let last = run.last, ".,;:?".contains(last) { run.removeLast() }
        return run
    }

    /// The maths a piece of text ends with.
    private static func mathsEnd(_ text: String) -> String {
        var taken: [Substring] = []
        for token in text.split(separator: " ").reversed() {
            if isWord(token) { break }
            taken.insert(token, at: 0)
        }
        return taken.joined(separator: " ")
    }

    /// "[2 marks]", "(4)": how much a part is worth, which ends it.
    private static func isMarks(_ text: String) -> Bool {
        text.range(of: #"^[\[(] ?\d{1,2} ?(?:marks?)? ?[\])]$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether a line tells something rather than asks, answers or is worth marks: "There are
    /// 12 blue cubes in the box."
    private static func isTold(_ text: String) -> Bool {
        guard wordCount(text) >= 3, !isMarks(text), !text.contains(".."), !text.contains("__"), !text.hasSuffix("?") else { return false }
        let first = text.split(separator: " ").first.map { $0.lowercased().filter(\.isLetter) } ?? ""
        let asking: Set<String> = ["work", "find", "calculate", "complete", "write", "show", "explain", "give", "draw", "solve", "estimate", "circle", "tick", "you", "use",
                                   "state", "hence", "describe", "simplify", "factorise", "factorize", "expand", "prove", "is", "does", "do", "how", "what", "which", "why",
                                   "answer", "choose", "select", "plot", "sketch", "construct", "measure", "compare", "mark", "shade", "label", "rearrange", "make", "express",
                                   "evaluate", "decide", "name", "fill", "put", "round", "convert", "change", "not", "optional", "turn", "total", "determine", "work out"]
        return !asking.contains(first) && !startsPart(text) && !startsQuestion(text)
    }

    /// "12 A curve has…", "3 (a) Work out…": a question's number, then its first words.
    private static func startsQuestion(_ text: String) -> Bool {
        text.range(of: #"^(?:Q(?:uestion)? ?)?\d{1,2}[:.]? ?(?:\(?a\) ?)?(?:\(?i\) ?)?[A-Z](?:[a-z]| [a-z])"#, options: .regularExpression) != nil
    }

    /// "(b) Write down…"
    /// Or, in a list under one instruction, "(e) 3x² + 4x + 1": a letter in brackets, then maths.
    private static func startsPart(_ text: String, _ isLetter: (Character, Bool) -> Bool = { letter, isClosed in isClosed && "abcdefgh".contains(letter) }) -> Bool {
        if text.range(of: #"^(?:\d{1,2} ?)?\(?[a-h]\) ?(?:\(?[ivx]{1,4}\) ?)?[A-Z(]"#, options: .regularExpression) != nil { return true }
        guard let found = groups(#"^\(([a-z01|])(\)?) ?[^ =+\-×÷^*/<>)]"#, in: text), let letter = found[1].lowercased().first else { return false }
        return isLetter(letter, !found[2].isEmpty)
    }
}
