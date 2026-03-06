import Foundation

enum FillerWordFilter {
    static let defaultFillerWords: [String] = [
        "you know",
        "I mean",
        "kind of",
        "sort of",
        "um",
        "uh",
        "ah",
        "er",
        "like",
        "basically",
        "actually",
        "literally",
        "honestly",
    ]

    nonisolated(unsafe) private static var compiledPatterns: [(NSRegularExpression, String)] = {
        buildPatterns(defaultFillerWords)
    }()

    static func updatePatterns(_ words: [String]) {
        compiledPatterns = buildPatterns(words)
    }

    private static func buildPatterns(_ words: [String]) -> [(NSRegularExpression, String)] {
        words.compactMap { word in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return (regex, word)
        }
    }

    static func removeFillersFromText(_ text: String) -> String {
        var result = text
        for (regex, _) in compiledPatterns {
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
