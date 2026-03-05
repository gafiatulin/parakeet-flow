package com.github.gafiatulin.parakeetflow.service

import com.github.gafiatulin.parakeetflow.core.model.AppPhase
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Singleton bridge connecting the various services (DictationService, ParakeetAccessibilityService)
 * with the rest of the application.
 *
 * Holds a reference to the active AccessibilityService instance and exposes
 * the current dictation pipeline phase as an observable [StateFlow].
 */
@Singleton
class ServiceBridge @Inject constructor() {

    /**
     * Reference to the currently connected [ParakeetAccessibilityService].
     * Set by the service on connect, cleared on destroy.
     *
     * This is intentionally not a WeakReference because the service lifecycle
     * is managed by the system and it will properly null this on destroy.
     */
    @Volatile
    var accessibilityService: ParakeetAccessibilityService? = null
        internal set

    private val _phase = MutableStateFlow(AppPhase.IDLE)

    /**
     * The current phase of the dictation pipeline.
     * Observed by the UI to show appropriate state indicators.
     */
    val phase: StateFlow<AppPhase> = _phase

    /**
     * Updates the current dictation phase.
     */
    fun updatePhase(phase: AppPhase) {
        _phase.value = phase
    }

    private val _textFieldFocused = MutableStateFlow(false)

    /**
     * Whether a text input field is currently focused in the foreground app.
     */
    val textFieldFocused: StateFlow<Boolean> = _textFieldFocused

    private val _textFieldFocusEvent = MutableSharedFlow<String>(extraBufferCapacity = 1)

    /**
     * Emitted every time a text field gains focus, with the node identity string.
     * Used to re-show the bubble after drag-to-dismiss.
     */
    val textFieldFocusEvent: SharedFlow<String> = _textFieldFocusEvent

    fun updateTextFieldFocused(focused: Boolean, nodeId: String = "") {
        _textFieldFocused.value = focused
        if (focused) {
            _textFieldFocusEvent.tryEmit(nodeId)
        }
    }

    /**
     * Whether the accessibility service is currently connected and available.
     */
    val isAccessibilityEnabled: Boolean
        get() = accessibilityService != null
}
