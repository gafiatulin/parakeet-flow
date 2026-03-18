package com.github.gafiatulin.parakeetflow.llm

import com.github.gafiatulin.parakeetflow.core.model.AppContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PromptBuilder @Inject constructor() {

    fun buildSystemPrompt(appContext: AppContext): String {
        return buildString {
            append(
                "You are a dictation post-processor. " +
                "The user sends raw voice-transcribed text. " +
                "Output ONLY the cleaned text. No commentary, no explanation, no quotes."
            )
            appendLine()
            appendLine()
            appendLine("Rules:")
            appendLine("- Fix punctuation and capitalization")
            appendLine("- Remove repeated or stuttered words")
            appendLine("- Keep ALL sentences and meaning intact")
            appendLine("- Do NOT remove, summarize, or condense content")
            appendLine("- Do NOT change technical terms or proper nouns")
            appendLine("- Do NOT add words that were not spoken")
            append("- If the input is already clean, return it unchanged\n/no_think")
        }
    }
}
