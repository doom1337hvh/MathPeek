import Foundation

/// A diagram read from a picture.
enum Diagram: Sendable {
    case circle(CircleDiagram)
    case triangle(TriangleDiagram)

    /// Everything in it that can be worked out, each with its working.
    var solutions: [Solution] {
        switch self {
        case .circle(let diagram): CircleTheorems.solve(diagram)
        case .triangle(let diagram): Triangles.solve(diagram)
        }
    }
}

/// A triangle as it's drawn: its three corners, and what's written in each corner and along
/// each side. Side 0 is opposite corner 0, and so on.
struct TriangleDiagram: Sendable {
    /// What's written: a number, a letter to find, or nothing.
    enum Mark: Sendable, Equatable {
        case number(Double)
        case letter(String)
    }

    struct Corner: Sendable {
        var name: String?
        var x: Double
        var y: Double
        var angle: Mark?
    }

    var corners: [Corner]
    var sides: [Mark?]
    /// cm, m: what the lengths are in, if the diagram says.
    var unit: String?
    /// What the question asks for, as the working names them: "QR", "∠PQR", "x".
    var asked: [String] = []
}

/// Works out the sides and angles of a triangle from the ones that are given: angles in a
/// triangle, Pythagoras and the sine, cosine and tangent ratios where there's a right angle,
/// and the sine and cosine rules where there isn't.
struct Triangles {
    private let diagram: TriangleDiagram
    private var names: [String] = []
    private var madeUp = false
    private var angles: [Double?]
    private var sides: [Double?]
    /// The step that gave each angle and side, and what it needed first.
    private var angleSteps: [(step: Step, needs: [Int])?] = [nil, nil, nil]
    private var sideSteps: [(step: Step, needs: [Int])?] = [nil, nil, nil]
    private var order: [Int] = []
    /// Corners said to be obtuse (true) or acute (false), where the sine rule could give either.
    private var obtuse: [Int: Bool] = [:]
    /// The other size an angle found by the sine rule could be, where nothing given rules it out.
    private var second: [Int: Double] = [:]

    private init(_ diagram: TriangleDiagram) {
        self.diagram = diagram
        angles = diagram.corners.map { if case .number(let value) = $0.angle { value } else { nil } }
        sides = diagram.sides.map { if case .number(let value) = $0 { value } else { nil } }
    }

    static func solve(_ diagram: TriangleDiagram) -> [Solution] {
        guard diagram.corners.count == 3, diagram.sides.count == 3 else { return [] }
        var triangle = Triangles(diagram)
        return triangle.solutions()
    }

    /// What follows in one triangle of a bigger figure from what's known of it, in the order
    /// it's found: each angle (0 to 2) or side (3 to 5), its size, the step that gave it and
    /// what that step needed. `names` are its corners' letters.
    static func deductions(in diagram: TriangleDiagram, names: [String], obtuse: [Int: Bool]) -> [(item: Int, value: Double, step: Step, needs: [Int])] {
        guard diagram.corners.count == 3, diagram.sides.count == 3, names.count == 3 else { return [] }
        var triangle = Triangles(diagram)
        triangle.names = names
        triangle.obtuse = obtuse
        let given = triangle.angles.compactMap { $0 }
        guard given.allSatisfy({ $0 > 0 && $0 < 180 }), given.count == 3 || given.reduce(0, +) < 180,
              triangle.sides.compactMap({ $0 }).allSatisfy({ $0 > 0 }) else { return [] }
        triangle.work()
        return triangle.order.compactMap { item in
            guard let found = item < 3 ? triangle.angleSteps[item] : triangle.sideSteps[item - 3],
                  let value = item < 3 ? triangle.angles[item] : triangle.sides[item - 3] else { return nil }
            return (item, value, found.step, found.needs)
        }
    }

    // MARK: Names

    /// Angles are 0 to 2 and sides 3 to 5, when one thing needs another.
    private func angleName(_ corner: Int) -> Expr {
        if case .letter(let letter) = diagram.corners[corner].angle { return .symbol(letter) }
        let others = [0, 1, 2].filter { $0 != corner }.map { names[$0] }.sorted()
        return .symbol("∠" + others[0] + names[corner] + others[1])
    }

