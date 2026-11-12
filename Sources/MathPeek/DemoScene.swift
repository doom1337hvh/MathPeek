import AppKit
import AppShell
import SwiftUI

/// The README's clips, recorded by scripts/record-clips.sh (AppShell's recorder). Opened with
/// `-demo <scene>` off screen (`Demo.isOffscreen`), MathPeek acts the scene out with its real
/// bubble and working window, on problems written here. Nothing is read from the screen, so it
/// needs no Screen Recording; the shortcut isn't registered, and no history or settings are
/// saved. Its windows are on AppShell's stage off every screen, where the recorder finds them,
/// and it never becomes the active app: a copy of MathPeek that's already running carries on
/// undisturbed.
///
/// The recorder draws the page MathPeek is pointed at (a picture from scripts/clip-pages.swift)
/// and the pointer, along the path in scripts/clips.jsonc. That path is this script's own:
/// clip-pages.swift rehearses each scene (`-demoRehearse <file>`) and writes down where the
/// pointer went. Every step here happens at a set time from the scene's start, so the
/// recording and the rehearsal run alike.
enum DemoScene: String {
    /// The README's main clip: a quadratic, its answer by the pointer, the roadmap, a step
    /// opened and written out.
    case tour
    /// Answers by the pointer: a sum, a written answer that's wrong, a percentage, fractions.
    case bubble
    /// Several problems read at once: the bubble lists them, and each has a tab.
    case several
    /// A cubic's roadmap to its three roots, then a quadratic another way.
    case roadmap
    /// Try It Yourself: lines checked as they're written.
    case tryIt = "try"
    /// Working written by hand on the roadmap: the pen, the eraser, the highlighter, a typed note.
    case draw
    /// Poking at the working: a term picked and followed, an answer checked and rounded,
    /// the roadmap zoomed and moved.
    case explore
    /// A circle-theorem diagram read from a picture and worked out.
    case diagram
    /// Changing a number in the problem, and Another Like This.
    case change
    /// The history: searching it, and opening an answer again.
    case history

    /// The scene being filmed, if one is. (`-demo` on screen shows a still set-up to look at,
    /// see `AppDelegate.showDemoScene`; AppShell plays the Settings clip itself.)
    static let current: DemoScene? = DemoStage.isFilming
        ? UserDefaults.standard.string(forKey: "demo").flatMap(DemoScene.init(rawValue:)) : nil
}

/// Where a clip is acted out: the area the recorder films, on AppShell's stage off every
/// screen. This keeps where the pointer is, since the real one is somewhere else, being used.
@MainActor
enum DemoStage {
    /// Whether a clip is being filmed off screen (as `Demo.isOffscreen`, for anywhere).
    nonisolated static let isFilming = UserDefaults.standard.string(forKey: "demo") != nil
        && UserDefaults.standard.bool(forKey: "demoOffscreen")

    /// What the recorder takes around the window it films, in points.
    static let margin: CGFloat = 40
    /// The area filmed, in AppKit's coordinates, once `open()` has put it on the stage.
    private(set) static var frame = CGRect(x: -12_040, y: -8_644, width: 964, height: 684)

    /// Where the page's problems are, from the area's top left (`-demoSpots "x,y;x,y"`).
    static let spots: [CGPoint] = (UserDefaults.standard.string(forKey: "demoSpots") ?? "").split(separator: ";").compactMap {
        let pair = $0.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return pair.count == 2 ? CGPoint(x: pair[0], y: pair[1]) : nil
    }

