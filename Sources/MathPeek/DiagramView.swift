import SwiftUI

/// A diagram redrawn for the working: the circle or triangle a problem was read from, with
/// its points, its lines, and what's written in its angles and along its sides. Positions are
/// across and up, as the diagram was read.
struct Figure {
    struct Point {
        var name: String
        var x: Double
        var y: Double
    }

    /// An angle at a point: starting along the direction `start` (in radians, anticlockwise
    /// from straight across) and turning anticlockwise through `sweep`.
    struct Corner {
        var vertex: Int
        var start: Double
        var sweep: Double

        func matches(_ other: Corner) -> Bool {
            vertex == other.vertex && abs(sweep - other.sweep) < 0.03 && abs(Figure.turn(start - other.start)) < 0.03
        }
    }

    /// Something written on the diagram: in an angle, or along the line between two points.
    struct Mark {
        var corner: Corner?
        var ends: [Int] = []
        var label: String
        /// The letter the working calls it by, when a letter is all that's written: x.
        var letter: String?
        /// Its size, when it's a number.
        var value: Double?
    }

    /// Something picked out in the picture: an angle or the line between two points, what to
    /// write by it, and whether it's the one being found.
    struct Light {
        var corner: Corner?
        var ends: [Int] = []
        var label: String?
        var isFound: Bool
    }

    var points: [Point]
    var lines: [[Int]]
    var circle: (x: Double, y: Double, radius: Double)?
    /// The circle's centre, if it's one of the points: the only place a reflex angle is worth asking about.
    var centre: Int?
    var marks: [Mark] = []

    /// The diagram a problem was read from, if it was read from one.
    init?(_ kind: ProblemKind) {
        guard case .diagram(let diagram, _) = kind else { return nil }
        switch diagram {
        case .circle(let circle): self.init(circle)
        case .triangle(let triangle): self.init(triangle)
        }
        guard points.count >= 3 else { return nil }
    }

    init(_ diagram: CircleDiagram) {
        let names = Self.names(in: diagram)
        points = diagram.points.enumerated().map { Point(name: names[$0.offset], x: $0.element.x, y: $0.element.y) }
        lines = diagram.lines.map { $0.points.filter(diagram.points.indices.contains) }
        circle = Self.circle(in: diagram)
        centre = diagram.points.firstIndex { $0.place == .centre }
        for mark in diagram.marks where [mark.vertex, mark.from, mark.to].allSatisfy(points.indices.contains) {
            let start = direction(from: mark.vertex, to: mark.from)
            var sweep = Self.turn(direction(from: mark.vertex, to: mark.to) - start)
            if sweep <= 0 { sweep += 2 * .pi }
            marks.append(Mark(corner: Corner(vertex: mark.vertex, start: start, sweep: sweep),
                              label: Format.text(mark.amount.expr) + (mark.amount.isNumber ? "°" : ""),
                              letter: Self.letter(mark.amount), value: mark.amount.isNumber ? mark.amount.constant : nil))
        }
        for length in diagram.lengths where points.indices.contains(length.a) && points.indices.contains(length.b) {
            let unit = length.amount.isNumber ? diagram.unit.map { " " + $0 } ?? "" : ""
            marks.append(Mark(ends: [length.a, length.b], label: Format.text(length.amount.expr) + unit,
                              letter: Self.letter(length.amount), value: length.amount.isNumber ? length.amount.constant : nil))
        }
    }

