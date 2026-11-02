import FluidAudio
import Foundation

/// Lightweight speech gate backed by FluidAudio's Silero VAD.
///
/// The gate prevents silent recordings from reaching Parakeet, where they can
/// become hallucinated closing phrases ("thank you", "bye"). It fails open:
/// if the VAD model cannot be loaded or run, transcription proceeds normally.
actor SpeechActivityDetector {
    private var manager: VadManager?
    private var unavailable = false

    /// Download/load the VAD model ahead of the first dictation.
    func prewarm() async {
        _ = await loadManager()
    }

    /// Whether the clip contains enough speech to be worth transcribing.
    func containsSpeech(_ samples: [Float]) async -> Bool {
        guard samples.count >= VadManager.chunkSize else { return false }
        guard let manager = await loadManager() else { return true }

        do {
            let results = try await manager.process(samples)
            guard !results.isEmpty else { return false }
            let peak = results.map(\.probability).max() ?? 0
            let active = results.filter { $0.probability >= 0.30 }.count
            return peak >= 0.30 && active >= 1
        } catch {
            // Never drop a recording because the gate itself failed.
            return true
        }
    }

    func unload() {
        manager = nil
        unavailable = false
    }

    private func loadManager() async -> VadManager? {
        if let manager { return manager }
        if unavailable { return nil }

        do {
            let manager = try await VadManager()
            self.manager = manager
            return manager
        } catch {
            unavailable = true
            return nil
        }
    }
}
