import AppKit
import Foundation

enum HistoryExportFormat {
    case markdown
    case json

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }

    var allowedType: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }
}

enum HistoryExporter {
    static func export(_ entries: [TranscriptionEntry], as format: HistoryExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: format.allowedType) ?? .plainText]
        panel.nameFieldStringValue = "ParakeetFlow-History.\(format.fileExtension)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text: String
        switch format {
        case .markdown:
            text = markdown(entries)
        case .json:
            text = json(entries)
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func markdown(_ entries: [TranscriptionEntry]) -> String {
        var output = "# ParakeetFlow transcript history\n\n"
        output += "Exported \(ISO8601DateFormatter().string(from: .now))\n\n"
        for entry in entries {
            output += "## \(entry.timestamp.formatted(date: .abbreviated, time: .standard))\n\n"
            if let app = entry.appName {
                output += "**App:** \(app)\n\n"
            }
            if let window = entry.windowTitle {
                output += "**Window:** \(window)\n\n"
            }
            output += "### Final\n\n\(entry.displayText)\n\n"
            if entry.rawText != entry.displayText {
                output += "### Raw ASR\n\n\(entry.rawText)\n\n"
            }
            if let filtered = entry.filteredText, filtered != entry.rawText {
                output += "### Filtered\n\n\(filtered)\n\n"
            }
            if let corrected = entry.dictionaryCorrectedText, corrected != entry.filteredText {
                output += "### Dictionary\n\n\(corrected)\n\n"
            }
            if entry.totalDurationMs > 0 {
                output += performanceLine(entry) + "\n\n"
            }
            output += "---\n\n"
        }
        return output
    }

    static func json(_ entries: [TranscriptionEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows: [[String: Any]] = entries.map { entry in
            var row: [String: Any] = [
                "timestamp": formatter.string(from: entry.timestamp),
                "raw_text": entry.rawText,
                "display_text": entry.displayText,
                "audio_duration_ms": entry.audioDurationMs,
                "asr_duration_ms": entry.asrDurationMs,
                "llm_duration_ms": entry.llmDurationMs,
                "total_duration_ms": entry.totalDurationMs,
            ]
            if let value = entry.filteredText { row["filtered_text"] = value }
            if let value = entry.dictionaryCorrectedText { row["dictionary_text"] = value }
            if let value = entry.cleanedText { row["cleaned_text"] = value }
            if let value = entry.appName { row["app_name"] = value }
            if let value = entry.appBundleIdentifier { row["app_bundle_id"] = value }
            if let value = entry.windowTitle { row["window_title"] = value }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func performanceLine(_ entry: TranscriptionEntry) -> String {
        var parts = ["\(entry.asrDurationMs) ms ASR"]
        if entry.llmDurationMs > 0 { parts.append("\(entry.llmDurationMs) ms LLM") }
        parts.append("\(entry.totalDurationMs) ms total")
        if entry.asrDurationMs > 0 {
            let rtf = Double(entry.audioDurationMs) / Double(entry.asrDurationMs)
            parts.append(String(format: "%.1f× RTF", rtf))
        }
        return "_" + parts.joined(separator: " · ") + "_"
    }
}
