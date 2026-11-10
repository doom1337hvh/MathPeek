import SwiftUI

/// The MathPeek tab of Settings, between General and About.
struct MainSettings: View {
    @Bindable var prefs: Preferences
    let hotkeys: HotkeyCenter
    let recorder: ShortcutRecorder
    let access: ScreenAccess
    let outline: AreaOutline

    var body: some View {
        Section {
            Toggle(isOn: $prefs.isEnabled) {
                Text("Turn on MathPeek")
                Text("Press the shortcut over a sum, in any app, to see its answer by the pointer.")
            }
            LabeledContent {
                ShortcutField(hotkey: prefs.hotkey, isUnavailable: hotkeys.isReadUnavailable,
                              recorder: recorder) { prefs.hotkey = nil }
            } label: {
                Text("Shortcut")
                Text(recorder.isRecording ? recorder.hint ?? "Press the keys. Esc cancels; Delete clears it."
                                          : "Click it, then press the keys you want.")
            }
        }
        .onAppear { access.watchUntilAllowed() }

        Section {
            Picker(selection: $prefs.areaMode) {
                ForEach(AreaMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Text("Area")
                Text(prefs.areaMode == .aroundPointer
                     ? "It works out the sum nearest the pointer within this area."
                     : "The shortcut dims the screen: drag over the sum, or click to read around that point. Esc cancels.")
            }
            if prefs.areaMode == .aroundPointer {
                SizeSlider(title: "Width", value: $prefs.areaWidth, range: Preferences.widthRange)
                SizeSlider(title: "Height", value: $prefs.areaHeight, range: Preferences.heightRange)
            }
        } header: {
            Text("What it reads")
        } footer: {
            if prefs.areaMode == .aroundPointer {
                Text("While you change the size, an outline of it follows the pointer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: prefs.areaWidth) { outline.flash(width: prefs.areaWidth, height: prefs.areaHeight) }
        .onChange(of: prefs.areaHeight) { outline.flash(width: prefs.areaWidth, height: prefs.areaHeight) }

        Section("Answer") {
            Picker(selection: $prefs.answerSeconds) {
                ForEach(Preferences.answerSecondsChoices, id: \.self) { seconds in
                    Text("\(Int(seconds)) seconds").tag(seconds)
                }
            } label: {
                Text("Keep it on screen for")
                Text("It stays while the pointer is on it. Click it, or press ⌘C while it shows, to copy it.")
            }
        }

        Section("Permission") {
            LabeledContent {
                if access.isAllowed {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Open System Settings") { access.openSettings() }
                }
            } label: {
                Text("Screen Recording")
                Text("To see the text in the area it reads, only when you press the shortcut. It's read on this Mac and never saved.")
            }
        }
    }
}

private struct SizeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                // Rounded by hand: a stepped slider draws a tick for every step.
                Slider(value: Binding(get: { value }, set: { value = ($0 / 10).rounded() * 10 }), in: range)
                Text("\(Int(value)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            .frame(width: 260)
        }
    }
}

/// Shows the shortcut; click it to record a new one.
private struct ShortcutField: View {
    let hotkey: Hotkey?
    let isUnavailable: Bool
    let recorder: ShortcutRecorder
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isUnavailable && !recorder.isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Another app already uses this shortcut, so macOS won't give it to MathPeek.")
            }
            Button {
                if recorder.isRecording { recorder.stop() } else { recorder.start() }
            } label: {
                Text(recorder.isRecording ? "Press keys…" : hotkey?.display ?? "Record Shortcut")
                    .frame(minWidth: 110)
            }
            if hotkey != nil && !recorder.isRecording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
    }
}
