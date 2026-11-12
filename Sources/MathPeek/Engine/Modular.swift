import Foundation

/// Remainders: what's left when a whole number, however large, is divided by another. Powers
/// far too big to work out are brought down by finding where their remainders repeat.
enum Modular {
    /// Above this, a divisor's remainders could overflow when multiplied.
    private static let largestModulus = 2_000_000_000

    static func remainder(_ expr: Expr, modulus m: Int, _ problem: Problem) -> Solution? {
        guard m >= 2, m <= largestModulus else { return nil }
        var work = Work(m: m)
        guard let reduced = work.reduce(expr), let value = value(of: reduced, mod: m) else { return nil }
        let suffix = "(mod \(m))"
        var steps: [Step] = []
        if !work.swapped.isEmpty {
            steps.append(Step(work.swapped.count == 1 ? "Divide by \(m)" : "Take the remainder of each number", "", work.swapped))
        }
        steps += work.steps

        // Putting the pieces together, unless the problem was a single number or power.
        var isCompound = false
        switch expr {
        case .add: isCompound = true
        case .multiply(let factors): isCompound = !(factors.count == 2 && factors[0] == .minusOne && factors[1].number != nil)
        default: break
        }
        if isCompound {
            var lines: [MathLine] = []
            if reduced != expr { lines.append(MathLine(expr, reduced, relation: "≡", suffix: suffix)) }
            let total = Simplify.run(reduced).number?.integer
            if let total, Expr.integer(total) != reduced { lines.append(MathLine(reduced, .integer(total))) }
            if let total, total != value {
                lines.append(MathLine(.integer(total), .integer(value), relation: "≡", suffix: suffix))
            } else if total == nil {
                lines.append(MathLine(reduced, .integer(value), relation: "≡", suffix: suffix))
            }
            var title = "Multiply the remainders"
            if case .add(let terms) = reduced {
                let subtracts = terms.contains { Simplify.splitCoefficient($0).0.isNegative }
                title = subtracts ? "Combine the remainders" : "Add the remainders"
            }
            if reduced == expr { title = "Work it out" }
            if !lines.isEmpty { steps.append(Step(title, "", lines)) }
        }
        return Solution(problem: problem, question: MathLine(expr), task: "Remainder when divided by \(m)",
                        answers: [MathLine(.integer(value))], steps: steps)
    }

    /// The remainder of a sum, product or power of whole numbers, without ever holding a big number.
    static func value(of expr: Expr, mod m: Int) -> Int? {
        switch expr {
        case .number(let number):
            guard let value = number.integer else { return nil }
            return ((value % m) + m) % m
        case .add(let terms):
            var sum = 0
            for term in terms {
                guard let value = value(of: term, mod: m) else { return nil }
                sum = (sum + value) % m
            }
            return sum
        case .multiply(let factors):
            var product = 1 % m
            for factor in factors {
                guard let value = value(of: factor, mod: m) else { return nil }
                product = product * value % m
            }
            return product
        case .power(let base, let exponent):
            guard let b = value(of: base, mod: m), let k = Simplify.run(exponent).number?.integer, k >= 0 else { return nil }
            return power(b, k, mod: m)
        default:
            return nil
        }
    }

    /// base^exponent mod m, by squaring.
    static func power(_ base: Int, _ exponent: Int, mod m: Int) -> Int {
        var result = 1 % m, square = base % m, left = exponent
        while left > 0 {
            if left & 1 == 1 { result = result * square % m }
            square = square * square % m
            left >>= 1
        }
        return result
    }

    /// base^exponent itself, if it's small enough to write down.
    static func smallPower(_ base: Int, _ exponent: Int) -> Int? {
        var result = 1
        for _ in 0..<exponent {
            result *= base
            if result > 1_000_000 { return nil }
        }
        return result
    }

