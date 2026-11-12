import CoreGraphics
import CoreText
import Foundation
import Vision

/// The ink in a picture: where each character's marks are, whatever text recognition made of
/// them. Text recognition gives the characters but not their size or height, drops ones it
/// isn't sure of, and reads the bars of |x| as letters; the ink says what's really there.
struct Ink: Sendable {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    /// How light each pixel is, rows from the top.
    private let pixels: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        self.width = width
        self.height = height
        bytesPerRow = context.bytesPerRow
        pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: context.bytesPerRow * height))
    }

    /// The picture with a margin of its own background around it. Text recognition misreads
    /// text that runs right up to the edge, as it does when an area is dragged tightly round it.
    static func padded(_ image: CGImage, by margin: Int) -> CGImage? {
        guard let ink = Ink(image) else { return nil }
        let shade = CGFloat(ink.background(x0: 0, y0: 0, x1: ink.width, y1: ink.height).shade) / 255
        let width = image.width + 2 * margin, height = image.height + 2 * margin
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: shade, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: margin, y: margin, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// The commonest shade in part of the picture (its background), and how far the ink is from it.
    private func background(x0: Int, y0: Int, x1: Int, y1: Int) -> (shade: Int, contrast: Int) {
        var histogram = [Int](repeating: 0, count: 256)
        for y in y0..<y1 {
            let row = y * bytesPerRow
            for x in x0..<x1 { histogram[Int(pixels[row + x])] += 1 }
        }
        let shade = histogram.indices.max { histogram[$0] < histogram[$1] } ?? 255
        var contrast = 0
        for value in 0..<256 where histogram[value] > 0 { contrast = max(contrast, abs(value - shade)) }
        return (shade, contrast)
    }

    private func bounds(_ area: CGRect) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let x0 = max(Int(area.minX.rounded(.down)), 0), y0 = max(Int(area.minY.rounded(.down)), 0)
        let x1 = min(Int(area.maxX.rounded(.up)), width), y1 = min(Int(area.maxY.rounded(.up)), height)
        guard x1 - x0 > 2, y1 - y0 > 2, (x1 - x0) * (y1 - y0) < 6_000_000 else { return nil }
        return (x0, y0, x1, y1)
    }

    /// The rows the line of text at `box` takes up: out from its middle, as far as the ink goes
    /// before the gap between lines. Vision's box can be loose enough to catch the next line.
    func rows(ofLineAt box: CGRect) -> ClosedRange<Int>? {
        let search = CGRect(x: box.minX, y: box.minY - box.height * 0.6, width: box.width, height: box.height * 2)
        guard let (x0, y0, x1, y1) = bounds(search) else { return nil }
        let (shade, contrast) = background(x0: x0, y0: y0, x1: x1, y1: y1)
        guard contrast >= 40 else { return nil }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        var inked = [Bool](repeating: false, count: y1 - y0)
        for y in y0..<y1 {
            let row = y * bytesPerRow
            for x in x0..<x1 where abs(Int(pixels[row + x]) - shade) > threshold {
                inked[y - y0] = true
                break
            }
        }
        // Start from an inked row near the middle of the box.
        let middle = min(max(Int(box.midY) - y0, 0), inked.count - 1)
        guard let start = (0..<inked.count).filter({ inked[$0] }).min(by: { abs($0 - middle) < abs($1 - middle) }),
              abs(start - middle) <= Int(box.height * 0.5) else { return nil }
        let gap = max(2, Int(box.height * 0.08))
        var top = start, bottom = start
        var blank = 0
        var row = start - 1
        while row >= 0, blank <= gap {
            if inked[row] { top = row; blank = 0 } else { blank += 1 }
            row -= 1
        }
        blank = 0
        row = start + 1
        while row < inked.count, blank <= gap {
            if inked[row] { bottom = row; blank = 0 } else { blank += 1 }
            row += 1
        }
        return (y0 + top)...(y0 + bottom)
    }

    /// A patch of ink whose pixels all touch: its box in the picture, and how many pixels.
    struct Patch {
        var minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var box: CGRect { CGRect(x: minX, y: minY, width: width, height: height) }
    }

    /// Every connected patch of ink in part of the picture, left to right.
    func patches(in area: CGRect) -> [Patch] {
        guard let (x0, y0, x1, y1) = bounds(area) else { return [] }
        let w = x1 - x0, h = y1 - y0
        let (shade, contrast) = background(x0: x0, y0: y0, x1: x1, y1: y1)
        guard contrast >= 40 else { return [] }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        var ink = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let row = (y0 + y) * bytesPerRow + x0
            for x in 0..<w { ink[y * w + x] = abs(Int(pixels[row + x]) - shade) > threshold }
        }
        var patches: [Patch] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where ink[start] {
            ink[start] = false
            stack.append(start)
            var patch = Patch(minX: start % w, minY: start / w, maxX: start % w, maxY: start / w, count: 0)
            while let point = stack.popLast() {
                let px = point % w, py = point / w
                patch.minX = min(patch.minX, px); patch.maxX = max(patch.maxX, px)
                patch.minY = min(patch.minY, py); patch.maxY = max(patch.maxY, py)
                patch.count += 1
                for ny in max(py - 1, 0)...min(py + 1, h - 1) {
                    for nx in max(px - 1, 0)...min(px + 1, w - 1) where ink[ny * w + nx] {
                        ink[ny * w + nx] = false
                        stack.append(ny * w + nx)
                    }
                }
            }
            if patch.count >= 3 {
                patch.minX += x0; patch.maxX += x0; patch.minY += y0; patch.maxY += y0
                patches.append(patch)
            }
        }
        return patches.sorted { $0.minX < $1.minX }
    }

    /// A box around each character's ink in part of the picture, left to right.
    func glyphs(in area: CGRect) -> [CGRect] {
        // A character can be several patches, one over another: i's dot, the bars of =.
        var merged: [Patch] = []
        for patch in patches(in: area) {
            if let last = merged.indices.last {
                let overlap = min(merged[last].maxX, patch.maxX) - max(merged[last].minX, patch.minX) + 1
                let narrower = min(merged[last].width, patch.width)
                // One over the other, and one of them slight: a dot, a bar of =. Something
                // bigger over a letter is a power leaning over it, unless it's right above.
                let together = max(merged[last].maxY, patch.maxY) - min(merged[last].minY, patch.minY) + 1
                let slighter = min(merged[last].height, patch.height)
                let isPart = slighter * 4 <= together ? overlap * 2 >= narrower : (slighter * 2 <= together && overlap * 5 >= narrower * 4)
                if isPart {
                    merged[last].minX = min(merged[last].minX, patch.minX); merged[last].maxX = max(merged[last].maxX, patch.maxX)
                    merged[last].minY = min(merged[last].minY, patch.minY); merged[last].maxY = max(merged[last].maxY, patch.maxY)
                    merged[last].count += patch.count
                    continue
                }
            }
            merged.append(patch)
        }
        // A thin stroke can break in two where it's faintest, a slash near its top: a scrap
        // of ink hard up against a bigger piece belongs to it. Hard up against its ink, not
        // just inside its box: the box of a slash has room in it for the power before it.
        let heights = merged.map(\.height).sorted()
        let usual = heights.isEmpty ? 0 : heights[heights.count * 3 / 4]
        var index = 0
        while index < merged.count {
            let scrap = merged[index]
            if scrap.count * 14 <= usual * usual, max(scrap.width, scrap.height) * 2 <= usual,
               let host = merged.indices.first(where: { other in
                   other != index && merged[other].count * 2 > scrap.count * 3
                       && scrap.minX <= merged[other].maxX + 1 && merged[other].minX <= scrap.maxX + 1
                       && scrap.minY <= merged[other].maxY + 1 && merged[other].minY <= scrap.maxY + 1
               }), hasInkBeside(scrap, in: area),
               // A dash wholly to the left of something tall is a minus sign before it, the
               // one in 10⁻⁴ that all but touches the crossbar of the 4: not a scrap of it.
               !(scrap.height <= max(2, usual * 4 / 25) && scrap.width >= scrap.height * 3 && scrap.maxX <= merged[host].minX + 1
                   && merged[host].height >= scrap.height * 3) {
                merged[host].minX = min(merged[host].minX, scrap.minX); merged[host].maxX = max(merged[host].maxX, scrap.maxX)
                merged[host].minY = min(merged[host].minY, scrap.minY); merged[host].maxY = max(merged[host].maxY, scrap.maxY)
                merged[host].count += scrap.count
                merged.remove(at: index)
            } else {
                index += 1
            }
        }
        return merged.sorted { $0.minX < $1.minX }.map(\.box)
    }

    /// Whether there's ink within two pixels of a patch's own that isn't part of it: the rest
    /// of a stroke it broke off from, with a faint row between them.
    private func hasInkBeside(_ patch: Patch, in area: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(area) else { return false }
        let (shade, contrast) = background(x0: x0, y0: y0, x1: x1, y1: y1)
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        func isInk(_ x: Int, _ y: Int) -> Bool {
            x >= x0 && x < x1 && y >= y0 && y < y1 && abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold
        }
        // The patch's own pixels: the ink in its box that reaches every side of it.
        let w = patch.width, h = patch.height
        var own = [Bool](repeating: false, count: w * h)
        var seen = [Bool](repeating: false, count: w * h)
        for start in 0..<(w * h) where !seen[start] && isInk(patch.minX + start % w, patch.minY + start / w) {
            var piece: [Int] = [], stack = [start]
            seen[start] = true
            var left = w, right = -1, top = h, bottom = -1
            while let point = stack.popLast() {
                piece.append(point)
                let px = point % w, py = point / w
                left = min(left, px); right = max(right, px); top = min(top, py); bottom = max(bottom, py)
                for ny in max(py - 1, 0)...min(py + 1, h - 1) {
                    for nx in max(px - 1, 0)...min(px + 1, w - 1) where !seen[ny * w + nx] && isInk(patch.minX + nx, patch.minY + ny) {
                        seen[ny * w + nx] = true
                        stack.append(ny * w + nx)
                    }
                }
            }
            if left == 0, right == w - 1, top == 0, bottom == h - 1 {
                for point in piece { own[point] = true }
                break
            }
        }
        guard own.contains(true) else { return true }
        for point in own.indices where own[point] {
            let px = point % w, py = point / w
            for dy in -2...2 {
                for dx in -2...2 {
                    let nx = px + dx, ny = py + dy
                    if nx >= 0, nx < w, ny >= 0, ny < h, own[ny * w + nx] { continue }
                    if isInk(patch.minX + nx, patch.minY + ny) { return true }
                }
            }
        }
        return false
    }

    /// The bars of fractions in part of the picture: thin lines of ink with something of a
    /// size close over and under them. `tall` is the height of a capital in the text there.
    /// The bars of = have only each other, a minus sign nothing, an underline nothing below.
    /// `plainOnly` keeps to the ones that can't be anything else, for looking over a whole
    /// picture: short, and with clear room over them, which an underline hasn't.
    func fractionBars(in area: CGRect, tall: CGFloat, plainOnly: Bool = false) -> [CGRect] {
        let all = patches(in: area)
        var bars: [CGRect] = []
        for (index, bar) in all.enumerated() {
            guard CGFloat(bar.height) <= max(3, tall * 0.16), CGFloat(bar.width) >= max(tall * 0.45, CGFloat(bar.height) * 4) else { continue }
            if plainOnly, CGFloat(bar.width) > tall * 6 { continue }
            /// How far the nearest sizeable ink over the bar (or under it) is from it, if
            /// it's within `reach`.
            func gap(above: Bool, within reach: CGFloat) -> CGFloat? {
                all.indices.compactMap { other -> CGFloat? in
                    let part = all[other]
                    guard other != index, CGFloat(part.height) >= tall * 0.3 else { return nil }
                    let overlap = min(part.maxX, bar.maxX) - max(part.minX, bar.minX) + 1
                    guard overlap * 2 >= min(part.width, bar.width) else { return nil }
                    let gap = above ? bar.minY - part.maxY : part.minY - bar.maxY
                    return gap > 0 && CGFloat(gap) <= reach ? CGFloat(gap) : nil
                }.min()
            }
            // A short bar is given more room: exam papers set a fraction further from its
            // bar than a web page does, and a small letter under one, the x of 1/x, starts
            // lower still. That much more only when there's a real gap over the bar, which
            // an underline hasn't.
            let reach = tall * (CGFloat(bar.width) <= tall * 6 ? 0.7 : 0.5)
            guard let over = gap(above: true, within: reach), !plainOnly || over >= tall * 0.25 else { continue }
            let under = CGFloat(bar.width) <= tall * 6 && over >= tall * 0.3 ? tall * 1.1 : reach
            if gap(above: false, within: under) != nil { bars.append(bar.box) }
        }
        return bars
    }

    /// Whether there's a line of ink across between two pieces of text, one above the other:
    /// the bar of a fraction. `length` is how long it has to be.
    func hasBar(between top: CGRect, and bottom: CGRect, length: CGFloat, faint: Bool = false) -> Bool {
        let slack = min(top.height, bottom.height) * 0.12
        let area = CGRect(x: min(top.minX, bottom.minX) - 4, y: top.maxY - slack,
                          width: max(top.maxX, bottom.maxX) - min(top.minX, bottom.minX) + 8,
                          height: bottom.minY - top.maxY + 2 * slack)
        guard let (x0, y0, x1, y1) = bounds(area) else { return false }
        let wider = CGRect(x: area.minX, y: top.minY, width: area.width, height: bottom.maxY - top.minY)
        guard let (cx0, cy0, cx1, cy1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: cx0, y0: cy0, x1: cx1, y1: cy1)
        guard contrast >= 40 else { return false }
        // The rules of a table are often pale: any steady line counts, however faint.
        let threshold = faint ? 10 : max(Int(Double(contrast) * 0.4), 24)
        for y in y0..<y1 {
            let row = y * bytesPerRow
            var run = 0
            for x in x0..<x1 {
                if abs(Int(pixels[row + x]) - shade) > threshold {
                    run += 1
                    if CGFloat(run) >= length { return true }
                } else {
                    run = 0
                }
            }
        }
        return false
    }

    /// A letter and its power that touch, and so came out as one patch of ink, parted again.
    /// `glyph` stands taller than the letters around it (`tall` is their height): if its left
    /// side is a letter of ordinary height on the line, and its right side is ink that starts
    /// higher and stops well above the line, they're cut where the two join.
    func splitRaised(_ glyph: CGRect, tall: CGFloat) -> (base: CGRect, raised: CGRect)? {
        guard let (x0, y0, x1, y1) = bounds(glyph), x1 - x0 >= 6 else { return nil }
        let wider = glyph.insetBy(dx: -glyph.width, dy: -glyph.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return nil }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return nil }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // For each column: its highest and lowest ink, and how much ink it has.
        var tops: [Int?] = [], bottoms: [Int?] = [], amounts: [Int] = []
        for x in x0..<x1 {
            var top: Int?, bottom: Int?, amount = 0
            for y in y0..<y1 where abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold {
                if top == nil { top = y }
                bottom = y
                amount += 1
            }
            tops.append(top); bottoms.append(bottom); amounts.append(amount)
        }
        let width = x1 - x0
        var best: (cut: Int, amount: Int)?
        for cut in max(width * 3 / 10, 2)..<min(width * 17 / 20, width - 2) {
            let leftTops = tops[..<cut].compactMap { $0 }, leftBottoms = bottoms[..<cut].compactMap { $0 }
            let rightTops = tops[cut...].compactMap { $0 }, rightBottoms = bottoms[cut...].compactMap { $0 }
            guard let leftTop = leftTops.min(), let leftBottom = leftBottoms.max(), let rightTop = rightTops.min(), let rightBottom = rightBottoms.max() else { continue }
            // The letter: on the line, and no taller than letters are. The power: starts
            // higher than the letter does, and stops well short of the line.
            guard CGFloat(y1 - 1 - leftBottom) <= tall * 0.08, CGFloat(leftBottom - leftTop) <= tall * 1.05,
                  CGFloat(leftTop - rightTop) >= tall * 0.15, CGFloat(y1 - 1 - rightBottom) >= tall * 0.3,
                  CGFloat(rightBottom - rightTop) >= tall * 0.3 else { continue }
            // A power has a foot: its far side comes down about as low as its near side.
            // The stroke of a root sign, or of a 7, only climbs away.
            let far = bottoms[(cut + (width - cut) * 4 / 10)...].compactMap { $0 }
            guard let farBottom = far.max(), CGFloat(rightBottom - farBottom) <= tall * 0.15 else { continue }
            if best == nil || amounts[cut] < best!.amount { best = (cut, amounts[cut]) }
        }
        guard let cut = best?.cut else { return nil }
        let leftTop = tops[..<cut].compactMap { $0 }.min()!, leftBottom = bottoms[..<cut].compactMap { $0 }.max()!
        let rightTop = tops[cut...].compactMap { $0 }.min()!, rightBottom = bottoms[cut...].compactMap { $0 }.max()!
        return (CGRect(x: x0, y: leftTop, width: cut, height: leftBottom - leftTop + 1),
                CGRect(x: x0 + cut, y: rightTop, width: width - cut, height: rightBottom - rightTop + 1))
    }

    /// Whether the ink in `box` is a root sign standing on its own, with no bar over what
    /// it's the root of (√3 × √5, as worksheets print it): a short arm on the left that starts
    /// part-way down and runs down to a point at the foot, and a long arm that climbs from
    /// there to the top right, where it may turn along the top a little way. Both arms of a V
    /// reach the top; a J's stem stands at its right edge and an integral sign's hook stays
    /// at the bottom; a 7 has its bar along the top; the bar of an f or a t doesn't run down
    /// to the foot; a 4 has a hole in it.
    func isRootSign(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box) else { return false }
        let w = x1 - x0, h = y1 - y0
        guard h >= 10, w >= 5, w * 20 >= h * 7, w * 10 <= h * 12 else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // The sign's own ink: the piece that the topmost ink belongs to. The digit after it
        // tucks in under its top, inside its box, and isn't part of it.
        var cells = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w where abs(Int(pixels[(y0 + y) * bytesPerRow + x0 + x]) - shade) > threshold { cells[y * w + x] = 1 }
        }
        guard let seed = cells.firstIndex(of: 1) else { return false }
        var stack = [seed]
        cells[seed] = 2
        while let cell = stack.popLast() {
            let x = cell % w, y = cell / w
            for dy in -1...1 {
                for dx in -1...1 where (dx != 0 || dy != 0) && x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && cells[(y + dy) * w + x + dx] == 1 {
                    cells[(y + dy) * w + x + dx] = 2
                    stack.append((y + dy) * w + x + dx)
                }
            }
        }
        // Its highest and lowest ink in each column, from the top of the box.
        var tops: [Int?] = [], bottoms: [Int?] = []
        for x in 0..<w {
            var top: Int?, bottom: Int?
            for y in 0..<h where cells[y * w + x] == 2 {
                if top == nil { top = y }
                bottom = y
            }
            tops.append(top); bottoms.append(bottom)
        }
        let inked = (0..<w).filter { tops[$0] != nil }
        guard inked.count * 10 >= w * 8, let lowest = inked.map({ bottoms[$0]! }).max(), let highest = inked.map({ tops[$0]! }).min() else { return false }
        // The foot: a point at the bottom, between the two arms.
        let foot = inked.filter { bottoms[$0]! >= lowest - max(1, h / 12) }
        let footAt = Double(foot.reduce(0, +)) / Double(foot.count)
        guard lowest >= h - 2, footAt >= Double(w) * 0.15, footAt <= Double(w) * 0.6 else { return false }
        // The short arm: its top is between a quarter and three quarters of the way down,
        // and it runs on down towards the foot.
        let leftColumns = inked.filter { $0 < max(2, w / 4) }
        guard let leftTop = leftColumns.map({ tops[$0]! }).min(), leftTop * 100 >= h * 25, leftTop * 100 <= h * 78,
              let leftBottom = leftColumns.map({ bottoms[$0]! }).max(), leftBottom * 100 >= h * 52 else { return false }
        // …but its far end stops well above the foot: the left end of a slash, a heavy one, is its foot.
        guard let endBottom = inked.filter({ $0 < max(1, w / 8) }).map({ bottoms[$0]! }).max(), endBottom * 100 <= h * 86 else { return false }
        // The long arm: the top of the ink is at the far right, with nothing near the top in
        // the left third; from the foot the ink climbs steadily; and half-way up the arm is
        // still well short of the right edge.
        guard highest <= 1, let topColumn = inked.last(where: { tops[$0]! <= highest + max(1, h / 12) }), topColumn * 100 >= w * 65,
              !inked.contains(where: { $0 * 100 < w * 35 && tops[$0]! * 100 < h * 20 }) else { return false }
        let footColumn = Int(footAt.rounded())
        var last = h
        for x in inked where x > footColumn {
            let top = tops[x]!
            if top > last + 2 { return false }
            last = min(last, top)
        }
        var middleRight = 0
        for y in (h * 2 / 5)...(h * 3 / 5) {
            if let x = (0..<w).last(where: { cells[y * w + $0] == 2 }) { middleRight = max(middleRight, x) }
        }
        guard middleRight * 10 <= (w - 1) * 8 else { return false }
        // The two arms stand apart for a few rows above the foot. A slanted bracket has the
        // same outline, and is one stroke all the way down.
        var apart = 0
        for y in 0..<h {
            var runs = 0, wasInk = false
            for x in 0..<w {
                let isInk = cells[y * w + x] == 2
                if isInk, !wasInk { runs += 1 }
                wasInk = isInk
            }
            if runs >= 2 { apart += 1 }
        }
        guard apart >= max(2, h * 7 / 100) else { return false }
        // Nothing shut in by the ink.
        return holes(in: box)?.holes.isEmpty ?? true
    }

    /// Whether the ink in `box` has a third stroke as well as the two arms of a > or a <: the
    /// line under ⩾ and ⩽, which exam papers draw slanted and joined on, and which gets read
    /// as the plain sign. Down a column of a plain one there are two runs of ink at most.
    func hasThirdStroke(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box), x1 - x0 >= 6, y1 - y0 >= 8 else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        var columns = 0
        for x in x0..<x1 {
            var runs = 0, wasInk = false
            for y in y0..<y1 {
                let isInk = abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold
                if isInk, !wasInk { runs += 1 }
                wasInk = isInk
            }
            if runs >= 3 { columns += 1 }
        }
        return columns >= max(3, (x1 - x0) * 3 / 10)
    }

    /// Whether the ink in `box` curves in at the bottom left, as a 6 does. A b has a straight
    /// stem down its left side, and its lowest ink is as far left as any.
    func hasRoundBase(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box), x1 - x0 >= 5, y1 - y0 >= 8 else { return true }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return true }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return true }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        /// The leftmost ink in each row, from the left edge of the box.
        let lefts: [Int?] = (y0..<y1).map { y in (x0..<x1).first { abs(Int(pixels[y * bytesPerRow + $0]) - shade) > threshold }.map { $0 - x0 } }
        let known = lefts.compactMap { $0 }
        guard let furthest = known.min(), known.count >= 6 else { return true }
        // The bottom two rows of ink, against the furthest left the ink goes anywhere.
        let base = lefts.suffix(max(2, (y1 - y0) / 10)).compactMap { $0 }
        guard let lowest = base.min() else { return true }
        return CGFloat(lowest - furthest) >= max(2, CGFloat(x1 - x0) * 0.1)
    }

    /// A round bracket drawn tall, to the height of the fraction it's round, and which one:
    /// "(" bows out to the left in the middle, ")" to the right. Nil for any other shape.
    func bracket(_ box: CGRect) -> String? {
        guard let (x0, y0, x1, y1) = bounds(box), y1 - y0 >= 12 else { return nil }
        let wider = box.insetBy(dx: -box.width * 2, dy: -box.height * 0.2)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return nil }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return nil }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // Where the ink starts and ends in each row.
        var lefts: [Double] = [], rights: [Double] = []
        for y in y0..<y1 {
            let inked = (x0..<x1).filter { abs(Int(pixels[y * bytesPerRow + $0]) - shade) > threshold }
            guard let first = inked.first, let last = inked.last else { continue }
            lefts.append(Double(first))
            rights.append(Double(last))
        }
        let count = lefts.count
        guard count * 10 >= (y1 - y0) * 9 else { return nil }
        let end = max(count / 7, 1)
        func mean(_ values: ArraySlice<Double>) -> Double { values.reduce(0, +) / Double(values.count) }
        let endsLeft = (mean(lefts[..<end]) + mean(lefts[(count - end)...])) / 2, middleLeft = mean(lefts[(count * 2 / 5)..<(count * 3 / 5)])
        let endsRight = (mean(rights[..<end]) + mean(rights[(count - end)...])) / 2, middleRight = mean(rights[(count * 2 / 5)..<(count * 3 / 5)])
        // (A bracket seven pixels wide, in ordinary print, bows by under two.)
        let bow = max(1.5, Double(x1 - x0) * 0.22)
        // Both ends bow, the top and the bottom: a j's hook is only at the bottom.
        let each = bow * 0.6
        let topLeft = mean(lefts[..<end]), bottomLeft = mean(lefts[(count - end)...])
        let topRight = mean(rights[..<end]), bottomRight = mean(rights[(count - end)...])
        if endsLeft - middleLeft >= bow, endsRight - middleRight >= bow / 2, topLeft - middleLeft >= each, bottomLeft - middleLeft >= each { return "(" }
        if middleRight - endsRight >= bow, middleLeft - endsLeft >= bow / 2, middleRight - topRight >= each, middleRight - bottomRight >= each { return ")" }
        return nil
    }

    /// Whether there's a dot just over the ink in `box`: the dot on a recurring decimal, which
    /// stands clear of its digit, above the rows the line of text takes up. Without it the
    /// number is another number. `tall` is the height of a capital there.
    func hasDot(over box: CGRect, tall: CGFloat) -> Bool {
        let area = CGRect(x: box.minX - 3, y: box.minY - tall * 0.9, width: box.width + 6, height: tall * 0.9)
        guard let (x0, y0, x1, y1) = bounds(area) else { return false }
        return patches(in: area).contains { patch in
            let gap = box.minY - CGFloat(patch.maxY) - 1
            // A whole mark with clear room all round it, not the tip of the slash or the
            // bracket next door reaching into the space over the digit.
            guard patch.minX > x0, patch.maxX < x1 - 1, patch.minY > y0, patch.maxY < y1 - 1 else { return false }
            guard patch.height >= 2, CGFloat(patch.height) <= tall * 0.4, CGFloat(patch.width) <= tall * 0.45,
                  patch.width * 5 >= patch.height * 3, patch.height * 5 >= patch.width * 3,
                  gap >= max(2, tall * 0.12), gap <= tall * 0.5, CGFloat(patch.minX) >= box.minX - 1, CGFloat(patch.maxX) <= box.maxX + 1 else { return false }
            // …and on its own up there: a dot has nothing beside it or over it but another
            // dot. The comma of the line above, hanging down over a digit, has its line.
            let around = CGRect(x: CGFloat(patch.minX) - tall * 0.7, y: CGFloat(patch.minY) - tall * 0.5,
                                width: CGFloat(patch.width) + tall * 1.4, height: CGFloat(patch.height) + tall * 0.5)
            return patches(in: around).allSatisfy { CGFloat($0.height) <= tall * 0.4 && CGFloat($0.width) <= tall * 0.45 }
        }
    }

    /// Whether the top of the ink in `box` is a small mark standing clear of the rest: the dot
    /// of a recurring decimal that got counted in with the digit under it, as an i's dot is.
    func hasDetachedTop(_ box: CGRect) -> Bool {
        body(underDetachedTopOf: box) != nil
    }

    /// The rest of the ink in `box`, without the small mark standing clear above it, if there
    /// is one: a digit without the dot that makes it recur.
    func body(underDetachedTopOf box: CGRect) -> CGRect? {
        guard let (x0, y0, x1, y1) = bounds(box), y1 - y0 >= 10 else { return nil }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return nil }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return nil }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        let spans: [(first: Int, last: Int)?] = (y0..<y1).map { y in
            let inked = (x0..<x1).filter { abs(Int(pixels[y * bytesPerRow + $0]) - shade) > threshold }
            return inked.first.map { ($0, inked.last!) }
        }
        guard let start = spans.firstIndex(where: { $0 != nil }) else { return nil }
        var end = start
        while end < spans.count, spans[end] != nil { end += 1 }
        guard end < spans.count, let body = spans[end...].firstIndex(where: { $0 != nil }) else { return nil }
        let top = spans[start..<end].compactMap { $0 }
        let across = (top.map(\.last).max() ?? 0) - (top.map(\.first).min() ?? 0) + 1
        let rest = spans.count - body
        // A dot: small, and no more than half as wide as the digit. The bar of a 5 that has
        // broken away from the rest of it in small slanted type is nearly as wide as the 5.
        guard rest >= 8, end - start <= max(3, rest * 2 / 5), across * 20 <= (x1 - x0) * 11 else { return nil }
        return CGRect(x: box.minX, y: CGFloat(y0 + body), width: box.width, height: CGFloat(rest))
    }

    /// Whether the ink in `box` is broad across its top, as the top of a 6 is where it curls
    /// over. A b starts with the top of its stem, a stroke's width and no more. In text of an
    /// ordinary size a 6 curves in at the bottom by a pixel at most, too little to go by.
    func hasBroadTop(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box), x1 - x0 >= 5, y1 - y0 >= 8 else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // The first rows that have ink in them.
        var spans: [Int] = [], middles: [Double] = []
        for y in y0..<y1 where spans.count < max(2, (y1 - y0) / 8) {
            let inked = (x0..<x1).filter { abs(Int(pixels[y * bytesPerRow + $0]) - shade) > threshold }
            guard let first = inked.first, let last = inked.last else { continue }
            spans.append(last - first + 1)
            middles.append(Double(first + last) / 2 - Double(x0))
        }
        guard let widest = spans.max() else { return false }
        if widest * 20 >= (x1 - x0) * 9 { return true }
        // In slanted type the top of a 6 is a thin curl, but it's out over the right-hand
        // half of the figure. The top of a b's stem is over the left, slanted or not.
        return middles.reduce(0, +) / Double(middles.count) >= Double(x1 - x0) * 0.55
    }

    /// Whether the ink in `box` is a division sign: a bar right across, with a dot above its
    /// middle and another below, clear of it. In text of an ordinary size Vision reads one as
    /// a plus sign.
    func isDivisionSign(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box.insetBy(dx: 0, dy: -1)), x1 - x0 >= 5, y1 - y0 >= 7 else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // The rows of ink, in runs with clear rows between: how far across each run reaches.
        var runs: [(first: Int, last: Int)] = []
        var isInRun = false
        for y in y0..<y1 {
            let inked = (x0..<x1).filter { abs(Int(pixels[y * bytesPerRow + $0]) - shade) > threshold }
            guard let first = inked.first, let last = inked.last else { isInRun = false; continue }
            if isInRun {
                runs[runs.count - 1] = (min(runs[runs.count - 1].first, first), max(runs[runs.count - 1].last, last))
            } else {
                runs.append((first, last))
                isInRun = true
            }
        }
        guard runs.count == 3 else { return false }
        let width = x1 - x0, middle = Double(x0 + x1 - 1) / 2
        func isDot(_ run: (first: Int, last: Int)) -> Bool {
            (run.last - run.first + 1) * 2 <= width && abs(Double(run.first + run.last) / 2 - middle) <= Double(width) * 0.2
        }
        return (runs[1].last - runs[1].first + 1) * 5 >= width * 4 && isDot(runs[0]) && isDot(runs[2])
    }

    /// Whether the ink in `box` has an upright stroke through its middle, top to bottom, as a
    /// plus sign has and a division sign hasn't.
    func hasUpright(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box.insetBy(dx: -1, dy: -1)), x1 - x0 >= 3, y1 - y0 >= 3 else { return true }
        let wider = box.insetBy(dx: -box.width, dy: -box.height)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return true }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return true }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        let middle = (x0 + x1) / 2, reach = max((x1 - x0) / 5, 1)
        var inked = 0
        let rows = (y0 + 1)..<(y1 - 1)
        for y in rows {
            if ((middle - reach)...(middle + reach)).contains(where: { $0 >= 0 && $0 < width && abs(Int(pixels[y * bytesPerRow + $0]) - shade) > threshold }) { inked += 1 }
        }
        return inked * 10 >= rows.count * 9
    }

    /// How far the ink in `box` leans to the right for each pixel it rises, if it's one thin
    /// straight stroke and nothing else, as a slash is: about 0.3 to 0.6 for a slash, nothing
    /// for an upright bar. Nil for any other shape.
    func lean(ofStrokeIn box: CGRect) -> Double? {
        guard let (x0, y0, x1, y1) = bounds(box), y1 - y0 >= 8 else { return nil }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return nil }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return nil }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // The stroke, followed up from its foot a row at a time: in each row the one run of
        // ink that carries on from the row below. A neighbour's ink can be inside the box
        // too, in slanted type; ink that forks off the stroke means it's no single stroke.
        var middles: [(row: Int, middle: Double)] = []
        var widest = 0
        var below: (start: Int, end: Int)?
        for y in stride(from: y1 - 1, through: y0, by: -1) {
            var runs: [(start: Int, end: Int)] = []
            var x = x0
            while x < x1 {
                guard abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold else { x += 1; continue }
                let start = x
                while x < x1, abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold { x += 1 }
                runs.append((start, x - 1))
            }
            let run: (start: Int, end: Int)
            if let last = below {
                let next = runs.filter { $0.start <= last.end + 1 && $0.end >= last.start - 1 }
                guard next.count <= 1 else { return nil }
                guard let only = next.first else { break }
                run = only
            } else {
                guard let first = runs.first else { continue }
                run = first
            }
            below = run
            widest = max(widest, run.end - run.start + 1)
            middles.append((y, Double(run.start + run.end) / 2))
        }
        middles.reverse()
        // The faint rows at the very ends may be missing, and none in between.
        guard let top = middles.first, let bottom = middles.last, middles.count >= 8, bottom.row - top.row + 1 == middles.count,
              middles.count >= y1 - y0 - 2 else { return nil }
        guard widest <= max(3, (x1 - x0) / 2) else { return nil }
        let rise = Double(bottom.row - top.row)
        let slope = (top.middle - bottom.middle) / rise
        // Straight: no hook at either end, no bend in the middle.
        for item in middles {
            let expected = top.middle - slope * Double(item.row - top.row)
            guard abs(item.middle - expected) <= 1.25 else { return nil }
        }
        return slope
    }

    /// Whether the left edge of the ink in `box` is a slash, with something more to the right
    /// of it: a slash run into the digit after it, "/7", which comes out as one patch and is
    /// read as the digit alone. No digit has a straight leaning edge from top to bottom.
    func hasSlashInFront(_ box: CGRect) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box), y1 - y0 >= 10, x1 - x0 >= 8 else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        func isInk(_ x: Int, _ y: Int) -> Bool { abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold }
        // The first run of ink in each row: where it starts, and how long it is.
        var edges: [(row: Int, start: Int, length: Int)] = []
        for y in y0..<y1 {
            guard let start = (x0..<x1).first(where: { isInk($0, y) }) else { continue }
            var end = start
            while end + 1 < x1, isInk(end + 1, y) { end += 1 }
            edges.append((y, start, end - start + 1))
        }
        guard let top = edges.first, let bottom = edges.last, edges.count >= y1 - y0 - 2, bottom.row - top.row + 1 == edges.count else { return false }
        let slope = Double(top.start - bottom.start) / Double(bottom.row - top.row)
        guard slope >= 0.22 else { return false }
        for edge in edges {
            guard abs(Double(edge.start) - (Double(top.start) - slope * Double(edge.row - top.row))) <= 1.25 else { return false }
        }
        // A thin stroke where it stands clear, and more ink than the stroke alone.
        let lengths = edges.map(\.length).sorted()
        let thick = lengths[lengths.count / 4]
        guard thick <= max(3, (y1 - y0) / 5), edges.filter({ $0.length <= thick + 1 }).count * 20 >= edges.count * 7 else { return false }
        return x1 - x0 >= top.start - x0 + thick + 5
    }

    /// Whether the right-hand end of the ink in `box` stops well short of the line the rest
    /// stands on, and has a foot of its own: a power run into the digit it's on, "5²", which
    /// comes out as one patch and is read as two digits. `tall` is a capital's height.
    func hasRaisedEnd(_ box: CGRect, tall: CGFloat) -> Bool {
        guard let (x0, y0, x1, y1) = bounds(box), x1 - x0 >= 8 else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        // The highest and lowest ink in each column of the right-hand third.
        let from = x1 - max((x1 - x0) * 28 / 100, 3)
        var tops: [Int] = [], bottoms: [Int] = []
        // Ink further down after a wide gap is the foot of whatever comes next, a slash's
        // say, which reaches back under a power in slanted type.
        let gap = max(4, Int(tall * 0.25))
        for x in from..<x1 {
            let inked = (y0..<y1).filter { abs(Int(pixels[$0 * bytesPerRow + x]) - shade) > threshold }
            guard let first = inked.first else { continue }
            var last = first
            for row in inked.dropFirst() {
                if row - last - 1 >= gap { break }
                last = row
            }
            tops.append(first); bottoms.append(last)
        }
        guard let top = tops.min(), bottoms.count >= 3 else { return false }
        // Its foot: the lowest level that several columns stop at. The stroke of a 7 has
        // none, it only climbs away. A column or two may go lower, into a neighbour's ink.
        guard let foot = Set(bottoms).filter({ level in
                  bottoms.filter { $0 == level }.count >= 3 || bottoms.filter { abs($0 - level) <= 1 }.count >= 4
              }).max(),
              bottoms.filter({ $0 > foot + 1 }).count * 4 <= bottoms.count else { return false }
        return CGFloat(y1 - 1 - foot) >= tall * 0.3 && CGFloat(foot - top) >= tall * 0.3
    }

    /// The holes in the ink in `box`, background shut in on every side: where each is (its
    /// middle and its first and last rows, from the top-left of the box with a pixel of
    /// margin) and how many pixels, with the size of that area and the ink's first and last rows.
    private func holes(in box: CGRect) -> (holes: [(x: Double, y: Double, first: Int, last: Int, count: Int)], width: Int, height: Int, inkTop: Int, inkBottom: Int)? {
        // A pixel of background all round, so that what's outside the ink joins up.
        guard let (x0, y0, x1, y1) = bounds(box.insetBy(dx: -1, dy: -1)), x1 - x0 >= 5, y1 - y0 >= 5 else { return nil }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return nil }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return nil }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        let w = x1 - x0, h = y1 - y0
        // 0 for background not yet reached, 1 for ink, 2 for background reached.
        var cells = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = (y0 + y) * bytesPerRow + x0
            for x in 0..<w where abs(Int(pixels[row + x]) - shade) > threshold { cells[y * w + x] = 1 }
        }
        /// Fills the background that joins up with `start`, edge to edge (not corner to
        /// corner: ink that touches at its corners still shuts a hole). The pixels filled.
        func fill(from start: Int) -> [Int] {
            guard cells[start] == 0 else { return [] }
            cells[start] = 2
            var filled: [Int] = [], stack = [start]
            while let point = stack.popLast() {
                filled.append(point)
                let px = point % w, py = point / w
                if px > 0, cells[point - 1] == 0 { cells[point - 1] = 2; stack.append(point - 1) }
                if px < w - 1, cells[point + 1] == 0 { cells[point + 1] = 2; stack.append(point + 1) }
                if py > 0, cells[point - w] == 0 { cells[point - w] = 2; stack.append(point - w) }
                if py < h - 1, cells[point + w] == 0 { cells[point + w] = 2; stack.append(point + w) }
            }
            return filled
        }
        for x in 0..<w { _ = fill(from: x); _ = fill(from: (h - 1) * w + x) }
        for y in 0..<h { _ = fill(from: y * w); _ = fill(from: y * w + w - 1) }
        // What's left is shut in by ink.
        var holes: [(x: Double, y: Double, first: Int, last: Int, count: Int)] = []
        for start in 0..<(w * h) where cells[start] == 0 {
            let hole = fill(from: start)
            guard hole.count >= 2 else { continue }
            let rows = hole.map { $0 / w }
            holes.append((Double(hole.map { $0 % w }.reduce(0, +)) / Double(hole.count), Double(rows.reduce(0, +)) / Double(hole.count), rows.min()!, rows.max()!, hole.count))
        }
        guard let inkTop = cells.firstIndex(of: 1).map({ $0 / w }), let inkBottom = cells.lastIndex(of: 1).map({ $0 / w }) else { return nil }
        return (holes, w, h, inkTop, inkBottom)
    }

    /// Whether the ink in `box` is a small ring, as round as it's tall, with one hole in the
    /// middle: a degree sign. A raised nought is narrower than it's tall.
    /// With `round` false it needn't be as wide as it's tall: a nought is a ring too.
    func isRing(_ box: CGRect, round: Bool = true, hole: Double = 0.13) -> Bool {
        guard box.width >= 4, box.height >= 4, !round || (box.width * 4 >= box.height * 3 && box.height * 4 >= box.width * 3),
              let (found, w, h, _, _) = holes(in: box), found.count == 1,
              abs(found[0].x - Double(w - 1) / 2) <= Double(w) * 0.2, abs(found[0].y - Double(h - 1) / 2) <= Double(h) * 0.2,
              // Mostly hole: the stroke of a ring is thin. The hole of a 4 is a small corner of it.
              Double(found[0].count) >= Double(box.width * box.height) * hole else { return false }
        // …and the same turned upside down, give or take a pixel, which a ring is (a slanted
        // one too) and a 4, a 6 or a 9 with its one hole isn't.
        guard let (x0, y0, x1, y1) = bounds(box) else { return false }
        let wider = box.insetBy(dx: -box.width, dy: -box.height * 0.5)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        let across = x1 - x0, down = y1 - y0
        func isInk(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && x < across && y >= 0 && y < down && abs(Int(pixels[(y0 + y) * bytesPerRow + x0 + x]) - shade) > threshold
        }
        func isInkNear(_ x: Int, _ y: Int) -> Bool {
            (-1...1).contains { dy in (-1...1).contains { dx in isInk(x + dx, y + dy) } }
        }
        var total = 0, turned = 0
        for y in 0..<down {
            for x in 0..<across where isInk(x, y) {
                total += 1
                if isInkNear(across - 1 - x, down - 1 - y) { turned += 1 }
            }
        }
        return total > 0 && turned * 20 >= total * 17
    }

    /// Whether the ink in `box` is a nought: one hole, in the middle, and most of the height of
    /// the figure. The hole of a 6 or a 9 is under half its height, and off to one end.
    func isNought(_ box: CGRect) -> Bool {
        guard box.width >= 4, box.height >= 6, let (found, w, h, inkTop, inkBottom) = holes(in: box), found.count == 1 else { return false }
        let hole = found[0], tall = inkBottom - inkTop + 1
        return (hole.last - hole.first + 1) * 2 >= tall && abs(hole.x - Double(w - 1) / 2) <= Double(w) * 0.2
            && abs(hole.y - Double(h - 1) / 2) <= Double(h) * 0.12
    }

    /// Whether the ink in `box` is a per cent sign rather than an 8, which is what a per cent
    /// sign drawn in one piece gets read as. Both have two holes. An 8's are one above the
    /// other (in slanted type the top one a little to the right); a per cent sign's rings
    /// sit corner to corner, the top one well to the left of the bottom one.
    func isPerCent(_ box: CGRect) -> Bool {
        guard box.width >= 6, box.height >= 8, let (found, w, h, inkTop, inkBottom) = holes(in: box), found.count == 2 else { return false }
        let top = found.min { $0.y < $1.y }!, bottom = found.max { $0.y < $1.y }!
        guard bottom.y - top.y >= Double(h) * 0.3 else { return false }
        if bottom.x - top.x >= Double(w) * 0.18 { return true }
        // In slanted type the rings can come out one above the other. Then it's what's
        // between them that tells: an 8 has only its waist there, as thick as one stroke and
        // thinner than its holes are tall; a per cent sign has the bottom of one ring, the
        // stroke, and the top of the other.
        let between = bottom.first - top.last - 1
        let tallestHole = max(top.last - top.first, bottom.last - bottom.first) + 1
        let stroke = max(top.first - inkTop, inkBottom - bottom.last)
        return between * 2 >= tallestHole * 3 && between >= stroke * 2
    }

    /// How alike the ink in two boxes is: 1 for the same character drawn twice, less the
    /// more they differ. The boxes are laid over each other, give or take a pixel.
    func likeness(_ a: CGRect, _ b: CGRect) -> Double {
        let w = Int(min(a.width, b.width)), h = Int(min(a.height, b.height))
        let ax = Int(a.minX), ay = Int(a.minY), bx = Int(b.minX), by = Int(b.minY)
        guard w >= 4, h >= 6, ax >= 0, ay >= 0, ax + w <= width, ay + h <= height else { return 0 }
        var sumA = 0.0, sumAA = 0.0
        for y in 0..<h {
            let row = (ay + y) * bytesPerRow + ax
            for x in 0..<w { let value = Double(pixels[row + x]); sumA += value; sumAA += value * value }
        }
        let count = Double(w * h)
        let spreadA = sumAA - sumA * sumA / count
        guard spreadA > 0 else { return 0 }
        var best = 0.0
        for dy in -1...1 {
            for dx in -1...1 {
                let ox = bx + dx, oy = by + dy
                guard ox >= 0, oy >= 0, ox + w <= width, oy + h <= height else { continue }
                var sumB = 0.0, sumBB = 0.0, sumAB = 0.0
                for y in 0..<h {
                    let rowA = (ay + y) * bytesPerRow + ax, rowB = (oy + y) * bytesPerRow + ox
                    for x in 0..<w {
                        let valueA = Double(pixels[rowA + x]), valueB = Double(pixels[rowB + x])
                        sumB += valueB; sumBB += valueB * valueB; sumAB += valueA * valueB
                    }
                }
                let spreadB = sumBB - sumB * sumB / count
                guard spreadB > 0 else { continue }
                best = max(best, (sumAB - sumA * sumB / count) / (spreadA * spreadB).squareRoot())
            }
        }
        return best
    }

    /// The longest unbroken run of ink along any row of `area` (or any column, if `down`).
    func longestRun(in area: CGRect, down: Bool = false) -> Int {
        guard let (x0, y0, x1, y1) = bounds(area.insetBy(dx: -1, dy: -1)) else { return 0 }
        let wider = area.insetBy(dx: -area.width * 0.5 - 20, dy: -area.height * 0.5 - 20)
        guard let (bx0, by0, bx1, by1) = bounds(wider) else { return 0 }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return 0 }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        var longest = 0
        if down {
            for x in x0..<x1 {
                var run = 0
                for y in y0..<y1 {
                    if abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold { run += 1; longest = max(longest, run) } else { run = 0 }
                }
            }
        } else {
            for y in y0..<y1 {
                var run = 0
                for x in x0..<x1 {
                    if abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold { run += 1; longest = max(longest, run) } else { run = 0 }
                }
            }
        }
        return longest
    }

    /// Whether a long line of ink runs right under or over `box` and on past its end: the
    /// bar of a fraction that the text in `box` is only part of the top or bottom of.
    func hasBarRunningOn(beside box: CGRect, tall: CGFloat) -> Bool {
        let reach = Int((tall * 0.55).rounded(.up))
        let x0 = max(Int(box.minX.rounded(.down)), 0), x1 = min(Int((box.maxX + tall * 1.5).rounded(.up)), width)
        let wider = box.insetBy(dx: -tall, dy: -tall)
        guard x1 - x0 >= 6, let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let threshold = max(Int(Double(contrast) * 0.4), 24)
        let edge = min(Int(box.maxX.rounded(.up)), width - 1)
        func isBar(_ y: Int) -> Bool {
            guard y >= 0, y < height else { return false }
            // Unbroken from under the text to well past its right-hand end.
            var run = 0
            for x in x0..<x1 {
                if abs(Int(pixels[y * bytesPerRow + x]) - shade) > threshold { run += 1 } else if x <= edge { run = 0 } else { break }
            }
            return run >= (x1 - x0) * 3 / 4 && run >= Int(tall * 1.2)
        }
        for offset in 1...max(reach, 1) {
            let below = Int(box.maxY.rounded(.up)) + offset, above = Int(box.minY.rounded(.down)) - offset
            for y in [below, above] where isBar(y) {
                // A line, not the edge of a block of colour.
                if !isBar(y + 4) || !isBar(y - 4) { return true }
            }
        }
        return false
    }

    /// Whether there's a short line of ink just under `box`, however faint, with more ink
    /// under that: the bar of a fraction in text so small that the bar is a pixel thick and
    /// half washed out. `tall` is the height of a capital there.
    func hasFaintBar(under box: CGRect, tall: CGFloat) -> Bool {
        let x0 = max(Int(box.minX.rounded(.down)), 0), x1 = min(Int(box.maxX.rounded(.up)), width)
        let y0 = min(max(Int(box.maxY.rounded(.up)), 0), height), y1 = min(Int((box.maxY + tall * 0.7).rounded(.up)), height)
        let wider = box.insetBy(dx: 0, dy: -tall)
        guard x1 - x0 >= 4, y1 > y0, let (bx0, by0, bx1, by1) = bounds(wider) else { return false }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40 else { return false }
        let faint = max(Int(Double(contrast) * 0.15), 8), strong = max(Int(Double(contrast) * 0.4), 24)
        let need = max(Int(tall * 0.35), 4)
        for y in y0..<y1 {
            var run = 0, start = x0
            for x in x0...x1 {
                if x < x1, abs(Int(pixels[y * bytesPerRow + x]) - shade) > faint {
                    if run == 0 { start = x }
                    run += 1
                    continue
                }
                if run >= need {
                    // More ink under the line, within a line's height of it.
                    var below = 0
                    for under in (y + 2)..<min(y + 2 + Int(tall), height) {
                        for across in start..<(start + run) where abs(Int(pixels[under * bytesPerRow + across]) - shade) > strong { below += 1 }
                    }
                    if below >= 4 { return true }
                }
                run = 0
            }
        }
        return false
    }

    /// Part of the picture as dark ink on white, whatever it was, for reading on its own.
    func cutOut(_ area: CGRect) -> CGImage? {
        guard let (x0, y0, x1, y1) = bounds(area) else { return nil }
        let w = x1 - x0, h = y1 - y0
        // The background is judged over a wider area, since a cut-out can be mostly ink.
        let around = area.insetBy(dx: -area.width, dy: -area.height)
        guard let (bx0, by0, bx1, by1) = bounds(around) else { return nil }
        let (shade, contrast) = background(x0: bx0, y0: by0, x1: bx1, y1: by1)
        guard contrast >= 40,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return nil }
        let out = data.assumingMemoryBound(to: UInt8.self)
        let stride = context.bytesPerRow
        for y in 0..<h {
            let row = (y0 + y) * bytesPerRow + x0
            for x in 0..<w {
                let darkness = min(abs(Int(pixels[row + x]) - shade) * 255 / contrast, 255)
                out[y * stride + x] = UInt8(255 - darkness)
            }
        }
        return context.makeImage()
    }
}

