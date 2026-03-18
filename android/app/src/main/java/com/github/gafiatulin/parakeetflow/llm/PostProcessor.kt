package com.github.gafiatulin.parakeetflow.llm

import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import com.github.gafiatulin.parakeetflow.core.model.AppContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PostProcessor @Inject constructor(
    private val promptBuilder: PromptBuilder
) {
    companion object {
        private const val TAG = "PostProcessor"
    }

    private var engine: Engine? = null

    @Volatile
    private var isInitialized = false

    val isReady: Boolean
        get() = isInitialized

    suspend fun initialize(modelPath: String, useGpu: Boolean = true): Boolean = withContext(Dispatchers.IO) {
        try {
            if (isInitialized) {
                release()
            }

            val modelFile = java.io.File(modelPath)
            if (!modelFile.exists()) {
                Log.e(TAG, "Model file does not exist: $modelPath")
                return@withContext false
            }

            // GPU init can OOM-kill the process on some devices, so only attempt
            // GPU when the user explicitly opts in.
            val backend = if (useGpu) Backend.GPU() else Backend.CPU()
            val eng = try {
                val config = EngineConfig(modelPath = modelPath, backend = backend)
                Engine(config).also {
                    it.initialize()
                    Log.i(TAG, "LLM engine initialized on ${if (useGpu) "GPU" else "CPU"}")
                }
            } catch (e: Exception) {
                if (!useGpu) throw e
                Log.w(TAG, "GPU init failed, falling back to CPU", e)
                val cpuConfig = EngineConfig(modelPath = modelPath, backend = Backend.CPU())
                Engine(cpuConfig).also {
                    it.initialize()
                    Log.i(TAG, "LLM engine initialized on CPU (GPU fallback)")
                }
            }

            engine = eng
            isInitialized = true
            Log.i(TAG, "LLM engine ready from $modelPath")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize LLM engine", e)
            isInitialized = false
            false
        }
    }

    suspend fun cleanup(rawText: String, appContext: AppContext): String = withContext(Dispatchers.IO) {
        if (!isInitialized || engine == null) {
            Log.w(TAG, "LLM not initialized, returning raw text")
            return@withContext rawText
        }

        if (rawText.isBlank()) {
            return@withContext rawText
        }

        try {
            val result = withTimeoutOrNull(15_000L) {
                val systemPrompt = promptBuilder.buildSystemPrompt(appContext)

                val convConfig = ConversationConfig(
                    systemInstruction = Contents.of(systemPrompt),
                    samplerConfig = SamplerConfig(
                        topK = 1,
                        topP = 0.9,
                        temperature = 0.1,
                        seed = 0
                    )
                )

                engine!!.createConversation(convConfig).use { conv ->
                    // Strip Qwen3 thinking tags if present
                    conv.sendMessage(rawText).toString().trim()
                        .replace(Regex("(?s)<think>.*?</think>\\s*"), "")
                }
            }

            if (result.isNullOrBlank()) {
                Log.w(TAG, "LLM timed out or returned empty, using raw text")
                rawText
            } else {
                Log.d(TAG, "LLM cleanup: '$rawText' -> '$result'")
                result
            }
        } catch (e: Exception) {
            Log.e(TAG, "LLM cleanup failed, returning raw text", e)
            rawText
        }
    }

    fun release() {
        try {
            engine?.close()
            engine = null
            isInitialized = false
            Log.i(TAG, "LLM engine released")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing LLM engine", e)
        }
    }
}
