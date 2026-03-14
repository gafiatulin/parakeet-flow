package com.github.gafiatulin.parakeetflow.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.github.gafiatulin.parakeetflow.ui.component.PipelineStageRow
import com.github.gafiatulin.parakeetflow.viewmodel.HistoryViewModel
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    onBack: () -> Unit,
    viewModel: HistoryViewModel = hiltViewModel()
) {
    val records by viewModel.records.collectAsState()
    val dateFormat = remember { SimpleDateFormat("MMM d, HH:mm", Locale.getDefault()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("History") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                },
                actions = {
                    if (records.isNotEmpty()) {
                        IconButton(onClick = { viewModel.clearHistory() }) {
                            Icon(Icons.Default.DeleteSweep, "Clear all")
                        }
                    }
                }
            )
        }
    ) { padding ->
        if (records.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "No transcriptions yet",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(records) { record ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp)
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    record.appContext,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Text(
                                    dateFormat.format(Date(record.timestampMillis)),
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            PipelineStageRow(label = "Raw", text = record.rawText)
                            if (record.filteredText != record.rawText) {
                                PipelineStageRow(label = "Filtered", text = record.filteredText)
                            }
                            if (record.cleanedText != record.filteredText) {
                                PipelineStageRow(label = "Cleaned", text = record.cleanedText)
                            }
                        }
                    }
                }
            }
        }
    }
}
