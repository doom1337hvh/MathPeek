import SwiftUI

/// A step written out the way it's done on paper, so you can see what was done to the
/// maths: what's added to both sides, in blue, and what cancels, struck through; what's
/// divided by; the part of a sum that's worked out and where its answer goes; like terms put
/// together; brackets multiplied out in a grid; a fraction's top and bottom multiplied by
/// the same number; a power brought down. Still, not animated: read it like a page.
struct StepVisual {
    /// One line of it, made of pieces, some marked.
    struct Row {
        var pieces: [Piece]
        /// Set apart from the line above by a rule, as a sum is in columns.
        var ruled = false
    }

    enum Mark { case plain, added, picked, cancelled, cancelledAdded, result }

    enum Piece {
        case math(Expr, Mark)
        /// A sum in brackets, the brackets close to it.
        case bracketed(Expr, Mark)
        case text(String, Mark)
        case fraction(top: [Piece], bottom: [Piece])
    }

    /// Brackets multiplied out: their terms along the top and side, the products inside.
    struct Grid {
        var across: [Expr]
        var down: [Expr]
        var cells: [[Expr]]
    }

    var rows: [Row] = []
    var grid: Grid?

    // MARK: Working out what the step did

    static func make(for steps: [Step], at index: Int, in solution: Solution) -> StepVisual? {
        guard steps.indices.contains(index) else { return nil }
        let step = steps[index]
        guard !step.lines.isEmpty else { return nil }
        if case .diagram = solution.problem.kind { return nil }
        if case .remainder = solution.problem.kind { return nil }
        let previous = steps[..<index].last { !$0.lines.isEmpty }?.lines ?? solution.problem.kind.lines
        let isSolving: Bool = if case .solve = solution.problem.kind { true } else { false }

        if isSolving {
            let before = previous.compactMap(equation)
            let after = step.lines.compactMap(equation)
            guard !after.isEmpty else { return nil }
            if before.count == 2, after.count == 1, let visual = combined(before[0], before[1], into: after[0]) { return visual }
            if case .solve(let equations, _) = solution.problem.kind, let visual = substituted(before, into: equations, giving: after) { return visual }
            if let from = before.last, after.count == 1 {
                let to = after[0]
                if let visual = bothSidesChanged(from, to) { return visual }
                if let visual = bothSidesScaled(from, to) { return visual }
                if let grid = grid(product: to.left, sum: Simplify.run(from.left)) ?? grid(product: from.left, sum: to.left) {
                    return StepVisual(rows: [], grid: grid)
                }
            }
            if let from = before.last, case .multiply(let factors) = from.left, same(from.right, .integer(0)),
               after.count == factors.count, after.allSatisfy({ eq in factors.contains { same($0, eq.left) } && same(eq.right, .integer(0)) }) {
                // Brackets multiplied to make zero: each picked out, and each made zero.
                return StepVisual(rows: [Row(pieces: pieces(from.left, picked: factors) + [.text("=", .plain), .math(from.right, .plain)])]
                                  + after.map { Row(pieces: pieces($0.left, mark: .result) + [.text("=", .plain), .math($0.right, .plain)]) })
            }
            return nil
        }

        // Rewriting: each line is what it was and what it became, or what the line before became.
        var visual = StepVisual()
        for line in step.lines {
            let from: Expr?, to: Expr
            if line.parts.count >= 2 {
                from = line.parts[0]
                to = line.parts[line.parts.count - 1]
            } else if let part = line.parts.first {
                from = previous.last?.parts.last
                to = part
            } else { continue }
            guard let from, from != to else { continue }
            if line.relation == "→", let rows = poweredDown(from, to) {
                visual.rows += rows
            } else if let row = fractionScaled(from, to) {
                visual.rows.append(row)
            } else if let row = numeratorsAdded(from, to) {
                visual.rows.append(row)
            } else if let grid = grid(product: from, sum: to) ?? grid(product: to, sum: from) {
                visual.grid = grid
            } else if let rows = workedOut(from, to) {
                visual.rows += rows
            } else if let rows = brokenDown(from, to) {
                visual.rows += rows
            }
        }
        return visual.rows.isEmpty && visual.grid == nil ? nil : visual
    }

