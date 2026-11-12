import AppKit
import SwiftUI

/// The README's clips, recorded by scripts/make-video.swift. Launched with
/// `-demo <scene> -demoClock <file>`, MathPeek acts out the scene with its real bubble and
/// working window, on problems written here. Nothing is read from the screen, so it needs no
/// Screen Recording; the shortcut isn't registered, the menu bar icon isn't shown, and no
/// history or settings are saved. Its windows open off every display (`DemoStage`), where the
/// recording finds them, and it never becomes the active app: a copy of MathPeek that's
/// already running carries on undisturbed.
enum DemoScene: String {
    /// The README's main clip: a quadratic, its answer by the pointer, the roadmap, a step
    /// opened and written out.
    case tour
    /// Answers by the pointer: a sum, fractions, a percentage, a written answer that's wrong,
    /// and several problems at once.
    case bubble
    /// Several problems read at once: the bubble lists them, and each has a tab.
    case several
    /// Stepping down a cubic's roadmap to its three roots, then a quadratic another way.
    case roadmap
    /// Try It Yourself: lines checked as they're written.
    case tryIt = "try"
    /// A circle-theorem diagram read from a picture and worked out.
    case diagram
    /// Changing a number in the problem, and Another Like This.
    case change
    /// The history: searching it, and opening an answer again.
    case history

    /// The scene being recorded, if one is. (`-demo` on its own, without `-demoClock`, shows a
    /// still set-up to look at: see `AppDelegate.showDemoScene`.)
    static let current: DemoScene? = {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "demoClock") != nil else { return nil }
        return defaults.string(forKey: "demo").flatMap(DemoScene.init(rawValue:))
    }()
}

/// Where a clip is acted out: an area the size of a small screen, off every display. The
/// recording draws the page MathPeek is pointed at and the pointer; this says where the
/// pointer is, since the real one is somewhere else, being used.
@MainActor
enum DemoStage {
    nonisolated static let isFilming = DemoScene.current != nil

    /// The stage in AppKit's coordinates. Its size comes from the recording (`-demoStage 960,640`).
    static let frame: CGRect = {
        let size = numbers(UserDefaults.standard.string(forKey: "demoStage") ?? "")
        return CGRect(x: -6000, y: -6000, width: size.count == 2 ? size[0] : 960, height: size.count == 2 ? size[1] : 640)
    }()

    /// Where the page's problems are, from the stage's top left (`-demoSpots "x,y;x,y"`).
    static let spots: [CGPoint] = (UserDefaults.standard.string(forKey: "demoSpots") ?? "").split(separator: ";").compactMap {
        let pair = numbers(String($0))
        return pair.count == 2 ? CGPoint(x: pair[0], y: pair[1]) : nil
    }

    /// A picture of the page the recording draws, for the one thing that's read from a picture
    /// rather than handed over as text: a diagram (`-demoPage <png>`).
    static let page: CGImage? = UserDefaults.standard.string(forKey: "demoPage")
        .flatMap { NSImage(contentsOfFile: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }

    /// The pointer, from the stage's top left.
    static var pointer = CGPoint(x: frame.width * 0.72, y: frame.height * 0.8)
    static var isPressed = false
    /// Whether the shortcut's keys are down.
    static var keysDown = false

    /// Where everything that can be clicked is in the working window, from its top left.
    static var places: [String: CGRect] = [:]

    /// The pointer in AppKit's coordinates.
    static var global: CGPoint { CGPoint(x: frame.minX + pointer.x, y: frame.maxY - pointer.y) }

    private static func numbers(_ text: String) -> [CGFloat] {
        text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
    }

    /// Puts a window in the middle of the stage. A window with a title bar is moved back onto
    /// a display as it's ordered in, so that happens while it can't be seen, and then it's
    /// put where it belongs.
    static func show(_ window: NSWindow) {
        guard !window.isVisible else { return }
        withoutGlass(window)
        let size = CGSize(width: min(880, frame.width), height: min(600, frame.height))
        let place = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrame(place, display: false)
        window.orderFrontRegardless()
        window.setFrame(place, display: true)
        (window as? DemoWindow)?.place = place
        // Only once it's off the screen for good can it be seen and clicked.
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) else { return }
        window.ignoresMouseEvents = false
        window.alphaValue = 1
    }

