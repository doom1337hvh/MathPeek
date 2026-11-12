import CoreGraphics
import CoreText
import Foundation
import Vision

/// Finds circle diagrams in a picture and reads them: the circle, the straight lines drawn in
/// and around it, the points where they meet, and the letters and numbers written by them.
///
/// Text recognition can't do this: it reads "126°" and "33°" but not which angle each is in.
/// So the lines are found in the ink itself. A drawn line is a thin stroke that differs from
/// what's either side of it, whatever the background is; the circle is the ring of stroke
/// that fits best; the straight lines are what's left that lies along a line; and whatever
/// remains is writing, which is read a label at a time.
enum DiagramReader {
    struct Found: Sendable {
        var diagram: Diagram
        /// Where it is in the picture, in pixels from the top-left.
        var box: CGRect
    }

    /// What was made out at each stage, for checking by eye.
    struct Trace {
        var circles: [(x: Double, y: Double, radius: Double, cover: Double)] = []
        var segments: [(CGPoint, CGPoint)] = []
        var points: [(CGPoint, String)] = []
        var labels: [(CGRect, String)] = []
        var notes: [String] = []
        var wantsRuns = false
        /// Keep what a reading that came to nothing made of the ink, for looking into why.
        var keepsAttempts = false
        /// The sheets the labels were read from.
        var sheets: [CGImage] = []
        /// The ink left once the circle, lines and arcs are taken away, for each diagram.
        var leftovers: [CGImage] = []
    }

    /// Every circle diagram in the picture that has an angle marked, nearest `focus` first.
    static func diagrams(in image: CGImage, near focus: CGPoint? = nil, limit: Int = 8, trace: UnsafeMutablePointer<Trace>? = nil) -> [Found] {
        guard let pixels = Pixels(image) else { return [] }
        let ink = strokes(in: pixels)
        let pieces = pieces(of: ink, width: pixels.width, height: pixels.height)
        var circles = circles(in: ink, pieces, width: pixels.width, height: pixels.height)
        func away(_ box: CGRect) -> Double {
            guard let focus else { return box.minY * 4 + box.minX }
            let distance = max(abs(focus.x - box.midX) - box.width / 2, 0) + max(abs(focus.y - box.midY) - box.height / 2, 0)
            // Drawings side by side, each with its letter at its top left: a pointer just past
            // the right of one, level with it, is on the next one's letter.
            if focus.x > box.maxX + 2, focus.y > box.minY - box.height * 0.3, focus.y < box.maxY + box.height * 0.1 {
                return distance + max(60, box.width * 0.4)
            }
            return distance
        }
        circles.sort { away(CGRect(x: $0.x - $0.radius, y: $0.y - $0.radius, width: $0.radius * 2, height: $0.radius * 2))
            < away(CGRect(x: $1.x - $1.radius, y: $1.y - $1.radius, width: $1.radius * 2, height: $1.radius * 2)) }
        trace?.pointee.circles = circles.map { ($0.x, $0.y, $0.radius, $0.cover) }
        var found: [Found] = []
        for circle in circles.prefix(limit * 3) {
            if let diagram = read(circle, pixels, ink, trace: trace) { found.append(diagram) }
            if found.count >= limit { break }
        }
        var rings = circles.map { CGRect(x: $0.x - $0.radius * 1.15, y: $0.y - $0.radius * 1.15, width: $0.radius * 2.3, height: $0.radius * 2.3) }
        // Circles drawn a little squashed, as exam papers often draw them: found as an oval,
        // then read from a copy of that part of the picture stretched back into a circle.
        var dice = Dice(state: 0x2545F4914F6CDD1D)
        for piece in pieces where found.count < limit {
            let box = piece.box
            guard max(box.width, box.height) >= 80, min(box.width, box.height) >= 60, !rings.contains(where: { $0.intersects(box) }),
                  let oval = oval(in: piece, ink, width: pixels.width, height: pixels.height, &dice) else { continue }
            rings.append(CGRect(x: oval.x - oval.a * 1.15, y: oval.y - oval.b * 1.15, width: oval.a * 2.3, height: oval.b * 2.3))
            trace?.pointee.notes.append(String(format: "oval at %.0f, %.0f: %.0f across, %.0f up", oval.x, oval.y, oval.a, oval.b))
            if let diagram = read(oval: oval, in: image, trace: trace) { found.append(diagram) }
        }
        // Triangles, in the pieces of ink that aren't part of a circle's diagram.
        var triangles = 0
        // Drawings the pointer is on that couldn't be read.
        var unread: [CGRect] = []
        for piece in pieces.sorted(by: { away($0.box) < away($1.box) }) where triangles < limit {
            let box = piece.box
            // An outline, not a block of something; and not in a circle.
            guard max(box.width, box.height) >= 70, min(box.width, box.height) >= 36, max(box.width, box.height) <= 1400,
                  piece.pixels.count <= Int(box.width + box.height) * 14,
                  !rings.contains(where: { $0.intersects(box) }) else { continue }
            // A triangle with its sides and angles; or failing that, a figure of lines with angles in it.
            // What a reading that came to nothing made of the ink isn't part of any diagram.
            let before = trace.map { ($0.pointee.segments.count, $0.pointee.points.count, $0.pointee.labels.count) }
            func forget() {
                guard let trace, let before, !trace.pointee.keepsAttempts else { return }
                trace.pointee.segments.removeSubrange(before.0...)
                trace.pointee.points.removeSubrange(before.1...)
                trace.pointee.labels.removeSubrange(before.2...)
            }
            if let diagram = read(triangleIn: piece, pixels, ink, trace: trace), !diagram.diagram.solutions.isEmpty {
                found.append(diagram)
                triangles += 1
                continue
            }
            forget()
            if let diagram = read(figureIn: piece, pixels, ink, trace: trace) {
                found.append(diagram)
                triangles += 1
            } else {
                if let focus, box.contains(focus) { unread.append(box) }
                forget()
            }
        }
        found.sort { away($0.box) < away($1.box) }
        // The pointer is on a drawing that couldn't be read: the one beside it is another
        // question's, and its answer isn't this one's. (A frame round both isn't a drawing
        // beside it.)
        if let focus {
            found.removeAll { item in !item.box.contains(focus) && unread.contains { !$0.intersects(item.box) } }
        }
        return Array(found.prefix(limit))
    }

    // MARK: The picture