    private static func equation(_ line: MathLine) -> Equation? {
        guard line.relation == "=", line.parts.count == 2 else { return nil }
        return Equation(left: line.parts[0], right: line.parts[1])
    }

    /// Whether two expressions are the same, tried at a few values of their letters.
    private static func same(_ a: Expr, _ b: Expr) -> Bool {
        let letters = a.symbols.union(b.symbols)
        for sample in [1.37, -2.21, 3.05] {
            let values = Dictionary(uniqueKeysWithValues: letters.sorted().enumerated().map { ($0.element, sample + Double($0.offset) * 0.71) })
            guard let x = a.evaluate(values), let y = b.evaluate(values), x.isFinite, y.isFinite else { return false }
            if abs(x - y) > 1e-7 * max(1, abs(x)) { return false }
        }
        return true
    }

    private static func minus(_ a: Expr, _ b: Expr) -> Expr { Simplify.run(.add([a, .multiply([.minusOne, b])])) }

    /// A difference written simply, as the terms it's made of: −3x + 4. Only for a number,
    /// or a straight line in one letter.
    private static func tidy(_ expr: Expr) -> Expr? {
        let letters = expr.symbols
        guard letters.count <= 1 else { return nil }
        guard let letter = letters.first else { return expr.evaluate().map(number) }
        guard let zero = expr.evaluate([letter: 0]), let one = expr.evaluate([letter: 1]), let two = expr.evaluate([letter: 2]),
              abs(two - (zero + 2 * (one - zero))) < 1e-9 else { return nil }
        let slope = one - zero
        var parts: [Expr] = []
        if abs(slope) > 1e-12 {
            parts.append(abs(slope - 1) < 1e-12 ? .symbol(letter) : (abs(slope + 1) < 1e-12 ? .multiply([.minusOne, .symbol(letter)]) : .multiply([number(slope), .symbol(letter)])))
        }
        if abs(zero) > 1e-12 { parts.append(number(zero)) }
        return parts.isEmpty ? nil : (parts.count == 1 ? parts[0] : .add(parts))
    }

    /// The same added to (or taken from) both sides: each term of it written on both sides in
    /// blue, and struck through with the term it cancels.
    private static func bothSidesChanged(_ from: Equation, _ to: Equation) -> StepVisual? {
        let left = minus(to.left, from.left), right = minus(to.right, from.right)
        guard !same(left, .integer(0)), same(left, right), let amount = tidy(left) else { return nil }
        let amounts = terms(amount)
        func side(_ expr: Expr) -> [Piece] {
            let own = terms(expr)
            // Which of the side's terms each added term cancels.
            var struck: Set<Int> = [], cancelling: Set<Int> = []
            for (index, amount) in amounts.enumerated() {
                if let match = own.indices.first(where: { !struck.contains($0) && same(.add([own[$0], amount]), .integer(0)) }) {
                    struck.insert(match)
                    cancelling.insert(index)
                }
            }
            var result: [Piece] = []
            for (index, term) in own.enumerated() {
                let (negative, size) = signed(term)
                let mark: Mark = struck.contains(index) ? .cancelled : .plain
                if index > 0 || negative { result.append(.text(negative ? "−" : "+", mark)) }
                result.append(.math(size, mark))
            }
            for (index, amount) in amounts.enumerated() {
                let (negative, size) = signed(amount)
                let mark: Mark = cancelling.contains(index) ? .cancelledAdded : .added
                result.append(.text(negative ? "−" : "+", mark))
                result.append(.math(size, mark))
            }
            return result
        }
        let written = side(from.left) + [.text("=", .plain)] + side(from.right)
        return StepVisual(rows: [Row(pieces: written), Row(pieces: pieces(to.left) + [.text("=", .plain)] + pieces(to.right, mark: .result))])
    }

