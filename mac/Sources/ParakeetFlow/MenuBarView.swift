import SwiftUI

@available(macOS 26, *)
struct MenuBarView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !appState.hasCompletedOnboarding {
            Text("Please complete onboarding")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } else {
            // Status (shows error detail or live transcription inline)
            Label(statusLabel, systemImage: statusIcon)

            if appState.isLLMEnabled && appState.llmBackend == .apple && !PostProcessor.isAvailable(backend: .apple) {
                Label("Apple Intelligence unavailable — LLM cleanup skipped", systemImage: "exclamationmark.triangle")
            }

            Divider()

            // if/else keeps NSMenu item count stable (always 1 item in this slot)
            // to avoid AppKit index mismatch warnings in menu-style MenuBarExtra.
            if appState.phase == .error {
                Menu("Troubleshoot...") {
                    Button("Open Accessibility") {
                        openSystemPrefs("Privacy_Accessibility")
                    }
                    Button("Open Microphone") {
                        openSystemPrefs("Privacy_Microphone")
                    }
                }
            } else {
                Text("\(appState.hotkeyChoice.symbol) hold / tap · esc cancel")
            }

            Divider()

            Button("History") {
                NSApp.activate()
                openWindow(id: "history")
            }

            Button("Settings...") {
                NSApp.activate()
                openSettings()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusLabel: String {
        if appState.phase == .recording, let partial = appState.partialTranscription {
            return partial
        }
        return appState.statusText
    }

    private var statusIcon: String {
        switch appState.phase {
        case .idle: return "checkmark.circle"
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .inserting: return "doc.on.clipboard"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func openSystemPrefs(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
