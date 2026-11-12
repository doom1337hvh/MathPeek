import SwiftUI

/// A part of a line of maths that's been picked to look at: a term, or a bracket.
struct MathPart: Hashable, Sendable {
    /// Which line it's in.
    var line: String
    /// Where it is in the line: the side of the =, then down through the expression.
    var path: [Int]
    var expr: Expr
}

/// A number in a line that can be changed.
struct MathNumber: Hashable, Sendable {
    var line: String
    var path: [Int]
    /// Whether it's shown without its minus sign, because the line draws that as a −.
    var negated: Bool
    var shown: Number
}

/// What a line of maths does when it's pointed at and clicked. Without one it's only drawn.
struct MathTouch {
    /// Names the line, so its parts can be told from other lines'.
    var line: String
    var accent: Color
    var picked: MathPart?
    /// The part and the number under the pointer.
    var hovered: String?
    var hoveredNumber: String?
    var pick: (MathPart) -> Void
    var hover: (String, Bool) -> Void
    /// Starts changing a number, if this line's numbers can be changed.
    var change: ((MathNumber) -> Void)?
    /// The number being changed now, and the field to draw in its place.
    var changing: MathNumber?
    var field: ((MathNumber, CGFloat) -> AnyView)?
}

/// Draws maths the way it's written on paper: fractions stacked, powers raised, roots with a
/// bar over them.
struct MathView: View {
    let expr: Expr
    var size: CGFloat = 18
    var design: Font.Design = .serif
    var weight: Font.Weight = .regular

    var body: some View {
        MathRender(design: design, weight: weight).view(expr, size)
            .fixedSize()
    }
}

/// A line of maths: parts joined by =, ≈ or →. With a `touch`, its terms can be picked and
/// its numbers changed.
struct MathLineView: View {
    let line: MathLine
    var size: CGFloat = 18
    var design: Font.Design = .serif
    var weight: Font.Weight = .regular
    var touch: MathTouch?

    var body: some View {
        let render = MathRender(design: design, weight: weight, touch: touch)
        HStack(alignment: .center, spacing: size * 0.35) {
            ForEach(Array(line.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(line.relation)
                        .font(.system(size: size, weight: weight, design: design))
                        .foregroundStyle(line.relation == "→" ? .secondary : .primary)
                }
                render.view(part, size, touch == nil ? nil : MathRender.Origin(path: [index]), parts: touch != nil)
            }
            if let suffix = line.suffix {
                // A degree sign goes straight after its number; words stand a little apart.
                Text(suffix)
                    .font(.system(size: size, weight: weight, design: design))
                    .foregroundStyle(suffix == "°" ? .primary : .secondary)
                    .padding(.leading, suffix == "°" ? -size * 0.33 : 0)
            }
        }
        .fixedSize()
    }
}

/// Draws one expression, in the font design and weight asked for.
struct MathRender {
    var design: Font.Design = .serif
    var weight: Font.Weight = .regular
    var touch: MathTouch?
    /// The part being drawn inside, if any: its numbers can be changed once it's picked.
    var within: MathPart?

    /// Where something drawn comes from in the line's expression, so a click can be traced
    /// back to it. Drawing pulls minus signs out in front and leaves out a coefficient of −1,
    /// so what's drawn isn't always exactly what's stored.
    struct Origin {
        var path: [Int]
        /// A number drawn without its minus sign.
        var negated = false
        /// A product drawn without its first factors.
        var shift = 0
        /// A product whose first factor, a number, is drawn without its minus sign.
        var negatesFirst = false

        func child(_ index: Int) -> Origin {
            Origin(path: path + [index + shift], negated: index == 0 && negatesFirst)
        }

        var name: String { path.map(String.init).joined(separator: ".") }
    }

