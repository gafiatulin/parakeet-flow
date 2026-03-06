import Cocoa
import ApplicationServices

enum ContextReader {
    static func readCurrentContext() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName
        let windowTitle = getWindowTitle(pid: app?.processIdentifier)
        let surroundingText = getSurroundingText(pid: app?.processIdentifier)

        return AppContext(
            appName: appName,
            appBundleIdentifier: app?.bundleIdentifier,
            windowTitle: windowTitle,
            surroundingText: surroundingText
        )
    }

    private static func getWindowTitle(pid: pid_t?) -> String? {
        guard let pid else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard result == .success else { return nil }

        var title: AnyObject?
        AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        )
        return title as? String
    }

    private static func getSurroundingText(pid: pid_t?) -> String? {
        guard let pid else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success else { return nil }

        let element = focusedElement as! AXUIElement

        // Try to get selected text first
        var selectedText: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
           let text = selectedText as? String, !text.isEmpty {
            return text
        }

        // Fall back to value (full text field content), truncated for context
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String {
            if text.count > 200 {
                return String(text.suffix(200))
            }
            return text
        }

        return nil
    }
}
