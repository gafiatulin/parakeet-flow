import AVFoundation
import FluidAudio
import os

/// Parakeet TDT transcription engine.
///
/// Parakeet sessions use FluidAudio's sliding-window manager so partial text
/// can be shown while recording. If the streaming manager cannot start, the
/// engine falls back to the existing whole-clip path.
final class ParakeetEngine: @unchecked Sendable {
    private let version: AsrModelVersion
    private var asrManager: AsrManager?
    private var models: AsrModels?
    private var streamManager: SlidingWindowAsrManager?
    private var feedTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private let streamInput = BufferStreamInput()
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())
    private let speechDetector = SpeechActivityDetector()

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
        try await manager.loadModels(models)
        self.models = models
        self.asrManager = manager
        Task { await speechDetector.prewarm() }
    }

    /// Begin a new recording session, clearing both the batch buffer and any
    /// previous stream, and start live transcription when possible.
    func startSession(onPartial: @escaping @Sendable (String) -> Void) async {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
        await cancelStream()

        guard let models else { return }

        let config = SlidingWindowAsrConfig(tdtConfig: TdtConfig(blankId: version.blankId))
        let manager = SlidingWindowAsrManager(config: config)
        do {
            try await manager.loadModels(models)

            let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
            streamInput.set(continuation)

            updatesTask = Task {
                for await _ in await manager.transcriptionUpdates {
                    let confirmed = await manager.confirmedTranscript
                    let volatile = await manager.volatileTranscript
                    let text = [confirmed, volatile]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    if !text.isEmpty { onPartial(text) }
                }
            }

            feedTask = Task {
                for await buffer in stream {
                    await manager.streamAudio(buffer)
                }
            }

            streamManager = manager
            try await manager.startStreaming(source: .microphone)
        } catch {
            await cancelStream()
        }
    }

    /// Feed an audio buffer during recording. Safe to call from any thread.
    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        samples.withLock { $0.append(contentsOf: chunk) }
        streamInput.yield(buffer)
    }

    /// Whether a model is currently loaded in memory.
    var isLoaded: Bool { asrManager != nil }

    /// Release the model from memory.
    func unload() {
        asrManager = nil
        models = nil
        Task {
            await cancelStream()
            await speechDetector.unload()
        }
    }

    /// Cancel an in-flight session without producing text.
    func cancelSession() async {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
        await cancelStream()
    }

    /// Finish recording and return the final transcription.
    func finishSession() async throws -> String {
        guard let asrManager else {
            throw ParakeetEngineError.notInitialized
        }
        let audioSamples = samples.withLock { Array($0) }
        guard audioSamples.count >= 16_000 else {
            // Less than 1 second of audio — not enough for Parakeet.
            await cancelStream()
            return ""
        }
        guard await speechDetector.containsSpeech(audioSamples) else {
            await cancelStream()
            return ""
        }

        if let manager = streamManager {
            streamInput.finish()
            await feedTask?.value
            let text = try await manager.finish()
            updatesTask?.cancel()
            updatesTask = nil
            feedTask = nil
            streamManager = nil
            return text
        }

        // Streaming could not start; use the whole-clip path.
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            audioSamples,
            decoderState: &decoderState
        )
        return result.text
    }

    private func cancelStream() async {
        streamInput.finish()
        feedTask?.cancel()
        updatesTask?.cancel()
        feedTask = nil
        updatesTask = nil
        if let manager = streamManager {
            await manager.cancel()
        }
        streamManager = nil
    }
}

enum ParakeetEngineError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        "Parakeet engine not initialized. Model may not be downloaded."
    }
}


/// Lock-protected input continuation for the streaming manager. AVAudioPCMBuffer
/// is not Sendable, so the buffer is yielded inside this box rather than in a
/// Sendable lock closure at the call site.
private final class BufferStreamInput: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func set(_ continuation: AsyncStream<AVAudioPCMBuffer>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func yield(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.yield(buffer)
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }
}
