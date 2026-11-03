import SwiftUI
import SwiftData
import AVFoundation
import FluidAudio

@available(macOS 26, *)
@MainActor
@Observable
final class Orchestrator {
    let appState: AppState
    private let modelContainer: ModelContainer
    private let audioCapture = AudioCaptureManager()
    private let transcriptionEngine = TranscriptionEngine()
    private let parakeetV2Engine: ParakeetEngine
    private let parakeetUltraEngine: ParakeetEngine
    private let bark3Engine: ParakeetEngine
    private let bark3CleanEngine: ParakeetEngine
    private let qwen3Engine: Qwen3AsrEngine
    private let nemotronEngine: NemotronStreamingEngine
    private let mlxPostProcessor = MLXPostProcessor()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()

    private var useBatchEngine: Bool { appState.asrBackend != .apple }

    private(set) var isInitialized = false
    private var recordingStartTask: Task<Void, Never>?
    private var isHandsFreeMode = false
    private var isRecordingOrPending = false
    private let holdThreshold: Double = 0.4
    private var modelUnloadTask: Task<Void, Never>?
    private var recordingStartedAt: Date?

    init(appState: AppState, modelContainer: ModelContainer) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.parakeetV2Engine = ParakeetEngine(version: .v2)
        self.parakeetUltraEngine = ParakeetEngine(version: .ultra)
        self.bark3Engine = ParakeetEngine(version: .bark3)
        self.bark3CleanEngine = ParakeetEngine(version: .bark3Clean)
        self.qwen3Engine = Qwen3AsrEngine()
        self.nemotronEngine = NemotronStreamingEngine()
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
                if self.appState.hotkeyMode == .toggle, self.isRecordingOrPending {
                    // Toggle mode: the second press finishes the recording.
                    self.requestStop()
                    await self.stopRecordingAndProcess()
                } else if self.isHandsFreeMode {
                    // Second press in hands-free — stop immediately
                    self.requestStop()
                    await self.stopRecordingAndProcess()
                } else if !self.isRecordingOrPending {
                    // Check for usable mic before showing any UI
                    guard AudioCaptureManager.hasUsableAudioInput() else {
                        self.appState.phase = .error
                        self.appState.errorMessage = AudioCaptureError.noInputDevice.localizedDescription
                        if self.appState.isAudioFeedbackEnabled {
                            NSSound(named: "Funk")?.play()
                        }
                        self.resetAfterDelay()
                        return
                    }

                    // Start recording — show feedback immediately
                    self.modelUnloadTask?.cancel()
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
                guard let self, self.appState.hotkeyMode == .hold else { return }
                guard self.isRecordingOrPending else { return }

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
        checkModelStatus()
        checkLlmModelStatus()
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

    /// Polls for permissions (Accessibility, Microphone) every 2 seconds.
    /// Auto-starts the hotkey tap as soon as all are granted.
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
                    var missing: [String] = []
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

        recordingStartedAt = .now
        do {
            if useBatchEngine {
                switch appState.asrBackend {
                case .parakeetV2:
                    try await parakeetV2Engine.ensureModelLoaded()
                case .parakeetUltra:
                    try await parakeetUltraEngine.ensureModelLoaded()
                case .bark3:
                    try await bark3Engine.ensureModelLoaded()
                case .bark3Clean:
                    try await bark3CleanEngine.ensureModelLoaded()
                case .qwen3Asr:
                    try await qwen3Engine.ensureModelLoaded()
                case .nemotronStreaming:
                    try await nemotronEngine.ensureModelLoaded()
                case .apple:
                    break
                }

                guard isRecordingOrPending else {
                    cleanUpRecordingUI()
                    return
                }

                await batchStartSession { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.appState.partialTranscription = text
                    }
                }

                guard isRecordingOrPending else {
                    await batchCancelSession()
                    cleanUpRecordingUI()
                    return
                }

                let format = batchTargetFormat()
                let feedAudio = batchFeedAudioClosure()

                try await audioCapture.startCapture(targetFormat: format) { buffer in
                    feedAudio(buffer)
                }

                guard isRecordingOrPending else {
                    await audioCapture.stopCapture()
                    cleanUpRecordingUI()
                    return
                }
            } else {
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
            }
        } catch {
            recordingStartedAt = nil
            await batchCancelSession()
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
        let audioDurationMs = recordingStartedAt.map {
            max(0, Int(Date.now.timeIntervalSince($0) * 1000))
        } ?? 0
        recordingStartedAt = nil

        let processingStart = CFAbsoluteTimeGetCurrent()
        let rawText: String
        let asrDurationMs: Int
        do {
            let asrStart = CFAbsoluteTimeGetCurrent()
            if useBatchEngine {
                appState.phase = .processing
                rawText = try await batchFinishSession()
            } else {
                rawText = try await transcriptionEngine.finishSession()
            }
            asrDurationMs = Int((CFAbsoluteTimeGetCurrent() - asrStart) * 1000)
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
        let filterRan = appState.isFillerRemovalEnabled
        if filterRan {
            processedText = FillerWordFilter.removeFillersFromText(processedText)
        }

        // Dictionary correction (fuzzy + phonetic matching)
        var dictCorrectedText = processedText
        let dictionaryRan = appState.isDictionaryEnabled
        if dictionaryRan {
            let words = fetchDictionaryWords()
            if !words.isEmpty {
                dictCorrectedText = DictionaryCorrector.applyCorrections(
                    processedText, dictionary: words,
                    threshold: appState.dictionaryThreshold
                )
            }
        }

        // LLM cleanup (if enabled and available)
        var finalText = dictCorrectedText
        let context = ContextReader.readCurrentContext()
        let llmEnabled = appState.isLLMEnabled
        let llmBackend = appState.llmBackend
        let llmAvailable = PostProcessor.isAvailable(backend: llmBackend)

        var llmDurationMs = 0
        if llmEnabled && llmAvailable {
            appState.phase = .processing
            let llmStart = CFAbsoluteTimeGetCurrent()
            do {
                if llmBackend == .mlx {
                    mlxPostProcessor.switchModel(to: appState.mlxModel.modelID)
                    try await mlxPostProcessor.ensureModelLoaded()
                }
                let dictionaryWords = dictionaryRan
                    ? DictionaryCorrector.relevantWords(from: fetchDictionaryWords(), for: dictCorrectedText)
                    : []
                finalText = try await PostProcessor.cleanup(
                    rawText: dictCorrectedText, context: context,
                    removeFillers: !filterRan,
                    dictionaryWords: dictionaryWords,
                    backend: llmBackend, mlxEngine: mlxPostProcessor
                )
            } catch {
                finalText = dictCorrectedText
            }
            llmDurationMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1000)
        }

        // Insert text
        appState.phase = .inserting
        _ = await TextInserter.insert(finalText, method: appState.pasteMethod)

        // Record to SwiftData
        let llmRan = llmEnabled && llmAvailable
        let filtered = processedText != rawText ? processedText : nil
        let dictCorrected = dictCorrectedText != processedText ? dictCorrectedText : nil
        let cleaned = finalText != (dictCorrected ?? filtered ?? rawText) ? finalText : nil
        let totalDurationMs = Int((CFAbsoluteTimeGetCurrent() - processingStart) * 1000)
        saveTranscription(
            rawText: rawText, filteredText: filtered,
            dictionaryCorrectedText: dictCorrected, cleanedText: cleaned,
            context: context, filterRan: filterRan,
            dictionaryRan: dictionaryRan, llmRan: llmRan,
            audioDurationMs: audioDurationMs, asrDurationMs: asrDurationMs,
            llmDurationMs: llmDurationMs, totalDurationMs: totalDurationMs
        )
        appState.phase = .idle
        scheduleModelUnload()
    }