    /// The picture of the page the recorder draws behind, for the one thing that's read from
    /// a picture rather than handed over as text: a diagram (`-demoPage`, a path in the
    /// repository, which the built app is two folders inside).
    static let page: CGImage? = UserDefaults.standard.string(forKey: "demoPage").flatMap { path in
        let file = path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(path)
        return NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// The pointer, from the area's top left.
    static var pointer = CGPoint(x: 694, y: 547)

    /// Where everything that can be clicked is in the working window, from its top left.
    static var places: [String: CGRect] = [:]

    /// The pointer in AppKit's coordinates.
    static var global: CGPoint { CGPoint(x: frame.minX + pointer.x, y: frame.maxY - pointer.y) }

    private static var desk: NSWindow?
    private static var keys: NSWindow?

    /// Sets the stage. The recorder films the biggest window it finds and the margin round it,
    /// and several scenes start with no window at all, pointing at the page: so an empty,
    /// see-through window marks the area out, a little bigger than the working window.
    static func open() {
        guard desk == nil else { return }
        let desk = clear(CGSize(width: 884, height: 604))
        Demo.stage(desk)
        frame = desk.frame.insetBy(dx: -margin, dy: -margin)
        self.desk = desk

        // The shortcut's keys, shown at the bottom of the area while it's pressed: the keys
        // themselves can't be seen in a clip.
        let caps = KeyCaps(["⌃", "⌥", "="])
        let keys = clear(caps.frame.size)
        keys.level = .floating
        keys.contentView = caps
        Demo.stage(keys, offset: CGPoint(x: (desk.frame.width - caps.frame.width) / 2, y: desk.frame.height + margin - 26 - caps.frame.height))
        keys.orderOut(nil)
        self.keys = keys
        keepOnEveryDesktop()
        // Once the recorder has measured the area, in its first moments, the empty window has
        // done its job: left there, it would be one more big picture to take for every frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { desk.orderOut(nil) }
    }

    /// Keeps the app's windows where they are when the person at the Mac changes desktop.
    /// Windows off the screen slide away with the desktop they were opened on like any others,
    /// and are gone from the recording once it's another's turn; these stay put, on all of
    /// them, a full-screen app's included.
    static func keepOnEveryDesktop() {
        for window in NSApp.windows { window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] }
    }

    private static func clear(_ size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        return window
    }

    static func showKeys(_ shown: Bool) {
        if shown { keys?.orderFrontRegardless() } else { keys?.orderOut(nil) }
    }

    /// Puts the working window in the middle of the area.
    static func show(_ window: NSWindow) {
        guard !window.isVisible else { return }
        open()
        withoutGlass(window)
        window.setContentSize(CGSize(width: 880, height: 600))
        Demo.stage(window, offset: CGPoint(x: 2, y: 2))
        // It's off every screen, where only a clip's own clicks reach it.
        window.ignoresMouseEvents = false
        keepOnEveryDesktop()
    }

    /// Off the screen there's nothing behind a window for its material to blur, and it's
    /// drawn as flat mid-grey. In its place goes the dark grey the material makes of a light
    /// page, which is what MathPeek is mostly over.
    static func withoutGlass(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        func plain(_ glass: NSVisualEffectView) -> NSView {
            let view = NSView(frame: glass.frame)
            view.autoresizingMask = glass.autoresizingMask
            view.wantsLayer = true
            view.layer?.backgroundColor = CGColor(srgbRed: 0.30, green: 0.30, blue: 0.305, alpha: 1)
            if !window.styleMask.contains(.titled) {
                view.layer?.cornerRadius = BubbleView.cornerRadius
                view.layer?.masksToBounds = true
            }
            for subview in glass.subviews {
                subview.removeFromSuperview()
                view.addSubview(subview)
            }
            return view
        }
        if let glass = content as? NSVisualEffectView {
            window.contentView = plain(glass)
        } else {
            for case let glass as NSVisualEffectView in content.subviews { content.replaceSubview(glass, with: plain(glass)) }
        }
    }
}

/// The working window while a clip is filmed: AppKit keeps a window with a title bar on a
/// screen, and this one has to stay on the stage (see `Demo.stage`). It has the keys, as the
/// window in front would, so what's typed into it shows its caret.
final class DemoWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var isKeyWindow: Bool { true }
}

/// The shortcut's keys, each on its own cap.
private final class KeyCaps: NSView {
    private let caps: [String]
    private static let side: CGFloat = 40, gap: CGFloat = 7

    init(_ caps: [String]) {
        self.caps = caps
        super.init(frame: CGRect(x: 0, y: 0, width: CGFloat(caps.count) * Self.side + CGFloat(caps.count - 1) * Self.gap, height: Self.side))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        for (index, cap) in caps.enumerated() {
            let box = CGRect(x: CGFloat(index) * (Self.side + Self.gap), y: 0, width: Self.side, height: Self.side)
            NSColor(srgbRed: 0.125, green: 0.13, blue: 0.14, alpha: 0.94).setFill()
            NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
            let glyph = NSAttributedString(string: cap, attributes: [.font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: NSColor.white])
            glyph.draw(at: CGPoint(x: box.midX - glyph.size().width / 2, y: box.midY - glyph.size().height / 2))
        }
    }
}

/// A picture handed to another thread to be read. It never changes once made.
private struct Picture: @unchecked Sendable {
    let image: CGImage
}

