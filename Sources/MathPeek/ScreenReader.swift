import AppKit
import ScreenCaptureKit
import Vision

/// What MathPeek found in the area it read.
enum Reading: Sendable {
    /// Every separate problem found, in reading order, and which is nearest the pointer.
    case solved([Solution], primary: Int)
    /// It found maths, but couldn't work it out.
    case unsolved(String)
    /// The pointer is on a question in words that couldn't be turned into maths.
    case words
    /// There's maths there, but part of it can't be made out: a power too small to read, a
    /// fraction whose top and bottom run together. Better no answer than one to another sum.
    case unclear
    case noMaths
    case failed(String)
}

/// A problem found somewhere on screen and already worked out, for highlighting.
struct Spotted: Sendable {
    /// Where it is, in points from the top-left of the area that was read.
    var box: CGRect
    /// What's there, worked out: one problem, or each angle of a diagram.
    var solutions: [Solution]
}

/// How to read and work things out.
struct ReadOptions: Sendable {
    var angles: AngleUnit
    /// Ask Apple Intelligence about maths text recognition can't read, and word problems.
    var useModel: Bool
    /// Read each problem a second time before answering, and answer only what reads the same.
    var confirms = true
}

/// The part of a screen to read, worked out on the main thread from NSScreen.
struct ScreenArea: Sendable {
    let displayID: CGDirectDisplayID
    /// In points, from the top-left corner of the display, as ScreenCaptureKit wants it.
    let rect: CGRect
    /// The point to find the nearest sum to, in points from the top-left corner of `rect`.
    let focus: CGPoint
    let scale: CGFloat

    /// `rect` and `focus` are in AppKit's global coordinates (origin bottom-left of the main
    /// screen). Nil if `rect` isn't on `screen`.
    @MainActor
    init?(_ rect: CGRect, focus: CGPoint, on screen: NSScreen) {
        let area = rect.intersection(screen.frame).integral
        guard area.width >= 4, area.height >= 4,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        displayID = number.uint32Value
        self.rect = CGRect(x: area.minX - screen.frame.minX, y: screen.frame.maxY - area.maxY,
                           width: area.width, height: area.height)
        self.focus = CGPoint(x: focus.x - area.minX, y: area.maxY - focus.y)
        scale = screen.backingScaleFactor
    }
}

/// A capture filter for one display that leaves out MathPeek's own windows. ScreenCaptureKit
/// doesn't mark it Sendable, but it never changes once made.
struct DisplayFilter: @unchecked Sendable {
    let filter: SCContentFilter
}

