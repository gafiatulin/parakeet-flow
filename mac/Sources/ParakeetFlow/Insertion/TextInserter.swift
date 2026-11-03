import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import os

/// What the frontmost app currently reports as its focused element.
enum TextFocusKind: Equatable {
    /// The focus is a text control (text field, text view, web editor, ...).
    case editable
    /// The focus is a control that cannot receive text (Finder items, menus, ...).
    case notEditable
    /// The app did not expose a usable accessibility element. Electron and
    /// Chromium apps (VS Code, Slack, Chrome, ...) keep their accessibility
    /// tree disabled until an assistive client asks for it, so this is the
    /// normal answer for them.
    case unknown
}

enum TextInserter {
    private static let logger = Logger(
        subsystem: "com.github.gafiatulin.ParakeetFlow", category: "Insertion"
    )

    /// Returns true when the text was sent to an editable target. When the
    /// focused element is known to be non-text (Finder desktop/list, a menu, an
    /// image, etc.), the transcript is copied instead of sending Cmd+V into
    /// arbitrary UI. Inconclusive targets are treated as editable so dictation
    /// is never silently dropped in Electron/Chromium apps.
    @discardableResult
    static func insert(_ text: String, method: PasteMethod) async -> Bool {
        let kind = method == .clipboardOnly ? TextFocusKind.editable : textFocusKind()
        logger.notice(
            "Insertion target: \(String(describing: kind), privacy: .public) in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public)"
        )
        if kind == .notEditable {
            copyToClipboard(text)
            return false
        }

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
            copyToClipboard(text)
        }
        return true
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Whether the frontmost app exposes an editable text element as focus.
    /// This prevents a normal Finder selection from receiving a Cmd+V that
    /// Finder treats as a file operation.
    static func hasEditableTextFocus() -> Bool {
        textFocusKind() != .notEditable
    }

    /// Classifies the focused element of the frontmost app. Never enables the
    /// target app's accessibility tree: doing so switches Chromium apps into
    /// their screen-reader mode, which is both slow and visible to the user.
    static func textFocusKind() -> TextFocusKind {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return effectiveFocusKind(rawFocusKind(for: app), bundleID: app.bundleIdentifier)
    }

    /// Focus classification straight from the accessibility tree. `.unknown`
    /// means the app did not answer, which is normal for Electron/Chromium
    /// apps because their accessibility tree stays disabled until an
    /// assistive client asks for it.
    static func rawFocusKind(for app: NSRunningApplication) -> TextFocusKind {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success, let focusedElement else {
            return .unknown
        }

        return focusKind(for: focusedElement as! AXUIElement)
    }

    /// Resolves an inconclusive accessibility answer. File managers report no
    /// useful focused element even when their file list is focused, and a
    /// Cmd+V there is a file operation — so an unknown focus means "copied to
    /// the clipboard" rather than "paste into the folder". Everywhere else an
    /// unknown focus means an app with a hidden accessibility tree (VS Code,
    /// Slack, Chrome, ...), which does accept text.
    static func effectiveFocusKind(_ kind: TextFocusKind, bundleID: String?) -> TextFocusKind {
        guard kind == .unknown, let bundleID, fileManagerBundleIDs.contains(bundleID) else {
            return kind
        }
        return .notEditable
    }

    static func focusKind(for element: AXUIElement) -> TextFocusKind {
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &settable
        )

        var selectedRange: AnyObject?
        let hasSelectedTextRange = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &selectedRange
        ) == .success

        return focusKind(
            role: roleValue as? String,
            valueSettable: settableResult == .success && settable.boolValue,
            hasSelectedTextRange: hasSelectedTextRange
        )
    }

    /// Pure role/attribute classification, split out so it can be tested.
    static func focusKind(
        role: String?,
        valueSettable: Bool,
        hasSelectedTextRange: Bool
    ) -> TextFocusKind {
        if let role {
            if editableRoles.contains(role) { return .editable }
            if nonTextRoles.contains(role) { return .notEditable }
        }

        // Some web views expose a settable value without a conventional role.
        // Require a text selection range as evidence that this is a text
        // control, not a Finder icon or another settable UI element.
        if valueSettable && hasSelectedTextRange { return .editable }

        // Unknown roles (AXWebArea, AXGroup, empty Electron trees, ...) are
        // inconclusive: let the caller paste rather than drop the dictation.
        return .unknown
    }

    static func isEditableRole(_ role: String) -> Bool {
        editableRoles.contains(role)
    }

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
    ]

    /// Apps where an inconclusive focus still means "a file list is focused"
    /// and Cmd+V would duplicate or create files instead of typing text.
    private static let fileManagerBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.cocoatech.PathFinder",
        "com.binarynights.ForkLift",
        "com.panic.Transmit",
    ]

    private static let nonTextRoles: Set<String> = [
        kAXButtonRole as String,
        kAXMenuItemRole as String,
        kAXMenuBarRole as String,
        kAXRowRole as String,
        kAXCellRole as String,
        kAXImageRole as String,
        kAXStaticTextRole as String,
    ]

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
        let changeCount = pasteboard.changeCount

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate Cmd+V
        await simulatePaste()

        // Chromium/Electron apps (VS Code, Slack, Chrome) read the pasteboard
        // asynchronously from a renderer process, so give them more time than
        // native text views before restoring the previous clipboard.
        try? await Task.sleep(for: .milliseconds(300))

        // Don't clobber anything the user copied while we waited.
        if !savedData.isEmpty, pasteboard.changeCount == changeCount {
            pasteboard.clearContents()
            for (type, data) in savedData {
                pasteboard.setData(data, forType: type)
            }
        }
    }

    private static func simulatePaste() async {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key code 9 = V key
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        // Give slower app runtimes a chance to see a real key press.
        try? await Task.sleep(for: .milliseconds(10))

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

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if let role = roleValue as? String, nonTextRoles.contains(role) {
            return false
        }

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
