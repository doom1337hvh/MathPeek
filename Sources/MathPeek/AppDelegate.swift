import AppKit
import AppShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private let hotkeys = HotkeyCenter()
    private let access = ScreenAccess()
    private let bubble = AnswerBubble()
    private let outline = AreaOutline()
    private lazy var learn = LearnWindow(prefs: prefs)
    private lazy var reader = MathReader(prefs: prefs, access: access, bubble: bubble)
    private lazy var recorder = ShortcutRecorder(prefs: prefs, hotkeys: hotkeys)
    private lazy var menuBar: MenuBar = MenuBar(symbol: "plus.forwardslash.minus", items: { [weak self] menu in
        guard let self else { return }
        menu.addItem(NSMenuItem("Turn On MathPeek", isOn: prefs.isEnabled) { [weak self] in
            self?.prefs.isEnabled.toggle()
        })
        menu.addItem(NSMenuItem("Read an Area…") { [weak self] in
            self?.reader.readChosenArea()
        })
        menu.addItem(NSMenuItem("Type a Problem…") { [weak self] in
            self?.typeProblem()
        })
    }, showSettings: { [weak self] in
        self?.settings.show()
    })
    private lazy var settings: SettingsWindow = SettingsWindow { [weak self] in
        guard let self else { return [] }
        return [
            .general(menuBar: menuBar),
            SettingsTab("MathPeek", symbol: "plus.forwardslash.minus") {
                MainSettings(prefs: self.prefs, hotkeys: self.hotkeys, recorder: self.recorder,
                             access: self.access, outline: self.outline)
            },
            .about(),
        ]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppShell.quitIfTranslocated() { return }
        prefs.onEnabledChange = { [weak self] in self?.update() }
        prefs.onHotkeyChange = { [weak self] in self?.update() }
        hotkeys.onAction = { [weak self] action in
            switch action {
            case .read: self?.reader.readByPointer()
            case .copyAnswer: self?.bubble.copy()
            }
        }
        reader.showWorking = { [weak self] solutions, selected in
            guard let self else { return }
            learn.show(solutions, selected: selected, angles: prefs.angles)
        }
        bubble.onCopyAvailable = { [weak self] available in
            self?.hotkeys.set(available ? .copy : nil, for: .copyAnswer)
        }
        settings.onResignedKey = { [weak self] in self?.recorder.stop() }
        settings.onClose = { [weak self] in self?.recorder.stop() }
        menuBar.install()
        update()

        if let scene = AppShell.demoScene {
            showDemoScene(scene)
            // A running demo can be told to change scene, so clips are recorded in one go.
            let name = Notification.Name((Bundle.main.bundleIdentifier ?? "MathPeek") + ".demo")
            DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? String else { return }
                MainActor.assumeIsolated { self?.showDemoScene(scene) }
            }
        }

        // Ready for the first press: the bubble's window exists (so captures leave it out) and
        // text recognition is loaded, which can take many seconds the first time.
        bubble.preload()
        let canCapture = access.isAllowed
        Task.detached(priority: .utility) {
            await ScreenReader.warmUp(canCapture: canCapture)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            Task { await ScreenReader.shared.forgetScreens() }
        }
    }

    /// Opening MathPeek again (Finder, Spotlight) shows Settings, which matters when the menu
    /// bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// The demo (`-demo <scene>`), also used for README clips. "tour" opens the working window
    /// with a range of problems; "steps", "graph", "breakdown" and "edit" show its other views;
    /// "fractions" shows a single answer and "problems" a worksheet; "bubble" and "bubble-list"
    /// show answers in the middle of the screen.
    private func showDemoScene(_ scene: String) {
        func solve(_ text: String) -> Solution? { Parser.problem(text).flatMap { Engine.solve($0, angles: prefs.angles) } }
        let center = NSScreen.main.map { CGPoint(x: $0.frame.midX - 150, y: $0.frame.midY + 80) } ?? .zero
        let tour = ["x^3 - 6x^2 + 11x - 6 = 0", "h/6 + 2h/9", "2x + y = 7; x - y = 2",
                    "differentiate x^2 sin x", "∫ x^2 dx from 0 to 3", "sin x = 0.5"]
        let worksheet = ["2x + 3 = 11", "x^2 - 5x + 6 = 0", "3/4 + 5/6", "differentiate x^3 + 2x"]
        switch scene {
        case "tour":
            learn.show(tour.compactMap(solve), selected: 0, angles: prefs.angles)
        case "steps":
            learn.show(tour.compactMap(solve), selected: 0, angles: prefs.angles, tab: .steps)
            learn.showDemo(step: 1)
        case "graph":
            learn.show(tour.compactMap(solve), selected: 0, angles: prefs.angles, tab: .graph)
            learn.showDemo(answer: 1)
        case "breakdown":
            learn.show(tour.compactMap(solve), selected: 0, angles: prefs.angles, tab: .breakdown)
            learn.showDemo(part: 1)
        case "edit":
            learn.show(tour.compactMap(solve), selected: 0, angles: prefs.angles)
            learn.beginTyping(prefilled: true)
        case "fractions":
            learn.show(tour.compactMap(solve), selected: 1, angles: prefs.angles)
        case "problems":
            learn.show(worksheet.compactMap(solve), selected: 1, angles: prefs.angles)
        case "bubble":
            guard let cubic = solve(tour[0]) else { return }
            bubble.show(.answer(sum: "Solve for x · " + cubic.question.text, answer: cubic.answerText, detail: nil,
                                copy: cubic.answerText, math: cubic.answers),
                        at: center, for: 60, action: { [weak self] in self?.learn.show(cubic, angles: .degrees) })
        case "bubble-list":
            let solutions = worksheet.compactMap(solve)
            let rows = solutions.enumerated().map { BubbleRow(question: LearnModel.summary($1), answer: $1.answerText, isNearest: $0 == 1) }
            bubble.show(.list(rows: rows, copy: ""), at: center, for: 60,
                        action: { [weak self] in self?.learn.show(solutions, selected: 1, angles: .degrees) })
        default:
            break
        }
    }

    /// Opens the working window on an example, with the field for typing a problem showing.
    private func typeProblem() {
        guard let example = Parser.problem("x^2 - 5x + 6 = 0").flatMap({ Engine.solve($0, angles: prefs.angles) }) else { return }
        learn.show(example, angles: prefs.angles)
        learn.beginTyping()
    }

    private func update() {
        menuBar.appearsDisabled = !prefs.isEnabled
        hotkeys.set(prefs.isEnabled ? prefs.hotkey : nil, for: .read)
        if !prefs.isEnabled { reader.stop() }
    }
}