    private func cancelRecording() async {
        guard appState.phase == .recording else { return }
        recordingStartedAt = nil

        if appState.isAudioFeedbackEnabled {
            AudioFeedbackManager.playStopSound()
        }
        if appState.isRecordingOverlayEnabled {
            overlayController.dismiss()
        }

        await audioCapture.stopCapture()
        if useBatchEngine {
            await batchCancelSession()
        } else {
            _ = try? await transcriptionEngine.finishSession()
        }

        appState.partialTranscription = nil
        appState.phase = .idle
    }

    // MARK: - Batch engine helpers

    private func batchStartSession(onPartial: @escaping @Sendable (String) -> Void) async {
        switch appState.asrBackend {
        case .parakeetV2: await parakeetV2Engine.startSession(onPartial: onPartial)
        case .parakeetUltra: await parakeetUltraEngine.startSession(onPartial: onPartial)
        case .bark3: await bark3Engine.startSession(onPartial: onPartial)
        case .bark3Clean: await bark3CleanEngine.startSession(onPartial: onPartial)
        case .qwen3Asr: await qwen3Engine.startSession(onPartial: onPartial)
        case .nemotronStreaming: await nemotronEngine.startSession(onPartial: onPartial)
        case .apple: break
        }
    }

    private func batchCancelSession() async {
        switch appState.asrBackend {
        case .parakeetV2: await parakeetV2Engine.cancelSession()
        case .parakeetUltra: await parakeetUltraEngine.cancelSession()
        case .bark3: await bark3Engine.cancelSession()
        case .bark3Clean: await bark3CleanEngine.cancelSession()
        case .qwen3Asr: await qwen3Engine.cancelSession()
        case .nemotronStreaming: await nemotronEngine.cancelSession()
        case .apple: break
        }
    }

