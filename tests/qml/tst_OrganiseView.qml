import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml"

Item {
    width: 800; height: 600; visible: true
    QtObject {
        id: backend
        property var workspaces: [{id: "inbox", name: "Personal"}]
        property var categories: [{workspace: "inbox", name: "Research"}]
        property var noteRows: [
            {id: "a", workspace: "inbox", collection: "", title: "Alpha", preview: "First", updated: 3, created: 1},
            {id: "b", workspace: "inbox", collection: "Research", title: "Beta", preview: "Second", updated: 2, created: 2},
            {id: "c", workspace: "inbox", collection: "", title: "Gamma", preview: "Third", updated: 1, created: 3}
        ]
        property var selectedNoteIds: []
        property string selectedId: ""
        property string title: "Title"
        property string body: "A note"
        property string collection: ""
        property string error: ""
        property bool connected: true
        property bool moving: false
        property bool editable: true
        property bool trashed: false
        property bool saving: false
        property bool recording: false
        property bool stopping: false
        property int failed: 0
        signal documentChanged()
        signal categoryChanged()
        function clearNoteSelection() { selectedNoteIds = [] }
        function selectNotes(ids) { selectedNoteIds = ids }
        function selectNote(id) { selectedId = id; documentChanged() }
    }
    OrganiseView { id: organiser; anchors.fill: parent; controller: backend; workspace: "inbox" }
    TestCase {
        name: "OrganiseInteraction"
        when: windowShown
        function init() {
            organiser.visible = false
            wait(250)
            organiser.category = "*"; organiser.sort = 0; organiser.selecting = false
            organiser.selectionAnchor = ""; backend.clearNoteSelection(); backend.selectedId = ""
            organiser.visible = true
        }
        function test_plainClickOpensNote() {
            const row = findChild(organiser, "organise-note-a")
            verify(row !== null)
            mouseClick(row, row.width / 2, row.height / 2)
            compare(backend.selectedId, "a")
            compare(backend.selectedNoteIds.length, 0)
            compare(organiser.selecting, false)
        }
        function test_selectionAndRangeFollowVisibleOrder() {
            organiser.sort = 2
            organiser.activateNote("a", Qt.ControlModifier)
            organiser.activateNote("c", Qt.ShiftModifier)
            compare(backend.selectedNoteIds.join(","), "a,b,c")
            compare(backend.selectedId, "")
            organiser.category = "Research"
            compare(backend.selectedNoteIds.length, 0)
            organiser.activateNote("b", Qt.ControlModifier)
            compare(backend.selectedNoteIds.join(","), "b")
        }
        function test_checkboxChangesSelection() {
            organiser.selecting = true
            const row = findChild(organiser, "organise-note-a")
            const checkbox = findChild(row, "noteSelection")
            verify(checkbox !== null)
            checkbox.toggle() // Same state transition used by accessibility activation.
            compare(backend.selectedNoteIds.join(","), "a")
            checkbox.toggle()
            compare(backend.selectedNoteIds.length, 0)
        }
        function test_listKeepsScrollWhenNotesRefresh() {
            const saved = backend.noteRows
            const many = []
            for (let i = 0; i < 40; i++) many.push({id: "n" + i, workspace: "inbox", collection: "", title: "Note " + i, preview: "", updated: 100 - i, created: i})
            backend.noteRows = many
            const list = findChild(organiser, "organisedNotes")
            list.contentY = list.originY + 300
            // A save or transcription refreshes the rows: the list stays where it was.
            backend.noteRows = many.map(n => Object.assign({}, n, n.id === "n3" ? {preview: "edited"} : {}))
            compare(list.contentY - list.originY, 300)
            // Changing what the list shows starts it at the top.
            organiser.sort = 1
            compare(list.contentY - list.originY, 0)
            backend.noteRows = saved
        }
    }
}
