import SwiftUI

@available(macOS 26, *)
struct SettingsView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState, orchestrator: orchestrator)
                .tabItem { Label("General", systemImage: "gear") }

            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 450, height: 400)
    }
}

@available(macOS 26, *)
struct GeneralSettingsView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Trigger key", selection: $appState.hotkeyChoice) {
                    ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .onChange(of: appState.hotkeyChoice) { _, newValue in
                    orchestrator?.updateHotkey(newValue)
                }
                Text("Hold to dictate · Tap to toggle · Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcription Engine") {
                Picker("ASR Backend", selection: $appState.asrBackend) {
                    ForEach(AsrBackend.allCases, id: \.self) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                .onChange(of: appState.asrBackend) { _, _ in
                    orchestrator?.checkModelStatus()
                }

                if appState.asrBackend.needsDownload {
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
                        case .notNeeded:
                            EmptyView()
                        }
                    }
                }

                HStack {
                    Button("Show in Finder") {
                        orchestrator?.revealModelCache()
                    }
                    .font(.caption)
                    Spacer()
                    Button("Clear All Models", role: .destructive) {
                        orchestrator?.deleteAllModels()
                    }
                    .font(.caption)
                }
            }

            Section("Transcription") {
                Toggle("Remove filler words", isOn: $appState.isFillerRemovalEnabled)
                Text("Removes um, uh, like, you know, etc. before LLM cleanup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Post-Processing") {
                Toggle("Enable LLM cleanup", isOn: $appState.isLLMEnabled)
                Text("Uses Apple Intelligence on-device model to clean up transcriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio Feedback") {
                Toggle("Play sounds on start/stop", isOn: $appState.isAudioFeedbackEnabled)
            }

            Section("Recording Indicator") {
                Toggle("Show floating overlay while recording", isOn: $appState.isRecordingOverlayEnabled)
                Picker("Waveform color", selection: $appState.waveformColor) {
                    ForEach(WaveformColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $appState.isLaunchAtLoginEnabled)
            }

        }
        .formStyle(.grouped)
        .padding()
        .onAppear { orchestrator?.checkModelStatus() }
    }
}

struct PermissionsView: View {
    var body: some View {
        Form {
            Section("Required Permissions") {
                PermissionRow(
                    name: "Microphone",
                    description: "For voice capture",
                    systemImage: "mic",
                    action: { openSystemSettings("Privacy_Microphone") }
                )

                PermissionRow(
                    name: "Accessibility",
                    description: "For global hotkey, text insertion, and context reading",
                    systemImage: "accessibility",
                    action: { openSystemSettings("Privacy_Accessibility") }
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let description: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action)
        }
    }
}
