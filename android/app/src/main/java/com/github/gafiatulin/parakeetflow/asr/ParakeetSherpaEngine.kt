package com.github.gafiatulin.parakeetflow.asr

import android.util.Log
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * [TranscriptionEngine] implementation backed by Parakeet TDT ONNX models
 * running through sherpa-onnx [OfflineRecognizer].
 *
 * Expects the following files in the model directory:
 * - `encoder.int8.onnx`
 * - `decoder.int8.onnx`
 * - `joiner.int8.onnx`
 * - `tokens.txt`
 */
@Singleton
class ParakeetSherpaEngine @Inject constructor() : TranscriptionEngine {

    companion object {
        private const val TAG = "ParakeetSherpa"
        private val REQUIRED_FILES = listOf(
            "encoder.int8.onnx",
            "decoder.int8.onnx",
            "joiner.int8.onnx",
            "tokens.txt"
        )
    }

    @Volatile
    private var recognizer: OfflineRecognizer? = null

    private val mutex = Mutex()

    override val isReady: Boolean
        get() = recognizer != null

    override suspend fun initialize(modelDir: String): Boolean = withContext(Dispatchers.IO) {
        mutex.withLock {
            try {
                recognizer?.release()
                recognizer = null

                val dir = File(modelDir)

                // Pick encoder: prefer int4 if available, fallback to int8
                val encoderFile = listOf("encoder.int4.onnx", "encoder.int8.onnx")
                    .map { File(dir, it) }
                    .firstOrNull { it.exists() }
                if (encoderFile == null) {
                    Log.e(TAG, "No encoder model found in $modelDir")
                    return@withContext false
                }
                val requiredFiles = listOf("decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt")
                for (fileName in requiredFiles) {
                    val file = File(dir, fileName)
                    if (!file.exists()) {
                        Log.e(TAG, "Missing required model file: ${file.absolutePath}")
                        return@withContext false
                    }
                }
                Log.i(TAG, "Using encoder: ${encoderFile.name}")

                val config = OfflineRecognizerConfig(
                    featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
                    modelConfig = OfflineModelConfig(
                        transducer = OfflineTransducerModelConfig(
                            encoder = encoderFile.absolutePath,
                            decoder = File(dir, "decoder.int8.onnx").absolutePath,
                            joiner = File(dir, "joiner.int8.onnx").absolutePath,
                        ),
                        tokens = File(dir, "tokens.txt").absolutePath,
                        numThreads = 4,
                        provider = "cpu",
                    ),
                    decodingMethod = "greedy_search",
                )

                recognizer = OfflineRecognizer(config = config)
                Log.i(TAG, "Engine initialized successfully from $modelDir")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize engine", e)
                false
            }
        }
    }

    override suspend fun transcribe(pcmSamples: FloatArray): String = withContext(Dispatchers.IO) {
        val rec = recognizer
        requireNotNull(rec) { "Recognizer not initialized — call initialize() first" }

        if (pcmSamples.isEmpty()) {
            return@withContext ""
        }

        try {
            val stream = rec.createStream()
            stream.acceptWaveform(pcmSamples, 16000)
            rec.decode(stream)
            val result = rec.getResult(stream).text
            stream.release()
            result.trim()
        } catch (e: Exception) {
            Log.e(TAG, "Transcription failed", e)
            ""
        }
    }

    override fun release() {
        val rec = recognizer
        if (rec != null) {
            recognizer = null
            try {
                rec.release()
                Log.i(TAG, "Engine released")
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing engine", e)
            }
        }
    }
}
