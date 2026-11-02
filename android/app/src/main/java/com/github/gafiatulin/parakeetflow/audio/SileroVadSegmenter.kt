package com.github.gafiatulin.parakeetflow.audio

import android.content.Context
import android.util.Log
import com.k2fsa.sherpa.onnx.SileroVadModelConfig
import com.k2fsa.sherpa.onnx.Vad
import com.k2fsa.sherpa.onnx.VadModelConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Silero VAD bundled as a small ONNX asset and driven by Sherpa-ONNX.
 *
 * The detector returns speech-only segments, which the dictation pipeline uses
 * both as a silence gate and as natural chunk boundaries for long recordings.
 */
@Singleton
class SileroVadSegmenter @Inject constructor(
    @param:ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "SileroVadSegmenter"
        private const val MODEL_ASSET = "silero_vad.onnx"
        private const val SAMPLE_RATE = 16_000
    }

    private val mutex = Mutex()
    private var vad: Vad? = null

    suspend fun segments(samples: FloatArray): List<FloatArray> = mutex.withLock {
        if (samples.isEmpty()) return@withLock emptyList()
        try {
            val detector = vad ?: create().also { vad = it }
            detector.reset()
            detector.acceptWaveform(samples)
            detector.flush()

            val result = ArrayList<FloatArray>()
            while (!detector.empty()) {
                val segment = detector.front()
                detector.pop()
                if (segment.samples.size >= SAMPLE_RATE / 4) {
                    result += segment.samples
                }
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Silero VAD failed; falling back to energy gate", e)
            emptyList()
        }
    }

    private fun create(): Vad = Vad(
        assetManager = context.assets,
        config = VadModelConfig(
            sileroVadModelConfig = SileroVadModelConfig(
                model = MODEL_ASSET,
                threshold = 0.5f,
                minSilenceDuration = 0.45f,
                minSpeechDuration = 0.2f,
                windowSize = 512,
                maxSpeechDuration = 15f,
            ),
            sampleRate = SAMPLE_RATE,
            numThreads = 1,
            provider = "cpu",
        )
    )
}
