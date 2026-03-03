struct AppContext: Codable {
    let appName: String?
    let windowTitle: String?
    let surroundingText: String?
}

enum PromptBuilder {
    static func buildSystemPrompt(context: AppContext, removeFillers: Bool = true) -> String {
        var prompt = """
        You are a dictation post-processor. Clean up voice-transcribed text and return the result. \
        Output ONLY the cleaned text — no commentary, no explanation, no quotes, no markdown.

        Rules:
        - Fix punctuation and capitalization
        - Remove repeated or stuttered words (e.g. "I I think" → "I think")
        - Remove false starts ONLY when the speaker immediately restates the same idea \
        (e.g. "go to the, go to the store" → "go to the store")
        - KEEP all sentences and ideas — do NOT remove, summarize, or condense content
        - Do NOT change technical terms, proper nouns, or names
        - Do NOT add words that weren't spoken
        - If the input is already clean, return it unchanged
        """

        if removeFillers {
            prompt += "\n- Remove filler words (um, uh, like, you know, so, basically, actually, I mean)"
        } else {
            prompt += "\n- Keep filler words as-is — do not remove them"
        }

        if let appName = context.appName {
            prompt += "\n\nContext: The user is typing in \(appName)."

            let tone = toneForApp(appName)
            prompt += " Use \(tone) tone and formatting."
        }

        if let windowTitle = context.windowTitle {
            prompt += "\nWindow: \(windowTitle)"
        }

        return prompt
    }

    private static func toneForApp(_ appName: String) -> String {
        let app = appName.lowercased()

        switch app {
        case let a where a.contains("slack") || a.contains("discord") || a.contains("messages"):
            return "casual, conversational"
        case let a where a.contains("mail") || a.contains("outlook"):
            return "professional, formal"
        case let a where a.contains("xcode") || a.contains("terminal") || a.contains("code"):
            return "technical, precise"
        case let a where a.contains("notes") || a.contains("notion"):
            return "clear, organized"
        default:
            return "neutral, clear"
        }
    }
}