    private struct Pixels {
        let width: Int
        let height: Int
        /// Red, green, blue and a spare byte for each pixel, rows from the top.
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            guard width > 8, height > 8, width * height < 40_000_000,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let data = context.data else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.width = width
            self.height = height
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        }
    }

    /// How different two colours are: the most any of red, green and blue differs.
    @inline(__always)
    private static func difference(_ p: UnsafePointer<UInt8>, _ a: Int, _ b: Int) -> Int {
        let i = a << 2, j = b << 2
        return max(abs(Int(p[i]) - Int(p[j])), abs(Int(p[i + 1]) - Int(p[j + 1])), abs(Int(p[i + 2]) - Int(p[j + 2])))
    }

    /// Which pixels are part of a thin stroke: unlike what's a little way off on both sides
    /// of them, in some direction. That finds lines and writing on any background, light or
    /// dark, plain or chequered, and leaves out the edges of filled shapes, where one side
    /// is the same as the pixel (and a blurred edge, which is in between its two sides).
    private static func strokes(in pixels: Pixels) -> [Bool] {
        let width = pixels.width, height = pixels.height
        var ink = [Bool](repeating: false, count: width * height)
        let threshold = 30
        // Across, down and both diagonals, near and farther: thin lines and thicker ones.
        let probes: [(dx: Int, dy: Int)] = [(3, 0), (0, 3), (2, 2), (2, -2), (7, 0), (0, 7), (5, 5), (5, -5)]
        pixels.bytes.withUnsafeBufferPointer { buffer in
            guard let p = buffer.baseAddress else { return }
            ink.withUnsafeMutableBufferPointer { out in
                probes.withUnsafeBufferPointer { probes in
                    for y in 0..<height {
                        for x in 0..<width {
                            let here = y * width + x
                            for probe in probes {
                                let ax = x + probe.dx, ay = y + probe.dy, bx = x - probe.dx, by = y - probe.dy
                                guard ax >= 0, ax < width, bx >= 0, bx < width, ay >= 0, ay < height, by >= 0, by < height else { continue }
                                let a = ay * width + ax, b = by * width + bx
                                let toA = difference(p, here, a)
                                guard toA > threshold else { continue }
                                let toB = difference(p, here, b)
                                guard toB > threshold else { continue }
                                if difference(p, a, b) * 10 <= max(toA, toB) * 12 {
                                    out[here] = true
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        return ink
    }

    // MARK: Circles

    struct Circle {
        var x: Double
        var y: Double
        var radius: Double
        /// How much of the way round has ink on it.
        var cover: Double
        /// How thick its line is.
        var thickness: Double
    }

    /// A small, repeatable source of random numbers: the same picture reads the same every time.
    private struct Dice {
        var state: UInt64
        mutating func roll(_ below: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(max(below, 1)))
        }
    }

    /// How much of the way round a circle there's ink, within `slack` pixels of it.
    private static func cover(_ ink: [Bool], _ width: Int, _ height: Int, x: Double, y: Double, radius: Double, slack: Int) -> Double {
        let count = min(720, max(48, Int(radius * 3)))
        var hits = 0
        for index in 0..<count {
            let angle = Double(index) * 2 * .pi / Double(count)
            let px = Int((x + radius * cos(angle)).rounded()), py = Int((y + radius * sin(angle)).rounded())
            var hit = false
            for dy in -slack...slack where !hit {
                for dx in -slack...slack {
                    let qx = px + dx, qy = py + dy
                    if qx >= 0, qx < width, qy >= 0, qy < height, ink[qy * width + qx] {
                        hit = true
                        break
                    }
                }
            }
            if hit { hits += 1 }
        }
        return Double(hits) / Double(count)
    }

    /// The circle through three points.
    private static func circle(through a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> (x: Double, y: Double, radius: Double)? {
        let d = 2 * (a.0 * (b.1 - c.1) + b.0 * (c.1 - a.1) + c.0 * (a.1 - b.1))
        guard abs(d) > 1e-6 else { return nil }
        let a2 = a.0 * a.0 + a.1 * a.1, b2 = b.0 * b.0 + b.1 * b.1, c2 = c.0 * c.0 + c.1 * c.1
        let x = (a2 * (b.1 - c.1) + b2 * (c.1 - a.1) + c2 * (a.1 - b.1)) / d
        let y = (a2 * (c.0 - b.0) + b2 * (a.0 - c.0) + c2 * (b.0 - a.0)) / d
        return (x, y, hypot(a.0 - x, a.1 - y))
    }

    /// The circle that fits the ink near a rough one best.
    private static func fitted(_ ink: [Bool], _ width: Int, _ height: Int, near rough: (x: Double, y: Double, radius: Double), within band: Double) -> (x: Double, y: Double, radius: Double)? {
        let x0 = max(Int(rough.x - rough.radius - band - 1), 0), x1 = min(Int(rough.x + rough.radius + band + 2), width)
        let y0 = max(Int(rough.y - rough.radius - band - 1), 0), y1 = min(Int(rough.y + rough.radius + band + 2), height)
        guard x1 > x0, y1 > y0 else { return nil }
        // Least squares for x² + y² + Dx + Ey + F = 0, about the rough centre to keep the sums small.
        var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0, sxz = 0.0, syz = 0.0, sz = 0.0, n = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 where ink[y * width + x] {
                let u = Double(x) - rough.x, v = Double(y) - rough.y
                guard abs(hypot(u, v) - rough.radius) <= band else { continue }
                let z = u * u + v * v
                sxx += u * u; sxy += u * v; syy += v * v; sx += u; sy += v
                sxz += u * z; syz += v * z; sz += z; n += 1
            }
        }
        guard n >= 12 else { return nil }
        // [sxx sxy sx][D]   [-sxz]
        // [sxy syy sy][E] = [-syz]
        // [sx  sy  n ][F]   [-sz ]
        let m = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]], r = [-sxz, -syz, -sz]
        guard let solved = solve3(m, r) else { return nil }
        let cx = -solved[0] / 2, cy = -solved[1] / 2
        let squared = cx * cx + cy * cy - solved[2]
        guard squared > 0 else { return nil }
        return (rough.x + cx, rough.y + cy, squared.squareRoot())
    }

    private static func solve3(_ m: [[Double]], _ r: [Double]) -> [Double]? {
        var a = m, b = r
        for column in 0..<3 {
            guard let pivot = (column..<3).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }), abs(a[pivot][column]) > 1e-9 else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in 0..<3 where row != column {
                let factor = a[row][column] / a[column][column]
                for k in column..<3 { a[row][k] -= factor * a[column][k] }
                b[row] -= factor * b[column]
            }
        }
        return (0..<3).map { b[$0] / a[$0][$0] }
    }

    struct Piece {
        var pixels: [Int32]
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
        var box: CGRect { CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1) }
    }

    /// The joined-up pieces of ink that are big enough to be a drawing.
    static func pieces(of ink: [Bool], width: Int, height: Int) -> [Piece] {
        var label = [Int32](repeating: 0, count: width * height)
        var pieces: [Piece] = []
        var stack: [Int32] = []
        for start in 0..<(width * height) where ink[start] && label[start] == 0 {
            let number: Int32 = 1
            var members: [Int32] = []
            var x0 = width, y0 = height, x1 = 0, y1 = 0
            stack.append(Int32(start))
            label[start] = number
            while let top = stack.popLast() {
                let index = Int(top), x = index % width, y = index / width
                members.append(top)
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let next = ny * width + nx
                        if ink[next], label[next] == 0 {
                            label[next] = number
                            stack.append(Int32(next))
                        }
                    }
                }
            }
            if max(x1 - x0, y1 - y0) >= 44, min(x1 - x0, y1 - y0) >= 24, members.count >= 100 {
                pieces.append(Piece(pixels: members, x0: x0, y0: y0, x1: x1, y1: y1))
            }
        }
        return Array(pieces.sorted { $0.pixels.count > $1.pixels.count }.prefix(80))
    }

    /// The drawn circles in the ink. Each piece is tried: three of its pixels at random give
    /// a circle, and the one with ink most of the way round wins.
    static func circles(in ink: [Bool], _ big: [Piece], width: Int, height: Int) -> [Circle] {

        var circles: [Circle] = []
        var dice = Dice(state: 0x9E3779B97F4A7C15)
        for piece in big {
            let span = Double(max(piece.x1 - piece.x0, piece.y1 - piece.y0))
            let count = piece.pixels.count
            var best: (x: Double, y: Double, radius: Double, cover: Double)?
            for _ in 0..<700 {
                let picks = (0..<3).map { _ -> (Double, Double) in
                    let index = Int(piece.pixels[dice.roll(count)])
                    return (Double(index % width), Double(index / width))
                }
                let apart = min(hypot(picks[0].0 - picks[1].0, picks[0].1 - picks[1].1), hypot(picks[1].0 - picks[2].0, picks[1].1 - picks[2].1),
                                hypot(picks[0].0 - picks[2].0, picks[0].1 - picks[2].1))
                guard apart >= 18, let rough = circle(through: picks[0], picks[1], picks[2]), rough.radius >= 20, rough.radius <= span * 0.75,
                      rough.x - rough.radius > -2, rough.y - rough.radius > -2, rough.x + rough.radius < Double(width) + 2, rough.y + rough.radius < Double(height) + 2
                else { continue }
                let covered = cover(ink, width, height, x: rough.x, y: rough.y, radius: rough.radius, slack: 2)
                if covered > (best?.cover ?? 0.5) {
                    best = (rough.x, rough.y, rough.radius, covered)
                    if covered > 0.93 { break }
                }
            }
            guard var rough = best.map({ (x: $0.x, y: $0.y, radius: $0.radius) }) else { continue }
            for band in [4.0, 2.5, 2.0] {
                guard let better = fitted(ink, width, height, near: rough, within: band) else { break }
                rough = better
            }
            let covered = cover(ink, width, height, x: rough.x, y: rough.y, radius: rough.radius, slack: 1)
            guard covered >= 0.8, rough.radius >= 20 else { continue }
            // One circle, found once.
            if circles.contains(where: { hypot($0.x - rough.x, $0.y - rough.y) < max($0.radius, rough.radius) * 0.2 && abs($0.radius - rough.radius) < max($0.radius, rough.radius) * 0.2 }) { continue }
            circles.append(Circle(x: rough.x, y: rough.y, radius: rough.radius, cover: covered,
                                  thickness: thickness(ink, width, height, x: rough.x, y: rough.y, radius: rough.radius)))
        }
        return circles
    }

    /// How thick a circle's line is: the usual run of ink across it.
    private static func thickness(_ ink: [Bool], _ width: Int, _ height: Int, x: Double, y: Double, radius: Double) -> Double {
        var runs: [Int] = []
        for index in 0..<90 {
            let angle = Double(index) * 2 * .pi / 90
            var run = 0
            for step in -24...24 {
                let distance = radius + Double(step) / 2
                let px = Int((x + distance * cos(angle)).rounded()), py = Int((y + distance * sin(angle)).rounded())
                if px >= 0, px < width, py >= 0, py < height, ink[py * width + px] { run += 1 }
            }
            runs.append(run)
        }
        runs.sort()
        return min(max(Double(runs[runs.count / 2]) / 2, 1), 10)
    }

    /// Solves a small set of linear equations. Nil if they don't have one answer.
    private static func solve(_ m: [[Double]], _ r: [Double]) -> [Double]? {
        var a = m, b = r
        let n = r.count
        for column in 0..<n {
            guard let pivot = (column..<n).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }), abs(a[pivot][column]) > 1e-12 else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in 0..<n where row != column {
                let factor = a[row][column] / a[column][column]
                for k in column..<n { a[row][k] -= factor * a[column][k] }
                b[row] -= factor * b[column]
            }
        }
        return (0..<n).map { b[$0] / a[$0][$0] }
    }

    /// How much of the way round an oval there's ink.
    private static func cover(_ ink: [Bool], _ width: Int, _ height: Int, x: Double, y: Double, a: Double, b: Double, slack: Int) -> Double {
        let count = min(720, max(48, Int(max(a, b) * 3)))
        var hits = 0
        for index in 0..<count {
            let angle = Double(index) * 2 * .pi / Double(count)
            let px = Int((x + a * cos(angle)).rounded()), py = Int((y + b * sin(angle)).rounded())
            var hit = false
            for dy in -slack...slack where !hit {
                for dx in -slack...slack {
                    let qx = px + dx, qy = py + dy
                    if qx >= 0, qx < width, qy >= 0, qy < height, ink[qy * width + qx] {
                        hit = true
                        break
                    }
                }
            }
            if hit { hits += 1 }
        }
        return Double(hits) / Double(count)
    }

    /// A circle drawn as an upright oval, a little wider than tall or taller than wide:
    /// four pixels of the piece at random give an oval, and the one with ink most of the
    /// way round wins.
    private static func oval(in piece: Piece, _ ink: [Bool], width: Int, height: Int, _ dice: inout Dice) -> (x: Double, y: Double, a: Double, b: Double)? {
        let span = Double(max(piece.x1 - piece.x0, piece.y1 - piece.y0))
        let midX = Double(piece.x0 + piece.x1) / 2, midY = Double(piece.y0 + piece.y1) / 2
        let count = piece.pixels.count
        /// The oval Au² + Bv² + Cu + Dv = 1, about the middle of the piece and in units of its size.
        func shape(_ k: [Double]) -> (x: Double, y: Double, a: Double, b: Double)? {
            guard abs(k[0]) > 1e-9, abs(k[1]) > 1e-9 else { return nil }
            let u = -k[2] / (2 * k[0]), v = -k[3] / (2 * k[1])
            let whole = 1 + k[2] * k[2] / (4 * k[0]) + k[3] * k[3] / (4 * k[1])
            let a2 = whole / k[0], b2 = whole / k[1]
            guard a2 > 0, b2 > 0 else { return nil }
            let a = a2.squareRoot() * span, b = b2.squareRoot() * span
            guard min(a, b) >= 24, max(a, b) <= span * 0.75, a / b > 0.78, a / b < 1.28 else { return nil }
            return (midX + u * span, midY + v * span, a, b)
        }
        var best: (x: Double, y: Double, a: Double, b: Double)?
        var bestCover = 0.5
        for _ in 0..<600 {
            var rows: [[Double]] = []
            for _ in 0..<4 {
                let index = Int(piece.pixels[dice.roll(count)])
                let u = (Double(index % width) - midX) / span, v = (Double(index / width) - midY) / span
                rows.append([u * u, v * v, u, v])
            }
            guard let k = solve(rows, [1, 1, 1, 1]), let found = shape(k) else { continue }
            let covered = cover(ink, width, height, x: found.x, y: found.y, a: found.a, b: found.b, slack: 2)
            if covered > bestCover {
                bestCover = covered
                best = found
                if covered > 0.93 { break }
            }
        }
        guard var found = best else { return nil }
        // Fitted to all the ink near it.
        for band in [4.0, 2.5] {
            var m = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4), r = [Double](repeating: 0, count: 4)
            var used = 0
            for pixel in piece.pixels {
                let x = Double(Int(pixel) % width), y = Double(Int(pixel) / width)
                let off = abs((((x - found.x) / found.a) * ((x - found.x) / found.a) + ((y - found.y) / found.b) * ((y - found.y) / found.b)).squareRoot() - 1) * min(found.a, found.b)
                guard off <= band else { continue }
                let u = (x - midX) / span, v = (y - midY) / span
                let row = [u * u, v * v, u, v]
                for i in 0..<4 {
                    for j in 0..<4 { m[i][j] += row[i] * row[j] }
                    r[i] += row[i]
                }
                used += 1
            }
            guard used >= 40, let k = solve(m, r), let better = shape(k) else { break }
            found = better
        }
        // A true circle is the circle finder's to read; and it has to go nearly all the way round.
        guard abs(found.a / found.b - 1) > 0.025, cover(ink, width, height, x: found.x, y: found.y, a: found.a, b: found.b, slack: 1) >= 0.8 else { return nil }
        return found
    }

    /// Reads the diagram of a circle drawn as an oval, from a copy of that part of the
    /// picture stretched until it's round.
    private static func read(oval: (x: Double, y: Double, a: Double, b: Double), in image: CGImage, trace: UnsafeMutablePointer<Trace>?) -> Found? {
        let r = max(oval.a, oval.b)
        let reach = r * 3.3
        let x0 = max(Int(oval.x - reach), 0), x1 = min(Int(oval.x + reach) + 1, image.width)
        let y0 = max(Int(oval.y - reach), 0), y1 = min(Int(oval.y + reach) + 1, image.height)
        guard x1 - x0 > 40, y1 - y0 > 40, let crop = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
        let across = r / oval.a, up = r / oval.b
        let w = Int(Double(crop.width) * across), h = Int(Double(crop.height) * up)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let round = context.makeImage(), let pixels = Pixels(round) else { return nil }
        let ink = strokes(in: pixels)
        let circles = circles(in: ink, pieces(of: ink, width: w, height: h), width: w, height: h)
        let middle = CGPoint(x: (oval.x - Double(x0)) * across, y: (oval.y - Double(y0)) * up)
        guard let circle = circles.min(by: { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }),
              hypot(circle.x - middle.x, circle.y - middle.y) < r * 0.15, abs(circle.radius - r) < r * 0.12,
              let found = read(circle, pixels, ink, trace: trace) else { return nil }
        let box = CGRect(x: found.box.minX / across + Double(x0), y: found.box.minY / up + Double(y0), width: found.box.width / across, height: found.box.height / up)
        return Found(diagram: found.diagram, box: box)
    }

    // MARK: One diagram

    private struct Segment {
        /// A point on it, its direction, and how far along from the point it starts and ends.
        var x: Double
        var y: Double
        var dx: Double
        var dy: Double
        var from: Double
        var to: Double
        var thickness: Double
        /// How wide its ink usually is, across it.
        var width = 0

        func point(_ t: Double) -> CGPoint { CGPoint(x: x + dx * t, y: y + dy * t) }
        func along(_ p: CGPoint) -> Double { (p.x - x) * dx + (p.y - y) * dy }
        func distance(_ p: CGPoint) -> Double { abs((p.x - x) * dy - (p.y - y) * dx) }
        var length: Double { to - from }
    }

    private struct Blob {
        var pixels: [Int32]
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
        var width: Int { x1 - x0 + 1 }
        var height: Int { y1 - y0 + 1 }
        var middle: CGPoint { CGPoint(x: Double(x0 + x1) / 2, y: Double(y0 + y1) / 2) }
    }

    /// A point of a diagram being read.
    private struct Vertex {
        var point: CGPoint
        var place: CircleDiagram.Place
        var name: String?
    }

    private struct Label {
        var blobs: [Blob]
        var box: CGRect
        var hasDegree = false
        var text = ""
    }

    private static func read(_ circle: Circle, _ pixels: Pixels, _ ink: [Bool], trace: UnsafeMutablePointer<Trace>?) -> Found? {
        let width = pixels.width, height = pixels.height
        let r = circle.radius, centre = CGPoint(x: circle.x, y: circle.y)
        // The part of the picture the diagram could be in: tangents reach well outside the circle.
        let reach = r * 3.2
        let x0 = max(Int(circle.x - reach), 0), x1 = min(Int(circle.x + reach) + 1, width)
        let y0 = max(Int(circle.y - reach), 0), y1 = min(Int(circle.y + reach) + 1, height)
        let w = x1 - x0, h = y1 - y0
        guard w > 20, h > 20 else { return nil }
        func note(_ text: String) { trace?.pointee.notes.append(text) }

        // 0 nothing, 1 loose ink, 2 ink joined to the circle, 3 the circle's own line, 4 a straight line's.
        var kind = [UInt8](repeating: 0, count: w * h)
        let rim = circle.thickness / 2 + 2.5
        var stack: [Int32] = []
        for y in 0..<h {
            for x in 0..<w where ink[(y + y0) * width + x + x0] {
                let distance = hypot(Double(x + x0) - circle.x, Double(y + y0) - circle.y)
                if abs(distance - r) <= rim {
                    kind[y * w + x] = 3
                    stack.append(Int32(y * w + x))
                } else {
                    kind[y * w + x] = 1
                }
            }
        }
        // Everything joined to the circle, across gaps of a pixel or two where lines meet.
        while let top = stack.popLast() {
            let x = Int(top) % w, y = Int(top) / w
            for dy in -2...2 {
                for dx in -2...2 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h, kind[ny * w + nx] == 1 else { continue }
                    kind[ny * w + nx] = 2
                    stack.append(Int32(ny * w + nx))
                }
            }
        }

        // Straight lines, by which line the most ink lies along.
        let steps = 360
        let cosines = (0..<steps).map { cos(Double($0) * .pi / Double(steps)) }, sines = (0..<steps).map { sin(Double($0) * .pi / Double(steps)) }
        let far = Int(reach * 1.5) + 2
        let bins = 2 * far + 1
        var votes = [Int32](repeating: 0, count: steps * bins)
        var joined: [(x: Double, y: Double, index: Int)] = []
        for y in 0..<h {
            for x in 0..<w where kind[y * w + x] == 2 || kind[y * w + x] == 3 {
                joined.append((Double(x + x0) - circle.x, Double(y + y0) - circle.y, y * w + x))
            }
        }
        func vote(_ x: Double, _ y: Double, _ amount: Int32) {
            for step in 0..<steps {
                let offset = Int((x * cosines[step] + y * sines[step]).rounded()) + far
                if offset >= 0, offset < bins { votes[step * bins + offset] += amount }
            }
        }
        for item in joined where kind[item.index] == 2 { vote(item.x, item.y, 1) }

        let shortest = max(14, r * 0.14)
        let gap = max(7, r * 0.06)
        var segments: [Segment] = []
        var misses = 0
        while segments.count < 44, misses < 40 {
            var top: Int32 = 0, at = 0
            for index in votes.indices where votes[index] > top {
                top = votes[index]
                at = index
            }
            guard Double(top) >= shortest * 0.8 else { break }
            let step = at / bins, offset = Double(at % bins - far)
            // The line through the ink near that one, twice over.
            var nx = cosines[step], ny = sines[step], px = nx * offset, py = ny * offset
            // Fitted to the middle of its longest unbroken stretch: at the ends, where it
            // meets other lines, arcs and writing, their ink would pull it round. Nor the ink
            // by the circle's own line, where a chord comes in at a shallow angle.
            for slack in [2.5, 1.8, 1.5] {
                let ax = -ny, ay = nx
                var near: [(t: Double, x: Double, y: Double)] = []
                for item in joined where kind[item.index] == 2 && abs((item.x - px) * nx + (item.y - py) * ny) <= slack
                    && abs(hypot(item.x, item.y) - r) > rim + 4 {
                    near.append(((item.x - px) * ax + (item.y - py) * ay, item.x, item.y))
                }
                guard near.count >= 6 else { break }
                near.sort { $0.t < $1.t }
                var best = 0..<0, start = 0
                for index in 1...near.count where index == near.count || near[index].t - near[index - 1].t > 4.5 {
                    if near[index - 1].t - near[start].t > (best.isEmpty ? -1 : near[best.upperBound - 1].t - near[best.lowerBound].t) { best = start..<index }
                    start = index
                }
                guard !best.isEmpty else { break }
                let low = near[best.lowerBound].t, high = near[best.upperBound - 1].t
                let trim = (high - low) * 0.1
                var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0, n = 0.0
                for item in near[best] where item.t >= low + trim && item.t <= high - trim {
                    sx += item.x; sy += item.y; sxx += item.x * item.x; sxy += item.x * item.y; syy += item.y * item.y; n += 1
                }
                guard n >= 6 else { break }
                let mx = sx / n, my = sy / n
                let a = sxx / n - mx * mx, b = sxy / n - mx * my, c = syy / n - my * my
                let angle = 0.5 * atan2(2 * b, a - c)
                px = mx; py = my
                nx = -sin(angle); ny = cos(angle)
            }
            let dx = -ny, dy = nx
            // The ink along it, in order, and the stretches without a gap.
            var along: [(t: Double, index: Int)] = []
            for item in joined where abs((item.x - px) * nx + (item.y - py) * ny) <= 1.8 {
                along.append(((item.x - px) * dx + (item.y - py) * dy, item.index))
            }
            along.sort { $0.t < $1.t }
            var accepted = false
            var start = 0
            for index in 0...along.count {
                // A drawn line is solid: the tops of a row of digits line up too, with gaps between.
                if index == along.count || (index > start && along[index].t - along[index - 1].t > 4.5) {
                    let run = along[start..<index]
                    if let first = run.first, let last = run.last {
                        let length = last.t - first.t
                        let fresh = run.filter { kind[$0.index] == 2 }.count
                        // And straight: an arc marking an angle fits along a line for a little way,
                        // but its middle is off to one side of its ends.
                        var bow = 0.0
                        if length < r * 0.5 {
                            var sums = [0.0, 0.0, 0.0], counts = [0.0, 0.0, 0.0]
                            for item in run where kind[item.index] == 2 {
                                let third = min(Int((item.t - first.t) / max(length, 1) * 3), 2)
                                let x = Double(item.index % w + x0) - circle.x, y = Double(item.index / w + y0) - circle.y
                                sums[third] += (x - px) * nx + (y - py) * ny
                                counts[third] += 1
                            }
                            if counts.allSatisfy({ $0 > 0 }) { bow = abs(sums[1] / counts[1] - (sums[0] / counts[0] + sums[2] / counts[2]) / 2) }
                        }
                        // And with nothing hanging off it: a line that runs through a letter
                        // or along a row of digits has their ink beside it most of the way.
                        var widths: [Int] = []
                        if length >= shortest {
                            var t = first.t + length * 0.1
                            while t <= last.t - length * 0.1 {
                                let ax = px + dx * t + circle.x - Double(x0), ay = py + dy * t + circle.y - Double(y0)
                                func isLoose(_ offset: Double) -> Bool {
                                    let x = Int((ax + nx * offset).rounded()), y = Int((ay + ny * offset).rounded())
                                    return x >= 0 && x < w && y >= 0 && y < h && (kind[y * w + x] == 1 || kind[y * w + x] == 2)
                                }
                                if isLoose(0) {
                                    var across = 1
                                    for side in [1.0, -1.0] {
                                        var offset = 1.0
                                        while offset <= 12, isLoose(offset * side) {
                                            across += 1
                                            offset += 1
                                        }
                                    }
                                    widths.append(across)
                                }
                                t += 1
                            }
                        }
                        let usual = widths.sorted().dropFirst(widths.count / 2).first ?? 0
                        let cluttered = widths.isEmpty ? 0 : Double(widths.filter { $0 >= usual + 3 }.count) / Double(widths.count)
                        if length >= shortest, trace?.pointee.wantsRuns == true {
                            note(String(format: "run %.0f,%.0f→%.0f,%.0f len %.0f fresh %d bow %.2f usual %d cluttered %.2f", px + dx * first.t + circle.x, py + dy * first.t + circle.y,
                                        px + dx * last.t + circle.x, py + dy * last.t + circle.y, length, fresh, bow, usual, cluttered))
                        }
                        // Not the fringe of the circle's own line, where it's thicker than it looked.
                        let hugging = run.filter { item in
                            kind[item.index] == 2 && abs(hypot(Double(item.index % w + x0) - circle.x, Double(item.index / w + y0) - circle.y) - r) <= rim + 3.5
                        }.count
                        // Mostly ink of its own: what's left along the edge of a thick line, or
                        // where several lines run in to one point, lines up too.
                        if length >= shortest, Double(fresh) >= max(shortest * 0.6, length * 0.6), bow <= 0.7,
                           cluttered <= (length >= r * 0.5 ? 0.6 : 0.35), Double(hugging) <= Double(fresh) * 0.7 {
                            accepted = true
                            segments.append(Segment(x: px + circle.x, y: py + circle.y, dx: dx, dy: dy, from: first.t, to: last.t,
                                                    thickness: min(max(Double(run.count) / max(length, 1), 1), 10), width: usual))
                        }
                    }
                    start = index
                }
            }
            if accepted, let segment = segments.last {
                // Its ink is spoken for.
                let reachAcross = max(segment.thickness, Double(segment.width)) / 2 + 2.5
                let found = segments.filter { $0.x == segment.x && $0.y == segment.y && $0.dx == segment.dx }
                for item in joined where kind[item.index] == 2 {
                    let across = abs((item.x - px) * nx + (item.y - py) * ny)
                    guard across <= reachAcross else { continue }
                    let t = (item.x - px) * dx + (item.y - py) * dy
                    if found.contains(where: { t >= $0.from - gap && t <= $0.to + gap }) {
                        kind[item.index] = 4
                        vote(item.x, item.y, -1)
                    }
                }
            } else {
                misses += 1
                for ds in -2...2 {
                    for d in -3...3 {
                        let s = (step + ds + steps) % steps, o = at % bins + d
                        if o >= 0, o < bins { votes[s * bins + o] = 0 }
                    }
                }
            }
        }
        guard segments.count >= 2 else { return nil }

        // Pieces of one line, found separately either side of something, are one line.
        var merged: [Segment] = []
        // In the order found, strongest first: a line's shadow beside it comes later.
        for segment in segments {
            // The same line found again beside itself, where it's thick or something runs along it.
            let sideBySide = max(6, r * 0.07)
            if merged.contains(where: { other in
                let middle = other.along(segment.point((segment.from + segment.to) / 2))
                return abs(other.dx * segment.dy - other.dy * segment.dx) < 0.1
                    && other.distance(segment.point(segment.from)) < sideBySide && other.distance(segment.point(segment.to)) < sideBySide
                    && middle > other.from && middle < other.to
                    && !(other.distance(segment.point(segment.from)) < 3.5 && other.distance(segment.point(segment.to)) < 3.5
                         && abs(other.dx * segment.dy - other.dy * segment.dx) < 0.035)
            }) { continue }
            if let index = merged.firstIndex(where: { other in
                abs(other.dx * segment.dy - other.dy * segment.dx) < 0.035
                    && other.distance(segment.point(segment.from)) < 3.5 && other.distance(segment.point(segment.to)) < 3.5
                    && max(other.along(segment.point(segment.from)), other.along(segment.point(segment.to))) > other.from - r * 0.2
                    && min(other.along(segment.point(segment.from)), other.along(segment.point(segment.to))) < other.to + r * 0.2
            }) {
                let a = merged[index].along(segment.point(segment.from)), b = merged[index].along(segment.point(segment.to))
                merged[index].from = min(merged[index].from, a, b)
                merged[index].to = max(merged[index].to, a, b)
            } else {
                merged.append(segment)
            }
        }
        segments = merged
        let nearCircle = max(4.5, r * 0.05), nearCentre = max(5, r * 0.075), nearPoint = max(6, r * 0.07), beyond = max(7, r * 0.07)
        func out(_ point: CGPoint) -> Double { hypot(point.x - centre.x, point.y - centre.y) }
        func isTangent(_ segment: Segment) -> Bool {
            let away = segment.distance(centre), foot = segment.along(centre)
            return away >= r - max(2.5, r * 0.03) && away <= r + max(3, r * 0.035)
                && (out(segment.point(segment.from)) > r + nearCircle || out(segment.point(segment.to)) > r + nearCircle)
                && foot >= segment.from - beyond && foot <= segment.to + beyond
        }
        // The middle as it's drawn. Exam diagrams aren't drawn accurately, and O is often a
        // little off the true middle of the circle: where two or more lines end together
        // near it, that's O.
        var hub = centre
        do {
            // Lines that come in from the circle and stop near the middle are radii. Where
            // two of them cross is O, even where each runs on a little into the letter there.
            let radii = segments.filter { segment in
                let ends = [segment.point(segment.from), segment.point(segment.to)]
                // (Reaching the circle, or past it into the letter by the point there.)
                return ends.contains { out($0) <= r * 0.3 } && ends.contains { out($0) >= r - nearCircle }
            }
            var best: (point: CGPoint, count: Int)?
            for (number, first) in radii.enumerated() {
                for second in radii[(number + 1)...] {
                    let cross = first.dx * second.dy - first.dy * second.dx
                    guard abs(cross) > 0.2 else { continue }
                    let point = first.point(((second.x - first.x) * second.dy - (second.y - first.y) * second.dx) / cross)
                    guard out(point) <= r * 0.3 else { continue }
                    func stopsAt(_ segment: Segment) -> Bool {
                        let inner = out(segment.point(segment.from)) < out(segment.point(segment.to)) ? segment.point(segment.from) : segment.point(segment.to)
                        return hypot(inner.x - point.x, inner.y - point.y) <= nearPoint * 1.6 && segment.distance(point) <= 3
                    }
                    let count = radii.filter(stopsAt).count
                    if count >= 2, count > (best?.count ?? 0) { best = (point, count) }
                }
            }
            // Only when it's clearly off: lines that meet at the true middle are left to it.
            if let best, out(best.point) > max(nearCentre, r * 0.09) { hub = best.point }
        }
        // A line belongs to the diagram if it's held at both ends: on the circle, at the middle,
        // or outside where another line from elsewhere on the circle meets it. That leaves
        // out the strokes of letters that touch the diagram, the rows of digits whose tops
        // line up, and the edge of the picture where it happens to touch the circle.
        enum End { case circle, centre, inside, outside }
        func end(_ point: CGPoint) -> End {
            let distance = out(point)
            if abs(distance - r) <= nearCircle { return .circle }
            if hypot(point.x - hub.x, point.y - hub.y) <= nearCentre * 1.6 { return .centre }
            return distance > r ? .outside : .inside
        }
        /// Where a line meets the circle, within its own length.
        func contacts(_ segment: Segment) -> [CGPoint] {
            let away = segment.distance(centre), foot = segment.along(centre)
            if isTangent(segment) { return [segment.point(foot)] }
            guard away < r else { return [] }
            let half = (r * r - away * away).squareRoot()
            return [foot - half, foot + half].filter { $0 >= segment.from - nearCircle * 1.5 && $0 <= segment.to + nearCircle * 1.5 }.map { segment.point($0) }
        }
        // Drawn lines are all about as thick as each other: the strokes of writing aren't.
        let long = segments.filter { $0.length >= r * 0.5 }.map(\.width).sorted()
        if !long.isEmpty {
            let usual = Double(long[long.count / 2])
            segments.removeAll { Double($0.width) < usual * 0.5 - 1 || Double($0.width) > usual * 1.6 + 2 }
        }
        var changed = true
        while changed {
            changed = false
            var kept: [Segment] = []
            for (number, whole) in segments.enumerated() {
                var segment = whole
                let mine = contacts(segment)
                func passes(_ other: Segment, _ point: CGPoint) -> Bool {
                    other.distance(point) <= nearPoint && other.along(point) >= other.from - beyond && other.along(point) <= other.to + beyond
                }
                /// Whether a point outside the circle is where this line meets another that
                /// comes from somewhere else on the circle.
                func isHeld(_ point: CGPoint) -> Bool {
                    segments.enumerated().contains { other in
                        guard other.offset != number, passes(other.element, point) else { return false }
                        let theirs = contacts(other.element)
                        return !theirs.isEmpty && !mine.isEmpty
                            && theirs.allSatisfy { a in mine.allSatisfy { hypot(a.x - $0.x, a.y - $0.y) >= r * 0.25 } }
                    }
                }
                let away = segment.distance(centre), foot = segment.along(centre)
                let ends = [segment.point(segment.from), segment.point(segment.to)]
                var keep = true
                if isTangent(segment) {
                    // Something has to end where it touches, or meet it outside.
                    let touch = segment.point(foot)
                    let isMet = segments.enumerated().contains { other in
                        other.offset != number && !isTangent(other.element)
                            && [other.element.from, other.element.to].contains { hypot(other.element.point($0).x - touch.x, other.element.point($0).y - touch.y) <= nearPoint * 1.5 }
                    }
                    keep = isMet || ends.contains { end($0) == .outside && isHeld($0) }
                } else if away > r - max(3, r * 0.02) || ends.allSatisfy({ end($0) == .centre }) {
                    // Along the edge of the circle, or a scrap by the middle.
                    keep = false
                } else {
                    let half = (r * r - away * away).squareRoot()
                    for (index, point) in ends.enumerated() {
                        switch end(point) {
                        case .outside:
                            // Out past the circle to nowhere: only the part inside counts.
                            if !isHeld(point) {
                                if index == 0 { segment.from = max(segment.from, foot - half) } else { segment.to = min(segment.to, foot + half) }
                            }
                        case .inside:
                            // Run on a little past the middle, into the letter there: it stops at the middle.
                            let hubFoot = segment.along(hub)
                            let past = index == 0 ? hubFoot - segment.from : segment.to - hubFoot
                            if segment.distance(hub) <= nearCentre, past > 0, past <= r * 0.3 {
                                if index == 0 { segment.from = hubFoot } else { segment.to = hubFoot }
                                break
                            }
                            // Stopping at another line it meets squarely, having come from the circle or the middle.
                            let far = end(ends[1 - index])
                            let stops = segments.enumerated().contains { other in
                                other.offset != number && other.element.length >= r * 0.4 && passes(other.element, point)
                                    && abs(other.element.dx * segment.dy - other.element.dy * segment.dx) >= 0.42
                            }
                            if !(stops && (far == .circle || far == .centre) && whole.length >= r * 0.3) { keep = false }
                        default:
                            break
                        }
                    }
                    if segment.length < shortest { keep = false }
                }
                if keep {
                    kept.append(segment)
                    if segment.from != whole.from || segment.to != whole.to { changed = true }
                } else {
                    changed = true
                }
            }
            segments = kept
        }
        guard segments.count >= 2 else { return nil }
        trace?.pointee.segments += segments.map { ($0.point($0.from), $0.point($0.to)) }
        // The ink of what turned out not to be lines is writing again.
        for index in kind.indices where kind[index] == 4 { kind[index] = 2 }

        // Where the lines end, cross each other, and meet the circle.
        enum Sort { case centre, circle, crossing, end }
        var spots: [(point: CGPoint, sort: Sort)] = []
        var touches: [Int: CGPoint] = [:]
        for (number, segment) in segments.enumerated() {
            let foot = segment.along(centre), away = segment.distance(centre)
            // Where the whole line meets the circle.
            var meets: [Double] = []
            if away < r {
                let half = (r * r - away * away).squareRoot()
                meets = [foot - half, foot + half]
            }
            let ends = [segment.from, segment.to]
            let endsOut = ends.map { out(segment.point($0)) }
            let isTangent = isTangent(segment)
            if isTangent {
                let touch = CGPoint(x: centre.x + (segment.point(foot).x - centre.x) * r / max(away, 1), y: centre.y + (segment.point(foot).y - centre.y) * r / max(away, 1))
                touches[number] = touch
                spots.append((touch, .circle))
            }
            for (index, end) in ends.enumerated() {
                let distance = endsOut[index]
                if isTangent, abs(end - foot) < max(beyond, (2 * r * nearCircle).squareRoot()) { continue }
                if abs(distance - r) <= nearCircle, let meet = meets.min(by: { abs($0 - end) < abs($1 - end) }), abs(meet - end) <= nearCircle * 2.5 {
                    spots.append((segment.point(meet), .circle))
                } else if hypot(segment.point(end).x - hub.x, segment.point(end).y - hub.y) <= nearCentre * 1.6 {
                    spots.append((hub, .centre))
                } else {
                    spots.append((segment.point(end), .end))
                }
            }
            if !isTangent {
                for meet in meets where meet > segment.from + nearCircle * 2.5 && meet < segment.to - nearCircle * 2.5 {
                    spots.append((segment.point(meet), .circle))
                }
            }
            // Straight through the middle: a diameter.
            if segment.distance(hub) <= max(2.5, r * 0.03), segment.along(hub) > segment.from + nearCentre, segment.along(hub) < segment.to - nearCentre {
                spots.append((hub, .centre))
            }
            for other in segments[(number + 1)...] {
                let cross = segment.dx * other.dy - segment.dy * other.dx
                guard abs(cross) > 0.05 else { continue }
                // Two radii nearly in line with each other meet at the middle, where they end:
                // where their lines would cross is anyone's guess.
                func endsAtHub(_ line: Segment) -> Bool {
                    [line.from, line.to].contains { hypot(line.point($0).x - hub.x, line.point($0).y - hub.y) <= nearCentre * 1.6 }
                }
                if abs(cross) < 0.3, endsAtHub(segment), endsAtHub(other) { continue }
                let t = ((other.x - segment.x) * other.dy - (other.y - segment.y) * other.dx) / cross
                let point = segment.point(t), u = other.along(point)
                if t >= segment.from - beyond, t <= segment.to + beyond, u >= other.from - beyond, u <= other.to + beyond {
                    // Lines that cross right by the middle cross at it.
                    spots.append(hypot(point.x - hub.x, point.y - hub.y) <= nearCentre * 1.6 ? (hub, .centre) : (point, .crossing))
                }
            }
        }
        // Spots close together are one point.
        var groups: [[Int]] = []
        var group = [Int](repeating: -1, count: spots.count)
        for index in spots.indices where group[index] < 0 {
            group[index] = groups.count
            var members = [index]
            var next = 0
            while next < members.count {
                let here = spots[members[next]].point
                // (Outside the circle, where two lines come to a point, their ends can be further apart.)
                let reach = out(here) > r + nearCircle * 2 ? max(nearPoint, r * 0.14) : nearPoint
                for other in spots.indices where group[other] < 0 && hypot(spots[other].point.x - here.x, spots[other].point.y - here.y) <= (out(spots[other].point) > r + nearCircle * 2 ? reach : nearPoint) {
                    group[other] = groups.count
                    members.append(other)
                }
                next += 1
            }
            groups.append(members)
        }
        var vertices: [Vertex] = []
        for members in groups {
            func mean(_ sort: Sort) -> CGPoint? {
                let some = members.filter { spots[$0].sort == sort }.map { spots[$0].point }
                guard !some.isEmpty else { return nil }
                return CGPoint(x: some.map(\.x).reduce(0, +) / Double(some.count), y: some.map(\.y).reduce(0, +) / Double(some.count))
            }
            if mean(.centre) != nil {
                vertices.append(Vertex(point: hub, place: .centre))
            } else if let onCircle = mean(.circle) {
                let distance = max(out(onCircle), 1)
                vertices.append(Vertex(point: CGPoint(x: centre.x + (onCircle.x - centre.x) * r / distance, y: centre.y + (onCircle.y - centre.y) * r / distance), place: .onCircle))
            } else if let point = mean(.crossing) ?? mean(.end) {
                // An end that stops just short of the middle is still a radius.
                if hypot(point.x - hub.x, point.y - hub.y) <= nearCentre * 1.6, !spots.contains(where: { $0.sort == .centre }) {
                    vertices.append(Vertex(point: hub, place: .centre))
                } else {
                    vertices.append(Vertex(point: point, place: out(point) < r ? .inside : .outside))
                }
            }
        }
        // Each line, and the points along it.
        var lines: [CircleDiagram.Line] = []
        /// Which drawn stroke each line is.
        var lineOf: [Int?] = []
        for (number, segment) in segments.enumerated() {
            var on: [(t: Double, vertex: Int)] = []
            for (index, vertex) in vertices.enumerated() {
                let t = segment.along(vertex.point)
                if segment.distance(vertex.point) <= nearPoint, t >= segment.from - beyond - nearPoint, t <= segment.to + beyond + nearPoint { on.append((t, index)) }
            }
            on.sort { $0.t < $1.t }
            guard on.count >= 2 else { continue }
            var tangentAt: Int?
            if let touch = touches[number] {
                tangentAt = on.map(\.vertex).min { hypot(vertices[$0].point.x - touch.x, vertices[$0].point.y - touch.y) < hypot(vertices[$1].point.x - touch.x, vertices[$1].point.y - touch.y) }
                if let found = tangentAt, vertices[found].place != .onCircle { tangentAt = nil }
            }
            lines.append(CircleDiagram.Line(points: on.map(\.vertex), tangentAt: tangentAt))
            lineOf.append(number)
        }
        // Points nothing goes through aren't part of it.
        let used = Set(lines.flatMap(\.points))
        guard used.count >= 3 else { return nil }

        // What's left is writing, the arcs that mark angles, and dots on the points. For
        // those, ink is whatever's darker or lighter than the diagram's own background, close
        // to a stroke: that keeps the true shape of small, thick digits, which the stroke
        // test runs together, without taking in the page beyond the picture's edge.
        func colour(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let at = ((y + y0) * width + x + x0) * 4
            return (Int(pixels.bytes[at]), Int(pixels.bytes[at + 1]), Int(pixels.bytes[at + 2]))
        }
        // The background: the commonest colour inside the circle, and the next if there's
        // nearly as much of it (a chequered one).
        var counts: [Int: Int] = [:]
        for y in max(Int(circle.y - r) - y0, 0)..<min(Int(circle.y + r) - y0, h) {
            for x in max(Int(circle.x - r) - x0, 0)..<min(Int(circle.x + r) - x0, w) where kind[y * w + x] == 0 {
                guard hypot(Double(x + x0) - circle.x, Double(y + y0) - circle.y) < r - rim else { continue }
                let c = colour(x, y)
                counts[(c.0 >> 4) << 8 | (c.1 >> 4) << 4 | c.2 >> 4, default: 0] += 1
            }
        }
        let common = counts.sorted { $0.value > $1.value }.prefix(2)
        guard let first = common.first else { return nil }
        func shade(_ key: Int) -> (Int, Int, Int) { ((key >> 8) << 4 | 8, ((key >> 4) & 15) << 4 | 8, (key & 15) << 4 | 8) }
        var grounds = [shade(first.key)]
        if common.count > 1, let second = common.last, second.value * 6 >= first.value { grounds.append(shade(second.key)) }
        func off(_ x: Int, _ y: Int) -> Int {
            let c = colour(x, y)
            return grounds.map { max(abs(c.0 - $0.0), abs(c.1 - $0.1), abs(c.2 - $0.2)) }.min() ?? 0
        }
        // How far the circle's own line is from the background sets what counts as ink.
        var ring: [Int] = []
        for index in 0..<120 {
            let angle = Double(index) * .pi / 60
            let x = Int((circle.x + r * cos(angle)).rounded()) - x0, y = Int((circle.y + r * sin(angle)).rounded()) - y0
            if x >= 0, x < w, y >= 0, y < h { ring.append(off(x, y)) }
        }
        ring.sort()
        let contrast = ring.isEmpty ? 100 : ring[ring.count / 2]
        let limit = max(34, contrast * 2 / 5)
        var mark = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var nearStroke = false
                for dy in -2...2 where !nearStroke {
                    for dx in -2...2 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && kind[(y + dy) * w + x + dx] != 0 {
                        nearStroke = true
                        break
                    }
                }
                if nearStroke, off(x, y) > limit { mark[y * w + x] = true }
            }
        }
        // The circle's own ink and the lines' come out: as wide as they are, and no wider,
        // since a letter can sit right up against a line.
        func isInk(_ point: CGPoint) -> Bool {
            let x = Int(point.x.rounded()) - x0, y = Int(point.y.rounded()) - y0
            return x >= 0 && x < w && y >= 0 && y < h && mark[y * w + x]
        }
        func run(through point: CGPoint, dx: Double, dy: Double) -> Int {
            guard isInk(point) else { return 0 }
            var count = 1
            for side in [1.0, -1.0] {
                var step = 1.0
                while step <= 14, isInk(CGPoint(x: point.x + dx * step * side, y: point.y + dy * step * side)) {
                    count += 1
                    step += 1
                }
            }
            return count
        }
        var across: [Int] = (0..<90).map { index in
            let angle = Double(index) * .pi / 45
            return run(through: CGPoint(x: circle.x + r * cos(angle), y: circle.y + r * sin(angle)), dx: cos(angle), dy: sin(angle))
        }.filter { $0 > 0 }.sorted()
        let ringWidth = across.isEmpty ? circle.thickness : Double(across[across.count / 2])
        var lineWidths: [Double] = []
        for segment in segments {
            across = (2...8).map { step in
                run(through: segment.point(segment.from + segment.length * Double(step) / 10), dx: -segment.dy, dy: segment.dx)
            }.filter { $0 > 0 }.sorted()
            lineWidths.append(across.isEmpty ? max(Double(segment.width), segment.thickness) : Double(across[across.count / 2]))
        }
        var taken = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where mark[y * w + x] {
                let point = CGPoint(x: Double(x + x0), y: Double(y + y0))
                if abs(out(point) - r) <= ringWidth / 2 + 3
                    || zip(segments, lineWidths).contains(where: { $0.distance(point) <= $1 / 2 + 1.5 && $0.along(point) >= $0.from - 3 && $0.along(point) <= $0.to + 3 }) {
                    taken[y * w + x] = true
                    mark[y * w + x] = false
                }
            }
        }
        // The arcs that mark angles come off first, or they run into the writing by them.
        // An arc is a thin ring of ink round a point, all the way from one of its lines to
        // the next.
        var arcs: [(vertex: Int, from: Double, to: Double, radius: Double)] = []
        for vertex in used {
            let here = vertices[vertex].point
            var around: [(angle: Double, length: Double, half: Double)] = []
            for (number, line) in lines.enumerated() {
                guard let place = line.points.firstIndex(of: vertex) else { continue }
                let half = (lineOf[number].map { lineWidths[$0] } ?? 4) / 2
                for next in [place - 1, place + 1] where line.points.indices.contains(next) {
                    let there = vertices[line.points[next]].point
                    around.append((atan2(there.y - here.y, there.x - here.x), hypot(there.x - here.x, there.y - here.y), half))
                }
            }
            guard around.count >= 2 else { continue }
            around.sort { $0.angle < $1.angle }
            for arc in takeArcs(at: here, between: around, within: r * 0.55, from: max(6, r * 0.05), &mark, &taken, x0: x0, y0: y0, w: w, h: h) {
                arcs.append((vertex, arc.from, arc.to, arc.radius))
            }
        }
        if let trace {
            let grey = mark.map { $0 ? UInt8(0) : UInt8(255) }
            if let provider = CGDataProvider(data: Data(grey) as CFData),
               let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent) { trace.pointee.leftovers.append(image) }
        }
        let blobs = joinedUp(mark, w: w, h: h)
        func inPicture(_ blob: Blob) -> CGRect { CGRect(x: blob.x0 + x0, y: blob.y0 + y0, width: blob.width, height: blob.height) }
        // Writing: near the circle or one of the points, the size letters are, and not a dot or an arc.
        var glyphs: [Blob] = []
        for blob in blobs {
            let middle = CGPoint(x: blob.middle.x + Double(x0), y: blob.middle.y + Double(y0))
            let nearest = used.map { hypot(vertices[$0].point.x - middle.x, vertices[$0].point.y - middle.y) }.min() ?? .infinity
            let outsideNear = used.filter { vertices[$0].place == .outside }.map { hypot(vertices[$0].point.x - middle.x, vertices[$0].point.y - middle.y) }.min() ?? .infinity
            guard out(middle) <= r * 1.38 || nearest <= r * 0.4 || outsideNear <= r * 0.9 else { continue }
            guard blob.pixels.count >= 8, blob.height >= 6 || blob.width >= 6, blob.width >= 3, blob.height <= Int(max(r * 0.42, 30)), blob.width <= Int(max(r * 0.6, 40)) else { continue }
            // A hairline: the edge of the picture, or a rule.
            if blob.width > blob.height * 5 || (blob.height >= blob.width * 3 && blob.width <= 3) || (blob.height >= blob.width * 5 && blob.width <= 5) { continue }
            // Outside the circle there are only the letters of points, right by them.
            // Or the size of an angle at a point outside, where two tangents meet.
            let nearestOutside = used.filter { vertices[$0].place == .outside }.map { hypot(vertices[$0].point.x - middle.x, vertices[$0].point.y - middle.y) }.min() ?? .infinity
            if out(middle) > r + 3, nearest > max(r * 0.3, 30), nearestOutside > r * 0.9 { continue }
            if blob.pixels.count * 10 >= blob.width * blob.height * 9, max(blob.width, blob.height) >= min(blob.width, blob.height) * 4 { continue }
            if blob.x0 <= 1 || blob.y0 <= 1 || blob.x1 >= w - 2 || blob.y1 >= h - 2 { continue }
            // A dot on a point, or the stub of a line there.
            if nearest <= nearPoint, max(blob.width, blob.height) <= Int(max(nearPoint * 2.2, 12)) { continue }
            guard blob.height >= 7 else { continue }
            glyphs.append(blob)
        }
        var labels = grouped(glyphs, specks: blobs.filter { $0.height < 7 && $0.width <= 9 && $0.pixels.count >= 3 }, x0: x0, y0: y0)
        guard !labels.isEmpty, labels.count <= 40 else { return nil }
        if let sheet = read(&labels, pixels, taken: taken, x0: x0, y0: y0, w: w, h: h) { trace?.pointee.sheets.append(sheet) }
        trace?.pointee.labels += labels.map { ($0.box, $0.text + ($0.hasDegree ? "°" : "")) }

        guard let made = diagram(vertices, lines, labels, arcs: arcs, rightAngles: [], centre: centre, r: r, hasCircle: true, trace: trace) else { return nil }
        let diagram = made.diagram, order = made.order
        var box = CGRect(x: circle.x - r, y: circle.y - r, width: 2 * r, height: 2 * r)
        for vertex in order { box = box.union(CGRect(x: vertices[vertex].point.x - 2, y: vertices[vertex].point.y - 2, width: 4, height: 4)) }
        for label in labels where !label.text.isEmpty { box = box.union(label.box) }
        return Found(diagram: .circle(diagram), box: box.intersection(CGRect(x: 0, y: 0, width: width, height: height)))
    }

    /// Takes the arcs that mark angles out of the ink round a point, and says which angles
    /// they were in. An arc is a thin ring of ink round the point, all the way from one of
    /// its lines to the next. `around` is the lines leaving the point, in order of direction.
    /// `faint` is the ink with the paler pixels counted too: an arc drawn as a thin grey line
    /// is in it all the way round, where in `mark` it's in bits.
    private static func takeArcs(at here: CGPoint, between around: [(angle: Double, length: Double, half: Double)], within limit: Double, from nearest: Double,
                             _ mark: inout [Bool], _ taken: inout [Bool], faint: [Bool]? = nil, x0: Int, y0: Int, w: Int, h: Int) -> [(from: Double, to: Double, radius: Double)] {
        var found: [(from: Double, to: Double, radius: Double)] = []
        for index in around.indices {
            let first = around[index], second = around[(index + 1) % around.count]
            var span = second.angle - first.angle
            if span <= 0 { span += 2 * .pi }
            guard span > 0.2, span < 5.9 else { continue }
            let farthest = min(limit, min(first.length, second.length) * 0.8)
            // How much of the way across the angle there's ink, at each distance from the point.
            var covers: [Double] = []
                    var radius = nearest
            while radius <= farthest + 4 {
                let margin = (max(first.half, second.half) + 2.5) / radius
                let sweep = span - 2 * margin
                var cover = 0.0
                if sweep * radius >= 8 {
                    let steps = max(6, Int(sweep * radius))
                    var hits = 0
                    for step in 0...steps {
                        let angle = first.angle + margin + sweep * Double(step) / Double(steps)
                        let x = Int((here.x + radius * cos(angle)).rounded()) - x0, y = Int((here.y + radius * sin(angle)).rounded()) - y0
                        var hit = false
                        for dy in -1...1 where !hit {
                            for dx in -1...1 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && (faint?[(y + dy) * w + x + dx] ?? mark[(y + dy) * w + x + dx]) {
                                hit = true
                                break
                            }
                        }
                        if hit { hits += 1 }
                    }
                    cover = Double(hits) / Double(steps + 1)
                }
                covers.append(cover)
                radius += 1
            }
            // A thin ring with clear space inside it and outside: writing that fills the
            // angle has ink at every distance.
            var groups: [[Double]] = []
            var at = 0
            while at < covers.count {
                guard covers[at] >= 0.88 else { at += 1; continue }
                var last = at
                while last + 1 < covers.count, covers[last + 1] >= 0.88 { last += 1 }
                // Clear inside it; and clear outside too, unless it's solid all the way
                // across, as writing never quite is (a number is often written right by its arc).
                let inside = at >= 3 ? covers[at - 3] : 0
                let outside = min(last + 3 < covers.count ? covers[last + 3] : 0, last + 5 < covers.count ? covers[last + 5] : 0)
                let solid = covers[at...last].filter { $0 >= 0.97 }.count >= 2
                if last - at < 8, inside < 0.3, outside < 0.45 || solid, nearest + Double(last) <= farthest {
                    groups.append((at...last).map { nearest + Double($0) })
                }
                at = last + 1
            }
            guard !groups.isEmpty else { continue }
            // In the diagram's own directions, up the page, an angle turns the other way.
            let reach = (groups.flatMap { $0 }.max() ?? 0) + 3
            found.append((-first.angle - span, -first.angle, reach - 3))
            for y in max(Int(here.y - reach) - y0, 0)..<min(Int(here.y + reach) - y0 + 1, h) {
                for x in max(Int(here.x - reach) - x0, 0)..<min(Int(here.x + reach) - x0 + 1, w) where mark[y * w + x] {
                    let dx = Double(x + x0) - here.x, dy = Double(y + y0) - here.y
                    let distance = hypot(dx, dy)
                    guard groups.contains(where: { distance >= $0[0] - 2 && distance <= $0[$0.count - 1] + 2 }) else { continue }
                    var angle = atan2(dy, dx) - first.angle
                    while angle < 0 { angle += 2 * .pi }
                    if angle <= span {
                        mark[y * w + x] = false
                        taken[y * w + x] = true
                    }
                }
            }
        }

        return found
    }

    /// The joined-up pieces of what's left.
    private static func joinedUp(_ mark: [Bool], w: Int, h: Int) -> [Blob] {
        var blobs: [Blob] = []
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int32] = []
        for start in 0..<(w * h) where mark[start] && !seen[start] {
            var blob = Blob(pixels: [], x0: w, y0: h, x1: 0, y1: 0)
            stack.append(Int32(start))
            seen[start] = true
            while let top = stack.popLast() {
                let x = Int(top) % w, y = Int(top) / w
                blob.pixels.append(top)
                blob.x0 = min(blob.x0, x); blob.x1 = max(blob.x1, x); blob.y0 = min(blob.y0, y); blob.y1 = max(blob.y1, y)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h, mark[ny * w + nx], !seen[ny * w + nx] else { continue }
                        seen[ny * w + nx] = true
                        stack.append(Int32(ny * w + nx))
                    }
                }
            }
            blobs.append(blob)
        }
        return blobs
    }

    /// Glyphs side by side as one label each, without their degree signs.
    private static func grouped(_ glyphs: [Blob], specks: [Blob] = [], x0: Int, y0: Int) -> [Label] {
        // Glyphs side by side are one label.
        let glyphs = glyphs.sorted { $0.x0 < $1.x0 }
        var labels: [Label] = []
        var grouped = [Bool](repeating: false, count: glyphs.count)
        for index in glyphs.indices where !grouped[index] {
            grouped[index] = true
            var members = [glyphs[index]]
            var box = (x0: glyphs[index].x0, y0: glyphs[index].y0, x1: glyphs[index].x1, y1: glyphs[index].y1)
            var grew = true
            while grew {
                grew = false
                for other in glyphs.indices where !grouped[other] {
                    let glyph = glyphs[other]
                    // Close together, going by the smaller of the two: a letter isn't part of a
                    // big shape that happens to be beside it.
                    let tall = min(box.y1 - box.y0 + 1, glyph.height)
                    let gapAcross = max(glyph.x0 - box.x1, box.x0 - glyph.x1)
                    let overlap = min(box.y1, glyph.y1) - max(box.y0, glyph.y0) + 1
                    guard gapAcross <= max(tall * 9 / 10, 3), overlap >= tall * 3 / 10,
                          max(box.y1 - box.y0 + 1, glyph.height) <= tall * 3 else { continue }
                    grouped[other] = true
                    members.append(glyph)
                    box = (min(box.x0, glyph.x0), min(box.y0, glyph.y0), max(box.x1, glyph.x1), max(box.y1, glyph.y1))
                    grew = true
                }
            }
            members.sort { $0.x0 < $1.x0 }
            guard members.count <= 7 else { continue }
            labels.append(Label(blobs: members, box: CGRect(x: box.x0 + x0, y: box.y0 + y0, width: box.x1 - box.x0 + 1, height: box.y1 - box.y0 + 1)))
        }
        // Two angles written side by side at one point are two labels: a degree sign in the
        // middle of a label is the end of the first.
        var index = 0
        while index < labels.count {
            let blobs = labels[index].blobs
            let tall = blobs.map(\.height).max() ?? 0, top = blobs.map(\.y0).min() ?? 0
            if blobs.count >= 3, let ring = blobs.indices.dropFirst().dropLast().first(where: { place in
                let blob = blobs[place]
                return blob.height * 100 <= tall * 62 && blob.width * 10 <= blob.height * 18 && blob.height * 10 <= blob.width * 18 && blob.y1 <= top + tall * 62 / 100
            }) {
                func label(_ part: ArraySlice<Blob>) -> Label {
                    let bx0 = part.map(\.x0).min() ?? 0, by0 = part.map(\.y0).min() ?? 0, bx1 = part.map(\.x1).max() ?? 0, by1 = part.map(\.y1).max() ?? 0
                    return Label(blobs: Array(part), box: CGRect(x: bx0 + x0, y: by0 + y0, width: bx1 - bx0 + 1, height: by1 - by0 + 1))
                }
                labels[index] = label(blobs[...ring])
                labels.insert(label(blobs[(ring + 1)...]), at: index + 1)
            }
            index += 1
        }
        // A degree sign is a small ring at the top right. Text recognition reads it as a nought,
        // so it's taken off first.
        for index in labels.indices {
            guard labels[index].blobs.count >= 2, let last = labels[index].blobs.last else { continue }
            let tall = labels[index].blobs.dropLast().map(\.height).max() ?? 0
            let top = labels[index].blobs.dropLast().map(\.y0).min() ?? 0
            if last.height * 100 <= tall * 62, last.width * 10 <= last.height * 18, last.height * 10 <= last.width * 18,
               last.y1 <= top + tall * 62 / 100 {
                labels[index].hasDegree = true
                labels[index].blobs.removeLast()
                let rest = labels[index].blobs
                let bx0 = rest.map(\.x0).min() ?? 0, by0 = rest.map(\.y0).min() ?? 0, bx1 = rest.map(\.x1).max() ?? 0, by1 = rest.map(\.y1).max() ?? 0
                labels[index].box = CGRect(x: bx0 + x0, y: by0 + y0, width: bx1 - bx0 + 1, height: by1 - by0 + 1)
            }
        }
        // A decimal point is a speck on the line between two digits: too small to count as
        // writing by itself, but 4.5 without it is 45.
        for speck in specks {
            // A degree sign too small to count as writing: a speck up at the top right of a number.
            if speck.width >= 3, speck.height >= 3, let index = labels.indices.first(where: { index in
                // (Of a number with more than one digit: a speck by a lone letter is just a speck.)
                let blobs = labels[index].blobs
                guard blobs.count >= 2 else { return false }
                let top = blobs.map(\.y0).min() ?? 0, bottom = blobs.map(\.y1).max() ?? 0, right = blobs.map(\.x1).max() ?? 0
                let tall = bottom - top + 1
                return speck.x0 >= right - 1 && speck.x0 - right <= max(tall / 2, 3) && speck.y1 <= top + tall * 55 / 100 && speck.y0 >= top - tall / 4
            }) {
                labels[index].hasDegree = true
                continue
            }
            for index in labels.indices where labels[index].blobs.count >= 2 {
                let blobs = labels[index].blobs
                let top = blobs.map(\.y0).min() ?? 0, bottom = blobs.map(\.y1).max() ?? 0
                let tall = bottom - top + 1
                guard speck.height * 3 <= tall, speck.width * 3 <= tall, speck.y1 >= bottom - tall * 3 / 10, speck.y1 <= bottom + 2,
                      let before = blobs.last(where: { $0.x1 < speck.x0 + 1 }), let after = blobs.first(where: { $0.x0 > speck.x1 - 1 }),
                      speck.x0 - before.x1 <= tall / 2, after.x0 - speck.x1 <= tall / 2 else { continue }
                labels[index].blobs.append(speck)
                labels[index].blobs.sort { $0.x0 < $1.x0 }
                break
            }
        }
        return labels
    }

    /// Which labels are a point's letter and which are written in an angle, and the diagram
    /// that makes of the points and lines. `rightAngles` are the corners marked with a little
    /// square: the point, and which way the square is from it.
    private static func diagram(_ vertices: [Vertex], _ lines: [CircleDiagram.Line], _ labels: [Label],
                                arcs: [(vertex: Int, from: Double, to: Double, radius: Double)], rightAngles: [(vertex: Int, towards: Double)],
                                centre: CGPoint, r: Double, hasCircle: Bool, trace: UnsafeMutablePointer<Trace>?) -> (diagram: CircleDiagram, order: [Int])? {
        var vertices = vertices
        let used = Set(lines.flatMap(\.points))
        func out(_ point: CGPoint) -> Double { hypot(point.x - centre.x, point.y - centre.y) }
        func note(_ text: String) { trace?.pointee.notes.append(text) }
        // Which labels are a point's letter, and which are in an angle. Capitals and digits
        // are the full height of the writing; small letters like x aren't.
        func tall(_ label: Label) -> Double { Double(label.blobs.map(\.height).max() ?? 0) }
        let fullHeight = labels.filter { label in
            !label.text.isEmpty && (label.text.allSatisfy { $0.isNumber } || (label.text.count == 1 && "ABDEFGHLMNQRT".contains(label.text)))
        }.map(tall).sorted()
        let tallest = fullHeight.isEmpty ? (labels.filter { !$0.text.isEmpty }.map(tall).max() ?? 1) : fullHeight[fullHeight.count / 2]
        // Writing too small to read for sure gives answers to some other diagram.
        guard tallest >= 11 else { return nil }
        var names: [(label: Int, letter: String)] = []
        var amounts: [(label: Int, amount: CircleDiagram.Amount)] = []
        var alongLines: [(label: Int, amount: CircleDiagram.Amount, unit: String)] = []
        for (index, label) in labels.enumerated() {
            let text = label.text
            // A speck: what's left of an arc, or of a dot.
            if tall(label) < tallest * 0.6 { continue }
            // A length written along a line: "9.7 m", "35 km". (Before "8m" is taken for
            // eight times an angle m.)
            if !label.hasDegree, let length = length(text) {
                alongLines.append((index, length.amount, length.unit))
                continue
            }
            let out = out(CGPoint(x: label.box.midX, y: label.box.midY))
            let glyphTall = Double(label.blobs.map(\.height).max() ?? 0)
            if ["(", ")", "()"].contains(label.text.trimmingCharacters(in: .whitespaces)) || ["0", "Q"].contains(text), !label.hasDegree, label.blobs.count == 1 {
                // A ring on its own is the letter O, by the middle or by a point; text
                // recognition takes a thin italic one for a nought or half of one.
                if text != "Q" || (hasCircle && out <= r * 0.35) { names.append((index, "O")) } else { names.append((index, text)) }
            } else if let number = Double(text), number > 0, number < 360, text.allSatisfy({ $0.isNumber || $0 == "." }) {
                // Without a circle, a number has to have its degree sign: tables and charts
                // are lines with numbers by them too.
                if hasCircle || label.hasDegree { amounts.append((index, .number(number))) }
            } else if text.count == 1, let letter = text.first, "abcdefghijklmnopqrstuvwxyzθαβ".contains(letter.lowercased()) {
                // A point's letter or an unknown angle? Capitals name points, but text
                // recognition can't tell C from c or X from x, so where it is decides: a
                // point's letter is outside the circle or right by the middle; an angle's is
                // inside, in the angle.
                let nearMiddle = out <= max(r * 0.3, tallest * 1.6)
                var isName = letter.isUppercase
                let lower = Character(letter.lowercased())
                if "o".contains(lower) {
                    isName = true
                } else if "xyz".contains(lower) {
                    isName = hasCircle && out >= r * 1.02
                } else if !hasCircle, "csuvwkp".contains(lower) {
                    // With no circle to go by, the size of the letter.
                    isName = glyphTall >= tallest * 0.86
                } else if "csuvwkp".contains(lower) {
                    let middleIsNamed = labels.enumerated().contains { other in
                        other.offset != index && ["O", "o", "0"].contains(other.element.text)
                            && hypot(other.element.box.midX - centre.x, other.element.box.midY - centre.y) <= max(r * 0.3, tallest * 1.6)
                    }
                    isName = out >= r * 0.97 || (nearMiddle && !middleIsNamed && glyphTall >= tallest * 0.75)
                }
                if label.hasDegree { isName = false }
                if isName {
                    names.append((index, text.uppercased()))
                } else {
                    amounts.append((index, .letter(text.lowercased())))
                }
            } else if let amount = expression(text) {
                amounts.append((index, amount))
            }
        }
        // Each letter goes to the nearest point that hasn't one.
        var pairs: [(distance: Double, label: Int, vertex: Int)] = []
        for (index, name) in names.enumerated() {
            let middle = CGPoint(x: labels[name.label].box.midX, y: labels[name.label].box.midY)
            for vertex in used {
                let apart = hypot(vertices[vertex].point.x - middle.x, vertices[vertex].point.y - middle.y)
                if apart <= max(r * 0.26, tallest * 2) { pairs.append((apart, index, vertex)) }
            }
        }
        pairs.sort { $0.distance < $1.distance }
        var named: Set<Int> = []
        for pair in pairs where !named.contains(pair.label) && vertices[pair.vertex].name == nil {
            vertices[pair.vertex].name = names[pair.label].letter
            named.insert(pair.label)
        }

        // The diagram so far, across and up from the middle of the circle.
        let order = used.sorted()
        var renumbered: [Int: Int] = [:]
        for (index, vertex) in order.enumerated() { renumbered[vertex] = index }
        var diagram = CircleDiagram(
            points: order.map { CircleDiagram.Point(name: vertices[$0].name, x: vertices[$0].point.x - centre.x, y: centre.y - vertices[$0].point.y, place: vertices[$0].place) },
            lines: lines.map { CircleDiagram.Line(points: $0.points.compactMap { renumbered[$0] }, tangentAt: $0.tangentAt.flatMap { renumbered[$0] }) },
            marks: [])
        trace?.pointee.points += order.map { (vertices[$0].point, (vertices[$0].name ?? "·") + " \(vertices[$0].place)") }

        // Each length goes with the stretch of line it's written beside: between two points
        // of one line, about half way along.
        var beside: [[Int]: (cost: Double, amount: CircleDiagram.Amount)] = [:]
        for item in alongLines {
            let label = labels[item.label]
            let middle = CGPoint(x: label.box.midX, y: label.box.midY)
            var best: (cost: Double, key: [Int])?
            for line in lines {
                for (place, p) in line.points.enumerated() {
                    for q in line.points[(place + 1)...] {
                        guard let first = renumbered[p], let second = renumbered[q] else { continue }
                        let a = vertices[p].point, b = vertices[q].point
                        let long = hypot(b.x - a.x, b.y - a.y)
                        guard long > 1 else { continue }
                        let along = ((middle.x - a.x) * (b.x - a.x) + (middle.y - a.y) * (b.y - a.y)) / (long * long)
                        let off = abs((middle.x - a.x) * (b.y - a.y) - (middle.y - a.y) * (b.x - a.x)) / long
                        guard along > 0.12, along < 0.88, off <= Double(label.box.width) / 2 + tallest * 2.5 else { continue }
                        let cost = off + abs(along - 0.5) * long * 0.6
                        if cost < (best?.cost ?? .infinity) { best = (cost, [min(first, second), max(first, second)]) }
                    }
                }
            }
            guard let best else {
                note("no line for \(label.text)")
                continue
            }
            if best.cost < (beside[best.key]?.cost ?? .infinity) { beside[best.key] = (best.cost, item.amount) }
            if diagram.unit == nil { diagram.unit = item.unit }
        }
        diagram.lengths = beside.sorted { ($0.key[0], $0.key[1]) < ($1.key[0], $1.key[1]) }.map { .init(a: $0.key[0], b: $0.key[1], amount: $0.value.amount) }

        // Each number or letter goes in the angle it's written in: at a point near it,
        // between the two lines either side of it.
        var costs: [Double] = []
        for item in amounts {
            let label = labels[item.label]
            let middle = CGPoint(x: label.box.midX - centre.x, y: centre.y - label.box.midY)
            var best: (cost: Double, mark: CircleDiagram.Mark)?
            for (index, point) in diagram.points.enumerated() {
                let apart = hypot(middle.x - point.x, middle.y - point.y)
                guard apart <= r * (point.place == .outside ? 0.9 : 0.62), apart > 1 else { continue }
                // An angle's number is inside the circle, or by a point outside it.
                if hasCircle, hypot(middle.x, middle.y) > r * 1.04, point.place != .outside { continue }
                let around = diagram.directions(at: index)
                guard around.count >= 2 else { continue }
                var towards = atan2(middle.y - point.y, middle.x - point.x)
                if towards < around[0].direction { towards += 2 * .pi }
                let after = around.lastIndex { $0.direction <= towards } ?? around.count - 1
                let next = (after + 1) % around.count
                var size = (around[next].direction - around[after].direction) * 180 / .pi
                if size <= 0 { size += 360 }
                var cost = apart / r
                // Where it sits in the angle: by one of the lines is less likely than in the middle.
                var inFromFirst = (towards - around[after].direction) * 180 / .pi
                if inFromFirst < 0 { inFromFirst += 360 }
                let edge = min(inFromFirst, size - inFromFirst)
                if edge < 6 { cost += 0.15 }
                if item.amount.isNumber {
                    let off = abs(item.amount.constant - size)
                    cost += off / 120
                    if off > 45 { cost += 0.6 }
                } else if size > 200 {
                    cost += 0.5
                }
                // An arc drawn across the angle there.
                let direction = atan2(middle.y - point.y, middle.x - point.x)
                // What's written goes just outside its arc, or inside a big one.
                if arcs.contains(where: { arc in
                    guard renumbered[arc.vertex] == index, apart <= arc.radius + tallest * 2.8 else { return false }
                    var d = direction
                    while d < arc.from - 0.2 { d += 2 * .pi }
                    return d <= arc.to + 0.2
                }) { cost -= 0.2 }
                if cost < (best?.cost ?? 1.0) {
                    best = (cost, CircleDiagram.Mark(vertex: index, from: around[after].towards, to: around[next].towards, amount: item.amount))
                }
            }
            if let best {
                // One thing to an angle. A number is surer than a letter, which a stray mark
                // can pass for; of two letters, the one that sits better in the angle. Two
                // numbers can't be told apart.
                if let clash = diagram.marks.firstIndex(where: { $0.vertex == best.mark.vertex && $0.from == best.mark.from && $0.to == best.mark.to }) {
                    note("two labels in one angle: \(label.text)")
                    let other = diagram.marks[clash]
                    if other.amount.isNumber, best.mark.amount.isNumber { return nil }
                    if best.mark.amount.isNumber != other.amount.isNumber ? best.mark.amount.isNumber : best.cost < costs[clash] {
                        diagram.marks[clash] = best.mark
                        costs[clash] = best.cost
                    }
                    continue
                }
                diagram.marks.append(best.mark)
                costs.append(best.cost)
            } else {
                note("no angle for \(label.text)")
                // A letter in no angle, written beside a stretch of line, is that length: the side marked x.
                if item.amount.letters.count == 1, item.amount.constant == 0, !item.amount.isNumber, item.amount.letters.values.first == 1 {
                    let middle = CGPoint(x: label.box.midX, y: label.box.midY)
                    var best: (cost: Double, key: [Int])?
                    for line in lines {
                        for (place, p) in line.points.enumerated() {
                            for q in line.points[(place + 1)...] {
                                guard let first = renumbered[p], let second = renumbered[q] else { continue }
                                let a = vertices[p].point, b = vertices[q].point
                                let long = hypot(b.x - a.x, b.y - a.y)
                                guard long > 1 else { continue }
                                let along = ((middle.x - a.x) * (b.x - a.x) + (middle.y - a.y) * (b.y - a.y)) / (long * long)
                                let off = abs((middle.x - a.x) * (b.y - a.y) - (middle.y - a.y) * (b.x - a.x)) / long
                                guard along > 0.25, along < 0.75, off <= Double(label.box.width) / 2 + tallest * 1.8 else { continue }
                                let cost = off + abs(along - 0.5) * long * 0.6
                                if cost < (best?.cost ?? .infinity) { best = (cost, [min(first, second), max(first, second)]) }
                            }
                        }
                    }
                    if let best, !diagram.lengths.contains(where: { [min($0.a, $0.b), max($0.a, $0.b)] == best.key }) {
                        diagram.lengths.append(.init(a: best.key[0], b: best.key[1], amount: item.amount))
                    }
                }
            }
        }
        // Without a circle there has to be an angle with its size written in it: squares
        // and letters alone are in any drawing of boxes.
        // (Or points with letters, for a question whose words give the angles.)
        if !hasCircle, !diagram.marks.contains(where: { $0.amount.isNumber }), diagram.points.filter({ $0.name != nil }).count < 3 { return nil }
        for square in rightAngles {
            guard let index = renumbered[square.vertex] else { continue }
            let around = diagram.directions(at: index)
            guard around.count >= 2 else { continue }
            var towards = square.towards
            while towards < around[0].direction { towards += 2 * .pi }
            while towards >= around[0].direction + 2 * .pi { towards -= 2 * .pi }
            let after = around.lastIndex { $0.direction <= towards } ?? around.count - 1
            let next = (after + 1) % around.count
            let mark = CircleDiagram.Mark(vertex: index, from: around[after].towards, to: around[next].towards, amount: .number(90))
            if let clash = diagram.marks.first(where: { $0.vertex == mark.vertex && $0.from == mark.from && $0.to == mark.to }) {
                if clash.amount != .number(90) { return nil }
            } else {
                diagram.marks.append(mark)
            }
        }
        // A circle diagram with nothing written in its angles still counts: exam questions
        // give them in words. Its points need letters for that.
        guard !diagram.marks.isEmpty || diagram.points.filter({ $0.name != nil }).count >= 3 else { return nil }
        return (diagram, order)
    }

    /// "9.7 m", "35km", "x cm": a length, and what it's measured in.
    private static func length(_ text: String) -> (amount: CircleDiagram.Amount, unit: String)? {
        let tidy = text.replacingOccurrences(of: " ", with: "").lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"^(?:(\d+(?:\.\d+)?)(mm|cm|km|m|miles?|in|ft|yd)|([a-z])(mm|cm|km))\.?$"#),
              let match = regex.firstMatch(in: tidy, range: NSRange(tidy.startIndex..., in: tidy)) else { return nil }
        func part(_ index: Int) -> String? { Range(match.range(at: index), in: tidy).map { String(tidy[$0]) } }
        if let number = part(1).flatMap(Double.init), number > 0, let unit = part(2) { return (.number(number), unit == "mile" ? "miles" : unit) }
        if let letter = part(3), let unit = part(4) { return (.letter(letter), unit) }
        return nil
    }

    /// 2x, x + 20, 3y − 10: a letter with a number in front, and one added or taken away.
    private static func expression(_ text: String) -> CircleDiagram.Amount? {
        let tidy = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "()°"))
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+(?:\.\d+)?)?([a-zθαβ])(?:([+-])(\d+(?:\.\d+)?))?$"#),
              let match = regex.firstMatch(in: tidy, range: NSRange(tidy.startIndex..., in: tidy)) else { return nil }
        func part(_ index: Int) -> String? { Range(match.range(at: index), in: tidy).map { String(tidy[$0]) } }
        guard let letter = part(2) else { return nil }
        var amount = CircleDiagram.Amount.letter(letter, times: part(1).flatMap(Double.init) ?? 1)
        if let sign = part(3), let number = part(4).flatMap(Double.init) { amount.constant = sign == "-" ? -number : number }
        return amount
    }

    // MARK: Triangles

    /// The straight lines in a piece of ink: the line the most ink lies along, then the
    /// next, each fitted to the middle of its longest unbroken stretch.
    private static func straightLines(in piece: Piece, _ ink: [Bool], width: Int, height: Int) -> [Segment] {
        let span = Double(max(piece.x1 - piece.x0, piece.y1 - piece.y0))
        let midX = Double(piece.x0 + piece.x1) / 2, midY = Double(piece.y0 + piece.y1) / 2
        let points = piece.pixels.map { (x: Double(Int($0) % width) - midX, y: Double(Int($0) / width) - midY) }
        let steps = 360
        let cosines = (0..<steps).map { cos(Double($0) * .pi / Double(steps)) }, sines = (0..<steps).map { sin(Double($0) * .pi / Double(steps)) }
        let far = Int(span) + 2
        let bins = 2 * far + 1
        var votes = [Int32](repeating: 0, count: steps * bins)
        var claimed = [Bool](repeating: false, count: points.count)
        func vote(_ point: (x: Double, y: Double), _ amount: Int32) {
            for step in 0..<steps {
                let offset = Int((point.x * cosines[step] + point.y * sines[step]).rounded()) + far
                if offset >= 0, offset < bins { votes[step * bins + offset] += amount }
            }
        }
        points.forEach { vote($0, 1) }
        let shortest = max(18, span * 0.1)
        var segments: [Segment] = []
        var misses = 0
        while segments.count < 14, misses < 24 {
            var top: Int32 = 0, at = 0
            for index in votes.indices where votes[index] > top {
                top = votes[index]
                at = index
            }
            guard Double(top) >= shortest * 0.8 else { break }
            let step = at / bins, offset = Double(at % bins - far)
            var nx = cosines[step], ny = sines[step], px = nx * offset, py = ny * offset
            for slack in [2.5, 1.8, 1.5] {
                let ax = -ny, ay = nx
                var near: [(t: Double, x: Double, y: Double)] = []
                for (index, point) in points.enumerated() where !claimed[index] && abs((point.x - px) * nx + (point.y - py) * ny) <= slack {
                    near.append(((point.x - px) * ax + (point.y - py) * ay, point.x, point.y))
                }
                guard near.count >= 6 else { break }
                near.sort { $0.t < $1.t }
                var best = 0..<0, start = 0
                for index in 1...near.count where index == near.count || near[index].t - near[index - 1].t > 4.5 {
                    if near[index - 1].t - near[start].t > (best.isEmpty ? -1 : near[best.upperBound - 1].t - near[best.lowerBound].t) { best = start..<index }
                    start = index
                }
                guard !best.isEmpty else { break }
                let low = near[best.lowerBound].t, high = near[best.upperBound - 1].t
                let trim = (high - low) * 0.1
                var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0, n = 0.0
                for item in near[best] where item.t >= low + trim && item.t <= high - trim {
                    sx += item.x; sy += item.y; sxx += item.x * item.x; sxy += item.x * item.y; syy += item.y * item.y; n += 1
                }
                guard n >= 6 else { break }
                let mx = sx / n, my = sy / n
                let angle = 0.5 * atan2(2 * (sxy / n - mx * my), (sxx / n - mx * mx) - (syy / n - my * my))
                px = mx; py = my
                nx = -sin(angle); ny = cos(angle)
            }
            let dx = -ny, dy = nx
            var along: [(t: Double, index: Int)] = []
            for (index, point) in points.enumerated() where abs((point.x - px) * nx + (point.y - py) * ny) <= 1.8 {
                along.append(((point.x - px) * dx + (point.y - py) * dy, index))
            }
            along.sort { $0.t < $1.t }
            var accepted: [Segment] = []
            var start = 0
            for index in 0...along.count where index == along.count || (index > start && along[index].t - along[index - 1].t > 4.5) {
                let run = along[start..<index]
                start = index
                guard let first = run.first, let last = run.last else { continue }
                let length = last.t - first.t
                let fresh = run.filter { !claimed[$0.index] }
                guard length >= shortest, Double(fresh.count) >= length * 0.6 else { continue }
                // Straight, not a shallow curve.
                var sums = [0.0, 0.0, 0.0], counts = [0.0, 0.0, 0.0]
                for item in fresh {
                    let third = min(Int((item.t - first.t) / max(length, 1) * 3), 2)
                    sums[third] += (points[item.index].x - px) * nx + (points[item.index].y - py) * ny
                    counts[third] += 1
                }
                if counts.allSatisfy({ $0 > 0 }), abs(sums[1] / counts[1] - (sums[0] / counts[0] + sums[2] / counts[2]) / 2) > 0.7 { continue }
                // How wide its ink is, across the middle of it.
                var widths: [Int] = []
                for part in 2...8 {
                    let t = first.t + length * Double(part) / 10
                    let ax = px + dx * t + midX, ay = py + dy * t + midY
                    func isInk(_ offset: Double) -> Bool {
                        let x = Int((ax + nx * offset).rounded()), y = Int((ay + ny * offset).rounded())
                        return x >= 0 && x < width && y >= 0 && y < height && ink[y * width + x]
                    }
                    guard isInk(0) else { continue }
                    var across = 1
                    for side in [1.0, -1.0] {
                        var offset = 1.0
                        while offset <= 12, isInk(offset * side) {
                            across += 1
                            offset += 1
                        }
                    }
                    widths.append(across)
                }
                widths.sort()
                accepted.append(Segment(x: px + midX, y: py + midY, dx: dx, dy: dy, from: first.t, to: last.t,
                                        thickness: min(max(Double(run.count) / max(length, 1), 1), 10), width: widths.isEmpty ? 3 : widths[widths.count / 2]))
            }
            if accepted.isEmpty {
                misses += 1
                for ds in -2...2 {
                    for d in -3...3 {
                        let s = (step + ds + steps) % steps, o = at % bins + d
                        if o >= 0, o < bins { votes[s * bins + o] = 0 }
                    }
                }
                continue
            }
            let reachAcross = (accepted.map { max($0.thickness, Double($0.width)) }.max() ?? 3) / 2 + 2.5
            for (index, point) in points.enumerated() where !claimed[index] && abs((point.x - px) * nx + (point.y - py) * ny) <= reachAcross {
                let t = (point.x - px) * dx + (point.y - py) * dy
                if accepted.contains(where: { t >= $0.from - 7 && t <= $0.to + 7 }) {
                    claimed[index] = true
                    vote(point, -1)
                }
            }
            segments += accepted
        }
        // One line found in pieces, or twice side by side, is one line.
        var merged: [Segment] = []
        for segment in segments {
            let ends = [segment.point(segment.from), segment.point(segment.to)]
            if merged.contains(where: { other in
                let middle = other.along(segment.point((segment.from + segment.to) / 2))
                return abs(other.dx * segment.dy - other.dy * segment.dx) < 0.1 && ends.allSatisfy { other.distance($0) < max(6, span * 0.03) }
                    && middle > other.from && middle < other.to && !(ends.allSatisfy { other.distance($0) < 3.5 } && abs(other.dx * segment.dy - other.dy * segment.dx) < 0.035)
            }) { continue }
            if let index = merged.firstIndex(where: { other in
                abs(other.dx * segment.dy - other.dy * segment.dx) < 0.035 && ends.allSatisfy { other.distance($0) < 3.5 }
                    && ends.map { other.along($0) }.max()! > other.from - span * 0.1 && ends.map { other.along($0) }.min()! < other.to + span * 0.1
            }) {
                let a = merged[index].along(ends[0]), b = merged[index].along(ends[1])
                merged[index].from = min(merged[index].from, a, b)
                merged[index].to = max(merged[index].to, a, b)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    /// A triangle drawn in a piece of ink, with what's written on its sides and in its corners.
    private static func read(triangleIn piece: Piece, _ pixels: Pixels, _ ink: [Bool], trace: UnsafeMutablePointer<Trace>?) -> Found? {
        let width = pixels.width, height = pixels.height
        let segments = straightLines(in: piece, ink, width: width, height: height)
        guard segments.count >= 3, segments.count <= 9 else { return nil }
        func crossing(_ a: Segment, _ b: Segment) -> CGPoint? {
            let cross = a.dx * b.dy - a.dy * b.dx
            guard abs(cross) > 0.2 else { return nil }
            return a.point(((b.x - a.x) * b.dy - (b.y - a.y) * b.dx) / cross)
        }
        func isOn(_ segment: Segment, _ point: CGPoint) -> Bool {
            let slack = max(8, segment.length * 0.08)
            return segment.along(point) >= segment.from - slack && segment.along(point) <= segment.to + slack
        }
        // Three lines that meet each other at three places: the biggest such triangle.
        var best: (area: Double, sides: [Int], corners: [CGPoint])?
        for i in segments.indices {
            for j in segments.indices where j > i {
                for k in segments.indices where k > j {
                    guard let ij = crossing(segments[i], segments[j]), let jk = crossing(segments[j], segments[k]), let ik = crossing(segments[i], segments[k]),
                          isOn(segments[i], ij), isOn(segments[j], ij), isOn(segments[j], jk), isOn(segments[k], jk), isOn(segments[i], ik), isOn(segments[k], ik) else { continue }
                    let area = abs((jk.x - ij.x) * (ik.y - ij.y) - (ik.x - ij.x) * (jk.y - ij.y)) / 2
                    // Corner 0 is opposite side i, and so on.
                    if area > (best?.area ?? 0) { best = (area, [i, j, k], [jk, ik, ij]) }
                }
            }
        }
        func stop(_ why: String) -> Found? {
            trace?.pointee.notes.append("triangle at \(piece.x0),\(piece.y0): \(why)")
            return nil
        }
        guard let triangle = best else { return nil }
        let corners = triangle.corners
        func length(_ side: Int) -> Double {
            let ends = (0..<3).filter { $0 != side }.map { corners[$0] }
            return hypot(ends[0].x - ends[1].x, ends[0].y - ends[1].y)
        }
        let longest = (0..<3).map(length).max() ?? 0, smallest = (0..<3).map(length).min() ?? 0
        guard smallest >= 40, triangle.area * 2 / longest >= max(24, longest * 0.1) else { return nil }
        func isInside(_ point: CGPoint, margin: Double = 0) -> Bool {
            var signs: [Double] = []
            for index in 0..<3 {
                let a = corners[index], b = corners[(index + 1) % 3], c = corners[(index + 2) % 3]
                let side = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                let whole = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                signs.append(side / whole * abs(whole) / max(hypot(b.x - a.x, b.y - a.y), 1))
            }
            return signs.allSatisfy { $0 >= -margin }
        }
        // Another line across it or up to it makes it more than a triangle: left alone, so
        // an angle isn't put in the wrong part.
        // (A line across it ends on its sides; a row of writing that lines up doesn't.)
        let sides = triangle.sides.map { segments[$0] }
        func isOnASide(_ point: CGPoint) -> Bool {
            sides.contains { $0.distance(point) <= max(7, longest * 0.03) && $0.along(point) >= $0.from - 8 && $0.along(point) <= $0.to + 8 }
        }
        for (index, segment) in segments.enumerated() where !triangle.sides.contains(index) && segment.length >= longest * 0.15 {
            let ends = [segment.point(segment.from), segment.point(segment.to)]
            // (A thick arc across one corner lies along a line for a little way too.)
            if corners.contains(where: { corner in ends.allSatisfy { hypot($0.x - corner.x, $0.y - corner.y) <= longest * 0.3 } }) { continue }
            if ends.allSatisfy(isOnASide), isInside(segment.point((segment.from + segment.to) / 2), margin: 4) { return stop("a line across it") }
        }

        // The part of the picture its labels could be in.
        let reach = max(60, longest * 0.45)
        let x0 = max(Int((corners.map(\.x).min() ?? 0) - reach), 0), x1 = min(Int((corners.map(\.x).max() ?? 0) + reach) + 1, width)
        let y0 = max(Int((corners.map(\.y).min() ?? 0) - reach), 0), y1 = min(Int((corners.map(\.y).max() ?? 0) + reach) + 1, height)
        let w = x1 - x0, h = y1 - y0
        guard w > 20, h > 20 else { return nil }
        func colour(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let at = ((y + y0) * width + x + x0) * 4
            return (Int(pixels.bytes[at]), Int(pixels.bytes[at + 1]), Int(pixels.bytes[at + 2]))
        }
        // Its background: the commonest colour inside it.
        var counts: [Int: Int] = [:]
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) where !ink[(y + y0) * width + x + x0] && isInside(CGPoint(x: x + x0, y: y + y0), margin: -5) {
                let c = colour(x, y)
                counts[(c.0 >> 4) << 8 | (c.1 >> 4) << 4 | c.2 >> 4, default: 0] += 1
            }
        }
        let common = counts.sorted { $0.value > $1.value }.prefix(2)
        guard let first = common.first else { return nil }
        func shade(_ key: Int) -> (Int, Int, Int) { ((key >> 8) << 4 | 8, ((key >> 4) & 15) << 4 | 8, (key & 15) << 4 | 8) }
        var grounds = [shade(first.key)]
        if common.count > 1, let second = common.last, second.value * 6 >= first.value { grounds.append(shade(second.key)) }
        func off(_ x: Int, _ y: Int) -> Int {
            let c = colour(x, y)
            return grounds.map { max(abs(c.0 - $0.0), abs(c.1 - $0.1), abs(c.2 - $0.2)) }.min() ?? 0
        }
        var edge: [Int] = []
        for side in 0..<3 {
            let ends = (0..<3).filter { $0 != side }.map { corners[$0] }
            for part in 2...8 {
                let x = Int((ends[0].x + (ends[1].x - ends[0].x) * Double(part) / 10).rounded()) - x0, y = Int((ends[0].y + (ends[1].y - ends[0].y) * Double(part) / 10).rounded()) - y0
                if x >= 0, x < w, y >= 0, y < h { edge.append(off(x, y)) }
            }
        }
        edge.sort()
        let limit = max(34, (edge.isEmpty ? 100 : edge[edge.count / 2]) * 2 / 5)
        var mark = [Bool](repeating: false, count: w * h)
        var taken = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var nearStroke = false
                for dy in -2...2 where !nearStroke {
                    for dx in -2...2 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && ink[(y + dy + y0) * width + x + dx + x0] {
                        nearStroke = true
                        break
                    }
                }
                guard nearStroke, off(x, y) > limit else { continue }
                // The lines' own ink comes out.
                let point = CGPoint(x: Double(x + x0), y: Double(y + y0))
                if sides.contains(where: { $0.distance(point) <= Double($0.width) / 2 + 2 && $0.along(point) >= $0.from - 3 && $0.along(point) <= $0.to + 3 }) {
                    taken[y * w + x] = true
                } else {
                    mark[y * w + x] = true
                }
            }
        }
        func isMarked(_ point: CGPoint) -> Bool {
            let x = Int(point.x.rounded()) - x0, y = Int(point.y.rounded()) - y0
            for dy in -1...1 {
                for dx in -1...1 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && mark[(y + dy) * w + x + dx] { return true }
            }
            return false
        }
        // The little square in a corner that says it's a right angle, and the arcs.
        var rightAngles: Set<Int> = []
        var arcs: [(corner: Int, radius: Double)] = []
        for corner in 0..<3 {
            let here = corners[corner], others = (0..<3).filter { $0 != corner }.map { corners[$0] }
            let lengths = others.map { hypot($0.x - here.x, $0.y - here.y) }
            let units = zip(others, lengths).map { (x: ($0.x - here.x) / $1, y: ($0.y - here.y) / $1) }
            let half = Double(segments[triangle.sides[(corner + 1) % 3]].width) / 2
            let cosine = units[0].x * units[1].x + units[0].y * units[1].y
            if abs(cosine) < 0.21 {
                var sizes: [Double] = []
                var size = 6.0
                while size <= min(lengths.min()! * 0.3, 60) {
                    var hits = 0, total = 0
                    for (a, b) in [(0, 1), (1, 0)] {
                        var t = half + 3
                        while t <= size {
                            total += 1
                            if isMarked(CGPoint(x: here.x + units[a].x * size + units[b].x * t, y: here.y + units[a].y * size + units[b].y * t)) { hits += 1 }
                            t += 1
                        }
                    }
                    if total >= 6, Double(hits) >= Double(total) * 0.85 { sizes.append(size) }
                    size += 1
                }
                if let biggest = sizes.max(), let least = sizes.min(), biggest - least <= 8 {
                    rightAngles.insert(corner)
                    for y in max(Int(here.y - biggest * 1.5) - y0, 0)..<min(Int(here.y + biggest * 1.5) - y0 + 1, h) {
                        for x in max(Int(here.x - biggest * 1.5) - x0, 0)..<min(Int(here.x + biggest * 1.5) - x0 + 1, w) where mark[y * w + x] {
                            let dx = Double(x + x0) - here.x, dy = Double(y + y0) - here.y
                            let a = dx * units[0].x + dy * units[0].y, b = dx * units[1].x + dy * units[1].y
                            if a >= -2, b >= -2, a <= biggest + 2.5, b <= biggest + 2.5, a >= least - 2.5 || b >= least - 2.5 {
                                mark[y * w + x] = false
                                taken[y * w + x] = true
                            }
                        }
                    }
                }
            }
            let around: [(angle: Double, length: Double, half: Double)] = zip(others, lengths)
                .map { (angle: Double(atan2($0.y - here.y, $0.x - here.x)), length: Double($1), half: half) }.sorted { $0.angle < $1.angle }
            for arc in takeArcs(at: here, between: around, within: longest * 0.3, from: max(6, longest * 0.03), &mark, &taken, x0: x0, y0: y0, w: w, h: h) {
                arcs.append((corner, arc.radius))
            }
        }
        if let trace {
            let grey = mark.map { $0 ? UInt8(0) : UInt8(255) }
            if let provider = CGDataProvider(data: Data(grey) as CFData),
               let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent) { trace.pointee.leftovers.append(image) }
            trace.pointee.segments += (0..<3).map { (corners[($0 + 1) % 3], corners[($0 + 2) % 3]) }
        }
        // Writing.
        var glyphs: [Blob] = [], further: [Blob] = []
        let blobs = joinedUp(mark, w: w, h: h)
        for blob in blobs {
            let middle = CGPoint(x: blob.middle.x + Double(x0), y: blob.middle.y + Double(y0))
            guard blob.pixels.count >= 8, blob.height >= 7, blob.width >= 3, blob.height <= Int(max(longest * 0.3, 34)), blob.width <= Int(max(longest * 0.4, 44)) else { continue }
            if blob.width > blob.height * 5 || (blob.height >= blob.width * 3 && blob.width <= 3) || (blob.height >= blob.width * 5 && blob.width <= 5) { continue }
            if blob.pixels.count * 10 >= blob.width * blob.height * 9, max(blob.width, blob.height) >= min(blob.width, blob.height) * 4 { continue }
            if blob.x0 <= 1 || blob.y0 <= 1 || blob.x1 >= w - 2 || blob.y1 >= h - 2 { continue }
            // A dot on a corner.
            if corners.contains(where: { hypot($0.x - middle.x, $0.y - middle.y) <= 7 }), max(blob.width, blob.height) <= 14 { continue }
            // Only what's written in it or close by it: the next picture along has writing too.
            if !isInside(middle), !sides.contains(where: { side in
                let t = min(max(side.along(middle), side.from), side.to)
                let nearest = side.point(t)
                return hypot(nearest.x - middle.x, nearest.y - middle.y) <= max(longest * 0.22, 56)
            }) {
                further.append(blob)
                continue
            }
            glyphs.append(blob)
        }
        // (And the rest of a number that starts further off than that: the 5 of "5.7cm" where
        // the 7 is close enough. Half a number is another number.)
        var grew = true
        while grew {
            grew = false
            for (index, blob) in further.enumerated().reversed() {
                let joins = glyphs.contains { glyph in
                    let overlap = min(glyph.y1, blob.y1) - max(glyph.y0, blob.y0)
                    let gap = max(glyph.x0, blob.x0) - min(glyph.x1, blob.x1)
                    return overlap * 2 >= min(glyph.height, blob.height) && gap <= max(glyph.height, blob.height) * 9 / 10
                }
                if joins {
                    glyphs.append(blob)
                    further.remove(at: index)
                    grew = true
                }
            }
        }
        var labels = grouped(glyphs, specks: blobs.filter { $0.height < 7 && $0.width <= 9 && $0.pixels.count >= 3 }, x0: x0, y0: y0)
        guard !labels.isEmpty, labels.count <= 30 else { return stop("\(labels.count) labels") }
        if let sheet = read(&labels, pixels, taken: taken, x0: x0, y0: y0, w: w, h: h, keepsWords: true) { trace?.pointee.sheets.append(sheet) }
        trace?.pointee.labels += labels.map { ($0.box, $0.text + ($0.hasDegree ? "°" : "")) }

        // What each label is: a length along a side, an angle in a corner, or a corner's letter.
        func tall(_ label: Label) -> Double { Double(label.blobs.map(\.height).max() ?? 0) }
        let heights = labels.filter { !$0.text.isEmpty }.map(tall).sorted()
        guard !heights.isEmpty else { return nil }
        let usual = heights[heights.count * 7 / 10]
        // Writing too small to read for sure gives answers to some other triangle.
        guard usual >= 11 else { return stop("writing too small") }
        var diagram = TriangleDiagram(corners: corners.map { .init(name: nil, x: $0.x, y: -$0.y, angle: nil) }, sides: [nil, nil, nil], unit: nil)
        for corner in rightAngles { diagram.corners[corner].angle = .number(90) }
        var sideCost = [Double](repeating: .infinity, count: 3), angleCost = [Double](repeating: .infinity, count: 3), nameCost = [Double](repeating: .infinity, count: 3)
        // A number with a unit after it (text recognition often gets only part of the unit), or a letter.
        guard let pattern = try? NSRegularExpression(pattern: #"^(?:(\d+(?:\.\d+)?)\s*([a-zA-Z]{0,3})|([a-zA-Zθαβ])\s*(cm|mm|km|m|in|ft)?)$"#) else { return nil }
        for label in labels where !label.text.isEmpty && tall(label) >= usual * 0.6 {
            // Only what a length or an angle is written with: text recognition adds accents
            // and odd letters to a unit now and then.
            let text = String(label.text.replacingOccurrences(of: "°", with: "").filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || " .θαβ".contains($0) })
                .trimmingCharacters(in: .whitespaces)
            // A unit that came apart from its number says nothing by itself.
            if ["cm", "mm", "km", "m", "in", "ft"].contains(text) { continue }
            guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let valueRange = Range(match.range(at: 1), in: text) ?? Range(match.range(at: 3), in: text) else {
                // Something written that can't be read: a length or an angle may be missing.
                if text.contains(where: \.isNumber) { return stop("can't read \(text)") }
                continue
            }
            var value = String(text[valueRange])
            let written = (Range(match.range(at: 2), in: text) ?? Range(match.range(at: 4), in: text)).map { String(text[$0]).lowercased() } ?? ""
            let unit = ["cm", "mm", "km", "m", "in", "ft"].contains(written) ? written : nil
            // 7x and 10y are lengths in letters, not 7 and 10: nothing here works with those.
            if match.range(at: 1).location != NSNotFound, written.count == 1, "xyzabdnpqtuvw".contains(written) { return stop("a length written with a letter: \(text)") }
            let middle = CGPoint(x: label.box.midX, y: label.box.midY)
            let inside = isInside(middle, margin: 2)
            // A ring on its own in a corner is a theta, which text recognition takes for a nought or an O.
            if inside, unit == nil, !label.hasDegree, ["0", "O", "o", "Θ", "ϴ", "Ø", "ø", "Ө", "ө", "Q"].contains(value) { value = "θ" }
            let cornerAway = corners.map { hypot($0.x - middle.x, $0.y - middle.y) }
            let nearestCorner = (0..<3).min { cornerAway[$0] < cornerAway[$1] } ?? 0
            // How far it is from each side, and how far along.
            var sideAway: [Double] = [], sidePlace: [Double] = []
            for side in 0..<3 {
                let ends = (0..<3).filter { $0 != side }.map { corners[$0] }
                let dx = ends[1].x - ends[0].x, dy = ends[1].y - ends[0].y, whole = dx * dx + dy * dy
                let t = ((middle.x - ends[0].x) * dx + (middle.y - ends[0].y) * dy) / whole
                sidePlace.append(t)
                let clamped = min(max(t, 0), 1)
                sideAway.append(hypot(middle.x - ends[0].x - dx * clamped, middle.y - ends[0].y - dy * clamped))
            }
            let adjacent = (0..<3).filter { $0 != nearestCorner }.map(length).min() ?? longest
            let asAngle = inside ? cornerAway[nearestCorner] / (adjacent * 0.45) : .infinity
            let nearestSide = (0..<3).min { sideAway[$0] / 1 + abs(sidePlace[$0] - 0.5) * longest * 0.3 < sideAway[$1] + abs(sidePlace[$1] - 0.5) * longest * 0.3 } ?? 0
            let asSide = sideAway[nearestSide] / max(longest * 0.14, usual * 2.6) + abs(sidePlace[nearestSide] - 0.5) * 1.3
            let number = Double(value)
            let isCapital = number == nil && value.first!.isUppercase && !"XYZ".contains(value)
            let ambiguous = number == nil && "cosuvwkpCOSUVWKP".contains(value)
            if number == nil, !inside, cornerAway[nearestCorner] <= max(longest * 0.16, usual * 2.4), unit == nil, !label.hasDegree,
               isCapital || (ambiguous && asSide > 0.75) {
                // A corner's letter.
                guard cornerAway[nearestCorner] < nameCost[nearestCorner] else { continue }
                nameCost[nearestCorner] = cornerAway[nearestCorner]
                diagram.corners[nearestCorner].name = value.uppercased()
                continue
            }
            let mark: TriangleDiagram.Mark = number.map { .number($0) } ?? .letter(value == value.uppercased() && value.count == 1 && "XYZ".contains(value) ? value.lowercased() : value)
            let isAngle = unit == nil && (label.hasDegree || "θαβ".contains(value) || asAngle < asSide)
            if isAngle {
                guard asAngle < 1.15 else { continue }
                if let number, number >= 180 { return nil }
                // A right angle already marked isn't labelled again.
                if angleCost[nearestCorner] < .infinity || rightAngles.contains(nearestCorner) { return stop("two angles in one corner: \(text)") }
                angleCost[nearestCorner] = asAngle
                diagram.corners[nearestCorner].angle = mark
            } else {
                guard asSide < 1.3 else { continue }
                if sideCost[nearestSide] < .infinity { return stop("two lengths on one side: \(text)") }
                sideCost[nearestSide] = asSide
                diagram.sides[nearestSide] = mark
                if let unit {
                    if let already = diagram.unit, already != unit { return nil }
                    diagram.unit = unit
                }
            }
        }
        // Enough to go on, and nothing wildly unlike the drawing.
        let given = diagram.corners.compactMap(\.angle).count + diagram.sides.compactMap { $0 }.count
        guard given >= 2 else { return stop("only \(given) given") }
        for corner in 0..<3 {
            guard case .number(let angle) = diagram.corners[corner].angle else { continue }
            let others = (0..<3).filter { $0 != corner }.map { corners[$0] }, here = corners[corner]
            let a = (others[0].x - here.x, others[0].y - here.y), b = (others[1].x - here.x, others[1].y - here.y)
            let drawn = acos(min(max((a.0 * b.0 + a.1 * b.1) / (hypot(a.0, a.1) * hypot(b.0, b.1)), -1), 1)) * 180 / .pi
            if abs(drawn - angle) > 28 { return stop("angle \(angle) drawn as \(Int(drawn))") }
        }
        let lengths = (0..<3).compactMap { side -> Double? in
            if case .number(let value) = diagram.sides[side] { return value / length(side) }
            return nil
        }
        if let least = lengths.min(), let most = lengths.max(), most > least * 2.5 { return stop("lengths unlike the drawing") }
        var box = CGRect(x: corners.map(\.x).min() ?? 0, y: corners.map(\.y).min() ?? 0, width: 0, height: 0)
        for corner in corners { box = box.union(CGRect(x: corner.x - 2, y: corner.y - 2, width: 4, height: 4)) }
        for label in labels where !label.text.isEmpty { box = box.union(label.box) }
        return Found(diagram: .triangle(diagram), box: box.intersection(CGRect(x: 0, y: 0, width: width, height: height)))
    }

    /// A figure of straight lines with no circle: lines across parallel lines, a shape with
    /// its corners marked, a triangle with a line across it.
    private static func read(figureIn piece: Piece, _ pixels: Pixels, _ ink: [Bool], trace: UnsafeMutablePointer<Trace>?) -> Found? {
        let width = pixels.width, height = pixels.height
        let span = Double(max(piece.x1 - piece.x0, piece.y1 - piece.y0))
        func stop(_ why: String) -> Found? {
            trace?.pointee.notes.append("figure at \(piece.x0),\(piece.y0): \(why)")
            return nil
        }
        let found = straightLines(in: piece, ink, width: width, height: height).filter { $0.length >= max(28, span * 0.14) }
        let nearPoint = max(7, span * 0.035), beyond = max(8, span * 0.04)
        // A thick arc across a corner lies along a line for a little way: a short stroke from
        // one line to another, close to where those two meet, isn't one of the figure's lines.
        func cutsACorner(_ stroke: Segment) -> Bool {
            guard stroke.length <= span * 0.3 else { return false }
            let ends: [CGPoint] = [stroke.point(stroke.from), stroke.point(stroke.to)]
            func hosts(_ end: CGPoint) -> [Segment] {
                found.filter { other in
                    let isItself = other.x == stroke.x && other.dx == stroke.dx && other.from == stroke.from
                    let t = other.along(end)
                    return !isItself && other.distance(end) <= nearPoint && t >= other.from - beyond && t <= other.to + beyond
                }
            }
            for a in hosts(ends[0]) {
                for b in hosts(ends[1]) {
                    let cross: Double = a.dx * b.dy - a.dy * b.dx
                    guard abs(cross) > 0.1 else { continue }
                    let along: Double = ((b.x - a.x) * b.dy - (b.y - a.y) * b.dx) / cross
                    let corner = a.point(along)
                    let reach: Double = span * 0.3
                    if hypot(ends[0].x - corner.x, ends[0].y - corner.y) <= reach, hypot(ends[1].x - corner.x, ends[1].y - corner.y) <= reach { return true }
                }
            }
            return false
        }
        var segments = found.filter { !cutsACorner($0) }
        // A letter that sits at the end of a line, in line with it, reads as a little more
        // line. Past the last place another line meets it, a short stretch with ink out to
        // its sides isn't line: it stops where the other line meets it.
        for index in segments.indices {
            let segment = segments[index]
            var meets: [Double] = []
            for (number, other) in segments.enumerated() where number != index {
                let cross = segment.dx * other.dy - segment.dy * other.dx
                guard abs(cross) > 0.1 else { continue }
                let t = ((other.x - segment.x) * other.dy - (other.y - segment.y) * other.dx) / cross
                let u = other.along(segment.point(t))
                if t >= segment.from - beyond, t <= segment.to + beyond, u >= other.from - beyond, u <= other.to + beyond { meets.append(t) }
            }
            guard let first = meets.min(), let last = meets.max() else { continue }
            /// Whether the ink between two places along it spreads out to its sides, as a letter's does.
            func isWriting(_ start: Double, _ end: Double) -> Bool {
                var beside = 0, all = 0
                var spans: [Int] = []
                var t = start
                while t <= end {
                    let on = segment.point(t)
                    var low = 99, high = -99
                    for across in -14...14 {
                        let x = Int((on.x - segment.dy * Double(across)).rounded()), y = Int((on.y + segment.dx * Double(across)).rounded())
                        guard x >= 0, x < width, y >= 0, y < height, ink[y * width + x] else { continue }
                        all += 1
                        low = min(low, across)
                        high = max(high, across)
                        if Double(abs(across)) > Double(segment.width) / 2 + 2.5 { beside += 1 }
                    }
                    if high >= low { spans.append(high - low + 1) }
                    t += 1
                }
                spans.sort()
                // Ink well off to the side, or (a letter the line runs up the middle of) wider than the line for most of the way.
                return all > 0 && (beside * 4 >= all || (spans.count >= 5 && spans[spans.count / 2] >= segment.width + 3))
            }
            let most = max(36, span * 0.09)
            if segment.to - last > 6, segment.to - last <= most, isWriting(last + 3, segment.to) { segments[index].to = last }
            if first - segment.from > 6, first - segment.from <= most, isWriting(segment.from, first - 3) { segments[index].from = first }
        }
        // A figure of lines is nearly all lines. Where much of the ink is something else (a
        // circle that wasn't made out, a curve, a drawing), the lines alone would give
        // answers to a different diagram.
        var explained = 0
        var other: Set<Int32> = []
        for pixel in piece.pixels {
            let point = CGPoint(x: Int(pixel) % width, y: Int(pixel) / width)
            if found.contains(where: { $0.distance(point) <= Double($0.width) / 2 + 3 && $0.along(point) >= $0.from - 4 && $0.along(point) <= $0.to + 4 }) {
                explained += 1
            } else {
                other.insert(pixel)
            }
        }
        guard explained * 100 >= piece.pixels.count * 50 else { return stop("only \(explained * 100 / max(piece.pixels.count, 1))% of it is lines") }
        // The arcs that mark angles, arrowheads and letters are small. One big piece of
        // something else is a curve or a circle.
        var biggest = 0
        var stack: [Int32] = []
        while let start = other.first {
            other.remove(start)
            stack.append(start)
            var x0 = Int(start) % width, x1 = x0, y0 = Int(start) / width, y1 = y0
            while let top = stack.popLast() {
                let x = Int(top) % width, y = Int(top) / width
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for dy in -1...1 {
                    for dx in -1...1 where x + dx >= 0 && x + dx < width && y + dy >= 0 && y + dy < height {
                        let next = Int32((y + dy) * width + x + dx)
                        if other.remove(next) != nil { stack.append(next) }
                    }
                }
            }
            biggest = max(biggest, x1 - x0, y1 - y0)
        }
        guard Double(biggest) <= span * 0.45 else { return stop("something curved in it, \(biggest) across") }
        // Not a table or a box: something in it slants.
        guard segments.count >= 2, segments.count <= 9, segments.contains(where: { abs($0.dx) > 0.06 && abs($0.dy) > 0.06 }) else { return stop("\(segments.count) lines, or none slanted") }
        // Its points: where lines end and where they cross.
        var spots: [(point: CGPoint, isCrossing: Bool)] = []
        for (number, segment) in segments.enumerated() {
            spots.append((segment.point(segment.from), false))
            spots.append((segment.point(segment.to), false))
            for other in segments[(number + 1)...] {
                let cross = segment.dx * other.dy - segment.dy * other.dx
                guard abs(cross) > 0.1 else { continue }
                let t = ((other.x - segment.x) * other.dy - (other.y - segment.y) * other.dx) / cross
                let point = segment.point(t), u = other.along(point)
                if t >= segment.from - beyond, t <= segment.to + beyond, u >= other.from - beyond, u <= other.to + beyond { spots.append((point, true)) }
            }
        }
        guard spots.contains(where: \.isCrossing) else { return stop("no lines cross") }
        var vertices: [Vertex] = []
        var group = [Int](repeating: -1, count: spots.count)
        for index in spots.indices where group[index] < 0 {
            group[index] = vertices.count
            var members = [index]
            var next = 0
            while next < members.count {
                let here = spots[members[next]].point
                for other in spots.indices where group[other] < 0 && hypot(spots[other].point.x - here.x, spots[other].point.y - here.y) <= nearPoint {
                    group[other] = vertices.count
                    members.append(other)
                }
                next += 1
            }
            // Where lines cross is surer than where one seems to end.
            let crossings = members.filter { spots[$0].isCrossing }
            let chosen = (crossings.isEmpty ? members : crossings).map { spots[$0].point }
            vertices.append(Vertex(point: CGPoint(x: chosen.map(\.x).reduce(0, +) / Double(chosen.count), y: chosen.map(\.y).reduce(0, +) / Double(chosen.count)), place: .free))
        }
        var lines: [CircleDiagram.Line] = []
        var lineOf: [Int] = []
        for (number, segment) in segments.enumerated() {
            let on = vertices.indices.filter { index in
                let t = segment.along(vertices[index].point)
                return segment.distance(vertices[index].point) <= nearPoint && t >= segment.from - beyond - nearPoint && t <= segment.to + beyond + nearPoint
            }.sorted { segment.along(vertices[$0].point) < segment.along(vertices[$1].point) }
            guard on.count >= 2 else { continue }
            lines.append(CircleDiagram.Line(points: on, tangentAt: nil))
            lineOf.append(number)
        }
        let used = Set(lines.flatMap(\.points))
        guard lines.count >= 2, used.count >= 3, used.count <= 14 else { return stop("\(lines.count) lines, \(used.count) points") }

        let reach = max(44, span * 0.2)
        let x0 = max(Int(Double(piece.x0) - reach), 0), x1 = min(Int(Double(piece.x1) + reach) + 1, width)
        let y0 = max(Int(Double(piece.y0) - reach), 0), y1 = min(Int(Double(piece.y1) + reach) + 1, height)
        let w = x1 - x0, h = y1 - y0
        guard w > 20, h > 20 else { return nil }
        func colour(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let at = ((y + y0) * width + x + x0) * 4
            return (Int(pixels.bytes[at]), Int(pixels.bytes[at + 1]), Int(pixels.bytes[at + 2]))
        }
        var counts: [Int: Int] = [:]
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) where !ink[(y + y0) * width + x + x0] {
                let c = colour(x, y)
                counts[(c.0 >> 4) << 8 | (c.1 >> 4) << 4 | c.2 >> 4, default: 0] += 1
            }
        }
        let common = counts.sorted { $0.value > $1.value }.prefix(2)
        guard let first = common.first else { return nil }
        func shade(_ key: Int) -> (Int, Int, Int) { ((key >> 8) << 4 | 8, ((key >> 4) & 15) << 4 | 8, (key & 15) << 4 | 8) }
        var grounds = [shade(first.key)]
        if common.count > 1, let second = common.last, second.value * 6 >= first.value { grounds.append(shade(second.key)) }
        func off(_ x: Int, _ y: Int) -> Int {
            let c = colour(x, y)
            return grounds.map { max(abs(c.0 - $0.0), abs(c.1 - $0.1), abs(c.2 - $0.2)) }.min() ?? 0
        }
        var edge: [Int] = []
        for segment in segments {
            for part in 2...8 {
                let point = segment.point(segment.from + segment.length * Double(part) / 10)
                let x = Int(point.x.rounded()) - x0, y = Int(point.y.rounded()) - y0
                if x >= 0, x < w, y >= 0, y < h { edge.append(off(x, y)) }
            }
        }
        edge.sort()
        let limit = max(34, (edge.isEmpty ? 100 : edge[edge.count / 2]) * 2 / 5)
        var mark = [Bool](repeating: false, count: w * h)
        var taken = [Bool](repeating: false, count: w * h)
        var faint = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var nearStroke = false
                for dy in -2...2 where !nearStroke {
                    for dx in -2...2 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && ink[(y + dy + y0) * width + x + dx + x0] {
                        nearStroke = true
                        break
                    }
                }
                guard nearStroke else { continue }
                let darkness = off(x, y)
                guard darkness > max(20, limit * 2 / 5) else { continue }
                let point = CGPoint(x: Double(x + x0), y: Double(y + y0))
                if segments.contains(where: { $0.distance(point) <= Double($0.width) / 2 + 2 && $0.along(point) >= $0.from - 3 && $0.along(point) <= $0.to + 3 }) {
                    if darkness > limit { taken[y * w + x] = true }
                } else {
                    faint[y * w + x] = true
                    if darkness > limit { mark[y * w + x] = true }
                }
            }
        }
        func isMarked(_ point: CGPoint) -> Bool {
            let x = Int(point.x.rounded()) - x0, y = Int(point.y.rounded()) - y0
            for dy in -1...1 {
                for dx in -1...1 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && mark[(y + dy) * w + x + dx] { return true }
            }
            return false
        }
        // At each point: the little squares that mark right angles, and the arcs.
        var arcs: [(vertex: Int, from: Double, to: Double, radius: Double)] = []
        var rightAngles: [(vertex: Int, towards: Double)] = []
        for vertex in used {
            let here = vertices[vertex].point
            var around: [(angle: Double, length: Double, half: Double)] = []
            for (number, line) in lines.enumerated() {
                guard let place = line.points.firstIndex(of: vertex) else { continue }
                for next in [place - 1, place + 1] where line.points.indices.contains(next) {
                    let there = vertices[line.points[next]].point
                    around.append((Double(atan2(there.y - here.y, there.x - here.x)), Double(hypot(there.x - here.x, there.y - here.y)), Double(segments[lineOf[number]].width) / 2))
                }
            }
            guard around.count >= 2 else { continue }
            around.sort { $0.angle < $1.angle }
            for index in around.indices {
                let a = around[index], b = around[(index + 1) % around.count]
                var turn = b.angle - a.angle
                if turn <= 0 { turn += 2 * .pi }
                guard abs(turn - .pi / 2) < 0.21 else { continue }
                let units = [(x: cos(a.angle), y: sin(a.angle)), (x: cos(b.angle), y: sin(b.angle))]
                var sizes: [Double] = []
                var size = 6.0
                while size <= min(min(a.length, b.length) * 0.3, 60) {
                    var hits = 0, total = 0
                    for (p, q) in [(0, 1), (1, 0)] {
                        var t = max(a.half, b.half) + 3
                        while t <= size {
                            total += 1
                            if isMarked(CGPoint(x: here.x + units[p].x * size + units[q].x * t, y: here.y + units[p].y * size + units[q].y * t)) { hits += 1 }
                            t += 1
                        }
                    }
                    if total >= 6, Double(hits) >= Double(total) * 0.85 { sizes.append(size) }
                    size += 1
                }
                guard let biggest = sizes.max(), let least = sizes.min(), biggest - least <= 8 else { continue }
                rightAngles.append((vertex, -(a.angle + turn / 2)))
                for y in max(Int(here.y - biggest * 1.5) - y0, 0)..<min(Int(here.y + biggest * 1.5) - y0 + 1, h) {
                    for x in max(Int(here.x - biggest * 1.5) - x0, 0)..<min(Int(here.x + biggest * 1.5) - x0 + 1, w) where mark[y * w + x] {
                        let dx = Double(x + x0) - here.x, dy = Double(y + y0) - here.y
                        let p = dx * units[0].x + dy * units[0].y, q = dx * units[1].x + dy * units[1].y
                        if p >= -2, q >= -2, p <= biggest + 2.5, q <= biggest + 2.5, p >= least - 2.5 || q >= least - 2.5 {
                            mark[y * w + x] = false
                            taken[y * w + x] = true
                        }
                    }
                }
            }
            for arc in takeArcs(at: here, between: around, within: span * 0.25, from: max(6, span * 0.025), &mark, &taken, faint: faint, x0: x0, y0: y0, w: w, h: h) {
                arcs.append((vertex, arc.from, arc.to, arc.radius))
            }
        }
        if let trace {
            trace.pointee.segments += segments.map { ($0.point($0.from), $0.point($0.to)) }
            trace.pointee.points += used.sorted().map { (vertices[$0].point, "·") }
        }
        let blobs = joinedUp(mark, w: w, h: h)
        // Words of the question that reach into the area round the figure aren't its labels:
        // letters in a row of eight or more, or in a row the edge of the area cuts off.
        // (A label is a letter, a number, a length: "12 miles" at the most.)
        var rows: [(x1: Int, top: Int, bottom: Int, members: [Int], isCut: Bool)] = []
        let lettered = blobs.indices.filter { blobs[$0].height >= 5 && blobs[$0].height <= 34 && blobs[$0].width <= 44 && blobs[$0].pixels.count >= 6 }
            .sorted { blobs[$0].x0 < blobs[$1].x0 }
        for index in lettered {
            let blob = blobs[index]
            let isCut = blob.x0 <= 1 || blob.x1 >= w - 2
            if let row = rows.indices.last(where: {
                blob.x0 - rows[$0].x1 <= max(rows[$0].bottom - rows[$0].top, 12) * 9 / 10 && blob.y0 <= rows[$0].bottom && blob.y1 >= rows[$0].top
            }) {
                rows[row].x1 = max(rows[row].x1, blob.x1)
                rows[row].top = min(rows[row].top, blob.y0)
                rows[row].bottom = max(rows[row].bottom, blob.y1)
                rows[row].members.append(index)
                rows[row].isCut = rows[row].isCut || isCut
            } else {
                rows.append((blob.x1, blob.y0, blob.y1, [index], isCut))
            }
        }
        var inWords: Set<Int> = [], inRow: Set<Int> = []
        for row in rows {
            if row.members.count >= 8 || (row.isCut && row.members.count >= 3) { inWords.formUnion(row.members) }
            if row.members.count >= 3 { inRow.formUnion(row.members) }
        }
        var glyphs: [Blob] = []
        for (number, blob) in blobs.enumerated() {
            if inWords.contains(number) { continue }
            let middle = CGPoint(x: blob.middle.x + Double(x0), y: blob.middle.y + Double(y0))
            guard blob.pixels.count >= 8, blob.height >= 7, blob.width >= 3 || (blob.width >= 2 && inRow.contains(number)), blob.height <= Int(max(span * 0.25, 34)), blob.width <= Int(max(span * 0.35, 44)) else { continue }
            // (A thin upright stroke on its own is a bit of line; among letters it's an i or an l.)
            if blob.width > blob.height * 5 || (!inRow.contains(number) && ((blob.height >= blob.width * 3 && blob.width <= 3) || (blob.height >= blob.width * 5 && blob.width <= 5))) { continue }
            if !inRow.contains(number), blob.pixels.count * 10 >= blob.width * blob.height * 9, max(blob.width, blob.height) >= min(blob.width, blob.height) * 4 { continue }
            if blob.x0 <= 1 || blob.y0 <= 1 || blob.x1 >= w - 2 || blob.y1 >= h - 2 { continue }
            // A dot on a point, or an arrowhead on a line.
            if used.contains(where: { hypot(vertices[$0].point.x - middle.x, vertices[$0].point.y - middle.y) <= 7 }), max(blob.width, blob.height) <= 14 { continue }
            // (Not a degree sign that sits by a line: a little ring, hollow in the middle.)
            let centreIndex = Int32((blob.y0 + blob.y1) / 2 * w + (blob.x0 + blob.x1) / 2)
            let isRing = blob.width >= 5 && blob.height >= 5 && blob.width * 10 <= blob.height * 17 && blob.height * 10 <= blob.width * 17 && !blob.pixels.contains(centreIndex)
            if !isRing, segments.contains(where: { $0.distance(middle) <= Double($0.width) / 2 + 5 && $0.along(middle) >= $0.from - 6 && $0.along(middle) <= $0.to + 6 }),
               max(blob.width, blob.height) <= 16 { continue }
            glyphs.append(blob)
        }
        var labels = grouped(glyphs, specks: blobs.filter { $0.height < 7 && $0.width <= 9 && $0.pixels.count >= 3 }, x0: x0, y0: y0)
        guard !labels.isEmpty, labels.count <= 30 else { return stop("\(labels.count) labels") }
        if let sheet = read(&labels, pixels, taken: taken, x0: x0, y0: y0, w: w, h: h) { trace?.pointee.sheets.append(sheet) }
        trace?.pointee.labels += labels.map { ($0.box, $0.text + ($0.hasDegree ? "°" : "")) }
        // A graph's axes aren't a figure to find angles in: a level line with x written past
        // its end, crossed by an upright one, with y past the end of that, or a letter where
        // they cross (the O), or points written as coordinates.
        func isPast(_ label: Label, _ segment: Segment) -> Bool {
            let middle = CGPoint(x: label.box.midX, y: label.box.midY)
            let along = segment.along(middle)
            guard segment.distance(middle) <= 26 else { return false }
            return (along >= segment.to - 14 && along <= segment.to + 40) || (along <= segment.from + 14 && along >= segment.from - 40)
        }
        for level in segments where abs(level.dy) < 0.06 {
            guard labels.contains(where: { $0.text.lowercased() == "x" && isPast($0, level) }) else { continue }
            for upright in segments where abs(upright.dx) < 0.06 {
                let cross = level.dx * upright.dy - level.dy * upright.dx
                guard abs(cross) > 0.5 else { continue }
                let t = ((upright.x - level.x) * upright.dy - (upright.y - level.y) * upright.dx) / cross
                let origin = level.point(t), u = upright.along(origin)
                guard t >= level.from - 6, t <= level.to + 6, u >= upright.from - 6, u <= upright.to + 6 else { continue }
                let hasY = labels.contains { ["y", ")", "v"].contains($0.text.lowercased()) && isPast($0, upright) }
                let hasOrigin = labels.contains { $0.text.count == 1 && hypot($0.box.midX - origin.x, $0.box.midY - origin.y) <= 34 }
                let hasCoordinates = labels.contains { $0.text.contains("(") && $0.text.contains(where: \.isNumber) }
                if hasY || hasOrigin || hasCoordinates { return stop("a graph's axes") }
            }
        }
        let centre = CGPoint(x: Double(piece.x0 + piece.x1) / 2, y: Double(piece.y0 + piece.y1) / 2)
        guard let made = diagram(vertices, lines, labels, arcs: arcs, rightAngles: rightAngles, centre: centre, r: span / 2, hasCircle: false, trace: trace) else { return stop("labels don't make a diagram") }
        var box = piece.box
        for label in labels where !label.text.isEmpty { box = box.union(label.box) }
        return Found(diagram: .circle(made.diagram), box: box.intersection(CGRect(x: 0, y: 0, width: width, height: height)))
    }

    // MARK: Reading the labels

    /// Reads every label in one go: each is drawn on its own row of a clean sheet, dark on
    /// white, after "N = ". Text recognition makes nonsense of a letter on its own, and
    /// reads it properly with something before it.
    @discardableResult
    private static func read(_ labels: inout [Label], _ pixels: Pixels, taken: [Bool], x0: Int, y0: Int, w: Int, h: Int, keepsWords: Bool = false) -> CGImage? {
        // As big as text recognition likes, going by the usual height of the writing.
        let heights = labels.map { $0.blobs.map(\.height).max() ?? 0 }.filter { $0 >= 9 }.sorted()
        let tallest = max(heights.isEmpty ? 12 : heights[min(heights.count * 7 / 10, heights.count - 1)], 1)
        let scale = min(max(44 / Double(tallest), 1), 6)
        let cap = Double(tallest) * scale
        let row = (cap * 2.4).rounded()
        let font = CTFontCreateWithName("Helvetica" as CFString, cap / 0.717, nil)
        let lead = NSAttributedString(string: "N =", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                  NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
        let leadLine = CTLineCreateWithAttributedString(lead)
        let leadWidth = CTLineGetTypographicBounds(leadLine, nil, nil, nil)
        let widest = labels.map { Double($0.box.width) }.max() ?? 0
        let sheetWidth = Int(leadWidth + cap * 1.2 + widest * scale + cap * 2), sheetHeight = Int(row) * labels.count + Int(row)
        guard let sheet = CGContext(data: nil, width: sheetWidth, height: sheetHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        sheet.setFillColor(CGColor(gray: 1, alpha: 1))
        sheet.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        sheet.interpolationQuality = .high
        let width = pixels.width
        for (number, label) in labels.enumerated() {
            // Too big to be writing: it would run over the rows either side.
            guard label.box.height <= Double(tallest) * 2, label.box.width <= Double(tallest) * 7 else { continue }
            // The label on its own: its ink as dark on white, however it was coloured.
            let bx0 = label.blobs.map(\.x0).min() ?? 0, by0 = label.blobs.map(\.y0).min() ?? 0
            let bx1 = label.blobs.map(\.x1).max() ?? 0, by1 = label.blobs.map(\.y1).max() ?? 0
            let pad = 3
            let cw = bx1 - bx0 + 1 + 2 * pad, ch = by1 - by0 + 1 + 2 * pad
            var own = [Bool](repeating: false, count: cw * ch)
            for blob in label.blobs {
                for pixel in blob.pixels {
                    let x = Int(pixel) % w - bx0 + pad, y = Int(pixel) / w - by0 + pad
                    for dy in -2...2 {
                        for dx in -2...2 where x + dx >= 0 && x + dx < cw && y + dy >= 0 && y + dy < ch {
                            own[(y + dy) * cw + x + dx] = true
                        }
                    }
                }
            }
            // The commonest colour round it is the background.
            var counts: [Int: Int] = [:]
            func colour(_ x: Int, _ y: Int) -> (Int, Int, Int)? {
                let px = x + bx0 - pad + x0, py = y + by0 - pad + y0
                guard px >= 0, px < width, py >= 0, py < pixels.height else { return nil }
                let at = (py * width + px) * 4
                return (Int(pixels.bytes[at]), Int(pixels.bytes[at + 1]), Int(pixels.bytes[at + 2]))
            }
            for y in 0..<ch {
                for x in 0..<cw {
                    guard let c = colour(x, y) else { continue }
                    counts[(c.0 >> 3) << 10 | (c.1 >> 3) << 5 | c.2 >> 3, default: 0] += 1
                }
            }
            let common = counts.max { $0.value < $1.value }?.key ?? 0x7FFF
            let ground = ((common >> 10) << 3 | 4, ((common >> 5) & 31) << 3 | 4, (common & 31) << 3 | 4)
            var darkest = 1
            var shade = [Int](repeating: 0, count: cw * ch)
            for y in 0..<ch {
                for x in 0..<cw where own[y * cw + x] {
                    // Not the edge of a line that runs past.
                    let kx = x + bx0 - pad, ky = y + by0 - pad
                    if kx >= 0, kx < w, ky >= 0, ky < h, taken[ky * w + kx] { continue }
                    guard let c = colour(x, y) else { continue }
                    let off = max(abs(c.0 - ground.0), abs(c.1 - ground.1), abs(c.2 - ground.2))
                    shade[y * cw + x] = off
                    darkest = max(darkest, off)
                }
            }
            var grey = [UInt8](repeating: 255, count: cw * ch)
            for index in shade.indices where shade[index] > 8 {
                grey[index] = UInt8(max(0, 255 - min(255, shade[index] * 290 / darkest)))
            }
            guard let provider = CGDataProvider(data: Data(grey) as CFData),
                  let cut = CGImage(width: cw, height: ch, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: cw, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                                    shouldInterpolate: true, intent: .defaultIntent) else { continue }
            // Rows from the top; the context counts from the bottom.
            let baseline = Double(sheetHeight) - (Double(number) + 1) * row
            sheet.textPosition = CGPoint(x: cap * 0.6, y: baseline)
            CTLineDraw(leadLine, sheet)
            // Sitting on the line the lead is on, the size it is next to the tallest label.
            let drawn = CGRect(x: cap * 0.6 + leadWidth + cap * 0.45, y: baseline - Double(pad) * scale, width: Double(cw) * scale, height: Double(ch) * scale)
            sheet.draw(cut, in: drawn)
        }
        guard let image = sheet.makeImage() else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil, let results = request.results else { return image }
        for observation in results {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            // Normalised, from the bottom.
            let middle = (1 - observation.boundingBox.midY) * Double(sheetHeight)
            let number = Int((middle / row - 0.25).rounded(.down))
            guard labels.indices.contains(number) else { continue }
            var rest = text
            if let range = rest.range(of: #"^\s*[NnMH]\s*[=\-–—:]+\s*"#, options: .regularExpression) { rest.removeSubrange(range) } else if rest.hasPrefix("N") { rest.removeFirst() }
            rest = rest.trimmingCharacters(in: .whitespaces)
            // What a degree sign that wasn't taken off comes out as.
            if rest.hasSuffix("°") || rest.hasSuffix("º") {
                rest.removeLast()
                labels[number].hasDegree = true
            }
            // Letters from other alphabets that look the same, and strokes that aren't letters.
            let alike: [Character: Character] = ["А": "A", "В": "B", "в": "B", "С": "C", "с": "c", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "о": "o",
                                                 "Р": "P", "р": "p", "Т": "T", "Х": "X", "х": "x", "у": "y", "У": "y", "Ү": "y", "γ": "y", "Υ": "y", "а": "a", "е": "e", "Θ": "θ", "ө": "θ", "×": "x", "χ": "x"]
            rest = String(rest.map { alike[$0] ?? $0 }).trimmingCharacters(in: CharacterSet(charactersIn: "|.,'`´:;_~-–—‹›<> "))
            // A speck above or below a letter isn't an accent, and a scrap beside it isn't a letter.
            rest = rest.folding(options: .diacriticInsensitive, locale: nil)
            rest = String(rest.filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || " .°+-−θαβ()".contains($0) }).trimmingCharacters(in: .whitespaces)
            labels[number].text = labels[number].text.isEmpty ? rest : labels[number].text + rest
            // One letter can't read as two: the other is the N it was written after, read out of order.
            if labels[number].blobs.count == 1, labels[number].text.count == 2 {
                let kept = labels[number].text.filter { $0 != "N" }
                if kept.count == 1 { labels[number].text = kept }
            }
        }
        return image
    }
}