    /// Both sides divided (or multiplied) by the same number: written over it in blue.
    private static func bothSidesScaled(_ from: Equation, _ to: Equation) -> StepVisual? {
        let letters = from.left.symbols.union(from.right.symbols)
        var ratio: Double?
        for sample in [1.37, -2.21] {
            let values = Dictionary(uniqueKeysWithValues: letters.map { ($0, sample) })
            for (a, b) in [(from.left, to.left), (from.right, to.right)] {
                guard let x = a.evaluate(values), let y = b.evaluate(values), abs(y) > 1e-9 else { continue }
                let r = x / y
                if let ratio, abs(ratio - r) > 1e-7 * max(1, abs(r)) { return nil }
                ratio = r
            }
        }
        guard let ratio, abs(ratio - 1) > 1e-9, abs(ratio) > 1e-9 else { return nil }
        let rows: [Row]
        if abs(ratio) >= 1 || abs(1 / ratio - (1 / ratio).rounded()) > 1e-9 {
            let by = number(ratio)
            rows = [Row(pieces: [.fraction(top: pieces(from.left), bottom: [.math(by, .added)]), .text("=", .plain),
                                 .fraction(top: pieces(from.right), bottom: [.math(by, .added)])])]
        } else {
            let by = number(1 / ratio)
            rows = [Row(pieces: [.math(by, .added), .text("×", .added)] + bracketed(from.left) + [.text("=", .plain), .math(by, .added), .text("×", .added)] + bracketed(from.right))]
        }
        return StepVisual(rows: rows + [Row(pieces: pieces(to.left) + [.text("=", .plain)] + pieces(to.right, mark: .result))])
    }

    /// Two equations added or taken away, set out in columns, with the terms that cancel
    /// struck through.
    private static func combined(_ first: Equation, _ second: Equation, into result: Equation) -> StepVisual? {
        for sign in [1.0, -1.0] {
            let other: (Expr) -> Expr = { sign > 0 ? $0 : .multiply([.minusOne, $0]) }
            guard same(.add([first.left, other(second.left)]), result.left),
                  same(.add([first.right, other(second.right)]), result.right) else { continue }
            let firstTerms = terms(first.left), secondTerms = terms(second.left)
            // A term in one that's gone from the result with its match in the other.
            func cancels(_ term: Expr, against others: [Expr], flip: Bool) -> Bool {
                others.contains { same(.add([term, flip == (sign > 0) ? $0 : .multiply([.minusOne, $0])]), .integer(0)) }
            }
            let top = row(firstTerms) { cancels($0, against: secondTerms, flip: true) } + [.text("=", .plain)] + pieces(first.right)
            let below = [Piece.text(sign > 0 ? "+" : "−", .added)] + row(secondTerms) { cancels($0, against: firstTerms, flip: true) }
                + [.text("=", .plain)] + pieces(second.right)
            return StepVisual(rows: [Row(pieces: top), Row(pieces: below),
                                     Row(pieces: pieces(result.left, mark: .result) + [.text("=", .plain)] + pieces(result.right, mark: .result), ruled: true)])
        }
        return nil
    }

    /// A fraction rewritten over a bigger denominator: top and bottom multiplied by the same.
    private static func fractionScaled(_ from: Expr, _ to: Expr) -> Row? {
        guard let a = fraction(from), let b = fraction(to), b.denominator > a.denominator,
              b.denominator % a.denominator == 0 else { return nil }
        let k = b.denominator / a.denominator
        guard same(.multiply([a.top, .integer(k)]), b.top) else { return nil }
        let top: [Piece] = [.math(a.top, .plain), .text("× \(k)", .added)]
        let bottom: [Piece] = [.math(.integer(a.denominator), .plain), .text("× \(k)", .added)]
        return Row(pieces: [.math(from, .plain), .text("=", .plain), .fraction(top: top, bottom: bottom), .text("=", .plain), .math(to, .result)])
    }

