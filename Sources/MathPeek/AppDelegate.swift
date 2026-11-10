import AppKit
import AppShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private let hotkeys = HotkeyCenter()
    private let access = ScreenAccess()
    private let bubble = AnswerBubble()
    private let outline = AreaOutline()
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
        bubble.onCopyAvailable = { [weak self] available in
            self?.hotkeys.set(available ? .copy : nil, for: .copyAnswer)
        }
        settings.onResignedKey = { [weak self] in self?.recorder.stop() }
        settings.onClose = { [weak self] in self?.recorder.stop() }
        menuBar.install()
        update()
    }

    /// Opening MathPeek again (Finder, Spotlight) shows Settings, which matters when the menu
    /// bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    private func update() {
        menuBar.appearsDisabled = !prefs.isEnabled
        hotkeys.set(prefs.isEnabled ? prefs.hotkey : nil, for: .read)
        if !prefs.isEnabled { reader.stop() }
    }
}
