import Speech
import AVFoundation

/// Streaming transcription engine using Apple SpeechAnalyzer (macOS 26+).
/// Audio buffers are fed during recording; results stream back in real time.
@available(macOS 26, *)
final class TranscriptionEngine: @unchecked Sendable {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<String, Error>?

    /// Feed an audio buffer into the active session. Safe to call from any thread.
    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        continuation?.yield(AnalyzerInput(buffer: buffer))
    }

    /// Start a streaming transcription session.
    /// Returns the optimal audio format for the mic tap (nil = use default).
    @MainActor
    func startSession(
        onPartialResult: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> AVAudioFormat? {
        let transcriber = SpeechTranscriber(
            locale: .current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        // Ensure the locale's speech model is downloaded before starting
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let optimalFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        )

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.transcriber = transcriber
        self.continuation = continuation

        let analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [transcriber]
        )
        self.analyzer = analyzer

        // Collect results — append each finalized segment
        resultTask = Task { [transcriber] in
            var finalizedText = ""
            var currentVolatile = ""

            for try await result in transcriber.results {
                let text = String(result.text.characters)

                if result.isFinal {
                    // Each final result is an incremental segment — append it
                    if !finalizedText.isEmpty {
                        finalizedText += " "
                    }
                    finalizedText += text
                    currentVolatile = ""
                } else {
                    currentVolatile = text
                }

                // Show full text so far
                var display = finalizedText
                if !currentVolatile.isEmpty {
                    if !display.isEmpty { display += " " }
                    display += currentVolatile
                }
                await MainActor.run { onPartialResult(display) }
            }

            // Return everything including any trailing volatile text
            if !currentVolatile.isEmpty {
                if !finalizedText.isEmpty { finalizedText += " " }
                finalizedText += currentVolatile
            }
            return finalizedText
        }

        return optimalFormat
    }

    /// Stop the session and return the final transcription.
    @MainActor
    func finishSession() async throws -> String {
        continuation?.finish()
        continuation = nil

        try await analyzer?.finalizeAndFinishThroughEndOfInput()

        let result = try await resultTask?.value ?? ""

        transcriber = nil
        analyzer = nil
        resultTask = nil

        return result
    }
}
