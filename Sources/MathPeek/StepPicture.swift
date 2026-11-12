import Charts
import SwiftUI

/// A picture of what one step of the working did, chosen from the maths itself rather than
/// from what kind of problem it is: curves for anything with a letter in it, lines crossing
/// for two letters, and for plain numbers a number line, an area, fraction bars or a bar
/// cut into shares.
enum StepPicture {
    /// Curves in one letter: before the step (faint) and after it, with the answers marked.
    case graph(Curves)
    /// Equations in two letters, drawn as lines across a grid, and where they cross.
    case plane(Lines)
    /// Starting at a number and moving along by each of the others, to the result.
    case numberLine(start: Double, moves: [Double], result: Double)
    /// Two numbers multiplied: a rectangle with those sides, and the area it makes.
    case area(Double, Double, result: Double)
    /// Fractions, a row of bars for each side of each line, labelled as it's written.
    case fractions([(label: String, terms: [Rational])])
    /// A fraction of an amount: the amount cut into equal shares, some of them taken.
    case portion(Rational, of: Double, result: Double)

    struct Curves {
        var variable: String
        var before: [(label: String, expr: Expr)]
        var after: [(label: String, expr: Expr)]
        var marks: [Double]
        /// Curves that are the right-hand side of an equation, drawn white beside the blue.
        var otherSides: Set<Int> = []
    }

    struct Lines {
        var across: String
        var up: String
        var before: [(label: String, equation: Equation)]
        var after: [(label: String, equation: Equation)]
    }

    // MARK: Choosing a picture

    /// The picture for step `index` of a solution's roadmap, if there's one worth showing.
    static func make(for steps: [Step], at index: Int, in solution: Solution) -> StepPicture? {
        guard steps.indices.contains(index) else { return nil }
        let step = steps[index]
        guard !step.lines.isEmpty else { return nil }
        let isSolving: Bool = if case .solve = solution.problem.kind { true } else { false }
        if case .diagram = solution.problem.kind { return nil }
        if case .remainder = solution.problem.kind { return nil }
        // Where the step starts from: the line before it, or the question.
        let previous = steps[..<index].last { !$0.lines.isEmpty }?.lines ?? solution.problem.kind.lines
        guard step.lines.allSatisfy({ ["=", "→"].contains($0.relation) }) else { return nil }

        if isSolving {
            let after = step.lines.compactMap(equation)
            let before = previous.compactMap(equation)
            guard !after.isEmpty else { return nil }
            let letters = Set((after + before).flatMap { [$0.0.left, $0.0.right] }.flatMap(\.symbols))
            guard letters.allSatisfy({ $0.count == 1 }) else { return nil }
            if letters.count == 1, let variable = letters.first {
                let marks = after.flatMap { roots(of: .add([$0.0.left, .multiply([.minusOne, $0.0.right])]), variable) }
                func sides(_ items: [(Equation, String)]) -> [(String, Expr)] {
                    items.flatMap { item in [(item.1, item.0.left), (item.1, item.0.right)] }
                }
                // A step that doesn't change the equation (only says it) has nothing before it.
                let unchanged = before.map(\.1) == after.map(\.1)
                let drawn = sides(after)
                let picture = Curves(variable: variable,
                                     before: sides(unchanged ? [] : before).map { (label: $0.0, expr: $0.1) },
                                     after: drawn.map { (label: $0.0, expr: $0.1) },
                                     marks: Array(Set(marks.map { ($0 * 1e6).rounded() / 1e6 })).sorted(),
                                     otherSides: Set(drawn.indices.filter { $0 % 2 == 1 }))
                return picture.isDrawable ? .graph(picture) : nil
            }
            if letters.count == 2 {
                let names = letters.sorted()
                let lines = Lines(across: names[0], up: names[1],
                                  before: before.filter { !$0.0.left.symbols.union($0.0.right.symbols).isEmpty && !after.map(\.1).contains($0.1) }
                                      .map { (label: $0.1, equation: $0.0) },
                                  after: after.map { (label: $0.1, equation: $0.0) })
                return .plane(lines)
            }
            return nil
        }

        // Rewriting: each line is what it was, then what it became; a line on its own is
        // what the step before it became.
        var before: [Expr] = [], after: [Expr] = []
        for line in step.lines {
            if line.parts.count >= 2 {
                before.append(line.parts[0])
                after.append(line.parts[line.parts.count - 1])
            } else if let part = line.parts.first {
                if let last = previous.last?.parts.last { before.append(last) }
                after.append(part)
            }
        }
        guard !after.isEmpty else { return nil }
        let letters = Set((before + after).flatMap(\.symbols))
        guard letters.allSatisfy({ $0.count == 1 }) else { return nil }
        if letters.count == 1, let variable = letters.first {
            // Brackets multiplied together: where each is zero is worth seeing.
            let marks = after.flatMap { expr -> [Double] in
                if case .multiply(let factors) = expr, factors.contains(where: { if case .add = $0 { true } else { false } }) {
                    return roots(of: expr, variable)
                }
                return []
            }
            let picture = Curves(variable: variable,
                                 before: before.filter { !after.contains($0) }.map { (label: Format.text($0), expr: $0) },
                                 after: after.map { (label: Format.text($0), expr: $0) },
                                 marks: marks)
            return picture.isDrawable ? .graph(picture) : nil
        }
        guard letters.isEmpty else { return nil }

        // Plain numbers. Fractions, when there are any to see.
        let lines = step.lines.flatMap { $0.parts }
        let rows = lines.compactMap { part in fractionRow(part).map { (label: Format.text(part), terms: $0) } }
        if rows.count == lines.count, rows.contains(where: { $0.terms.contains { !$0.isInteger } }) {
            return .fractions(rows)
        }
        // Otherwise what the step worked out: the part of the sum that became a number.
        guard let from = before.first, let to = after.first, let (was, became) = changed(from, to) else { return nil }
        return numbers(was, became)
    }

