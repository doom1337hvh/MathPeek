import AppKit
import ScreenCaptureKit
import Vision

/// What MathPeek found in the area it read.
enum Reading: Sendable {
    /// Every separate problem found, in reading order, and which is nearest the pointer.
    case solved([Solution], primary: Int)
    /// It found maths, but couldn't work it out.
    case unsolved(String)
    case noMaths
    case failed(String)
}

/// How to read and work things out.
struct ReadOptions: Sendable {
    var angles: AngleUnit
    /// Ask Apple Intelligence about maths text recognition can't read, and word problems.
    var useModel: Bool
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

    static func read(_ area: ScreenArea, _ options: ReadOptions) async -> Reading {
        let image: CGImage
        do {
            do {
                image = try await capture(area, with: try await shared.filter(for: area.displayID, fresh: false))
            } catch {
                // The displays may have changed since the filters were made.
                image = try await capture(area, with: try await shared.filter(for: area.displayID, fresh: true))
            }
        } catch {
            return .failed("Couldn't read the screen: \(error.localizedDescription)")
        }
        let text: RecognisedText
        do {
            text = try recognize(image, size: area.rect.size)
        } catch {
            return .failed("Couldn't recognise the text: \(error.localizedDescription)")
        }
        return await solve(text, image: image, focus: area.focus, options)
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
        func solved(_ maths: String) -> Solution? {
            guard let problem = Parser.problem(maths), let solution = Engine.solve(problem, angles: options.angles),
                  !solution.answers.isEmpty || solution.note != nil else { return nil }
            return solution
        }
        // A word problem: the model writes it as maths.
        if modelReady, let prose, nearest.map({ !$0.isEquationOrCommand }) ?? true,
           let (maths, meaning) = await Tutor.translate(prose), var solution = solved(maths) {
            solution.steps.insert(Step("Write it as maths", meaning.map { "Where \($0)." } ?? "Choose a letter for each unknown."), at: 0)
            solution.source = "Apple Intelligence turned the words into maths: \(maths)"
            return .solved([solution], primary: 0)
        }
        // Stacked fractions, or nothing text recognition could make sense of: the model reads the picture.
        if modelReady, text.isStacked || found.isEmpty, let image, let maths = await Tutor.transcribe(image),
           var solution = solved(maths) {
            solution.source = "Apple Intelligence read it as: \(maths)"
            return .solved([solution], primary: 0)
        }
        var solutions: [Solution] = []
        var primary = 0
        for candidate in found {
            guard let solution = solved(candidate.text) else { continue }
            if candidate.text == nearest?.text { primary = solutions.count }
            solutions.append(solution)
        }
        if !solutions.isEmpty { return .solved(solutions, primary: primary) }
        if let nearest {
            if modelReady, !text.isStacked, let image, let maths = await Tutor.transcribe(image), var solution = solved(maths) {
                solution.source = "Apple Intelligence read it as: \(maths)"
                return .solved([solution], primary: 0)
            }
            return .unsolved(nearest.text)
        }
        return .noMaths
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

    /// One piece of text Vision found, with its best readings, and where it is in points from
    /// the top-left of the area.
    struct Piece: Sendable {
        let readings: [String]
        let box: CGRect
    }

    /// Pieces of text on the same row, left to right, so a sum Vision split in two ("12 × 3"
    /// and "=") is read whole.
    struct Line: Sendable {
        var pieces: [Piece]
        var box: CGRect
    }

    struct RecognisedText: Sendable {
        var lines: [Line]
        /// Lines with stacked fractions put back together, if there are any.
        var stacked: [Layout.Item]
        var isStacked: Bool { !stacked.isEmpty }
    }

    static func recognize(_ image: CGImage, size: CGSize) throws -> RecognisedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" numbers and symbols into words.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        func box(_ normalized: CGRect) -> CGRect {
            // Vision's boxes are 0...1 from the bottom-left.
            CGRect(x: normalized.minX * size.width, y: (1 - normalized.maxY) * size.height,
                   width: normalized.width * size.width, height: normalized.height * size.height)
        }
        var pieces: [Piece] = []
        var words: [Layout.Item] = []
        for observation in request.results ?? [] {
            let candidates = observation.topCandidates(3)
            guard let best = candidates.first else { continue }
            pieces.append(Piece(readings: candidates.map(\.string), box: box(observation.boundingBox)))
            // Each word on its own, for putting stacked fractions back together.
            let string = best.string
            var start = string.startIndex
            while start < string.endIndex {
                guard let wordStart = string[start...].firstIndex(where: { $0 != " " }) else { break }
                let wordEnd = string[wordStart...].firstIndex(of: " ") ?? string.endIndex
                let range = wordStart..<wordEnd
                let wordBox = (try? best.boundingBox(for: range))?.map { box($0.boundingBox) } ?? box(observation.boundingBox)
                words.append(Layout.Item(text: String(string[range]), box: wordBox))
                start = wordEnd
            }
        }
        return RecognisedText(lines: rows(pieces), stacked: Layout.linearize(words))
    }

    static func rows(_ pieces: [Piece]) -> [Line] {
        var lines: [Line] = []
        for piece in pieces.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let index = lines.firstIndex(where: { sameRow($0.box, piece.box) }) {
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
    }

    /// Every separate problem in the area, in reading order. Each line is tried with Vision's
    /// best reading of every piece, then its second best, and so on; where readings overlap, the
    /// longest wins. Stacked fractions put back together come first. Equations that share the same
    /// unknowns, as many equations as unknowns, are one problem: simultaneous equations.
    static func problems(in text: RecognisedText, to focus: CGPoint) -> [Candidate] {
        var all: [Candidate] = []
        func add(_ found: String, box: CGRect, fromStack: Bool) {
            let isEquationOrCommand = found.contains("=") || found.first?.isLetter == true
            all.append(Candidate(text: found, distance: distanceFrom(focus, to: box), box: box,
                                 isEquationOrCommand: isEquationOrCommand, fromStack: fromStack))
        }
        for item in text.stacked {
            for (found, range) in ProblemFinder.problems(in: item.text) {
                add(found, box: boxOf(range, spans: [(0..<item.text.count, item.box)], line: item.box), fromStack: true)
            }
        }
        for line in text.lines {
            let variants = line.pieces.map(\.readings.count).max() ?? 0
            for variant in 0..<variants {
                var joined = ""
                var spans: [(range: Range<Int>, box: CGRect)] = []
                var previous: CGRect?
                for piece in line.pieces {
                    if let previous {
                        // A wide gap separates problems; a narrow one is a space within one.
                        joined += piece.box.minX - previous.maxX > 1.5 * piece.box.height ? " ¦ " : " "
                    }
                    let reading = piece.readings[min(variant, piece.readings.count - 1)]
                    let start = joined.count
                    joined += reading
                    spans.append((start..<joined.count, piece.box))
                    previous = piece.box
                }
                for (found, range) in ProblemFinder.problems(in: joined) {
                    add(found, box: boxOf(range, spans: spans, line: line.box), fromStack: false)
                }
            }
        }
        // One reading per place: stacked first, then the longest, then the nearest.
        all.sort { a, b in
            if a.fromStack != b.fromStack { return a.fromStack }
            if a.text.count != b.text.count { return a.text.count > b.text.count }
            return a.distance < b.distance
        }
        var accepted: [Candidate] = []
        for candidate in all {
            let key = candidate.text.filter { !$0.isWhitespace }
            guard !accepted.contains(where: { overlaps($0.box, candidate.box) || $0.text.filter { !$0.isWhitespace } == key })
            else { continue }
            accepted.append(candidate)
        }
        guard let nearest = accepted.min(by: { a, b in
            abs(a.distance - b.distance) <= 4 ? a.text.count > b.text.count : a.distance < b.distance
        }) else { return [] }
        // Besides the nearest, keep only what's clearly maths: an equation, letters, an
        // instruction, or a sum with two operations, so a date or page number isn't a problem.
        accepted = accepted.filter { $0.text == nearest.text || isSubstantial($0.text) }
        accepted = groupSimultaneous(accepted)
        // Reading order: top to bottom, then left to right.
        return accepted.sorted { a, b in
            abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5 ? a.box.minX < b.box.minX : a.box.minY < b.box.minY
        }
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 && intersection.width * intersection.height > 0.3 * smaller
    }

    private static func isSubstantial(_ text: String) -> Bool {
        if text.contains("=") || text.contains(where: \.isLetter) { return true }
        let operations = text.filter { "+-−*/×÷^√%".contains($0) }.count
        return operations >= 2
    }

    /// Equations in the same two or more unknowns, as many as there are unknowns: solved together.
    private static func groupSimultaneous(_ candidates: [Candidate]) -> [Candidate] {
        func unknowns(_ text: String) -> Set<String>? {
            let sides = text.split(separator: "=", omittingEmptySubsequences: false)
            guard sides.count == 2, let left = Parser.expression(String(sides[0])),
                  let right = Parser.expression(String(sides[1])) else { return nil }
            let symbols = left.symbols.union(right.symbols)
            return symbols.count >= 2 ? symbols : nil
        }
        var groups: [Set<String>: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            if let set = unknowns(candidate.text) { groups[set, default: []].append(index) }
        }
        var grouped = Set<Int>()
        var result: [Candidate] = []
        for (set, members) in groups where members.count == set.count {
            let ordered = members.sorted { candidates[$0].box.minY < candidates[$1].box.minY }
            var combined = candidates[ordered[0]]
            combined.text = ordered.map { candidates[$0].text }.joined(separator: "; ")
            combined.box = ordered.dropFirst().reduce(combined.box) { $0.union(candidates[$1].box) }
            combined.distance = ordered.map { candidates[$0].distance }.min() ?? combined.distance
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

    /// Roughly where a run of characters is, assuming they're evenly spaced within each piece.
    private static func boxOf(_ range: Range<Int>, spans: [(range: Range<Int>, box: CGRect)], line: CGRect) -> CGRect {
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for span in spans where span.range.overlaps(range) {
            let count = CGFloat(max(span.range.count, 1))
            let from = CGFloat(max(range.lowerBound, span.range.lowerBound) - span.range.lowerBound)
            let to = CGFloat(min(range.upperBound, span.range.upperBound) - span.range.lowerBound)
            minX = min(minX, span.box.minX + span.box.width * from / count)
            maxX = max(maxX, span.box.minX + span.box.width * to / count)
        }
        guard minX <= maxX else { return line }
        return CGRect(x: minX, y: line.minY, width: maxX - minX, height: line.height)
    }

    private static func distanceFrom(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
