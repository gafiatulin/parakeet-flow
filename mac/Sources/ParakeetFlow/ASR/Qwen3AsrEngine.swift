import AVFoundation
import FluidAudio
import os

/// Batch transcription engine using FluidAudio's Qwen3-ASR model.
/// Audio samples are accumulated during recording; transcription runs after recording stops.
@available(macOS 15, *)
final class Qwen3AsrEngine: @unchecked Sendable {
    private let variant: Qwen3AsrVariant
    private var manager: Qwen3AsrManager?
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())

    /// The audio format Qwen3-ASR expects: 16 kHz mono Float32.
    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(variant: Qwen3AsrVariant) {
        self.variant = variant
    }

    /// Downloads the Qwen3-ASR model (if needed) and initializes the manager.
    func ensureModelLoaded() async throws {
        guard manager == nil else { return }
        let modelDir = try await Qwen3AsrModels.download(variant: variant)
        let mgr = Qwen3AsrManager()
        try await mgr.loadModels(from: modelDir)
        manager = mgr
    }

    /// Whether a model is currently loaded in memory.
    var isLoaded: Bool { manager != nil }

    /// Release the model from memory.
    func unload() {
        manager = nil
    }

    /// Begin a new recording session — clears accumulated samples.
    func startSession() {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
    }

    /// Feed an audio buffer during recording. Safe to call from any thread.
    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        samples.withLock { $0.append(contentsOf: chunk) }
    }

    /// Finish recording and run batch transcription. Returns the transcribed text.
    func finishSession() async throws -> String {
        guard let manager else {
            throw Qwen3AsrEngineError.notInitialized
        }
        let audioSamples = samples.withLock { Array($0) }
        guard audioSamples.count >= 16_000 else {
            return ""
        }
        return try await manager.transcribe(audioSamples: audioSamples)
    }
}

enum Qwen3AsrEngineError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        "Qwen3-ASR engine not initialized. Model may not be downloaded."
    }
}
