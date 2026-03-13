import SwiftUI
import SwiftData

@available(macOS 26, *)
@main
struct ParakeetFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                appState: appDelegate.appState,
                orchestrator: appDelegate.orchestrator
            )
        } label: {
            Image(systemName: appDelegate.appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: "history") {
            HistoryView()
        }
        .defaultSize(width: 500, height: 400)
        .modelContainer(appDelegate.modelContainer)

        Settings {
            SettingsView(
                appState: appDelegate.appState,
                orchestrator: appDelegate.orchestrator
            )
            .modelContainer(appDelegate.modelContainer)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var orchestrator: Orchestrator?
    let modelContainer: ModelContainer
    private var onboardingWindow: NSWindow?

    override init() {
        do {
            modelContainer = try ModelContainer(for: TranscriptionEntry.self, DictionaryWord.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        super.init()
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip initialization when running as a test host
        if NSClassFromString("XCTestCase") != nil { return }

        Task { @MainActor in
            if !self.appState.hasCompletedOnboarding {
                NSApp.setActivationPolicy(.regular)
                self.showOnboarding()
            } else {
                NSApp.setActivationPolicy(.accessory)
                let orch = self.ensureOrchestrator()
                await orch.initialize()
            }
        }
    }

    private func ensureOrchestrator() -> Orchestrator {
        if let orch = orchestrator { return orch }
        let orch = Orchestrator(appState: appState, modelContainer: modelContainer)
        orchestrator = orch
        return orch
    }

    private func showOnboarding() {
        let orch = ensureOrchestrator()
        let onboardingView = OnboardingView(
            appState: appState,
            orchestrator: orch
        ) { [weak self] in
            guard let self else { return }
            self.appState.hasCompletedOnboarding = true
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                let orch = self.ensureOrchestrator()
                await orch.initialize()
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ParakeetFlow"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        onboardingWindow = window
    }
}
