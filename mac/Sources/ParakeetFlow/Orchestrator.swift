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
    private let parakeetEngine: ParakeetEngine
    private let qwen3Engine: Qwen3AsrEngine
    private let qwen3Int8Engine: Qwen3AsrEngine
    private let mlxPostProcessor = MLXPostProcessor()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()

    private var useBatchEngine: Bool { appState.asrBackend != .apple }

    private var isInitialized = false
    private var recordingStartTask: Task<Void, Never>?
    private var isHandsFreeMode = false
    private var isRecordingOrPending = false
    private let holdThreshold: Double = 0.4

    init(appState: AppState, modelContainer: ModelContainer) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.parakeetV2Engine = ParakeetEngine(version: .v2)
        self.parakeetEngine = ParakeetEngine(version: .v3)
        self.qwen3Engine = Qwen3AsrEngine(variant: .f32)
        self.qwen3Int8Engine = Qwen3AsrEngine(variant: .int8)
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

        do {
            if useBatchEngine {
                switch appState.asrBackend {
                case .parakeetV2:
                    try await parakeetV2Engine.ensureModelLoaded()
                case .parakeet:
                    try await parakeetEngine.ensureModelLoaded()
                case .qwen3Asr:
                    try await qwen3Engine.ensureModelLoaded()
                case .qwen3AsrInt8:
                    try await qwen3Int8Engine.ensureModelLoaded()
                case .apple:
                    break
                }

                guard isRecordingOrPending else {
                    cleanUpRecordingUI()
                    return
                }

                batchStartSession()
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
            if useBatchEngine {
                appState.phase = .processing
                rawText = try await batchFinishSession()
            } else {
                rawText = try await transcriptionEngine.finishSession()
            }
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

        if llmEnabled && llmAvailable {
            appState.phase = .processing
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
        }

        // Insert text
        appState.phase = .inserting
        await TextInserter.insert(finalText, method: appState.pasteMethod)

        // Record to SwiftData
        let llmRan = llmEnabled && llmAvailable
        let filtered = processedText != rawText ? processedText : nil
        let dictCorrected = dictCorrectedText != processedText ? dictCorrectedText : nil
        let cleaned = finalText != (dictCorrected ?? filtered ?? rawText) ? finalText : nil
        saveTranscription(
            rawText: rawText, filteredText: filtered,
            dictionaryCorrectedText: dictCorrected, cleanedText: cleaned,
            context: context, filterRan: filterRan,
            dictionaryRan: dictionaryRan, llmRan: llmRan
        )
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
        if !useBatchEngine {
            _ = try? await transcriptionEngine.finishSession()
        }

        appState.partialTranscription = nil
        appState.phase = .idle
    }

    // MARK: - Batch engine helpers

    private func batchStartSession() {
        switch appState.asrBackend {
        case .parakeetV2: parakeetV2Engine.startSession()
        case .parakeet: parakeetEngine.startSession()
        case .qwen3Asr: qwen3Engine.startSession()
        case .qwen3AsrInt8: qwen3Int8Engine.startSession()
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
        case .parakeet:
            let engine = parakeetEngine
            return { buffer in engine.feedAudio(buffer) }
        case .qwen3Asr:
            let engine = qwen3Engine
            return { buffer in engine.feedAudio(buffer) }
        case .qwen3AsrInt8:
            let engine = qwen3Int8Engine
            return { buffer in engine.feedAudio(buffer) }
        case .apple:
            return { _ in }
        }
    }

    private func batchTargetFormat() -> AVAudioFormat? {
        switch appState.asrBackend {
        case .parakeetV2: return parakeetV2Engine.targetFormat
        case .parakeet: return parakeetEngine.targetFormat
        case .qwen3Asr: return qwen3Engine.targetFormat
        case .qwen3AsrInt8: return qwen3Int8Engine.targetFormat
        case .apple: return nil
        }
    }

    private func batchFinishSession() async throws -> String {
        switch appState.asrBackend {
        case .parakeetV2: return try await parakeetV2Engine.finishSession()
        case .parakeet: return try await parakeetEngine.finishSession()
        case .qwen3Asr: return try await qwen3Engine.finishSession()
        case .qwen3AsrInt8: return try await qwen3Int8Engine.finishSession()
        case .apple: return ""
        }
    }

    // MARK: - Model status

    func checkModelStatus() {
        let backend = appState.asrBackend
        guard backend.needsDownload else { return }
        // Don't overwrite if already downloading
        if case .downloading = appState.modelStatusByBackend[backend] { return }
        let dir = Self.cacheDirectory(for: backend)
        let exists: Bool
        switch backend {
        case .parakeetV2:
            exists = AsrModels.modelsExist(at: dir, version: .v2)
        case .parakeet:
            exists = AsrModels.modelsExist(at: dir, version: .v3)
        case .qwen3Asr, .qwen3AsrInt8:
            exists = Qwen3AsrModels.modelsExist(at: dir)
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
            case .parakeet:
                try await parakeetEngine.ensureModelLoaded()
            case .qwen3Asr:
                try await qwen3Engine.ensureModelLoaded()
            case .qwen3AsrInt8:
                try await qwen3Int8Engine.ensureModelLoaded()
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
        case .parakeet: return AsrModels.defaultCacheDirectory(for: .v3)
        case .qwen3Asr: return Qwen3AsrModels.defaultCacheDirectory(variant: .f32)
        case .qwen3AsrInt8: return Qwen3AsrModels.defaultCacheDirectory(variant: .int8)
        case .apple: return URL(fileURLWithPath: "/dev/null")
        }
    }

    private static func expectedModelBytes(for backend: AsrBackend) -> Int64 {
        switch backend {
        case .parakeetV2: return 473_000_000
        case .parakeet: return 484_000_000
        case .qwen3Asr: return 3_512_000_000
        case .qwen3AsrInt8: return 2_304_000_000
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
        let model = appState.mlxModel
        if case .downloading = appState.mlxModelStatus[model] { return }
        mlxPostProcessor.switchModel(to: model.modelID)
        let exists = mlxPostProcessor.modelIsReady()
        appState.mlxModelStatus[model] = exists ? .ready : .notDownloaded
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
        dictionaryRan: Bool, llmRan: Bool
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
            llmRan: llmRan
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
}