    /// `parts` makes the terms of a sum, or the brackets of a product, things to pick.
    func view(_ expr: Expr, _ size: CGFloat, _ origin: Origin? = nil, parts: Bool = false) -> AnyView {
        if parts, touch != nil, let origin {
            switch expr {
            case .add:
                break
            case .number where touch?.change != nil:
                // In the problem a number on its own is changed with a click instead.
                break
            case .symbol(let name) where name.count > 2:
                // Words standing in for maths, like a list of terms: nothing to pick.
                break
            case .multiply(let factors) where bracketCount(factors) >= 2:
                break
            default:
                return asPart(expr, origin, size) { $0.view(expr, size, origin) }
            }
        }
        switch expr {
        case .number(let value):
            return number(value, size, origin)
        case .symbol(let name):
            if name.contains("/") {
                let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
                return fraction(text(parts[0], size, italic: true), text(parts[1], size, italic: true), size)
            }
            return text(name, size, italic: name.count == 1 || name.hasSuffix("′"))
        case .constant(.pi):
            return text("π", size)
        case .constant(.e):
            return text("e", size, italic: true)
        case .add(let terms):
            return sum(terms, size, origin, parts: parts)
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                let onlySign = value.negated.isOne && factors.count > 1
                let rest = onlySign ? Array(factors.dropFirst()) : [Expr.number(value.negated)] + factors.dropFirst()
                let inner = origin.map {
                    onlySign ? Origin(path: $0.path, shift: $0.shift + 1) : Origin(path: $0.path, shift: $0.shift, negatesFirst: true)
                }
                return AnyView(HStack(spacing: 1) { text("−", size); product(rest, size, inner, parts: parts) })
            }
            return product(factors, size, origin, parts: parts)
        case .power(let base, let exponent):
            return power(base, exponent, size, origin)
        case .function(let function, let argument):
            return functionView(function, argument, size, origin)
        }
    }

    /// Letters standing for numbers are set as maths sets them: in a serif italic, 𝑥 rather
    /// than x, so they can't be taken for a times sign and stand apart from the numbers.
    func text(_ string: String, _ size: CGFloat, italic: Bool = false) -> AnyView {
        if italic {
            return AnyView(Text(string).font(.system(size: design == .serif ? size : size * 1.08, weight: weight, design: .serif)).italic())
        }
        return AnyView(Text(string).font(.system(size: size, weight: weight, design: design)))
    }

    func fraction(_ top: AnyView, _ bottom: AnyView, _ size: CGFloat) -> AnyView {
        AnyView(VStack(spacing: size * 0.12) {
            top
            Rectangle().frame(height: max(1, size / 18))
            bottom
        }
        .fixedSize()
        .padding(.horizontal, size * 0.08))
    }

    // MARK: Things to click

    /// How many of a product's factors are brackets.
    private func bracketCount(_ factors: [Expr]) -> Int {
        factors.filter { factor in
            if case .add = factor { return true }
            if case .power(.add, _) = factor { return true }
            return false
        }.count
    }

    /// What kind of term something is, whatever number it's multiplied by: 3x and −5x are
    /// both "x", 2x² is "x²", a number on its own is "number". A bracket is itself.
    static func kind(of expr: Expr) -> String {
        switch expr {
        case .number: return "number"
        case .multiply(let factors):
            let rest = factors.filter { $0.number == nil }
            if rest.isEmpty { return "number" }
            return rest.map(Format.text).sorted().joined(separator: "·")
        default:
            return Format.text(expr)
        }
    }

    /// Draws something as a part to pick, with what's inside knowing it's inside it.
    private func asPart(_ expr: Expr, _ origin: Origin?, _ size: CGFloat, _ draw: (MathRender) -> AnyView) -> AnyView {
        guard let touch, let origin else { return draw(self) }
        var inner = self
        inner.within = MathPart(line: touch.line, path: origin.path, expr: expr)
        return part(draw(inner), expr, origin, size)
    }

    /// Something to pick: lit under the pointer, and when picked. The light is drawn outside
    /// the layout, so a line that can be clicked is spaced exactly like one that can't.
    private func part(_ content: AnyView, _ expr: Expr, _ origin: Origin?, _ size: CGFloat) -> AnyView {
        guard let touch, let origin else { return content }
        let part = MathPart(line: touch.line, path: origin.path, expr: expr)
        let id = touch.line + "/" + origin.name
        let fill: Color
        if touch.picked == part {
            fill = touch.accent.opacity(0.36)
        } else if let picked = touch.picked, Self.kind(of: picked.expr) == Self.kind(of: expr) {
            // The same kind of term elsewhere (3x picked lights 5x and 2x too, in every step),
            // so it can be followed down the working as it moves and combines.
            fill = touch.accent.opacity(0.16)
        } else if touch.hovered == id, touch.hoveredNumber == nil {
            fill = Color.white.opacity(0.1)
        } else {
            fill = .clear
        }
        return AnyView(content
            .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(fill)
                .padding(.horizontal, -size * 0.14).padding(.vertical, -size * 0.08))
            .contentShape(Rectangle())
            .onHover { touch.hover(id, $0) }
            .onTapGesture { touch.pick(part) })
    }

    private func number(_ value: Number, _ size: CGFloat, _ origin: Origin?) -> AnyView {
        let drawn: AnyView
        if let rational = value.rational, !rational.isInteger {
            let fraction = self.fraction(text(String(abs(rational.numerator)), size), text(String(rational.denominator), size), size)
            drawn = rational.numerator < 0 ? AnyView(HStack(spacing: 1) { text("−", size); fraction }) : fraction
        } else {
            drawn = text(Format.number(value), size)
        }
        guard let touch, let change = touch.change, let origin else { return drawn }
        let spot = MathNumber(line: touch.line, path: origin.path, negated: origin.negated, shown: value)
        if let changing = touch.changing, changing.line == spot.line, changing.path == spot.path, let field = touch.field {
            return field(spot, size)
        }
        // A number inside a term waits for the term to be picked: the first click says what
        // the term is, and then the number, now underlined, can be clicked to change it.
        guard within == nil || touch.picked == within else { return drawn }
        let id = "n:" + touch.line + "/" + origin.name
        return AnyView(drawn
            .background(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(touch.hoveredNumber == id ? touch.accent.opacity(0.5) : Color.clear)
                .padding(.horizontal, -size * 0.1).padding(.vertical, -size * 0.04))
            .overlay(alignment: .bottom) {
                if within != nil {
                    Rectangle().fill(Color.white.opacity(0.75)).frame(height: max(1, size / 16)).offset(y: size * 0.06)
                }
            }
            .contentShape(Rectangle())
            .onHover { touch.hover(id, $0) }
            .onTapGesture { change(spot) })
    }

    // MARK: Drawing

    private func brackets(_ content: AnyView, tall: Bool, _ size: CGFloat) -> AnyView {
        // Around something tall, like a fraction, brackets grow and thin out; otherwise they
        // match the text.
        guard tall else { return AnyView(HStack(spacing: 0) { text("(", size); content; text(")", size) }) }
        return AnyView(HStack(spacing: 0) {
            Text("(").font(.system(size: size * 1.9, weight: .ultraLight))
            content
            Text(")").font(.system(size: size * 1.9, weight: .ultraLight))
        })
    }

    /// Whether drawing it stacks things, so brackets around it need to be taller.
    private func isTall(_ expr: Expr) -> Bool {
        switch expr {
        case .number(let value): !(value.rational?.isInteger ?? true)
        case .multiply(let factors):
            factors.contains { factor in
                if case .power(_, let e) = factor, e.number?.isNegative == true { return true }
                return isTall(factor)
            }
        case .add(let terms): terms.contains(where: isTall)
        case .power(let base, let e): e.number?.isNegative == true || isTall(base)
        case .function(_, let argument): isTall(argument)
        default: false
        }
    }

    private func sum(_ terms: [Expr], _ size: CGFloat, _ origin: Origin?, parts: Bool) -> AnyView {
        // The same order as the text: a positive term first, numbers before surds.
        let order = reorder(terms)
        return AnyView(HStack(alignment: .center, spacing: size * 0.25) {
            ForEach(Array(order.enumerated()), id: \.offset) { position, index in
                let termOrigin = origin?.child(index)
                let (negative, body, bodyOrigin) = split(terms[index], termOrigin)
                let sign: String? = position == 0 ? (negative ? "−" : nil) : (negative ? "−" : "+")
                let isSum = { if case .add = body { true } else { false } }()
                if isSum, !negative {
                    // A sum written inside a sum reads as one: its terms are the parts.
                    if position > 0 { text("+", size) }
                    view(body, size, bodyOrigin, parts: parts)
                } else {
                    let group: (MathRender) -> AnyView = { render in
                        AnyView(HStack(alignment: .center, spacing: position == 0 ? 1 : size * 0.25) {
                            if let sign { render.text(sign, size) }
                            if isSum {
                                render.brackets(render.view(body, size, bodyOrigin), tall: render.isTall(body), size)
                            } else {
                                render.view(body, size, bodyOrigin)
                            }
                        })
                    }
                    if parts { asPart(terms[index], termOrigin, size, group) } else { group(self) }
                }
            }
        })
    }

    /// The order to draw a sum's terms in, as places in `terms`.
    private func reorder(_ terms: [Expr]) -> [Int] {
        var order = Array(terms.indices)
        let surdOrImaginary = terms.contains { term in
            if term.contains("i") { return true }
            let factors: [Expr] = if case .multiply(let parts) = term { parts } else { [term] }
            return factors.contains { if case .power(.number, let e) = $0, e.number?.rational?.isInteger == false { true } else { false } }
        }
        if surdOrImaginary, terms.allSatisfy({ $0.symbols.subtracting(["i"]).isEmpty }),
           let index = terms.lastIndex(where: { $0.number != nil }) {
            order.insert(order.remove(at: index), at: 0)
        } else if split(terms[0]).0, let positive = terms.firstIndex(where: { !split($0).0 }) {
            order.insert(order.remove(at: positive), at: 0)
        }
        return order
    }

    /// A term's sign, the term without it, and where that comes from.
    private func split(_ term: Expr, _ origin: Origin? = nil) -> (Bool, Expr, Origin?) {
        switch term {
        case .number(let value) where value.isNegative:
            return (true, .number(value.negated), origin.map { Origin(path: $0.path, negated: true) })
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                if value.negated.isOne && factors.count > 1 {
                    let rest = Array(factors.dropFirst())
                    if rest.count == 1 { return (true, rest[0], origin?.child(1)) }
                    return (true, .multiply(rest), origin.map { Origin(path: $0.path, shift: $0.shift + 1) })
                }
                return (true, .multiply([.number(value.negated)] + factors.dropFirst()),
                        origin.map { Origin(path: $0.path, shift: $0.shift, negatesFirst: true) })
            }
            return (false, term, origin)
        default:
            return (false, term, origin)
        }
    }

    private func product(_ factors: [Expr], _ size: CGFloat, _ origin: Origin?, parts: Bool = false) -> AnyView {
        // (A product of numbers inside it counts as one of them: 5 × 5(5 × 5) is drawn
        // 5 × 5 × (5 × 5), not 5 × 55 × 5.)
        let numbers = factors.filter { $0.number != nil || Format.isProductOfNumbers($0) }
        // Working before it's simplified: 2 × 4, 12 × 7.5 ÷ 3, 12 × (3 + 4.5)
        // (And a number in front of something that starts with a number: 3 × 2x, not 32x.)
        let startsWithNumber = factors.contains { if case .multiply(let inner) = $0 { inner.first?.number != nil && !Format.isProductOfNumbers($0) } else { false } }
        if numbers.count > 1 || (numbers.count == 1 && factors.first?.number == nil)
            || (numbers.count == 1 && (factors.contains(where: isSumOfNumbers) || startsWithNumber)) {
            return AnyView(HStack(spacing: size * 0.2) {
                ForEach(Array(factors.enumerated()), id: \.offset) { index, factor in
                    if index > 0, case .power(let base, .minusOne) = factor {
                        text("÷", size)
                        wrapped(base, size, origin?.child(index).child(0))
                    } else {
                        if index > 0 { text("×", size) }
                        if index > 0, Format.isProductOfNumbers(factor) {
                            brackets(view(factor, size, origin?.child(index)), tall: isTall(factor), size)
                        } else {
                            wrapped(factor, size, origin?.child(index), bracketNegative: true)
                        }
                    }
                }
            })
        }
        var topNumber: String?, bottomNumber: String?
        var coefficient: (Number, Origin)?
        var top: [(Expr, Origin?)] = [], bottom: [(Expr, Origin?)] = []
        for (index, factor) in factors.enumerated() {
            let place = origin?.child(index)
            if case .number(let value) = factor {
                if let rational = value.rational {
                    if rational.numerator != 1 { topNumber = String(rational.numerator) }
                    if rational.denominator != 1 { bottomNumber = String(rational.denominator) }
                    if rational.isInteger, let place { coefficient = (value, place) }
                } else {
                    topNumber = Format.number(value)
                    if let place { coefficient = (value, place) }
                }
            } else if case .power(let base, let exponent) = factor, let e = exponent.number, e.isNegative {
                bottom.append((Simplify.power(base, .number(e.negated)), e.negated.isOne ? place?.child(0) : nil))
            } else {
                top.append((factor, place))
            }
        }
        let numerator = row(top, leading: topNumber ?? (top.isEmpty ? "1" : nil), coefficient: topNumber == nil ? nil : coefficient, size, parts: parts)
        guard !bottom.isEmpty || bottomNumber != nil else { return numerator }
        return fraction(numerator, row(bottom, leading: bottomNumber, coefficient: nil, size, parts: parts), size)
    }

    /// A bracket of plain numbers, as in a sum still to be worked out: (3 + 4.5).
    private func isSumOfNumbers(_ expr: Expr) -> Bool {
        func plain(_ expr: Expr) -> Bool {
            switch expr {
            case .number: true
            case .add(let parts), .multiply(let parts): parts.allSatisfy(plain)
            default: false
            }
        }
        if case .add = expr { return plain(expr) }
        return false
    }

    /// Factors side by side: 3x²y, 2√3, 3(x + 1).
    private func row(_ factors: [(Expr, Origin?)], leading: String?, coefficient: (Number, Origin)?, _ size: CGFloat, parts: Bool) -> AnyView {
        AnyView(HStack(alignment: .center, spacing: 1) {
            if let leading {
                if let coefficient { number(coefficient.0, size, coefficient.1) } else { text(leading, size) }
            }
            ForEach(Array(factors.enumerated()), id: \.offset) { index, item in
                let (factor, origin) = item
                if case .function = factor, index > 0 || leading != nil {
                    Spacer().frame(width: size * 0.2)
                }
                // 6 × 1², not 61²
                if index > 0 || leading != nil, isWholePowerOfNumber(factor) {
                    text("×", size).padding(.horizontal, size * 0.2)
                }
                if parts { asPart(factor, origin, size) { $0.wrapped(factor, size, origin) } } else { wrapped(factor, size, origin) }
            }
        })
    }

    private func isWholePowerOfNumber(_ expr: Expr) -> Bool {
        if case .power(.number, let exponent) = expr, exponent.number?.rational?.isInteger == true { return true }
        return false
    }

    private func wrapped(_ expr: Expr, _ size: CGFloat, _ origin: Origin?, bracketNegative: Bool = false) -> AnyView {
        if case .add = expr { return brackets(view(expr, size, origin), tall: isTall(expr), size) }
        if bracketNegative, case .number(let value) = expr, value.isNegative { return brackets(view(expr, size, origin), tall: false, size) }
        return view(expr, size, origin)
    }

    private func power(_ base: Expr, _ exponent: Expr, _ size: CGFloat, _ origin: Origin?) -> AnyView {
        if let e = exponent.number, e.isNegative {
            let under = e.negated.isOne ? origin?.child(0) : nil
            return fraction(text("1", size), view(Simplify.power(base, .number(e.negated)), size, under), size)
        }
        if exponent == .half || exponent == .fraction(1, 3) {
            let content = view(base, size, origin?.child(0))
            return AnyView(HStack(alignment: .bottom, spacing: 0) {
                if exponent != .half {
                    Text("3").font(.system(size: size * 0.5)).padding(.bottom, size * 0.55)
                }
                Text("√").font(.system(size: size * 1.15))
                content
                    .padding(.top, size * 0.18)
                    .overlay(alignment: .top) { Rectangle().frame(height: max(1, size / 16)) }
            })
        }
        let drawn = view(base, size, origin?.child(0))
        let baseView: AnyView = Format.isAtomic(base) ? drawn : brackets(drawn, tall: isTall(base), size)
        // Monospaced letters are wide, so the power tucks in closer.
        return AnyView(HStack(alignment: .bottom, spacing: design == .monospaced ? -size * 0.07 : size * 0.04) {
            baseView
            view(exponent, size * 0.6, origin?.child(1)).padding(.bottom, size * 0.52)
        })
    }

    private func functionView(_ function: MathFunction, _ argument: Expr, _ size: CGFloat, _ origin: Origin?) -> AnyView {
        let inside = origin?.child(0)
        if function == .abs {
            return AnyView(HStack(spacing: 2) { text("|", size); view(argument, size, inside); text("|", size) })
        }
        let name = text(Format.functionName(function), size)
        if function.takesAngle, MathSettings.angles == .degrees, case .number(let value) = argument, !value.isNegative {
            return AnyView(HStack(spacing: size * 0.2) { name; text(Format.number(value) + "°", size) })
        }
        if Format.isAtomic(argument) {
            return AnyView(HStack(spacing: size * 0.2) { name; view(argument, size, inside) })
        }
        if case .function(.abs, _) = argument {
            return AnyView(HStack(spacing: 1) { name; view(argument, size, inside) })
        }
        return AnyView(HStack(spacing: 1) { name; brackets(view(argument, size, inside), tall: isTall(argument), size) })
    }
}