    static func isPrime(_ n: Int) -> Bool {
        guard n >= 2 else { return false }
        if n < 4 { return true }
        if n % 2 == 0 { return false }
        var divisor = 3
        while divisor * divisor <= n {
            if n % divisor == 0 { return false }
            divisor += 2
        }
        return true
    }

    /// 2026 as raised digits, for a step's title.
    static func raised(_ n: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        return String(String(n).map { digits[$0] ?? $0 })
    }

    /// The working for one problem.
    private struct Work {
        let m: Int
        var steps: [Step] = []
        /// Numbers swapped for their remainders: 17 = 5 × 3 + 2.
        var swapped: [MathLine] = []
        /// Powers already brought down, so the same one isn't explained twice.
        var known: [Expr: Int] = [:]

        private var suffix: String { "(mod \(m))" }

        private func congruent(_ parts: Expr...) -> MathLine {
            MathLine(parts: parts, relation: "≡", suffix: suffix)
        }

        /// n as a multiple of `divisor` plus what's left: 13 × 78 + 10.
        private func split(_ n: Int, by divisor: Int) -> Expr {
            let multiple = Expr.multiply([.integer(divisor), .integer(n / divisor)])
            return n % divisor == 0 ? multiple : .add([multiple, .integer(n % divisor)])
        }

        /// The expression with each big number and each power replaced by its remainder.
        mutating func reduce(_ expr: Expr) -> Expr? {
            switch expr {
            case .number(let number):
                guard let value = number.integer else { return nil }
                guard abs(value) >= m else { return expr }
                swapped.append(MathLine(expr, split(value, by: m)))
                return .integer(value % m)
            case .add(let terms):
                var reduced: [Expr] = []
                for term in terms {
                    guard let part = reduce(term) else { return nil }
                    reduced.append(part)
                }
                return .add(reduced)
            case .multiply(let factors):
                var reduced: [Expr] = []
                for factor in factors {
                    guard let part = reduce(factor) else { return nil }
                    reduced.append(part)
                }
                return .multiply(reduced)
            case .power(let base, let exponent):
                guard let k = Simplify.run(exponent).number?.integer, k >= 0 else { return nil }
                if let value = known[expr] { return .integer(value) }
                guard let reducedBase = reduce(base), let r = Modular.value(of: reducedBase, mod: m) else { return nil }
                let value = power(written: base, r, k)
                known[expr] = value
                return .integer(value)
            default:
                return nil
            }
        }

