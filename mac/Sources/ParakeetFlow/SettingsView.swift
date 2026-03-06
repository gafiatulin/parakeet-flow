import SwiftUI
import SwiftData

@available(macOS 26, *)
struct SettingsView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState, orchestrator: orchestrator)
                .tabItem { Label("General", systemImage: "gear") }

            if appState.isDictionaryEnabled {
                DictionarySettingsView(appState: appState)
                    .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            }

            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 450, height: 450)
    }
}

@available(macOS 26, *)
struct GeneralSettingsView: View {
    @Bindable var appState: AppState
    var orchestrator: Orchestrator?
    @State private var showClearAsrModels = false
    @State private var showClearLlmModels = false

    private var downloadedAsrModels: [AsrBackend] {
        AsrBackend.allCases.filter { backend in
            backend.needsDownload && appState.modelStatusByBackend[backend] == .ready
        }
    }

    private var downloadedLlmModels: [MlxModelChoice] {
        MlxModelChoice.allCases.filter { model in
            appState.mlxModelStatus[model] == .ready
        }
    }

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
                    Text(AsrBackend.apple.label).tag(AsrBackend.apple)
                    Divider()
                    ForEach(AsrBackend.allCases.filter(\.needsDownload), id: \.self) { backend in
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

                if appState.asrBackend.needsDownload {
                    HStack {
                        Button("Show in Finder") {
                            orchestrator?.revealModelCache()
                        }
                        .font(.caption)
                        Spacer()
                        Button("Clear All Models", role: .destructive) {
                            showClearAsrModels = true
                        }
                        .font(.caption)
                        .disabled(downloadedAsrModels.isEmpty)
                    }
                }
            }

            Section("Transcription") {
                Toggle("Remove filler words", isOn: $appState.isFillerRemovalEnabled)
                Text("Removes um, uh, like, you know, etc. before LLM cleanup")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Dictionary correction", isOn: $appState.isDictionaryEnabled)
                Text("Corrects ASR errors using fuzzy matching against your word list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Post-Processing") {
                Toggle("Enable LLM cleanup", isOn: $appState.isLLMEnabled)

                if appState.isLLMEnabled {
                    Picker("LLM Backend", selection: llmChoiceBinding) {
                        Text("Apple Intelligence").tag(LlmChoice.apple)
                        Divider()
                        ForEach(MlxModelChoice.allCases, id: \.self) { model in
                            Text("MLX · \(model.label)").tag(LlmChoice.mlx(model))
                        }
                    }

                    if appState.llmBackend == .mlx {
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
                            case .notNeeded:
                                EmptyView()
                            }
                        }

                        HStack {
                            Button("Show in Finder") {
                                orchestrator?.revealLlmModelCache()
                            }
                            .font(.caption)
                            Spacer()
                            Button("Clear All LLM Models", role: .destructive) {
                                showClearLlmModels = true
                            }
                            .font(.caption)
                            .disabled(downloadedLlmModels.isEmpty)
                        }
                    } else {
                        Text("Uses Apple Intelligence on-device model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Uses on-device LLM to clean up transcriptions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onAppear {
            orchestrator?.checkModelStatus()
            orchestrator?.checkLlmModelStatus()
        }
        .confirmationDialog(
            "Delete all ASR models?",
            isPresented: $showClearAsrModels,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                orchestrator?.deleteAllModels()
            }
        } message: {
            let names = downloadedAsrModels.map(\.label).joined(separator: "\n")
            Text("The following models will be deleted:\n\(names)\n\nThis action cannot be undone. Models can be re-downloaded.")
        }
        .confirmationDialog(
            "Delete all LLM models?",
            isPresented: $showClearLlmModels,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                orchestrator?.deleteAllLlmModels()
            }
        } message: {
            let names = downloadedLlmModels.map(\.label).joined(separator: "\n")
            Text("The following models will be deleted:\n\(names)\n\nThis action cannot be undone. Models can be re-downloaded.")
        }
    }

    private var llmChoiceBinding: Binding<LlmChoice> {
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

private enum LlmChoice: Hashable {
    case apple
    case mlx(MlxModelChoice)
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

struct DictionarySettingsView: View {
    @Bindable var appState: AppState
    @Query(sort: \DictionaryWord.dateAdded, order: .reverse)
    private var words: [DictionaryWord]
    @Environment(\.modelContext) private var modelContext
    @State private var newWord = ""
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @State private var duplicateWarning: String?

    private var filteredWords: [DictionaryWord] {
        guard !searchText.isEmpty else { return words }
        let query = searchText.lowercased()
        return words.filter { $0.word.lowercased().contains(query) }
    }

    private var manualCount: Int { words.filter { $0.sourceType == .manual }.count }
    private var learnedCount: Int { words.filter { $0.sourceType == .learned }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Sensitivity settings
            Form {
                Section("Sensitivity") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Match threshold")
                            Slider(value: $appState.dictionaryThreshold, in: 0.05...0.4, step: 0.01)
                            Text(String(format: "%.2f", appState.dictionaryThreshold))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                        }
                        HStack(spacing: 12) {
                            SensitivityLabel(text: "Strict", active: appState.dictionaryThreshold < 0.12)
                            SensitivityLabel(text: "Balanced", active: appState.dictionaryThreshold >= 0.12 && appState.dictionaryThreshold <= 0.25)
                            SensitivityLabel(text: "Loose", active: appState.dictionaryThreshold > 0.25)
                            Spacer()
                            Button("Reset") {
                                appState.dictionaryThreshold = DictionaryCorrector.defaultThreshold
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 100)

            // Word list
            VStack(spacing: 0) {
                // Add bar
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                    TextField("Add word or phrase...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    if let warning = duplicateWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !newWord.isEmpty {
                        Button("Add") { addWord() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Search + stats bar (only when there are words)
                if !words.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        TextField("Filter", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                        Spacer()
                        HStack(spacing: 8) {
                            if manualCount > 0 {
                                Label("\(manualCount) manual", systemImage: "character.cursor.ibeam")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if learnedCount > 0 {
                                Label("\(learnedCount) learned", systemImage: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove all words")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                Divider()

                // Word list
                if words.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "text.book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.quaternary)
                        Text("No dictionary words yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Add names, technical terms, or words\nthat are frequently misheard by ASR.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if filteredWords.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No matches for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(filteredWords) { word in
                            DictionaryWordRow(word: word) {
                                modelContext.delete(word)
                                try? modelContext.save()
                            }
                        }
                        .onDelete { offsets in
                            let toDelete = offsets.map { filteredWords[$0] }
                            for word in toDelete {
                                modelContext.delete(word)
                            }
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove all \(words.count) dictionary words?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                for word in words {
                    modelContext.delete(word)
                }
                try? modelContext.save()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Check for duplicates
        if words.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) {
            duplicateWarning = "Already exists"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                duplicateWarning = nil
            }
            return
        }

        let entry = DictionaryWord(word: trimmed, source: .manual)
        modelContext.insert(entry)
        try? modelContext.save()
        newWord = ""
        duplicateWarning = nil
    }
}

private struct DictionaryWordRow: View {
    let word: DictionaryWord
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(word.word)
                .fontWeight(word.sourceType == .learned ? .regular : .medium)

            Spacer()

            if word.sourceType == .learned {
                Label("learned", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text(word.dateAdded, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isHovering {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(word.word, forType: .string)
            }
            Button("Remove", role: .destructive) {
                onDelete()
            }
        }
    }
}

private struct SensitivityLabel: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(active ? .primary : .tertiary)
            .fontWeight(active ? .semibold : .regular)
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
