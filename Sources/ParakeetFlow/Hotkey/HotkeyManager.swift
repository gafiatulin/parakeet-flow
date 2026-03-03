import Cocoa
import AVFoundation
@preconcurrency import ApplicationServices

/// Manages a CGEventTap for hotkey detection.
/// Emits key-press, key-release (with hold duration), and escape callbacks.
final class HotkeyManager: @unchecked Sendable {
    var onKeyPress: (@Sendable () -> Void)?
    var onKeyRelease: (@Sendable (_ duration: Double) -> Void)?
    var onEscapeKey: (@Sendable () -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var isKeyDown = false
    fileprivate var keyDownTime: CFAbsoluteTime = 0

    var hotkeyModifier: CGEventFlags = .maskAlternate

    @MainActor
    static func permissionStatus() -> (listenAccess: Bool, accessibility: Bool) {
        let listen = CGPreflightListenEventAccess()
        let ax = AXIsProcessTrusted()
        return (listen, ax)
    }

    @MainActor
    static func requestPermissions() -> String? {
        let (listen, ax) = permissionStatus()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        if !listen {
            CGRequestListenEventAccess()
        }
        if !ax {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        var missing: [String] = []
        if !listen { missing.append("Input Monitoring") }
        if !ax { missing.append("Accessibility") }
        if !mic { missing.append("Microphone") }

        if missing.isEmpty { return nil }
        return "Grant \(missing.joined(separator: " and ")) permission\(missing.count > 1 ? "s" : ""), then retry."
    }

    @MainActor
    func start() -> (success: Bool, error: String?) {
        let (listen, ax) = Self.permissionStatus()

        if !listen || !ax {
            let msg = Self.requestPermissions()
            return (false, msg)
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: userInfo
        ) else {
            return (false, "Failed to create event tap. Try restarting the app after granting permissions.")
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return (true, nil)
    }

    @MainActor
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyDown = false
    }

    fileprivate func handleFlagsChanged(_ flags: CGEventFlags) {
        let isPressed = flags.contains(hotkeyModifier)

        if isPressed && !isKeyDown {
            isKeyDown = true
            keyDownTime = CFAbsoluteTimeGetCurrent()
            onKeyPress?()
        } else if !isPressed && isKeyDown {
            isKeyDown = false
            let duration = CFAbsoluteTimeGetCurrent() - keyDownTime
            onKeyRelease?(duration)
        }
    }

    fileprivate func handleKeyDown(_ keycode: Int64) {
        if keycode == 53 { // Escape
            onEscapeKey?()
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if type == .flagsChanged {
        manager.handleFlagsChanged(event.flags)
    } else if type == .keyDown {
        manager.handleKeyDown(event.getIntegerValueField(.keyboardEventKeycode))
    }

    return Unmanaged.passRetained(event)
}