    /// What blurs the screen behind a window is drawn as plain grey off the screen. Without
    /// it the window is recorded see-through, and the recording blurs the page behind it.
    static func withoutGlass(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        func plain(_ glass: NSVisualEffectView) -> NSView {
            let view = NSView(frame: glass.frame)
            view.autoresizingMask = glass.autoresizingMask
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

/// A window that stays where it's put, off the screen, and looks like the one in front:
/// MathPeek is never the active app during a clip, and the window buttons of an app that
/// isn't are grey.
final class DemoWindow: NSWindow {
    /// Where it was put on the stage. From then on it can't be moved or brought forward:
    /// AppKit does both to a window that's clicked, and would put it on a display.
    var place: CGRect?

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { place ?? frameRect }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) { super.setFrame(place ?? frameRect, display: flag) }
    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) { super.setFrame(place ?? frameRect, display: displayFlag) }
    override func setFrameOrigin(_ point: NSPoint) { super.setFrameOrigin(place?.origin ?? point) }
    override func setFrameTopLeftPoint(_ point: NSPoint) { if place == nil { super.setFrameTopLeftPoint(point) } }
    override func center() { if place == nil { super.center() } }
    override func makeKeyAndOrderFront(_ sender: Any?) { if place == nil { super.makeKeyAndOrderFront(sender) } }
    override func orderFront(_ sender: Any?) { if place == nil { super.orderFront(sender) } }
    override func orderFrontRegardless() { if place == nil { super.orderFrontRegardless() } }
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) { if self.place == nil || place == .out { super.order(place, relativeTo: otherWin) } }
    override func makeKey() { if place == nil { super.makeKey() } }
    override func makeMain() { if place == nil { super.makeMain() } }
    override func miniaturize(_ sender: Any?) {}
    override func zoom(_ sender: Any?) {}
    override func toggleFullScreen(_ sender: Any?) {}

    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
    @objc(_hasKeyAppearance) func demoHasKeyAppearance() -> Bool { true }
    @objc(_hasMainAppearance) func demoHasMainAppearance() -> Bool { true }
    @objc(_hasActiveAppearance) func demoHasActiveAppearance() -> Bool { true }
    @objc(hasKeyAppearance) func demoKeyAppearance() -> Bool { true }
    @objc(hasMainAppearance) func demoMainAppearance() -> Bool { true }
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
    private let clock = UserDefaults.standard.string(forKey: "demoClock").map { URL(fileURLWithPath: $0) }
    /// Where to note what a scene couldn't find, when it's being worked on (`-demoLog <file>`).
    private let log = UserDefaults.standard.string(forKey: "demoLog")
    private var start = 0.0
    private var isDone = false
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
        // Never the active app: the keys stay with whoever is using the Mac.
        NSApp.setActivationPolicy(.prohibited)
        Task {
            // Text recognition and the first window take a moment the first time.
            try? await Task.sleep(for: .seconds(0.6))
            // Some scenes start with the working already open.
            switch scene {
            case .tryIt: open(["3x + 5 = 20"])
            case .change: open(["x^2 - 6x + 8 = 0"])
            case .history:
                history.showDemo(pastEntries())
                open(["x^2 - 5x + 6 = 0"])
            default: break
            }
            if learn.demo != nil { try? await Task.sleep(for: .seconds(0.8)) }
            start = CACurrentMediaTime()
            publish()
            await pause(0.8)
            switch scene {
            case .tour: await tour()
            case .bubble: await bubbles()
            case .several: await several()
            case .roadmap: await roadmap()
            case .tryIt: await tryIt()
            case .diagram: await diagram()
            case .change: await change()
            case .history: await pastAnswers()
            }
            await pause(1.4)
            isDone = true
            publish()
        }
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

    private func diagram() async {
        await move(to: spot(0))
        await pause(0.4)
        DemoStage.keysDown = true
        publish()
        await pause(0.2)
        let reading = await readPage()
        reader.showDemo(reading, at: DemoStage.global)
        await pause(0.5)
        DemoStage.keysDown = false
        publish()
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
            note("no number in \(term.key): \(DemoStage.places.keys.filter { $0.hasPrefix("n:") })")
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
            DemoStage.isPressed = true
            publish()
            await pause(0.1)
            window.makeFirstResponder(field)
            DemoStage.isPressed = false
            publish()
            await pause(0.4)
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

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// The pointer glides to a point on the stage, easing in and out; further takes longer.
    private func move(to point: CGPoint, over seconds: Double? = nil) async {
        let from = DemoStage.pointer
        let distance = hypot(point.x - from.x, point.y - from.y)
        guard distance > 0.5 else { return }
        let duration = seconds ?? min(max(0.35 + distance / 900, 0.45), 1.0)
        let began = CACurrentMediaTime()
        while true {
            let linear = min((CACurrentMediaTime() - began) / duration, 1)
            let eased = linear * linear * (3 - 2 * linear)
            DemoStage.pointer = CGPoint(x: from.x + (point.x - from.x) * eased, y: from.y + (point.y - from.y) * eased)
            pointerMoved()
            if linear >= 1 { break }
            try? await Task.sleep(for: .milliseconds(12))
        }
    }

    /// The shortcut, pressed where the pointer is. What a read of the page would hand on is
    /// handed on from here: each problem as text, worked out by the same engine.
    private func press(_ sums: [String], nearest: Int = 0) async {
        DemoStage.keysDown = true
        publish()
        await pause(0.2)
        let options = ReadOptions(angles: prefs.angles, useModel: false)
        let solutions = sums.compactMap { ScreenReader.worked($0, options) }
        reader.showDemo(solutions.isEmpty ? .noMaths : .solved(solutions, primary: min(nearest, solutions.count - 1)), at: DemoStage.global)
        await pause(0.5)
        DemoStage.keysDown = false
        publish()
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

    private func note(_ text: String) {
        guard let log, let data = (text + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: log) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: log, contents: data)
        }
    }