    /// Fractions over the same denominator added: their tops added over it.
    private static func numeratorsAdded(_ from: Expr, _ to: Expr) -> Row? {
        guard case .add(let parts) = from, parts.count >= 2, let total = fraction(to) else { return nil }
        let fractions = parts.compactMap(fraction)
        guard fractions.count == parts.count, fractions.allSatisfy({ $0.denominator == total.denominator }) else { return nil }
        var top: [Piece] = []
        for (index, part) in fractions.enumerated() {
            let (negative, size) = signed(part.top)
            if index > 0 || negative { top.append(.text(negative ? "−" : "+", .added)) }
            top.append(.math(size, .plain))
        }
        return Row(pieces: [.fraction(top: top, bottom: [.math(.integer(total.denominator), .plain)]), .text("=", .plain), .math(to, .result)])
    }

    /// A power brought down in front and one taken off it: x³ → 3 × x³⁻¹ = 3x².
    private static func poweredDown(_ from: Expr, _ to: Expr) -> [Row]? {
        var coefficient = Expr.integer(1), x: Expr?, power: Int?
        switch from {
        case .power(let base, let exponent):
            x = base; power = exponent.number?.integer
        case .multiply(let factors) where factors.count == 2:
            if case .power(let base, let exponent) = factors[1] { coefficient = factors[0]; x = base; power = exponent.number?.integer }
        default:
            break
        }
        guard let x, let power, power >= 2, case .symbol = x else { return nil }
        let brought: Expr = .power(x, .add([.integer(power), .minusOne]))
        var middle: [Piece] = [.math(.integer(power), .added), .text("×", .added)]
        if coefficient != .integer(1) { middle += [.math(coefficient, .plain), .text("×", .plain)] }
        middle.append(.math(brought, .plain))
        return [Row(pieces: [.math(from, .plain), .text("→", .plain)] + middle + [.text("=", .plain), .math(to, .result)])]
    }

    /// A value found, put back into one of the equations: the letter picked out, the number
    /// written in its place in blue, and what that comes to.
    private static func substituted(_ before: [Equation], into equations: [Equation], giving after: [Equation]) -> StepVisual? {
        guard let first = after.first else { return nil }
        // The value found: a letter equal to a number.
        guard let known = before.last, case .symbol(let letter) = known.left, let value = known.right.number else { return nil }
        let number = Expr.number(value)
        func put(_ expr: Expr) -> Expr {
            switch expr {
            case .symbol(let name) where name == letter: return number
            case .add(let parts): return .add(parts.map(put))
            case .multiply(let parts): return .multiply(parts.map(put))
            case .power(let base, let exponent): return .power(put(base), put(exponent))
            case .function(let function, let argument): return .function(function, put(argument))
            default: return expr
            }
        }
        // The equation it went into: the one that gives the step's first line.
        guard let into = equations.first(where: { equation in
            equation.left.symbols.union(equation.right.symbols).contains(letter)
                && same(.add([put(equation.left), .multiply([.minusOne, put(equation.right)])]), .add([first.left, .multiply([.minusOne, first.right])]))
        }) else { return nil }
        var rows = [Row(pieces: pieces(into.left, picked: [.symbol(letter)]) + [.text("=", .plain)] + pieces(into.right, picked: [.symbol(letter)])),
                    Row(pieces: pieces(put(into.left), picked: [number], mark: .added) + [.text("=", .plain)] + pieces(put(into.right), picked: [number], mark: .added)),
                    Row(pieces: pieces(first.left, mark: .result) + [.text("=", .plain)] + pieces(first.right))]
        // And on to the answer, if the step goes on.
        if after.count >= 2, let rest = bothSidesChanged(after[0], after[1]) ?? bothSidesScaled(after[0], after[1]) {
            rows += rest.rows
        }
        return StepVisual(rows: rows)
    }

