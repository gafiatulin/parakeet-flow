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
                    description: "For text insertion and context reading",
                    systemImage: "accessibility",
                    action: { openSystemSettings("Privacy_Accessibility") }
                )

                PermissionRow(
                    name: "Input Monitoring",
                    description: "For global hotkey (push-to-talk)",
                    systemImage: "keyboard",
                    action: { openSystemSettings("Privacy_ListenEvent") }
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
