import Foundation
import MLXLMCommon
import MLXLLM
import MLX

/// MLX-based LLM post-processor using mlx-swift-lm.
/// Follows the ParakeetEngine pattern: lazy model loading, @unchecked Sendable.
final class MLXPostProcessor: @unchecked Sendable {
    private var container: ModelContainer?
    private(set) var modelID: String

    /// Whether the model is currently loaded in memory.
    var isLoaded: Bool { container != nil }

    init(modelID: String = MlxModelChoice.qwen35_2b.modelID) {
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
        let loaded = try await loadModelContainer(id: modelID, progressHandler: progress ?? { _ in })
        container = loaded
    }

    /// Clean up raw transcription text using the MLX model.
    func cleanup(rawText: String, context: AppContext, removeFillers: Bool = true) async throws -> String {
        guard let container else {
            throw MLXPostProcessorError.notLoaded
        }

        var instructions = PromptBuilder.buildSystemPrompt(context: context, removeFillers: removeFillers)
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
    /// Uses the same `defaultHubApi` (cachesDirectory) that `loadModelContainer` uses.
    static func modelCacheDirectory(for modelID: String) -> URL {
        defaultHubApi.localRepoLocation(.init(id: modelID))
    }
}

enum MLXPostProcessorError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        "MLX model not loaded. Download the model first."
    }
}