    /// A sum of two plain numbers worked out in your head: a multiplication split by place
    /// value (12 × 7.5 is 12 × 7 and 12 × 0.5), an addition or subtraction taken through the
    /// next ten, or tens and units added apart.
    private static func brokenDown(_ from: Expr, _ to: Expr) -> [Row]? {
        guard from.symbols.isEmpty, let result = to.evaluate() else { return nil }
        func plain(_ value: Double) -> Expr {
            abs(value - value.rounded()) < 1e-9 ? .integer(Int(value.rounded())) : .number(.real((value * 1e6).rounded() / 1e6))
        }
        switch from {
        case .multiply(let factors) where factors.count == 2:
            guard let a = factors[0].evaluate(), let b = factors[1].evaluate(), a > 0, b > 0 else { return nil }
            // Split the number that's easier to split: one with a decimal, or the bigger one.
            let (keep, split) = (b != b.rounded() || (a == a.rounded() && b >= a)) ? (a, b) : (b, a)
            let whole = split.rounded(.down), part = split - whole
            var parts: [Double] = []
            if part > 1e-9 {
                if whole > 0 { parts.append(whole) }
                parts.append((part * 1e6).rounded() / 1e6)
            } else if split >= 10, split.truncatingRemainder(dividingBy: 10) != 0 {
                let units = split.truncatingRemainder(dividingBy: 10)
                parts = [split - units, units]
            }
            guard parts.count == 2 else { return nil }
            let products = parts.map { keep * $0 }
            var rows = zip(parts, products).map { piece, product in
                Row(pieces: [.math(plain(keep), .plain), .text("×", .plain), .math(plain(piece), .added), .text("=", .plain), .math(plain(product), .picked)])
            }
            rows.append(Row(pieces: [.math(plain(products[0]), .picked), .text("+", .plain), .math(plain(products[1]), .picked), .text("=", .plain), .math(to, .result)]))
            return rows
        case .add(let terms) where terms.count == 2:
            guard let a = terms[0].evaluate(), let b = terms[1].evaluate(), a == a.rounded(), b == b.rounded(), a >= 0 else { return nil }
            let size = abs(b)
            if size < 10 {
                // Through the next ten (or back to the last one).
                let ten = b > 0 ? (a / 10).rounded(.down) * 10 + 10 : (a / 10).rounded(.up) * 10 - 10
                let first = abs(ten - a)
                guard first > 0, first < size, (b > 0 ? a + b > ten : a + b < ten) || a + b == ten else { return nil }
                let sign = b > 0 ? "+" : "−"
                let near = b > 0 ? ten : ten
                let stepTo = a.truncatingRemainder(dividingBy: 10) == 0 ? nil : near
                guard let stop = stepTo else { return nil }
                return [Row(pieces: [.math(plain(a), .plain), .text(sign, .added), .math(plain(first), .added), .text("=", .plain), .math(plain(stop), .picked)]),
                        Row(pieces: [.math(plain(stop), .picked), .text(sign, .added), .math(plain(size - first), .added), .text("=", .plain), .math(to, .result)])]
            }
            guard b > 0, a >= 10 else { return nil }
            // Tens and units apart.
            let aUnits = a.truncatingRemainder(dividingBy: 10), bUnits = b.truncatingRemainder(dividingBy: 10)
            let tens = (a - aUnits) + (b - bUnits), units = aUnits + bUnits
            return [Row(pieces: [.math(plain(a - aUnits), .plain), .text("+", .plain), .math(plain(b - bUnits), .plain), .text("=", .plain), .math(plain(tens), .picked)]),
                    Row(pieces: [.math(plain(aUnits), .plain), .text("+", .plain), .math(plain(bUnits), .plain), .text("=", .plain), .math(plain(units), .picked)]),
                    Row(pieces: [.math(plain(tens), .picked), .text("+", .plain), .math(plain(units), .picked), .text("=", .plain), .math(plain(result), .result)])]
        default:
            return nil
        }
    }

