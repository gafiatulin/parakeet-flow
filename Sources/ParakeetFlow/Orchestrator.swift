import SwiftUI
import AVFoundation

@available(macOS 26, *)
@MainActor
@Observable
final class Orchestrator {
    let appState: AppState
    private let audioCapture = AudioCaptureManager()
    private let transcriptionEngine = TranscriptionEngine()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()

    private var isInitialized = false
    private var recordingStartTask: Task<Void, Never>?
    private var isHandsFreeMode = false
    private var isRecordingOrPending = false
    private let holdThreshold: Double = 0.4

    init(appState: AppState) {
        self.appState = appState
    }

    func initialize() async {
        guard !isInitialized else { return }

        // Request microphone permission upfront (triggers system dialog)
        _ = await AVCaptureDevice.requestAccess(for: .audio)

        hotkeyManager.hotkeyModifier = appState.hotkeyChoice.eventFlag

        // Key down: start recording, or stop if in hands-free mode
        hotkeyManager.onKeyPress = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isHandsFreeMode {
                    // Second press in hands-free — stop immediately
                    self.requestStop()
                    await self.stopRecordingAndProcess()
                } else if !self.isRecordingOrPending {
                    // Start recording — show feedback immediately
                    self.isRecordingOrPending = true
                    self.appState.phase = .recording
                    self.appState.partialTranscription = nil
                    if self.appState.isAudioFeedbackEnabled {
                        AudioFeedbackManager.playStartSound()
                    }
                    if self.appState.isRecordingOverlayEnabled {
                        self.overlayController.show(colors: self.appState.waveformColor.colors)
                    }
                    self.recordingStartTask = Task {
                        await self.startRecording()
                    }
                }
            }
        }

        // Key up: push-to-talk stop or enter hands-free
        hotkeyManager.onKeyRelease = { [weak self] duration in
            Task { @MainActor in
                guard let self, self.isRecordingOrPending else { return }

                if duration < self.holdThreshold {
                    // Quick tap — enter hands-free mode, keep recording
                    self.isHandsFreeMode = true
                } else {
                    // Held past threshold — push-to-talk, stop on release
                    self.requestStop()
                    await self.stopRecordingAndProcess()
                }
            }
        }

        // Escape key — cancel recording
        hotkeyManager.onEscapeKey = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.requestStop()
                await self.cancelRecording()
            }
        }

        await startHotkeyWithRetry()
    }

    func updateHotkey(_ choice: HotkeyChoice) {
        hotkeyManager.stop()
        hotkeyManager.hotkeyModifier = choice.eventFlag
        let (success, error) = hotkeyManager.start()
        if !success {
            appState.phase = .error
            appState.errorMessage = error ?? "Failed to restart hotkey"
        }
    }

    private var permissionPollTask: Task<Void, Never>?

    private func startHotkeyWithRetry() async {
        let (success, error) = hotkeyManager.start()
        if success {
            isInitialized = true
            return
        }

        appState.phase = .error
        appState.errorMessage = error ?? "Permission required"
        startPermissionPolling()
    }

    /// Polls for all three permissions (Input Monitoring, Accessibility, Microphone)
    /// every 2 seconds. Auto-starts the hotkey tap as soon as all are granted.
    private func startPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                let (listen, ax) = HotkeyManager.permissionStatus()
                let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

                if listen && ax && mic {
                    let (success, _) = hotkeyManager.start()
                    if success {
                        appState.phase = .idle
                        appState.errorMessage = nil
                        isInitialized = true
                        permissionPollTask = nil
                        return
                    }
                } else {
                    // Update error message to reflect what's still missing
                    var missing: [String] = []
                    if !listen { missing.append("Input Monitoring") }
                    if !ax { missing.append("Accessibility") }
                    if !mic { missing.append("Microphone") }
                    appState.errorMessage = "Grant \(missing.joined(separator: " and ")) permission\(missing.count > 1 ? "s" : ""), then retry."
                }
            }
        }
    }

    /// Synchronously signal that recording should stop.
    /// Never awaits — the start task detects this via `isRecordingOrPending` and cleans up itself.
    private func requestStop() {
        isRecordingOrPending = false
        isHandsFreeMode = false
        recordingStartTask?.cancel()
        recordingStartTask = nil
    }

    /// Starts the transcription engine and audio capture.
    /// Phase, overlay, and sound are already set by the caller.
    private func startRecording() async {
        guard appState.phase == .recording else { return }

        do {
            let optimalFormat = try await transcriptionEngine.startSession { [weak self] partial in
                self?.appState.partialTranscription = partial
            }

            // Stop requested while starting session?
            guard isRecordingOrPending else {
                _ = try? await transcriptionEngine.finishSession()
                cleanUpRecordingUI()
                return
            }

            try await audioCapture.startCapture(targetFormat: optimalFormat) { [transcriptionEngine] buffer in
                transcriptionEngine.feedAudio(buffer)
            }

            // Stop requested while starting capture?
            guard isRecordingOrPending else {
                await audioCapture.stopCapture()
                _ = try? await transcriptionEngine.finishSession()
                cleanUpRecordingUI()
                return
            }
        } catch {
            if appState.isRecordingOverlayEnabled {
                overlayController.dismiss()
            }
            // If canceled/stopped, go idle silently; otherwise show error
            if isRecordingOrPending {
                isRecordingOrPending = false
                appState.phase = .error
                appState.errorMessage = "Recording error: \(error.localizedDescription)"
                resetAfterDelay()
            } else {
                appState.partialTranscription = nil
                appState.phase = .idle
            }
        }
    }

    /// Reset UI after an aborted recording start.
    private func cleanUpRecordingUI() {
        if appState.isRecordingOverlayEnabled {
            overlayController.dismiss()
        }
        appState.partialTranscription = nil
        appState.phase = .idle
    }

    private func stopRecordingAndProcess() async {
        guard appState.phase == .recording else { return }

        if appState.isAudioFeedbackEnabled {
            AudioFeedbackManager.playStopSound()
        }
        if appState.isRecordingOverlayEnabled {
            overlayController.dismiss()
        }

        await audioCapture.stopCapture()

        let rawText: String
        do {
            rawText = try await transcriptionEngine.finishSession()
        } catch {
            appState.phase = .error
            appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
            resetAfterDelay()
            return
        }

        appState.partialTranscription = nil

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appState.phase = .idle
            return
        }

        // Filler word removal
        var processedText = rawText
        if appState.isFillerRemovalEnabled {
            processedText = FillerWordFilter.removeFillersFromText(processedText)
        }

        // LLM cleanup (if enabled and available)
        var finalText = processedText
        let context = ContextReader.readCurrentContext()
        let llmEnabled = appState.isLLMEnabled
        let llmAvailable = PostProcessor.isAvailable

        if llmEnabled && llmAvailable {
            appState.phase = .processing
            do {
                finalText = try await PostProcessor.cleanup(
                    rawText: processedText, context: context,
                    removeFillers: !appState.isFillerRemovalEnabled
                )
            } catch {
                finalText = processedText
            }
        }

        // Insert text
        appState.phase = .inserting
        await TextInserter.insert(finalText)

        // Record and reset
        let filterRan = appState.isFillerRemovalEnabled
        let llmRan = appState.isLLMEnabled && PostProcessor.isAvailable
        let filtered = processedText != rawText ? processedText : nil
        let cleaned = finalText != (filtered ?? rawText) ? finalText : nil
        appState.addTranscription(raw: rawText, filtered: filtered, cleaned: cleaned,
                                  context: context, filterRan: filterRan, llmRan: llmRan)
        appState.phase = .idle
    }

    private func cancelRecording() async {
        guard appState.phase == .recording else { return }

        if appState.isAudioFeedbackEnabled {
            AudioFeedbackManager.playStopSound()
        }
        if appState.isRecordingOverlayEnabled {
            overlayController.dismiss()
        }

        await audioCapture.stopCapture()
        _ = try? await transcriptionEngine.finishSession()

        appState.partialTranscription = nil
        appState.phase = .idle
    }

    private func resetAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            appState.phase = .idle
            appState.errorMessage = nil
        }
    }
}
