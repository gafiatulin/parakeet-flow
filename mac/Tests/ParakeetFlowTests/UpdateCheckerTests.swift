import Testing
@testable import ParakeetFlow

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    @Test func newerVersionsCompareNumerically() {
        #expect(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        #expect(UpdateChecker.isNewer("v2.0.0", than: "1.99.99"))
        #expect(UpdateChecker.isNewer("1.0.1", than: "1.0"))
    }

    @Test func equalAndOlderVersionsAreNotNewer() {
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.1"))
    }
}
