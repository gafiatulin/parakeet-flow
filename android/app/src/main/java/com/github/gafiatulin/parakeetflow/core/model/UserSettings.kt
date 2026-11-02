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
    val hfToken: String = "",
    // Bubble appearance
    val bubbleSizeDp: Int = 64,
    val bubbleColor: Int = DEFAULT_BUBBLE_COLOR,
    val bubbleOpacity: Float = 1f,
    // While recording, show pause/cancel beside the bubble on the inward side
    // instead of below it.
    val bubbleControlsBeside: Boolean = true
)

/** Default idle bubble color (ParakeetGreen, 0xFF4CAF50) as a packed ARGB int. */
const val DEFAULT_BUBBLE_COLOR: Int = 0xFF4CAF50.toInt()

data class BubblePosition(val x: Int, val y: Int)
