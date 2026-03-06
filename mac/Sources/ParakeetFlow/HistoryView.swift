import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \TranscriptionEntry.timestamp, order: .reverse)
    private var entries: [TranscriptionEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showClearConfirmation = false

    private var filteredEntries: [TranscriptionEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { entry in
            fuzzyMatch(query, in: entry.displayText)
            || fuzzyMatch(query, in: entry.rawText)
            || fuzzyMatch(query, in: entry.appName ?? "")
        }
    }

    /// Returns true if the query appears as a substring OR if any word in the
    /// text fuzzy-matches any query word (Levenshtein distance ≤ 30% of length).
    private func fuzzyMatch(_ query: String, in text: String) -> Bool {
        let lower = text.lowercased()
        // Fast path: exact substring
        if lower.contains(query) { return true }
        guard !lower.isEmpty else { return false }

        let queryWords = query.split(separator: " ").map(String.init)
        let textWords = lower.split(separator: " ").map(String.init)

        // Every query word must match at least one text word
        return queryWords.allSatisfy { qw in
            textWords.contains { tw in
                // Exact prefix
                if tw.hasPrefix(qw) { return true }
                // Levenshtein fuzzy (allow ~30% edit distance)
                let maxDist = max(1, qw.count / 3)
                return DictionaryCorrector.levenshteinDistance(qw, tw) <= maxDist
            }
        }
    }

    private var groupedEntries: [(String, [TranscriptionEntry])] {
        let calendar = Calendar.current
        let now = Date.now
        var groups: [(String, [TranscriptionEntry])] = []
        var buckets: [String: [TranscriptionEntry]] = [:]
        var order: [String] = []

        for entry in filteredEntries {
            let label: String
            if calendar.isDateInToday(entry.timestamp) {
                label = "Today"
            } else if calendar.isDateInYesterday(entry.timestamp) {
                label = "Yesterday"
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      entry.timestamp > weekAgo {
                label = "This Week"
            } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
                      entry.timestamp > monthAgo {
                label = "This Month"
            } else {
                label = "Older"
            }

            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(entry)
        }

        for key in order {
            if let items = buckets[key] {
                groups.append((key, items))
            }
        }
        return groups
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "text.bubble",
                    description: Text("Transcriptions will appear here.")
                )
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(groupedEntries, id: \.0) { section, items in
                        Section(section) {
                            ForEach(items) { entry in
                                HistoryRow(entry: entry) {
                                    modelContext.delete(entry)
                                    try? modelContext.save()
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        modelContext.delete(entry)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.displayText, forType: .string)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !entries.isEmpty {
                Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .modifier(ConditionalSearchable(isEnabled: !entries.isEmpty, text: $searchText))
        .frame(minWidth: 480, minHeight: 340)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") {
                        showClearConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete all \(entries.count) transcriptions?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                for entry in entries {
                    modelContext.delete(entry)
                }
                try? modelContext.save()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

private struct HistoryRow: View {
    let entry: TranscriptionEntry
    let onDelete: () -> Void
    @State private var isExpanded = false
    @State private var showCopied = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                PipelineStage(label: "ASR", text: entry.rawText)

                if let filtered = entry.filteredText {
                    PipelineStage(label: "Filtered", text: filtered)
                } else if entry.filterRan {
                    PipelineStage(label: "Filtered", unchanged: true)
                }

                if let dictCorrected = entry.dictionaryCorrectedText {
                    PipelineStage(label: "Dictionary", text: dictCorrected)
                } else if entry.dictionaryRan {
                    PipelineStage(label: "Dictionary", unchanged: true)
                }

                if let cleaned = entry.cleanedText {
                    PipelineStage(label: "LLM", text: cleaned)
                } else if entry.llmRan {
                    PipelineStage(label: "LLM", unchanged: true)
                }

                if entry.appName != nil || entry.windowTitle != nil || entry.surroundingText != nil {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONTEXT")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let app = entry.appName {
                            Label(app, systemImage: "app")
                                .font(.callout)
                        }
                        if let window = entry.windowTitle {
                            Label(window, systemImage: "macwindow")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let text = entry.surroundingText {
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
            HStack(spacing: 8) {
                AppIconView(bundleIdentifier: entry.appBundleIdentifier)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayText)
                        .lineLimit(isExpanded ? nil : 2)
                        .textSelection(.enabled)

                    HStack(spacing: 4) {
                        Text(entry.timestamp, style: .relative)
                        if let app = entry.appName {
                            Text("·")
                            Text(app)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.displayText, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(showCopied ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
        .contextMenu {
            Button("Copy Final Text") {
                copyText(entry.displayText)
            }
            if entry.displayText != entry.rawText {
                Button("Copy Raw ASR") {
                    copyText(entry.rawText)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct AppIconView: View {
    let bundleIdentifier: String?

    var body: some View {
        Group {
            if let bundleID = bundleIdentifier,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct ConditionalSearchable: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: "Search")
        } else {
            content
        }
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
