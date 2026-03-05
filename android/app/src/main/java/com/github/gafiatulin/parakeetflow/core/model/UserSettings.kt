package com.github.gafiatulin.parakeetflow.core.model

data class UserSettings(
    val llmEnabled: Boolean = true,
    val fillerFilterEnabled: Boolean = true,
    val hapticFeedback: Boolean = true,
    val audioFeedback: Boolean = true,
    val bubblePosition: BubblePosition = BubblePosition(x = -1, y = -1),
    val autoCapitalize: Boolean = true,
    val autoPunctuation: Boolean = true,
    val llmGpu: Boolean = true,
    val lingeringBubble: Boolean = false,
    val hfToken: String = ""
)

data class BubblePosition(val x: Int, val y: Int)
