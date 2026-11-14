import Foundation
import os

let rlog = Logger(subsystem: "io.github.bruno-alumn.rinsewrite", category: "app")

/// Runs the language engine (engine/main.py on MLX) as a child process and
/// talks JSON lines over its stdin and stdout. The model stays loaded
/// between rinses, which is what makes them take a fraction of a second.
final class EngineClient {
    enum State: Equatable {
        case notInstalled
        case starting
        case ready
        case unloaded
        case failed(String)
    }

    struct EngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Called on the main queue.
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .starting {
        didSet {
            let s = state
            DispatchQueue.main.async { self.onStateChange?(s) }
        }
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: (Result<String, Error>) -> Void] = [:]
    private let queue = DispatchQueue(label: "rinsewrite.engine")
    private var restarts = 0
    private var stopping = false

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rinsewrite")
    }

    static var pythonPath: String {
        ProcessInfo.processInfo.environment["RINSEWRITE_PYTHON"]
            ?? supportDirectory.appendingPathComponent("venv/bin/python").path
    }

    static var engineScript: String {
        ProcessInfo.processInfo.environment["RINSEWRITE_ENGINE"]
            ?? Bundle.main.resourceURL!.appendingPathComponent("engine/main.py").path
    }

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: pythonPath) }

    static var logURL: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Rinsewrite.log")
    }

    /// The engine's process ID while it runs, for the memory readout.
    var pid: Int32? { queue.sync { process?.processIdentifier } }

    func start(grammar: Double, humanize: Double) {
        queue.async { self.launch(grammar: grammar, humanize: humanize) }
    }

    func stop() {
        queue.sync {
            stopping = true
            process?.terminate()
        }
    }

    private var lastSliders = (0.5, 0.5)

    private func launch(grammar: Double, humanize: Double) {
        lastSliders = (grammar, humanize)
        guard Self.isInstalled else {
            state = .notInstalled
            return
        }
        state = .starting
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.pythonPath)
        p.arguments = ["-u", Self.engineScript, String(grammar), String(humanize)]
        var env = ProcessInfo.processInfo.environment
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["TRANSFORMERS_VERBOSITY"] = "error"
        env["PYTHONWARNINGS"] = "ignore"
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: Self.logURL)) ?? FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            self?.queue.async { self?.handleExit(proc.terminationStatus) }
        }
        do {
            try p.run()
            process = p
            stdin = input.fileHandleForWriting
        } catch {
            state = .failed("Couldn't start the engine: \(error.localizedDescription)")
        }
    }

    private func handleExit(_ status: Int32) {
        process = nil
        stdin = nil
        for (_, callback) in pending { callback(.failure(EngineError(message: "The engine stopped"))) }
        pending.removeAll()
        if stopping { return }
        if case .failed = state { return } // a fatal error was already reported
        restarts += 1
        rlog.error("engine exited with status \(status), restart \(self.restarts)")
        if restarts > 5 {
            state = .failed("The engine keeps stopping. See the log.")
            return
        }
        let (g, h) = lastSliders
        queue.asyncAfter(deadline: .now() + Double(restarts)) { self.launch(grammar: g, humanize: h) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let event = object["event"] as? String {
                switch event {
                case "ready", "warmed": restarts = 0; state = .ready
                case "unloaded": state = .unloaded
                case "fatal": state = .failed(object["error"] as? String ?? "The engine couldn't start")
                default: break
                }
                continue
            }
            guard let id = object["id"] as? Int, let callback = pending.removeValue(forKey: id) else { continue }
            if let text = object["text"] as? String {
                if state == .unloaded { state = .ready } // it reloaded for this request
                callback(.success(text))
            } else {
                callback(.failure(EngineError(message: object["error"] as? String ?? "Unknown engine error")))
            }
        }
    }

    private func send(_ request: [String: Any]) -> Bool {
        guard let stdin, let data = try? JSONSerialization.data(withJSONObject: request) else { return false }
        var line = data
        line.append(0x0A)
        stdin.write(line)
        return true
    }

    /// Rinses `text`. The completion runs on the main queue.
    func rinse(_ text: String, grammar: Double, humanize: Double,
               completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let done: (Result<String, Error>) -> Void = { result in DispatchQueue.main.async { completion(result) } }
            guard self.state == .ready || self.state == .unloaded else {
                done(.failure(EngineError(message: "The engine is still loading")))
                return
            }
            let id = self.nextID
            self.nextID += 1
            self.pending[id] = done
            if !self.send(["id": id, "text": text, "grammar": grammar, "humanize": humanize]) {
                self.pending[id] = nil
                done(.failure(EngineError(message: "The engine isn't running")))
            }
        }
    }

    /// Pre-fills the prompt for these slider values, so the next rinse is instant.
    func warm(grammar: Double, humanize: Double) {
        queue.async {
            self.lastSliders = (grammar, humanize)
            _ = self.send(["cmd": "warm", "grammar": grammar, "humanize": humanize])
        }
    }

    /// Frees the model's memory; the next rinse loads it again.
    func unload() {
        queue.async { _ = self.send(["cmd": "unload"]) }
    }
}
