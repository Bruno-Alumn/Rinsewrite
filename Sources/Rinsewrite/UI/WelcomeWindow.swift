import AppKit
import SwiftUI

/// Shown on first launch until the user clicks Done (or closes it). It covers
/// what a menu bar app can't show on its own: that it lives in the menu
/// bar, the shortcut, and that it needs Accessibility access.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private nonisolated static let finishedKey = "hasFinishedWelcome"
    private var window: NSWindow?

    nonisolated static func isNeeded(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: finishedKey)
    }

    func show(askingForAccess: Bool = false) {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.setContentSize(window.contentViewController?.view.fittingSize ?? window.frame.size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // macOS's Accessibility prompt, after the window: asked any earlier,
        // the window opens over it and hides its buttons.
        if askingForAccess && !Permissions.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = Permissions.requestIfNeeded()
                NSApp.deactivate()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: WelcomeView(state: AppState.shared) { [weak self] in
            self?.window?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to Rinsewrite"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.finishedKey)
        MainWindow.backToMenuBar(closing: notification.object as? NSWindow)
    }
}

struct WelcomeView: View {
    @ObservedObject var state: AppState
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("Welcome to Rinsewrite")
                        .font(.title2.bold())
                    Text("Clean up anything you type with one shortcut.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)

            Form {
                Section {
                    LabeledContent {
                        if state.accessibilityTrusted {
                            Label {
                                Text("Allowed")
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Button("Open System Settings") { Permissions.openSystemSettings() }
                                .buttonStyle(.borderedProminent)
                        }
                    } label: {
                        Label { Text("Accessibility access") } icon: {
                            SettingsIcon(symbol: "accessibility", color: .blue)
                        }
                    }
                } footer: {
                    formFooter("Rinsewrite needs this to copy your text and paste the rinsed version back. Nothing you type leaves your Mac.")
                }

                Section {
                    LabeledContent {
                        Text(state.shortcut.display)
                            .font(.body.monospaced())
                    } label: {
                        Label { Text("Rinse text") } icon: {
                            SettingsIcon(symbol: SettingsPage.shortcut.sidebarSymbol, color: SettingsPage.shortcut.color)
                        }
                    }
                    LabeledContent {
                        Text(state.status.canRinse ? "Ready" : state.status.title)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label { Text("Language model") } icon: {
                            SettingsIcon(symbol: SettingsPage.memory.sidebarSymbol, color: SettingsPage.memory.color)
                        }
                    }
                } footer: {
                    formFooter("Select text, or click into a text field, and press \(state.shortcut.display). Undo with ⌘Z.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Rinsewrite lives in the menu bar.")
                    .foregroundStyle(.secondary)
                Spacer()
                if state.accessibilityTrusted {
                    Button("Done", action: done)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: done)
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .onAppear { state.refreshTrust() }
    }
}
