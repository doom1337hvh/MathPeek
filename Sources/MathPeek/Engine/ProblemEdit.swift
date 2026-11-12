import Foundation

/// A problem as it's written out, so a number in it can be changed and the problem read again.
extension ProblemKind {
    /// The lines the problem is shown as: each equation, or the one expression.
    var lines: [MathLine] {
        switch self {
        case .solve(let equations, _): equations.map { MathLine($0.left, $0.right) }
        case .evaluate(let expr), .simplify(let expr), .expand(let expr), .factorise(let expr): [MathLine(expr)]
        case .differentiate(let expr, _, _), .integrate(let expr, _, _, _), .substitute(let expr, _), .remainder(let expr, _): [MathLine(expr)]
        case .sequence(let terms): [MathLine(.symbol(terms.map(Format.text).joined(separator: ", ") + ", …"))]
        case .diagram(_, let find): [MathLine(.symbol(find))]
        case .worded(let question, _): [MathLine(.symbol(question))]
        }
    }

    /// The problem with one side of one of its lines replaced.
    func replacing(line: Int, side: Int, with new: Expr) -> ProblemKind {
        switch self {
        case .solve(var equations, let unknowns):
            guard equations.indices.contains(line) else { return self }
            if side == 0 { equations[line].left = new } else { equations[line].right = new }
            return .solve(equations, unknowns: unknowns)
        case .evaluate: return .evaluate(new)
        case .simplify: return .simplify(new)
        case .expand: return .expand(new)
        case .factorise: return .factorise(new)
        case .differentiate(_, let variable, let order): return .differentiate(new, variable: variable, order: order)
        case .integrate(_, let variable, let from, let to): return .integrate(new, variable: variable, from: from, to: to)
        case .substitute(_, let values): return .substitute(new, values: values)
        case .remainder(_, let modulus): return .remainder(new, modulus: modulus)
        case .sequence, .diagram, .worded: return self
        }
    }

    /// Written as a line MathPeek can read back.
    var text: String {
        switch self {
        case .evaluate(let expr), .simplify(let expr):
            return Format.text(expr)
        case .expand(let expr):
            return "Expand " + Format.text(expr)
        case .factorise(let expr):
            return "Factorise " + Format.text(expr)
        case .solve(let equations, let unknowns):
            let written = equations.map { Format.text($0.left) + " = " + Format.text($0.right) }.joined(separator: "; ")
            return unknowns.isEmpty || equations.count > 1 ? written : written + " for " + unknowns.joined(separator: ", ")
        case .differentiate(let expr, let variable, let order):
            return (order == 2 ? "d²/d\(variable)² " : "d/d\(variable) ") + Format.text(expr)
        case .integrate(let expr, let variable, let from, let to):
            let limits = from.flatMap { a in to.map { b in " from \(Format.text(a)) to \(Format.text(b))" } } ?? ""
            return "∫ " + Format.text(expr) + " d\(variable)" + limits
        case .substitute(let expr, let values):
            return Format.text(expr) + " when " + values.sorted { $0.key < $1.key }.map { "\($0.key) = \(Format.text($0.value))" }.joined(separator: ", ")
        case .remainder(let expr, let modulus):
            return Format.text(expr) + " mod \(modulus)"
        case .sequence(let terms):
            return "nth term of " + terms.map(Format.text).joined(separator: ", ")
        case .diagram(_, let find):
            return find
        case .worded(let question, _):
            return question
        }
    }

    /// The letter the problem is about, if it has one.
    var variable: String? {
        switch self {
        case .solve(let equations, let unknowns):
            unknowns.first ?? Parser.mainVariable(equations.reduce(into: Set<String>()) { $0.formUnion($1.left.symbols.union($1.right.symbols)) })
        case .differentiate(_, let variable, _), .integrate(_, let variable, _, _): variable
        case .evaluate(let expr), .simplify(let expr), .expand(let expr), .factorise(let expr), .substitute(let expr, _), .remainder(let expr, _):
            Parser.mainVariable(expr.symbols)
        case .sequence: "n"
        case .diagram, .worded: nil
        }
    }
}

extension Expr {
    /// This with what's at `path` replaced: a place in a sum or product, 0 or 1 for a power's
    /// base or exponent, 0 for what a function applies to. Nil if there's nothing there.
    func replacing(at path: ArraySlice<Int>, with new: Expr) -> Expr? {
        guard let index = path.first else { return new }
        let rest = path.dropFirst()
        switch self {
        case .add(var parts):
            guard parts.indices.contains(index), let part = parts[index].replacing(at: rest, with: new) else { return nil }
            parts[index] = part
            return .add(parts)
        case .multiply(var parts):
            guard parts.indices.contains(index), let part = parts[index].replacing(at: rest, with: new) else { return nil }
            parts[index] = part
            return .multiply(parts)
        case .power(let base, let exponent):
            if index == 0 { return base.replacing(at: rest, with: new).map { .power($0, exponent) } }
            if index == 1 { return exponent.replacing(at: rest, with: new).map { .power(base, $0) } }
            return nil
        case .function(let function, let argument):
            guard index == 0 else { return nil }
            return argument.replacing(at: rest, with: new).map { .function(function, $0) }
        default:
            return nil
        }
    }
}
