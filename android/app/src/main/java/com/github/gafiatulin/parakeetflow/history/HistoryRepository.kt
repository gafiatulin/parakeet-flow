package com.github.gafiatulin.parakeetflow.history

import android.content.Context
import android.util.Log
import com.github.gafiatulin.parakeetflow.core.model.TranscriptionRecord
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HistoryRepository @Inject constructor(
    @param:ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "HistoryRepository"
        private const val FILE_NAME = "history.json"
        private const val MAX_RECORDS = 25
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val file: File get() = File(context.filesDir, FILE_NAME)

    private val _records = MutableStateFlow<List<TranscriptionRecord>>(emptyList())
    val records: StateFlow<List<TranscriptionRecord>> = _records

    suspend fun load() = withContext(Dispatchers.IO) {
        try {
            if (file.exists()) {
                val data = file.readText()
                _records.value = json.decodeFromString<List<TranscriptionRecord>>(data)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load history", e)
        }
    }

    suspend fun add(record: TranscriptionRecord) = withContext(Dispatchers.IO) {
        val updated = (listOf(record) + _records.value).take(MAX_RECORDS)
        _records.value = updated
        save(updated)
    }

    suspend fun clear() = withContext(Dispatchers.IO) {
        _records.value = emptyList()
        file.delete()
    }

    private fun save(records: List<TranscriptionRecord>) {
        try {
            file.writeText(json.encodeToString(records))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save history", e)
        }
    }
}
