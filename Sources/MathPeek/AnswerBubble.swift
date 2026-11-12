import AppKit
import SwiftUI

/// What the bubble by the pointer shows.
enum BubbleContent: Equatable {
    /// Shown only if reading takes a moment.
    case reading
    /// The question, the answer, a decimal or a note under it, and what ⌘C copies.
    case answer(sum: String, answer: String, detail: String?, copy: String, math: [MathLine] = [])
    case problem(sum: String, message: String)
    case message(symbol: String, title: String, detail: String)
    /// Several separate problems, each with its answer; ⌘C copies them all.
    case list(rows: [BubbleRow], copy: String)
}

struct BubbleRow: Hashable {
    var question: String
    var answer: String
    /// The one nearest the pointer.
    var isNearest: Bool
}

/// A small dark, semi-transparent bubble next to the pointer, which fades away by itself.
/// Clicking it copies the answer, and so does ⌘C while it shows. It never takes the focus from
/// the app you're in.
@MainActor
final class AnswerBubble {
    /// Told when there is (or stops being) an answer on screen to copy with ⌘C.
    var onCopyAvailable: ((Bool) -> Void)?
    /// Told of each answer shown, for the history.
    var onAnswer: ((BubbleContent) -> Void)?
    /// Told when the bubble starts to go, however it goes: its time is up, it's clicked, or
    /// it's put away.
    var onHide: (() -> Void)?
    /// The least time a bubble stays. Set while what was made out is drawn over the screen
    /// (Settings, Debug), so a short message doesn't take the drawing away with it too soon.
    var minimumSeconds: Double = 0

    private var content: BubbleContent = .reading
    private var isCopied = false
    private var panel: NSPanel?
    private var hosting: NSHostingView<BubbleView>?
    /// Measures exactly what's about to be shown, at a set maximum width, so a long sum is cut
    /// short in the middle.
    private let measurer = NSHostingController(rootView: BubbleView(content: .reading, isCopied: false))
    private var anchor = CGPoint.zero
    private var clickAction: (() -> Void)?
    private var isHovered = false
    private var hideTask: Task<Void, Never>?
    private var readingTask: Task<Void, Never>?
    /// Changes with every show, so a fade-out that finishes late doesn't hide a newer bubble.
    private var generation = 0

    /// Makes the window now, so that it exists for ScreenCaptureKit to leave out of captures.
    func preload() {
        _ = panel ?? makePanel()
    }

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
        onAnswer?(content)
        present(content, at: point, for: max(seconds, minimumSeconds), action: action)
    }

    /// Copies the answer showing, if there is one, and says so.
    func copy() {
        guard panel?.isVisible == true else { return }
        let copy: String
        switch content {
        case .answer(_, _, _, let text, _): copy = text
        case .list(_, let text): copy = text
        default: return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copy, forType: .string)
        isCopied = true
        refresh()
        scheduleHide(after: 0.9)
    }

    func hide() {
        readingTask?.cancel()
        readingTask = nil
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        onCopyAvailable?(false)
        onHide?()
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
        self.content = content
        isCopied = false
        anchor = point
        clickAction = action
        refresh()
        place(panel, showing: BubbleView(content: content, isCopied: false))
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        switch content {
        case .answer, .list: onCopyAvailable?(true)
        default: onCopyAvailable?(false)
        }
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
    private func place(_ panel: NSPanel, showing view: BubbleView) {
        measurer.rootView = view
        let fitting = measurer.sizeThatFits(in: CGSize(width: 460, height: 2000))
        let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
        let gap: CGFloat = 14
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        // A README clip's bubble keeps to its stage, which is on no screen.
        let visible = DemoStage.isFilming ? DemoStage.frame
            : screen?.visibleFrame ?? CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000))
        var origin = CGPoint(x: anchor.x + gap, y: anchor.y - gap - size.height)
        if origin.x + size.width > visible.maxX { origin.x = anchor.x - gap - size.width }
        if origin.y < visible.minY { origin.y = anchor.y + gap }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }

    private func makePanel() -> NSPanel {
        // Not deferred: the window exists from the start, so captures can leave it out.
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let hosting = PassThroughHostingView(rootView: BubbleView(content: content, isCopied: false))
        hosting.sizingOptions = []
        let surface = BubbleSurface(frame: panel.contentLayoutRect, content: hosting)
        surface.onClick = { [weak self] in self?.clicked() }
        surface.onHover = { [weak self] inside in self?.hovered(inside) }
        panel.contentView = surface
        if DemoStage.isFilming { DemoStage.withoutGlass(panel) }

        self.panel = panel
        self.hosting = hosting
        return panel
    }

    /// Opens the working, or whatever the message offers.
    private func clicked() {
        if let clickAction {
            clickAction()
            hide()
        } else if case .answer = content {
            copy()
        } else {
            hide()
        }
    }

    /// Where the bubble is while it shows, for a README clip's pointer to find it.
    var demoFrame: CGRect? {
        guard let panel, panel.isVisible, panel.alphaValue > 0 else { return nil }
        return panel.frame
    }

    /// A README clip's pointer is drawn by the recording: this says where it is, as the real
    /// pointer coming onto the bubble and leaving it would.
    func demoPointer(_ point: CGPoint) {
        let inside = demoFrame?.contains(point) ?? false
        if inside != isHovered { hovered(inside) }
    }

    /// Redraws the bubble for what it's showing now.
    private func refresh() {
        hosting?.rootView = BubbleView(content: content, isCopied: isCopied, opens: isHovered && clickAction != nil)
    }

    /// The bubble stays while the pointer is on it, and shows that a click opens the working.
    private func hovered(_ inside: Bool) {
        isHovered = inside
        refresh()
        if inside {
            hideTask?.cancel()
        } else if panel?.isVisible == true {
            scheduleHide(after: isCopied ? 0.5 : 1.5)
        }
    }
}

