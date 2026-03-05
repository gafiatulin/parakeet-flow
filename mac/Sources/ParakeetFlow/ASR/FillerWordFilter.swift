import Foundation

enum FillerWordFilter {
    private static let fillerPatterns: [String] = [
        "\\byou know\\b",
        "\\bI mean\\b",
        "\\bkind of\\b",
        "\\bsort of\\b",
        "\\bum\\b",
        "\\buh\\b",
        "\\bah\\b",
        "\\ber\\b",
        "\\blike\\b",
        "\\bbasically\\b",
        "\\bactually\\b",
        "\\bliterally\\b",
        "\\bhonestly\\b",
    ]

    static func removeFillersFromText(_ text: String) -> String {
        var result = text
        for pattern in fillerPatterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: .caseInsensitive
            ) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
