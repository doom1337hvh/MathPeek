import AppKit

/// What was chosen while the screen was dimmed.
enum Picked {
    /// An area dragged out, in global coordinates.
    case area(CGRect)
    /// A click on nothing in particular: read around that point.
    case point(CGPoint)
    /// A click on a highlighted problem, by the number it was given.
    case spot(Int)
}

/// Dims every screen and lets you drag out the area to read, as for a screenshot. Problems
/// MathPeek has found on screen are highlighted, and clicking one picks it. A click elsewhere
/// reads around that point; Escape or a right-click cancels. The overlay is a panel that
/// doesn't activate MathPeek, so the app you were in keeps the focus.
@MainActor
final class AreaPicker {
    private var windows: [PickerPanel] = []
    private var completion: ((Picked?) -> Void)?

    var isPicking: Bool { !windows.isEmpty }

    /// Calls `completion` with what was picked, or nil if it was cancelled.
    func pick(_ completion: @escaping (Picked?) -> Void) {
        cancel()
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = PickerPanel(screen: screen) { [weak self] picked in self?.finish(picked) }
            windows.append(panel)
            panel.orderFrontRegardless()
        }
        let pointer = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(pointer) } ?? windows.first)?.makeKey()
        // MathPeek isn't the active app, and macOS only lets the active app change the cursor.
        BackgroundCursor.allow(true)
        NSCursor.crosshair.set()
    }

    /// Highlights problems found on screen: where each is, in global coordinates, and its number.
    func highlight(_ spots: [(id: Int, rect: CGRect)]) {
        for panel in windows {
            let here = spots.filter { panel.frame.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            panel.add(here.map { ($0.id, $0.rect.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)) })
        }
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ picked: Picked?) {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.arrow.set()
        BackgroundCursor.allow(false)
        let done = completion
        completion = nil
        done?(picked)
    }
}

/// Lets MathPeek change the cursor while another app is the active one. macOS has no public
/// way to: an app in the background is ignored when it sets the cursor, and the picker's panel
/// deliberately leaves the app you're in active. The window server has a setting for it, which
/// is looked up when it's needed, so if it's ever gone the cursor just stays an arrow.
enum BackgroundCursor {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func allow(_ on: Bool) {
        let anywhere = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(anywhere, "CGSMainConnectionID") ?? dlsym(anywhere, "_CGSDefaultConnection"),
              let setProperty = dlsym(anywhere, "CGSSetConnectionProperty") else { return }
        let id = unsafeBitCast(connection, to: Connection.self)()
        let value: CFTypeRef = on ? kCFBooleanTrue : kCFBooleanFalse
        _ = unsafeBitCast(setProperty, to: SetProperty.self)(id, id, "SetsCursorInBackground" as CFString, value)
    }
}

private final class PickerPanel: NSPanel {
    private let picker: PickerView

    init(screen: NSScreen, onFinish: @escaping (Picked?) -> Void) {
        picker = PickerView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        let origin = screen.frame.origin
        picker.onFinish = { picked in
            // The view works in its own coordinates; the rest of the app in global ones.
            switch picked {
            case .area(let rect): onFinish(.area(rect.offsetBy(dx: origin.x, dy: origin.y)))
            case .point(let point): onFinish(.point(CGPoint(x: point.x + origin.x, y: point.y + origin.y)))
            case .spot, nil: onFinish(picked)
            }
        }
        contentView = picker
    }

    override var canBecomeKey: Bool { true }

    func add(_ spots: [(id: Int, rect: CGRect)]) {
        picker.add(spots)
    }
}

private final class PickerView: NSView {
    /// What was picked, in this view's coordinates, or nil to cancel.
    var onFinish: ((Picked?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?
    /// Problems found on this screen, and the one under the pointer.
    private var spots: [(id: Int, rect: CGRect)] = []
    private var hovered: Int?

    private static let accent = NSColor(srgbRed: 0.04, green: 0.62, blue: 1.0, alpha: 1)

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    func add(_ new: [(id: Int, rect: CGRect)]) {
        guard !new.isEmpty else { return }
        // A little room round the text, so the outline doesn't touch it.
        spots += new.map { ($0.id, $0.rect.insetBy(dx: -5, dy: -4)) }
        if let window { point(at: convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        needsDisplay = true
    }

    // MARK: The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
                                       owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// The pointer is at `location`: light the problem it's over, and show a hand there.
    private func point(at location: CGPoint) {
        let over = start == nil ? spots.last(where: { $0.rect.contains(location) })?.id : nil
        if over != hovered {
            hovered = over
            needsDisplay = true
        }
        (hovered == nil ? NSCursor.crosshair : NSCursor.pointingHand).set()
    }

    override func mouseMoved(with event: NSEvent) {
        point(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        point(at: convert(event.locationInWindow, from: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        point(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        if let selection, selection.width >= 6 || selection.height >= 6, hovered != nil { hovered = nil }
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let area = selection, let point = current else { return }
        // A click, not a drag: the problem under it, or else around that point.
        if area.width < 6 && area.height < 6 {
            if let spot = spots.last(where: { $0.rect.contains(point) }) {
                onFinish?(.spot(spot.id))
            } else {
                onFinish?(.point(point))
            }
        } else {
            onFinish?(.area(area))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onFinish?(nil)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        // Each problem shows through the dimming, with an outline: brighter under the pointer.
        for spot in spots {
            let path = NSBezierPath(roundedRect: spot.rect, xRadius: 5, yRadius: 5)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            let lit = spot.id == hovered && selection.map { $0.width < 6 && $0.height < 6 } ?? true
            Self.accent.withAlphaComponent(lit ? 0.2 : 0.07).setFill()
            path.fill()
            let outline = NSBezierPath(roundedRect: spot.rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.5, yRadius: 4.5)
            outline.lineWidth = lit ? 2 : 1.5
            Self.accent.withAlphaComponent(lit ? 1 : 0.75).setStroke()
            outline.stroke()
        }
        if let selection, selection.width >= 6 || selection.height >= 6 {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            selection.fill(using: .sourceOver)
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            NSColor.white.setStroke()
            outline.stroke()
        } else if start == nil {
            drawHint()
        }
    }

    private func drawHint() {
        let text = "Drag over the maths to read it  ·  Click to read around a point  ·  Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - 120,
                         width: size.width + 28, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 6), withAttributes: attributes)
    }
}

/// While the area's size changes in Settings, an outline of it follows the pointer, so you
/// can see how much MathPeek will read.
@MainActor
final class AreaOutline {
    private var window: NSWindow?
    private var timer: Timer?
    private var hideAt = Date.distantPast
    private var size = CGSize.zero

    func flash(width: Double, height: Double) {
        size = CGSize(width: width, height: height)
        hideAt = Date().addingTimeInterval(1.2)
        let window = window ?? makeWindow()
        follow()
        window.alphaValue = 1
        window.orderFrontRegardless()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard Date() < hideAt else {
            timer?.invalidate()
            timer = nil
            window?.orderOut(nil)
            return
        }
        follow()
    }

    private func follow() {
        let pointer = NSEvent.mouseLocation
        let frame = CGRect(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2,
                           width: size.width, height: size.height)
        if window?.frame != frame { window?.setFrame(frame.integral, display: true) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = OutlineView()
        self.window = window
        return window
    }
}

private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.lineWidth = 3
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.stroke()
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