    /// Moves to something in the working window and clicks it.
    private func click(_ id: String, after seconds: Double = 0.35) async {
        guard let point = await place(id) else {
            let steps = learn.demo?.model.stops.map(\.title).joined(separator: " | ") ?? "no window"
            note("nothing called \(id). Steps: \(steps). There is: \(DemoStage.places.map { "\($0.key) \(Int($0.value.minX)),\(Int($0.value.minY)) \(Int($0.value.width))x\(Int($0.value.height))" }.sorted().joined(separator: "; "))")
            return
        }
        target = id
        await move(to: point)
        await pause(seconds)
        // It may have moved while the pointer was on its way.
        if let now = await place(id, wait: 0.1), hypot(now.x - point.x, now.y - point.y) > 2 { await move(to: now, over: 0.25) }
        await click()
    }

    /// A click where the pointer is, on whichever of MathPeek's windows is there.
    private func click() async {
        let point = DemoStage.global
        let windows = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && $0.frame.contains(point) }
        guard let window = windows.max(by: { ($0.level.rawValue, -$0.orderedIndex) < ($1.level.rawValue, -$1.orderedIndex) }) else { return }
        DemoStage.isPressed = true
        publish()
        await pause(0.08)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            eventNumber += 1
            return NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        takeFirstClicks(at: point, in: window)
        if let down = event(.leftMouseDown) { window.sendEvent(down) }
        await pause(0.1)
        if let up = event(.leftMouseUp) { window.sendEvent(up) }
        note("clicked \(target ?? "") in \(window.className) now at \(window.frame), visible \(window.isVisible), alpha \(window.alphaValue), active \(NSApp.isActive)")
        await pause(0.05)
        DemoStage.isPressed = false
        pointerMoved()
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

    /// Scrolls the roadmap until something on it is clear of the bottom of the window.
    private func bringIntoView(_ id: String) async {
        guard let model = learn.demo?.model, let rect = DemoStage.places[id] else { return }
        let bottom = model.canvasFrame.maxY - 40
        if rect.maxY > bottom { await scroll(by: bottom - rect.maxY - 60) }
        await pause(0.3)
    }

    /// A key on its own: Return, Escape, an arrow.
    private func key(_ code: UInt16, _ characters: String) async {
        guard let window = learn.demo?.window,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
        await pause(0.1)
    }

    /// Two fingers on the trackpad: the roadmap moves and the pointer stays.
    private func scroll(by distance: CGFloat, over seconds: Double = 0.6) async {
        guard let model = learn.demo?.model else { return }
        let began = CACurrentMediaTime()
        var done: CGFloat = 0
        while done != distance {
            let linear = min((CACurrentMediaTime() - began) / seconds, 1)
            let eased = distance * linear * linear * (3 - 2 * linear)
            model.scroll(by: CGSize(width: 0, height: eased - done))
            done = linear >= 1 ? distance : eased
            if linear >= 1 { break }
            try? await Task.sleep(for: .milliseconds(12))
        }
    }

    /// Tells the recording where the pointer is, and MathPeek's windows what it's over: they
    /// can't see for themselves, since the real pointer is elsewhere.
    private func pointerMoved() {
        publish()
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

    /// One line for the recording: when the scene started (as CACurrentMediaTime), where the
    /// stage is in screen coordinates (from the main display's top left), the pointer on
    /// it, whether the button and the shortcut are down, and whether the scene has finished.
    private func publish() {
        guard let clock else { return }
        let top = (NSScreen.screens.first?.frame.height ?? 0) - DemoStage.frame.maxY
        let line = String(format: "%.4f %.1f %.1f %.1f %.1f %d %d %d", start, DemoStage.frame.minX, top,
                          DemoStage.pointer.x, DemoStage.pointer.y, DemoStage.isPressed ? 1 : 0, DemoStage.keysDown ? 1 : 0, isDone ? 1 : 0)
        try? line.write(to: clock, atomically: true, encoding: .utf8)
    }
}
