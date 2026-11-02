import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// MLX-based LLM post-processor using mlx-swift-lm.
/// Follows the ParakeetEngine pattern: lazy model loading, @unchecked Sendable.
final class MLXPostProcessor: @unchecked Sendable {
    private var container: ModelContainer?
    private(set) var modelID: String

    /// Whether the model is currently loaded in memory.
    var isLoaded: Bool { container != nil }

    init(modelID: String = MlxModelChoice.qwen35_08b_cleanup.modelID) {
        self.modelID = modelID
    }

    /// Switch to a different model. Unloads the current model if loaded.
    func switchModel(to newModelID: String) {
        guard newModelID != modelID else { return }
        unload()
        modelID = newModelID
    }

    /// Downloads the model (if needed) and loads it into memory.
    func ensureModelLoaded(progress: (@Sendable (Progress) -> Void)? = nil) async throws {
        guard container == nil else { return }
        Memory.cacheLimit = 512 * 1024 * 1024
        let loaded = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            id: modelID,
            progressHandler: progress ?? { _ in }
        )
        container = loaded
    }

    /// Clean up raw transcription text using the MLX model.
    func cleanup(rawText: String, context: AppContext, removeFillers: Bool = true, dictionaryWords: [String] = []) async throws -> String {
        guard let container else {
            throw MLXPostProcessorError.notLoaded
        }

        if modelID == MlxModelChoice.qwen35_08b_cleanup.modelID {
            return try await cleanupWithDictationModel(container, rawText: rawText)
        }

        var instructions = PromptBuilder.buildSystemPrompt(context: context, removeFillers: removeFillers, dictionaryWords: dictionaryWords)
        // Qwen models support /no_think to disable chain-of-thought
        if modelID.lowercased().contains("qwen") {
            instructions += "\n/no_think"
        }
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(temperature: 0.1)
        )

        var response = try await session.respond(
            to: "[DICTATION START]\n\(rawText)\n[DICTATION END]"
        )
        // Strip any thinking tokens the model may emit despite /no_think
        if let thinkEnd = response.range(of: "</think>") {
            response = String(response[thinkEnd.upperBound...])
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Qwen3.5-0.8B full fine-tune trained for Parakeet-style dictation cleanup.
    /// The model returns `{"cleaned_text": "..."}` and is deliberately
    /// conservative; the guardrails below fall back to the raw transcript when
    /// an edit looks destructive or malformed.
    private func cleanupWithDictationModel(_ container: ModelContainer, rawText: String) async throws -> String {
        let system = "You are a transcription formatting assistant. Follow the user's formatting instructions exactly and return only the final formatted transcript."
        let user = """
        You are a transcription cleanup assistant.

        Convert the following raw transcript into polished, readable text.

        Instructions:
        1. Add punctuation and capitalization.
        2. Split the text into natural sentences.
        3. Break the text into readable paragraphs whenever the speaker moves into a new topic, example, action taken, or result.
        4. Prefer short paragraphs of 1 to 3 sentences.
        5. For medium-length monologues, favor multiple paragraphs over one dense block when the ideas naturally separate.
        6. Use real paragraph breaks in the cleaned text.
        7. Fix obvious speech-to-text errors.
        8. Remove repeated words and filler sounds when unnecessary.
        9. Keep the original meaning, tone, language and wording as close as possible.
        10. Do not summarize, shorten, or add content.
        11. Do not explain your edits.
        12. Output only the final cleaned text.

        Return JSON with one field: {"cleaned_text": "..."}.

        Raw transcript:
        \(rawText)
        """

        let session = ChatSession(
            container,
            instructions: system,
            generateParameters: GenerateParameters(temperature: 0.2)
        )
        let response = try await session.respond(to: user)
        let cleaned = Self.extractCleanedText(response) ?? response
        return Self.guardCleanup(cleaned, raw: rawText)
    }

    /// Release the model from memory.
    func unload() {
        container = nil
        Memory.clearCache()
    }

    /// Check if the model exists on disk or is loaded in memory.
    func modelIsReady() -> Bool {
        if isLoaded { return true }
        return Self.modelCacheExists(for: modelID)
    }

    /// Check if a model's cache directory exists on disk.
    static func modelCacheExists(for modelID: String) -> Bool {
        let dir = modelCacheDirectory(for: modelID)
        return FileManager.default.fileExists(atPath: dir.path)
    }

    /// Returns the cache directory for a given model ID.
    /// Uses the same default `HubCache` that `#hubDownloader()` uses.
    static func modelCacheDirectory(for modelID: String) -> URL {
        guard let repo = Repo.ID(rawValue: modelID) else {
            return HubCache.default.cacheDirectory.appendingPathComponent(modelID)
        }
        return HubCache.default.repoDirectory(repo: repo, kind: .model)
    }
}

enum MLXPostProcessorError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        "MLX model not loaded. Download the model first."
    }
}


private extension MLXPostProcessor {
    static func extractCleanedText(_ response: String) -> String? {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let json = String(text[start...end])
            if let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cleaned = object["cleaned_text"] as? String {
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let thinkEnd = text.range(of: "</think>") {
            text = String(text[thinkEnd.upperBound...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func guardCleanup(_ cleaned: String, raw: String) -> String {
        let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !rawTrimmed.isEmpty else { return rawTrimmed }
        // Refuse obviously destructive or runaway rewrites.
        if candidate.count < max(4, rawTrimmed.count / 4) { return rawTrimmed }
        if candidate.count > max(80, rawTrimmed.count * 2) { return rawTrimmed }
        return candidate
    }
}