    private static func equation(_ line: MathLine) -> (Equation, String)? {
        guard line.relation == "=", line.parts.count == 2 else { return nil }
        return (Equation(left: line.parts[0], right: line.parts[1]), line.text)
    }

    /// Where an expression in one letter is zero, between −50 and 50.
    private static func roots(of expr: Expr, _ variable: String) -> [Double] {
        var found: [Double] = []
        var x = -50.0, last = expr.evaluate([variable: x])
        while x < 50 {
            let next = x + 0.05
            let value = expr.evaluate([variable: next])
            if let a = last, let b = value, a.isFinite, b.isFinite {
                if a == 0 { found.append(x) } else if a * b < 0, abs(a - b) < 1e6 {
                    // Narrowed down by halving.
                    var low = x, high = next, lowValue = a
                    for _ in 0..<50 {
                        let middle = (low + high) / 2
                        guard let m = expr.evaluate([variable: middle]) else { break }
                        if (m < 0) == (lowValue < 0) { low = middle; lowValue = m } else { high = middle }
                    }
                    found.append((low + high) / 2)
                }
            }
            x = next
            last = value
        }
        return found.prefix(6).map { ($0 * 1e6).rounded() / 1e6 }
    }

    /// The part of `from` that was worked out to give `to`: the smallest piece that differs.
    private static func changed(_ from: Expr, _ to: Expr) -> (Expr, Expr)? {
        guard from != to else { return nil }
        switch (from, to) {
        case (.add(let a), .add(let b)) where a.count == b.count, (.multiply(let a), .multiply(let b)) where a.count == b.count:
            let differing = zip(a, b).filter { $0 != $1 }
            if differing.count == 1 { return changed(differing[0].0, differing[0].1) }
        case (.add(let a), .add(let b)) where a.count > b.count:
            // Some terms put together: the ones that went, and what they became.
            var gone = a, came = b
            for term in b { if let at = gone.firstIndex(of: term) { gone.remove(at: at); came.removeAll { $0 == term } } }
            if came.count == 1, gone.count >= 2 { return (.add(gone), came[0]) }
        case (.multiply(let a), .multiply(let b)) where a.count > b.count:
            var gone = a, came = b
            for factor in b { if let at = gone.firstIndex(of: factor) { gone.remove(at: at); came.removeAll { $0 == factor } } }
            if came.count == 1, gone.count >= 2 { return (.multiply(gone), came[0]) }
        default:
            break
        }
        return (from, to)
    }

