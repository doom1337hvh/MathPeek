import SwiftUI

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

/// A line of maths: parts joined by =, ≈ or →.
struct MathLineView: View {
    let line: MathLine
    var size: CGFloat = 18
    var design: Font.Design = .serif
    var weight: Font.Weight = .regular

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.35) {
            ForEach(Array(line.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(line.relation)
                        .font(.system(size: size, weight: weight, design: design))
                        .foregroundStyle(line.relation == "→" ? .secondary : .primary)
                }
                MathRender(design: design, weight: weight).view(part, size)
            }
        }
        .fixedSize()
    }
}

/// Draws one expression, in the font design and weight asked for.
struct MathRender {
    var design: Font.Design = .serif
    var weight: Font.Weight = .regular

    func view(_ expr: Expr, _ size: CGFloat) -> AnyView {
        switch expr {
        case .number(let value):
            if let rational = value.rational, !rational.isInteger {
                let fraction = self.fraction(text(String(abs(rational.numerator)), size), text(String(rational.denominator), size), size)
                return rational.numerator < 0 ? AnyView(HStack(spacing: 1) { text("−", size); fraction }) : fraction
            }
            return text(Format.number(value), size)
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
            return sum(terms, size)
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                let rest = value.negated.isOne && factors.count > 1 ? Array(factors.dropFirst()) : [Expr.number(value.negated)] + factors.dropFirst()
                return AnyView(HStack(spacing: 1) { text("−", size); product(rest, size) })
            }
            return product(factors, size)
        case .power(let base, let exponent):
            return power(base, exponent, size)
        case .function(let function, let argument):
            return functionView(function, argument, size)
        }
    }

    func text(_ string: String, _ size: CGFloat, italic: Bool = false) -> AnyView {
        AnyView(Text(string).font(.system(size: size, weight: weight, design: design)).italic(italic && design == .serif))
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

    private func sum(_ rawTerms: [Expr], _ size: CGFloat) -> AnyView {
        // The same order as the text: a positive term first, numbers before surds.
        let ordered = reorder(rawTerms)
        return AnyView(HStack(alignment: .center, spacing: size * 0.25) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, term in
                let (negative, body) = split(term)
                if index == 0 {
                    if negative { HStack(spacing: 1) { text("−", size); view(body, size) } } else { view(body, size) }
                } else {
                    text(negative ? "−" : "+", size)
                    view(body, size)
                }
            }
        })
    }

    private func reorder(_ terms: [Expr]) -> [Expr] {
        var terms = terms
        let surdOrImaginary = terms.contains { term in
            if term.contains("i") { return true }
            let factors: [Expr] = if case .multiply(let parts) = term { parts } else { [term] }
            return factors.contains { if case .power(.number, let e) = $0, e.number?.rational?.isInteger == false { true } else { false } }
        }
        if surdOrImaginary, terms.allSatisfy({ $0.symbols.subtracting(["i"]).isEmpty }),
           let index = terms.lastIndex(where: { $0.number != nil }) {
            terms.insert(terms.remove(at: index), at: 0)
        } else if split(terms[0]).0, let positive = terms.firstIndex(where: { !split($0).0 }) {
            terms.insert(terms.remove(at: positive), at: 0)
        }
        return terms
    }

    /// A term's sign, and the term without it.
    private func split(_ term: Expr) -> (Bool, Expr) {
        switch term {
        case .number(let value) where value.isNegative:
            return (true, .number(value.negated))
        case .multiply(let factors):
            if case .number(let value) = factors.first, value.isNegative {
                if value.negated.isOne && factors.count > 1 {
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

    private func product(_ factors: [Expr], _ size: CGFloat) -> AnyView {
        let numbers = factors.filter { $0.number != nil }
        // Working before it's simplified: 2 × 4, 12 × 7.5 ÷ 3
        if numbers.count > 1 || (numbers.count == 1 && factors.first?.number == nil) {
            return AnyView(HStack(spacing: size * 0.2) {
                ForEach(Array(factors.enumerated()), id: \.offset) { index, factor in
                    if index > 0, case .power(let base, .minusOne) = factor {
                        text("÷", size)
                        wrapped(base, size)
                    } else {
                        if index > 0 { text("×", size) }
                        wrapped(factor, size, bracketNegative: true)
                    }
                }
            })
        }
        var topNumber: String?, bottomNumber: String?
        var top: [Expr] = [], bottom: [Expr] = []
        for factor in factors {
            if case .number(let value) = factor {
                if let rational = value.rational {
                    if rational.numerator != 1 { topNumber = String(rational.numerator) }
                    if rational.denominator != 1 { bottomNumber = String(rational.denominator) }
                } else {
                    topNumber = Format.number(value)
                }
            } else if case .power(let base, let exponent) = factor, let e = exponent.number, e.isNegative {
                bottom.append(Simplify.power(base, .number(e.negated)))
            } else {
                top.append(factor)
            }
        }
        let numerator = row(top, leading: topNumber ?? (top.isEmpty ? "1" : nil), size)
        guard !bottom.isEmpty || bottomNumber != nil else { return numerator }
        return fraction(numerator, row(bottom, leading: bottomNumber, size), size)
    }

    /// Factors side by side: 3x²y, 2√3, 3(x + 1).
    private func row(_ factors: [Expr], leading: String?, _ size: CGFloat) -> AnyView {
        AnyView(HStack(alignment: .center, spacing: 1) {
            if let leading { text(leading, size) }
            ForEach(Array(factors.enumerated()), id: \.offset) { index, factor in
                if case .function = factor, index > 0 || leading != nil {
                    Spacer().frame(width: size * 0.2)
                }
                // 6 × 1², not 61²
                if index > 0 || leading != nil, isWholePowerOfNumber(factor) {
                    text("×", size).padding(.horizontal, size * 0.2)
                }
                wrapped(factor, size)
            }
        })
    }

    private func isWholePowerOfNumber(_ expr: Expr) -> Bool {
        if case .power(.number, let exponent) = expr, exponent.number?.rational?.isInteger == true { return true }
        return false
    }

    private func wrapped(_ expr: Expr, _ size: CGFloat, bracketNegative: Bool = false) -> AnyView {
        if case .add = expr { return brackets(view(expr, size), tall: isTall(expr), size) }
        if bracketNegative, case .number(let value) = expr, value.isNegative { return brackets(view(expr, size), tall: false, size) }
        return view(expr, size)
    }

    private func power(_ base: Expr, _ exponent: Expr, _ size: CGFloat) -> AnyView {
        if let e = exponent.number, e.isNegative {
            return fraction(text("1", size), view(Simplify.power(base, .number(e.negated)), size), size)
        }
        if exponent == .half || exponent == .fraction(1, 3) {
            let content = view(base, size)
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
        let baseView: AnyView = Format.isAtomic(base) ? view(base, size) : brackets(view(base, size), tall: isTall(base), size)
        // Monospaced letters are wide, so the power tucks in closer.
        return AnyView(HStack(alignment: .bottom, spacing: design == .monospaced ? -size * 0.07 : size * 0.04) {
            baseView
            view(exponent, size * 0.6).padding(.bottom, size * 0.52)
        })
    }

    private func functionView(_ function: MathFunction, _ argument: Expr, _ size: CGFloat) -> AnyView {
        if function == .abs {
            return AnyView(HStack(spacing: 2) { text("|", size); view(argument, size); text("|", size) })
        }
        let name = text(Format.functionName(function), size)
        if function.takesAngle, MathSettings.angles == .degrees, case .number(let value) = argument, !value.isNegative {
            return AnyView(HStack(spacing: size * 0.2) { name; text(Format.number(value) + "°", size) })
        }
        if Format.isAtomic(argument) {
            return AnyView(HStack(spacing: size * 0.2) { name; view(argument, size) })
        }
        if case .function(.abs, _) = argument {
            return AnyView(HStack(spacing: 1) { name; view(argument, size) })
        }
        return AnyView(HStack(spacing: 1) { name; brackets(view(argument, size), tall: isTall(argument), size) })
    }
}
