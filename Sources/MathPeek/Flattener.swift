import CoreGraphics
import CoreText
import Foundation

/// Maths set out in two dimensions, laid out again on one line so that it can be read: a
/// fraction with one thing over another becomes (top)/(bottom), a root with a bar over what
/// it's the root of becomes sqrt(…). Text recognition reads lines; given a fraction it reads
/// the top as one line and the bottom as another, or neither. The ink shows where the bars
/// are, and each piece is cut out and set down again in a row, which reads like any other.
struct Flattener {
    let ink: Ink

    /// A fraction or a root, in the picture's pixels.
    enum Structure {
        case fraction(top: CGRect, bottom: CGRect, bar: CGRect)
        /// `index` is the small number in the crook of the sign, the 3 of a cube root.
        case root(inside: CGRect, sign: CGRect, index: CGRect? = nil)

        var box: CGRect {
            switch self {
            case .fraction(let top, let bottom, let bar): top.union(bottom).union(bar)
            case .root(let inside, let sign, _): inside.union(sign)
            }
        }

        /// The height its line runs along: the bar of a fraction, the middle of a root.
        var axis: CGFloat {
            switch self {
            case .fraction(_, _, let bar): bar.midY
            case .root(let inside, _, _): inside.midY
            }
        }
    }

    /// One piece of a row: a stretch of the line copied from the picture as it is, the top
    /// or bottom of a fraction (or the inside of a root) set down on the line, or a sign drawn in.
    enum Piece {
        case stretch(CGRect)
        case part(CGRect)
        case sign(String)
    }

    /// A line of maths with fractions or roots in it, as the pieces of the row it becomes.
    struct Expression {
        /// `group` numbers the fraction or root a piece is part of; a stretch of the line has none.
        var pieces: [(piece: Piece, source: CGRect, group: Int?)]
        /// Everything it covers in the picture, and the height of a capital in it.
        var region: CGRect
        var tall: CGFloat
        /// The line the text sits on.
        var baseline: CGFloat
    }

    // MARK: Finding fractions and roots

    /// The fractions and roots in part of the picture. `tall` is the height of a capital there.
    func structures(in area: CGRect, tall: CGFloat) -> [Structure] {
        structures(in: area, tall: tall, mayGrow: true)
    }

