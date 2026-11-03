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
}