/// Maths written as text ("3/4 + 5/6", "x = 1/2 or x = 3") drawn as maths, in the maths
/// typeface and with a fraction stacked rather than written with a slash. Text that isn't only
/// maths ("Expand (x + 2)(x + 3)", "d/dx x³", "Copied") is left as it's written.
struct MathText: View {
    let text: String
    var size: CGFloat = 15
    var weight: Font.Weight = .regular
    /// Shown as words when it can't be read as maths.
    var plainFont: Font?

    var body: some View {
        if let pieces = Self.pieces(text) {
            HStack(alignment: .center, spacing: size * 0.4) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    switch piece {
                    case .line(let line): MathLineView(line: line, size: size, design: Z.maths, weight: weight)
                    case .word(let word): Text(word).font(.system(size: size * 0.9, weight: weight))
                    }
                }
            }
            .fixedSize()
        } else {
            Text(text).font(plainFont ?? .system(size: size, weight: weight))
        }
    }

    enum Piece {
        case line(MathLine)
        case word(String)
    }

    /// The text as lines of maths and the words between them, or nil to leave it as text.
    static func pieces(_ text: String) -> [Piece]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("d/d"), trimmed.rangeOfCharacter(from: .decimalDigits.union(.letters)) != nil else { return nil }
        // Words other than maths functions mean it's a sentence or an instruction.
        let functions: Set<String> = ["sin", "cos", "tan", "ln", "log", "sqrt", "or"]
        let words = trimmed.split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 || $0 == "or" }
        guard words.allSatisfy({ functions.contains($0.lowercased()) }) else { return nil }
        var body = trimmed
        var ending: String?
        if body.hasSuffix("=") { body = String(body.dropLast()).trimmingCharacters(in: .whitespaces); ending = "=" }
        var pieces: [Piece] = []
        let alternatives = body.components(separatedBy: " or ")
        for (index, alternative) in alternatives.enumerated() {
            if index > 0 { pieces.append(.word("or")) }
            let parts = alternative.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for (number, part) in parts.enumerated() {
                if number > 0 { pieces.append(.word(",")) }
                let sides = part.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                let read = sides.compactMap { Parser.expression($0.replacingOccurrences(of: "−", with: "-")) }
                guard read.count == sides.count, !read.isEmpty else { return nil }
                pieces.append(.line(MathLine(parts: read)))
            }
        }
        if let ending { pieces.append(.word(ending)) }
        return pieces
    }
}
