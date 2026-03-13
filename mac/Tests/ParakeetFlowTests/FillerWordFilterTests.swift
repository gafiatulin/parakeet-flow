import Testing
@testable import ParakeetFlow

@Suite("FillerWordFilter")
struct FillerWordFilterTests {

    init() {
        FillerWordFilter.updatePatterns(FillerWordFilter.defaultFillerWords)
    }

    @Test func removesSimpleFillers() {
        let result = FillerWordFilter.removeFillersFromText("I um think this is uh great")
        #expect(result == "I think this is great")
    }

    @Test func removesMultiWordFillers() {
        let result = FillerWordFilter.removeFillersFromText("So you know I was kind of thinking")
        #expect(result == "So I was thinking")
    }

    @Test func preservesCleanText() {
        let input = "This is a clean sentence."
        let result = FillerWordFilter.removeFillersFromText(input)
        #expect(result == input)
    }

    @Test func handlesEmptyString() {
        let result = FillerWordFilter.removeFillersFromText("")
        #expect(result == "")
    }

    @Test func isCaseInsensitive() {
        let result = FillerWordFilter.removeFillersFromText("UM I think UH this is LIKE great")
        #expect(result == "I think this is great")
    }

    @Test func collapsesMultipleSpaces() {
        let result = FillerWordFilter.removeFillersFromText("I um uh think")
        #expect(result == "I think")
    }

    @Test func respectsWordBoundaries() {
        // "like" should not be removed from "likelihood"
        let result = FillerWordFilter.removeFillersFromText("the likelihood is high")
        #expect(result == "the likelihood is high")
    }

    @Test func customPatterns() {
        FillerWordFilter.updatePatterns(["well", "right"])
        let result = FillerWordFilter.removeFillersFromText("well I think right this works")
        #expect(result == "I think this works")
        // Restore defaults
        FillerWordFilter.updatePatterns(FillerWordFilter.defaultFillerWords)
    }
}