    /// A part of the sum worked out: picked out where it is, worked out on its own, and its
    /// answer picked out where it goes.
    private static func workedOut(_ from: Expr, _ to: Expr) -> [Row]? {
        guard let (was, became) = changed(from, to), was != from || became != to else {
            return nil
        }
        let picked = terms(was).count > 1 && !containsAsWhole(was, in: from) ? terms(was) : [was]
        let sum: Expr = picked.count > 1 ? .add(picked) : was
        return [Row(pieces: pieces(from, picked: picked)),
                Row(pieces: pieces(sum, mark: .picked) + [.text("=", .plain), .math(became, .result)]),
                Row(pieces: pieces(to, picked: [became], mark: .result))]
    }

    private static func containsAsWhole(_ part: Expr, in expr: Expr) -> Bool {
        if part == expr { return true }
        switch expr {
        case .add(let parts), .multiply(let parts): return parts.contains { containsAsWhole(part, in: $0) }
        case .power(let base, let exponent): return containsAsWhole(part, in: base) || containsAsWhole(part, in: exponent)
        case .function(_, let argument): return containsAsWhole(part, in: argument)
        default: return false
        }
    }

    /// The smallest part of `from` that changed to give `to`.
    private static func changed(_ from: Expr, _ to: Expr) -> (Expr, Expr)? {
        guard from != to else { return nil }
        switch (from, to) {
        case (.add(let a), .add(let b)) where a.count == b.count, (.multiply(let a), .multiply(let b)) where a.count == b.count:
            let differing = zip(a, b).filter { $0 != $1 }
            if differing.count == 1 { return changed(differing[0].0, differing[0].1) }
        case (.add(let a), .add(let b)) where a.count > b.count:
            var gone = a, came = b
            for term in b { if let at = gone.firstIndex(of: term) { gone.remove(at: at); came.removeAll { $0 == term } } }
            if came.count == 1, gone.count >= 2 { return (.add(gone), came[0]) }
        default:
            break
        }
        return (from, to)
    }

    /// Brackets multiplied together and the sum they make, as a grid.
    private static func grid(product: Expr, sum: Expr) -> Grid? {
        guard case .multiply(let factors) = product else { return nil }
        let brackets = factors.filter { if case .add = $0 { true } else { false } }
        guard brackets.count == 2, factors.count == 2, case .add = sum else { return nil }
        let across = terms(brackets[1]), down = terms(brackets[0])
        guard across.count <= 3, down.count <= 3, same(product, sum) else { return nil }
        let cells = down.map { a in across.map { b in Simplify.run(.multiply([a, b])) } }
        return Grid(across: across, down: down, cells: cells)
    }

    // MARK: Pieces

    private static func terms(_ expr: Expr) -> [Expr] {
        if case .add(let parts) = expr { return parts }
        return [expr]
    }

