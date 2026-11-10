import AppKit
import Carbon.HIToolbox
import Observation

/// What a global keyboard shortcut does.
enum HotkeyAction: UInt32, CaseIterable {
    /// Read the maths by the pointer: the shortcut people choose.
    case read = 1
    /// ⌘C, only while an answer is showing, to copy it.
    case copyAnswer = 2
}

/// A key with modifiers, as recorded in Settings.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, ...).
    var modifiers: UInt32
    /// The key as shown, e.g. "M" or "Space".
    var keyName: String

    init(keyCode: Int, modifiers: Int, keyName: String) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.keyName = keyName
    }

    /// ⌃⌥=
    static let standard = Hotkey(keyCode: kVK_ANSI_Equal, modifiers: controlKey | optionKey, keyName: "=")
    static let copy = Hotkey(keyCode: kVK_ANSI_C, modifiers: cmdKey, keyName: "C")

    /// Nil unless the key is held with ⌘, ⌥ or ⌃, or is a function key: on its own, a
    /// letter would stop typing it anywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        let keyCode = Int(event.keyCode)
        guard Self.functionKeys[keyCode] != nil || !flags.intersection([.command, .option, .control]).isEmpty
        else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
        keyName = Self.functionKeys[keyCode] ?? Self.specialKeys[keyCode]
            ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "?"
    }

    /// Like "⌃⌥=", in the order the menus use.
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

/// Registers the keyboard shortcuts with macOS. Carbon hotkeys work in every app without
/// any permission, and cost nothing until pressed.
@Observable @MainActor
final class HotkeyCenter {
    /// Whether macOS wouldn't take the read shortcut, usually because another app has it.
    private(set) var isReadUnavailable = false
    /// Off while a shortcut is being recorded, so pressing the current one records it
    /// instead of running it.
    var isSuspended = false {
        didSet { if isSuspended != oldValue { HotkeyAction.allCases.forEach(apply) } }
    }

    @ObservationIgnored var onAction: ((HotkeyAction) -> Void)?
    @ObservationIgnored private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @ObservationIgnored private var registered: [HotkeyAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?

    /// "MPek"
    nonisolated private static let signature: OSType = 0x4D50_656B

    /// Sets the shortcut for `action`, or none.
    func set(_ hotkey: Hotkey?, for action: HotkeyAction) {
        guard hotkeys[action] != hotkey else { return }
        hotkeys[action] = hotkey
        apply(action)
    }

    private func apply(_ action: HotkeyAction) {
        if let ref = registered.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        var failed = false
        if !isSuspended, let hotkey = hotkeys[action] {
            installHandler()
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[action] = ref
            } else {
                failed = true
            }
        }
        if action == .read, failed != isReadUnavailable { isReadUnavailable = failed }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(context).takeUnretainedValue()
            let actionID = id.id
            // Carbon delivers hotkeys on the main thread.
            MainActor.assumeIsolated { center.fire(actionID) }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func fire(_ id: UInt32) {
        guard let action = HotkeyAction(rawValue: id) else { return }
        onAction?(action)
    }
}

/// Records the shortcut in Settings: click the field, then press the keys. Escape cancels;
/// Delete clears the shortcut.
@Observable @MainActor
final class ShortcutRecorder {
    private(set) var isRecording = false
    /// Why the last keys pressed weren't taken.
    private(set) var hint: String?

    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private let hotkeys: HotkeyCenter
    @ObservationIgnored private var monitor: Any?

    init(prefs: Preferences, hotkeys: HotkeyCenter) {
        self.prefs = prefs
        self.hotkeys = hotkeys
    }

    func start() {
        stop()
        isRecording = true
        hint = nil
        hotkeys.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let used = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return used ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        hotkeys.isSuspended = false
    }

    /// Returns whether the key press was used, so it doesn't also reach the window.
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty && Int(event.keyCode) == kVK_Escape {
            stop()
            return true
        }
        if flags.isEmpty && [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode)) {
            prefs.hotkey = nil
            stop()
            return true
        }
        guard let hotkey = Hotkey(event: event) else {
            hint = "Hold ⌘, ⌥ or ⌃ with the key, or use a function key."
            NSSound.beep()
            return true
        }
        guard hotkey != .copy else {
            hint = "⌘C copies the answer while it shows. Choose another shortcut."
            NSSound.beep()
            return true
        }
        prefs.hotkey = hotkey
        hint = nil
        stop()
        return true
    }
}
