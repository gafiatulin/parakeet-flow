import SwiftUI
import SwiftData

@available(macOS 26, *)
struct PerformanceSettingsView: View {
    @Query(sort: \TranscriptionEntry.timestamp, order: .reverse)
    private var entries: [TranscriptionEntry]

    private var timedEntries: [TranscriptionEntry] {
        entries.filter { $0.asrDurationMs > 0 && $0.audioDurationMs > 0 }
    }

    private var averages: (asr: Double, llm: Double, total: Double, rtf: Double)? {
        let timed = timedEntries
        guard !timed.isEmpty else { return nil }
        let count = Double(timed.count)
        let asr = Double(timed.reduce(0) { $0 + $1.asrDurationMs }) / count
        let llm = Double(timed.reduce(0) { $0 + $1.llmDurationMs }) / count
        let total = Double(timed.reduce(0) { $0 + $1.totalDurationMs }) / count
        let audio = Double(timed.reduce(0) { $0 + $1.audioDurationMs }) / count
        return (asr, llm, total, asr > 0 ? audio / asr : 0)
    }

    var body: some View {
        Form {
            Section("Benchmarks") {
                if let averages {
                    LabeledContent("Average ASR") {
                        Text(String(format: "%.0f ms", averages.asr))
                    }
                    LabeledContent("Average LLM") {
                        Text(String(format: "%.0f ms", averages.llm))
                    }
                    LabeledContent("Average total") {
                        Text(String(format: "%.0f ms", averages.total))
                    }
                    LabeledContent("Average ASR speed") {
                        Text(String(format: "%.1f× realtime", averages.rtf))
                    }
                    LabeledContent("Measured dictations") {
                        Text("\(timedEntries.count)")
                    }
                } else {
                    Text("No measured dictations yet. Complete a dictation to collect ASR, LLM, and total latency.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !timedEntries.isEmpty {
                Section("Recent runs") {
                    ForEach(timedEntries.prefix(12)) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.appName ?? "Unknown app")
                                    .font(.callout)
                                Spacer()
                                Text(entry.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(runSummary(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func runSummary(_ entry: TranscriptionEntry) -> String {
        var parts = ["\(entry.asrDurationMs) ms ASR"]
        if entry.llmDurationMs > 0 {
            parts.append("\(entry.llmDurationMs) ms LLM")
        }
        parts.append("\(entry.totalDurationMs) ms total")
        if entry.asrDurationMs > 0 {
            let rtf = Double(entry.audioDurationMs) / Double(entry.asrDurationMs)
            parts.append(String(format: "%.1f× RTF", rtf))
        }
        return parts.joined(separator: " · ")
    }
}
