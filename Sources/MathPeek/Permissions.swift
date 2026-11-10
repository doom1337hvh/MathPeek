import AppKit
import CoreGraphics
import Observation

/// MathPeek needs one permission: Screen Recording, to see the area around the pointer it
/// reads. It's asked for the first time the shortcut is pressed.
@Observable @MainActor
final class ScreenAccess {
    private(set) var isAllowed = CGPreflightScreenCaptureAccess()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var stopWatchingAt = Date.distantPast

    func refresh() {
        let allowed = CGPreflightScreenCaptureAccess()
        if allowed != isAllowed { isAllowed = allowed }
    }

    /// Shows macOS's own prompt, which also puts MathPeek in the list in System Settings.
    /// macOS only ever shows it once.
    func request() {
        CGRequestScreenCaptureAccess()
        watchUntilAllowed()
    }

    /// Opens Privacy & Security › Screen & System Audio Recording in System Settings.
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        watchUntilAllowed()
    }

    /// Checks every second for a few minutes while it's missing, so Settings shows the change.
    func watchUntilAllowed() {
        refresh()
        guard !isAllowed else { return }
        stopWatchingAt = Date().addingTimeInterval(300)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                if self.isAllowed || Date() > self.stopWatchingAt {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }
}
