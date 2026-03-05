package com.github.gafiatulin.parakeetflow.core.model

import kotlinx.serialization.Serializable

@Serializable
data class TranscriptionRecord(
    val id: String,
    val rawText: String,
    val filteredText: String,
    val cleanedText: String,
    val appContext: String,
    val timestampMillis: Long,
    val durationMillis: Long
)
