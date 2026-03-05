package com.github.gafiatulin.parakeetflow.insertion

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import com.github.gafiatulin.parakeetflow.service.ServiceBridge
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Inserts processed text into the currently focused text field.
 *
 * Strategy:
 * 1. Try `ACTION_SET_TEXT` on the focused input node (cleanest approach).
 * 2. Fall back to clipboard paste via `ACTION_PASTE` if set-text fails.
 * 3. Restores the previous clipboard content after a short delay.
 */
@Singleton
class TextInserter @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val serviceBridge: ServiceBridge
) {
    companion object {
        private const val TAG = "TextInserter"
        private const val CLIPBOARD_RESTORE_DELAY_MS = 500L
    }

    /**
     * Inserts [text] into the currently focused text field.
     *
     * @return `true` if the text was successfully inserted.
     */
    fun insert(text: String): Boolean {
        if (text.isEmpty()) return false

        val service = serviceBridge.accessibilityService
        if (service == null) {
            Log.w(TAG, "Accessibility service unavailable, cannot insert text")
            return false
        }

        val rootNode = service.rootInActiveWindow
        if (rootNode == null) {
            Log.w(TAG, "No active window, falling back to clipboard paste")
            return pasteViaClipboard(text)
        }

        val focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focusedNode == null) {
            Log.w(TAG, "No focused input node, falling back to clipboard paste")
            return pasteViaClipboard(text)
        }

        try {
            // Strategy 1: Paste via clipboard (inserts at cursor, doesn't read existing text)
            val pasted = pasteViaClipboard(text, focusedNode)
            if (pasted) return true

            // Strategy 2: Fall back to ACTION_SET_TEXT
            Log.d(TAG, "Clipboard paste failed, falling back to ACTION_SET_TEXT")
            val args = Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    text
                )
            }
            val setTextSuccess = focusedNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            if (setTextSuccess) {
                Log.d(TAG, "Text inserted via ACTION_SET_TEXT")
                return true
            }

            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting text", e)
            return pasteViaClipboard(text)
        } finally {
        }
    }

    private fun pasteViaClipboard(text: String, existingFocusedNode: AccessibilityNodeInfo? = null): Boolean {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        // Save previous clipboard content
        val previousClip = try {
            clipboard.primaryClip
        } catch (e: Exception) {
            Log.w(TAG, "Could not read previous clipboard", e)
            null
        }

        // Set our text to clipboard
        clipboard.setPrimaryClip(ClipData.newPlainText("parakeetflow_dictation", text))

        // Attempt to paste via accessibility
        val focusedNode: AccessibilityNodeInfo?
        var rootNode: AccessibilityNodeInfo? = null
        if (existingFocusedNode != null) {
            focusedNode = existingFocusedNode
        } else {
            val service = serviceBridge.accessibilityService
            rootNode = service?.rootInActiveWindow
            focusedNode = rootNode?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        }

        val pasted = try {
            focusedNode?.performAction(AccessibilityNodeInfo.ACTION_PASTE) ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Paste action failed", e)
            false
        }


        // Restore previous clipboard after a delay to ensure paste completes
        if (previousClip != null) {
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    clipboard.setPrimaryClip(previousClip)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not restore previous clipboard", e)
                }
            }, CLIPBOARD_RESTORE_DELAY_MS)
        }

        if (pasted) {
            Log.d(TAG, "Text inserted via clipboard paste")
        } else {
            Log.w(TAG, "Clipboard paste failed — text is on clipboard for manual paste")
        }

        return pasted
    }
}
