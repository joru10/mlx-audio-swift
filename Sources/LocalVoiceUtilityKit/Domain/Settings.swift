import Foundation

public enum InferenceBackend: String, Codable, CaseIterable, Sendable {
    case automatic
    case swiftMLX
    case pythonMLX
    case systemFallback
}

public enum SpeechEnhancementMode: String, Codable, CaseIterable, Sendable {
    case off
    case deepFilterNet1
    case deepFilterNet2
    case deepFilterNet3
    case mossFormer2

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .deepFilterNet1: return "DeepFilterNet v1"
        case .deepFilterNet2: return "DeepFilterNet v2"
        case .deepFilterNet3: return "DeepFilterNet v3"
        case .mossFormer2: return "MossFormer2"
        }
    }
}

public struct TTSOptions: Codable, Sendable {
    public enum ChunkMode: String, Codable, CaseIterable, Sendable {
        case paragraph
        case perPage
    }

    public var modelId: String
    public var chunkMode: ChunkMode
    public var maxChunkCharacters: Int
    public var outputFormat: String
    public var voiceIdentifier: String?
    public var languageCode: String
    public var backend: InferenceBackend
    public var pythonRepoPath: String?

    public init(
        modelId: String = "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit",
        chunkMode: ChunkMode = .paragraph,
        maxChunkCharacters: Int = 750,
        outputFormat: String = "wav",
        voiceIdentifier: String? = nil,
        languageCode: String = "en",
        backend: InferenceBackend = .automatic,
        pythonRepoPath: String? = nil
    ) {
        self.modelId = modelId
        self.chunkMode = chunkMode
        self.maxChunkCharacters = maxChunkCharacters
        self.outputFormat = outputFormat
        self.voiceIdentifier = voiceIdentifier
        self.languageCode = languageCode
        self.backend = backend
        self.pythonRepoPath = pythonRepoPath
    }
}

public struct STTOptions: Codable, Sendable {
    public var modelId: String
    public var includeTimestamps: Bool
    public var useVAD: Bool
    public var diarization: Bool
    public var languageCode: String
    public var backend: InferenceBackend
    public var pythonRepoPath: String?
    public var enhancementMode: SpeechEnhancementMode

    public init(
        modelId: String = "mlx-community/Qwen3-ASR-0.6B-4bit",
        includeTimestamps: Bool = false,
        useVAD: Bool = false,
        diarization: Bool = false,
        languageCode: String = "en",
        backend: InferenceBackend = .automatic,
        pythonRepoPath: String? = nil,
        enhancementMode: SpeechEnhancementMode = .off
    ) {
        self.modelId = modelId
        self.includeTimestamps = includeTimestamps
        self.useVAD = useVAD
        self.diarization = diarization
        self.languageCode = languageCode
        self.backend = backend
        self.pythonRepoPath = pythonRepoPath
        self.enhancementMode = enhancementMode
    }
}

public struct AppSettings: Codable, Sendable {
    public var outputFolderPath: String
    public var loggingLevel: String
    public var ttsDefaults: TTSOptions
    public var sttDefaults: STTOptions
    public var ttsVoiceByModel: [String: String]
    public var preferredReaderLanguage: String
    public var preferredTranscriptionLanguage: String
    public var pythonMLXRepoPath: String

    public init(
        outputFolderPath: String,
        loggingLevel: String = "info",
        ttsDefaults: TTSOptions = TTSOptions(),
        sttDefaults: STTOptions = STTOptions(),
        ttsVoiceByModel: [String: String] = [:],
        preferredReaderLanguage: String = "en",
        preferredTranscriptionLanguage: String = "en",
        pythonMLXRepoPath: String = PythonMLXBridge.defaultRepoPath
    ) {
        self.outputFolderPath = outputFolderPath
        self.loggingLevel = loggingLevel
        self.ttsDefaults = ttsDefaults
        self.sttDefaults = sttDefaults
        self.ttsVoiceByModel = ttsVoiceByModel
        self.preferredReaderLanguage = preferredReaderLanguage
        self.preferredTranscriptionLanguage = preferredTranscriptionLanguage
        self.pythonMLXRepoPath = pythonMLXRepoPath
    }

    private enum CodingKeys: String, CodingKey {
        case outputFolderPath
        case loggingLevel
        case ttsDefaults
        case sttDefaults
        case ttsVoiceByModel
        case preferredReaderLanguage
        case preferredTranscriptionLanguage
        case pythonMLXRepoPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outputFolderPath = try c.decode(String.self, forKey: .outputFolderPath)
        loggingLevel = try c.decodeIfPresent(String.self, forKey: .loggingLevel) ?? "info"
        ttsDefaults = try c.decodeIfPresent(TTSOptions.self, forKey: .ttsDefaults) ?? TTSOptions()
        sttDefaults = try c.decodeIfPresent(STTOptions.self, forKey: .sttDefaults) ?? STTOptions()
        ttsVoiceByModel = try c.decodeIfPresent([String: String].self, forKey: .ttsVoiceByModel) ?? [:]
        preferredReaderLanguage = try c.decodeIfPresent(String.self, forKey: .preferredReaderLanguage) ?? ttsDefaults.languageCode
        preferredTranscriptionLanguage = try c.decodeIfPresent(String.self, forKey: .preferredTranscriptionLanguage) ?? sttDefaults.languageCode
        pythonMLXRepoPath = try c.decodeIfPresent(String.self, forKey: .pythonMLXRepoPath) ?? PythonMLXBridge.defaultRepoPath
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputFolderPath, forKey: .outputFolderPath)
        try c.encode(loggingLevel, forKey: .loggingLevel)
        try c.encode(ttsDefaults, forKey: .ttsDefaults)
        try c.encode(sttDefaults, forKey: .sttDefaults)
        try c.encode(ttsVoiceByModel, forKey: .ttsVoiceByModel)
        try c.encode(preferredReaderLanguage, forKey: .preferredReaderLanguage)
        try c.encode(preferredTranscriptionLanguage, forKey: .preferredTranscriptionLanguage)
        try c.encode(pythonMLXRepoPath, forKey: .pythonMLXRepoPath)
    }
}
