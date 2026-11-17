import SwiftUI

@main
struct RinsewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            Image(nsImage: state.status.canRinse || state.status == .rinsing ? MenuBarIcon.ready : MenuBarIcon.waiting)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(index + 1) {
            Snapshot.run(into: CommandLine.arguments[index + 1])
            return
        }
        let state = AppState.shared
        state.startUp()
        MenuSliderItem.grammar.install()
        MenuSliderItem.humanize.install()
        if CommandLine.arguments.contains("--health-check") { return }
        // New installs get the welcome window (Accessibility access, the
        // shortcut) until they finish it. Otherwise start in the menu bar.
        if WelcomeWindow.isNeeded() {
            WelcomeWindow.shared.show(askingForAccess: true)
        } else if !Permissions.isTrusted {
            MainWindow.shared.show(.general)
        }
    }

    /// Opening Rinsewrite again (Finder, Launchpad, Spotlight) while it's
    /// running brings up the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutDown()
    }
}

/// Renders the settings window's pages to PNGs, in light and dark, for the
/// README: `Rinsewrite --snapshot docs/screenshots`. Only the page itself:
/// the Liquid Glass sidebar is composited by the window server and doesn't
/// appear in an off-screen render.
@MainActor
enum Snapshot {
    static func run(into directory: String) {
        let state = AppState.shared
        state.showReadyForSnapshot()
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for page in [SettingsPage.rinse] {
                let host = NSHostingController(rootView: SettingsPageView(page: page, state: state)
                    .frame(width: 560, height: 430))
                let window = NSWindow(contentViewController: host)
                window.isReleasedWhenClosed = false
                window.styleMask = [.titled, .closable, .fullSizeContentView]
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(NSSize(width: 560, height: 430))
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderFrontRegardless()
                window.makeKey()
                RunLoop.main.run(until: Date().addingTimeInterval(1.0))
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = url.appendingPathComponent("\(page.rawValue)-\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
                print(file.path)
                window.close()
            }
        }
        NSApp.terminate(nil)
    }
}
