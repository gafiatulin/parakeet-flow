import AVFoundation
import Foundation

struct ModelBenchmarkResult: Sendable {
    let backend: String
    let loadMilliseconds: Double
    let inferenceMilliseconds: Double
    let audioMilliseconds: Double
    let transcript: String

    var realtimeFactor: Double {
        guard inferenceMilliseconds > 0 else { return 0 }
        return audioMilliseconds / inferenceMilliseconds
    }
}

enum BenchmarkAudio {
    enum BenchmarkAudioError: LocalizedError {
        case generationFailed
        case noSamples

        var errorDescription: String? {
            switch self {
            case .generationFailed: "The system speech synthesizer failed."
            case .noSamples: "The benchmark audio contained no samples."
            }
        }
    }

    static func samples() throws -> [Float] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParakeetFlowBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let aiff = directory.appendingPathComponent("speech.aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [
            "-o", aiff.path,
            "The quick brown fox jumps over the lazy dog. This is a local dictation benchmark."
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BenchmarkAudioError.generationFailed
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
            throw BenchmarkAudioError.noSamples
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
