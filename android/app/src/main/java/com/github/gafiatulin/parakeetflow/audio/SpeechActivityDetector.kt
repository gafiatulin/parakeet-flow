package com.github.gafiatulin.parakeetflow.audio

import kotlin.math.sqrt

/**
 * Conservative energy-based speech gate for the offline ASR path.
 *
 * It is intentionally fail-open for anything that looks like speech and only
 * rejects clips whose level is essentially silence. A future Silero model can
 * replace this without changing the pipeline contract.
 */
object SpeechActivityDetector {
    private const val FRAME_MS = 20
    private const val MIN_PEAK_RMS = 0.010f
    private const val MIN_ACTIVE_FRAMES = 2
    private const val ACTIVE_RMS_FLOOR = 0.008f

    fun containsSpeech(samples: FloatArray, sampleRate: Int = AudioCaptureManager.SAMPLE_RATE): Boolean {
        if (samples.isEmpty() || sampleRate <= 0) return false

        val frameSize = maxOf(1, sampleRate * FRAME_MS / 1000)
        val frameRms = ArrayList<Float>(samples.size / frameSize + 1)
        var index = 0
        while (index < samples.size) {
            val end = minOf(index + frameSize, samples.size)
            var sum = 0.0
            for (i in index until end) {
                val value = samples[i].toDouble()
                sum += value * value
            }
            frameRms += sqrt(sum / (end - index)).toFloat()
            index = end
        }

        val peak = frameRms.maxOrNull() ?: 0f
        if (peak < MIN_PEAK_RMS) return false

        // Compare frames with the loudest frame rather than the mean: a
        // continuous voice at a steady level should pass, while one isolated
        // click in an otherwise silent clip should not.
        val threshold = maxOf(ACTIVE_RMS_FLOOR, peak * 0.25f)
        return frameRms.count { it >= threshold } >= MIN_ACTIVE_FRAMES
    }
}
