import Foundation

/// Shapes and measures asked in words: area, perimeter, volume and surface area of named shapes, arcs and sectors, similar shapes, and speed, density and pressure where a shape is part of it.
/// Tried after `Worded.problem`, on the same text: the lines of the question the pointer is
/// in, joined by line breaks. Nil unless the whole of the question is understood.
enum WordedMensuration {
    static func problem(_ input: String) -> Problem? {
        let display = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = plain(display)
        guard !text.isEmpty, text.count <= 1500, !has(#"\bprove\b|\bexplain\b|\bdraw\b|\bsketch\b|\bconstruct\b"#, text) else { return nil }
        // "Tick a box" is left alone, but for a yes or no that is worked out: only the kinds that give one are tried.
        if has(#"\btick\b"#, text) {
            guard has(#"\btick (?:a|one) box\b"#, text), has(#"\byes\b"#, text), has(#"\bno\b"#, text), var problem = mapScale(text) else { return nil }
            problem.text = display
            return problem
        }
        let kinds: [(String) -> Problem?] = [rectangle, prism, sameVolume, sectorAngle, prismSurface, partVolume, ring, laps, pressureBounds, sectorShare,
                                               unitArea, rectanglesChanged, semicircleArc, shadedInside, triangularPrism, pressureRatio, coneAndHemisphere, rightTriangleRatio, similarTimes,
                                               similarNamed, namedRectangles, coneOnHemisphere, areaPerPerson, pressureFace, twoSectors, bearings, twoElevations, twoShips, sailsFrom, equalSolids, scaledSolid, cuboidDiagonal,
                                               densityEstimate, massDensityVolume, mixture, circleFacts, quarterCircle, pyramid, similarSolids, oneUnknownSolid, cubeOnCuboid,
                                               similarThree, populationDensity, trackSpeed, paintCylinders, fillTime, pressureOfCylinder, frustumSurface,
                                               polygonFromAngles, similarPrice, greaterArea, similarIsosceles, cuboidFromVolumeAndSurface, sectorFromArc,
                                               invariantVertices, scaleDrawingArea, scaleCylinder, fliesTowards,
                                               polygonsAtPoint, similarSmallLarge, similarRatio, whatHappens, invariantOnEdge, mapScale,
                                               prismEdgeRatio, twoCones, greaterVolume]
        for kind in kinds {
            if var problem = kind(text) {
                problem.text = display
                return problem
            }
        }
        return nil
    }

    // MARK: Reading

    /// The question on one line, with the margin note, the question's number, the marks and the
    /// answer line taken out, and the letters and signs that are misread made plain.
    private static func plain(_ display: String) -> String {
        var raw = display
        for (from, to) in [("–", "-"), ("−", "-"), ("—", "-"), ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\t", " "), ("\u{FFFC}", " "),
                           ("’", "'"), ("“", "\""), ("”", "\""), ("²", "^2"), ("³", "^3"), ("⩽", "≤"), ("⩾", "≥")] {
            raw = raw.replacingOccurrences(of: from, with: to)
        }
        // Letters from other alphabets read for ones that look the same: Cyrillic с and т in "ст".
        let alike: [Character: Character] = ["а": "a", "А": "A", "В": "B", "в": "b", "С": "C", "с": "c", "Е": "E", "е": "e", "Н": "H", "К": "K", "к": "k", "М": "M",
                                              "О": "O", "о": "o", "Р": "P", "р": "p", "Т": "T", "т": "m", "Х": "X", "х": "x", "У": "Y", "у": "y", "з": "3", "З": "3"]
        raw = String(raw.map { alike[$0] ?? $0 })
        // A capital letter run into "is": "Bis 6 km due South", "Vis vertically above".
        raw = raw.replacingOccurrences(of: #"\b([A-Z])is\b"#, with: "$1 is", options: .regularExpression)
        var lines: [String] = []
        for piece in raw.components(separatedBy: "\n") {
            var line = piece.trimmingCharacters(in: .whitespaces)
            if line.range(of: #"^(?:do not(?: write)?(?: v)?|outside(?: the)?(?: box)?|the box|box|bo[:s]?|write|not drawn|accurately|answer\b.*)$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            line = line.replacingOccurrences(of: #"^\d{1,2}\s*(?:\([a-z]\)\s*)?(?=[A-Z])"#, with: "", options: .regularExpression)
            if line.range(of: #"^\d{1,2}(?: ?\([a-z]\))?$"#, options: .regularExpression) != nil { continue }
            line = line.replacingOccurrences(of: #"[\[I1]\d+ marks?[\]l1|]*!?"#, with: "", options: [.regularExpression, .caseInsensitive])
            line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { lines.append(line) }
        }
        return lines.joined(separator: " ")
    }

    private static let number = #"\d+(?:\.\d+)?"#

    /// The numbers in the text, leaving out powers (cm^3) and digits stuck to letters.
    private static func numbers(_ text: String) -> [Double] {
        // (A lone 0 is a centre O misread, never a size given.)
        every(#"(?<![\d.^A-Za-z])\d+(?:\.\d+)?"#, in: text).compactMap { Double($0[0]) }.filter { $0 != 0 }
    }

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func every(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    private static let counts = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "half": 0]

    private static func count(_ word: String) -> Double? { Double(word) ?? counts[word.lowercased()].map(Double.init) }

    /// A number as it is written: whole where it is, otherwise a decimal with no rounding noise.
    private static func shown(_ value: Double) -> String {
        let tidy = Double(String(format: "%.10g", value)) ?? value
        if abs(tidy - tidy.rounded()) < 1e-9, abs(tidy) < 1e15 { return String(Int(tidy.rounded())) }
        return String(format: "%.10g", tidy)
    }

    private static func amount(_ value: Double) -> Expr { CircleDiagram.number(value) }

    private static func maths(_ text: String) -> Expr? { Parser.expression(text) }

    private static func sum(_ expr: Expr, decimals: Bool, _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .evaluate(expr), text: "", usesDecimals: decimals)
        problem.lead = lead
        return problem
    }

    private static func told(_ question: String, _ answers: [MathLine], _ lead: [Step]) -> Problem {
        var problem = Problem(kind: .worded(question: question, answers: answers), text: "", usesDecimals: false)
        problem.lead = lead
        return problem
    }

    private static func rounded(_ value: Double, significant places: Int) -> Double {
        guard value != 0 else { return 0 }
        let scale = pow(10, Double(places) - 1 - floor(log10(abs(value))))
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    /// The units of length, by how many millimetres each is.
    private static func millimetres(_ unit: String) -> Double? {
        switch unit.lowercased() {
        case "mm", "millimetre", "millimetres": 1
        case "cm", "centimetre", "centimetres": 10
        case "m", "metre", "metres": 1000
        case "km", "kilometre", "kilometres": 1_000_000
        default: nil
        }
    }

    /// A unit of length as it is written short: "metres" as m.
    private static func short(_ unit: String) -> String {
        switch millimetres(unit) {
        case 1: "mm"
        case 10: "cm"
        case 1000: "m"
        case 1_000_000: "km"
        default: unit
        }
    }

    private static let lengthUnit = #"(mm|cm|km|m|millimetres?|centimetres?|kilometres?|metres?)"#

    // MARK: A rectangle whose length is a number of times its width

    /// "The length of a rectangle is five times the width. The area of the rectangle is 1620 cm².
    /// Work out the width of the rectangle."
    private static func rectangle(_ text: String) -> Problem? {
        guard let told = groups(#"\b(length|width) of (?:a|the|this) rectangle is (\w+) times (?:the|its) (width|length)\b"#, in: text),
              told[1].lowercased() != told[3].lowercased(), let times = count(told[2]), times > 0,
              let area = groups(#"\barea of (?:the|this|a) rectangle is (\#(number)) ?(mm|cm|m|km)\^?2"#, in: text),
              let size = Double(area[1]), size > 0,
              let asked = groups(#"\b(?:work out|find|calculate|what is) the (width|length|perimeter) of the rectangle\b"#, in: text)?[1].lowercased(),
              // Nothing else to use: one area, and no other numbers.
              numbers(text).count == 1 + (Double(told[2]) == nil ? 0 : 1) else { return nil }
        let unit = area[2], short = told[3].lowercased(), long = told[1].lowercased()
        let k = shown(times)
        let lead = [
            Step("Call the \(short) w", "The \(long) is \(k) times the \(short), so it is \(k)w.", [MathLine(.symbol(long), .symbol("\(k)w"))]),
            Step("Area is length × width", "", [MathLine(.symbol("w × \(k)w"), .symbol("\(k)w²"), amount(size))]),
            Step("Find w", "Divide by \(k), then take the square root.", [MathLine(.symbol("w²"), amount(size / times))]),
        ]
        let w = (size / times).squareRoot()
        guard w.isFinite else { return nil }
        let root = Expr.power(amount(size / times), .power(.integer(2), .minusOne))
        switch asked {
        case short: return sum(root, decimals: abs(w - w.rounded()) > 1e-9, lead)
        case long: return sum(.multiply([amount(times), root]), decimals: abs(w * times - (w * times).rounded()) > 1e-9,
                              lead + [Step("The \(long)", "\(k) times the \(short): \(k) × w, in \(unit).")])
        default: return sum(.multiply([.integer(2), .add([amount(times), .integer(1)]), root]), decimals: abs(w - w.rounded()) > 1e-9,
                            lead + [Step("The perimeter", "Twice the \(long) and twice the \(short): 2 × (\(k)w + w), in \(unit).")])
        }
    }

    // MARK: Volume of a prism

    /// "The prism has volume = 3500 cm³ and length = 20 cm. Work out the area of the cross-section of the prism."
    private static func prism(_ text: String) -> Problem? {
        guard has(#"\bprism\b"#, text) else { return nil }
        let volume = groups(#"\bvolume(?: of the prism)?(?: is| =|=| of)? ?(\#(number)) ?(mm|cm|m)\^?3"#, in: text)
        let length = groups(#"\blength(?: of the prism)?(?: is| =|=| of)? ?(\#(number)) ?(mm|cm|m)\b(?!\^)"#, in: text)
        let area = groups(#"\b(?:area of the )?cross[- ]?section(?:al area)?(?: has area| is| =|=| of)? ?(\#(number)) ?(mm|cm|m)\^?2"#, in: text)
        let ask = #"\b(?:work out|find|calculate|what is) the "#
        if let volume, let length, area == nil, has(ask + #"(?:area of the cross[- ]?section|cross[- ]?sectional area)"#, text),
           volume[2].lowercased() == length[2].lowercased(), let v = Double(volume[1]), let l = Double(length[1]), l > 0, numbers(text).count == 2 {
            return sum(.multiply([amount(v), .power(amount(l), .minusOne)]), decimals: (v / l).rounded() != v / l,
                       [Step("Volume of a prism", "The area of the cross-section times the length. So the area is the volume divided by the length, in \(volume[2])².",
                             [MathLine(.symbol("area"), .symbol("\(volume[1]) ÷ \(length[1])"))])])
        }
        if let volume, let area, length == nil, has(ask + #"length\b"#, text),
           volume[2].lowercased() == area[2].lowercased(), let v = Double(volume[1]), let a = Double(area[1]), a > 0, numbers(text).count == 2 {
            return sum(.multiply([amount(v), .power(amount(a), .minusOne)]), decimals: (v / a).rounded() != v / a,
                       [Step("Volume of a prism", "The area of the cross-section times the length. So the length is the volume divided by the area, in \(volume[2]).",
                             [MathLine(.symbol("length"), .symbol("\(volume[1]) ÷ \(area[1])"))])])
        }
        if let length, let area, volume == nil, has(ask + #"volume\b"#, text),
           length[2].lowercased() == area[2].lowercased(), let l = Double(length[1]), let a = Double(area[1]), numbers(text).count == 2 {
            return sum(.multiply([amount(a), amount(l)]), decimals: (a * l).rounded() != a * l,
                       [Step("Volume of a prism", "The area of the cross-section times the length, in \(length[2])³.",
                             [MathLine(.symbol("volume"), .symbol("\(area[1]) × \(length[1])"))])])
        }
        return nil
    }

    // MARK: Two solids with the same volume

    private struct Solid {
        var name: String
        /// Radius (or side) as a number of x.
        var radius: Int
        /// Height as a number of x, or nil when it is the unknown h.
        var height: Int?
        var hasHeight: Bool
    }

    /// Volume as a fraction of π times x³ (or x²h): sphere 4/3, hemisphere 2/3, cone 1/3, cylinder 1.
    private static func share(_ name: String) -> (top: Int, bottom: Int, formula: String)? {
        switch name.lowercased() {
        case "sphere": (4, 3, "4/3 × π × r³")
        case "hemisphere": (2, 3, "2/3 × π × r³")
        case "cone": (1, 3, "1/3 × π × r² × h")
        case "cylinder": (1, 1, "π × r² × h")
        default: nil
        }
    }

    /// "A sphere has radius 2x cm. A cone has radius 3x cm, perpendicular height h cm. The sphere and
    /// the cone have the same volume. Work out radius of cone : perpendicular height of cone."
    private static func sameVolume(_ text: String) -> Problem? {
        guard has(#"\bsame volume\b|\bvolumes? (?:are|is) (?:the same|equal)\b"#, text) else { return nil }
        let names = #"(sphere|hemisphere|cone|cylinder)"#
        var solids: [Solid] = []
        for found in every(#"\b(?:a|the) \#(names) has (?:a )?radius (\d*) ?x ?(?:mm|cm|m)?\b"#, in: text) {
            let radius = found[2].isEmpty ? 1 : Int(found[2]) ?? 0
            guard radius > 0, !solids.contains(where: { $0.name == found[1].lowercased() }) else { return nil }
            solids.append(Solid(name: found[1].lowercased(), radius: radius, height: nil, hasHeight: ["cone", "cylinder"].contains(found[1].lowercased())))
        }
        // "A cone has radius 3x cm perpendicular height h cm": the radius comes after "has".
        for found in every(#"\b(?:a|the) \#(names) has (?!(?:a )?radius)[^.]*?\bradius (\d*) ?x ?(?:mm|cm|m)?\b"#, in: text) {
            let radius = found[2].isEmpty ? 1 : Int(found[2]) ?? 0
            guard radius > 0, !solids.contains(where: { $0.name == found[1].lowercased() }) else { continue }
            solids.append(Solid(name: found[1].lowercased(), radius: radius, height: nil, hasHeight: ["cone", "cylinder"].contains(found[1].lowercased())))
        }
        guard solids.count == 2 else { return nil }
        // The one height given as a letter is the unknown; one given as a number of x is known.
        let heights = every(#"\bheight (?:is |of )?(\d*) ?((?-i:[a-z]))(?![A-Za-z])"#, in: text)
        guard heights.count == solids.filter(\.hasHeight).count, heights.count >= 1 else { return nil }
        var unknown: String?
        var index = 0
        for (place, solid) in solids.enumerated() where solid.hasHeight {
            let found = heights[index]
            index += 1
            if found[2] == "x" { solids[place].height = found[1].isEmpty ? 1 : Int(found[1]) } else if found[1].isEmpty { unknown = found[2] } else { return nil }
        }
        guard let h = unknown, solids.filter({ $0.hasHeight && $0.height == nil }).count == 1,
              let which = solids.firstIndex(where: { $0.hasHeight && $0.height == nil }) else { return nil }
        let other = solids[1 - which], open = solids[which]
        guard let a = share(other.name), let b = share(open.name) else { return nil }
        // Every number in the question is a radius or a height (or the a : b of the form asked for).
        let used = solids.count + (other.height == nil ? 0 : 1)
        let written = every(#"(?<![a-z^])\d+(?=\s?x\b)"#, in: text).count
        guard written <= used else { return nil }
        // The known solid's volume as (p/q)πx³, the other's as (s/t)π(rx)²h.
        let knownTop = a.top * other.radius * other.radius * (other.hasHeight ? (other.height ?? 0) : other.radius)
        let knownBottom = a.bottom
        guard knownTop > 0 else { return nil }
        let openTop = b.top * open.radius * open.radius, openBottom = b.bottom
        // h = (knownTop/knownBottom) ÷ (openTop/openBottom) × x
        var top = knownTop * openBottom, bottom = knownBottom * openTop
        let common = gcd(top, bottom)
        top /= common; bottom /= common
        let hText = bottom == 1 ? "\(top)x" : "\(top)x/\(bottom)"
        func volume(_ solid: Solid, _ part: (top: Int, bottom: Int, formula: String)) -> String {
            let r = solid.radius == 1 ? "x" : "\(solid.radius)x"
            let height = solid.hasHeight ? (solid.height.map { $0 == 1 ? "x" : "\($0)x" } ?? h) : nil
            let coefficient = part.top * solid.radius * solid.radius * (solid.hasHeight ? (solid.height ?? 1) : solid.radius)
            let front: String = {
                let g = gcd(coefficient, part.bottom)
                return part.bottom / g == 1 ? "\(coefficient / g)" : "\(coefficient / g)/\(part.bottom / g)"
            }()
            let rest = solid.hasHeight ? (solid.height == nil ? "x²\(h)" : "x³") : "x³"
            let filled = part.formula.replacingOccurrences(of: "r", with: "(\(r))").replacingOccurrences(of: "h", with: height ?? "")
            return "\(filled) = \(front)πx\(rest.dropFirst())".replacingOccurrences(of: "πxx", with: "πx")
        }
        var lead = [
            Step("Volume of the \(other.name)", other.name.capitalized + ": " + a.formula + ".", [MathLine(.symbol(volume(other, a)))]),
            Step("Volume of the \(open.name)", open.name.capitalized + ": " + b.formula + ".", [MathLine(.symbol(volume(open, b)))]),
            Step("Make them equal and find \(h)", "Divide both sides by π and by x².", [MathLine(.symbol(h), .symbol(hText))]),
        ]
        let r = open.radius == 1 ? "x" : "\(open.radius)x"
        // What's asked: a ratio of the radius and the height, or the height itself.
        if let ratio = groups(#"\b(radius|height|perpendicular height) of (?:the )?(?:cone|cylinder) ?: ?(radius|height|perpendicular height) of (?:the )?(?:cone|cylinder)\b"#, in: text) {
            let radiusFirst = ratio[1].lowercased() == "radius"
            guard radiusFirst != (ratio[2].lowercased() == "radius") else { return nil }
            // r : h = (radius)x : (top/bottom)x = radius·bottom : top
            var left = open.radius * bottom, right = top
            let g = gcd(left, right)
            left /= g; right /= g
            if !radiusFirst { swap(&left, &right) }
            lead.append(Step("Write the ratio", "Both have x in them, so it cancels. Multiply by \(bottom) to clear the fraction, then simplify.",
                             [MathLine(.symbol(radiusFirst ? "\(r) : \(hText)" : "\(hText) : \(r)"), .symbol("\(left) : \(right)"))]))
            return Self.told("\(ratio[1].lowercased()) : \(ratio[2].lowercased())", [MathLine(.symbol("\(left) : \(right)"))], lead)
        }
        if has(#"\b(?:work out|find|write|express)\b[^.]*?\b(?:\#(h)|(?:perpendicular )?height)\b[^.]*?\bin terms of x\b"#, text) {
            return Self.told(h, [MathLine(.symbol(h), .symbol(hText))], Array(lead.dropLast()) + [Step("Make them equal and find \(h)", "Divide both sides by π and by x².")])
        }
        return nil
    }

    // MARK: A circle and a sector

    /// "Here are a circle and a sector of the circle. They each have radius r.
    /// circumference of circle = perimeter of sector. Work out the size of angle x. Give your answer in terms of π"
    private static func sectorAngle(_ text: String) -> Problem? {
        guard has(#"\bcircle and a sector\b|\bsector and a circle\b"#, text), has(#"\b(?:each|both) have (?:a )?radius ([a-z])\b|\bsame radius\b"#, text),
              has(#"\bcircumference of (?:the )?circle ?= ?(?:the )?perimeter of (?:the )?sector\b|\bperimeter of (?:the )?sector ?= ?(?:the )?circumference of (?:the )?circle\b"#, text),
              let angle = groups(#"\b(?:work out|find|calculate) the (?:size of )?angle ([a-z])\b"#, in: text)?[1],
              has(#"\bin terms of\b"#, text), !has(#"\d"#, text) else { return nil }
        let r = groups(#"\bradius ([a-z])\b"#, in: text)?[1] ?? "r"
        guard let answer = maths("360-360/π") else { return nil }
        let lead = [
            Step("Circumference of the circle", "2 × π × radius.", [MathLine(.symbol("2π\(r)"))]),
            Step("Perimeter of the sector", "Two radii and the arc. The arc is \(angle)/360 of the circumference.", [MathLine(.symbol("2\(r) + \(angle)/360 × 2π\(r)"))]),
            Step("Make them equal", "Divide every part by 2\(r).", [MathLine(.symbol("π"), .symbol("1 + \(angle)π/360"))]),
            Step("Find \(angle)", "Take 1 from both sides, multiply by 360 and divide by π.", [MathLine(.symbol(angle), .symbol("360(π − 1)/π"))]),
        ]
        return told("angle \(angle)", [MathLine(.symbol(angle), answer, suffix: "°")], lead)
    }

    // MARK: Surface area of a prism, kept under a limit

    private static let polygons: [String: Int] = ["triangle": 3, "square": 4, "pentagon": 5, "hexagon": 6, "heptagon": 7, "octagon": 8, "nonagon": 9, "decagon": 10]

    /// "The cross section is a regular hexagon with side x. The length is 5x. The area of the cross
    /// section is (3√3)/2 x². The total surface area must be less than 650 cm². Work out the largest possible integer value of x."
    private static func prismSurface(_ text: String) -> Problem? {
        guard let shape = groups(#"\bcross[- ]?section(?: of (?:a|the) [a-z]+)? is (?:a|an) (?:regular|equilateral) (triangle|square|pentagon|hexagon|heptagon|octagon|nonagon|decagon) with sides? (?:of length )?([a-z])\b"#, in: text),
              let sides = polygons[shape[1].lowercased()] else { return nil }
        let x = shape[2]
        guard let long = groups(#"\blength (?:of the (?:prism|box) )?is (\d*) ?\#(x)\b"#, in: text), let limit = groups(#"\bsurface area\b[^.]*?\b(less than|under|below|at most|no more than) (\#(number)) ?(?:mm|cm|m)\^?2"#, in: text),
              let most = Double(limit[2]), has(#"\b(?:largest|greatest|biggest|maximum) (?:possible )?(?:integer|whole number) (?:value )?(?:of|for) \#(x)\b"#, text) else { return nil }
        let length = long[1].isEmpty ? 1 : Double(long[1]) ?? 0
        guard length > 0 else { return nil }
        // The area of the cross-section as a number times x², given or, for a square, side².
        var front: Expr
        var frontText: String
        if let given = groups(#"\bcross[- ]?section\b[^.]*? is (.{1,24}?) ?\#(x)\^2"#, in: text), let expr = maths(given[1].replacingOccurrences(of: " ", with: "")),
           let size = expr.evaluate(), size > 0 {
            front = expr
            frontText = given[1].replacingOccurrences(of: " ", with: "")
        } else if sides == 4 {
            front = .integer(1)
            frontText = ""
        } else {
            return nil
        }
        guard let c = front.evaluate() else { return nil }
        // Every number: the length's, the limit, and those in the given area.
        let total = 2 * c + Double(sides) * length
        let bound = (most / total).squareRoot()
        let strict = !has(#"\bat most\b|\bno more than\b"#, limit[1])
        var largest = floor(bound)
        if strict, abs(largest - bound) < 1e-9 { largest -= 1 }
        guard largest >= 1 else { return nil }
        let L = shown(length)
        let lead = [
            Step("The two ends", "Two cross-sections, each \(frontText.isEmpty ? "" : frontText + " ")\(x)².", [MathLine(.symbol("2 × \(frontText.isEmpty ? "" : frontText)\(x)²"))]),
            Step("The sides", "\(sides) rectangles, each \(x) by \(L == "1" ? "" : L)\(x).", [MathLine(.symbol("\(sides) × \(x) × \(L == "1" ? "" : L)\(x)"), .symbol("\(shown(Double(sides) * length))\(x)²"))]),
            Step("Total surface area", "Add them, and keep it \(limit[1].lowercased()) \(limit[2]).",
                 [MathLine(.symbol("\(shown((total * 10000).rounded() / 10000))…\(x)²"), .symbol(limit[2]), relation: strict ? "<" : "≤")]),
            Step("Find \(x)", "Divide by \(shown((total * 10000).rounded() / 10000)) and take the square root.",
                 [MathLine(.symbol(x), amount(bound), relation: strict ? "<" : "≤")]),
            Step("The largest whole number", "The largest integer that fits.", []),
        ]
        return told("largest integer \(x)", [MathLine(.symbol(x), .integer(Int(largest)))], lead)
    }

    // MARK: Mass, density and a part's volume

    /// "The trophy is made from a metal of density 7.5 grams per cm³. The total mass of the trophy is 2340 grams.
    /// [The volume of the stand is 258 cm³.] Work out the volume of the player."
    private static func partVolume(_ text: String) -> Problem? {
        guard let density = groups(#"\bdensity (?:of )?(\#(number)) ?(g|grams?|kg|kilograms?)(?: per |/)(mm|cm|m)\^?3"#, in: text),
              let mass = groups(#"\btotal mass of the ([a-z]+) is (\#(number)) ?(g|grams?|kg|kilograms?)\b"#, in: text),
              let part = groups(#"\bvolume of the ([a-z]+) is (\#(number)) ?(mm|cm|m)\^?3"#, in: text),
              let asked = groups(#"\b(?:work out|find|calculate) the volume of the ([a-z]+)\b"#, in: text)?[1].lowercased() else { return nil }
        let whole = mass[1].lowercased(), known = part[1].lowercased()
        guard asked != whole, asked != known, known != whole, density[3].lowercased() == part[3].lowercased(),
              density[2].lowercased().prefix(1) == mass[3].lowercased().prefix(1),
              let d = Double(density[1]), d > 0, let m = Double(mass[2]), let v = Double(part[2]) else { return nil }
        // The whole is made of the two parts: said outright, or meant by "total".
        if has(#"\bconsists of\b|\bmade (?:up )?of\b"#, text), !has("\\b\(whole) (?:consists|is made(?: up)?) of (?:a|an|the) (?:\(known)|\(asked)) and (?:a|an|the) (?:\(known)|\(asked))\\b", text) { return nil }
        guard numbers(text).count == 3 else { return nil }
        let unit = part[3]
        let lead = [
            Step("Volume of the whole \(whole)", "Mass divided by density.", [MathLine(.symbol("\(mass[2]) ÷ \(density[1])"), amount(m / d), suffix: "\(unit)³")]),
            Step("Take away the \(known)", "The \(whole) is the \(known) and the \(asked) together.", [MathLine(.symbol("\(shown(m / d)) − \(part[2])"))]),
        ]
        return sum(.add([.multiply([amount(m), .power(amount(d), .minusOne)]), .multiply([.minusOne, amount(v)])]), decimals: (m / d - v).rounded() != m / d - v, lead)
    }

    // MARK: A small circle inside a large one

    /// "A large circle and a small circle are shown. The radius of the large circle is 12 cm.
    /// radius of large circle : radius of small circle = 4 : 1. Work out the shaded area. Give your answer in terms of π"
    private static func ring(_ text: String) -> Problem? {
        guard has(#"\b(?:a|the) large circle and (?:a|the) small circle\b"#, text),
              let large = groups(#"\b(radius|diameter) of the large circle is (\#(number)) ?(mm|cm|m)?\b"#, in: text),
              let ratio = groups(#"\b(radius|diameter) of (?:the )?large circle ?: ?(?:radius|diameter) of (?:the )?small circle ?= ?(\#(number)) ?: ?(\#(number))\b"#, in: text),
              has(#"\b(?:work out|find|calculate) the shaded area\b"#, text),
              let size = Double(large[2]), let a = Double(ratio[2]), let b = Double(ratio[3]), a > b, b > 0,
              numbers(text).count == 3 else { return nil }
        let R = large[1].lowercased() == "radius" ? size : size / 2
        let r = R * b / a
        let exact = has(#"\bin terms of\b"#, text)
        let lead = [
            Step("The small circle's radius", "The radii are in the ratio \(ratio[2]) : \(ratio[3]).", [MathLine(.symbol("\(shown(R)) × \(ratio[3])/\(ratio[2])"), amount(r))]),
            Step("Shaded area", "The large circle with the small circle taken out: π × R² − π × r².", [MathLine(.symbol("π × \(shown(R))² − π × \(shown(r))²"))]),
        ]
        let area = R * R - r * r
        let expr = Expr.multiply([amount(area), .constant(.pi)])
        return sum(exact ? expr : expr, decimals: !exact, lead)
    }

    // MARK: Laps of a track

    /// "A motor racing circuit consists of two parallel straight sections, each of length 0.75 km, a semicircle of
    /// diameter 0.9 km, three equal, smaller semicircles. The length of a motor race must be greater than 305 km.
    /// What is the lowest number of full laps needed at this circuit?"
    private static func laps(_ text: String) -> Problem? {
        guard let straight = groups(#"\btwo (?:parallel )?straight (?:sections|parts|lengths),? each (?:of length|of|is) (\#(number)) ?\#(lengthUnit)"#, in: text),
              let big = groups(#"\ba semicircle (?:of|with) diameter (\#(number)) ?\#(lengthUnit)"#, in: text),
              let small = groups(#"\b(two|three|four|five|six|\d) equal,? smaller semicircles\b"#, in: text), let n = count(small[1]), n >= 2,
              let race = groups(#"\blength of (?:a|the) [a-z ]*?race must be (greater than|more than|at least) (\#(number)) ?\#(lengthUnit)"#, in: text),
              has(#"\b(?:lowest|least|smallest) number of (?:full |whole |complete )?laps\b"#, text),
              let s = Double(straight[1]), let d = Double(big[1]), let total = Double(race[2]),
              let su = millimetres(straight[2]), let du = millimetres(big[2]), let ru = millimetres(race[3]), su == du, su == ru, d > 0 else { return nil }
        // Numbers: the straights, the diameter, the race; the labels on the drawing repeat them.
        let others = numbers(text).filter { ![s, d, total, n].contains($0) }
        guard others.isEmpty else { return nil }
        let lap = 2 * s + Double.pi * d
        let atLeast = race[1].lowercased() == "at least"
        var count = (total / lap).rounded(.up)
        if !atLeast, abs(count * lap - total) < 1e-9 { count += 1 }
        let u = straight[2]
        let lead = [
            Step("The two straights", "", [MathLine(.symbol("2 × \(straight[1])"), amount(2 * s), suffix: u)]),
            Step("The large semicircle", "Half of π × diameter.", [MathLine(.symbol("π × \(big[1]) ÷ 2"))]),
            Step("The \(shown(n)) small semicircles", "They fill the other end, so together their diameters make \(big[1]) \(u): each is \(shown(d / n)) \(u). Each is half of π × \(shown(d / n)).",
                 [MathLine(.symbol("\(shown(n)) × π × \(shown(d / n)) ÷ 2"), .symbol("π × \(big[1]) ÷ 2"))]),
            Step("One lap", "Add them: the two ends together are π × \(big[1]).", [MathLine(.symbol("\(shown(2 * s)) + π × \(big[1])"), amount((lap * 10000).rounded() / 10000), relation: "≈", suffix: u)]),
            Step("Laps needed", "Divide the race length by one lap, and go up to the next whole lap\(atLeast ? "" : ": the race must be longer than \(race[2]) \(u)").",
                 [MathLine(.symbol("\(race[2]) ÷ \(shown((lap * 10000).rounded() / 10000))"), amount((total / lap * 100).rounded() / 100), relation: "≈")]),
        ]
        return told("lowest number of full laps", [MathLine(.integer(Int(count)))], lead)
    }

    // MARK: Bounds of a pressure

    /// "The dimensions of a rectangular floor are to the nearest 0.1 metres. 2.6 m, 6.4 m. A force of 345 Newtons …
    /// to the nearest 5 Newtons. pressure = force/area. Work out the upper bound of the pressure. Give your answer to 4 significant figures."
    private static func pressureBounds(_ text: String) -> Problem? {
        guard has(#"\bpressure\b"#, text), let asked = groups(#"\b(upper|lower) bound of the pressure\b"#, in: text)?[1].lowercased(),
              let accuracy = groups(#"\b(?:dimensions|sides|lengths) of (?:a|the) rectangular ([a-z]+) are (?:correct )?to the nearest (\#(number)) ?\#(lengthUnit)"#, in: text),
              let force = groups(#"\bforce of (\#(number)) ?(?:newtons?|n)\b"#, in: text),
              let forceAccuracy = groups(#"\bforce is (?:correct )?to the nearest (\#(number)) ?(?:newtons?|n)\b"#, in: text),
              let step = Double(accuracy[2]), let f = Double(force[1]), let fStep = Double(forceAccuracy[1]), step > 0 else { return nil }
        // The two sides are the other lengths, written with the unit of the accuracy.
        let unit = short(accuracy[3])
        var rest = text
        for phrase in [accuracy[0], force[0], forceAccuracy[0]] { rest = rest.replacingOccurrences(of: phrase, with: " ") }
        let sides = every(#"(?<![\d.])(\#(number)) ?\#(lengthUnit)\b"#, in: rest).filter { millimetres($0[2]) == millimetres(unit) }.compactMap { Double($0[1]) }
        let significant = groups(#"\bto (\d) significant figures?\b"#, in: text).flatMap { Int($0[1]) }
        let leftover = every(#"(?<![\d.^])\d+(?:\.\d+)?"#, in: rest).count - sides.count - (significant == nil ? 0 : 1)
        guard sides.count == 2, leftover == 0, let a = sides.first, let b = sides.last else { return nil }
        let upper = asked == "upper"
        let half = step / 2, fHalf = fStep / 2
        let fBound = upper ? f + fHalf : f - fHalf
        let aBound = upper ? a - half : a + half, bBound = upper ? b - half : b + half
        guard aBound > 0, bBound > 0 else { return nil }
        let value = fBound / (aBound * bBound)
        let fWord = upper ? "upper" : "lower", sWord = upper ? "lower" : "upper"
        var lead = [
            Step("Bounds of the force", "To the nearest \(forceAccuracy[1]) N, so half of \(forceAccuracy[1]) either way. The \(fWord) bound makes the pressure \(fWord == "upper" ? "biggest" : "smallest").",
                 [MathLine(.symbol("\(fWord) bound"), amount(fBound), suffix: "N")]),
            Step("Bounds of the sides", "To the nearest \(accuracy[2]) \(unit), so half of \(accuracy[2]) either way. Dividing by a \(sWord == "lower" ? "smaller" : "larger") area makes the pressure \(upper ? "bigger" : "smaller"), so take the \(sWord) bounds.",
                 [MathLine(.symbol("\(shown(aBound)) and \(shown(bBound))"))]),
            Step("Pressure is force divided by area", "", [MathLine(.symbol("\(shown(fBound)) ÷ (\(shown(aBound)) × \(shown(bBound)))"), amount(value), relation: "≈")]),
        ]
        if let significant, significant >= 1 {
            lead.append(Step("Round it", "The answer is asked for to \(significant) significant figure\(significant == 1 ? "" : "s")."))
            return told("\(asked) bound of the pressure", [MathLine(.symbol(shown(rounded(value, significant: significant))), suffix: "N/\(unit)²")], lead)
        }
        return sum(.multiply([amount(fBound), .power(.multiply([amount(aBound), amount(bBound)]), .minusOne)]), decimals: true, Array(lead.dropLast()))
    }

    // MARK: A sector cut from a semicircle

    /// "The cross section of an earring is a semicircle, centre C, radius 25 mm … Sector BCD is white and has radius 12 mm …
    /// 150° … Is more than 20% of the semicircle white?"
    private static func sectorShare(_ text: String) -> Problem? {
        guard let whole = groups(#"\bis a semicircle,? (?:centre [A-Z],? )?(?:with )?radius (\#(number)) ?\#(lengthUnit)"#, in: text),
              let sector = groups(#"\bsector [A-Z]{3} is ([a-z]+) and has radius (\#(number)) ?\#(lengthUnit)"#, in: text),
              let question = groups(#"\bis more than (\#(number))% of the semicircle ([a-z]+)\?"#, in: text),
              question[2].lowercased() == sector[1].lowercased(), millimetres(whole[2]) == millimetres(sector[3]) else { return nil }
        let angles = every(#"(\d+(?:\.\d+)?) ?°"#, in: text)
        guard angles.count == 1, let angle = Double(angles[0][1]), angle > 0, angle < 180,
              let R = Double(whole[1]), let r = Double(sector[2]), r <= R, let limit = Double(question[1]) else { return nil }
        let half = Double.pi * R * R / 2, part = angle / 360 * Double.pi * r * r
        let percent = part / half * 100
        let yes = percent > limit
        let colour = sector[1].lowercased()
        let lead = [
            Step("Area of the semicircle", "Half of π × radius².", [MathLine(.symbol("½ × π × \(whole[1])²"), amount((half * 10).rounded() / 10), relation: "≈")]),
            Step("Area of the \(colour) sector", "\(shown(angle))/360 of a circle of radius \(sector[2]).", [MathLine(.symbol("\(shown(angle))/360 × π × \(sector[2])²"), amount((part * 10).rounded() / 10), relation: "≈")]),
            Step("As a percentage", "Divide the sector by the semicircle and multiply by 100, then compare with \(question[1])%.",
                 [MathLine(.symbol("\(shown((part * 10).rounded() / 10)) ÷ \(shown((half * 10).rounded() / 10)) × 100"), amount((percent * 10).rounded() / 10), relation: "≈", suffix: "%")]),
        ]
        return told("is more than \(question[1])% \(colour)", [MathLine(.symbol("\(yes ? "Yes" : "No"): \(shown((percent * 10).rounded() / 10))% is \(colour)"))], lead)
    }

    // MARK: Round 2

    /// A number with its trailing noise taken off, for answers: 0.36, 12.
    private static func tidy(_ value: Double) -> Double { Double(String(format: "%.10g", value)) ?? value }

    /// Whole numbers in the same ratio as two decimals, simplest form: 1.2 : 0.9 is 4 : 3.
    private static func whole(_ a: Double, _ b: Double) -> (Int, Int)? {
        for scale in [1.0, 10, 100, 1000, 10000] {
            let x = a * scale, y = b * scale
            if abs(x - x.rounded()) < 1e-6, abs(y - y.rounded()) < 1e-6, x.rounded() > 0, y.rounded() > 0 {
                let p = Int(x.rounded()), q = Int(y.rounded()), g = gcd(p, q)
                return (p / g, q / g)
            }
        }
        return nil
    }

    /// "Circle the area that is equal to 36 mm²", with the areas to choose from after it.
    private static func unitArea(_ text: String) -> Problem? {
        guard let given = groups(#"\b(?:area|volume) (?:that is )?equal to (\#(number)) ?(mm|cm|m|km) ?\^?([23])\b"#, in: text),
              let size = Double(given[1]), let from = millimetres(given[2]), let power = Double(given[3]) else { return nil }
        let after = String(text[text.range(of: given[0])!.upperBound...])
        let choices = every(#"(\#(number)) ?(mm|cm|m|km) ?\^?([23])\b"#, in: after).filter { $0[3] == given[3] }
        guard choices.count >= 2 else { return nil }
        let matching = choices.filter { choice in
            guard let value = Double(choice[1]), let to = millimetres(choice[2]) else { return false }
            return abs(value - size * pow(from / to, power)) < 1e-9 * max(1, value)
        }
        guard matching.count == 1, let to = millimetres(matching[0][2]) else { return nil }
        let raised = given[3] == "2" ? "²" : "³", per = shown(to / from), unit = matching[0][2]
        let lead = [
            Step("Change the units", "1 \(unit) is \(per) \(given[2]), so 1 \(unit)\(raised) is \(per)\(raised) = \(shown(pow(to / from, power))) \(given[2])\(raised).",
                 [MathLine(.symbol("\(given[1]) ÷ \(shown(pow(to / from, power)))"), amount(tidy(size * pow(from / to, power))), suffix: "\(unit)\(raised)")]),
        ]
        return told("equal to \(given[1]) \(given[2])\(raised)", [MathLine(.symbol("\(matching[0][1]) \(unit)\(raised)"))], lead)
    }

    /// "P is a rectangle with length 50 cm and width x cm. Q is a rectangle with width y cm. The length of Q
    /// is 20% more than the length of P. The area of Q is 10% less than the area of P. Work out the ratio x : y"
    private static func rectanglesChanged(_ text: String) -> Problem? {
        guard let first = groups(#"\b([A-Z]) is a rectangle with length (\#(number)) ?(?:mm|cm|m) and width ([a-z]) ?(?:mm|cm|m)?\b"#, in: text),
              let second = groups(#"\b([A-Z]) is a rectangle with width ([a-z]) ?(?:mm|cm|m)?\b"#, in: text), first[1] != second[1],
              let long = groups("\\blength of \(second[1]) is (\(number))% (more|less|greater|smaller) than the length of \(first[1])\\b", in: text),
              let area = groups("\\barea of \(second[1]) is (\(number))% (more|less|greater|smaller) than the area of \(first[1])\\b", in: text),
              let asked = groups(#"\bratio ([a-z]) ?: ?([a-z])\b"#, in: text),
              let p = Double(long[1]), let q = Double(area[1]), let l0 = Double(first[2]), numbers(text).allSatisfy({ [l0, p, q].contains($0) }) else { return nil }
        let x = first[3], y = second[2]
        guard Set([asked[1], asked[2]]) == Set([x, y]) else { return nil }
        func factor(_ percent: Double, _ word: String) -> Double { ["more", "greater"].contains(word.lowercased()) ? 1 + percent / 100 : 1 - percent / 100 }
        let lengthFactor = factor(p, long[2]), areaFactor = factor(q, area[2])
        guard lengthFactor > 0, areaFactor > 0 else { return nil }
        // x·L·(area factor) = y·L·(length factor), so x : y = length factor : area factor.
        guard var ratio = whole(lengthFactor, areaFactor) else { return nil }
        if asked[1] != x { ratio = (ratio.1, ratio.0) }
        let L = first[2]
        let lead = [
            Step("Length of \(second[1])", "\(long[1])% \(long[2].lowercased()) than \(L).", [MathLine(.symbol("\(L) × \(shown(lengthFactor))"), amount(tidy(Double(L)! * lengthFactor)))]),
            Step("Area of \(second[1])", "\(area[1])% \(area[2].lowercased()) than the area of \(first[1]), which is \(L)\(x).", [MathLine(.symbol("\(shown(tidy(Double(L)! * lengthFactor)))\(y)"), .symbol("\(shown(tidy(Double(L)! * areaFactor)))\(x)"))]),
            Step("Write the ratio", "Put \(x) and \(y) on opposite sides and simplify.", [MathLine(.symbol("\(asked[1]) : \(asked[2])"), .symbol("\(ratio.0) : \(ratio.1)"))]),
        ]
        return told("\(asked[1]) : \(asked[2])", [MathLine(.symbol("\(ratio.0) : \(ratio.1)"))], lead)
    }

    /// "Work out the arc length, in metres, of a semicircle of radius 6 metres." (choices 3π 6π 12π 18π, if read)
    private static func semicircleArc(_ text: String) -> Problem? {
        guard let found = groups(#"\barc length,?(?: in [a-z]+,)? of a semicircle (?:of|with) (radius|diameter) (\#(number)) ?\#(lengthUnit)"#, in: text),
              let size = Double(found[2]) else { return nil }
        let radius = found[1].lowercased() == "radius" ? size : size / 2
        // If the choices were read, the answer must be one of them.
        let offered = every(#"(\#(number))π"#, in: text).compactMap { Double($0[1]) }
        if !offered.isEmpty, !offered.contains(where: { abs($0 - radius) < 1e-9 }) { return nil }
        guard numbers(text).allSatisfy({ $0 == size || offered.contains($0) }) else { return nil }
        let lead = [Step("Arc of a semicircle", "Half of the circumference: half of 2 × π × radius, which is π × radius.", [MathLine(.symbol("π × \(shown(radius))"))])]
        return sum(.multiply([amount(radius), .constant(.pi)]), decimals: false, lead)
    }

    /// "A shaded semicircle is inside a circle. The radius of the circle is 10 cm. The diameter of the semicircle is 8 cm.
    /// How many times bigger is the unshaded area than the shaded area?"
    private static func shadedInside(_ text: String) -> Problem? {
        guard let shapes = groups(#"\ba shaded (semicircle|circle) is inside a (circle|semicircle)\b"#, in: text),
              shapes[1].lowercased() != shapes[2].lowercased() || true,
              let asked = groups(#"\bhow many times (?:bigger|greater|larger) is the (unshaded|shaded) area than the (unshaded|shaded) area\b"#, in: text),
              asked[1] != asked[2] else { return nil }
        func size(_ shape: String) -> Double? {
            guard let found = groups("\\b(radius|diameter) of the \(shape) is (\(number)) ?(?:mm|cm|m)\\b", in: text), let value = Double(found[2]) else { return nil }
            return found[1].lowercased() == "radius" ? value : value / 2
        }
        let inner = shapes[1].lowercased(), outer = shapes[2].lowercased()
        guard let r = size(inner), let R = size(outer), numbers(text).allSatisfy({ [2 * r, r, 2 * R, R].contains($0) }) else { return nil }
        func area(_ shape: String, _ radius: Double) -> Double { (shape == "semicircle" ? 0.5 : 1) * radius * radius }
        let shaded = area(inner, r), whole = area(outer, R)
        guard whole > shaded, shaded > 0 else { return nil }
        let unshaded = whole - shaded
        let lead = [
            Step("Shaded area", "The \(inner)\(inner == "semicircle" ? ": half of π × radius²" : ": π × radius²"), radius \(shown(r)).", [MathLine(.symbol("\(inner == "semicircle" ? "½ × " : "")π × \(shown(r))²"), .symbol("\(shown(shaded))π"))]),
            Step("Unshaded area", "The \(outer) without the shaded part.", [MathLine(.symbol("\(outer == "semicircle" ? "½ × " : "")π × \(shown(R))² − \(shown(shaded))π"), .symbol("\(shown(unshaded))π"))]),
            Step("How many times bigger", "Divide one by the other; the π cancels.", [MathLine(.symbol(asked[1].lowercased() == "unshaded" ? "\(shown(unshaded)) ÷ \(shown(shaded))" : "\(shown(shaded)) ÷ \(shown(unshaded))"))]),
        ]
        let value: Expr = asked[1].lowercased() == "unshaded" ? .multiply([amount(unshaded), .power(amount(shaded), .minusOne)]) : .multiply([amount(shaded), .power(amount(unshaded), .minusOne)])
        return sum(value, decimals: true, lead)
    }

    /// "The triangular cross section of a prism is an isosceles right-angled triangle. [x cm, x cm, 8.14 cm]
    /// The volume of the prism is 102 cm³. Use approximations to estimate the value of x."
    private static func triangularPrism(_ text: String) -> Problem? {
        guard has(#"\bcross[- ]?section of (?:a|the) prism is an isosceles right[- ]angled triangle\b"#, text),
              let volume = groups(#"\bvolume of the prism is (\#(number)) ?(mm|cm|m)\^?3"#, in: text), let v = Double(volume[1]),
              let letter = groups(#"\b(?:estimate|work out|find|calculate) the value of ([a-z])\b"#, in: text)?[1] else { return nil }
        // The length of the prism is the one other length given, on the drawing.
        let lengths = every(#"(?<![\d.^A-Za-z])(\#(number)) ?\#(volume[2])\b(?!\^)"#, in: text).compactMap { Double($0[1]) }
        guard lengths.count == 1, numbers(text).count == 2, let l = lengths.first, l > 0 else { return nil }
        let estimate = has(#"\bapproximations?\b|\bestimate\b"#, text)
        let V = estimate ? rounded(v, significant: 1) : v, L = estimate ? rounded(l, significant: 1) : l
        let value = (2 * V / L).squareRoot()
        var lead: [Step] = []
        if estimate { lead.append(Step("Round to one significant figure", "", [MathLine(.symbol("\(volume[1]) ≈ \(shown(V)),  \(shown(l)) ≈ \(shown(L))"))])) }
        lead += [
            Step("Volume of a prism", "Area of the cross-section × length. The triangle has two sides \(letter) at a right angle, so its area is ½\(letter)².",
                 [MathLine(.symbol("½\(letter)² × \(shown(L))"), amount(V))]),
            Step("Find \(letter)", "", [MathLine(.symbol("\(letter)²"), amount(tidy(2 * V / L)))]),
        ]
        return told(letter, [MathLine(.symbol(letter), amount((value * 10000).rounded() / 10000), relation: estimate ? "≈" : "=")], lead)
    }

    /// "For J, the force is 18.9 newtons and the area is 0.45 m². pressure for J : pressure for K = 7 : 8,
    /// area for J : area for K = 9 : 5. Work out the force for K."
    private static func pressureRatio(_ text: String) -> Problem? {
        guard let known = groups(#"\bfor ([A-Z]),? the force is (\#(number)) ?(?:newtons?|n) and the area is (\#(number)) ?(mm|cm|m) ?\^?2"#, in: text),
              let pressure = groups("\\bpressure for ([A-Z]) ?: ?pressure for ([A-Z]) ?= ?(\(number)) ?: ?(\(number))", in: text),
              let area = groups("\\barea for ([A-Z]) ?: ?area for ([A-Z]) ?= ?(\(number)) ?: ?(\(number))", in: text),
              let asked = groups(#"\bwork out the force for ([A-Z])\b"#, in: text)?[1],
              let f = Double(known[2]), let a = Double(known[3]), a > 0, numbers(text).count == 6 else { return nil }
        let j = known[1], k = asked
        guard j != k, Set([pressure[1], pressure[2]]) == Set([j, k]), Set([area[1], area[2]]) == Set([j, k]),
              let p1 = Double(pressure[3]), let p2 = Double(pressure[4]), let a1 = Double(area[3]), let a2 = Double(area[4]), p1 > 0, a1 > 0 else { return nil }
        let pScale = pressure[1] == j ? p2 / p1 : p1 / p2, aScale = area[1] == j ? a2 / a1 : a1 / a2
        let pJ = f / a, pK = pJ * pScale, aK = a * aScale
        let unit = known[4]
        let lead = [
            Step("Pressure for \(j)", "Force divided by area.", [MathLine(.symbol("\(known[2]) ÷ \(known[3])"), amount(tidy(pJ)))]),
            Step("Pressure for \(k)", "From the ratio of the pressures.", [MathLine(.symbol("\(shown(tidy(pJ))) × \(shown(pressure[1] == j ? p2 : p1))/\(shown(pressure[1] == j ? p1 : p2))"), amount(tidy(pK)))]),
            Step("Area for \(k)", "From the ratio of the areas, in \(unit)².", [MathLine(.symbol("\(known[3]) × \(shown(area[1] == j ? a2 : a1))/\(shown(area[1] == j ? a1 : a2))"), amount(tidy(aK)))]),
            Step("Force for \(k)", "Force is pressure × area, in newtons.", [MathLine(.symbol("\(shown(tidy(pK))) × \(shown(tidy(aK)))"))]),
        ]
        return sum(.multiply([amount(tidy(pK)), amount(tidy(aK))]), decimals: true, lead)
    }

    /// "The cornet is a hemisphere on top of a cone. The cone and the hemisphere each have radius 24 cm.
    /// The cone has perpendicular height 117 cm. Work out the total volume of the cornet."
    private static func coneAndHemisphere(_ text: String) -> Problem? {
        guard has(#"\b(?:is )?a hemisphere on (?:top of )?a cone\b|\ba cone (?:with|and) a hemisphere\b"#, text),
              let radius = groups(#"\bthe cone and the hemisphere each have (?:a )?radius (\#(number)) ?(mm|cm|m)\b"#, in: text) ?? groups(#"\bthe hemisphere and the cone each have (?:a )?radius (\#(number)) ?(mm|cm|m)\b"#, in: text),
              let height = groups(#"\bthe cone has (?:a )?(?:perpendicular )?height (\#(number)) ?(mm|cm|m)\b"#, in: text),
              has(#"\b(?:work out|find|calculate) the (?:total )?volume\b"#, text), !has(#"\bsimilar\b"#, text),
              radius[2] == height[2], let r = Double(radius[1]), let h = Double(height[1]) else { return nil }
        // Numbers: the radius and the height; the formula box's 1/3, 2/3 and powers may be read too.
        guard numbers(text).allSatisfy({ [r, h, 1, 2, 3].contains($0) }) else { return nil }
        let cone = r * r * h / 3, half = 2 * r * r * r / 3
        let exact = has(#"\bin terms of\b"#, text)
        let unit = radius[2]
        let lead = [
            Step("The cone", "⅓ × π × r² × h.", [MathLine(.symbol("⅓ × π × \(radius[1])² × \(height[1])"), .symbol("\(shown(cone))π"))]),
            Step("The hemisphere", "Half a sphere: ⅔ × π × r³.", [MathLine(.symbol("⅔ × π × \(radius[1])³"), .symbol("\(shown(half))π"))]),
            Step("Add them", "The answer is in \(unit)³.", [MathLine(.symbol("\(shown(cone))π + \(shown(half))π"), .symbol("\(shown(cone + half))π"))]),
        ]
        return sum(.multiply([amount(cone + half), .constant(.pi)]), decimals: !exact, lead)
    }

    /// "In this right-angled triangle, a = 16 cm, a : c = 4 : 5. Work out the area of the triangle."
    /// The sides are a, b and c, with c the hypotenuse (it's the one the ratio makes longer).
    private static func rightTriangleRatio(_ text: String) -> Problem? {
        guard has(#"\bright[- ]angled triangle\b"#, text), has(#"\b(?:work out|find|calculate) the area of the triangle\b"#, text),
              let side = groups(#"\b([abc]) ?= ?(\#(number)) ?(mm|cm|m)\b"#, in: text),
              let ratio = groups(#"\b([abc]) ?: ?([abc]) ?= ?(\#(number)) ?: ?(\#(number))\b"#, in: text),
              ratio[1] != ratio[2], Set([ratio[1], ratio[2]]).contains(side[1]), Set([ratio[1], ratio[2]]).contains("c"),
              let given = Double(side[2]), let m = Double(ratio[3]), let n = Double(ratio[4]), m > 0, n > 0, numbers(text).count == 3 else { return nil }
        // c is the hypotenuse, so it must come out longest.
        let cPart = ratio[1] == "c" ? m : n, otherPart = ratio[1] == "c" ? n : m
        guard cPart > otherPart else { return nil }
        let other = ratio[1] == "c" ? ratio[2] : ratio[1]
        let scale = side[1] == "c" ? given / cPart : given / otherPart
        let c = cPart * scale, leg = otherPart * scale, third = (c * c - leg * leg).squareRoot()
        let missing = ["a", "b"].first { $0 != other } ?? "b"
        let unit = side[3]
        let lead = [
            Step("Use the ratio", "\(ratio[1]) : \(ratio[2]) = \(ratio[3]) : \(ratio[4]), and \(side[1]) = \(side[2]).", [MathLine(.symbol("c"), amount(tidy(c))), MathLine(.symbol(other), amount(tidy(leg)))]),
            Step("Pythagoras for \(missing)", "c is the hypotenuse.", [MathLine(.symbol("\(missing)²"), .symbol("\(shown(tidy(c)))² − \(shown(tidy(leg)))²"), amount(tidy(c * c - leg * leg)))]),
            Step("Area", "Half the base times the height: the two shorter sides, in \(unit)².", [MathLine(.symbol("½ × \(shown(tidy(leg))) × \(shown(tidy(third)))"))]),
        ]
        return sum(.multiply([.power(.integer(2), .minusOne), amount(tidy(leg)), amount(tidy(third))]), decimals: abs(third - third.rounded()) > 1e-9, lead)
    }

    /// Similar solids with a pair of matching lengths: "radius 24 cm" … "similar" … "radius 2 cm" … "How many
    /// times greater is the volume of the plastic cornet than an actual cornet?"
    private static func similarTimes(_ text: String) -> Problem? {
        guard has(#"\bsimilar\b"#, text), let asked = groups(#"\bhow many times (?:greater|bigger|larger) is the (volume|surface area|area) of\b"#, in: text)?[1].lowercased() else { return nil }
        let sizes = every(#"\b(radius|radii|height|length|diameter) (?:of )?(\#(number)) ?(mm|cm|m)\b"#, in: text)
        guard sizes.count >= 2 else { return nil }
        // The first and the last: the large one, then the one it's compared with.
        let first = sizes[0], last = sizes[sizes.count - 1]
        guard first[1].lowercased().prefix(4) == last[1].lowercased().prefix(4) || (first[1].lowercased().hasPrefix("radi") && last[1].lowercased().hasPrefix("radi")),
              first[3] == last[3], let a = Double(first[2]), let b = Double(last[2]), a > b, b > 0 else { return nil }
        let k = a / b, power = asked == "volume" ? 3.0 : 2.0
        let lead = [
            Step("Scale factor for length", "The matching lengths are \(first[2]) \(first[3]) and \(last[2]) \(last[3]).", [MathLine(.symbol("\(first[2]) ÷ \(last[2])"), amount(tidy(k)))]),
            Step("Scale factor for \(asked)", "\(asked == "volume" ? "Volumes go up by the cube" : "Areas go up by the square") of the length scale factor.", [MathLine(.symbol("\(shown(tidy(k)))\(power == 3 ? "³" : "²")"))]),
        ]
        return sum(.power(amount(tidy(k)), .integer(Int(power))), decimals: false, lead)
    }

    // MARK: Round 3

    /// A value rounded as the question asks (significant figures, decimal places, a whole number); otherwise exact
    /// where it comes out to four decimal places, and to 3 significant figures where it doesn't. Nil when the question
    /// asks for a rounding that can't be made out.
    private static func asAsked(_ value: Double, _ text: String) -> (value: Double, relation: String)? {
        func result(_ r: Double) -> (Double, String) { (tidy(r), abs(r - value) < 1e-9 * max(1, abs(value)) ? "=" : "≈") }
        if let s = groups(#"\bto (\d) (?:significant figures?|sig\.? figs?|s\.? ?f\.?)(?![a-z])"#, in: text).flatMap({ Int($0[1]) }), s >= 1 { return result(rounded(value, significant: s)) }
        if let d = groups(#"\bto (\d) (?:decimal places?|d\.? ?p\.?)(?![a-z])"#, in: text).flatMap({ Int($0[1]) }) {
            let scale = pow(10, Double(d))
            return result((value * scale).rounded(.toNearestOrAwayFromZero) / scale)
        }
        if has(#"\bnearest (?:whole|integer|unit|minute|second|hour|degree|day|metre|centimetre|millimetre|kilometre|mile|gram|kilogram|litre|cm|mm|km|m|g|kg)\b"#, text) { return result(value.rounded(.toNearestOrAwayFromZero)) }
        if has(#"\b(?:give|write) (?:your|the) answers? (?:correct )?to\b|\bcorrect to\b|\bto the nearest\b"#, text) { return nil }
        if abs(value * 10000 - (value * 10000).rounded()) < 1e-6 { return (tidy(value), "=") }
        return result(rounded(value, significant: 3))
    }

    /// A number written with its thousands spaced or with commas: 80 000, 80,000.
    private static let big = #"\d{1,3}(?:[ ,]\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?"#

    private static func bigValue(_ written: String) -> Double? { Double(written.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")) }

    /// The text without a question's number ("7.", "Question 3:"), the marks for a part ("(2)") or a dotted answer line
    /// with its marks ("........ g [31"), which aren't part of the sum.
    private static func withoutNumbering(_ text: String) -> String {
        text.replacingOccurrences(of: #"\.{2,} ?[a-z%°£]{0,3} ?\[\d{1,3}\]?|\bto \d{1,2} (?:significant figures?|sig\.? figs?|s\.? ?f\.?|decimal places?|d\.? ?p\.?)(?![a-z])|\(total for question \d{1,2} is \d{1,2} marks?\)|©\s*ocr \d{4}|\*[A-Z0-9]+\*|\[\d{1,2}\]|\bquestion \d{1,2}\b:?|\(\d\)|(?<![\d.])\d{1,2}\.(?!\d)|(?<![\d.])\d{1,2} ?\([a-z]\)"#, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    private static let shapeWords = #"(?:rectangles?|triangles?|shapes?|trapezi(?:a|ums?)|quadrilaterals?|parallelograms?|pentagons?|hexagons?|kites?|polygons?)"#
    private static let corners = #"((?-i:[A-Z]{3,6}))(?![A-Za-z])"#

    /// Similar shapes named by their corners, with every length in the words: "Rectangles ABCD and EFGH are similar.
    /// AB = 3cm, BC = 7cm, EF = 9cm. Work out the length of FG." Corners named in the same order match. Also one triangle
    /// inside the other at a shared corner: "Triangle ABC is similar to triangle ADE. AB = 6cm, BC = 8cm, CE = 6.25cm,
    /// DE = 18cm. Work out the length of DB."
    private static func similarNamed(_ text: String) -> Problem? {
        guard has(#"\bsimilar\b"#, text),
              let names = groups(#"\b\#(shapeWords) \#(corners) and \#(corners) are similar\b"#, in: text)
                ?? groups(#"\b\#(shapeWords) \#(corners) is similar to (?:\#(shapeWords) )?\#(corners)"#, in: text)
                ?? groups(#"(?<![A-Za-z])\#(corners) and \#(corners) are similar (?:right[- ]angled )?\#(shapeWords)"#, in: text),
              names[1].count == names[2].count else { return nil }
        let first = Array(names[1]), second = Array(names[2]), n = first.count
        guard Set(first).count == n, Set(second).count == n else { return nil }
        // A corner in both shapes must be the same corner of each.
        let shared = Set(first).intersection(second)
        guard shared.count <= 1 else { return nil }
        var corner: Int?
        if let v = shared.first {
            guard let i = first.firstIndex(of: v), second.firstIndex(of: v) == i else { return nil }
            corner = i
        }
        func key(_ a: Character, _ b: Character) -> String { String([a, b].sorted()) }
        var label: [String: String] = [:]
        // Sides that match: between corners in the same places.
        var pairs: [(String, String)] = []
        for i in 0..<n {
            for j in (i + 1)..<n {
                let a = key(first[i], first[j]), b = key(second[i], second[j])
                guard a != b else { continue }
                pairs.append((a, b))
                label[a] = String([first[i], first[j]])
                label[b] = String([second[i], second[j]])
            }
        }
        // With a corner shared, the bit of a line between matching corners: BD, from B in one to D in the other.
        struct Piece { var piece: String, near: String, far: String, inner: Character, outer: Character }
        var pieces: [Piece] = []
        if let corner {
            for i in 0..<n where i != corner {
                let piece = Piece(piece: key(first[i], second[i]), near: key(first[corner], first[i]), far: key(second[corner], second[i]), inner: first[i], outer: second[i])
                pieces.append(piece)
                label[piece.piece] = String([first[i], second[i]])
            }
        }
        // The lengths given: "AB = 3cm".
        var given: [String: Double] = [:]
        var unit: String?
        for found in every(#"(?<![A-Za-z])((?-i:[A-Z]{2})) ?= ?(\#(number)) ?\#(lengthUnit)(?![A-Za-z^])"#, in: text) {
            let letters = Array(found[1])
            guard letters[0] != letters[1], let value = Double(found[2]), value > 0 else { return nil }
            let k = key(letters[0], letters[1])
            if let old = given[k], old != value { return nil }
            given[k] = value
            label[k] = found[1]
            let u = short(found[3])
            if let unit, unit != u { return nil }
            unit = u
        }
        guard let unit, given.count >= 2,
              let ask = every(#"\b(?:work out|find|calculate|what is) the (?:length|size) of ((?-i:[A-Z]{2}))(?![A-Za-z])"#, in: text).last?[1] else { return nil }
        let asked = key(Array(ask)[0], Array(ask)[1])
        label[asked] = ask
        let usable = Set(pairs.flatMap { [$0.0, $0.1] } + pieces.map(\.piece))
        guard given.keys.allSatisfy(usable.contains), usable.contains(asked), given[asked] == nil else { return nil }
        // Every number is a length given (the drawing's labels repeat them).
        guard numbers(withoutNumbering(text)).allSatisfy({ given.values.contains($0) }) else { return nil }
        // How triangles with a corner shared sit: one inside the other along the same lines, the other's corners
        // further out or nearer in, or crossed at the corner. Straight lines named say which; otherwise one is
        // inside the other, and the scale factor says which is bigger.
        var layout: String?
        let lines = every(#"(?<![A-Za-z])((?-i:[A-Z]{3,4}))(?: and ((?-i:[A-Z]{3,4})))? (?:is a|are) straight lines?\b"#, in: text).flatMap { [$0[1], $0[2]] }.filter { !$0.isEmpty }
        if let corner, !lines.isEmpty {
            let v = first[corner]
            var kinds: Set<String> = []
            for piece in pieces {
                guard let line = lines.map(Array.init).first(where: { Set($0).isSuperset(of: [v, piece.inner, piece.outer]) }),
                      let iv = line.firstIndex(of: v), let ii = line.firstIndex(of: piece.inner), let io = line.firstIndex(of: piece.outer) else { continue }
                kinds.insert((iv - ii) * (iv - io) < 0 ? "crossed" : abs(io - iv) > abs(ii - iv) ? "beyond" : "between")
            }
            guard kinds.count == 1 else { return nil }
            layout = kinds.first
        }
        var known = given
        var k: Double?
        var lead: [Step] = []
        func name(_ key: String) -> String { label[key] ?? key }
        func put(_ key: String, _ value: Double, _ how: String, _ sum: String) -> Bool {
            guard value > 1e-9 else { return false }
            known[key] = value
            lead.append(Step("\(name(key))", how, [MathLine(.symbol(name(key)), .symbol(sum), amount(tidy(value)), relation: "=", suffix: unit)]))
            return true
        }
        for _ in 0..<8 {
            if k == nil, let (a, b) = pairs.first(where: { known[$0.0] != nil && known[$0.1] != nil }), let x = known[a], let y = known[b] {
                k = y / x
                lead.append(Step("Scale factor", "\(name(a)) and \(name(b)) are matching sides.", [MathLine(.symbol("\(shown(y)) ÷ \(shown(x))"), amount(tidy(y / x)), relation: abs(y / x * 10000 - (y / x * 10000).rounded()) < 1e-6 ? "=" : "≈")]))
            }
            if let scale = k {
                for (a, b) in pairs {
                    if known[b] == nil, let x = known[a] {
                        guard put(b, x * scale, "It matches \(name(a)): multiply by the scale factor.", "\(shown(x)) × \(shown(tidy(scale)))") else { return nil }
                    } else if known[a] == nil, let y = known[b] {
                        guard put(a, y / scale, "It matches \(name(b)): divide by the scale factor.", "\(shown(y)) ÷ \(shown(tidy(scale)))") else { return nil }
                    }
                }
            }
            for piece in pieces {
                let kind = layout ?? k.flatMap { abs($0 - 1) < 1e-9 ? nil : ($0 > 1 ? "beyond" : "between") }
                guard let kind else { continue }
                let p = known[piece.piece], a = known[piece.near], b = known[piece.far]
                let (np, na, nb) = (name(piece.piece), name(piece.near), name(piece.far))
                switch kind {
                case "beyond":   // far = near + piece
                    if b == nil, let a, let p { guard put(piece.far, a + p, "\(na) and \(np) together.", "\(shown(a)) + \(shown(p))") else { return nil } }
                    else if p == nil, let a, let b { guard put(piece.piece, b - a, "\(nb) take away \(na).", "\(shown(b)) − \(shown(a))") else { return nil } }
                    else if a == nil, let b, let p { guard put(piece.near, b - p, "\(nb) take away \(np).", "\(shown(b)) − \(shown(p))") else { return nil } }
                case "between":  // far = near − piece
                    if b == nil, let a, let p { guard put(piece.far, a - p, "\(na) take away \(np).", "\(shown(a)) − \(shown(p))") else { return nil } }
                    else if p == nil, let a, let b { guard put(piece.piece, a - b, "\(na) take away \(nb).", "\(shown(a)) − \(shown(b))") else { return nil } }
                    else if a == nil, let b, let p { guard put(piece.near, b + p, "\(nb) and \(np) together.", "\(shown(b)) + \(shown(p))") else { return nil } }
                default:         // crossed: piece = near + far
                    if p == nil, let a, let b { guard put(piece.piece, a + b, "\(na) and \(nb) together.", "\(shown(a)) + \(shown(b))") else { return nil } }
                    else if b == nil, let a, let p { guard put(piece.far, p - a, "\(np) take away \(na).", "\(shown(p)) − \(shown(a))") else { return nil } }
                    else if a == nil, let b, let p { guard put(piece.near, p - b, "\(np) take away \(nb).", "\(shown(p)) − \(shown(b))") else { return nil } }
                }
            }
            // Only the piece known, with the scale factor: the sides through the corner are k times each other.
            if let scale = k {
                for piece in pieces where known[piece.near] == nil && known[piece.far] == nil {
                    guard let p = known[piece.piece] else { continue }
                    let kind = layout ?? (abs(scale - 1) < 1e-9 ? nil : (scale > 1 ? "beyond" : "between"))
                    guard let kind else { continue }
                    // beyond: k·near = near + piece; between: k·near = near − piece; crossed: piece = near + k·near.
                    let (np, nn) = (name(piece.piece), name(piece.near))
                    let near = kind == "crossed" ? p / (1 + scale) : p / abs(scale - 1)
                    let how = kind == "crossed" ? "\(np) is \(nn) and \(name(piece.far)) together, and \(name(piece.far)) is \(shown(tidy(scale))) × \(nn): so \(np) is \(shown(tidy(1 + scale))) × \(nn)."
                        : "\(name(piece.far)) is \(shown(tidy(scale))) × \(nn), and the difference between them is \(np): so \(np) is \(shown(tidy(abs(scale - 1)))) × \(nn)."
                    guard put(piece.near, near, how, "\(shown(p)) ÷ \(shown(tidy(kind == "crossed" ? 1 + scale : abs(scale - 1))))") else { return nil }
                }
            }
            // A piece and its two sides known, but no scale factor yet: the sides through the corner match.
            if k == nil, pieces.contains(where: { known[$0.near] != nil && known[$0.far] != nil }) { continue }
            if known[asked] != nil { break }
        }
        // Everything found must agree with every length given.
        guard let scale = k, let value = known[asked] else { return nil }
        for (a, b) in pairs { if let x = known[a], let y = known[b], abs(y - x * scale) > 1e-6 * max(1, y) { return nil } }
        // Shapes in the same place and the same size aren't asked about.
        guard abs(scale - 1) > 1e-9 || corner == nil else { return nil }
        guard let rounding = asAsked(value, text) else { return nil }
        let (answer, relation) = rounding
        return told(ask, [MathLine(.symbol(ask), amount(answer), relation: relation, suffix: unit)], lead)
    }

    /// Rectangles named by their corners, with sides, perimeters, areas and equal sides in the words: "QR = 10 cm,
    /// BC = PQ. The perimeter of ABCD is 26 cm. The area of PQRS is 45 cm². Find the length of AB."
    private static func namedRectangles(_ text: String) -> Problem? {
        guard has(#"\brectangles?\b"#, text), !has(#"\bsquares?\b|\bsimilar\b"#, text) else { return nil }
        var shapes: [[Character]] = []
        for found in every(#"\b(?:perimeter|area) of ((?-i:[A-Z]{4}))(?![A-Za-z])|\brectangles? ((?-i:[A-Z]{4}))(?![A-Za-z])"#, in: text) {
            let shape = Array(found[1].isEmpty ? found[2] : found[1])
            if !shapes.contains(shape) { shapes.append(shape) }
        }
        guard (1...3).contains(shapes.count), Set(shapes.flatMap { $0 }).count == shapes.count * 4 else { return nil }
        // A side as (rectangle, 0 for AB and CD, 1 for BC and DA).
        func side(_ name: String) -> (Int, Int)? {
            let l = Array(name)
            guard l.count == 2 else { return nil }
            for (i, shape) in shapes.enumerated() {
                guard let a = shape.firstIndex(of: l[0]), let b = shape.firstIndex(of: l[1]) else { continue }
                let d = (b - a + 4) % 4
                guard d == 1 || d == 3 else { return nil }
                return (i, (d == 1 ? a : b) % 2)
            }
            return nil
        }
        var sides = Array(repeating: [Double?](repeating: nil, count: 2), count: shapes.count)
        var perimeters = [Double?](repeating: nil, count: shapes.count), areas = [Double?](repeating: nil, count: shapes.count)
        var equal: [((Int, Int), (Int, Int))] = []
        var unit: String?
        var used: [Double] = []
        func agree(_ u: String) -> Bool { let s = short(u); if let unit, unit != s { return false }; unit = s; return true }
        for found in every(#"(?<![A-Za-z])((?-i:[A-Z]{2})) ?= ?(\#(number)) ?\#(lengthUnit)(?![A-Za-z^])"#, in: text) {
            guard let at = side(found[1]), let value = Double(found[2]), value > 0, agree(found[3]) else { return nil }
            if let old = sides[at.0][at.1], old != value { return nil }
            sides[at.0][at.1] = value
            used.append(value)
        }
        for found in every(#"(?<![A-Za-z])((?-i:[A-Z]{2})) ?= ?((?-i:[A-Z]{2}))(?![A-Za-z])"#, in: text) {
            guard let a = side(found[1]), let b = side(found[2]) else { return nil }
            equal.append((a, b))
        }
        let index = { (name: String) in shapes.firstIndex(of: Array(name)) }
        for found in every(#"\bperimeter of ((?-i:[A-Z]{4})) is (\#(number)) ?\#(lengthUnit)(?![A-Za-z^])"#, in: text) {
            guard let i = index(found[1]), let value = Double(found[2]), agree(found[3]) else { return nil }
            perimeters[i] = value
            used.append(value)
        }
        for found in every(#"\barea of ((?-i:[A-Z]{4})) is (\#(number)) ?\#(lengthUnit) ?\^?2"#, in: text) {
            guard let i = index(found[1]), let value = Double(found[2]), agree(found[3]) else { return nil }
            areas[i] = value
            used.append(value)
        }
        guard let unit, numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        // What's asked: a side, a perimeter or an area.
        guard let ask = every(#"\b(?:work out|find|calculate|what is) the (length of ((?-i:[A-Z]{2}))|perimeter of ((?-i:[A-Z]{4}))|area of ((?-i:[A-Z]{4})))(?![A-Za-z])"#, in: text).last else { return nil }
        var lead: [Step] = []
        func shapeName(_ i: Int) -> String { String(shapes[i]) }
        func sideName(_ i: Int, _ j: Int) -> String { j == 0 ? String([shapes[i][0], shapes[i][1]]) : String([shapes[i][1], shapes[i][2]]) }
        for _ in 0..<8 {
            for (a, b) in equal {
                if sides[b.0][b.1] == nil, let v = sides[a.0][a.1] { sides[b.0][b.1] = v; lead.append(Step("\(sideName(b.0, b.1))", "It's the same length as \(sideName(a.0, a.1)).", [MathLine(.symbol(sideName(b.0, b.1)), amount(v), suffix: unit)])) }
                if sides[a.0][a.1] == nil, let v = sides[b.0][b.1] { sides[a.0][a.1] = v; lead.append(Step("\(sideName(a.0, a.1))", "It's the same length as \(sideName(b.0, b.1)).", [MathLine(.symbol(sideName(a.0, a.1)), amount(v), suffix: unit)])) }
            }
            for i in shapes.indices {
                for j in 0..<2 where sides[i][j] == nil {
                    guard let other = sides[i][1 - j] else { continue }
                    if let area = areas[i] {
                        sides[i][j] = area / other
                        lead.append(Step("\(sideName(i, j))", "The area of \(shapeName(i)) is length × width, so divide it by \(sideName(i, 1 - j)).", [MathLine(.symbol(sideName(i, j)), .symbol("\(shown(area)) ÷ \(shown(other))"), amount(tidy(area / other)), suffix: unit)]))
                    } else if let perimeter = perimeters[i] {
                        sides[i][j] = perimeter / 2 - other
                        lead.append(Step("\(sideName(i, j))", "Half the perimeter of \(shapeName(i)) is one length and one width.", [MathLine(.symbol(sideName(i, j)), .symbol("\(shown(perimeter)) ÷ 2 − \(shown(other))"), amount(tidy(perimeter / 2 - other)), suffix: unit)]))
                    }
                }
            }
        }
        guard sides.allSatisfy({ $0.allSatisfy { ($0 ?? 1) > 0 } }) else { return nil }
        // Every fact must hold with the sides found.
        for i in shapes.indices {
            if let a = sides[i][0], let b = sides[i][1] {
                if let area = areas[i], abs(a * b - area) > 1e-6 * area { return nil }
                if let perimeter = perimeters[i], abs(2 * (a + b) - perimeter) > 1e-6 * perimeter { return nil }
            }
        }
        if !ask[2].isEmpty {
            guard let at = side(ask[2]), let value = sides[at.0][at.1] else { return nil }
            return told(ask[2], [MathLine(.symbol(ask[2]), amount(tidy(value)), suffix: unit)], lead)
        }
        let shape = ask[3].isEmpty ? ask[4] : ask[3]
        guard let i = index(shape), let a = sides[i][0], let b = sides[i][1] else { return nil }
        if ask[3].isEmpty {
            lead.append(Step("Area of \(shape)", "Length × width.", [MathLine(.symbol("\(shown(tidy(a))) × \(shown(tidy(b)))"))]))
            return told("area of \(shape)", [MathLine(amount(tidy(a * b)), suffix: "\(unit)²")], lead)
        }
        lead.append(Step("Perimeter of \(shape)", "Two lengths and two widths.", [MathLine(.symbol("2 × (\(shown(tidy(a))) + \(shown(tidy(b))))"))]))
        return told("perimeter of \(shape)", [MathLine(amount(tidy(2 * (a + b))), suffix: unit)], lead)
    }

    /// "The shape is a cone on top of a hemisphere. The height of the cone is 10 cm. The base of the cone has a diameter
    /// of 6 cm. The hemisphere has a diameter of 6 cm. The total volume of the shape is kπ cm³, where k is an integer.
    /// Work out the value of k." (π is often read as r or т.)
    private static func coneOnHemisphere(_ text: String) -> Problem? {
        guard has(#"\ba cone on (?:top of )?a hemisphere\b|\ba hemisphere (?:on top of|under|below) a cone\b"#, text),
              let height = groups(#"\b(?:perpendicular )?height of the cone is (\#(number)) ?(mm|cm|m)\b"#, in: text)
                ?? groups(#"\bthe cone has (?:a )?(?:perpendicular )?height (?:of )?(\#(number)) ?(mm|cm|m)\b"#, in: text),
              let base = groups(#"\b(?:base of the cone|the cone) has (?:a )?(radius|diameter) (?:of )?(\#(number)) ?(mm|cm|m)\b"#, in: text),
              let half = groups(#"\bthe hemisphere has (?:a )?(radius|diameter) (?:of )?(\#(number)) ?(mm|cm|m)\b"#, in: text),
              height[2] == base[3], base[3] == half[3],
              let h = Double(height[1]), let b = Double(base[2]), let s = Double(half[2]) else { return nil }
        let r = base[1].lowercased() == "radius" ? b : b / 2, R = half[1].lowercased() == "radius" ? s : s / 2
        // The cone sits on the flat face of the hemisphere, so they're the same width.
        guard r > 0, h > 0, abs(r - R) < 1e-9 else { return nil }
        // Numbers: the height, the widths, and the formulae's 1/3, 4/3 and powers.
        guard numbers(withoutNumbering(text)).allSatisfy({ [h, b, s, 1, 2, 3, 4].contains($0) }) else { return nil }
        let cone = r * r * h / 3, hemisphere = 2 * r * r * r / 3, total = cone + hemisphere
        let unit = height[2]
        let lead = [
            Step("The cone", "⅓ × π × r² × h, with radius \(shown(r)).", [MathLine(.symbol("⅓ × π × \(shown(r))² × \(shown(h))"), .symbol("\(shown(tidy(cone)))π"))]),
            Step("The hemisphere", "Half of a sphere: ½ × 4/3 × π × r³.", [MathLine(.symbol("⅔ × π × \(shown(r))³"), .symbol("\(shown(tidy(hemisphere)))π"))]),
            Step("Add them", "The total volume in \(unit)³.", [MathLine(.symbol("\(shown(tidy(cone)))π + \(shown(tidy(hemisphere)))π"), .symbol("\(shown(tidy(total)))π"))]),
        ]
        // "The total volume is kπ cm³, where k is an integer": k is the number in front of π.
        if let k = groups(#"\btotal volume of the (?:shape|solid|object) is ((?-i:[a-z])) ?(?:π|r|т|n|t|tt|jt)? ?(?:mm|cm|m) ?\^?3,? where \1 is an integer\b"#, in: text)?[1],
           has("\\b(?:work out|find|write down|what is) (?:the value of )?\(k)\\b", text) {
            guard abs(total - total.rounded()) < 1e-9 else { return nil }
            return told(k, [MathLine(.symbol(k), .integer(Int(total.rounded())))], lead)
        }
        guard has(#"\b(?:work out|find|calculate) the (?:total )?volume\b"#, text) else { return nil }
        return sum(.multiply([amount(tidy(total)), .constant(.pi)]), decimals: !has(#"\bin terms of\b"#, text), lead)
    }

    /// "Festival A will be in a rectangular field with an area of 80 000 m². The greatest number of people allowed to
    /// attend Festival A is 425. Festival B will be in a rectangular field 700 m by 2000 m. … Festival B is 6750. The area
    /// per person allowed for Festival B is greater than the area per person allowed for Festival A. How much greater?"
    private static func areaPerPerson(_ text: String) -> Problem? {
        guard has(#"\barea per person\b"#, text),
              let compared = groups(#"\barea per person (?:allowed )?(?:for|at|in) ((?-i:[A-Z][a-z]+ [A-Z0-9]))\b is (greater|more|bigger|larger|smaller|less) than the area per person (?:allowed )?(?:for|at|in) ((?-i:[A-Z][a-z]+ [A-Z0-9]))\b"#, in: text),
              has(#"\bhow much (?:greater|more|bigger|larger|smaller|less)\b"#, text) else { return nil }
        let place = #"((?-i:[A-Z][a-z]+ [A-Z0-9]))\b"#
        // Up to the facts, with no other place named on the way.
        let on = #"(?:(?!(?-i:[A-Z][a-z]+ [A-Z0-9])\b)[^.])*?"#
        var area: [String: Double] = [:], people: [String: Double] = [:], areaSum: [String: String] = [:]
        var used: [Double] = []
        var unit: String?
        for found in every(#"\b\#(place)\#(on)\bwith an area of (\#(big)) ?(km|cm|m) ?\^?2"#, in: text) {
            guard let value = bigValue(found[2]), area[found[1]] == nil else { return nil }
            area[found[1]] = value
            areaSum[found[1]] = shown(value)
            used.append(value)
            if let unit, unit != found[3] { return nil }
            unit = found[3]
        }
        for found in every(#"\b\#(place)\#(on)\b(?:field|room|park|garden|space|hall|area|site) (?:measuring )?(\#(big)) ?(km|cm|m) by (\#(big)) ?(km|cm|m)\b"#, in: text) {
            guard let a = bigValue(found[2]), let b = bigValue(found[4]), found[3] == found[5], area[found[1]] == nil else { return nil }
            area[found[1]] = a * b
            areaSum[found[1]] = "\(shown(a)) × \(shown(b))"
            used += [a, b]
            if let unit, unit != found[3] { return nil }
            unit = found[3]
        }
        for found in every(#"\bnumber of (?:people|visitors|spectators|fans|guests) (?:allowed )?(?:to attend|at|in|for) \#(place) is (\#(big))(?![\d.])"#, in: text) {
            guard let value = bigValue(found[2]), value > 0, people[found[1]] == nil else { return nil }
            people[found[1]] = value
            used.append(value)
        }
        let more = compared[1], less = compared[3]
        guard let unit, more != less, Set(area.keys) == [more, less], Set(people.keys) == [more, less],
              let aMore = area[more], let aLess = area[less], let pMore = people[more], let pLess = people[less] else { return nil }
        // Every number is an area, a side or a number of people (thousands may be spaced).
        let rest = withoutNumbering(text).replacingOccurrences(of: #"(?<=\d)[ ,](?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        guard numbers(rest).allSatisfy({ used.contains($0) }) else { return nil }
        let isMore = ["greater", "more", "bigger", "larger"].contains(compared[2].lowercased())
        let first = aMore / pMore, second = aLess / pLess
        let difference = isMore ? first - second : second - first
        guard difference > 0 else { return nil }
        guard let rounding = asAsked(difference, text) else { return nil }
        let (answer, relation) = rounding
        let lead = [
            Step("Area per person for \(more)", "Divide the area by the number of people.", [MathLine(.symbol("\(areaSum[more]!) ÷ \(shown(pMore))"), amount(tidy(first)), relation: "≈", suffix: "\(unit)²")]),
            Step("Area per person for \(less)", "", [MathLine(.symbol("\(areaSum[less]!) ÷ \(shown(pLess))"), amount(tidy(second)), relation: "≈", suffix: "\(unit)²")]),
            Step("The difference", "", [MathLine(.symbol(isMore ? "\(shown(tidy(first))) − \(shown(tidy(second)))" : "\(shown(tidy(second))) − \(shown(tidy(first)))"), amount(tidy(difference)), relation: "≈")]),
        ]
        return told("how much \(compared[2].lowercased())", [MathLine(amount(answer), suffix: "\(unit)²")], lead + (relation == "≈" ? [Step("Round it", "As the question asks.")] : []))
    }

    /// "The box exerts a force of 180 newtons on the floor. The box exerts a pressure of 187.5 newtons/m² on the floor.
    /// The face in contact with the floor is a rectangle of length 1.2 metres and width x metres. Work out the value of x."
    private static func pressureFace(_ text: String) -> Problem? {
        guard let force = groups(#"\bforce of (\#(number)) ?(?:newtons?|n)\b"#, in: text),
              let pressure = groups(#"\bpressure of (\#(number)) ?(?:newtons?|n) ?(?:/|per) ?(?:m|metre)(?:\^?2|'|²| squared)?"#, in: text),
              let face = groups(#"\bis a rectangle (?:of|with) length (\#(number)|(?-i:[a-z])) ?(?:m|metres?) and width (\#(number)|(?-i:[a-z])) ?(?:m|metres?)\b"#, in: text),
              let letter = groups(#"\b(?:work out|find|calculate) the value of ((?-i:[a-z]))\b"#, in: text)?[1],
              let f = Double(force[1]), let p = Double(pressure[1]), p > 0 else { return nil }
        let known = Double(face[1]) ?? Double(face[2])
        guard let side = known, side > 0, (face[1] == letter) != (face[2] == letter), Double(face[1]) == nil || Double(face[2]) == nil else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ [f, p, side].contains($0) }) else { return nil }
        let area = f / p, value = area / side
        guard let rounding = asAsked(value, text) else { return nil }
        let (answer, relation) = rounding
        let lead = [
            Step("The area of the face", "Pressure is force ÷ area, so the area is force ÷ pressure, in m².", [MathLine(.symbol("\(shown(f)) ÷ \(shown(p))"), amount(tidy(area)))]),
            Step("Find \(letter)", "The area is length × width.", [MathLine(.symbol(letter), .symbol("\(shown(tidy(area))) ÷ \(shown(side))"))]),
        ]
        return told(letter, [MathLine(.symbol(letter), amount(answer), relation: relation)], lead)
    }

    /// "A shaded shape made by removing sector OAB from sector OCD. Both sectors have an angle of 60°. The radius, OA, of
    /// the smaller sector is r cm. The ratio of radius OA to radius OC is 2 : 3. Work out, in terms of π and r, the total
    /// length of arc AB and arc CD." (π is often read as r or n.)
    private static func twoSectors(_ text: String) -> Problem? {
        guard let sectors = groups(#"\bremoving sector ((?-i:[A-Z]{3})) from sector ((?-i:[A-Z]{3}))(?![A-Za-z])"#, in: text),
              let angle = groups(#"\bboth sectors have an angle of (\#(number)) ?°"#, in: text), let theta = Int(angle[1]), theta > 0, theta < 360,
              let small = groups(#"\bradius,? ((?-i:[A-Z]{2})),? of the smaller sector is ((?-i:[a-z])) ?(?:mm|cm|m)?\b"#, in: text),
              let ratio = groups(#"\bratio of (?:the )?radius ((?-i:[A-Z]{2})) to (?:the )?radius ((?-i:[A-Z]{2})) is (\d+) ?: ?(\d+)\b"#, in: text),
              has(#"\bin terms of\b"#, text), let p = Int(ratio[3]), let q = Int(ratio[4]), p > 0, q > 0, p != q else { return nil }
        let inner = Array(sectors[1]), outer = Array(sectors[2])
        // The two sectors share their centre, the first letter of each.
        guard inner[0] == outer[0], Set(inner).intersection(outer).count == 1 else { return nil }
        let centre = inner[0]
        func isRadius(_ name: String, of sector: [Character]) -> Bool { let l = Array(name); return l.contains(centre) && Set(l).isSubset(of: sector) }
        // The ratio is small radius : large radius, either way round.
        let smallFirst: Bool
        if ratio[1] == small[1], isRadius(ratio[2], of: outer) { smallFirst = true } else if ratio[2] == small[1], isRadius(ratio[1], of: outer) { smallFirst = false } else { return nil }
        guard isRadius(small[1], of: inner) else { return nil }
        let (a, b) = smallFirst ? (p, q) : (q, p)   // small : large = a : b
        guard b > a, numbers(withoutNumbering(text)).allSatisfy({ [Double(theta), Double(p), Double(q)].contains($0) }) else { return nil }
        let r = small[2]
        let innerArc = String(inner.dropFirst()), outerArc = String(outer.dropFirst())
        let perimeter = has(#"\bperimeter of the shaded (?:shape|region)\b"#, text)
        guard perimeter || every(#"\btotal length of arc ((?-i:[A-Z]{2})) and arc ((?-i:[A-Z]{2}))\b"#, in: text).contains(where: { Set([Set($0[1]), Set($0[2])]) == Set([Set(innerArc), Set(outerArc)]) }) else { return nil }
        // Arcs: θ/360 × 2π × (r + br/a) = 2θ(a + b)/(360a) × πr.
        func fraction(_ top: Int, _ bottom: Int) -> (Int, Int) { let g = gcd(top, bottom); return (top / g, bottom / g) }
        let arcs = fraction(2 * theta * (a + b), 360 * a)
        func written(_ f: (Int, Int), _ tail: String) -> String { (f.0 == 1 ? "" : "\(f.0)") + tail + (f.1 == 1 ? "" : "/\(f.1)") }
        let large = fraction(b, a)
        var lead = [
            Step("The larger radius", "The radii are in the ratio \(a) : \(b).", [MathLine(.symbol("\(String([centre]))\(String(outer[1]))"), .symbol(written(large, r)))]),
            Step("Arc \(innerArc)", "\(theta)/360 of the circumference 2π\(r).", [MathLine(.symbol("\(theta)/360 × 2π\(r)"), .symbol(written(fraction(2 * theta, 360), "π\(r)")))]),
            Step("Arc \(outerArc)", "\(theta)/360 of 2π × \(written(large, r)).", [MathLine(.symbol(written(fraction(2 * theta * b, 360 * a), "π\(r)")))]),
            Step("Add the arcs", "", [MathLine(.symbol(written(arcs, "π\(r)")))]),
        ]
        guard perimeter else { return told("total length of the arcs", [MathLine(.symbol(written(arcs, "π\(r)")))], lead) }
        // The perimeter also has the two straight edges, each the larger radius take away the smaller.
        let edges = fraction(2 * (b - a), a)
        lead.append(Step("The straight edges", "Two of them, each the larger radius take away the smaller.", [MathLine(.symbol(written(edges, r)))]))
        return told("perimeter of the shaded shape", [MathLine(.symbol("\(written(arcs, "π\(r)")) + \(written(edges, r))"))], lead)
    }

    // MARK: Bearings, elevation and speed

    /// What the places are called once "helicopter F" is just F.
    private static let placeWords = #"(?:helicopters?|ships?|boats?|yachts?|points?|ports?|harbours?|towns?|villages?|lighthouses?|buoys?|planes?|aircraft|islands?|houses?|trees?|airports?|cities|city|camps?|checkpoints?)"#
    private static let place = #"((?-i:[A-Z][a-z]+|[A-Z]))(?![A-Za-z])"#
    private static let degrees = #"(\d{1,3}(?:\.\d+)?) ?(?:°|º|degrees)?"#

    private static func direction(_ bearing: Double) -> (x: Double, y: Double) {
        let radians = bearing * .pi / 180
        return (sin(radians), cos(radians))
    }

    /// Places linked by bearings and distances in words: "Donhampton is 48km from Castletown on a bearing of 050°.
    /// Eastville is on a bearing of 075° from Castletown and on a bearing of 150° from Donhampton. Calculate the distance
    /// of Eastville from Castletown." or "Helicopter D is due South of helicopter E. The bearing of helicopter F from
    /// helicopter E is 060°. …" Each place is found from ones already placed; nothing is shown unless all of it fits.
    private static func bearings(_ text: String) -> Problem? {
        guard has(#"\bbearings?\b|\bdue (?:north|south|east|west)\b"#, text), !has(#"\belevation\b|\bdepression\b|\bspeed\b|km/h|\bmph\b"#, text) else { return nil }
        let words = text.replacingOccurrences(of: "(?i)\\b(?:the )?\(placeWords) ((?-i:[A-Z]))(?![A-Za-z])", with: "$1", options: .regularExpression)
        struct Ray { var to: String, from: String, bearing: Double }
        struct Gap { var a: String, b: String, length: Double }
        var rays: [Ray] = [], gaps: [Gap] = []
        var unit: String?
        var used: [Double] = []
        func agree(_ u: String) -> Bool { let s = short(u); if let unit, unit != s { return false }; unit = s; return true }
        // "X is 48km from Y on a bearing of 050°"
        for f in every(#"\b\#(place) is (\#(number)) ?\#(lengthUnit) (?:away )?from \#(place),? on a bearing of \#(degrees)"#, in: words) {
            guard let d = Double(f[2]), let b = Double(f[5]), b < 360, agree(f[3]) else { return nil }
            rays.append(Ray(to: f[1], from: f[4], bearing: b)); gaps.append(Gap(a: f[1], b: f[4], length: d)); used += [d, b]
        }
        // "X is on a bearing of 075° from Y (and on a bearing of 150° from Z)"
        for f in every(#"\b\#(place) is on a bearing of \#(degrees) from \#(place)(?:,? and (?:is )?on a bearing of \#(degrees) from \#(place))?"#, in: words) {
            guard let b = Double(f[2]), b < 360 else { return nil }
            rays.append(Ray(to: f[1], from: f[3], bearing: b)); used.append(b)
            if !f[4].isEmpty { guard let c = Double(f[4]), c < 360 else { return nil }; rays.append(Ray(to: f[1], from: f[5], bearing: c)); used.append(c) }
        }
        // "The bearing of X from Y is 060°"
        for f in every(#"\bbearing of \#(place) from \#(place) is \#(degrees)"#, in: words) {
            guard let b = Double(f[3]), b < 360 else { return nil }
            rays.append(Ray(to: f[1], from: f[2], bearing: b)); used.append(b)
        }
        // "X is due South of Y"
        for f in every(#"\b\#(place) is (?:directly |due )(north|south|east|west) of \#(place)"#, in: words) {
            let b: Double = ["north": 0, "east": 90, "south": 180, "west": 270][f[2].lowercased()]!
            rays.append(Ray(to: f[1], from: f[3], bearing: b))
        }
        // "B is 25 kilometres due East of A", "B is 6 km due South of A and 6 km due West of C"
        let compass: [String: Double] = ["north": 0, "east": 90, "south": 180, "west": 270]
        for f in every(#"\b\#(place) is (\#(number)) ?\#(lengthUnit) (?:directly |due )(north|south|east|west) of \#(place)(?:,? and (\#(number)) ?\#(lengthUnit) (?:directly |due )(north|south|east|west) of \#(place))?"#, in: words) {
            guard let d = Double(f[2]), agree(f[3]) else { return nil }
            rays.append(Ray(to: f[1], from: f[5], bearing: compass[f[4].lowercased()]!)); gaps.append(Gap(a: f[1], b: f[5], length: d)); used.append(d)
            if !f[6].isEmpty {
                guard let e = Double(f[6]), agree(f[7]) else { return nil }
                rays.append(Ray(to: f[1], from: f[9], bearing: compass[f[8].lowercased()]!)); gaps.append(Gap(a: f[1], b: f[9], length: e)); used.append(e)
            }
        }
        // "The distance of X from Y is 900m", "the distance between X and Y is 30 km", "X is 12 km from Y."
        for f in every(#"\bdistance (?:of \#(place) from|between) \#(place)(?: and \#(place))? is (\#(number)) ?\#(lengthUnit)"#, in: words) {
            let a = f[1].isEmpty ? f[2] : f[1], b = f[1].isEmpty ? f[3] : f[2]
            guard !a.isEmpty, !b.isEmpty, let d = Double(f[4]), agree(f[5]) else { return nil }
            gaps.append(Gap(a: a, b: b, length: d)); used.append(d)
        }
        for f in every(#"\b\#(place) is (\#(number)) ?\#(lengthUnit) (?:away )?from \#(place)(?!,? on a bearing)"#, in: words) {
            guard let d = Double(f[2]), agree(f[3]) else { return nil }
            gaps.append(Gap(a: f[1], b: f[4], length: d)); used.append(d)
        }
        guard let unit, !rays.isEmpty, !gaps.isEmpty else { return nil }
        // What's asked: a distance, or a bearing (the last one asked, for a question in parts).
        guard let ask = every(#"\b(?:find|calculate|work out|what is) the (distance|bearing) (?:of \#(place) from \#(place)|between \#(place) and \#(place))|\bhow far is \#(place) from \#(place)"#, in: words).last else { return nil }
        let isBearing = ask[1].lowercased() == "bearing"
        let pair: (String, String) = !ask[2].isEmpty ? (ask[2], ask[3]) : !ask[4].isEmpty ? (ask[4], ask[5]) : (ask[6], ask[7])
        guard !(isBearing && !ask[4].isEmpty) else { return nil }
        let places = Set(rays.flatMap { [$0.to, $0.from] } + gaps.flatMap { [$0.a, $0.b] })
        guard places.contains(pair.0), places.contains(pair.1), pair.0 != pair.1 else { return nil }
        // Every number: a bearing, a distance, the angles on the drawing (from the bearings), how many places there are.
        // (An angle label on the drawing read with a raised digit, "3^3°" for 37°, is left out.)
        let checked = withoutNumbering(words).replacingOccurrences(of: #"\d+\^\d+ ?°"#, with: " ", options: .regularExpression)
        guard numbers(checked).allSatisfy({ used.contains($0) || $0 == Double(places.count) }) else { return nil }
        // Place them, one at a time, from the first distance.
        var at: [String: (x: Double, y: Double)] = [gaps[0].b: (0, 0)]
        for _ in 0..<places.count + 2 {
            for name in places where at[name] == nil {
                // Lines it lies on from places already placed, and distances from them.
                var lines: [(x: Double, y: Double, dx: Double, dy: Double)] = []
                var circles: [(x: Double, y: Double, r: Double)] = []
                for ray in rays {
                    if ray.to == name, let p = at[ray.from] { let u = direction(ray.bearing); lines.append((p.x, p.y, u.x, u.y)) }
                    if ray.from == name, let p = at[ray.to] { let u = direction(ray.bearing + 180); lines.append((p.x, p.y, u.x, u.y)) }
                }
                for gap in gaps {
                    if gap.a == name, let p = at[gap.b] { circles.append((p.x, p.y, gap.length)) }
                    if gap.b == name, let p = at[gap.a] { circles.append((p.x, p.y, gap.length)) }
                }
                var found: [(x: Double, y: Double)] = []
                for line in lines {
                    for circle in circles {
                        // |P + s·u − C| = r, s > 0
                        let fx = line.x - circle.x, fy = line.y - circle.y
                        let bq = 2 * (fx * line.dx + fy * line.dy), cq = fx * fx + fy * fy - circle.r * circle.r
                        let disc = bq * bq - 4 * cq
                        guard disc >= -1e-9 else { continue }
                        let roots = [(-bq + max(disc, 0).squareRoot()) / 2, (-bq - max(disc, 0).squareRoot()) / 2].filter { $0 > 1e-9 }
                        let distinct = roots.count == 2 && abs(roots[0] - roots[1]) > 1e-6 ? roots : Array(roots.prefix(1))
                        if distinct.count == 1 { found.append((line.x + distinct[0] * line.dx, line.y + distinct[0] * line.dy)) }
                    }
                }
                for i in lines.indices {
                    for j in lines.indices where j > i {
                        let a = lines[i], b = lines[j]
                        let det = a.dx * (-b.dy) - a.dy * (-b.dx)
                        guard abs(det) > 1e-9 else { continue }
                        let rx = b.x - a.x, ry = b.y - a.y
                        let s = (rx * (-b.dy) - ry * (-b.dx)) / det, t = (a.dx * ry - a.dy * rx) / det
                        if s > 1e-9, t > 1e-9 { found.append((a.x + s * a.dx, a.y + s * a.dy)) }
                    }
                }
                if let first = found.first {
                    // Two ways of placing it must agree.
                    guard found.allSatisfy({ abs($0.x - first.x) < 1e-6 * max(1, abs(first.x)) && abs($0.y - first.y) < 1e-6 * max(1, abs(first.y)) }) else { return nil }
                    at[name] = first
                }
            }
        }
        guard at.count == places.count else { return nil }
        // Every fact must hold where the places are.
        for ray in rays {
            let p = at[ray.from]!, q = at[ray.to]!, u = direction(ray.bearing)
            let dx = q.x - p.x, dy = q.y - p.y, length = (dx * dx + dy * dy).squareRoot()
            guard length > 1e-9, abs(dx / length - u.x) < 1e-6, abs(dy / length - u.y) < 1e-6 else { return nil }
        }
        for gap in gaps {
            let p = at[gap.a]!, q = at[gap.b]!
            guard abs(((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)).squareRoot() - gap.length) < 1e-6 * max(1, gap.length) else { return nil }
        }
        func distance(_ a: String, _ b: String) -> Double { let p = at[a]!, q = at[b]!; return ((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)).squareRoot() }
        func angle(at v: String, _ a: String, _ b: String) -> Double {
            let p = at[v]!, q = at[a]!, r = at[b]!
            let ux = q.x - p.x, uy = q.y - p.y, wx = r.x - p.x, wy = r.y - p.y
            return acos(max(-1, min(1, (ux * wx + uy * wy) / ((ux * ux + uy * uy).squareRoot() * (wx * wx + wy * wy).squareRoot())))) * 180 / .pi
        }
        func degreesText(_ value: Double) -> String { shown((value * 100).rounded() / 100) + "°" }
        var lead: [Step] = []
        // The working, as it's done by hand: the triangle with the side asked for and a side given, its angles from the
        // bearings, then the sine rule.
        if let gap = gaps.first(where: { Set([$0.a, $0.b]) != Set([pair.0, pair.1]) && (Set([$0.a, $0.b]).contains(pair.0) || Set([$0.a, $0.b]).contains(pair.1)) }) {
            let corners = Array(Set([gap.a, gap.b, pair.0, pair.1]))
            if corners.count == 3 {
                let third = corners.first { $0 != pair.0 && $0 != pair.1 }!, facing = corners.first { $0 != gap.a && $0 != gap.b }!
                let angles = corners.sorted().map { c in (c, angle(at: c, corners.first { $0 != c }!, corners.last { $0 != c }!)) }
                let lettered = corners.allSatisfy { $0.count == 1 }
                lead.append(Step(lettered ? "Angles of triangle \(corners.sorted().joined())" : "Angles of the triangle", "From the bearings: angles on a straight line, angles round a point, and the angles of a triangle adding to 180°.",
                                 angles.map { MathLine(.symbol("angle at \($0.0)"), .symbol(degreesText($0.1))) }))
                if !isBearing {
                    lead.append(Step("Sine rule", "The side asked for faces the angle at \(third); the side given, \(shown(gap.length)) \(unit), faces the angle at \(facing).",
                                     [MathLine(.symbol(lettered ? "\(pair.0)\(pair.1)" : "distance"), .symbol("\(shown(gap.length)) × sin \(degreesText(angle(at: third, pair.0, pair.1))) ÷ sin \(degreesText(angle(at: facing, gap.a, gap.b)))"))]))
                }
            }
        }
        if isBearing {
            let p = at[pair.1]!, q = at[pair.0]!
            var b = atan2(q.x - p.x, q.y - p.y) * 180 / .pi
            if b < 0 { b += 360 }
            guard let rounding = asAsked(b, text) else { return nil }
        let (value, relation) = rounding
            let written = abs(value - value.rounded()) < 1e-9 ? String(format: "%03d", Int(value.rounded()) % 360) : shown(value)
            return told("bearing of \(pair.0) from \(pair.1)", [MathLine(.symbol(written), relation: relation, suffix: "°")], lead)
        }
        guard let rounding = asAsked(distance(pair.0, pair.1), text) else { return nil }
        let (value, relation) = rounding
        let side = pair.0.count == 1 && pair.1.count == 1 ? "\(pair.0)\(pair.1)" : "distance"
        return told("distance of \(pair.0) from \(pair.1)", [MathLine(.symbol(side), amount(value), relation: relation, suffix: unit)], lead)
    }

    /// The height of something seen from two places on level ground, from its angles of elevation: "Two small boats are
    /// 28m apart. The angle of elevation of the boats to the top of the lighthouse are 24° and 40° respectively." The
    /// two places are on the same side of it (boats out from a lighthouse or a cliff), or on either side ("flying above
    /// two people"); unless the words say which, nothing is shown.
    private static func twoElevations(_ text: String) -> Problem? {
        guard has(#"\belevation\b"#, text), !has(#"\bdepression\b|\bbearing\b"#, text),
              let apart = groups(#"\b(?:are|is) (\#(number)) ?\#(lengthUnit) apart\b"#, in: text) ?? groups(#"\bdistance between (?:them|the two [a-z]+|[A-Z] and [A-Z]) is (\#(number)) ?\#(lengthUnit)"#, in: text),
              let what = groups(#"\b(?:find|calculate|work out|what is) the height of (?:the )?([a-z]+)\b"#, in: text)?[1],
              let d = Double(apart[1]), d > 0 else { return nil }
        var angles: [Double] = []
        if let both = groups(#"\bangles? of elevation[^.]*? (?:are|is) \#(degrees) and \#(degrees)"#, in: text), let a = Double(both[1]), let b = Double(both[2]) {
            angles = [a, b]
        } else {
            angles = every(#"\bangle of elevation of (?:the )?[a-z]+ from (?:point )?(?-i:[A-Z])\b is \#(degrees)"#, in: text).compactMap { Double($0[1]) }
        }
        guard angles.count == 2, angles.allSatisfy({ $0 > 0 && $0 < 90 }) else { return nil }
        let between = has(#"\babove two\b|\bbetween (?:the |these )?(?:two|them)\b|\beither side\b|\bopposite sides\b|\bon each side\b"#, text)
        let sameSide = has(#"\bsame side\b|\bin (?:a straight )?line with\b"#, text) || (has(#"\blighthouses?\b|\bcliffs?\b"#, text) && has(#"\bboats?\b|\bships?\b|\byachts?\b"#, text))
        guard between != sameSide else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ $0 == d || angles.contains($0) }) else { return nil }
        let (a, b) = (min(angles[0], angles[1]), max(angles[0], angles[1]))
        guard sameSide ? a < b : true else { return nil }
        let ta = tan(a * .pi / 180), tb = tan(b * .pi / 180)
        let h = sameSide ? d * ta * tb / (tb - ta) : d * ta * tb / (ta + tb)
        let unit = short(apart[2])
        let lead = sameSide ? [
            Step("Distances along the ground", "From each place to the foot of the \(what): the height ÷ tan of its angle of elevation. The nearer one has the bigger angle.",
                 [MathLine(.symbol("h ÷ tan \(shown(a))° − h ÷ tan \(shown(b))°"), amount(d))]),
            Step("Find h", "Take h out as a factor and divide.", [MathLine(.symbol("h"), .symbol("\(shown(d)) ÷ (1/tan \(shown(a))° − 1/tan \(shown(b))°)"))]),
        ] : [
            Step("Distances along the ground", "From each place to the point under the \(what): the height ÷ tan of its angle of elevation. Together they make \(shown(d)) \(unit).",
                 [MathLine(.symbol("h ÷ tan \(shown(angles[0]))° + h ÷ tan \(shown(angles[1]))°"), amount(d))]),
            Step("Find h", "Take h out as a factor and divide.", [MathLine(.symbol("h"), .symbol("\(shown(d)) ÷ (1/tan \(shown(angles[0]))° + 1/tan \(shown(angles[1]))°)"))]),
        ]
        guard let rounding = asAsked(h, text) else { return nil }
        let (value, relation) = rounding
        return told("height of the \(what)", [MathLine(.symbol("h"), amount(value), relation: relation, suffix: unit)], lead)
    }

    /// The clock time in hours: "midday", "14:00", "2 pm", "2.30 pm".
    private static func hours(_ written: String) -> Double? {
        let w = written.lowercased().replacingOccurrences(of: ".", with: ":").replacingOccurrences(of: " ", with: "")
        if w == "midday" || w == "noon" { return 12 }
        if w == "midnight" { return 0 }
        guard let f = groups(#"^(\d{1,2})(?::(\d{2}))?(?::?([ap])m?)?:?$"#, in: w), let h = Double(f[1]) else { return nil }
        let m = Double(f[2]) ?? 0
        guard h < 24, m < 60, !(f[3].isEmpty && f[2].isEmpty) else { return nil }
        if f[3] == "p", h < 12 { return h + 12 + m / 60 }
        if f[3] == "a", h == 12 { return m / 60 }
        return h + m / 60
    }

    /// Two ships leaving a port together on different bearings: "Two ships, A and B, leave a port at midday. A travels on
    /// a bearing of 085° at a speed of 18km/h. B travels on a bearing of 113° at a speed of y km/h. At 14:00 the distance
    /// between A and B is 30km. Boat B was travelling at a slower speed than boat A. Work out y, the speed of boat B."
    private static func twoShips(_ text: String) -> Problem? {
        let time = #"(midday|noon|midnight|\d{1,2}[:.]\d{2}(?: ?[ap]\.?m\.?)?|\d{1,2} ?[ap]\.?m\.?)"#
        guard let start = groups(#"\bleave (?:a|the) (?:port|harbour|airport|airfield|base|marina)(?: (?-i:[A-Z]))? (?:together )?at \#(time)"#, in: text),
              let t0 = hours(start[1]) else { return nil }
        let goes = every(#"(?<![A-Za-z])((?-i:[A-Z])) (?:travels|sails|flies|goes|moves) on a bearing of \#(degrees) at (?:a (?:constant |steady )?speed of )?(\#(number)|(?-i:[a-z])) ?(km/h|kmh|mph|km per hour|miles per hour)"#, in: text)
        guard goes.count == 2, goes[0][1] != goes[1][1], goes[0][4] == goes[1][4],
              let b1 = Double(goes[0][2]), let b2 = Double(goes[1][2]), b1 < 360, b2 < 360 else { return nil }
        let unit = goes[0][4].lowercased().hasPrefix("m") ? "miles" : "km"
        guard let later = groups(#"\bat \#(time),? the distance between ((?-i:[A-Z])) and ((?-i:[A-Z])) is (\#(number)) ?(km|kilometres|miles)\b"#, in: text),
              let t1 = hours(later[1]), t1 > t0, Set([later[2], later[3]]) == Set([goes[0][1], goes[1][1]]),
              let gap = Double(later[4]), gap > 0, (later[5].lowercased().hasPrefix("m") ? "miles" : "km") == unit else { return nil }
        let t = t1 - t0
        var turn = abs(b1 - b2).truncatingRemainder(dividingBy: 360)
        if turn > 180 { turn = 360 - turn }
        let c = cos(turn * .pi / 180)
        let speeds = [Double(goes[0][3]), Double(goes[1][3])]
        // One speed unknown: its letter is asked for.
        guard speeds.compactMap({ $0 }).count == 1, let which = speeds.firstIndex(where: { $0 == nil }), let known = speeds[1 - which] ?? nil else { return nil }
        let letter = goes[which][3], ship = goes[which][1], other = goes[1 - which][1]
        guard has("\\b(?:work out|find|calculate) \(letter)\\b|\\b(?:work out|find|calculate) the (?:speed|value of \(letter))\\b", text) else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ [b1, b2, known, gap, floor(t0), floor(t1), (t0 - floor(t0)) * 60, (t1 - floor(t1)) * 60, 0].contains($0) }) else { return nil }
        // gap² = a² + x² − 2ax·cos θ, with a the known ship's distance and x the other's.
        let a = known * t
        let disc = 4 * a * a * c * c - 4 * (a * a - gap * gap)
        guard disc >= 0 else { return nil }
        let roots = [(2 * a * c + disc.squareRoot()) / 2, (2 * a * c - disc.squareRoot()) / 2].filter { $0 > 1e-9 }
        var x: Double
        if roots.count == 1 || (roots.count == 2 && abs(roots[0] - roots[1]) < 1e-9) {
            x = roots[0]
        } else if roots.count == 2 {
            // Which of the two: the words say whether it was the slower or the faster.
            let slower = has("\\b\(ship)\\b[^.]*?\\b(?:slower|less) (?:speed )?than (?:\(placeWords) )?\(other)\\b", text)
            let faster = has("\\b\(ship)\\b[^.]*?\\b(?:faster|greater|more) (?:speed )?than (?:\(placeWords) )?\(other)\\b", text)
            guard slower != faster else { return nil }
            let fits = roots.filter { slower ? $0 / t < known : $0 / t > known }
            guard fits.count == 1 else { return nil }
            x = fits[0]
        } else {
            return nil
        }
        let speed = x / t
        let per = goes[0][4]
        let lead = [
            Step("How far \(other) has gone", "\(shown(t)) hours at \(shown(known)) \(per).", [MathLine(.symbol("\(shown(known)) × \(shown(t))"), amount(tidy(a)), suffix: unit)]),
            Step("The angle between their paths", "The difference of the bearings.", [MathLine(.symbol("\(shown(max(b1, b2))) − \(shown(min(b1, b2)))"), .symbol(shown(turn) + "°"))]),
            Step("Cosine rule", "Call the distance \(ship) has gone d: \(shown(gap))² = \(shown(tidy(a)))² + d² − 2 × \(shown(tidy(a))) × d × cos \(shown(turn))°. Solve the quadratic for d\(roots.count == 2 ? ", and keep the one that makes \(ship) the \(speed < known ? "slower" : "faster")" : "").",
                 [MathLine(.symbol("d"), amount(tidy((x * 1000).rounded() / 1000)), relation: "≈", suffix: unit)]),
            Step("Speed of \(ship)", "Distance ÷ time.", [MathLine(.symbol("d ÷ \(shown(t))"))]),
        ]
        guard let rounding = asAsked(speed, text) else { return nil }
        let (value, relation) = rounding
        return told(letter, [MathLine(.symbol(letter), amount(value), relation: relation, suffix: per)], lead)
    }

    /// A time in hours as it's written: "1 1/2 hours", "1½ hours", "1.5 hours", "90 minutes", "2 hours 30 minutes".
    private static func duration(_ text: String) -> (hours: Double, numbers: [Double])? {
        let t = text.replacingOccurrences(of: "½", with: " 1/2").replacingOccurrences(of: "¼", with: " 1/4").replacingOccurrences(of: "¾", with: " 3/4")
        if let f = groups(#"\bfor (\d+)(?: (\d)/(\d))? hours?(?: and (\d+) minutes?)?\b"#, in: t), let whole = Double(f[1]) {
            var h = whole, used = [whole]
            if !f[2].isEmpty, let a = Double(f[2]), let b = Double(f[3]), b > a, a > 0 { h += a / b; used += [a, b] }
            if !f[4].isEmpty, let m = Double(f[4]) { h += m / 60; used.append(m) }
            return (h, used)
        }
        if let f = groups(#"\bfor (\d+\.\d+) hours?\b"#, in: t), let h = Double(f[1]) { return (h, [h]) }
        if let f = groups(#"\bfor (\d+) minutes?\b"#, in: t), let m = Double(f[1]) { return (m / 60, [m]) }
        return nil
    }

    /// "B is 60 miles from A on a bearing of 170°. A ship sails from A on a bearing of 247°. It travels at a constant speed
    /// of 23 mph for 1 1/2 hours. Is the ship now closer to B than it was when it left A?"
    private static func sailsFrom(_ text: String) -> Problem? {
        let unit = #"(miles|mile|km|kilometres?|nautical miles)"#
        guard let fixed = groups(#"\b((?-i:[A-Z])) is (\#(number)) ?\#(unit) from ((?-i:[A-Z])) on a bearing of \#(degrees)"#, in: text),
              let trip = groups(#"\b(?:a|the) (ship|boat|yacht|plane|helicopter|car|walker|hiker|cyclist) (?:sails|travels|flies|sets off|leaves|walks|cycles|drives) from ((?-i:[A-Z])) on a bearing of \#(degrees)"#, in: text),
              let pace = groups(#"\bat a (?:constant |steady |average )?speed of (\#(number)) ?(mph|miles per hour|km/h|kmh|km per hour|knots)\b"#, in: text),
              let time = duration(text),
              let d = Double(fixed[2]), let b1 = Double(fixed[5]), let b2 = Double(trip[3]), let v = Double(pace[1]), b1 < 360, b2 < 360, d > 0, v > 0 else { return nil }
        let other = fixed[1], start = fixed[4], what = trip[1].lowercased()
        guard trip[2] == start, other != start else { return nil }
        // The units must go together: miles with mph, km with km/h.
        let isMiles = fixed[3].lowercased().hasPrefix("mile")
        let perMiles = pace[2].lowercased().hasPrefix("m")
        guard isMiles == perMiles, !pace[2].lowercased().hasPrefix("kn") else { return nil }
        let asksCloser = has("\\bis the \(what) now (?:closer|nearer) to \(other) than (?:it was )?when it left \(start)\\b", text)
        let asksDistance = has("\\bhow far is the \(what) from \(other)\\b|\\b(?:work out|find|calculate) the distance (?:of|from) the \(what) (?:from|to) \(other)\\b", text)
        guard asksCloser != asksDistance else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ [d, b1, b2, v].contains($0) || time.numbers.contains($0) }) else { return nil }
        let travelled = v * time.hours
        var turn = abs(b1 - b2).truncatingRemainder(dividingBy: 360)
        if turn > 180 { turn = 360 - turn }
        let gap = (d * d + travelled * travelled - 2 * d * travelled * cos(turn * .pi / 180)).squareRoot()
        let u = isMiles ? "miles" : "km"
        let lead = [
            Step("How far the \(what) goes", "Speed × time.", [MathLine(.symbol("\(shown(v)) × \(shown(time.hours))"), amount(tidy(travelled)), suffix: u)]),
            Step("The angle at \(start)", "Between the two bearings.", [MathLine(.symbol("\(shown(max(b1, b2))) − \(shown(min(b1, b2)))"), .symbol(shown(turn) + "°"))]),
            Step("Cosine rule", "The \(what)'s distance from \(other), with the angle at \(start) between the two sides.",
                 [MathLine(.symbol("√(\(shown(d))² + \(shown(tidy(travelled)))² − 2 × \(shown(d)) × \(shown(tidy(travelled))) × cos \(shown(turn))°)"), amount((gap * 100).rounded() / 100), relation: "≈", suffix: u)]),
        ]
        if asksDistance {
            guard let rounding = asAsked(gap, text) else { return nil }
            return told("distance from \(other)", [MathLine(amount(rounding.value), suffix: u)], lead)
        }
        // Too close to call at the accuracy shown: say nothing.
        guard abs(gap - d) >= 0.05 else { return nil }
        let closer = gap < d
        return told("closer to \(other)", [MathLine(.symbol("\(closer ? "Yes" : "No"): \(shown((gap * 10).rounded() / 10)) \(u) from \(other), against \(shown(d))"))],
                    lead + [Step("Compare", "When it left \(start) it was \(shown(d)) \(u) from \(other).")])
    }

    /// The text without a formula box's lines ("Volume of a sphere = 4/3 πr³ where r is the radius"), whose numbers are
    /// often misread and aren't part of the sum.
    private static func withoutFormulae(_ text: String) -> String {
        text.replacingOccurrences(of: #"\b(?:volume|(?:curved )?surface area|area) of an? [a-z ]+? ?[=\-][^=]*?\bwhere\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    /// "A cylinder, C, and a sphere, S, each have radius r. C has height h. volume of C = volume of S. Work out the ratio r : h"
    private static func equalSolids(_ text: String) -> Problem? {
        let solid = #"(cylinder|cone|sphere|hemisphere)"#
        guard let named = groups(#"\b(?:a|the) \#(solid),? ((?-i:[A-Z])),? and (?:a|the) \#(solid),? ((?-i:[A-Z])),? (?:each |both )?have (?:a )?radius ((?-i:[a-z]))\b"#, in: text) else { return nil }
        let r = named[5]
        var solids = [(name: named[1].lowercased(), letter: named[2]), (name: named[3].lowercased(), letter: named[4])]
        guard solids[0].letter != solids[1].letter, solids[0].name != solids[1].name else { return nil }
        // The one with a height is a cylinder or cone; the other a sphere or hemisphere.
        guard let tall = groups(#"\b((?-i:[A-Z])) has (?:a )?(?:perpendicular )?height ((?-i:[a-z]))\b"#, in: text), tall[2] != r else { return nil }
        let h = tall[2]
        if solids[1].letter == tall[1] { solids.swapAt(0, 1) }
        guard solids[0].letter == tall[1], ["cylinder", "cone"].contains(solids[0].name), ["sphere", "hemisphere"].contains(solids[1].name),
              has("\\bvolume of \(solids[0].letter) ?= ?volume of \(solids[1].letter)\\b|\\bvolume of \(solids[1].letter) ?= ?volume of \(solids[0].letter)\\b|\\bsame volume\\b", text),
              let asked = groups("\\bratio (\(r)|\(h)) ?: ?(\(r)|\(h))\\b", in: text), asked[1] != asked[2],
              numbers(withoutNumbering(withoutFormulae(text))).isEmpty, let a = share(solids[0].name), let b = share(solids[1].name) else { return nil }
        // (a.top/a.bottom)·r²h = (b.top/b.bottom)·r³, so h = (b.top·a.bottom)/(b.bottom·a.top)·r, and r : h = b.bottom·a.top : b.top·a.bottom.
        var left = b.bottom * a.top, right = b.top * a.bottom
        let g = gcd(left, right)
        left /= g; right /= g
        if asked[1] == h { swap(&left, &right) }
        let hText = right / left == 0 || right % left != 0 ? "\(right)\(r)/\(left)" : "\(right / left)\(r)"
        let lead = [
            Step("Volume of \(solids[0].letter)", "The \(solids[0].name): \(a.formula).", [MathLine(.symbol(a.formula.replacingOccurrences(of: "× h", with: "× \(h)").replacingOccurrences(of: "r", with: r)))]),
            Step("Volume of \(solids[1].letter)", "The \(solids[1].name): \(b.formula).", [MathLine(.symbol(b.formula.replacingOccurrences(of: "r", with: r)))]),
            Step("Make them equal", "Divide both sides by π and by \(r)².", [MathLine(.symbol(h), .symbol(asked[1] == h ? "\(left)\(r)/\(right)" : hText))]),
        ]
        return told("\(asked[1]) : \(asked[2])", [MathLine(.symbol("\(left) : \(right)"))], lead)
    }

    /// "A different cylinder has radius 3r and height 2h. How many times bigger is the volume of this cylinder than the
    /// volume of C?", with C (a cylinder with radius r and height h) in view.
    private static func scaledSolid(_ text: String) -> Problem? {
        guard let other = groups(#"\ba different (cylinder|cone) has (?:a )?radius (\d*) ?((?-i:[a-z])) and (?:a )?(?:perpendicular )?height (\d*) ?((?-i:[a-z]))\b"#, in: text),
              other[3] != other[5],
              let asked = groups("\\bhow many times (?:bigger|greater|larger) is the volume of this \(other[1]) than the volume of ((?-i:[A-Z]))\\b", in: text) else { return nil }
        let k = Int(other[2].isEmpty ? "1" : other[2]) ?? 0, m = Int(other[4].isEmpty ? "1" : other[4]) ?? 0
        let r = other[3], h = other[5], c = asked[1]
        guard k > 0, m > 0, k * k * m > 1 else { return nil }
        // C itself must be in view: the same kind of solid, with radius r and height h. (The question's start is often
        // on the page before; then nothing is shown.)
        guard groups("\\b(?:a|the) (cylinder|cone|sphere|hemisphere|cuboid|prism),? \(c)\\b", in: text)?[1].lowercased() == other[1].lowercased(),
              groups("\\b\(c) has (?:a )?(?:perpendicular )?height ((?-i:[a-z]))\\b", in: text)?[1] == h,
              groups(#"\b(?:each |both )?ha(?:s|ve) (?:a )?radius ((?-i:[a-z]))\b"#, in: text)?[1] == r else { return nil }
        guard numbers(withoutNumbering(withoutFormulae(text))).allSatisfy({ [Double(k), Double(m)].contains($0) }) else { return nil }
        let lead = [
            Step("The volume of a \(other[1])", other[1].lowercased() == "cone" ? "⅓ × π × radius² × height." : "π × radius² × height.", []),
            Step("Scale each part", "The radius is \(k) times as big, and it's squared; the height is \(m) times as big.", [MathLine(.symbol("\(k)² × \(m)"))]),
        ]
        return told("how many times bigger", [MathLine(.integer(k * k * m))], lead)
    }

    /// "The length of a diagonal of a cuboid is 20 cm. The diagonal makes an angle of 24° with the base. The area of the
    /// base is 150 cm². Work out the volume of the cuboid."
    private static func cuboidDiagonal(_ text: String) -> Problem? {
        guard let diagonal = groups(#"\b(?:length of (?:a|the) diagonal of (?:a|the|this) cuboid|diagonal of (?:a|the|this) cuboid) is (\#(number)) ?(mm|cm|m)\b(?!\^)"#, in: text),
              let angle = groups(#"\bdiagonal makes an angle of \#(degrees) with the base\b"#, in: text),
              let base = groups(#"\barea of the base is (\#(number)) ?(mm|cm|m) ?\^?2"#, in: text),
              diagonal[2] == base[2], let d = Double(diagonal[1]), let theta = Double(angle[1]), let a = Double(base[1]), theta > 0, theta < 90, a > 0,
              numbers(withoutNumbering(text)).allSatisfy({ [d, theta, a].contains($0) }) else { return nil }
        let unit = diagonal[2]
        let height = d * sin(theta * .pi / 180)
        var lead = [Step("The height", "The diagonal, the height and the diagonal of the base make a right-angled triangle; the height faces the \(shown(theta))° angle.",
                         [MathLine(.symbol("\(shown(d)) × sin \(shown(theta))°"), amount((height * 10000).rounded() / 10000), relation: "≈", suffix: unit)])]
        if has(#"\b(?:work out|find|calculate) the volume of the cuboid\b"#, text) {
            lead.append(Step("Volume", "Area of the base × height.", [MathLine(.symbol("\(shown(a)) × \(shown((height * 10000).rounded() / 10000))"))]))
            guard let rounding = asAsked(a * height, text) else { return nil }
            return told("volume of the cuboid", [MathLine(amount(rounding.value), suffix: "\(unit)³")], lead)
        }
        guard has(#"\b(?:work out|find|calculate) the height of the cuboid\b"#, text), let rounding = asAsked(height, text) else { return nil }
        return told("height of the cuboid", [MathLine(amount(rounding.value), suffix: unit)], lead)
    }

    // MARK: Round 4

    /// Cubic centimetres in one of a unit of volume (litres and millilitres too).
    private static func cubicCentimetres(_ unit: String) -> Double? {
        let u = unit.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "³", with: "^3").replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "?", with: "3")
        switch u {
        case "cm3", "ml", "millilitre", "millilitres": return 1
        case "m3": return 1_000_000
        case "mm3": return 0.001
        case "l", "litre", "litres": return 1000
        default: return nil
        }
    }

    /// Grams in one of a unit of mass.
    private static func gramsIn(_ unit: String) -> Double? {
        switch unit.lowercased() {
        case "g", "gram", "grams": 1
        case "kg", "kilogram", "kilograms": 1000
        case "tonne", "tonnes": 1_000_000
        default: nil
        }
    }

    private static let volumeUnit = #"(cm ?\^?3|m ?\^?3|mm ?\^?3|cm³|m³|cm\?|m\?|ml|millilitres?|litres?)(?![a-z])"#
    private static let massUnit = #"(kg|kilograms?|g|grams?|tonnes?)(?![a-z])"#
    private static let densityUnit = #"(kg|g|grams?|kilograms?) ?(?:/|per) ?(?:cubic )?(cm|m|centimetres?|metres?)(?: ?\^?3|³|'| cubed)?(?![a-z])"#

    /// The text without a stated conversion ("1 m³ = 1000 litres"), whose numbers aren't part of the sum.
    private static func withoutConversions(_ text: String) -> String {
        text.replacingOccurrences(of: #"\b1 ?(?:m|cm) ?\^?3 ?= ?[\d ,]+ ?(?:litres|cm ?\^?3|ml)\b|\b1 litre ?= ?[\d ,]+ ?(?:cm ?\^?3|ml)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    /// A unit as it's shown in an answer.
    private static func unitShown(_ unit: String) -> String {
        let u = unit.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "^", with: "")
        switch u {
        case "cm3", "cm³": return "cm³"
        case "m3", "m³": return "m³"
        case "mm3", "mm³": return "mm³"
        case "litre", "litres", "l": return "litres"
        case "gram", "grams", "g": return "g"
        case "kilogram", "kilograms", "kg": return "kg"
        default: return unit
        }
    }

    /// Mass, density and volume: two given, the third asked. "Some oil has a mass of 537 g and a density of 895 000 g/m³.
    /// Work out the volume of the oil. Give your answer in litres." The volume can also come from a cube's face.
    private static func massDensityVolume(_ text: String) -> Problem? {
        let words = withoutConversions(text)
        func distinct(_ found: [[String]]) -> [[String]] {
            var seen: Set<String> = []
            return found.filter { seen.insert(($0[1] + $0[2]).lowercased().replacingOccurrences(of: " ", with: "")).inserted }
        }
        let densities = distinct(every(#"\bdensity (?:of (?:the )?[a-z ]+? )?(?:is |of |= ?)?(\#(big)) ?\#(densityUnit)"#, in: words))
        let masses = distinct(every(#"\bmass (?:of (?:the )?[a-z ]+? )?(?:is |of |= ?)?(\#(big)) ?\#(massUnit)"#, in: words))
        var volumes = distinct(every(#"\bvolume (?:of (?:the )?[a-z ]+? )?(?:is |of |= ?)?(\#(big)) ?\#(volumeUnit)"#, in: words)).map { ($0[1], $0[2]) }
        var used: [Double] = []
        var cubeSide: (face: Double, side: Double, unit: String)?
        if volumes.isEmpty, has(#"\bcubes?\b"#, words), let face = groups(#"\barea of (?:each|one|a) face (?:of (?:the cube |cube )?[A-Z] |of the cube )?is (\#(number)) ?(cm|m|mm) ?\^?2"#, in: words), let f = Double(face[1]), f > 0 {
            cubeSide = (f, f.squareRoot(), face[2])
            volumes = [(shown(pow(f.squareRoot(), 3)), "\(face[2])^3")]
            used.append(f)
        }
        // A cuboid's volume from its three edges: "a cuboid which measures 3 cm by 4 cm by 5 cm".
        var box: (a: Double, b: Double, c: Double, unit: String)?
        if volumes.isEmpty, cubeSide == nil, has(#"\bcuboid\b"#, words), !has(#"\bnearest\b|\bcorrect to\b|\bbounds?\b"#, words),
           let f = groups(#"\b(?:measures|measuring|is|dimensions(?: of)?) (\#(number)) ?(cm|m|mm)? by (\#(number)) ?(cm|m|mm)? by (\#(number)) ?(cm|m|mm)\b(?! ?\^)"#, in: words),
           let a = Double(f[1]), let b = Double(f[3]), let c = Double(f[5]), [f[2], f[4]].allSatisfy({ $0.isEmpty || $0.lowercased() == f[6].lowercased() }) {
            box = (a, b, c, f[6].lowercased())
            volumes = [(shown(tidy(a * b * c)), "\(f[6].lowercased())^3")]
            used += [a, b, c]
        }
        guard densities.count <= 1, masses.count <= 1, volumes.count <= 1, densities.count + masses.count + volumes.count == 2,
              !has(#"\bmixed\b|\bratio\b|\bpercentage\b|%"#, words),
              let ask = every(#"\b(?:work out|find|calculate|what is|what) (?:the )?(mass|volume|density)\b"#, in: words).last?[1].lowercased() else { return nil }
        // A mass or volume given must be of the thing asked about: not the whole trophy's mass for a part's volume.
        if let object = groups(#"\b(?:work out|find|calculate|what is) the (?:mass|volume|density) of (?:the |this |each |one )?([a-z]+)\b"#, in: words)?[1].lowercased() {
            for f in every(#"\b(?:total )?(?:mass|volume) of (?:the |a |an |this |each )?([a-z]+) (?:is|=)"#, in: words) where f[1].lowercased() != object { _ = f; return nil }
        }
        if has(#"\btotal (?:mass|volume)\b"#, words) { return nil }
        let have = Set((densities.isEmpty ? [] : ["density"]) + (masses.isEmpty ? [] : ["mass"]) + (volumes.isEmpty ? [] : ["volume"]))
        guard !have.contains(ask), have.count == 2 else { return nil }
        // Everything in grams and cubic centimetres.
        var d: Double?, m: Double?, v: Double?
        var densityMass = "g", densityVolume = "cm"
        if let f = densities.first {
            guard let value = bigValue(f[1]), let g = gramsIn(f[2].lowercased().hasPrefix("k") ? "kg" : "g") else { return nil }
            densityMass = f[2].lowercased().hasPrefix("k") ? "kg" : "g"
            densityVolume = f[3].lowercased().hasPrefix("c") ? "cm" : "m"
            d = value * g / (densityVolume == "cm" ? 1 : 1_000_000)
            used.append(value)
        }
        if let f = masses.first { guard let value = bigValue(f[1]), let g = gramsIn(f[2]) else { return nil }; m = value * g; used.append(value) }
        if let f = volumes.first, cubeSide == nil { guard let value = bigValue(f.0), let c = cubicCentimetres(f.1) else { return nil }; v = value * c; used.append(value) }
        if let cubeSide, let c = cubicCentimetres("\(cubeSide.unit)3") { v = pow(cubeSide.side, 3) * c }
        let rest = words.replacingOccurrences(of: #"(?<=\d)[ ,](?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        guard numbers(withoutNumbering(rest)).allSatisfy({ used.contains($0) }) else { return nil }
        // The unit asked for, or the one the density is in.
        let wanted = groups(#"\b(?:give|write) (?:your|the) answer in ([a-z ]+?(?: ?(?:/|per) ?[a-z]+(?: ?\^?3)?)?|cm ?\^?3|m ?\^?3)(?=[.,]|$| correct| to )"#, in: words)?[1].lowercased().trimmingCharacters(in: .whitespaces)
        var lead: [Step] = []
        if let cubeSide { lead.append(Step("The cube's volume", "Each face is a square of area \(shown(cubeSide.face)), so each edge is √\(shown(cubeSide.face)) = \(shown(tidy(cubeSide.side))) \(cubeSide.unit).", [MathLine(.symbol("\(shown(tidy(cubeSide.side)))³"), amount(tidy(pow(cubeSide.side, 3))), suffix: "\(cubeSide.unit)³")])) }
        if let box { lead.append(Step("The cuboid's volume", "Length × width × height.", [MathLine(.symbol("\(shown(box.a)) × \(shown(box.b)) × \(shown(box.c))"), amount(tidy(box.a * box.b * box.c)), suffix: "\(box.unit)³")])) }
        let value: Double, unit: String
        switch ask {
        case "mass":
            guard let d, let v else { return nil }
            var u = densityMass
            if let wanted { if wanted.hasPrefix("k") { u = "kg" } else if wanted.hasPrefix("g") { u = "g" } else if wanted.hasPrefix("t") { u = "tonnes" } else { return nil } }
            value = d * v / gramsIn(u)!
            unit = u == "tonnes" ? "tonnes" : u
            lead.append(Step("Mass is density × volume", "", [MathLine(.symbol("mass"), .symbol("density × volume"))]))
        case "volume":
            guard let d, let m else { return nil }
            var u = densityVolume == "cm" ? "cm3" : "m3"
            if let wanted { guard cubicCentimetres(wanted) != nil else { return nil }; u = wanted }
            value = m / d / cubicCentimetres(u)!
            unit = unitShown(u)
            lead.append(Step("Volume is mass ÷ density", "", [MathLine(.symbol("volume"), .symbol("mass ÷ density"))]))
        default:
            guard let m, let v else { return nil }
            var perGram = 1.0, perVolume = 1.0, written = "g/cm³"
            if let wanted {
                if has(#"^(?:kg|kilograms?) ?(?:/|per) ?(?:cubic )?(?:m|metres?)"#, wanted) { perGram = 1000; perVolume = 1_000_000; written = "kg/m³" }
                else if has(#"^(?:g|grams?) ?(?:/|per) ?(?:cubic )?(?:cm|centimetres?)"#, wanted) {}
                else if has(#"^(?:g|grams?) ?(?:/|per) ?(?:cubic )?(?:m|metres?)"#, wanted) { perVolume = 1_000_000; written = "g/m³" }
                else { return nil }
            }
            value = m / v / perGram * perVolume
            unit = written
            lead.append(Step("Density is mass ÷ volume", "", [MathLine(.symbol("density"), .symbol("mass ÷ volume"))]))
        }
        guard value.isFinite, value > 0, let rounding = asAsked(value, text) else { return nil }
        return told(ask, [MathLine(amount(rounding.value), suffix: unit)], lead)
    }

    /// Liquids or metals mixed: "The density of apple juice is 1.05 g/cm³ … 25 cm³ of apple juice are mixed with 15 cm³
    /// of fruit syrup and 280 cm³ of carbonated water … Work out the density of the drink." Or parts in a ratio of a total:
    /// "The volume of a medal is 45 cm³. volume of copper : volume of tin = 22 : 3 … Work out the mass of the medal."
    private static func mixture(_ text: String) -> Problem? {
        var density: [String: Double] = [:]
        var unitFound: (String, String)?
        for f in every(#"\bdensity of ([a-z][a-z ]*?) is (\#(number)) ?\#(densityUnit)"#, in: text) {
            guard let d = Double(f[2]) else { return nil }
            let u = (f[3].lowercased().hasPrefix("k") ? "kg" : "g", f[4].lowercased().hasPrefix("c") ? "cm" : "m")
            if let unitFound, unitFound != u { return nil }
            unitFound = u
            density[f[1].lowercased()] = d
        }
        guard density.count >= 2, let unitFound else { return nil }
        // How much of each: volumes written out, or a ratio of a total.
        var parts: [(name: String, volume: Double)] = []
        var used = Array(density.values)
        var volumeUnitWritten = ""
        for f in every(#"(\#(number)) ?\#(volumeUnit) of ([a-z][a-z ]*?)(?= (?:are|is) mixed| and |,| to make|\.|$)"#, in: text) {
            guard let v = Double(f[1]), let name = density.keys.first(where: { $0 == f[3].lowercased() }) else { continue }
            if !volumeUnitWritten.isEmpty, volumeUnitWritten != unitShown(f[2]) { return nil }
            volumeUnitWritten = unitShown(f[2])
            parts.append((name, v))
            used.append(v)
        }
        var total: Double?
        if parts.isEmpty, let ratio = groups(#"\bvolume of ([a-z]+) ?: ?volume of ([a-z]+) ?= ?(\#(number)) ?: ?(\#(number))"#, in: text),
           let a = Double(ratio[3]), let b = Double(ratio[4]), let whole = groups(#"\bvolume of (?:a|the) [a-z]+ is (\#(number)) ?\#(volumeUnit)"#, in: text), let t = Double(whole[1]),
           density[ratio[1].lowercased()] != nil, density[ratio[2].lowercased()] != nil, a > 0, b > 0 {
            parts = [(ratio[1].lowercased(), t * a / (a + b)), (ratio[2].lowercased(), t * b / (a + b))]
            volumeUnitWritten = unitShown(whole[2])
            total = t
            used += [a, b, t]
        }
        guard parts.count == density.count, Set(parts.map(\.name)).count == parts.count else { return nil }
        let sum = parts.reduce(0) { $0 + $1.volume }
        // A total volume made must be the parts added up.
        if let made = groups(#"\bto make (?:a [a-z]+ with a volume of |a total of )?(\#(number)) ?\#(volumeUnit)"#, in: text), let t = Double(made[1]) {
            guard abs(t - sum) < 1e-9 * max(1, t) else { return nil }
            total = t
            used.append(t)
        }
        guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let mass = parts.reduce(0) { $0 + $1.volume * density[$1.name]! }
        // Litres with g/cm³: a litre is 1000 cm³, so the mass is in kg. Litres or ml with a density per m³ isn't done.
        let perLitre = volumeUnitWritten == "litres" && unitFound.1 == "cm"
        guard unitFound.1 == "cm" || !["litres", "ml"].contains(volumeUnitWritten) else { return nil }
        var lead: [Step] = [Step("Mass of each part", "Mass is density × volume.", parts.map { MathLine(.symbol("\($0.name)"), .symbol("\(shown(density[$0.name]!)) × \(shown(tidy($0.volume)))"), amount(tidy($0.volume * density[$0.name]!))) })]
        if total != nil, parts.count == 2, groups(#"\bvolume of ([a-z]+) ?: ?volume of"#, in: text) != nil {
            lead.insert(Step("Volume of each part", "Share the volume in the ratio.", parts.map { MathLine(.symbol($0.name), amount(tidy($0.volume))) }), at: 0)
        }
        lead.append(Step("Total mass", "", [MathLine(amount(tidy(mass)))]))
        if has(#"\b(?:work out|find|calculate) the density of the [a-z ]+"#, text) {
            let value = mass / sum
            lead.append(Step("Density of the mixture", "Total mass ÷ total volume.", [MathLine(.symbol("\(shown(tidy(mass))) ÷ \(shown(sum))"))]))
            guard let rounding = asAsked(value, text) else { return nil }
            return told("density", [MathLine(amount(rounding.value), suffix: "\(unitFound.0)/\(unitFound.1)³")], lead)
        }
        if has(#"\b(?:work out|find|calculate) the (?:total )?mass of the [a-z ]+"#, text) {
            guard let rounding = asAsked(mass, text) else { return nil }
            return told("mass", [MathLine(amount(rounding.value), suffix: perLitre ? "kg" : unitFound.0)], lead)
        }
        return nil
    }

    /// Circles through the corners of a square, a rectangle or a right-angled triangle, where the diameter is the
    /// diagonal or the side facing the right angle.
    private static func circleFacts(_ text: String) -> Problem? {
        let ask = every(#"\b(?:work out|find|calculate|what is) (?:the )?(circumference|area|radius|diameter|value of ([a-z])|length of (?:a |each )?side)(?: of the (circle|square))?\b"#, in: text).last
        guard let ask else { return nil }
        var diameter: Double?, lead: [Step] = [], unit = "cm", used: [Double] = []
        // A square with its corners on the circle: given the circle, asked the side.
        if has(#"\bsquare\b[^.]*?\binside a circle\b|\bsquare is inscribed in a circle\b"#, text), has(#"\b(?:each|every) vertex of the square is on the circumference\b|\bvertices of the square (?:are|lie) on the (?:circle|circumference)\b"#, text) {
            guard let side = groups(#"\bsides? of length ((?-i:[a-z])) ?(mm|cm|m)\b"#, in: text), ask[2] == side[1] || ask[1].lowercased().hasPrefix("length") else { return nil }
            unit = side[2]
            var r: Double?
            if let area = groups(#"\barea of the circle is (\#(number)) ?(mm|cm|m) ?\^?2"#, in: text), let a = Double(area[1]) { r = (a / .pi).squareRoot(); used.append(a)
                lead.append(Step("Radius of the circle", "Area = π × r², so r = √(area ÷ π).", [MathLine(.symbol("r"), .symbol("√(\(area[1]) ÷ π)"), amount(tidy((r! * 10000).rounded() / 10000)), relation: "≈")])) }
            else if let c = groups(#"\bcircumference of the circle is (\#(number)) ?(mm|cm|m)\b"#, in: text), let v = Double(c[1]) { r = v / (2 * .pi); used.append(v) }
            else if let rr = groups(#"\bradius of the circle is (\#(number)) ?(mm|cm|m)\b"#, in: text), let v = Double(rr[1]) { r = v; used.append(v) }
            guard let r, numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
            let x = 2 * r / 2.squareRoot()
            lead.append(Step("The square's diagonal is a diameter", "The diagonal is 2r, and it's √2 times the side.", [MathLine(.symbol(side[1]), .symbol("2r ÷ √2"))]))
            guard let rounding = asAsked(x, text) else { return nil }
            return told(side[1], [MathLine(.symbol(side[1]), amount(rounding.value), relation: rounding.relation, suffix: unit)], lead)
        }
        // A rectangle ABCD with its corners on the circle.
        if has(#"\b([A-Z]), ([A-Z]), ([A-Z]) and ([A-Z]) (?:lie|are(?: points)?) on (?:a|the) (?:circle|circumference)"#, text),
           let rect = groups(#"\b((?-i:[A-Z]{4})) is a rectangle\b"#, in: text)?[1] {
            let l = Array(rect)
            guard let a = groups("\\b(?:\(l[0])\(l[1])|\(l[1])\(l[0])) ?= ?(\(number)) ?(mm|cm|m)\\b", in: text), let b = groups("\\b(?:\(l[1])\(l[2])|\(l[2])\(l[1])) ?= ?(\(number)) ?(mm|cm|m)\\b", in: text),
                  a[2] == b[2], let x = Double(a[1]), let y = Double(b[1]) else { return nil }
            unit = a[2]; used = [x, y]
            diameter = (x * x + y * y).squareRoot()
            lead.append(Step("The diagonal is a diameter", "A right angle at each corner, so the diagonal is a diameter (Pythagoras).", [MathLine(.symbol("√(\(a[1])² + \(b[1])²)"), amount(tidy((diameter! * 10000).rounded() / 10000)), relation: "≈", suffix: unit)]))
        }
        // A right-angled triangle with its corners on the circle: the side facing the right angle is a diameter.
        else if has(#"\b([A-Z]), ([A-Z]) and ([A-Z]) (?:lie|are(?: points)?) on (?:the circumference of )?(?:a|the) (?:circle|circumference)"#, text),
                let angle = groups(#"\bangle ((?-i:[A-Z]))((?-i:[A-Z]))((?-i:[A-Z])) ?(?:is |= ?)90 ?°"#, in: text) {
            let p = angle[1], v = angle[2], q = angle[3]
            guard let a = groups("\\b(?:\(p)\(v)|\(v)\(p)) ?= ?(\(number)) ?(mm|cm|m)\\b", in: text), let b = groups("\\b(?:\(q)\(v)|\(v)\(q)) ?= ?(\(number)) ?(mm|cm|m)\\b", in: text),
                  a[2] == b[2], let x = Double(a[1]), let y = Double(b[1]) else { return nil }
            unit = a[2]; used = [x, y, 90]
            diameter = (x * x + y * y).squareRoot()
            lead.append(Step("\(p)\(q) is a diameter", "The angle in a semicircle is a right angle, so the side facing it is a diameter (Pythagoras).", [MathLine(.symbol("√(\(a[1])² + \(b[1])²)"), amount(tidy((diameter! * 10000).rounded() / 10000)), relation: "≈", suffix: unit)]))
        }
        guard let diameter, ask[3].isEmpty || ask[3].lowercased() == "circle", numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let what = ask[1].lowercased()
        let value: Double, suffix: String
        switch what {
        case "circumference": value = .pi * diameter; suffix = unit; lead.append(Step("Circumference", "π × diameter.", []))
        case "area": value = .pi * diameter * diameter / 4; suffix = "\(unit)²"; lead.append(Step("Area", "π × radius².", []))
        case "radius": value = diameter / 2; suffix = unit
        case "diameter": value = diameter; suffix = unit
        default: return nil
        }
        guard let rounding = asAsked(value, text) else { return nil }
        return told(what, [MathLine(amount(rounding.value), suffix: suffix)], lead)
    }

    /// "Here is a quarter circle of radius 6 cm. Work out the area of the quarter circle. Give your answer in terms of π."
    private static func quarterCircle(_ text: String) -> Problem? {
        guard let shape = groups(#"\b(?:here is )?a (quarter circle|quadrant|semicircle|semi-circle) (?:of|with) (radius|diameter) (\#(number)) ?(mm|cm|m)\b"#, in: text),
              let size = Double(shape[3]), size > 0,
              let ask = groups(#"\b(?:work out|find|calculate) the (area|perimeter) of the (?:quarter circle|quadrant|semicircle|semi-circle|shape)\b"#, in: text)?[1].lowercased(),
              numbers(withoutNumbering(text)).allSatisfy({ $0 == size }) else { return nil }
        let r = shape[2].lowercased() == "radius" ? size : size / 2
        let share = shape[1].lowercased().hasPrefix("semi") ? 0.5 : 0.25
        let exact = has(#"\bin terms of\b"#, text)
        let unit = shape[4]
        if ask == "area" {
            let k = share * r * r
            let lead = [Step("Area", "\(share == 0.5 ? "Half" : "A quarter") of π × r².", [MathLine(.symbol("\(share == 0.5 ? "½" : "¼") × π × \(shown(r))²"), .symbol("\(shown(tidy(k)))π"))])]
            if exact { return told("area", [MathLine(.symbol("\(shown(tidy(k)))π"), suffix: "\(unit)²")], lead) }
            guard let rounding = asAsked(k * .pi, text) else { return nil }
            return told("area", [MathLine(amount(rounding.value), suffix: "\(unit)²")], lead)
        }
        // Perimeter: the arc and the straight edges (two radii, or the diameter).
        let arc = share * 2 * r, straight = share == 0.5 ? 2 * r : 2 * r
        let lead = [Step("Perimeter", "The arc, \(share == 0.5 ? "half" : "a quarter") of 2πr, and the straight edge\(share == 0.5 ? " (the diameter)" : "s (two radii)").", [MathLine(.symbol("\(shown(tidy(arc)))π + \(shown(straight))"))])]
        if exact { return told("perimeter", [MathLine(.symbol("\(shown(tidy(arc)))π + \(shown(straight))"), suffix: unit)], lead) }
        guard let rounding = asAsked(arc * .pi + straight, text) else { return nil }
        return told("perimeter", [MathLine(amount(rounding.value), suffix: unit)], lead)
    }

    /// A pyramid with a square base and its top above the centre: from the side (or the base's diagonal) and the height,
    /// or the angle a sloping edge makes with the base. "VABCD is a square-based pyramid. The horizontal base ABCD has side
    /// length 10 cm and centre M. Angle VMA is 90°. Angle VAM is 68°. Work out the volume of the pyramid."
    private static func pyramid(_ text: String) -> Problem? {
        guard has(#"\bsquare[- ]based pyramid\b|\bpyramid with a (?:horizontal )?square base\b|\bpyramid\b[^.]*?\bsquare (?:horizontal )?base\b|\bbase\b[^.]*?\bof the pyramid is a square\b"#, text),
              !has(#"\bcube\b|\bcuboid\b|\bsphere\b|\bhemisphere\b|\bcone\b|\bcylinder\b|\bprism\b|\bsimilar\b"#, text) else { return nil }
        var used: [Double] = []
        var half: Double?          // the centre to a corner: half the diagonal
        var side: Double?
        var halfText = ""
        var unit = "cm"
        if let s = groups(#"\b(?:side length|side|sides of length|base length|length) (?:of )?(\#(number)) ?(mm|cm|m)\b(?!\^)"#, in: text), let v = Double(s[1]) {
            side = v; half = v / 2.squareRoot(); unit = s[2]; used.append(v)
            halfText = "Half the diagonal of the square base: half of √2 × \(shown(v))."
        }
        // A diagonal of the base: two of its corners that aren't next to each other.
        if side == nil, let base = groups(#"\b(?:base|square) ((?-i:[A-Z]{4}))\b"#, in: text)?[1] ?? groups(#"\b(?-i:[A-Z])((?-i:[A-Z]{4})) is a pyramid\b"#, in: text)?[1] {
            let l = Array(base)
            for (a, b) in [(l[0], l[2]), (l[1], l[3])] {
                if let d = groups("\\b(?:\(a)\(b)|\(b)\(a)) ?= ?(\(number)) ?(mm|cm|m)\\b", in: text), let v = Double(d[1]) {
                    half = v / 2; side = v / 2.squareRoot(); unit = d[2]; used.append(v)
                    halfText = "Half the diagonal \(a)\(b): \(shown(v)) ÷ 2."
                }
            }
        }
        guard let half, let side else { return nil }
        var height: Double?
        var lead: [Step] = []
        if let h = groups(#"\b(?:perpendicular )?height (?:(?-i:[A-Z]{2}) )?(?:of the pyramid )?(?:is |of )?(\#(number)) ?(mm|cm|m)\b(?!\^)"#, in: text), let v = Double(h[1]), h[2] == unit {
            height = v; used.append(v)
        }
        // The angle between a sloping edge and the base, at a corner: VAM with M the centre.
        var edge: Double?
        for f in every(#"\bangle ((?-i:[A-Z]{3})) (?:is |= ?)(\#(number)) ?°"#, in: text) {
            guard let a = Double(f[2]) else { return nil }
            used.append(a)
            if a == 90 { continue }
            guard height == nil, a > 0, a < 90 else { return nil }
            let t = a * .pi / 180
            height = half * tan(t)
            edge = half / cos(t)
            lead.append(Step("From the centre to a corner", halfText, [MathLine(amount(tidy((half * 10000).rounded() / 10000)), relation: "≈", suffix: unit)]))
            lead.append(Step("The right-angled triangle", "The height, the half-diagonal and the sloping edge, with \(shown(a))° at the corner.",
                             [MathLine(.symbol("height"), .symbol("\(shown(tidy((half * 10000).rounded() / 10000))) × tan \(shown(a))°"), amount((height! * 100).rounded() / 100), relation: "≈", suffix: unit),
                              MathLine(.symbol("edge"), .symbol("\(shown(tidy((half * 10000).rounded() / 10000))) ÷ cos \(shown(a))°"), amount((edge! * 100).rounded() / 100), relation: "≈", suffix: unit)]))
        }
        guard let h = height else { return nil }
        // The formula box's ⅓ may be read as 1 and 3.
        guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) || [1, 3].contains($0) }) else { return nil }
        if edge == nil { edge = (h * h + half * half).squareRoot() }
        let asked = every(#"\b(?:work out|find|calculate|what is) the (volume|(?:total )?surface area|height|length of ((?-i:[A-Z]{2})))\b"#, in: text).last
        guard let asked else { return nil }
        let what = asked[1].lowercased()
        if what == "volume" {
            lead.append(Step("Volume", "⅓ × area of the base × height.", [MathLine(.symbol("⅓ × \(shown(side))² × \(shown((h * 100).rounded() / 100))"))]))
            guard let r = asAsked(side * side * h / 3, text) else { return nil }
            return told("volume", [MathLine(amount(r.value), suffix: "\(unit)³")], lead)
        }
        if what.hasSuffix("surface area") {
            let slant = (h * h + side * side / 4).squareRoot()
            lead.append(Step("Height of each triangle", "From the top to the middle of a side of the base (Pythagoras).", [MathLine(.symbol("√(\(shown(tidy(h)))² + \(shown(tidy(side / 2)))²)"), amount((slant * 1000).rounded() / 1000), relation: "≈", suffix: unit)]))
            lead.append(Step("Surface area", "The square base and four triangles.", [MathLine(.symbol("\(shown(side))² + 4 × ½ × \(shown(side)) × \(shown((slant * 1000).rounded() / 1000))"))]))
            guard let r = asAsked(side * side + 2 * side * slant, text) else { return nil }
            return told("surface area", [MathLine(amount(r.value), suffix: "\(unit)²")], lead)
        }
        if what == "height" { guard let r = asAsked(h, text) else { return nil }; return told("height", [MathLine(amount(r.value), suffix: unit)], lead) }
        // A sloping edge: from the top to a corner of the base.
        let apex = groups(#"\b((?-i:[A-Z])) ?is vertically above\b"#, in: text)?[1] ?? groups(#"\bthe vertex ((?-i:[A-Z])) is\b"#, in: text)?[1]
            ?? groups(#"\b((?-i:[A-Z]))(?-i:[A-Z]{4}) is a (?:square[- ]based )?pyramid\b"#, in: text)?[1]
        guard let apex, asked[2].contains(apex), let r = asAsked(edge!, text) else { return nil }
        return told(asked[2], [MathLine(.symbol(asked[2]), amount(r.value), relation: r.relation, suffix: unit)], lead)
    }

    /// Similar solids: "Two prisms, A and B, are mathematically similar. The ratio of the volume of prism A to the volume of
    /// prism B is 8 : 27. The height of prism A is 6 cm. Work out the height of prism B." or "Pyramid A has surface area
    /// 12 cm² and volume 8 cm³. Pyramid B has surface area 75 cm². Work out the volume of pyramid B."
    private static func similarSolids(_ text: String) -> Problem? {
        let solid = #"(?:prisms?|pyramids?|solids?|cylinders?|cones?|cuboids?|cubes?|spheres?|shapes?|bottles?|containers?|statues?|models?|vases?|jugs?|tins?|boxes?|objects?)"#
        guard let pair = groups(#"\b\#(solid),? ((?-i:[A-Z])),? and ((?-i:[A-Z])),? are (?:mathematically )?similar\b"#, in: text)
                ?? groups(#"\b((?-i:[A-Z])) and ((?-i:[A-Z])) are (?:mathematically )?similar\b"#, in: text) else { return nil }
        let a = pair[1], b = pair[2]
        guard a != b else { return nil }
        func power(_ what: String) -> Double? {
            let w = what.lowercased()
            if w.hasPrefix("volume") || w.hasPrefix("capacity") { return 3 }
            if w.contains("area") { return 2 }
            if ["height", "length", "width", "radius", "diameter", "perimeter", "base"].contains(where: { w.hasPrefix($0) }) { return 1 }
            return nil
        }
        // What each is known to have, by measure.
        var facts: [String: [String: (value: Double, unit: String)]] = [a: [:], b: [:]]
        var ratios: [(what: String, first: String, x: Double, y: Double)] = []
        var used: [Double] = []
        let measure = #"(volume|capacity|(?:total )?surface area|area of (?:the )?(?:cross[- ]section|base)|height|length|width|radius|diameter|perimeter)"#
        for f in every(#"\bratio of the \#(measure) of (?:\#(solid) )?((?-i:[A-Z])) to the \#(measure) of (?:\#(solid) )?((?-i:[A-Z])) is (\#(number)) ?: ?(\#(number))"#, in: text) {
            guard f[1].lowercased() == f[3].lowercased(), let x = Double(f[5]), let y = Double(f[6]), x > 0, y > 0 else { return nil }
            ratios.append((f[1], f[2], x, y)); used += [x, y]
        }
        for f in every(#"\b\#(measure) of (?:\#(solid) )?((?-i:[A-Z])) ?: ?\#(measure) of (?:\#(solid) )?((?-i:[A-Z])) ?= ?(\#(number)) ?: ?(\#(number))"#, in: text) {
            guard f[1].lowercased() == f[3].lowercased(), let x = Double(f[5]), let y = Double(f[6]), x > 0, y > 0 else { return nil }
            ratios.append((f[1], f[2], x, y)); used += [x, y]
        }
        for f in every(#"\b(?:\#(solid) )?((?-i:[A-Z])) has (?:a )?\#(measure) (?:of )?(\#(number)) ?(mm|cm|m)? ?\^?([23])?(?: and (?:a )?\#(measure) (?:of )?(\#(number)) ?(mm|cm|m)? ?\^?([23])?)?"#, in: text) {
            guard facts[f[1]] != nil, let v = Double(f[3]) else { continue }
            facts[f[1]]![f[2].lowercased()] = (v, f[4]); used.append(v)
            if !f[6].isEmpty, let w = Double(f[7]) { facts[f[1]]![f[6].lowercased()] = (w, f[8]); used.append(w) }
        }
        for f in every(#"\bthe \#(measure) of (?:\#(solid) )?((?-i:[A-Z])) is (\#(number)) ?(mm|cm|m)?\b"#, in: text) {
            guard facts[f[2]] != nil, let v = Double(f[3]) else { continue }
            facts[f[2]]![f[1].lowercased()] = (v, f[4]); used.append(v)
        }
        guard let ask = every(#"\b(?:work out|find|calculate) the \#(measure) of (?:\#(solid) )?((?-i:[A-Z]))\b"#, in: text).last,
              facts[ask[2]] != nil, facts[ask[2]]![ask[1].lowercased()] == nil, let p = power(ask[1]) else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        // The length scale factor from A to B, from a ratio or from a measure both have.
        var k: Double?
        var lead: [Step] = []
        func setScale(_ value: Double, _ how: String, _ line: MathLine) -> Bool {
            if let k { return abs(k - value) < 1e-6 * k }
            k = value
            lead.append(Step("Length scale factor from \(a) to \(b)", how, [line]))
            return true
        }
        for r in ratios {
            guard let q = power(r.what) else { return nil }
            let ratio = r.first == a ? r.y / r.x : r.x / r.y
            let root = q == 1 ? "" : q == 2 ? "√" : "∛"
            guard setScale(pow(ratio, 1 / q), "The \(r.what.lowercased())s are in the ratio \(shown(r.x)) : \(shown(r.y)); take the \(q == 1 ? "ratio as it is" : q == 2 ? "square root" : "cube root").",
                           MathLine(.symbol("\(root)(\(shown(r.first == a ? r.y : r.x))/\(shown(r.first == a ? r.x : r.y)))"))) else { return nil }
        }
        for (what, va) in facts[a]! {
            guard let vb = facts[b]![what], let q = power(what) else { continue }
            guard setScale(pow(vb.value / va.value, 1 / q), "Both have a \(what): \(shown(va.value)) and \(shown(vb.value)).",
                           MathLine(.symbol("\(q == 1 ? "" : q == 2 ? "√" : "∛")(\(shown(vb.value)) ÷ \(shown(va.value)))"), amount(tidy(pow(vb.value / va.value, 1 / q))), relation: "≈")) else { return nil }
        }
        let other = ask[2] == a ? b : a
        guard let scale = k, let known = facts[other]![ask[1].lowercased()] else { return nil }
        let factor = ask[2] == b ? pow(scale, p) : pow(1 / scale, p)
        let value = known.value * factor
        lead.append(Step("The \(ask[1].lowercased()) of \(ask[2])", "\(p == 1 ? "Lengths go" : p == 2 ? "Areas go" : "Volumes go") up by the \(p == 1 ? "scale factor" : p == 2 ? "square of the scale factor" : "cube of the scale factor").",
                         [MathLine(.symbol("\(shown(known.value)) × \(shown(tidy(factor)))"))]))
        guard let r = asAsked(value, text) else { return nil }
        let unit = known.unit.isEmpty ? "" : known.unit + (p == 2 ? "²" : p == 3 ? "³" : "")
        return told("\(ask[1].lowercased()) of \(ask[2])", [MathLine(amount(r.value), suffix: unit.isEmpty ? nil : unit)], lead)
    }

    /// "A cube is placed on top of a cuboid. The cube has edges of length 4 cm. The cuboid has dimensions 7 cm by 6 cm by
    /// 5 cm. Work out the total surface area of the solid."
    private static func cubeOnCuboid(_ text: String) -> Problem? {
        guard has(#"\ba cube is placed on (?:top of )?a cuboid\b"#, text),
              let cube = groups(#"\bthe cube has (?:edges|sides) of length (\#(number)) ?(mm|cm|m)\b"#, in: text),
              let box = groups(#"\bthe cuboid has dimensions (\#(number)) ?(mm|cm|m) by (\#(number)) ?(?:mm|cm|m) by (\#(number)) ?(?:mm|cm|m)\b"#, in: text),
              has(#"\b(?:work out|find|calculate) the total surface area\b"#, text),
              box.count == 5, let e = Double(cube[1]), let x = Double(box[1]), let y = Double(box[3]), let z = Double(box[4]), cube[2] == box[2] else { return nil }
        // The cube must fit on some face of the cuboid; then its bottom face covers part of that face.
        guard [x, y, z].sorted().suffix(2).allSatisfy({ $0 >= e }), numbers(withoutNumbering(text)).allSatisfy({ [e, x, y, z].contains($0) }) else { return nil }
        let cuboid = 2 * (x * y + y * z + x * z), added = 4 * e * e
        let lead = [
            Step("The cuboid", "Six rectangles: 2 × (\(shown(x)) × \(shown(y)) + \(shown(y)) × \(shown(z)) + \(shown(x)) × \(shown(z))).", [MathLine(amount(cuboid), suffix: "\(cube[2])²")]),
            Step("The cube", "Its top covers as much as its bottom hides, so only its four sides are added.", [MathLine(.symbol("4 × \(shown(e))²"), amount(added))]),
        ]
        return told("total surface area", [MathLine(amount(cuboid + added), suffix: "\(cube[2])²")], lead)
    }

    /// A length of a solid: a number, or a number of times a letter ("2R", "r").
    private struct Term { var k: Double; var letter: String? }

    private static let solidNames = #"(cube|cuboid|sphere|hemisphere|cylinder|cone|square[- ]based pyramid|pyramid|triangular prism|prism)"#

    /// The volume as a number times a letter to a power, from what's known of each length: (coefficient, power, letter).
    private static func volumeOf(_ kind: String, _ d: [String: Term]) -> (Double, Int, String?)? {
        let parts: [Term]
        var front = 1.0
        switch kind {
        case "cube": guard let s = d["side"] else { return nil }; parts = [s, s, s]
        case "cuboid": guard let a = d["a"], let b = d["b"], let c = d["c"] else { return nil }; parts = [a, b, c]
        case "sphere": guard let r = d["radius"] else { return nil }; parts = [r, r, r]; front = 4 * .pi / 3
        case "hemisphere": guard let r = d["radius"] else { return nil }; parts = [r, r, r]; front = 2 * .pi / 3
        case "cylinder": guard let r = d["radius"], let h = d["height"] else { return nil }; parts = [r, r, h]; front = .pi
        case "cone": guard let r = d["radius"], let h = d["height"] else { return nil }; parts = [r, r, h]; front = .pi / 3
        case "pyramid": guard let s = d["side"], let h = d["height"] else { return nil }; parts = [s, s, h]; front = 1.0 / 3
        case "prism": guard let b = d["base"], let h = d["height"], let l = d["length"] else { return nil }; parts = [b, h, l]; front = 0.5
        default: return nil
        }
        let letters = Set(parts.compactMap(\.letter))
        guard letters.count <= 1 else { return nil }
        return (parts.reduce(front) { $0 * $1.k }, parts.filter { $0.letter != nil }.count, letters.first)
    }

    /// The total surface area at a value of the letter (or with numbers only).
    private static func surfaceOf(_ kind: String, _ d: [String: Term], at t: Double) -> Double? {
        func v(_ name: String) -> Double? { d[name].map { $0.k * ($0.letter == nil ? 1 : t) } }
        switch kind {
        case "cube": guard let s = v("side") else { return nil }; return 6 * s * s
        case "cuboid": guard let a = v("a"), let b = v("b"), let c = v("c") else { return nil }; return 2 * (a * b + b * c + a * c)
        case "sphere": guard let r = v("radius") else { return nil }; return 4 * .pi * r * r
        case "hemisphere": guard let r = v("radius") else { return nil }; return 3 * .pi * r * r
        case "cylinder": guard let r = v("radius"), let h = v("height") else { return nil }; return 2 * .pi * r * r + 2 * .pi * r * h
        case "cone": guard let r = v("radius"), let h = v("height") else { return nil }; return .pi * r * r + .pi * r * (r * r + h * h).squareRoot()
        case "pyramid": guard let s = v("side"), let h = v("height") else { return nil }; return s * s + 2 * s * (h * h + s * s / 4).squareRoot()
        default: return nil
        }
    }

    /// One or two solids described in words, with one length unknown (a letter, or a solid with no size given) found from
    /// one fact: the same volume as the other solid, a volume or surface area given, or a cube's diagonal. "A cuboid
    /// measures 6 cm by 8 cm by 15 cm. A cube has the same volume as the cuboid. Find the surface area of the cube."
    /// "A cone has radius r cm and height h cm. The height is three times the radius. The volume of the cone is 2100 cm³.
    /// Calculate the radius of the cone." With two letters, one in terms of the other: "A sphere has radius x cm. A cone
    /// has radius R cm and height 2R cm. … Write R in terms of x."
    private static func oneUnknownSolid(_ text: String) -> Problem? {
        let words = withoutFormulae(text).replacingOccurrences(of: #"\[(?:the )?(?:volume|surface area|curved surface area)[^\]]*\]?"#, with: " ", options: [.regularExpression, .caseInsensitive])
        // Each kind of solid and the words about it: from each mention to the next mention of another kind.
        guard let regex = try? NSRegularExpression(pattern: #"\b\#(solidNames)s?\b"#, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: words, range: NSRange(words.startIndex..., in: words))
        guard !matches.isEmpty, !has(#"\bsimilar\b|\bdensity\b|\bmass\b|\bjoined\b|\bon top of\b|\bplaced\b|\bremoved\b|\bcut\b|\bfrustum\b|\bhollow\b"#, words) else { return nil }
        var clauses: [String: String] = [:], order: [String] = []
        for (i, m) in matches.enumerated() {
            var kind = (Range(m.range(at: 1), in: words).map { String(words[$0]) } ?? "").lowercased()
            if kind.hasSuffix("pyramid") { kind = "pyramid" }
            if kind.hasSuffix("prism") { kind = "prism" }
            let end = i + 1 < matches.count ? matches[i + 1].range.location : (words as NSString).length
            let piece = (words as NSString).substring(with: NSRange(location: m.range.location, length: end - m.range.location))
            if clauses[kind] == nil { order.append(kind) }
            clauses[kind, default: ""] += " " + piece
        }
        guard (1...2).contains(order.count) else { return nil }
        let value = #"(?:(\d+(?:\.\d+)?) ?(mm|cm|m)\b(?!\^)|(\d*(?:\.\d+)?) ?((?-i:[a-zA-Z]))(?: ?(?:mm|cm|m))?\b(?!\^))"#
        var used: [Double] = []
        var unit: String?
        func term(_ f: [String], _ at: Int) -> Term? {
            if !f[at].isEmpty, let v = Double(f[at]) { used.append(v); if let u = unit, u != f[at + 1] { return nil }; unit = f[at + 1]; return Term(k: v, letter: nil) }
            if !f[at + 3].isEmpty { let k = f[at + 2].isEmpty ? 1 : Double(f[at + 2]) ?? 0; if !f[at + 2].isEmpty { used.append(k) }; return k > 0 ? Term(k: k, letter: f[at + 3]) : nil }
            return nil
        }
        var dims: [String: [String: Term]] = [:]
        for kind in order {
            let c = clauses[kind]!
            var d: [String: Term] = [:]
            if let f = groups(#"\bradius (?:of )?\#(value)"#, in: c) { guard let t = term(f, 1) else { return nil }; d["radius"] = t }
            if let f = groups(#"\bdiameter (?:of )?\#(value)"#, in: c) { guard let t = term(f, 1) else { return nil }; d["radius"] = Term(k: t.k / 2, letter: t.letter) }
            if let f = groups(#"\b(?:perpendicular )?height (?:of )?\#(value)"#, in: c) { guard let t = term(f, 1) else { return nil }; d["height"] = t }
            if let f = groups(#"\b(?:side length|base length|edge length|sides? of length|edges? of length|side|edge) (?:of )?\#(value)"#, in: c) { guard let t = term(f, 1) else { return nil }; d["side"] = t }
            if let f = groups(#"\bmeasur(?:es|ing) (\#(number)) ?(mm|cm|m) by (\#(number)) ?(?:mm|cm|m) by (\#(number)) ?(?:mm|cm|m)\b"#, in: c),
               let a = Double(f[1]), let b = Double(f[3]), let e = Double(f[4]) {
                d["a"] = Term(k: a, letter: nil); d["b"] = Term(k: b, letter: nil); d["c"] = Term(k: e, letter: nil); used += [a, b, e]; unit = f[2]
            }
            if kind == "prism" {
                guard has(#"\bright[- ]angled triangles?\b"#, c), let f = groups(#"\bbase (\#(number)) ?(mm|cm|m) and height (\#(number)) ?(?:mm|cm|m)\b"#, in: c),
                      let l = groups(#"\bprism is (\#(number)) ?(?:mm|cm|m) long\b|\blength (?:of the prism )?(?:is )?(\#(number)) ?(?:mm|cm|m)\b"#, in: c),
                      let b = Double(f[1]), let h = Double(f[3]), let len = Double(l[1].isEmpty ? l[2] : l[1]) else { return nil }
                d = ["base": Term(k: b, letter: nil), "height": Term(k: h, letter: nil), "length": Term(k: len, letter: nil)]
                used += [b, h, len]; unit = f[2]
            }
            // A solid with no size given has its size unknown.
            if d.isEmpty, ["cube", "sphere", "hemisphere"].contains(kind) { d[kind == "cube" ? "side" : "radius"] = Term(k: 1, letter: "·") }
            dims[kind] = d
        }
        // The height as a number of times the radius.
        for kind in order where ["cone", "cylinder"].contains(kind) {
            let c = clauses[kind]!
            guard let r = dims[kind]?["radius"], let rl = r.letter else { continue }
            if let f = groups(#"\bheight is (twice|two|three|four|five|\d+(?:\.\d+)?) times the radius\b"#, in: c), let k = f[1].lowercased() == "twice" ? 2 : count(f[1]) {
                dims[kind]!["height"] = Term(k: k * r.k, letter: rl); if Double(f[1]) != nil { used.append(k) }
            } else if let f = groups("\\bratio \(rl) ?: ?((?-i:[a-z])) is (\(number)) ?: ?(\(number))", in: c) ?? groups("\\bratio \(rl) ?: ?((?-i:[a-z])) is (\(number)) ?: ?(\(number))", in: words),
                      dims[kind]?["height"]?.letter == f[1], let p = Double(f[2]), let q = Double(f[3]), p > 0 {
                dims[kind]!["height"] = Term(k: r.k * q / p, letter: rl); used += [p, q]
            }
        }
        let letters = Set(dims.values.flatMap { $0.values.compactMap(\.letter) })
        let volumes = order.map { volumeOf($0, dims[$0]!) }
        guard volumes.allSatisfy({ $0 != nil }) || order.count == 1 else { return nil }
        let unitText = unit ?? "cm"
        var lead: [Step] = []
        func formula(_ kind: String) -> String {
            ["cube": "side³", "cuboid": "length × width × height", "sphere": "4/3 × π × r³", "hemisphere": "2/3 × π × r³", "cylinder": "π × r² × h",
             "cone": "1/3 × π × r² × h", "pyramid": "1/3 × base² × height", "prism": "½ × base × height × length"][kind] ?? ""
        }
        // A ratio of the two solids' surface areas or volumes, both in the same letter: "total surface area of the
        // hemisphere : total surface area of the cylinder".
        if order.count == 2, letters.count == 1, letters.first != "·",
           let ratio = groups(#"\b((?:total )?surface area|volume) of the \#(solidNames) ?: ?(?:the )?((?:total )?surface area|volume) of the \#(solidNames)\b"#, in: words),
           ratio[1].lowercased() == ratio[3].lowercased() {
            func kindOf(_ name: String) -> String { let n = name.lowercased(); return n.hasSuffix("pyramid") ? "pyramid" : n.hasSuffix("prism") ? "prism" : n }
            let first = kindOf(ratio[2]), second = kindOf(ratio[4])
            guard first != second, let d1 = dims[first], let d2 = dims[second] else { return nil }
            let isVolume = ratio[1].lowercased() == "volume"
            let x: Double?, y: Double?
            if isVolume { x = volumeOf(first, d1)?.0; y = volumeOf(second, d2)?.0 } else { x = surfaceOf(first, d1, at: 1); y = surfaceOf(second, d2, at: 1) }
            let formulae: [Double] = has(#"\bV ?=|[1-4] ?/ ?3|\b(?:volume|surface area) of an? [a-z]+ (?:is|=)"#, words) ? [1, 2, 3, 4] : []
            guard let x, let y, x > 0, y > 0, numbers(withoutNumbering(words)).allSatisfy({ used.contains($0) || formulae.contains($0) }),
                  let simple = wholeRatio([x, y]), simple.allSatisfy({ $0 <= 1000 }) else { return nil }
            let what = ratio[1].lowercased()
            let lead = [
                Step("The \(first)", what.contains("surface") ? (first == "hemisphere" ? "Curved half of a sphere, 2πr², and the flat circle, πr²." : "Every face.") : formula(first) + ".", [MathLine(.symbol("\(shown(tidy(x / .pi)))π\(letters.first!)\(isVolume ? "³" : "²")"))]),
                Step("The \(second)", what.contains("surface") ? (second == "cylinder" ? "Two circles, 2πr², and the curved side, 2πrh." : "Every face.") : formula(second) + ".", [MathLine(.symbol("\(shown(tidy(y / .pi)))π\(letters.first!)\(isVolume ? "³" : "²")"))]),
                Step("Simplify", "π and \(letters.first!)\(isVolume ? "³" : "²") cancel.", []),
            ]
            return told("\(what) ratio", [MathLine(.symbol("\(simple[0]) : \(simple[1])"))], lead)
        }
        // What fixes the unknown.
        var t: Double?
        if order.count == 2, has(#"\bsame volume\b|\bvolume of the [a-z ]+ is equal to the volume of the\b|\bvolumes? (?:are|is) (?:the same|equal)\b"#, words),
           let v0 = volumes[0], let v1 = volumes[1] {
            if v0.1 == 0, v1.1 > 0 { t = pow(v0.0 / v1.0, 1 / Double(v1.1)); lead.append(Step("Volume of the \(order[0])", formula(order[0]) + ".", [MathLine(amount(tidy((v0.0 * 1000).rounded() / 1000)), relation: "≈", suffix: "\(unitText)³")])) }
            else if v1.1 == 0, v0.1 > 0 { t = pow(v1.0 / v0.0, 1 / Double(v0.1)); lead.append(Step("Volume of the \(order[1])", formula(order[1]) + ".", [MathLine(amount(tidy((v1.0 * 1000).rounded() / 1000)), relation: "≈", suffix: "\(unitText)³")])) }
            else if v0.1 == 3, v1.1 == 3, let a = v0.2, let b = v1.2, a != b, a != "·", b != "·",
                    let asked = groups(#"\b(?:write|express|find|work out) ((?-i:[a-zA-Z])) in terms of ((?-i:[a-zA-Z]))\b"#, in: words), Set([asked[1], asked[2]]) == Set([a, b]) {
                // c0·a³ = c1·b³: the asked letter as a number times the other.
                let (cAsked, cOther) = asked[1] == a ? (v0.0, v1.0) : (v1.0, v0.0)
                let cube = cOther / cAsked
                guard numbers(withoutNumbering(words)).allSatisfy({ used.contains($0) }) else { return nil }
                let rootText: String
                let nearest = cube.rounded()
                if abs(pow(cube, 1.0 / 3).rounded() - pow(cube, 1.0 / 3)) < 1e-9 { rootText = shown(pow(cube, 1.0 / 3).rounded()) == "1" ? "" : shown(pow(cube, 1.0 / 3).rounded()) }
                else if abs(cube - nearest) < 1e-9 { rootText = "∛\(shown(nearest))" }
                else if let f = whole(cube, 1) { rootText = "∛(\(f.0)/\(f.1))" } else { return nil }
                lead = [Step("Make the volumes equal", "\(formula(order[0])) for the \(order[0]), \(formula(order[1])) for the \(order[1]). The π cancels.", []),
                        Step("Find \(asked[1])", "\(asked[1])³ = \(shown(tidy(cube)))\(asked[2])³, so take the cube root.", [])]
                return told(asked[1], [MathLine(.symbol(asked[1]), .symbol("\(rootText)\(asked[2])"))], lead)
            }
        } else if order.count == 1, let v = volumes[0], v.1 > 0 {
            let kind = order[0]
            if let f = groups("\\bvolume of the \(kind) is (\(number)) ?(mm|cm|m) ?(?:\\^?3|\\?)", in: words), let given = Double(f[1]) {
                t = pow(given / v.0, 1 / Double(v.1)); used.append(given); unit = unit ?? f[2]
                lead.append(Step("Write the volume", formula(kind) + ", with what's known put in.", [MathLine(.symbol("\(shown(tidy((v.0 * 1000).rounded() / 1000)))\(v.2 ?? "")\(v.1 == 3 ? "³" : v.1 == 2 ? "²" : "")"), amount(given))]))
            } else if let f = groups("\\b(?:total )?surface area of (?:the|a|this) \(kind) is (\(number)) ?(mm|cm|m) ?\\^?2|\\b\(kind) has a (?:total )?surface area of (\(number)) ?(mm|cm|m) ?\\^?2", in: words),
                      let given = Double(f[1].isEmpty ? f[3] : f[1]), let s1 = surfaceOf(kind, dims[kind]!, at: 1), s1 > 0 {
                t = (given / s1).squareRoot(); used.append(given); unit = unit ?? (f[2].isEmpty ? f[4] : f[2])
                lead.append(Step("From the surface area", kind == "cube" ? "Six square faces: each is \(shown(given)) ÷ 6." : "Write the surface area with what's known put in.", []))
            } else if kind == "cube", let f = groups(#"\blongest diagonal of (?:a|the) cube is (\#(number)) ?(mm|cm|m)\b"#, in: words), let given = Double(f[1]) {
                t = given / 3.squareRoot(); used.append(given); unit = f[2]
                lead.append(Step("The cube's side", "The longest diagonal is √3 times the side (Pythagoras twice).", [MathLine(.symbol("side"), .symbol("\(shown(given)) ÷ √3"))]))
            }
        }
        // A formula box (⅓, 4/3, powers) may be read as numbers.
        let formulae: [Double] = has(#"\bV ?=|[1-4] ?/ ?3|\bvolume of an? [a-z]+ (?:is|=)"#, words) ? [1, 2, 3, 4] : []
        guard let t, t.isFinite, t > 0, letters.count == 1, numbers(withoutNumbering(words)).allSatisfy({ used.contains($0) || formulae.contains($0) }) else { return nil }
        let unitAll = unit ?? unitText
        // The solid with the unknown, and what's asked of it.
        guard let target = order.first(where: { dims[$0]!.values.contains { $0.letter != nil } }) else { return nil }
        let d = dims[target]!
        if let f = groups("\\b(?:work out|find|calculate) the (?:total )?surface area of the \(target)\\b", in: words), f.count > 0, let sa = surfaceOf(target, d, at: t) {
            lead.append(Step("Surface area of the \(target)", target == "cube" ? "Six squares, each side \(shown(tidy((t * 1000).rounded() / 1000)))." : "", []))
            guard let r = asAsked(sa, text) else { return nil }
            return told("surface area", [MathLine(amount(r.value), suffix: "\(unitAll)²")], lead)
        }
        if has("\\b(?:work out|find|calculate) the volume of the \(target)\\b", words), let v = volumeOf(target, d) {
            guard let r = asAsked(v.0 * pow(t, Double(v.1)), text) else { return nil }
            return told("volume", [MathLine(amount(r.value), suffix: "\(unitAll)³")], lead)
        }
        for (name, term) in d where term.letter != nil {
            let spoken = ["side": "(?:side|side length|length of (?:a|each|one) side|edge)", "radius": "radius", "height": "(?:perpendicular )?height", "base": "base"][name] ?? name
            let letter = term.letter!
            if has("\\b(?:work out|find|calculate) the \(spoken) of the \(target)\\b", words) || (letter != "·" && has("\\b(?:work out|find|calculate) (?:the value of )?\(letter)\\b", words) && term.k == 1) {
                guard let r = asAsked(term.k * t, text) else { return nil }
                return told(name, [MathLine(.symbol(letter == "·" ? name : letter), amount(r.value), relation: r.relation, suffix: unitAll)], lead)
            }
        }
        return nil
    }

    /// Whole numbers in the same ratio as some decimals, simplest form: 4, 5 and 5/3 as 12 : 15 : 5.
    private static func wholeRatio(_ values: [Double]) -> [Int]? {
        guard let smallest = values.min(), smallest > 0 else { return nil }
        for scale in 1...1000 {
            let scaled = values.map { $0 / smallest * Double(scale) }
            if scaled.allSatisfy({ abs($0 - $0.rounded()) < 1e-6 }) {
                let ints = scaled.map { Int($0.rounded()) }
                let g = ints.reduce(0) { gcd($0, $1) }
                return ints.map { $0 / g }
            }
        }
        return nil
    }

    /// "L, M and P are three similar solid cylinders made from the same material. L has a mass of 64 g. M has a mass of
    /// 125 g. M has a total surface area of 144 cm². P has a total surface area of 16 cm². Work out height of cylinder L :
    /// height of cylinder M : height of cylinder P"
    private static func similarThree(_ text: String) -> Problem? {
        guard let names = groups(#"\b((?-i:[A-Z])), ((?-i:[A-Z])) and ((?-i:[A-Z])) are (?:three )?(?:mathematically )?similar\b"#, in: text) else { return nil }
        let solids = [names[1], names[2], names[3]]
        let sameStuff = has(#"\bsame material\b|\bsame metal\b|\bsame density\b"#, text)
        var facts: [(name: String, power: Double, value: Double, what: String)] = []
        var used: [Double] = []
        for f in every(#"\b((?-i:[A-Z])) has (?:a )?(mass|volume|(?:total )?surface area|height|length|radius) of (\#(number))"#, in: text) {
            guard solids.contains(f[1]), let v = Double(f[3]), v > 0 else { continue }
            let w = f[2].lowercased()
            let p: Double = w == "mass" ? (sameStuff ? 3 : 0) : w == "volume" ? 3 : w.contains("area") ? 2 : 1
            guard p > 0 else { return nil }
            facts.append((f[1], p, v, w)); used.append(v)
        }
        guard let ask = groups(#"\b(height|length|radius|diameter|width) of (?:cylinder |cone |prism |solid |shape )?((?-i:[A-Z])) ?: ?\1 of (?:cylinder |cone |prism |solid |shape )?((?-i:[A-Z])) ?: ?\1 of (?:cylinder |cone |prism |solid |shape )?((?-i:[A-Z]))\b"#, in: text),
              Set([ask[2], ask[3], ask[4]]) == Set(solids), numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        // Length of each relative to the first named, from pairs with the same measure.
        var length: [String: Double] = [solids[0]: 1]
        var lead: [Step] = []
        for _ in 0..<3 {
            for a in facts {
                for b in facts where b.what == a.what && b.name != a.name {
                    guard let la = length[a.name], length[b.name] == nil else { continue }
                    let k = pow(b.value / a.value, 1 / a.power)
                    length[b.name] = la * k
                    lead.append(Step("\(a.name) and \(b.name)", "Their \(a.what)s are \(shown(a.value)) and \(shown(b.value)): the lengths are in the ratio of the \(a.power == 3 ? "cube" : a.power == 2 ? "square" : "") roots.", [MathLine(.symbol("\(a.power == 3 ? "∛" : a.power == 2 ? "√" : "")\(shown(a.value)) : \(a.power == 3 ? "∛" : a.power == 2 ? "√" : "")\(shown(b.value))"), .symbol("\(shown(tidy(pow(a.value, 1 / a.power)))) : \(shown(tidy(pow(b.value, 1 / a.power))))"))]))
                }
            }
        }
        guard length.count == 3, let ratio = wholeRatio([ask[2], ask[3], ask[4]].map { length[$0]! }) else { return nil }
        lead.append(Step("Put them together", "Scale so the shared one matches, then use whole numbers.", []))
        return told("\(ask[1]) ratio", [MathLine(.symbol(ratio.map(String.init).joined(separator: " : ")))], lead)
    }

    /// "A town has a population density of 278 people per km² and a population of 158 460. The population increases to
    /// 168 720. Work out the population density after the increase."
    private static func populationDensity(_ text: String) -> Problem? {
        guard let density = groups(#"\bpopulation density of (\#(big)) people per (km|square kilometre|mile|square mile|m) ?\^?2?"#, in: text),
              let people = groups(#"\ba population of (\#(big))(?![\d.])"#, in: text),
              let d = bigValue(density[1]), let n = bigValue(people[1]), d > 0 else { return nil }
        let area = n / d
        var used = [d, n]
        var lead = [Step("The area", "Population ÷ population density.", [MathLine(.symbol("\(shown(n)) ÷ \(shown(d))"), amount(tidy(area)))])]
        let unit = density[2].lowercased().hasPrefix("k") ? "km²" : density[2].lowercased().contains("mile") ? "square miles" : "m²"
        if let grown = groups(#"\bpopulation (?:increases|decreases|rises|falls|grows|changes) to (\#(big))(?![\d.])"#, in: text), let m = bigValue(grown[1]),
           has(#"\b(?:work out|find|calculate) the (?:new )?population density\b"#, text) {
            used.append(m)
            let rest = withoutNumbering(text).replacingOccurrences(of: #"(?<=\d)[ ,](?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
            guard numbers(rest).allSatisfy({ used.contains($0) }), let r = asAsked(m / area, text) else { return nil }
            lead.append(Step("The new density", "The area stays the same.", [MathLine(.symbol("\(shown(m)) ÷ \(shown(tidy(area)))"))]))
            return told("population density", [MathLine(amount(r.value), suffix: "people per \(unit)")], lead)
        }
        guard has(#"\b(?:work out|find|calculate) the area\b"#, text), let r = asAsked(area, text) else { return nil }
        return told("area", [MathLine(amount(r.value), suffix: unit)], lead)
    }

    /// "Part of a running track is the arc of a semicircle joined to a straight line. The semicircle has diameter 45 metres.
    /// The straight line has length 75 metres. Abby runs once along this part of the track in 18 seconds. Work out her
    /// average speed."
    private static func trackSpeed(_ text: String) -> Problem? {
        guard has(#"\barc of a semicircle joined to a straight line\b|\bsemicircle and a straight line\b"#, text),
              let d = groups(#"\bsemicircle has (radius|diameter) (\#(number)) ?(m|metres|km)\b"#, in: text),
              let line = groups(#"\bstraight line has length (\#(number)) ?(m|metres|km)\b"#, in: text),
              let time = groups(#"\bin (\#(number)) ?(seconds|s|minutes|hours)\b"#, in: text),
              has(#"\b(?:work out|find|calculate) (?:her|his|their|the) average speed\b"#, text),
              let size = Double(d[2]), let l = Double(line[1]), let t = Double(time[1]), t > 0, short(d[3]) == short(line[2]),
              numbers(withoutNumbering(text)).allSatisfy({ [size, l, t].contains($0) }) else { return nil }
        let r = d[1].lowercased() == "radius" ? size : size / 2
        let distance = Double.pi * r + l
        let per = time[2].lowercased().hasPrefix("s") ? "s" : time[2].lowercased().hasPrefix("m") ? "min" : "h"
        let lead = [
            Step("The distance", "Half the circumference of the circle, and the straight line.", [MathLine(.symbol("π × \(shown(2 * r)) ÷ 2 + \(shown(l))"), amount((distance * 1000).rounded() / 1000), relation: "≈", suffix: short(d[3]))]),
            Step("Average speed", "Distance ÷ time.", [MathLine(.symbol("\(shown((distance * 1000).rounded() / 1000)) ÷ \(shown(t))"))]),
        ]
        guard let rounding = asAsked(distance / t, text) else { return nil }
        return told("average speed", [MathLine(amount(rounding.value), suffix: "\(short(d[3]))/\(per)")], lead)
    }

    /// "Jeremy has to cover 3 tanks completely with paint. Each tank is in the shape of a cylinder with a top and a bottom.
    /// The tank has a diameter of 1.6 m and a height of 1.8 m. Jeremy has 7 tins of paint. Each tin of paint covers 5 m².
    /// Has Jeremy got enough paint?"
    private static func paintCylinders(_ text: String) -> Problem? {
        guard let many = groups(#"\bcover (\d+|two|three|four|five|six) (?:tanks|cylinders|drums|pillars)\b"#, in: text), let n = count(many[1]),
              has(#"\bcylinder with a top and a bottom\b|\bcylinders? (?:are|is) closed\b"#, text),
              let size = groups(#"\b(diameter|radius) of (\#(number)) ?(m|cm) and a height of (\#(number)) ?(m|cm)\b"#, in: text), size[3] == size[5],
              let tins = groups(#"\bhas (\d+) tins of paint\b"#, in: text), let each = groups(#"\beach tin (?:of paint )?covers (\#(number)) ?(m|cm) ?\^?2"#, in: text), each[2] == size[3],
              has(#"\b(?:got |have |has )?enough paint\b"#, text),
              let w = Double(size[2]), let h = Double(size[4]), let k = Double(tins[1]), let c = Double(each[1]) else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ [w, h, k, c, n].contains($0) }) else { return nil }
        let r = size[1].lowercased() == "radius" ? w : w / 2
        let one = 2 * Double.pi * r * r + 2 * Double.pi * r * h, need = n * one, have = k * c
        guard abs(need - have) > 0.05 else { return nil }
        let u = size[3]
        let lead = [
            Step("Surface of one tank", "Top and bottom (two circles) and the curved side: 2πr² + 2πrh.", [MathLine(.symbol("2π × \(shown(r))² + 2π × \(shown(r)) × \(shown(h))"), amount((one * 100).rounded() / 100), relation: "≈", suffix: "\(u)²")]),
            Step("All \(shown(n)) tanks", "", [MathLine(amount((need * 100).rounded() / 100), relation: "≈", suffix: "\(u)²")]),
            Step("The paint", "\(shown(k)) tins, each covering \(shown(c)) \(u)².", [MathLine(amount(have), suffix: "\(u)²")]),
        ]
        return told("enough paint", [MathLine(.symbol(have >= need ? "Yes: \(shown(have)) \(u)² covers \(shown((need * 10).rounded() / 10)) \(u)²" : "No: \(shown((need * 10).rounded() / 10)) \(u)² to cover, \(shown(have)) \(u)² of paint"))], lead)
    }

    /// "A paddling pool is in the shape of a cylinder. The pool has radius 100 cm. The pool has depth 30 cm. It is then
    /// filled with water at a rate of 250 cm³ per second. Work out the number of minutes it takes to fill the pool."
    private static func fillTime(_ text: String) -> Problem? {
        guard has(#"\bin the shape of a (?:cylinder|cuboid)\b"#, text), !has(#"\bhalf\b|\bfull\b|\b\d+ ?%"#, text),
              let rate = groups(#"\brate of (\#(number)) ?(cm|m) ?(?:\^?3|\?|³) per (second|minute|hour)\b"#, in: text),
              let ask = groups(#"\bthe number of (seconds|minutes|hours) it takes to fill\b"#, in: text)?[1].lowercased(),
              let q = Double(rate[1]), q > 0 else { return nil }
        var volume: Double, used = [q], lead: [Step] = []
        let u = rate[2]
        if has(#"\bcylinder\b"#, text), let r = groups(#"\bradius (?:of )?(\#(number)) ?(cm|m)\b"#, in: text), let h = groups(#"\b(?:depth|height) (?:of )?(\#(number)) ?(cm|m)\b"#, in: text),
           r[2] == u, h[2] == u, let rv = Double(r[1]), let hv = Double(h[1]) {
            volume = Double.pi * rv * rv * hv; used += [rv, hv]
            lead.append(Step("Volume of the cylinder", "π × r² × h.", [MathLine(.symbol("π × \(shown(rv))² × \(shown(hv))"), amount((volume * 10).rounded() / 10), relation: "≈", suffix: "\(u)³")]))
        } else { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let seconds: [String: Double] = ["second": 1, "minute": 60, "hour": 3600, "seconds": 1, "minutes": 60, "hours": 3600]
        let time = volume / q * seconds[rate[3].lowercased()]! / seconds[ask]!
        lead.append(Step("Time", "Volume ÷ rate, then in \(ask).", [MathLine(.symbol("\(shown((volume * 10).rounded() / 10)) ÷ \(shown(q))"))]))
        guard let rounding = asAsked(time, text) else { return nil }
        return told(ask, [MathLine(amount(rounding.value), suffix: ask)], lead)
    }

    /// "The diagram shows a solid cylinder on a horizontal floor. The cylinder has a volume of 1200 cm³ and height of 40 cm.
    /// The cylinder exerts a force of 90 newtons on the floor. Work out the pressure on the floor due to the cylinder."
    private static func pressureOfCylinder(_ text: String) -> Problem? {
        guard has(#"\bsolid (?:cylinder|cuboid|prism)\b"#, text),
              let volume = groups(#"\bvolume of (\#(number)) ?(cm|m) ?(?:\^?3|\?|³)"#, in: text), let height = groups(#"\bheight of (\#(number)) ?(cm|m)\b"#, in: text),
              let force = groups(#"\bforce of (\#(number)) ?(?:newtons?|n)\b"#, in: text),
              has(#"\b(?:work out|find|calculate) the pressure\b"#, text), volume[2] == height[2],
              let v = Double(volume[1]), let h = Double(height[1]), let f = Double(force[1]), h > 0, v > 0,
              numbers(withoutNumbering(text)).allSatisfy({ [v, h, f].contains($0) }) else { return nil }
        let area = v / h, u = volume[2]
        let lead = [
            Step("Area on the floor", "The cross-section: volume ÷ height.", [MathLine(.symbol("\(shown(v)) ÷ \(shown(h))"), amount(tidy(area)), suffix: "\(u)²")]),
            Step("Pressure", "Force ÷ area.", [MathLine(.symbol("\(shown(f)) ÷ \(shown(tidy(area)))"))]),
        ]
        guard let rounding = asAsked(f / area, text) else { return nil }
        return told("pressure", [MathLine(amount(rounding.value), suffix: "N/\(u)²")], lead)
    }

    /// "A solid frustum is made by removing a small cone from a large cone. The slant height of the small cone is 6 cm. The
    /// slant height of the large cone is 10 cm. The radius of the base of the large cone is 3 cm. Calculate the total
    /// surface area of the frustum."
    private static func frustumSurface(_ text: String) -> Problem? {
        guard has(#"\bfrustum is made by removing a small cone from a large cone\b"#, text),
              let small = groups(#"\bslant height of the small cone is (\#(number)) ?(cm|m|mm)\b"#, in: text),
              let large = groups(#"\bslant height of the large cone is (\#(number)) ?(cm|m|mm)\b"#, in: text),
              let radius = groups(#"\bradius of the (?:base of the )?large cone is (\#(number)) ?(cm|m|mm)\b"#, in: text),
              has(#"\b(?:work out|find|calculate) the (?:total )?surface area of the frustum\b"#, text),
              let l = Double(small[1]), let L = Double(large[1]), let R = Double(radius[1]), L > l, l > 0,
              numbers(withoutNumbering(text)).allSatisfy({ [l, L, R].contains($0) }) else { return nil }
        let r = R * l / L
        let curved = Double.pi * R * L - Double.pi * r * l, ends = Double.pi * R * R + Double.pi * r * r
        let u = radius[2]
        let lead = [
            Step("Radius of the small cone", "The cones are similar: \(shown(R)) × \(shown(l)) ÷ \(shown(L)).", [MathLine(amount(tidy(r)), suffix: u)]),
            Step("Curved surface", "πrl of the large cone take away πrl of the small one.", [MathLine(.symbol("π × \(shown(R)) × \(shown(L)) − π × \(shown(tidy(r))) × \(shown(l))"), .symbol("\(shown(tidy(R * L - r * l)))π"))]),
            Step("The two circles", "The base and the top.", [MathLine(.symbol("π × \(shown(R))² + π × \(shown(tidy(r)))²"), .symbol("\(shown(tidy(R * R + r * r)))π"))]),
        ]
        guard let rounding = asAsked(curved + ends, text) else { return nil }
        return told("total surface area", [MathLine(amount(rounding.value), suffix: "\(u)²")], lead)
    }

    // MARK: Round 5

    /// A fraction in its lowest terms.
    private static func lowest(_ n: Int, _ d: Int) -> (n: Int, d: Int) {
        let g = max(1, gcd(n, d))
        return d < 0 ? (-n / g, -d / g) : (n / g, d / g)
    }

    /// A decimal as a fraction: 2.5 as 5/2. Nil past four decimal places.
    private static func fraction(_ value: Double) -> (n: Int, d: Int)? {
        for scale in [1, 10, 100, 1000, 10000] {
            let x = value * Double(scale)
            if abs(x - x.rounded()) < 1e-9, abs(x) < 1e9 { return lowest(Int(x.rounded()), scale) }
        }
        return nil
    }

    /// A fraction of π as it's written: 17π/4, 9π, π/2.
    private static func piTimes(_ f: (n: Int, d: Int), _ letter: String = "π") -> String {
        "\(f.n == 1 ? "" : String(f.n))\(letter)\(f.d == 1 ? "" : "/\(f.d)")"
    }

    /// The square of a length written as a number, a fraction or a simple surd: 5, 2.5, 7/2, √17/2, (√(17))/2, 3√2.
    private static func squareOf(_ written: String) -> (n: Int, d: Int)? {
        // A fraction under the root, √(17/2), isn't one of these.
        guard !has(#"√\([^)]*/"#, written) else { return nil }
        let w = written.replacingOccurrences(of: #"[ ()]"#, with: "", options: .regularExpression)
        if let f = groups(#"^(\d*)√(\d+)(?:/(\d+))?$"#, in: w), let n = Int(f[2]), let k = f[1].isEmpty ? 1 : Int(f[1]), let d = f[3].isEmpty ? 1 : Int(f[3]),
           k > 0, n > 0, d > 0, k < 1000, n < 100_000, d < 1000 {
            return lowest(k * k * n, d * d)
        }
        if let f = groups(#"^(\d+)/(\d+)$"#, in: w), let a = Int(f[1]), let b = Int(f[2]), a > 0, b > 0, a < 10000, b < 10000 { return lowest(a * a, b * b) }
        if let v = Double(w), v > 0, let f = fraction(v), f.n < 100_000 { return lowest(f.n * f.n, f.d * f.d) }
        return nil
    }

    /// "A regular polygon has n sides. The interior angle of the polygon is 15 times its exterior angle. Find the value
    /// of n." Also the two angles as a ratio, or one a number of degrees more than the other.
    private static func polygonFromAngles(_ text: String) -> Problem? {
        guard has(#"\bregular polygon\b"#, text) else { return nil }
        let angle = #"(?:size of )?(?:each |an? |one |the )?(interior|exterior) angles?(?: of (?:the|this|a) (?:regular )?polygon)?"#
        let other = #"(?:the size of )?(?:its |the |each |an? |one of its )?(interior|exterior) angles?"#
        // The exterior angle as a share of the 180° the two make together.
        var share: Double?, used: [Double] = [], how = "", sum = ""
        if let f = groups(#"\b\#(angle) (?:is|are) (\#(number)|[a-z]+) times (?:as (?:big|large) as )?\#(other)\b"#, in: text),
           f[1].lowercased() != f[3].lowercased(), let k = count(f[2]), k > 0 {
            if Double(f[2]) != nil { used.append(k) }
            let interior = f[1].lowercased() == "interior"
            share = interior ? 1 / (k + 1) : k / (k + 1)
            how = "The \(f[1].lowercased()) angle is \(shown(k)) times the \(f[3].lowercased()) angle, so \(shown(k + 1)) lots of the \(f[3].lowercased()) angle make 180°."
            sum = interior ? "180 ÷ \(shown(k + 1))" : "180 ÷ \(shown(k + 1)) × \(shown(k))"
        } else if let f = groups(#"\b(interior|exterior) angle ?: ?(interior|exterior) angle ?(?:=|is) ?(\#(number)) ?: ?(\#(number))"#, in: text)
                    ?? groups(#"\bratio of (?:the |an? |each )?(interior|exterior) angle to (?:the |an? |each )?(interior|exterior) angle is (\#(number)) ?: ?(\#(number))"#, in: text),
                  f[1].lowercased() != f[2].lowercased(), let a = Double(f[3]), let b = Double(f[4]), a > 0, b > 0 {
            used += [a, b]
            let exteriorParts = f[1].lowercased() == "exterior" ? a : b
            share = exteriorParts / (a + b)
            how = "The two angles are in the ratio \(shown(a)) : \(shown(b)), so \(shown(a + b)) parts make 180°."
            sum = "180 ÷ \(shown(a + b)) × \(shown(exteriorParts))"
        } else if let f = groups(#"\b\#(angle) (?:is|are) (\#(number)) ?°? (more|greater|larger|bigger|less|smaller) than \#(other)\b"#, in: text),
                  f[1].lowercased() != f[4].lowercased(), let d = Double(f[2]), d > 0, d < 180 {
            used.append(d)
            // The interior angle is the larger of the two in either wording, or the question makes no sense.
            let firstIsMore = ["more", "greater", "larger", "bigger"].contains(f[3].lowercased())
            guard (f[1].lowercased() == "interior") == firstIsMore else { return nil }
            share = (180 - d) / 360
            how = "The interior angle is \(shown(d))° more than the exterior angle, so twice the exterior angle is 180° − \(shown(d))°."
            sum = "(180 − \(shown(d))) ÷ 2"
        }
        else if let f = groups(#"\b(interior|exterior) angles? (?:of (?:a|the|this) regular polygon )?(?:is|are|of) (\#(number)) ?°"#, in: text), let v = Double(f[2]), v > 0, v < 180,
                !has(#"\b(?:interior|exterior) angles?\b[^.?]*\b(?:interior|exterior) angles?\b"#, text) {
            // The size of one angle of a regular polygon: "Each interior angle of a regular polygon is 156°."
            used.append(v)
            let interior = f[1].lowercased() == "interior"
            share = (interior ? 180 - v : v) / 180
            how = interior ? "The interior and exterior angles are on a straight line, so the exterior angle is 180° − \(shown(v))°." : "The exterior angle is given."
            sum = interior ? "180 − \(shown(v))" : shown(v)
        }
        guard let share, share > 0, share < 1, numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let letter = groups(#"\bpolygon has ((?-i:[a-z])) sides\b"#, in: text)?[1]
        let asksLetter = letter.map { has("\\b(?:find|work out|calculate|what is) (?:the value of )?\($0)\\b", text) } ?? false
        guard asksLetter || has(#"\bhow many sides\b|\b(?:find|work out|calculate|write down) the number of sides\b"#, text) else { return nil }
        let exterior = 180 * share, n = 360 / exterior
        guard abs(n - n.rounded()) < 1e-9, n.rounded() >= 3 else { return nil }
        let lead = [
            Step("Interior and exterior angles make 180°", how, [MathLine(.symbol("exterior angle"), .symbol(sum), amount(tidy(exterior)), suffix: "°")]),
            Step("Exterior angles add up to 360°", "A regular polygon has one equal exterior angle at each corner, so the number of sides is 360 ÷ the exterior angle.",
                 [MathLine(.symbol("360 ÷ \(shown(tidy(exterior)))"), amount(n.rounded()))]),
        ]
        if asksLetter, let letter { return told(letter, [MathLine(.symbol(letter), amount(n.rounded()))], lead) }
        return told("number of sides", [MathLine(amount(n.rounded()), suffix: "sides")], lead)
    }

    /// Two similar solids priced by their volume: "Here are two square-based paving stones. The stones are similar solids.
    /// [25 cm, 20 cm] The price per cm³ is the same for both stones. The price of the larger stone is £17.50. Work out the
    /// price of the smaller stone." The larger length is the larger solid's; with a price per cm², the areas are used.
    private static func similarPrice(_ text: String) -> Problem? {
        guard has(#"\bsimilar\b"#, text), has(#"\btwo\b|\bboth\b"#, text),
              let per = groups(#"\b(?:price|cost) per (mm|cm|m) ?\^?([23]) is the same\b"#, in: text),
              let known = groups(#"\b(?:price|cost) of the (larger|smaller|bigger|large|small) ([a-z]+) is £ ?(\#(number))(?!\d|\.\d)"#, in: text),
              let asked = groups(#"\b(?:work out|find|calculate|what is) the (?:price|cost) of the (larger|smaller|bigger|large|small) ([a-z]+)\b"#, in: text),
              known[2].lowercased() == asked[2].lowercased(), let price = Double(known[3]), price > 0 else { return nil }
        let knownIsLarge = known[1].lowercased() != "smaller" && known[1].lowercased() != "small"
        let askedIsLarge = asked[1].lowercased() != "smaller" && asked[1].lowercased() != "small"
        guard knownIsLarge != askedIsLarge else { return nil }
        // One length on each solid, in the same unit: nothing else to match them by, so there must be exactly two.
        let lengths = every(#"(?<![\d.^A-Za-z£])(\#(number)) ?(mm|cm|m)\b(?! ?\^)"#, in: text)
        let sizes = Set(lengths.compactMap { Double($0[1]) }), units = Set(lengths.map { $0[2].lowercased() })
        guard sizes.count == 2, units.count == 1, let large = sizes.max(), let small = sizes.min(), small > 0 else { return nil }
        // Lengths named in the words must be the same measure of each: not one's height and the other's width.
        let named = Set(every(#"\b(heights?|widths?|lengths?|sides?|radius|radii|diameters?|depths?|thickness|edges?|base)\b[^.\d]{0,25}?\#(number) ?(?:mm|cm|m)\b"#, in: text).map { String($0[1].lowercased().prefix(4)) })
        guard named.count <= 1, numbers(withoutNumbering(text)).allSatisfy({ [large, small, price].contains($0) }) else { return nil }
        let power = per[2] == "3" ? 3.0 : 2.0, unit = units.first!
        let scale = askedIsLarge ? large / small : small / large
        let value = (price * pow(scale, power) * 100).rounded(.toNearestOrAwayFromZero) / 100
        guard value.isFinite, value > 0 else { return nil }
        func pounds(_ v: Double) -> String { abs(v - v.rounded()) < 1e-9 ? "£\(Int(v.rounded()))" : "£" + String(format: "%.2f", v) }
        let from = askedIsLarge ? small : large, to = askedIsLarge ? large : small
        let what = power == 3 ? "volume" : "area", raised = power == 3 ? "³" : "²"
        let lead = [
            Step("Scale factor for length", "The solids are similar, and the matching lengths are \(shown(from)) \(unit) and \(shown(to)) \(unit).",
                 [MathLine(.symbol("\(shown(to)) ÷ \(shown(from))"), amount(tidy(scale)))]),
            Step("Scale factor for \(what)", "The price per \(per[1])\(raised) is the same, so the price goes with the \(what): \(power == 3 ? "cube" : "square") the scale factor.",
                 [MathLine(.symbol("\(shown(tidy(scale)))\(raised)"), amount(tidy(pow(scale, power))))]),
            Step("Price of the \(asked[1].lowercased()) \(asked[2].lowercased())", "", [MathLine(.symbol("\(pounds(price)) × \(shown(tidy(pow(scale, power))))"), .symbol(pounds(value)))]),
        ]
        return told("price of the \(asked[1].lowercased()) \(asked[2].lowercased())", [MathLine(.symbol(pounds(value)))], lead)
    }

    /// Two shapes that are circles or parts of circles, compared: "Shape A is a circle with radius √17/2 cm. Shape B is a
    /// sector of a circle with radius 5 cm [60° on the drawing]. Which shape has the greater area, A or B?" A sector's
    /// angle is the one angle in the question.
    private static func greaterArea(_ text: String) -> Problem? {
        guard let ask = groups(#"\bwhich (?:shape |one )?has the (greater|larger|bigger|greatest|largest|smaller|smallest|lesser|least) area\b"#, in: text)?[1].lowercased() else { return nil }
        let found = every(#"\b(?:shape )?((?-i:[A-Z])) is a (semicircle|quarter circle|sector of a circle|sector|circle) (?:with|of) (?:a )?(radius|diameter) (?:of )?([\d.√()/ ]+?) ?(mm|cm|m)\b(?:,? (?:and|with) (?:an? )?angle (?:of )?(\#(number)) ?°)?"#, in: text)
        guard found.count == 2, found[0][1] != found[1][1], found[0][5].lowercased() == found[1][5].lowercased(),
              every(#"\b(?:shape )?(?-i:[A-Z]) is an? "#, in: text).count == 2 else { return nil }
        if let pair = groups(#"\barea,? ((?-i:[A-Z])) or ((?-i:[A-Z]))\b"#, in: text), Set([pair[1], pair[2]]) != Set([found[0][1], found[1][1]]) { return nil }
        let angles = Set(every(#"(?<![\d.^])(\#(number)) ?°"#, in: text).compactMap { Double($0[1]) })
        let sectors = found.filter { $0[2].lowercased().hasPrefix("sector") }
        // Every angle in the question is a sector's: one sector takes the one angle there is; two need theirs in the words.
        var used: [Double] = []
        var shapes: [(name: String, kind: String, area: (n: Int, d: Int), working: String)] = []
        for f in found {
            guard let square = squareOf(f[4]) else { return nil }
            used += numbers(f[4])
            let r2 = f[3].lowercased() == "radius" ? square : lowest(square.n, square.d * 4)
            let kind = f[2].lowercased()
            let radius = f[3].lowercased() == "radius" ? f[4].trimmingCharacters(in: .whitespaces) : "(\(f[4].trimmingCharacters(in: .whitespaces)) ÷ 2)"
            var part: (n: Int, d: Int) = (1, 1), front = ""
            if kind.hasPrefix("sector") {
                let written = Double(f[6]) ?? (sectors.count == 1 && angles.count == 1 ? angles.first : nil)
                guard let theta = written, theta > 0, theta < 360, let t = fraction(theta) else { return nil }
                used.append(theta)
                part = lowest(t.n, t.d * 360); front = "\(shown(theta))/360 × "
            } else if kind == "semicircle" { part = (1, 2); front = "½ × " } else if kind.hasPrefix("quarter") { part = (1, 4); front = "¼ × " }
            let area = lowest(r2.n * part.n, r2.d * part.d)
            shapes.append((f[1], kind, area, "\(front)π × \(radius.contains("√") || radius.contains("/") ? "(\(radius))" : radius)²"))
        }
        guard angles.allSatisfy({ used.contains($0) }), sectors.count > 0 || angles.isEmpty, numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let a = shapes[0], b = shapes[1]
        let left = a.area.n * b.area.d, right = b.area.n * a.area.d
        guard left != right else { return nil }
        let wantsGreater = !["smaller", "smallest", "lesser", "least"].contains(ask)
        let winner = (left > right) == wantsGreater ? a : b, loser = winner.name == a.name ? b : a
        // Enough decimal places to tell the two apart.
        func value(_ s: (n: Int, d: Int)) -> Double { Double(s.n) / Double(s.d) * .pi }
        var places = 2
        while places < 6, String(format: "%.\(places)f", value(a.area)) == String(format: "%.\(places)f", value(b.area)) { places += 1 }
        func decimal(_ s: (n: Int, d: Int)) -> String { String(format: "%.\(places)f", value(s)) }
        let unit = found[0][5].lowercased()
        var lead = shapes.map { s in
            Step("Area of \(s.name)", s.kind.hasPrefix("sector") ? "A sector: its angle out of 360, of π × r²." : s.kind == "circle" ? "A circle: π × r²." : "\(s.kind == "semicircle" ? "Half" : "A quarter") of π × r².",
                 [MathLine(.symbol(s.working), .symbol(piTimes(s.area))), MathLine(.symbol(piTimes(s.area)), .symbol(decimal(s.area)), relation: "≈", suffix: "\(unit)²")])
        }
        func front(_ f: (n: Int, d: Int)) -> String { f.d == 1 ? "\(f.n)" : "\(f.n)/\(f.d) = \(shown(rounded(Double(f.n) / Double(f.d), significant: 4)))" }
        lead.append(Step("Compare", "Both are a number of π, so compare the numbers: \(front(a.area)) and \(front(b.area)).", []))
        return told("the \(ask) area", [MathLine(.symbol("\(winner.name): \(decimal(winner.area)) \(unit)² against \(decimal(loser.area)) \(unit)²"))], lead)
    }

    /// A whole number's square root with the squares taken outside: 24 as 2√6, 100 as 10 (inside 1).
    private static func root(_ n: Int) -> (outside: Int, inside: Int) {
        var outside = 1, inside = n, factor = 2
        while factor * factor <= inside {
            if inside % (factor * factor) == 0 { inside /= factor * factor; outside *= factor } else { factor += 1 }
        }
        return (outside, inside)
    }

    /// Two similar isosceles triangles that share a side, one standing on a side of the other: "ABC and DAB are similar
    /// isosceles triangles. AB = AC. AD = BD. BC : CD = 4 : 21. Find the ratio AB : AD." The shared side AB is a base of
    /// one and an equal side of the other; both have the same angle at B, so C lies on BD.
    private static func similarIsosceles(_ text: String) -> Problem? {
        guard let names = groups(#"(?<![A-Za-z])((?-i:[A-Z]{3})) and ((?-i:[A-Z]{3})) are (?:mathematically )?similar isosceles triangles\b"#, in: text)
                ?? groups(#"\bsimilar isosceles triangles,? ((?-i:[A-Z]{3})) and ((?-i:[A-Z]{3}))(?![A-Za-z])"#, in: text) else { return nil }
        let first = Set(names[1]), second = Set(names[2]), shared = first.intersection(second)
        guard first.count == 3, second.count == 3, shared.count == 2 else { return nil }
        // Each triangle's equal sides, and so its top corner (the letter in both).
        let equal = every(#"(?<![A-Za-z:])((?-i:[A-Z]{2})) ?= ?((?-i:[A-Z]{2}))(?![A-Za-z]| ?:)"#, in: text)
        guard equal.count == 2 else { return nil }
        func top(_ triangle: Set<Character>) -> Character? {
            let mine = equal.filter { Set($0[1]).union(Set($0[2])) == triangle }
            guard mine.count == 1, Set(mine[0][1]).count == 2, Set(mine[0][2]).count == 2 else { return nil }
            let both = Set(mine[0][1]).intersection(Set(mine[0][2]))
            return both.count == 1 ? both.first : nil
        }
        guard let topFirst = top(first), let topSecond = top(second), shared.contains(topFirst) != shared.contains(topSecond) else { return nil }
        // The small triangle has the shared side as one of its equal sides; the large one has it as its base.
        let small = shared.contains(topFirst) ? first : second, a = shared.contains(topFirst) ? topFirst : topSecond
        let d = shared.contains(topFirst) ? topSecond : topFirst
        guard let b = shared.subtracting([a]).first, let c = small.subtracting(shared).first else { return nil }
        // The ratio given: the small triangle's base, and what is left of the large triangle's side beyond it.
        guard let given = groups(#"(?<![A-Za-z])((?-i:[A-Z]{2})) ?: ?((?-i:[A-Z]{2})) ?= ?(\d+) ?: ?(\d+)(?!\d|\.\d)"#, in: text),
              let x = Int(given[3]), let y = Int(given[4]), x > 0, y > 0, x < 10000, y < 10000 else { return nil }
        let base: Set<Character> = [b, c], rest: Set<Character> = [c, d]
        guard Set([Set(given[1]), Set(given[2])]) == Set([base, rest]) else { return nil }
        let m = Set(given[1]) == base ? x : y, n = Set(given[1]) == base ? y : x
        guard let asked = groups(#"\b(?:find|work out|calculate|write down) the ratio (?:of )?((?-i:[A-Z]{2})) ?: ?((?-i:[A-Z]{2}))(?![A-Za-z]| ?=)"#, in: text),
              numbers(withoutNumbering(text)).allSatisfy({ [Double(x), Double(y)].contains($0) }) else { return nil }
        // Lengths in parts: the small triangle's base m, the large triangle's equal sides m + n, the shared side √(m(m + n)).
        let side = root(m * (m + n))
        func length(_ name: String) -> (whole: Int, inside: Int)? {
            let s = Set(name)
            guard s.count == 2 else { return nil }
            if s == [a, b] || s == [a, c] { return (side.outside, side.inside) }
            if s == [d, a] || s == [d, b] { return (m + n, 1) }
            if s == base { return (m, 1) }
            if s == rest { return (n, 1) }
            return nil
        }
        guard let p = length(asked[1]), let q = length(asked[2]), !(p.inside > 1 && q.inside > 1), Set(asked[1]) != Set(asked[2]) else { return nil }
        let g = gcd(p.whole, q.whole)
        func written(_ v: (whole: Int, inside: Int)) -> String { v.inside == 1 ? "\(v.whole / g)" : "\(v.whole / g == 1 ? "" : String(v.whole / g))√\(v.inside)" }
        func plainLength(_ v: (whole: Int, inside: Int)) -> String { v.inside == 1 ? "\(v.whole)" : "\(v.whole == 1 ? "" : String(v.whole))√\(v.inside)" }
        let A = String(a), B = String(b), C = String(c), D = String(d)
        let answer = "\(written(p)) : \(written(q))"
        let lead = [
            Step("Match the triangles", "\(A)\(B)\(C) has its equal sides meeting at \(A), and \(D)\(A)\(B) has its equal sides meeting at \(D). So \(A) matches \(D), and the bases \(B)\(C) and \(A)\(B) match.",
                 [MathLine(.symbol("\(A)\(B)/\(B)\(C)"), .symbol("\(D)\(B)/\(A)\(B)"))]),
            Step("\(C) is on \(B)\(D)", "Both triangles have the same angle at \(B), so \(C) is on the side \(B)\(D). With \(B)\(C) as \(m) parts and \(C)\(D) as \(n) parts, \(B)\(D) is \(m + n) parts, and \(A)\(D) = \(B)\(D).",
                 [MathLine(.symbol("\(B)\(D)"), .symbol("\(m) + \(n)"), .symbol("\(m + n)"))]),
            Step("Find \(A)\(B)", "Multiply out the matching sides: \(A)\(B)² = \(B)\(C) × \(B)\(D).", [MathLine(.symbol("\(A)\(B)²"), .symbol("\(m) × \(m + n)"), .symbol("\(m * (m + n))")), MathLine(.symbol("\(A)\(B)"), .symbol(plainLength((side.outside, side.inside))))]),
            Step("Write the ratio", "In its simplest form.", [MathLine(.symbol("\(asked[1]) : \(asked[2])"), .symbol("\(plainLength(p)) : \(plainLength(q))"), .symbol(answer))]),
        ]
        return told("\(asked[1]) : \(asked[2])", [MathLine(.symbol(answer))], lead)
    }

    /// A cuboid from its volume, its surface area and one edge: "A solid cuboid has a volume of 300 cm³. The cuboid has a
    /// total surface area of 370 cm². The length of the cuboid is 20 cm. The width of the cuboid is greater than the height
    /// of the cuboid. Work out the height of the cuboid."
    private static func cuboidFromVolumeAndSurface(_ text: String) -> Problem? {
        let edge = #"(length|width|height|depth)"#
        guard has(#"\bcuboid\b"#, text), !has(#"\bcubes?\b|\bsimilar\b|\bprism\b|\bcylinder\b|\bcuboids\b"#, text),
              let volume = groups(#"\bvolume (?:of (?:the |this )?cuboid )?(?:of |is |= ?)?(\#(number)) ?(mm|cm|m) ?(?:\^?3|\?|³)"#, in: text),
              let surface = groups(#"\b(?:total )?surface area (?:of (?:the |this )?cuboid )?(?:of |is |= ?)?(\#(number)) ?(mm|cm|m) ?\^?2"#, in: text),
              let given = groups(#"\b\#(edge) of the cuboid is (\#(number)) ?(mm|cm|m)\b(?! ?\^)"#, in: text),
              let order = groups(#"\b\#(edge) of the cuboid is (greater|more|longer|bigger|larger|less|smaller|shorter) than (?:the|its) \#(edge)\b"#, in: text),
              let ask = groups(#"\b(?:work out|find|calculate) the \#(edge) of the cuboid\b"#, in: text)?[1].lowercased(),
              let v = Double(volume[1]), let s = Double(surface[1]), let l = Double(given[2]), v > 0, s > 0, l > 0,
              Set([volume[2], surface[2], given[3]].map { $0.lowercased() }).count == 1 else { return nil }
        let known = given[1].lowercased(), big = ["greater", "more", "longer", "bigger", "larger"].contains(order[2].lowercased())
        let larger = big ? order[1].lowercased() : order[3].lowercased(), smaller = big ? order[3].lowercased() : order[1].lowercased()
        // The two edges compared are the two that aren't given, and one of them is asked for.
        guard larger != smaller, larger != known, smaller != known, ask == larger || ask == smaller,
              numbers(withoutNumbering(text)).allSatisfy({ [v, s, l].contains($0) }) else { return nil }
        let product = v / l, total = (s / 2 - product) / l, inside = total * total - 4 * product
        guard inside > 1e-9 else { return nil }
        let high = (total + inside.squareRoot()) / 2, low = (total - inside.squareRoot()) / 2
        guard low > 0, let rounding = asAsked(ask == larger ? high : low, text) else { return nil }
        let unit = given[3].lowercased(), a = String(larger.prefix(1)), b = String(smaller.prefix(1))
        let lead = [
            Step("Use the volume", "\(known.capitalized) × \(larger) × \(smaller) = \(shown(v)), and the \(known) is \(shown(l)).", [MathLine(.symbol("\(a)\(b)"), .symbol("\(shown(v)) ÷ \(shown(l))"), amount(tidy(product)))]),
            Step("Use the surface area", "Two of each face: 2(\(shown(l))\(a) + \(shown(l))\(b) + \(a)\(b)) = \(shown(s)), so \(shown(l))(\(a) + \(b)) + \(shown(tidy(product))) = \(shown(tidy(s / 2))).",
                 [MathLine(.symbol("\(a) + \(b)"), .symbol("(\(shown(tidy(s / 2))) − \(shown(tidy(product)))) ÷ \(shown(l))"), amount(tidy(total)))]),
            Step("Two numbers from their sum and product", "Put \(b) = \(shown(tidy(total))) − \(a) into \(a)\(b) = \(shown(tidy(product))) and solve the quadratic.",
                 [MathLine(.symbol("\(a)² − \(shown(tidy(total)))\(a) + \(shown(tidy(product)))"), .integer(0)),
                  MathLine(.symbol("\(a)"), .symbol("\(shown(tidy((high * 10000).rounded() / 10000))) or \(shown(tidy((low * 10000).rounded() / 10000)))"))]),
            Step("Choose", "The \(larger) is the greater of the two, so the \(smaller) is the other.", []),
        ]
        return told(ask, [MathLine(amount(rounding.value), relation: rounding.relation, suffix: unit)], lead)
    }

    /// A sector from its radius and its arc, or its radius and its area: "OAB is a sector of a circle with centre O and
    /// radius 6 cm. The length of the arc AB is 5π cm. Work out, in terms of π, the area of the sector." The area is half
    /// the radius times the arc, so it comes out in whatever letter the arc is given in. Or "… radius 7 cm. The area of
    /// the sector is 40 cm². Calculate the perimeter of the sector."
    private static func sectorFromArc(_ text: String) -> Problem? {
        guard has(#"\bsector\b"#, text), !has(#"\bsectors\b|\bsemicircle\b|\bshaded\b|\bsegment\b|\btriangle\b|\bchord\b|\bcone\b|\bperpendicular\b"#, text),
              let radius = groups(#"\bradius (?:of |is |= ?)?(\#(number)) ?(mm|cm|m)\b"#, in: text), let r = Double(radius[1]), r > 0 else { return nil }
        let unit = radius[2].lowercased()
        let arcGiven = groups(#"\b(?:length of (?:the )?arc(?: (?-i:[A-Z]{2,3}))?|arc length(?: of the sector)?|arc (?-i:[A-Z]{2,3}) has length) (?:is |= ?|of )?(\#(number)) ?(π|(?-i:[a-z]))?? ?(mm|cm|m)\b(?! ?\^)"#, in: text)
        let areaGiven = groups(#"\barea of (?:the |this )?sector(?: (?-i:[A-Z]{3}))? (?:is |= ?)(\#(number)) ?(π|(?-i:[a-z]))?? ?(mm|cm|m) ?\^?2"#, in: text)
        guard (arcGiven == nil) != (areaGiven == nil), let given = arcGiven ?? areaGiven, given[3].lowercased() == unit, let k = Double(given[1]), k > 0 else { return nil }
        // "In terms of π" (or of the letter read for it) has to be the letter the arc or area is given in.
        let letter = given[2]
        if let terms = groups(#"\bin terms of (π|[a-z]+)\b"#, in: text)?[1] {
            guard !letter.isEmpty, letter == "π" || terms == letter else { return nil }
        } else if !letter.isEmpty, letter != "π" { return nil }
        // A π is sometimes read as a 7 ("5π cm" as "57cm", "57.8π" as "57.87"): a plain number ending in 7 isn't trusted.
        if letter.isEmpty, given[1].count >= 2, given[1].hasSuffix("7") { return nil }
        // The sector has to fit in its circle.
        let whole = arcGiven != nil ? 2 * r : r * r
        guard k < whole * (letter.isEmpty ? Double.pi : 1), numbers(withoutNumbering(text)).allSatisfy({ [r, k].contains($0) }) else { return nil }
        let asks = every(#"\b(?:work out|find|calculate)\b[^.?]{0,40}?\b(area of (?:the |this )?sector|perimeter of (?:the |this )?sector|length of (?:the )?arc|arc length)\b"#, in: text)
        guard asks.count == 1, let what = asks.first?[1].lowercased().components(separatedBy: " ").first else { return nil }
        // The arc and the area as numbers of the letter (or plain numbers).
        let arc = arcGiven != nil ? k : 2 * k / r, area = arcGiven != nil ? r * k / 2 : k
        var lead: [Step] = []
        func written(_ value: Double) -> String? {
            if letter.isEmpty { return shown(tidy((value * 10000).rounded() / 10000)) }
            return fraction(value).map { piTimes($0, letter) }
        }
        guard let arcText = written(arc), let areaText = written(area) else { return nil }
        if arcGiven != nil {
            guard what != "length", what != "arc" else { return nil }
            lead.append(Step("Area of the sector", "The sector is the same fraction of the circle as its arc is of the circumference, which makes the area ½ × radius × arc.",
                             [MathLine(.symbol("½ × \(shown(r)) × \(shown(k))\(letter)"), .symbol(areaText))]))
        } else {
            guard what != "area" else { return nil }
            lead.append(Step("The arc", "The area of a sector is ½ × radius × arc, so the arc is twice the area divided by the radius.",
                             [MathLine(.symbol("2 × \(shown(k))\(letter) ÷ \(shown(r))"), .symbol(arcText), relation: letter.isEmpty && abs(arc * 10000 - (arc * 10000).rounded()) > 1e-6 ? "≈" : "=")]))
        }
        switch what {
        case "area":
            if !letter.isEmpty { return told("area", [MathLine(.symbol(areaText), suffix: "\(unit)²")], lead) }
            guard let rounding = asAsked(area, text) else { return nil }
            return told("area", [MathLine(amount(rounding.value), suffix: "\(unit)²")], lead)
        case "perimeter":
            lead.append(Step("Perimeter of the sector", "Two radii and the arc.", [MathLine(.symbol("2 × \(shown(r)) + \(arcText)"))]))
            if !letter.isEmpty { return told("perimeter", [MathLine(.symbol("\(shown(2 * r)) + \(arcText)"), suffix: unit)], lead) }
            guard let rounding = asAsked(2 * r + arc, text) else { return nil }
            return told("perimeter", [MathLine(amount(rounding.value), suffix: unit)], lead)
        default:
            if !letter.isEmpty { return told("arc length", [MathLine(.symbol(arcText), suffix: unit)], lead) }
            guard let rounding = asAsked(arc, text) else { return nil }
            return told("arc length", [MathLine(amount(rounding.value), suffix: unit)], lead)
        }
    }

    /// An estimate from rounded values: "A bronze ornament has a volume of 198 cm³. The density of bronze is 8.9 g/cm³. By
    /// rounding each value correct to one significant figure, work out an estimate for the mass of the bronze ornament."
    private static func densityEstimate(_ text: String) -> Problem? {
        guard has(#"\brounding each (?:value|number|of the values|of the numbers) (?:correct )?to (?:one|1) significant figure\b"#, text),
              let ask = groups(#"\bestimate (?:for|of) the (mass|volume|density)\b"#, in: text)?[1].lowercased() else { return nil }
        // (A raised ³ is often read as "?" or "*", or lost.)
        let volumes = every(#"\bvolume (?:of (?:the )?[a-z ]+? )?(?:of |is |= ?)?(\#(number)) ?(cm|m)(?! ?\^?2)(?: ?\^?3|³|\?|\*)?(?![a-z])"#, in: text)
        let masses = every(#"\bmass (?:of (?:the )?[a-z ]+? )?(?:of |is |= ?)?(\#(number)) ?(kg|g|grams|kilograms)\b"#, in: text)
        let densities = every(#"\bdensity (?:of (?:the )?[a-z ]+? )?(?:of |is |= ?)?(\#(number)) ?(kg|g|grams?|kilograms?) ?(?:/|per) ?(?:cubic )?(cm|m|centimetres?|metres?)"#, in: text)
        guard volumes.count <= 1, masses.count <= 1, densities.count <= 1, !has(#"\bmixed\b|\bratio\b|%"#, text) else { return nil }
        func one(_ value: Double) -> Double { rounded(value, significant: 1) }
        let v = volumes.first.flatMap { Double($0[1]) }, m = masses.first.flatMap { Double($0[1]) }, d = densities.first.flatMap { Double($0[1]) }
        let volumeIn = volumes.first.map { $0[2].lowercased() }, massIn = masses.first.map { $0[2].lowercased().hasPrefix("k") ? "kg" : "g" }
        let densityMass = densities.first.map { $0[2].lowercased().hasPrefix("k") ? "kg" : "g" }, densityVolume = densities.first.map { $0[3].lowercased().hasPrefix("c") ? "cm" : "m" }
        let used = [v, m, d].compactMap { $0 }
        guard used.count == 2, used.allSatisfy({ $0 > 0 }), numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        func rounding(_ values: [Double]) -> Step {
            Step("Round each value to one significant figure", "", [MathLine(.symbol(values.map { "\(shown($0)) ≈ \(shown(one($0)))" }.joined(separator: ",  ")))])
        }
        switch ask {
        case "mass":
            guard let v, let d, let densityMass, volumeIn == densityVolume else { return nil }
            return told("estimate of the mass", [MathLine(amount(tidy(one(d) * one(v))), suffix: densityMass)],
                        [rounding([v, d]), Step("Mass is density × volume", "", [MathLine(.symbol("\(shown(one(d))) × \(shown(one(v)))"))])])
        case "volume":
            guard let m, let d, let densityVolume, massIn == densityMass else { return nil }
            return told("estimate of the volume", [MathLine(amount(tidy(one(m) / one(d))), suffix: "\(densityVolume)³")],
                        [rounding([m, d]), Step("Volume is mass ÷ density", "", [MathLine(.symbol("\(shown(one(m))) ÷ \(shown(one(d)))"))])])
        default:
            guard let m, let v, let massIn, let volumeIn else { return nil }
            return told("estimate of the density", [MathLine(amount(tidy(one(m) / one(v))), suffix: "\(massIn)/\(volumeIn)³")],
                        [rounding([m, v]), Step("Density is mass ÷ volume", "", [MathLine(.symbol("\(shown(one(m))) ÷ \(shown(one(v)))"))])])
        }
    }

    /// The corners of a shape that stay where they are in a reflection: "The diagram shows the coordinates of the vertices
    /// of a rectangle. (5,4) (1,4) (1,1) (5,1) The rectangle is reflected in the line y = 4. Write down the coordinates of
    /// the vertices of the rectangle that are invariant." They are the ones on the mirror line.
    private static func invariantVertices(_ text: String) -> Problem? {
        guard has(#"\binvariant\b"#, text), !has(#"\brotat|\btranslat|\benlarg"#, text), every(#"\breflect"#, in: text).count == 1,
              let shape = groups(#"\bvertices of (?:a|the|this) (rectangle|square|triangle|parallelogram|trapezium|kite|rhombus|quadrilateral)\b"#, in: text)?[1].lowercased(),
              let mirror = groups(#"\breflected in the (?:line )?(?:(?:with equation )?([xy]) ?= ?(-?\#(number))(?![\dx])|([xy])[- ]axis|y ?= ?(-?) ?x\b)"#, in: text),
              has(#"\bcoordinates of the (?:vertices|vertex|points?|corners?)\b[^.?]*\binvariant\b|\bwhich (?:of the )?(?:vertices|points|corners)\b[^.?]*\binvariant\b|\binvariant (?:points?|vertices|vertex)\b"#, text) else { return nil }
        var points: [(x: Double, y: Double)] = []
        for f in every(#"\( ?(-?\#(number)) ?, ?(-?\#(number)) ?\)"#, in: text) {
            guard let x = Double(f[1]), let y = Double(f[2]) else { return nil }
            if !points.contains(where: { $0.x == x && $0.y == y }) { points.append((x, y)) }
        }
        guard points.count == (shape == "triangle" ? 3 : 4) else { return nil }
        // A rectangle's corners: the middle of the four is the same distance from each, and opposite corners balance.
        if shape == "rectangle" || shape == "square" {
            let cx = points.reduce(0) { $0 + $1.x } / 4, cy = points.reduce(0) { $0 + $1.y } / 4
            let far = points.map { ($0.x - cx) * ($0.x - cx) + ($0.y - cy) * ($0.y - cy) }
            guard far.allSatisfy({ abs($0 - far[0]) < 1e-9 }), far[0] > 0,
                  points.allSatisfy({ p in points.contains(where: { abs($0.x + p.x - 2 * cx) < 1e-9 && abs($0.y + p.y - 2 * cy) < 1e-9 }) }) else { return nil }
        }
        var used = points.flatMap { [abs($0.x), abs($0.y)] }
        let line: String, stays: ((x: Double, y: Double)) -> Bool
        if !mirror[1].isEmpty, let k = Double(mirror[2]) {
            used.append(abs(k))
            line = "\(mirror[1].lowercased()) = \(shown(k).replacingOccurrences(of: "-", with: "−"))"
            stays = mirror[1].lowercased() == "x" ? { $0.x == k } : { $0.y == k }
        } else if !mirror[3].isEmpty {
            line = "the \(mirror[3].lowercased())-axis"
            stays = mirror[3].lowercased() == "x" ? { $0.y == 0 } : { $0.x == 0 }
        } else {
            line = mirror[4].isEmpty ? "y = x" : "y = −x"
            stays = mirror[4].isEmpty ? { $0.y == $0.x } : { $0.y == -$0.x }
        }
        guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let kept = points.filter(stays).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard !kept.isEmpty, kept.count < points.count else { return nil }
        func written(_ p: (x: Double, y: Double)) -> String { "(\(shown(p.x)), \(shown(p.y)))".replacingOccurrences(of: "-", with: "−") }
        let names = kept.map(written)
        let answer = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        let lead = [
            Step("What invariant means", "A point is invariant when the reflection leaves it where it is. That happens only for points on the mirror line, \(line).", []),
            Step("Look for the vertices on \(line)", "", [MathLine(.symbol(answer))]),
        ]
        return told("invariant vertices", [MathLine(.symbol(answer))], lead)
    }

    /// A scale drawing's area made real: "Dan makes a scale drawing of the playground. He uses a scale of 1 cm represents
    /// 5 m. The area of the playground on the scale drawing is 28 cm². Work out the real area of the playground." Also a
    /// side of a right-angled triangle from that area, when the words say where the right angle is: "Angle PQR is 90°. The
    /// real length of QR is 40 m. Work out the real length of PQ." (With the right angle only on the drawing: nothing.)
    private static func scaleDrawingArea(_ text: String) -> Problem? {
        guard let scale = groups(#"\bscale(?: of|:)? ?1 ?(mm|cm) (?:represents|to|=|is) (\#(number)) ?(mm|cm|m|km)\b"#, in: text),
              let drawn = groups(#"\barea (?:of (?:the |this )?[a-z ]+? )?on the (?:scale )?drawing is (\#(number)) ?(mm|cm) ?\^?2"#, in: text),
              scale[1].lowercased() == drawn[2].lowercased(), let k = Double(scale[2]), let small = Double(drawn[1]), k > 0, small > 0,
              every(#"\bscale(?: of|:)? ?1 ?(?:mm|cm) "#, in: text).count == 1 else { return nil }
        let unit = scale[3].lowercased(), paper = scale[1].lowercased()
        let area = small * k * k
        var used = [1, k, small]
        var lead = [
            Step("The scale for areas", "1 \(paper) is \(shown(k)) \(unit), so 1 \(paper)² is \(shown(k)) × \(shown(k)) = \(shown(k * k)) \(unit)².", []),
            Step("The real area", "", [MathLine(.symbol("\(shown(small)) × \(shown(k * k))"), amount(tidy(area)), suffix: "\(unit)²")]),
        ]
        let real = #"(?:real|actual|true)"#
        if has(#"\b(?:work out|find|calculate|what is) the \#(real) area\b"#, text) {
            guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }), let rounding = asAsked(area, text) else { return nil }
            return told("real area", [MathLine(amount(rounding.value), suffix: "\(unit)²")], lead)
        }
        // A side of a right-angled triangle: the two sides at the right angle are its base and height.
        guard has(#"\bright[- ]angled triangle\b"#, text),
              let given = groups(#"\b\#(real) length of ((?-i:[A-Z]{2})) is (\#(number)) ?(mm|cm|m|km)\b"#, in: text), given[3].lowercased() == unit,
              let asked = groups(#"\b(?:work out|find|calculate) the \#(real) length of ((?-i:[A-Z]{2}))\b"#, in: text)?[1],
              let g = Double(given[2]), g > 0 else { return nil }
        used.append(g)
        let corner: Character
        if let angle = groups(#"\bangle ((?-i:[A-Z]{3})) (?:is|=) ?90 ?°"#, in: text) { corner = Array(angle[1])[1]; used.append(90) }
        else if let at = groups(#"\bright angle (?:is )?at ((?-i:[A-Z]))\b"#, in: text) { corner = Character(at[1]) }
        else { return nil }
        let known = Set(given[1]), wanted = Set(asked)
        guard known.count == 2, wanted.count == 2, known != wanted, known.contains(corner), numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let other = 2 * area / g
        guard let third = known.subtracting([corner]).first, let fourth = wanted.subtracting(known).first, fourth != corner || wanted.contains(third) else { return nil }
        if wanted.contains(corner) {
            lead.append(Step("Area of a right-angled triangle", "Half of \(given[1]) × \(asked), the two sides at the right angle. So \(asked) is twice the area divided by \(given[1]).",
                             [MathLine(.symbol(asked), .symbol("2 × \(shown(tidy(area))) ÷ \(shown(g))"))]))
            guard let rounding = asAsked(other, text) else { return nil }
            return told(asked, [MathLine(.symbol(asked), amount(rounding.value), relation: rounding.relation, suffix: unit)], lead)
        }
        // The side facing the right angle: the other side first, then Pythagoras.
        lead.append(Step("The other side at the right angle", "The area is half of the two sides at the right angle multiplied.", [MathLine(.symbol("2 × \(shown(tidy(area))) ÷ \(shown(g))"), amount(tidy(other)), suffix: unit)]))
        lead.append(Step("Pythagoras", "\(asked) faces the right angle.", [MathLine(.symbol("\(asked)²"), .symbol("\(shown(g))² + \(shown(tidy(other)))²"))]))
        guard let rounding = asAsked((g * g + other * other).squareRoot(), text) else { return nil }
        return told(asked, [MathLine(.symbol(asked), amount(rounding.value), relation: rounding.relation, suffix: unit)], lead)
    }

    /// A volume from a circle drawn on a scale drawing: "Here is a scale drawing of a reservoir. Scale: 1 cm represents
    /// 500 m. He draws on the scale drawing a circle with radius 3 cm. Virat estimates the volume by assuming that the
    /// reservoir is a cylinder whose cross section is the circle, the depth of the reservoir is 17 metres. Work out Virat's
    /// estimate in cubic metres."
    private static func scaleCylinder(_ text: String) -> Problem? {
        guard let scale = groups(#"\bscale(?: of|:)? ?1 ?(mm|cm) (?:represents|to|=|is) (\#(number)) ?(mm|cm|m|km)\b"#, in: text),
              every(#"\bscale(?: of|:)? ?1 ?(?:mm|cm) "#, in: text).count == 1,
              let circle = groups(#"\bon the scale drawing,? a circle (?:with|of) (radius|diameter) (\#(number)) ?(mm|cm)\b"#, in: text),
              has(#"\bis a cylinder whose cross[- ]?section is the circle\b"#, text),
              let depth = groups(#"\b(?:depth|height) (?:of the [a-z]+ )?is (\#(number)) ?\#(lengthUnit)\b"#, in: text),
              has(#"\bwork out [a-z]+'s estimate\b|\b(?:work out|find|calculate|estimate) (?:an estimate (?:for|of) )?the volume\b"#, text),
              scale[1].lowercased() == circle[3].lowercased(), short(depth[2]) == scale[3].lowercased(),
              let k = Double(scale[2]), let size = Double(circle[2]), let h = Double(depth[1]), k > 0, size > 0, h > 0 else { return nil }
        let unit = scale[3].lowercased()
        // The answer's unit, where it is asked for, is the one the scale and the depth are in.
        if let wanted = groups(#"\bin cubic (metres|centimetres|kilometres)\b"#, in: text)?[1], short(wanted) != unit { return nil }
        guard numbers(withoutNumbering(text)).allSatisfy({ [1, k, size, h].contains($0) }) else { return nil }
        let drawn = circle[1].lowercased() == "radius" ? size : size / 2, r = drawn * k
        let lead = [
            Step("The real radius", "1 \(scale[1].lowercased()) is \(shown(k)) \(unit).", [MathLine(.symbol("\(shown(drawn)) × \(shown(k))"), amount(tidy(r)), suffix: unit)]),
            Step("Volume of a cylinder", "π × r² × depth.", [MathLine(.symbol("π × \(shown(tidy(r)))² × \(shown(h))"), .symbol("\(shown(tidy(r * r * h)))π"))]),
        ]
        if has(#"\bin terms of\b"#, text) { return told("volume", [MathLine(.symbol("\(shown(tidy(r * r * h)))π"), suffix: "\(unit)³")], lead) }
        guard let rounding = asAsked(Double.pi * r * r * h, text) else { return nil }
        return told("volume", [MathLine(amount(rounding.value), suffix: "\(unit)³")], lead)
    }

    /// The time something arrives, from how far it has to go: "At 3pm aircraft A is 3250 km from T on a bearing of 015°.
    /// Aircraft A flies directly towards radar tower T at a speed of 890 km/h. At what time will the aircraft pass over
    /// radar tower T? Give your answer to the nearest minute."
    private static func fliesTowards(_ text: String) -> Problem? {
        let time = #"(midday|noon|midnight|\d{1,2}[:.]\d{2}(?: ?[ap]\.?m\.?)?|\d{1,2} ?[ap]\.?m\.?)"#
        let craft = #"(?:aircraft|plane|aeroplane|helicopter|ship|boat|yacht)"#
        guard let goes = groups(#"\b\#(craft) ((?-i:[A-Z])) (?:flies|sails|travels) directly towards (?:[a-z]+ ){0,3}((?-i:[A-Z])) at a (?:constant |steady )?speed of (\#(number)) ?(km/h|mph|km per hour|miles per hour)"#, in: text),
              has("\\bat what time will (?:the )?\(craft)(?: \(goes[1]))? (?:pass over|reach|arrive at|get to|fly over|be over) (?:[a-z]+ ){0,3}\(goes[2])\\b", text),
              has(#"\bto the nearest minute\b"#, text), let v = Double(goes[3]), v > 0 else { return nil }
        // One clock time in the question: when the distances are as given.
        let times = Set(every(#"\bat \#(time)(?![\d:])"#, in: text).compactMap { hours($0[1]) })
        guard times.count == 1, let t0 = times.first, let start = groups(#"\bat \#(time)(?![\d:])"#, in: text)?[1] else { return nil }
        let places = every(#"\b\#(craft) ((?-i:[A-Z])) is (\#(number)) ?(km|kilometres|miles) from ((?-i:[A-Z])) on a bearing of \#(degrees)"#, in: text)
        let mine = places.filter { $0[1] == goes[1] && $0[4] == goes[2] }
        guard mine.count == 1, let d = Double(mine[0][2]), d > 0, mine[0][3].lowercased().hasPrefix("m") == goes[4].lowercased().hasPrefix("m") else { return nil }
        var used = [v, floor(t0), ((t0 - floor(t0)) * 60).rounded()]
        if let f = groups(#"^(\d{1,2})"#, in: start), let shownHour = Double(f[1]) { used.append(shownHour) }
        for p in places { used += [Double(p[2]), Double(p[5])].compactMap { $0 } }
        guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        let minutes = (d / v * 60).rounded(.toNearestOrAwayFromZero), arrive = t0 * 60 + minutes
        guard arrive < 24 * 60 else { return nil }
        let hour = Int(arrive) / 60, minute = Int(arrive) % 60
        let twelve = has(#"[ap]\.?m"#, start) || ["midday", "noon", "midnight"].contains(start.lowercased())
        let clock = twelve ? "\(hour % 12 == 0 ? 12 : hour % 12).\(String(format: "%02d", minute)) \(hour < 12 ? "am" : "pm")" : String(format: "%02d:%02d", hour, minute)
        let unit = goes[4].lowercased().hasPrefix("m") ? "miles" : "km"
        let lead = [
            Step("Time is distance ÷ speed", "\(shown(d)) \(unit) at \(shown(v)) \(goes[4]).", [MathLine(.symbol("\(shown(d)) ÷ \(shown(v))"), amount((d / v * 10000).rounded() / 10000), relation: "≈", suffix: "hours")]),
            Step("In hours and minutes", "Multiply the part after the point by 60, to the nearest minute.", [MathLine(.symbol("\(Int(minutes) / 60) h \(Int(minutes) % 60) min"))]),
            Step("Add to \(start)", "", [MathLine(.symbol(clock))]),
        ]
        return told("time", [MathLine(.symbol(clock))], lead)
    }

    // MARK: Round 5, from other papers

    /// Regular polygons that fit round a point: "Three regular polygons meet at a point. Two of the polygons are pentagons.
    /// Find the number of sides of the third polygon." or "An equilateral triangle, a regular 10-sided polygon and another
    /// regular polygon meet at a point. Work out the number of sides of the other regular polygon."
    private static func polygonsAtPoint(_ text: String) -> Problem? {
        guard let meet = text.range(of: #"\bmeet at a point\b"#, options: [.regularExpression, .caseInsensitive]),
              has(#"\b(?:find|work out|calculate) the number of sides (?:of|on) the (?:third|other|remaining|unknown) (?:regular )?polygon\b|\bhow many sides does the (?:third|other|remaining) (?:regular )?polygon have\b"#, text) else { return nil }
        func sides(_ name: String) -> Int? {
            let n = name.lowercased()
            if let f = groups(#"^(\d+)[- ]sided"#, in: n) { return Int(f[1]) }
            if n.hasPrefix("equilateral triangle") { return 3 }
            if n.hasPrefix("square") { return 4 }
            return ["pentagon": 5, "hexagon": 6, "heptagon": 7, "octagon": 8, "nonagon": 9, "decagon": 10, "dodecagon": 12].first { n.hasPrefix($0.key) }?.value
        }
        let shape = #"(equilateral triangles?|squares?|pentagons?|hexagons?|heptagons?|octagons?|nonagons?|decagons?|dodecagons?|\d+[- ]sided polygons?)"#
        var known: [Int] = [], used: [Double] = []
        if let total = groups(#"\b(two|three|four|2|3|4) regular polygons meet at a point\b"#, in: text), let all = count(total[1]) {
            // "Two of the polygons are pentagons", "One of the polygons is a square".
            for f in every(#"\b(one|two|three|1|2|3) of the (?:regular )?polygons (?:is|are) (?:an? )?(?:regular )?\#(shape)"#, in: text) {
                guard let c = count(f[1]), let n = sides(f[2]) else { return nil }
                known += Array(repeating: n, count: Int(c))
                if let digits = Double(f[1]) { used.append(digits) }
            }
            if let digits = Double(total[1]) { used.append(digits) }
            guard known.count == Int(all) - 1 else { return nil }
        } else {
            // The polygons listed in the sentence that ends "meet at a point", one of them not named.
            let before = String(text[..<meet.lowerBound])
            let sentence = before.components(separatedBy: ". ").last ?? before
            var unknown = 0
            for f in every(#"\b(?:an?|another|the other|one other) (regular )?(?:\#(shape)|(polygon))\b"#, in: sentence) {
                if !f[3].isEmpty { unknown += 1; continue }
                guard let n = sides(f[2]), !f[1].isEmpty || n <= 4 else { return nil }
                known.append(n)
            }
            guard unknown == 1, !known.isEmpty else { return nil }
        }
        used += every(#"(?<![\d.^A-Za-z])(\d+)[- ]sided"#, in: text).compactMap { Double($0[1]) }
        guard known.allSatisfy({ $0 >= 3 }) else { return nil }
        func interior(_ n: Int) -> Double { 180 - 360 / Double(n) }
        let left = 360 - known.reduce(0) { $0 + interior($1) }
        guard left > 0, left < 180 else { return nil }
        let n = 360 / (180 - left)
        // (A part before it may give the angle to show: "Show that angle A is 156°".)
        guard abs(n - n.rounded()) < 1e-9, n.rounded() >= 3, numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) || abs($0 - left) < 1e-9 }) else { return nil }
        let lead = [
            Step("Interior angles of the polygons that are known", "A regular polygon with n sides has exterior angles of 360 ÷ n, and interior angles of 180 minus that.",
                 Set(known).sorted().map { MathLine(.symbol("\($0) sides"), .symbol("180 − 360 ÷ \($0)"), amount(tidy(interior($0))), suffix: "°") }),
            Step("Angles at a point add up to 360°", "Take the known angles from 360° for the last polygon's interior angle.",
                 [MathLine(.symbol("360 − " + known.map { shown(tidy(interior($0))) }.joined(separator: " − ")), amount(tidy(left)), suffix: "°")]),
            Step("Its number of sides", "Its exterior angle is 180° − \(shown(tidy(left)))° = \(shown(tidy(180 - left)))°, and the exterior angles add up to 360°.",
                 [MathLine(.symbol("360 ÷ \(shown(tidy(180 - left)))"), amount(n.rounded()))]),
        ]
        return told("number of sides", [MathLine(amount(n.rounded()), suffix: "sides")], lead)
    }

    /// Two similar things called small and large, with what's known of each in the words: "Two bottles are mathematically
    /// similar. The small bottle holds 0.5 litres and has a height of 35 cm. The large bottle holds 2 litres. Calculate the
    /// height of the large bottle."
    private static func similarSmallLarge(_ text: String) -> Problem? {
        let size = #"(small|smaller|large|larger|big|bigger)"#
        let measure = #"(height|width|length|radius|diameter|depth|volume|capacity|(?:total )?surface area)"#
        guard has(#"\bsimilar\b"#, text),
              let ask = every(#"\b(?:calculate|work out|find) the \#(measure) of (?:the|a|each) \#(size) ([a-z]+)\b"#, in: text).last else { return nil }
        let noun = ask[3].lowercased()
        func sizeKey(_ word: String) -> String { word.lowercased().hasPrefix("small") ? "small" : "large" }
        func key(_ word: String) -> String { let w = word.lowercased(); return w == "capacity" ? "volume" : w.hasSuffix("surface area") ? "surface area" : w }
        func power(_ k: String) -> Double { k == "volume" ? 3 : k == "surface area" ? 2 : 1 }
        // What is said of each: the words from one "the small …" or "the large …" to the next.
        guard let regex = try? NSRegularExpression(pattern: "\\b(?:the|a|each) \(size) \(noun)\\b", options: [.caseInsensitive]) else { return nil }
        let marks = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var facts: [String: [String: (value: Double, unit: String)]] = ["small": [:], "large": [:]]
        var used: [Double] = []
        for (i, m) in marks.enumerated() {
            let end = i + 1 < marks.count ? marks[i + 1].range.location : (text as NSString).length
            let clause = (text as NSString).substring(with: NSRange(location: m.range.location, length: end - m.range.location))
            guard let which = Range(m.range(at: 1), in: text).map({ sizeKey(String(text[$0])) }) else { return nil }
            var found: [(String, Double, String)] = []
            for f in every(#"\b(?:holds|(?:volume|capacity) (?:of |is )?) ?(\#(number)) ?(litres?|ml|cl|cm ?\^?3|m ?\^?3|cm\?)"#, in: clause) {
                guard let v = Double(f[1]) else { return nil }
                found.append(("volume", v, unitShown(f[2].replacingOccurrences(of: "?", with: "^3"))))
            }
            for f in every(#"\bsurface area (?:of |is )?(\#(number)) ?(mm|cm|m) ?\^?2"#, in: clause) {
                guard let v = Double(f[1]) else { return nil }
                found.append(("surface area", v, f[2].lowercased() + "²"))
            }
            for f in every(#"\b(height|width|length|radius|diameter|depth) (?:of |is )?(\#(number)) ?(mm|cm|m)\b(?! ?\^)"#, in: clause) {
                guard let v = Double(f[2]) else { return nil }
                found.append((f[1].lowercased(), v, f[3].lowercased()))
            }
            for (k, v, u) in found {
                if let have = facts[which]![k], have.value != v || have.unit != u { return nil }
                facts[which]![k] = (v, u); used.append(v)
            }
        }
        let wanted = key(ask[1]), target = sizeKey(ask[2]), other = target == "small" ? "large" : "small"
        guard facts[target]![wanted] == nil, let known = facts[other]![wanted], numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }) else { return nil }
        // The length scale factor, small to large, from what both are known to have.
        var scale: Double?, lead: [Step] = []
        for (k, small) in facts["small"]!.sorted(by: { $0.key < $1.key }) {
            guard let large = facts["large"]![k] else { continue }
            guard small.unit == large.unit, small.value > 0, large.value > small.value else { return nil }
            let p = power(k), value = pow(large.value / small.value, 1 / p)
            if let scale { guard abs(scale - value) < 1e-6 * scale else { return nil } } else {
                scale = value
                lead.append(Step("Scale factor for \(k)", "", [MathLine(.symbol("\(shown(large.value)) ÷ \(shown(small.value))"), amount(tidy(large.value / small.value)))]))
                if p > 1 { lead.append(Step("Scale factor for length", "Take the \(p == 3 ? "cube" : "square") root.", [MathLine(.symbol("\(p == 3 ? "∛" : "√")\(shown(tidy(large.value / small.value)))"), amount(tidy((value * 10000).rounded() / 10000)), relation: abs(value * 10000 - (value * 10000).rounded()) < 1e-6 ? "=" : "≈")])) }
            }
        }
        guard let scale else { return nil }
        let q = power(wanted), factor = target == "large" ? pow(scale, q) : pow(1 / scale, q)
        lead.append(Step("The \(wanted) of the \(target) \(noun)", "\(q == 1 ? "Lengths" : q == 2 ? "Areas" : "Volumes") go \(target == "large" ? "up" : "down") by the \(q == 1 ? "scale factor" : q == 2 ? "square of the scale factor" : "cube of the scale factor").",
                         [MathLine(.symbol("\(shown(known.value)) \(target == "large" ? "×" : "÷") \(shown(tidy((pow(scale, q) * 10000).rounded() / 10000)))"))]))
        guard let rounding = asAsked(known.value * factor, text) else { return nil }
        return told("\(wanted) of the \(target) \(noun)", [MathLine(amount(rounding.value), suffix: known.unit)], lead)
    }

    /// A ratio of two similar solids from another: "A and B are similar cuboids. surface area of A : surface area of B =
    /// 16 : 25. Work out volume of A : volume of B." (with the ratios to choose from, if read).
    private static func similarRatio(_ text: String) -> Problem? {
        let measure = #"(volume|capacity|(?:total )?surface area|area|height|length|width|radius|diameter|perimeter)"#
        let solid = #"(?:(?:prism|pyramid|solid|cylinder|cone|cuboid|cube|sphere|shape) )?"#
        guard let pair = groups(#"(?<![A-Za-z])((?-i:[A-Z])) and ((?-i:[A-Z])) are (?:mathematically )?similar\b"#, in: text), pair[1] != pair[2],
              let given = groups(#"\b\#(measure) of \#(solid)((?-i:[A-Z])) ?: ?\#(measure) of \#(solid)((?-i:[A-Z])) ?= ?(\d+) ?: ?(\d+)(?!\d|\.\d)"#, in: text),
              let ask = groups(#"\b(?:work out|find|calculate|write down) (?:the ratio )?(?:of )?(?:the )?\#(measure) of \#(solid)((?-i:[A-Z])) ?: ?(?:the )?\#(measure) of \#(solid)((?-i:[A-Z]))(?![A-Za-z]| ?=)"#, in: text),
              given[1].lowercased() == given[3].lowercased(), ask[1].lowercased() == ask[3].lowercased(), ask[1].lowercased() != given[1].lowercased(),
              Set([given[2], given[4]]) == Set([pair[1], pair[2]]), Set([ask[2], ask[4]]) == Set([pair[1], pair[2]]),
              let a = Int(given[5]), let b = Int(given[6]), a > 0, b > 0, a < 1_000_000, b < 1_000_000 else { return nil }
        func power(_ what: String) -> Int { let w = what.lowercased(); return w == "volume" || w == "capacity" ? 3 : w.contains("area") ? 2 : 1 }
        let p = power(given[1]), q = power(ask[1])
        // The lengths' ratio must come out whole: the square or cube roots of the two numbers.
        func wholeRoot(_ n: Int) -> Int? { let r = Int(pow(Double(n), 1 / Double(p)).rounded()); return Int(pow(Double(r), Double(p))) == n ? r : nil }
        guard let x = wholeRoot(a), let y = wholeRoot(b) else { return nil }
        var first = Int(pow(Double(x), Double(q))), second = Int(pow(Double(y), Double(q)))
        if ask[2] != given[2] { swap(&first, &second) }
        let g = gcd(first, second)
        let answer = "\(first / g) : \(second / g)"
        // Ratios to choose from: the answer has to be one of them, and their numbers aren't part of the sum.
        let choices = every(#"(?<![\d.])(\d+) ?: ?(\d+)(?![\d.])"#, in: text).filter { !($0[1] == given[5] && $0[2] == given[6]) }.map { "\($0[1]) : \($0[2])" }
        if !choices.isEmpty, !choices.contains(answer) { return nil }
        let offered = choices.flatMap { $0.components(separatedBy: " : ").compactMap(Double.init) }
        guard numbers(withoutNumbering(text)).allSatisfy({ [Double(a), Double(b)].contains($0) || offered.contains($0) }) else { return nil }
        let root = p == 1 ? "" : p == 2 ? "√" : "∛"
        let lead = [
            Step("Ratio of lengths", p == 1 ? "The \(given[1].lowercased())s are lengths." : "\(p == 2 ? "Areas go with the square" : "Volumes go with the cube") of the lengths, so take the \(p == 2 ? "square" : "cube") roots.",
                 [MathLine(.symbol("\(root)\(a) : \(root)\(b)"), .symbol("\(x) : \(y)"))]),
            Step("Ratio of \(ask[1].lowercased())s", q == 1 ? "Lengths are in that ratio." : "\(q == 2 ? "Square" : "Cube") each number.",
                 [MathLine(.symbol("\(ask[1].lowercased()) of \(ask[2]) : \(ask[1].lowercased()) of \(ask[4])"), .symbol(answer))]),
        ]
        return told("\(ask[1].lowercased()) of \(ask[2]) : \(ask[1].lowercased()) of \(ask[4])", [MathLine(.symbol(answer))], lead)
    }

    /// What a change to two measures does to the one made from them: "The mass is divided by 2 and the volume is multiplied
    /// by 4. What happens to the density?" or "The mass of solid A is 6 times the mass of solid B. The volume of solid A is
    /// 3 times the volume of solid B. The density of solid A is … times the density of solid B."
    private static func whatHappens(_ text: String) -> Problem? {
        let made: [(whole: String, top: String, bottom: String)] = [("density", "mass", "volume"), ("average speed", "distance", "time"), ("speed", "distance", "time"), ("pressure", "force", "area")]
        let change = #"(halved|doubled|trebled|tripled|quartered|multiplied by \d+(?:\.\d+)?|divided by \d+(?:\.\d+)?)"#
        func factor(_ written: String) -> Double? {
            let w = written.lowercased()
            if let f = groups(#"^(multiplied|divided) by (\d+(?:\.\d+)?)$"#, in: w), let k = Double(f[2]), k > 0 { return f[1] == "multiplied" ? k : 1 / k }
            return ["halved": 0.5, "doubled": 2, "trebled": 3, "tripled": 3, "quartered": 0.25][w]
        }
        // Two parts in view, one about each measure ("the density of A is … times", then "what happens to the average
        // speed?"): which is asked isn't known.
        let about = Set(made.filter { has("\\bwhat happens to the \($0.whole)\\b|\\bthe \($0.whole) of (?:solid |shape |object )?(?-i:[A-Z]) is\\b", text) }.map(\.top))
        guard about.count == 1 else { return nil }
        for m in made {
            var top: Double?, bottom: Double?, used: [Double] = []
            let asksChange = has("\\bwhat happens to the \(m.whole)\\b", text)
            let sentence = groups("\\bthe \(m.whole) of (?:solid |shape |object )?((?-i:[A-Z])) is (?:\\.+ |_+ |… )?times the \(m.whole) of (?:solid |shape |object )?((?-i:[A-Z]))\\b", in: text)
            if asksChange {
                guard let t = groups("\\b\(m.top) is \(change)", in: text), let b = groups("\\b\(m.bottom) is \(change)", in: text) else { continue }
                top = factor(t[1]); bottom = factor(b[1])
                used += numbers(t[1]) + numbers(b[1])
            } else if let sentence {
                let x = sentence[1], y = sentence[2]
                guard let t = groups("\\b\(m.top) of (?:solid |shape |object )?\(x) is (\(number)|[a-z]+) times the \(m.top) of (?:solid |shape |object )?\(y)\\b", in: text),
                      let b = groups("\\b\(m.bottom) of (?:solid |shape |object )?\(x) is (\(number)|[a-z]+) times the \(m.bottom) of (?:solid |shape |object )?\(y)\\b", in: text) else { continue }
                top = t[1].lowercased() == "twice" ? 2 : count(t[1]); bottom = b[1].lowercased() == "twice" ? 2 : count(b[1])
                used += [Double(t[1]), Double(b[1])].compactMap { $0 }
            } else { continue }
            guard let top, let bottom, top > 0, bottom > 0 else { return nil }
            let result = top / bottom
            // Changes to choose from ("× 2 ÷ 2 × 8 ÷ 8"): the answer has to be one of them.
            let offered = every(#"(?<![\dA-Za-z])([×x÷]) ?(\d+)(?![\d.])"#, in: text).map { "\($0[1].lowercased() == "÷" ? "÷" : "×") \($0[2])" }
            let offeredNumbers = every(#"(?<![\dA-Za-z])[×x÷] ?(\d+)(?![\d.])"#, in: text).compactMap { Double($0[1]) }
            guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) || offeredNumbers.contains($0) }), let simple = fraction(result) else { return nil }
            let lead = [
                Step("\(m.whole.prefix(1).uppercased() + m.whole.dropFirst()) is \(m.top) ÷ \(m.bottom)", "The \(m.top) is multiplied by \(shown(tidy(top))) and the \(m.bottom) by \(shown(tidy(bottom))).",
                     [MathLine(.symbol("\(shown(tidy(top))) ÷ \(shown(tidy(bottom)))"), .symbol(simple.d == 1 ? "\(simple.n)" : "\(simple.n)/\(simple.d)"))]),
            ]
            if asksChange {
                let answer = simple.n == simple.d ? "no change" : simple.d == 1 ? "× \(simple.n)" : simple.n == 1 ? "÷ \(simple.d)" : "× \(simple.n)/\(simple.d)"
                if !offered.isEmpty, answer != "no change", !offered.contains(answer) { return nil }
                return told("what happens to the \(m.whole)", [MathLine(.symbol(answer))], lead)
            }
            return told("how many times the \(m.whole)", [MathLine(.symbol(simple.d == 1 ? "\(simple.n)" : "\(simple.n)/\(simple.d)"))], lead)
        }
        return nil
    }

    /// A shape reflected in one of its own edges: "Quadrilateral ABCD is reflected in edge BC. How many of the vertices are
    /// invariant?" The two ends of the edge are on the mirror line and stay; every other vertex moves.
    private static func invariantOnEdge(_ text: String) -> Problem? {
        guard has(#"\binvariant\b"#, text), !has(#"\brotat|\btranslat|\benlarg"#, text), every(#"\breflect"#, in: text).count == 1,
              let shape = groups(#"\b(triangle|quadrilateral|rectangle|square|parallelogram|trapezium|kite|rhombus|pentagon|hexagon) ((?-i:[A-Z]{3,6})) is reflected in (?:the )?(?:edge|side|line|diagonal) ((?-i:[A-Z]{2}))(?![A-Za-z])"#, in: text) else { return nil }
        let corners = Array(shape[2]), mirror = Array(shape[3])
        let expected = ["triangle": 3, "pentagon": 5, "hexagon": 6][shape[1].lowercased()] ?? 4
        guard corners.count == expected, Set(corners).count == expected, mirror[0] != mirror[1], mirror.allSatisfy({ corners.contains($0) }) else { return nil }
        let lead = [Step("What invariant means", "A vertex is invariant when the reflection leaves it where it is: only the vertices on the mirror line, \(shape[3]). No other corner of the \(shape[1].lowercased()) can be on that line.",
                         [MathLine(.symbol("\(mirror[0]) and \(mirror[1])"))])]
        let digits = numbers(withoutNumbering(text))
        if has(#"\bhow many (?:of (?:the|its) )?vertices are invariant\b"#, text) {
            // Numbers to choose from must be small ones with 2 among them.
            guard digits.isEmpty || (digits.contains(2) && digits.allSatisfy({ $0 <= Double(expected) && $0 == $0.rounded() })) else { return nil }
            return told("invariant vertices", [MathLine(.integer(2))], lead)
        }
        guard digits.isEmpty, has(#"\bwhich (?:of the )?vertices are invariant\b|\bwrite down the (?:letters of the )?(?:vertices that are invariant|invariant vertices)\b"#, text) else { return nil }
        return told("invariant vertices", [MathLine(.symbol("\(mirror[0]) and \(mirror[1])"))], lead)
    }

    /// Maps and models made to a scale: "A map has a scale of 1 : 4000. On the map, the distance from a station to a museum
    /// is 7 cm. Is the actual distance more than 300 m?", "The scale of a map is 1 cm represents 25 m. The length of a path
    /// is 240 m. Work out the length, in centimetres, of the path on the map."
    private static func mapScale(_ text: String) -> Problem? {
        // How many times bigger the real thing is.
        var times: Double?, used: [Double] = [], scaleWords = ""
        if let f = groups(#"\bscale (?:of |is )?1 ?: ?(\#(big))(?!\d|\.\d| ?:)"#, in: text), let n = bigValue(f[1]), n > 1 {
            times = n; used += [1, n]; scaleWords = "1 : \(shown(n))"
        } else if let f = groups(#"\b1 ?(mm|cm) (?:on (?:a|the) (?:map|plan|drawing|model) )?(?:represents|to|=) (\#(number)) ?(mm|cm|m|km)\b"#, in: text),
                  let v = Double(f[2]), v > 0, let paper = millimetres(f[1]), let real = millimetres(f[3]) {
            times = v * real / paper; used += [1, v]; scaleWords = "1 \(f[1].lowercased()) to \(shown(v)) \(f[3].lowercased())"
        }
        guard let times, times > 1, every(#"\bscale\b"#, in: text).count <= 2 else { return nil }
        let thing = #"(?:map|plan|drawing|model|scale drawing)"#
        let asksForm = groups(#"\bin the form 1 ?: ?((?-i:[a-z]))\b"#, in: text)?[1]
        let drawn = groups(#"\bon the \#(thing)\b[^.?]{0,80}?\b(?:is|=) (\#(number)) ?(mm|cm)\b"#, in: text)
        let actual = groups(#"\b(?:length|distance|height|width)\b[^.?]{0,60}?\bis (\#(number)) ?(m|km)\b(?! ?\^)"#, in: text)
        let toPaper = groups(#"\b(?:work out|calculate|find) the (?:length|distance|height|width),? in (centimetres|millimetres|cm|mm),?[^.?]{0,60}\bon the \#(thing)\b"#, in: text)
        let decision = groups(#"\bis the (?:actual|real|true) (?:distance|length|height|width)\b[^.?]{0,80}?\b(more|greater|longer|less|shorter) than (\#(number)) ?(mm|cm|m|km)\b"#, in: text)
        let toReal = groups(#"\b(?:work out|calculate|find),? in (metres|kilometres|centimetres|m|km|cm),? the (?:actual |real |true )?(?:length|distance|height|width)\b"#, in: text)
            ?? groups(#"\b(?:work out|calculate|find) the (?:actual|real|true) (?:length|distance|height|width)\b[^.?]{0,80}?\bin (metres|kilometres|centimetres|m|km|cm)\b"#, in: text)
        // One thing asked, or it isn't clear which.
        let asked = [asksForm != nil, toPaper != nil, decision != nil, toReal != nil].filter { $0 }.count
        guard asked == 1 else { return nil }
        // (The scale itself as 1 : k is answered before this file is reached; with another part beside it, nothing is shown.)
        if asksForm != nil { return nil }
        if let toPaper {
            guard drawn == nil, let actual, let v = Double(actual[1]), let real = millimetres(actual[2]), let paper = millimetres(toPaper[1]) else { return nil }
            used.append(v)
            guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }), let rounding = asAsked(v * real / times / paper, text) else { return nil }
            let lead = [Step("Divide by the scale", "\(scaleWords), so the real length is \(shown(times)) times the length on the map. Change \(shown(v)) \(actual[2].lowercased()) to \(short(toPaper[1])) first.",
                             [MathLine(.symbol("\(shown(tidy(v * real / paper))) ÷ \(shown(times))"))])]
            return told("length on the map", [MathLine(amount(rounding.value), suffix: short(toPaper[1]))], lead)
        }
        guard actual == nil || decision != nil, let drawn, let v = Double(drawn[1]), let paper = millimetres(drawn[2]) else { return nil }
        used.append(v)
        let real = v * paper * times
        if let decision {
            guard let limit = Double(decision[2]), let unit = millimetres(decision[3]) else { return nil }
            used.append(limit)
            guard numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }), abs(real - limit * unit) > 1e-9 else { return nil }
            let value = tidy(real / unit), more = ["more", "greater", "longer"].contains(decision[1].lowercased())
            let lead = [Step("Multiply by the scale", "\(scaleWords): \(shown(v)) \(drawn[2].lowercased()) on the map is \(shown(v)) × \(shown(times)) = \(shown(tidy(v * times))) \(drawn[2].lowercased()), which is \(shown(value)) \(decision[3].lowercased()).", [MathLine(amount(value), suffix: decision[3].lowercased())]),
                        Step("Compare", "\(shown(value)) \(decision[3].lowercased()) against \(shown(limit)) \(decision[3].lowercased()).", [])]
            return told("actual distance", [MathLine(.symbol("\((real > limit * unit) == more ? "Yes" : "No"): \(shown(value)) \(decision[3].lowercased())"))], lead)
        }
        guard let toReal, let unit = millimetres(toReal[1]), numbers(withoutNumbering(text)).allSatisfy({ used.contains($0) }), let rounding = asAsked(real / unit, text) else { return nil }
        let lead = [Step("Multiply by the scale", "\(scaleWords): the real length is \(shown(times)) times the length on the \(has(#"\bmodel\b"#, text) ? "model" : "map").",
                         [MathLine(.symbol("\(shown(v)) × \(shown(times))"), amount(tidy(v * times)), suffix: drawn[2].lowercased())]),
                    Step("Change the units", "To \(short(toReal[1])).", [])]
        return told("real length", [MathLine(amount(rounding.value), suffix: short(toReal[1]))], lead)
    }

    /// "Here is a right-angled triangular prism. The ratio of the edges is a : b : c : d = 3 : 4 : 5 : 12. The volume of
    /// the prism is 1125 cm³. Work out the total length of all of the edges of the prism." Three of the four are the sides
    /// of the right-angled triangle (the only three that fit Pythagoras) and the other is the prism's length.
    private static func prismEdgeRatio(_ text: String) -> Problem? {
        guard has(#"\bright[- ]angled triangular prism\b"#, text),
              let ratio = groups(#"\bratio of the edges is (?-i:[a-z]) ?: ?(?-i:[a-z]) ?: ?(?-i:[a-z]) ?: ?(?-i:[a-z]) ?= ?(\d+) ?: ?(\d+) ?: ?(\d+) ?: ?(\d+)(?!\d|\.\d)"#, in: text),
              let volume = groups(#"\bvolume of the prism is (\#(number)) ?(mm|cm|m) ?(?:\^?3|\?|³)"#, in: text), let v = Double(volume[1]), v > 0,
              has(#"\b(?:work out|find|calculate) the total length of all (?:of )?the edges\b"#, text) else { return nil }
        let parts = (1...4).compactMap { Double(ratio[$0]) }
        guard parts.count == 4, parts.allSatisfy({ $0 > 0 }) else { return nil }
        var fits: [(a: Double, b: Double, c: Double, length: Double)] = []
        for skip in 0..<4 {
            let triangle = parts.enumerated().filter { $0.offset != skip }.map(\.element).sorted()
            if abs(triangle[0] * triangle[0] + triangle[1] * triangle[1] - triangle[2] * triangle[2]) < 1e-9 { fits.append((triangle[0], triangle[1], triangle[2], parts[skip])) }
        }
        guard fits.count == 1, let f = fits.first, numbers(withoutNumbering(text)).allSatisfy({ parts.contains($0) || $0 == v }) else { return nil }
        let each = 0.5 * f.a * f.b * f.length, k = cbrt(v / each)
        let edges = 2 * (f.a + f.b + f.c) + 3 * f.length
        let unit = volume[2].lowercased()
        let lead = [
            Step("Which edges are which", "\(shown(f.a)), \(shown(f.b)) and \(shown(f.c)) fit Pythagoras, so they are the triangle, and \(shown(f.length)) is the length of the prism. Call the edges \(shown(f.a))k, \(shown(f.b))k, \(shown(f.c))k and \(shown(f.length))k.", []),
            Step("Use the volume", "Area of the triangle × length: ½ × \(shown(f.a))k × \(shown(f.b))k × \(shown(f.length))k.", [MathLine(.symbol("\(shown(each))k³"), amount(v)), MathLine(.symbol("k"), amount(tidy((k * 10000).rounded() / 10000)), relation: abs(k * 10000 - (k * 10000).rounded()) < 1e-6 ? "=" : "≈")]),
            Step("Add up the edges", "Two triangles and three edges along the length: 2 × (\(shown(f.a)) + \(shown(f.b)) + \(shown(f.c)))k + 3 × \(shown(f.length))k.", [MathLine(.symbol("\(shown(edges))k"))]),
        ]
        guard let rounding = asAsked(edges * k, text) else { return nil }
        return told("total length of the edges", [MathLine(amount(rounding.value), suffix: unit)], lead)
    }

    /// "A solid shape is made by joining two cones. Each cone has the same radius. One cone has slant height = 2 × radius.
    /// The other cone has slant height = 3 × radius. The total surface area of the shape is 57.8π cm². Work out the
    /// radius." The circles are joined, so the surface is the two curved parts.
    private static func twoCones(_ text: String) -> Problem? {
        let words = withoutFormulae(text)
        guard has(#"\bsolid shape is made by joining two cones\b"#, words), has(#"\b(?:each cone has|the cones have|both cones have) the same radius\b"#, words),
              let surface = groups(#"\btotal surface area of the (?:solid )?shape is (\#(number)) ?π ?(mm|cm|m) ?\^?2"#, in: words), let s = Double(surface[1]), s > 0,
              has(#"\b(?:work out|find|calculate) the radius\b"#, words) else { return nil }
        let slants = every(#"\bslant height ?(?:=|is) ?(\#(number)) ?[×x*] ?(?:the )?radius\b"#, in: words).compactMap { Double($0[1]) }
        guard slants.count == 2, slants.allSatisfy({ $0 >= 1 }), numbers(withoutNumbering(words)).allSatisfy({ slants.contains($0) || $0 == s }) else { return nil }
        let r = (s / (slants[0] + slants[1])).squareRoot()
        let lead = [
            Step("The surface", "The two circles are joined together, so the surface is the two curved parts: π × r × slant height for each.",
                 [MathLine(.symbol("π × r × \(shown(slants[0]))r + π × r × \(shown(slants[1]))r"), .symbol("\(shown(slants[0] + slants[1]))πr²"))]),
            Step("Find r", "Make it equal to \(shown(s))π and divide by \(shown(slants[0] + slants[1]))π.", [MathLine(.symbol("r²"), amount(tidy(s / (slants[0] + slants[1]))))]),
        ]
        guard let rounding = asAsked(r, text) else { return nil }
        return told("radius", [MathLine(.symbol("r"), amount(rounding.value), relation: rounding.relation, suffix: surface[2].lowercased())], lead)
    }

    /// Two round solids with their sizes in the words: "Here are two solids. Cylinder: radius 4 cm, height 10 cm.
    /// Hemisphere: radius 6 cm. Which solid has the greater volume?"
    private static func greaterVolume(_ text: String) -> Problem? {
        let words = withoutFormulae(text)
        guard let ask = groups(#"\bwhich (?:solid|shape|one) has the (greater|larger|bigger|greatest|largest|smaller|smallest|lesser|least) volume\b"#, in: words)?[1].lowercased(),
              let regex = try? NSRegularExpression(pattern: #"\b(cylinder|hemisphere|sphere|cone)\b"#, options: [.caseInsensitive]) else { return nil }
        let marks = regex.matches(in: words, range: NSRange(words.startIndex..., in: words))
        guard marks.count == 2 else { return nil }
        var solids: [(name: String, volume: (n: Int, d: Int), working: String)] = [], used: [Double] = [], units: Set<String> = []
        for (i, m) in marks.enumerated() {
            let end = i + 1 < marks.count ? marks[i + 1].range.location : (words as NSString).length
            let clause = (words as NSString).substring(with: NSRange(location: m.range.location, length: end - m.range.location))
            let kind = (words as NSString).substring(with: m.range).lowercased()
            let radii = every(#"\b(radius|diameter) (?:of |is |= ?)?(\#(number)) ?(mm|cm|m)\b(?! ?\^)"#, in: clause)
            let heights = every(#"\bheight (?:of |is |= ?)?(\#(number)) ?(mm|cm|m)\b(?! ?\^)"#, in: clause)
            let needsHeight = kind == "cylinder" || kind == "cone"
            guard radii.count == 1, heights.count == (needsHeight ? 1 : 0), let size = Double(radii[0][2]), size > 0, let f = fraction(radii[0][1].lowercased() == "radius" ? size : size / 2) else { return nil }
            used.append(size); units.insert(radii[0][3].lowercased())
            let r = shown(Double(f.n) / Double(f.d))
            var volume: (n: Int, d: Int), working: String
            if needsHeight {
                guard let h = Double(heights[0][1]), h > 0, let hf = fraction(h) else { return nil }
                used.append(h); units.insert(heights[0][2].lowercased())
                volume = lowest(f.n * f.n * hf.n * (kind == "cone" ? 1 : 3), f.d * f.d * hf.d * 3)
                working = "\(kind == "cone" ? "⅓ × " : "")π × \(r)² × \(shown(h))"
            } else {
                volume = lowest(f.n * f.n * f.n * (kind == "sphere" ? 4 : 2), f.d * f.d * f.d * 3)
                working = "\(kind == "sphere" ? "4/3" : "⅔") × π × \(r)³"
            }
            solids.append((kind, volume, working))
        }
        // The formula box's fractions may be read as loose numbers.
        let formulae: [Double] = has(#"\bvolume of an? [a-z]+ ?="#, text) ? [1, 2, 3, 4] : []
        guard solids[0].name != solids[1].name, units.count == 1, let unit = units.first,
              numbers(withoutNumbering(words)).allSatisfy({ used.contains($0) || formulae.contains($0) }) else { return nil }
        let a = solids[0], b = solids[1], left = a.volume.n * b.volume.d, right = b.volume.n * a.volume.d
        guard left != right else { return nil }
        let wantsGreater = !["smaller", "smallest", "lesser", "least"].contains(ask)
        let winner = (left > right) == wantsGreater ? a : b, loser = winner.name == a.name ? b : a
        var lead = solids.map { Step("Volume of the \($0.name)", "", [MathLine(.symbol($0.working), .symbol(piTimes($0.volume)), suffix: "\(unit)³")]) }
        lead.append(Step("Compare", "Both are a number of π, so compare the numbers.", []))
        return told("the \(ask) volume", [MathLine(.symbol("\(winner.name.prefix(1).uppercased() + winner.name.dropFirst()): \(piTimes(winner.volume)) \(unit)³ against \(piTimes(loser.volume)) \(unit)³"))], lead)
    }
}
