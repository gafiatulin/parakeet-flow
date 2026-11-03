import ApplicationServices
import Testing
@testable import ParakeetFlow

@Suite("TextInserter")
struct TextInserterTests {
    @Test func acceptsEditableTextRoles() {
        #expect(TextInserter.isEditableRole(kAXTextFieldRole as String))
        #expect(TextInserter.isEditableRole(kAXTextAreaRole as String))
        #expect(TextInserter.isEditableRole(kAXComboBoxRole as String))
        #expect(TextInserter.isEditableRole("AXSearchField"))
    }

    @Test func rejectsFinderAndNonTextRoles() {
        #expect(!TextInserter.isEditableRole(kAXRowRole as String))
        #expect(!TextInserter.isEditableRole(kAXCellRole as String))
        #expect(!TextInserter.isEditableRole(kAXImageRole as String))
        #expect(!TextInserter.isEditableRole(kAXButtonRole as String))
        #expect(!TextInserter.isEditableRole(kAXMenuItemRole as String))
    }

    @Test func classifiesEditableRoles() {
        #expect(TextInserter.focusKind(
            role: kAXTextAreaRole as String,
            valueSettable: false,
            hasSelectedTextRange: false
        ) == .editable)
        #expect(TextInserter.focusKind(
            role: kAXTextFieldRole as String,
            valueSettable: true,
            hasSelectedTextRange: true
        ) == .editable)
    }

    @Test func classifiesNonTextTargets() {
        #expect(TextInserter.focusKind(
            role: kAXRowRole as String,
            valueSettable: true,
            hasSelectedTextRange: true
        ) == .notEditable)
        #expect(TextInserter.focusKind(
            role: kAXImageRole as String,
            valueSettable: false,
            hasSelectedTextRange: false
        ) == .notEditable)
    }

    @Test func treatsUnknownTargetsAsInconclusive() {
        // Electron/Chromium apps (VS Code, Slack, Chrome) usually expose no
        // usable focused element, so the insertion must not be dropped.
        #expect(TextInserter.focusKind(
            role: nil,
            valueSettable: false,
            hasSelectedTextRange: false
        ) == .unknown)
        #expect(TextInserter.effectiveFocusKind(.unknown, bundleID: "com.microsoft.VSCode") == .unknown)
        #expect(TextInserter.focusKind(
            role: "AXWebArea",
            valueSettable: false,
            hasSelectedTextRange: false
        ) == .unknown)
        #expect(TextInserter.focusKind(
            role: nil,
            valueSettable: true,
            hasSelectedTextRange: true
        ) == .editable)
    }

    @Test func blocksInconclusiveFocusInFileManagers() {
        // A Finder desktop or icon view exposes no focused text element, and a
        // Cmd+V there duplicates files instead of typing the transcript.
        #expect(TextInserter.effectiveFocusKind(.unknown, bundleID: "com.apple.finder") == .notEditable)
        #expect(TextInserter.effectiveFocusKind(.unknown, bundleID: "com.binarynights.ForkLift") == .notEditable)

        // A real text control (search field, rename sheet) still counts.
        #expect(TextInserter.effectiveFocusKind(.editable, bundleID: "com.apple.finder") == .editable)

        // Known non-text roles stay blocked in any app.
        #expect(TextInserter.effectiveFocusKind(.notEditable, bundleID: "com.microsoft.VSCode") == .notEditable)
    }
}
