import Foundation

/// Finds the maths in a line of recognised text: the whole line if it's a problem ("Solve
/// 2x + 3 = 11"), or the runs of maths between the words of a sentence.
enum ProblemFinder {
    /// Words that can be part of maths. Any other word of two or more letters ends a run.
    private static let mathsWords: Set<String> = [
        "sin", "cos", "tan", "sec", "csc", "cosec", "cot", "asin", "acos", "atan", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "ln", "log", "sqrt", "exp", "abs", "pi",
        // A recurring decimal as the reader writes it: rec(0.1,5) is 0.1555…
        "rec",
        // Run together, as some pages set them and text recognition often reads them.
        "sinx", "cosx", "tanx", "lnx", "logx", "secx", "cotx", "sinhx", "coshx", "tanhx", "siny", "tany", "lny",
    ]

    /// Words that start a problem: "Solve", "Differentiate".
    private static let commandWords: Set<String> = [
        "solve", "simplify", "expand", "factorise", "factorize", "factor", "differentiate", "integrate", "evaluate", "calculate",
    ]

    /// Problems found in `line`, each with the range of characters it came from.
    /// Units written hard up against a number: "12cm", "3kg", "the 2nd".
    private static let units: Set<String> = ["mm", "cm", "km", "kg", "mg", "ml", "cl", "dl", "ft", "in", "yd", "lb", "oz", "st", "hr", "hrs", "min", "sec",
                                             "mph", "kph", "kmh", "am", "pm", "th", "nd", "rd", "cc", "kb", "mb", "gb", "kj", "kw", "hz", "mol", "rad", "deg"]

