package com.github.gafiatulin.parakeetflow.core.model

sealed interface ModelStatus {
    data object NotDownloaded : ModelStatus
    data class Downloading(val progress: Float) : ModelStatus
    data object Ready : ModelStatus
    data class Error(val message: String) : ModelStatus
}
