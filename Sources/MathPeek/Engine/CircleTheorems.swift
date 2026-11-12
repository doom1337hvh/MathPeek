import Foundation

/// A circle diagram as it's drawn: its points, the straight lines through them, and what's
/// written in its angles. Positions are across and up, in any unit; only the layout matters
/// (which point is where, and which side of a line another is on), not the sizes, since
/// these diagrams are rarely drawn to scale.
struct CircleDiagram: Sendable {
    /// `free` is a point of a figure with no circle in it.
    enum Place: Sendable { case centre, onCircle, inside, outside, free }

    struct Point: Sendable {
        /// The letter by it, if it has one.
        var name: String?
        var x: Double
        var y: Double
        var place: Place
    }

    /// A straight line, with every point on it in order from one end to the other.
    struct Line: Sendable {
        var points: [Int]
        /// The point where it touches the circle, if it's a tangent.
        var tangentAt: Int?
    }

    /// What's written in an angle: 56, x, 2x + 10.
    struct Amount: Sendable, Equatable {
        var constant: Double = 0
        var letters: [String: Double] = [:]

        static func number(_ value: Double) -> Amount { Amount(constant: value) }
        static func letter(_ name: String, times: Double = 1) -> Amount { Amount(letters: [name: times]) }

        var isNumber: Bool { letters.values.allSatisfy { abs($0) < 1e-9 } }

        static func + (a: Amount, b: Amount) -> Amount {
            var sum = Amount(constant: a.constant + b.constant, letters: a.letters)
            for (name, value) in b.letters { sum.letters[name, default: 0] += value }
            return sum
        }

        static func * (a: Amount, k: Double) -> Amount {
            Amount(constant: a.constant * k, letters: a.letters.mapValues { $0 * k })
        }

        static func - (a: Amount, b: Amount) -> Amount { a + b * -1 }

        /// With the letters whose values are known put in.
        func with(_ values: [String: Double]) -> Amount {
            var result = Amount(constant: constant)
            for (name, coefficient) in letters where abs(coefficient) > 1e-9 {
                if let value = values[name] { result.constant += coefficient * value } else { result.letters[name] = coefficient }
            }
            return result
        }

        var expr: Expr {
            var terms: [Expr] = []
            for name in letters.keys.sorted() {
                let coefficient = letters[name] ?? 0
                guard abs(coefficient) > 1e-9 else { continue }
                if abs(coefficient - 1) < 1e-9 {
                    terms.append(.symbol(name))
                } else if abs(coefficient + 1) < 1e-9 {
                    terms.append(.multiply([.minusOne, .symbol(name)]))
                } else {
                    terms.append(.multiply([CircleDiagram.number(coefficient), .symbol(name)]))
                }
            }
            if terms.isEmpty || abs(constant) > 1e-9 { terms.append(CircleDiagram.number(constant)) }
            return terms.count == 1 ? terms[0] : .add(terms)
        }
    }

    /// Something written in an angle: at `vertex`, turning anticlockwise from the line
    /// towards `from` round to the line towards `to`.
    struct Mark: Sendable {
        var vertex: Int
        var from: Int
        var to: Int
        var amount: Amount
    }

    /// An angle the question asks for: at `vertex`, anticlockwise from the line towards
    /// `from` round to the line towards `to`, and what the question calls it.
    struct Asked: Sendable {
        var vertex: Int
        var from: Int
        var to: Int
        var name: String
    }

    /// Two lengths the question says are equal: each a pair of points.
    struct Equal: Sendable {
        var first: [Int]
        var second: [Int]
    }

    /// A length written along a line, between two of its points: a number, or a letter to find.
    struct Length: Sendable {
        var a: Int
        var b: Int
        var amount: Amount
    }

    /// A length the question asks for, and what it calls it.
    struct AskedLength: Sendable {
        var a: Int
        var b: Int
        var name: String
    }

    var points: [Point]
    var lines: [Line]
    var marks: [Mark]
    var asked: [Asked] = []
    var equal: [Equal] = []
    var lengths: [Length] = []
    /// cm, m, miles: what the lengths are in, if the diagram says.
    var unit: String?
    var askedLengths: [AskedLength] = []
    /// Triangles whose area the question asks for, each by its three points.
    var askedAreas: [[Int]] = []
    /// Letters the question says stand for an acute angle (true) or an obtuse one (false).
    var acute: [String: Bool] = [:]
    /// Whether a question's words gave some of it. Then it isn't held to how it's drawn:
    /// exam diagrams say they aren't drawn accurately.
    var hasWords = false

    /// A whole number where it is one, a decimal otherwise.
    static func number(_ value: Double) -> Expr {
        let rounded = (value * 10000).rounded() / 10000
        if abs(rounded - rounded.rounded()) < 1e-9, abs(rounded) < 1e12 { return .integer(Int(rounded.rounded())) }
        return .number(.real(rounded))
    }
}

/// Works out the angles of a circle diagram from what's marked on it, the way it's done by
/// hand: one fact at a time (angles in a triangle, the angle at the centre, the alternate
/// segment…), each giving one more angle, until nothing more follows. Every angle found
/// comes with the facts that led to it.
struct CircleTheorems {
    private let diagram: CircleDiagram
    /// Every point's name: the letter by it, or one made up here.
    private var names: [String] = []
    private var madeUp: Set<Int> = []

    /// A line leaving a point, and the points along it from nearest to farthest.
    private struct Ray {
        var direction: Double
        var points: [Int]
        var line: Int
    }

    /// The lines leaving each point, in order anticlockwise.
    private var rays: [[Ray]] = []
    /// The angles between neighbouring lines at each point are numbered from here.
    private var firstSector: [Int] = []
    /// Each of those angles as it's drawn, in degrees.
    private var drawn: [Double] = []

    /// An angle at a point: anticlockwise from one of its lines round to another.
    private struct Angle: Hashable {
        var vertex: Int
        var from: Int
        var to: Int
    }

    private struct Fact {
        var title: String
        var reason: String
        /// These, each times its number, add up to `total`.
        var terms: [(coefficient: Double, angle: Angle)]
        var total: CircleDiagram.Amount
        /// The more usual facts are tried first.
        var rank: Int
    }

    private enum Found: Hashable {
        case sector(Int)
        case letter(String)
        /// Several angles next to each other at a point, known only as a total.
        case sum(Int)
        /// The length between two points, the lower numbered first.
        case length(Int, Int)
    }

    private struct Derivation {
        var step: Step?
        var needs: [Found]
        var order: Int
        /// The marks it was read from, for a given angle.
        var mark: Int?
    }

    private var facts: [Fact] = []
    private var value: [CircleDiagram.Amount?] = []
    private var letters: [String: Double] = [:]
    private var derivations: [Found: Derivation] = [:]
    private var isConsistent = true
    /// Totals of neighbouring angles at a point that are known when the angles themselves
    /// aren't: a tangent and a radius are at 90°, whatever line runs between them.
    private var sums: [[Int]: (amount: CircleDiagram.Amount, id: Int)] = [:]
    /// The lengths between points, given or worked out, by the two points (lower first), and
    /// the letters written along the ones to find.
    private var lengths: [[Int]: Double] = [:]
    private var lengthLetters: [[Int]: String] = [:]
    /// How many things have been found, for putting the working in order.
    private var order = 0

    init(_ diagram: CircleDiagram) {
        self.diagram = diagram
    }

    // MARK: Answers

    /// Each angle that can be worked out, with its working: the letters written in the
    /// diagram if it has any, or else every angle that isn't given.
    static func solve(_ diagram: CircleDiagram) -> [Solution] {
        var solver = CircleTheorems(diagram)
        return solver.solutions()
    }

