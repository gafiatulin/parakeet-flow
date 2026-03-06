import Foundation

enum DictionaryCorrector {
    static let defaultThreshold: Double = 0.18

    /// Apply fuzzy + phonetic dictionary corrections to transcribed text.
    /// Scans n-grams (3→2→1 words) against dictionary entries using combined
    /// Levenshtein + Soundex scoring. Greedy longest-match-first.
    static func applyCorrections(
        _ text: String,
        dictionary: [String],
        threshold: Double = defaultThreshold
    ) -> String {
        guard !dictionary.isEmpty, !text.isEmpty else { return text }

        let entries = dictionary.map { word in
            (original: word, normalized: normalize(word))
        }

        let words = text.components(separatedBy: " ")
        var result: [String] = []
        var i = 0

        while i < words.count {
            var matched = false

            for n in stride(from: min(3, words.count - i), through: 1, by: -1) {
                let span = Array(words[i..<i+n])
                let joined = span.joined(separator: " ")
                let (core, leading, trailing) = extractPunctuation(joined)
                let normalized = normalize(core)

                if normalized.isEmpty { continue }

                // Length guard: skip very short normalized strings (likely punctuation-only)
                guard normalized.count >= 2 else { continue }

                if let best = findBestMatch(normalized, in: entries, threshold: threshold) {
                    let corrected = preserveCase(original: core, replacement: best)
                    result.append(leading + corrected + trailing)
                    i += n
                    matched = true
                    break
                }
            }

            if !matched {
                result.append(words[i])
                i += 1
            }
        }

        return result.joined(separator: " ")
    }

    /// Returns the subset of dictionary words that are relevant to the given text
    /// (i.e., at least one word in the text fuzzy-matches the dictionary entry).
    /// Useful for trimming the dictionary before injecting into an LLM prompt.
    static func relevantWords(from dictionary: [String], for text: String, threshold: Double = defaultThreshold) -> [String] {
        guard !dictionary.isEmpty, !text.isEmpty else { return [] }

        let textWords = text.lowercased().components(separatedBy: " ")
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { $0.count >= 2 }

        return dictionary.filter { entry in
            let normalized = entry.lowercased().filter { $0.isLetter || $0.isNumber }
            guard normalized.count >= 2 else { return false }
            return textWords.contains { word in
                combinedScore(word, normalized) < threshold * 2
            }
        }
    }

    // MARK: - Matching

    private static func findBestMatch(
        _ candidate: String,
        in entries: [(original: String, normalized: String)],
        threshold: Double
    ) -> String? {
        var bestScore = Double.infinity
        var bestWord: String?

        for entry in entries {
            // Length guard: skip if lengths differ by more than 25% (min 2 chars)
            let lenDiff = abs(candidate.count - entry.normalized.count)
            let maxAllowed = max(2, Int(Double(max(candidate.count, entry.normalized.count)) * 0.25))
            if lenDiff > maxAllowed { continue }

            let score = combinedScore(candidate, entry.normalized)
            if score < bestScore && score < threshold {
                bestScore = score
                bestWord = entry.original
            }
        }

        return bestWord
    }

    private static func combinedScore(_ a: String, _ b: String) -> Double {
        let levDistance = levenshteinDistance(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        let normalizedLev = Double(levDistance) / Double(maxLen)

        // If phonetic codes match, apply 70% discount (sounds alike → likely correct)
        if soundex(a) == soundex(b) {
            return normalizedLev * 0.3
        }
        return normalizedLev
    }

    // MARK: - Levenshtein Distance

    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1), b = Array(s2)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    curr[j] = prev[j-1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j-1], prev[j-1])
                }
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    // MARK: - Soundex

    static func soundex(_ word: String) -> String {
        let letters = word.uppercased().filter { $0.isASCII && $0.isLetter }
        guard let first = letters.first else { return "" }

        let map: [Character: Character] = [
            "B": "1", "F": "1", "P": "1", "V": "1",
            "C": "2", "G": "2", "J": "2", "K": "2", "Q": "2", "S": "2", "X": "2", "Z": "2",
            "D": "3", "T": "3",
            "L": "4",
            "M": "5", "N": "5",
            "R": "6",
        ]

        var code = String(first)
        var lastCode = map[first]

        for char in letters.dropFirst() {
            let charCode = map[char]
            if let c = charCode, c != lastCode {
                code.append(c)
                if code.count == 4 { break }
            }
            lastCode = charCode
        }

        return code.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    // MARK: - Text Helpers

    /// Lowercase, strip non-alphanumeric, remove spaces — for comparison.
    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Separate leading/trailing punctuation from the alphanumeric core.
    private static func extractPunctuation(_ text: String) -> (core: String, leading: String, trailing: String) {
        let chars = Array(text)
        var start = 0
        while start < chars.count, !chars[start].isLetter, !chars[start].isNumber {
            start += 1
        }
        var end = chars.count - 1
        while end >= start, !chars[end].isLetter, !chars[end].isNumber {
            end -= 1
        }

        let leading = start > 0 ? String(chars[0..<start]) : ""
        let trailing = end < chars.count - 1 ? String(chars[(end+1)...]) : ""
        let core = start <= end ? String(chars[start...end]) : ""
        return (core, leading, trailing)
    }

    /// Preserve the casing pattern of the original text on the replacement.
    private static func preserveCase(original: String, replacement: String) -> String {
        if original == original.uppercased(), original.count > 1 {
            return replacement.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
