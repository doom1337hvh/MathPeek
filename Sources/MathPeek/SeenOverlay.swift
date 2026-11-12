import AppKit

/// Draws what MathPeek made out over the part of the screen it read (Settings, Debug). Its
/// windows let clicks through, so whatever's under them works as usual, and MathPeek leaves
/// its own windows out of what it reads.
@MainActor
final class SeenOverlay {
    private var windows: [NSWindow] = []
    private var timer: Timer?

    var isShowing: Bool { !windows.isEmpty }

    /// `area` is the part of the screen that was read, in global coordinates. `outlined`
    /// draws its edge too, when nothing else on screen shows where it was.
    func show(_ seen: Seen, over area: CGRect, outlined: Bool) {
        // Round a small area there's room for the notes: above for why a sum was left out,
        // below for how the line under the pointer was read.
        let above: CGFloat = outlined ? 24 : 0, below: CGFloat = outlined ? 110 : 0
        let frame = CGRect(x: area.minX, y: area.minY - below, width: area.width, height: area.height + above + below)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Over the dimmed screen an area is chosen on.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let view = SeenView(frame: CGRect(origin: .zero, size: frame.size))
        view.seen = seen
        view.isOutlined = outlined
        view.area = CGRect(x: 0, y: above, width: area.width, height: area.height)
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)
        guard timer == nil else { return }
        // The windows don't get the mouse, so where the pointer is has to be asked.
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func follow() {
        let pointer = NSEvent.mouseLocation
        for window in windows {
            let inside = window.frame.contains(pointer)
            (window.contentView as? SeenView)?.point(at: inside ? CGPoint(x: pointer.x - window.frame.minX, y: window.frame.maxY - pointer.y) : nil)
        }
    }
}

/// What was made out, drawn where it is. Works from the top-left, as what was seen does.
final class SeenView: NSView {
    var seen = Seen() { didSet { needsDisplay = true } }
    var isOutlined = false
    /// The part of the view that the area read takes up: all of it, unless there's room
    /// round it for notes.
    var area: CGRect?
    /// Where things can be drawn, measured from the top-left of the area read.
    private var room: CGRect {
        guard let area else { return bounds }
        return bounds.offsetBy(dx: -area.minX, dy: -area.minY)
    }
    /// The line of text the pointer is on.
    private var hovered: Int?

    private static let character = NSColor.systemGray
    private static let power = NSColor.systemOrange
    private static let slash = NSColor.systemGreen
    private static let bar = NSColor.systemPurple
    private static let leftOut = NSColor.systemYellow
    private static let shown = NSColor(srgbRed: 0.04, green: 0.62, blue: 1.0, alpha: 1)
    private static let drawn = NSColor.systemTeal

    override var isFlipped: Bool { true }

    func point(at location: CGPoint?) {
        let origin = area?.origin ?? .zero
        let over = location.flatMap { point in
            seen.lines.firstIndex { $0.box.insetBy(dx: -3, dy: -3).contains(CGPoint(x: point.x - origin.x, y: point.y - origin.y)) }
        }
        guard over != hovered else { return }
        hovered = over
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Everything is measured from the top-left of the area that was read.
        let read = area ?? bounds
        let move = NSAffineTransform()
        move.translateX(by: read.minX, yBy: read.minY)
        move.concat()
        if isOutlined {
            let edge = NSBezierPath(rect: CGRect(origin: .zero, size: read.size).insetBy(dx: 1, dy: 1))
            edge.lineWidth = 1
            edge.setLineDash([5, 4], count: 2, phase: 0)
            Self.character.setStroke()
            edge.stroke()
        }
        // Each line of text that was read.
        let lines = NSBezierPath()
        for line in seen.lines { lines.appendRect(line.box.insetBy(dx: -2, dy: -2)) }
        lines.lineWidth = 0.5
        Self.character.withAlphaComponent(0.55).setStroke()
        lines.stroke()

        // Each patch of ink in them, by what it's taken to be.
        for (kind, colour) in [(LineMender.Mark.character, Self.character), (.power, Self.power), (.slash, Self.slash), (.bar, Self.bar)] {
            let path = NSBezierPath()
            for mark in seen.marks where mark.kind == kind { path.appendRect(mark.box.insetBy(dx: -0.5, dy: -0.5)) }
            guard !path.isEmpty else { continue }
            if kind != .character {
                colour.withAlphaComponent(0.3).setFill()
                path.fill()
            }
            path.lineWidth = kind == .character ? 0.5 : 1
            colour.withAlphaComponent(kind == .character ? 0.8 : 1).setStroke()
            path.stroke()
        }

        // The circles and lines of diagrams, their corners and what's written on them.
        Self.drawn.setStroke()
        for circle in seen.circles {
            let path = NSBezierPath(ovalIn: CGRect(x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
                                                   width: circle.radius * 2, height: circle.radius * 2))
            path.lineWidth = 1.5
            path.stroke()
        }
        let strokes = NSBezierPath()
        for stroke in seen.strokes {
            strokes.move(to: stroke.from)
            strokes.line(to: stroke.to)
        }
        strokes.lineWidth = 1.5
        strokes.stroke()
        for point in seen.points {
            Self.drawn.setFill()
            NSBezierPath(ovalIn: CGRect(x: point.at.x - 3, y: point.at.y - 3, width: 6, height: 6)).fill()
        }
        for label in seen.labels {
            let path = NSBezierPath(rect: label.box)
            path.lineWidth = 1
            Self.drawn.setStroke()
            path.stroke()
            tag(label.text, at: CGPoint(x: label.box.minX, y: label.box.maxY + 2), colour: Self.drawn)
        }

        // Each sum found: outlined if it's highlighted, and if not, why not.
        for sum in seen.sums {
            let box = sum.box.insetBy(dx: -5, dy: -4)
            let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
            path.lineWidth = 1.5
            if let reason = sum.leftOut {
                path.setLineDash([4, 3], count: 2, phase: 0)
                Self.leftOut.setStroke()
                path.stroke()
                tag(reason, at: CGPoint(x: box.minX, y: box.minY - 17), colour: Self.leftOut)
            } else if isOutlined {
                Self.shown.setStroke()
                path.stroke()
            }
        }

        if let hovered, seen.lines.indices.contains(hovered) { describe(seen.lines[hovered]) }
        if read.height >= 400 { drawKey() }
    }

