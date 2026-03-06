import Cocoa
import ApplicationServices
import Carbon.HIToolbox

enum TextInserter {
    static func insert(_ text: String, method: PasteMethod) async {
        switch method {
        case .paste:
            await insertViaPaste(text)
        case .accessibility:
            if !insertViaAccessibility(text) {
                await insertViaPaste(text)
            }
        case .keyByKey:
            await insertViaKeyByKey(text)
        case .clipboardOnly:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    // MARK: - Cmd+V Paste

    private static func insertViaPaste(_ text: String) async {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let savedTypes = pasteboard.types
        var savedData: [(NSPasteboard.PasteboardType, Data)] = []
        if let types = savedTypes {
            for type in types {
                if let data = pasteboard.data(forType: type) {
                    savedData.append((type, data))
                }
            }
        }

        // Set our text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate Cmd+V
        simulatePaste()

        // Wait for paste to complete, then restore
        try? await Task.sleep(for: .milliseconds(100))

        if !savedData.isEmpty {
            pasteboard.clearContents()
            for (type, data) in savedData {
                pasteboard.setData(data, forType: type)
            }
        }
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key code 9 = V key
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Accessibility API

    private static func insertViaAccessibility(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success else { return false }

        let element = focusedElement as! AXUIElement

        // Check if the element is writable
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return false
        }

        // Check for selected text range — if there's a selection, replace it
        var selectedRange: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            // Set selected text (replaces selection, or inserts at cursor if selection is empty)
            let setResult = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            return setResult == .success
        }

        // No selection support — try appending to value
        var currentValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success,
           let current = currentValue as? String {
            let newValue = current + text
            let setResult = AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                newValue as CFTypeRef
            )
            return setResult == .success
        }

        // Empty field — just set the value
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        return setResult == .success
    }

    // MARK: - Key-by-Key Typing

    private static func insertViaKeyByKey(_ text: String) async {
        let source = CGEventSource(stateID: .combinedSessionState)

        for char in text {
            let str = String(char) as NSString
            let uniChar = str.character(at: 0)

            // Create key event and set the Unicode string
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }

            var buffer = uniChar
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &buffer)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &buffer)

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)

            // Small delay between keystrokes to avoid overwhelming the target app
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