/// Puts back what text recognition loses in a line of maths. A power sits higher and smaller
/// than the rest: Vision reads 2²⁰²⁶ as "22026", or x² as "x" or "x'". The bars of |x − 3| come
/// back as "I", "1" or nothing. The ink shows where these are; a raised run is then cut out and
/// read on its own, enlarged, where it reads reliably.
struct LineMender {
    let ink: Ink

    /// A piece of recognised text: where it is in the picture, in pixels from the top-left,
    /// and Vision's readings of it, best first.
    struct Piece {
        var box: CGRect
        var readings: [Reading]
    }

    struct Reading {
        var text: String
        /// Where each word of the text is: its characters, counted from the start, and its box.
        var words: [(range: Range<Int>, box: CGRect)]
    }

    private enum Kind { case normal, raised, bar }

    /// A power: glyphs sitting high after something to be a power of.
    private struct Run {
        var glyphs: Range<Int>
        var box: CGRect
        /// Its first glyph is a dash set as high as the rest: a negative power, 10⁻⁴.
        var startsWithMinus = false
    }

    private struct Layout {
        var glyphs: [CGRect]
        var kinds: [Kind]
        var runs: [Run]
        /// The height of a digit or capital in this line, and the line the text sits on.
        var tall: CGFloat
        var baseline: CGFloat
        /// Glyphs that are a slash by their shape, whatever they were read as. Vision drops
        /// the slash after a power, "(x + 3)²/2", as often as it reads it.
        var slashes: Set<Int> = []
        /// Glyphs that are a root sign by their shape, with no bar: read as V or J.
        var roots: Set<Int> = []
        /// Glyphs that are a round bracket by their shape, and which: read or not.
        var brackets: [Int: Character] = [:]
        /// The usual gap between one character and the next, in pixels.
        var usualGap: CGFloat = 0
        /// Raised glyphs that were parted from the glyph before them, which they touched.
        var parted: Set<Int> = []
        /// Glyphs that had a dot standing clear above them, taken off: a recurring digit.
        var dotted: Set<Int> = []
    }