    private func structures(in area: CGRect, tall: CGFloat, mayGrow: Bool) -> [Structure] {
        // A bar that the edge of the area cuts through is a fraction seen in part, and would
        // be taken for a narrower one: its whole length is found along its own rows, and the
        // area takes that in. (A rule right across the area, or one too long for a fraction,
        // isn't a fraction's bar and is left cut.)
        let picture = CGRect(x: 0, y: 0, width: ink.width, height: ink.height)
        var area = area.intersection(picture)
        var all = ink.patches(in: area)
        let left = area.minX.rounded(.down), right = area.maxX.rounded(.up) - 1
        var wider = area
        for bar in all where CGFloat(bar.height) <= max(3, tall * 0.16) && CGFloat(bar.width) >= tall * 0.35 && CGFloat(bar.width) < area.width * 0.8 {
            let cutLeft = left > 0 && CGFloat(bar.minX) <= left, cutRight = right < picture.maxX - 1 && CGFloat(bar.maxX) >= right
            guard cutLeft != cutRight else { continue }
            let strip = CGRect(x: bar.box.minX - tall * 25, y: bar.box.minY - 1, width: bar.box.width + tall * 50, height: bar.box.height + 2).intersection(picture)
            guard let whole = ink.patches(in: strip).first(where: { $0.minX <= bar.maxX && $0.maxX >= bar.minX && $0.width >= bar.width }),
                  CGFloat(whole.width) <= tall * 25, CGFloat(whole.height) <= max(3, tall * 0.16) + 2 else { continue }
            wider = wider.union(CGRect(x: whole.box.minX - tall, y: area.minY, width: whole.box.width + tall * 2, height: area.height))
        }
        if wider != area {
            area = wider.intersection(picture)
            all = ink.patches(in: area)
        }
        guard all.count >= 2, all.count <= 600 else { return [] }
        var found: [Structure] = []
        let sizeable = all.filter { CGFloat($0.height) >= tall * 0.3 }
        for bar in all {
            let box = bar.box
            guard box.height <= max(3, tall * 0.16), box.width >= max(tall * 0.35, box.height * 4) else { continue }
            // What's over it and under it: the line of ink nearest the bar in the column over
            // it. A line's characters all start within about half their height of each other
            // (a power sits that much higher); anything further off is the next line.
            // A short bar is given more room: exam papers set a fraction further from its bar
            // than a web page does, and a small letter under one, the x of 1/x, starts lower
            // still. That much more only when there's a real gap over the bar, which an
            // underline hasn't.
            let isShort = box.width <= tall * 6
            func part(above: Bool, within limit: CGFloat) -> (region: CGRect, gap: CGFloat)? {
                func near(_ other: Ink.Patch) -> CGFloat { above ? box.minY - other.box.maxY : other.box.minY - box.maxY }
                let column = all.filter { other in
                    other.box != box && other.box.midX >= box.minX - 1 && other.box.midX <= box.maxX + 1 && near(other) >= 0
                }.sorted { near($0) < near($1) }
                guard let first = column.first(where: { CGFloat($0.height) >= tall * 0.25 }), near(first) <= limit else { return nil }
                // As far as the line of ink nearest the bar goes. Over the bar that takes in a
                // power, which stands higher than what it's on: 3¹² over 3⁷.
                // (Under the bar, the nearest ink can be a mark set high, the ring of
                // cos 58.7°: the reach goes by the tallest of what starts about level with it.)
                let lead = column.filter { near($0) <= near(first) + tall * 0.35 }.map { CGFloat($0.height) }.max() ?? CGFloat(first.height)
                let reach = near(first) + (above ? max(CGFloat(first.height), tall) * 0.95 : min(lead, tall * 1.2) * 0.6)
                var region = column.filter { near($0) <= reach }.reduce(CGRect.null) { $0.union($1.box) }
                guard !region.isNull else { return nil }
                // A part can run on past the end of its bar, "√10" under a bar that stops at
                // the 1: ink hard up against the part, on its own rows, belongs to it. (What
                // stands beside a fraction on the line itself is level with the bar, half in
                // these rows at most.)
                var grew = true
                while grew {
                    grew = false
                    for other in all where other.box != box && CGFloat(other.height) >= tall * 0.25 && !region.insetBy(dx: -1, dy: -1).contains(other.box) {
                        let shared = min(other.box.maxY, region.maxY) - max(other.box.minY, region.minY)
                        let gap = max(other.box.minX - region.maxX, region.minX - other.box.maxX)
                        guard shared >= other.box.height * 0.6, gap >= -1, gap <= tall * 0.25,
                              above ? other.box.maxY <= box.minY : other.box.minY >= box.maxY else { continue }
                        region = region.union(other.box)
                        grew = true
                    }
                }
                return region.height < tall * 0.3 || region.height > tall * 1.9 ? nil : (region, near(first))
            }
            let usual = tall * (isShort ? 0.7 : 0.5)
            let over = part(above: true, within: usual)
            let under = part(above: false, within: isShort && (over?.gap ?? 0) >= tall * 0.3 ? tall * 1.1 : usual)
            if let top = over?.region, let bottom = under?.region {
                // The bar is about as wide as what it divides: a rule across a page isn't one.
                guard box.width <= max(top.width, bottom.width) * 1.6 + tall else { continue }
                // With more room than usual round its bar it has to be plainly a fraction:
                // hardly wider than what it divides, and not one of the rules of a table,
                // which come one under another.
                if (over?.gap ?? 0) > tall * 0.5 || (under?.gap ?? 0) > tall * 0.5 {
                    guard box.width <= max(top.width, bottom.width) + tall * 0.8 else { continue }
                    let isRule = all.contains { other in
                        other.box != box && CGFloat(other.height) <= max(3, tall * 0.16) && abs(other.box.minX - box.minX) <= 3
                            && abs(other.box.width - box.width) <= 4 && abs(other.box.midY - box.midY) <= tall * 6
                    }
                    if isRule { continue }
                }
                found.append(.fraction(top: top, bottom: bottom, bar: box))
            } else if over == nil, let under = part(above: false, within: tall * 0.5)?.region,
                      box.width <= under.width * 1.6 + tall,
                      let sign = all.first(where: { other in
                          // A root sign just before the bar, reaching up to it: a tick with
                          // some width to it, where the upright rule of a table has none.
                          other.box != box && CGFloat(other.height) >= tall * 0.8 && CGFloat(other.height) <= tall * 2.6 && CGFloat(other.width) >= tall * 0.25
                              && other.box.maxX >= box.minX - tall * 0.4
                              && other.box.maxX <= box.minX + tall * 0.35 && abs(other.box.minY - box.minY) <= tall * 0.25
                      }) {
                let whole = sign.box.union(box)
                found.append(.root(inside: under, sign: whole, index: index(of: whole, before: under, among: all, tall: tall)))
            }
        }
        // A root sign drawn in one piece with its bar: a patch with other ink inside its box,
        // a line along its top, and (unlike a box round something) nothing along its bottom
        // or down its right.
        // (Whole, inside the area: the rules of a table that the area cuts through have a line
        // along the top and nothing down the right either.)
        let edges = (left: area.minX.rounded(.down), top: area.minY.rounded(.down), right: area.maxX.rounded(.up) - 1, bottom: area.maxY.rounded(.up) - 1)
        for sign in all {
            let box = sign.box
            guard box.height >= tall * 0.9, box.height <= tall * 2.4, box.width >= tall * 0.9 else { continue }
            guard CGFloat(sign.minX) > edges.left, CGFloat(sign.maxX) < edges.right, CGFloat(sign.minY) > edges.top, CGFloat(sign.maxY) < edges.bottom else { continue }
            let inside = sizeable.filter { other in
                other.box != box && other.box.minX >= box.minX + 2 && other.box.midX <= box.maxX
                    && other.box.minY > box.minY + 1 && other.box.maxY <= box.maxY + tall * 0.2
            }
            // The bar covers at least one character whole: the short stub that a root sign
            // has in many fonts only reaches part-way over the first.
            guard let first = inside.map(\.box.minX).min(), inside.contains(where: { $0.box.maxX <= box.maxX + 1 }) else { continue }
            let band = max(3, tall * 0.14)
            let top = ink.longestRun(in: CGRect(x: box.minX, y: box.minY, width: box.width, height: band))
            let bottom = ink.longestRun(in: CGRect(x: box.minX, y: box.maxY - band, width: box.width, height: band))
            let right = ink.longestRun(in: CGRect(x: box.maxX - band, y: box.minY + band, width: band, height: box.height - band), down: true)
            guard CGFloat(top) >= (box.maxX - first) * 0.8, CGFloat(bottom) <= box.width * 0.3, CGFloat(right) <= box.height * 0.4 else { continue }
            let content = inside.reduce(CGRect.null) { $0.union($1.box) }
            // Everything under the bar, down to the bottom of the sign: small marks too.
            let under = CGRect(x: first - 1, y: box.minY + band + 1, width: max(content.maxX, box.maxX) - first + 2, height: max(content.maxY, box.maxY) - box.minY - band)
            found.append(.root(inside: under, sign: box, index: index(of: box, before: under, among: all, tall: tall)))
        }
        // One that runs into the top or bottom of the area is cut short, the root sign under
        // a bar when only the top of the fraction was read as text: looked for again with
        // more room that way.
        if mayGrow {
            let top = area.minY.rounded(.down), bottom = area.maxY.rounded(.up) - 1
            let cutAbove = top > 0 && found.contains { $0.box.minY <= top + 1 }
            let cutBelow = bottom < picture.maxY - 1 && found.contains { $0.box.maxY >= bottom - 1 }
            if cutAbove || cutBelow {
                let taller = CGRect(x: area.minX, y: area.minY - (cutAbove ? tall * 2 : 0), width: area.width,
                                    height: area.height + (cutAbove ? tall * 2 : 0) + (cutBelow ? tall * 2 : 0))
                return structures(in: taller, tall: tall, mayGrow: false)
            }
        }
        return found
    }

