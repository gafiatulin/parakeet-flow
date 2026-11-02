package com.github.gafiatulin.parakeetflow.asr

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.launch

/**
 * Consumes VAD speech segments while recording and transcribes them in order.
 * The producer closes [segments] in AudioCaptureManager.stopCapture().
 */
class ChunkTranscriptionSession(
    private val engine: TranscriptionEngine,
    private val segments: ReceiveChannel<FloatArray>,
    scope: CoroutineScope
) {
    data class Result(val text: String, val segmentCount: Int, val speechSamples: Int)

    private val texts = mutableListOf<String>()
    private var segmentCount = 0
    private var speechSamples = 0
    private val job: Job = scope.launch(Dispatchers.Default) {
        for (segment in segments) {
            segmentCount++
            speechSamples += segment.size
            val text = engine.transcribe(segment).trim()
            if (text.isNotEmpty()) texts += text
        }
    }

    suspend fun finish(): Result {
        job.join()
        return Result(texts.joinToString(" "), segmentCount, speechSamples)
    }

    fun cancel() {
        job.cancel()
        segments.cancel()
    }
}