/// Notes where something that can be clicked is, for a clip's pointer to find it.
struct DemoPlace: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        if DemoStage.isFilming {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { DemoStage.places[id] = $0 }
        } else {
            content
        }
    }
}

extension View {
    nonisolated func demoPlace(_ id: String) -> some View { modifier(DemoPlace(id: id)) }
}

/// Acts a scene out: moves the pointer, presses the shortcut, clicks and types, as someone
/// would. Clicks and keys are real events sent to MathPeek's own windows.
@MainActor
final class DemoDirector {
    private let prefs: Preferences
    private let reader: MathReader
    private let bubble: AnswerBubble
    private let learn: LearnWindow
    private let history: History
    /// When the scene starts, as `CACurrentMediaTime`, and how far into it the script has got.
    private var start = 0.0
    private var time = 0.0
    /// Where the pointer has been (seconds into the scene, and points from the stage's top
    /// left) and when it clicked, and what a scene meant to click and couldn't find: written
    /// down for clips.jsonc when the scene is rehearsed.
    private var path: [(time: Double, point: CGPoint)] = []
    private var clicks: [Double] = []
    /// When its button was held down, drawing: from and to.
    private var drags: [[Double]] = []
    private var missing: [String] = []
    private var eventNumber = 0
    private var firstClickViews: Set<ObjectIdentifier> = []
    /// What the pointer was last sent to, lit as the real pointer would light it.
    private var target: String?

    init(prefs: Preferences, reader: MathReader, bubble: AnswerBubble, learn: LearnWindow, history: History) {
        self.prefs = prefs
        self.reader = reader
        self.bubble = bubble
        self.learn = learn
        self.history = history
    }

    func run(_ scene: DemoScene) {
        DemoStage.open()
        // Some scenes start with the working already open.
        switch scene {
        case .tryIt: open(["3x + 5 = 20"])
        case .explore: open(["2x^2 + 3x = x + 7"])
        case .draw:
            open(["3x + 5 = 20"])
            learn.demo?.model.setTryFirst(true)
        case .change: open(["x^2 - 6x + 8 = 0"])
        case .history:
            history.showDemo(pastEntries())
            open(["x^2 - 5x + 6 = 0"])
        default: break
        }
        start = CACurrentMediaTime() + Demo.lead
        Demo.started(at: start)
        path = [(-1, DemoStage.pointer)]
        Task {
            await pause(0.3)
            switch scene {
            case .tour: await tour()
            case .bubble: await bubbles()
            case .several: await several()
            case .roadmap: await roadmap()
            case .tryIt: await tryIt()
            case .draw: await draw()
            case .explore: await explore()
            case .diagram: await diagram()
            case .change: await change()
            case .history: await pastAnswers()
            }
            await pause(1.2)
            rehearsed()
        }
    }

    /// After a rehearsal (`-demoRehearse <file>`): how long the scene took and where its
    /// pointer went, as the recorder measures it, from the stage's top left inside its margin.
    private func rehearsed() {
        guard let file = UserDefaults.standard.string(forKey: "demoRehearse") else { return }
        let notes: [String: Any] = [
            "length": time,
            "pointer": path.map { [$0.time, Double($0.point.x - DemoStage.margin), Double($0.point.y - DemoStage.margin)] },
            "clicks": clicks, "drags": drags, "missing": missing,
        ]
        try? JSONSerialization.data(withJSONObject: notes).write(to: URL(fileURLWithPath: file), options: .atomic)
    }

    // MARK: The scenes

    private func tour() async {
        await move(to: spot(0))
        await pause(0.4)
        await press(["x^2 - 5x + 6 = 0"])
        await pause(1.5)
        await clickBubble()
        await pause(1.4)
        await click("stop.1")
        await pause(1.5)
        await click("visualise")
        await moveAside()
        await pause(2.4)
    }

    private func bubbles() async {
        let sums = ["12 × (3 + 4.5) =", "12 × 7.5 = 91", "15% of 80 =", "3/4 + 5/6 ="]
        for (index, sum) in sums.enumerated() {
            await move(to: spot(index))
            await pause(0.35)
            await press([sum])
            await pause(index == 1 ? 1.9 : 1.5)
        }
    }

    private func several() async {
        await move(to: spot(0))
        await pause(0.4)
        await press(["2x + 3 = 11", "x^2 - 7x + 10 = 0", "5/6 - 1/4", "3(2y - 1) = 15"], nearest: 1)
        await pause(1.8)
        await clickBubble()
        await pause(1.5)
        await click("tab.problem.2")
        await pause(1.4)
        await click("tab.problem.3")
        await pause(1.2)
    }

