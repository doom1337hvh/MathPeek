import Foundation

/// What the words of a question add to its diagram. Exam questions give most of what's
/// needed in words ("Angle OCB = 34°", "BC = CD", "Work out the size of angle DOA"), with
/// the diagram only showing where the points are.
enum DiagramWords {
    /// Adds the angles the words give, the lengths they say are equal, and the angles they
    /// ask for. Only for points the diagram has by the same letters.
    static func apply(_ words: String, to diagram: inout CircleDiagram) {
        // Text recognition writes some capitals with letters from other alphabets that look the same.
        let alike: [Character: Character] = ["А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T", "Х": "X", "У": "Y",
                                             "Α": "A", "Β": "B", "Ε": "E", "Η": "H", "Κ": "K", "Μ": "M", "Ο": "O", "Ρ": "P", "Τ": "T", "Χ": "X", "Ζ": "Z", "Ν": "N"]
        let text = String(words.replacingOccurrences(of: "∠", with: "angle ").replacingOccurrences(of: "\n", with: " ").map { alike[$0] ?? $0 })
        func point(_ letter: Character) -> Int? { diagram.points.firstIndex { $0.name == String(letter) } }
        /// The angle XVY as the diagram draws it: anticlockwise from one line to the other,
        /// whichever way round is under 180°, or over it for a reflex angle.
        func angle(_ name: String, reflex: Bool) -> (vertex: Int, from: Int, to: Int)? {
            let letters = Array(name)
            guard letters.count == 3, let x = point(letters[0]), let v = point(letters[1]), let y = point(letters[2]), x != v, y != v, x != y else { return nil }
            // A line the question speaks of but the diagram doesn't draw, like a radius, is put in.
            for end in [x, y] where !diagram.lines.contains(where: { $0.points.contains(v) && $0.points.contains(end) }) {
                diagram.lines.append(.init(points: [v, end], tangentAt: nil))
            }
            let around = diagram.directions(at: v)
            func heading(_ target: Int) -> Double? {
                // The line from v that goes through the point, even past other points.
                guard let line = diagram.lines.first(where: { $0.points.contains(v) && $0.points.contains(target) }),
                      let here = line.points.firstIndex(of: v), let there = line.points.firstIndex(of: target) else { return nil }
                let next = line.points[here + (there > here ? 1 : -1)]
                return around.first { $0.towards == next }?.direction
            }
            guard let a = heading(x), let b = heading(y), a != b else { return nil }
            var turn = b - a
            if turn < 0 { turn += 2 * .pi }
            func towards(_ direction: Double) -> Int { around.first { $0.direction == direction }?.towards ?? x }
            return (turn <= .pi) != reflex ? (v, towards(a), towards(b)) : (v, towards(b), towards(a))
        }
        func matches(_ pattern: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
                (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            }
        }
        // "…a circle, centre O": the middle's letter, if the picture's wasn't read.
        if let letter = matches(#"(?i:centre)\s+([A-Z])\b"#).first?[1], !diagram.points.contains(where: { $0.name == letter }) {
            if let index = diagram.points.firstIndex(where: { $0.place == .centre && $0.name == nil }) {
                diagram.points[index].name = letter
            } else if !diagram.points.contains(where: { $0.place == .centre }), diagram.points.contains(where: { $0.place == .onCircle }) {
                // No line is drawn to it: it's the middle of the circle, which the diagram is measured from.
                diagram.points.append(.init(name: letter, x: 0, y: 0, place: .centre))
            }
        }
        // "A, B, C and D are points on the circumference": one point on the circle with no
        // letter, and one letter with no point, go together.
        for found in matches(#"((?:[A-Z],\s*)*[A-Z]\s+and\s+[A-Z])\s+are\s+(?:\w+\s+)?points\s+on"#) {
            let letters = found[1].filter(\.isUppercase).map(String.init)
            let missing = letters.filter { letter in !diagram.points.contains { $0.name == letter } }
            let unnamed = diagram.points.indices.filter { diagram.points[$0].place == .onCircle && diagram.points[$0].name == nil }
            if missing.count == 1, unnamed.count == 1 { diagram.points[unnamed[0]].name = missing[0] }
        }
        // One point outside the circle with no letter, and one letter the words use that no
        // point has: they go together.
        do {
            let used = Set(matches(#"\b[A-Z]{2,3}\b"#).flatMap { $0[0].map(String.init) })
            let missing = used.filter { letter in !diagram.points.contains { $0.name == letter } }
            let unnamed = diagram.points.indices.filter { diagram.points[$0].place == .outside && diagram.points[$0].name == nil }
            if missing.count == 1, unnamed.count == 1, let letter = missing.first { diagram.points[unnamed[0]].name = letter }
        }
        // "PA and PB are tangents", "DA is a tangent", "ABC is a tangent": the line touches
        // the circle at whichever of its points is on it. A tangent the picture's lines
        // missed is put in.
        var tangents: [String] = []
        for found in matches(#"\b([A-Z]{2,3})\s+and\s+([A-Z]{2,3})\s+are\s+(?:the\s+)?tangents"#) { tangents += [found[1], found[2]] }
        for found in matches(#"\b([A-Z]{2,3})\s+is\s+(?:a|the)\s+tangent"#) { tangents.append(found[1]) }
        // The letter the tangents share is the point outside that they both come from.
        for letter in Set(tangents.joined()) where point(letter) == nil {
            let others = tangents.filter { $0.contains(letter) }.flatMap { $0.filter { $0 != letter }.compactMap(point) }
            guard others.count >= 2 else { continue }
            let shared = diagram.points.indices.filter { candidate in
                diagram.points[candidate].place == .outside && diagram.points[candidate].name == nil
                    && others.allSatisfy { other in diagram.lines.contains { $0.points.contains(candidate) && $0.points.contains(other) } }
            }
            if shared.count == 1 { diagram.points[shared[0]].name = String(letter) }
        }
        for name in tangents {
            let on = name.compactMap(point)
            guard on.count == name.count, let touch = on.first(where: { diagram.points[$0].place == .onCircle }),
                  on.filter({ diagram.points[$0].place == .onCircle }).count == 1 else { continue }
            if let line = diagram.lines.firstIndex(where: { line in on.allSatisfy { line.points.contains($0) } }) {
                diagram.lines[line].tangentAt = touch
            } else if on.count == 2 {
                diagram.lines.append(.init(points: on, tangentAt: touch))
            }
        }
        // "diameter AC", "AC is a diameter": no centre is drawn, but it's on that line, halfway
        // along, and that's what makes the angle in a semicircle a right angle.
        for found in matches(#"(?i:diameter)\s+([A-Z]{2})\b"#) + matches(#"\b([A-Z]{2})\s+is\s+(?:a|the)\s+diameter"#) {
            let ends = found[1].compactMap(point)
            guard ends.count == 2, ends[0] != ends[1], ends.allSatisfy({ diagram.points[$0].place == .onCircle }),
                  !diagram.points.contains(where: { $0.place == .centre }),
                  let line = diagram.lines.firstIndex(where: { $0.points.contains(ends[0]) && $0.points.contains(ends[1]) }),
                  let first = diagram.lines[line].points.firstIndex(of: ends[0]), let second = diagram.lines[line].points.firstIndex(of: ends[1]),
                  abs(first - second) == 1 else { continue }
            let a = diagram.points[ends[0]], b = diagram.points[ends[1]]
            diagram.points.append(.init(name: nil, x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, place: .centre))
            diagram.lines[line].points.insert(diagram.points.count - 1, at: max(first, second))
        }
        // "BCD is a straight line": one line through all three, where the picture has it as two.
        for found in matches(#"\b([A-Z]{3})\s+is\s+a\s+straight\s+line"#) {
            let on = found[1].compactMap(point)
            guard on.count == 3, !diagram.lines.contains(where: { line in on.allSatisfy { line.points.contains($0) } }) else { continue }
            let halves = [0, 2].map { end in diagram.lines.firstIndex { $0.points.contains(on[1]) && $0.points.contains(on[end]) } }
            guard let first = halves[0], let second = halves[1], first != second else { continue }
            var whole = diagram.lines[first].points
            if whole.first == on[1] { whole.reverse() }
            var rest = diagram.lines[second].points
            if rest.last == on[1] { rest.reverse() }
            guard whole.last == on[1], rest.first == on[1] else { continue }
            diagram.lines[first].points = whole + rest.dropFirst()
            diagram.lines.remove(at: second)
        }
        // "BOD is a diameter": the end of it with no letter gets the one that's left.
        for found in matches(#"\b([A-Z]{3})\s+is\s+(?:a|the)\s+diameter"#) {
            let letters = found[1].map(String.init)
            guard let centre = point(Character(letters[1])), diagram.points[centre].place == .centre else { continue }
            for (known, missing) in [(letters[0], letters[2]), (letters[2], letters[0])] {
                guard let end = point(Character(known)), point(Character(missing)) == nil,
                      let line = diagram.lines.first(where: { $0.points.contains(centre) && $0.points.contains(end) }),
                      let here = line.points.firstIndex(of: centre), let there = line.points.firstIndex(of: end) else { continue }
                let beyond = there < here ? line.points[(here + 1)...] : line.points[..<here]
                if let other = beyond.first(where: { diagram.points[$0].place == .onCircle && diagram.points[$0].name == nil }) { diagram.points[other].name = missing }
            }
        }
        // "BOD is a diameter": one straight line through the middle, where the picture has
        // it as two lines that meet there.
        for found in matches(#"\b([A-Z]{3})\s+is\s+(?:a|the)\s+diameter"#) {
            let on = found[1].compactMap(point)
            guard on.count == 3, diagram.points[on[1]].place == .centre, !diagram.lines.contains(where: { line in on.allSatisfy { line.points.contains($0) } }) else { continue }
            let halves = [0, 2].map { end in diagram.lines.firstIndex { $0.points.contains(on[1]) && $0.points.contains(on[end]) } }
            guard let first = halves[0], let second = halves[1], first != second else { continue }
            var whole = diagram.lines[first].points
            if whole.first == on[1] { whole.reverse() }
            var rest = diagram.lines[second].points
            if rest.last == on[1] { rest.reverse() }
            guard whole.last == on[1], rest.first == on[1] else { continue }
            diagram.lines[first].points = whole + rest.dropFirst()
            diagram.lines.remove(at: second)
        }
        // "Angle ABD = 54°", "angle APB is 86°", "reflex angle AOC = 200°", "Angle BOD = x°".
        // (Not "Angle BCD = 2 × angle ABC": that's how two angles compare, not a size.)
        for found in matches(#"(?i:(reflex\s+)?angle)\s+([A-Z]{3})\s*(?:=|is)\s*(\d+(?:\.\d+)?|[a-z])\b(?!\s*(?:[×x*]|times|lots)\s*(?i:the |of )?(?i:angle|∠|size))"#) {
            guard let place = angle(found[2], reflex: !found[1].isEmpty) else { continue }
            let amount: CircleDiagram.Amount = Double(found[3]).map { .number($0) } ?? .letter(found[3])
            let mark = CircleDiagram.Mark(vertex: place.vertex, from: place.from, to: place.to, amount: amount)
            // The words are surer than a number read from the picture.
            if let index = diagram.marks.firstIndex(where: { $0.vertex == mark.vertex && $0.from == mark.from && $0.to == mark.to }) {
                if amount.isNumber || !diagram.marks[index].amount.isNumber { diagram.marks[index] = mark }
            } else {
                diagram.marks.append(mark)
            }
        }
        if !diagram.asked.isEmpty || diagram.marks.count > 0 { diagram.hasWords = diagram.hasWords || !matches(#"(?i:angle)\s+[A-Z]{3}\s*(?:=|is)|(?i:diameter|tangent|straight line|isosceles)"#).isEmpty }
        // "BC = CD".
        for found in matches(#"\b([A-Z]{2})\s*=\s*([A-Z]{2})\b"#) {
            let first = found[1].compactMap(point), second = found[2].compactMap(point)
            if first.count == 2, second.count == 2 { diagram.equal.append(.init(first: first, second: second)) }
        }
        /// A line between two points that the words speak of and the picture doesn't draw.
        func join(_ a: Int, _ b: Int) {
            if !diagram.lines.contains(where: { $0.points.contains(a) && $0.points.contains(b) }) { diagram.lines.append(.init(points: [a, b], tangentAt: nil)) }
        }
        // "AB = 8.7 cm": a length the words give.
        for found in matches(#"\b([A-Z])([A-Z])\s*(?:=|is)\s*(\d+(?:\.\d+)?)\s*(mm|cm|km|m|miles)\b"#) {
            guard let a = found[1].first.flatMap(point), let b = found[2].first.flatMap(point), a != b, let size = Double(found[3]), size > 0 else { continue }
            if !diagram.lengths.contains(where: { Set([$0.a, $0.b]) == Set([a, b]) }) { diagram.lengths.append(.init(a: a, b: b, amount: .number(size))) }
            if diagram.unit == nil { diagram.unit = found[4] }
            join(a, b)
            diagram.hasWords = true
        }
        // "x is an acute angle", "angle y is obtuse": which of the two angles a sine could be.
        for found in matches(#"\b([a-zθ])\s+is\s+(?:an?\s+)?(acute|obtuse)"#) { diagram.acute[found[1]] = found[2] == "acute" }
        // "the length of AC", "the distance from P to R": a length to find.
        let lengths = matches(#"(?i:length)\s+(?:of\s+)?(?:(?i:the\s+)?(?i:line|side)\s+)?([A-Z])([A-Z])\b"#)
            + matches(#"(?i:distance)[^.?]{0,40}?(?i:from|between)\s+([A-Z])\s+(?i:to|and)\s+([A-Z])\b"#)
        for found in lengths {
            guard let a = found[1].first.flatMap(point), let b = found[2].first.flatMap(point), a != b else { continue }
            let name = String((found[1] + found[2]).sorted())
            guard !diagram.askedLengths.contains(where: { $0.name == name }) else { continue }
            join(a, b)
            diagram.askedLengths.append(.init(a: a, b: b, name: name))
        }
        // "Work out the area of triangle ABC": the three points, or the figure's only triangle.
        for found in matches(#"(?i:area)\s+of\s+(?:(?i:the|this)\s+)?(?i:triangle)(?:\s+([A-Z]{3})\b)?"#) {
            var corners = found[1].compactMap(point)
            if corners.count != 3, diagram.points.count == 3 { corners = Array(diagram.points.indices) }
            if corners.count == 3, Set(corners).count == 3, !diagram.askedAreas.contains(corners) { diagram.askedAreas.append(corners) }
        }
        // "Work out the size of angle DOA", "Find the size of angle ACD".
        for found in matches(#"(?i:find|work out|calculate|write down|show that|prove that)[^.?]{0,60}?(?<![A-Za-z])(?i:(reflex\s+)?angle)\s+([A-Z]{3})\b"#) {
            guard let place = angle(found[2], reflex: !found[1].isEmpty), !diagram.asked.contains(where: { $0.name.hasSuffix(found[2]) }) else { continue }
            diagram.asked.append(.init(vertex: place.vertex, from: place.from, to: place.to, name: (found[1].isEmpty ? "∠" : "reflex ∠") + found[2]))
        }
    }

    /// The answers from a diagram that are what the question's words ask for. Where the words
    /// ask for a letter the diagram's working didn't reach, or for a kind of thing none of
    /// its answers is (an area, a radius, a bearing, who gets there first), showing the angles
    /// and sides it did find would be answering another question: nothing is shown.
    static func wanted(_ words: String, among solutions: [Solution]) -> [Solution] {
        let lower = words.lowercased()
        func found(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { return nil }
            return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: lower).map { String(lower[$0]) } ?? "" }
        }
        func cased(_ pattern: String) -> Bool { words.range(of: pattern, options: .regularExpression) != nil }
        // "Work out the value of y", "the size of the angle marked x", "the length x". (Not
        // the a of "find a reason" or "the length of a side".)
        // (Asked for, not stated: "Angle B = 90°" isn't asking for b.)
        let asking = #"(?:work out|find|calculate|write down)\b[^.?=]{0,40}?"#
        // (And "Find x for each of the triangles below".)
        let letters = [#"value of ([a-z])\b"#, asking + #"(?<![a-z])angle (?:marked )?([a-z])\b(?![a-z]| ?=)"#,
                       asking + #"length (?:of )?(?:the side )?(?:marked )?([b-z])\b(?![a-z]| ?=)"#, #"(?:work out|find|calculate) ([b-z])(?:\s*[.?]|\s+(?:for|in|on)\b)"#,
                       asking + #"\bside,? ([b-z])\b(?![a-z]| ?=)"#]
        var asked = Set(letters.compactMap { found($0)?[1] })
        // "Find the size of θ", "the missing angle θ or side, x" (a theta is often read as 0 or O).
        if found(#"(?:size of|(?<![a-z])angle|values? (?:of|for)(?: the angle)?) (?:θ|0|o)\b(?! ?=)"#) != nil { asked.insert("θ") }
        if !asked.isEmpty {
            func isLetter(_ solution: Solution) -> Bool { solution.problem.text.count == 1 && solution.problem.text.first?.isLetter == true }
            var places = solutions.indices.filter { asked.contains(solutions[$0].problem.text) }
            // (And on the drawing a theta may have been read as some other letter: the only letter there is.)
            if places.isEmpty, asked.contains("θ"), solutions.filter(isLetter).count == 1 {
                places = solutions.indices.filter { isLetter(solutions[$0]) && solutions[$0].answers.first?.suffix == "°" }
            }
            guard !places.isEmpty else { return [] }
            return places.map { solutions[$0] } + solutions.enumerated().filter { !places.contains($0.offset) }.map(\.element)
        }
        // "How many students walk to school?" wants a count: an angle or a length of the drawing isn't one.
        if found(#"\bhow many\b(?! degrees| times (?:longer|bigger|larger))"#) != nil, !solutions.contains(where: { $0.answers.first?.suffix == nil }) { return [] }
        // A bound of a measurement isn't worked out from the drawing as it stands.
        if found(#"\b(?:upper|lower) bound\b|\berror interval\b"#) != nil { return [] }
        // "Work out the size of angle CDE", "Calculate the length of QS": the angle or length
        // named. One the working never reached isn't answered by the ones it did.
        func named(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)),
                  let range = Range(match.range(at: 1), in: words) else { return nil }
            return String(words[range])
        }
        func first(_ names: [String]) -> [Solution] {
            guard let place = solutions.firstIndex(where: { names.contains($0.problem.text.replacingOccurrences(of: "reflex ", with: "")) }) else { return [] }
            return [solutions[place]] + solutions.enumerated().filter { $0.offset != place }.map(\.element)
        }
        let verb = #"(?i:work out|find|calculate|write down)\b[^.?=]{0,60}?"#
        if let angle = named(verb + #"(?<![A-Za-z])(?i:angle)\s+([A-Z]{3})\b(?!\s*(?:=|is\b))"#) {
            return first(["∠" + angle, "∠" + String(angle.reversed())])
        }
        if let length = named(verb + #"(?i:length|distance)\s+(?:of\s+)?(?:(?i:the\s+)?(?i:side|line)\s+)?([A-Z]{2})\b(?!\s*(?:=|is\b)|[A-Za-z])"#)
            ?? named(#"(?i:work out|find|calculate)\s+([A-Z]{2})\s*[.?]"#) {
            return first([length, String(length.reversed())])
        }
        for kind in ["area", "perimeter", "volume", "radius", "diameter", "circumference", "bearing"] {
            guard found("(?:work out|find|calculate|what is|estimate)\\b[^.?]{0,60}\\b\(kind)\\b") != nil else { continue }
            guard let place = solutions.firstIndex(where: { $0.problem.text.lowercased().hasPrefix(kind) }) else { return [] }
            return [solutions[place]] + solutions.enumerated().filter { $0.offset != place }.map(\.element)
        }
        // "Who arrives first?", "Is she correct? Tick a box." (Not "PQR is a right-angled triangle".)
        if cased(#"\b[Ww]ho\b|\b[Tt]ick\b|\b[Ii]s (?:he|she|it|this|[A-Z][a-z]+) (?:correct|right)\b(?!-)"#) { return [] }
        return solutions
    }

    /// What a question's words add to its triangle: the letter of a corner that wasn't
    /// read, lengths and angles given in words, and the length or angle asked for.
    static func apply(_ words: String, to triangle: inout TriangleDiagram) {
        let alike: [Character: Character] = ["А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T", "Х": "X", "У": "Y"]
        let text = String(words.replacingOccurrences(of: "∠", with: "angle ").replacingOccurrences(of: "\n", with: " ").map { alike[$0] ?? $0 })
        func matches(_ pattern: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
                (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            }
        }
        // "PQR is a right-angled triangle", "triangle ABC": the corner with no letter gets the one that's left.
        for found in matches(#"\b([A-Z]{3})\s+is\s+an?\s+(?:[a-z-]+\s+)*triangle"#) + matches(#"(?i:triangle)\s+([A-Z]{3})\b"#) {
            let letters = found[1].map(String.init)
            let missing = letters.filter { letter in !triangle.corners.contains { $0.name == letter } }
            let unnamed = triangle.corners.indices.filter { triangle.corners[$0].name == nil }
            if missing.count == 1, unnamed.count == 1 { triangle.corners[unnamed[0]].name = missing[0] }
        }
        func corner(_ letter: Character) -> Int? { triangle.corners.firstIndex { $0.name == String(letter) } }
        /// The side between two corners is the one opposite the third.
        func side(_ name: String) -> Int? {
            let ends = name.compactMap(corner)
            guard ends.count == 2, ends[0] != ends[1] else { return nil }
            return (0..<3).first { !ends.contains($0) }
        }
        func angleName(_ index: Int) -> String? {
            let others = (0..<3).filter { $0 != index }.compactMap { triangle.corners[$0].name }.sorted()
            guard others.count == 2, let name = triangle.corners[index].name else { return nil }
            return "∠" + others[0] + name + others[1]
        }
        // "AB = 8.7 cm".
        for found in matches(#"\b([A-Z]{2})\s*=\s*(\d+(?:\.\d+)?)\s*(cm|mm|km|m)?\b"#) {
            guard let index = side(found[1]), let length = Double(found[2]) else { continue }
            triangle.sides[index] = .number(length)
            if !found[3].isEmpty, triangle.unit == nil { triangle.unit = found[3] }
        }
        // "Angle A = 36", "Angle PRQ = 90°".
        for found in matches(#"(?i:angle)\s+([A-Z]|[A-Z]{3})\s*(?:=|is)\s*(\d+(?:\.\d+)?)\b(?!\s*(?:[×x*]|times|lots)\s*(?i:the |of )?(?i:angle|∠|size))"#) {
            let letters = Array(found[1])
            guard let index = corner(letters.count == 3 ? letters[1] : letters[0]), let size = Double(found[2]), size > 0, size < 180 else { continue }
            triangle.corners[index].angle = .number(size)
        }
        // "Work out the area of triangle ABC."
        if !matches(#"(?i:area)\s+of\s+(?:(?i:the|this)\s+)?(?i:triangle)"#).isEmpty { triangle.asked.append("Area") }
        // "The triangles have two possible values for the angle θ. Find both."
        if !matches(#"(?i:two possible|both possible|the possible (?:values|sizes|angles)|two different (?:values|sizes))"#).isEmpty { triangle.asked.append("Both") }
        // "Calculate the length of QR", "Work out the size of angle PQR".
        for found in matches(#"(?i:find|work out|calculate)[^.?]{0,50}?(?i:length\s+of(?:\s+the\s+side)?|side)\s+([A-Z]{2})\b"#) {
            if side(found[1]) != nil { triangle.asked.append(String(found[1].sorted())) }
        }
        for found in matches(#"(?i:find|work out|calculate)[^.?]{0,50}?(?<![A-Za-z])(?i:angle)\s+([A-Z]{3})\b"#) {
            if let index = corner(Array(found[1])[1]), let name = angleName(index) { triangle.asked.append(name) }
        }
        for found in matches(#"(?i:find|work out|calculate)[^.?]{0,50}?(?i:marked|value\s+of|size\s+of)\s+([a-z])\b"#) {
            triangle.asked.append(found[1])
        }
    }
}