    private mutating func solutions() -> [Solution] {
        guard diagram.points.count >= 3, !diagram.marks.isEmpty || !diagram.equal.isEmpty || diagram.lengths.count >= 2 else { return [] }
        name()
        lay()
        guard given() else { return [] }
        gather()
        order = diagram.marks.count
        chain()
        // Lengths: each triangle with enough known gives its other sides and angles, and an
        // angle found that way may be what the angle facts were waiting for.
        var rounds = 0
        while isConsistent, rounds < 12, measure() {
            chain()
            rounds += 1
        }
        guard isConsistent else { return [] }
        // A marked angle that comes to nothing or less with the letters found means a label
        // wasn't read whole (2x − 10 taken as 2x, say): the letters are then wrong too.
        for mark in diagram.marks {
            let open = mark.amount.letters.filter { abs($0.value) > 1e-9 }
            guard !open.isEmpty, open.keys.allSatisfy({ letters[$0] != nil }) else { continue }
            let size = mark.amount.constant + open.reduce(0) { $0 + $1.value * (letters[$1.key] ?? 0) }
            if size <= 0.05 || size >= 360 { return [] }
        }

        var found: [(target: Found, line: MathLine, title: String, depth: Int)] = []
        let alongLines = Set(lengthLetters.values)
        let unknowns = Set(diagram.marks.flatMap { $0.amount.letters.filter { abs($0.value) > 1e-9 }.keys }).union(alongLines)
        if !unknowns.isEmpty {
            for letter in unknowns.sorted() {
                guard let size = letters[letter], size > 0 else { continue }
                if alongLines.contains(letter) {
                    found.append((.letter(letter), lengthLine(.symbol(letter), size), letter, 0))
                } else if size < 360, abs(size - 180) > 1e-6 {
                    // (180° for a letter is a line taken for an angle, not an answer.)
                    found.append((.letter(letter), angleLine(.symbol(letter), size), letter, 0))
                }
            }
        } else {
            for vertex in diagram.points.indices {
                for index in rays[vertex].indices where rays[vertex].count >= 2 {
                    let sector = firstSector[vertex] + index
                    guard let derivation = derivations[.sector(sector)], derivation.mark == nil, derivation.step != nil,
                          let amount = value[sector], amount.isNumber, amount.constant > 0, amount.constant < 180 - 1e-6,
                          drawn[sector] < 180 else { continue }
                    let angle = Angle(vertex: vertex, from: index, to: (index + 1) % rays[vertex].count)
                    // Far from how it's drawn means something was misread.
                    guard diagram.hasWords || abs(amount.constant - drawn[sector]) < 50 else { return [] }
                    found.append((.sector(sector), angleLine(.symbol(name(of: angle)), amount.constant), name(of: angle), depth(of: .sector(sector))))
                }
            }
            // And every length that was worked out.
            for (key, size) in lengths where derivations[.length(key[0], key[1])]?.step != nil {
                let title = name(ofLength: key)
                found.append((.length(key[0], key[1]), lengthLine(.symbol(title), size), title, depth(of: .length(key[0], key[1]))))
            }
            found.sort { ($0.depth, $0.title) < ($1.depth, $1.title) }
        }

        var solutions = found.prefix(8).map { item in
            let steps = working(for: [item.target])
            let problem = Problem(kind: .diagram(.circle(diagram), find: item.title), text: item.title, usesDecimals: false)
            return Solution(problem: problem, question: MathLine(.symbol(item.title)), task: "Find", answers: [item.line],
                            approximation: nil, steps: steps)
        }
        // The angles the question asks for come first, by the names it gives them: each may
        // be made of several of the angles found.
        var wanted: [Solution] = []
        for item in diagram.asked {
            guard let from = ray(at: item.vertex, towards: item.from), let to = ray(at: item.vertex, towards: item.to), from != to else { continue }
            let parts = sectors(Angle(vertex: item.vertex, from: from, to: to))
            guard let whole = self.total(of: parts), whole.amount.isNumber else { continue }
            let total = whole.amount.constant
            guard total > 0, total < 360 else { continue }
            var steps = working(for: whole.needs)
            let line = angleLine(.symbol(item.name), total)
            if parts.count > 1, parts.allSatisfy({ value[$0] != nil }) {
                let count = rays[item.vertex].count
                let pieces = parts.map { part -> Expr in
                    let index = part - firstSector[item.vertex]
                    return .symbol(name(of: Angle(vertex: item.vertex, from: index, to: (index + 1) % count)))
                }
                let sizes = parts.map { CircleDiagram.number(value[$0]?.with(letters).constant ?? 0) }
                steps.append(Step("Add the parts", "\(item.name) is made of the angles next to each other at \(names[item.vertex]).",
                                  [MathLine(.symbol(item.name), .add(pieces)), MathLine(.symbol(item.name), .add(sizes)), line]))
            }
            let problem = Problem(kind: .diagram(.circle(diagram), find: item.name), text: item.name, usesDecimals: false)
            wanted.append(Solution(problem: problem, question: MathLine(.symbol(item.name)), task: "Find", answers: [line], approximation: nil, steps: steps))
        }
        for item in diagram.askedLengths {
            let key = [min(item.a, item.b), max(item.a, item.b)]
            guard let size = lengths[key], derivations[.length(key[0], key[1])]?.step != nil else { continue }
            let problem = Problem(kind: .diagram(.circle(diagram), find: item.name), text: item.name, usesDecimals: true)
            wanted.append(Solution(problem: problem, question: MathLine(.symbol(item.name)), task: "Find", answers: [lengthLine(.symbol(item.name), size)],
                                   approximation: nil, steps: working(for: [.length(key[0], key[1])])))
        }
        // The area of a triangle: half of two of its sides, times the sine of the angle between them.
        for corners in diagram.askedAreas where corners.count == 3 {
            var best: (derived: Int, corner: Int, sides: [[Int]], angle: Double, needs: [Found])?
            for corner in corners {
                let others = corners.filter { $0 != corner }
                let sides = others.map { [min(corner, $0), max(corner, $0)] }
                guard let angle = angle(at: corner, others[0], others[1]), let whole = total(of: sectors(angle)), whole.amount.with(letters).isNumber,
                      lengths[sides[0]] != nil, lengths[sides[1]] != nil else { continue }
                let needs = whole.needs + sides.map { Found.length($0[0], $0[1]) }
                let derived = needs.filter { derivations[$0]?.step != nil }.count
                if derived < (best?.derived ?? .max) { best = (derived, corner, sides, whole.amount.with(letters).constant, needs) }
            }
            guard let best, let first = lengths[best.sides[0]], let second = lengths[best.sides[1]] else { continue }
            let area = 0.5 * first * second * sin(best.angle * .pi / 180)
            var line = lengthLine(.symbol("Area"), area)
            line.suffix = diagram.unit.map { $0 + "²" }
            let shown = [first, second].map { lengthLine(.symbol(""), $0).parts[1] }
            let isRight = abs(best.angle - 90) < 1e-9
            let sine = Expr.function(.sin, CircleDiagram.number((best.angle * 10).rounded() / 10))
            let step = Step("Area of a triangle", isRight ? "Half the base times the height: the two sides at the right angle."
                                                           : "Half of two sides multiplied together, times the sine of the angle between them.",
                            [MathLine(.symbol("Area"), .multiply(isRight ? [.half, shown[0], shown[1]] : [.half, shown[0], shown[1], sine])), line])
            let problem = Problem(kind: .diagram(.circle(diagram), find: "Area"), text: "Area", usesDecimals: true)
            wanted.insert(Solution(problem: problem, question: MathLine(.symbol("Area")), task: "Find", answers: [line], approximation: nil,
                                   steps: working(for: best.needs) + [step]), at: 0)
        }
        if !wanted.isEmpty {
            let titles = Set(wanted.map(\.problem.text))
            solutions = wanted + solutions.filter { !titles.contains($0.problem.text) }
        }
        return Array(solutions.prefix(8))
    }

    /// How many facts deep an angle is.
    private func depth(of target: Found) -> Int {
        var seen: Set<Found> = []
        func count(_ item: Found) {
            guard seen.insert(item).inserted, let derivation = derivations[item] else { return }
            derivation.needs.forEach(count)
        }
        count(target)
        return seen.filter { derivations[$0]?.step != nil }.count
    }

    /// The steps to an angle: what's given, then each fact it rests on, in the order found.
    private func working(for targets: [Found]) -> [Step] {
        var seen: Set<Found> = []
        var used: [Derivation] = []
        func collect(_ item: Found) {
            guard seen.insert(item).inserted, let derivation = derivations[item] else { return }
            derivation.needs.forEach(collect)
            used.append(derivation)
        }
        targets.forEach(collect)
        used.sort { $0.order < $1.order }

        var steps: [Step] = []
        // What the working starts from, where it can be written with the diagram's own letters.
        var givens: [MathLine] = used.compactMap { derivation in
            guard let index = derivation.mark else { return nil }
            let mark = diagram.marks[index]
            guard let from = ray(at: mark.vertex, towards: mark.from), let to = ray(at: mark.vertex, towards: mark.to) else { return nil }
            let angle = Angle(vertex: mark.vertex, from: from, to: to)
            guard isNamed(angle), mark.amount.isNumber else { return nil }
            return MathLine(.symbol(name(of: angle)), mark.amount.expr, suffix: "°")
        }
        for item in seen.compactMap({ found -> [Int]? in if case .length(let a, let b) = found { [a, b] } else { nil } }).sorted(by: { ($0[0], $0[1]) < ($1[0], $1[1]) }) {
            guard derivations[.length(item[0], item[1])]?.step == nil, let size = lengths[item] else { continue }
            givens.append(MathLine(.symbol(name(ofLength: item)), CircleDiagram.number(size), suffix: diagram.unit))
        }
        if !givens.isEmpty { steps.append(Step("From the diagram", "", givens)) }
        var workingSteps: [Step] = []
        var seenSteps: Set<UUID> = []
        for derivation in used {
            if let step = derivation.step, seenSteps.insert(step.id).inserted { workingSteps.append(step) }
        }
        // Points with no letter get one, and the working says which is which.
        let written = (workingSteps.flatMap(\.lines) + givens).map(\.text).joined(separator: " ")
        let invented = madeUp.sorted().filter { written.contains(names[$0]) }
        if !invented.isEmpty { steps.insert(Step("Name the points", naming(invented)), at: 0) }
        return steps + workingSteps
    }

