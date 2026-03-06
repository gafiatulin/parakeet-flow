import AVFoundation
import FluidAudio
import os

/// Batch transcription engine using FluidAudio's Parakeet TDT model.
/// Audio samples are accumulated during recording; transcription runs after recording stops.
final class ParakeetEngine: @unchecked Sendable {
    private let version: AsrModelVersion
    private var asrManager: AsrManager?
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())

    /// The audio format Parakeet expects: 16 kHz mono Float32.
    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(version: AsrModelVersion) {
        self.version = version
    }

    /// Downloads the Parakeet TDT model (if needed) and initializes the ASR manager.
    func ensureModelLoaded() async throws {
        guard asrManager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrManager = manager
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

    /// Whether a model is currently loaded in memory.
    var isLoaded: Bool { asrManager != nil }

    /// Release the model from memory.
    func unload() {
        asrManager = nil
    }

    /// Finish recording and run batch transcription. Returns the transcribed text.
    func finishSession() async throws -> String {
        guard let asrManager else {
            throw ParakeetEngineError.notInitialized
        }
        let audioSamples = samples.withLock { Array($0) }
        guard audioSamples.count >= 16_000 else {
            // Less than 1 second of audio — not enough for Parakeet
            return ""
        }
        let result = try await asrManager.transcribe(audioSamples)
        return result.text
    }
}

enum ParakeetEngineError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        "Parakeet engine not initialized. Model may not be downloaded."
    }
}
