import AppKit
import ApplicationServices

/// Accessibility access, which Rinsewrite needs to copy your text and put
/// the rinsed version back (it presses ⌘C and ⌘V for you).
enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestIfNeeded() -> Bool {
        // `make test` launches a copy for a health check; no prompt for it.
        if CommandLine.arguments.contains("--health-check") { return isTrusted }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// For when the switch in System Settings is on but macOS still doesn't
    /// trust this build: forget the stale entry and ask again.
    static func reset() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", id]
        try? task.run()
        task.waitUntilExit()
        requestIfNeeded()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