    private func roadmap() async {
        await move(to: spot(0))
        await pause(0.4)
        await press(["x^3 - 6x^2 + 11x - 6 = 0", "2x^2 + 5x - 3 = 0"])
        await pause(1.2)
        await clickBubble()
        await pause(1.2)
        await click("stop.1")
        await pause(1.7)
        await click("stop.1")
        await pause(0.4)
        await click("answer.1")
        await scroll(by: -90, over: 0.4)
        await pause(1.5)
        await click("tab.problem.1")
        await pause(1.1)
        await click("method.1")
        await pause(1.4)
        await click("method.2")
        await pause(1.2)
    }

    private func tryIt() async {
        await click("footer.try")
        await moveAside()
        await pause(0.6)
        await type("3x = 25")
        await pause(1.6)
        await backspace(2)
        await type("15")
        await pause(0.9)
        await command(#selector(NSResponder.insertNewline(_:)))
        await pause(0.5)
        await type("x = 5")
        await pause(1.2)
    }

    /// Working it out by hand on the roadmap, under the line to type in: two lines with the
    /// pen, a slip rubbed out and put right, the answer highlighted, and a typed note.
    private func draw() async {
        await click("tool.Pen", after: 0.15)
        for line in handwriting("3x = 15", at: CGPoint(x: 196, y: 372)) { await stroke(line) }
        await pause(0.15)
        let second = handwriting("x = 6", at: CGPoint(x: 222, y: 428))
        for line in second { await stroke(line) }
        await pause(0.3)
        // The 6 is wrong: rubbed out with a scribble across it.
        await click("tool.Eraser", after: 0.15)
        if let six = second.last, let left = six.map(\.x).min(), let right = six.map(\.x).max(), let top = six.map(\.y).min(), let bottom = six.map(\.y).max() {
            await stroke([CGPoint(x: left - 4, y: top + 6), CGPoint(x: right + 4, y: (top + bottom) / 2), CGPoint(x: left - 2, y: bottom - 4)], speed: 200)
        }
        await pause(0.2)
        // A colour picked while rubbing out is for the pen: the 5 goes in in yellow.
        await click("color.Yellow", after: 0.15)
        for line in handwriting("5", at: CGPoint(x: 222 + 79, y: 428)) { await stroke(line) }
        await pause(0.3)
        await click("tool.Highlighter", after: 0.15)
        await stroke([stagePoint(inWindow: CGPoint(x: 214, y: 446)), stagePoint(inWindow: CGPoint(x: 290, y: 444)), stagePoint(inWindow: CGPoint(x: 352, y: 447))], speed: 300)
        await pause(0.3)
        await click("tool.Text", after: 0.15)
        await move(to: stagePoint(inWindow: CGPoint(x: 430, y: 392)))
        await pause(0.2)
        await click()
        await pause(0.3)
        await type("take away 5", each: 0.06)
        await pause(0.3)
        await command(#selector(NSResponder.insertNewline(_:)))
        await moveAside()
    }

    /// The working isn't a printout: a term clicked says what it is and lights every term of
    /// its kind, a step opened shows them moving, an answer clicked is put back into the
    /// question and marked on the graph, and it can be rounded, zoomed and dragged about.
    private func explore() async {
        // The second term from the left in the problem: 3x.
        let terms = DemoStage.places.filter { $0.key.hasPrefix("problem.0/") }.sorted { $0.value.minX < $1.value.minX }
        guard terms.count >= 2 else {
            missing.append("the problem's terms")
            return
        }
        await click(terms[1].key)
        await pause(1.6)
        await click("stop.0")
        await pause(1.9)
        // Two fingers up the trackpad, to the answers.
        if let model = learn.demo?.model, let answer = DemoStage.places["answer.1"] {
            await scroll(by: min(0, model.canvasFrame.maxY - 190 - answer.maxY), over: 0.7)
        }
        await pause(0.3)
        await click("answer.1")
        await pause(1.8)
        await click("round.2 dp")
        await pause(1.6)
        await click("zoom.in")
        await pause(1.0)
        // The roadmap dragged up by a bare patch of it, to the graph under the answers.
        let grip = stagePoint(inWindow: CGPoint(x: 806, y: 470))
        await stroke((0...28).map { CGPoint(x: grip.x - CGFloat($0) * 0.3, y: grip.y - CGFloat($0) * 10) }, speed: 240)
        await pause(0.6)
    }

    private func diagram() async {
        await move(to: spot(0))
        await pause(0.4)
        DemoStage.showKeys(true)
        await pause(0.2)
        // Reading takes a moment, as it does from the screen: the time for it is allowed.
        let reading = await readPage()
        await pause(0.9)
        reader.showDemo(reading, at: DemoStage.global)
        DemoStage.showKeys(false)
        await pause(1.6)
        await clickBubble()
        await pause(1.8)
        await click("stop.1")
        await moveAside()
        await pause(2.2)
    }

    private func change() async {
        // The last term before the "=": clicking it says what it is and underlines its
        // number, which can then be clicked and changed.
        let terms = DemoStage.places.filter { $0.key.hasPrefix("problem.0/0.") }.sorted { $0.value.minX < $1.value.minX }
        guard let term = terms.last else { return }
        await click(term.key)
        await pause(0.9)
        guard let number = DemoStage.places.first(where: { $0.key.hasPrefix("n:problem.0/0.") && term.value.insetBy(dx: -4, dy: -4).contains($0.value) }) else {
            missing.append("the number in \(term.key)")
            return
        }
        await click(number.key)
        await pause(0.7)
        await type("5", each: 0.3)
        await pause(0.5)
        await command(#selector(NSResponder.insertNewline(_:)))
        await pause(2.0)
        await click("another")
        await moveAside()
        await pause(2.0)
    }

    private func pastAnswers() async {
        await click("history")
        await pause(1.4)
        if let field = searchField(), let window = field.window {
            let box = field.convert(field.bounds, to: nil)
            await move(to: CGPoint(x: window.frame.minX - DemoStage.frame.minX + box.minX + 60,
                                   y: DemoStage.frame.maxY - window.frame.minY - box.midY))
            await pause(0.3)
            // A click in a text field follows the mouse until it's let go, which a click made
            // here can't end: the field is given the keys as the click would give them.
            clicks.append(time)
            window.makeFirstResponder(field)
            await pause(0.5)
            await type("frac", each: 0.16)
            await pause(1.2)
        }
        if let entry = history.entries.first(where: { $0.question.contains("5/6") }) {
            await click("history.\(entry.id)")
            await moveAside()
            await pause(1.8)
        }
    }

    /// Takes the pointer off what it just clicked, so it isn't in the way of what that shows.
    private func moveAside() async {
        guard let window = learn.demo?.window else { return }
        target = nil
        await move(to: CGPoint(x: window.frame.maxX - DemoStage.frame.minX - 150, y: DemoStage.frame.maxY - window.frame.minY - 190), over: 0.6)
    }

    /// Answers from earlier today and yesterday, as the history would have them.
    private func pastEntries() -> [History.Entry] {
        let options = ReadOptions(angles: prefs.angles, useModel: false)
        let asked: [(String, Double)] = [
            ("x^2 - 5x + 6 = 0", 2), ("15% of 80", 9), ("3/4 + 5/6", 14), ("2x + 3 = 11", 31), ("differentiate x^2 sin x", 47),
            ("x^3 - 6x^2 + 11x - 6 = 0", 26 * 60), ("h/6 + 2h/9", 26 * 60 + 12), ("2x + y = 7; x - y = 2", 27 * 60), ("12 × (3 + 4.5)", 27 * 60 + 20),
        ]
        return asked.compactMap { text, minutes in
            guard let solution = ScreenReader.worked(text, options) else { return nil }
            return History.Entry(date: Date().addingTimeInterval(-minutes * 60), question: History.question(for: solution),
                                 answer: solution.answerText, input: LearnModel.inputText(for: solution), topic: History.topic(for: solution))
        }
    }

    /// The working window, opened on problems as if their answers had just been clicked.
    private func open(_ sums: [String], selected: Int = 0) {
        let options = ReadOptions(angles: prefs.angles, useModel: false)
        learn.show(sums.compactMap { ScreenReader.worked($0, options) }, selected: selected, angles: prefs.angles)
    }

    /// What's around the pointer on the page, read from its picture the way the screen is:
    /// the diagram found in it and worked out, with the words beside it.
    private func readPage() async -> Reading {
        guard let page = DemoStage.page else { return .noMaths }
        let scale = CGFloat(page.width) / DemoStage.frame.width
        let pointer = DemoStage.pointer
        let area = CGRect(x: pointer.x - 450, y: pointer.y - 450, width: 900, height: 900)
            .intersection(CGRect(origin: .zero, size: DemoStage.frame.size))
        guard let picture = page.cropping(to: CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale))
        else { return .noMaths }
        let focus = CGPoint(x: (pointer.x - area.minX) * scale, y: (pointer.y - area.minY) * scale)
        let size = area.size
        let cut = Picture(image: picture)
        return await Task.detached(priority: .userInitiated) {
            let found = DiagramReader.diagrams(in: cut.image, near: focus, limit: 1)
            guard let nearest = ScreenReader.solved(found, in: cut.image, size: size, text: try? ScreenReader.recognize(cut.image, size: size)).first
            else { return Reading.noMaths }
            return .solved(nearest.solutions, primary: 0)
        }.value
    }

    // MARK: Acting

    private func spot(_ index: Int) -> CGPoint {
        DemoStage.spots.indices.contains(index) ? DemoStage.spots[index] : CGPoint(x: DemoStage.frame.width / 2, y: DemoStage.frame.height / 2)
    }

    /// Waits until `seconds` further into the scene. Steps are timed from the scene's start
    /// rather than from each other, so a step that takes a moment longer doesn't put the rest out.
    private func pause(_ seconds: Double) async {
        time += seconds
        let wait = start + time - CACurrentMediaTime()
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
    }

    /// The pointer glides to a point on the stage, easing in and out; further takes longer.
    private func move(to point: CGPoint, over seconds: Double? = nil) async {
        let from = DemoStage.pointer
        let distance = hypot(point.x - from.x, point.y - from.y)
        guard distance > 0.5 else { return }
        let duration = seconds ?? min(max(0.35 + distance / 900, 0.45), 1.0)
        let began = time
        path += [(began, from), (began + duration, point)]
        while true {
            let linear = min(max((CACurrentMediaTime() - start - began) / duration, 0), 1)
            let eased = linear * linear * (3 - 2 * linear)
            DemoStage.pointer = CGPoint(x: from.x + (point.x - from.x) * eased, y: from.y + (point.y - from.y) * eased)
            pointerMoved()
            if linear >= 1 { break }
            try? await Task.sleep(for: .milliseconds(12))
        }
        time = began + duration
    }

    /// The shortcut, pressed where the pointer is. What a read of the page would hand on is
    /// handed on from here: each problem as text, worked out by the same engine.
    private func press(_ sums: [String], nearest: Int = 0) async {
        DemoStage.showKeys(true)
        await pause(0.2)
        let options = ReadOptions(angles: prefs.angles, useModel: false)
        let solutions = sums.compactMap { ScreenReader.worked($0, options) }
        reader.showDemo(solutions.isEmpty ? .noMaths : .solved(solutions, primary: min(nearest, solutions.count - 1)), at: DemoStage.global)
        await pause(0.6)
        DemoStage.showKeys(false)
    }

    /// Moves onto the bubble and clicks it.
    private func clickBubble() async {
        guard let frame = bubble.demoFrame else { return }
        // Its lower right corner, clear of the answer.
        await move(to: CGPoint(x: frame.maxX - 24 - DemoStage.frame.minX, y: DemoStage.frame.maxY - frame.minY - 14))
        await pause(0.5)
        await click()
    }

    /// Where something in the working window is on the stage, once it's there.
    private func place(_ id: String, wait: Double = 3) async -> CGPoint? {
        let began = CACurrentMediaTime()
        while CACurrentMediaTime() - began < wait {
            if let window = learn.demo?.window, window.isVisible, let rect = DemoStage.places[id], rect.width > 1, rect.height > 1 {
                return CGPoint(x: window.frame.minX - DemoStage.frame.minX + rect.midX,
                               y: DemoStage.frame.maxY - window.frame.maxY + rect.midY)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Moves to something in the working window and clicks it.
    private func click(_ id: String, after seconds: Double = 0.35) async {
        guard let point = await place(id) else {
            missing.append(id)
            return
        }
        target = id
        await move(to: point)
        await pause(seconds)
        // It may have moved while the pointer was on its way.
        if let now = await place(id, wait: 0.05), hypot(now.x - point.x, now.y - point.y) > 2 { await move(to: now, over: 0.25) }
        await click()
    }

    /// A click where the pointer is, on whichever of MathPeek's windows is there.
    private func click() async {
        let point = DemoStage.global
        let windows = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && !$0.ignoresMouseEvents && $0.frame.contains(point) }
        guard let window = windows.max(by: { ($0.level.rawValue, -$0.orderedIndex) < ($1.level.rawValue, -$1.orderedIndex) }) else { return }
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            eventNumber += 1
            return NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        clicks.append(time)
        takeFirstClicks(at: point, in: window)
        if let down = event(.leftMouseDown) { window.sendEvent(down) }
        await pause(0.1)
        if let up = event(.leftMouseUp) { window.sendEvent(up) }
        await pause(0.05)
        pointerMoved()
    }

    /// A point in the working window, from its top left, as a point on the stage.
    private func stagePoint(inWindow point: CGPoint) -> CGPoint {
        guard let window = learn.demo?.window else { return point }
        return CGPoint(x: window.frame.minX - DemoStage.frame.minX + point.x, y: DemoStage.frame.maxY - window.frame.maxY + point.y)
    }

    /// The pointer pressed, drawn along a line and let go: a pen stroke, or whatever the tool
    /// picked does with a drag. The points are on the stage.
    private func stroke(_ points: [CGPoint], speed: CGFloat = 285) async {
        guard let first = points.first else { return }
        let hop = hypot(first.x - DemoStage.pointer.x, first.y - DemoStage.pointer.y)
        await move(to: first, over: hop < 80 ? 0.12 : nil)
        await pause(0.05)
        let windows = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && !$0.ignoresMouseEvents && $0.frame.contains(DemoStage.global) }
        guard let window = windows.max(by: { ($0.level.rawValue, -$0.orderedIndex) < ($1.level.rawValue, -$1.orderedIndex) }) else { return }
        func send(_ type: NSEvent.EventType) {
            eventNumber += 1
            if let event = NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: DemoStage.global), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
                window.sendEvent(event)
            }
        }
        target = nil
        takeFirstClicks(at: DemoStage.global, in: window)
        let began = time
        path.append((began, first))
        send(.leftMouseDown)
        var last = first
        for point in points.dropFirst() {
            await pause(Double(hypot(point.x - last.x, point.y - last.y) / speed))
            DemoStage.pointer = point
            path.append((time, point))
            send(.leftMouseDragged)
            last = point
        }
        send(.leftMouseUp)
        drags.append([began, time])
        await pause(0.05)
    }

    /// Writing as a hand would do it: each character a stroke or two through many points,
    /// leaning a little and never quite the same twice. From the top left of the writing, in
    /// the working window; the strokes are on the stage.
    private func handwriting(_ text: String, at origin: CGPoint, height: CGFloat = 32) -> [[CGPoint]] {
        // Each character in a box one high: its width, and its strokes.
        let shapes: [Character: (width: CGFloat, strokes: [[(CGFloat, CGFloat)]])] = [
            "3": (0.62, [[(0.08, 0.14), (0.3, 0.02), (0.52, 0.06), (0.58, 0.24), (0.46, 0.42), (0.26, 0.48), (0.48, 0.56), (0.6, 0.74), (0.5, 0.94), (0.26, 1.0), (0.06, 0.9)]]),
            "5": (0.62, [[(0.56, 0.02), (0.2, 0.03), (0.15, 0.44), (0.36, 0.4), (0.54, 0.5), (0.6, 0.72), (0.5, 0.93), (0.28, 1.0), (0.08, 0.9)]]),
            "6": (0.62, [[(0.52, 0.04), (0.3, 0.2), (0.14, 0.48), (0.1, 0.78), (0.24, 0.98), (0.46, 0.97), (0.58, 0.78), (0.5, 0.58), (0.3, 0.54), (0.13, 0.7)]]),
            "1": (0.42, [[(0.06, 0.26), (0.28, 0.03), (0.27, 1.0)]]),
            "x": (0.56, [[(0.06, 0.4), (0.26, 0.68), (0.5, 1.0)], [(0.5, 0.4), (0.28, 0.7), (0.04, 1.0)]]),
            "=": (0.6, [[(0.06, 0.52), (0.52, 0.5)], [(0.07, 0.76), (0.53, 0.74)]]),
            " ": (0.34, []),
        ]
        var strokes: [[CGPoint]] = []
        var x = origin.x
        // The same wobble every time, so the rehearsal and the recording draw alike.
        var seed: UInt64 = 0x5EED + UInt64(text.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        func wobble() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 40) / CGFloat(1 << 24) - 0.5
        }
        for character in text {
            guard let shape = shapes[character] else { continue }
            let lift = wobble() * 2.4
            for line in shape.strokes {
                let corners = line.map { CGPoint(x: x + ($0.0 + (1 - $0.1) * 0.14) * height, y: origin.y + lift + $0.1 * height) }
                var points: [CGPoint] = []
                for (from, to) in zip(corners, corners.dropFirst()) {
                    let steps = max(1, Int(hypot(to.x - from.x, to.y - from.y) / 4))
                    for step in 0..<steps {
                        let part = CGFloat(step) / CGFloat(steps)
                        points.append(CGPoint(x: from.x + (to.x - from.x) * part + wobble() * 0.9, y: from.y + (to.y - from.y) * part + wobble() * 0.9))
                    }
                }
                if let end = corners.last { points.append(end) }
                strokes.append(points.map(stagePoint(inWindow:)))
            }
            x += (shape.width + 0.16) * height
        }
        return strokes
    }