/// Reads the maths in part of the screen: a screenshot of just that part with
/// ScreenCaptureKit (which leaves out MathPeek's own windows), text recognition on this Mac
/// with Vision, and then the sum nearest the pointer. Nothing is saved or sent anywhere.
///
/// To be instant, it keeps the displays' capture filters between reads (asking for them takes
/// longer than the picture), and `warmUp` loads Vision's models at launch: the first text
/// recognition in a process can take many seconds.
actor ScreenReader {
    static let shared = ScreenReader()

    private var filters: [CGDirectDisplayID: DisplayFilter] = [:]

    /// A picture of the area, without MathPeek's own windows.
    private static func picture(of area: ScreenArea) async throws -> CGImage {
        do {
            return try await capture(area, with: try await shared.filter(for: area.displayID, fresh: false))
        } catch {
            // The displays may have changed since the filters were made.
            return try await capture(area, with: try await shared.filter(for: area.displayID, fresh: true))
        }
    }

    /// Every problem in the area that MathPeek can work out on its own, with where it is: for
    /// highlighting what can be clicked when an area is being chosen. Apple Intelligence isn't
    /// asked: that takes seconds, and waits until something is clicked.
    /// `seen`, for the debug view, is given everything that was made out along the way.
    static func spot(_ area: ScreenArea, _ options: ReadOptions, seen: SeenBox? = nil) async -> [Spotted] {
        guard let image = try? await picture(of: area) else { return [] }
        // Diagrams too, each as one thing to click: found while the text is read, then
        // given the words of the question beside them.
        async let drawn = Task.detached { DiagramReader.diagrams(in: image, limit: 12) }.value
        let text = try? recognize(image, size: area.rect.size)
        let written = text.map { spotted(in: $0, options) } ?? []
        let diagrams = solved(await drawn, in: image, size: area.rect.size, text: text).map { Spotted(box: $0.box, solutions: $0.solutions) }
        // What's written inside a diagram is part of it.
        let all = diagrams + written.filter { spot in
            !diagrams.contains { $0.box.insetBy(dx: -4, dy: -4).contains(CGPoint(x: spot.box.midX, y: spot.box.midY)) }
        }
        seen?.seen = Self.seen(in: image, size: area.rect.size, text: text, shown: all, options)
        return all
    }

    /// The diagrams found in a picture, worked out: where each is, in points, and every angle
    /// or side of it that follows from what's marked and from what the words beside it say.
    static func solved(_ found: [DiagramReader.Found], in image: CGImage, size: CGSize, text: RecognisedText?) -> [(box: CGRect, solutions: [Solution])] {
        let scale = CGFloat(image.width) / max(size.width, 1)
        let boxes = found.map { CGRect(x: $0.box.minX / scale, y: $0.box.minY / scale, width: $0.box.width / scale, height: $0.box.height / scale) }
        return zip(found, boxes).compactMap { item, box in
            var diagram = item.diagram
            // A question's words run on under its diagram, as far as the next diagram down.
            let next = boxes.filter { $0.minY > box.maxY - 4 && $0.maxX > box.minX - box.width && $0.minX < box.maxX + box.width }.map(\.minY).min()
            let bottom = min(next.map { $0 - 6 } ?? .infinity, box.maxY + max(box.height * 1.6, 320))
            var question = text.map { words(by: box, in: $0, downTo: bottom) } ?? ""
            // What the question says before its drawing, further up than "beside it": one
            // instruction over a row of drawings.
            if let text {
                let rows = text.lines.map { (text: $0.pieces.map { $0.readings[0] }.joined(separator: " "), height: $0.box.midY, left: $0.box.minX) }
                let opening = Asked.opening(rows, at: box.midY, across: box.midX, above: box.minY - box.height * 0.5)
                if !opening.isEmpty { question = opening + "\n" + question }
            }
            if case .circle(var drawn) = diagram, text != nil {
                DiagramWords.apply(question, to: &drawn)
                diagram = .circle(drawn)
            } else if case .triangle(var drawn) = diagram, text != nil {
                DiagramWords.apply(question, to: &drawn)
                diagram = .triangle(drawn)
            }
            // Only what the words ask for: the angles of a triangle aren't the answer to "work out the area of the shape".
            let solutions = DiagramWords.wanted(question, among: diagram.solutions)
            return solutions.isEmpty ? nil : (box, solutions)
        }
    }

    /// The words of the question a diagram belongs to: what's written beside it and under
    /// it, where exam questions say what's given and what to find.
    static func words(by box: CGRect, in text: RecognisedText, downTo bottom: CGFloat? = nil) -> String {
        let top = box.minY - box.height * 0.5
        let near = CGRect(x: box.minX - max(box.width * 1.2, 260), y: top, width: box.width + 2 * max(box.width * 1.2, 260), height: (bottom ?? box.maxY + box.height * 1.6) - top)
        var lines: [String] = []
        for line in text.lines {
            let pieces = line.pieces.filter { near.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) && !box.insetBy(dx: 4, dy: 4).contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
            if !pieces.isEmpty { lines.append(pieces.map { $0.readings[0] }.joined(separator: " ")) }
        }
        return lines.joined(separator: "\n")
    }

    static func spotted(in text: RecognisedText, _ options: ReadOptions) -> [Spotted] {
        var spotted: [Spotted] = []
        func add(_ box: CGRect, _ solution: Solution) {
            guard !spotted.contains(where: { overlaps($0.box, box, by: 0.1) }) else { return }
            spotted.append(Spotted(box: box, solutions: [solution]))
        }
        // Questions in words, a paragraph at a time.
        for paragraph in paragraphs(in: text) where paragraph.isSound && paragraph.tall.map({ $0 >= smallestTall + 2 }) ?? false {
            let fixed = String(ProblemFinder.fixSlips(paragraph.text))
            // (Or one of the questions in words that always mean the same sum.)
            guard let problem = ProblemFinder.sentenceProblem(in: fixed).flatMap({ Parser.problem($0.text) }) ?? Worded.problem(fixed),
                  let solution = Engine.solve(problem, angles: options.angles),
                  !solution.answers.isEmpty, solution.answers.allSatisfy({ $0.parts.last?.symbols.subtracting(["n"]).isEmpty ?? false }) else { continue }
            add(paragraph.box, solution)
        }
        // Only what's certain is pointed out. Text too small to make out may have lost a
        // power, and the answer would be to a different question; so would the answer to the
        // top of a fraction on its own.
        var likely: [(candidate: Candidate, solution: Solution)] = []
        for candidate in problems(in: text, to: nil) {
            guard !candidate.isSuspect, candidate.tall.map({ $0 >= smallestTall }) ?? candidate.fromStack else { continue }
            if let page = text.page {
                if !candidate.fromStack, page.isPartOfFraction(candidate.box, tall: candidate.tall) { continue }
                // A line that was laid out from its fractions can still be the top of a bigger one.
                let inPixels = page.inPicture(candidate.box)
                if candidate.fromStack, page.ink.hasBarRunningOn(beside: inPixels, tall: candidate.tall ?? inPixels.height * 0.5) { continue }
            }
            guard let solution = worked(candidate.text, options) else { continue }
            guard isAnswerInNumbers(solution) else { continue }
            // A sum picked out of a question in words about something else, a remainder or
            // a sequence, isn't what's being asked.
            switch solution.problem.kind {
            case .evaluate, .simplify:
                if !candidate.isAlone, candidate.context.range(of: #"(?i)remainder|divided\s+by|\bterms?\b|sequence|proportional|\bvaries\b"#, options: .regularExpression) != nil { continue }
                // "a 3 × 3 matrix", "an 8 × 10 photo": two numbers with a times sign and a
                // noun after them are a size, not a sum.
                if candidate.following.count >= 3, !["and", "then", "equals", "gives", "from"].contains(candidate.following.lowercased()),
                   candidate.text.range(of: #"^\s*\d+(\.\d+)?\s*[×xX*]\s*\d+(\.\d+)?\s*$"#, options: .regularExpression) != nil { continue }
                // A number hard up against a bracket, "5(9 + 16)", is how a root sign
                // read as a digit comes out. Sums in numbers are set with a times sign.
                if !candidate.text.contains(where: \.isLetter), candidate.text.range(of: #"\d\("#, options: .regularExpression) != nil { continue }
            default:
                break
            }
            likely.append((candidate, solution))
        }
        // Each is read a second time on its own, enlarged. Text recognition makes different
        // mistakes at a different size, so what it reads the same twice is right. Powers are
        // the exception, read wrongly at any size: for those the ink has the say.
        guard let page = text.page else { return Array(spotted.prefix(60)) }
        // (From the diagram session, 12 Nov: the same test as where the pointer is. A sum
        // quoted in a sentence that asks for something else, one of the answers to choose
        // from, a line of someone's working: none of those is pointed out as an answer.)
        let rows = text.lines.map { (text: $0.pieces.map { $0.readings[0] }.joined(separator: " "), height: $0.box.midY, left: $0.box.minX) }
        for (item, solution) in zip(likely, confirmed(likely, on: page, options)) {
            guard let solution else { continue }
            let box = item.candidate.box
            let asked = Asked.answers([solution], at: [box.midY], lefts: [box.minX], primary: 0, lines: rows, pointer: box.midY, across: box.minX, angles: options.angles).solutions
            if asked.contains(where: { $0.answerText == solution.answerText }) {
                add(box, solution)
            } else if let first = asked.first, isAnswerInNumbers(first) {
                add(box, first)
            }
        }
        return Array(spotted.prefix(60))
    }

    /// Each problem read a second time on its own, enlarged, and where that doesn't settle
    /// it a third: the solution to go with for each, or nil where the readings don't agree.
    /// Text recognition makes different mistakes at a different size, so what it reads the
    /// same twice is right. Powers are the exception, read wrongly at any size: for those the
    /// ink has the say, and a reading the ink doesn't bear out only counts if another does.
    private static func confirmed(_ likely: [(candidate: Candidate, solution: Solution)], on page: Page, _ options: ReadOptions) -> [Solution?] {
        /// Whether a look at a problem on its own came out the same as a reading of it: the
        /// same characters, or (for a question put together from words or from a stack) the
        /// same question and answer.
        func agrees(_ look: (text: String, found: [Candidate]), with reading: Candidate, _ solution: Solution) -> Bool {
            // The whole line read the same again: then so did the problem in it, whatever
            // was made of it afterwards ("the remainder when … is divided by 13").
            if !reading.context.isEmpty, sameCharacters(reading.context, look.text) { return true }
            return sameCharacters(reading.text, look.text) || look.found.contains { other in
                if sameCharacters(reading.text, other.text) { return true }
                guard let again = worked(other.text, options) else { return false }
                return again.question.text == solution.question.text && again.answerText == solution.answerText
            }
        }
        var result = [Solution?](repeating: nil, count: likely.count)
        let second = secondLook(at: likely.map(\.candidate), on: page, capHeight: 40)
        /// A reading the ink bears out, with the same characters as one it doesn't: the
        /// solution to that reading, which has the powers right. Where both have a power in
        /// the same place they must be the same power.
        func borneOut(_ look: (text: String, found: [Candidate]), for reading: Candidate) -> Solution? {
            guard let other = look.found.first(where: { $0.isChecked && sameCharacters($0.text, reading.text) && samePowers($0.text, reading.text) }),
                  let solution = worked(other.text, options), isAnswerInNumbers(solution) else { return nil }
            // A raised mark that the first reading saw and couldn't read has to turn up in
            // this one as a power: a reading without it has only lost it altogether.
            if reading.hasUnreadMark, other.text.filter({ $0 == "^" }).count <= reading.text.filter({ $0 == "^" }).count { return nil }
            return solution
        }
        var undecided: [Int] = []
        for (index, item) in likely.enumerated() {
            if item.candidate.isChecked {
                if agrees(second[index], with: item.candidate, item.solution) { result[index] = item.solution } else { undecided.append(index) }
            } else if let solution = borneOut(second[index], for: item.candidate) {
                result[index] = solution
            } else {
                undecided.append(index)
            }
        }
        // Where the second reading differs, a third at another size: the first stands if the
        // third agrees with it. Two enlarged readings agreeing against the first prove
        // nothing, since they can share a mistake; then there's no answer.
        let third = secondLook(at: undecided.map { likely[$0].candidate }, on: page, capHeight: 28)
        for (index, look) in zip(undecided, third) {
            let item = likely[index]
            if item.candidate.isChecked {
                if agrees(look, with: item.candidate, item.solution) { result[index] = item.solution }
            } else if let solution = borneOut(look, for: item.candidate) {
                result[index] = solution
            }
        }
        return result
    }

    /// Whether two readings have the same powers, where both have powers at all: "x^3" and
    /// "x^5" differ, but "x^2" and a reading that lost the power don't.
    static func samePowers(_ a: String, _ b: String) -> Bool {
        func powers(_ text: String) -> [String] {
            let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"]
            var plain = ""
            for character in ProblemFinder.fixSlips(text) {
                if let digit = superscripts[character] { plain += "^" + String(digit) } else { plain.append(character) }
            }
            guard let regex = try? NSRegularExpression(pattern: #"\^\(?([0-9a-zA-Z]+)"#) else { return [] }
            return regex.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)).compactMap { Range($0.range(at: 1), in: plain).map { String(plain[$0]) } }
        }
        let first = powers(a), second = powers(b)
        return first.count != second.count || first == second
    }

    /// Whether a problem is worth pointing out. A formula like A + B = C can only be
    /// rearranged, which nobody asked for: an equation is, when it has an answer in numbers.
    /// "128 + 419 = 0" isn't a question anyone set, so something in it was misread; and
    /// "3 + 2 = 5" has its answer already.
    private static func isAnswerInNumbers(_ solution: Solution) -> Bool {
        if case .solve = solution.problem.kind, !solution.answers.isEmpty,
           !solution.answers.allSatisfy({ $0.parts.last?.symbols.isEmpty ?? false }) { return false }
        if solution.answers.isEmpty, solution.problem.kind.variable == nil { return false }
        // Nothing to show for a sum that can't be worked out: a misreading, more likely than not.
        if solution.answers.isEmpty, solution.note.map({ $0.hasPrefix("This has no real answer") || $0.hasPrefix("No solutions between") }) ?? true { return false }
        return solution.problem.writtenAnswer == nil
    }

    /// Capitals shorter than this, in pixels, are too small to read reliably.
    static let smallestTall: CGFloat = 12

    /// Reads each candidate again from a sheet where its part of the picture is drawn on its
    /// own, dark on white, at a size text recognition is best at. What's found in each.
    private static func secondLook(at candidates: [Candidate], on page: Page, capHeight: CGFloat) -> [(text: String, found: [Candidate])] {
        guard !candidates.isEmpty else { return [] }
        let rowHeight = capHeight * 3.75, margin: CGFloat = 60
        var cuts: [(image: CGImage, size: CGSize)?] = []
        for candidate in candidates {
            // The whole line it's in, not just the problem: Vision reads a line better for
            // having its label and its words.
            let inPicture = page.inPicture(candidate.line.isNull ? candidate.box : candidate.line.union(candidate.box))
            // A stack of two lines or more has no one height of capital: go by its lines.
            let tall = candidate.tall ?? inPicture.height * 0.3
            var area = inPicture.insetBy(dx: -max(tall * 0.3, 3), dy: -max(tall * 0.3, 2))
            // The dots of a recurring decimal stand above the line: they come too, or the
            // second reading is of another number.
            if candidate.text.contains("rec(") || candidate.context.contains("rec(") {
                area = CGRect(x: area.minX, y: area.minY - tall * 0.7, width: area.width, height: area.height + tall * 0.7)
            }
            guard tall >= 4, let image = page.ink.cutOut(area) else { cuts.append(nil); continue }
            var scale = min(max(capHeight / tall, 0.4), 5)
            scale = min(scale, (rowHeight - 20) / CGFloat(image.height))
            cuts.append((image, CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)))
        }
        // Vision reads a short piece of maths on its own as nonsense, and reads it properly
        // after a couple of words: each row starts with some, a wide gap before the maths.
        let font = CTFontCreateUIFontForLanguage(.system, capHeight / 0.705, nil)!
        let lead = CTLineCreateWithAttributedString(CFAttributedStringCreate(
            nil, "Work out" as CFString, [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true] as CFDictionary)!)
        let start = margin + CGFloat(CTLineGetTypographicBounds(lead, nil, nil, nil)) + capHeight * 3
        // A line that's only a few characters is read after "N =", close up: on its own,
        // even after words at a distance, Vision often reads nothing at all.
        let letter = CTLineCreateWithAttributedString(CFAttributedStringCreate(
            nil, "N = " as CFString, [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true] as CFDictionary)!)
        let afterLetter = margin + CGFloat(CTLineGetTypographicBounds(letter, nil, nil, nil))
        func isShort(_ row: Int) -> Bool { cuts[row].map { $0.size.width < capHeight * 4 && $0.size.height < capHeight * 2.2 } ?? false }
        let widest = cuts.compactMap { $0?.size.width }.max() ?? 0
        let width = Int(start + widest + margin), height = Int(rowHeight * CGFloat(candidates.count) + margin * 2)
        guard widest > 0, width * height < 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return candidates.map { _ in ("", []) } }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        var places: [(box: CGRect, tall: CGFloat)] = []
        for (row, cut) in cuts.enumerated() {
            guard let cut else { continue }
            let middle = CGFloat(height) - margin - rowHeight * (CGFloat(row) + 0.5)
            places.append((CGRect(x: start, y: CGFloat(height) - middle - cut.size.height / 2, width: cut.size.width, height: cut.size.height),
                           min(capHeight, cut.size.height * 0.5)))
            context.setFillColor(gray: 0, alpha: 1)
            context.textPosition = CGPoint(x: margin, y: middle - capHeight / 2)
            CTLineDraw(isShort(row) ? letter : lead, context)
            let start = isShort(row) ? afterLetter : start
            context.draw(cut.image, in: CGRect(x: start, y: middle - cut.size.height / 2, width: cut.size.width, height: cut.size.height))
        }
        guard let sheet = context.makeImage(),
              let text = try? recognize(in: sheet, margin: 0, of: sheet, size: CGSize(width: width, height: height), depth: 1, alsoLookAt: places) else {
            return candidates.map { _ in ("", []) }
        }
        func row(_ box: CGRect) -> Int { Int(((box.midY - margin) / rowHeight).rounded(.down)) }
        return candidates.indices.map { index in
            if isShort(index) {
                // What follows "N =": the line as a string, its problems found in that.
                let pieces = text.lines.filter { row($0.box) == index }.flatMap(\.pieces).sorted { $0.box.minX < $1.box.minX }
                var read = pieces.map { $0.readings[0] }.joined(separator: " ")
                guard let lead = read.range(of: #"^\s*[NnMH]\s*[=-]\s?"#, options: .regularExpression) else { return ("", []) }
                read.removeSubrange(lead)
                let isChecked = pieces.allSatisfy { piece in piece.words[0].allSatisfy(\.isChecked) }
                let found = ProblemFinder.problems(in: read).map {
                    Candidate(text: $0.text, distance: 0, box: .zero, isEquationOrCommand: $0.text.contains("="), isChecked: isChecked)
                }
                return (read, found)
            }
            let lines = text.lines.filter { row($0.box) == index && $0.box.minX > start - capHeight }.sorted { a, b in
                abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5 ? a.box.minX < b.box.minX : a.box.minY < b.box.minY
            }
            let part = RecognisedText(lines: lines, stacked: text.stacked.filter { row($0.box) == index && $0.box.minX > start - capHeight }, page: text.page)
            let read = lines.map { $0.pieces.map { $0.readings[0] }.joined(separator: " ") }.joined(separator: " ")
            let found = problems(in: part, to: nil)
            return (read, found)
        }
    }

    /// Whether another reading of a problem has the same characters as `reference`, leaving
    /// its powers aside: where the reference has a power, the other reading may have
    /// anything of that length or nothing. The powers are checked against the ink instead.
    static func sameCharacters(_ reference: String, _ other: String) -> Bool {
        let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"]
        /// The marks Vision puts where there's a power it couldn't read: x', x*, x°.
        let marks = "'*°?`´′\u{FFFD}"
        func plain(_ text: String) -> [Character] {
            var fixed = ProblemFinder.fixSlips(text)
            while let last = fixed.last, " ?.".contains(last) { fixed.removeLast() }
            return fixed.indices.compactMap { index -> Character? in
                let character = fixed[index]
                if " ¦;:!".contains(character) { return nil }
                // A full stop or comma counts only inside a number.
                if ".,".contains(character) {
                    let inNumber = index > 0 && index + 1 < fixed.count && fixed[index - 1].isNumber && fixed[index + 1].isNumber
                    return inNumber ? character : nil
                }
                // A letter that's the same shape small and capital (s and S) is the same
                // letter either way: enlarged, a small one is often read as the capital.
                if "COSUVWXZ".contains(character) { return Character(character.lowercased()) }
                return "−–".contains(character) ? "-" : character
            }
        }
        // The reference as a pattern: its characters as they are, its powers as gaps. A mark
        // in the other reading where the reference has no power means there is one there,
        // unread: the readings don't agree.
        let characters = plain(reference)
        var pattern = ""
        var index = 0
        func gap(_ length: Int) { pattern += "[0-9a-zA-Z^()'*°?`´′\u{FFFD}]{0,\(length + 2)}" }
        while index < characters.count {
            let character = characters[index]
            if character == "^" {
                var end = index + 1
                if end < characters.count, characters[end] == "(" {
                    while end < characters.count, characters[end] != ")" { end += 1 }
                    end = min(end + 1, characters.count)
                } else {
                    while end < characters.count, characters[end].isNumber || characters[end].isLetter { end += 1 }
                }
                gap(end - index - 1)
                index = end
            } else if superscripts[character] != nil {
                var end = index
                while end < characters.count, superscripts[characters[end]] != nil { end += 1 }
                gap(end - index)
                index = end
            } else if marks.contains(character) {
                // A mark that's really there, like the ° of an angle: there or not in the other.
                pattern += NSRegularExpression.escapedPattern(for: String(character)) + "?"
                index += 1
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }
        let text = String(plain(other).map { superscripts[$0] ?? $0 })
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whether a word is maths rather than prose: it has a number or a sign in it.
    private static func isMaths(_ word: some StringProtocol) -> Bool {
        word.contains { $0.isNumber || "+-−=×÷/^√<>".contains($0) || $0 == LineMender.unreadable }
    }

    /// Whether the ink bears out all the maths in a line. Its words matter less: a word read
    /// a little wrong doesn't change the question, as long as nothing was left out of it.
    private static func isSound(_ line: Line) -> Bool {
        line.pieces.allSatisfy { piece in
            let characters = Array(piece.readings[0])
            return piece.words[0].allSatisfy { $0.isChecked || (!$0.isSuspect && !isMaths(String(characters[$0.range]))) }
        }
    }

    /// Lines of words that follow on from each other, as one piece of text each.
    static func paragraphs(in text: RecognisedText) -> [(text: String, box: CGRect, isSound: Bool, tall: CGFloat?)] {
        func reading(_ line: Line) -> String { line.pieces.map { $0.readings[0] }.joined(separator: " ") }
        func isProse(_ line: Line) -> Bool {
            reading(line).split(separator: " ").filter { $0.filter(\.isLetter).count >= 2 }.count >= 3
        }
        /// "7.", "(b)", "Q3": the start of another question.
        func isNumbered(_ line: Line) -> Bool {
            reading(line).range(of: #"^\s*(\(?\d{1,2}[.)]|\(?[a-zA-Z]\)|\([ivx]{2,4}\)|Q\d{1,2}[.:]?|(Example|Question|Exercise|Problem)\s+\d+[.:)]?)\s"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
        }
        var result: [(text: String, box: CGRect, isSound: Bool, tall: CGFloat?)] = []
        func tall(_ line: Line) -> CGFloat? { line.pieces.map { $0.tall ?? 0 }.min().flatMap { $0 > 0 ? $0 : nil } }
        /// Where the line's ink is: Vision's own box for a line is loose.
        func ink(_ line: Line) -> CGRect {
            let words = line.pieces.flatMap { $0.words[0].map(\.box) }.reduce(CGRect.null) { $0.union($1) }
            return words.isNull ? line.box : words
        }
        func hasWord(_ line: Line) -> Bool { reading(line).split(separator: " ").contains { $0.filter(\.isLetter).count >= 2 } }
        // The last line of each paragraph so far, and the widest gap between its lines: a
        // page can have several columns, with a paragraph going on in each.
        var ends: [(last: Line, spacing: CGFloat?)] = []
        for line in text.lines.sorted(by: { $0.box.minY < $1.box.minY }) {
            // The rest of a question can be mostly maths: "x = 4, y = 12. Find y when x = 10."
            let open = isNumbered(line) || !hasWord(line) ? nil : ends.indices.last { index in
                let previous = ends[index].last
                let gap = line.box.minY - previous.box.maxY
                guard gap > -previous.box.height * 0.3, gap < previous.box.height * 0.9, gap <= (ends[index].spacing ?? gap) * 1.5 + 2,
                      abs(line.box.minX - previous.box.minX) < previous.box.height * 2.5, line.box.minX < previous.box.maxX else { return false }
                // The same size of text, with no rule between: the next row of a table, or
                // the small print under a question, is something else.
                if let size = tall(line), let before = tall(previous), abs(size - before) > before * 0.2 { return false }
                if let page = text.page {
                    let upper = page.inPicture(previous.box), lower = page.inPicture(line.box)
                    if page.ink.hasBar(between: upper, and: lower, length: min(upper.width, lower.width) * 0.6, faint: true) { return false }
                }
                return true
            }
            if let open {
                let gap = line.box.minY - ends[open].last.box.maxY
                result[open].text += " " + reading(line)
                result[open].box = result[open].box.union(ink(line))
                result[open].isSound = result[open].isSound && isSound(line)
                result[open].tall = tall(line).flatMap { height in result[open].tall.map { min($0, height) } }
                ends[open] = (line, max(ends[open].spacing ?? 0, gap))
            } else if isProse(line) {
                result.append((reading(line), ink(line), isSound(line), tall(line)))
                ends.append((line, nil))
            }
        }
        return result
    }

    /// Whether a line of what was read has an upright bar with no partner: |x − 3| has two, a
    /// caret in a text box is one on its own.
    static func hasLoneBar(_ text: RecognisedText) -> Bool {
        text.lines.contains { line in
            line.pieces.compactMap(\.readings.first).joined(separator: " ").filter { $0 == "|" }.count % 2 == 1
        }
    }

    /// A problem written as text, worked out: nil if it isn't one, or there's nothing to do.
    static func worked(_ maths: String, _ options: ReadOptions) -> Solution? {
        guard let problem = Parser.problem(maths), let solution = Engine.solve(problem, angles: options.angles),
              !solution.answers.isEmpty || solution.note != nil else { return nil }
        // A bit of algebra picked out of a sentence that's already as simple as it gets
        // isn't a problem: there's nothing to work out.
        if case .simplify = problem.kind, solution.answers.count == 1 {
            let answer = solution.answers[0].text.filter { !$0.isWhitespace }.sorted(), question = solution.question.text.filter { !$0.isWhitespace }.sorted()
            // The same again, or the same letters in another order ("ut" as "tu").
            if answer == question { return nil }
        }
        // …nor is anything else whose answer is what was written, "scale factor 1/2" taken
        // as "factor 1/2".
        switch problem.kind {
        case .evaluate, .factorise, .expand:
            if solution.answers.count == 1, solution.note == nil,
               solution.answers[0].text.filter({ !$0.isWhitespace }) == solution.question.text.filter({ !$0.isWhitespace }) { return nil }
        default:
            break
        }
        // A formula with its subject on the left, s = ½at², already says what s is: its
        // right-hand side tidied up isn't the answer to anything. What's asked of a formula
        // ("make t the subject") is in the words round it.
        let sides = maths.split(separator: "=", omittingEmptySubsequences: false)
        if sides.count == 2, solution.answers.count == 1, solution.note == nil {
            let left = sides[0].trimmingCharacters(in: .whitespaces)
            let others = Set(sides[1].filter { $0.isLetter && $0.isASCII }.map { String($0) })
            // (The answer is in those same letters: a turning point or a number is something found.)
            let answer = solution.answers[0].text
            let inAnswer = Set(answer.filter { $0.isLetter && $0.isASCII }.map { String($0) }).subtracting([left])
            if left.count == 1, left.first?.isLetter == true, !others.contains(left), others.count >= 2,
               !inAnswer.isEmpty, inAnswer.isSubset(of: others), !answer.contains("=") || answer.hasPrefix(left) { return nil }
        }
        return solution
    }

    /// `wide` is a bigger area round the same point, to look for a diagram in: a diagram
    /// takes up far more room than a line of maths.
    static func read(_ area: ScreenArea, wide: ScreenArea? = nil, _ options: ReadOptions) async -> Reading {
        let image: CGImage
        do {
            image = try await picture(of: area)
        } catch {
            return .failed("Couldn't read the screen: \(error.localizedDescription)")
        }
        // A circle diagram the pointer is on is worked out as a whole, while the text is read.
        async let drawn: (solutions: [Solution], isPointedAt: Bool)? = {
            let around = wide ?? area
            guard let picture = wide == nil ? image : try? await ScreenReader.picture(of: around) else { return nil }
            let scale = CGFloat(picture.width) / max(around.rect.width, 1)
            let found = DiagramReader.diagrams(in: picture, near: CGPoint(x: around.focus.x * scale, y: around.focus.y * scale), limit: 1)
            guard !found.isEmpty else { return nil }
            // The question's words are read from the same picture as the diagram.
            guard let nearest = solved(found, in: picture, size: around.rect.size, text: try? recognize(picture, size: around.rect.size)).first else { return nil }
            return (nearest.solutions, nearest.box.insetBy(dx: -6, dy: -6).contains(around.focus))
        }()
        let reading: Reading
        do {
            var text = try recognize(image, size: area.rect.size)
            var picture = image
            // A text box's caret is a thin upright line the height of the text, and reads as
            // a bar or a 1 in the middle of the sum. It blinks: an upright bar with no partner
            // is looked at again half a second later, and once more, and if it's gone by then
            // that picture is the one that's read. One that stays is a bar, or a caret that
            // isn't blinking, and the line is left as it was read.
            if hasLoneBar(text) {
                for wait in [0.55, 0.3] {
                    try? await Task.sleep(for: .seconds(wait))
                    guard let again = try? await ScreenReader.picture(of: area), let reread = try? recognize(again, size: area.rect.size) else { break }
                    if !hasLoneBar(reread) {
                        text = reread
                        picture = again
                        break
                    }
                }
            }
            let answer = await solve(text, image: picture, focus: area.focus, options)
            // Still there on the line the pointer is on: with a bar that may be a caret in
            // the middle of it, the sum can't be told from another one.
            let isBarred = text.lines.contains { line in
                line.pieces.compactMap(\.readings.first).joined(separator: " ").filter { $0 == "|" }.count % 2 == 1
                    && abs(line.box.midY - area.focus.y) <= max(line.box.height, 12)
            }
            if isBarred, case .solved = answer { reading = .unclear } else { reading = answer }
        } catch {
            reading = .failed("Couldn't recognise the text: \(error.localizedDescription)")
        }
        guard let diagram = await drawn else { return reading }
        if diagram.isPointedAt { return .solved(diagram.solutions, primary: 0) }
        // Nothing written that could be worked out, but a diagram close by.
        if case .solved = reading { return reading }
        return .solved(diagram.solutions, primary: 0)
    }

    /// The problems in the area, worked out: each separate one, nearest the pointer first in
    /// importance. Text recognition is instant and exact, so it goes first; Apple Intelligence
    /// reads word problems, and maths laid out over several lines (stacked fractions), where text
    /// recognition misses lone letters and signs.
    static func solve(_ text: RecognisedText, image: CGImage?, focus: CGPoint, _ options: ReadOptions) async -> Reading {
        let found = problems(in: text, to: focus)
        let nearest = found.min { $0.distance < $1.distance }
        let prose = proseNear(focus, in: text)
        let modelReady = options.useModel && Tutor.isAvailable
        func solved(_ maths: String) -> Solution? { worked(maths, options) }
        /// Whether maths the model wrote came out as plain numbers. Anything else means it
        /// left something out, and the answer would be to a different question.
        func isSettled(_ solution: Solution) -> Bool {
            !solution.answers.isEmpty && solution.answers.allSatisfy { $0.parts.last?.symbols.isEmpty ?? false }
        }
        // The question the pointer is in, where more than one is in the area: its lines, top
        // to bottom, and the sentences among them.
        // (Numbers set out along a row, the terms of a sequence, are separate lines level with
        // each other: left to right, not by which box happens to start a hair higher.)
        let ordered = text.lines.sorted { a, b in
            abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5 ? a.box.minX < b.box.minX : a.box.minY < b.box.minY
        }
        let rows = ordered.map { (text: $0.pieces.map { $0.readings[0] }.joined(separator: " "), height: $0.box.midY, left: $0.box.minX) }
        // Lines with maths in them that the ink says was misread, and that read as if nothing
        // were wrong ("3^2 − 22x + 7" for 3x² − 22x + 7): no question in words is answered
        // from one of those, any more than the sum itself would be. (Not a number on its
        // own, a question's label. Not a word with a stray mark in it either, "(x+e)^2'+^f":
        // what's wrong there shows, and a solver takes it or leaves it.)
        let isMisread = ordered.map { line -> Bool in
            let hasSuspectMaths = line.pieces.contains { piece in
                guard let words = piece.words.first, let reading = piece.readings.first else { return false }
                let characters = Array(reading)
                return words.contains { word in
                    guard word.isSuspect, word.range.upperBound <= characters.count else { return false }
                    let written = String(characters[word.range])
                    // (Maths: a number with a sign, a power or a bracket to it. Not "mark1" for
                    // "mark]", and not a label, "(1)" for (l).)
                    guard written.contains(where: \.isNumber), written.contains(where: { "+-−×÷*/=^²³√(".contains($0) }),
                          written.range(of: #"^\(?(\d{1,2}|[A-Za-z])\)?[.:]?$"#, options: .regularExpression) == nil else { return false }
                    return written.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || "+-−×÷*/=().,^²³√".contains($0) }
                }
            }
            let whole = line.pieces.map { $0.readings[0] }.joined(separator: " ")
            return hasSuspectMaths && whole.contains(where: { !$0.isNumber && !" .\u{FFFD}".contains($0) })
        }
        // (From the diagram session, 12 Nov: a misread line that is only one of the answers to
        // choose from, under "Circle your answer", says nothing the question depends on. It
        // doesn't stop an answer worked out from the question's own sentence; the solvers of
        // words are then not shown the lines of choices at all, so none can pick a misread one.)
        let choiceLines = Asked.choiceLines(rows, pointer: focus.y, across: focus.x)
        let hasMisreadChoice = zip(rows, isMisread).contains { $0.1 && choiceLines.contains($0.0.text) }
        let isMisreadLine = zip(rows, isMisread).map { $0.1 && !choiceLines.contains($0.0.text) }
        let doubtful = Set(zip(rows, isMisreadLine).filter(\.1).map(\.0.text))
        func isDoubtful(_ question: String) -> Bool { question.split(separator: "\n").contains { doubtful.contains(String($0)) } }
        // The lines without those. The part pointed at, or the whole of its question, has
        // one in it if it comes out different with them taken away.
        let soundRows = zip(rows, isMisreadLine).filter { !$0.1 }.map(\.0)
        let everything = Asked.pointed(rows, pointer: focus.y, across: focus.x)
        let hasMisreadPart = !doubtful.isEmpty && Asked.pointed(soundRows, pointer: focus.y, across: focus.x) != everything
        let hasMisreadLine = hasMisreadPart || (!doubtful.isEmpty
            && Asked.pointed(soundRows, pointer: focus.y, across: focus.x, whole: true) != Asked.pointed(rows, pointer: focus.y, across: focus.x, whole: true))
        let sentences = everything.split(separator: "\n").filter { line in line.split(separator: " ").filter { $0.filter(\.isLetter).count >= 2 }.count >= 3 }.joined(separator: " ")
        // A question in words that MathPeek reads itself, over as many lines as it takes. Its
        // answer goes first, and the maths in the question, worked out as it stands, comes
        // after it as further answers.
        var lead: Solution?
        if prose != nil, !hasMisreadPart, let problem = WordProblems.problem(sentences), let solution = Engine.solve(problem, angles: options.angles),
           !solution.answers.isEmpty || solution.note != nil {
            lead = solution
        }
        // A question whose sum is spread over more than its sentence: a formula on a line of
        // its own, a table, a row of values to choose from. Every line of the question.
        // (Also where the question is too short to count as a sentence: "Work out 20% of 14 000".)
        // (The part pointed at; failing that, the whole of its question: a table's values may be in the next part.)
        func inWords(_ text: String) -> Solution? {
            guard !isDoubtful(text) else { return nil }
            let text = hasMisreadChoice ? text.split(separator: "\n").filter { !choiceLines.contains(String($0)) }.joined(separator: "\n") : text
            // (A solver whose problem comes to nothing doesn't stop the next one being tried.)
            // (From the diagram session: a bare amount of money or percentage gets its £ or %.)
            if let problem = Worded.problem(text).map({ WordProblems.signed($0, for: text) }), let solution = Engine.solve(problem, angles: options.angles), !solution.answers.isEmpty { return solution }
            guard let problem = WordedTopics.problem(text).map({ WordProblems.signed($0, for: text) }), let solution = Engine.solve(problem, angles: options.angles), !solution.answers.isEmpty else { return nil }
            return solution
        }
        // The part pointed at has a line like that: nothing can be made of it.
        if hasMisreadPart { return .unclear }
        if lead == nil { lead = inWords(everything) }
        // (Not an answer that comes out the same without the part pointed at: that's another part's.)
        if lead == nil, !hasMisreadLine { lead = Asked.wholeQuestion(rows, pointer: focus.y, across: focus.x, inWords) }
        // Everything that was read, for holding the model to it.
        let seen = (text.lines.flatMap { $0.pieces.flatMap(\.readings) } + text.stacked.map(\.text)).joined(separator: " ")
        // A word problem: the model writes it as maths.
        if lead == nil, modelReady, let prose, nearest.map({ !$0.isEquationOrCommand }) ?? true,
           let (maths, meaning) = await Tutor.translate(prose), isGrounded(maths, in: prose, isWords: true),
           var solution = solved(maths), isSettled(solution) {
            solution.steps.insert(Step("Write it as maths", meaning.map { "Where \($0)." } ?? "Choose a letter for each unknown."), at: 0)
            solution.source = "Apple Intelligence turned the words into maths: \(maths)"
            // What each letter stands for goes with the answer, since the question didn't have them.
            if solution.note == nil, let meaning { solution.note = meaning.trimmingCharacters(in: CharacterSet(charactersIn: " .")) + "." }
            return .solved([solution], primary: 0)
        }
        // What text recognition found, leaving out anything the ink says was misread:
        // something left over that no character accounts for, or a line that's really the
        // top or bottom of a fraction.
        func isSound(_ candidate: Candidate) -> Bool {
            guard !candidate.isSuspect else { return false }
            guard let page = text.page else { return true }
            let inPixels = page.inPicture(candidate.box)
            if candidate.fromStack { return !page.ink.hasBarRunningOn(beside: inPixels, tall: candidate.tall ?? inPixels.height * 0.5) }
            return !page.isPartOfFraction(candidate.box, tall: candidate.tall)
        }
        let sound = found.filter(isSound)
        var likely: [(candidate: Candidate, solution: Solution)] = []
        for candidate in sound {
            if let solution = solved(candidate.text) { likely.append((candidate, solution)) }
        }
        // Each is read again on its own, enlarged: what text recognition reads the same
        // twice is right, and what it doesn't isn't to be trusted.
        var settled = likely.map { Optional($0.solution) }
        if options.confirms, let page = text.page { settled = confirmed(likely, on: page, options) }
        var solutions: [Solution] = []
        var places: [CGFloat] = [], lefts: [CGFloat] = []
        var primary = 0
        var best = CGFloat.infinity
        for (item, solution) in zip(likely, settled) {
            guard let solution else { continue }
            if item.candidate.distance < best {
                best = item.candidate.distance
                primary = solutions.count
            }
            solutions.append(solution)
            places.append(item.candidate.box.midY)
            lefts.append(item.candidate.box.minX)
        }
        // What the words round the maths ask of it goes first ("the turning point of the curve
        // y = (x − 3)² − 8"), and the maths worked out as it stands stays as another answer.
        // A lone number out of a sentence, said back, isn't an answer.
        if let lead { return .solved(Asked.answers(after: lead, solutions, at: places, lefts: lefts, lines: rows, pointer: focus.y, across: focus.x, angles: options.angles), primary: 0) }
        let asked = Asked.answers(solutions, at: places, lefts: lefts, primary: primary, lines: rows, pointer: focus.y, across: focus.x, angles: options.angles)
        if !asked.solutions.isEmpty { return .solved(asked.solutions, primary: asked.primary) }
        if !solutions.isEmpty { return .words }
        let isUnclear = found.count > sound.count || !likely.isEmpty
        // Nothing it could be sure of: the model reads the picture, and is held to what's there.
        if modelReady, let image, let maths = await Tutor.transcribe(image),
           isGrounded(maths, in: seen, isWords: false), var solution = solved(maths), prose == nil || isSettled(solution) {
            solution.source = "Apple Intelligence read it as: \(maths)"
            return .solved([solution], primary: 0)
        }
        if isUnclear { return .unclear }
        if let nearest {
            // A scrap of algebra from inside a sentence isn't what was asked.
            return prose == nil ? .unsolved(nearest.text) : .words
        }
        return prose == nil ? .noMaths : .words
    }

    /// Whether maths that Apple Intelligence wrote sticks to what's there. It makes things
    /// up: shown a circle with one angle marked 56°, it wrote x = (56 + 90 − 180)/2. Every
    /// number in its maths has to be one that was read from the screen, and (when it read a
    /// picture) every letter too. A question in words can also spell its numbers out, and
    /// may need a 2 or a 100 that isn't written: half, double, per cent.
    static func isGrounded(_ maths: String, in seen: String, isWords: Bool) -> Bool {
        let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"]
        func numbers(_ text: String) -> Set<String> {
            let plain = String(text.map { superscripts[$0] ?? $0 })
            guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return [] }
            return Set(regex.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)).compactMap { match in
                Range(match.range, in: plain).map { text -> String in
                    // 2.50 and 2.5, 07 and 7 are the same number.
                    var number = String(plain[text])
                    if number.contains(".") { while number.hasSuffix("0") { number.removeLast() }; if number.hasSuffix(".") { number.removeLast() } }
                    while number.count > 1, number.hasPrefix("0"), !number.hasPrefix("0.") { number.removeFirst() }
                    return number
                }
            })
        }
        var allowed = numbers(seen)
        if isWords {
            allowed.formUnion(["1", "2", "100"])
            let words: [String: String] = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
                                           "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "twenty": "20", "thirty": "30", "forty": "40",
                                           "fifty": "50", "sixty": "60", "hundred": "100", "thousand": "1000", "half": "2", "twice": "2",
                                           "double": "2", "triple": "3", "third": "3", "quarter": "4", "dozen": "12", "week": "7", "hour": "60",
                                           "minute": "60", "year": "12"]
            for word in seen.lowercased().split(whereSeparator: { !$0.isLetter }) {
                if let number = words[String(word)] ?? words[String(word.dropLast(word.hasSuffix("s") ? 1 : 0))] { allowed.insert(number) }
            }
        }
        guard numbers(maths).isSubset(of: allowed) else { return false }
        guard !isWords else { return true }
        // Its letters, leaving out the words maths is written with.
        var letters = maths.lowercased()
        for word in ["sqrt", "sin", "cos", "tan", "log", "ln", "pi", "solve", "simplify", "expand", "factorise", "factorize", "differentiate",
                     "integrate", "from", "to", "and", "or"] {
            letters = letters.replacingOccurrences(of: word, with: " ")
        }
        let onScreen = Set(seen.lowercased().map { Parser.lookalikes[$0] ?? $0 }.filter(\.isLetter))
        // d is the d of dx; e may be the number.
        return letters.filter(\.isLetter).allSatisfy { onScreen.contains($0) || $0 == "d" || $0 == "e" }
    }

    /// Gets text recognition (and, with Screen Recording, the capture filters) ready, so the
    /// first press is as quick as the rest. Recognises a made-up sum with the same settings as
    /// a read.
    static func warmUp(canCapture: Bool) async {
        if canCapture {
            await shared.prepareFilters()
        }
        let size = CGSize(width: 320, height: 80)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateUIFontForLanguage(.system, 28, nil)
        let text = NSAttributedString(string: "12 × (3 + 4.5) =",
                                      attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font as Any])
        context.textPosition = CGPoint(x: 12, y: 28)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        guard let image = context.makeImage() else { return }
        _ = try? recognize(image, size: size)
    }

    /// After the displays change: the next read asks for them afresh.
    func forgetScreens() {
        filters = [:]
    }

    private func prepareFilters() async {
        if filters.isEmpty, let made = try? await Self.makeFilters() {
            filters = made
        }
    }

    private func filter(for displayID: CGDirectDisplayID, fresh: Bool) async throws -> DisplayFilter {
        if !fresh, let filter = filters[displayID] { return filter }
        filters = try await Self.makeFilters()
        guard let filter = filters[displayID] else { throw CocoaError(.featureUnsupported) }
        return filter
    }

    /// Off-screen windows are included so MathPeek is in the list (and can be left out) even
    /// while none of its windows show.
    private static func makeFilters() async throws -> [CGDirectDisplayID: DisplayFilter] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownProcess }
        var filters: [CGDirectDisplayID: DisplayFilter] = [:]
        for display in content.displays {
            filters[display.displayID] = DisplayFilter(
                filter: SCContentFilter(display: display, excludingApplications: own, exceptingWindows: []))
        }
        return filters
    }

    private static func capture(_ area: ScreenArea, with display: DisplayFilter) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area.rect
        configuration.width = Int(area.rect.width * area.scale)
        configuration.height = Int(area.rect.height * area.scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: display.filter, configuration: configuration)
    }

    // MARK: Text recognition

    /// A word of a reading: its characters, counted from the start of the reading, where its
    /// ink is, and whether the ink bears the reading out (see LineMender).
    struct Word: Sendable {
        var range: Range<Int>
        var box: CGRect
        var isChecked: Bool
        /// There's ink in it that no character accounts for.
        var isSuspect = false
        /// The ink of each character, where it's known.
        var places: [CGRect?] = []
        /// There's a small raised mark in it that couldn't be read: a power, perhaps.
        var hasUnreadMark = false
    }

    /// One piece of text Vision found, with its best readings and the words of each, and where
    /// it is in points from the top-left of the area.
    struct Piece: Sendable {
        let readings: [String]
        let words: [[Word]]
        let box: CGRect
        /// How tall a capital letter is, in pixels: nil if the ink couldn't be made out.
        let tall: CGFloat?
        /// It was read from a row that its fractions and roots were laid out along.
        var isFlattened = false
    }

    /// Pieces of text on the same row, left to right, so a sum Vision split in two ("12 × 3"
    /// and "=") is read whole.
    struct Line: Sendable {
        var pieces: [Piece]
        var box: CGRect
    }

    /// The picture the text was read from, for looking at the ink around a piece of it.
    struct Page: Sendable {
        let ink: Ink
        /// Points for each pixel, and the margin round the picture in pixels.
        let scale: CGFloat
        let margin: CGFloat

        func inPicture(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX / scale + margin, y: rect.minY / scale + margin, width: rect.width / scale, height: rect.height / scale)
        }

        func inPoints(_ rect: CGRect) -> CGRect {
            CGRect(x: (rect.minX - margin) * scale, y: (rect.minY - margin) * scale, width: rect.width * scale, height: rect.height * scale)
        }

        /// Whether the text at `box` has a fraction written one number over another in it or
        /// beside it, or a root with a bar over what it's the root of: read as a plain line,
        /// it would be a different sum. `tall` is the height of its capitals, in pixels.
        func isPartOfFraction(_ box: CGRect, tall: CGFloat?) -> Bool {
            let inPixels = inPicture(box)
            let height = tall ?? inPixels.height * 0.7
            let area = inPixels.insetBy(dx: -height * 0.6, dy: -height * 1.4)
            if !ink.fractionBars(in: area, tall: height).isEmpty || !Flattener(ink: ink).structures(in: area, tall: height).isEmpty { return true }
            // The bar of a long fraction runs on past this part of its top or bottom.
            if ink.hasBarRunningOn(beside: inPixels, tall: height) { return true }
            // In small text the bar is too faint to stand out as ink of its own.
            return height < 18 && ink.hasFaintBar(under: inPixels, tall: height)
        }
    }

    struct RecognisedText: Sendable {
        var lines: [Line]
        /// Lines with stacked fractions put back together, if there are any.
        var stacked: [Layout.Item]
        var page: Page?
        var isStacked: Bool { !stacked.isEmpty }
    }

    static func recognize(_ image: CGImage, size: CGSize) throws -> RecognisedText {
        // A margin all round: Vision misreads text that runs up to the edge of the picture.
        // Now and then the margin makes it read a line upside down instead; then it's read
        // again without.
        let margin = 80
        if let padded = Ink.padded(image, by: margin), let text = try recognize(in: padded, margin: margin, of: image, size: size) {
            return text
        }
        return try recognize(in: image, margin: 0, of: image, size: size) ?? RecognisedText(lines: [], stacked: [], page: nil)
    }

    /// Reads `picture`, which is `image` with a margin round it. Nil if Vision read any of it
    /// upside down, unless there's no margin to blame.
    private static func recognize(in picture: CGImage, margin: Int, of image: CGImage, size: CGSize, depth: Int = 0,
                                  alsoLookAt areas: [(box: CGRect, tall: CGFloat)] = []) throws -> RecognisedText? {
        let offset = CGFloat(margin)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" numbers and symbols into words.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: picture, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        if margin > 0, observations.contains(where: { $0.topLeft.x > $0.topRight.x }) { return nil }
        /// Vision's boxes are 0...1 from the bottom-left of the picture it was given: here, in
        /// that picture's pixels from the top-left.
        func pixels(_ normalized: CGRect) -> CGRect {
            CGRect(x: normalized.minX * CGFloat(picture.width), y: (1 - normalized.maxY) * CGFloat(picture.height),
                   width: normalized.width * CGFloat(picture.width), height: normalized.height * CGFloat(picture.height))
        }
        /// …and in points from the top-left of the area that was read.
        let scale = size.width / CGFloat(image.width)
        func box(_ normalized: CGRect) -> CGRect {
            let inPixels = pixels(normalized)
            return CGRect(x: (inPixels.minX - offset) * scale, y: (inPixels.minY - offset) * scale,
                          width: inPixels.width * scale, height: inPixels.height * scale)
        }
        /// The words of a reading: their characters, counted from its start, and where they are.
        func words(of candidate: VNRecognizedText) -> [(text: String, range: Range<Int>, normalized: CGRect?)] {
            let string = candidate.string
            var found: [(String, Range<Int>, CGRect?)] = []
            var start = string.startIndex
            while start < string.endIndex {
                guard let wordStart = string[start...].firstIndex(where: { $0 != " " }) else { break }
                let wordEnd = string[wordStart...].firstIndex(of: " ") ?? string.endIndex
                let from = string.distance(from: string.startIndex, to: wordStart)
                let range = from..<(from + string.distance(from: wordStart, to: wordEnd))
                let place = (try? candidate.boundingBox(for: wordStart..<wordEnd))?.map { $0.boundingBox }
                found.append((String(string[wordStart..<wordEnd]), range, place))
                start = wordEnd
            }
            return found
        }
        let ink = Ink(picture)
        var found: [(readings: [LineMender.Reading], box: CGRect, pixels: CGRect)] = []
        for observation in observations where observation.topLeft.x <= observation.topRight.x {
            let candidates = observation.topCandidates(3)
            guard !candidates.isEmpty else { continue }
            let readings = candidates.map { candidate in
                LineMender.Reading(text: candidate.string, words: words(of: candidate).compactMap { word in
                    word.normalized.map { (word.range, pixels($0)) }
                })
            }
            found.append((readings, box(observation.boundingBox), pixels(observation.boundingBox)))
        }
        // A scrap of a word at the very edge of the area, the "bo" of a margin note's "box",
        // is a word the area cut through: there's no saying what it was, and read as letters
        // it would be taken for part of the maths beside it.
        if margin > 0, depth == 0, let ink {
            let left = offset, right = CGFloat(picture.width) - offset
            found.removeAll { item in
                guard let text = item.readings.first?.text.filter({ $0 != " " }), text.count <= 4,
                      text.contains(where: \.isLetter), !text.contains(where: \.isNumber) else { return false }
                let box = item.pixels
                func hasInk(from x: CGFloat) -> Bool {
                    !ink.patches(in: CGRect(x: x, y: box.minY, width: 3, height: box.height)).isEmpty
                }
                return (box.minX <= left + 6 && hasInk(from: left)) || (box.maxX >= right - 6 && hasInk(from: right - 3))
            }
        }
        // Vision reads a power as ordinary characters ("22026" for 2²⁰²⁶) or not at all, and
        // the bars of |x| as letters: the ink says what's really there.
        let mended: [(readings: [LineMender.Mended], tall: CGFloat?)]
        if let ink {
            mended = LineMender(ink: ink).mend(found.map { LineMender.Piece(box: $0.pixels, readings: $0.readings) })
        } else {
            mended = found.map { item in (item.readings.map { LineMender.unchanged($0, in: item.pixels) }, nil) }
        }
        func points(_ inPixels: CGRect) -> CGRect {
            CGRect(x: (inPixels.minX - offset) * scale, y: (inPixels.minY - offset) * scale, width: inPixels.width * scale, height: inPixels.height * scale)
        }
        var pieces: [Piece] = []
        var layoutWords: [Layout.Item] = []
        for (item, result) in zip(found, mended) {
            let words = result.readings.map { reading in
                reading.tokens.map { Word(range: $0.range, box: points($0.box), isChecked: $0.isChecked, isSuspect: $0.isSuspect,
                                          places: $0.places.map { $0.map(points) }, hasUnreadMark: $0.hasUnreadMark) }
            }
            pieces.append(Piece(readings: result.readings.map(\.text), words: words, box: item.box, tall: result.tall))
            // Each word on its own, for putting stacked fractions back together.
            if let best = result.readings.first {
                let characters = Array(best.text)
                for word in words[0] {
                    layoutWords.append(Layout.Item(text: String(characters[word.range]), box: word.box, isChecked: word.isChecked))
                }
            }
        }
        // Fractions and roots set out in two dimensions: laid out along a row and read again.
        if depth < 2, let ink {
            let flattened = try flatten(ink, near: zip(found, mended).map { ($0.pixels, $1.tall, $1.readings.first?.text ?? "") }
                                        + areas.map { ($0.box, $0.tall, "") }, depth: depth)
            if !flattened.isEmpty {
                var kept: [Piece] = []
                for (index, piece) in pieces.enumerated() {
                    let box = found[index].pixels
                    let covered = flattened.contains { $0.region.insetBy(dx: -2, dy: -2).intersection(box).width * $0.region.insetBy(dx: -2, dy: -2).intersection(box).height >= box.width * box.height * 0.5 }
                    guard !covered else { continue }
                    // A line Vision read as one piece can run on over a fraction, as nonsense
                    // ("Work out the value of (16) %"): its words there go, the rest stays.
                    let regions = flattened.map { points($0.region).insetBy(dx: -1, dy: -1) }
                    if let rest = without(wordsIn: regions, piece) { kept.append(rest) }
                }
                for row in flattened {
                    // A fraction that runs into the top or bottom edge of the area was cut
                    // through there: what's left of its top or bottom reads as something
                    // else ("120" for √20), and can't be trusted.
                    let isCut = margin > 0 && depth == 0 && (row.region.minY <= offset + 1 || row.region.maxY >= CGFloat(picture.height) - offset - 2)
                    let words = row.words.map { reading in
                        reading.map { Word(range: $0.range, box: points($0.box), isChecked: $0.isChecked, isSuspect: $0.isSuspect || isCut) }
                    }
                    kept.append(Piece(readings: row.readings, words: words, box: points(row.region), tall: row.tall, isFlattened: true))
                }
                pieces = kept
                layoutWords = []
            }
        }
        pieces = pieces.flatMap { separated($0, scale: scale) }
        let page = ink.map { Page(ink: $0, scale: scale, margin: offset) }
        // One thing over another is only a fraction if there's a bar between them.
        let stacked = Layout.linearize(layoutWords) { top, bottom in
            guard let page else { return true }
            let upper = page.inPicture(top), lower = page.inPicture(bottom)
            return page.ink.hasBar(between: upper, and: lower, length: max(upper.width, lower.width) * 0.9)
        }
        return RecognisedText(lines: unglued(rows(pieces, scale: scale)), stacked: stacked, page: page)
    }

    /// Question numbers that Vision ran into the maths after them, parted again. "4.48 − 19"
    /// could be the number 4.48, or question 4: it's question 4 if there's a question 3 or 5
    /// lined up with it.
    private static func unglued(_ lines: [Line]) -> [Line] {
        func leading(_ line: Line) -> Int? {
            guard let text = line.pieces.first?.readings.first,
                  let match = text.range(of: #"^\s*\(?\d{1,2}[.)]"#, options: .regularExpression) else { return nil }
            return Int(text[match].filter(\.isNumber))
        }
        /// A number that's plainly a question's: a space after it, or a letter or bracket,
        /// not more digits (which would make it a decimal).
        func isLabel(_ line: Line) -> Bool {
            line.pieces.first?.readings.first?.range(of: #"^\s*\(?\d{1,2}[.)](\s|[A-Za-z(√∫|])"#, options: .regularExpression) != nil
        }
        let numbers = lines.map(leading)
        var result = lines
        for (index, line) in lines.enumerated() {
            guard let number = numbers[index], number >= 1, let piece = line.pieces.first,
                  piece.readings[0].range(of: #"^\s*\d{1,2}\.\d"#, options: .regularExpression) != nil else { continue }
            let isNumbered = lines.indices.contains { other in
                other != index && isLabel(lines[other]) && numbers[other].map { abs($0 - number) == 1 } == true
                    && abs(lines[other].box.minX - line.box.minX) <= max(line.box.height, lines[other].box.height) * 0.6
            }
            guard isNumbered else { continue }
            var readings: [String] = []
            var words: [[Word]] = []
            for (variant, reading) in piece.readings.enumerated() {
                let characters = Array(reading)
                guard let dot = characters.firstIndex(of: "."), dot + 1 < characters.count, characters[dot + 1].isNumber,
                      characters[..<dot].allSatisfy({ $0.isNumber || $0 == " " }) else {
                    readings.append(reading)
                    words.append(piece.words[variant])
                    continue
                }
                readings.append(String(characters[...dot]) + " " + String(characters[(dot + 1)...]))
                var list: [Word] = []
                for word in piece.words[variant] {
                    if word.range.contains(dot), word.range.upperBound > dot + 1 {
                        // The word with the full stop in it becomes two.
                        let cut = dot + 1 - word.range.lowerBound
                        func part(_ range: Range<Int>, shift: Int) -> Word {
                            var half = word
                            half.range = (word.range.lowerBound + range.lowerBound + shift)..<(word.range.lowerBound + range.upperBound + shift)
                            let known = word.places.count == word.range.count ? Array(word.places[range]) : []
                            let ink = known.compactMap { $0 }.reduce(CGRect.null) { $0.union($1) }
                            half.places = known
                            half.box = ink.isNull ? CGRect(x: word.box.minX + word.box.width * CGFloat(range.lowerBound) / CGFloat(word.range.count), y: word.box.minY,
                                                           width: word.box.width * CGFloat(range.count) / CGFloat(word.range.count), height: word.box.height) : ink
                            return half
                        }
                        list.append(part(0..<cut, shift: 0))
                        list.append(part(cut..<word.range.count, shift: 1))
                    } else if word.range.lowerBound > dot {
                        var moved = word
                        moved.range = (word.range.lowerBound + 1)..<(word.range.upperBound + 1)
                        list.append(moved)
                    } else {
                        list.append(word)
                    }
                }
                words.append(list)
            }
            result[index].pieces[0] = Piece(readings: readings, words: words, box: piece.box, tall: piece.tall, isFlattened: piece.isFlattened)
        }
        return result
    }

    /// A piece without its words that are in any of `regions`, which something else was read
    /// from: unchanged if none are, nil if they all are.
    private static func without(wordsIn regions: [CGRect], _ piece: Piece) -> Piece? {
        func isInside(_ word: Word) -> Bool {
            regions.contains { $0.contains(CGPoint(x: word.box.midX, y: word.box.midY)) }
        }
        guard piece.words.contains(where: { $0.contains(where: isInside) }) else { return piece }
        var readings: [String] = []
        var words: [[Word]] = []
        for (reading, list) in zip(piece.readings, piece.words) {
            let characters = Array(reading)
            var text = ""
            var rest: [Word] = []
            for word in list where !isInside(word) && word.range.upperBound <= characters.count {
                if !text.isEmpty { text += " " }
                var moved = word
                moved.range = text.count..<(text.count + word.range.count)
                text += String(characters[word.range])
                rest.append(moved)
            }
            readings.append(text)
            words.append(rest)
        }
        guard let first = words.first, !first.isEmpty else { return nil }
        return Piece(readings: readings, words: words, box: first.map(\.box).reduce(CGRect.null) { $0.union($1) }, tall: piece.tall, isFlattened: piece.isFlattened)
    }

    /// A line with fractions or roots in it, read from the row they were laid out along:
    /// its readings and their words, with the words' places back in the picture.
    private struct FlatRow {
        var readings: [String]
        var words: [[Word]]
        var region: CGRect
        var tall: CGFloat
    }

    /// Finds the fractions and roots near pieces of text that could be maths, lays each line
    /// that has any out along a row of a sheet, and reads the sheet.
    private static func flatten(_ ink: Ink, near pieces: [(box: CGRect, tall: CGFloat?, text: String)], depth: Int) throws -> [FlatRow] {
        let flattener = Flattener(ink: ink)
        var structures: [(structure: Flattener.Structure, tall: CGFloat)] = []
        let measured = pieces.filter { $0.tall != nil }
        for piece in pieces {
            // Words alone have no fractions in them: only short pieces, and ones with numbers or signs.
            guard piece.text.count <= 8 || piece.text.contains(where: { $0.isNumber || "+-−=/×÷√".contains($0) }) else { continue }
            // Text whose size couldn't be measured (a fraction's line is one, its box taking
            // in the top and bottom) is taken to be the size of the nearest that could.
            let nearest = measured.min { a, b in
                hypot(a.box.midX - piece.box.midX, a.box.midY - piece.box.midY) < hypot(b.box.midX - piece.box.midX, b.box.midY - piece.box.midY)
            }
            // A line with a fraction in it measures too big, its top and bottom run together
            // into one tall shape: the size of the text beside it is tried as well.
            let other = measured.filter { $0.box != piece.box }.min { a, b in
                hypot(a.box.midX - piece.box.midX, a.box.midY - piece.box.midY) < hypot(b.box.midX - piece.box.midX, b.box.midY - piece.box.midY)
            }
            var sizes = [piece.tall ?? nearest?.tall ?? piece.box.height * 0.6]
            if let beside = other?.tall, abs(beside - sizes[0]) > sizes[0] * 0.15 { sizes.append(beside) }
            for tall in sizes where tall >= 8 {
                // Further to the right of a short piece: a fraction after a question's label
                // may not have been read at all.
                var area = piece.box.insetBy(dx: -tall, dy: -tall * 1.7)
                if piece.text.count <= 8 { area.size.width += tall * 8 }
                structures += flattener.structures(in: area, tall: tall).map { ($0, tall) }
            }
        }
        // A fraction that nothing near it was read from, its top and bottom single characters
        // that Vision passes over (the 2/5 among the choices of an exam question), is found
        // from its bar: the whole picture is looked over for plain ones, a band at a time,
        // at each size of text there is.
        let near = structures.map(\.structure.box)
        var sizes: [CGFloat] = []
        for tall in measured.compactMap(\.tall).sorted() where tall >= 8 && tall <= 80 {
            if let last = sizes.last, tall <= last * 1.15 { continue }
            sizes.append(tall)
        }
        if depth == 0, sizes.count <= 8 {
            let band: CGFloat = 900
            var top: CGFloat = 0
            while top < CGFloat(ink.height) {
                for tall in sizes {
                    let area = CGRect(x: 0, y: top - tall * 4, width: CGFloat(ink.width), height: band + tall * 8)
                    for bar in ink.fractionBars(in: area, tall: tall, plainOnly: true)
                    where !structures.contains(where: { $0.structure.box.insetBy(dx: -1, dy: -1).intersects(bar) }) {
                        for structure in flattener.structures(in: bar.insetBy(dx: -tall * 1.5, dy: -tall * 2.4), tall: tall) {
                            // Characters over it and under it, not the dots of a division sign.
                            guard case .fraction(let over, let under, _) = structure, min(over.height, under.height) >= tall * 0.45 else { continue }
                            structures.append((structure, tall))
                        }
                    }
                }
                top += band
            }
        }
        // A lone digit in a row of numbers, the 8 of "5  8  14  23", is passed over by Vision
        // like any single character on its own. Where two or more numbers stand level and
        // evenly spaced, ink of a digit's size at one of the places along that row that
        // nothing was read from is cut out and read too.
        var lone: [CGRect] = []
        var loneSizes: [CGFloat] = []
        if depth == 0 {
            /// The ink of each number in a stretch of the picture: digits with no more than a
            /// space's width between them are one number.
            func numbers(in box: CGRect, tall: CGFloat) -> [CGRect] {
                var found: [CGRect] = []
                for glyph in ink.glyphs(in: box).sorted(by: { $0.minX < $1.minX }) where glyph.height >= tall * 0.6 {
                    if let last = found.last, glyph.minX - last.maxX <= tall * 0.5 {
                        found[found.count - 1] = last.union(glyph)
                    } else {
                        found.append(glyph)
                    }
                }
                return found
            }
            // Every number that was read, by where its ink is: Vision's box for a short number
            // can be far too wide, and it may give two numbers of a row as one piece.
            var known: [(box: CGRect, tall: CGFloat)] = []
            for piece in pieces {
                guard let tall = piece.tall, piece.text.range(of: #"^\s*-?\d+(\.\d+)?(\s+-?\d+(\.\d+)?)*\s*$"#, options: .regularExpression) != nil else { continue }
                known += numbers(in: piece.box, tall: tall).map { ($0, tall) }
            }
            var done: [CGRect] = []
            for item in known {
                let tall = item.tall
                let level = known.filter { abs($0.box.midY - item.box.midY) <= tall * 0.5 }.sorted { $0.box.midX < $1.box.midX }
                guard level.count >= 2, !done.contains(where: { $0.contains(CGPoint(x: item.box.midX, y: item.box.midY)) }) else { continue }
                let step = zip(level, level.dropFirst()).map { $1.box.midX - $0.box.midX }.min() ?? 0
                guard step >= tall * 2 else { continue }
                let band = CGRect(x: level[0].box.minX - step * 3.5, y: item.box.midY - tall * 0.8,
                                  width: level[level.count - 1].box.maxX - level[0].box.minX + step * 7, height: tall * 1.6)
                done.append(band)
                var clusters: [CGRect] = []
                for glyph in ink.glyphs(in: band).sorted(by: { $0.minX < $1.minX })
                where glyph.height >= tall * 0.75 && glyph.height <= tall * 1.3 && glyph.width <= tall * 1.1
                    && !pieces.contains(where: { $0.box.insetBy(dx: -2, dy: -2).intersects(glyph) })
                    // (Not the top or bottom of a fraction that's been found: the 3 under a bar.)
                    && !structures.contains(where: { $0.structure.box.insetBy(dx: -2, dy: -2).intersects(glyph) }) {
                    if let last = clusters.last, glyph.minX - last.maxX <= tall * 0.5 {
                        clusters[clusters.count - 1] = last.union(glyph)
                    } else {
                        clusters.append(glyph)
                    }
                }
                for cluster in clusters where cluster.width <= tall * 3 {
                    // At one of the places along the row: a whole number of steps from a number that was read.
                    let isInStep = level.contains { known in
                        let steps = (cluster.midX - known.box.midX) / step
                        return abs(steps.rounded()) >= 1 && abs(steps.rounded()) <= 4 && abs(steps - steps.rounded()) <= 0.2
                    }
                    if isInStep, lone.count < 12 {
                        lone.append(cluster)
                        loneSizes.append(tall)
                    }
                }
            }
        }
        guard !structures.isEmpty || !lone.isEmpty, structures.count <= 200 else { return [] }
        var expressions = flattener.expressions(from: structures)
        for (box, tall) in zip(lone, loneSizes) {
            expressions.append(Flattener.Expression(pieces: [(.part(box.insetBy(dx: -1, dy: -1)), box, nil)], region: box, tall: tall, baseline: box.maxY))
        }
        guard let (sheet, rows, items) = flattener.sheet(of: expressions),
              let text = try recognize(in: sheet, margin: 0, of: sheet, size: CGSize(width: sheet.width, height: sheet.height), depth: 2) else { return [] }
        let read = text.lines.flatMap(\.pieces)
        var result: [FlatRow] = []
        for (expression, list) in zip(expressions, items) {
            // The line put together again: each row as it was read, the signs between them
            // as they're known to be.
            var out: [(character: Character, source: CGRect, isChecked: Bool, isSuspect: Bool)] = []
            // Where a mixed number's whole part ends, and which item is the bottom of its fraction.
            var mixed: (at: Int, bottom: Int)?
            for (position, item) in list.enumerated() {
                switch item {
                case .sign(let sign, let place, let spaceBefore):
                    if spaceBefore, !out.isEmpty { out.append((" ", .null, true, false)) }
                    for character in sign { out.append((character, place, true, character == LineMender.unreadable)) }
                case .ink(let number, let across, let place, let spaceBefore):
                    if spaceBefore, !out.isEmpty { out.append((" ", .null, true, false)) }
                    let row = rows[number]
                    let pieces = read.filter { $0.box.midY >= row.top && $0.box.midY < row.bottom }.sorted { $0.box.minX < $1.box.minX }
                    // Every character read in the row, and how far along it is.
                    var line: [(character: Character, from: CGFloat, to: CGFloat, isChecked: Bool, isSuspect: Bool)] = []
                    for piece in pieces {
                        let characters = Array(piece.readings[0])
                        for word in piece.words[0] {
                            if !line.isEmpty { line.append((" ", word.box.minX, word.box.minX, true, false)) }
                            let each = word.box.width / CGFloat(max(word.range.count, 1))
                            for (offset, index) in word.range.enumerated() {
                                let known = word.places.count == word.range.count ? word.places[offset] : nil
                                let from = known?.minX ?? word.box.minX + each * CGFloat(offset)
                                line.append((characters[index], from, known?.maxX ?? from + each, word.isChecked, word.isSuspect))
                            }
                        }
                    }
                    // Without the words that lead in to the ink: "N =" by what it says, since
                    // Vision runs it into what follows; "Work out" by where it is.
                    let whole = String(line.map(\.character))
                    if !row.hasWords, let lead = whole.range(of: #"^\s*[NnMH]\s*[=-]\s?"#, options: .regularExpression) {
                        line.removeFirst(whole.distance(from: whole.startIndex, to: lead.upperBound))
                    } else {
                        line.removeAll { ($0.from + $0.to) / 2 < row.start - 4 }
                    }
                    while line.first?.character == " " { line.removeFirst() }
                    // A letter on its own, the x under the bar of 1/x, is drawn as big as a
                    // capital to be read, and read as one. Its ink says which it was: a small
                    // letter is well short of the line's capitals.
                    if !across, line.count == 1, line[0].character.isLetter, line[0].character.isUppercase,
                       let highest = ink.glyphs(in: row.source).map(\.height).max(), highest <= expression.tall * 0.8 {
                        if "COSUVWXZ".contains(line[0].character) {
                            line[0].character = Character(line[0].character.lowercased())
                        } else if let digit = Parser.lookalikes[line[0].character], digit.isNumber {
                            // (A letter of another alphabet that's the shape of a digit, З: the
                            // 3 of a fraction set small.)
                            line[0].character = digit
                        } else {
                            // Any other capital has no small letter of its shape: the x under
                            // a bar read as Y is a misreading, and there's no saying of what.
                            line[0].character = LineMender.unreadable
                            line[0].isSuspect = true
                        }
                    }
                    // Nothing read where there's ink: whatever it is, the line can't be trusted without it.
                    guard line.contains(where: { $0.character != " " }) else {
                        out.append((LineMender.unreadable, place, false, true))
                        continue
                    }
                    // A whole number straight before a fraction of two plain numbers, 1⅔, is a
                    // mixed number: a space keeps them apart (run together it's 12 over 3).
                    let isNumber = line.allSatisfy { $0.character.isNumber }
                    if !across, isNumber, position > 0, position + 2 < list.count, out.last?.character.isNumber == true,
                       case .ink(_, true, _, _) = list[position - 1], case .sign(let sign, _, _) = list[position + 1], sign == "/",
                       case .ink(_, false, _, _) = list[position + 2] {
                        mixed = (out.count, position + 2)
                    }
                    if let whole = mixed, whole.bottom == position {
                        if isNumber { out.insert((" ", .null, true, false), at: whole.at) }
                        mixed = nil
                    }
                    for item in line {
                        var source = place
                        if item.character == " " {
                            source = .null
                        } else if across {
                            // Along a stretch of the line, each character is where it was.
                            source = CGRect(x: row.source.minX + (item.from - row.start) / row.scale, y: expression.region.minY,
                                            width: (item.to - item.from) / row.scale, height: expression.region.height)
                        }
                        out.append((item.character, source, item.isChecked, item.isSuspect))
                    }
                }
            }
            // Its words, each with its place in the picture.
            var words: [Word] = []
            var index = 0
            while index < out.count {
                guard out[index].character != " " else { index += 1; continue }
                var end = index
                while end < out.count, out[end].character != " " { end += 1 }
                let part = out[index..<end]
                let box = part.map(\.source).reduce(CGRect.null) { $0.union($1) }
                words.append(Word(range: index..<end, box: box.isNull ? expression.region : box, isChecked: part.allSatisfy(\.isChecked),
                                  isSuspect: part.contains(where: \.isSuspect), places: part.map { $0.source.isNull ? nil : $0.source }))
                index = end
            }
            let reading = String(out.map(\.character))
            // Found from a bar alone, it has to read as maths: a rule between two labels
            // reads as words over words, and those are left as they were.
            if !near.contains(where: { $0.intersects(expression.region) }),
               reading.contains(LineMender.unreadable) || !readsAsMaths(reading) { continue }
            // …and a lone digit has to read as a number.
            if lone.contains(expression.region), reading.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) == nil { continue }
            result.append(FlatRow(readings: [reading], words: [words], region: expression.region, tall: expression.tall))
        }
        return result
    }

    /// Whether a row reads as maths rather than words: it has a number in it, or nothing
    /// longer than the name of a function.
    private static func readsAsMaths(_ text: String) -> Bool {
        if text.contains(where: \.isNumber) { return true }
        return text.split(whereSeparator: { !$0.isLetter }).allSatisfy { $0.count <= 3 }
    }

    /// How wide a gap between words has to be, in points, to part two columns or two problems
    /// rather than two words: much wider than a capital is tall.
    private static func wideGap(in piece: Piece, scale: CGFloat) -> CGFloat {
        1.7 * (piece.tall.map { $0 * scale } ?? piece.box.height * 0.6)
    }

    /// A piece cut where there are wide gaps in it: Vision reads across narrow columns, and
    /// what's in one has nothing to do with what's in the next.
    private static func separated(_ piece: Piece, scale: CGFloat) -> [Piece] {
        guard let first = piece.words.first, first.count >= 2 else { return [piece] }
        let gaps = zip(first, first.dropFirst()).map { $1.box.minX - $0.box.maxX }
        let usual = gaps.count >= 3 ? gaps.sorted()[gaps.count / 2] : 0
        let limit = max(wideGap(in: piece, scale: scale), 2.2 * usual)
        let cuts = zip(first, first.dropFirst()).compactMap { $1.box.minX - $0.box.maxX > limit ? ($0.box.maxX + $1.box.minX) / 2 : nil }
        guard !cuts.isEmpty else { return [piece] }
        let edges = [-CGFloat.infinity] + cuts + [CGFloat.infinity]
        var parts: [Piece] = []
        for (lower, upper) in zip(edges, edges.dropFirst()) {
            var readings: [String] = []
            var words: [[Word]] = []
            var box = CGRect.null
            for (number, reading) in piece.readings.enumerated() {
                let characters = Array(reading)
                let inside = piece.words[number].filter { $0.box.midX > lower && $0.box.midX <= upper }
                guard let start = inside.map(\.range.lowerBound).min(), let end = inside.map(\.range.upperBound).max() else { continue }
                let text = String(characters[start..<end])
                guard !readings.contains(text) else { continue }
                readings.append(text)
                words.append(inside.map { word in
                    var moved = word
                    moved.range = (word.range.lowerBound - start)..<(word.range.upperBound - start)
                    return moved
                })
                if box.isNull { box = inside.reduce(CGRect.null) { $0.union($1.box) } }
            }
            guard !readings.isEmpty, !box.isNull else { continue }
            parts.append(Piece(readings: readings, words: words,
                               box: CGRect(x: box.minX, y: piece.box.minY, width: box.width, height: piece.box.height), tall: piece.tall,
                               isFlattened: piece.isFlattened))
        }
        return parts.isEmpty ? [piece] : parts
    }

    /// Pieces on the same row and near each other, left to right, as lines. Pieces far apart
    /// are in different columns, and have nothing to do with each other.
    static func rows(_ pieces: [Piece], scale: CGFloat) -> [Line] {
        var lines: [Line] = []
        for piece in pieces.sorted(by: { $0.box.minX < $1.box.minX }) {
            let startsQuestion = piece.readings[0].range(of: #"^\s*(\(([a-zA-Z]|[ivx]{2,4}|\d{1,2})\)|\d{1,2}[.)]\s|Q\d)"#, options: .regularExpression) != nil
            if !startsQuestion, let index = lines.firstIndex(where: { line in
                guard let last = line.pieces.last else { return false }
                return sameRow(last.box, piece.box) && piece.box.minX - line.box.maxX <= max(wideGap(in: last, scale: scale), wideGap(in: piece, scale: scale))
            }) {
                lines[index].pieces.append(piece)
                lines[index].box = lines[index].box.union(piece.box)
            } else {
                lines.append(Line(pieces: [piece], box: piece.box))
            }
        }
        return lines
    }

    /// Two boxes are on the same row when they overlap by most of the smaller one's height.
    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.6 * min(a.height, b.height)
    }

    // MARK: Choosing the problem

    struct Candidate {
        var text: String
        var distance: CGFloat
        var box: CGRect
        var isEquationOrCommand: Bool
        var fromStack = false
        /// Whether the ink bears out every word of it: nothing dropped, no power unread.
        var isChecked = true
        /// How tall its capitals are, in pixels, if the ink could be made out.
        var tall: CGFloat?
        /// It's all there is on its line, apart from a question number.
        var isAlone = false
        /// There's ink in it that no character accounts for: something's been missed.
        var isSuspect = false
        /// The whole line it's in, for reading it again where it stands, and what it says.
        var line = CGRect.null
        var context = ""
        /// The word straight after it on its line, if there is one.
        var following = ""
        /// There's a small raised mark in it that couldn't be read: a power, perhaps.
        var hasUnreadMark = false
    }

    /// A word in a line of text put together from several pieces.
    private struct Span {
        var range: Range<Int>
        var box: CGRect
        var isChecked: Bool
        var tall: CGFloat?
        var places: [CGRect?] = []
        var isSuspect = false
        var isFlattened = false
        var hasUnreadMark = false
    }

    /// Every separate problem in the area, in reading order. Each line is tried with Vision's
    /// best reading of every piece, then its second best, and so on; where readings overlap, the
    /// longest wins. Stacked fractions put back together come first. Equations that share the same
    /// unknowns, as many equations as unknowns, are one problem: simultaneous equations.
    static func problems(in text: RecognisedText, to focus: CGPoint?) -> [Candidate] {
        var all: [(candidate: Candidate, variant: Int)] = []
        let scale = text.page?.scale ?? 0.5
        func add(_ found: String, _ range: Range<Int>, _ spans: [Span], variant: Int, fromStack: Bool) {
            guard let place = place(of: range, in: spans) else { return }
            let isEquationOrCommand = found.contains("=") || found.first?.isLetter == true || found.contains(" mod ")
            all.append((Candidate(text: found, distance: focus.map { distanceFrom($0, to: place.box) } ?? 0, box: place.box,
                                  isEquationOrCommand: isEquationOrCommand, fromStack: fromStack || place.isFlattened, isChecked: place.isChecked,
                                  tall: place.tall, isSuspect: place.isSuspect, hasUnreadMark: place.hasUnreadMark), variant))
        }
        for item in text.stacked {
            for (found, range) in ProblemFinder.problems(in: item.text) {
                add(found, range, [Span(range: 0..<item.text.count, box: item.box, isChecked: item.isChecked, tall: nil)], variant: 0, fromStack: true)
            }
        }
        /// Each line as it was first read, for joining lines that run on.
        var firstReadings: [(joined: String, spans: [Span], whole: CGRect)] = []
        for line in text.lines {
            let variants = line.pieces.map(\.readings.count).max() ?? 0
            for variant in 0..<variants {
                var joined = ""
                var length = 0
                var spans: [Span] = []
                var previous: CGRect?
                // The words of the line, and the gaps between them. A gap much wider than a
                // capital is tall, and than the line's usual gap, separates problems (or a
                // question number in a column of its own); anything less is a space.
                var entries: [(piece: Piece, characters: [Character], word: Word)] = []
                for piece in line.pieces {
                    let number = min(variant, piece.readings.count - 1)
                    let characters = Array(piece.readings[number])
                    var words = piece.words[number]
                    if words.isEmpty, !characters.isEmpty { words = [Word(range: 0..<characters.count, box: piece.box, isChecked: false)] }
                    entries += words.map { (piece, characters, $0) }
                }
                let gaps = zip(entries, entries.dropFirst()).map { $1.word.box.minX - $0.word.box.maxX }.sorted()
                let usual = gaps.count >= 3 ? gaps[gaps.count / 2] : 0
                // The gaps after the first word: a question number stands further off than
                // the words of its question do from each other. In a fixed-width font every
                // space is wide, and "9 −4 +2" is all one sum.
                let later = zip(entries.dropFirst(), entries.dropFirst(2)).map { $1.word.box.minX - $0.word.box.maxX }.sorted()
                let usualLater = later.isEmpty ? 0 : later[later.count / 2]
                do {
                    for (number, (piece, characters, word)) in entries.enumerated() {
                        if let previous {
                            let gap = word.box.minX - previous.maxX
                            var isWide = gap > max(wideGap(in: piece, scale: scale), 2.2 * usual)
                            // A number on its own before everything else, with more than a
                            // space after it, numbers the question: a table has it in a column.
                            // What follows a question number is a question, which doesn't start
                            // with a sign that needs something before it: "50 + 10%" in a
                            // fixed-width font has gaps as wide.
                            if number == 1, String(entries[0].characters[entries[0].word.range]).range(of: #"^\d{1,2}[.)]?$"#, options: .regularExpression) != nil,
                               !["+", "×", "÷", "*", "/", "="].contains(String(characters[word.range])),
                               gap > max(wideGap(in: piece, scale: scale) * 0.6, 1.6 * usual, 1.6 * usualLater) { isWide = true }
                            let separator = isWide ? " ¦ " : " "
                            joined += separator
                            length += separator.count
                        }
                        joined += String(characters[word.range])
                        spans.append(Span(range: length..<(length + word.range.count), box: word.box, isChecked: word.isChecked, tall: piece.tall,
                                          places: word.places, isSuspect: word.isSuspect, isFlattened: piece.isFlattened,
                                          hasUnreadMark: word.hasUnreadMark))
                        length += word.range.count
                        previous = word.box
                    }
                }
                let slips = ProblemFinder.fixSlips(joined)
                let whole = spans.reduce(CGRect.null) { $0.union($1.box) }
                if variant == 0 { firstReadings.append((joined, spans, whole)) }
                for (found, range) in ProblemFinder.problems(in: joined) {
                    let count = all.count
                    add(found, range, spans, variant: variant, fromStack: false)
                    if all.count > count {
                        all[all.count - 1].candidate.line = whole
                        all[all.count - 1].candidate.context = joined
                        let rest = slips[min(range.upperBound, slips.count)...].drop { $0 == " " }
                        all[all.count - 1].candidate.following = String(rest.prefix { $0.isLetter })
                    }
                    // Nothing else on the line but question numbers and full stops.
                    let rest = slips.indices.filter { !range.contains($0) && !" ¦.,:;".contains(slips[$0]) }
                    let bar = slips.firstIndex(of: "¦")
                    let isOnlyNumber = rest.count <= 2 && rest.allSatisfy { index in slips[index].isNumber && bar.map { index < $0 } == true }
                    if rest.isEmpty || isOnlyNumber, !all.isEmpty { all[all.count - 1].candidate.isAlone = true }
                }
            }
        }
        // A line that ends on a sign, or on "of", runs on to the next: "Simplify 3m +" /
        // "4n − m + 2n". The two are one problem, and neither is one on its own.
        for upper in firstReadings {
            let end = upper.joined.trimmingCharacters(in: .whitespaces)
            guard let last = end.last, "+-−×÷*/(,".contains(last) || end.lowercased().hasSuffix(" of") else { continue }
            let below = firstReadings.filter { lower in
                // Below it, and starting no further left than a question's label would.
                lower.whole.minY > upper.whole.midY && lower.whole.minY - upper.whole.maxY < upper.whole.height * 1.2
                    && lower.whole.minX < upper.whole.maxX && lower.whole.minX > upper.whole.minX - upper.whole.height * 4
                    && lower.whole.maxX > upper.whole.minX
            }
            guard let lower = below.min(by: { $0.whole.minY < $1.whole.minY }) else { continue }
            // Whatever was found in either line on its own, in any of its readings.
            let both = upper.whole.union(lower.whole).insetBy(dx: -2, dy: -2)
            all.removeAll { both.contains($0.candidate.box) }
            let joined = upper.joined + " " + lower.joined
            let offset = upper.joined.count + 1
            let spans = upper.spans + lower.spans.map { span -> Span in
                var moved = span
                moved.range = (span.range.lowerBound + offset)..<(span.range.upperBound + offset)
                return moved
            }
            let slips = ProblemFinder.fixSlips(joined)
            for (found, range) in ProblemFinder.problems(in: joined) {
                let count = all.count
                add(found, range, spans, variant: 0, fromStack: false)
                guard all.count > count else { continue }
                all[all.count - 1].candidate.line = upper.whole.union(lower.whole)
                all[all.count - 1].candidate.context = joined
                let rest = slips.indices.filter { !range.contains($0) && !" ¦.,:;".contains(slips[$0]) }
                all[all.count - 1].candidate.isAlone = rest.isEmpty
            }
        }
        // A question in words that runs over two lines: "… the remainder when 2^10 is divided" / "by 7?"
        let rows = text.lines.sorted { $0.box.minY < $1.box.minY }
        func reading(_ line: Line) -> String { line.pieces.map { $0.readings[0] }.joined(separator: " ") }
        for (upper, lower) in zip(rows, rows.dropFirst()) where lower.box.minY - upper.box.maxY < upper.box.height
            && lower.box.minX < upper.box.maxX && upper.box.minX < lower.box.maxX {
            let first = String(ProblemFinder.fixSlips(reading(upper))), second = String(ProblemFinder.fixSlips(reading(lower)))
            guard ProblemFinder.sentenceProblem(in: first) == nil, ProblemFinder.sentenceProblem(in: second) == nil,
                  let sentence = ProblemFinder.sentenceProblem(in: first + " " + second) else { continue }
            let box = upper.box.union(lower.box)
            all.append((Candidate(text: sentence.text, distance: focus.map { distanceFrom($0, to: box) } ?? 0, box: box, isEquationOrCommand: true,
                                  isChecked: isSound(upper) && isSound(lower), tall: [upper, lower].flatMap(\.pieces).compactMap(\.tall).min()), 0))
        }
        // One reading per place: stacked first, then what the ink bears out, then the longest,
        // then Vision's first choice, then the nearest.
        all.sort { a, b in
            if a.candidate.fromStack != b.candidate.fromStack { return a.candidate.fromStack }
            if a.candidate.isChecked != b.candidate.isChecked { return a.candidate.isChecked }
            if a.candidate.text.count != b.candidate.text.count { return a.candidate.text.count > b.candidate.text.count }
            if a.variant != b.variant { return a.variant < b.variant }
            return a.candidate.distance < b.candidate.distance
        }
        var accepted: [Candidate] = []
        for (candidate, _) in all {
            let key = candidate.text.filter { !$0.isWhitespace }
            guard !accepted.contains(where: { overlaps($0.box, candidate.box) || $0.text.filter { !$0.isWhitespace } == key && $0.box.intersects(candidate.box) })
            else { continue }
            accepted.append(candidate)
        }
        guard let nearest = accepted.min(by: { a, b in
            abs(a.distance - b.distance) <= 4 ? a.text.count > b.text.count : a.distance < b.distance
        }) else { return [] }
        // Besides the nearest, keep only what's clearly maths: an equation, letters, an
        // instruction, or a sum with two operations, so a date or page number isn't a problem.
        // With no pointer, nothing is nearest.
        accepted = accepted.filter {
            (focus != nil && $0.text == nearest.text) || isSubstantial($0.text) || ($0.isAlone && $0.text.contains("−")) || isTakingAway($0)
        }
        accepted = groupSimultaneous(accepted, anywhere: focus != nil)
        // Reading order: top to bottom, then left to right.
        return accepted.sorted { a, b in
            abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5 ? a.box.minX < b.box.minX : a.box.minY < b.box.minY
        }
    }

    /// Where a run of characters is: the ink of the words it takes in. Part of a word is taken
    /// to be that part of its width.
    private static func place(of range: Range<Int>, in spans: [Span]) -> (box: CGRect, isChecked: Bool, tall: CGFloat?, isSuspect: Bool, isFlattened: Bool, hasUnreadMark: Bool)? {
        var box = CGRect.null
        var isChecked = true
        var isSuspect = false
        var isFlattened = false
        var hasUnreadMark = false
        var tall: CGFloat?
        var hasTall = true
        for span in spans where span.range.overlaps(range) {
            let count = max(span.range.count, 1)
            let from = max(range.lowerBound, span.range.lowerBound) - span.range.lowerBound
            let to = min(range.upperBound, span.range.upperBound) - span.range.lowerBound
            // Part of a word: the ink of just those characters, if it's known.
            let exact = from == 0 && to == count ? span.box
                : (span.places.count == count ? span.places[from..<to].compactMap { $0 }.reduce(CGRect.null) { $0.union($1) } : .null)
            box = box.union(exact.isNull ? CGRect(x: span.box.minX + span.box.width * CGFloat(from) / CGFloat(count), y: span.box.minY,
                                                  width: span.box.width * CGFloat(to - from) / CGFloat(count), height: span.box.height) : exact)
            isChecked = isChecked && span.isChecked
            isSuspect = isSuspect || span.isSuspect
            isFlattened = isFlattened || span.isFlattened
            hasUnreadMark = hasUnreadMark || span.hasUnreadMark
            if let height = span.tall { tall = min(tall ?? height, height) } else { hasTall = false }
        }
        guard !box.isNull else { return nil }
        return (box, isChecked, hasTall ? tall : nil, isSuspect, isFlattened, hasUnreadMark)
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect, by share: CGFloat = 0.3) -> Bool {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 && intersection.width * intersection.height > share * smaller
    }

    private static func isSubstantial(_ text: String) -> Bool {
        if text.contains("=") || text.contains(where: \.isLetter) { return true }
        // A − or / alone could be a date or a range; the other signs couldn't.
        if text.contains(where: { "+×÷*^√%".contains($0) }) { return true }
        let operations = text.filter { "-−/".contains($0) }.count
        return operations >= 2
    }

    /// One number taken from a bigger one in the middle of a sentence, "718 − 114", with room
    /// round the minus sign. A range runs the other way, low to high (pages 12 – 18); two
    /// years are a span of time; and a score has a name straight after it (3 – 1 United).
    private static func isTakingAway(_ candidate: Candidate) -> Bool {
        let parts = candidate.text.split(separator: "−", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        }
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber || $0 == "." } }),
              let first = Double(parts[0]), let second = Double(parts[1]), first > second else { return false }
        let years = 1000.0...2100.0
        if years.contains(first), years.contains(second), parts.allSatisfy({ !$0.contains(".") }) { return false }
        // A number written with a nought in front is part of a phone number or a code.
        if parts.contains(where: { $0.count > 1 && $0.hasPrefix("0") && !$0.hasPrefix("0.") }) { return false }
        // The word before says when it's a time, a range or a score: "open 9 – 5".
        if let place = candidate.context.range(of: candidate.text) {
            let before = candidate.context[..<place.lowerBound].split(separator: " ").last.map { $0.lowercased().filter(\.isLetter) } ?? ""
            if ["from", "between", "open", "opens", "hours", "pages", "ages", "aged", "won", "lost", "drew", "beat", "score"].contains(before) { return false }
        }
        return candidate.following.first?.isUppercase != true
    }

    /// Equations in the same two or more unknowns, as many as there are unknowns, one under
    /// another or side by side: solved together. In a small area that was pointed at they
    /// needn't be neighbours, as long as there are just the right number.
    private static func groupSimultaneous(_ candidates: [Candidate], anywhere: Bool) -> [Candidate] {
        func unknowns(_ text: String) -> Set<String>? {
            let sides = text.split(separator: "=", omittingEmptySubsequences: false)
            guard sides.count == 2, let left = Parser.expression(String(sides[0])),
                  let right = Parser.expression(String(sides[1])) else { return nil }
            let symbols = left.symbols.union(right.symbols)
            return symbols.count >= 2 ? symbols : nil
        }
        func follows(_ next: CGRect, _ last: CGRect) -> Bool {
            let height = max(next.height, last.height)
            let below = next.minY - last.maxY
            if below > -0.4 * height {
                return below < 1.6 * height && next.minX < last.maxX + height && last.minX < next.maxX + height
            }
            // On the same row: side by side.
            return abs(next.midY - last.midY) < 0.5 * height && next.minX - last.maxX < 8 * height && next.minX > last.minX
        }
        let sets = candidates.map { unknowns($0.text) }
        let order = candidates.indices.filter { sets[$0] != nil }.sorted { a, b in
            abs(candidates[a].box.midY - candidates[b].box.midY) < 0.5 * min(candidates[a].box.height, candidates[b].box.height)
                ? candidates[a].box.minX < candidates[b].box.minX : candidates[a].box.minY < candidates[b].box.minY
        }
        // Runs of neighbours in the same unknowns.
        var chains: [[Int]] = []
        for index in order {
            if let chain = chains.firstIndex(where: { sets[$0.last!] == sets[index] && follows(candidates[index].box, candidates[$0.last!].box) }) {
                chains[chain].append(index)
            } else {
                chains.append([index])
            }
        }
        var groups: [[Int]] = []
        for chain in chains {
            let size = sets[chain[0]]!.count
            guard chain.count >= size, chain.count % size == 0 else { continue }
            for start in stride(from: 0, to: chain.count, by: size) { groups.append(Array(chain[start..<(start + size)])) }
        }
        if groups.isEmpty, anywhere {
            var bySet: [Set<String>: [Int]] = [:]
            for index in order { bySet[sets[index]!, default: []].append(index) }
            groups = bySet.filter { $0.value.count == $0.key.count }.map(\.value)
        }
        var grouped = Set<Int>()
        var result: [Candidate] = []
        for members in groups {
            var combined = candidates[members[0]]
            combined.text = members.map { candidates[$0].text }.joined(separator: "; ")
            combined.box = members.dropFirst().reduce(combined.box) { $0.union(candidates[$1].box) }
            combined.distance = members.map { candidates[$0].distance }.min() ?? combined.distance
            combined.isChecked = members.allSatisfy { candidates[$0].isChecked }
            combined.isSuspect = members.contains { candidates[$0].isSuspect }
            combined.hasUnreadMark = members.contains { candidates[$0].hasUnreadMark }
            combined.line = members.reduce(CGRect.null) { $0.union(candidates[$1].line.isNull ? candidates[$1].box : candidates[$1].line) }
            combined.tall = members.compactMap { candidates[$0].tall }.min()
            result.append(combined)
            grouped.formUnion(members)
        }
        for (index, candidate) in candidates.enumerated() where !grouped.contains(index) {
            result.append(candidate)
        }
        return result
    }

    /// The sentences around `focus`, if it's pointing at a word problem rather than at maths.
    static func proseNear(_ focus: CGPoint, in text: RecognisedText) -> String? {
        let lines = text.lines.sorted { $0.box.minY < $1.box.minY }
        guard let nearest = lines.min(by: { distanceFrom(focus, to: $0.box) < distanceFrom(focus, to: $1.box) }) else { return nil }
        func words(_ line: Line) -> Int {
            line.pieces.map { $0.readings[0] }.joined(separator: " ").split(separator: " ").filter { $0.filter(\.isLetter).count >= 2 }.count
        }
        guard words(nearest) >= 4 else { return nil }
        // The paragraph: neighbouring lines that are prose too.
        let paragraph = lines.filter { words($0) >= 3 }.map { $0.pieces.map { $0.readings[0] }.joined(separator: " ") }.joined(separator: " ")
        guard paragraph.contains(where: \.isNumber) else { return nil }
        return paragraph
    }

    private static func distanceFrom(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
