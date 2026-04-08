import Foundation
import MLXLLM
import MLXLMCommon

public actor LMService {
    private var loadedModelID: String?
    private var container: ModelContainer?
    private var session: ChatSession?
    private var activeInstructions: String?

    public init() {}

    public func resetConversation() async {
        session = nil
        activeInstructions = nil
    }

    public func respond(
        prompt: String,
        context: String?,
        options: LMOptions,
        progress: (@Sendable (String) -> Void)? = nil,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let session = try await prepareSession(options: options, progress: progress)
        let finalPrompt = composePrompt(prompt: prompt, context: context)
        progress?("Generating response...")
        var response = ""
        for try await chunk in session.streamResponse(to: finalPrompt) {
            response += chunk
            onChunk?(response)
        }
        progress?("Response completed.")
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareSession(
        options: LMOptions,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> ChatSession {
        let needsReload = container == nil || loadedModelID != options.modelId
        let needsNewSession = session == nil || activeInstructions != options.systemPrompt || needsReload

        if needsReload {
            progress?("Loading text model \(options.modelId)...")
            let loadedContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: .init(id: options.modelId),
                progressHandler: { loadProgress in
                    let total = loadProgress.totalUnitCount
                    if total > 0 {
                        let percent = Int((Double(loadProgress.completedUnitCount) / Double(total)) * 100)
                        progress?("Loading text model \(options.modelId): \(percent)%")
                    } else if !loadProgress.localizedDescription.isEmpty {
                        progress?(loadProgress.localizedDescription)
                    }
                }
            )
            container = loadedContainer
            loadedModelID = options.modelId
            session = nil
        }

        if needsNewSession, let container {
            let parameters = GenerateParameters(maxTokens: options.maxTokens, temperature: Float(options.temperature))
            session = ChatSession(container, instructions: options.systemPrompt, generateParameters: parameters)
            activeInstructions = options.systemPrompt
        } else {
            session?.generateParameters = GenerateParameters(maxTokens: options.maxTokens, temperature: Float(options.temperature))
        }

        guard let session else {
            throw NSError(domain: "LMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local text model session is unavailable."])
        }
        return session
    }

    private func composePrompt(prompt: String, context: String?) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedContext.isEmpty else {
            return trimmedPrompt
        }
        return """
        Context:
        \(trimmedContext)

        User request:
        \(trimmedPrompt)
        """
    }
}
