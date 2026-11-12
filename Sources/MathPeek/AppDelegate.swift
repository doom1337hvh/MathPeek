import AppKit
import AppShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private let hotkeys = HotkeyCenter()
    private let access = ScreenAccess()
    private let bubble = AnswerBubble()
    private let outline = AreaOutline()
    private lazy var history = History(prefs: prefs)
    private lazy var learn = LearnWindow(prefs: prefs, history: history)
    private lazy var reader = MathReader(prefs: prefs, access: access, bubble: bubble)
    private lazy var recorder = ShortcutRecorder(prefs: prefs, hotkeys: hotkeys)
    private lazy var director = DemoDirector(prefs: prefs, reader: reader, bubble: bubble, learn: learn, history: history)
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
        menu.addItem(NSMenuItem("History") { [weak self] in
            self?.learn.showHistory()
        })
    }, showSettings: { [weak self] in
        self?.settings.show()
    })
    private lazy var settings: SettingsWindow = SettingsWindow { [weak self] in
        guard let self else { return [] }
        return [
            .general(menuBar: menuBar, iconHiddenNote: "To get back here, open \(AppShell.name) again and click the gear at the top right."),
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
        // Each answer shown by the pointer goes into the history.
        bubble.onAnswer = { [weak self] content in
            guard let self else { return }
            switch content {
            case .answer(let sum, let answer, _, _, _):
                history.add(question: sum, answer: answer, input: History.readable(sum))
            case .list(let rows, _):
                for row in rows.reversed() { history.add(question: row.question, answer: row.answer, input: History.readable(row.question)) }
            default:
                break
            }
        }
        bubble.onCopyAvailable = { [weak self] available in
            // A README clip leaves ⌘C to whoever is using the Mac.
            self?.hotkeys.set(available && !DemoStage.isFilming ? .copy : nil, for: .copyAnswer)
        }
        learn.showSettings = { [weak self] in self?.settings.show() }
        settings.onResignedKey = { [weak self] in self?.recorder.stop() }
        settings.onClose = { [weak self] in self?.recorder.stop() }
        // A README clip is recorded off the screen, without a second icon in the menu bar.
        if !DemoStage.isFilming { menuBar.install() }
        update()

        if let scene = DemoScene.current {
            director.run(scene)
        } else if let scene = AppShell.demoScene {
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
        let canCapture = access.isAllowed && !DemoStage.isFilming
        Task.detached(priority: .utility) {
            await ScreenReader.warmUp(canCapture: canCapture)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            Task { await ScreenReader.shared.forgetScreens() }
        }
    }

    /// Opening MathPeek again (Finder, Spotlight) shows its window: the working as it was left,
    /// or the field for typing a problem. ⌘, there opens Settings, which matters when the menu
    /// bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        learn.open()
        return false
    }

    /// The demo (`-demo <scene>`), also used for README clips. "tour" opens the working window
    /// on its roadmap with a range of problems; "step", "part", "check", "try" and "zoom" show
    /// what the roadmap does; "graph" and "edit" its other views; "fractions", "remainder" and
    /// "problems" other problems; "bubble" and "bubble-list" show answers in the middle of the
    /// screen. Adding `-behind` opens the window behind the others.
    private func showDemoScene(_ scene: String) {
        func solve(_ text: String) -> Solution? { Parser.problem(text).flatMap { Engine.solve($0, angles: prefs.angles) } }
        let center = NSScreen.main.map { CGPoint(x: $0.frame.midX - 150, y: $0.frame.midY + 80) } ?? .zero
        let tour = ["x^3 - 6x^2 + 11x - 6 = 0", "h/6 + 2h/9", "2x + y = 7; x - y = 2",
                    "differentiate x^2 sin x", "∫ x^2 dx from 0 to 3", "sin x = 0.5", "2^2026 + 3^2026 mod 13"]
        let worksheet = ["2x + 3 = 11", "x^2 - 5x + 6 = 0", "3/4 + 5/6", "differentiate x^3 + 2x"]
        learn.opensBehind = CommandLine.arguments.contains("-behind")
        func route(_ selected: Int = 0) {
            learn.show(tour.compactMap(solve), selected: selected, angles: prefs.angles)
            learn.showDemo(tryFirst: nil, zoom: 1)
        }
        switch scene {
        case "tour":
            route()
        case "step":
            route()
            learn.showDemo(stop: 1)
        case "part":
            route()
            learn.showDemo(stop: 2, part: 1)
        case "check":
            route()
            learn.showDemo(answer: 1)
        case "try":
            route()
            learn.showDemo(tryFirst: 2)
        case "zoom":
            route()
            learn.showDemo(stop: 1, zoom: 1.5)
        case "graph":
            learn.show(tour.compactMap(solve), selected: 0, angles: prefs.angles, tab: .graph)
            learn.showDemo(answer: 1)
        case "edit":
            route()
            learn.beginTyping(prefilled: true)
        case "fractions":
            route(1)
        case "simultaneous":
            route(2)
        case "remainder":
            route(6)
            learn.showDemo(stop: 1)
        case let scene where scene.hasPrefix("open-"):
            // Opens a step of what's showing, or closes it ("open-none"), for filming.
            learn.openStop(Int(scene.dropFirst("open-".count)))
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

    /// Opens the working window with the field for typing a problem showing.
    private func typeProblem() {
        learn.beginTyping()
    }

    private func update() {
        menuBar.appearsDisabled = !prefs.isEnabled
        // A README clip presses the shortcut itself; the real one stays with the copy in use.
        hotkeys.set(prefs.isEnabled && !DemoStage.isFilming ? prefs.hotkey : nil, for: .read)
        if !prefs.isEnabled { reader.stop() }
    }
}