    /// A few words on a dark ground, kept inside the view.
    private func tag(_ text: String, at point: CGPoint, colour: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5, weight: .medium), .foregroundColor: colour]
        let size = (text as NSString).size(withAttributes: attributes)
        let room = room
        let box = CGRect(x: min(max(point.x, room.minX + 2), max(room.maxX - size.width - 10, room.minX + 2)),
                         y: min(max(point.y, room.minY + 2), room.maxY - size.height - 6), width: size.width + 8, height: size.height + 3)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 4, y: box.minY + 1), withAttributes: attributes)
    }

    /// How the line under the pointer was read, and what came of the sums in it.
    private func describe(_ line: Seen.Line) {
        var notes: [String] = []
        if let tall = line.tall { notes.append("capitals \(Int(tall.rounded())) px tall") } else { notes.append("ink too faint to check") }
        for sum in seen.sums where !sum.box.intersection(line.box.insetBy(dx: -2, dy: -2)).isNull {
            let answer = sum.answer.map { "  →  \($0)" } ?? ""
            notes.append(sum.leftOut.map { "\(sum.text)\(answer), left out: \($0)" } ?? "\(sum.text)\(answer), highlighted")
        }
        let reading = NSAttributedString(string: line.text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.white,
        ])
        let detail = NSAttributedString(string: notes.joined(separator: "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ])
        let room = room
        let width = min(max(reading.size().width, detail.size().width), room.width - 40)
        let readingHeight = reading.boundingRect(with: CGSize(width: width, height: 400), options: [.usesLineFragmentOrigin]).height
        let detailHeight = detail.boundingRect(with: CGSize(width: width, height: 400), options: [.usesLineFragmentOrigin]).height
        let height = readingHeight + detailHeight + 16
        // Under the line, or over it near the bottom of the screen.
        var top = line.box.maxY + 8
        if top + height > room.maxY - 8 { top = line.box.minY - 8 - height }
        let box = CGRect(x: min(max(line.box.minX, room.minX + 8), room.maxX - width - 28), y: max(top, room.minY + 8), width: width + 20, height: height)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        reading.draw(with: CGRect(x: box.minX + 10, y: box.minY + 6, width: width, height: readingHeight), options: [.usesLineFragmentOrigin])
        detail.draw(with: CGRect(x: box.minX + 10, y: box.minY + 8 + readingHeight, width: width, height: detailHeight), options: [.usesLineFragmentOrigin])
    }

    /// What each colour stands for.
    private func drawKey() {
        let items: [(String, NSColor)] = [("character", Self.character), ("power", Self.power), ("slash", Self.slash), ("bar", Self.bar),
                                          ("sum left out", Self.leftOut), ("diagram", Self.drawn)]
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white]
        let widths = items.map { ($0.0 as NSString).size(withAttributes: attributes).width }
        let total = widths.reduce(0, +) + CGFloat(items.count) * 26 + 8
        let box = CGRect(x: 16, y: room.maxY - 40, width: total, height: 24)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        var x = box.minX + 12
        for (item, width) in zip(items, widths) {
            let swatch = NSBezierPath(rect: CGRect(x: x, y: box.midY - 4, width: 8, height: 8))
            item.1.withAlphaComponent(0.35).setFill()
            swatch.fill()
            swatch.lineWidth = 1
            item.1.setStroke()
            swatch.stroke()
            (item.0 as NSString).draw(at: CGPoint(x: x + 12, y: box.minY + 5), withAttributes: attributes)
            x += width + 26
        }
    }
}
