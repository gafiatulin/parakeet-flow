package com.github.gafiatulin.parakeetflow

import android.os.Debug
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Benchmark int8 vs int4 encoder: WER, RTF, memory.
 *
 * Push models:
 *   adb push encoder.int4.onnx /data/local/tmp/sherpa-test/
 *   (int8 models already at /data/local/tmp/sherpa-test/)
 *
 * Push test wavs:
 *   adb push /tmp/librispeech_test/ /data/local/tmp/librispeech_test/
 *
 * Run:
 *   ./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.github.gafiatulin.parakeetflow.Int4BenchmarkTest
 */
@RunWith(AndroidJUnit4::class)
class Int4BenchmarkTest {

    companion object {
        private const val TAG = "Int4Benchmark"
        private const val MODEL_DIR = "/data/local/tmp/sherpa-test"
        private const val WAV_DIR = "/data/local/tmp/librispeech_test/librispeech_test"
    }

    @Test
    fun benchmarkInt8VsInt4() {
        val modelDir = File(MODEL_DIR)
        val wavDir = File(WAV_DIR)
        assertTrue("Model dir missing: $MODEL_DIR", modelDir.exists())
        assertTrue("WAV dir missing: $WAV_DIR", wavDir.exists())

        val refs = File(wavDir, "refs.txt").readLines().filter { it.isNotBlank() }
        val wavFiles = (0 until refs.size).map { File(wavDir, "%03d.wav".format(it)) }
        assertTrue("No WAV files found", wavFiles.all { it.exists() })
        Log.i(TAG, "Loaded ${refs.size} references")

        data class Result(val label: String, val wer: Double, val rtf: Double, val inferMs: Long, val audioSec: Double, val loadMs: Long, val memDeltaMB: Double, val heapMB: Double)
        val results = mutableListOf<Result>()

        for ((label, encoderFile) in listOf("INT8" to "encoder.int8.onnx", "INT4" to "encoder.int4.onnx")) {
            val encFile = File(modelDir, encoderFile)
            if (!encFile.exists()) {
                Log.w(TAG, "Skipping $label: $encoderFile not found")
                continue
            }

            // Force GC before measuring
            System.gc()
            Thread.sleep(500)
            val memBefore = Debug.getNativeHeapAllocatedSize()

            val loadStart = System.currentTimeMillis()
            val recognizer = createRecognizer(modelDir, encoderFile)
            val loadMs = System.currentTimeMillis() - loadStart

            val memAfter = Debug.getNativeHeapAllocatedSize()
            val memDeltaMB = (memAfter - memBefore) / 1024.0 / 1024.0

            Log.i(TAG, "=== $label ===")
            Log.i(TAG, "Load: ${loadMs}ms, Memory delta: ${"%.0f".format(memDeltaMB)} MB")
            Log.i(TAG, "Native heap: ${"%.0f".format(memAfter / 1024.0 / 1024.0)} MB")

            val hyps = mutableListOf<String>()
            var totalInferMs = 0L
            var totalAudioSec = 0.0

            for (i in wavFiles.indices) {
                val pcm = readWavAsFloat(wavFiles[i]) ?: continue
                val audioSec = pcm.size / 16000.0
                totalAudioSec += audioSec

                val stream = recognizer.createStream()
                stream.acceptWaveform(pcm, 16000)
                val t0 = System.currentTimeMillis()
                recognizer.decode(stream)
                val inferMs = System.currentTimeMillis() - t0
                totalInferMs += inferMs

                val text = recognizer.getResult(stream).text.trim()
                stream.release()
                hyps.add(text)

                if (i < 3) {
                    Log.i(TAG, "  [$i] ${inferMs}ms RTF=${"%.3f".format(inferMs / 1000.0 / audioSec)}")
                    Log.i(TAG, "    H: \"$text\"")
                    Log.i(TAG, "    R: \"${refs[i]}\"")
                }
            }

            val rtf = totalInferMs / 1000.0 / totalAudioSec

            // Simple WER: count word errors
            var totalWords = 0
            var totalErrors = 0
            for (i in refs.indices) {
                val refWords = refs[i].uppercase().split("\\s+".toRegex())
                val hypWords = hyps[i].uppercase().split("\\s+".toRegex())
                totalWords += refWords.size
                // Levenshtein distance on words
                totalErrors += editDistance(refWords, hypWords)
            }
            val wer = totalErrors.toDouble() / totalWords * 100

            results.add(Result(label, wer, rtf, totalInferMs, totalAudioSec, loadMs, memDeltaMB, memAfter / 1024.0 / 1024.0))

            recognizer.release()
            System.gc()
            Thread.sleep(500)
        }

        // Print combined summary at the end so it doesn't get flushed from logcat
        Log.i(TAG, "========== BENCHMARK SUMMARY ==========")
        for (r in results) {
            Log.i(TAG, "--- ${r.label}: WER=${"%.2f".format(r.wer)}% RTF=${"%.3f".format(r.rtf)} Load=${r.loadMs}ms MemDelta=${"%.0f".format(r.memDeltaMB)}MB Heap=${"%.0f".format(r.heapMB)}MB Infer=${r.inferMs}ms Audio=${"%.0f".format(r.audioSec)}s")
        }
        Log.i(TAG, "========================================")
    }

