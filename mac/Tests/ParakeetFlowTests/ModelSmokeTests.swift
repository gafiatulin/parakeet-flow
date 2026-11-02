import AVFoundation
import Foundation
import Testing
@testable import ParakeetFlow

/// Opt-in tests that download real models and transcribe generated speech.
/// Run with `touch /tmp/parakeetflow-run-model-smoke` then target a test with
/// `xcodebuild test ... -only-testing:ParakeetFlowTests/ModelSmokeTests/<name>`.
@Suite("Model smoke")
struct ModelSmokeTests {
    private static let enabled = FileManager.default.fileExists(
        atPath: "/tmp/parakeetflow-run-model-smoke"
    )

    @Test func bark3TranscribesGeneratedSpeech() async throws {
        guard Self.enabled else { return }
        let engine = ParakeetEngine(version: .bark3)
        let text = try await transcribe(engine)
        #expect(text.lowercased().contains("quick brown fox"))
    }

    @Test func qwen3TranscribesGeneratedSpeech() async throws {
        guard Self.enabled else { return }
        let engine = Qwen3AsrEngine()
        let text = try await transcribe(engine)
        #expect(text.lowercased().contains("quick brown fox"))
    }

    @Test func nemotronStreamsGeneratedSpeech() async throws {
        guard Self.enabled else { return }
        let engine = NemotronStreamingEngine()
        let text = try await transcribe(engine)
        #expect(text.lowercased().contains("quick brown fox"))
    }

    @Test func cleanupModelCleansGeneratedTranscript() async throws {
        guard Self.enabled else { return }
        let processor = MLXPostProcessor(modelID: MlxModelChoice.qwen35_08b_cleanup.modelID)
        try await processor.ensureModelLoaded()
        let cleaned = try await processor.cleanup(
            rawText: "um so the meeting is like at three thirty tomorrow",
            context: AppContext(
                appName: "Testing",
                appBundleIdentifier: nil,
                windowTitle: nil,
                surroundingText: nil
            )
        )
        #expect(cleaned.lowercased().contains("meeting"))
        #expect(!cleaned.lowercased().contains("um"))
    }

    private func transcribe(_ engine: ParakeetEngine) async throws -> String {
        let samples = try GeneratedSpeech.samples()
        try await engine.ensureModelLoaded()
        await engine.startSession { _ in }
        feed(samples, to: { buffer in engine.feedAudio(buffer) })
        return try await engine.finishSession()
    }

    private func transcribe(_ engine: Qwen3AsrEngine) async throws -> String {
        let samples = try GeneratedSpeech.samples()
        try await engine.ensureModelLoaded()
        await engine.startSession { _ in }
        feed(samples, to: { buffer in engine.feedAudio(buffer) })
        return try await engine.finishSession()
    }

    private func transcribe(_ engine: NemotronStreamingEngine) async throws -> String {
        let samples = try GeneratedSpeech.samples()
        try await engine.ensureModelLoaded()
        await engine.startSession { _ in }
        feed(samples, to: { buffer in engine.feedAudio(buffer) })
        return try await engine.finishSession()
    }

    private func feed(_ samples: [Float], to receive: (AVAudioPCMBuffer) -> Void) {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        let chunkSize = 1600
        var offset = 0
        while offset < samples.count {
            let count = min(chunkSize, samples.count - offset)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(
                    from: source.baseAddress!.advanced(by: offset),
                    count: count
                )
            }
            receive(buffer)
            offset += count
        }
    }
}

private enum GeneratedSpeech {
    static func samples() throws -> [Float] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParakeetFlowSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let aiff = directory.appendingPathComponent("speech.aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", aiff.path, "The quick brown fox jumps over the lazy dog."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SpeechGenerationError.sayFailed
        }

        let file = try AVAudioFile(forReading: aiff)
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        let converter = AVAudioConverter(from: file.processingFormat, to: target)!
        let input = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: input)
        let outputFrames = AVAudioFrameCount(
            Double(file.length) * target.sampleRate / file.processingFormat.sampleRate
        ) + 1024
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputFrames)!
        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard let data = output.floatChannelData else {
            throw SpeechGenerationError.noSamples
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }

    enum SpeechGenerationError: Error {
        case sayFailed
        case noSamples
    }
}
