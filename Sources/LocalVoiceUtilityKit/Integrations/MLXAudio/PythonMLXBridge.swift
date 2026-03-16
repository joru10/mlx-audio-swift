import Foundation
#if os(macOS)
import AVFoundation
#endif

public enum PythonMLXBridgeError: LocalizedError {
    case repoNotFound(String)
    case toolMissing(String)
    case commandFailed(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .repoNotFound(let path):
            return "Python mlx-audio repo not found at \(path)."
        case .toolMissing(let message):
            return message
        case .commandFailed(let message):
            return message
        case .invalidOutput(let message):
            return message
        }
    }
}

public struct PythonMLXBridge: Sendable {
    public static let defaultRepoPath = {
        let env = ProcessInfo.processInfo.environment["LOCALVOICE_MLX_AUDIO_REPO"]
        if let env, !env.isEmpty {
            return env
        }
        let candidates = [
            "/Users/joru2/Applications/MLXAudio/Vendor/mlx-audio-v041",
            "/Users/joru2/Applications/mlx-audio-v041",
            "/Users/joru2/Applications/mlx-audio",
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    }()

    public struct TranscriptionResult: Sendable {
        public var document: TranscriptDocument
        public var enhancedAudioURL: URL?
    }

    public init() {}

    public func synthesize(
        text: String,
        options: TTSOptions,
        outputURL: URL
    ) async throws -> (samples: [Float], sampleRate: Double) {
        let repoPath = resolvedRepoPath(options.pythonRepoPath)
        try ensureRepoExists(repoPath)

        let outputDirectory = outputURL.deletingLastPathComponent()
        let prefix = outputURL.deletingPathExtension().lastPathComponent
        let voice = normalizedPythonVoice(options.voiceIdentifier)
        var args = baseCommandArgs(repoPath: repoPath)
        args += [
            "python", "-m", "mlx_audio.tts.generate",
            "--model", options.modelId,
            "--text", text,
            "--lang_code", options.languageCode,
            "--voice", voice,
            "--audio_format", "wav",
            "--output_path", outputDirectory.path,
            "--file_prefix", prefix,
            "--join_audio",
        ]

        try await run(args: args, currentDirectory: repoPath)

#if os(macOS)
        return try readSamples(from: outputURL)
#else
        throw PythonMLXBridgeError.invalidOutput("Python TTS bridge is only supported on macOS in this app.")
#endif
    }

    public func transcribe(
        audioURL: URL,
        options: STTOptions,
        workingDirectory: URL
    ) async throws -> TranscriptionResult {
        let repoPath = resolvedRepoPath(options.pythonRepoPath)
        try ensureRepoExists(repoPath)

        var effectiveAudioURL = audioURL
        var enhancedAudioURL: URL?
        if options.enhancementMode != .off {
            let enhancedURL = workingDirectory
                .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent + "-enhanced")
                .appendingPathExtension(audioURL.pathExtension.isEmpty ? "wav" : audioURL.pathExtension)
            try await enhance(audioURL: audioURL, mode: options.enhancementMode, outputURL: enhancedURL, repoPath: repoPath)
            effectiveAudioURL = enhancedURL
            enhancedAudioURL = enhancedURL
        }

        let outputBase = workingDirectory.appendingPathComponent(UUID().uuidString)
        let outputFormat = preferredSTTFormat(for: options)
        var args = baseCommandArgs(repoPath: repoPath)
        args += [
            "python", "-m", "mlx_audio.stt.generate",
            "--model", options.modelId,
            "--audio", effectiveAudioURL.path,
            "--output-path", outputBase.path,
            "--format", outputFormat,
            "--language", options.languageCode,
        ]
        if options.useVAD {
            args += ["--gen-kwargs", "{\"min_chunk_duration\": 0.5}"]
        }

        try await run(args: args, currentDirectory: repoPath)
        let document = try parseTranscriptOutput(
            format: outputFormat,
            baseURL: outputBase,
            sourcePath: audioURL.path,
            modelID: options.modelId
        )
        return TranscriptionResult(document: document, enhancedAudioURL: enhancedAudioURL)
    }

    private func enhance(audioURL: URL, mode: SpeechEnhancementMode, outputURL: URL, repoPath: String) async throws {
        var args = baseCommandArgs(repoPath: repoPath)
        args += [
            "python", "-m", "mlx_audio.sts.generate",
            "--audio", audioURL.path,
            "--output-path", outputURL.path,
        ]

        switch mode {
        case .off:
            return
        case .deepFilterNet1:
            args += ["--model", "mlx-community/DeepFilterNet-mlx", "--version", "1"]
        case .deepFilterNet2:
            args += ["--model", "mlx-community/DeepFilterNet-mlx", "--version", "2"]
        case .deepFilterNet3:
            args += ["--model", "mlx-community/DeepFilterNet-mlx", "--version", "3"]
        case .mossFormer2:
            args += ["--model", "starkdmi/MossFormer2_SE_48K_MLX"]
        }

        try await run(args: args, currentDirectory: repoPath)
    }

