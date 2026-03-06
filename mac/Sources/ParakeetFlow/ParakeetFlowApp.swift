import SwiftUI
import SwiftData

@available(macOS 26, *)
@main
struct ParakeetFlowApp: App {
    @State private var appState = AppState()
    @State private var orchestrator: Orchestrator?
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TranscriptionEntry.self, DictionaryWord.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, orchestrator: orchestrator)
                .task {
                    if orchestrator == nil {
                        NSApp.setActivationPolicy(.accessory)

                        let orch = Orchestrator(appState: appState, modelContainer: modelContainer)
                        orchestrator = orch
                        await orch.initialize()
                    }
                }
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: "history") {
            HistoryView()
        }
        .defaultSize(width: 500, height: 400)
        .modelContainer(modelContainer)

        Settings {
            SettingsView(appState: appState, orchestrator: orchestrator)
                .modelContainer(modelContainer)
        }
    }
}