    /// Returns a Sendable closure that feeds audio to the active batch engine.
    /// Captures the engine reference so it can be called from the audio tap thread.
    private func batchFeedAudioClosure() -> @Sendable (AVAudioPCMBuffer) -> Void {
        switch appState.asrBackend {
        case .parakeetV2:
            let engine = parakeetV2Engine
            return { buffer in engine.feedAudio(buffer) }
        case .parakeetUltra:
            let engine = parakeetUltraEngine
            return { buffer in engine.feedAudio(buffer) }
        case .bark3:
            let engine = bark3Engine
            return { buffer in engine.feedAudio(buffer) }
        case .bark3Clean:
            let engine = bark3CleanEngine
            return { buffer in engine.feedAudio(buffer) }
        case .qwen3Asr:
            let engine = qwen3Engine
            return { buffer in engine.feedAudio(buffer) }
        case .nemotronStreaming:
            let engine = nemotronEngine
            return { buffer in engine.feedAudio(buffer) }
        case .apple:
            return { _ in }
        }
    }

    private func batchTargetFormat() -> AVAudioFormat? {
        switch appState.asrBackend {
        case .parakeetV2: return parakeetV2Engine.targetFormat
        case .parakeetUltra: return parakeetUltraEngine.targetFormat
        case .bark3: return bark3Engine.targetFormat
        case .bark3Clean: return bark3CleanEngine.targetFormat
        case .qwen3Asr: return qwen3Engine.targetFormat
        case .nemotronStreaming: return nemotronEngine.targetFormat
        case .apple: return nil
        }
    }

    private func batchFinishSession() async throws -> String {
        switch appState.asrBackend {
        case .parakeetV2: return try await parakeetV2Engine.finishSession()
        case .parakeetUltra: return try await parakeetUltraEngine.finishSession()
        case .bark3: return try await bark3Engine.finishSession()
        case .bark3Clean: return try await bark3CleanEngine.finishSession()
        case .qwen3Asr: return try await qwen3Engine.finishSession()
        case .nemotronStreaming: return try await nemotronEngine.finishSession()
        case .apple: return ""
        }
    }

    // MARK: - Benchmark