    private func sideName(_ side: Int) -> Expr {
        if case .letter(let letter) = diagram.sides[side] { return .symbol(letter) }
        return .symbol([0, 1, 2].filter { $0 != side }.map { names[$0] }.sorted().joined())
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    /// A length to three significant figures; an angle to one decimal place.
    private static func length(_ value: Double) -> Double {
        guard value > 0 else { return value }
        let digits = Int(floor(log10(value))) + 1
        return rounded(value, places: max(3 - digits, 0))
    }

    private static func number(_ value: Double) -> Expr { CircleDiagram.number(value) }
    private func shown(side: Int) -> Expr { Self.number(Self.length(sides[side] ?? 0)) }
    private func shown(angle: Int) -> Expr { Self.number(Self.rounded(angles[angle] ?? 0, places: 1)) }

    /// "=" when the rounded value is the value, "≈" when it isn't.
    private static func relation(_ value: Double, _ shown: Double) -> String { abs(value - shown) < 1e-9 ? "=" : "≈" }

    private func sideLine(_ side: Int) -> MathLine {
        let value = sides[side] ?? 0, shown = Self.length(value)
        return MathLine(sideName(side), Self.number(shown), relation: Self.relation(value, shown), suffix: diagram.unit)
    }

    private func angleLine(_ corner: Int) -> MathLine {
        let value = angles[corner] ?? 0, shown = Self.rounded(value, places: 1)
        return MathLine(angleName(corner), Self.number(shown), relation: Self.relation(value, shown), suffix: "°")
    }

    private static func square(_ expr: Expr) -> Expr { .power(expr, .two) }
    private static func sine(_ expr: Expr) -> Expr { .function(.sin, expr) }
    private static func cosine(_ expr: Expr) -> Expr { .function(.cos, expr) }
    private static func over(_ top: Expr, _ bottom: Expr) -> Expr { .multiply([top, .power(bottom, .minusOne)]) }

    // MARK: Working it out

    private mutating func set(angle corner: Int, _ value: Double, _ title: String, _ why: String, _ lines: [MathLine], needs: [Int]) {
        angles[corner] = value
        angleSteps[corner] = (Step(title, why, lines + [angleLine(corner)]), needs)
        order.append(corner)
    }

    private mutating func set(side: Int, _ value: Double, _ title: String, _ why: String, _ lines: [MathLine], needs: [Int]) {
        sides[side] = value
        sideSteps[side] = (Step(title, why, lines + [sideLine(side)]), needs)
        order.append(side + 3)
    }

    private mutating func work() {
        var progressed = true
        while progressed {
            progressed = false
            // Angles in a triangle.
            let unknown = (0..<3).filter { angles[$0] == nil }
            if unknown.count == 1 {
                let corner = unknown[0], others = (0..<3).filter { $0 != corner }
                let value = 180 - (angles[others[0]] ?? 0) - (angles[others[1]] ?? 0)
                guard value > 0 else { return }
                set(angle: corner, value, "Angles in a triangle", "The angles in a triangle add up to 180°.",
                    [MathLine(angleName(corner), .add([.integer(180), .multiply([.minusOne, shown(angle: others[0])]), .multiply([.minusOne, shown(angle: others[1])])]))],
                    needs: others)
                progressed = true
                continue
            }
            if let right = (0..<3).first(where: { angles[$0].map { abs($0 - 90) < 1e-9 } ?? false }) {
                if rightAngled(at: right) { progressed = true; continue }
            }
            if sineRule() || cosineRule() { progressed = true }
        }
    }

    /// Pythagoras and the three ratios, in a triangle with a right angle.
    private mutating func rightAngled(at right: Int) -> Bool {
        let legs = (0..<3).filter { $0 != right }
        let known = (0..<3).filter { sides[$0] != nil }
        // Two sides give the third.
        if known.count == 2, let missing = (0..<3).first(where: { sides[$0] == nil }) {
            let why = "In a right-angled triangle, the square of the longest side (the hypotenuse, opposite the right angle) is the sum of the squares of the other two."
            if missing == right {
                let a = sides[legs[0]] ?? 0, b = sides[legs[1]] ?? 0
                let squared = a * a + b * b
                set(side: right, squared.squareRoot(), "Pythagoras' theorem", why,
                    [MathLine(Self.square(sideName(right)), .add([Self.square(shown(side: legs[0])), Self.square(shown(side: legs[1]))])),
                     MathLine(Self.square(sideName(right)), Self.number(Self.length(squared)), relation: Self.relation(squared, Self.length(squared)))],
                    needs: legs.map { $0 + 3 })
            } else {
                let other = legs.first { $0 != missing } ?? legs[0]
                let c = sides[right] ?? 0, a = sides[other] ?? 0
                let squared = c * c - a * a
                guard squared > 0 else { return false }
                set(side: missing, squared.squareRoot(), "Pythagoras' theorem", why,
                    [MathLine(Self.square(sideName(missing)), .add([Self.square(shown(side: right)), .multiply([.minusOne, Self.square(shown(side: other))])])),
                     MathLine(Self.square(sideName(missing)), Self.number(Self.length(squared)), relation: Self.relation(squared, Self.length(squared)))],
                    needs: [right + 3, other + 3])
            }
            return true
        }
        // One side and an angle give another side: the side opposite the angle, the one
        // next to it, and the hypotenuse.
        for corner in legs {
            guard let angle = angles[corner] else { continue }
            let opposite = corner, adjacent = legs.first { $0 != corner } ?? corner, hypotenuse = right
            let radians = angle * .pi / 180
            let ratios: [(name: String, function: MathFunction, top: Int, bottom: Int, value: Double, words: String)] = [
                ("Sine", .sin, opposite, hypotenuse, sin(radians), "sin = opposite ÷ hypotenuse"),
                ("Cosine", .cos, adjacent, hypotenuse, cos(radians), "cos = adjacent ÷ hypotenuse"),
                ("Tangent", .tan, opposite, adjacent, tan(radians), "tan = opposite ÷ adjacent"),
            ]
            for ratio in ratios {
                let written = Expr.function(ratio.function, shown(angle: corner))
                let why = "The triangle has a right angle, so \(ratio.words). For the angle \(Format.text(shown(angle: corner)))°, \(Format.text(sideName(opposite))) is opposite, \(Format.text(sideName(adjacent))) is adjacent and \(Format.text(sideName(hypotenuse))) is the hypotenuse."
                if let bottom = sides[ratio.bottom], sides[ratio.top] == nil {
                    set(side: ratio.top, bottom * ratio.value, "\(ratio.name) ratio", why,
                        [MathLine(written, Self.over(sideName(ratio.top), shown(side: ratio.bottom))),
                         MathLine(sideName(ratio.top), .multiply([shown(side: ratio.bottom), written]))],
                        needs: [corner, ratio.bottom + 3])
                    return true
                }
                if let top = sides[ratio.top], sides[ratio.bottom] == nil, ratio.value > 1e-9 {
                    set(side: ratio.bottom, top / ratio.value, "\(ratio.name) ratio", why,
                        [MathLine(written, Self.over(shown(side: ratio.top), sideName(ratio.bottom))),
                         MathLine(sideName(ratio.bottom), Self.over(shown(side: ratio.top), written))],
                        needs: [corner, ratio.top + 3])
                    return true
                }
            }
        }
        // Two sides give an angle.
        for corner in legs where angles[corner] == nil {
            let opposite = corner, adjacent = legs.first { $0 != corner } ?? corner, hypotenuse = right
            let choices: [(name: String, function: MathFunction, inverse: MathFunction, top: Int, bottom: Int, words: String)] = [
                ("Tangent", .tan, .atan, opposite, adjacent, "tan = opposite ÷ adjacent"),
                ("Sine", .sin, .asin, opposite, hypotenuse, "sin = opposite ÷ hypotenuse"),
                ("Cosine", .cos, .acos, adjacent, hypotenuse, "cos = adjacent ÷ hypotenuse"),
            ]
            // Sides that were given come before ones worked out.
            let workedOut = (0..<3).map { sideSteps[$0] == nil ? 0 : 1 }
            let given = choices.sorted { workedOut[$0.top] + workedOut[$0.bottom] < workedOut[$1.top] + workedOut[$1.bottom] }
            for choice in given {
                guard let top = sides[choice.top], let bottom = sides[choice.bottom], bottom > 0 else { continue }
                let ratio = top / bottom
                guard ratio > 0, choice.function == .tan || ratio <= 1 else { continue }
                let value: Double = (choice.function == .tan ? atan(ratio) : (choice.function == .sin ? asin(ratio) : acos(ratio))) * 180 / .pi
                let fraction = Self.over(shown(side: choice.top), shown(side: choice.bottom))
                set(angle: corner, value, "\(choice.name) ratio",
                    "The triangle has a right angle, so \(choice.words). For this angle, \(Format.text(sideName(opposite))) is opposite, \(Format.text(sideName(adjacent))) is adjacent and \(Format.text(sideName(hypotenuse))) is the hypotenuse.",
                    [MathLine(.function(choice.function, angleName(corner)), fraction),
                     MathLine(angleName(corner), .function(choice.inverse, fraction))],
                    needs: [choice.top + 3, choice.bottom + 3])
                return true
            }
        }
        return false
    }

    /// A side and the angle opposite it, with one more side or angle.
    private mutating func sineRule() -> Bool {
        let why = "In any triangle, each side divided by the sine of the angle opposite it comes to the same."
        for pair in 0..<3 {
            guard let side = sides[pair], let angle = angles[pair], angle > 0, angle < 180 else { continue }
            let ratio = side / sin(angle * .pi / 180)
            for other in 0..<3 where other != pair {
                if let otherAngle = angles[other], sides[other] == nil {
                    set(side: other, ratio * sin(otherAngle * .pi / 180), "Sine rule", why,
                        [MathLine(Self.over(sideName(other), Self.sine(shown(angle: other))), Self.over(shown(side: pair), Self.sine(shown(angle: pair)))),
                         MathLine(sideName(other), Self.over(.multiply([shown(side: pair), Self.sine(shown(angle: other))]), Self.sine(shown(angle: pair))))],
                        needs: [pair + 3, pair, other])
                    return true
                }
                if let otherSide = sides[other], angles[other] == nil {
                    let sine = otherSide / ratio
                    guard sine > 0, sine <= 1 else { continue }
                    var value = asin(sine) * 180 / .pi
                    // Two angles have that sine. Opposite the shorter of the two sides it can
                    // only be the acute one. Opposite the longer it could be either: with all
                    // three sides known the cosine rule settles it; otherwise it's the obtuse
                    // one if the question says so, or that's how it's drawn.
                    var note = why
                    if otherSide > side + 1e-9 {
                        if sides.allSatisfy({ $0 != nil }) { continue }
                        if obtuse[other] ?? (drawn(other) > 95), value < 90 {
                            value = 180 - value
                            note += " Two angles have this sine; this one is obtuse, so it's 180° take away the one the calculator gives."
                        }
                    }
                    guard value + angle < 180 else { continue }
                    if otherSide > side + 1e-9, (180 - value) + angle < 180, abs(value - 90) > 0.05 { second[other] = 180 - value }
                    let fraction = Self.over(.multiply([shown(side: other), Self.sine(shown(angle: pair))]), shown(side: pair))
                    set(angle: other, value, "Sine rule", note,
                        [MathLine(Self.over(Self.sine(angleName(other)), shown(side: other)), Self.over(Self.sine(shown(angle: pair)), shown(side: pair))),
                         MathLine(Self.sine(angleName(other)), fraction)],
                        needs: [pair + 3, pair, other + 3])
                    return true
                }
            }
        }
        return false
    }

    /// Two sides and the angle between them, or all three sides.
    private mutating func cosineRule() -> Bool {
        for corner in 0..<3 {
            let others = (0..<3).filter { $0 != corner }
            guard let b = sides[others[0]], let c = sides[others[1]] else { continue }
            if let angle = angles[corner], sides[corner] == nil {
                let squared = b * b + c * c - 2 * b * c * cos(angle * .pi / 180)
                guard squared > 0 else { continue }
                set(side: corner, squared.squareRoot(), "Cosine rule",
                    "With two sides and the angle between them: the square of the third side is the sum of their squares, less twice their product times the cosine of the angle.",
                    [MathLine(Self.square(sideName(corner)),
                              .add([Self.square(shown(side: others[0])), Self.square(shown(side: others[1])),
                                    .multiply([.integer(-2), shown(side: others[0]), shown(side: others[1]), Self.cosine(shown(angle: corner))])])),
                     MathLine(Self.square(sideName(corner)), Self.number(Self.length(squared)), relation: Self.relation(squared, Self.length(squared)))],
                    needs: [others[0] + 3, others[1] + 3, corner])
                return true
            }
            if let a = sides[corner], angles[corner] == nil {
                let cosine = (b * b + c * c - a * a) / (2 * b * c)
                guard abs(cosine) <= 1 else { continue }
                let top = Expr.add([Self.square(shown(side: others[0])), Self.square(shown(side: others[1])), .multiply([.minusOne, Self.square(shown(side: corner))])])
                let bottom = Expr.multiply([.two, shown(side: others[0]), shown(side: others[1])])
                let shownCosine = Self.rounded(cosine, places: 4)
                set(angle: corner, acos(cosine) * 180 / .pi, "Cosine rule",
                    "With all three sides, the cosine of an angle is the sum of the squares of the sides either side of it, less the square of the side opposite, over twice the product of the sides either side.",
                    [MathLine(Self.cosine(angleName(corner)), Self.over(top, bottom)),
                     MathLine(Self.cosine(angleName(corner)), Self.number(shownCosine), relation: Self.relation(cosine, shownCosine))],
                    needs: others.map { $0 + 3 } + [corner + 3])
                return true
            }
        }
        return false
    }

    /// An angle as it's drawn, in degrees.
    private func drawn(_ corner: Int) -> Double {
        let here = diagram.corners[corner], others = (0..<3).filter { $0 != corner }.map { diagram.corners[$0] }
        let a = (others[0].x - here.x, others[0].y - here.y), b = (others[1].x - here.x, others[1].y - here.y)
        let cosine = (a.0 * b.0 + a.1 * b.1) / max(hypot(a.0, a.1) * hypot(b.0, b.1), 1e-9)
        return acos(min(max(cosine, -1), 1)) * 180 / .pi
    }

    // MARK: Answers

    private mutating func solutions() -> [Solution] {
        // Points with no letter get one.
        let taken = Set(diagram.corners.compactMap(\.name))
        let spare: [String] = ["A", "B", "C", "P", "Q", "R"].filter { !taken.contains($0) }
        var next = spare.makeIterator()
        names = []
        for corner in diagram.corners {
            if let name = corner.name {
                names.append(name)
            } else {
                madeUp = true
                names.append(next.next() ?? "?")
            }
        }
        // What's given has to make a triangle.
        let givenAngles = angles.compactMap { $0 }
        guard givenAngles.allSatisfy({ $0 > 0 && $0 < 180 }), givenAngles.reduce(0, +) < 180 || givenAngles.count == 3 else { return [] }
        if givenAngles.count == 3, abs(givenAngles.reduce(0, +) - 180) > 0.5 { return [] }
        guard sides.compactMap({ $0 }).allSatisfy({ $0 > 0 }) else { return [] }
        // A letter stands for one thing.
        let letters = (diagram.corners.map(\.angle) + diagram.sides).compactMap { mark -> String? in if case .letter(let letter) = mark { letter } else { nil } }
        guard Set(letters).count == letters.count else { return [] }
        work()

        var found: [(target: Int, title: String, line: MathLine)] = []
        func add(_ target: Int) {
            let isAngle = target < 3
            guard (isAngle ? angleSteps[target] : sideSteps[target - 3]) != nil else { return }
            let name = Format.text(isAngle ? angleName(target) : sideName(target - 3))
            found.append((target, name, isAngle ? angleLine(target) : sideLine(target - 3)))
        }
        if letters.isEmpty || !diagram.asked.isEmpty {
            order.forEach(add)
        }
        if !letters.isEmpty {
            for corner in 0..<3 { if case .letter = diagram.corners[corner].angle { add(corner) } }
            for side in 0..<3 { if case .letter = diagram.sides[side] { add(side + 3) } }
            found.sort { $0.title < $1.title }
        }
        // What the question asks for comes first.
        if !diagram.asked.isEmpty {
            var seen: Set<String> = []
            found = found.filter { seen.insert($0.title).inserted }
            found = found.filter { diagram.asked.contains($0.title) } + found.filter { !diagram.asked.contains($0.title) }
        }
        // Wildly unlike the drawing means something was misread.
        for corner in 0..<3 {
            if let angle = angles[corner], abs(angle - drawn(corner)) > 50 { return [] }
        }
        var solutions = found.map { item in
            let problem = Problem(kind: .diagram(.triangle(diagram), find: item.title), text: item.title, usesDecimals: true)
            var answers = [item.line], steps = working(for: item.target)
            // "There are two possible values": the sine rule's other angle too.
            if diagram.asked.contains("Both"), item.target < 3, let other = second[item.target], let first = angles[item.target] {
                let shown = Self.rounded(other, places: 1), given = Self.rounded(first, places: 1)
                let line = MathLine(angleName(item.target), Self.number(shown), relation: Self.relation(other, shown), suffix: "°")
                answers = first < other ? [item.line, line] : [line, item.line]
                steps.append(Step("The other angle with the same sine", "Two angles under 180° have the same sine: they add up to 180°.",
                                  [MathLine(.add([.integer(180), .multiply([.minusOne, Self.number(given)])]), Self.number(shown), suffix: "°")]))
            }
            return Solution(problem: problem, question: MathLine(.symbol(item.title)), task: "Find", answers: answers, approximation: nil, steps: steps)
        }
        // The area, when that's what the question asks for: half of two sides, times the
        // sine of the angle between them. From what was given, where it can be.
        if diagram.asked.contains("Area") {
            let corners = (0..<3).filter { corner in
                let others = (0..<3).filter { $0 != corner }
                return angles[corner] != nil && sides[others[0]] != nil && sides[others[1]] != nil
            }.sorted { a, b in
                func derived(_ corner: Int) -> Int { (angleSteps[corner] == nil ? 0 : 1) + (0..<3).filter { $0 != corner && sideSteps[$0] != nil }.count }
                return derived(a) < derived(b)
            }
            if let corner = corners.first, let angle = angles[corner] {
                let others = (0..<3).filter { $0 != corner }
                let area = 0.5 * (sides[others[0]] ?? 0) * (sides[others[1]] ?? 0) * sin(angle * .pi / 180)
                let nearest = Self.length(area)
                let line = MathLine(.symbol("Area"), Self.number(nearest), relation: Self.relation(area, nearest), suffix: diagram.unit.map { $0 + "²" })
                var steps: [Step] = []
                var seen: Set<UUID> = []
                for item in [corner, others[0] + 3, others[1] + 3] {
                    for step in working(for: item) where seen.insert(step.id).inserted && !steps.contains(where: { $0.title == step.title && $0.lines == step.lines }) { steps.append(step) }
                }
                let right = abs(angle - 90) < 1e-9
                steps.append(Step("Area of a triangle", right ? "Half the base times the height: the two sides at the right angle."
                                                              : "Half of two sides multiplied together, times the sine of the angle between them.",
                                  [MathLine(.symbol("Area"), .multiply(right ? [.half, shown(side: others[0]), shown(side: others[1])]
                                                                             : [.half, shown(side: others[0]), shown(side: others[1]), Self.sine(shown(angle: corner))])), line]))
                let problem = Problem(kind: .diagram(.triangle(diagram), find: "Area"), text: "Area", usesDecimals: true)
                solutions.insert(Solution(problem: problem, question: MathLine(.symbol("Area")), task: "Find", answers: [line], approximation: nil, steps: steps), at: 0)
            }
        }
        return solutions
    }

    private func working(for target: Int) -> [Step] {
        var seen: Set<Int> = []
        func collect(_ item: Int) {
            guard seen.insert(item).inserted else { return }
            (item < 3 ? angleSteps[item] : sideSteps[item - 3])?.needs.forEach(collect)
        }
        collect(target)
        var steps: [Step] = []
        // What it starts from.
        var givens: [MathLine] = []
        for item in seen.sorted() {
            if item < 3, angleSteps[item] == nil, let value = angles[item] {
                givens.append(MathLine(angleName(item), Self.number(value), suffix: "°"))
            } else if item >= 3, sideSteps[item - 3] == nil, let value = sides[item - 3] {
                givens.append(MathLine(sideName(item - 3), Self.number(value), suffix: diagram.unit))
            }
        }
        if !givens.isEmpty { steps.append(Step("From the diagram", "", givens)) }
        for item in order where seen.contains(item) {
            if let step = (item < 3 ? angleSteps[item] : sideSteps[item - 3])?.step { steps.append(step) }
        }
        let written = steps.flatMap(\.lines).map(\.text).joined(separator: " ")
        if madeUp, names.enumerated().contains(where: { diagram.corners[$0.offset].name == nil && written.contains($0.element) }) {
            steps.insert(Step("Name the corners", naming()), at: 0)
        }
        return steps
    }

    private func naming() -> String {
        let middle = (x: diagram.corners.map(\.x).reduce(0, +) / 3, y: diagram.corners.map(\.y).reduce(0, +) / 3)
        let parts = diagram.corners.indices.filter { diagram.corners[$0].name == nil }.map { index -> String in
            let corner = diagram.corners[index]
            let across = corner.x - middle.x, up = corner.y - middle.y
            let where_ = abs(up) > abs(across) * 1.5 ? (up > 0 ? "at the top" : "at the bottom")
                : (abs(across) > abs(up) * 1.5 ? (across > 0 ? "on the right" : "on the left")
                   : (up > 0 ? "at the top " : "at the bottom ") + (across > 0 ? "right" : "left"))
            return "\(names[index]) is the corner \(where_)"
        }
        return "These corners have no letters in the diagram. " + parts.joined(separator: ", ") + "."
    }
}
