import Foundation

public struct LMOptions: Codable, Sendable {
    public var modelId: String
    public var systemPrompt: String
    public var maxTokens: Int
    public var temperature: Double
    public var backend: InferenceBackend
    public var pythonRepoPath: String?

    public init(
        modelId: String = "mlx-community/Qwen3-4B-4bit",
        systemPrompt: String = "You are a local assistant inside Local Voice Utility. Be concise, factual, and use the provided transcript, OCR, or analysis context when it is relevant.",
        maxTokens: Int = 512,
        temperature: Double = 0.4,
        backend: InferenceBackend = .swiftMLX,
        pythonRepoPath: String? = nil
    ) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.backend = backend
        self.pythonRepoPath = pythonRepoPath
    }
}

public struct LocalTextModelPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let backend: InferenceBackend

    public init(id: String, title: String, summary: String, backend: InferenceBackend) {
        self.id = id
        self.title = title
        self.summary = summary
        self.backend = backend
    }
}

public enum TextModelCatalog {
    public static let presets: [LocalTextModelPreset] = [
        .init(id: "mlx-community/Qwen3-0.6B-4bit", title: "Qwen3 0.6B", summary: "Fast local assistant for light prompts and routing", backend: .swiftMLX),
        .init(id: "mlx-community/Qwen3-4B-4bit", title: "Qwen3 4B", summary: "Balanced general local assistant model", backend: .swiftMLX),
        .init(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", title: "Llama 3.2 3B", summary: "Compact instruct model for summaries and Q&A", backend: .swiftMLX),
        .init(id: "mlx-community/SmolLM3-3B-4bit", title: "SmolLM3 3B", summary: "Small local model for short contextual tasks", backend: .swiftMLX),
        .init(id: "google/gemma-4-e2b-it", title: "Gemma 4 E2B", summary: "Smaller Gemma 4 model via Python mlx-lm", backend: .pythonMLX),
        .init(id: "google/gemma-4-e4b-it", title: "Gemma 4 E4B", summary: "Gemma 4 local assistant via Python mlx-lm", backend: .pythonMLX),
        .init(id: "google/gemma-4-31b-it", title: "Gemma 4 31B", summary: "Largest Gemma 4 option; expect heavy RAM use", backend: .pythonMLX),
    ]

    public static func preset(for id: String) -> LocalTextModelPreset? {
        presets.first(where: { $0.id == id })
    }
}

public struct LocalAssistantSeed: Sendable, Hashable {
    public var title: String
    public var context: String
    public var suggestedPrompt: String

    public init(title: String, context: String, suggestedPrompt: String) {
        self.title = title
        self.context = context
        self.suggestedPrompt = suggestedPrompt
    }
}
