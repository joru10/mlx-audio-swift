import Foundation
@preconcurrency import MLXAudioTTS
#if os(macOS)
import AppKit
import AVFoundation
#endif

public struct TTSService {
    private let pythonBridge = PythonMLXBridge()

    public init() {}

    public func synthesize(text: String, modelID: String, voiceIdentifier: String? = nil) async throws -> (samples: [Float], sampleRate: Double) {
        try await synthesize(
            text: text,
            options: TTSOptions(modelId: modelID, voiceIdentifier: voiceIdentifier)
        )
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> (samples: [Float], sampleRate: Double) {
        if shouldUsePythonBackend(options: options) {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")
            defer { try? FileManager.default.removeItem(at: outputURL) }
            return try await pythonBridge.synthesize(text: text, options: options, outputURL: outputURL)
        }
        if options.backend == .systemFallback {
#if os(macOS)
            return try await SystemTTSFallback.synthesize(text: text, voiceIdentifier: options.voiceIdentifier)
#else
            throw PythonMLXBridgeError.invalidOutput("System fallback TTS is only available on macOS.")
#endif
        }

        do {
            try MLXRuntimePreflight.ensureReady()
            let model = try await TTS.loadModel(modelRepo: options.modelId)
            let output = try await model.generate(
                text: text,
                voice: options.voiceIdentifier,
                refAudio: nil,
                refText: nil,
                language: options.languageCode,
                generationParameters: model.defaultGenerationParameters
            )
            return (output.asArray(Float.self), Double(model.sampleRate))
        } catch {
            if options.backend == .swiftMLX {
                throw error
            }
#if os(macOS)
            // Fallback allows PDF/URL reading even when MLX runtime is unavailable.
            return try await SystemTTSFallback.synthesize(text: text, voiceIdentifier: options.voiceIdentifier)
#else
            throw error
#endif
        }
    }

    private func shouldUsePythonBackend(options: TTSOptions) -> Bool {
        switch options.backend {
        case .pythonMLX:
            return true
        case .swiftMLX, .systemFallback:
            return false
        case .automatic:
            let lower = options.modelId.lowercased()
            return lower.contains("fish")
        }
    }
}

#if os(macOS)
@MainActor
private enum SystemTTSFallback {
    final class Delegate: NSObject, NSSpeechSynthesizerDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func waitForCompletion() async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            if finishedSpeaking {
                continuation.resume()
            } else {
                continuation.resume(
                    throwing: NSError(
                        domain: "SystemTTSFallback",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "System TTS failed before completion."]
                    )
                )
            }
        }
    }

    static func synthesize(text: String, voiceIdentifier: String?) async throws -> (samples: [Float], sampleRate: Double) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("aiff")

        let synthesizer = NSSpeechSynthesizer()
        if let voiceIdentifier, !voiceIdentifier.isEmpty {
            _ = synthesizer.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: voiceIdentifier))
        }
        let delegate = Delegate()
        synthesizer.delegate = delegate

        guard synthesizer.startSpeaking(text, to: tempURL) else {
            throw NSError(
                domain: "SystemTTSFallback",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start system TTS synthesis."]
            )
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await delegate.waitForCompletion()

        let (samples, sampleRate) = try readSamples(from: tempURL)
        return (samples, sampleRate)
    }

    private static func readSamples(from fileURL: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "SystemTTSFallback",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to allocate audio buffer for fallback speech file."]
            )
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw NSError(
                domain: "SystemTTSFallback",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Unable to read fallback speech samples."]
            )
        }

        let count = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        return (samples, format.sampleRate)
    }
}
#endif
