import Foundation

/// What Rinsewrite is doing, in the words the menu's first line and the
/// settings window both use, so they always agree.
enum Status: Equatable {
    case needsAccess
    case notInstalled
    case loading
    case ready(note: String?)
    case rinsing
    case unloaded
    case failed(String)

    var title: String {
        switch self {
        case .needsAccess: "Needs Accessibility access"
        case .notInstalled: "Engine not installed"
        case .loading: "Loading the language model…"
        case .ready(let note): note.map { "Ready — \($0)" } ?? "Ready"
        case .rinsing: "Rinsing…"
        case .unloaded: "Ready — model unloaded to save memory"
        case .failed: "The engine stopped"
        }
    }

    var detail: String? {
        switch self {
        case .needsAccess:
            "Rinsewrite copies your text and pastes the rinsed version back, which macOS allows only with Accessibility access."
        case .notInstalled:
            "Run make engine in the Rinsewrite folder. It installs MLX and downloads the model, about 1 GB, once."
        case .unloaded:
            "The next rinse takes about 1.5 seconds while the model loads again."
        case .failed(let message): message
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .needsAccess: "lock.fill"
        case .notInstalled, .failed: "exclamationmark.triangle.fill"
        case .loading, .rinsing: "hourglass"
        case .ready, .unloaded: "checkmark.circle.fill"
        }
    }

    /// Settings shows a banner only for these.
    var needsAttention: Bool {
        switch self {
        case .needsAccess, .notInstalled, .failed: true
        default: false
        }
    }

    var canRinse: Bool {
        switch self {
        case .ready, .unloaded: true
        default: false
        }
    }
}

/// The slider steps and their names. The engine maps each 0…1 value to
/// the nearest step.
enum Levels {
    static let grammar = ["Minimal", "Light", "Standard", "Polished", "Formal"]
    static let humanize = ["Off", "Natural", "Casual"]

    static func name(_ value: Double, in names: [String]) -> String {
        names[index(value, count: names.count)]
    }

    static func index(_ value: Double, count: Int) -> Int {
        min(max(Int((min(max(value, 0), 1) * Double(count - 1)).rounded()), 0), count - 1)
    }

    static func value(_ index: Int, count: Int) -> Double {
        Double(index) / Double(count - 1)
    }
}
