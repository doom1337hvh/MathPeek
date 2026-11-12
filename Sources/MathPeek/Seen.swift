import AppKit

/// What MathPeek made out in a picture of the screen, for the debug view (Settings, Debug):
/// every patch of ink in the text it read, each line as it read it, each sum it found with
/// why it was left out if it was, and the circles and lines of any diagram. All of it in
/// points from the top-left of the area that was read.
struct Seen: Sendable {
    struct Mark: Sendable {
        var box: CGRect
        var kind: LineMender.Mark
    }

    struct Line: Sendable {
        var box: CGRect
        var text: String
        /// How tall its capitals are, in pixels, if the ink could be made out.
        var tall: CGFloat?
    }

    struct Sum: Sendable {
        var box: CGRect
        var text: String
        var answer: String?
        /// Why it isn't highlighted, or nil if it is.
        var leftOut: String?
    }

    struct Circle: Sendable {
        var centre: CGPoint
        var radius: CGFloat
    }

    struct Stroke: Sendable {
        var from: CGPoint
        var to: CGPoint
    }

    struct Label: Sendable {
        var box: CGRect
        var text: String
    }

    struct Point: Sendable {
        var at: CGPoint
        var name: String
    }

    var marks: [Mark] = []
    var lines: [Line] = []
    var sums: [Sum] = []
    var circles: [Circle] = []
    var strokes: [Stroke] = []
    var points: [Point] = []
    var labels: [Label] = []
}

/// Somewhere to put what was seen, from the thread that reads the screen.
final class SeenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held: Seen?

    var seen: Seen? {
        get { lock.withLock { held } }
        set { lock.withLock { held = newValue } }
    }
}

extension ScreenReader {
    /// What was made out in `image`, given the text read from it and what's highlighted.
    /// The diagrams are looked for again, to keep what was found at each stage; that's slow,
    /// and only done for the debug view.
    static func seen(in image: CGImage, size: CGSize, text: RecognisedText?, shown: [Spotted], _ options: ReadOptions) -> Seen {
        var seen = Seen()
        func isShown(_ box: CGRect) -> Bool {
            shown.contains { spot in
                let both = spot.box.intersection(box)
                return !both.isNull && both.width * both.height >= min(spot.box.width * spot.box.height, box.width * box.height) * 0.3
            }
        }
        if let text {
            let mender = text.page.map { LineMender(ink: $0.ink) }
            for piece in text.lines.flatMap(\.pieces) {
                seen.lines.append(Seen.Line(box: piece.box, text: piece.readings.first ?? "", tall: piece.tall))
                guard let page = text.page, let mender else { continue }
                seen.marks += mender.marks(of: page.inPicture(piece.box)).map { Seen.Mark(box: page.inPoints($0.box), kind: $0.mark) }
            }
            for candidate in problems(in: text, to: nil) {
                let solution = worked(candidate.text, options)
                var leftOut: String?
                if !isShown(candidate.box) {
                    if candidate.hasUnreadMark || candidate.text.contains(LineMender.unreadable) {
                        leftOut = "a raised mark couldn't be read"
                    } else if candidate.isSuspect {
                        leftOut = "the ink doesn't match what was read"
                    } else if let tall = candidate.tall, tall < smallestTall {
                        leftOut = "too small to be sure of"
                    } else if !candidate.fromStack, text.page?.isPartOfFraction(candidate.box, tall: candidate.tall) == true {
                        leftOut = "part of a fraction or a root"
                    } else if solution == nil {
                        leftOut = "can't be worked out as read"
                    } else {
                        leftOut = "a second reading differed, or it isn't a question"
                    }
                }
                seen.sums.append(Seen.Sum(box: candidate.box, text: candidate.text, answer: solution?.answerText, leftOut: leftOut))
            }
        }
        // What's highlighted that isn't a line of maths: a question in words, a diagram.
        for spot in shown where !seen.sums.contains(where: { $0.leftOut == nil && !$0.box.intersection(spot.box).isNull }) {
            guard let solution = spot.solutions.first else { continue }
            seen.sums.append(Seen.Sum(box: spot.box, text: solution.question.text, answer: solution.answerText, leftOut: nil))
        }

        var trace = DiagramReader.Trace()
        _ = withUnsafeMutablePointer(to: &trace) { DiagramReader.diagrams(in: image, limit: 12, trace: $0) }
        let scale = CGFloat(image.width) / max(size.width, 1)
        func inPoints(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x / scale, y: point.y / scale) }
        seen.circles = trace.circles.map { Seen.Circle(centre: CGPoint(x: $0.x / scale, y: $0.y / scale), radius: $0.radius / scale) }
        seen.strokes = trace.segments.map { Seen.Stroke(from: inPoints($0.0), to: inPoints($0.1)) }
        seen.points = trace.points.map { Seen.Point(at: inPoints($0.0), name: $0.1) }
        seen.labels = trace.labels.map {
            Seen.Label(box: CGRect(x: $0.0.minX / scale, y: $0.0.minY / scale, width: $0.0.width / scale, height: $0.0.height / scale), text: $0.1)
        }
        return seen
    }
}
