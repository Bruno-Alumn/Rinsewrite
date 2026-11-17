import Combine
import SwiftUI

/// The settings window's pages, one per sidebar row (see MainWindow). Each is
/// a grouped Form of standard controls.
enum SettingsPage: String, CaseIterable, Identifiable {
    case rinse, shortcut, memory, general

    var id: Self { self }

    var title: String {
        switch self {
        case .rinse: "Rinse"
        case .shortcut: "Shortcut"
        case .memory: "Memory"
        case .general: "General"
        }
    }

    var sidebarSymbol: String {
        switch self {
        case .rinse: "drop.fill"
        case .shortcut: "keyboard.fill"
        case .memory: "memorychip.fill"
        case .general: "gearshape.fill"
        }
    }

    /// The same families System Settings uses: the icon's blue for the app's own
    /// work, green for resources, gray for the rest.
    var color: Color {
        switch self {
        case .rinse: .rinseBlue
        case .shortcut: .gray
        case .memory: .green
        case .general: .gray
        }
    }
}

struct SettingsPageView: View {
    let page: SettingsPage
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            switch page {
            case .rinse: RinsePage(state: state)
            case .shortcut: ShortcutPage(state: state)
            case .memory: MemoryPage(state: state)
            case .general: GeneralPage(state: state)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { state.refreshTrust() }
    }
}

/// Shown at the top of a page only when something needs fixing.
private struct AttentionSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        let status = state.status
        if status.needsAttention {
            Section {
                Label {
                    Text(status.title)
                    if let detail = status.detail { Text(detail) }
                } icon: {
                    Image(systemName: status.symbol)
                        .foregroundStyle(.orange)
                }
                if status == .needsAccess {
                    HStack {
                        Button("Reset…", action: confirmAccessibilityReset)
                        Button("Open System Settings") { Permissions.openSystemSettings() }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// Already switched on in System Settings but still not allowed: a stale
    /// entry macOS won't match to this build. Clearing it brings the prompt back.
    private func confirmAccessibilityReset() {
        let alert = NSAlert()
        alert.messageText = "Reset Accessibility Access?"
        alert.informativeText = "Use this when Rinsewrite is switched on in System Settings › Privacy & Security › Accessibility but still can't rinse. Rinsewrite is removed from that list, then asks to be allowed again."
        alert.addButton(withTitle: "Reset").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Permissions.reset()
    }
}

// MARK: - Rinse

private struct RinsePage: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            AttentionSection(state: state)

            Section {
                LevelSlider(title: "Grammar", value: $state.grammar, names: Levels.grammar,
                            low: "Leave mistakes", high: "Fully correct")
                LevelSlider(title: "Humanize", value: $state.humanize, names: Levels.humanize,
                            low: "Keep wording", high: "Casual, no AI tells")
            } footer: {
                formFooter(footer)
            }

            Section {
                Toggle("Rinse the whole field when nothing is selected", isOn: $state.wholeField)
            } footer: {
                formFooter("Press \(state.shortcut.display) anywhere you type. With this on, you don't need to select first: Rinsewrite selects the field for you.")
            }

            Section("Try It") {
                TryItField(state: state)
            }
        }
    }

    private var footer: String {
        let grammar: String = switch Levels.index(state.grammar, count: Levels.grammar.count) {
        case 0: "Minimal fixes only garbled words and leaves small, natural mistakes."
        case 1: "Light fixes spelling, apostrophes and wrong words, and keeps your lowercase style and slang."
        case 2: "Standard fixes spelling, grammar, punctuation and capitals, and keeps slang like u and lol."
        case 3: "Polished also writes out abbreviations and smooths awkward phrasing."
        default: "Formal turns it into complete, correct sentences without slang."
        }
        return grammar + " English, Spanish and French; your language never changes."
    }
}

// MARK: - Shortcut

private struct ShortcutPage: View {
    @ObservedObject var state: AppState
    @State private var refusal: String?

    var body: some View {
        Form {
            AttentionSection(state: state)
            Section {
                LabeledContent("Rinse text") {
                    ShortcutRecorder(state: state, refusal: $refusal)
                }
            } footer: {
                if let refusal {
                    formFooter(refusal)
                } else if state.shortcutTaken {
                    formFooter("Another app already uses \(state.shortcut.display). Choose different keys.")
                } else {
                    formFooter("Works in any app, with text selected or not. Undo with ⌘Z in that app.")
                }
            }
        }
    }
}

// MARK: - Memory

private struct MemoryPage: View {
    @ObservedObject var state: AppState
    @State private var memoryMB: Int?

    var body: some View {
        Form {
            AttentionSection(state: state)
            Section {
                LabeledContent("Language model", value: "LFM3 1.7B, 4-bit, on this Mac")
                LabeledContent("Memory in use", value: memoryMB.map { "\($0) MB" } ?? "Not running")
                LabeledContent("Status", value: state.status.title)
            }
            Section {
                Picker("Free memory when idle", selection: $state.idleUnloadMinutes) {
                    Text("Never").tag(0)
                    Text("After 5 Minutes").tag(5)
                    Text("After 10 Minutes").tag(10)
                    Text("After 30 Minutes").tag(30)
                    Text("After 1 Hour").tag(60)
                }
                HStack {
                    Spacer()
                    Button("Free Memory Now") { state.freeMemory() }
                        .disabled(state.engineState != .ready)
                }
            } footer: {
                formFooter("While loaded the model uses about 1.5 GB. Freed, Rinsewrite uses about 0.3 GB, and the next rinse takes about 1.5 seconds while the model loads again.")
            }
        }
        .task {
            while !Task.isCancelled {
                let mb = state.engineMemoryMB()
                if mb != memoryMB { memoryMB = mb }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            AttentionSection(state: state)
            Section {
                Toggle("Open Rinsewrite at login", isOn: $state.opensAtLogin)
                LabeledContent("Accessibility access") {
                    if state.accessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Open System Settings") { Permissions.openSystemSettings() }
                    }
                }
            }
            Section {
                LabeledContent("Version", value: Self.version)
                HStack {
                    Button("Show Welcome Window") { WelcomeWindow.shared.show() }
                    Spacer()
                    Button("Open Log") { NSWorkspace.shared.open(EngineClient.logURL) }
                    Button("Report a Problem…", action: report)
                }
            }
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// A new GitHub issue with the versions filled in.
    private func report() {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = "**Rinsewrite** \(Self.version), macOS \(os)\n\n**What happened:**\n\n**What you expected:**\n"
        var url = URLComponents(string: "https://github.com/Bruno-Alumn/Rinsewrite/issues/new")!
        url.queryItems = [URLQueryItem(name: "body", value: body)]
        if let link = url.url { NSWorkspace.shared.open(link) }
    }
}
