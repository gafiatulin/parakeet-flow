import SwiftUI

@available(macOS 26, *)
@main
struct ParakeetFlowApp: App {
    @State private var appState = AppState()
    @State private var orchestrator: Orchestrator?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, orchestrator: orchestrator)
                .task {
                    if orchestrator == nil {
                        NSApp.setActivationPolicy(.accessory)

                        let orch = Orchestrator(appState: appState)
                        orchestrator = orch
                        await orch.initialize()
                    }
                }
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: "history") {
            HistoryView(appState: appState)
        }
        .defaultSize(width: 500, height: 400)

        Settings {
            SettingsView(appState: appState, orchestrator: orchestrator)
        }
    }
}