    /// MathPeek is never the active app during a clip, and the first click on a window of an
    /// app that isn't only brings it forward. The views under the pointer are told to take
    /// that click as a click, as they would the second.
    private func takeFirstClicks(at point: CGPoint, in window: NSWindow) {
        guard let frame = window.contentView?.superview, var view = frame.hitTest(frame.convert(window.convertPoint(fromScreen: point), from: nil)) else { return }
        let selector = #selector(NSView.acceptsFirstMouse(for:))
        let always: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
        while true {
            let kind: AnyClass = Swift.type(of: view)
            if !firstClickViews.contains(ObjectIdentifier(kind)), let method = class_getInstanceMethod(kind, selector) {
                firstClickViews.insert(ObjectIdentifier(kind))
                class_replaceMethod(kind, selector, imp_implementationWithBlock(always), method_getTypeEncoding(method))
            }
            guard let above = view.superview else { break }
            view = above
        }
    }

    /// Types into whatever has the keys in the working window, a character at a time.
    private func type(_ text: String, each seconds: Double = 0.09) async {
        for character in text {
            guard let editor = learn.demo?.window.firstResponder as? NSTextView else { return }
            editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            await pause(seconds)
        }
    }

    /// Delete, pressed a few times.
    private func backspace(_ count: Int) async {
        for _ in 0..<count {
            (learn.demo?.window.firstResponder as? NSTextView)?.deleteBackward(nil)
            await pause(0.12)
        }
    }

