package com.github.gafiatulin.parakeetflow

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * On-device instrumentation test for the Sherpa-ONNX ASR pipeline.
 *
 * Prerequisites — push models and a test WAV to the device:
 *   ./scripts/push_test_models.sh
 *
 * Run:
 *   ./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.github.gafiatulin.parakeetflow.SherpaOnnxPipelineTest
 */
@RunWith(AndroidJUnit4::class)
class SherpaOnnxPipelineTest {

    companion object {
        private const val TAG = "SherpaOnnxPipelineTest"
        private const val TEST_DIR = "parakeet-test"
    }

    private val testDir: File
        get() = File("/data/local/tmp", TEST_DIR)

    private var recognizer: OfflineRecognizer? = null

    @Before
    fun setUp() {
        val dir = testDir
        assertTrue(
            "Test directory not found: ${dir.absolutePath}. " +
                "Push models with: ./scripts/push_test_models.sh",
            dir.exists()
        )

        val requiredFiles = listOf(
            "encoder.int8.onnx",
            "decoder.int8.onnx",
            "joiner.int8.onnx",
            "tokens.txt",
            "test.wav"
        )
        for (name in requiredFiles) {
            val f = File(dir, name)
            assertTrue("Missing: ${f.absolutePath}", f.exists())
            Log.i(TAG, "Found: $name (${f.length() / 1024}KB)")
        }
    }

    @After
    fun tearDown() {
        recognizer?.release()
        recognizer = null
        Log.i(TAG, "Recognizer released")
    }

    @Test
    fun testLoadModels() {
        val dir = testDir
        Log.i(TAG, "=== testLoadModels ===")

        val t0 = System.currentTimeMillis()
        recognizer = createRecognizer(dir)
        val loadMs = System.currentTimeMillis() - t0

        assertNotNull("createRecognizer returned null", recognizer)
        Log.i(TAG, "Models loaded in ${loadMs}ms")
    }

    @Test
    fun testTranscription() {
        val dir = testDir
        Log.i(TAG, "=== testTranscription ===")

        // Load models
        val t0 = System.currentTimeMillis()
        recognizer = createRecognizer(dir)
        val loadMs = System.currentTimeMillis() - t0
        assertNotNull("createRecognizer returned null", recognizer)
        Log.i(TAG, "Models loaded in ${loadMs}ms")

        // Read WAV file
        val wavFile = File(dir, "test.wav")
        val pcm = readWavAsFloat(wavFile)
        assertNotNull("Failed to read WAV", pcm)
        assertTrue("WAV is empty", pcm!!.isNotEmpty())
        Log.i(TAG, "WAV: ${pcm.size} samples (${pcm.size / 16000.0}s)")

        // Transcribe
        val rec = recognizer!!
        val t1 = System.currentTimeMillis()
        val stream = rec.createStream()
        stream.acceptWaveform(pcm, 16000)
        rec.decode(stream)
        val text = rec.getResult(stream).text
        stream.release()
        val inferMs = System.currentTimeMillis() - t1

        Log.i(TAG, "Transcription (${inferMs}ms): \"$text\"")
        Log.i(TAG, "RTF: ${inferMs / 1000.0 / (pcm.size / 16000.0)}")

        assertTrue("Transcription is empty", text.isNotBlank())
        val wordCount = text.trim().split("\\s+".toRegex()).size
        Log.i(TAG, "Word count: $wordCount")
        assertTrue("Expected at least 3 words, got $wordCount", wordCount >= 3)

        Log.i(TAG, "=== PASS ===")
    }