    /// A picture of a sum of plain numbers worked out.
    private static func numbers(_ was: Expr, _ became: Expr) -> StepPicture? {
        guard let result = became.evaluate(), result.isFinite else { return nil }
        switch was {
        case .add(let terms):
            let values = terms.compactMap { $0.evaluate() }
            guard values.count == terms.count, values.count >= 2, values.allSatisfy({ abs($0) < 1e7 }) else { return nil }
            return .numberLine(start: values[0], moves: Array(values.dropFirst()), result: result)
        case .multiply(let factors):
            // A fraction of an amount, or two numbers multiplied.
            if factors.count == 2, let first = exact(factors[0]), let second = factors[1].evaluate(),
               !first.isInteger, first.denominator <= 24, first.numerator > 0, first.double < 1, second > 0 {
                return .portion(first, of: second, result: result)
            }
            if factors.count == 2, let second = exact(factors[1]), let first = factors[0].evaluate(),
               !second.isInteger, second.denominator <= 24, second.numerator > 0, second.double < 1, first > 0 {
                return .portion(second, of: first, result: result)
            }
            let values = factors.compactMap { $0.evaluate() }
            guard values.count == 2, values.allSatisfy({ $0 > 0 && $0 < 1e6 }) else { return nil }
            return .area(values[0], values[1], result: result)
        case .power(let base, let exponent):
            guard exponent.number?.double == 2, let side = base.evaluate(), side > 0, side < 1e6 else { return nil }
            return .area(side, side, result: result)
        default:
            return nil
        }
    }

    /// A number written exactly: 3, 9/12, 3/20.
    private static func exact(_ expr: Expr) -> Rational? {
        switch expr {
        case .number(let value): return value.rational
        case .multiply(let factors):
            var product = Rational(1)
            for factor in factors {
                guard let value = exact(factor), let next = product * value else { return nil }
                product = next
            }
            return product
        case .power(let base, let exponent):
            guard let value = exact(base), let power = exponent.number?.integer, abs(power) <= 6 else { return nil }
            if power < 0 { return value.power(-power).flatMap { Rational(1) / $0 } }
            return value.power(power)
        default:
            return nil
        }
    }

    /// One side of a line as fractions to draw: its terms, each a fraction no bigger than
    /// four wholes, in parts small enough to count.
    private static func fractionRow(_ expr: Expr) -> [Rational]? {
        let terms: [Expr] = if case .add(let parts) = expr { parts } else { [expr] }
        let values = terms.compactMap(exact)
        guard values.count == terms.count, values.allSatisfy({ $0.numerator >= 0 && $0.denominator <= 24 && $0.double <= 4 }) else { return nil }
        return values
    }
}

extension StepPicture.Curves {
    var isDrawable: Bool { !after.isEmpty && !after.allSatisfy { $0.expr.symbols.isEmpty && before.isEmpty } }
}

// MARK: Drawing

/// A step's picture, `width` points across.
struct StepPictureView: View {
    let picture: StepPicture
    let width: CGFloat
    let blue: Color

    var body: some View {
        switch picture {
        case .graph(let curves): CurvesView(curves: curves, width: width, blue: blue)
        case .plane(let lines): PlaneView(lines: lines, width: width, blue: blue)
        case .numberLine(let start, let moves, let result): NumberLineView(start: start, moves: moves, result: result, width: width, blue: blue)
        case .area(let a, let b, let result): AreaView(a: a, b: b, result: result, width: width, blue: blue)
        case .fractions(let rows): FractionBarsView(rows: rows, width: width, blue: blue)
        case .portion(let fraction, let amount, let result): PortionView(fraction: fraction, amount: amount, result: result, width: width, blue: blue)
        }
    }
}