    init(_ diagram: TriangleDiagram) {
        // Corners with no letter get one, the way the working names them.
        let taken = Set(diagram.corners.compactMap(\.name))
        var spare = ["A", "B", "C", "P", "Q", "R"].filter { !taken.contains($0) }.makeIterator()
        points = diagram.corners.map { Point(name: $0.name ?? spare.next() ?? "?", x: $0.x, y: $0.y) }
        lines = points.count == 3 ? [[0, 1], [1, 2], [2, 0]] : []
        circle = nil
        guard points.count == 3 else { return }
        func written(_ mark: TriangleDiagram.Mark, _ ending: String) -> (label: String, letter: String?, value: Double?) {
            switch mark {
            case .number(let value): (Format.text(CircleDiagram.number(value)) + ending, nil, value)
            case .letter(let letter): (letter, letter, nil)
            }
        }
        for (index, corner) in diagram.corners.enumerated() {
            guard let angle = corner.angle else { continue }
            let others = [0, 1, 2].filter { $0 != index }
            let text = written(angle, "°")
            marks.append(Mark(corner: self.corner(at: index, others[0], others[1]), label: text.label, letter: text.letter, value: text.value))
        }
        // Side 0 is opposite corner 0, and so on.
        for (index, side) in diagram.sides.enumerated() where index < 3 {
            guard let side else { continue }
            let text = written(side, diagram.unit.map { " " + $0 } ?? "")
            marks.append(Mark(ends: [0, 1, 2].filter { $0 != index }, label: text.label, letter: text.letter, value: text.value))
        }
    }

    // MARK: Reading a circle diagram

    /// Every point's name: the letter by it, or the one the working makes up for it. This
    /// follows `CircleTheorems`, which keeps its names to itself: round the circle clockwise
    /// from the top, then the rest.
    private static func names(in diagram: CircleDiagram) -> [String] {
        var names = diagram.points.map { $0.name ?? "" }
        var taken = Set(names)
        var spare = ["P", "Q", "R", "S", "T", "U", "V", "W", "K", "L", "M", "N", "E", "F", "G", "H", "J"]
            .filter { !taken.contains($0) }.makeIterator()
        var middle = (x: 0.0, y: 0.0)
        if let centre = diagram.points.first(where: { $0.place == .centre }) {
            middle = (centre.x, centre.y)
        } else {
            let around = diagram.points.filter { $0.place == .onCircle }
            let all = around.isEmpty ? diagram.points : around
            middle = (all.map(\.x).reduce(0, +) / Double(max(all.count, 1)), all.map(\.y).reduce(0, +) / Double(max(all.count, 1)))
        }
        func clockwise(_ index: Int) -> Double {
            let point = diagram.points[index]
            let angle = atan2(point.x - middle.x, point.y - middle.y)
            return angle < 0 ? angle + 2 * .pi : angle
        }
        let unnamed = diagram.points.indices.filter { names[$0].isEmpty }
        let ordered = unnamed.filter { diagram.points[$0].place == .onCircle }.sorted { clockwise($0) < clockwise($1) }
            + unnamed.filter { diagram.points[$0].place != .onCircle }
        for index in ordered {
            if diagram.points[index].place == .centre, !taken.contains("O") {
                names[index] = "O"
            } else {
                names[index] = spare.next() ?? "X\(index)"
            }
            taken.insert(names[index])
        }
        return names
    }

    /// The circle: round its centre if that's a point, or else the one that best fits the
    /// points on it. None for a figure that has no circle.
    private static func circle(in diagram: CircleDiagram) -> (x: Double, y: Double, radius: Double)? {
        let around = diagram.points.filter { $0.place == .onCircle }
        if let centre = diagram.points.first(where: { $0.place == .centre }) {
            guard !around.isEmpty else { return nil }
            let radius = around.map { hypot($0.x - centre.x, $0.y - centre.y) }.reduce(0, +) / Double(around.count)
            return radius > 0 ? (centre.x, centre.y, radius) : nil
        }
        if around.count == 2 {
            // Too few to place it: taken as the ends of a diameter.
            let x = (around[0].x + around[1].x) / 2, y = (around[0].y + around[1].y) / 2
            return (x, y, hypot(around[0].x - x, around[0].y - y))
        }
        guard around.count >= 3 else { return nil }
        // x² + y² + ax + by + c = 0, fitted to the points.
        var sums = [Double](repeating: 0, count: 12)
        for point in around {
            let x = point.x, y = point.y, z = x * x + y * y
            sums[0] += x * x; sums[1] += x * y; sums[2] += x
            sums[3] += y * y; sums[4] += y; sums[5] += 1
            sums[6] -= x * z; sums[7] -= y * z; sums[8] -= z
        }
        let m = [[sums[0], sums[1], sums[2]], [sums[1], sums[3], sums[4]], [sums[2], sums[4], sums[5]]]
        let right = [sums[6], sums[7], sums[8]]
        func determinant(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let whole = determinant(m)
        guard abs(whole) > 1e-12 else { return nil }
        func solved(_ column: Int) -> Double {
            var replaced = m
            for row in 0..<3 { replaced[row][column] = right[row] }
            return determinant(replaced) / whole
        }
        let a = solved(0), b = solved(1), c = solved(2)
        let squared = a * a / 4 + b * b / 4 - c
        return squared > 0 ? (-a / 2, -b / 2, squared.squareRoot()) : nil
    }

    private static func letter(_ amount: CircleDiagram.Amount) -> String? {
        let letters = amount.letters.filter { abs($0.value) > 1e-9 }
        guard letters.count == 1, let only = letters.first, abs(only.value - 1) < 1e-9, abs(amount.constant) < 1e-9 else { return nil }
        return only.key
    }

    // MARK: Angles

    /// An angle brought into −π...π.
    static func turn(_ angle: Double) -> Double {
        var angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }
        return angle
    }

