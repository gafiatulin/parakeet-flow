import SwiftUI

struct HistoryView: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if appState.recentTranscriptions.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "text.bubble",
                    description: Text("Transcriptions will appear here.")
                )
            } else {
                List {
                    ForEach(appState.recentTranscriptions) { record in
                        HistoryRow(record: record)
                    }
                    .onDelete { offsets in
                        appState.removeTranscriptions(at: offsets)
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 300)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear All") {
                    appState.clearTranscriptions()
                }
                .disabled(appState.recentTranscriptions.isEmpty)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: TranscriptionRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                PipelineStage(label: "ASR", text: record.rawText)

                if let filtered = record.filteredText {
                    PipelineStage(label: "Filtered", text: filtered)
                } else if record.filterRan {
                    PipelineStage(label: "Filtered", unchanged: true)
                }

                if let cleaned = record.cleanedText {
                    PipelineStage(label: "LLM", text: cleaned)
                } else if record.llmRan {
                    PipelineStage(label: "LLM", unchanged: true)
                }

                if let context = record.context, context.appName != nil || context.windowTitle != nil || context.surroundingText != nil {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONTEXT")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let app = context.appName {
                            Label(app, systemImage: "app")
                                .font(.callout)
                        }
                        if let window = context.windowTitle {
                            Label(window, systemImage: "macwindow")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let text = context.surroundingText {
                            Text(text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayText)
                    .lineLimit(isExpanded ? nil : 2)
                    .textSelection(.enabled)

                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Copy") {
                copyText(record.displayText)
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct PipelineStage: View {
    let label: String
    var text: String?
    var unchanged: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let text {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
            } else if unchanged {
                Text("no changes")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }
}
