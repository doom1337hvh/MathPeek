import AppKit

/// Dims every screen and lets you drag out the area to read, as for a screenshot. A click
/// without a drag reads around that point; Escape or a right-click cancels. The overlay is a
/// panel that doesn't activate MathPeek, so the app you were in keeps the focus.
@MainActor
final class AreaPicker {
    private var windows: [PickerPanel] = []
    private var completion: ((CGRect?) -> Void)?

    var isPicking: Bool { !windows.isEmpty }

    /// Calls `completion` with the area in global coordinates (zero-sized for a click), or nil
    /// if it was cancelled.
    func pick(_ completion: @escaping (CGRect?) -> Void) {
        cancel()
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = PickerPanel(screen: screen) { [weak self] rect in self?.finish(rect) }
            windows.append(panel)
            panel.orderFrontRegardless()
        }
        let pointer = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(pointer) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ rect: CGRect?) {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.pop()
        let done = completion
        completion = nil
        done?(rect)
    }
}

private final class PickerPanel: NSPanel {
    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
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
        let view = PickerView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] local in
            guard let self else { return }
            onFinish(local.map { $0.offsetBy(dx: self.frame.minX, dy: self.frame.minY) })
        }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    /// The area in this view's coordinates, or nil to cancel.
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard var area = selection else { return }
        // A click, not a drag: read around that point.
        if area.width < 6 && area.height < 6 {
            area = CGRect(origin: current ?? area.origin, size: .zero)
        }
        onFinish?(area)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onFinish?(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            selection.fill(using: .sourceOver)
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            NSColor.white.setStroke()
            outline.stroke()
        } else {
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