    func direction(from: Int, to: Int) -> Double {
        atan2(points[to].y - points[from].y, points[to].x - points[from].x)
    }

    /// The angle at `vertex` between the lines towards `a` and `b`: the smaller one, or the
    /// one the long way round if it's a reflex angle.
    func corner(at vertex: Int, _ a: Int, _ b: Int, reflex: Bool = false) -> Corner {
        let first = direction(from: vertex, to: a), second = direction(from: vertex, to: b)
        var sweep = Self.turn(second - first)
        if sweep < 0 { sweep += 2 * .pi }
        if (sweep > .pi) != reflex { return Corner(vertex: vertex, start: second, sweep: 2 * .pi - sweep) }
        return Corner(vertex: vertex, start: first, sweep: sweep)
    }

    private func index(of name: String) -> Int? {
        points.firstIndex { $0.name == name }
    }

    // MARK: What the working is about

    /// What a name in the working points at: "∠BOD", "reflex ∠BOD", "BD", or a letter that's
    /// written on the diagram.
    func light(for name: String, label: String? = nil, isFound: Bool) -> Light? {
        var text = name
        let reflex = text.hasPrefix("reflex ")
        if reflex { text.removeFirst("reflex ".count) }
        if text.hasPrefix("∠") {
            let letters = text.dropFirst().map(String.init)
            guard letters.count == 3, let a = index(of: letters[0]), let vertex = index(of: letters[1]), let b = index(of: letters[2]),
                  a != vertex, b != vertex else { return nil }
            let corner = corner(at: vertex, a, b, reflex: reflex)
            let written = marks.first { $0.corner?.matches(corner) == true }?.label
            return Light(corner: corner, label: label ?? written, isFound: isFound)
        }
        if let mark = marks.first(where: { $0.letter == text }) {
            return Light(corner: mark.corner, ends: mark.ends, label: label ?? mark.label, isFound: isFound)
        }
        let letters = text.map(String.init)
        if letters.count == 2, let a = index(of: letters[0]), let b = index(of: letters[1]), a != b {
            let written = marks.first { Set($0.ends) == [a, b] }?.label
            return Light(ends: [a, b], label: label ?? written, isFound: isFound)
        }
        return nil
    }

    /// What the question asks for.
    func lights(asked name: String) -> [Light] {
        light(for: name, isFound: true).map { [$0] } ?? []
    }

