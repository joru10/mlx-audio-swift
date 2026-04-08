import Foundation

public enum PythonMLXLMBridgeError: LocalizedError {
    case repoNotFound(String)
    case toolMissing(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .repoNotFound(let path):
            return "Python mlx-lm repo not found at \(path)."
        case .toolMissing(let message):
            return message
        case .commandFailed(let message):
            return message
        }
    }
}

public struct PythonMLXLMBridge: Sendable {
    public static let defaultRepoPath: String = {
        let env = ProcessInfo.processInfo.environment["LOCALVOICE_MLX_LM_REPO"]
        if let env, !env.isEmpty {
            return env
        }
        let candidates = [
            "/Users/joru2/Applications/MLXAudio/Vendor/mlx-lm",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/MLXAudio/Vendor/mlx-lm").path,
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    }()

    public init() {}

    public func respond(
        prompt: String,
        options: LMOptions,
        progress: (@Sendable (String) -> Void)? = nil,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let repoPath = resolvedRepoPath(options.pythonRepoPath)
        try ensureRepoExists(repoPath)
        let invocation = try resolvedInvocation(repoPath: repoPath)

        var args = invocation.arguments + [
            "--model", options.modelId,
            "--prompt", prompt,
            "--system-prompt", options.systemPrompt,
            "--max-tokens", String(options.maxTokens),
            "--temp", String(options.temperature),
            "--verbose", "False",
        ]

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = args
        process.environment = processEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        let accumulator = DataAccumulator()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            accumulator.append(data)
            if let text = String(data: accumulator.data, encoding: .utf8) {
                onChunk?(text)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                for rawLine in text.split(whereSeparator: \.isNewline) {
                    let line = String(rawLine)
                    guard !line.isEmpty else { continue }
                    progress?(normalizeStatus(line, modelId: options.modelId))
                }
            }
        }

        try process.run()
        let monitor = DownloadProgressMonitor(modelId: options.modelId, progress: progress)
        monitor.start()
        process.waitUntilExit()
        monitor.stop()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        let trailingStdout = stdout.fileHandleForReading.readDataToEndOfFile()
        if !trailingStdout.isEmpty {
            accumulator.append(trailingStdout)
        }
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let output = String(data: accumulator.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw PythonMLXLMBridgeError.commandFailed(stderrText.isEmpty ? "mlx-lm generation failed." : stderrText)
        }
        guard !output.isEmpty else {
            throw PythonMLXLMBridgeError.commandFailed(stderrText.isEmpty ? "mlx-lm returned no output." : stderrText)
        }
        progress?("Response completed.")
        return output
    }

    private func resolvedRepoPath(_ provided: String?) -> String {
        guard let provided, !provided.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.defaultRepoPath
        }
        return provided
    }

    private func ensureRepoExists(_ repoPath: String) throws {
        guard FileManager.default.fileExists(atPath: repoPath) else {
            throw PythonMLXLMBridgeError.repoNotFound(repoPath)
        }
    }

    private func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_DISABLE_XET"] = "1"
        env["HF_HUB_ENABLE_HF_TRANSFER"] = "0"
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    private func normalizeStatus(_ line: String, modelId: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("fetching") || lower.contains("downloading") {
            return "Downloading model assets: \(trimmed)"
        }
        if lower.contains("loading") {
            return "Loading text model \(modelId): \(trimmed)"
        }
        if lower.contains("unauthenticated requests") || lower.contains("set a hf_token") {
            return "Hugging Face is downloading without authentication. Set HF_TOKEN for higher rate limits and faster downloads."
        }
        return trimmed
    }

    private func resolvedInvocation(repoPath: String) throws -> (executable: String, arguments: [String]) {
        let venvExecutable = URL(fileURLWithPath: repoPath).appendingPathComponent(".venv/bin/mlx_lm.generate").path
        if FileManager.default.isExecutableFile(atPath: venvExecutable) {
            return (venvExecutable, [])
        }

        let uvCandidates = [
            ProcessInfo.processInfo.environment["UV_BIN"],
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            "/Users/joru2/.local/bin/uv",
        ].compactMap { $0 }
        if let uv = uvCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return (uv, ["run", "mlx_lm.generate"])
        }

        throw PythonMLXLMBridgeError.toolMissing("Could not find mlx-lm runtime. Install it in \(repoPath)/.venv or provide UV_BIN.")
    }
}

private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

private final class DownloadProgressMonitor: @unchecked Sendable {
    private let modelId: String
    private let progress: (@Sendable (String) -> Void)?
    private let queue = DispatchQueue(label: "PythonMLXLMBridge.DownloadProgress")
    private var timer: DispatchSourceTimer?
    private var lastBytes: Int64 = -1

    init(modelId: String, progress: (@Sendable (String) -> Void)?) {
        self.modelId = modelId
        self.progress = progress
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.emitProgressIfNeeded()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func emitProgressIfNeeded() {
        let bytes = currentIncompleteBytes()
        guard bytes >= 0, bytes != lastBytes else { return }
        lastBytes = bytes
        progress?("Downloading model \(modelId): \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) fetched")
    }

    private func currentIncompleteBytes() -> Int64 {
        let cacheRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent("models--" + modelId.replacingOccurrences(of: "/", with: "--"))

        guard let enumerator = FileManager.default.enumerator(
            at: cacheRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return -1
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "incomplete" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let fileSize = values?.fileSize else { continue }
            total += Int64(fileSize)
        }
        return total
    }
}