private func shown(_ value: Double) -> String {
    Format.decimal((value * 10_000).rounded() / 10_000)
}

/// What each line of a picture is: a short dash in its colour and the maths it draws.
private struct Key: View {
    let items: [(label: String, color: Color, dashed: Bool)]
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Path { path in path.move(to: CGPoint(x: 0, y: 1)); path.addLine(to: CGPoint(x: 14, y: 1)) }
                        .stroke(item.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: item.dashed ? [3, 3] : []))
                        .frame(width: 14, height: 2)
                    Text(item.label)
                        .font(.system(size: size).monospacedDigit())
                        .foregroundStyle(Z.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct CurvesView: View {
    let curves: StepPicture.Curves
    let width: CGFloat
    let blue: Color

    private struct Point: Identifiable {
        let id: Int
        let series: String
        let x: Double
        let y: Double
        let isBefore: Bool
        let tone: Int
    }

    /// The labels, each once: an equation names both its sides.
    private var keyItems: [(label: String, color: Color, dashed: Bool)] {
        var seen: Set<String> = []
        var items: [(label: String, color: Color, dashed: Bool)] = []
        for item in curves.before where seen.insert("b" + item.label).inserted {
            items.append((item.label, Color.white.opacity(0.35), true))
        }
        for item in curves.after where seen.insert("a" + item.label).inserted {
            items.append((item.label, blue, false))
        }
        return items
    }

    var body: some View {
        let (points, range, yRange) = samples()
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                RuleMark(y: .value("zero", 0)).foregroundStyle(Color.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1))
                if range.contains(0) {
                    RuleMark(x: .value("zero", 0)).foregroundStyle(Color.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(points) { point in
                    LineMark(x: .value(curves.variable, point.x), y: .value("y", point.y), series: .value("Series", point.series))
                        .foregroundStyle(point.isBefore ? Color.white.opacity(0.32) : (point.tone == 0 ? blue : Color.white.opacity(0.75)))
                        .lineStyle(StrokeStyle(lineWidth: point.isBefore ? 1.5 : 2.2, lineCap: .round, dash: point.isBefore ? [4, 4] : []))
                }
                ForEach(Array(curves.marks.enumerated()), id: \.offset) { number, mark in
                    RuleMark(x: .value(curves.variable, mark))
                        .foregroundStyle(Z.yellow.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: number % 2 == 0 ? .top : .bottom, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            Text("\(curves.variable) = \(shown(mark))")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Z.yellow)
                                .fixedSize()
                        }
                }
            }
            .chartXScale(domain: range)
            .chartYScale(domain: yRange)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Z.tertiary)
            } }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Z.tertiary)
            } }
            .frame(width: width, height: width * 0.62)
            Key(items: keyItems, size: 11)
        }
    }

    /// Points along each curve, split where it jumps, the stretch of x to show (round the
    /// answers when there are some), and a y range that leaves out the extremes.
    private func samples() -> ([Point], ClosedRange<Double>, ClosedRange<Double>) {
        let range: ClosedRange<Double>
        if let low = curves.marks.min(), let high = curves.marks.max() {
            let half = max((high - low) * 0.8 + 2, 4)
            range = ((low + high) / 2 - half)...((low + high) / 2 + half)
        } else {
            range = -6...6
        }
        let all = curves.before.map { ($0, true) } + curves.after.map { ($0, false) }
        var raw: [(series: Int, x: Double, y: Double?, isBefore: Bool, tone: Int)] = []
        let count = 240
        for (index, item) in all.enumerated() {
            let tone = !item.1 && curves.otherSides.contains(index - curves.before.count) ? 1 : 0
            for i in 0...count {
                let x = range.lowerBound + Double(i) * (range.upperBound - range.lowerBound) / Double(count)
                raw.append((index, x, item.0.expr.evaluate([curves.variable: x]), item.1, tone))
            }
        }
        let ys = raw.compactMap(\.y).filter(\.isFinite).sorted()
        guard !ys.isEmpty else { return ([], range, -5...5) }
        var low = ys[Int(Double(ys.count - 1) * 0.04)], high = ys[Int(Double(ys.count - 1) * 0.96)]
        low = min(low, 0); high = max(high, 0)
        let pad = max((high - low) * 0.15, 1)
        let yRange = (low - pad)...(high + pad)
        var points: [Point] = []
        var segment = 0
        var previous: (Int, Double)?
        for (index, sample) in raw.enumerated() {
            guard let y = sample.y, y.isFinite, yRange.contains(y) else { segment += 1; previous = nil; continue }
            if let (series, lastY) = previous, series == sample.series, abs(y - lastY) > (yRange.upperBound - yRange.lowerBound) * 0.5 { segment += 1 }
            points.append(Point(id: index, series: "\(sample.series)#\(segment)", x: sample.x, y: y, isBefore: sample.isBefore, tone: sample.tone))
            previous = (sample.series, y)
        }
        return (points, range, yRange)
    }
}

