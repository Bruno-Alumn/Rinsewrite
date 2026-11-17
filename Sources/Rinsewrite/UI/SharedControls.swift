import SwiftUI

/// Controls used in the settings and welcome windows that SwiftUI doesn't
/// provide as is.

/// Section footer text in the standard footnote style, leading-aligned as
/// in System Settings.
func formFooter(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// A stepped slider with the current step's name beside its title, and
/// what each end means under it.
struct LevelSlider: View {
    let title: String
    @Binding var value: Double
    let names: [String]
    let low: String
    let high: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(Levels.name(value, in: names))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: Binding(
                get: { value },
                set: {
                    let snapped = Levels.value(Levels.index($0, count: names.count), count: names.count)
                    if snapped != value { value = snapped }
                }
            ), in: 0...1, step: 1 / Double(names.count - 1)) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
            .accessibilityValue(Levels.name(value, in: names))
        }
    }
}

/// A field to try the current settings without leaving the window. What's
/// typed isn't kept.
struct TryItField: View {
    @ObservedObject var state: AppState
    @State private var text = ""
    @State private var result: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Try it", text: $text, prompt: Text("Type something messy, like “i dont thinl so tbh”"))
                    .labelsHidden()
                    .onSubmit(run)
                Button("Rinse", action: run)
                    .disabled(text.isEmpty || busy || !state.status.canRinse)
            }
            if let result {
                Text(result)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func run() {
        guard !text.isEmpty, !busy else { return }
        busy = true
        state.rinsePreview(text) { rinsed in
            result = rinsed
            busy = false
        }
    }
}

/// Records a new shortcut: click, then press the keys. Esc cancels.
struct ShortcutRecorder: View {
    @ObservedObject var state: AppState
    @Binding var refusal: String?
    var title = "Rinse text"
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if monitor == nil && state.shortcut != .standard {
                Button {
                    state.shortcut = .standard
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Reset to \(Shortcut.standard.display)")
                .accessibilityLabel("Reset Shortcut for \(title)")
            }
            Button {
                monitor == nil ? start() : stop()
            } label: {
                Text(monitor == nil ? state.shortcut.display : "Press keys…")
                    .frame(minWidth: 76)
            }
            .accessibilityLabel(monitor == nil ? title : "Recording \(title)")
            .accessibilityValue(monitor == nil ? state.shortcut.spoken : "Press the new keys")
        }
        .onDisappear { stop() }
        // Recording releases the shortcut; don't leave it off while the
        // user is in another app, where key presses never reach the recorder.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stop()
        }
    }

    private func start() {
        refusal = nil
        state.pauseHotKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
            } else if let recorded = Shortcut(event: event) {
                state.shortcut = recorded
                stop()
            } else if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                NSSound.beep()
                refusal = Shortcut.requirement
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        state.pauseHotKey(false)
    }
}