    /// A term's sign, and the term without it.
    private static func signed(_ term: Expr) -> (Bool, Expr) {
        switch term {
        case .number(let value) where value.isNegative: return (true, .number(value.negated))
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                if value.negated.isOne, factors.count > 1 {
                    let rest = Array(factors.dropFirst())
                    return (true, rest.count == 1 ? rest[0] : .multiply(rest))
                }
                return (true, .multiply([.number(value.negated)] + factors.dropFirst()))
            }
            return (false, term)
        default:
            return (false, term)
        }
    }

    private static func number(_ value: Double) -> Expr {
        if abs(value - value.rounded()) < 1e-9 { return .integer(Int(value.rounded())) }
        return .number(.real(value))
    }

    /// A fraction with a whole number underneath: 9/12, 3h/18.
    private static func fraction(_ expr: Expr) -> (top: Expr, denominator: Int)? {
        switch expr {
        case .number(let value):
            guard let r = value.rational, !r.isInteger else { return nil }
            return (.integer(r.numerator), r.denominator)
        case .multiply(let factors) where factors.count >= 2:
            guard case .power(let base, let exponent) = factors[factors.count - 1], exponent == .minusOne,
                  let bottom = base.number?.integer, bottom > 1 else { return nil }
            let rest = Array(factors.dropLast())
            return (rest.count == 1 ? rest[0] : .multiply(rest), bottom)
        default:
            return nil
        }
    }

    /// A row of terms, each struck through if it cancels.
    private static func row(_ terms: [Expr], cancels: (Expr) -> Bool) -> [Piece] {
        var result: [Piece] = []
        for (index, term) in terms.enumerated() {
            let (negative, size) = signed(term)
            let mark: Mark = cancels(term) ? .cancelled : .plain
            if index > 0 || negative { result.append(.text(negative ? "−" : "+", mark)) }
            result.append(.math(size, mark))
        }
        return result
    }

    private static func bracketed(_ expr: Expr) -> [Piece] {
        if case .add = expr { return [.bracketed(expr, .plain)] }
        return pieces(expr)
    }

    /// An expression as pieces, with some of its parts picked out: a sum term by term, a
    /// product factor by factor, as far down as a picked part is.
    private static func pieces(_ expr: Expr, picked: [Expr] = [], mark: Mark = .plain) -> [Piece] {
        if picked.contains(expr) { return [.math(expr, mark == .result ? .result : .picked)] }
        guard !picked.isEmpty, picked.contains(where: { containsAsWhole($0, in: expr) }) else {
            return [.math(expr, picked.isEmpty ? mark : .plain)]
        }
        switch expr {
        case .add(let parts):
            let chosen = parts.indices.filter { picked.contains(parts[$0]) }
            if chosen.count > 1, chosen.last! - chosen.first! == chosen.count - 1 {
                // A run of picked terms: one box round them all.
                let run = Array(parts[chosen.first!...chosen.last!])
                var result: [Piece] = []
                for (index, term) in parts.enumerated() where !chosen.contains(index) || index == chosen.first! {
                    if index == chosen.first! {
                        let startsNegative = signed(run[0]).0
                        if index > 0, !startsNegative { result.append(.text("+", .plain)) }
                        result.append(.math(.add(run), mark == .result ? .result : .picked))
                        continue
                    }
                    let (negative, size) = signed(term)
                    if index > 0 || negative { result.append(.text(negative ? "−" : "+", .plain)) }
                    result += pieces(size, picked: picked, mark: mark)
                }
                return result
            }
            var result: [Piece] = []
            for (index, term) in parts.enumerated() {
                let (negative, size) = signed(term)
                let isPicked = picked.contains(term)
                if index > 0 || negative { result.append(.text(negative ? "−" : "+", isPicked ? (mark == .result ? .result : .picked) : .plain)) }
                result += isPicked ? [.math(size, mark == .result ? .result : .picked)] : pieces(size, picked: picked, mark: mark)
            }
            return result
        case .multiply(let factors):
            var result: [Piece] = []
            for (index, factor) in factors.enumerated() {
                // × between plain numbers, as in 12 × (3 + 4.5); none before a letter or bracket of letters.
                if index > 0, factor.symbols.isEmpty, factors[index - 1].symbols.isEmpty { result.append(.text("×", .plain)) }
                if case .add = factor, !picked.contains(factor), picked.contains(where: { containsAsWhole($0, in: factor) }) {
                    result += [.text("(", .plain)] + pieces(factor, picked: picked, mark: mark) + [.text(")", .plain)]
                } else if case .add = factor {
                    result.append(.bracketed(factor, picked.contains(factor) ? (mark == .result ? .result : .picked) : .plain))
                } else {
                    result += pieces(factor, picked: picked, mark: mark)
                }
            }
            return result
        default:
            return [.math(expr, .plain)]
        }
    }
}

// MARK: Drawing

