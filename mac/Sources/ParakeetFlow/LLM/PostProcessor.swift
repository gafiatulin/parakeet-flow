import FoundationModels

@available(macOS 26, *)
enum PostProcessor {

    /// Check if the given backend is available for use.
    static func isAvailable(backend: LlmBackend) -> Bool {
        switch backend {
        case .apple:
            return SystemLanguageModel.default.availability == .available
        case .mlx:
            return true  // Always available if model is downloaded
        }
    }

    /// Clean up raw transcription text using the selected LLM backend.
    static func cleanup(
        rawText: String, context: AppContext, removeFillers: Bool = true,
        dictionaryWords: [String] = [],
        backend: LlmBackend, mlxEngine: MLXPostProcessor? = nil
    ) async throws -> String {
        switch backend {
        case .apple:
            return try await cleanupWithApple(rawText: rawText, context: context, removeFillers: removeFillers, dictionaryWords: dictionaryWords)
        case .mlx:
            guard let mlxEngine else {
                throw MLXPostProcessorError.notLoaded
            }
            return try await mlxEngine.cleanup(rawText: rawText, context: context, removeFillers: removeFillers, dictionaryWords: dictionaryWords)
        }
    }

    /// Apple Intelligence cleanup via FoundationModels.
    private static func cleanupWithApple(rawText: String, context: AppContext, removeFillers: Bool, dictionaryWords: [String]) async throws -> String {
        let instructions = PromptBuilder.buildSystemPrompt(context: context, removeFillers: removeFillers, dictionaryWords: dictionaryWords)
        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(
            to: "[DICTATION START]\n\(rawText)\n[DICTATION END]",
            options: GenerationOptions(temperature: 0.1)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