    /// The small number in the crook of a root sign, the 3 of a cube root: over the sign's
    /// short stroke, to the left of what the root is of. Without it the root is a square root.
    private func index(of sign: CGRect, before inside: CGRect, among all: [Ink.Patch], tall: CGFloat) -> CGRect? {
        all.map(\.box).first { patch in
            patch != sign && patch.height >= tall * 0.3 && patch.height <= tall * 0.85 && patch.width <= tall * 0.8
                && patch.maxX <= inside.minX - 2 && patch.minX >= sign.minX - tall * 0.4
                && patch.midY <= sign.midY && patch.minY >= sign.minY - tall * 0.3
        }
    }

    // MARK: Putting a line together

    /// The lines of maths that `structures` are in, each as the pieces of a row.
    func expressions(from structures: [(structure: Structure, tall: CGFloat)]) -> [Expression] {
        let heights = structures.map(\.tall)
        let structures = structures.map(\.structure)
        // No two of the same, and none inside another: a fraction under a root, or a root in
        // a fraction, is more than one row can hold.
        // Found from the small text of its top it looks smaller than it is: the tallest
        // estimate of the capitals round it is the line's.
        // Found more than once, at different sizes of text: the smallest size it was found
        // at. Too big a size comes of measuring a line whose fractions run together; the
        // text of the line itself puts right one that's too small, below.
        var unique: [Structure] = []
        var sizes: [CGFloat] = []
        for (index, structure) in structures.enumerated() {
            if let same = unique.firstIndex(where: { isSameKind($0, structure) && isSame($0, structure) }) {
                sizes[same] = min(sizes[same], heights[index])
            } else {
                unique.append(structure)
                sizes.append(heights[index])
            }
        }
        // A root in the top or bottom of a fraction, 3 over 5√x, isn't always found from the
        // text round it: each fraction is looked through for one.
        for index in unique.indices {
            guard case .fraction = unique[index] else { continue }
            for structure in self.structures(in: unique[index].box.insetBy(dx: -3, dy: -3), tall: sizes[index]) {
                guard case .root = structure, !unique.contains(where: { isSameKind($0, structure) && isSame($0, structure) }) else { continue }
                unique.append(structure)
                sizes.append(sizes[index])
            }
        }
        // One inside another. A root that's wholly in the top or the bottom of a fraction is
        // read as part of it; anything else is spoiled, and so is what it's in.
        var spoiled = Set<Int>()
        var inner: [Int: [Int]] = [:]
        func isInside(_ index: Int, _ other: Int) -> Bool {
            unique[other].box.insetBy(dx: -2, dy: -2).contains(unique[index].box)
                && unique[index].box.width * unique[index].box.height < unique[other].box.width * unique[other].box.height * 0.8
        }
        func isRoot(_ index: Int, inPartOf other: Int) -> Bool {
            guard isInside(index, other), case .root = unique[index], case .fraction(let over, let under, _) = unique[other] else { return false }
            return over.insetBy(dx: -2, dy: -2).contains(unique[index].box) || under.insetBy(dx: -2, dy: -2).contains(unique[index].box)
        }
        for index in unique.indices {
            for other in unique.indices where other != index {
                if isRoot(index, inPartOf: other) {
                    inner[other, default: []].append(index)
                } else if isRoot(other, inPartOf: index) {
                    continue
                } else if isInside(index, other) || (!isSameKind(unique[index], unique[other]) && isSame(unique[index], unique[other])) {
                    spoiled.insert(index)
                    spoiled.insert(other)
                }
            }
        }
        for (holder, roots) in inner where roots.contains(where: spoiled.contains) { spoiled.insert(holder) }
        var used = spoiled.union(inner.values.joined())
        var result: [Expression] = []
        for index in unique.indices.sorted(by: { unique[$0].box.minX < unique[$1].box.minX }) where !used.contains(index) {
            var height = sizes[index]
            let axis = unique[index].axis
            // The line through it: ink whose middle is near its height, as far each way as it
            // goes without a wide gap.
            let reach = height * 30
            let band = CGRect(x: unique[index].box.minX - reach, y: axis - height * 1.25, width: unique[index].box.width + 2 * reach, height: height * 2.3)
            let level = unique.indices.filter { !used.contains($0) && abs(unique[$0].axis - axis) <= height * 0.45 }
            // (A power stands higher than the rest of the line: the 2 of ½at², which is the
            // last thing in it, would be left off the end.)
            let inBand = ink.patches(in: band).map(\.box).filter { patch in !unique.contains { $0.box.insetBy(dx: -1, dy: -1).intersects(patch) } }
            let onAxis = inBand.filter { abs($0.midY - axis) <= height * 0.75 }
            // (Whole, small, and straight after something on the line: the bottoms of the
            // line above reach into the band too, cut off by its edge.)
            let bandTop = band.minY
            func isRaisedMark(_ patch: CGRect) -> Bool {
                guard patch.midY < axis - height * 0.75, patch.midY >= axis - height * 1.1, patch.minY > bandTop + 1, patch.height <= height * 0.85 else { return false }
                return onAxis.contains { base in
                    let gap = patch.minX - base.maxX
                    return base.height >= height * 0.4 && gap >= -height * 0.15 && gap <= height * 0.6 && base.minY > patch.minY
                }
            }
            let ordinary = onAxis + inBand.filter(isRaisedMark)
            var members = [index]
            var extent = unique[index].box
            var glyphs: [CGRect] = []
            var grew = true
            while grew {
                grew = false
                for other in level where !members.contains(other) && gap(unique[other].box, extent) <= height * 1.7 {
                    members.append(other)
                    extent = extent.union(unique[other].box)
                    grew = true
                }
                for glyph in ordinary where !glyphs.contains(glyph) && gap(glyph, extent) <= height * 1.7 {
                    glyphs.append(glyph)
                    extent = extent.union(glyph)
                    grew = true
                }
            }
            used.formUnion(members)
            // The ordinary text of the line says how big its capitals are, if there's
            // enough of it: bigger than the top of a fraction suggested, often.
            let full = glyphs.map(\.height).filter { $0 >= height * 0.45 }.sorted()
            if full.count >= 2, full[full.count / 2] > height * 1.15 { height = min(full[full.count / 2], height * 1.8) }
            // Where the ordinary text sits: the level most of its ink ends at.
            let bottoms = glyphs.filter { $0.height >= height * 0.5 }.map(\.maxY).sorted()
            let baseline = bottoms.isEmpty ? axis + height * 0.36 : bottoms[bottoms.count / 2]
            let top = baseline - height * 1.35, bottom = baseline + height * 0.5

            // Round brackets drawn tall, to the height of a fraction: too tall to read along
            // with the line. They're known by their shape, and written in.
            let around = CGRect(x: extent.minX - height * 2, y: axis - height * 2.6, width: extent.width + height * 4, height: height * 5.2)
            var brackets: [(box: CGRect, sign: String)] = []
            for patch in ink.patches(in: around).map(\.box) where patch.height >= height * 1.5 && patch.width <= patch.height * 0.4 {
                guard gap(patch, extent) <= height * 0.5, let sign = ink.bracket(patch) else { continue }
                brackets.append((patch, sign))
            }
            glyphs.removeAll { glyph in brackets.contains { $0.box.insetBy(dx: -1, dy: -1).intersects(glyph) } }
            for bracket in brackets { extent = extent.union(bracket.box) }

            // A fraction set small and high, straight after something on this line, is a
            // power: (9/16) to the −3/2. A dash just before it, at the height of its bar, is
            // its minus sign.
            func size(_ structure: Structure) -> CGFloat {
                if case .fraction(let over, let under, _) = structure { return max(over.height, under.height) }
                return structure.box.height
            }
            let raised = unique.indices.filter { other in
                guard !used.contains(other), case .fraction = unique[other] else { return false }
                let box = unique[other].box
                return unique[other].axis <= baseline - height * 0.9 && box.maxY <= baseline - height * 0.15 && size(unique[other]) <= height * 0.9
                    && box.minX >= extent.minX + height * 0.5 && box.minX - extent.maxX <= height * 1.2
            }
            used.formUnion(raised)
            func minus(before structure: Structure) -> CGRect? {
                let small = size(structure), box = structure.box
                let area = CGRect(x: box.minX - small * 1.6, y: structure.axis - small * 0.45, width: small * 1.6 - 1, height: small * 0.9)
                return ink.patches(in: area).map(\.box).first { $0.height <= max(2, small * 0.2) && $0.width >= small * 0.3 && $0.width <= small * 1.2 }
            }
            let minuses = raised.map { minus(before: unique[$0]) }
            let powers = zip(raised, minuses).map { index, minus in minus.map { unique[index].box.union($0) } ?? unique[index].box }

            // Anything else set high straight after a tall closing bracket is a power too,
            // (9/16)²: without it the line would be another sum.
            var high: [CGRect] = []
            for bracket in brackets where bracket.sign == ")" {
                let top = bracket.box.minY - height * 0.5
                let area = CGRect(x: bracket.box.maxX, y: top, width: height * 2.5, height: baseline - height * 0.9 - top)
                let marks = ink.patches(in: area).map(\.box).filter { patch in
                    patch.height >= 2 && !powers.contains { $0.insetBy(dx: -2, dy: -2).intersects(patch) }
                }.sorted { $0.minX < $1.minX }
                guard let first = marks.first, first.minX - bracket.box.maxX <= height * 0.6 else { continue }
                var box = first
                for patch in marks.dropFirst() where patch.minX - box.maxX <= height * 0.5 { box = box.union(patch) }
                high.append(box)
            }

            /// What stands in the line besides its ordinary text, left to right.
            enum Mark { case structure(Int), power(Int, hasMinus: Bool, box: CGRect), bracket(CGRect, String), high(CGRect) }
            var marks: [(at: CGFloat, mark: Mark)] = members.map { (unique[$0].box.minX, .structure($0)) }
            marks += brackets.map { ($0.box.minX, .bracket($0.box, $0.sign)) }
            marks += zip(zip(raised, minuses), powers).map { ($1.minX, .power($0.0, hasMinus: $0.1 != nil, box: $1)) }
            marks += high.map { ($0.minX, .high($0)) }

            var pieces: [(piece: Piece, source: CGRect, group: Int?)] = []
            var cursor = extent.minX - 2
            func plain(upTo edge: CGFloat) {
                let stretch = glyphs.filter { $0.midX > cursor && $0.midX < edge }
                guard let first = stretch.map(\.minX).min(), let last = stretch.map(\.maxX).max(), let highest = stretch.map(\.minY).min() else { return }
                // …and tall enough for a power set high.
                let top = min(top, highest - 1)
                let box = CGRect(x: first - 1, y: top, width: last - first + 2, height: bottom - top)
                pieces.append((.stretch(box), box, nil))
            }
            /// A fraction, as its top, a slash and its bottom: brackets only where they're
            /// needed, a number on its own has none.
            func fraction(_ over: CGRect, _ under: CGRect, at source: CGRect, group: Int) {
                let roots = (inner[group] ?? []).map { unique[$0] }
                let inTop = roots.filter { over.insetBy(dx: -2, dy: -2).contains($0.box) }
                let inBottom = roots.filter { under.insetBy(dx: -2, dy: -2).contains($0.box) }
                let bareTop = bareRoots(in: over), bareBottom = bareRoots(in: under)
                let simpleTop = inTop.isEmpty && bareTop.isEmpty && isSingle(over, height)
                let simpleBottom = inBottom.isEmpty && bareBottom.isEmpty && isSingle(under, height)
                if !simpleTop { pieces.append((.sign("("), source, group)) }
                part(over.insetBy(dx: -1, dy: -1), roots: inTop, bare: bareTop, at: source, group: group)
                pieces.append((.sign(simpleTop ? "/" : ")/"), source, group))
                if !simpleBottom { pieces.append((.sign("("), source, group)) }
                part(under.insetBy(dx: -1, dy: -1), roots: inBottom, bare: bareBottom, at: source, group: group)
                if !simpleBottom { pieces.append((.sign(")"), source, group)) }
            }
            /// Root signs printed with no bar, in the top or bottom of a fraction: known by
            /// their shape, and by standing as tall as the digits beside them or taller. Read along
            /// with those digits they turn them into letters ("OГО" for 3√2), so each is
            /// written in as a sign and the digits are read without it.
            func bareRoots(in part: CGRect) -> [CGRect] {
                let glyphs = ink.glyphs(in: part.insetBy(dx: -1, dy: -1)).filter { $0.height >= height * 0.25 }
                let signs = glyphs.filter { ink.isRootSign($0) }
                guard !signs.isEmpty, let others = glyphs.filter({ !signs.contains($0) }).map(\.height).max() else { return [] }
                return signs.filter { $0.height >= others * 0.9 }
            }
            /// A root: the sign, and what it's of in brackets. A cube root, or a fourth, is
            /// what it's of to the power of one over the number in its crook.
            func root(_ inside: CGRect, index: CGRect?, at source: CGRect, group: Int) {
                if let index {
                    pieces.append((.sign("("), source, group))
                    pieces.append((.part(inside), source, group))
                    pieces.append((.sign(")^(1/"), source, group))
                    pieces.append((.part(index.insetBy(dx: -1, dy: -1)), source, group))
                    pieces.append((.sign(")"), source, group))
                } else {
                    pieces.append((.sign("√("), source, group))
                    pieces.append((.part(inside), source, group))
                    pieces.append((.sign(")"), source, group))
                }
            }
            /// The top or bottom of a fraction: as it stands, or, with a root in it, what's
            /// before the root, the root, and what's after it.
            func part(_ box: CGRect, roots: [Structure], bare: [CGRect] = [], at source: CGRect, group: Int) {
                let bare = bare.filter { sign in !roots.contains { $0.box.insetBy(dx: -1, dy: -1).intersects(sign) } }
                guard !roots.isEmpty || !bare.isEmpty else {
                    pieces.append((.part(box), source, group))
                    return
                }
                var from = box.minX
                func plain(to edge: CGFloat) {
                    let strip = CGRect(x: from, y: box.minY, width: edge - from, height: box.height)
                    let marks = strip.width > 2 ? ink.patches(in: strip).map(\.box).filter { $0.height >= 2 } : []
                    guard !marks.isEmpty else { return }
                    pieces.append((.part(marks.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -1, dy: -1)), source, group))
                }
                let signs: [(at: CGFloat, barred: Structure?, bare: CGRect)] = roots.map { ($0.box.minX, $0, .null) } + bare.map { ($0.minX, nil, $0) }
                for sign in signs.sorted(by: { $0.at < $1.at }) {
                    if let structure = sign.barred, case .root(let inside, let stroke, let index) = structure {
                        plain(to: min(stroke.minX, index?.minX ?? stroke.minX) - 1)
                        root(inside, index: index, at: source, group: group)
                        from = max(structure.box.maxX, index?.maxX ?? 0) + 1
                    } else if sign.barred == nil {
                        plain(to: sign.bare.minX - 1)
                        pieces.append((.sign("√"), source, group))
                        from = sign.bare.maxX + 1
                    }
                }
                plain(to: box.maxX)
            }
            for (at, mark) in marks.sorted(by: { $0.at < $1.at }) {
                plain(upTo: at)
                switch mark {
                case .structure(let member):
                    let structure = unique[member]
                    switch structure {
                    case .fraction(let over, let under, _):
                        fraction(over, under, at: structure.box, group: member)
                    case .root(let inside, _, let index):
                        root(inside, index: index, at: structure.box, group: member)
                    }
                    cursor = max(cursor, structure.box.maxX)
                case .bracket(let box, let sign):
                    pieces.append((.sign(sign), box, nil))
                    cursor = max(cursor, box.maxX)
                case .power(let member, let hasMinus, let box):
                    guard case .fraction(let over, let under, _) = unique[member] else { continue }
                    pieces.append((.sign(hasMinus ? "^(−" : "^("), box, member))
                    fraction(over, under, at: box, group: member)
                    pieces.append((.sign(")"), box, member))
                    cursor = max(cursor, box.maxX)
                    extent = extent.union(box)
                case .high(let box):
                    pieces.append((.sign("^("), box, nil))
                    pieces.append((.part(box.insetBy(dx: -1, dy: -1)), box, nil))
                    pieces.append((.sign(")"), box, nil))
                    cursor = max(cursor, box.maxX)
                    extent = extent.union(box)
                }
            }
            plain(upTo: .infinity)
            result.append(Expression(pieces: pieces, region: extent, tall: height, baseline: baseline))
        }
        return result
    }

    /// Whether two finds are the same fraction or root, seen from two places: they cover
    /// most of each other.
    private func isSameKind(_ a: Structure, _ b: Structure) -> Bool {
        switch (a, b) {
        case (.fraction, .fraction), (.root, .root): true
        default: false
        }
    }

    private func isSame(_ a: Structure, _ b: Structure) -> Bool {
        let both = a.box.intersection(b.box)
        guard !both.isNull else { return false }
        return both.width * both.height >= 0.6 * min(a.box.width * a.box.height, b.box.width * b.box.height)
    }

    private func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(a.minX - b.maxX, b.minX - a.maxX, 0)
    }

    /// Whether the top or bottom of a fraction is one character: no brackets needed round it.
    private func isSingle(_ part: CGRect, _ tall: CGFloat) -> Bool {
        ink.glyphs(in: part.insetBy(dx: -1, dy: -1)).filter { $0.height >= tall * 0.25 }.count == 1
    }

    // MARK: Drawing the rows

    /// A row of the sheet: one stretch of a line, or the top or bottom of a fraction, or the
    /// inside of a root, on its own. Where it is on the sheet, and where it came from.
    struct Row {
        var top: CGFloat
        var bottom: CGFloat
        /// Where the ink starts across the sheet: what's before it is the words leading in.
        var start: CGFloat
        /// Sheet pixels for each pixel of the picture.
        var scale: CGFloat
        /// The part of the picture that was copied.
        var source: CGRect
        /// It follows "Work out" at a distance, rather than "N =" close up.
        var hasWords: Bool
    }

    /// What an expression is made of, in order: rows of the sheet to be read, and signs.
    enum Item {
        /// `across`: a stretch of the line, where places along the row match places along
        /// the picture. Otherwise it's part of the fraction or root at `place`.
        case ink(row: Int, across: Bool, place: CGRect, spaceBefore: Bool)
        case sign(String, place: CGRect, spaceBefore: Bool)
    }

    /// Every stretch and part of the expressions drawn on a row of its own, dark on white,
    /// its capitals `capHeight` tall, each after a couple of words: text recognition reads a
    /// short piece of maths on its own as nonsense. Nothing else is drawn, so nothing else can
    /// be misread: the signs between the parts are known, and are written in afterwards.
    func sheet(of expressions: [Expression], capHeight: CGFloat = 40) -> (image: CGImage, rows: [Row], items: [[Item]])? {
        guard !expressions.isEmpty else { return nil }
        let rowHeight = capHeight * 3.75, margin: CGFloat = 60
        let font = CTFontCreateUIFontForLanguage(.system, capHeight / 0.705, nil)!
        func line(_ text: String) -> CTLine {
            CTLineCreateWithAttributedString(CFAttributedStringCreate(
                nil, text as CFString, [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true] as CFDictionary)!)
        }
        // A stretch of a line follows a couple of words, at a distance. The top of a
        // fraction can be a single letter, which is only read as part of a line, and only
        // read at its right size next to a capital: it follows "N =", close up.
        let words = line("Work out"), letter = line("N = ")
        let afterWords = margin + CGFloat(CTLineGetTypographicBounds(words, nil, nil, nil)) + capHeight * 3
        let afterLetter = margin + CGFloat(CTLineGetTypographicBounds(letter, nil, nil, nil))

        struct Cut { var image: CGImage; var width: CGFloat; var height: CGFloat; var rise: CGFloat; var scale: CGFloat; var source: CGRect; var hasWords = false }
        var cuts: [Cut] = []
        var items: [[Item]] = []
        for expression in expressions {
            var list: [Item] = []
            var edge: CGFloat?
            var lastGroup: Int?
            for (piece, source, group) in expression.pieces {
                // A space where there was one: between a stretch and a fraction, or two fractions.
                let isNew = group == nil || group != lastGroup
                let spaceBefore = isNew && (edge.map { source.minX - $0 >= expression.tall * 0.2 } ?? false)
                edge = source.maxX
                lastGroup = group
                switch piece {
                case .sign(let text):
                    list.append(.sign(text, place: source, spaceBefore: spaceBefore))
                case .stretch(let box):
                    // A stretch of the line keeps its place on the line.
                    let scale = min(max(capHeight / expression.tall, 0.4), 5)
                    guard let image = ink.cutOut(box) else { list.append(.sign(String(LineMender.unreadable), place: source, spaceBefore: false)); continue }
                    cuts.append(Cut(image: image, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale,
                                    rise: (box.maxY - expression.baseline) * scale, scale: scale, source: box, hasWords: box.width >= expression.tall * 4))
                    list.append(.ink(row: cuts.count - 1, across: true, place: source, spaceBefore: spaceBefore))
                case .part(let box):
                    // The top or bottom of a fraction is often set smaller: it's drawn at the
                    // size of the line, and set down by its own lowest full-size ink.
                    let glyphs = ink.glyphs(in: box)
                    let own = max(glyphs.map(\.height).max() ?? expression.tall, expression.tall * 0.62)
                    let scale = min(max(capHeight / min(own, expression.tall), 0.4), 6)
                    guard let image = ink.cutOut(box) else { list.append(.sign(String(LineMender.unreadable), place: source, spaceBefore: false)); continue }
                    let bottoms = glyphs.filter { $0.height >= own * 0.4 }.map(\.maxY).sorted()
                    var ownLine = bottoms.isEmpty ? box.maxY : bottoms[bottoms.count / 2]
                    // A number with a power, 3¹², has most of its ink up where the power is:
                    // the line is where the number itself stands, well below.
                    if let lower = glyphs.filter({ $0.height >= own * 0.85 && $0.maxY >= ownLine + own * 0.4 }).map(\.maxY).max() { ownLine = lower }
                    cuts.append(Cut(image: image, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale,
                                    rise: (box.maxY - ownLine) * scale, scale: scale, source: box))
                    list.append(.ink(row: cuts.count - 1, across: false, place: source, spaceBefore: spaceBefore))
                }
            }
            items.append(list)
        }
        let widest = cuts.map(\.width).max() ?? 0
        let width = Int(afterWords + widest + margin), height = Int(rowHeight * CGFloat(cuts.count) + margin * 2)
        guard widest > 0, cuts.count <= 400, width * height < 80_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.setFillColor(gray: 0, alpha: 1)
        var rows: [Row] = []
        for (number, cut) in cuts.enumerated() {
            // The line the row's text sits on, from the bottom of the sheet.
            let baseline = CGFloat(height) - margin - rowHeight * CGFloat(number) - rowHeight * 0.62
            context.textPosition = CGPoint(x: margin, y: baseline)
            // A sign or two between fractions is as short as the top of one, and read the same way.
            CTLineDraw(cut.hasWords ? words : letter, context)
            let start = cut.hasWords ? afterWords : afterLetter
            // Too tall for the row: made to fit, the line kept where it is.
            let fit = min(1, rowHeight * 0.58 / max(cut.height - cut.rise, 1), rowHeight * 0.34 / max(cut.rise, 1))
            context.draw(cut.image, in: CGRect(x: start, y: baseline - cut.rise * fit, width: cut.width * fit, height: cut.height * fit))
            let top = margin + rowHeight * CGFloat(number)
            rows.append(Row(top: top, bottom: top + rowHeight, start: start, scale: cut.scale * fit, source: cut.source, hasWords: cut.hasWords))
        }
        guard let image = context.makeImage() else { return nil }
        return (image, rows, items)
    }
}