    static func problems(in line: String) -> [(text: String, range: Range<Int>)] {
        // Letters from another alphabet stuck to a number mean Vision couldn't read the number,
        // and what's left of it would be a different sum.
        var raw = Array(line)
        for index in raw.indices where raw[index].isLetter && !raw[index].isASCII && Parser.lookalikes[raw[index]] == nil
            && !raw[index].unicodeScalars.allSatisfy({ (0x370...0x3FF).contains($0.value) }) {
            let before = index > 0 ? raw[index - 1] : " ", after = index + 1 < raw.count ? raw[index + 1] : " "
            if before.isNumber || after.isNumber { raw[index] = LineMender.unreadable }
        }
        let characters = fixSlips(String(raw))
        let fixed = String(characters)
        if let sentence = sentenceProblem(in: fixed) { return [trimmed(sentence, characters)] }
        var found: [(String, Range<Int>)] = []
        // Each stretch between question numbers and wide gaps, if it's nothing but a problem.
        var stretch = 0
        for end in characters.indices.filter({ characters[$0] == "¦" }) + [characters.count] {
            let text = String(characters[stretch..<end]).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, isWorthShowing(text), !containsProse(text) { found.append((text, stretch..<end)) }
            stretch = end + 1
        }
        // Runs of maths between other words, with a command word just before kept on.
        var runStart: Int?
        var commandStart: Int?
        var index = 0
        func endRun(at end: Int) {
            guard let start = runStart else { return }
            // A number stuck to the end of a word is part of a code, not the start of a
            // sum: the foot of an exam page reads "IB/M/Jun24/8300/3H".
            if commandStart == nil, start > 0, characters[start].isNumber, characters[start - 1].isLetter {
                runStart = nil
                return
            }
            let from = commandStart ?? start
            var text = String(characters[from..<end]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,:;?!")))
            // "… look at J x² dx and …": an integral sign read as a letter, in a sentence.
            if let first = text.first, "JS".contains(first), text.dropFirst().first.map({ !$0.isLetter }) ?? false,
               text.range(of: #"\bd[a-z]$"#, options: .regularExpression) != nil {
                text = "∫" + text.dropFirst()
            }
            if isWorthShowing(text) { found.append((text, from..<end)) }
            if commandStart != nil {
                let bare = String(characters[start..<end]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,:;?!")))
                if isWorthShowing(bare) { found.append((bare, start..<end)) }
            }
            runStart = nil
            commandStart = nil
        }
        func nextWordIsLetter(after position: Int) -> Bool {
            var i = position
            while i < characters.count, characters[i] == " " { i += 1 }
            guard i < characters.count, characters[i].isLetter else { return false }
            return i + 1 >= characters.count || !characters[i + 1].isLetter
        }
        while index < characters.count {
            let character = characters[index]
            if character.isLetter {
                var end = index
                while end < characters.count, characters[end].isLetter { end += 1 }
                let word = String(characters[index..<end])
                let lower = word.lowercased()
                let isDifferential = word.count == 2 && word.first == "d"
                if word.count == 1 || mathsWords.contains(lower) || isDifferential {
                    if runStart == nil { runStart = index }
                } else if commandWords.contains(lower) {
                    endRun(at: index)
                    commandStart = index
                    runStart = nil
                } else if ["for", "when", "if", "where"].contains(lower), runStart != nil, nextWordIsLetter(after: end) {
                    // "… for x", "… when x = 4" carry on.
                } else if ["from", "to"].contains(lower), runStart != nil,
                          String(characters[(commandStart ?? runStart!)..<index]).lowercased().contains(where: { $0 == "∫" }) || commandStart != nil {
                    // "integrate … from 0 to 3"
                } else {
                    // Two or three small letters hard up against the number before them are a
                    // product of letters where the last has a power, "½at²". Without a power
                    // there's no telling a product from a word, and what's before it isn't the
                    // sum that's written ("s = 1/2" from s = ½at): it's dropped, unless the
                    // letters are a unit, "12cm".
                    let isGlued = runStart != nil && index > 0 && (characters[index - 1].isNumber || ")²³".contains(characters[index - 1]))
                        && word.count <= 3 && word.allSatisfy(\.isLowercase)
                    let hasPower = end < characters.count && "^²³⁴⁵⁶⁷⁸⁹".contains(characters[end])
                    if isGlued, hasPower {
                        // Part of the run.
                    } else if isGlued, !units.contains(lower) {
                        runStart = nil
                        commandStart = nil
                    } else {
                        endRun(at: index)
                        commandStart = nil
                    }
                }
                index = end
                continue
            }
            let isMaths = character.isNumber || " .+-*/^%()=√∛π°'|_,!<>≤≥∫×÷−–·⋅∗[]{}²³⁴⁵⁶⁷⁸⁹⁰¹⁻½¼¾".contains(character)
                || character == LineMender.unreadable
            if isMaths {
                if runStart == nil && character != " " { runStart = index }
            } else {
                endRun(at: index)
            }
            index += 1
        }
        endRun(at: characters.count)
        return found.map { trimmed($0, characters) }
    }

    /// A problem with its range drawn in to the maths itself: no question number or spaces
    /// before it, no full stop after.
    private static func trimmed(_ found: (text: String, range: Range<Int>), _ characters: [Character]) -> (text: String, range: Range<Int>) {
        var lower = found.range.lowerBound, upper = min(found.range.upperBound, characters.count)
        while lower < upper, " ¦".contains(characters[lower]) { lower += 1 }
        while upper > lower, " ¦.,:;?!".contains(characters[upper - 1]) { upper -= 1 }
        return (found.text, lower..<upper)
    }

    /// A question asked in words that needs no guessing: "the remainder when 2^10 is divided
    /// by 7" is "2^10 mod 7".
    static func sentenceProblem(in line: String) -> (text: String, range: Range<Int>)? {
        guard !line.contains(LineMender.unreadable) else { return nil }
        if WordProblems.problem(line) != nil {
            return (line.replacingOccurrences(of: "¦", with: " ").trimmingCharacters(in: .whitespaces), 0..<line.count)
        }
        guard let parts = Parser.remainderParts(line), Parser.expression(parts.dividend) != nil else { return nil }
        let start = line.distance(from: line.startIndex, to: parts.range.lowerBound)
        let end = line.distance(from: line.startIndex, to: parts.range.upperBound)
        return ("\(parts.dividend) mod \(parts.modulus)", start..<end)
    }

    /// Whether text is a problem worth an answer: it has an operation, an equation or an
    /// instruction, not just a number or a letter.
    static func isWorthShowing(_ text: String) -> Bool {
        guard text.contains(where: \.isNumber) || text.contains(where: \.isLetter), !text.contains(LineMender.unreadable) else { return false }
        // A date, a phone number or a percentage on its own isn't a sum.
        let plain = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
        // Starting on a sign that needs something before it, "+ 10%": the front was cut off.
        if let first = plain.first, "+×÷*/=".contains(first) { return false }
        // …nor is a score with its percentage after it, 7/10 (70%), or the size of a screen
        // or a picture, 1920 × 1080.
        for pattern in [#"^\d{1,4}([-/.])\d{1,2}\1\d{1,4}$"#, #"^\d+(-\d+){2,}$"#, #"^[-−]?\s*\d[\d,.]*\s*%?$"#,
                        #"\d\s*\(\s*\d+(\.\d+)?\s*%\s*\)$"#, #"^\d[\d,]{2,6}\s*[×xX*]\s*\d[\d,]{2,6}$"#, #"^\d+(\s*-\s*\d+){2,}$"#] {
            if plain.range(of: pattern, options: .regularExpression) != nil { return false }
        }
        // One thing over another over a third with nothing else is a reference or a code,
        // 24/8300/3H: nobody sets a sum that way.
        if plain.range(of: #"^[\w.]+(/[\w.]+){2,}$"#, options: .regularExpression) != nil { return false }
        // …and a number over a number with a capital after it, 8300/1H, is the name of a paper
        // or a part.
        if plain.range(of: #"^\d+/\d+[A-Z]{1,2}$"#, options: .regularExpression) != nil { return false }
        // P(6) = 3/5 says what a probability or a function comes to. It isn't P times 6.
        if plain.range(of: #"^[A-Za-z]\s*\(\s*-?\d+(\.\d+)?\s*\)\s*="#, options: .regularExpression) != nil { return false }
        // Numbers with their minus signs hard up against them and gaps between, "-10 -9",
        // are a row of numbers along an axis. A sum has room round its minus sign.
        if text.range(of: #"^\s*[-−]?\d[\d.,]*(\s+-\d[\d.,]*)+\s*$"#, options: .regularExpression) != nil { return false }
        // A power on a power: something read twice over, once in the line and once above it.
        if text.range(of: #"[²³⁴⁵⁶⁷⁸⁹]\s*\^|\^\(?\d*[²³⁴⁵⁶⁷⁸⁹]|\^\d+\^"#, options: .regularExpression) != nil { return false }
        // Brackets that don't pair up: the line was cut short, or runs on to the next.
        let opened = text.filter { "([{".contains($0) }.count, closed = text.filter { ")]}".contains($0) }.count
        guard opened == closed, let problem = Parser.problem(text) else { return false }
        switch problem.kind {
        case .solve(let equations, _):
            // "c = 0" is an answer already, not a problem; so is "x = 4, y = 12".
            return !equations.allSatisfy { equation in
                let sides = [equation.left, equation.right]
                return sides.contains { if case .symbol = $0 { true } else { false } } && sides.contains { isPlainNumber($0) }
            }
        case .evaluate(let expr):
            return hasOperation(expr)
        case .simplify(let expr):
            // "y = x²" is one line of a pair of equations, whatever there is to do to it.
            return hasOperation(expr) && (text.contains("=") || hasSomethingToSimplify(expr))
        default:
            return true
        }
    }

    /// Whether there's anything to do to an expression: terms to collect, a fraction, a
    /// function, or the same letter more than once. "x86" and "2ab" are just names.
    private static func hasSomethingToSimplify(_ expr: Expr) -> Bool {
        switch expr {
        case .number, .symbol, .constant:
            return false
        case .add, .function:
            return true
        case .power(let base, let exponent):
            if let power = exponent.number, power.isNegative || power.rational?.isInteger == false { return true }
            return hasSomethingToSimplify(base) || hasSomethingToSimplify(exponent)
        case .multiply(let factors):
            if factors.contains(where: hasSomethingToSimplify) { return true }
            // x² × x³: a letter that's there twice can be gathered up.
            var seen = Set<String>()
            for factor in factors {
                let letters = factor.symbols
                if !seen.isDisjoint(with: letters) { return true }
                seen.formUnion(letters)
            }
            return factors.filter { $0.number != nil }.count > 1
        }
    }

    /// 5, −2.5: a number with nothing to work out.
    private static func isPlainNumber(_ expr: Expr) -> Bool {
        if expr.number != nil { return true }
        if case .multiply(let parts) = expr, parts.count == 2, parts[0] == .minusOne, parts[1].number != nil { return true }
        return false
    }

    private static func hasOperation(_ expr: Expr) -> Bool {
        switch expr {
        case .number, .symbol, .constant: false
        case .multiply(let parts): !(parts.count == 2 && parts[0] == .minusOne && parts[1].number != nil)
        default: true
        }
    }

    /// Words that aren't maths or instructions.
    private static func containsProse(_ text: String) -> Bool {
        let allowed = mathsWords.union(commandWords).union([
            "for", "when", "if", "where", "from", "to", "and", "of", "the", "with", "respect", "wrt", "what", "is", "find",
            "value", "work", "out", "derivative", "integral", "fully", "completely", "square", "cube", "root", "squared",
            "cubed", "mod", "remainder", "divided", "by", "compute", "determine", "hence", "following", "expression", "equation",
            "equations", "simultaneous", "simultaneously", "given", "that", "these", "pair", "increase", "decrease", "reduce",
        ])
        let words = text.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }
        return words.contains { $0.count > 1 && !allowed.contains($0) && !($0.count == 2 && $0.first == "d") }
    }

    /// Fixes what text recognition commonly gets wrong, keeping every character in place:
    /// × read as x, √ as V or J, ∫ as J or [, 0 as O, stray letters from other alphabets, and
    /// superscripts read as plain digits (x2 for x²).
    static func fixSlips(_ text: String) -> [Character] {
        var characters = Array(text).map { Parser.lookalikes[$0] ?? $0 }
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
        func isAlone(_ index: Int) -> Bool {
            (index == 0 || !characters[index - 1].isLetter) && (index + 1 >= count || !characters[index + 1].isLetter)
        }

        // Question numbers ("1.", "b)", "Q3") separate problems; they aren't part of the maths.
        // "1." only counts at the start: "… is 2. The 5th …" ends a sentence. A number before a
        // closing bracket, as in 7(x − 2), isn't one either.
        // A time of day, 21:42, isn't a division, and nothing beside it is maths.
        if let regex = try? NSRegularExpression(pattern: #"(?<![\d.])\d{1,2}:\d{2}(?::\d{2})?(?![\d.])"#) {
            let text = String(characters)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                for i in start..<min(start + text.distance(from: range.lowerBound, to: range.upperBound), count) { characters[i] = "¦" }
            }
        }
        let marks = String(characters)
        for pattern in [#"(?:^|¦)\s*(\(?\d{1,2}\.)(?=\s)"#,
                        #"(?:^|(?<=\s))(\(?\d{1,2}\)|\(?[a-hA-H]\)|Q\d{1,2}[.:]?|\((?:[a-zA-Z]|i{2,3}|iv|vi{1,3}|ix|xi{0,2})\))(?=\s)"#,
                        #"(?:^|¦)\s*((?:[a-zA-Z]|i{2,3}|iv|vi{1,3}|ix|xi{0,2})\))(?=\s)"#,
                        // "6.0.5x + 1.5": two full stops can't both be in one number.
                        #"^\s*(\d{1,2}\.)(?=\d+\.\d)"#,
                        // "(+)", "()": a label whose letter was misread or lost.
                        #"^\s*(\((?![-−+]\d)[^()\s\d]{0,2}\))(?=\s)"#,
                        // "Example 3.", "Question 2:" number the questions too.
                        #"(?i)\b(?:example|question|exercise|problem|part)\s+(\d{1,2}[.:)]?)(?=\s)"#,
                        // "(j)7 × 8": a letter in brackets at the start is a label even hard up against the maths.
                        #"(?:^|¦)\s*(\((?:[a-zA-Z]|i{2,3}|iv|vi{1,3}|ix|xi{0,2})\))(?=[\dA-Za-z√∫|])"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: marks, range: NSRange(marks.startIndex..., in: marks)) {
                guard let range = Range(match.range(at: 1), in: marks) else { continue }
                let before = marks[..<range.lowerBound]
                let opened = before.filter { $0 == "(" }.count - before.filter { $0 == ")" }.count
                if opened > 0, !marks[range].hasPrefix("(") { continue }
                let start = marks.distance(from: marks.startIndex, to: range.lowerBound)
                let length = marks.distance(from: range.lowerBound, to: range.upperBound)
                for i in start..<min(start + length, count) { characters[i] = "¦" }
            }
        }

        // "2.x² − 5x": a question number that's lost its space. It can't be a decimal.
        for index in 0..<count where characters[index].isNumber {
            guard index == 0 || characters[index - 1] == " " || characters[index - 1] == "(" else { continue }
            var end = index
            while end < count, characters[end].isNumber { end += 1 }
            guard end - index <= 2, end + 1 < count, characters[end] == ".",
                  characters[end + 1].isLetter || "(√∫|".contains(characters[end + 1]) else { continue }
            for i in index...end { characters[i] = "¦" }
        }

        // |x − 3| with its bars read as I or l.
        let barred = String(characters)
        if let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9.])[Il|]((?:(?![A-Za-z]{2})[^Il|=¦]){1,24}?[0-9a-z)])[Il|](?![A-Za-z0-9(])"#) {
            for match in regex.matches(in: barred, range: NSRange(barred.startIndex..., in: barred)) {
                guard let range = Range(match.range, in: barred) else { continue }
                let start = barred.distance(from: barred.startIndex, to: range.lowerBound)
                let end = barred.distance(from: barred.startIndex, to: range.upperBound) - 1
                characters[start] = "|"
                characters[end] = "|"
            }
        }

        // ∫ … dx: the integral sign comes back as J, S, [, ( or 1.
        if let first = characters.firstIndex(where: { $0 != " " && $0 != "¦" }),
           let last = characters.lastIndex(where: { !" .,;:?".contains($0) }), last - first >= 3,
           characters[last].isLetter, characters[last - 1] == "d", !characters[last - 2].isLetter {
            let sign = characters[first]
            let after = first + 1 < count ? characters[first + 1] : " "
            let unclosed = characters.filter { $0 == "(" || $0 == "[" }.count > characters.filter { $0 == ")" || $0 == "]" }.count
            let looksLikeIt: Bool
            switch sign {
            case "∫", "ʃ", "ƒ", "Г", "/": looksLikeIt = true
            case "[", "(": looksLikeIt = unclosed
            case "J", "S", "f": looksLikeIt = !after.isLetter
            case "1", "I", "l", "|": looksLikeIt = !after.isNumber
            default: looksLikeIt = false
            }
            if looksLikeIt { characters[first] = "∫" }
        }

        // A line of surds with its root signs read as V or J, and its times signs as X:
        // "2V3 X 3V5", "V3XV5". Where the line has no other letters, a capital V or J straight
        // before a number or a bracket is a root sign wherever it stands, and an X between a
        // number and a root sign is a times sign.
        let lettersRead = characters.filter(\.isLetter)
        if lettersRead.contains(where: { "VJ".contains($0) }), lettersRead.allSatisfy({ "VJXx".contains($0) }) {
            for index in 0..<count where "VJ".contains(characters[index]) {
                guard let after = next(index), after.isNumber || after == "(" else { continue }
                characters[index] = "√"
            }
            for index in 0..<count where "Xx".contains(characters[index]) {
                guard let before = previous(index), before.isNumber || before == ")", let after = next(index), after == "√" || after.isNumber || after == "(" else { continue }
                if characters[index] == "X" || after == "√" { characters[index] = "×" }
            }
        }

        for index in 0..<count {
            let character = characters[index]
            // A × with nothing to multiply on its left, or an operator straight after, is the letter x.
            if character == "×" {
                let before = previous(index), after = next(index)
                if before == nil || "+-−=(×÷*/".contains(before!) || after.map({ "=+-−)^²³".contains($0) }) == true
                    || before!.isLetter {
                    characters[index] = "x"
                }
            }
            // x⅔: a superscript 2 read as a fraction.
            if character == "⅔", index > 0, characters[index - 1].isLetter || characters[index - 1] == ")" {
                characters[index] = "²"
            }
            // 12 x 3: the letter x between numbers is a times sign. So is one after a degree
            // sign or before sin, cos or tan, with a space either side: cos 30° x sin 45°.
            if character == "x" || character == "X" {
                var rest = index + 1
                while rest < count, characters[rest] == " " { rest += 1 }
                let word = String(characters[rest..<min(rest + 3, count)]).lowercased()
                let spaceBefore = index > 0 && characters[index - 1] == " ", spaceAfter = index + 1 < count && characters[index + 1] == " "
                let isSpaced = spaceBefore && spaceAfter
                // (Before a root sign a space on either side is enough, "√10 x√3", "√11x √10":
                // a letter x times a root is written hard up against both, 3x√2.)
                let beforeRoot = next(index) == "√" && (spaceBefore || spaceAfter || character == "X")
                if let before = previous(index), before.isNumber || before == ")" || (isSpaced && "°%".contains(before)),
                   let after = next(index), after.isNumber || after == "(" || (isSpaced && ["sin", "cos", "tan", "log"].contains(word)) || beforeRoot,
                   spaceBefore || character == "X" || beforeRoot {
                    characters[index] = "×"
                }
            }
            // √ read as V, v or J: "V144", "J(x + 1)"
            if "VJ".contains(character) || (character == "v" && index + 2 < count && characters[index + 2].isNumber),
               index + 1 < count, characters[index + 1].isNumber || characters[index + 1] == "(",
               index == 0 || " +-−*/^(×÷=".contains(characters[index - 1]) {
                characters[index] = "√"
            }
            // A letter O or l inside a number.
            if "Oo".contains(character) || "lI|".contains(character) {
                let left = index > 0 ? characters[index - 1] : nil
                let right = index + 1 < count ? characters[index + 1] : nil
                let digitBeside = (left?.isNumber ?? false) && (right?.isNumber ?? false)
                if digitBeside { characters[index] = "Oo".contains(character) ? "0" : "1" }
            }
            // An o on its own is a zero: "from o to 3", "= O".
            if "oOøØ".contains(character), isAlone(index) {
                characters[index] = "0"
            }
            // X, Y and Z on their own are x, y and z: capitals are rare there, and often misread.
            if "XYZ".contains(character), characters[index] == character, isAlone(index) {
                characters[index] = Character(character.lowercased())
            }
        }

        // Letters from other alphabets that have no business in maths: Vision adds them at the
        // ends of lines, and in place of characters it can't make out.
        for index in 0..<count {
            let character = characters[index]
            guard character.isLetter, !character.isASCII else { continue }
            let isGreek = character.unicodeScalars.allSatisfy { (0x370...0x3FF).contains($0.value) }
            if !isGreek { characters[index] = " " }
        }

        // 3+4x2−6÷3: with no other letters and nothing after an =, an x between numbers is ×.
        let letters = Set(characters.filter { $0.isLetter })
        if letters == ["x"] {
            let places = characters.indices.filter { characters[$0] == "x" }
            let allBetweenNumbers = places.allSatisfy { index in
                guard let before = previous(index), let after = next(index) else { return false }
                return (before.isNumber || before == ")") && (after.isNumber || after == "(")
            }
            let equals = characters.lastIndex(of: "=")
            let asksOnly = equals.map { next($0) == nil || next($0) == "?" } ?? true
            if allBetweenNumbers, asksOnly, !characters.contains("^") {
                for index in places { characters[index] = "×" }
            }
        }

        // x2 + 3x: a digit straight after a lone letter was a superscript.
        for index in 1..<max(count, 1) where characters[index].isNumber && characters[index - 1].isLetter {
            let letterAlone = index < 2 || !characters[index - 2].isLetter
            let digitAlone = index + 1 >= count || !characters[index + 1].isNumber && characters[index + 1] != "."
            if letterAlone && digitAlone, let digit = characters[index].wholeNumberValue, digit >= 2 && digit <= 9 {
                let superscripts: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
                characters[index] = superscripts[digit]
            }
        }
        return characters
    }
}

/// Maths laid out in two dimensions, put back on one line: a fraction's top and bottom are
/// separate pieces of text, one above the other.
enum Layout {
    struct Item: Sendable {
        var text: String
        var box: CGRect
        /// Whether the ink bears out every word of it.
        var isChecked = true
        var isFraction = false
    }