    private fun createRecognizer(dir: File): OfflineRecognizer {
        val config = OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
            modelConfig = OfflineModelConfig(
                transducer = OfflineTransducerModelConfig(
                    encoder = File(dir, "encoder.int8.onnx").absolutePath,
                    decoder = File(dir, "decoder.int8.onnx").absolutePath,
                    joiner = File(dir, "joiner.int8.onnx").absolutePath,
                ),
                tokens = File(dir, "tokens.txt").absolutePath,
                numThreads = 4,
                provider = "cpu",
            ),
            decodingMethod = "greedy_search",
        )
        return OfflineRecognizer(config = config)
    }

    /**
     * Read a 16-bit PCM WAV file and return float samples in [-1, 1].
     * Handles only mono/stereo 16-bit WAV. Converts stereo to mono.
     */
    private fun readWavAsFloat(file: File): FloatArray? {
        try {
            val raf = RandomAccessFile(file, "r")
            val bytes = ByteArray(raf.length().toInt())
            raf.readFully(bytes)
            raf.close()

            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

            // Parse RIFF header
            val riff = ByteArray(4); buf.get(riff)
            require(String(riff) == "RIFF") { "Not a RIFF file" }
            buf.int // chunk size
            val wave = ByteArray(4); buf.get(wave)
            require(String(wave) == "WAVE") { "Not a WAVE file" }

            var sampleRate = 0
            var numChannels = 0
            var bitsPerSample = 0
            var dataBytes: ByteArray? = null

            // Parse chunks
            while (buf.remaining() >= 8) {
                val chunkId = ByteArray(4); buf.get(chunkId)
                val chunkSize = buf.int
                val id = String(chunkId)

                when (id) {
                    "fmt " -> {
                        val audioFormat = buf.short.toInt()
                        numChannels = buf.short.toInt()
                        sampleRate = buf.int
                        buf.int // byte rate
                        buf.short // block align
                        bitsPerSample = buf.short.toInt()
                        val extraFmt = chunkSize - 16
                        if (extraFmt > 0) {
                            buf.position(buf.position() + extraFmt)
                        }
                        Log.i(TAG, "WAV fmt: ${sampleRate}Hz, ${numChannels}ch, ${bitsPerSample}bit, format=$audioFormat")
                        require(audioFormat == 1) { "Only PCM WAV supported (got format $audioFormat)" }
                        require(bitsPerSample == 16) { "Only 16-bit WAV supported (got $bitsPerSample)" }
                    }
                    "data" -> {
                        dataBytes = ByteArray(chunkSize)
                        buf.get(dataBytes)
                    }
                    else -> {
                        buf.position(buf.position() + chunkSize)
                    }
                }
            }

            requireNotNull(dataBytes) { "No data chunk found" }
            require(sampleRate > 0) { "No fmt chunk found" }

            val dataBuf = ByteBuffer.wrap(dataBytes).order(ByteOrder.LITTLE_ENDIAN)
            val totalSamples = dataBytes.size / 2
            val samplesPerChannel = totalSamples / numChannels

            val pcm = FloatArray(samplesPerChannel)
            for (i in 0 until samplesPerChannel) {
                if (numChannels == 1) {
                    pcm[i] = dataBuf.short.toFloat() / 32768f
                } else {
                    var sum = 0f
                    for (ch in 0 until numChannels) {
                        sum += dataBuf.short.toFloat() / 32768f
                    }
                    pcm[i] = sum / numChannels
                }
            }

            if (sampleRate != 16000) {
                Log.i(TAG, "Resampling from ${sampleRate}Hz to 16000Hz")
                return resample(pcm, sampleRate, 16000)
            }

            return pcm
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read WAV: ${e.message}", e)
            return null
        }
    }

    private fun resample(input: FloatArray, srcRate: Int, dstRate: Int): FloatArray {
        val ratio = srcRate.toDouble() / dstRate
        val outLen = (input.size / ratio).toInt()
        val output = FloatArray(outLen)
        for (i in 0 until outLen) {
            val srcPos = i * ratio
            val idx = srcPos.toInt()
            val frac = (srcPos - idx).toFloat()
            output[i] = if (idx + 1 < input.size) {
                input[idx] * (1f - frac) + input[idx + 1] * frac
            } else {
                input[idx]
            }
        }
        return output
    }
}
