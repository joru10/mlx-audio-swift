import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
#if os(macOS)
import Speech
#endif

public actor STTService {
    private var loadedModelID: String?
    private var model: (any STTGenerationModel)?
    private let pythonBridge = PythonMLXBridge()

    public init() {}

    public func transcribe(audioURL: URL, options: STTOptions) async throws -> TranscriptDocument {
        if shouldUsePythonBackend(options: options) {
            let result = try await pythonBridge.transcribe(
                audioURL: audioURL,
                options: options,
                workingDirectory: audioURL.deletingLastPathComponent()
            )
            return result.document
        }
        if options.backend == .systemFallback {
#if os(macOS)
            return try await SystemSpeechTranscriber.transcribeFile(audioURL: audioURL, sourcePath: audioURL.path, languageCode: options.languageCode)
#else
            throw NSError(domain: "STTService", code: 98, userInfo: [NSLocalizedDescriptionKey: "System fallback STT is only available on macOS."])
#endif
        }

        do {
            try MLXRuntimePreflight.ensureReady()
            let (sampleRate, audio) = try loadAudioArray(from: audioURL)
            return try await transcribe(audio: audio, sampleRate: sampleRate, options: options, sourcePath: audioURL.path, sourceType: "audio")
        } catch {
            if options.backend == .swiftMLX {
                throw error
            }
#if os(macOS)
            // Fallback for machines without MLX Metal runtime.
            return try await SystemSpeechTranscriber.transcribeFile(audioURL: audioURL, sourcePath: audioURL.path, languageCode: options.languageCode)
#else
            throw error
#endif
        }
    }

    public func transcribe(samples: [Float], sampleRate: Int, options: STTOptions) async throws -> TranscriptDocument {
        if shouldUsePythonBackend(options: options) {
            throw NSError(
                domain: "STTService",
                code: 99,
                userInfo: [NSLocalizedDescriptionKey: "Python mlx-audio live streaming bridge is not implemented yet. Use Swift MLX or system fallback for live mode."]
            )
        }
        try MLXRuntimePreflight.ensureReady()
        return try await transcribe(
            audio: MLXArray(samples),
            sampleRate: sampleRate,
            options: options,
            sourcePath: "live://capture",
            sourceType: "live"
        )
    }

    private func transcribe(
        audio: MLXArray,
        sampleRate: Int,
        options: STTOptions,
        sourcePath: String,
        sourceType: String
    ) async throws -> TranscriptDocument {
        let prepared = try prepareAudio(audio, sampleRate: sampleRate, targetSampleRate: 16000)
        let sttModel = try await loadIfNeeded(modelID: options.modelId)

        var params = sttModel.defaultGenerationParameters
        params = STTGenerateParameters(
            maxTokens: params.maxTokens,
            temperature: params.temperature,
            topP: params.topP,
            topK: params.topK,
            verbose: params.verbose,
            language: normalizedLanguageCode(options.languageCode, fallback: params.language) ?? "",
            chunkDuration: options.useVAD ? 30.0 : params.chunkDuration,
            minChunkDuration: params.minChunkDuration
        )

        let output = sttModel.generate(audio: prepared, generationParameters: params)
        let segments = parseSegments(output.segments)

        return TranscriptDocument(
            source: .init(path: sourcePath, type: sourceType),
            model: .init(id: options.modelId),
            fullText: output.text,
            segments: segments
        )
    }

    private func loadIfNeeded(modelID: String) async throws -> any STTGenerationModel {
        if let model, loadedModelID == modelID {
            return model
        }

        let lower = modelID.lowercased()
        let loaded: any STTGenerationModel
        if lower.contains("glmasr") || lower.contains("glm-asr") {
            loaded = try await GLMASRModel.fromPretrained(modelID)
        } else if lower.contains("qwen3-asr") || lower.contains("qwen3_asr") {
            loaded = try await Qwen3ASRModel.fromPretrained(modelID)
        } else if lower.contains("voxtral") {
            loaded = try await VoxtralRealtimeModel.fromPretrained(modelID)
        } else if lower.contains("parakeet") {
            loaded = try await ParakeetModel.fromPretrained(modelID)
        } else {
            throw NSError(
                domain: "STTService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported STT model repo: \(modelID)"]
            )
        }

        model = loaded
        loadedModelID = modelID
        return loaded
    }

    private func parseSegments(_ raw: [[String: Any]]?) -> [TranscriptSegment] {
        guard let raw else { return [] }
        return raw.compactMap { item in
            guard let text = item["text"] as? String,
                  let start = item["start"] as? Double,
                  let end = item["end"] as? Double else {
                return nil
            }
            return TranscriptSegment(startSec: start, endSec: end, text: text)
        }
    }

    private func prepareAudio(_ audio: MLXArray, sampleRate: Int, targetSampleRate: Int) throws -> MLXArray {
        let mono = audio.ndim > 1 ? audio.mean(axis: -1) : audio
        guard sampleRate != targetSampleRate else {
            return mono
        }

        let resampled = try resampleAudio(mono.asArray(Float.self), from: sampleRate, to: targetSampleRate)
        return MLXArray(resampled)
    }

    private func shouldUsePythonBackend(options: STTOptions) -> Bool {
        switch options.backend {
        case .pythonMLX:
            return true
        case .swiftMLX, .systemFallback:
            return false
        case .automatic:
            let lower = options.modelId.lowercased()
            if options.enhancementMode != .off {
                return true
            }
            return lower.contains("canary")
                || lower.contains("moonshine")
                || lower.contains("mms")
                || lower.contains("granite")
                || lower.contains("firered")
                || lower.contains("sensevoice")
                || lower.contains("whisper")
                || lower.contains("cohere")
                || lower.contains("qwen2-audio")
                || lower.contains("parakeet")
        }
    }

    private func normalizedLanguageCode(_ languageCode: String, fallback: String?) -> String? {
        guard !languageCode.isEmpty, languageCode != "auto" else {
            return fallback
        }
        return languageCode
    }
}

#if os(macOS)
private enum SystemSpeechTranscriber {
    static func transcribeFile(audioURL: URL, sourcePath: String, languageCode: String) async throws -> TranscriptDocument {
        let status = await requestAuthorization()
        guard status == .authorized else {
            throw NSError(
                domain: "SystemSpeechTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission not granted."]
            )
        }

        let requestedLocale = requestedLocale(for: languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: requestedLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw NSError(
                domain: "SystemSpeechTranscriber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No speech recognizer available."]
            )
        }

        guard recognizer.isAvailable else {
            throw NSError(
                domain: "SystemSpeechTranscriber",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is currently unavailable."]
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        let text = try await recognize(recognizer: recognizer, request: request)

        return TranscriptDocument(
            source: .init(path: sourcePath, type: "audio"),
            model: .init(id: "system.apple.speech"),
            fullText: text,
            segments: text.isEmpty ? [] : [TranscriptSegment(startSec: 0, endSec: 0, text: text)]
        )
    }

    private static func requestedLocale(for languageCode: String) -> Locale {
        if languageCode.isEmpty || languageCode == "auto" {
            return Locale.current
        }
        return Locale(identifier: languageCode)
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    task?.cancel()
                    task = nil
                    return
                }
                guard let result, result.isFinal else { return }
                continuation.resume(returning: result.bestTranscription.formattedString)
                task?.cancel()
                task = nil
            }
        }
    }
}
#endif