/// Equations in two letters as lines, the ones after the step solid, and where they cross.
private struct PlaneView: View {
    let lines: StepPicture.Lines
    let width: CGFloat
    let blue: Color

    private struct Point: Identifiable {
        let id: Int
        let series: String
        let x: Double
        let y: Double
        let isBefore: Bool
    }

    /// Where `equation` is, as points across, or nil if it can't be drawn as a line.
    private func points(of equation: Equation, in range: ClosedRange<Double>, up upRange: ClosedRange<Double>) -> [(Double, Double)] {
        let difference = Expr.add([equation.left, .multiply([.minusOne, equation.right])])
        func value(_ a: Double, _ b: Double) -> Double? { difference.evaluate([lines.across: a, lines.up: b]) }
        var result: [(Double, Double)] = []
        // Straight in the upward letter: one point for each step across.
        for i in 0...60 {
            let a = range.lowerBound + Double(i) * (range.upperBound - range.lowerBound) / 60
            guard let zero = value(a, 0), let one = value(a, 1), abs(one - zero) > 1e-9 else { continue }
            result.append((a, -zero / (one - zero)))
        }
        if result.count >= 2 { return result }
        // Upright: the same across whatever it is upward.
        guard let zero = value(0, 0), let one = value(1, 0), abs(one - zero) > 1e-9 else { return [] }
        let a = -zero / (one - zero)
        return [(a, upRange.lowerBound), (a, upRange.upperBound)]
    }

