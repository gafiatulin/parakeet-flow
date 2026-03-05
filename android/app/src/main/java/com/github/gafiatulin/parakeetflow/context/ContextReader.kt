package com.github.gafiatulin.parakeetflow.context

import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import com.github.gafiatulin.parakeetflow.core.model.AppContext
import com.github.gafiatulin.parakeetflow.core.util.PackageNameMapper
import com.github.gafiatulin.parakeetflow.service.ServiceBridge
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Reads context from the currently focused application via the AccessibilityService.
 *
 * This provides the LLM post-processor with information about where the dictated
 * text will be inserted, allowing it to adapt tone and formatting.
 */
@Singleton
class ContextReader @Inject constructor(
    @param:ApplicationContext private val appContext: Context,
    private val serviceBridge: ServiceBridge
) {
    companion object {
        private const val TAG = "ContextReader"
    }

    /**
     * Reads context from the currently active window and focused input field.
     *
     * @return [AppContext] with package name, app label, window title, and surrounding text.
     *         Returns an empty [AppContext] if the accessibility service is unavailable.
     */
    fun readCurrentContext(): AppContext {
        val service = serviceBridge.accessibilityService
        if (service == null) {
            Log.d(TAG, "Accessibility service not available")
            return AppContext()
        }

        val rootNode = service.rootInActiveWindow
        if (rootNode == null) {
            Log.d(TAG, "No active window root node")
            return AppContext()
        }

        var focusedNode: AccessibilityNodeInfo? = null
        try {
            val packageName = rootNode.packageName?.toString() ?: ""
            val appLabel = PackageNameMapper.getAppLabel(appContext, packageName)

            // Find the currently focused input field for surrounding text
            focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            val surroundingText = focusedNode?.text?.toString() ?: ""

            // Get the active window title
            val activityTitle = try {
                service.windows
                    .firstOrNull { it.isActive }
                    ?.title?.toString() ?: ""
            } catch (e: Exception) {
                Log.w(TAG, "Could not read window title", e)
                ""
            }

            return AppContext(
                packageName = packageName,
                appLabel = appLabel,
                activityTitle = activityTitle,
                surroundingText = surroundingText
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error reading context", e)
            return AppContext()
        } finally {
        }
    }
}