    /// What a step is about: the angles and lengths it works from, and the one it finds.
    /// `earlier` are the steps before it, which say what's been worked out by then.
    func lights(for step: Step, after earlier: [Step]) -> [Light] {
        var known: [String: String] = [:]
        for line in (earlier + [step]).flatMap(\.lines) where line.parts.count == 2 {
            if case .symbol(let name) = line.parts[0], line.parts[1].number != nil {
                known[name] = Format.text(line.parts[1]) + (line.suffix.map { $0 == "°" ? $0 : " " + $0 } ?? "")
            }
        }
        // A step finds what its last line starts with. The first step only says what's given.
        var found: String?
        if step.title != "From the diagram", let last = step.lines.last, case .symbol(let name)? = last.parts.first { found = name }
        var names: [String] = []
        for line in step.lines {
            for name in line.parts.flatMap({ $0.symbols.sorted() }) where !names.contains(name) { names.append(name) }
        }
        var lights = names.filter { $0 != found }.compactMap { light(for: $0, label: known[$0], isFound: false) }
        // Some working has only the numbers ("90 − 25"): then it's the angles found earlier
        // that are those sizes, and the ones those numbers are written in on the diagram.
        if lights.isEmpty, let first = step.lines.first {
            let numbers = first.parts.flatMap(Self.numbers)
            func isUsed(_ value: Double) -> Bool { numbers.contains { abs($0 - value) < 1e-9 } }
            for line in earlier.flatMap(\.lines) where line.parts.count == 2 {
                guard case .symbol(let name) = line.parts[0], name != found, let value = line.parts[1].number?.double, isUsed(value),
                      let light = light(for: name, label: known[name], isFound: false), !lights.contains(where: { same($0, light) }) else { continue }
                lights.append(light)
            }
            for mark in marks where mark.value.map(isUsed) ?? false {
                let light = Light(corner: mark.corner, ends: mark.ends, label: mark.label, isFound: false)
                if !lights.contains(where: { same($0, light) }) { lights.append(light) }
            }
        }
        if let found, let light = light(for: found, label: known[found], isFound: true) {
            lights.removeAll { same($0, light) }
            lights.append(light)
        }
        return lights
    }

    func same(_ a: Light, _ b: Light) -> Bool {
        if let first = a.corner, let second = b.corner { return first.matches(second) }
        return a.corner == nil && b.corner == nil && Set(a.ends) == Set(b.ends)
    }

    private static func numbers(in expr: Expr) -> [Double] {
        switch expr {
        case .number(let value): [value.double]
        case .symbol, .constant: []
        case .add(let parts), .multiply(let parts): parts.flatMap(numbers)
        case .power(let base, let exponent): numbers(in: base) + numbers(in: exponent)
        case .function(_, let argument): numbers(in: argument)
        }
    }
}

/// Draws a figure `side` points across: its circle, lines and letters, with some of its
/// angles and lines picked out.
// MARK: Picking a part of the figure

extension Figure {
    /// An angle or a line of the figure, picked by pointing at it.
    enum Target: Equatable {
        /// At `vertex`, turning anticlockwise from the line towards `from` to the line towards `to`.
        case corner(vertex: Int, from: Int, to: Int)
        /// The line between two points next to each other along it.
        case side(Int, Int)
    }

    /// Lengths can be asked for when the diagram has some written on it.
    var measuresLengths: Bool { marks.contains { $0.ends.count == 2 && $0.value != nil } }

    /// The points next to `vertex` along each line through it, anticlockwise round it.
    func neighbours(of vertex: Int) -> [Int] {
        var found: [Int] = []
        for line in lines {
            guard let place = line.firstIndex(of: vertex) else { continue }
            if place > 0 { found.append(line[place - 1]) }
            if place < line.count - 1 { found.append(line[place + 1]) }
        }
        func turn(_ point: Int) -> Double {
            let angle = direction(from: vertex, to: point)
            return angle < 0 ? angle + 2 * .pi : angle
        }
        return found.sorted { turn($0) < turn($1) }
    }

    /// The farthest point along the line from `vertex` through `point`.
    private func end(from vertex: Int, through point: Int) -> Int {
        guard let line = lines.first(where: { $0.contains(vertex) && $0.contains(point) }),
              let here = line.firstIndex(of: vertex), let there = line.firstIndex(of: point) else { return point }
        return there > here ? line[line.count - 1] : line[0]
    }

    func light(for target: Target, isFound: Bool) -> Light {
        switch target {
        case .corner(let vertex, let from, let to):
            let start = direction(from: vertex, to: from)
            var sweep = Self.turn(direction(from: vertex, to: to) - start)
            if sweep <= 1e-9 { sweep += 2 * .pi }
            let corner = Corner(vertex: vertex, start: start, sweep: sweep)
            let written = marks.first { $0.corner?.matches(corner) == true }?.label
            return Light(corner: corner, label: written, isFound: isFound)
        case .side(let a, let b):
            let written = marks.first { Set($0.ends) == [a, b] }?.label
            return Light(ends: [a, b], label: written, isFound: isFound)
        }
    }

