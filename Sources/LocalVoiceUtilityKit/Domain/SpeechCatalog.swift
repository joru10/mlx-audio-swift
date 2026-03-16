import Foundation

public struct SpeechLanguageOption: Identifiable, Hashable, Sendable {
    public let code: String
    public let label: String

    public var id: String { code }

    public init(code: String, label: String) {
        self.code = code
        self.label = label
    }
}

public struct ModelPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let backend: InferenceBackend
    public let summary: String

    public init(id: String, backend: InferenceBackend, summary: String) {
        self.id = id
        self.backend = backend
        self.summary = summary
    }
}

public enum SpeechCatalog {
    public static let languages: [SpeechLanguageOption] = [
        .init(code: "auto", label: "Auto Detect"),
        .init(code: "en", label: "English"),
        .init(code: "es", label: "Spanish"),
        .init(code: "fr", label: "French"),
        .init(code: "de", label: "German"),
        .init(code: "pt", label: "Portuguese"),
        .init(code: "it", label: "Italian"),
        .init(code: "nl", label: "Dutch"),
        .init(code: "ja", label: "Japanese"),
        .init(code: "ko", label: "Korean"),
        .init(code: "zh", label: "Chinese"),
        .init(code: "ar", label: "Arabic"),
        .init(code: "hi", label: "Hindi"),
    ]

    public static let ttsPresets: [ModelPreset] = [
        .init(id: "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit", backend: .swiftMLX, summary: "Current Swift-native TTS model"),
        .init(id: "mlx-community/fish-audio-s2-pro", backend: .pythonMLX, summary: "Fish Audio S2 Pro via Python mlx-audio 0.4.1"),
    ]

    public static let sttPresets: [ModelPreset] = [
        .init(id: "mlx-community/Qwen3-ASR-0.6B-4bit", backend: .swiftMLX, summary: "Fast local Swift-native ASR"),
        .init(id: "path/to/canary-1b-v2-mlx", backend: .pythonMLX, summary: "Canary multilingual STT + translation"),
        .init(id: "UsefulSensors/moonshine-base", backend: .pythonMLX, summary: "Moonshine lower-latency live STT"),
        .init(id: "facebook/mms-1b-all", backend: .pythonMLX, summary: "MMS broad language coverage"),
        .init(id: "ibm-granite/granite-4.0-1b-speech", backend: .pythonMLX, summary: "Granite Speech STT + translation"),
        .init(id: "mlx-community/FireRedASR2-AED-mlx", backend: .pythonMLX, summary: "FireRedASR2 AED model"),
        .init(id: "mlx-community/SenseVoiceSmall", backend: .pythonMLX, summary: "SenseVoice multilingual STT"),
    ]
}