/// The bubble's background: dark and semi-transparent, like the working window. It takes the
/// clicks for the whole bubble and notices the pointer.
private final class BubbleSurface: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    init(frame: CGRect, content: NSView) {
        super.init(frame: frame)
        let material = NSVisualEffectView(frame: bounds)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.roundedMask(radius: BubbleView.cornerRadius)
        material.autoresizingMask = [.width, .height]
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        addSubview(material)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    /// Clicks anywhere on the bubble come here, not to the views inside it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

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
    let content: BubbleContent
    let isCopied: Bool
    /// Whether to show that a click opens the working: while the pointer is on it.
    var opens = false

    static let cornerRadius: CGFloat = 12
    private static let blue = Color(red: 0.04, green: 0.62, blue: 1.0)
    private static let green = Color(red: 0.37, green: 0.85, blue: 0.57)
    private static let secondary = Color.white.opacity(0.6)
    private static let tint = Color(red: 0.07, green: 0.075, blue: 0.105)

    var body: some View {
        body(for: content)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .foregroundStyle(Color.white.opacity(0.95))
            // Rounded like the material's mask, so the tint stays inside the corners.
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(Self.tint.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(Color.white.opacity(0.12)))
            .overlay(alignment: .topTrailing) {
                if opens && !isCopied {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Self.secondary)
                        .padding(7)
                }
            }
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func body(for content: BubbleContent) -> some View {
        switch content {
        case .reading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading").font(.system(size: 13, weight: .medium)).foregroundStyle(Self.secondary)
            }
        case .answer(let sum, let answer, let detail, _, let math):
            VStack(alignment: .leading, spacing: 8) {
                caption(sum)
                if math.count == 1 {
                    MathLineView(line: math[0], size: 28, design: Z.maths, weight: .semibold)
                } else if !math.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(math.enumerated()), id: \.offset) { _, line in
                            chip(highlighted: true) { MathLineView(line: line, size: 18, design: Z.maths, weight: .medium) }
                        }
                    }
                } else {
                    MathText(text: answer, size: 22, weight: .semibold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Self.secondary)
                        .lineLimit(2)
                }
            }
        case .list(let rows, _):
            VStack(alignment: .leading, spacing: 6) {
                caption("\(rows.count) problems")
                    .padding(.bottom, 2)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    chip(highlighted: row.isNearest) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            MathText(text: row.question, size: 12.5)
                                .foregroundStyle(Self.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 190, alignment: .leading)
                            MathText(text: row.answer, size: 13.5, weight: .semibold)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        case .problem(let sum, let message):
            VStack(alignment: .leading, spacing: 6) {
                caption(sum)
                Text(message).font(.system(size: 16, weight: .semibold))
            }
        case .message(_, let title, let detail):
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Self.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 290, alignment: .leading)
        }
    }

    /// The line over the answer: the question, or "Copied" once it has been.
    private func caption(_ text: String) -> some View {
        MathText(text: isCopied ? "Copied" : text, size: 12.5, weight: isCopied ? .semibold : .regular)
            .foregroundStyle(isCopied ? Self.green : Self.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// A pill, blue when it's the one to look at.
    private func chip<Content: View>(highlighted: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(highlighted ? Self.blue.opacity(0.18) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