    /// Lines with stacked fractions joined up, "(h)/(6) + (2h)/(9)", or none if nothing is
    /// stacked.
    static func linearize(_ words: [Item], hasBar: (CGRect, CGRect) -> Bool = { _, _ in true }) -> [Item] {
        var used = Set<Int>()
        var items: [Item] = []
        let order = words.indices.sorted { words[$0].box.minY < words[$1].box.minY }
        for i in order where !used.contains(i) {
            let top = words[i]
            guard isMathy(top.text) else { continue }
            let below = words.indices.filter { j in
                j != i && !used.contains(j) && isStacked(top.box, over: words[j].box) && isMathy(words[j].text)
                    && hasBar(top.box, words[j].box)
            }
            guard let j = below.min(by: { words[$0].box.minY < words[$1].box.minY }) else { continue }
            items.append(Item(text: "(\(clean(top.text)))/(\(clean(words[j].text)))", box: top.box.union(words[j].box),
                              isChecked: top.isChecked && words[j].isChecked, isFraction: true))
            used.insert(i)
            used.insert(j)
        }
        guard !items.isEmpty else { return [] }
        for k in words.indices where !used.contains(k) { items.append(words[k]) }
        // Rows: items whose middles are level, left to right.
        var rows: [[Item]] = []
        for item in items.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let index = rows.firstIndex(where: { row in row.contains { abs($0.box.midY - item.box.midY) < 0.45 * max($0.box.height, item.box.height) } }) {
                rows[index].append(item)
            } else {
                rows.append([item])
            }
        }
        // Only the rows with a fraction in them: the rest read well enough as they are.
        return rows.filter { $0.contains(where: \.isFraction) }.map { row in
            Item(text: row.map(\.text).joined(separator: " "), box: row.dropFirst().reduce(row[0].box) { $0.union($1.box) },
                 isChecked: row.allSatisfy(\.isChecked), isFraction: true)
        }
    }

    /// Short and made of numbers, single letters and signs: the top or bottom of a fraction,
    /// not a word in a sentence.
    private static func isMathy(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return text.count <= 8 && (text.contains(where: \.isNumber) || letters.count <= 2) && !text.hasSuffix(".")
    }

    /// `top` is directly over `bottom`, close enough to be a fraction.
    private static func isStacked(_ top: CGRect, over bottom: CGRect) -> Bool {
        guard bottom.minY > top.midY else { return false }
        let gap = bottom.minY - top.maxY
        let overlap = min(top.maxX, bottom.maxX) - max(top.minX, bottom.minX)
        return gap < 0.9 * max(top.height, bottom.height) && overlap > 0.4 * min(top.width, bottom.width)
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
