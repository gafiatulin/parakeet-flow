import Testing
@testable import ParakeetFlow

@Suite("DictionaryCorrector")
struct DictionaryCorrectorTests {

    // MARK: - Levenshtein Distance

    @Test func levenshteinIdenticalStrings() {
        #expect(DictionaryCorrector.levenshteinDistance("hello", "hello") == 0)
    }

    @Test func levenshteinEmptyStrings() {
        #expect(DictionaryCorrector.levenshteinDistance("", "") == 0)
        #expect(DictionaryCorrector.levenshteinDistance("abc", "") == 3)
        #expect(DictionaryCorrector.levenshteinDistance("", "abc") == 3)
    }

    @Test func levenshteinSingleEdit() {
        #expect(DictionaryCorrector.levenshteinDistance("cat", "bat") == 1)  // substitution
        #expect(DictionaryCorrector.levenshteinDistance("cat", "cats") == 1) // insertion
        #expect(DictionaryCorrector.levenshteinDistance("cats", "cat") == 1) // deletion
    }

    @Test func levenshteinMultipleEdits() {
        #expect(DictionaryCorrector.levenshteinDistance("kitten", "sitting") == 3)
    }

    // MARK: - Soundex

    @Test func soundexBasicCodes() {
        #expect(DictionaryCorrector.soundex("Robert") == "R163")
        #expect(DictionaryCorrector.soundex("Rupert") == "R163")
    }

    @Test func soundexSimilarNames() {
        // Smith and Smyth should have the same soundex code
        #expect(DictionaryCorrector.soundex("Smith") == DictionaryCorrector.soundex("Smyth"))
    }

    @Test func soundexEmptyString() {
        #expect(DictionaryCorrector.soundex("") == "")
    }

    @Test func soundexPadding() {
        // Short codes should be padded with zeros
        let code = DictionaryCorrector.soundex("A")
        #expect(code == "A000")
    }

    // MARK: - Apply Corrections

    @Test func correctsMisspelling() {
        let result = DictionaryCorrector.applyCorrections(
            "open parakeetflo now",
            dictionary: ["ParakeetFlow"]
        )
        #expect(result.contains("ParakeetFlow"))
    }

    @Test func noMatchBelowThreshold() {
        let result = DictionaryCorrector.applyCorrections(
            "I went to the store",
            dictionary: ["ParakeetFlow"]
        )
        #expect(result == "I went to the store")
    }

    @Test func emptyDictionary() {
        let result = DictionaryCorrector.applyCorrections(
            "some text here",
            dictionary: []
        )
        #expect(result == "some text here")
    }

    @Test func emptyText() {
        let result = DictionaryCorrector.applyCorrections(
            "",
            dictionary: ["ParakeetFlow"]
        )
        #expect(result == "")
    }

    @Test func preservesPunctuation() {
        let result = DictionaryCorrector.applyCorrections(
            "I use parakeetflo, right?",
            dictionary: ["ParakeetFlow"]
        )
        #expect(result.contains("ParakeetFlow"))
    }

    @Test func preservesTitleCase() {
        let result = DictionaryCorrector.applyCorrections(
            "the Parakeetflo app",
            dictionary: ["ParakeetFlow"]
        )
        // Title-case input should preserve capitalized first letter
        #expect(result.contains("ParakeetFlow"))
    }

    // MARK: - Relevant Words

    @Test func findsRelevantWords() {
        let relevant = DictionaryCorrector.relevantWords(
            from: ["ParakeetFlow", "Xcode", "unrelated"],
            for: "I opened parakeetflo today"
        )
        #expect(relevant.contains("ParakeetFlow"))
        #expect(!relevant.contains("unrelated"))
    }

    @Test func emptyTextReturnsNoRelevant() {
        let relevant = DictionaryCorrector.relevantWords(
            from: ["ParakeetFlow"],
            for: ""
        )
        #expect(relevant.isEmpty)
    }
}
