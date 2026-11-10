import Foundation

/// Finds the maths in a line of recognised text: the whole line if it's a problem ("Solve
/// 2x + 3 = 11"), or the runs of maths between the words of a sentence.
enum ProblemFinder {
    /// Words that can be part of maths. Any other word of two or more letters ends a run.
    private static let mathsWords: Set<String> = [
        "sin", "cos", "tan", "sec", "csc", "cosec", "cot", "asin", "acos", "atan", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "ln", "log", "sqrt", "exp", "abs", "pi",
    ]

    /// Words that start a problem: "Solve", "Differentiate".
    private static let commandWords: Set<String> = [
        "solve", "simplify", "expand", "factorise", "factorize", "factor", "differentiate", "integrate", "evaluate", "calculate",
    ]

    /// Problems found in `line`, each with the range of characters it came from.
    static func problems(in line: String) -> [(text: String, range: Range<Int>)] {
        let characters = fixSlips(line)
        let fixed = String(characters)
        var found: [(String, Range<Int>)] = []
        // The whole line, if it's nothing but a problem.
        if isWorthShowing(fixed), !containsProse(fixed) {
            found.append((fixed, 0..<characters.count))
        }
        // Runs of maths between other words, with a command word just before kept on.
        var runStart: Int?
        var commandStart: Int?
        var index = 0
        func endRun(at end: Int) {
            guard let start = runStart else { return }
            let from = commandStart ?? start
            let text = String(characters[from..<end]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,:;?!")))
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
                    endRun(at: index)
                    commandStart = nil
                }
                index = end
                continue
            }
            let isMaths = character.isNumber || " .+-*/^%()=√∛π°'|_,!<>≤≥∫×÷−–·⋅∗[]{}²³⁴⁵⁶⁷⁸⁹⁰¹⁻½¼¾".contains(character)
            if isMaths {
                if runStart == nil && character != " " { runStart = index }
            } else {
                endRun(at: index)
            }
            index += 1
        }
        endRun(at: characters.count)
        return found
    }

    /// Whether text is a problem worth an answer: it has an operation, an equation or an
    /// instruction, not just a number or a letter.
    static func isWorthShowing(_ text: String) -> Bool {
        guard text.contains(where: \.isNumber) || text.contains(where: \.isLetter),
              let problem = Parser.problem(text) else { return false }
        switch problem.kind {
        case .evaluate(let expr), .simplify(let expr):
            return hasOperation(expr)
        default:
            return true
        }
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
        let allowed = mathsWords.union(commandWords).union(["for", "when", "if", "where", "from", "to", "and", "of", "the", "with", "respect", "wrt", "what", "is", "find", "value", "work", "out", "derivative", "integral"])
        let words = text.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }
        return words.contains { $0.count > 1 && !allowed.contains($0) && !($0.count == 2 && $0.first == "d") }
    }

    /// Fixes what text recognition commonly gets wrong, keeping every character in place:
    /// × read as x, √ as V, 0 as O, and superscripts read as plain digits (x2 for x²).
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
        for index in 0..<count {
            let character = characters[index]
            // A × with nothing to multiply on its left, or an operator straight after, is the letter x.
            if character == "×" {
                let before = previous(index), after = next(index)
                if before == nil || "+-−=(×÷*/".contains(before!) || after.map({ "=+-−)".contains($0) }) == true {
                    characters[index] = "x"
                }
            }
            // x⅔: a superscript 2 read as a fraction.
            if character == "⅔", index > 0, characters[index - 1].isLetter || characters[index - 1] == ")" {
                characters[index] = "²"
            }
            // 12 x 3: the letter x between numbers is a times sign.
            if character == "x" || character == "X" {
                if let before = previous(index), before.isNumber || before == ")",
                   let after = next(index), after.isNumber || after == "(",
                   (index > 0 && characters[index - 1] == " ") || character == "X" {
                    characters[index] = "×"
                }
            }
            // √ read as V: "V144"
            if character == "V", index + 1 < count, characters[index + 1].isNumber || characters[index + 1] == "(",
               index == 0 || " +-−*/^(×÷".contains(characters[index - 1]) {
                characters[index] = "√"
            }
            // A letter O or l inside a number.
            if "Oo".contains(character) || "lI|".contains(character) {
                let left = index > 0 ? characters[index - 1] : nil
                let right = index + 1 < count ? characters[index + 1] : nil
                let digitBeside = (left?.isNumber ?? false) && (right?.isNumber ?? false)
                if digitBeside { characters[index] = "Oo".contains(character) ? "0" : "1" }
            }
        }
        // Question numbers ("1.", "b)", "Q3") separate problems; they aren't part of the maths.
        let marks = String(characters)
        let pattern = #"(^|(?<=\s))(\(?\d{1,2}[.)]|\(?[a-hA-H]\)|Q\d{1,2}[.:]?)(?=\s)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = marks as NSString
            for match in regex.matches(in: marks, range: NSRange(location: 0, length: ns.length)) {
                guard let range = Range(match.range, in: marks) else { continue }
                let start = marks.distance(from: marks.startIndex, to: range.lowerBound)
                let length = marks.distance(from: range.lowerBound, to: range.upperBound)
                for i in start..<min(start + length, count) { characters[i] = "¦" }
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
    struct Item {
        var text: String
        var box: CGRect
    }

    /// Lines with stacked fractions joined up, "(h)/(6) + (2h)/(9)", or none if nothing is
    /// stacked.
    static func linearize(_ words: [Item]) -> [Item] {
        var used = Set<Int>()
        var items: [Item] = []
        let order = words.indices.sorted { words[$0].box.minY < words[$1].box.minY }
        for i in order where !used.contains(i) {
            let top = words[i]
            guard isMathy(top.text) else { continue }
            let below = words.indices.filter { j in
                j != i && !used.contains(j) && isStacked(top.box, over: words[j].box) && isMathy(words[j].text)
            }
            guard let j = below.min(by: { words[$0].box.minY < words[$1].box.minY }) else { continue }
            items.append(Item(text: "(\(clean(top.text)))/(\(clean(words[j].text)))", box: top.box.union(words[j].box)))
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
        return rows.map { row in
            Item(text: row.map(\.text).joined(separator: " "), box: row.dropFirst().reduce(row[0].box) { $0.union($1.box) })
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
