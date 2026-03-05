package com.github.gafiatulin.parakeetflow.llm

import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
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

            val eng = if (useGpu) {
                try {
                    val gpuConfig = EngineConfig(modelPath = modelPath, backend = Backend.GPU)
                    Engine(gpuConfig).also {
                        it.initialize()
                        Log.i(TAG, "LLM engine initialized on GPU")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "GPU init failed, falling back to CPU", e)
                    val cpuConfig = EngineConfig(modelPath = modelPath, backend = Backend.CPU)
                    Engine(cpuConfig).also {
                        it.initialize()
                        Log.i(TAG, "LLM engine initialized on CPU (GPU fallback)")
                    }
                }
            } else {
                val cpuConfig = EngineConfig(modelPath = modelPath, backend = Backend.CPU)
                Engine(cpuConfig).also {
                    it.initialize()
                    Log.i(TAG, "LLM engine initialized on CPU")
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
                val systemMessage = Message.user(systemPrompt)

                val convConfig = ConversationConfig(
                    systemMessage = systemMessage,
                    samplerConfig = SamplerConfig(
                        topK = 1,
                        topP = 0.9,
                        temperature = 0.1,
                        seed = 0
                    )
                )

                val conv = engine!!.createConversation(convConfig)
                val response = conv.sendMessage(rawText)
                conv.close()

                // Strip Qwen3 thinking tags if present
                response.toString().trim()
                    .replace(Regex("(?s)<think>.*?</think>\\s*"), "")
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