    private fun createRecognizer(dir: File, encoderFile: String): OfflineRecognizer {
        return OfflineRecognizer(
            config = OfflineRecognizerConfig(
                featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
                modelConfig = OfflineModelConfig(
                    transducer = OfflineTransducerModelConfig(
                        encoder = File(dir, encoderFile).absolutePath,
                        decoder = File(dir, "decoder.int8.onnx").absolutePath,
                        joiner = File(dir, "joiner.int8.onnx").absolutePath,
                    ),
                    tokens = File(dir, "tokens.txt").absolutePath,
                    numThreads = 4,
                    provider = "cpu",
                ),
                decodingMethod = "greedy_search",
            )
        )
    }

    private fun editDistance(a: List<String>, b: List<String>): Int {
        val m = a.size
        val n = b.size
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in 0..m) dp[i][0] = i
        for (j in 0..n) dp[0][j] = j
        for (i in 1..m) {
            for (j in 1..n) {
                dp[i][j] = if (a[i - 1] == b[j - 1]) {
                    dp[i - 1][j - 1]
                } else {
                    minOf(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
                }
            }
        }
        return dp[m][n]
    }

    private fun readWavAsFloat(file: File): FloatArray? {
        try {
            val raf = RandomAccessFile(file, "r")
            val bytes = ByteArray(raf.length().toInt())
            raf.readFully(bytes)
            raf.close()

            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val riff = ByteArray(4); buf.get(riff)
            require(String(riff) == "RIFF")
            buf.int
            val wave = ByteArray(4); buf.get(wave)
            require(String(wave) == "WAVE")

            var sampleRate = 0
            var numChannels = 0
            var dataBytes: ByteArray? = null

            while (buf.remaining() >= 8) {
                val chunkId = ByteArray(4); buf.get(chunkId)
                val chunkSize = buf.int
                when (String(chunkId)) {
                    "fmt " -> {
                        buf.short // format
                        numChannels = buf.short.toInt()
                        sampleRate = buf.int
                        buf.int; buf.short
                        val bits = buf.short.toInt()
                        val extra = chunkSize - 16
                        if (extra > 0) buf.position(buf.position() + extra)
                        require(bits == 16)
                    }
                    "data" -> {
                        dataBytes = ByteArray(chunkSize)
                        buf.get(dataBytes)
                    }
                    else -> buf.position(buf.position() + chunkSize)
                }
            }

            requireNotNull(dataBytes)
            val dataBuf = ByteBuffer.wrap(dataBytes).order(ByteOrder.LITTLE_ENDIAN)
            val samplesPerChannel = dataBytes.size / 2 / numChannels
            val pcm = FloatArray(samplesPerChannel)
            for (i in 0 until samplesPerChannel) {
                if (numChannels == 1) {
                    pcm[i] = dataBuf.short.toFloat() / 32768f
                } else {
                    var sum = 0f
                    repeat(numChannels) { sum += dataBuf.short.toFloat() / 32768f }
                    pcm[i] = sum / numChannels
                }
            }
            return pcm
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read WAV: ${file.name}", e)
            return null
        }
    }
}
