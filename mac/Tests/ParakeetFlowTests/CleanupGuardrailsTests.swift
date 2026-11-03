import Testing
@testable import ParakeetFlow

@Suite("Cleanup guardrails")
struct CleanupGuardrailsTests {
    @Test func extractsJsonCleanedText() {
        let response = """
        {"cleaned_text":"The meeting is at 3:30 tomorrow."}
        """
        #expect(
            CleanupGuardrails.extractCleanedText(response)
                == "The meeting is at 3:30 tomorrow."
        )
    }

    @Test func fallsBackToPlainText() {
        #expect(
            CleanupGuardrails.extractCleanedText("  The meeting is at three.  ")
                == "The meeting is at three."
        )
    }

    @Test func rejectsEmptyAndTruncatedRewrites() {
        let raw = "The meeting is at three thirty tomorrow afternoon."
        #expect(CleanupGuardrails.guardCleanup("", raw: raw) == raw)
        #expect(CleanupGuardrails.guardCleanup("The meeting", raw: raw) == raw)
    }

    @Test func rejectsRunawayRewrites() {
        let raw = "The meeting is at three."
        let runaway = String(repeating: "unrelated text ", count: 20)
        #expect(CleanupGuardrails.guardCleanup(runaway, raw: raw) == raw)
    }

    @Test func acceptsFaithfulCleanup() {
        let raw = "um the meeting is like at three thirty"
        let cleaned = "The meeting is at 3:30."
        #expect(CleanupGuardrails.guardCleanup(cleaned, raw: raw) == cleaned)
    }

    @Test func detectsNonLatinText() {
        #expect(CleanupGuardrails.isMostlyLatin("The quick brown fox"))
        #expect(!CleanupGuardrails.isMostlyLatin("今天的会议在三点半"))
    }
}
