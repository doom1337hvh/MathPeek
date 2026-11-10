import AppKit
import Observation
import SwiftUI

/// What the bubble by the pointer shows.
enum BubbleContent: Equatable {
    /// Shown only if reading takes a moment.
    case reading
    /// `answer` as shown, `copy` as copied: no grouping, a plain minus.
    case answer(sum: String, answer: String, copy: String)
    case problem(sum: String, message: String)
    case message(symbol: String, title: String, detail: String)
}

@Observable @MainActor
final class BubbleModel {
    var content: BubbleContent = .reading
    var isCopied = false
}

/// A small borderless bubble next to the pointer that fades away by itself. Clicking it
/// copies the answer, and so does ⌘C while it shows. It never takes the focus from the app
/// you're in.
@MainActor
final class AnswerBubble {
    /// Told when there is (or stops being) an answer on screen to copy with ⌘C.
    var onCopyAvailable: ((Bool) -> Void)?

    private let model = BubbleModel()
    private var panel: NSPanel?
    private var surface: BubbleSurface?
    private var hosting: NSHostingView<BubbleView>?
    /// Measures the content at a set maximum width, so a long sum is cut short in the middle.
    private lazy var measurer = NSHostingController(rootView: BubbleView(model: model))
    private var anchor = CGPoint.zero
    private var seconds: Double = 5
    private var clickAction: (() -> Void)?
    private var isHovered = false
    private var hideTask: Task<Void, Never>?
    private var readingTask: Task<Void, Never>?
    /// Changes with every show, so a fade-out that finishes late doesn't hide a newer bubble.
    private var generation = 0

    /// Called as reading starts: shows "Reading…" by `point` if the answer takes more than a
    /// moment.
    func prepare(at point: CGPoint) {
        readingTask?.cancel()
        readingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.present(.reading, at: point, for: 30, action: nil)
        }
    }

    func show(_ content: BubbleContent, at point: CGPoint, for seconds: Double, action: (() -> Void)? = nil) {
        readingTask?.cancel()
        readingTask = nil
        present(content, at: point, for: seconds, action: action)
    }

    /// Copies the answer showing, if there is one, and says so.
    func copy() {
        guard panel?.isVisible == true, case .answer(_, _, let copy) = model.content else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copy, forType: .string)
        model.isCopied = true
        scheduleHide(after: 0.9)
    }

    func hide() {
        readingTask?.cancel()
        readingTask = nil
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        onCopyAvailable?(false)
        let shown = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func present(_ content: BubbleContent, at point: CGPoint, for seconds: Double, action: (() -> Void)?) {
        generation += 1
        let panel = panel ?? makePanel()
        model.content = content
        model.isCopied = false
        anchor = point
        self.seconds = seconds
        clickAction = action
        place(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        if case .answer = content { onCopyAvailable?(true) } else { onCopyAvailable?(false) }
        if !isHovered { scheduleHide(after: seconds) }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Below and to the right of the pointer, or wherever it fits on that screen.
    private func place(_ panel: NSPanel) {
        guard let hosting, let surface else { return }
        let fitting = measurer.sizeThatFits(in: CGSize(width: 460, height: 2000))
        let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
        let gap: CGFloat = 14
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000))
        var origin = CGPoint(x: anchor.x + gap, y: anchor.y - gap - size.height)
        if origin.x + size.width > visible.maxX { origin.x = anchor.x - gap - size.width }
        if origin.y < visible.minY { origin.y = anchor.y + gap }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        surface.frame = CGRect(origin: .zero, size: size)
        hosting.frame = surface.bounds
        panel.invalidateShadow()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let surface = BubbleSurface()
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        surface.maskImage = Self.roundedMask(radius: 12)
        surface.onClick = { [weak self] in self?.clicked() }
        surface.onHover = { [weak self] inside in self?.hovered(inside) }
        let hosting = PassThroughHostingView(rootView: BubbleView(model: model))
        hosting.sizingOptions = []
        surface.addSubview(hosting)
        panel.contentView = surface

        self.panel = panel
        self.surface = surface
        self.hosting = hosting
        return panel
    }

    private func clicked() {
        if case .answer = model.content {
            copy()
        } else {
            clickAction?()
            hide()
        }
    }

    /// The bubble stays while the pointer is on it.
    private func hovered(_ inside: Bool) {
        isHovered = inside
        if inside {
            hideTask?.cancel()
        } else if panel?.isVisible == true {
            scheduleHide(after: model.isCopied ? 0.5 : 1.5)
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The bubble's frosted background, which takes the clicks and notices the pointer.
private final class BubbleSurface: NSVisualEffectView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Draws the SwiftUI content but leaves clicks to the surface behind it.
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BubbleView: View {
    let model: BubbleModel

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        switch model.content {
        case .reading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading…").foregroundStyle(.secondary)
            }
        case .answer(let sum, let answer, _):
            VStack(alignment: .leading, spacing: 1) {
                sumLine(sum)
                Text(answer)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(model.isCopied ? "Copied" : "Click or ⌘C to copy")
                    .font(.system(size: 10))
                    .foregroundStyle(model.isCopied ? .secondary : .tertiary)
            }
        case .problem(let sum, let message):
            VStack(alignment: .leading, spacing: 3) {
                sumLine(sum)
                Text(message).font(.system(size: 17, weight: .semibold, design: .rounded))
            }
        case .message(let symbol, let title, let detail):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 300, alignment: .leading)
        }
    }

    private func sumLine(_ sum: String) -> some View {
        Text(sum + " =")
            .font(.system(size: 13, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
