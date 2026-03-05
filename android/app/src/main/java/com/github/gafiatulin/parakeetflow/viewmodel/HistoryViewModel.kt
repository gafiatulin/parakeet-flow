package com.github.gafiatulin.parakeetflow.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.github.gafiatulin.parakeetflow.core.model.TranscriptionRecord
import com.github.gafiatulin.parakeetflow.history.HistoryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val historyRepository: HistoryRepository
) : ViewModel() {
    val records: StateFlow<List<TranscriptionRecord>> = historyRepository.records

    init {
        viewModelScope.launch { historyRepository.load() }
    }

    fun clearHistory() {
        viewModelScope.launch { historyRepository.clear() }
    }
}
