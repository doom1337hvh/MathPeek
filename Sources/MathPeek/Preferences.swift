import AppShell
import Foundation
import Observation

/// How MathPeek picks the part of the screen it reads.
enum AreaMode: String, CaseIterable, Identifiable {
    /// A rectangle of a set size, centred on the pointer.
    case aroundPointer
    /// The shortcut dims the screen and you drag out the area, as for a screenshot.
    case drag

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aroundPointer: "Around the pointer"
        case .drag: "An area I drag out"
        }
    }
}

@Observable @MainActor
final class Preferences {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let hotkey = "hotkey"
        static let areaMode = "areaMode"
        static let areaWidth = "areaWidth"
        static let areaHeight = "areaHeight"
        static let answerSeconds = "answerSeconds"
        static let askedForScreenRecording = "askedForScreenRecording"
        static let angles = "angles"
        static let useAppleIntelligence = "useAppleIntelligence"
        static let windowTranslucency = "windowTranslucency"
    }

    static let widthRange: ClosedRange<Double> = 200...1600
    static let heightRange: ClosedRange<Double> = 40...800
    static let answerSecondsChoices: [Double] = [3, 5, 10]
    static let translucencyRange: ClosedRange<Double> = 0...0.9

    @ObservationIgnored var onEnabledChange: (() -> Void)?
    @ObservationIgnored var onHotkeyChange: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        didSet {
            save(isEnabled, Key.isEnabled)
            onEnabledChange?()
        }
    }

    /// The shortcut that reads the maths, or none. ⌃⌥= until it's changed.
    var hotkey: Hotkey? {
        didSet {
            // Empty means cleared, as opposed to never set.
            save(hotkey.flatMap { try? JSONEncoder().encode($0) } ?? Data(), Key.hotkey)
            onHotkeyChange?()
        }
    }

    var areaMode: AreaMode {
        didSet { save(areaMode.rawValue, Key.areaMode) }
    }

    /// The size of the area read around the pointer, in points.
    var areaWidth: Double {
        didSet { save(areaWidth, Key.areaWidth) }
    }

    var areaHeight: Double {
        didSet { save(areaHeight, Key.areaHeight) }
    }

    /// How long an answer stays by the pointer, unless the pointer is on it.
    var answerSeconds: Double {
        didSet { save(answerSeconds, Key.answerSeconds) }
    }

    /// Degrees or radians for sin, cos and tan. Calculus always uses radians.
    var angles: AngleUnit {
        didSet { save(angles.rawValue, Key.angles) }
    }

    /// Ask Apple Intelligence, on this Mac, about maths laid out over several lines and word
    /// problems.
    var useAppleIntelligence: Bool {
        didSet { save(useAppleIntelligence, Key.useAppleIntelligence) }
    }

    /// How see-through the working window is: 0 is solid, 0.9 nearly clear.
    var windowTranslucency: Double {
        didSet { save(windowTranslucency, Key.windowTranslucency) }
    }

    /// Whether macOS has shown its Screen Recording prompt; it only ever does once.
    var askedForScreenRecording: Bool {
        didSet { save(askedForScreenRecording, Key.askedForScreenRecording) }
    }

    init() {
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.areaMode: AreaMode.aroundPointer.rawValue,
            Key.areaWidth: 700.0,
            Key.areaHeight: 200.0,
            Key.answerSeconds: 5.0,
            Key.askedForScreenRecording: false,
            Key.angles: AngleUnit.degrees.rawValue,
            Key.useAppleIntelligence: true,
            Key.windowTranslucency: 0.55,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        if let data = defaults.data(forKey: Key.hotkey) {
            hotkey = data.isEmpty ? nil : (try? JSONDecoder().decode(Hotkey.self, from: data)) ?? .standard
        } else {
            hotkey = .standard
        }
        areaMode = AreaMode(rawValue: defaults.string(forKey: Key.areaMode) ?? "") ?? .aroundPointer
        areaWidth = Self.widthRange.clamp(defaults.double(forKey: Key.areaWidth))
        areaHeight = Self.heightRange.clamp(defaults.double(forKey: Key.areaHeight))
        let seconds = defaults.double(forKey: Key.answerSeconds)
        answerSeconds = Self.answerSecondsChoices.contains(seconds) ? seconds : 5
        askedForScreenRecording = defaults.bool(forKey: Key.askedForScreenRecording)
        angles = AngleUnit(rawValue: defaults.string(forKey: Key.angles) ?? "") ?? .degrees
        useAppleIntelligence = defaults.bool(forKey: Key.useAppleIntelligence)
        windowTranslucency = Self.translucencyRange.clamp(defaults.double(forKey: Key.windowTranslucency))
    }

    /// A README clip (`-demo <scene>`) changes settings on screen, but never saves them.
    private func save(_ value: Any, _ key: String) {
        guard AppShell.demoScene == nil else { return }
        defaults.set(value, forKey: key)
    }
}

extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
