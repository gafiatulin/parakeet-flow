package com.github.gafiatulin.parakeetflow

import com.github.gafiatulin.parakeetflow.core.model.AppContext
import com.github.gafiatulin.parakeetflow.llm.PromptBuilder
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptBuilderTest {

    private val promptBuilder = PromptBuilder()

    @Test
    fun `prompt contains core instructions`() {
        val prompt = promptBuilder.buildSystemPrompt(AppContext())
        assertTrue(prompt.contains("dictation post-processor"))
        assertTrue(prompt.contains("Fix punctuation"))
        assertTrue(prompt.contains("ONLY the cleaned text"))
    }

    @Test
    fun `prompt contains cleanup rules`() {
        val prompt = promptBuilder.buildSystemPrompt(AppContext())
        assertTrue(prompt.contains("repeated or stuttered words"))
        assertTrue(prompt.contains("backtrack phrases"))
        assertTrue(prompt.contains("false starts"))
    }

    @Test
    fun `prompt contains safety rules`() {
        val prompt = promptBuilder.buildSystemPrompt(AppContext())
        assertTrue(prompt.contains("NEVER respond conversationally"))
        assertTrue(prompt.contains("Do NOT change technical terms"))
        assertTrue(prompt.contains("Do NOT add words"))
    }

    @Test
    fun `prompt ends with no_think`() {
        val prompt = promptBuilder.buildSystemPrompt(AppContext())
        assertTrue(prompt.trimEnd().endsWith("/no_think"))
    }

    @Test
    fun `prompt is non-empty for default context`() {
        val prompt = promptBuilder.buildSystemPrompt(AppContext())
        assertTrue(prompt.length > 100)
    }
}