    var body: some View {
        // Round where the lines after the step cross, if they do.
        let crossing = cross()
        let centre = crossing ?? (0, 0)
        let span = max(abs(centre.0), abs(centre.1)) + 5
        let range = (centre.0 - span)...(centre.0 + span)
        let upRange = (centre.1 - span)...(centre.1 + span)
        var all: [Point] = []
        for (index, item) in (lines.before.map { ($0, true) } + lines.after.map { ($0, false) }).enumerated() {
            for (number, point) in points(of: item.0.equation, in: range, up: upRange).enumerated() where upRange.contains(point.1) {
                all.append(Point(id: index * 1000 + number, series: "\(index)", x: point.0, y: point.1, isBefore: item.1))
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                RuleMark(y: .value("zero", 0)).foregroundStyle(Color.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1))
                RuleMark(x: .value("zero", 0)).foregroundStyle(Color.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(all) { point in
                    LineMark(x: .value(lines.across, point.x), y: .value(lines.up, point.y), series: .value("Series", point.series))
                        .foregroundStyle(point.isBefore ? Color.white.opacity(0.32) : blue)
                        .lineStyle(StrokeStyle(lineWidth: point.isBefore ? 1.5 : 2.2, lineCap: .round, dash: point.isBefore ? [4, 4] : []))
                }
                if let crossing {
                    PointMark(x: .value(lines.across, crossing.0), y: .value(lines.up, crossing.1))
                        .symbolSize(70)
                        .foregroundStyle(Z.yellow)
                        .annotation(position: .topTrailing, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            Text("(\(shown(crossing.0)), \(shown(crossing.1)))")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Z.yellow)
                                .fixedSize()
                        }
                }
            }
            .chartXScale(domain: range)
            .chartYScale(domain: upRange)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Z.tertiary)
            } }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Z.tertiary)
            } }
            .frame(width: width, height: width * 0.8)
            Key(items: lines.before.map { ($0.label, Color.white.opacity(0.35), true) } + lines.after.map { ($0.label, blue, false) }, size: 11)
        }
    }

    /// Where the lines cross: those after the step, or with the ones before when there's one.
    private func cross() -> (Double, Double)? {
        let equations = (lines.after + lines.before).map(\.equation)
        guard equations.count >= 2 else { return nil }
        func coefficients(_ equation: Equation) -> (Double, Double, Double)? {
            let difference = Expr.add([equation.left, .multiply([.minusOne, equation.right])])
            guard let c = difference.evaluate([lines.across: 0, lines.up: 0]),
                  let a = difference.evaluate([lines.across: 1, lines.up: 0]).map({ $0 - c }),
                  let b = difference.evaluate([lines.across: 0, lines.up: 1]).map({ $0 - c }) else { return nil }
            return (a, b, c)
        }
        for i in equations.indices {
            for j in equations.indices where j > i {
                guard let (a1, b1, c1) = coefficients(equations[i]), let (a2, b2, c2) = coefficients(equations[j]) else { continue }
                let d = a1 * b2 - a2 * b1
                guard abs(d) > 1e-9 else { continue }
                return ((-c1 * b2 + c2 * b1) / d, (-a1 * c2 + a2 * c1) / d)
            }
        }
        return nil
    }
}

/// Jumps along a number line: from the first number, by each of the others, to the result.
private struct NumberLineView: View {
    let start: Double
    let moves: [Double]
    let result: Double
    let width: CGFloat
    let blue: Color

    var body: some View {
        var stops = [start]
        for move in moves { stops.append(stops[stops.count - 1] + move) }
        let low = min(stops.min() ?? 0, result)
        let high = max(stops.max() ?? 1, result)
        let pad = max((high - low) * 0.08, 0.5)
        let lowest = low - pad, highest = high + pad
        let height = width * 0.42
        return Canvas { context, size in
            let baseline = size.height * 0.72
            func x(_ value: Double) -> CGFloat { 8 + CGFloat((value - lowest) / (highest - lowest)) * (size.width - 16) }
            var axis = Path()
            axis.move(to: CGPoint(x: 4, y: baseline)); axis.addLine(to: CGPoint(x: size.width - 4, y: baseline))
            context.stroke(axis, with: .color(Color.white.opacity(0.35)), lineWidth: 1.2)
            // Ticks at a round step.
            let step = Self.tick(highest - lowest)
            var tick = (lowest / step).rounded(.up) * step
            while tick <= highest {
                var mark = Path()
                mark.move(to: CGPoint(x: x(tick), y: baseline - 3)); mark.addLine(to: CGPoint(x: x(tick), y: baseline + 3))
                context.stroke(mark, with: .color(Color.white.opacity(0.3)), lineWidth: 1)
                if abs(x(tick) - x(result)) > 18 {
                    context.draw(Text(shown(tick)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Z.tertiary),
                                 at: CGPoint(x: x(tick), y: baseline + 13))
                }
                tick += step
            }
            // Each jump an arc above the line, with what it adds.
            for (index, move) in moves.enumerated() {
                let from = x(stops[index]), to = x(stops[index + 1])
                let rise = min(max(abs(to - from) * 0.45, 14), baseline - 26)
                var arc = Path()
                arc.move(to: CGPoint(x: from, y: baseline))
                arc.addQuadCurve(to: CGPoint(x: to, y: baseline), control: CGPoint(x: (from + to) / 2, y: baseline - rise * 2))
                context.stroke(arc, with: .color(blue), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                let sign = move < 0 ? "−" : "+"
                context.draw(Text(sign + shown(abs(move))).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Z.text),
                             at: CGPoint(x: (from + to) / 2, y: baseline - rise - 10))
            }
            for (index, value) in stops.enumerated() {
                let isLast = index == stops.count - 1
                let dot: CGFloat = isLast ? 4.5 : 3.5
                context.fill(Path(ellipseIn: CGRect(x: x(value) - dot, y: baseline - dot, width: dot * 2, height: dot * 2)),
                             with: .color(isLast ? Z.yellow : Color.white.opacity(0.9)))
            }
            context.draw(Text(shown(result)).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(Z.yellow),
                         at: CGPoint(x: x(result), y: baseline + 13))
        }
        .frame(width: width, height: height)
    }