    @MainActor
    func runBenchmark() async -> ModelBenchmarkResult? {
        guard let samples = try? BenchmarkAudio.samples() else { return nil }
        let audioMilliseconds = Double(samples.count) / 16.0
        let backend = appState.asrBackend.label

        switch appState.asrBackend {
        case .parakeetV2:
            return await benchmark(parakeetV2Engine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        case .parakeetUltra:
            return await benchmark(parakeetUltraEngine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        case .bark3:
            return await benchmark(bark3Engine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        case .bark3Clean:
            return await benchmark(bark3CleanEngine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        case .qwen3Asr:
            return await benchmark(qwen3Engine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        case .nemotronStreaming:
            return await benchmark(nemotronEngine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        case .apple:
            return await benchmark(transcriptionEngine, backend: backend, samples: samples, audioMilliseconds: audioMilliseconds)
        }
    }

    private func benchmark(
        _ engine: ParakeetEngine, backend: String, samples: [Float], audioMilliseconds: Double
    ) async -> ModelBenchmarkResult {
        let loadStart = CFAbsoluteTimeGetCurrent()
        do {
            try await engine.ensureModelLoaded()
            let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
            await engine.startSession { _ in }
            feed(samples) { engine.feedAudio($0) }
            let inferenceStart = CFAbsoluteTimeGetCurrent()
            let text = try await engine.finishSession()
            let inferenceMs = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: loadMs,
                inferenceMilliseconds: inferenceMs,
                audioMilliseconds: audioMilliseconds, transcript: text
            )
        } catch {
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: 0, inferenceMilliseconds: 0,
                audioMilliseconds: audioMilliseconds, transcript: "Failed: \(error.localizedDescription)"
            )
        }
    }

    private func benchmark(
        _ engine: Qwen3AsrEngine, backend: String, samples: [Float], audioMilliseconds: Double
    ) async -> ModelBenchmarkResult {
        let loadStart = CFAbsoluteTimeGetCurrent()
        do {
            try await engine.ensureModelLoaded()
            let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
            await engine.startSession { _ in }
            feed(samples) { engine.feedAudio($0) }
            let inferenceStart = CFAbsoluteTimeGetCurrent()
            let text = try await engine.finishSession()
            let inferenceMs = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: loadMs,
                inferenceMilliseconds: inferenceMs,
                audioMilliseconds: audioMilliseconds, transcript: text
            )
        } catch {
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: 0, inferenceMilliseconds: 0,
                audioMilliseconds: audioMilliseconds, transcript: "Failed: \(error.localizedDescription)"
            )
        }
    }

    private func benchmark(
        _ engine: NemotronStreamingEngine, backend: String, samples: [Float], audioMilliseconds: Double
    ) async -> ModelBenchmarkResult {
        let loadStart = CFAbsoluteTimeGetCurrent()
        do {
            try await engine.ensureModelLoaded()
            let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
            await engine.startSession { _ in }
            feed(samples) { engine.feedAudio($0) }
            let inferenceStart = CFAbsoluteTimeGetCurrent()
            let text = try await engine.finishSession()
            let inferenceMs = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: loadMs,
                inferenceMilliseconds: inferenceMs,
                audioMilliseconds: audioMilliseconds, transcript: text
            )
        } catch {
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: 0, inferenceMilliseconds: 0,
                audioMilliseconds: audioMilliseconds, transcript: "Failed: \(error.localizedDescription)"
            )
        }
    }