    // MARK: Names

    private mutating func name() {
        names = diagram.points.map { $0.name ?? "" }
        var taken = Set(names)
        let spare = ["P", "Q", "R", "S", "T", "U", "V", "W", "K", "L", "M", "N", "E", "F", "G", "H", "J"].filter { !taken.contains($0) }
        var next = spare.makeIterator()
        // Round the circle clockwise from the top, then the rest.
        let middle = centre
        func turn(_ index: Int) -> Double {
            let point = diagram.points[index]
            let angle = atan2(point.x - middle.x, point.y - middle.y)
            return angle < 0 ? angle + 2 * .pi : angle
        }
        let unnamed = diagram.points.indices.filter { names[$0].isEmpty }
        let ordered = unnamed.filter { diagram.points[$0].place == .onCircle }.sorted { turn($0) < turn($1) }
            + unnamed.filter { diagram.points[$0].place != .onCircle }
        for index in ordered {
            if diagram.points[index].place == .centre, !taken.contains("O") {
                names[index] = "O"
            } else {
                names[index] = next.next() ?? "X\(index)"
            }
            taken.insert(names[index])
            madeUp.insert(index)
        }
    }

    private func naming(_ points: [Int]) -> String {
        var parts: [String] = []
        let onCircle = points.filter { diagram.points[$0].place == .onCircle }
        if !onCircle.isEmpty {
            let list = Self.list(onCircle.map { names[$0] })
            parts.append(onCircle.count == 1 ? "\(list) is the point on the circle \(position(onCircle[0]))"
                         : "Going clockwise round the circle from the top, the points are \(list)")
        }
        for index in points where diagram.points[index].place != .onCircle {
            switch diagram.points[index].place {
            case .centre: parts.append("\(names[index]) is the centre")
            case .inside: parts.append("\(names[index]) is where the lines cross inside the circle")
            case .free: parts.append("\(names[index]) is the point \(position(index))")
            default: parts.append("\(names[index]) is the point outside the circle \(position(index))")
            }
        }
        return "These points have no letters in the diagram. " + parts.joined(separator: ". ") + "."
    }