    /// What the working calls it: the letter written in it, or "∠ABC", "reflex ∠ABC", "AB".
    func name(of target: Target) -> String {
        let light = light(for: target, isFound: false)
        if let letter = marks.first(where: { mark in mark.letter != nil && same(light, Light(corner: mark.corner, ends: mark.ends, isFound: false)) })?.letter {
            return letter
        }
        switch target {
        case .corner(let vertex, let from, let to):
            let ends = [points[end(from: vertex, through: from)].name, points[end(from: vertex, through: to)].name].sorted()
            let reflex = (light.corner?.sweep ?? 0) > .pi + 0.01
            return (reflex ? "reflex ∠" : "∠") + ends[0] + points[vertex].name + ends[1]
        case .side(let a, let b):
            return [points[a].name, points[b].name].sorted().joined()
        }
    }

    /// Its size, if it's written on the diagram.
    func given(_ target: Target) -> String? {
        let light = light(for: target, isFound: false)
        return marks.first { $0.value != nil && same(light, Light(corner: $0.corner, ends: $0.ends, isFound: false)) }?.label
    }
}

/// Draws a figure `side` points across: its circle, lines and letters, with some of its
/// angles and lines picked out. With `pick`, its angles (and lines, where lengths are
/// written on it) can be pointed at and clicked.
struct FigureView: View {
    let figure: Figure
    var lights: [Figure.Light] = []
    /// Also draws what's written on the diagram: for the picture of the question itself.
    var showsMarks = false
    let side: CGFloat
    var hovered: Figure.Target?
    var hover: ((Figure.Target?) -> Void)?
    /// A click: on an angle or a line, or on nothing.
    var pick: ((Figure.Target?) -> Void)?

    var body: some View {
        var shown = lights
        if let hovered {
            let light = figure.light(for: hovered, isFound: false)
            if !shown.contains(where: { figure.same($0, light) }) { shown.append(light) }
        }
        let drawing = FigureDrawing(figure: figure, lights: shown, showsMarks: showsMarks, side: side)
        let canvas = Canvas { context, _ in drawing.draw(in: &context) }
            .frame(width: side, height: drawing.height)
            .accessibilityHidden(true)
        if let pick {
            // What's written on the diagram is already known: there's nothing to work out, so
            // it doesn't light up or take a click.
            func target(at spot: CGPoint) -> Figure.Target? {
                drawing.target(at: spot).flatMap { figure.given($0) == nil ? $0 : nil }
            }
            return AnyView(canvas
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let spot): hover?(target(at: spot))
                    case .ended: hover?(nil)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { spot in pick(target(at: spot)) })
        }
        return AnyView(canvas)
    }
}

private struct FigureDrawing {
    let figure: Figure
    let lights: [Figure.Light]
    let showsMarks: Bool
    let side: CGFloat

    /// Sizes are for a picture 250 points across, and follow it up and down.
    private var unit: CGFloat { side / 250 }
    private var margin: CGFloat { 27 * unit }
    private var arc: CGFloat { 21 * unit }

    private static let ink = Color.white.opacity(0.72)
    private static let found = Color(red: 0.3, green: 0.72, blue: 1.0)

    /// What the figure covers, across and up.
    private var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var xs = figure.points.map(\.x), ys = figure.points.map(\.y)
        if let circle = figure.circle {
            xs += [circle.x - circle.radius, circle.x + circle.radius]
            ys += [circle.y - circle.radius, circle.y + circle.radius]
        }
        return (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
    }

    private var scale: CGFloat {
        let box = bounds
        let room = side - 2 * margin
        return min(room / CGFloat(max(box.maxX - box.minX, 1e-6)), room / CGFloat(max(box.maxY - box.minY, 1e-6)))
    }

    var height: CGFloat {
        CGFloat(bounds.maxY - bounds.minY) * scale + 2 * margin
    }

    private func place(_ x: Double, _ y: Double) -> CGPoint {
        let box = bounds
        let across = CGFloat(box.maxX - box.minX) * scale
        return CGPoint(x: (side - across) / 2 + CGFloat(x - box.minX) * scale, y: margin + CGFloat(box.maxY - y) * scale)
    }