struct StepVisualView: View {
    let visual: StepVisual
    let size: CGFloat
    let blue: Color

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.55) {
            ForEach(Array(visual.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: size * 0.45) {
                    if row.ruled { Rectangle().fill(Color.white.opacity(0.35)).frame(width: size * 9, height: 1) }
                    HStack(alignment: .center, spacing: size * 0.3) {
                        ForEach(Array(row.pieces.enumerated()), id: \.offset) { _, piece in draw(piece) }
                    }
                    .fixedSize()
                }
            }
            if let grid = visual.grid { gridView(grid) }
        }
    }

    private func draw(_ piece: StepVisual.Piece) -> AnyView {
        switch piece {
        case .math(let expr, let mark):
            return marked(AnyView(MathView(expr: expr, size: size, design: Z.maths)), mark)
        case .bracketed(let expr, let mark):
            return marked(AnyView(HStack(spacing: 1) {
                Text("(").font(.system(size: size))
                MathView(expr: expr, size: size, design: Z.maths)
                Text(")").font(.system(size: size))
            }), mark)
        case .text(let text, let mark):
            return marked(AnyView(Text(text).font(.system(size: size))), mark)
        case .fraction(let top, let bottom):
            return AnyView(VStack(spacing: size * 0.12) {
                HStack(spacing: size * 0.25) { ForEach(Array(top.enumerated()), id: \.offset) { _, piece in draw(piece) } }
                Rectangle().frame(height: max(1, size / 18))
                HStack(spacing: size * 0.25) { ForEach(Array(bottom.enumerated()), id: \.offset) { _, piece in draw(piece) } }
            }.fixedSize())
        }
    }

    /// Blue for what's done to the maths, a soft blue box for what's picked out and for what
    /// it gives, and a line through what cancels.
    private func marked(_ view: AnyView, _ mark: StepVisual.Mark) -> AnyView {
        switch mark {
        case .plain:
            return AnyView(view.foregroundStyle(Z.text))
        case .added:
            return AnyView(view.foregroundStyle(blue))
        case .picked:
            return AnyView(view.foregroundStyle(Z.text)
                .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color.white.opacity(0.1))
                    .padding(.horizontal, -size * 0.14).padding(.vertical, -size * 0.06)))
        case .result:
            return AnyView(view.foregroundStyle(Z.text)
                .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(blue.opacity(0.3))
                    .padding(.horizontal, -size * 0.14).padding(.vertical, -size * 0.06)))
        case .cancelled, .cancelledAdded:
            return AnyView(view.foregroundStyle(mark == .cancelled ? Z.tertiary : blue.opacity(0.6))
                .overlay { Rectangle().fill(Color.white.opacity(0.7)).frame(height: max(1, size / 14)).rotationEffect(.degrees(-12)) })
        }
    }

    /// The grid method: one bracket's terms along the top, the other's down the side, and
    /// each pair multiplied in its cell.
    private func gridView(_ grid: StepVisual.Grid) -> some View {
        let cell = size * 3.6
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("×").font(.system(size: size * 0.85)).foregroundStyle(Z.tertiary).frame(width: cell * 0.7, height: size * 1.8)
                ForEach(Array(grid.across.enumerated()), id: \.offset) { _, term in
                    MathView(expr: term, size: size * 0.9, design: Z.maths).foregroundStyle(blue).frame(width: cell, height: size * 1.8)
                }
            }
            ForEach(Array(grid.down.enumerated()), id: \.offset) { row, term in
                GridRow {
                    MathView(expr: term, size: size * 0.9, design: Z.maths).foregroundStyle(blue).frame(width: cell * 0.7, height: size * 2.2)
                    ForEach(Array(grid.cells[row].enumerated()), id: \.offset) { _, product in
                        MathView(expr: product, size: size * 0.9, design: Z.maths)
                            .foregroundStyle(Z.text)
                            .frame(width: cell, height: size * 2.2)
                            .background(blue.opacity(0.12))
                            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }
                }
            }
        }
        .fixedSize()
    }
}
