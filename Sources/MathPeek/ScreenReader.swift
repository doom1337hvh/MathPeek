import AppKit
import ScreenCaptureKit
import Vision

/// What MathPeek found in the area it read.
enum Reading: Sendable {
    case sum(Calculation)
    case noMaths
    case failed(String)
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

/// Reads the maths in part of the screen: a screenshot of just that part with
/// ScreenCaptureKit (which leaves out MathPeek's own windows), text recognition on this Mac
/// with Vision, and then the sum nearest the pointer. Nothing is saved or sent anywhere.
enum ScreenReader {
    static func read(_ area: ScreenArea) async -> Reading {
        let image: CGImage
        do {
            image = try await capture(area)
        } catch {
            return .failed("Couldn't read the screen: \(error.localizedDescription)")
        }
        let lines: [Line]
        do {
            lines = try recognize(image, size: area.rect.size)
        } catch {
            return .failed("Couldn't recognise the text: \(error.localizedDescription)")
        }
        guard let nearest = nearestSum(in: lines, to: area.focus) else { return .noMaths }
        return .sum(nearest)
    }

    private static func capture(_ area: ScreenArea) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
            throw CocoaError(.featureUnsupported)
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area.rect
        configuration.width = Int(area.rect.width * area.scale)
        configuration.height = Int(area.rect.height * area.scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    // MARK: Text recognition

    /// One piece of text Vision found, with its best readings, and where it is in points from
    /// the top-left of the area.
    struct Piece {
        let readings: [String]
        let box: CGRect
    }

    /// Pieces of text on the same row, left to right, so a sum Vision split in two ("12 × 3"
    /// and "=") is read whole.
    struct Line {
        var pieces: [Piece]
        var box: CGRect
    }

    static func recognize(_ image: CGImage, size: CGSize) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" numbers and symbols into words.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let pieces = (request.results ?? []).compactMap { observation -> Piece? in
            let readings = observation.topCandidates(3).map(\.string)
            guard !readings.isEmpty else { return nil }
            // Vision's boxes are 0...1 from the bottom-left.
            let box = observation.boundingBox
            return Piece(readings: readings,
                         box: CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                                     width: box.width * size.width, height: box.height * size.height))
        }
        return rows(pieces)
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

    // MARK: Choosing the sum

    /// The sum nearest `focus`. Each line is tried with Vision's best reading of every piece,
    /// then its second best, and so on; a longer sum wins over one that's about as near.
    static func nearestSum(in lines: [Line], to focus: CGPoint) -> Calculation? {
        var best: (calculation: Calculation, distance: CGFloat, length: Int)?
        for line in lines {
            let variants = line.pieces.map(\.readings.count).max() ?? 0
            for variant in 0..<variants {
                // The line's text, and where each piece's characters start in it.
                var text = ""
                var spans: [(range: Range<Int>, box: CGRect)] = []
                for piece in line.pieces {
                    if !text.isEmpty { text += " " }
                    let reading = piece.readings[min(variant, piece.readings.count - 1)]
                    let start = text.count
                    text += reading
                    spans.append((start..<text.count, piece.box))
                }
                for (calculation, range) in Maths.findSums(in: text) {
                    let box = boxOf(range, spans: spans, line: line.box)
                    let distance = distanceFrom(focus, to: box)
                    let length = calculation.text.count
                    if let current = best {
                        let nearer = distance < current.distance - 4
                        let asNear = abs(distance - current.distance) <= 4
                        guard nearer || (asNear && length > current.length) else { continue }
                    }
                    best = (calculation, distance, length)
                }
            }
        }
        return best?.calculation
    }

    /// Roughly where a run of characters is, assuming they're evenly spaced within each piece.
    private static func boxOf(_ range: Range<Int>, spans: [(range: Range<Int>, box: CGRect)], line: CGRect) -> CGRect {
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for span in spans where span.range.overlaps(range) || span.range.isEmpty && range.contains(span.range.lowerBound) {
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