    private func place(_ index: Int) -> CGPoint {
        place(figure.points[index].x, figure.points[index].y)
    }

    /// The angle or line at a spot in the picture: a line when the spot is right on one away
    /// from its ends, otherwise the angle at the nearest point, if the spot is close to it.
    func target(at spot: CGPoint) -> Figure.Target? {
        func distance(_ spot: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let squared = max(along.x * along.x + along.y * along.y, 1e-6)
            let t = min(max(((spot.x - a.x) * along.x + (spot.y - a.y) * along.y) / squared, 0), 1)
            return hypot(spot.x - (a.x + along.x * t), spot.y - (a.y + along.y * t))
        }
        var side: (target: Figure.Target, distance: CGFloat)?
        if figure.measuresLengths {
            for line in figure.lines where line.count >= 2 {
                for (a, b) in zip(line, line.dropFirst()) {
                    let start = place(a), end = place(b)
                    let gap = distance(spot, start, end)
                    guard gap < 7 * unit, hypot(spot.x - start.x, spot.y - start.y) > 14 * unit,
                          hypot(spot.x - end.x, spot.y - end.y) > 14 * unit, gap < side?.distance ?? .infinity else { continue }
                    side = (.side(a, b), gap)
                }
            }
        }
        if let side, side.distance < 4 * unit { return side.target }
        // The nearest point with two lines or more leaving it.
        let near = figure.points.indices
            .map { (index: $0, distance: hypot(spot.x - place($0).x, spot.y - place($0).y)) }
            .filter { $0.distance > 2 * unit && $0.distance < 44 * unit && figure.neighbours(of: $0.index).count >= 2 }
            .min { $0.distance < $1.distance }
        if let near {
            let vertex = place(near.index)
            var pointing = atan2(Double(vertex.y - spot.y), Double(spot.x - vertex.x))
            if pointing < 0 { pointing += 2 * .pi }
            let around = figure.neighbours(of: near.index)
            for (index, from) in around.enumerated() {
                let to = around[(index + 1) % around.count]
                var start = figure.direction(from: near.index, to: from), sweep = Figure.turn(figure.direction(from: near.index, to: to) - start)
                if start < 0 { start += 2 * .pi }
                if sweep <= 1e-9 { sweep += 2 * .pi }
                var along = pointing - start
                if along < 0 { along += 2 * .pi }
                // Outside a corner is a reflex angle, which only means something at a centre.
                if along < sweep { return sweep > .pi && near.index != figure.centre ? side?.target : .corner(vertex: near.index, from: from, to: to) }
            }
        }
        return side?.target
    }

