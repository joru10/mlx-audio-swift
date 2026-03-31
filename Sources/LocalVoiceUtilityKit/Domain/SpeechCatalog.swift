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

public enum SpeechWorkflow: String, CaseIterable, Sendable {
    case documentReader
    case fileTranscription
    case liveTranscription
}

public enum ModelCapability: String, Hashable, Sendable {
    case timestamps
    case multilingual
    case audioUnderstanding
    case lowLatency
    case streaming
}

public struct ModelPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let backend: InferenceBackend
    public let summary: String
    public let workflows: Set<SpeechWorkflow>
    public let capabilities: Set<ModelCapability>
    public let languageCodes: [String]

    public init(
        id: String,
        title: String,
        backend: InferenceBackend,
        summary: String,
        workflows: Set<SpeechWorkflow>,
        capabilities: Set<ModelCapability> = [],
        languageCodes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.backend = backend
        self.summary = summary
        self.workflows = workflows
        self.capabilities = capabilities
        self.languageCodes = languageCodes
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
        .init(code: "pl", label: "Polish"),
        .init(code: "ru", label: "Russian"),
        .init(code: "uk", label: "Ukrainian"),
    ]

    public static let ttsPresets: [ModelPreset] = [
        .init(
            id: "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit",
            title: "Marvis TTS",
            backend: .swiftMLX,
            summary: "Swift-native local TTS baseline",
            workflows: [.documentReader],
            languageCodes: ["en"]
        ),
        .init(
            id: "mlx-community/fish-audio-s2-pro",
            title: "Fish Audio S2 Pro",
            backend: .pythonMLX,
            summary: "Expressive multilingual TTS via mlx-audio 0.4.2",
            workflows: [.documentReader],
            capabilities: [.multilingual],
            languageCodes: ["en", "es", "fr", "de", "pt", "it", "ja", "zh"]
        ),
        .init(
            id: "mlx-community/Irodori-TTS-500M-fp16",
            title: "Irodori TTS",
            backend: .pythonMLX,
            summary: "Japanese TTS optimized for native Japanese reading",
            workflows: [.documentReader],
            capabilities: [.multilingual],
            languageCodes: ["ja"]
        ),
        .init(
            id: "kugelaudio/kugelaudio-0-open",
            title: "KugelAudio",
            backend: .pythonMLX,
            summary: "7B multilingual European-language TTS",
            workflows: [.documentReader],
            capabilities: [.multilingual],
            languageCodes: ["en", "de", "fr", "es", "it", "pt", "nl", "pl", "ru", "uk"]
        ),
        .init(
            id: "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16",
            title: "Voxtral TTS",
            backend: .pythonMLX,
            summary: "Streaming-capable multilingual TTS with voice presets",
            workflows: [.documentReader],
            capabilities: [.multilingual, .streaming],
            languageCodes: ["en", "fr", "es", "de", "it", "pt", "nl", "ar", "hi"]
        ),
        .init(
            id: "HumeAI/mlx-tada-3b",
            title: "HumeAI Tada",
            backend: .pythonMLX,
            summary: "Higher-fidelity multilingual TTS with aligned speech-text generation",
            workflows: [.documentReader],
            capabilities: [.multilingual],
            languageCodes: ["en", "ar", "zh", "de", "es", "fr", "it", "ja", "pl", "pt"]
        ),
    ]

    public static let sttPresets: [ModelPreset] = [
        .init(
            id: "mlx-community/Qwen3-ASR-0.6B-4bit",
            title: "Qwen3 ASR 0.6B",
            backend: .swiftMLX,
            summary: "Fast local Swift-native ASR",
            workflows: [.fileTranscription, .liveTranscription],
            capabilities: [.timestamps, .multilingual],
            languageCodes: ["auto", "en", "zh", "ja", "ko"]
        ),
        .init(
            id: "mlx-community/whisper-large-v3-turbo-asr-fp16",
            title: "Whisper Large v3 Turbo",
            backend: .pythonMLX,
            summary: "Robust multilingual transcription with timestamp support",
            workflows: [.fileTranscription],
            capabilities: [.timestamps, .multilingual],
            languageCodes: ["auto"]
        ),
        .init(
            id: "distil-whisper/distil-large-v3",
            title: "Distil-Whisper",
            backend: .pythonMLX,
            summary: "Faster English Whisper variant for file transcription",
            workflows: [.fileTranscription],
            capabilities: [.timestamps],
            languageCodes: ["en"]
        ),
        .init(
            id: "CohereLabs/cohere-transcribe-03-2026",
            title: "Cohere Transcribe",
            backend: .pythonMLX,
            summary: "14-language long-form ASR with punctuation control",
            workflows: [.fileTranscription],
            capabilities: [.timestamps, .multilingual],
            languageCodes: ["auto", "en", "es", "fr", "de", "it", "pt", "ja"]
        ),
        .init(
            id: "path/to/canary-1b-v2-mlx",
            title: "Canary 1B v2",
            backend: .pythonMLX,
            summary: "Multilingual ASR and speech translation",
            workflows: [.fileTranscription],
            capabilities: [.timestamps, .multilingual],
            languageCodes: ["auto", "en", "es", "fr", "de", "pt", "ja"]
        ),
        .init(
            id: "UsefulSensors/moonshine-base",
            title: "Moonshine Base",
            backend: .pythonMLX,
            summary: "Lower-latency English STT for live use",
            workflows: [.fileTranscription, .liveTranscription],
            capabilities: [.lowLatency],
            languageCodes: ["en"]
        ),
        .init(
            id: "facebook/mms-1b-all",
            title: "MMS 1B",
            backend: .pythonMLX,
            summary: "Broadest language coverage for file transcription",
            workflows: [.fileTranscription],
            capabilities: [.multilingual],
            languageCodes: ["auto"]
        ),
        .init(
            id: "ibm-granite/granite-4.0-1b-speech",
            title: "Granite Speech 4.0",
            backend: .pythonMLX,
            summary: "ASR plus speech translation",
            workflows: [.fileTranscription],
            capabilities: [.timestamps, .multilingual],
            languageCodes: ["auto", "en", "fr", "de", "es", "pt", "ja"]
        ),
        .init(
            id: "mlx-community/FireRedASR2-AED-mlx",
            title: "FireRedASR2 AED",
            backend: .pythonMLX,
            summary: "Accurate multilingual AED-style transcription",
            workflows: [.fileTranscription],
            capabilities: [.multilingual],
            languageCodes: ["auto", "en", "zh"]
        ),
        .init(
            id: "mlx-community/SenseVoiceSmall",
            title: "SenseVoice Small",
            backend: .pythonMLX,
            summary: "Multilingual live/file STT with strong conversational handling",
            workflows: [.fileTranscription, .liveTranscription],
            capabilities: [.multilingual, .lowLatency],
            languageCodes: ["auto", "en", "zh", "ja", "ko"]
        ),
        .init(
            id: "mlx-community/parakeet-tdt-0.6b-v2",
            title: "Parakeet TDT",
            backend: .pythonMLX,
            summary: "Streaming-oriented STT with improved defaults in mlx-audio 0.4.2",
            workflows: [.fileTranscription, .liveTranscription],
            capabilities: [.timestamps, .lowLatency, .streaming],
            languageCodes: ["en"]
        ),
        .init(
            id: "mlx-community/Qwen2-Audio-7B-Instruct-4bit",
            title: "Qwen2-Audio 7B Instruct",
            backend: .pythonMLX,
            summary: "Audio understanding model for ASR, captioning, translation, and emotion analysis",
            workflows: [.fileTranscription],
            capabilities: [.multilingual, .audioUnderstanding],
            languageCodes: ["auto"]
        ),
    ]

    public static func ttsModels(for workflow: SpeechWorkflow) -> [ModelPreset] {
        ttsPresets.filter { $0.workflows.contains(workflow) }
    }

    public static func sttModels(for workflow: SpeechWorkflow) -> [ModelPreset] {
        sttPresets.filter { $0.workflows.contains(workflow) }
    }

    public static func preset(for id: String) -> ModelPreset? {
        ttsPresets.first(where: { $0.id == id }) ?? sttPresets.first(where: { $0.id == id })
    }

    public static func languageOptions(for preset: ModelPreset?, allowAutoDetect: Bool) -> [SpeechLanguageOption] {
        guard let preset, !preset.languageCodes.isEmpty else {
            return allowAutoDetect ? languages : languages.filter { $0.code != "auto" }
        }
        let allowed = Set(preset.languageCodes)
        return languages.filter { option in
            if option.code == "auto" {
                return allowAutoDetect && allowed.contains("auto")
            }
            return allowed.contains(option.code)
        }
    }

    public static func supportsTimestamps(_ modelID: String) -> Bool {
        preset(for: modelID)?.capabilities.contains(.timestamps) ?? true
    }

    public static func supportsAudioUnderstanding(_ modelID: String) -> Bool {
        preset(for: modelID)?.capabilities.contains(.audioUnderstanding) ?? false
    }

    public static func capabilityBadges(for preset: ModelPreset?) -> [String] {
        guard let preset else { return [] }
        var badges: [String] = []
        if preset.capabilities.contains(.multilingual) { badges.append("Multilingual") }
        if preset.capabilities.contains(.timestamps) { badges.append("Timestamps") }
        if preset.capabilities.contains(.lowLatency) { badges.append("Low latency") }
        if preset.capabilities.contains(.streaming) { badges.append("Streaming") }
        if preset.capabilities.contains(.audioUnderstanding) { badges.append("Audio understanding") }
        return badges
    }
}
