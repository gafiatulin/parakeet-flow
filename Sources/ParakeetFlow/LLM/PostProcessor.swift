import FoundationModels

@available(macOS 26, *)
enum PostProcessor {

    /// Check if the on-device model is available.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Clean up raw transcription text using the on-device Foundation Model.
    static func cleanup(rawText: String, context: AppContext, removeFillers: Bool = true) async throws -> String {
        let instructions = PromptBuilder.buildSystemPrompt(context: context, removeFillers: removeFillers)
        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(
            to: "[DICTATION START]\n\(rawText)\n[DICTATION END]",
            options: GenerationOptions(temperature: 0.1)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
