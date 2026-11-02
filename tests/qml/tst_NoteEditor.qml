import QtQuick
import QtTest
import "../../qml"

Item {
    width: 500; height: 600
    NoteEditor { id: note; anchors.fill: parent }
    SignalSpy { id: edits; target: note; signalName: "edited" }
    TestCase {
        name: "NoteEditor"
        when: windowShown
        function init() {
            note.readOnly = false
            note.loadDocument("initial-" + name, "")
            note.preview = false
            edits.clear()
        }
        function test_formattingIsOneUndoStepAndKeepsSelection() {
            note.loadDocument("bold", "A thought to keep")
            note.editor.select(2, 9)
            note.wrap("**", "**", "bold text")
            compare(note.text, "A **thought** to keep")
            compare(note.editor.selectedText, "thought")
            verify(edits.count > 0)
            note.editor.undo()
            compare(note.text, "A thought to keep")
            note.editor.redo()
            compare(note.text, "A **thought** to keep")
        }
        function test_previewPreservesSourceCursorAndUndo() {
            const markdown = "## Session\n\n**Keep** _this_ source.\n\n- [ ] Follow up\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```cpp\na < b;\n```\n"
            note.loadDocument("preview", markdown)
            note.editor.insert(note.editor.length, "Last line")
            note.editor.select(3, 10)
            const cursor = note.editor.cursorPosition
            const original = note.text
            edits.clear()
            note.togglePreview()
            compare(note.preview, true)
            const viewer = findChild(note, "markdownPreview")
            verify(viewer !== null)
            compare(viewer.readOnly, true)
            tryVerify(function() { return viewer.getText(0, viewer.length).indexOf("Session") >= 0 })
            verify(viewer.getText(0, viewer.length).indexOf("**Keep**") < 0)
            note.togglePreview()
            compare(note.text, original)
            compare(note.editor.cursorPosition, cursor)
            compare(edits.count, 0)
            note.editor.undo()
            compare(note.text, markdown)
        }
        function test_switchingNotesDoesNotSaveOrCarryUndo() {
            note.loadDocument("one", "Same body")
            note.editor.insert(0, "Changed ")
            edits.clear()
            note.loadDocument("two", "Changed Same body")
            compare(edits.count, 0)
            verify(!note.editor.canUndo)
            note.editor.undo()
            compare(note.text, "Changed Same body")
            note.editor.selectAll()
            note.editor.cursorSelection.text = ""
            verify(note.editor.canUndo)
            note.loadDocument("three", "")
            verify(!note.editor.canUndo)
        }
        function test_multiLineListAndLinkInsertion() {
            note.loadDocument("list", "one\ntwo\nthree")
            note.editor.select(0, 8)
            note.prefixLines("- ")
            compare(note.text, "- one\n- two\nthree")
            note.prefixLines("- ")
            compare(note.text, "one\ntwo\nthree")
            note.editor.select(0, 3)
            note.insertLink()
            compare(note.text, "[one](https://)\ntwo\nthree")
            compare(note.editor.selectedText, "https://")
        }
        function test_trackpadPixelScrollingFollowsGesture() {
            note.loadDocument("scroll", Array(200).fill("A line of text to scroll through.").join("\n"))
            note.focusEditor()
            const view = findChild(note, "noteScroll")
            tryVerify(function() { return view.contentHeight > view.height * 2 })
            wait(50) // Let document layout and initial scroll positioning settle.
            view.contentY = 0
            trackpad.pixelScroll(view, 0, Qt.ScrollBegin)
            for (let i = 0; i < 12; ++i) trackpad.pixelScroll(view, -10, Qt.ScrollUpdate)
            trackpad.pixelScroll(view, 0, Qt.ScrollEnd)
            tryCompare(view, "contentY", 120, 200)
            wait(100)
            compare(view.contentY, 120)
            note.togglePreview()
            const preview = findChild(note, "previewScroll")
            tryVerify(function() { return preview.contentHeight > preview.height * 2 })
            trackpad.pixelScroll(preview, -75, Qt.ScrollUpdate)
            compare(preview.contentY, 75)
            trackpad.pixelScroll(preview, 200, Qt.ScrollUpdate)
            compare(preview.contentY, 0)
            mouseWheel(preview, preview.width / 2, preview.height / 2, 0, -120)
            tryVerify(function() { return preview.contentY > 0 })
        }
        function test_readOnlyAndPreviewRejectFormatting() {
            note.loadDocument("readonly", "Original")
            note.editor.selectAll()
            note.readOnly = true
            note.wrap("**", "**", "bold text")
            note.prefixLines("- ")
            note.insertLink()
            compare(note.text, "Original")
            compare(edits.count, 0)
            note.readOnly = false; note.preview = true
            note.wrap("*", "*", "italic text")
            compare(note.text, "Original")
        }
    }
}
