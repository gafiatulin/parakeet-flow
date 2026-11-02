import AnySpeechRecognizer
import AVFoundation
import Foundation
import HuggingFace
import os

/// Batch Qwen3-ASR engine for 30 languages and 22 Chinese dialects.
///
/// AnySpeechRecognizer's Qwen provider is file-oriented, so samples are written
/// to a temporary 16 kHz WAV before transcription. The model runs locally on
/// Core ML; no audio leaves the machine.
final class Qwen3AsrEngine: @unchecked Sendable {
    private let variant: QwenSpeechModel.Variant
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())
    private let speechDetector = SpeechActivityDetector()

    static var cacheDirectory: URL {
        guard let repo = Repo.ID(rawValue: "mattt/qwen3-asr-0.6b-coreml") else {
            return HubCache.default.cacheDirectory
        }
        return HubCache.default.repoDirectory(repo: repo, kind: .model)
    }

    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(variant: QwenSpeechModel.Variant = .small) {
        self.variant = variant
    }

    func ensureModelLoaded(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let model = QwenSpeechModel(variant: variant)
        guard let request = try await model.assetInstallationRequest() else { return }

        let progressTask: Task<Void, Never>? = progress.map { handler in
            Task {
                while !Task.isCancelled {
                    handler(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        defer { progressTask?.cancel() }
        try await request.downloadAndInstall()
        progress?(1)
    }

    func isModelReady() async -> Bool {
        await QwenSpeechModel(variant: variant).availability() == .ready
    }

    func startSession(onPartial: @escaping @Sendable (String) -> Void) async {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
    }

    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        samples.withLock { $0.append(contentsOf: chunk) }
    }

    var isLoaded: Bool { false }

    func unload() {
        samples.withLock { $0.removeAll(keepingCapacity: false) }
        Task { await speechDetector.unload() }
    }

    func cancelSession() async {
        samples.withLock { $0.removeAll(keepingCapacity: false) }
    }

    func finishSession() async throws -> String {
        let audioSamples = samples.withLock { Array($0) }
        guard audioSamples.count >= 16_000 else { return "" }
        guard await speechDetector.containsSpeech(audioSamples) else { return "" }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeetflow-qwen-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeWav(audioSamples, to: url)

        let model = QwenSpeechModel(variant: variant)
        let transcriber = SpeechTranscriber(
            model: model,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let resultTask = Task {
            var text = AttributedString()
            for try await result in transcriber.results {
                text.append(result.text)
            }
            return String(text.characters)
        }

        do {
            let file = try AVAudioFile(forReading: url)
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await resultTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            resultTask.cancel()
            throw error
        }
    }

    private func writeWav(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