        /// The remainder of r^k, with the steps that find it. `written` is the base as the
        /// problem has it, which r is the remainder of.
        private mutating func power(written: Expr, _ r: Int, _ k: Int) -> Int {
            let whole = Expr.power(written, .integer(k))
            let b = Expr.integer(r)
            let name = (Format.isAtomic(written) ? Format.text(written) : "(" + Format.text(written) + ")") + Modular.raised(k)
            func raise(_ exponent: Int) -> Expr { exponent == 1 ? b : .power(b, .integer(exponent)) }
            var lines: [MathLine] = written == b ? [] : [congruent(whole, raise(k))]

            if k == 0 { return 1 % m }
            if r == 0 {
                steps.append(Step("\(Format.text(written)) is a multiple of \(m)", "So is every power of it.", [congruent(whole, .zero)]))
                return 0
            }
            if r == 1 {
                steps.append(Step("\(Format.text(written)) leaves remainder 1", "So does every power of it.", [congruent(whole, .one)]))
                return 1
            }
            // Small enough to work out as it is.
            if let direct = Modular.smallPower(r, k) {
                lines.append(direct >= m ? MathLine(raise(k), .integer(direct), split(direct, by: m)) : MathLine(raise(k), .integer(direct)))
                if direct >= m || written != b { lines.append(congruent(whole, .integer(direct % m))) }
                steps.append(Step("Work out \(name)", "", lines))
                return direct % m
            }

            // The remainders of r, r², r³, … until one comes round again.
            var remainders = [r]
            var firstSeen = [r: 1]
            var loop: (start: Int, length: Int)?
            var current = r
            for exponent in 2...min(m + 1, 4000) {
                current = current * r % m
                if let seen = firstSeen[current] {
                    loop = (seen, exponent - seen)
                    break
                }
                firstSeen[current] = exponent
                remainders.append(current)
            }
            let listed = remainders.prefix(12).map(String.init).joined(separator: ", ") + (remainders.count > 12 ? ", …" : "")

            // A power that leaves remainder 1: from there on the remainders repeat.
            var cycle: Int?
            var finding: Step?
            let fermat = "\(m) is prime and \(r) isn't a multiple of it, so Fermat's little theorem says \(r)\(Modular.raised(m - 1)) leaves remainder 1."
            if let loop, loop.start == 1, remainders.indices.contains(loop.length - 1), remainders[loop.length - 1] == 1 {
                let order = loop.length
                if let small = Modular.smallPower(r, order) {
                    finding = Step("Find a power of \(r) that leaves remainder 1", "",
                                   [MathLine(raise(order), .integer(small), split(small, by: m)), congruent(raise(order), .one)])
                    cycle = order
                } else if Modular.isPrime(m), k >= m - 1 {
                    finding = Step("Find a power of \(r) that leaves remainder 1", fermat, [congruent(raise(m - 1), .one)])
                    cycle = m - 1
                } else {
                    finding = Step("Find a power of \(r) that leaves remainder 1",
                                   "The powers of \(r) leave remainders \(listed), reaching 1 at \(r)\(Modular.raised(order)).",
                                   [congruent(raise(order), .one)])
                    cycle = order
                }
            } else if loop == nil, Modular.isPrime(m) {
                finding = Step("Find a power of \(r) that leaves remainder 1", fermat, [congruent(raise(m - 1), .one)])
                cycle = m - 1
            }
            // A power smaller than the cycle can't be reduced by it.
            if let length = cycle, k < length { cycle = nil }

            if let cycle {
                if let finding { steps.append(finding) }
                let left = k % cycle
                lines.append(MathLine(.integer(k), split(k, by: cycle)))
                let explanation = "Each \(r)\(Modular.raised(cycle)) is worth 1, so " + (left == 0 ? "nothing is left over." : "only the \(left) left over counts.")
                let value: Int
                if left == 0 {
                    lines.append(congruent(whole, .one))
                    value = 1 % m
                } else if left == 1 {
                    lines.append(congruent(whole, b))
                    value = r
                } else if let small = Modular.smallPower(r, left) {
                    lines.append(congruent(whole, raise(left)))
                    if small >= m {
                        lines.append(MathLine(raise(left), .integer(small), split(small, by: m)))
                        lines.append(congruent(whole, .integer(small % m)))
                    } else {
                        lines.append(MathLine(raise(left), .integer(small)))
                    }
                    value = small % m
                } else {
                    value = Modular.power(r, left, mod: m)
                    lines.append(congruent(whole, raise(left), .integer(value)))
                }
                steps.append(Step("Reduce the power in \(name)", explanation, lines))
                return value
            }

            // The remainders repeat without ever reaching 1.
            if let loop {
                let position = k < loop.start + loop.length ? k : loop.start + (k - loop.start) % loop.length
                let value = remainders[position - 1]
                lines.append(congruent(whole, .integer(value)))
                let from = loop.start == 1 ? "" : " from \(r)\(Modular.raised(loop.start)) on"
                steps.append(Step("Follow the remainders of the powers of \(r)",
                                  "They go \(listed), repeating every \(loop.length)\(from). \(name) lands on \(value).", lines))
                return value
            }

            let value = Modular.power(r, k, mod: m)
            lines.append(congruent(whole, .integer(value)))
            steps.append(Step("Work out \(name) a square at a time", "Square, take the remainder, and repeat, so the numbers never get big.", lines))
            return value
        }
    }
}
