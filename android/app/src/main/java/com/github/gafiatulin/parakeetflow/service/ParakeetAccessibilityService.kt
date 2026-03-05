package com.github.gafiatulin.parakeetflow.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class ParakeetAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "ParakeetA11yService"
    }

    @Inject lateinit var serviceBridge: ServiceBridge

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceBridge.accessibilityService = this

        serviceInfo = serviceInfo.apply {
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            eventTypes = AccessibilityEvent.TYPE_VIEW_FOCUSED or
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            flags = flags or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            notificationTimeout = 100
        }

        Log.i(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_FOCUSED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                checkForTextFieldFocus()
            }
        }
    }

    private fun checkForTextFieldFocus() {
        try {
            val root = rootInActiveWindow ?: run {
                Log.d(TAG, "No active window root")
                serviceBridge.updateTextFieldFocused(false)
                return
            }
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            val isTextField = focused != null && focused.isEditable
            val nodeId = if (isTextField) {
                "${focused.className}@${focused.windowId}:${focused.viewIdResourceName.orEmpty()}"
            } else ""
            Log.d(TAG, "Text field focused: $isTextField (node: $nodeId)")
            serviceBridge.updateTextFieldFocused(isTextField, nodeId)
        } catch (e: Exception) {
            Log.w(TAG, "Focus check failed", e)
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        serviceBridge.accessibilityService = null
        serviceBridge.updateTextFieldFocused(false)
        Log.i(TAG, "Accessibility service destroyed")
        super.onDestroy()
    }
}
