import Testing
@testable import ParakeetFlow

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test func basicPromptContainsRules() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: nil, appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil)
        )
        #expect(prompt.contains("dictation post-processor"))
        #expect(prompt.contains("Fix punctuation"))
        #expect(prompt.contains("Remove filler words"))
    }

    @Test func fillerRemovalDisabled() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: nil, appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil),
            removeFillers: false
        )
        #expect(prompt.contains("Keep filler words"))
        #expect(!prompt.contains("Remove filler words"))
    }

    @Test func includesAppContext() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: "Slack", appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil)
        )
        #expect(prompt.contains("Slack"))
        #expect(prompt.contains("casual"))
    }

    @Test func slackToneIsCasual() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: "Slack", appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil)
        )
        #expect(prompt.contains("casual, conversational"))
    }

    @Test func mailToneIsFormal() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: "Mail", appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil)
        )
        #expect(prompt.contains("professional, formal"))
    }

    @Test func xcodeToneIsTechnical() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: "Xcode", appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil)
        )
        #expect(prompt.contains("technical, precise"))
    }

    @Test func unknownAppToneIsNeutral() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: "SomeRandomApp", appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil)
        )
        #expect(prompt.contains("neutral, clear"))
    }

    @Test func includesWindowTitle() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: "Safari", appBundleIdentifier: nil, windowTitle: "GitHub - Pull Request", surroundingText: nil)
        )
        #expect(prompt.contains("GitHub - Pull Request"))
    }

    @Test func includesDictionaryWords() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: nil, appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil),
            dictionaryWords: ["ParakeetFlow", "SwiftUI"]
        )
        #expect(prompt.contains("ParakeetFlow"))
        #expect(prompt.contains("SwiftUI"))
        #expect(prompt.contains("Dictionary"))
    }

    @Test func emptyDictionaryOmitsSection() {
        let prompt = PromptBuilder.buildSystemPrompt(
            context: AppContext(appName: nil, appBundleIdentifier: nil, windowTitle: nil, surroundingText: nil),
            dictionaryWords: []
        )
        #expect(!prompt.contains("Dictionary"))
    }
}
