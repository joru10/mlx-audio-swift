import Foundation

public struct LMOptions: Codable, Sendable {
    public var modelId: String
    public var systemPrompt: String
    public var maxTokens: Int
    public var temperature: Double

    public init(
        modelId: String = "mlx-community/Qwen3-4B-4bit",
        systemPrompt: String = "You are a local assistant inside Local Voice Utility. Be concise, factual, and use the provided transcript, OCR, or analysis context when it is relevant.",
        maxTokens: Int = 512,
        temperature: Double = 0.4
    ) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public struct LocalTextModelPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String

    public init(id: String, title: String, summary: String) {
        self.id = id
        self.title = title
        self.summary = summary
    }
}

public enum TextModelCatalog {
    public static let presets: [LocalTextModelPreset] = [
        .init(id: "mlx-community/Qwen3-0.6B-4bit", title: "Qwen3 0.6B", summary: "Fast local assistant for light prompts and routing"),
        .init(id: "mlx-community/Qwen3-4B-4bit", title: "Qwen3 4B", summary: "Balanced general local assistant model"),
        .init(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", title: "Llama 3.2 3B", summary: "Compact instruct model for summaries and Q&A"),
        .init(id: "mlx-community/SmolLM3-3B-4bit", title: "SmolLM3 3B", summary: "Small local model for short contextual tasks")
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
