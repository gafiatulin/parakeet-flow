import AVFoundation
import FluidAudio
import Foundation
import os

/// True cache-aware Nemotron 3.5 streaming ASR for multilingual dictation.
///
/// FluidAudio's multilingual Nemotron manager keeps encoder caches across
/// chunks, so partial text arrives while the microphone is still open.
final class NemotronStreamingEngine: @unchecked Sendable {
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())
    private let streamInput = SampleStreamInput()
    private let speechDetector = SpeechActivityDetector()
    private var manager: StreamingNemotronMultilingualAsrManager?
    private var feedTask: Task<Void, Never>?

    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
            .appendingPathComponent("multilingual", isDirectory: true)
            .appendingPathComponent("1120ms", isDirectory: true)
    }

    func ensureModelLoaded() async throws {
        guard manager == nil else { return }
        let shared = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
            languageCode: "auto",
            chunkMs: 1120
        )
        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadFromShared(shared)
        self.manager = manager
    }

    func isModelDownloaded() -> Bool {
        FileManager.default.fileExists(
            atPath: Self.cacheDirectory.appendingPathComponent("metadata.json").path
        )
    }

    func startSession(onPartial: @escaping @Sendable (String) -> Void) async {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
        await cancelSession()
        guard let manager else { return }

        await manager.reset()
        await manager.setLanguage(nil)
        await manager.setPartialCallback { text in
            if !text.isEmpty { onPartial(text) }
        }

        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        streamInput.set(continuation)
        feedTask = Task {
            for await chunk in stream {
                _ = try? await manager.process(samples: chunk)
            }
        }
    }

    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        samples.withLock { $0.append(contentsOf: chunk) }
        streamInput.yield(chunk)
    }

    var isLoaded: Bool { manager != nil }

    func cancelSession() async {
        streamInput.finish()
        feedTask?.cancel()
        await feedTask?.value
        feedTask = nil
        samples.withLock { $0.removeAll(keepingCapacity: false) }
        await manager?.reset()
    }

    func unload() {
        samples.withLock { $0.removeAll(keepingCapacity: false) }
        Task {
            streamInput.finish()
            feedTask?.cancel()
            await feedTask?.value
            feedTask = nil
            await manager?.cleanup()
            await speechDetector.unload()
            manager = nil
        }
    }

    func finishSession() async throws -> String {
        guard let manager else { throw NemotronStreamingError.notInitialized }
        let audioSamples = samples.withLock { Array($0) }
        guard audioSamples.count >= 16_000 else {
            await cancelSession()
            return ""
        }
        guard await speechDetector.containsSpeech(audioSamples) else {
            await cancelSession()
            return ""
        }

        streamInput.finish()
        await feedTask?.value
        feedTask = nil
        let text = try await manager.finish()
        await manager.reset()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class SampleStreamInput: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<[Float]>.Continuation?

    func set(_ continuation: AsyncStream<[Float]>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func yield(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.yield(samples)
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }
}

enum NemotronStreamingError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        "Nemotron streaming engine not initialized. Download the model first."
    }
}
