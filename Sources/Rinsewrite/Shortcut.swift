import AppKit

/// The key combination that rinses the text you're typing.
struct Shortcut: Codable, Equatable {
    let keyCode: UInt16
    /// NSEvent.ModifierFlags raw value, limited to ⌃ ⌥ ⇧ ⌘.
    let modifiers: UInt
    /// The key as shown, e.g. "R" or "Space".
    let key: String

    /// ⌥Space: rarely bound, and one hand reaches it mid-sentence.
    static let standard = Shortcut(keyCode: 49, flags: [.option], key: "Space")
    private static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Self.relevant).rawValue
        self.key = key
    }

    /// A recorded key press, or nil if it would get in the way.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevant)
        guard Self.isAllowed(flags, keyCode: event.keyCode) else { return nil }
        self.init(keyCode: event.keyCode, flags: flags, key: Self.name(for: event))
    }

    /// The shortcut is owned system-wide, so it needs ⌃, or ⌘ with ⌥: plain
    /// or ⇧ keys fire while typing, and ⌘ alone is an app command. ⌥Space is
    /// the one ⌥-only exception: it types a non-breaking space, which almost
    /// no one types on purpose.
    static func isAllowed(_ flags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        if flags.contains(.control) || flags.isSuperset(of: [.command, .option]) { return true }
        return keyCode == 49 && flags.contains(.option) && !flags.contains(.command)
    }

    static let requirement = "Use ⌃, ⌘ with ⌥, or ⌥Space, so it doesn't clash with typing or app commands."

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// "⌥Space", modifiers in the order macOS menus use.
    var display: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key
    }

    /// What VoiceOver reads: "Option Space".
    var spoken: String {
        let names: [(NSEvent.ModifierFlags, String)] = [(.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")]
        return (names.filter { flags.contains($0.0) }.map(\.1) + [key]).joined(separator: " ")
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func name(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters
    }
}
