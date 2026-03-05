package com.github.gafiatulin.parakeetflow.ui.component

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.github.gafiatulin.parakeetflow.core.model.ModelStatus

@Composable
fun ModelStatusCard(
    title: String,
    description: String,
    status: ModelStatus,
    onDownload: () -> Unit,
    onCancel: () -> Unit = {},
    onDelete: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    Card(modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            when (status) {
                is ModelStatus.NotDownloaded -> {
                    Button(onClick = onDownload) { Text("Download") }
                }
                is ModelStatus.Downloading -> {
                    LinearProgressIndicator(
                        progress = { status.progress },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "${(status.progress * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall
                        )
                        TextButton(onClick = onCancel) { Text("Cancel") }
                    }
                }
                is ModelStatus.Ready -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "\u2713 Ready",
                            color = MaterialTheme.colorScheme.primary
                        )
                        TextButton(onClick = onDelete) {
                            Text("Delete", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
                is ModelStatus.Error -> {
                    Text(
                        "Error: ${status.message}",
                        color = MaterialTheme.colorScheme.error
                    )
                    TextButton(onClick = onDownload) { Text("Retry") }
                }
            }
        }
    }
}
