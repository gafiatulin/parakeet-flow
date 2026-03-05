package com.github.gafiatulin.parakeetflow.ui.screen

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PermissionsScreen(onBack: () -> Unit) {
    val context = LocalContext.current

    // Re-check permissions when returning from system settings
    var refreshKey by remember { mutableIntStateOf(0) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshKey++
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val hasMic = remember(refreshKey) { checkPermission(context, Manifest.permission.RECORD_AUDIO) }
    val hasOverlay = remember(refreshKey) { Settings.canDrawOverlays(context) }
    val hasNotif = remember(refreshKey) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            checkPermission(context, Manifest.permission.POST_NOTIFICATIONS)
        else true
    }
    val hasAccessibility = remember(refreshKey) { isAccessibilityServiceEnabled(context) }

    val micLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refreshKey++ }

    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { refreshKey++ }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Permissions") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Required Permissions", style = MaterialTheme.typography.headlineSmall)
            Text(
                "ParakeetFlow needs these permissions to work properly.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))

            PermissionRow(
                icon = Icons.Default.Mic,
                title = "Microphone",
                description = "Record your voice for transcription",
                granted = hasMic,
                actionLabel = "Grant",
                onAction = { micLauncher.launch(Manifest.permission.RECORD_AUDIO) }
            )

            PermissionRow(
                icon = Icons.Default.ChatBubble,
                title = "Overlay",
                description = "Show the floating dictation bubble",
                granted = hasOverlay,
                actionLabel = "Open Settings",
                onAction = {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${context.packageName}")
                    )
                    context.startActivity(intent)
                }
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                PermissionRow(
                    icon = Icons.Default.Notifications,
                    title = "Notifications",
                    description = "Show recording status notification",
                    granted = hasNotif,
                    actionLabel = "Grant",
                    onAction = { notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }
                )
            }

            PermissionRow(
                icon = Icons.Default.Accessibility,
                title = "Accessibility Service",
                description = "Insert text and read context from apps",
                granted = hasAccessibility,
                actionLabel = "Open Settings",
                onAction = {
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                }
            )
        }
    }
}

@Composable
private fun PermissionRow(
    icon: ImageVector,
    title: String,
    description: String,
    granted: Boolean,
    actionLabel: String,
    onAction: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (granted) MaterialTheme.colorScheme.primary
                       else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(
                    description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (granted) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = "Granted",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(32.dp)
                )
            } else {
                FilledTonalButton(onClick = onAction) { Text(actionLabel) }
            }
        }
    }
}

private fun checkPermission(context: Context, permission: String): Boolean =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

private fun isAccessibilityServiceEnabled(context: Context): Boolean {
    val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    val enabledServices = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
    return enabledServices.any {
        it.resolveInfo.serviceInfo.packageName == context.packageName
    }
}
