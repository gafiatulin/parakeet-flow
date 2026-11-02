import Foundation

enum CleanupGuardrails {
    static func extractCleanedText(_ response: String) -> String? {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let json = String(text[start...end])
            if let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cleaned = object["cleaned_text"] as? String {
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let thinkEnd = text.range(of: "</think>") {
            text = String(text[thinkEnd.upperBound...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func guardCleanup(_ cleaned: String, raw: String) -> String {
        let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !rawTrimmed.isEmpty else { return rawTrimmed }
        // Refuse obviously destructive or runaway rewrites.
        if candidate.count < max(4, rawTrimmed.count / 4) { return rawTrimmed }
        if candidate.count > max(80, rawTrimmed.count * 2) { return rawTrimmed }
        return candidate
    }

    /// The default cleanup fine-tune is English-only. Leaving non-Latin text
    /// alone is safer than letting an English cleanup model rewrite it.
    static func isMostlyLatin(_ text: String) -> Bool {
        var letters = 0
        var nonLatin = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            if scalar.value > 0x024F { nonLatin += 1 }
        }
        guard letters > 0 else { return true }
        return nonLatin <= max(1, letters / 5)
    }
}