    /// `distance` from a point, in a direction given the way the figure's angles are: up is up.
    private func step(from point: CGPoint, towards direction: Double, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + CGFloat(cos(direction)) * distance, y: point.y - CGFloat(sin(direction)) * distance)
    }

    /// The middle of the figure, which letters keep away from.
    private var middle: CGPoint {
        if let circle = figure.circle { return place(circle.x, circle.y) }
        let all = figure.points.indices.map(place)
        return CGPoint(x: all.map(\.x).reduce(0, +) / CGFloat(max(all.count, 1)), y: all.map(\.y).reduce(0, +) / CGFloat(max(all.count, 1)))
    }

    func draw(in context: inout GraphicsContext) {
        let width = max(1, 1.4 * unit)
        if let circle = figure.circle {
            let centre = place(circle.x, circle.y), radius = CGFloat(circle.radius) * scale
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(Self.ink), lineWidth: width)
        }
        // Angles go under the lines, so a filled one doesn't cover them.
        let written = showsMarks ? figure.marks.filter { mark in !lights.contains { light in covers(light, mark) } } : []
        for mark in written { if let corner = mark.corner { draw(corner, label: mark.label, lit: nil, in: &context) } }
        for light in lights { if let corner = light.corner { draw(corner, label: light.label, lit: light.isFound, in: &context) } }

        for line in figure.lines where line.count >= 2 {
            var path = Path()
            path.move(to: place(line[0]))
            path.addLine(to: place(line[line.count - 1]))
            context.stroke(path, with: .color(Self.ink), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        for mark in written where mark.ends.count == 2 { draw(ends: mark.ends, label: mark.label, lit: nil, in: &context) }
        for light in lights where light.ends.count == 2 { draw(ends: light.ends, label: light.label, lit: light.isFound, in: &context) }

        for index in figure.points.indices {
            let point = place(index)
            let dot = 2.3 * unit
            context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white.opacity(0.92)))
            let name = figure.points[index].name
            guard !name.isEmpty else { continue }
            context.draw(Text(name).font(.system(size: max(9.5, 12.5 * unit), weight: .medium)).foregroundStyle(Z.body),
                         at: step(from: point, towards: letterDirection(index), 12.5 * unit))
        }
    }

    private func covers(_ light: Figure.Light, _ mark: Figure.Mark) -> Bool {
        if let a = light.corner, let b = mark.corner { return a.matches(b) }
        return light.ends.count == 2 && Set(light.ends) == Set(mark.ends)
    }

    /// An angle: an arc, or a square for a right angle. `lit` is nil for one that's only
    /// written on the diagram, false for one the step works from, true for the one it finds.
    private func draw(_ corner: Figure.Corner, label: String?, lit: Bool?, in context: inout GraphicsContext) {
        let vertex = place(corner.vertex)
        let color: Color = lit == true ? Self.found : Color.white.opacity(lit == nil ? 0.5 : 0.95)
        let width = max(1, (lit == nil ? 1.1 : 1.6) * unit)
        let isRight = label == "90°" && abs(corner.sweep - .pi / 2) < 0.6
        let radius = corner.sweep > .pi ? arc * 0.62 : arc
        if isRight {
            // Drawn square whatever the diagram's proportions.
            let size = arc * 0.62, end = corner.start + corner.sweep
            let first = step(from: vertex, towards: corner.start, size), second = step(from: vertex, towards: end, size)
            let far = CGPoint(x: first.x + second.x - vertex.x, y: first.y + second.y - vertex.y)
            var path = Path()
            path.move(to: first); path.addLine(to: far); path.addLine(to: second)
            if lit != nil {
                var filled = path
                filled.addLine(to: vertex); filled.closeSubpath()
                context.fill(filled, with: .color(color.opacity(lit == true ? 0.3 : 0.12)))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .miter))
            return
        }
        var path = Path()
        let count = max(Int(corner.sweep / 0.08), 6)
        for index in 0...count {
            let point = step(from: vertex, towards: corner.start + corner.sweep * Double(index) / Double(count), radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if lit != nil {
            var wedge = path
            wedge.addLine(to: vertex); wedge.closeSubpath()
            context.fill(wedge, with: .color(color.opacity(lit == true ? 0.3 : 0.12)))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        guard let label, !label.isEmpty else { return }
        // Its size goes along the middle of the angle, as near the arc as it's clear of the
        // figure's lines: a narrow angle has no room near its point.
        let middle = corner.start + corner.sweep / 2
        let size = max(9, (lit == nil ? 11 : 11.5) * unit)
        let extent = Self.extent(of: label, size: size)
        var spot = step(from: vertex, towards: middle, radius + 11 * unit), clearest = -CGFloat.infinity
        for extra in [11, 15, 20, 26, 33, 41, 50, 60, 72] as [CGFloat] {
            let candidate = step(from: vertex, towards: middle, radius + extra * unit)
            let room = clearance(of: extent, at: candidate)
            if room > clearest { (spot, clearest) = (candidate, room) }
            if room >= 2 * unit { break }
        }
        let text = Text(label).font(.system(size: size, weight: lit == nil ? .regular : .semibold).monospacedDigit())
            .foregroundStyle(lit == true ? Self.found : (lit == nil ? Z.secondary : Z.text))
        context.draw(text, at: spot)
    }

    /// Roughly how much room a label takes.
    private static func extent(of label: String, size: CGFloat) -> CGSize {
        CGSize(width: CGFloat(label.count) * size * 0.6, height: size)
    }

    /// How far a label at `spot` would be from the nearest line, the circle and the edge of
    /// the picture: less than nothing if it would lie across one.
    private func clearance(of extent: CGSize, at spot: CGPoint) -> CGFloat {
        var room = CGFloat.infinity
        for across in [-0.5, 0, 0.5] as [CGFloat] {
            for down in [-0.5, 0.5] as [CGFloat] {
                room = min(room, clearance(at: CGPoint(x: spot.x + across * extent.width, y: spot.y + down * extent.height)))
            }
        }
        return room
    }

    /// How far a spot is from the nearest line, the circle and the edge of the picture.
    private func clearance(at spot: CGPoint) -> CGFloat {
        var room = min(spot.x, side - spot.x, spot.y, height - spot.y)
        if let circle = figure.circle {
            let centre = place(circle.x, circle.y)
            room = min(room, abs(hypot(spot.x - centre.x, spot.y - centre.y) - CGFloat(circle.radius) * scale))
        }
        for line in figure.lines where line.count >= 2 {
            let a = place(line[0]), b = place(line[line.count - 1])
            let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let squared = max(along.x * along.x + along.y * along.y, 1e-6)
            let t = min(max(((spot.x - a.x) * along.x + (spot.y - a.y) * along.y) / squared, 0), 1)
            room = min(room, hypot(spot.x - (a.x + along.x * t), spot.y - (a.y + along.y * t)))
        }
        return room
    }

    /// The line between two points, with what's written along it on the side away from the middle.
    private func draw(ends: [Int], label: String?, lit: Bool?, in context: inout GraphicsContext) {
        let a = place(ends[0]), b = place(ends[1])
        if let lit {
            var path = Path()
            path.move(to: a); path.addLine(to: b)
            context.stroke(path, with: .color(lit ? Self.found : Color.white.opacity(0.95)),
                           style: StrokeStyle(lineWidth: max(1.5, (lit ? 2.6 : 2) * unit), lineCap: .round))
        }
        guard let label, !label.isEmpty else { return }
        let halfway = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let length = max(hypot(b.x - a.x, b.y - a.y), 1)
        var normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        let centre = middle
        if normal.x * (halfway.x - centre.x) + normal.y * (halfway.y - centre.y) < 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let size = max(9, 11 * unit)
        let text = Text(label).font(.system(size: size, weight: lit == nil ? .regular : .semibold).monospacedDigit())
            .foregroundStyle(lit == true ? Self.found : (lit == nil ? Z.secondary : Z.text))
        // Far enough out that the words clear the line, however it slopes.
        let extent = Self.extent(of: label, size: size)
        let reach = 5 * unit + abs(normal.x) * extent.width / 2 + abs(normal.y) * extent.height / 2
        context.draw(text, at: CGPoint(x: halfway.x + normal.x * reach, y: halfway.y + normal.y * reach))
    }

    /// Which way a point's letter goes from it: clear of the lines that leave the point and
    /// of the angles drawn at it, and away from the middle of the figure when it can be.
    private func letterDirection(_ index: Int) -> Double {
        var rays: [Double] = []
        for line in figure.lines {
            guard let position = line.firstIndex(of: index) else { continue }
            if position > 0 { rays.append(figure.direction(from: index, to: line[position - 1])) }
            if position < line.count - 1 { rays.append(figure.direction(from: index, to: line[position + 1])) }
        }
        let drawn = (showsMarks ? figure.marks.compactMap(\.corner) : []) + lights.compactMap(\.corner)
        let corners = drawn.filter { $0.vertex == index }
        let point = place(index), centre = middle
        let offset = CGPoint(x: point.x - centre.x, y: centre.y - point.y)
        let outward: Double? = hypot(offset.x, offset.y) > 2 ? atan2(Double(offset.y), Double(offset.x)) : nil
        var best = outward ?? -.pi / 2, bestScore = -Double.infinity
        for step in 0..<24 {
            let direction = Double(step) * .pi / 12
            var score = rays.map { abs(Figure.turn(direction - $0)) }.min() ?? .pi
            score = min(score, 1.2)
            if let outward { score += 0.5 * cos(direction - outward) }
            if corners.contains(where: { corner in
                var along = Figure.turn(direction - corner.start)
                if along < 0 { along += 2 * .pi }
                return along < corner.sweep
            }) { score -= 2 }
            if score > bestScore { (best, bestScore) = (direction, score) }
        }
        return best
    }
}
