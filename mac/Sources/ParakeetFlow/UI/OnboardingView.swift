import SwiftUI
import AVFoundation
@preconcurrency import ApplicationServices

@available(macOS 26, *)
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case backends
    case ready
}

@available(macOS 26, *)
struct OnboardingView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    @State private var pollTask: Task<Void, Never>?

    private var canContinue: Bool {
        switch step {
        case .welcome:
            return true
        case .microphone:
            return micGranted
        case .accessibility:
            return axGranted
        case .backends:
            return isAsrReady && isLlmReady
        case .ready:
            return true
        }
    }

    private var isAsrReady: Bool {
        if appState.asrBackend == .apple {
            return PostProcessor.isAvailable(backend: .apple)
        }
        return appState.modelStatusByBackend[appState.asrBackend] == .ready
    }

    private var isLlmReady: Bool {
        if !appState.isLLMEnabled { return true }
        if appState.llmBackend == .apple {
            return PostProcessor.isAvailable(backend: .apple)
        }
        return appState.mlxModelStatus[appState.mlxModel] == .ready
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch step {
                case .welcome:
                    WelcomeStepView()
                case .microphone:
                    MicPermissionStepView()
                case .accessibility:
                    AccessibilityPermissionStepView()
                case .backends:
                    BackendSelectionStepView(appState: appState, orchestrator: orchestrator)
                case .ready:
                    ReadyStepView(appState: appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                // Step dots
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                        Circle()
                            .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if step != .welcome {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                        }
                    }
                }

                if step == .ready {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step = OnboardingStep(rawValue: step.rawValue + 1) ?? .ready
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 620)
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                axGranted = AXIsProcessTrusted()
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 192, height: 192)
            }

            Text("Welcome to ParakeetFlow")
                .font(.largeTitle.bold())

            Text("On-device voice dictation powered by AI.\nHold a key, speak, release — your words appear as clean text.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 2: Microphone

@available(macOS 26, *)
private struct MicPermissionStepView: View {
    @State private var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var pollTask: Task<Void, Never>?

    private var isGranted: Bool { status == .authorized }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: isGranted ? "mic.circle.fill" : "mic.circle")
                .font(.system(size: 52))
                .foregroundStyle(isGranted ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text("Microphone Access")
                .font(.title.bold())

            Text("ParakeetFlow needs microphone access to hear your voice and transcribe it into text. Audio is processed entirely on-device — nothing is sent to the cloud.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            if isGranted {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        await AVCaptureDevice.requestAccess(for: .audio)
                        status = AVCaptureDevice.authorizationStatus(for: .audio)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if status == .denied {
                    Text("Permission was denied. Open **System Settings > Privacy & Security > Microphone** to enable it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                status = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }
}

// MARK: - Step 3: Accessibility

@available(macOS 26, *)
private struct AccessibilityPermissionStepView: View {
    @State private var isGranted = AXIsProcessTrusted()
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: isGranted ? "accessibility.fill" : "accessibility")
                .font(.system(size: 52))
                .foregroundStyle(isGranted ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text("Accessibility Permission")
                .font(.title.bold())

            Text("ParakeetFlow needs Accessibility access to detect your hotkey globally, read context from the active app, and insert transcribed text.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            if isGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Accessibility Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Add ParakeetFlow in **System Settings > Privacy & Security > Accessibility**, then return here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Spacer()
        }
        .padding()
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                isGranted = AXIsProcessTrusted()
            }
        }
    }
}

// MARK: - Step 4: Backend Selection

@available(macOS 26, *)
private struct BackendSelectionStepView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?
    private var appleIntelligenceAvailable: Bool {
        PostProcessor.isAvailable(backend: .apple)
    }
    private var needsAppleIntelligence: Bool {
        appState.asrBackend == .apple || (appState.isLLMEnabled && appState.llmBackend == .apple)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 16)

            Text("Choose Your Engines")
                .font(.title.bold())

            Text("Select which on-device models to use for speech recognition and text cleanup. You can change these later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            if !appleIntelligenceAvailable && needsAppleIntelligence {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Apple Intelligence is not available. Enable it in **System Settings > Apple Intelligence & Siri**, or choose an alternative engine below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 440)
            }

            Form {
                Section {
                    Picker("Speech Recognition", selection: $appState.asrBackend) {
                        Text(AsrBackend.apple.label).tag(AsrBackend.apple)
                        Divider()
                        ForEach(AsrBackend.allCases.filter(\.needsDownload), id: \.self) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .onChange(of: appState.asrBackend) { _, _ in
                        orchestrator?.checkModelStatus()
                    }

                    if appState.asrBackend == .apple && !appleIntelligenceAvailable {
                        Text("Apple Intelligence is required for this engine but is not enabled.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if appState.asrBackend.needsDownload {
                        AsrModelStatusRow(appState: appState, orchestrator: orchestrator)
                    }
                }

                Section {
                    Toggle("Enable LLM cleanup", isOn: $appState.isLLMEnabled)

                    if appState.isLLMEnabled {
                        Picker("Text Cleanup (LLM)", selection: llmChoiceBinding) {
                            Text("Apple Intelligence").tag(OnboardingLlmChoice.apple)
                            Divider()
                            ForEach(MlxModelChoice.allCases, id: \.self) { model in
                                Text("MLX · \(model.label)").tag(OnboardingLlmChoice.mlx(model))
                            }
                        }

                        if appState.llmBackend == .apple && !appleIntelligenceAvailable {
                            Text("Apple Intelligence is required but is not enabled. LLM cleanup will be skipped.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if appState.llmBackend == .mlx {
                            LlmModelDownloadRow(appState: appState, orchestrator: orchestrator)
                        }
                    } else {
                        Text("Transcriptions will be inserted as-is without LLM post-processing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(maxWidth: 460)
        }
        .padding(.horizontal)
        .onAppear {
            orchestrator?.checkModelStatus()
            orchestrator?.checkLlmModelStatus()
        }
    }

    private var llmChoiceBinding: Binding<OnboardingLlmChoice> {
        Binding(
            get: {
                if appState.llmBackend == .apple {
                    return .apple
                }
                return .mlx(appState.mlxModel)
            },
            set: { newValue in
                switch newValue {
                case .apple:
                    appState.llmBackend = .apple
                case .mlx(let model):
                    appState.llmBackend = .mlx
                    appState.mlxModel = model
                    orchestrator?.switchMlxModel(to: model)
                }
                orchestrator?.checkLlmModelStatus()
            }
        )
    }
}

private enum OnboardingLlmChoice: Hashable {
    case apple
    case mlx(MlxModelChoice)
}

@available(macOS 26, *)
private struct AsrModelStatusRow: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?

    var body: some View {
        HStack {
            switch appState.modelStatusByBackend[appState.asrBackend] ?? .notDownloaded {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Model ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete", role: .destructive) {
                    orchestrator?.deleteModel()
                }
                .font(.caption)
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.orange)
                Text("Model not downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    orchestrator?.downloadModel()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Downloading model...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            orchestrator?.cancelDownload()
                        }
                        .font(.caption)
                    }
                    ProgressView(value: progress)
                }
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("Retry") {
                    orchestrator?.downloadModel()
                }
                .font(.caption)
            case .notNeeded:
                EmptyView()
            }
        }
    }
}

