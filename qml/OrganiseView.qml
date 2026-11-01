pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as T

Item {
    id: root
    required property var controller
    required property string workspace
    property string notice: ""
    property string search: ""
    property int filter: 0
    property int sort: 0
    property string category: "*"
    property bool selecting: false
    property string selectionAnchor: ""
    property var contextIds: []
    property string contextId: ""
    readonly property var visibleNotes: notes.filter(n => category === "*" || n.collection === category)
    property string categoryTarget: ""
    property bool removingCategory: false
    property bool categoryBusy: false
    property string categoryError: ""
    property string editTarget: ""
    property bool creatingNote: false
    property bool syncing: false
    readonly property var categories: controller.categories.filter(n => n.workspace === workspace)
    readonly property var groups: [{name: "unfiled", value: ""}].concat(categories.map(n => ({name: n.name, value: n.name})))
    readonly property var notes: controller.noteRows.filter(n => n.workspace === workspace && !n.deleted && (filter === 0 || (filter === 1 ? n.errors > 0 || n.pending > 0 : !n.preview.trim()))).sort((a, b) => sort === 1 ? a.title.localeCompare(b.title) : sort === 2 ? a.created - b.created : b.updated - a.updated)
    signal workspaceChosen(string id)
    signal backRequested()
    signal moveRequested(var ids)
    signal createCategoryRequested()

    function groupNotes(category) { return notes.filter(n => n.collection === category) }
    function focusSearch() { searchBox.forceActiveFocus() }
    function findInEditor() { if (editDrawer.visible) editBody.focusSearch(); else focusSearch() }
    function focusedEditor() { return editTitle.activeFocus ? editTitle : editBody.focusedEditor() }
    function activateNote(id, modifiers) {
        if (!selecting && !(modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) {
            controller.clearNoteSelection(); edit(id); return
        }
        selecting = true
        let ids = controller.selectedNoteIds.slice()
        let anchor = visibleNotes.findIndex(n => n.id === selectionAnchor)
        let index = visibleNotes.findIndex(n => n.id === id)
        if (modifiers & Qt.ShiftModifier && anchor >= 0) {
            ids = visibleNotes.slice(Math.min(anchor, index), Math.max(anchor, index) + 1).map(n => n.id)
        } else {
            let existing = ids.indexOf(id)
            if (existing >= 0) ids.splice(existing, 1); else ids.push(id)
            selectionAnchor = id
        }
        controller.selectNotes(ids)
    }
    function edit(id) {
        editTarget = id
        controller.selectNote(id)
        if (controller.selectedId === id) { syncEditor(); editDrawer.open() }
    }
    function newNote(category) { creatingNote = true; editTarget = controller.selectedId; controller.newNote(category, workspace) }
    function syncEditor() {
        syncing = true
        if (editTitle.text !== controller.title) {
            editTitle.text = controller.title
            if (!editTitle.activeFocus) editTitle.cursorPosition = 0
        }
        editBody.loadDocument(controller.selectedId, controller.body)
        syncing = false
    }
    function changeCategory(remove) {
        removingCategory = remove; categoryBusy = false; categoryError = ""
        categoryName.text = categoryTarget
        categoryDialog.open()
        if (!remove) { categoryName.forceActiveFocus(); categoryName.selectAll() }
    }
    function reorder(direction) {
        let names = categories.map(n => n.name), index = names.indexOf(categoryTarget)
        let next = index + direction
        if (index < 0 || next < 0 || next >= names.length) return
        names.splice(index, 1); names.splice(next, 0, categoryTarget)
        controller.reorderCategories(workspace, names)
    }
    onWorkspaceChanged: { category = "*"; selecting = false; editDrawer.close(); creatingNote = false }
    onCategoryChanged: { controller.clearNoteSelection(); selectionAnchor = "" }
    onFilterChanged: controller.clearNoteSelection()
    onVisibleNotesChanged: {
        if (!visible) return
        let visibleIds = visibleNotes.map(n => n.id)
        let selected = controller.selectedNoteIds.filter(id => visibleIds.indexOf(id) >= 0)
        if (selected.length !== controller.selectedNoteIds.length) controller.selectNotes(selected)
    }
    onVisibleChanged: if (!visible) editDrawer.close()
    Connections {
        target: root.controller
        function onDocumentChanged() {
            if (root.creatingNote && root.controller.selectedId !== root.editTarget) {
                root.creatingNote = false; root.editTarget = root.controller.selectedId
            }
            if (root.editTarget && root.controller.selectedId === root.editTarget) {
                root.syncEditor()
                if (root.visible && !editDrawer.visible) editDrawer.open()
            }
        }
        function onCategoryChanged() { root.categoryBusy = false; categoryDialog.close(); if (root.category !== "*" && !root.groups.some(n => n.value === root.category)) root.category = "*" }
        function onErrorChanged() {
            root.creatingNote = false
            if (categoryDialog.visible) { root.categoryBusy = false; root.categoryError = root.controller.error }
        }
    }
    Timer { id: searchDelay; interval: 180; onTriggered: root.search = searchBox.text }
    Keys.onPressed: event => {
        if (event.matches(StandardKey.SelectAll)) { root.selecting = true; root.controller.selectNotes(root.visibleNotes.map(n => n.id)); event.accepted = true }
        else if (event.key === Qt.Key_Escape) { root.selecting = false; root.controller.clearNoteSelection(); event.accepted = true }
    }
    ColumnLayout {
        anchors.fill: parent; anchors.topMargin: 16; spacing: 0
        RowLayout {
            Layout.leftMargin: 24; Layout.rightMargin: 24
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 24
            ColumnLayout {
                Layout.preferredWidth: 232; Layout.minimumWidth: 232; Layout.maximumWidth: 232; Layout.fillHeight: true; spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "categories"; font.family: T.sans; font.pixelSize: 13; color: T.p.muted }
                    Item { Layout.fillWidth: true }
                    ActionButton { text: "+"; quiet: true; implicitHeight: 22; Accessible.name: "New category"; onClicked: root.createCategoryRequested() }
                }
                ListView {
                    id: categoryRail
                    PixelScroll { viewport: categoryRail }
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 0
                    model: [{name: "all notes", value: "*"}].concat(root.groups)
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: FieldScrollBar { }
                    delegate: ItemDelegate {
                        id: destination
                        required property var modelData
                        readonly property bool current: root.category === modelData.value
                        readonly property bool inverted: current || visualFocus || drop.containsDrag
                        width: categoryRail.width; height: 28; leftPadding: 10; rightPadding: 4; topPadding: 0; bottomPadding: 0; hoverEnabled: true
                        Accessible.name: modelData.name + ", category"; Accessible.selected: root.category === modelData.value
                        onClicked: root.category = modelData.value
                        background: Rectangle { color: drop.containsDrag || destination.visualFocus ? T.p.accent : destination.current ? T.p.ink : destination.hovered ? T.p.cell : "transparent" }
                        contentItem: RowLayout {
                            spacing: 8
                            Text { text: destination.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; color: destination.inverted ? T.p.floodInk : T.p.ink; font.family: T.sans; font.pixelSize: 13 }
                            Text { text: destination.modelData.value === "*" ? root.notes.length : root.groupNotes(destination.modelData.value).length; color: destination.inverted ? T.alpha(T.p.floodInk, .6) : T.p.muted; font.family: T.mono; font.pixelSize: T.small }
                            ActionButton {
                                id: categoryActions
                                visible: destination.modelData.value !== "*" && destination.modelData.value !== ""
                                text: "…"; implicitWidth: 24; implicitHeight: 22; leftPadding: 2; rightPadding: 2; quiet: true; onBand: destination.inverted
                                Accessible.name: "Manage category: " + destination.modelData.name
                                onClicked: { root.categoryTarget = destination.modelData.value; categoryMenu.popup(categoryActions, 0, height) }
                            }
                        }
                        DropArea {
                            id: drop
                            anchors.fill: parent; keys: ["organise-notes"]; enabled: destination.modelData.value !== "*"
                            onEntered: drag => drag.accepted = drag.source === dragGhost && !root.controller.moving
                            onDropped: event => {
                                if (event.source === dragGhost && !root.controller.moving) {
                                    root.controller.moveNotes(dragGhost.ids, root.workspace, destination.modelData.value)
                                    event.accept(Qt.MoveAction)
                                }
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    FieldText {
                        id: searchBox
                        Layout.fillWidth: true
                        placeholderText: "search"; Accessible.name: "Search organised notes"
                        onTextChanged: { root.controller.clearNoteSelection(); searchDelay.restart() }
                    }
                    ActionButton {
                        id: viewButton
                        text: (root.filter === 1 ? "Needs attention" : root.filter === 2 ? "Empty" : "All") + " ⌄"; quiet: true
                        Accessible.name: "Sort and filter notes"
                        onClicked: viewMenu.popup(viewButton, 0, height)
                        FieldMenu {
                            id: viewMenu
                            FieldMenuItem { text: "All notes"; checkable: true; checked: root.filter === 0; onTriggered: root.filter = 0 }
                            FieldMenuItem { text: "Needs attention"; checkable: true; checked: root.filter === 1; onTriggered: root.filter = 1 }
                            FieldMenuItem { text: "Empty notes"; checkable: true; checked: root.filter === 2; onTriggered: root.filter = 2 }
                            FieldMenuGap { }
                            FieldMenuItem { text: "Recently edited"; checkable: true; checked: root.sort === 0; onTriggered: root.sort = 0 }
                            FieldMenuItem { text: "Title A–Z"; checkable: true; checked: root.sort === 1; onTriggered: root.sort = 1 }
                            FieldMenuItem { text: "Oldest first"; checkable: true; checked: root.sort === 2; onTriggered: root.sort = 2 }
                        }
                    }
                    ActionButton { text: root.selecting ? "Done" : "Select"; quiet: !root.selecting; highlighted: root.selecting; Accessible.name: root.selecting ? "Finish selecting notes" : "Select multiple notes"; onClicked: { root.selecting = !root.selecting; root.controller.clearNoteSelection() } }
                }
                RowLayout {
                    visible: root.selecting; Layout.fillWidth: true; spacing: 2
                    Text { text: root.controller.selectedNoteIds.length + " selected"; Layout.fillWidth: true; color: T.p.ink; font.family: T.mono; font.pixelSize: T.value }
                    ActionButton { text: "All"; quiet: true; Accessible.name: "Select all visible notes"; onClicked: root.controller.selectNotes(root.visibleNotes.map(n => n.id)) }
                    ActionButton { text: "Clear"; quiet: true; enabled: root.controller.selectedNoteIds.length > 0; onClicked: root.controller.clearNoteSelection() }
                    ActionButton { text: "Move"; enabled: root.controller.connected && root.controller.selectedNoteIds.length > 0 && !root.controller.moving; onClicked: root.moveRequested(root.controller.selectedNoteIds) }
                }
                ListView {
                    id: files
                    PixelScroll { viewport: files }
                    objectName: "organisedNotes"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    model: root.visibleNotes; boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: FieldScrollBar { }
                    delegate: ItemDelegate {
                        id: file
                        required property var modelData
                        required property int index
                        objectName: "organise-note-" + modelData.id
                        readonly property bool selected: root.controller.selectedNoteIds.indexOf(modelData.id) >= 0
                        readonly property bool inverted: selected || visualFocus
                        readonly property var noteState: T.noteState(modelData)
                        width: files.width; height: 56; leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8; hoverEnabled: true
                        Accessible.role: Accessible.ListItem; Accessible.name: modelData.title; Accessible.selected: selected
                        background: Rectangle { color: file.visualFocus ? T.p.accent : file.selected ? T.p.ink : file.hovered ? T.p.cell : file.index % 2 ? T.p.panel : "transparent" }
                        onClicked: root.activateNote(modelData.id, Qt.NoModifier)
                        Keys.onReturnPressed: root.edit(modelData.id)
                        Keys.onSpacePressed: root.activateNote(modelData.id, Qt.ControlModifier)
                        MouseArea {
                            anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                file.forceActiveFocus()
                                if (mouse.button === Qt.RightButton) { root.contextIds = file.selected ? root.controller.selectedNoteIds.slice() : [file.modelData.id]; root.contextId = file.modelData.id; fileMenu.popup(file, mouse.x, mouse.y) }
                                else root.activateNote(file.modelData.id, mouse.modifiers)
                            }
                        }
                        DragHandler {
                            id: drag
                            target: null; acceptedButtons: Qt.LeftButton; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            enabled: root.controller.connected && !root.controller.moving
                            function positionGhost() { let p = file.mapToItem(dragGhost.parent, centroid.position.x, centroid.position.y); dragGhost.x = p.x - 90; dragGhost.y = p.y - 18 }
                            onCentroidChanged: if (active) positionGhost()
                            onActiveChanged: {
                                if (active) { dragGhost.ids = file.selected ? root.controller.selectedNoteIds.slice() : [file.modelData.id]; positionGhost(); dragGhost.dragging = true }
                                else { if (dragGhost.dragging) dragGhost.Drag.drop(); dragGhost.dragging = false }
                            }
                            onCanceled: { dragGhost.Drag.cancel(); dragGhost.dragging = false }
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            FieldCheck {
                                id: check
                                objectName: "noteSelection"
                                visible: root.selecting; checked: file.selected
                                Layout.preferredWidth: 12; Layout.preferredHeight: 24
                                Accessible.name: "Select note: " + file.modelData.title
                                onCheckedChanged: if (checked !== file.selected) root.activateNote(file.modelData.id, Qt.ControlModifier)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Text { Layout.fillWidth: true; text: file.modelData.title; color: file.inverted ? T.p.floodInk : T.p.ink; font.family: T.sans; font.pixelSize: 14; elide: Text.ElideRight }
                                Text { Layout.fillWidth: true; text: file.modelData.preview.replace(/\[\d+:\d+:\d+\]\s*/g, "").replace(/\s+/g, " ").trim() || "empty"; color: file.inverted ? T.alpha(T.p.floodInk, .6) : T.p.muted; font.family: T.sans; font.pixelSize: 12; elide: Text.ElideRight }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: Math.min(150, files.width * 0.28); spacing: 4
                                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: file.modelData.collection || "unfiled"; color: file.inverted ? T.p.floodInk : T.p.ink; font.family: T.mono; font.pixelSize: T.small; elide: Text.ElideRight }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Item { Layout.fillWidth: true }
                                    Rectangle { visible: !!file.noteState.text; Layout.preferredWidth: 6; Layout.preferredHeight: 6; color: file.noteState.color }
                                    Text { text: file.noteState.text || T.date(file.modelData.updated); color: file.inverted ? T.alpha(T.p.floodInk, .6) : T.p.muted; font.family: T.mono; font.pixelSize: T.small }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent; width: parent.width - 32; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        visible: files.count === 0
                        text: root.search || root.filter ? "no matches" : "no notes"
                        font.family: T.mono; font.pixelSize: T.value; color: T.p.dim
                    }
                }
            }
        }
        // A footer bar in the panel tone, so the list scrolls under a tone step.
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 44; color: T.p.panel
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 8
            Rectangle { visible: !!root.controller.error || !!root.notice; Layout.preferredWidth: 6; Layout.preferredHeight: 6; color: root.controller.error ? T.p.magenta : T.p.ink }
            Text { visible: !root.controller.error && !root.notice; text: "notes"; color: T.p.muted; font.family: T.sans; font.pixelSize: 12 }
            Text { Layout.fillWidth: true; text: T.lower(root.controller.error || root.notice) || root.visibleNotes.length; color: root.controller.error ? T.p.ink : T.p.muted; font.family: T.mono; font.pixelSize: T.value; elide: Text.ElideRight }
            ActionButton { visible: !!root.controller.error; text: "Dismiss"; quiet: true; implicitHeight: 22; onClicked: root.controller.dismissError() }
            ActionButton { text: "New note"; keys: "⌘N"; enabled: root.controller.connected; onClicked: root.newNote(root.category === "*" ? "" : root.category) }
        }
        }
    }
    FieldMenu {
        id: fileMenu
        FieldMenuItem { text: "Open note"; onTriggered: root.edit(root.contextId) }
        FieldMenuItem { text: "Move to category…"; enabled: !root.controller.moving; onTriggered: root.moveRequested(root.contextIds) }
    }
    Rectangle {
        id: dragGhost
        parent: Overlay.overlay
        property var ids: []
        property bool dragging: false
        visible: dragging; width: 180; height: 38; z: 100
        color: T.p.ink
        Drag.active: dragging; Drag.source: dragGhost; Drag.keys: ["organise-notes"]; Drag.supportedActions: Qt.MoveAction
        Drag.hotSpot.x: 90; Drag.hotSpot.y: 18
        Text { anchors.centerIn: parent; text: dragGhost.ids.length + (dragGhost.ids.length === 1 ? " note" : " notes"); color: T.p.floodInk; font.family: T.mono; font.pixelSize: T.value }
    }
    FieldMenu {
        id: categoryMenu
        FieldMenuItem { text: "Rename category…"; onTriggered: root.changeCategory(false) }
        FieldMenuItem { text: "Move category up"; enabled: root.categories.findIndex(n => n.name === root.categoryTarget) > 0; onTriggered: root.reorder(-1) }
        FieldMenuItem { text: "Move category down"; enabled: root.categories.findIndex(n => n.name === root.categoryTarget) < root.categories.length - 1; onTriggered: root.reorder(1) }
        FieldMenuItem { text: "Remove category…"; onTriggered: root.changeCategory(true) }
    }
    FieldDialog {
        id: categoryDialog
        anchors.centerIn: parent; width: 390
        title: root.removingCategory ? "Remove category?" : "Rename category"
        closePolicy: root.categoryBusy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        contentItem: ColumnLayout {
            spacing: 12
            Text { Layout.fillWidth: true; visible: root.removingCategory; text: "“" + root.categoryTarget + "” becomes unfiled. No notes are deleted."; wrapMode: Text.WordWrap; color: T.p.ink; font.family: T.sans; font.pixelSize: T.label }
            FieldText {
                id: categoryName
                Layout.fillWidth: true; visible: !root.removingCategory; enabled: !root.categoryBusy
                Accessible.name: "Category name"
            }
            Text { Layout.fillWidth: true; visible: !!root.categoryError; text: T.lower(root.categoryError); wrapMode: Text.WordWrap; color: T.p.magenta; font.family: T.mono; font.pixelSize: T.value }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ActionButton { text: "Cancel"; quiet: true; enabled: !root.categoryBusy; onClicked: categoryDialog.close() }
                ActionButton {
                    text: root.categoryBusy ? "Saving" : root.removingCategory ? "Remove" : "Save"
                    enabled: root.controller.connected && !root.categoryBusy && (root.removingCategory || !!categoryName.text.trim())
                    onClicked: { root.categoryBusy = true; root.categoryError = ""; if (root.removingCategory) root.controller.removeCategory(root.workspace, root.categoryTarget); else root.controller.renameCategory(root.workspace, root.categoryTarget, categoryName.text) }
                }
            }
        }
    }
    Drawer {
        id: editDrawer
        edge: Qt.RightEdge; width: Math.min(520, root.width - 48); height: root.height
        modal: true; leftPadding: 24; rightPadding: 20; topPadding: 16; bottomPadding: 16
        onOpened: if (!root.controller.body && root.controller.editable) editBody.focusEditor()
        onClosed: { root.editTarget = ""; root.creatingNote = false }
        background: Rectangle { color: T.p.panel }
        Overlay.modal: Rectangle { color: T.alpha(T.p.ground, .6) }
        contentItem: ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: editTitle
                    Layout.fillWidth: true; implicitHeight: 34; font.family: T.sans; font.pixelSize: 22; color: activeFocus ? T.p.ink : "transparent"; selectByMouse: true; padding: 0
                    selectionColor: T.alpha(T.p.accent, .38); selectedTextColor: T.p.ink
                    Accessible.name: "Organise note title"; readOnly: root.controller.trashed
                    onTextEdited: if (!root.syncing) root.controller.updateTitle(text)
                    background: Item { }
                    Text { anchors.fill: parent; visible: !editTitle.activeFocus; text: editTitle.text; font: editTitle.font; color: T.p.ink; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                    TextContextMenu { field: editTitle }
                }
                ActionButton { text: "Done"; keys: "esc"; quiet: true; onClicked: editDrawer.close() }
            }
            RowLayout {
            Layout.fillWidth: true; spacing: 12
            Text { text: "category"; font.family: T.sans; font.pixelSize: 13; color: T.p.ink }
            FieldCombo {
                Layout.fillWidth: true; model: root.groups; textRole: "name"
                Accessible.name: "Organise note category"; enabled: !root.controller.trashed
                currentIndex: Math.max(0, root.groups.findIndex(n => n.value === root.controller.collection))
                onActivated: root.controller.updateCollection(model[currentIndex].value)
            }
            }
            NoteEditor {
                id: editBody
                Layout.fillWidth: true; Layout.fillHeight: true
                readOnly: !root.controller.editable; accessibleName: "Organise note editor"
                footerColour: T.p.cell; leftInset: 10; rightInset: 10
                placeholderText: root.controller.editable ? "" : "transcribing"
                onEdited: value => { if (editDrawer.visible) root.controller.updateBody(value) }
                statusText: root.controller.error ? "" : root.controller.saving ? "saving" : root.controller.editable ? "saved" : "transcribing"
                statusColour: !root.controller.error && !root.controller.saving && !root.controller.editable ? T.p.amber : "transparent"
            }
            Text { Layout.fillWidth: true; visible: !!root.controller.error; text: T.lower(root.controller.error); color: T.p.magenta; font.family: T.mono; font.pixelSize: T.value; wrapMode: Text.WordWrap }
            RowLayout {
                Layout.fillWidth: true; spacing: 2
                ActionButton { text: "Copy transcript"; enabled: !!root.controller.body; onClicked: root.controller.copy() }
                ActionButton { text: "Retry audio"; visible: root.controller.failed > 0; onClicked: root.controller.retry() }
                Item { Layout.fillWidth: true }
                ActionButton { text: "Move to trash"; quiet: true; enabled: root.controller.editable; onClicked: { root.controller.deleteNote(); editDrawer.close() } }
            }
        }
    }
}