    private func benchmark(
        _ engine: TranscriptionEngine, backend: String, samples: [Float], audioMilliseconds: Double
    ) async -> ModelBenchmarkResult {
        let inferenceStart = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await engine.startSession { _ in }
            feed(samples) { engine.feedAudio($0) }
            let text = try await engine.finishSession()
            let inferenceMs = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: 0,
                inferenceMilliseconds: inferenceMs,
                audioMilliseconds: audioMilliseconds, transcript: text
            )
        } catch {
            return ModelBenchmarkResult(
                backend: backend, loadMilliseconds: 0, inferenceMilliseconds: 0,
                audioMilliseconds: audioMilliseconds, transcript: "Failed: \(error.localizedDescription)"
            )
        }
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

    // MARK: - Model status

    func checkModelStatus() {
        let backend = appState.asrBackend
        guard backend.needsDownload else { return }
        // Don't overwrite if already downloading
        if case .downloading = appState.modelStatusByBackend[backend] { return }
        if backend == .qwen3Asr {
            Task {
                let ready = await qwen3Engine.isModelReady()
                appState.modelStatusByBackend[backend] = ready ? .ready : .notDownloaded
            }
            return
        }
        let dir = Self.cacheDirectory(for: backend)
        let exists: Bool
        switch backend {
        case .parakeetV2:
            exists = AsrModels.modelsExist(at: dir, version: .v2)
        case .parakeetUltra:
            exists = AsrModels.modelsExist(at: dir, version: .ultra)
        case .bark3:
            exists = AsrModels.modelsExist(at: dir, version: .bark3)
        case .bark3Clean:
            exists = AsrModels.modelsExist(at: dir, version: .bark3Clean)
        case .qwen3Asr:
            // Handled by the async availability check above.
            exists = false
        case .nemotronStreaming:
            exists = nemotronEngine.isModelDownloaded()
        case .apple:
            exists = true
        }
        appState.modelStatusByBackend[backend] = exists ? .ready : .notDownloaded
    }

    private var downloadProgressTasks: [AsrBackend: Task<Void, Never>] = [:]
    private var downloadTasks: [AsrBackend: Task<Void, Error>] = [:]

    func downloadModel() {
        let backend = appState.asrBackend
        guard backend.needsDownload else { return }
        appState.modelStatusByBackend[backend] = .downloading(progress: 0)

        let cacheDir = Self.cacheDirectory(for: backend)
        let expectedBytes = Self.expectedModelBytes(for: backend)

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                let currentSize = Self.directorySize(cacheDir)
                let fraction = min(Double(currentSize) / Double(expectedBytes), 0.99)
                appState.modelStatusByBackend[backend] = .downloading(progress: fraction)
            }
        }
        downloadProgressTasks[backend] = progressTask

        let downloadTask = Task {
            switch backend {
            case .parakeetV2:
                try await parakeetV2Engine.ensureModelLoaded()
            case .parakeetUltra:
                try await parakeetUltraEngine.ensureModelLoaded()
            case .bark3:
                try await bark3Engine.ensureModelLoaded()
            case .bark3Clean:
                try await bark3CleanEngine.ensureModelLoaded()
            case .qwen3Asr:
                let appState = self.appState
                try await qwen3Engine.ensureModelLoaded { fraction in
                    Task { @MainActor in
                        appState.modelStatusByBackend[.qwen3Asr] = .downloading(progress: fraction)
                    }
                }
            case .nemotronStreaming:
                try await nemotronEngine.ensureModelLoaded()
            case .apple:
                break
            }
        }
        downloadTasks[backend] = downloadTask

        Task {
            do {
                try await downloadTask.value
                progressTask.cancel()
                downloadProgressTasks[backend] = nil
                downloadTasks[backend] = nil
                appState.modelStatusByBackend[backend] = .ready
            } catch is CancellationError {
                progressTask.cancel()
                downloadProgressTasks[backend] = nil
                downloadTasks[backend] = nil
                Self.removeModelCache(for: backend)
                appState.modelStatusByBackend[backend] = .notDownloaded
            } catch {
                progressTask.cancel()
                downloadProgressTasks[backend] = nil
                downloadTasks[backend] = nil
                appState.modelStatusByBackend[backend] = .error(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        let backend = appState.asrBackend
        downloadTasks[backend]?.cancel()
    }

    func deleteModel() {
        let backend = appState.asrBackend
        guard backend.needsDownload else { return }
        Self.removeModelCache(for: backend)
        appState.modelStatusByBackend[backend] = .notDownloaded
    }

    func revealModelCache() {
        let dir = Self.fluidAudioModelsRoot()
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.deletingLastPathComponent().path)
        }
    }

    func deleteAllModels() {
        // Cancel any active downloads
        for (backend, task) in downloadTasks {
            task.cancel()
            downloadProgressTasks[backend]?.cancel()
        }
        downloadTasks.removeAll()
        downloadProgressTasks.removeAll()

        // Remove each backend's cache directory
        for backend in AsrBackend.allCases where backend.needsDownload {
            Self.removeModelCache(for: backend)
            appState.modelStatusByBackend[backend] = .notDownloaded
        }
    }

    private static func cacheDirectory(for backend: AsrBackend) -> URL {
        switch backend {
        case .parakeetV2: return AsrModels.defaultCacheDirectory(for: .v2)
        case .parakeetUltra: return AsrModels.defaultCacheDirectory(for: .ultra)
        case .bark3: return AsrModels.defaultCacheDirectory(for: .bark3)
        case .bark3Clean: return AsrModels.defaultCacheDirectory(for: .bark3Clean)
        case .qwen3Asr: return Qwen3AsrEngine.cacheDirectory
        case .nemotronStreaming: return NemotronStreamingEngine.cacheDirectory
        case .apple: return URL(fileURLWithPath: "/dev/null")
        }
    }

    private static func expectedModelBytes(for backend: AsrBackend) -> Int64 {
        switch backend {
        case .parakeetV2: return 473_000_000
        case .parakeetUltra: return 630_000_000
        case .bark3: return 420_000_000
        case .bark3Clean: return 430_000_000
        case .qwen3Asr: return 945_000_000
        case .nemotronStreaming: return 1_500_000_000
        case .apple: return 1
        }
    }

    private static func removeModelCache(for backend: AsrBackend) {
        guard backend.needsDownload else { return }
        try? FileManager.default.removeItem(at: cacheDirectory(for: backend))
    }

    // MARK: - LLM model management

    func switchMlxModel(to choice: MlxModelChoice) {
        mlxPostProcessor.switchModel(to: choice.modelID)
        checkLlmModelStatus()
    }

    func checkLlmModelStatus() {
        for model in MlxModelChoice.allCases {
            if case .downloading = appState.mlxModelStatus[model] { continue }
            let exists = MLXPostProcessor.modelCacheExists(for: model.modelID)
            appState.mlxModelStatus[model] = exists ? .ready : .notDownloaded
        }
    }

    private var llmDownloadTask: Task<Void, Error>?

    func downloadLlmModel() {
        let model = appState.mlxModel
        appState.mlxModelStatus[model] = .downloading(progress: 0)
        mlxPostProcessor.switchModel(to: model.modelID)

        llmDownloadTask = Task {
            try await mlxPostProcessor.ensureModelLoaded { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.appState.mlxModelStatus[model] = .downloading(progress: progress.fractionCompleted)
                }
            }
        }

        Task {
            do {
                try await llmDownloadTask?.value
                llmDownloadTask = nil
                appState.mlxModelStatus[model] = .ready
            } catch is CancellationError {
                llmDownloadTask = nil
                deleteLlmModel()
            } catch {
                llmDownloadTask = nil
                appState.mlxModelStatus[model] = .error(error.localizedDescription)
            }
        }
    }

    func cancelLlmDownload() {
        llmDownloadTask?.cancel()
    }

    func deleteLlmModel() {
        let model = appState.mlxModel
        mlxPostProcessor.unload()
        let cacheDir = MLXPostProcessor.modelCacheDirectory(for: model.modelID)
        try? FileManager.default.removeItem(at: cacheDir)
        appState.mlxModelStatus[model] = .notDownloaded
    }

    func revealLlmModelCache() {
        let cacheDir = MLXPostProcessor.modelCacheDirectory(for: appState.mlxModel.modelID)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cacheDir.path)
        } else {
            let parent = cacheDir.deletingLastPathComponent()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parent.path)
        }
    }

    func deleteAllLlmModels() {
        llmDownloadTask?.cancel()
        llmDownloadTask = nil
        mlxPostProcessor.unload()
        for model in MlxModelChoice.allCases {
            let cacheDir = MLXPostProcessor.modelCacheDirectory(for: model.modelID)
            try? FileManager.default.removeItem(at: cacheDir)
            appState.mlxModelStatus[model] = .notDownloaded
        }
    }

    private static func fluidAudioModelsRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Dictionary & History helpers

    private func fetchDictionaryWords() -> [String] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DictionaryWord>()
        return (try? context.fetch(descriptor).map(\.word)) ?? []
    }

    private func saveTranscription(
        rawText: String, filteredText: String?,
        dictionaryCorrectedText: String?, cleanedText: String?,
        context: AppContext, filterRan: Bool,
        dictionaryRan: Bool, llmRan: Bool,
        audioDurationMs: Int, asrDurationMs: Int,
        llmDurationMs: Int, totalDurationMs: Int
    ) {
        let ctx = ModelContext(modelContainer)
        let entry = TranscriptionEntry(
            timestamp: .now,
            rawText: rawText,
            filteredText: filteredText,
            dictionaryCorrectedText: dictionaryCorrectedText,
            cleanedText: cleanedText,
            appName: context.appName,
            appBundleIdentifier: context.appBundleIdentifier,
            windowTitle: context.windowTitle,
            surroundingText: context.surroundingText,
            filterRan: filterRan,
            dictionaryRan: dictionaryRan,
            llmRan: llmRan,
            audioDurationMs: audioDurationMs,
            asrDurationMs: asrDurationMs,
            llmDurationMs: llmDurationMs,
            totalDurationMs: totalDurationMs
        )
        ctx.insert(entry)
        try? ctx.save()
    }

    private func resetAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            appState.phase = .idle
            appState.errorMessage = nil
        }
    }

    // MARK: - Model unloading after inactivity

    /// Reschedule the inactivity timer. Call after each transcription completes.
    private func scheduleModelUnload() {
        modelUnloadTask?.cancel()
        let minutes = appState.modelUnloadMinutes
        guard minutes > 0 else { return }

        modelUnloadTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            unloadAllModels()
        }
    }

    private func unloadAllModels() {
        if parakeetV2Engine.isLoaded { parakeetV2Engine.unload() }
        if parakeetUltraEngine.isLoaded { parakeetUltraEngine.unload() }
        if bark3Engine.isLoaded { bark3Engine.unload() }
        if bark3CleanEngine.isLoaded { bark3CleanEngine.unload() }
        qwen3Engine.unload()
        nemotronEngine.unload()
        if mlxPostProcessor.isLoaded { mlxPostProcessor.unload() }
    }
}
