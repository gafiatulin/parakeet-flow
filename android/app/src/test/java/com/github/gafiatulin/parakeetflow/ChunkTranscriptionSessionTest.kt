package com.github.gafiatulin.parakeetflow

import com.github.gafiatulin.parakeetflow.asr.ChunkTranscriptionSession
import com.github.gafiatulin.parakeetflow.asr.TranscriptionEngine
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class ChunkTranscriptionSessionTest {
    @Test
    fun joins_segments_in_order() = runBlocking {
        val channel = Channel<FloatArray>(Channel.UNLIMITED)
        val engine = object : TranscriptionEngine {
            override suspend fun initialize(modelDir: String) = true
            override suspend fun transcribe(pcmSamples: FloatArray) = "seg${pcmSamples[0].toInt()}"
            override fun release() = Unit
            override val isReady = true
        }

        val session = ChunkTranscriptionSession(engine, channel, this)
        channel.send(floatArrayOf(1f))
        channel.send(floatArrayOf(2f))
        channel.close()

        val result = session.finish()
        assertEquals("seg1 seg2", result.text)
        assertEquals(2, result.segmentCount)
        assertEquals(2, result.speechSamples)
    }
}