    private func parseTranscriptJSON(at url: URL, sourcePath: String, modelID: String) throws -> TranscriptDocument {
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let root else {
            throw PythonMLXBridgeError.invalidOutput("Unexpected JSON output from Python STT bridge.")
        }

        let fullText = (root["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var segments: [TranscriptSegment] = []

        if let sentences = root["sentences"] as? [[String: Any]] {
            segments = sentences.compactMap { item in
                guard let text = item["text"] as? String else { return nil }
                let start = item["start"] as? Double ?? 0
                let end = item["end"] as? Double ?? 0
                let speaker = item["speaker_id"] as? String
                return TranscriptSegment(startSec: start, endSec: end, speaker: speaker, text: text)
            }
        } else if let rawSegments = root["segments"] as? [[String: Any]] {
            segments = rawSegments.compactMap { item in
                guard let text = item["text"] as? String else { return nil }
                let start = item["start"] as? Double ?? 0
                let end = item["end"] as? Double ?? 0
                let speaker = item["speaker_id"] as? String
                return TranscriptSegment(startSec: start, endSec: end, speaker: speaker, text: text)
            }
        }

        return TranscriptDocument(
            source: .init(path: sourcePath, type: "audio"),
            model: .init(id: modelID),
            fullText: fullText,
            segments: segments
        )
    }

    private func parseTranscriptText(at url: URL, sourcePath: String, modelID: String) throws -> TranscriptDocument {
        let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptDocument(
            source: .init(path: sourcePath, type: "audio"),
            model: .init(id: modelID),
            fullText: text,
            segments: text.isEmpty ? [] : [TranscriptSegment(startSec: 0, endSec: 0, text: text)]
        )
    }

    private func parseTranscriptOutput(format: String, baseURL: URL, sourcePath: String, modelID: String) throws -> TranscriptDocument {
        switch format {
        case "json":
            return try parseTranscriptJSON(at: baseURL.appendingPathExtension("json"), sourcePath: sourcePath, modelID: modelID)
        case "txt":
            return try parseTranscriptText(at: baseURL.appendingPathExtension("txt"), sourcePath: sourcePath, modelID: modelID)
        default:
            throw PythonMLXBridgeError.invalidOutput("Unsupported transcript format from Python bridge: \(format)")
        }
    }

    private func preferredSTTFormat(for options: STTOptions) -> String {
        if options.includeTimestamps && modelSupportsJSONSegments(options.modelId) {
            return "json"
        }
        return "txt"
    }

    private func modelSupportsJSONSegments(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        if lower.contains("sensevoice") {
            return false
        }
        return true
    }

    private func resolvedRepoPath(_ provided: String?) -> String {
        guard let provided, !provided.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.defaultRepoPath
        }
        return provided
    }

    private func normalizedPythonVoice(_ voiceIdentifier: String?) -> String {
        guard let voiceIdentifier, !voiceIdentifier.isEmpty else {
            return "af_heart"
        }
        if voiceIdentifier.contains("com.apple.speech") {
            return "af_heart"
        }
        return voiceIdentifier
    }

    private func ensureRepoExists(_ repoPath: String) throws {
        guard FileManager.default.fileExists(atPath: repoPath) else {
            throw PythonMLXBridgeError.repoNotFound(repoPath)
        }
    }

    private func baseCommandArgs(repoPath: String) -> [String] {
        let executable = (try? resolveUVExecutable()) ?? "uv"
        return [executable, "run", "--directory", repoPath]
    }

    private func run(args: [String], currentDirectory: String) async throws {
        let executable = try resolveExecutable(args.first)
        let output = try await ProcessRunner.run(executable: executable, arguments: Array(args.dropFirst()), currentDirectory: currentDirectory)
        guard output.exitCode == 0 else {
            let detail = [output.stdout, output.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw PythonMLXBridgeError.commandFailed(detail.isEmpty ? "mlx-audio bridge failed." : detail)
        }
    }

    private func resolveExecutable(_ executable: String?) throws -> String {
        guard let executable, !executable.isEmpty else {
            throw PythonMLXBridgeError.toolMissing("Missing executable for mlx-audio bridge command.")
        }
        if executable.hasPrefix("/") {
            return executable
        }
        if executable == "uv" {
            return try resolveUVExecutable()
        }
        return executable
    }

    private func resolveUVExecutable() throws -> String {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let candidates = [
            env["UV_BIN"],
            "\(home)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            "/usr/bin/uv",
        ].compactMap { $0 }

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }

        throw PythonMLXBridgeError.toolMissing(
            "Could not find `uv` for the Python mlx-audio bridge. Install uv or set UV_BIN in the app environment."
        )
    }

#if os(macOS)
    private func readSamples(from fileURL: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw PythonMLXBridgeError.invalidOutput("Unable to allocate audio buffer for Python bridge output.")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw PythonMLXBridgeError.invalidOutput("Unable to read audio samples from Python bridge output.")
        }

        let count = Int(buffer.frameLength)
        return (Array(UnsafeBufferPointer(start: channel, count: count)), format.sampleRate)
    }
#endif
}

private enum ProcessRunner {
    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    static func run(executable: String, arguments: [String], currentDirectory: String) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Result(
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self),
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
