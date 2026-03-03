struct AppContext: Codable {
    let appName: String?
    let windowTitle: String?
    let surroundingText: String?
}

enum PromptBuilder {
    static func buildSystemPrompt(context: AppContext, removeFillers: Bool = true) -> String {
        var prompt = """
        You are a dictation post-processor. Your ONLY job is to clean up voice-transcribed text \
        and return the cleaned version. Do NOT add any commentary, explanation, or extra text. \
        Do NOT use <think> tags or any reasoning. Do NOT wrap output in quotes or markdown.

        Rules:
        - Remove false starts and self-corrections (keep only the corrected version)
        - Fix grammar and punctuation
        - Maintain the speaker's intended meaning exactly
        - Do not add information that wasn't spoken
        - Do not change technical terms or proper nouns
        - Output ONLY the cleaned text, nothing else — no preamble, no explanation
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
