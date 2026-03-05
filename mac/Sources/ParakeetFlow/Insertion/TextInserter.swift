import Cocoa

enum TextInserter {
    static func insert(_ text: String) async {
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

        // Wait for paste to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Restore previous clipboard
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
}