    static func tick(_ span: Double) -> Double {
        let rough = span / 6
        let power = pow(10, floor(log10(max(rough, 1e-9))))
        for factor in [1.0, 2, 5, 10] where rough <= factor * power { return factor * power }
        return 10 * power
    }
}

/// Two numbers multiplied as a rectangle: one along the bottom, the other up the side, and
/// what it comes to written inside. Small whole numbers get their squares drawn.
private struct AreaView: View {
    let a: Double
    let b: Double
    let result: Double
    let width: CGFloat
    let blue: Color

    var body: some View {
        // Kept in proportion, unless one side is far longer than the other.
        let ratio = min(max(b / a, 0.25), 1)
        let across = width * 0.78
        let up = across * CGFloat(ratio)
        let grid = a == a.rounded() && b == b.rounded() && a <= 15 && b <= 15
        return Canvas { context, size in
            let origin = CGPoint(x: (size.width - across) / 2 + 8, y: 18)
            let box = CGRect(x: origin.x, y: origin.y, width: across, height: up)
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(blue.opacity(0.22)))
            if grid {
                for i in 1..<Int(a) {
                    var line = Path()
                    let x = box.minX + box.width * CGFloat(i) / CGFloat(a)
                    line.move(to: CGPoint(x: x, y: box.minY)); line.addLine(to: CGPoint(x: x, y: box.maxY))
                    context.stroke(line, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                }
                for j in 1..<Int(b) {
                    var line = Path()
                    let y = box.minY + box.height * CGFloat(j) / CGFloat(b)
                    line.move(to: CGPoint(x: box.minX, y: y)); line.addLine(to: CGPoint(x: box.maxX, y: y))
                    context.stroke(line, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                }
            }
            context.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(blue), lineWidth: 1.5)
            context.draw(Text(shown(a)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Z.secondary),
                         at: CGPoint(x: box.midX, y: box.minY - 9))
            context.draw(Text(shown(b)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Z.secondary),
                         at: CGPoint(x: box.minX - 6, y: box.midY), anchor: .trailing)
            context.draw(Text(shown(result)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Z.text),
                         at: CGPoint(x: box.midX, y: box.midY))
        }
        .frame(width: width, height: up + 28)
    }
}

/// Fractions as bars cut into equal parts, some filled: each side of each line on a row, so
/// fractions that are equal fill the same length.
private struct FractionBarsView: View {
    let rows: [(label: String, terms: [Rational])]
    let width: CGFloat
    let blue: Color