    private func position(_ index: Int) -> String {
        let point = diagram.points[index], middle = centre
        let angle = atan2(point.y - middle.y, point.x - middle.x) * 180 / .pi
        let words = ["on the right", "at the top right", "at the top", "at the top left", "on the left", "at the bottom left", "at the bottom", "at the bottom right"]
        return words[Int(((angle < 0 ? angle + 360 : angle) / 45).rounded()) % 8]
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// The middle of the circle: the centre if it's a point, or the middle of the points on it.
    private var centre: (x: Double, y: Double) {
        if let point = diagram.points.first(where: { $0.place == .centre }) { return (point.x, point.y) }
        let around = diagram.points.filter { $0.place == .onCircle }
        let all = around.isEmpty ? diagram.points : around
        return (all.map(\.x).reduce(0, +) / Double(all.count), all.map(\.y).reduce(0, +) / Double(all.count))
    }

    /// The point a line from `vertex` is named by: the farthest along it with a letter of its own.
    private func end(of ray: Ray) -> Int {
        ray.points.last { !madeUp.contains($0) } ?? ray.points[ray.points.count - 1]
    }

    private func isNamed(_ angle: Angle) -> Bool {
        let lines = rays[angle.vertex]
        return !madeUp.contains(angle.vertex) && !madeUp.contains(end(of: lines[angle.from])) && !madeUp.contains(end(of: lines[angle.to]))
    }

    private func size(_ angle: Angle) -> Double {
        sectors(angle).reduce(0) { $0 + drawn[$1] }
    }

    private func name(of angle: Angle) -> String {
        let lines = rays[angle.vertex]
        let ends = [names[end(of: lines[angle.from])], names[end(of: lines[angle.to])]].sorted()
        return (size(angle) > 180.5 ? "reflex ∠" : "∠") + ends[0] + names[angle.vertex] + ends[1]
    }

    /// How an angle is written in the working: by what's written in it if that's a letter,
    /// or by its three points.
    private func label(_ angle: Angle) -> Expr {
        let covered = sectors(angle)
        // A number stands for an angle whose points have no letters to call it by.
        for mark in diagram.marks where !mark.amount.isNumber || !isNamed(angle) {
            guard mark.vertex == angle.vertex, let from = ray(at: mark.vertex, towards: mark.from), let to = ray(at: mark.vertex, towards: mark.to) else { continue }
            if sectors(Angle(vertex: mark.vertex, from: from, to: to)) == covered { return mark.amount.expr }
        }
        return .symbol(name(of: angle))
    }

    // MARK: Layout

    private mutating func lay() {
        rays = diagram.points.indices.map { _ in [] }
        for (number, line) in diagram.lines.enumerated() {
            for (place, vertex) in line.points.enumerated() {
                let before = Array(line.points[..<place].reversed()), after = Array(line.points[(place + 1)...])
                for along in [before, after] where !along.isEmpty {
                    let here = diagram.points[vertex], there = diagram.points[along[0]]
                    rays[vertex].append(Ray(direction: atan2(there.y - here.y, there.x - here.x), points: along, line: number))
                }
            }
        }
        firstSector = []
        drawn = []
        for vertex in diagram.points.indices {
            rays[vertex].sort { $0.direction < $1.direction }
            firstSector.append(drawn.count)
            let lines = rays[vertex]
            guard lines.count >= 2 else { continue }
            for index in lines.indices {
                var turn = (lines[(index + 1) % lines.count].direction - lines[index].direction) * 180 / .pi
                if turn <= 0 { turn += 360 }
                drawn.append(turn)
            }
        }
        value = Array(repeating: nil, count: drawn.count)
    }

    private func ray(at vertex: Int, towards point: Int) -> Int? {
        rays[vertex].firstIndex { $0.points.contains(point) }
    }

    private func isJoined(_ a: Int, _ b: Int) -> Bool {
        a != b && ray(at: a, towards: b) != nil
    }

    private func sectors(_ angle: Angle) -> [Int] {
        let count = rays[angle.vertex].count
        var result: [Int] = []
        var index = angle.from
        while index != angle.to {
            result.append(firstSector[angle.vertex] + index)
            index = (index + 1) % count
        }
        return result
    }

    /// The angle XVY, the one under 180° as drawn. Nil if X and Y aren't both joined to V,
    /// or they're along the same line from it.
    private func angle(at vertex: Int, _ x: Int, _ y: Int) -> Angle? {
        guard let a = ray(at: vertex, towards: x), let b = ray(at: vertex, towards: y), a != b,
              rays[vertex][a].line != rays[vertex][b].line else { return nil }
        let forwards = Angle(vertex: vertex, from: a, to: b)
        return size(forwards) <= 180 ? forwards : Angle(vertex: vertex, from: b, to: a)
    }

    /// The angle between two of the lines leaving a point, the one under 180°.
    private func angle(at vertex: Int, between a: Int, and b: Int) -> Angle? {
        guard a != b, rays[vertex][a].line != rays[vertex][b].line else { return nil }
        let forwards = Angle(vertex: vertex, from: a, to: b)
        return size(forwards) <= 180 ? forwards : Angle(vertex: vertex, from: b, to: a)
    }

    /// Which side of the line through a and b the point p is on: positive to its left.
    private func side(_ p: Int, of a: Int, _ b: Int) -> Double {
        let p = diagram.points[p], a = diagram.points[a], b = diagram.points[b]
        return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }

    // MARK: What's given

    /// The marked angles. False if two of them disagree.
    private mutating func given() -> Bool {
        for (index, mark) in diagram.marks.enumerated() {
            guard let from = ray(at: mark.vertex, towards: mark.from), let to = ray(at: mark.vertex, towards: mark.to), from != to else { return false }
            let angle = Angle(vertex: mark.vertex, from: from, to: to)
            let covered = sectors(angle)
            if covered.count == 1 {
                if let already = value[covered[0]], already != mark.amount { return false }
                value[covered[0]] = mark.amount
                derivations[.sector(covered[0])] = Derivation(step: nil, needs: [], order: index, mark: index)
            } else {
                facts.append(Fact(title: "From the diagram", reason: "", terms: [(1, angle)], total: mark.amount, rank: 0))
            }
        }
        for length in diagram.lengths where length.a != length.b {
            let key = [min(length.a, length.b), max(length.a, length.b)]
            if length.amount.isNumber {
                guard length.amount.constant > 0, lengths[key] == nil || lengths[key] == length.amount.constant else { return false }
                lengths[key] = length.amount.constant
                derivations[.length(key[0], key[1])] = Derivation(step: nil, needs: [], order: -1, mark: nil)
            } else if length.amount.letters.count == 1, let letter = length.amount.letters.first, abs(letter.value - 1) < 1e-9, abs(length.amount.constant) < 1e-9 {
                lengthLetters[key] = letter.key
            }
        }
        // A straight line through a point with nothing else on one side is 180° there.
        for vertex in diagram.points.indices {
            let lines = rays[vertex]
            for index in lines.indices where lines.count >= 2 {
                let next = (index + 1) % lines.count
                if lines[index].line == lines[next].line, lines.count > 2 || index == 0 {
                    let sector = firstSector[vertex] + index
                    if value[sector] == nil {
                        value[sector] = .number(180)
                        derivations[.sector(sector)] = Derivation(step: nil, needs: [], order: -1, mark: nil)
                    }
                }
            }
            if lines.count == 2, lines[0].line == lines[1].line {
                for index in 0..<2 where value[firstSector[vertex] + index] == nil {
                    value[firstSector[vertex] + index] = .number(180)
                    derivations[.sector(firstSector[vertex] + index)] = Derivation(step: nil, needs: [], order: -1, mark: nil)
                }
            }
        }
        return true
    }

    // MARK: Facts

    private mutating func add(_ title: String, _ reason: String, _ terms: [(Double, Angle?)], _ total: Double, rank: Int) {
        var whole: [(coefficient: Double, angle: Angle)] = []
        for (coefficient, angle) in terms {
            guard let angle else { return }
            whole.append((coefficient, angle))
        }
        facts.append(Fact(title: title, reason: reason, terms: whole, total: .number(total), rank: rank))
    }

    private mutating func gather() {
        let points = diagram.points.indices
        let onCircle = points.filter { diagram.points[$0].place == .onCircle }
        let middle = points.first { diagram.points[$0].place == .centre }
        func n(_ index: Int) -> String { names[index] }

        for vertex in points {
            let lines = rays[vertex]
            guard lines.count >= 2 else { continue }
            let each = lines.indices.map { Angle(vertex: vertex, from: $0, to: ($0 + 1) % lines.count) }
            // Angles on a straight line.
            for a in lines.indices {
                for b in lines.indices where a != b && lines[a].line == lines[b].line {
                    let across = Angle(vertex: vertex, from: a, to: b)
                    let parts = sectors(across)
                    guard parts.count >= 2 else { continue }
                    add("Angles on a straight line", "Angles on a straight line add up to 180°.",
                        parts.map { (1, each[$0 - firstSector[vertex]]) }, 180, rank: 1)
                }
            }
            // Where two lines cross.
            for a in lines.indices {
                for b in lines.indices where a < b && lines[a].line != lines[b].line {
                    guard let a2 = lines.indices.first(where: { $0 != a && lines[$0].line == lines[a].line }),
                          let b2 = lines.indices.first(where: { $0 != b && lines[$0].line == lines[b].line }), a < a2, b < b2 else { continue }
                    add("Vertically opposite angles", "Where two straight lines cross, the angles opposite each other are equal.",
                        [(1, Angle(vertex: vertex, from: a, to: b)), (-1, Angle(vertex: vertex, from: a2, to: b2))], 0, rank: 1)
                    add("Vertically opposite angles", "Where two straight lines cross, the angles opposite each other are equal.",
                        [(1, Angle(vertex: vertex, from: b, to: a2)), (-1, Angle(vertex: vertex, from: b2, to: a))], 0, rank: 1)
                }
            }
            // All the way round.
            if diagram.points[vertex].place == .centre || diagram.points[vertex].place == .inside || diagram.points[vertex].place == .free {
                add("Angles round a point", "The angles round a point add up to 360°.", each.map { (1, $0) }, 360, rank: 2)
            }
        }

        // Triangles.
        for a in points {
            for b in points where b > a && isJoined(a, b) {
                for c in points where c > b && isJoined(a, c) && isJoined(b, c) {
                    guard let atA = angle(at: a, b, c), let atB = angle(at: b, a, c), let atC = angle(at: c, a, b),
                          abs(size(atA) + size(atB) + size(atC) - 180) < 3 else { continue }
                    add("Angles in a triangle", "The angles in triangle \(n(a))\(n(b))\(n(c)) add up to 180°.", [(1, atA), (1, atB), (1, atC)], 180, rank: 2)
                    // Two sides that are radii, or tangents from the same point, are equal.
                    for (apex, left, right, top, bottomLeft, bottomRight) in [(a, b, c, atA, atB, atC), (b, a, c, atB, atA, atC), (c, a, b, atC, atA, atB)] {
                        var why: String?
                        if diagram.points[apex].place == .centre, diagram.points[left].place == .onCircle, diagram.points[right].place == .onCircle {
                            why = "\(n(apex))\(n(left)) and \(n(apex))\(n(right)) are both radii"
                        } else if diagram.points[apex].place == .outside, isTangent(from: apex, at: left), isTangent(from: apex, at: right) {
                            why = "\(n(apex))\(n(left)) and \(n(apex))\(n(right)) are tangents from the same point, so they're the same length"
                        }
                        guard let why else { continue }
                        add("Isosceles triangle", "\(why), so triangle \(n(apex))\(n(left))\(n(right)) is isosceles: its angles at \(n(left)) and \(n(right)) are equal.",
                            [(1, bottomLeft), (-1, bottomRight)], 0, rank: 1)
                        let shared = "\(why), so triangle \(n(apex))\(n(left))\(n(right)) is isosceles. Its angles at \(n(left)) and \(n(right)) are equal, and share what's left of 180°."
                        add("Isosceles triangle", shared, [(2, bottomLeft), (1, top)], 180, rank: 4)
                        add("Isosceles triangle", shared, [(2, bottomRight), (1, top)], 180, rank: 4)
                    }
                }
            }
        }

        // Shapes with four sides, and five or six where there's no circle: every way round
        // points that are joined, each counted once.
        let isFigure = onCircle.isEmpty && middle == nil
        func rings(_ count: Int) -> [[Int]] {
            var found: [[Int]] = []
            var path: [Int] = []
            func walk() {
                if path.count == count {
                    if isJoined(path[count - 1], path[0]), path[1] < path[count - 1] { found.append(path) }
                    return
                }
                for next in points where next > path[0] && !path.contains(next) && isJoined(path[path.count - 1], next) {
                    path.append(next)
                    walk()
                    path.removeLast()
                }
            }
            for start in points {
                path = [start]
                walk()
            }
            return found
        }
        for count in (isFigure ? [4, 5, 6] : [4]) where points.count >= count {
            for corners in rings(count) {
                // No side crossing another.
                var isSimple = true
                for i in 0..<count {
                    for j in 0..<count where j > i + 1 && !(i == 0 && j == count - 1) {
                        if crosses(corners[i], corners[(i + 1) % count], corners[j], corners[(j + 1) % count]) { isSimple = false }
                    }
                }
                guard isSimple else { continue }
                var area = 0.0
                for index in 0..<count {
                    let p = diagram.points[corners[index]], q = diagram.points[corners[(index + 1) % count]]
                    area += p.x * q.y - q.x * p.y
                }
                var inside: [(Double, Angle?)] = []
                for index in 0..<count {
                    let here = corners[index], next = corners[(index + 1) % count], previous = corners[(index + count - 1) % count]
                    guard let forwards = ray(at: here, towards: next), let back = ray(at: here, towards: previous), forwards != back,
                          rays[here][forwards].line != rays[here][back].line else { inside = []; break }
                    inside.append((1, area > 0 ? Angle(vertex: here, from: forwards, to: back) : Angle(vertex: here, from: back, to: forwards)))
                }
                let total = Double(count - 2) * 180
                guard inside.count == count, abs(inside.reduce(0) { $0 + size($1.1!) } - total) < 5 else { continue }
                let shape = ["quadrilateral", "pentagon", "hexagon"][count - 4]
                add("Angles in a \(shape)", "The angles in \(shape) \(corners.map(n).joined()) add up to \(Int(total))°.", inside, total, rank: 5)
            }
        }

        // Parallel lines, in a figure with no circle: lines drawn parallel, and a line across both.
        if isFigure {
            let reach = max((diagram.points.map(\.x).max() ?? 0) - (diagram.points.map(\.x).min() ?? 0), (diagram.points.map(\.y).max() ?? 0) - (diagram.points.map(\.y).min() ?? 0))
            func heading(_ line: Int) -> (x: Double, y: Double)? {
                let onIt = diagram.lines[line].points
                guard onIt.count >= 2 else { return nil }
                let first = diagram.points[onIt[0]], last = diagram.points[onIt[onIt.count - 1]]
                let length = hypot(last.x - first.x, last.y - first.y)
                return length > 0 ? ((last.x - first.x) / length, (last.y - first.y) / length) : nil
            }
            func ray(_ vertex: Int, _ line: Int, _ way: (x: Double, y: Double)) -> Int? {
                rays[vertex].indices.first { rays[vertex][$0].line == line && cos(rays[vertex][$0].direction) * way.x + sin(rays[vertex][$0].direction) * way.y > 0 }
            }
            func between(_ vertex: Int, _ a: Int?, _ b: Int?) -> Angle? {
                guard let a, let b else { return nil }
                return angle(at: vertex, between: a, and: b)
            }
            for a in diagram.lines.indices {
                for b in diagram.lines.indices where b > a {
                    guard let u = heading(a), var v = heading(b), abs(u.x * v.y - u.y * v.x) < 0.03 else { continue }
                    if u.x * v.x + u.y * v.y < 0 { v = (-v.x, -v.y) }
                    let p0 = diagram.points[diagram.lines[a].points[0]], q0 = diagram.points[diagram.lines[b].points[0]]
                    guard abs((q0.x - p0.x) * u.y - (q0.y - p0.y) * u.x) > reach * 0.04 else { continue }
                    for across in diagram.lines.indices where across != a && across != b {
                        guard let p = diagram.lines[across].points.first(where: { diagram.lines[a].points.contains($0) }),
                              let q = diagram.lines[across].points.first(where: { diagram.lines[b].points.contains($0) }), p != q else { continue }
                        let toQ = (x: diagram.points[q].x - diagram.points[p].x, y: diagram.points[q].y - diagram.points[p].y)
                        let toP = (x: -toQ.x, y: -toQ.y)
                        for sign in [1.0, -1.0] {
                            let way = (x: u.x * sign, y: u.y * sign), back = (x: -u.x * sign, y: -u.y * sign)
                            let atP = between(p, ray(p, a, way), ray(p, across, toQ))
                            add("Alternate angles", "The lines are drawn parallel, and alternate angles between parallel lines are equal.",
                                [(1, atP), (-1, between(q, ray(q, b, back), ray(q, across, toP)))], 0, rank: 1)
                            add("Corresponding angles", "The lines are drawn parallel, and corresponding angles on parallel lines are equal.",
                                [(1, atP), (-1, between(q, ray(q, b, way), ray(q, across, toQ)))], 0, rank: 1)
                            add("Corresponding angles", "The lines are drawn parallel, and corresponding angles on parallel lines are equal.",
                                [(1, between(p, ray(p, a, way), ray(p, across, toP))), (-1, between(q, ray(q, b, way), ray(q, across, toP)))], 0, rank: 1)
                            add("Co-interior angles", "The lines are drawn parallel, and co-interior angles between parallel lines add up to 180°.",
                                [(1, atP), (1, between(q, ray(q, b, way), ray(q, across, toP)))], 180, rank: 2)
                        }
                    }
                }
            }
        }

        // Angles at the circumference from the same two points.
        for a in onCircle {
            for b in onCircle where b > a {
                let across = onCircle.filter { $0 != a && $0 != b && isJoined($0, a) && isJoined($0, b) }
                let isDiameter = middle.map { centre in
                    guard let toA = ray(at: centre, towards: a), let toB = ray(at: centre, towards: b) else { return false }
                    return toA != toB && rays[centre][toA].line == rays[centre][toB].line
                } ?? false
                for p in across {
                    if isDiameter {
                        add("Angle in a semicircle", "\(n(a))\(n(b)) is a diameter, and the angle in a semicircle is a right angle.",
                            [(1, angle(at: p, a, b))], 90, rank: 1)
                    } else if let centre = middle, let toA = ray(at: centre, towards: a), let toB = ray(at: centre, towards: b), toA != toB {
                        // The angle at the centre that faces away from p.
                        let facing = side(p, of: a, b) * side(centre, of: a, b) >= 0
                        let small = Angle(vertex: centre, from: toA, to: toB), other = Angle(vertex: centre, from: toB, to: toA)
                        let minor = size(small) <= size(other) ? small : other, major = size(small) <= size(other) ? other : small
                        add("Angle at the centre", "The angle at the centre is twice the angle at the circumference from the same two points.",
                            [(1, facing ? minor : major), (-2, angle(at: p, a, b))], 0, rank: 1)
                    }
                    for q in across where q > p {
                        if side(p, of: a, b) * side(q, of: a, b) > 0 {
                            add("Angles in the same segment", "Angles at the circumference from the same two points, on the same side of them, are equal.",
                                [(1, angle(at: p, a, b)), (-1, angle(at: q, a, b))], 0, rank: 1)
                        } else if !isDiameter {
                            add("Cyclic quadrilateral", "\(n(a))\(n(p))\(n(b))\(n(q)) has all four corners on the circle, so its opposite angles add up to 180°.",
                                [(1, angle(at: p, a, b)), (1, angle(at: q, a, b))], 180, rank: 1)
                        }
                    }
                }
            }
        }

        // Lengths the question says are equal.
        for pair in diagram.equal where pair.first.count == 2 && pair.second.count == 2 {
            // Two lengths from one point make an isosceles triangle with the line between their ends.
            guard let apex = pair.first.first(where: { pair.second.contains($0) }),
                  let left = pair.first.first(where: { $0 != apex }), let right = pair.second.first(where: { $0 != apex }), left != right else { continue }
            let same = "\(n(apex))\(n(left)) = \(n(apex))\(n(right))"
            add("Isosceles triangle", "\(same), so triangle \(n(apex))\(n(left))\(n(right)) is isosceles: its angles at \(n(left)) and \(n(right)) are equal.",
                [(1, angle(at: left, apex, right)), (-1, angle(at: right, apex, left))], 0, rank: 1)
            add("Isosceles triangle", "\(same), so triangle \(n(apex))\(n(left))\(n(right)) is isosceles. Its angles at \(n(left)) and \(n(right)) are equal, and share what's left of 180°.",
                [(2, angle(at: left, apex, right)), (1, angle(at: apex, left, right))], 180, rank: 4)
            // Equal chords from a point on the circle: the line to the centre halves the angle between them.
            if let centre = middle, diagram.points[apex].place == .onCircle, diagram.points[left].place == .onCircle, diagram.points[right].place == .onCircle {
                let why = "\(same), and \(n(centre))\(n(left)) = \(n(centre))\(n(right)) (radii), so triangles \(n(centre))\(n(apex))\(n(left)) and \(n(centre))\(n(apex))\(n(right)) are the same shape and size: \(n(apex))\(n(centre)) halves the angles at \(n(apex)) and at \(n(centre))."
                add("Equal chords", why, [(1, angle(at: apex, left, centre)), (-1, angle(at: apex, centre, right))], 0, rank: 3)
                add("Equal chords", why, [(1, angle(at: centre, left, apex)), (-1, angle(at: centre, apex, right))], 0, rank: 3)
                add("Equal chords", why, [(1, angle(at: left, apex, centre)), (-1, angle(at: right, apex, centre))], 0, rank: 3)
            }
        }

        // Tangents.
        for (number, line) in diagram.lines.enumerated() {
            guard let touch = line.tangentAt else { continue }
            let along = rays[touch].indices.filter { rays[touch][$0].line == number }
            if let centre = middle, let inwards = ray(at: touch, towards: centre) {
                for tangent in along {
                    add("Tangent and radius", "A tangent meets the radius at 90°.", [(1, angle(at: touch, between: tangent, and: inwards))], 90, rank: 1)
                }
            }
            for tangent in along {
                let outer = rays[touch][tangent].points[0]
                for a in onCircle where a != touch {
                    guard let chord = ray(at: touch, towards: a), rays[touch][chord].line != number else { continue }
                    for p in onCircle where p != touch && p != a && isJoined(p, touch) && isJoined(p, a) {
                        // The far side of the chord from the tangent.
                        guard side(p, of: touch, a) * side(outer, of: touch, a) < 0 else { continue }
                        add("Alternate segment theorem", "The angle between a tangent and a chord equals the angle in the alternate segment: the one at the circumference on the other side of the chord.",
                            [(1, angle(at: touch, between: tangent, and: chord)), (-1, angle(at: p, touch, a))], 0, rank: 1)
                    }
                }
            }
        }
        // Two tangents from one point, and the line from there to the centre.
        if let centre = middle {
            for p in points where diagram.points[p].place == .outside && isJoined(p, centre) {
                let touches = onCircle.filter { isTangent(from: p, at: $0) }
                guard touches.count == 2 else { continue }
                let why = "Tangents from the same point are equal, and the line from there to the centre halves the angle between them."
                add("Tangents from a point", why, [(1, angle(at: p, touches[0], centre)), (-1, angle(at: p, touches[1], centre))], 0, rank: 3)
                add("Tangents from a point", why, [(1, angle(at: centre, touches[0], p)), (-1, angle(at: centre, touches[1], p))], 0, rank: 3)
            }
        }
        facts.sort { $0.rank < $1.rank }
    }

    private func isTangent(from point: Int, at touch: Int) -> Bool {
        diagram.lines.contains { $0.tangentAt == touch && $0.points.contains(point) }
    }

    /// Whether the line from a to b crosses the line from c to d.
    private func crosses(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
        side(c, of: a, b) * side(d, of: a, b) < 0 && side(a, of: c, d) * side(b, of: c, d) < 0
    }

    // MARK: Working it out

    private mutating func chain() {
        var isDone = [Bool](repeating: false, count: facts.count)
        var progressed = true
        while progressed, isConsistent {
            progressed = false
            for (index, fact) in facts.enumerated() where !isDone[index] {
                var unknown: [Int: Double] = [:]
                var rest = CircleDiagram.Amount()
                var needs: [Found] = []
                var groups: [(coefficient: Double, sectors: [Int])] = []
                for (coefficient, angle) in fact.terms {
                    var missing: [Int] = []
                    for sector in sectors(angle) {
                        if let known = value[sector] {
                            rest = rest + known.with(letters) * coefficient
                            needs.append(.sector(sector))
                            needs += known.letters.keys.filter { letters[$0] != nil }.map { .letter($0) }
                        } else {
                            missing.append(sector)
                        }
                    }
                    if missing.count >= 2, let total = sums[missing.sorted()] {
                        rest = rest + total.amount.with(letters) * coefficient
                        needs.append(.sum(total.id))
                    } else if !missing.isEmpty {
                        for sector in missing { unknown[sector, default: 0] += coefficient }
                        groups.append((coefficient, missing))
                    }
                }
                rest = rest - fact.total.with(letters)
                unknown = unknown.filter { abs($0.value) > 1e-9 }
                if unknown.count >= 2, groups.count == 1, sums[groups[0].sectors.sorted()] == nil {
                    // Everything but one run of neighbouring angles is known: their total is.
                    let amount = (rest * (-1 / groups[0].coefficient)).with(letters)
                    let id = sums.count
                    sums[groups[0].sectors.sorted()] = (amount, id)
                    order += 1
                    derivations[.sum(id)] = Derivation(step: step(fact, totalling: groups[0].sectors, amount), needs: needs, order: order, mark: nil)
                    isDone[index] = true
                    progressed = true
                } else if unknown.count == 1, let (sector, coefficient) = unknown.first {
                    let amount = (rest * (-1 / coefficient)).with(letters)
                    value[sector] = amount
                    order += 1
                    derivations[.sector(sector)] = Derivation(step: step(fact, finding: sector), needs: needs, order: order, mark: nil)
                    isDone[index] = true
                    progressed = true
                } else if unknown.isEmpty {
                    let open = rest.letters.filter { abs($0.value) > 1e-9 }
                    if open.isEmpty {
                        // Nothing new; but it has to hold.
                        if abs(rest.constant) > 0.05 { isConsistent = false }
                        isDone[index] = true
                    } else if open.count == 1, let (letter, coefficient) = open.first {
                        letters[letter] = -rest.constant / coefficient
                        order += 1
                        derivations[.letter(letter)] = Derivation(step: step(fact, solving: letter), needs: needs, order: order, mark: nil)
                        isDone[index] = true
                        progressed = true
                    }
                }
            }
            // Two facts about the same two angles, neither enough alone, settle both together.
            if !progressed {
                var open: [(fact: Int, sectors: [Int], coefficients: [Double], rest: Double, needs: [Found])] = []
                for (index, fact) in facts.enumerated() where !isDone[index] {
                    var unknown: [Int: Double] = [:]
                    var rest = CircleDiagram.Amount()
                    var needs: [Found] = []
                    var isUsable = true
                    for (coefficient, angle) in fact.terms {
                        var missing: [Int] = []
                        for sector in sectors(angle) {
                            if let known = value[sector] {
                                rest = rest + known.with(letters) * coefficient
                                needs.append(.sector(sector))
                            } else {
                                missing.append(sector)
                            }
                        }
                        if missing.count >= 2, let total = sums[missing.sorted()] {
                            rest = rest + total.amount.with(letters) * coefficient
                            needs.append(.sum(total.id))
                        } else {
                            for sector in missing { unknown[sector, default: 0] += coefficient }
                        }
                    }
                    rest = rest - fact.total.with(letters)
                    unknown = unknown.filter { abs($0.value) > 1e-9 }
                    if unknown.count != 2 || !rest.isNumber { isUsable = false }
                    if isUsable {
                        let pair = unknown.keys.sorted()
                        open.append((index, pair, pair.map { unknown[$0] ?? 0 }, rest.constant, needs))
                    }
                }
                // A total of two angles that's known is a fact about the two as well.
                for (parts, known) in sums where parts.count == 2 && parts.allSatisfy({ value[$0] == nil }) {
                    let amount = known.amount.with(letters)
                    if amount.isNumber { open.append((-1, parts.sorted(), [1, 1], -amount.constant, [.sum(known.id)])) }
                }
                search: for (number, first) in open.enumerated() {
                    for second in open[(number + 1)...] where second.sectors == first.sectors {
                        let determinant = first.coefficients[0] * second.coefficients[1] - first.coefficients[1] * second.coefficients[0]
                        guard abs(determinant) > 1e-9 else { continue }
                        let a = (-first.rest * second.coefficients[1] + second.rest * first.coefficients[1]) / determinant
                        let b = (-second.rest * first.coefficients[0] + first.rest * second.coefficients[0]) / determinant
                        guard a > 0, b > 0, a < 360, b < 360 else { continue }
                        let names = first.sectors.map { Expr.symbol(self.name(of: spanning([$0]))) }
                        func written(_ fact: Fact) -> MathLine {
                            var left: [Expr] = [], right: [Expr] = []
                            for (coefficient, angle) in fact.terms {
                                let size = abs(coefficient)
                                let term: Expr = abs(size - 1) < 1e-9 ? (amount(angle)?.expr ?? label(angle)) : .multiply([CircleDiagram.number(size), amount(angle)?.expr ?? label(angle)])
                                if coefficient > 0 { left.append(term) } else { right.append(term) }
                            }
                            if abs(fact.total.constant) > 1e-9 || right.isEmpty { right.insert(fact.total.expr, at: 0) }
                            if left.isEmpty { left = [.zero] }
                            return MathLine(left.count == 1 ? left[0] : .add(left), right.count == 1 ? right[0] : .add(right))
                        }
                        guard first.fact >= 0 || second.fact >= 0 else { continue }
                        func line(_ entry: (fact: Int, sectors: [Int], coefficients: [Double], rest: Double, needs: [Found])) -> MathLine {
                            entry.fact >= 0 ? written(facts[entry.fact])
                                : MathLine(.symbol(self.name(of: spanning(sums.first { $0.value.id == sums[entry.sectors]?.id }?.key ?? entry.sectors))), CircleDiagram.number(-entry.rest))
                        }
                        let real = [first, second].filter { $0.fact >= 0 }.map { facts[$0.fact] }
                        let lines = [line(first), line(second), MathLine(names[0], CircleDiagram.number(a), suffix: "°"), MathLine(names[1], CircleDiagram.number(b), suffix: "°")]
                        let reason = real.map(\.reason).filter { !$0.isEmpty }.joined(separator: " ") + " With what's already known, that gives both angles."
                        let title = real.count == 2 && real[0].title != real[1].title ? "\(real[0].title) and \(real[1].title.prefix(1).lowercased() + real[1].title.dropFirst())" : real[0].title
                        let step = Step(title, reason, lines)
                        order += 1
                        for (sector, size) in zip(first.sectors, [a, b]) {
                            value[sector] = .number(size)
                            derivations[.sector(sector)] = Derivation(step: step, needs: first.needs + second.needs, order: order, mark: nil)
                        }
                        if first.fact >= 0 { isDone[first.fact] = true }
                        if second.fact >= 0 { isDone[second.fact] = true }
                        progressed = true
                        break search
                    }
                }
            }
            // One angle of a known total, once the rest of it is known.
            for (parts, known) in sums {
                let missing = parts.filter { value[$0] == nil }
                guard missing.count == 1 else { continue }
                var left = known.amount.with(letters)
                var needs: [Found] = [.sum(known.id)]
                var taken: [(Double, Expr)] = []
                for sector in parts where sector != missing[0] {
                    guard let size = value[sector]?.with(letters) else { continue }
                    left = left - size
                    needs.append(.sector(sector))
                    taken.append((1, size.expr))
                }
                value[missing[0]] = left
                order += 1
                let name = Expr.symbol(self.name(of: spanning(missing)))
                let whole = self.name(of: spanning(parts))
                derivations[.sector(missing[0])] = Derivation(
                    step: Step("Take away the part that's known", "\(whole) is made of the angles next to each other there.",
                               tidied([MathLine(name, isolated(taken, total: known.amount.with(letters), over: 1)), MathLine(name, left.expr, suffix: left.isNumber ? "°" : nil)])),
                    needs: needs, order: order, mark: nil)
                progressed = true
            }
        }
    }

    // MARK: Lengths

    private func name(ofLength key: [Int]) -> String {
        lengthLetters[key] ?? key.map { names[$0] }.sorted().joined()
    }

    /// An angle to one decimal place, with ≈ where that isn't all of it.
    private func angleLine(_ name: Expr, _ size: Double) -> MathLine {
        let shown = (size * 10).rounded() / 10
        return MathLine(name, CircleDiagram.number(shown), relation: abs(size - shown) < 1e-6 ? "=" : "≈", suffix: "°")
    }

    /// A length to three significant figures.
    private func lengthLine(_ name: Expr, _ size: Double) -> MathLine {
        let digits = size > 0 ? Int(floor(log10(size))) + 1 : 1
        let scale = pow(10, Double(max(3 - digits, 0)))
        let shown = (size * scale).rounded() / scale
        return MathLine(name, CircleDiagram.number(shown), relation: abs(size - shown) < 1e-9 ? "=" : "≈", suffix: diagram.unit)
    }

    private mutating func found(length key: [Int], _ size: Double, _ step: Step, needs: [Found]) {
        lengths[key] = size
        order += 1
        derivations[.length(key[0], key[1])] = Derivation(step: step, needs: needs, order: order, mark: nil)
        if let letter = lengthLetters[key], letters[letter] == nil {
            letters[letter] = size
            derivations[.letter(letter)] = Derivation(step: nil, needs: [.length(key[0], key[1])], order: order, mark: nil)
        }
    }

    /// One round of the lengths: every triangle with enough known gives its other sides and
    /// angles (Pythagoras, the sine, cosine and tangent ratios, the sine and cosine rules),
    /// and lengths along one line add up. True if anything new came of it.
    private mutating func measure() -> Bool {
        guard !lengths.isEmpty else { return false }
        var progressed = false
        let count = diagram.points.count
        for i in 0..<count {
            for j in (i + 1)..<count where isJoined(i, j) {
                for k in (j + 1)..<count where isJoined(i, k) && isJoined(j, k) {
                    let corners = [i, j, k]
                    // Each corner's angle; three points along one line aren't a triangle.
                    var angles: [Angle] = []
                    for (place, corner) in corners.enumerated() {
                        let others = corners.indices.filter { $0 != place }.map { corners[$0] }
                        if let angle = angle(at: corner, others[0], others[1]) { angles.append(angle) }
                    }
                    guard angles.count == 3 else { continue }
                    var marks: [TriangleDiagram.Mark?] = []
                    var isUsable = true
                    for angle in angles {
                        guard let known = amount(angle)?.with(letters) else { marks.append(nil); continue }
                        if known.isNumber {
                            if known.constant <= 0 || known.constant >= 180 { isUsable = false }
                            marks.append(.number(known.constant))
                        } else if known.letters.count == 1, let letter = known.letters.first, abs(letter.value - 1) < 1e-9, abs(known.constant) < 1e-9 {
                            marks.append(.letter(letter.key))
                        } else {
                            marks.append(nil)
                        }
                    }
                    guard isUsable else { continue }
                    let keys = corners.indices.map { place -> [Int] in corners.indices.filter { $0 != place }.map { corners[$0] }.sorted() }
                    let sides = keys.map { key -> TriangleDiagram.Mark? in
                        if let size = lengths[key] { return .number(size) }
                        return lengthLetters[key].map { .letter($0) }
                    }
                    guard sides.contains(where: { if case .number = $0 { true } else { false } }) else { continue }
                    let triangle = TriangleDiagram(corners: corners.enumerated().map { place, corner in
                        .init(name: names[corner], x: diagram.points[corner].x, y: diagram.points[corner].y, angle: marks[place])
                    }, sides: sides, unit: diagram.unit)
                    var obtuse: [Int: Bool] = [:]
                    for (place, mark) in marks.enumerated() {
                        if case .letter(let letter)? = mark, let isAcute = diagram.acute[letter] { obtuse[place] = !isAcute }
                    }
                    func needs(_ items: [Int]) -> [Found] {
                        items.flatMap { item -> [Found] in
                            if item >= 3 { return [.length(keys[item - 3][0], keys[item - 3][1])] }
                            var all = total(of: sectors(angles[item]))?.needs ?? []
                            if case .letter(let letter)? = marks[item] { all.append(.letter(letter)) }
                            return all
                        }
                    }
                    for result in Triangles.deductions(in: triangle, names: corners.map { names[$0] }, obtuse: obtuse) {
                        let before = needs(result.needs)
                        if result.item >= 3 {
                            let key = keys[result.item - 3]
                            guard lengths[key] == nil else { continue }
                            found(length: key, result.value, result.step, needs: before)
                            progressed = true
                            continue
                        }
                        let parts = sectors(angles[result.item])
                        if case .letter(let letter)? = marks[result.item] {
                            guard letters[letter] == nil else { continue }
                            letters[letter] = result.value
                            order += 1
                            derivations[.letter(letter)] = Derivation(step: result.step, needs: before + (total(of: parts)?.needs ?? []), order: order, mark: nil)
                            progressed = true
                        } else if parts.count == 1, value[parts[0]] == nil {
                            value[parts[0]] = .number(result.value)
                            order += 1
                            derivations[.sector(parts[0])] = Derivation(step: result.step, needs: before, order: order, mark: nil)
                            progressed = true
                        } else if parts.count > 1, total(of: parts) == nil, sums[parts.sorted()] == nil {
                            let id = sums.count
                            sums[parts.sorted()] = (.number(result.value), id)
                            order += 1
                            derivations[.sum(id)] = Derivation(step: result.step, needs: before, order: order, mark: nil)
                            progressed = true
                        }
                    }
                }
            }
        }
        // Along a line: two of the lengths between three of its points give the third.
        for line in diagram.lines where line.points.count >= 3 {
            let along = line.points
            for first in 0..<along.count {
                for middle in (first + 1)..<along.count {
                    for last in (middle + 1)..<along.count {
                        let near = [along[first], along[middle]].sorted(), far = [along[middle], along[last]].sorted(), whole = [along[first], along[last]].sorted()
                        let known = [lengths[near], lengths[far], lengths[whole]]
                        guard known.compactMap({ $0 }).count == 2 else { continue }
                        func written(_ key: [Int]) -> Expr { lengths[key].map { lengthLine(.symbol(""), $0).parts[1] } ?? .symbol(name(ofLength: key)) }
                        if let a = known[0], let b = known[1] {
                            let step = Step("Add the lengths along the line", "", [MathLine(.symbol(name(ofLength: whole)), .add([written(near), written(far)]))])
                            found(length: whole, a + b, step, needs: [.length(near[0], near[1]), .length(far[0], far[1])])
                        } else if let total = known[2], let part = known[0] ?? known[1], total > part {
                            let missing = known[0] == nil ? near : far, other = known[0] == nil ? far : near
                            let step = Step("Take away the part that's known", "", [MathLine(.symbol(name(ofLength: missing)), .add([written(whole), .multiply([.minusOne, written(other)])]))])
                            found(length: missing, total - part, step, needs: [.length(whole[0], whole[1]), .length(other[0], other[1])])
                        } else {
                            continue
                        }
                        progressed = true
                    }
                }
            }
        }
        // Lengths the question says are equal.
        for pair in diagram.equal where pair.first.count == 2 && pair.second.count == 2 {
            let first = pair.first.sorted(), second = pair.second.sorted()
            for (known, other) in [(first, second), (second, first)] {
                guard let size = lengths[known], lengths[other] == nil else { continue }
                let step = Step("Equal lengths", "The question says \(name(ofLength: known)) and \(name(ofLength: other)) are the same length.",
                                [MathLine(.symbol(name(ofLength: other)), lengthLine(.symbol(""), size).parts[1])])
                found(length: other, size, step, needs: [.length(known[0], known[1])])
                progressed = true
            }
        }
        return progressed
    }

    /// The value of an angle so far, as it's written: a number, or with letters still in it.
    private func amount(_ angle: Angle) -> CircleDiagram.Amount? {
        total(of: sectors(angle))?.amount
    }

    /// What some neighbouring angles add up to, if that's known: each of them, or the ones
    /// that aren't as a total.
    private func total(of parts: [Int]) -> (amount: CircleDiagram.Amount, needs: [Found])? {
        var total = CircleDiagram.Amount()
        var needs: [Found] = []
        var missing: [Int] = []
        for sector in parts {
            if let known = value[sector] {
                total = total + known.with(letters)
                needs.append(.sector(sector))
            } else {
                missing.append(sector)
            }
        }
        if !missing.isEmpty {
            guard let known = sums[missing.sorted()] else { return nil }
            total = total + known.amount.with(letters)
            needs.append(.sum(known.id))
        }
        return (total, needs)
    }

    /// The point an angle between neighbouring lines is at, and the angle that spans a run of them.
    private func spanning(_ parts: [Int]) -> Angle {
        let vertex = firstSector.indices.last { firstSector[$0] <= parts[0] && rays[$0].count >= 2 } ?? 0
        let count = rays[vertex].count
        return Angle(vertex: vertex, from: parts[0] - firstSector[vertex], to: (parts[parts.count - 1] - firstSector[vertex] + 1) % count)
    }

    /// The step where a fact gives the total of some neighbouring angles.
    private func step(_ fact: Fact, totalling parts: [Int], _ amount: CircleDiagram.Amount) -> Step {
        let name = Expr.symbol(self.name(of: spanning(parts)))
        guard let place = fact.terms.firstIndex(where: { term in parts.allSatisfy { sectors(term.angle).contains($0) } }) else {
            return Step(fact.title, fact.reason, [MathLine(name, amount.expr, suffix: amount.isNumber ? "°" : nil)])
        }
        var terms = fact.terms, total = fact.total
        if terms[place].coefficient < 0 {
            terms = terms.map { (-$0.coefficient, $0.angle) }
            total = total * -1
        }
        var others: [(Double, Expr)] = [], filled: [(Double, Expr)] = []
        for (index, term) in terms.enumerated() where index != place {
            others.append((term.coefficient, label(term.angle)))
            filled.append((term.coefficient, self.amount(term.angle)?.expr ?? label(term.angle)))
        }
        // The known angles inside the same term come off too.
        for sector in sectors(terms[place].angle) where !parts.contains(sector) {
            if let known = value[sector]?.with(letters) {
                others.append((terms[place].coefficient, known.expr))
                filled.append((terms[place].coefficient, known.expr))
            }
        }
        let lines = [MathLine(name, isolated(others, total: total, over: terms[place].coefficient)),
                     MathLine(name, isolated(filled, total: total, over: terms[place].coefficient)),
                     MathLine(name, amount.expr, suffix: amount.isNumber ? "°" : nil)]
        return Step(fact.title, fact.reason, tidied(lines))
    }

    /// `total` less the other terms, over the number in front of the one being found.
    private func isolated(_ others: [(Double, Expr)], total: CircleDiagram.Amount, over divisor: Double) -> Expr {
        var parts: [Expr] = []
        let hasTotal = abs(total.constant) > 1e-9 || !total.isNumber
        if hasTotal { parts.append(total.expr) }
        for (coefficient, expr) in others {
            let k = -coefficient
            if abs(k - 1) < 1e-9 {
                parts.append(expr)
            } else if abs(k + 1) < 1e-9 {
                parts.append(.multiply([.minusOne, expr]))
            } else {
                parts.append(.multiply([CircleDiagram.number(k), expr]))
            }
        }
        // What's added before what's taken away.
        func isNegative(_ expr: Expr) -> Bool {
            if case .multiply(let factors) = expr, let first = factors.first?.number { return first.isNegative }
            return false
        }
        parts = parts.filter { !isNegative($0) } + parts.filter(isNegative)
        var sum = parts.isEmpty ? Expr.zero : (parts.count == 1 ? parts[0] : .add(parts))
        if abs(divisor - 1) > 1e-9 {
            if abs(divisor - divisor.rounded()) < 1e-9, abs(divisor) >= 2 {
                sum = .multiply([sum, .power(CircleDiagram.number(divisor), .minusOne)])
            } else {
                sum = .multiply([CircleDiagram.number(1 / divisor), sum])
            }
        }
        return sum
    }

    /// The step where a fact gives one more angle.
    private func step(_ fact: Fact, finding sector: Int) -> Step {
        guard let place = fact.terms.firstIndex(where: { sectors($0.angle).contains(sector) }),
              fact.terms.filter({ sectors($0.angle).contains(sector) }).count == 1 else {
            return Step(fact.title, fact.reason, value[sector].map { [MathLine($0.expr, suffix: "°")] } ?? [])
        }
        var terms = fact.terms, total = fact.total
        if terms[place].coefficient < 0 {
            terms = terms.map { (-$0.coefficient, $0.angle) }
            total = total * -1
        }
        let found = terms[place]
        let others = terms.enumerated().filter { $0.offset != place }.map(\.element)
        let name = Expr.symbol(self.name(of: found.angle))
        let written = isolated(others.map { ($0.coefficient, label($0.angle)) }, total: total, over: found.coefficient)
        let filled = isolated(others.map { ($0.coefficient, amount($0.angle)?.expr ?? label($0.angle)) }, total: total, over: found.coefficient)
        // The whole angle, then the part of it that wasn't known.
        let parts = sectors(found.angle)
        var whole = CircleDiagram.Amount()
        for part in parts { whole = whole + (value[part]?.with(letters) ?? CircleDiagram.Amount()) }
        var lines = [MathLine(name, written), MathLine(name, filled), MathLine(name, whole.expr, suffix: whole.isNumber ? "°" : nil)]
        if parts.count > 1, let index = parts.firstIndex(of: sector) {
            let count = rays[found.angle.vertex].count
            let first = (found.angle.from + index) % count
            let part = Angle(vertex: found.angle.vertex, from: first, to: (first + 1) % count)
            let rest = parts.filter { $0 != sector }.compactMap { other -> (Double, Expr)? in
                guard let known = value[other] else { return nil }
                return (1, known.with(letters).expr)
            }
            let partName = Expr.symbol(self.name(of: part))
            lines.append(MathLine(partName, isolated(rest, total: whole, over: 1)))
            if let amount = value[sector]?.with(letters) { lines.append(MathLine(partName, amount.expr, suffix: amount.isNumber ? "°" : nil)) }
        }
        return Step(fact.title, fact.reason, tidied(lines))
    }

    /// The step where a fact, with every angle in it known in terms of a letter, gives the letter.
    private func step(_ fact: Fact, solving letter: String) -> Step {
        func sides(_ write: (Angle) -> Expr) -> MathLine {
            var left: [Expr] = [], right: [Expr] = []
            for (coefficient, angle) in fact.terms {
                let size = abs(coefficient)
                let term: Expr = abs(size - 1) < 1e-9 ? write(angle) : .multiply([CircleDiagram.number(size), write(angle)])
                if coefficient > 0 { left.append(term) } else { right.append(term) }
            }
            if abs(fact.total.constant) > 1e-9 || !fact.total.isNumber || right.isEmpty { right.insert(fact.total.expr, at: 0) }
            if left.isEmpty { left = [.zero] }
            return MathLine(left.count == 1 ? left[0] : .add(left), right.count == 1 ? right[0] : .add(right))
        }
        // Before the letter is put in: its value isn't known yet at this point.
        var before = letters
        before[letter] = nil
        func filled(_ angle: Angle) -> Expr {
            var total = CircleDiagram.Amount()
            for sector in sectors(angle) { total = total + (value[sector]?.with(before) ?? CircleDiagram.Amount()) }
            return total.expr
        }
        var lines = [sides(label), sides(filled)]
        // Everything with the letter on one side.
        var rest = CircleDiagram.Amount()
        for (coefficient, angle) in fact.terms {
            for sector in sectors(angle) { rest = rest + (value[sector]?.with(before) ?? CircleDiagram.Amount()) * coefficient }
        }
        rest = rest - fact.total.with(before)
        var coefficient = rest.letters[letter] ?? 1
        var constant = -rest.constant
        if coefficient < 0 { coefficient = -coefficient; constant = -constant }
        let multiple: Expr = abs(coefficient - 1) < 1e-9 ? .symbol(letter) : .multiply([CircleDiagram.number(coefficient), .symbol(letter)])
        lines.append(MathLine(multiple, CircleDiagram.number(constant)))
        lines.append(MathLine(.symbol(letter), CircleDiagram.number(constant / coefficient), suffix: "°"))
        return Step(fact.title, fact.reason, tidied(lines))
    }

    /// Without lines that say the same as the one before, or nothing at all.
    private func tidied(_ lines: [MathLine]) -> [MathLine] {
        var result: [MathLine] = []
        for line in lines {
            let text = line.text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
            if let last = result.last, last.text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces) == text {
                // The later one may be the one with the degree sign.
                if line.suffix != nil { result[result.count - 1] = line }
                continue
            }
            if line.parts.count == 2, Format.text(line.parts[0]) == Format.text(line.parts[1]) { continue }
            result.append(line)
        }
        return result
    }
}

extension CircleDiagram {
    /// The lines leaving a point, in order anticlockwise: which way each goes, and the
    /// nearest point along it.
    func directions(at vertex: Int) -> [(direction: Double, towards: Int)] {
        var result: [(direction: Double, towards: Int)] = []
        for line in lines {
            guard let place = line.points.firstIndex(of: vertex) else { continue }
            for next in [place - 1, place + 1] where line.points.indices.contains(next) {
                let here = points[vertex], there = points[line.points[next]]
                result.append((atan2(there.y - here.y, there.x - here.x), line.points[next]))
            }
        }
        return result.sorted { $0.direction < $1.direction }
    }
}