@available(macOS 26, *)
private struct LlmModelDownloadRow: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?

    var body: some View {
        HStack {
            switch appState.mlxModelStatus[appState.mlxModel] ?? .notDownloaded {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Model ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete", role: .destructive) {
                    orchestrator?.deleteLlmModel()
                }
                .font(.caption)
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.orange)
                Text("Model not downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    orchestrator?.downloadLlmModel()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Downloading model...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            orchestrator?.cancelLlmDownload()
                        }
                        .font(.caption)
                    }
                    ProgressView(value: progress)
                }
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("Retry") {
                    orchestrator?.downloadLlmModel()
                }
                .font(.caption)
            case .notNeeded:
                EmptyView()
            }
        }
    }
}

// MARK: - Step 5: Ready

@available(macOS 26, *)
private struct ReadyStepView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            Text("You're All Set")
                .font(.title.bold())

            Text("ParakeetFlow lives in your menu bar.\nUse the hotkey to start dictating.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            // Hotkey selection
            GroupBox {
                VStack(spacing: 12) {
                    Picker("Hotkey", selection: $appState.hotkeyChoice) {
                        ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("**Hold** to dictate, release to insert", systemImage: "hand.tap")
                        Label("**Tap** to toggle hands-free mode", systemImage: "hand.point.up")
                        Label("**Esc** to cancel recording", systemImage: "escape")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(4)
            }
            .frame(maxWidth: 340)

            Text("All parameters — including filler words filtering, dictionary corrections, paste methods, and so on — can be changed later via the Settings.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Spacer()
        }
        .padding()
    }
}
