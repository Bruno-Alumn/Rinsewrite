import AppKit
import Combine
import ServiceManagement

/// Settings, the engine and the rinse itself. The menu and the settings
/// window both read `status`.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let engine = EngineClient()
    private let defaults = UserDefaults.standard

    @Published var grammar: Double { didSet { defaults.set(grammar, forKey: "grammar"); slidersChanged() } }
    @Published var humanize: Double { didSet { defaults.set(humanize, forKey: "humanize"); slidersChanged() } }
    /// With nothing selected, select the whole field (⌘A) and rinse all of it.
    @Published var wholeField: Bool { didSet { defaults.set(wholeField, forKey: "wholeField") } }
    /// Minutes without a rinse before the model is unloaded; 0 means never.
    @Published var idleUnloadMinutes: Int { didSet { defaults.set(idleUnloadMinutes, forKey: "idleUnloadMinutes"); resetIdleTimer() } }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut")
            registerHotKey()
        }
    }

    @Published private(set) var accessibilityTrusted = Permissions.isTrusted
    @Published private(set) var engineState: EngineClient.State = .starting
    @Published private(set) var rinsing = false
    @Published private(set) var note: String?
    @Published private(set) var shortcutTaken = false

    private var hotKey: GlobalHotKey?
    private var idleTimer: Timer?
    private var trustTimer: Timer?
    private var warmWork: DispatchWorkItem?
    private var noteWork: DispatchWorkItem?
    private var pinnedForSnapshot = false

    static let maxCharacters = 6000

    private init() {
        Self.migrateFromTextFix()
        grammar = defaults.object(forKey: "grammar") as? Double ?? 0.5
        humanize = defaults.object(forKey: "humanize") as? Double ?? 0.5
        wholeField = defaults.object(forKey: "wholeField") as? Bool ?? true
        idleUnloadMinutes = defaults.integer(forKey: "idleUnloadMinutes")
        if let data = defaults.data(forKey: "shortcut"), let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .standard
        }
    }

    var status: Status {
        if !accessibilityTrusted { return .needsAccess }
        if rinsing { return .rinsing }
        switch engineState {
        case .notInstalled: return .notInstalled
        case .starting: return .loading
        case .unloaded: return .unloaded
        case .failed(let message): return .failed(message)
        case .ready: return .ready(note: note)
        }
    }

    func startUp() {
        engine.onStateChange = { [weak self] state in
            self?.engineState = state
            if state == .ready { self?.resetIdleTimer() }
        }
        if CommandLine.arguments.contains("--health-check") {
            engineState = .notInstalled
        } else {
            engine.start(grammar: grammar, humanize: humanize)
        }
        registerHotKey()
        // macOS doesn't announce a new Accessibility grant; check until it arrives.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrust() }
        }
    }

    func shutDown() { engine.stop() }

    /// For `--snapshot`: shows the window as it looks once everything is set up.
    func showReadyForSnapshot() {
        pinnedForSnapshot = true
        engineState = .ready
        accessibilityTrusted = true
    }

    func refreshTrust() {
        guard !pinnedForSnapshot else { return }
        let trusted = Permissions.isTrusted
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
    }

    private func registerHotKey() {
        hotKey = nil
        hotKey = GlobalHotKey(shortcut) { [weak self] in
            DispatchQueue.main.async { self?.rinse() }
        }
        shortcutTaken = hotKey == nil
    }

    /// While a recorder listens, the shortcut is released so its keys can be recorded.
    func pauseHotKey(_ paused: Bool) {
        if paused { hotKey = nil } else { registerHotKey() }
    }

    // MARK: Rinsing

    /// Rinse the selection (or the whole field) in the app in front.
    func rinse() {
        guard !rinsing else { return }
        refreshTrust()
        guard accessibilityTrusted else {
            Permissions.requestIfNeeded()
            return
        }
        guard status.canRinse else { return fail(status.title) }
        rinsing = true
        let started = Date()
        TextReplacer.copy(wholeField: wholeField) { [weak self] text, snapshot in
            guard let self else { return }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                snapshot.restore()
                return self.fail(self.wholeField ? "No text found here" : "Nothing selected")
            }
            guard text.count <= Self.maxCharacters else {
                snapshot.restore()
                return self.fail("Too long to rinse: \(text.count) characters, \(Self.maxCharacters) at most")
            }
            self.engine.rinse(text, grammar: self.grammar, humanize: self.humanize) { result in
                switch result {
                case .success(let rinsed):
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    if rinsed != text {
                        TextReplacer.paste(rinsed, restoring: snapshot) { self.finish(note: "rinsed in \(ms) ms") }
                    } else {
                        snapshot.restore()
                        self.finish(note: "nothing to change (\(ms) ms)")
                    }
                case .failure(let error):
                    snapshot.restore()
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    /// Rinses text typed into the settings window's Try It field.
    func rinsePreview(_ text: String, completion: @escaping (String) -> Void) {
        engine.rinse(text, grammar: grammar, humanize: humanize) { result in
            switch result {
            case .success(let rinsed): completion(rinsed)
            case .failure(let error): completion("(\(error.localizedDescription))")
            }
        }
    }

    private func finish(note: String) {
        rinsing = false
        show(note)
        resetIdleTimer()
    }

    private func fail(_ message: String) {
        rinsing = false
        NSSound.beep()
        show(message)
    }

    /// A short note on the status line that fades after a while.
    private func show(_ text: String) {
        note = text
        noteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.note = nil }
        noteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    // MARK: Memory

    /// Pre-fills the prompt for the new slider position shortly after it
    /// settles, so the next rinse doesn't wait for it.
    private func slidersChanged() {
        warmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.engineState == .ready || self.engineState == .unloaded else { return }
            self.engine.warm(grammar: self.grammar, humanize: self.humanize)
            self.resetIdleTimer()
        }
        warmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard idleUnloadMinutes > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(idleUnloadMinutes * 60), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.freeMemory() }
        }
    }

    func freeMemory() {
        guard !rinsing, engineState == .ready else { return }
        engine.unload()
    }

    /// The engine's resident memory in MB, or nil when it isn't running.
    func engineMemoryMB() -> Int? {
        guard let pid = engine.pid else { return nil }
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard ok == 0 else { return nil }
        return Int(info.ri_phys_footprint / 1_048_576)
    }

    // MARK: Login

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                rlog.error("login item: \(error.localizedDescription, privacy: .public)")
            }
            objectWillChange.send()
        }
    }

    // MARK: Migration

    /// Settings from the app's working name, TextFix, carried over once.
    private static func migrateFromTextFix() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromTextFix"),
              let old = UserDefaults(suiteName: "local.textfix") else { return }
        defaults.set(true, forKey: "migratedFromTextFix")
        for key in ["grammar", "humanize", "idleUnloadMinutes"] {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        if let value = old.object(forKey: "autoSelect") { defaults.set(value, forKey: "wholeField") }
    }
}
