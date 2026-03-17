package com.github.gafiatulin.parakeetflow.model

import android.content.Context
import android.util.Log
import com.github.gafiatulin.parakeetflow.core.model.AsrModel
import com.github.gafiatulin.parakeetflow.core.model.ModelStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ModelManager @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val downloader: ModelDownloader
) {
    companion object {
        private const val TAG = "ModelManager"
        private const val MODELS_DIR = "models"
        private const val LLM_MODEL_DIR = "qwen3-llm"

        private const val LLM_BASE_URL =
            "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main"
        private const val LLM_MODEL_FILE = "Qwen3-0.6B.litertlm"
    }

    private val modelsDir: File
        get() = File(context.filesDir, MODELS_DIR)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _selectedAsrModel = MutableStateFlow(AsrModel.PARAKEET_V2)
    val selectedAsrModel: StateFlow<AsrModel> = _selectedAsrModel

    private val _asrStatusMap = MutableStateFlow(
        AsrModel.entries.associateWith<AsrModel, ModelStatus> { ModelStatus.NotDownloaded }
    )

    val asrStatus: StateFlow<ModelStatus> = combine(
        _selectedAsrModel, _asrStatusMap
    ) { model, map -> map[model] ?: ModelStatus.NotDownloaded }
        .stateIn(scope, kotlinx.coroutines.flow.SharingStarted.Eagerly, ModelStatus.NotDownloaded)

    private val _llmStatus = MutableStateFlow<ModelStatus>(ModelStatus.NotDownloaded)
    val llmStatus: StateFlow<ModelStatus> = _llmStatus

    fun getAsrModelDir(): File = File(modelsDir, _selectedAsrModel.value.dirName)

    /** Get model dir for a specific variant (used when switching models). */
    fun getAsrModelDir(model: AsrModel): File = File(modelsDir, model.dirName)

    fun getLlmModelDir(): File = File(modelsDir, LLM_MODEL_DIR)
    fun getLlmModelPath(): String = File(getLlmModelDir(), LLM_MODEL_FILE).absolutePath

    fun selectAsrModel(model: AsrModel) {
        _selectedAsrModel.value = model
        // Only update if not currently downloading
        val current = _asrStatusMap.value[model]
        if (current !is ModelStatus.Downloading) {
            updateAsrStatus(model, checkAsrModels(model))
        }
        Log.i(TAG, "Selected ASR model: ${model.displayName}, status: ${_asrStatusMap.value[model]}")
    }

    private fun updateAsrStatus(model: AsrModel, status: ModelStatus) {
        _asrStatusMap.value = _asrStatusMap.value.toMutableMap().apply { put(model, status) }
    }

    fun checkModelStatus() {
        for (model in AsrModel.entries) {
            val current = _asrStatusMap.value[model]
            if (current !is ModelStatus.Downloading) {
                updateAsrStatus(model, checkAsrModels(model))
            }
        }
        _llmStatus.value = checkLlmModels()
        Log.i(TAG, "ASR status: ${_asrStatusMap.value}, LLM status: ${_llmStatus.value}")
    }

    /** Check if a specific ASR model variant has all required files. */
    fun isAsrModelReady(model: AsrModel): Boolean {
        val dir = getAsrModelDir(model)
        return model.files.all { File(dir, it).exists() }
    }

    private fun checkAsrModels(model: AsrModel): ModelStatus {
        val dir = getAsrModelDir(model)
        return if (model.files.all { File(dir, it).exists() }) {
            ModelStatus.Ready
        } else {
            ModelStatus.NotDownloaded
        }
    }

    private fun checkLlmModels(): ModelStatus {
        val modelFile = File(getLlmModelDir(), LLM_MODEL_FILE)
        return if (modelFile.exists()) {
            ModelStatus.Ready
        } else {
            ModelStatus.NotDownloaded
        }
    }

    suspend fun downloadAsrModels(onProgress: (Float) -> Unit) {
        val model = _selectedAsrModel.value
        updateAsrStatus(model, ModelStatus.Downloading(0f))

        try {
            val dir = getAsrModelDir(model).apply { mkdirs() }
            val totalFiles = model.files.size
            var completedFiles = 0

            for (fileName in model.files) {
                val url = "${model.baseUrl}/$fileName"
                val destination = File(dir, fileName)

                downloader.downloadFile(
                    url = url,
                    destination = destination,
                    onProgress = { fileProgress ->
                        val overall = (completedFiles + fileProgress) / totalFiles
                        updateAsrStatus(model, ModelStatus.Downloading(overall))
                        onProgress(overall)
                    }
                )
                completedFiles++
            }

            updateAsrStatus(model, ModelStatus.Ready)
            Log.i(TAG, "${model.displayName} downloaded to ${dir.absolutePath}")
        } catch (e: Exception) {
            val message = e.message ?: "Download failed"
            updateAsrStatus(model, ModelStatus.Error(message))
            Log.e(TAG, "${model.displayName} download failed", e)
            throw e
        }
    }

    suspend fun downloadLlmModel(onProgress: (Float) -> Unit) {
        _llmStatus.value = ModelStatus.Downloading(0f)

        try {
            val dir = getLlmModelDir().apply { mkdirs() }
            val url = "$LLM_BASE_URL/$LLM_MODEL_FILE"
            val destination = File(dir, LLM_MODEL_FILE)

            downloader.downloadFile(
                url = url,
                destination = destination,
                onProgress = { progress ->
                    _llmStatus.value = ModelStatus.Downloading(progress)
                    onProgress(progress)
                },
            )

            _llmStatus.value = ModelStatus.Ready
            Log.i(TAG, "LLM model downloaded to ${dir.absolutePath}")
        } catch (e: Exception) {
            val message = e.message ?: "Download failed"
            _llmStatus.value = ModelStatus.Error(message)
            Log.e(TAG, "LLM model download failed", e)
            throw e
        }
    }

    fun deleteAsrModels() {
        val model = _selectedAsrModel.value
        getAsrModelDir(model).deleteRecursively()
        updateAsrStatus(model, ModelStatus.NotDownloaded)
        Log.i(TAG, "${model.displayName} deleted")
    }

    fun deleteLlmModel() {
        getLlmModelDir().deleteRecursively()
        _llmStatus.value = ModelStatus.NotDownloaded
        Log.i(TAG, "LLM model deleted")
    }

    fun cancelAsrDownload() {
        val model = _selectedAsrModel.value
        updateAsrStatus(model, ModelStatus.NotDownloaded)
        Log.i(TAG, "ASR download cancelled")
    }

    fun cancelLlmDownload() {
        _llmStatus.value = ModelStatus.NotDownloaded
        Log.i(TAG, "LLM download cancelled")
    }
}