    var body: some View {
        let wholes = max(rows.map { Int(ceil($0.terms.reduce(0) { $0 + $1.double } - 1e-9)) }.max() ?? 1, 1)
        let bar = (width - 8 * CGFloat(wholes - 1) - 74) / CGFloat(wholes)
        return VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Z.secondary)
                        .frame(width: 64, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Canvas { context, size in draw(row.terms, wholes: wholes, bar: bar, in: &context, height: size.height) }
                        .frame(width: CGFloat(wholes) * bar + 8 * CGFloat(wholes - 1), height: 16)
                }
            }
        }
    }

    /// The row's terms fill the bars one after another, in alternating blues.
    private func draw(_ row: [Rational], wholes: Int, bar: CGFloat, in context: inout GraphicsContext, height: CGFloat) {
        // The parts each bar is cut into: shared when the terms share a denominator.
        let parts = row.map(\.denominator).reduce(1) { Rational.lcm($0, $1) ?? $0 }
        guard parts > 0, parts <= 48 else { return }
        var filled = 0
        var spans: [(from: Int, to: Int, tone: Int)] = []
        for (index, term) in row.enumerated() {
            let count = term.numerator * (parts / term.denominator)
            spans.append((filled, filled + count, index % 2))
            filled += count
        }
        for whole in 0..<wholes {
            let left = CGFloat(whole) * (bar + 8)
            for part in 0..<parts {
                let cell = whole * parts + part
                let rect = CGRect(x: left + bar * CGFloat(part) / CGFloat(parts), y: 0, width: bar / CGFloat(parts), height: height)
                if let span = spans.first(where: { cell >= $0.from && cell < $0.to }) {
                    context.fill(Path(rect.insetBy(dx: 0.5, dy: 0)), with: .color(span.tone == 0 ? blue : blue.opacity(0.55)))
                }
                if part > 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: rect.minX, y: 0)); line.addLine(to: CGPoint(x: rect.minX, y: height))
                    context.stroke(line, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
                }
            }
            context.stroke(Path(roundedRect: CGRect(x: left, y: 0, width: bar, height: height), cornerRadius: 2.5),
                           with: .color(Color.white.opacity(0.45)), lineWidth: 1)
        }
    }
}

/// A fraction of an amount: a bar for the amount, cut into the fraction's parts, with its
/// share filled and what that share is.
private struct PortionView: View {
    let fraction: Rational
    let amount: Double
    let result: Double
    let width: CGFloat
    let blue: Color

    var body: some View {
        let parts = fraction.denominator, taken = fraction.numerator
        let bar = width - 8
        return Canvas { context, size in
            let top: CGFloat = 16, height: CGFloat = 20
            let rect = CGRect(x: 4, y: top, width: bar, height: height)
            let share = bar / CGFloat(parts)
            context.fill(Path(CGRect(x: rect.minX, y: top, width: share * CGFloat(taken), height: height)), with: .color(blue.opacity(0.85)))
            for part in 1..<parts {
                var line = Path()
                let x = rect.minX + share * CGFloat(part)
                line.move(to: CGPoint(x: x, y: top)); line.addLine(to: CGPoint(x: x, y: top + height))
                context.stroke(line, with: .color(Color.white.opacity(0.2)), lineWidth: 1)
            }
            context.stroke(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(Color.white.opacity(0.45)), lineWidth: 1)
            context.draw(Text(shown(amount)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Z.secondary),
                         at: CGPoint(x: rect.midX, y: top - 8))
            // A brace under the share, and what it comes to.
            var brace = Path()
            let end = rect.minX + share * CGFloat(taken)
            brace.move(to: CGPoint(x: rect.minX, y: top + height + 4))
            brace.addLine(to: CGPoint(x: rect.minX, y: top + height + 8))
            brace.addLine(to: CGPoint(x: end, y: top + height + 8))
            brace.addLine(to: CGPoint(x: end, y: top + height + 4))
            context.stroke(brace, with: .color(Z.yellow.opacity(0.8)), lineWidth: 1.2)
            context.draw(Text("\(Format.text(.number(.exact(fraction)))) of \(shown(amount)) = \(shown(result))")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Z.yellow),
                         at: CGPoint(x: max(rect.minX + 60, (rect.minX + end) / 2), y: top + height + 20))
        }
        .frame(width: width, height: 64)
    }
}