    /// A word of a mended reading: its characters, counted from the start, where its ink is in
    /// the picture, and whether every mark of that ink is accounted for by a character. A word
    /// that isn't checked may have lost something, a power most likely.
    struct Token: Sendable {
        var range: Range<Int>
        var box: CGRect
        var isChecked: Bool
        /// There's ink in it that no character accounts for, or a power that can't be read.
        var isSuspect = false
        /// The ink of each character, where it's known.
        var places: [CGRect?] = []
        /// There's a small raised mark in it that couldn't be read: a power, perhaps.
        var hasUnreadMark = false
    }

    struct Mended: Sendable {
        var text: String
        var tokens: [Token]
    }

    /// Stands where a power is that couldn't be read: whatever it's part of can't be trusted.
    static let unreadable: Character = "\u{FFFD}"

    /// The readings of each piece, mended, and the height of a capital letter in it: nil if
    /// the ink is too small or faint to make out, and then nothing in the piece is checked.
    func mend(_ pieces: [Piece]) -> [(readings: [Mended], tall: CGFloat?)] {
        let layouts = pieces.map { layout(of: $0.box) }
        // Every power in the picture is read in one go.
        var wanted: [(piece: Int, run: Int)] = []
        for (index, layout) in layouts.enumerated() {
            for run in (layout?.runs ?? []).indices { wanted.append((index, run)) }
        }
        let texts = read(wanted.map { (layouts[$0.piece]!.runs[$0.run].box, layouts[$0.piece]!.tall) })
        var runText: [[String?]] = layouts.map { [String?](repeating: nil, count: $0?.runs.count ?? 0) }
        for (item, text) in zip(wanted, texts) { runText[item.piece][item.run] = text }

        return pieces.enumerated().map { index, piece in
            guard let layout = layouts[index] else {
                return (piece.readings.map { Self.unchanged($0, in: piece.box) }, nil)
            }
            return (piece.readings.map { rewrite($0, layout, runText[index], in: piece.box) }, layout.tall)
        }
    }

