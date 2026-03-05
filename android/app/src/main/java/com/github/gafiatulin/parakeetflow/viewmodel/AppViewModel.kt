package com.github.gafiatulin.parakeetflow.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.github.gafiatulin.parakeetflow.core.model.AppPhase
import com.github.gafiatulin.parakeetflow.core.model.AsrModel
import com.github.gafiatulin.parakeetflow.core.model.ModelStatus
import com.github.gafiatulin.parakeetflow.model.ModelManager
import com.github.gafiatulin.parakeetflow.service.ServiceBridge
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AppViewModel @Inject constructor(
    private val serviceBridge: ServiceBridge,
    private val modelManager: ModelManager
) : ViewModel() {

    val phase: StateFlow<AppPhase> = serviceBridge.phase
    val asrStatus: StateFlow<ModelStatus> = modelManager.asrStatus
    val llmStatus: StateFlow<ModelStatus> = modelManager.llmStatus
    val selectedAsrModel: StateFlow<AsrModel> = modelManager.selectedAsrModel

    val isAccessibilityEnabled: Boolean
        get() = serviceBridge.isAccessibilityEnabled

    private var asrDownloadJob: Job? = null
    private var llmDownloadJob: Job? = null

    init {
        modelManager.checkModelStatus()
    }

    fun selectAsrModel(model: AsrModel) {
        modelManager.selectAsrModel(model)
    }

    fun downloadAsrModel() {
        asrDownloadJob = viewModelScope.launch {
            try {
                modelManager.downloadAsrModels { }
            } catch (_: Exception) { }
        }
    }

    fun cancelAsrDownload() {
        asrDownloadJob?.cancel()
        asrDownloadJob = null
        modelManager.cancelAsrDownload()
    }

    fun deleteAsrModel() {
        modelManager.deleteAsrModels()
    }

    fun downloadLlmModel() {
        llmDownloadJob = viewModelScope.launch {
            try {
                modelManager.downloadLlmModel(onProgress = {})
            } catch (_: Exception) { }
        }
    }

    fun cancelLlmDownload() {
        llmDownloadJob?.cancel()
        llmDownloadJob = null
        modelManager.cancelLlmDownload()
    }

    fun deleteLlmModel() {
        modelManager.deleteLlmModel()
    }
}
