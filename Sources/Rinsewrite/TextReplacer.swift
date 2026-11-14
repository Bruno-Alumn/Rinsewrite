import AppKit
import Carbon.HIToolbox

/// Copies the text you're working on with ⌘C and puts the rinsed version
/// back with ⌘V, then restores whatever was on your clipboard before.
enum TextReplacer {
    /// Every item and type on the clipboard, so it can be put back as it was.
    struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func take() -> ClipboardSnapshot {
            let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
                var types: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types { if let data = item.data(forType: type) { types[type] = data } }
                return types
            }
            return ClipboardSnapshot(items: items)
        }

        func restore() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let objects: [NSPasteboardItem] = items.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            }
            if !objects.isEmpty { pasteboard.writeObjects(objects) }
        }
    }

    // A private event source, so the shortcut's own held keys (⌥) don't
    // leak into the ⌘C and ⌘V Rinsewrite presses.
    private static let source = CGEventSource(stateID: .privateState)

    private static func pressCommand(_ key: Int) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Copies the selection. With nothing selected and `wholeField` on, it
    /// presses ⌘A first, so the whole text field gets rinsed. Calls back on
    /// the main queue with the text, or nil if there was nothing to copy.
    static func copy(wholeField: Bool, completion: @escaping (String?, ClipboardSnapshot) -> Void) {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.take()

        func copyOnce(timeout: TimeInterval, then: @escaping (String?) -> Void) {
            let before = pasteboard.changeCount
            pressCommand(kVK_ANSI_C)
            let deadline = Date().addingTimeInterval(timeout)
            func poll() {
                if pasteboard.changeCount != before {
                    then(pasteboard.string(forType: .string))
                } else if Date() > deadline {
                    then(nil)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.005, execute: poll)
                }
            }
            poll()
        }

        // Apps update the clipboard within a few tens of milliseconds, so
        // with whole-field rinsing on, a short wait means nothing was selected.
        copyOnce(timeout: wholeField ? 0.15 : 0.35) { text in
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(text, snapshot)
                return
            }
            guard wholeField else { return completion(nil, snapshot) }
            pressCommand(kVK_ANSI_A)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                copyOnce(timeout: 0.35) { completion($0, snapshot) }
            }
        }
    }

    /// Pastes over the selection that's still active, then restores the clipboard.
    static func paste(_ text: String, restoring snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Transient, so clipboard managers don't keep it.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pressCommand(kVK_ANSI_V)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { snapshot.restore() }
    }
}
