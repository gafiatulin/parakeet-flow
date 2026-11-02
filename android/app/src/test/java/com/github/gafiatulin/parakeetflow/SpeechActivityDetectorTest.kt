package com.github.gafiatulin.parakeetflow

import com.github.gafiatulin.parakeetflow.audio.SpeechActivityDetector
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class SpeechActivityDetectorTest {
    @Test
    fun silence_is_rejected() {
        assertFalse(SpeechActivityDetector.containsSpeech(FloatArray(16_000)))
    }

    @Test
    fun audible_clip_is_accepted() {
        val samples = FloatArray(16_000) { index ->
            (0.15 * sin(2.0 * PI * 220.0 * index / 16_000.0)).toFloat()
        }
        assertTrue(SpeechActivityDetector.containsSpeech(samples))
    }

    @Test
    fun quiet_clip_with_a_single_spike_is_rejected() {
        val samples = FloatArray(16_000)
        samples[8_000] = 0.2f
        assertFalse(SpeechActivityDetector.containsSpeech(samples))
    }
}