    /// A reading as Vision gave it, when there's no ink to check it against. A sign or a
    /// letter on its own has nothing to lose, so it counts as checked.
    static func unchanged(_ reading: Reading, in box: CGRect) -> Mended {
        let characters = Array(reading.text)
        let isSlight = characters.filter { $0 != " " }.count <= 2
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            guard characters[index] != " " else { index += 1; continue }
            var end = index
            while end < characters.count, characters[end] != " " { end += 1 }
            let place = reading.words.first { $0.range.lowerBound <= index && $0.range.upperBound >= end }?.box ?? box
            tokens.append(Token(range: index..<end, box: place, isChecked: isSlight))
            index = end
        }
        return Mended(text: reading.text, tokens: tokens)
    }

    // MARK: What the ink shows

    private func layout(of box: CGRect) -> Layout? {
        // Just this line's rows: powers and bars poke out of Vision's box, and the box can
        // reach into the next line.
        guard let rows = ink.rows(ofLineAt: box) else { return nil }
        let area = CGRect(x: box.minX - 3, y: CGFloat(rows.lowerBound), width: box.width + 6, height: CGFloat(rows.count))
        var glyphs = ink.glyphs(in: area)
        guard glyphs.count >= 2, glyphs.count <= 200 else { return nil }
        // A typical tall glyph, whatever towers over the line (an integral sign) or hides in it.
        // (A root sign printed without a bar stands taller than the digits it's before, and
        // a line of surds has as many of them as digits: they're left out of the measure.)
        let rootBoxes = glyphs.filter { ink.isRootSign($0) }
        let measured = glyphs.filter { !rootBoxes.contains($0) }
        let heights = (measured.isEmpty ? glyphs : measured).map(\.height).sorted()
        let typical = heights[Int(Double(heights.count - 1) * 0.75)]
        guard typical >= 8 else { return nil }
        // A slanted letter can touch its power, and the two come out as one patch of ink,
        // taller than anything else: they're parted where they join.
        // A slash stands tall too, and is all one stroke: nothing to part.
        // A dot over a digit, the mark of a recurring decimal, comes out as part of the digit,
        // as an i's dot does, and makes it half as tall again: taken off, so that the line
        // is measured by its digits, and remembered.
        var dottedBoxes: [CGRect] = []
        glyphs = glyphs.map { glyph in
            guard glyph.height >= typical * 1.25, let body = ink.body(underDetachedTopOf: glyph),
                  body.height >= typical * 0.85, body.height <= typical * 1.15 else { return glyph }
            dottedBoxes.append(body)
            return body
        }
        var partedBoxes: [CGRect] = []
        // (On a short line of small letters, x² − y² = 6, the typical glyph is shorter than a
        // capital, and a y with its tail and its power is too tall by that measure: the
        // tallest of the other glyphs is tried as the measure too.)
        let whole = glyphs
        glyphs = glyphs.flatMap { glyph -> [CGRect] in
            guard ink.lean(ofStrokeIn: glyph) == nil, !rootBoxes.contains(glyph) else { return [glyph] }
            var measures = [typical]
            if let other = whole.filter({ $0 != glyph && $0.height <= glyph.height * 0.8 }).map(\.height).max(), other > typical * 1.1 { measures.append(other) }
            for measure in measures {
                let limit = measure * (measure == typical ? 1.7 : 1.8)
                guard glyph.height >= measure * 1.12, glyph.height <= limit, glyph.width >= measure * 0.55,
                      let (base, raised) = ink.splitRaised(glyph, tall: measure) else { continue }
                partedBoxes.append(raised)
                return [base, raised]
            }
            return [glyph]
        }

        // The line the text sits on: the level most glyphs share. The exception is a short line
        // that's mostly powers, like 2¹⁰: there the few glyphs lower down are much bigger than
        // the many above, and far enough below not to be tails.
        let sizeable = glyphs.filter { $0.height >= typical * 0.35 }
        let tolerance = max(1.5, typical * 0.05)
        // (Round brackets hang below the line, and a short line can have more of them than
        // of anything else, "(e) (√3)⁴": they don't say where it is.)
        let standing = sizeable.filter { !($0.height >= 12 && $0.width <= $0.height * 0.45 && ink.bracket($0) != nil) }
        var levels: [(level: CGFloat, members: [CGRect])] = []
        for glyph in (standing.count >= 2 ? standing : sizeable).sorted(by: { $0.maxY > $1.maxY }) {
            if let index = levels.firstIndex(where: { abs($0.level - glyph.maxY) <= tolerance }) {
                levels[index].members.append(glyph)
            } else {
                levels.append((glyph.maxY, [glyph]))
            }
        }
        guard var chosen = levels.max(by: { ($0.members.count, $0.level) < ($1.members.count, $1.level) }) else { return nil }
        let usual = chosen.members.map(\.height).max() ?? typical
        // (Brackets drawn tall, round (3.1 × 10⁹)², hang below the line too: they aren't it.)
        for lower in levels where lower.level > chosen.level {
            if lower.members.contains(where: { $0.height >= usual * 1.3 && lower.level - chosen.level >= $0.height * 0.33 && ink.bracket($0) == nil }) {
                chosen = lower
            }
        }
        // A lone glyph at the bottom with others just above it has a tail (y, p, a bracket):
        // the line is where the others sit.
        if chosen.members.count == 1, let tail = chosen.members.first,
           let above = levels.filter({ $0.level < chosen.level && chosen.level - $0.level <= tail.height * 0.33 })
               .max(by: { $0.level < $1.level }) {
            chosen = above
        }
        // A short line of letters with tails, y = 2x + p: the tails' level has the most on
        // it, and what stands on the line itself is the depth of a tail higher, top and
        // bottom alike, and as tall. The line is where that stands, if a sign says so: an
        // = or a + is level with the middle of what's on the line, far too high for the
        // tails' level. (Powers as big as their digits, in a font whose digits have tails,
        // are the same shape of thing; there the signs are level with the lower line.)
        if chosen.members.count <= 3, let tails = chosen.members.map(\.height).max(), let tops = chosen.members.map(\.minY).min(),
           let upper = levels.filter({ $0.level < chosen.level }).max(by: { $0.level < $1.level }),
           let high = upper.members.map(\.height).max() {
            let shift = chosen.level - upper.level
            let hasSign = glyphs.contains { glyph in
                glyph.height <= tails * 0.85 && !chosen.members.contains(glyph) && !upper.members.contains(glyph)
                    && glyph.midY >= upper.level - high * 0.65 && glyph.midY <= upper.level - high * 0.25 && chosen.level - glyph.midY >= tails * 0.62
            }
            if hasSign, shift >= tails * 0.18, shift <= tails * 0.45,
               upper.members.contains(where: { $0.height >= tails * 0.85 && abs((tops - $0.minY) - shift) <= max(1.5, tails * 0.1) }) {
                chosen = upper
            }
        }
        let baseline = chosen.members.map(\.maxY).sorted()[chosen.members.count / 2]
        let onLine = sizeable.filter { abs($0.maxY - baseline) <= tolerance }
        let plain = onLine.filter { !rootBoxes.contains($0) }
        guard let tall = (plain.isEmpty ? onLine : plain).map(\.height).max(), tall >= 8 else { return nil }
        let top = baseline - tall

        var kinds: [Kind] = glyphs.map { glyph in
            let lift = baseline - glyph.maxY
            let bigEnough = glyph.height >= tall * 0.45 || (glyph.height >= tall * 0.36 && glyph.width >= glyph.height * 0.7)
            if lift >= tall * 0.3, bigEnough, glyph.height <= tall * 1.1, glyph.minY <= top + tall * 0.15 {
                return .raised
            }
            if glyph.width <= glyph.height * 0.16, glyph.height >= tall * 1.12, glyph.maxY - baseline >= tall * 0.06 {
                return .bar
            }
            return .normal
        }

        // Raised glyphs side by side are one power, if they follow something to be a power of.
        // How close it has to be goes by the gaps between this line's characters: in a
        // fixed-width font a power has a cell to itself, and stands well off.
        let gaps = zip(glyphs, glyphs.dropFirst()).map { $1.minX - $0.maxX }.filter { $0 > 0 }.sorted()
        let usualGap = gaps.isEmpty ? 0 : gaps[gaps.count / 4]
        let reach = max(tall * 0.45, min(usualGap * 2.2, tall * 0.75))
        // A dash set high, straight before something raised and after something to be a
        // power of, is the minus sign of a negative power: too thin to count as raised by
        // its size. An ordinary minus sign sits at half the height of a capital.
        var raisedMinus = Set<Int>()
        for k in glyphs.indices.dropFirst().dropLast() where kinds[k] == .normal && kinds[k + 1] == .raised {
            let dash = glyphs[k]
            guard dash.height <= max(2, tall * 0.16), dash.width >= tall * 0.2, dash.width <= tall * 0.7,
                  baseline - dash.maxY >= tall * 0.62, glyphs[k + 1].minX - dash.maxX <= tall * 0.35,
                  dash.midY >= glyphs[k + 1].minY, dash.midY <= glyphs[k + 1].maxY,
                  kinds[k - 1] != .raised, glyphs[k - 1].height >= tall * 0.4, dash.minX - glyphs[k - 1].maxX <= reach else { continue }
            kinds[k] = .raised
            raisedMinus.insert(k)
        }
        var runs: [Run] = []
        var index = 0
        while index < glyphs.count {
            guard kinds[index] == .raised else { index += 1; continue }
            var end = index + 1
            while end < glyphs.count, kinds[end] == .raised, glyphs[end].minX - glyphs[end - 1].maxX <= tall * 0.4 { end += 1 }
            let hasBase = index > 0 && kinds[index - 1] != .raised && glyphs[index - 1].height >= tall * 0.4
                && glyphs[index].minX - glyphs[index - 1].maxX <= reach
            if hasBase {
                runs.append(Run(glyphs: index..<end, box: glyphs[index..<end].dropFirst().reduce(glyphs[index]) { $0.union($1) },
                                startsWithMinus: raisedMinus.contains(index)))
            } else {
                for k in index..<end { kinds[k] = .normal }
            }
            index = end
        }
        // Many powers among few ordinary glyphs means the line's been misjudged, not that
        // it's full of powers.
        let ordinary = kinds.filter { $0 == .normal }.count
        guard runs.count <= max(2, ordinary / 3) else { return nil }
        // A slash is one thin straight stroke that leans well over. The stems of slanted
        // letters (l, I, 1) lean less, 0.24 at most, and stop at the line; a slash that leans
        // as little as that goes on below it.
        var slashes = Set<Int>()
        for (index, glyph) in glyphs.enumerated() where kinds[index] == .normal && glyph.height >= tall * 0.85 && glyph.height <= tall * 2 {
            guard let lean = ink.lean(ofStrokeIn: glyph) else { continue }
            if lean >= 0.26 || (lean >= 0.2 && glyph.maxY - baseline >= tall * 0.12) { slashes.insert(index) }
        }
        // A root sign with no bar: by its shape, and standing taller than the line's digits.
        // (In bold print it's no taller than they are.)
        let roots = Set(glyphs.indices.filter { kinds[$0] == .normal && rootBoxes.contains(glyphs[$0]) && glyphs[$0].height >= tall * 0.95 && glyphs[$0].height <= tall * 2.2 })
        // Round brackets, which Vision drops now and then ("(f √3 × √3") or reads as square ones.
        var brackets: [Int: Character] = [:]
        for (index, glyph) in glyphs.enumerated() where kinds[index] == .normal && glyph.height >= max(12, tall * 1.05) && glyph.width <= glyph.height * 0.45 {
            if let sign = ink.bracket(glyph)?.first { brackets[index] = sign }
        }
        return Layout(glyphs: glyphs, kinds: kinds, runs: runs, tall: tall, baseline: baseline, slashes: slashes, roots: roots, brackets: brackets, usualGap: usualGap,
                      parted: Set(glyphs.indices.filter { partedBoxes.contains(glyphs[$0]) }),
                      dotted: Set(glyphs.indices.filter { dottedBoxes.contains(glyphs[$0]) }))
    }

    /// How tall the capitals are in the text at `box`, and the line it sits on.
    func metrics(of box: CGRect) -> (tall: CGFloat, baseline: CGFloat)? {
        layout(of: box).map { ($0.tall, $0.baseline) }
    }

    /// What the ink shows for a piece, for checking: each glyph's box and what it's taken to be.
    func describe(_ box: CGRect) -> String {
        guard let layout = layout(of: box) else { return "no layout" }
        let marks = zip(layout.glyphs, layout.kinds).enumerated().map { index, item in
            let (glyph, kind) = item
            return "\(kind == .raised ? "R" : (kind == .bar ? "B" : (layout.slashes.contains(index) ? "s" : (layout.roots.contains(index) ? "√" : "n"))))(\(Int(glyph.minX)),\(Int(glyph.minY)) \(Int(glyph.width))×\(Int(glyph.height)))"
        }
        return "tall \(Int(layout.tall)) runs \(layout.runs.count): " + marks.joined(separator: " ")
    }

    /// What a patch of ink is taken to be.
    /// What a root sign with no bar is read as: a V, a J, a Г, a stroke, some letter or
    /// sign. Never a digit, but for the two that are strokes themselves.
    private static func passesForRoot(_ character: Character) -> Bool {
        !character.isNumber || character == "1" || character == "7"
    }

    /// …and what one is usually read as.
    /// (A 5 too: the heavy sign, with its hook, its stem and its stroke along the top, is read
    /// as one, "952 cm" for 9√2 cm. A real 5 has ink at its top left corner, and a root sign's
    /// shape rules that out.)
    private static let rootLookalikes: Set<Character> = ["√", "V", "v", "J", "j", "Г", "Ґ", "Γ", "F", "T", "f", "r", "Y", "y", "/", "\\", "1", "7", "5", "l", "I", "|", "ſ", "ʃ", "ƒ", "ν", "✓", "✔"]

    enum Mark: Sendable { case character, power, bar, slash }

    /// Each patch of ink in the text at `box` and what it's taken to be, for showing what
    /// was made out (Settings, Debug). In pixels, like `box`.
    func marks(of box: CGRect) -> [(box: CGRect, mark: Mark)] {
        guard let layout = layout(of: box) else { return [] }
        return layout.glyphs.indices.map { index in
            switch layout.kinds[index] {
            case .raised:
                // A degree sign is a ring as wide as it's tall: not a power.
                (layout.glyphs[index], layout.glyphs[index].height < layout.tall * 0.62 && layout.glyphs[index].width >= layout.glyphs[index].height * 0.86
                    && ink.isRing(layout.glyphs[index]) ? .character : .power)
            case .bar: (layout.glyphs[index], .bar)
            case .normal: (layout.glyphs[index], layout.slashes.contains(index) ? .slash : .character)
            }
        }
    }

    // MARK: Matching the ink to a reading

    /// Characters that really are drawn alike in many fonts, so that one shape read as both
    /// says nothing.
    private static func lookAlike(_ a: Character, _ b: Character) -> Bool {
        for group in ["lI1|!ij", "O0oQD", "xX×", "-−–—_=", ".,·:;'", "cCeo", "sS5", "vVyY", "wW", "zZ2", "uUnh", "pP", "kK", "()[]{}"] where group.contains(a) && group.contains(b) {
            return true
        }
        return false
    }

    private static func isPlain(_ character: Character) -> Bool {
        character.isASCII && (character.isNumber || character.isLetter)
    }

    /// How badly a character suits a glyph: nothing for a fit, more the odder the pairing.
    private func mismatch(_ glyph: Int, _ character: Character, _ layout: Layout) -> Double {
        let box = layout.glyphs[glyph], tall = layout.tall
        switch layout.kinds[glyph] {
        case .raised:
            return Self.isPlain(character) ? 0 : 0.4
        case .bar:
            return "|Il1![]".contains(character) ? 0 : 5
        case .normal:
            let flat = box.height <= tall * 0.3 && box.width >= box.height * 1.6
            let dot = box.height <= tall * 0.3 && box.width <= box.height * 1.5
            let big = box.height >= tall * 0.6
            var cost = 0.0
            if flat, !"-−–—=_~≈".contains(character) { cost += 2 }
            if dot, !".,·:;'`".contains(character) { cost += 2 }
            if big, "-−–—_.,·~".contains(character) { cost += 2 }
            if box.height < tall * 0.5, (character.isASCII && character.isNumber) || character.isUppercase || "()[]|/".contains(character) { cost += 2 }
            // A slash is read as a slash, or as some other stroke; anything else read where
            // it stands belongs to the ink beside it.
            if layout.slashes.contains(glyph), !"/⁄∕lI1|!\\%".contains(character) { cost += 2 }
            if layout.roots.contains(glyph), !Self.passesForRoot(character) { cost += 2 }
            // A bracket is read as a bracket, or as some upright stroke.
            if layout.brackets[glyph] != nil, !"()[]{}|lI1!/\\CcJj".contains(character) { cost += 2 }
            return cost
        }
    }

    /// Which character each of some glyphs goes with: every character goes with one glyph, in
    /// order, and a glyph can go without only if it's a raised one, a bar or a slash, which
    /// Vision often leaves out. Nil if they can't be matched up.
    private func match(_ glyphs: [Int], _ places: [Int], _ characters: [Character], _ layout: Layout) -> [Int: Int]? {
        matchWithCost(glyphs, places, characters, layout)?.matched
    }

    private func matchWithCost(_ glyphs: [Int], _ places: [Int], _ characters: [Character], _ layout: Layout) -> (matched: [Int: Int], cost: Double)? {
        let glyphCount = glyphs.count, count = places.count
        guard count <= glyphCount, glyphCount > 0 else { return nil }
        let impossible = Double.infinity
        // A round bracket can go unread only where one is missing: more opened than closed
        // in what was read, or the other way about. ("()" for the label (j) has both.)
        let opened = places.filter { characters[$0] == "(" }.count, closed = places.filter { characters[$0] == ")" }.count
        let missing: Character? = opened > closed ? ")" : (closed > opened ? "(" : nil)
        var cost = [[Double]](repeating: [Double](repeating: impossible, count: count + 1), count: glyphCount + 1)
        cost[0][0] = 0
        for g in 1...glyphCount {
            for c in 0...min(g, count) {
                var best = impossible
                if c > 0, cost[g - 1][c - 1] < impossible {
                    best = cost[g - 1][c - 1] + mismatch(glyphs[g - 1], characters[places[c - 1]], layout)
                }
                // A per cent sign can be two or three patches of ink: its rings and its stroke.
                if c > 0, characters[places[c - 1]] == "%" {
                    for size in 2...3 where g >= size && cost[g - size][c - 1] < impossible { best = min(best, cost[g - size][c - 1]) }
                }
                if layout.kinds[glyphs[g - 1]] != .normal || layout.slashes.contains(glyphs[g - 1]) || layout.roots.contains(glyphs[g - 1])
                    || (missing != nil && layout.brackets[glyphs[g - 1]] == missing), cost[g - 1][c] < impossible {
                    best = min(best, cost[g - 1][c] + 1)
                }
                cost[g][c] = best
            }
        }
        // Too odd a fit means the glyphs and characters don't really correspond.
        guard cost[glyphCount][count] < impossible, cost[glyphCount][count] <= 3 + Double(glyphCount) * 0.5 else { return nil }
        var matched: [Int: Int] = [:]
        var g = glyphCount, c = count
        while g > 0 {
            if c > 0, characters[places[c - 1]] == "%",
               let size = (2...3).first(where: { g >= $0 && cost[g - $0][c - 1] < impossible && cost[g - $0][c - 1] <= cost[g][c] + 1e-9 }) {
                // The sign takes all of them: the first stands for it, the rest are passed over.
                matched[glyphs[g - size]] = places[c - 1]
                for k in (g - size + 1)..<g { matched[glyphs[k]] = -1 }
                g -= size
                c -= 1
                continue
            }
            let viaMatch = c > 0 && cost[g - 1][c - 1] < impossible
                ? cost[g - 1][c - 1] + mismatch(glyphs[g - 1], characters[places[c - 1]], layout) : impossible
            if viaMatch < impossible, viaMatch <= cost[g][c] + 1e-9 {
                matched[glyphs[g - 1]] = places[c - 1]
                c -= 1
            }
            g -= 1
        }
        return (matched, cost[glyphCount][count])
    }

    /// The reading with its powers and bars put right. A power that can't be read leaves a
    /// mark in its place. Words that can't be matched to the ink are left as they were, unchecked.
    private func rewrite(_ reading: Reading, _ layout: Layout, _ runText: [String?], in pieceBox: CGRect) -> Mended {
        // Stray letters from other alphabets, which Vision adds at the ends of lines, are
        // nothing on the page.
        let original = Array(reading.text)
        var characters: [Character] = original.map { character in
            guard character.isLetter, !character.isASCII, Parser.lookalikes[character] == nil else { return character }
            return character.unicodeScalars.allSatisfy { (0x370...0x3FF).contains($0.value) } ? character : " "
        }
        // The words, or the whole line as one if Vision can't say where its words are.
        var words = reading.words.filter { !$0.range.isEmpty && $0.range.upperBound <= characters.count }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        let distinct = Set(words.map { Int($0.box.minX) }).count
        var hasPlaces = true
        if words.isEmpty || (words.count > 1 && distinct == 1) {
            words = [(0..<characters.count, CGRect(x: -1e6, y: 0, width: 2e6, height: 1))]
            hasPlaces = false
        }
        // Each glyph belongs to the word it's under, or failing that the word before it: a
        // power Vision didn't read is outside every word.
        var glyphsOf = [[Int]](repeating: [], count: words.count)
        var current = 0
        for (index, glyph) in layout.glyphs.enumerated() {
            if let word = words.firstIndex(where: { glyph.midX >= $0.box.minX - 1 && glyph.midX <= $0.box.maxX + 1 }) { current = word }
            glyphsOf[current].append(index)
        }

        var runOf = [Int: Int]()
        for (number, run) in layout.runs.enumerated() { for k in run.glyphs { runOf[k] = number } }
        var matches: [[Int: Int]?] = []
        var matched: [Int: Int] = [:]
        /// Glyphs that are part of a character already written, like the rings of %.
        var absorbed = Set<Int>()
        /// Words with a letter of no alphabet maths is written in, where there's ink for one:
        /// something was misread there, and there's no saying what.
        var misread = Set<Int>()
        for (index, word) in words.enumerated() {
            let places = word.range.filter { characters[$0] != " " }
            let plain = matchWithCost(glyphsOf[index], places, characters, layout)
            var found = plain?.matched
            // A letter from another alphabet may be something misread rather than something
            // made up, with ink of its own: whichever way fits the ink better.
            if word.range.contains(where: { characters[$0] == " " && original[$0] != " " }) {
                var kept = characters
                for place in word.range where original[place] != " " { kept[place] = original[place] }
                if let again = matchWithCost(glyphsOf[index], word.range.filter { kept[$0] != " " }, kept, layout),
                   again.cost <= (plain?.cost ?? .infinity) {
                    // A letter of some alphabet standing on the line, ț or ą, is a character
                    // misread. (Not a mark like º, which is what a power gets read as.)
                    let strays = Set(word.range.filter { characters[$0] == " " && original[$0] != " " })
                    let isMisread = again.matched.contains { glyph, place in
                        guard strays.contains(place), layout.kinds[glyph] == .normal, let scalar = kept[place].unicodeScalars.first else { return false }
                        return scalar.properties.generalCategory == .lowercaseLetter || scalar.properties.generalCategory == .uppercaseLetter
                    }
                    found = again.matched
                    characters = kept
                    if isMisread { misread.insert(index) }
                }
            }
            matches.append(found)
            for (glyph, character) in found ?? [:] {
                if character >= 0 { matched[glyph] = character } else { absorbed.insert(glyph) }
            }
        }
        // Words with ink left over, or a letter far taller than it should be: something's been
        // missed there, most likely a power run into the letter under it.
        var suspect = misread
        /// Glyphs read as 6 whose ink is a b: a straight stem down to the bottom left corner,
        /// and no more than the stem's width across the top.
        var stems = Set<Int>()
        /// Numbers with a dot over a digit, recurring decimals, and which digits have one.
        var recurring = Set<Int>()
        var dotted = Set<Int>()
        /// Words whose letters run together in the ink, with nothing missing.
        var touching = Set<Int>()
        let small = "acemnorsuvwxz"
        /// Words that are maths rather than prose: the two can be in different fonts, and
        /// only letters in the same font can be compared for size.
        func isMaths(_ word: Int) -> Bool {
            let text = words[word].range.map { characters[$0] }
            return text.count < 4 || text.contains { !$0.isLetter }
        }
        var wordOf = [Int: Int]()
        for (index, glyphs) in glyphsOf.enumerated() { for glyph in glyphs { wordOf[glyph] = index } }
        let ordinary = matched.filter { layout.kinds[$0.key] == .normal }
        let digits = ordinary.filter { characters[$0.value].isNumber }.map { layout.glyphs[$0.key] }
        let capitals = ordinary.filter { characters[$0.value].isUppercase && characters[$0.value].isASCII }.map { layout.glyphs[$0.key] }
        let smallOnes = ordinary.filter { small.contains(characters[$0.value]) && isMaths(wordOf[$0.key] ?? 0) }.map { layout.glyphs[$0.key].height }.sorted()
        let usualSmall = smallOnes.isEmpty ? nil : smallOnes[(smallOnes.count - 1) / 2]
        // The small letters of the whole line, words and all. The words may be in another
        // font, but never one so much smaller that a letter with a power run into it,
        // half as tall again, would pass for an ordinary one.
        let allSmall = ordinary.filter { small.contains(characters[$0.value]) }.map { layout.glyphs[$0.key].height }.sorted()
        let usualOfAll = allSmall.count >= 3 ? allSmall[(allSmall.count - 1) / 2] : nil
        /// Whether digits are all of a height and sit on the line, as in most fonts. Old-style
        /// digits go up and down like small letters, and tell nothing about the letters' size.
        func areLining(_ boxes: [CGRect]) -> Bool {
            guard let tallest = boxes.map(\.height).max(), let shortest = boxes.map(\.height).min() else { return false }
            return tallest - shortest <= max(1.5, tallest * 0.08) && boxes.allSatisfy { abs($0.maxY - layout.baseline) <= layout.tall * 0.08 }
        }
        let highest = ((areLining(digits) ? digits : []) + capitals).map(\.minY).min()
        for (index, word) in words.enumerated() {
            guard let found = matches[index] else {
                let places = word.range.filter { characters[$0] != " " }
                if glyphsOf[index].count > places.count || glyphsOf[index].contains(where: { layout.kinds[$0] != .normal }) {
                    suspect.insert(index)
                } else if let highest, !glyphsOf[index].isEmpty, places.count - glyphsOf[index].count <= 2 {
                    // Fewer patches of ink than characters: letters that touch, as slanted
                    // ones do. Nothing's been left out, as long as nothing stands above the
                    // capitals, where a power would be. Something broad that does (not a
                    // bracket or a stroke) is a power run into what it's on.
                    let above = glyphsOf[index].filter { layout.glyphs[$0].minY < highest - layout.tall * 0.06 }
                    let broad = above.filter { layout.glyphs[$0].width > layout.glyphs[$0].height * 0.5 }
                    // A root sign stands tall too, and often touches the number after it.
                    let startsWithRoot = places.first.map { "√VvJ".contains(characters[$0]) } == true && broad == [glyphsOf[index][0]]
                    // …or stops short of the line at its right-hand end, where two digits were
                    // read: the second is a power, level with the top of the first, "5²".
                    let hasDigits = zip(places, places.dropFirst()).contains { characters[$0].isNumber && (characters[$1].isNumber || "°º".contains(characters[$1])) }
                    let hasPowerRunIn = hasDigits && glyphsOf[index].contains {
                        layout.glyphs[$0].width >= layout.tall * 0.95 && ink.hasRaisedEnd(layout.glyphs[$0], tall: layout.tall)
                    }
                    if hasPowerRunIn {
                        suspect.insert(index)
                    } else if broad.isEmpty || startsWithRoot {
                        touching.insert(index)
                    } else {
                        suspect.insert(index)
                    }
                }
                continue
            }
            for (glyph, place) in found where layout.kinds[glyph] == .normal && place >= 0 {
                let box = layout.glyphs[glyph]
                let character = characters[place]
                let floats = box.maxY < layout.baseline - layout.tall * 0.22
                // A times sign read as x floats, and is no letter.
                if "xX".contains(character), box.maxY <= layout.baseline - layout.tall * 0.12, box.height <= layout.tall * 0.75 { continue }
                // (In heavier print it's nearly as tall as a digit, and only just clear of the line.)
                if "xXхХ×".contains(character), box.height >= layout.tall * 0.4, box.height <= layout.tall * 0.92,
                   box.width >= box.height * 0.7, box.width <= box.height * 1.4,
                   layout.baseline - box.maxY >= max(1.5, layout.tall * 0.08), box.minY >= layout.baseline - layout.tall { continue }
                // A root sign known by its shape is no letter either, whatever it was read as.
                if layout.roots.contains(glyph), box.height >= layout.tall * 1.05 ? Self.passesForRoot(character) : Self.rootLookalikes.contains(character) { continue }
                // A number or letter well clear of the line the rest sits on is the top or
                // bottom of a fraction, read as if it were in the line.
                if character.isNumber || character.isLetter, floats || box.minY > layout.baseline - layout.tall * 0.3 { suspect.insert(index) }
                // …and one half as tall again as a capital is a whole fraction, top, bar
                // and bottom run together in small text, read as a single digit.
                if character.isNumber ? box.height > layout.tall * 1.45 : (character.isLetter && box.height > layout.tall * 1.8) { suspect.insert(index) }
                // A "digit" that stands above the capitals and hangs below the line as well
                // is an integral sign or a bracket.
                if character.isNumber, box.minY < layout.baseline - layout.tall * 1.12, box.maxY > layout.baseline + layout.tall * 0.12 { suspect.insert(index) }
                // A "digit" wider than it's tall has a letter run into it that Vision left
                // out: the 3x of 3x², read as 3².
                if character.isNumber, box.width > max(box.height * 0.95, layout.tall * 0.9) { suspect.insert(index) }
                // A 6 curves in at the bottom; a slanted b, which Vision reads as 6 time
                // after time, has a straight stem that reaches the bottom left corner.
                // That's a b, then, 81b² and not 816², where it stands taller than the
                // digits beside it (a b's stem does) in a line that has a letter of its own.
                // Anywhere else there's no saying, and the word isn't to be trusted.
                if character == "6", !ink.hasRoundBase(box), !ink.hasBroadTop(box) {
                    let others = digits.filter { $0 != box }
                    let hasLetter = characters.indices.contains { i in
                        characters[i].isLetter && characters[i].isASCII && (i == 0 || !characters[i - 1].isLetter)
                            && (i + 1 >= characters.count || !characters[i + 1].isLetter)
                    }
                    if hasLetter, others.count >= 2, areLining(others), let top = others.map(\.minY).min(), let tallest = others.map(\.height).max(),
                       box.minY <= top - max(1, layout.tall * 0.05), box.height >= tallest + 1 {
                        stems.insert(glyph)
                    } else {
                        suspect.insert(index)
                    }
                }
                // A times sign is small. Read where something as tall as a capital stands,
                // the characters and the ink have been paired off wrongly: a³ × b² came back
                // with its b and its × the other way round.
                if character == "×", box.height >= layout.tall * 0.85 { suspect.insert(index) }
                // …and a letter of another alphabet standing for a digit, З for 3, where the
                // ink is too short to be a digit.
                // (A capital: a small з is the 3 of a fraction set small.)
                if character.isUppercase, Parser.lookalikes[character]?.isNumber == true, box.height <= layout.tall * 0.72 { suspect.insert(index) }
                // A dot over a digit makes it recur, 0.4̇5̇: the number as read is another one.
                // (Only a digit after a decimal point recurs: a dot over the 30 on a
                // diagram is a point of the diagram.)
                let isDecimal = (word.range.lowerBound..<place).reversed().prefix { characters[$0].isNumber || characters[$0] == "." }.contains { characters[$0] == "." }
                if character.isNumber, isDecimal, layout.dotted.contains(glyph) || ink.hasDot(over: box, tall: layout.tall) || ink.hasDetachedTop(box) {
                    recurring.insert(index)
                    dotted.insert(place)
                }
                // A "digit" with a slash for its left edge has the slash run into it, "/7".
                if character.isNumber, ink.hasSlashInFront(box) { suspect.insert(index) }
                // A slash by its shape, read as something that's no kind of stroke.
                if layout.slashes.contains(glyph), !"/⁄∕lI1|!\\%".contains(character) { suspect.insert(index) }
                // A plus sign has an upright through its middle. Without one it's a ÷, which
                // in small text Vision reads as a plus.
                if character == "+", !ink.hasUpright(box), !ink.isDivisionSign(box) { suspect.insert(index) }
                // "x2" with the 2 full size and on the line: not a power, which would be
                // raised, so something between them was lost, a slash most likely.
                if character.isNumber, place > 0, characters[place - 1].isLetter, place < 2 || !characters[place - 2].isLetter,
                   let before = found.first(where: { $0.value == place - 1 })?.key, layout.kinds[before] == .normal,
                   // …and not found in the ink after all.
                   !layout.slashes.contains(where: { $0 > before && $0 < glyph && found[$0] == nil }),
                   // …unless the "letter" is a root sign, which stands taller than any letter.
                   !("VvJ".contains(characters[place - 1]) && layout.glyphs[before].height >= layout.tall * 1.12),
                   box.height >= layout.tall * 0.85, abs(box.maxY - layout.baseline) <= layout.tall * 0.1 { suspect.insert(index) }
                if small.contains(character) {
                    // A small letter standing above every capital and digit in the line, or
                    // well above the other small letters, has a power run into it.
                    if let highest, box.minY < highest - layout.tall * 0.06 { suspect.insert(index) }
                    if let usualSmall, isMaths(index), box.height > usualSmall * 1.25 { suspect.insert(index) }
                    if let usualOfAll, box.height > usualOfAll * 1.4 { suspect.insert(index) }
                } else if character.isNumber, digits.count >= 3 {
                    // A "digit" standing taller than the rest, when the rest are all of a
                    // height, is a root sign or a bracket misread.
                    var others = digits
                    if let own = others.firstIndex(of: box) { others.remove(at: own) }
                    if areLining(others), let tallest = others.map(\.height).max(), box.height >= (tallest * 1.12).rounded(.up) { suspect.insert(index) }
                }
            }
        }

        // The same shape read as two different characters: one of the readings is wrong
        // (an italic b read as 6 in one place and b in another).
        let sized = ordinary.filter { layout.glyphs[$0.key].height >= layout.tall * 0.45 }.sorted { $0.key < $1.key }
        for (first, one) in sized.enumerated() {
            for other in sized[(first + 1)...] {
                let a = Parser.lookalikes[characters[one.value]] ?? characters[one.value]
                let b = Parser.lookalikes[characters[other.value]] ?? characters[other.value]
                let boxA = layout.glyphs[one.key], boxB = layout.glyphs[other.key]
                guard abs(boxA.width - boxB.width) <= max(1, boxA.width * 0.08), abs(boxA.height - boxB.height) <= max(1, boxA.height * 0.06) else { continue }
                // A digit and a letter are never drawn alike, bar the few that always are: any
                // likeness there is one of them misread.
                let limit = a.isNumber != b.isNumber ? 0.85 : 0.93
                guard a != b, !Self.lookAlike(a, b), ink.likeness(boxA, boxB) >= limit else { continue }
                if let word = wordOf[one.key] { suspect.insert(word) }
                if let word = wordOf[other.key] { suspect.insert(word) }
            }
        }

        // What's written, character by character: the ink each came from, and its word.
        var out: [(character: Character, box: CGRect?, word: Int)] = []
        var spoiled = Set<Int>()
        var unsure = Set<Int>()
        func write(_ text: some Sequence<Character>, _ box: CGRect?, _ word: Int) {
            for character in text { out.append((character, box, word)) }
        }
        /// Characters of the reading that no ink was matched to, written as they are, but
        /// for letters from other alphabets, which Vision makes up at the ends of lines.
        func writeBack(_ range: Range<Int>, _ word: Int) {
            for place in range where !(characters[place] == " " && original[place] != " ") {
                out.append((original[place], nil, word))
            }
        }
        var written = 0
        for (index, word) in words.enumerated() {
            if word.range.lowerBound > written { write(original[written..<word.range.lowerBound], nil, -1) }
            written = max(written, word.range.upperBound)
            guard matches[index] != nil else {
                write(original[word.range], nil, index)
                continue
            }
            var lastCharacter = word.range.lowerBound - 1
            // The last glyph written as an ordinary character, for the gaps between them.
            var before: (glyph: Int, character: Character)?
            var beforeThat: Int?
            for glyph in glyphsOf[index] where !absorbed.contains(glyph) {
                let character = matched[glyph]
                let box = layout.glyphs[glyph]
                if let character {
                    if character > lastCharacter + 1 { writeBack((lastCharacter + 1)..<character, index) }
                    lastCharacter = character
                    // A per cent sign's ring sits high, like a power, but it's the sign.
                    if characters[character] == "%" {
                        let parts = glyphsOf[index].filter { $0 > glyph && absorbed.contains($0) }.prefix(2)
                        write("%", parts.reduce(box) { $0.union(layout.glyphs[$1]) }, index)
                        continue
                    }
                }
                switch layout.kinds[glyph] {
                case .normal:
                    guard let character else {
                        // Ink that no character was read for. A slash is known by its shape.
                        if layout.slashes.contains(glyph) {
                            write("/", box, index)
                            beforeThat = before?.glyph
                            before = (glyph, "/")
                        } else if layout.roots.contains(glyph) {
                            // …and so is a root sign.
                            write("√", box, index)
                            beforeThat = before?.glyph
                            before = (glyph, "√")
                        } else if let sign = layout.brackets[glyph] {
                            // …and a round bracket.
                            write([sign], box, index)
                            beforeThat = before?.glyph
                            before = (glyph, sign)
                        }
                        continue
                    }
                    var symbol = characters[character]
                    // A root sign with no bar, read as a V, a J or some stroke: the ink says
                    // which it is. Read as anything else, there's no saying what's there.
                    // (One no taller than the digits has to have been read as something a
                    // root sign is read as: its shape alone isn't enough to go on.)
                    if layout.roots.contains(glyph) {
                        if box.height >= layout.tall * 1.05 {
                            if Self.passesForRoot(symbol) { symbol = "√" } else { suspect.insert(index) }
                        } else if Self.rootLookalikes.contains(symbol) {
                            symbol = "√"
                        }
                    }
                    // A times sign read between a pair of brackets, g(×), with its ink sitting on
                    // the line: the letter x.
                    if symbol == "×", layout.baseline - box.maxY < max(1.5, layout.tall * 0.08), glyph > 0, glyph + 1 < layout.glyphs.count,
                       matched[glyph - 1].map({ characters[$0] }) == "(", matched[glyph + 1].map({ characters[$0] }) == ")" {
                        symbol = "x"
                    }
                    // A round bracket read as a square one, or as a stroke.
                    if let sign = layout.brackets[glyph], "[]{}".contains(symbol) { symbol = sign }
                    // A times sign read as the letter x, between numbers or roots: it stands
                    // clear of the line the digits sit on, where a letter sits on it.
                    if "xXхХ".contains(symbol), box.height >= layout.tall * 0.4, box.height <= layout.tall * 0.92,
                       box.width >= box.height * 0.7, box.width <= box.height * 1.4,
                       layout.baseline - box.maxY >= max(1.5, layout.tall * 0.08), box.minY >= layout.baseline - layout.tall,
                       glyph > 0, glyph + 1 < layout.glyphs.count,
                       let left = matched[glyph - 1].map({ characters[$0] }), left.isNumber || ")°%".contains(left),
                       layout.roots.contains(glyph + 1) || matched[glyph + 1].map({ characters[$0].isNumber || "(√".contains(characters[$0]) }) == true {
                        symbol = "×"
                    }
                    // Words Vision ran together, "intheform": between two letters of a long
                    // run of letters, a gap as wide as a space, and far wider than the gaps
                    // between this line's characters, is one.
                    if let last = before, last.character.isLetter, symbol.isLetter,
                       word.range.count >= 5, word.range.allSatisfy({ characters[$0].isLetter }) {
                        let gap = box.minX - layout.glyphs[last.glyph].maxX
                        if gap >= max(layout.tall * 0.3, layout.usualGap * 2.5) { write(" ", nil, -1) }
                    }
                    // A full stop with a gap after it ended a question number, "4. 7(x − 2)":
                    // Vision closes the gap up, and 4.7 is another number altogether.
                    if let last = before, last.character == ".", let earlier = beforeThat, symbol != " " {
                        let gapAfter = box.minX - layout.glyphs[last.glyph].maxX
                        let gapBefore = layout.glyphs[last.glyph].minX - layout.glyphs[earlier].maxX
                        if gapAfter >= layout.tall * 0.35, gapAfter >= gapBefore * 1.5, gapAfter - gapBefore >= layout.tall * 0.2 { write(" ", nil, -1) }
                    }
                    // ÷ comes back as a colon, which is much narrower.
                    if symbol == ":", box.width >= layout.tall * 0.4 { symbol = "÷" }
                    // A dash with room either side is a minus sign; one hard up against
                    // its neighbours joins a range or a date, 9-5.
                    if "-–−—".contains(symbol), box.height <= layout.tall * 0.3 {
                        let left = glyph > 0 ? box.minX - layout.glyphs[glyph - 1].maxX : 0
                        let right = glyph + 1 < layout.glyphs.count ? layout.glyphs[glyph + 1].minX - box.maxX : 0
                        symbol = min(left, right) >= layout.tall * 0.3 ? "−" : "-"
                    }
                    // A times sign read as the letter x: it floats above the line, which no letter does.
                    if "xX".contains(symbol), box.maxY <= layout.baseline - layout.tall * 0.12, box.height <= layout.tall * 0.75 { symbol = "×" }
                    // A root sign stands taller than any capital. Vision reads it as V or J.
                    if "VvJ".contains(symbol), box.height >= layout.tall * 1.12, box.minY < layout.baseline - layout.tall * 1.05 {
                        symbol = "√"
                    }
                    // A slash read as a 1 or an l, "7/8" as "718": the ink says which.
                    if layout.slashes.contains(glyph), "lI1|!".contains(symbol) { symbol = "/" }
                    // A slanted b read as a 6: the ink says which.
                    if symbol == "6", stems.contains(glyph) { symbol = "b" }
                    // A per cent sign drawn in one piece, read as an 8: "50%" as "508".
                    if symbol == "8", ink.isPerCent(box) { symbol = "%" }
                    // A division sign read as a plus: the ink has the bar and its two dots.
                    if symbol == "+", ink.isDivisionSign(box) { symbol = "÷" }
                    // ⩾ and ⩽ read as > and <: the ink has the line under the sign.
                    if symbol == ">" || symbol == "<", ink.hasThirdStroke(box) { symbol = symbol == ">" ? "≥" : "≤" }
                    write([symbol], box, index)
                    beforeThat = before?.glyph
                    before = (glyph, symbol)
                case .bar:
                    write("|", box, index)
                case .raised:
                    guard let number = runOf[glyph] else {
                        if let character { write([characters[character]], box, index) }
                        continue
                    }
                    guard layout.runs[number].glyphs.lowerBound == glyph else { continue }
                    let run = layout.runs[number]
                    // What Vision made of the run.
                    let inline = run.glyphs.compactMap { matched[$0] }.map { characters[$0] }
                    let small = run.glyphs.count == 1 && run.box.height < layout.tall * 0.5
                    // One mark set high that's a ring, or was read as one (a nought, an o, a
                    // degree sign): a degree sign if it's as wide as it's tall, whatever it was
                    // read as, and never a power (42° isn't 42 to the nought). A nought is
                    // narrower than it's tall: read as a degree sign, it's still a nought.
                    // Courier's ring is over half as tall as a capital, bigger than "small".
                    let shape = run.box.width / run.box.height
                    let readsAsRing = runText[number].map { ["0", "o", "O", "°", "º"].contains($0) } ?? false
                        || (!inline.isEmpty && inline.allSatisfy { "0oO°º".contains($0) })
                    if run.glyphs.count == 1 {
                        // (In small print a ring comes out a pixel narrower than it's tall, 6 by 7;
                        // it's under half a capital high, which a raised nought never is.)
                        let isRoundAndSmall = run.box.height < layout.tall * 0.62
                            && ((0.86...1.25).contains(shape) || (shape >= 0.8 && run.box.height <= layout.tall * 0.47))
                        // (A ring with a real hole: 9% of its box or more in the heaviest type,
                        // where a raised 4 has a nick of 2 or 3%.)
                        let isLoop = ink.isRing(run.box, round: false, hole: 0.06)
                        // (Too small to show its hole, a ring is taken on trust. Bigger, it has
                        // to be one: a raised 4 is as wide as it's tall and gets read as a ring.)
                        if isRoundAndSmall, isLoop || (readsAsRing && min(run.box.width, run.box.height) < 7) {
                            write("°", run.box, index)
                            continue
                        }
                        let isNought = !isRoundAndSmall && shape < 0.86 && ink.isNought(run.box)
                        if isNought, readsAsRing || inline.isEmpty {
                            while out.last?.character == " " { out.removeLast() }
                            write("^0", run.box, index)
                            continue
                        }
                        // Read as a ring when the ink is no ring at all: a 6 or a 2 set high,
                        // misread. Read on its own it may come out as the digit it is;
                        // if not, there's no saying what the power is.
                        if !isNought, readsAsRing {
                            if let alone = runText[number], alone.count == 1, alone.allSatisfy(\.isNumber), alone != "0" {
                                while out.last?.character == " " { out.removeLast() }
                                write("^\(alone)", run.box, index)
                            } else {
                                write([Self.unreadable], run.box, index)
                                spoiled.insert(index)
                            }
                            continue
                        }
                    }
                    // A degree sign or a dash (for a derivative) is raised too, and isn't a power.
                    if !inline.isEmpty, inline.allSatisfy({ $0 == "°" }) || (small && inline.allSatisfy({ "'′″".contains($0) })) {
                        write(inline, run.box, index)
                        continue
                    }
                    var power = runText[number]
                    if small, let read = power, read == "0" || read == "o", (0.75...1.3).contains(run.box.width / run.box.height) {
                        power = nil
                    }
                    // The minus sign of a negative power is known by its shape: read or not,
                    // it's written.
                    if run.startsWithMinus {
                        let digits = (power ?? String(inline.filter(Self.isPlain))).drop { "-−–—_~".contains($0) }
                        power = digits.isEmpty || !digits.allSatisfy(Self.isPlain) ? nil : "−" + digits
                    }
                    if power == nil, inline.count == run.glyphs.count, inline.allSatisfy(Self.isPlain) { power = String(inline) }
                    guard let power else {
                        // Small, unreadable, and read by Vision as some mark: a mark, not a
                        // power. Anything bigger, or anything Vision passed over, may be a
                        // power, and what it's on can't be trusted without it.
                        if small {
                            // A speck: part of a thin stroke broken off, or a small power.
                            // The word can't be vouched for, but there's no saying it's wrong.
                            write(inline, run.box, index)
                            if inline.isEmpty { unsure.insert(index) }
                        } else {
                            write([Self.unreadable], run.box, index)
                            spoiled.insert(index)
                        }
                        continue
                    }
                    // Fewer digits read than there are marks set high: one was lost, the 2 of
                    // 3¹², and what's left is another power.
                    if power.allSatisfy(\.isNumber), power.count < run.glyphs.count - (run.startsWithMinus ? 1 : 0) {
                        write([Self.unreadable], run.box, index)
                        spoiled.insert(index)
                        continue
                    }
                    // The top of a tall letter, the hook of an f, parted from it and read as
                    // the letter again: no power, just the letter.
                    if layout.parted.contains(run.glyphs.lowerBound), power.count == 1, let base = before?.character, base.isLetter,
                       power.lowercased() == String(base).lowercased() || "fſ".contains(base) {
                        continue
                    }
                    // One digit read from ink wider than it's tall: a minus sign has run into
                    // it, or a second digit. Whatever it is, it isn't that power.
                    if run.glyphs.count == 1, power.count == 1, power.allSatisfy(\.isNumber), run.box.width > run.box.height * 1.15 {
                        write([Self.unreadable], run.box, index)
                        spoiled.insert(index)
                        continue
                    }
                    while out.last?.character == " " { out.removeLast() }
                    write(power.count > 1 && !power.allSatisfy(\.isNumber) ? "^(\(power))" : "^\(power)", run.box, index)
                    // A full-size digit straight after a power, "x²14", is never written: a
                    // slash between them was read as a 1, or dropped. As text it would pass
                    // for part of the power.
                    if let next = glyphsOf[index].first(where: { $0 >= run.glyphs.upperBound && !absorbed.contains($0) }),
                       layout.kinds[next] == .normal, !layout.slashes.contains(next),
                       let place = matched[next], characters[place].isNumber { spoiled.insert(index) }
                }
            }
            if lastCharacter + 1 < word.range.upperBound { writeBack((lastCharacter + 1)..<word.range.upperBound, index) }
            // "(f" for the label (f): the bracket after the letter touches it, the two came
            // out as one piece of ink, and it was read as the letter alone. The bracket's
            // there, on the right of that ink, as wide as the one that opens the label.
            let label = word.range.map { characters[$0] }
            if label.count == 2, label[0] == "(", label[1].isLetter, glyphsOf[index].count == 2,
               let first = glyphsOf[index].first, let last = glyphsOf[index].last, layout.brackets[first] == "(", matched[last] == word.range.upperBound - 1 {
                let box = layout.glyphs[last], width = layout.glyphs[first].width
                if box.width >= width * 1.6, ink.bracket(CGRect(x: box.maxX - width, y: box.minY, width: width, height: box.height)) == ")" {
                    write(")", box, index)
                }
            }
        }
        if written < characters.count { write(original[written...], nil, -1) }
        // A recurring decimal isn't the number its digits spell: 0.15 with a dot on the 5 is
        // 0.1555…, not 0.15. It's written rec(A,B), A the part that doesn't recur (with its
        // point) and B the digits that do, which the parser turns into the exact fraction:
        // rec(0.1,5), and rec(0.,68) for 0.68 with a dot on each digit. The dots go on the
        // first and last digits of what recurs, or on its one digit, and what recurs runs to
        // the end of the number. Dots anywhere else leave no saying what it is.
        for word in recurring {
            guard let first = out.firstIndex(where: { $0.word == word }) else { continue }
            let box = out.filter { $0.word == word }.compactMap(\.box).reduce(CGRect.null) { $0.union($1) }
            let range = words[word].range
            let text = range.map { characters[$0] }
            var written = [Self.unreadable]
            if let from = text.firstIndex(where: \.isNumber), let to = text.lastIndex(where: \.isNumber) {
                let number = Array(text[from...to])
                let marks = (from...to).map { dotted.contains(range.lowerBound + $0) }
                if number.allSatisfy({ $0.isNumber || $0 == "." }), number.filter({ $0 == "." }).count == 1, let point = number.firstIndex(of: "."),
                   let firstDot = marks.firstIndex(of: true), let lastDot = marks.lastIndex(of: true), firstDot > point, lastDot == number.count - 1,
                   marks.filter({ $0 }).count <= 2 || marks[firstDot...].allSatisfy({ $0 }) {
                    written = Array(String(text[..<from]) + "rec(" + String(number[..<firstDot]) + "," + String(number[firstDot...]) + ")" + String(text[(to + 1)...]))
                }
            }
            if written == [Self.unreadable] { spoiled.insert(word) }
            out.removeAll { $0.word == word }
            out.insert(contentsOf: written.map { ($0, box.isNull ? nil : box, word) }, at: min(first, out.count))
        }

        // The words of what's written, each with its ink.
        var tokens: [Token] = []
        var index = 0
        while index < out.count {
            guard out[index].character != " " else { index += 1; continue }
            var end = index
            while end < out.count, out[end].character != " " { end += 1 }
            let part = out[index..<end]
            let from = Set(part.map(\.word))
            let isSuspect = from.contains { $0 >= 0 && (spoiled.contains($0) || suspect.contains($0)) }
            // A word of four letters or more hides nothing, however its letters run together.
            let isWord = part.count >= 4 && part.allSatisfy { $0.character.isLetter }
            let isChecked = !isSuspect && !from.contains(where: unsure.contains)
                && (isWord || from.allSatisfy { $0 >= 0 && (matches[$0] != nil || touching.contains($0)) })
            var box = part.compactMap(\.box).reduce(CGRect.null) { $0.union($1) }
            if box.isNull, let word = from.first, from.count == 1, touching.contains(word) {
                box = glyphsOf[word].reduce(CGRect.null) { $0.union(layout.glyphs[$1]) }
            }
            if box.isNull {
                box = from.filter { $0 >= 0 && hasPlaces }.map { words[$0].box }.reduce(CGRect.null) { $0.union($1) }
            }
            tokens.append(Token(range: index..<end, box: box.isNull ? pieceBox : box, isChecked: isChecked, isSuspect: isSuspect,
                                places: part.map(\.box), hasUnreadMark: from.contains(where: unsure.contains)))
            index = end
        }
        return Mended(text: String(out.map(\.character)), tokens: tokens)
    }

    // MARK: Reading the powers

    /// Each run of raised glyphs read on its own. They're drawn enlarged, one to a row, each
    /// after "N = " so that Vision has a line to read and something to judge its size by: a
    /// lone small character often isn't read at all.
    private func read(_ runs: [(box: CGRect, tall: CGFloat)]) -> [String?] {
        guard !runs.isEmpty else { return [] }
        let capHeight: CGFloat = 44
        let rowHeight: CGFloat = 150, margin: CGFloat = 70
        let font = CTFontCreateUIFontForLanguage(.system, capHeight / 0.705, nil)!
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true] as CFDictionary
        let lead = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "N = " as CFString, attributes)!)
        let leadWidth = CGFloat(CTLineGetTypographicBounds(lead, nil, nil, nil))

        // A power is drawn at about 70% of the size of the text it's on.
        var cuts: [(image: CGImage, size: CGSize)?] = []
        for run in runs {
            let scale = capHeight / max(run.tall * 0.7, 4)
            guard let image = ink.cutOut(run.box.insetBy(dx: -1, dy: -1)) else { cuts.append(nil); continue }
            cuts.append((image, CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)))
        }
        let widest = cuts.compactMap { $0?.size.width }.max() ?? 0
        let width = Int(margin * 2 + leadWidth + widest + 40), height = Int(margin + rowHeight * CGFloat(runs.count))
        guard widest > 0, width * height < 40_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return runs.map { _ in nil } }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        context.interpolationQuality = .high
        for (row, cut) in cuts.enumerated() {
            guard let cut else { continue }
            let baseline = CGFloat(height) - margin - rowHeight * CGFloat(row) - 90
            context.textPosition = CGPoint(x: margin, y: baseline)
            CTLineDraw(lead, context)
            context.draw(cut.image, in: CGRect(x: margin + leadWidth, y: baseline - 1, width: cut.size.width, height: cut.size.height))
        }
        guard let sheet = context.makeImage() else { return runs.map { _ in nil } }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: sheet, options: [:]).perform([request])
        var texts = [String?](repeating: nil, count: runs.count)
        for observation in request.results ?? [] {
            let fromTop = (1 - observation.boundingBox.midY) * CGFloat(height)
            let row = Int((fromTop - margin * 0.5) / rowHeight)
            guard texts.indices.contains(row), let line = observation.topCandidates(1).first?.string else { continue }
            texts[row] = Self.power(from: line)
        }
        return texts
    }

    /// The power in a line read back from the sheet: what follows "N =".
    private static func power(from line: String) -> String? {
        guard let equals = line.lastIndex(of: "=") else { return nil }
        var text = line[line.index(after: equals)...].replacingOccurrences(of: "×", with: "x")
            .filter { $0.isASCII && ($0.isNumber || $0.isLetter) }
        guard !text.isEmpty, text.count <= 6 else { return nil }
        // A lone letter has nothing beside it to show its size: x and X, o and 0 look alike.
        if text.count == 1, let letter = text.first {
            if "oO".contains(letter) { text = "0" }
            else if "zZ".contains(letter) { text = "2" }
            else if letter == "A" { text = "4" }
            else if "XCKSVWPUY".contains(letter) { text = letter.lowercased() }
        }
        return String(text)
    }
}
