package com.github.gafiatulin.parakeetflow.asr

/**
 * Interface for speech-to-text transcription engines.
 *
 * Implementations must be thread-safe. [initialize] and [transcribe] are suspending
 * functions that should perform heavy work on an appropriate dispatcher.
 */
interface TranscriptionEngine {

    /**
     * Loads model files from [modelDir] and prepares the engine for inference.
     *
     * @param modelDir Absolute path to the directory containing model artifacts.
     * @return `true` if initialization succeeded, `false` otherwise.
     */
    suspend fun initialize(modelDir: String): Boolean

    /**
     * Transcribes 16 kHz mono PCM audio samples to text.
     *
     * @param pcmSamples Float array of audio samples in the range [-1.0, 1.0].
     * @return The transcribed text, or an empty string if nothing was recognized.
     */
    suspend fun transcribe(pcmSamples: FloatArray): String

    /**
     * Releases all native resources held by the engine.
     * After calling this, [isReady] must return `false`.
     */
    fun release()

    /**
     * Whether the engine is initialized and ready for transcription.
     */
    val isReady: Boolean
}
