import SwiftUI

/// The menu bar menu: a standard macOS menu. What Rinsewrite is doing comes
/// first, then the two sliders people change day to day. Everything else
/// is in Settings.
struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let status = state.status
        Text(status.title)
        if status == .needsAccess {
            Button("Open System Settings") { Permissions.openSystemSettings() }
        }
        if status.needsAttention, status != .needsAccess {
            Button("What's Wrong?") { explain(status) }
        }
        Divider()

        Button("Rinse Text  (\(state.shortcut.display))") {
            // The menu closes first and the app in front gets its focus back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { state.rinse() }
        }
        .disabled(!status.canRinse)
        Toggle("Rinse Whole Field When Nothing Is Selected", isOn: $state.wholeField)
        Divider()

        // The sliders are AppKit items added under these headings when the
        // menu opens; see MenuSliderItem.
        Text(MenuSliderItem.grammar.heading)
        Text(MenuSliderItem.humanize.heading)
        Divider()

        Button("Settings…") { MainWindow.shared.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Rinsewrite") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The full explanation in a standard alert; a menu item can't hold it.
    private func explain(_ status: Status) {
        let alert = NSAlert()
        alert.messageText = status.title
        alert.informativeText = status.detail ?? ""
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