    /// A key that does something rather than types: Return, an arrow. It goes the way the
    /// key would, through the field that has the keys.
    private func command(_ selector: Selector) async {
        (learn.demo?.window.firstResponder as? NSTextView)?.doCommand(by: selector)
        await pause(0.1)
    }

    /// The field for searching the history.
    private func searchField() -> NSTextField? {
        func find(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            for subview in view.subviews {
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        return learn.demo?.window.contentView.flatMap(find)
    }

    /// Two fingers on the trackpad: the roadmap moves and the pointer stays.
    private func scroll(by distance: CGFloat, over seconds: Double = 0.6) async {
        guard let model = learn.demo?.model else { return }
        let began = time
        var done: CGFloat = 0
        while true {
            let linear = min(max((CACurrentMediaTime() - start - began) / seconds, 0), 1)
            let eased = distance * linear * linear * (3 - 2 * linear)
            model.scroll(by: CGSize(width: 0, height: eased - done))
            done = eased
            if linear >= 1 { break }
            try? await Task.sleep(for: .milliseconds(12))
        }
        time = began + seconds
    }

    /// Tells MathPeek's windows what the pointer is over: they can't see for themselves,
    /// since the real pointer is elsewhere.
    private func pointerMoved() {
        let point = DemoStage.global
        bubble.demoPointer(point)
        guard let (window, model) = learn.demo else { return }
        var over: String?
        if window.isVisible, window.frame.contains(point), bubble.demoFrame?.contains(point) != true {
            let inWindow = CGPoint(x: point.x - window.frame.minX, y: window.frame.maxY - point.y)
            // The smallest thing under the pointer; a part of the maths only when it's
            // what the pointer was sent to.
            over = DemoStage.places.filter { $0.value.contains(inWindow) && (!$0.key.contains("/") || $0.key == target) }
                .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
        }
        if let over, over.contains("/") {
            model.hover(over, true)
        } else {
            if let target, target.contains("/") { model.hover(target, false) }
            if model.hovered != over { model.hovered = over }
        }
    }
}
