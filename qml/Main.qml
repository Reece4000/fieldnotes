pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import "Theme.js" as T

ApplicationWindow {
    id: window
    width: Qt.application.arguments.indexOf("--compact") >= 0 ? 800 : 1280
    height: Qt.application.arguments.indexOf("--compact") >= 0 ? 620 : 900
    minimumWidth: 760; minimumHeight: 580
    visible: true; title: "Fieldnotes"; color: T.ground
    flags: Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint
    // The ground extends through the native title bar; ApplicationWindow keeps
    // interactive content inside the system-reported safe area.
    background: Rectangle { color: T.ground }
    font.family: T.sans
    palette.window: T.ground; palette.windowText: T.ink; palette.base: T.cell; palette.alternateBase: T.panel
    palette.button: T.cell; palette.buttonText: T.ink; palette.text: T.ink; palette.brightText: T.ink
    palette.placeholderText: T.muted; palette.highlight: T.accent; palette.highlightedText: T.floodInk
    palette.toolTipBase: T.cell; palette.toolTipText: T.ink; palette.dark: T.cell; palette.mid: T.dim; palette.light: T.cell; palette.shadow: T.ground
    FontLoader { source: "../assets/fonts/Geist-Regular.ttf" }
    FontLoader { source: "../assets/fonts/Geist-Medium.ttf" }
    FontLoader { source: "../assets/fonts/GeistMono-Regular.ttf" }
    FontLoader { source: "../assets/fonts/DSEG14Modern-Regular.ttf" }
    // qmllint disable unqualified
    property var c: appController
    // qmllint enable unqualified
    property string chosenWorkspace: preferences.lastWorkspace
    property string recordingWorkspace: chosenWorkspace
    property string recordingCategory: recordingWorkspace === chosenWorkspace ? currentCategory() : ""
    function chooseRecordingWorkspace(workspace) { recordingWorkspace = workspace; recordingCategory = "" }
    property string chosenCategory: "*"
    property bool trash: false
    property bool organising: false
    readonly property string section: organising ? "organise" : trash ? "trash" : "notes"
    function chooseSection(name) {
        if (name === "organise") { organising = true; return }
        organising = false
        if (trash !== (name === "trash")) { trash = name === "trash"; chosenCategory = "*" }
    }
    property int deviceId: -1
    property bool syncing: false
    property bool queryStarted: false
    property bool focusedWriting: false
    property bool focusNewNote: false
    function workspaceName(id) { let w = c.workspaces.find(n => n.id === id); return w ? w.name : "" }
    property string loadedId: ""
    property string notice: ""
    property bool undoVisible: false
    property string creationKind: "category"
    property bool creating: false
    property string creationError: ""
    property bool reducedMotion: preferences.reduceMotion || c.systemReduceMotion
    property var contextNote: ({})
    property var contextNoteIds: []
    property bool selectingNotes: false
    readonly property bool showNoteSelection: selectingNotes || c.selectedNoteIds.length > 1
    property string renameTarget: ""
    property string contextCategory: ""
    function canTrash(note) { return !!(note && note.id && !note.deleted && note.status !== "recording" && note.status !== "paused" && (note.pending || 0) <= (note.errors || 0)) }
    function openNoteMenu(note, item, x, y) {
        contextNote = note
        contextNoteIds = c.selectedNoteIds.indexOf(note.id) >= 0 ? c.selectedNoteIds.slice() : [note.id]
        sidebarNoteMenu.popup(item, x, y)
    }
    function chooseNote(id, modifiers) {
        if (trash) { c.selectNote(id); return }
        if (!selectingNotes && !c.selectedNoteIds.length && modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) c.selectNoteRow(c.selectedId)
        c.selectNoteRow(id, selectingNotes || !!(modifiers & Qt.ControlModifier), !!(modifiers & Qt.ShiftModifier))
    }
    function finishSelection() { selectingNotes = false; c.clearNoteSelection() }
    function openMove(ids, workspace) {
        moveDialog.noteIds = ids.slice()
        moveDialog.workspace = workspace
        moveDialog.errorText = ""
        moveCategory.currentIndex = 0
        moveDialog.open()
        moveCategory.forceActiveFocus()
    }
    function renameNote(id) {
        renameTarget = id
        if (c.selectedId === id) { titleField.forceActiveFocus(); titleField.selectAll(); renameTarget = "" }
        else c.selectNote(id)
    }
    property var categoryRows: [{name: "all notes", value: "*"}, {name: "unfiled", value: ""}].concat(
        c.categories.filter(n => n.workspace === chosenWorkspace).map(n => ({name: n.name, value: n.name, count: n.count})))
    property var noteCategories: [{name: "unfiled", value: ""}].concat(
        c.categories.filter(n => n.workspace === c.workspace).map(n => ({name: n.name, value: n.name})))
    Settings { id: preferences; location: window.c.settingsFile; property double voiceDb: -72; property bool reduceMotion: false; property string lastWorkspace: "inbox" }
    function refreshQuery() { finishSelection(); if (c.connected) c.query(chosenWorkspace, organising ? "*" : chosenCategory, organising ? organiser.search : searchField.text, organising ? false : trash, organising) }
    onOrganisingChanged: refreshQuery()
    function currentCategory() { return chosenCategory === "*" || trash ? "" : chosenCategory }
    function recordToggle() { if (c.connected) { if (c.recording) c.stop(); else c.record(deviceId, recordingCategory, recordingWorkspace, preferences.voiceDb) } }
    function newNote(category) {
        if (organising) organiser.newNote(category === undefined ? "" : category)
        else { focusedWriting = true; focusNewNote = true; c.newNote(category === undefined ? currentCategory() : category, chosenWorkspace) }
    }
    function focusedEditor() { return organising ? organiser.focusedEditor() : titleField.activeFocus ? titleField : noteEditor.focusedEditor() }
    function showNotice(text, undo) { notice = text; undoVisible = undo || false; noticeTimer.restart() }
    function create(kind) { creationKind = kind; creating = false; creationError = ""; creationName.text = ""; creationDialog.open(); creationName.forceActiveFocus() }
    function loadDocument() {
        syncing = true
        let changed = loadedId !== c.selectedId
        if (titleField.text !== c.title) {
            titleField.text = c.title
            if (!titleField.activeFocus) titleField.cursorPosition = 0
        }
        noteEditor.loadDocument(c.selectedId, c.body)
        loadedId = c.selectedId
        if (changed && focusNewNote) { focusNewNote = false; Qt.callLater(function() { noteEditor.focusEditor() }) }
        syncing = false
        if (renameTarget === c.selectedId) Qt.callLater(function() { titleField.forceActiveFocus(); titleField.selectAll(); renameTarget = "" })
    }
    onChosenWorkspaceChanged: { preferences.lastWorkspace = chosenWorkspace; chosenCategory = "*"; trash = false; refreshQuery() }
    onChosenCategoryChanged: refreshQuery()
    onTrashChanged: refreshQuery()
    Connections {
        target: window.c
        function onDocumentChanged() { window.loadDocument() }
        function onCopied() { copyButton.confirm() }
        function onExported() { window.showNotice("Note exported", false) }
        function onDeleted() { window.showNotice("Moved to Trash", true) }
        function onNotesMoved(count, collection) {
            moveDialog.close()
            window.finishSelection()
            window.showNotice(count + (count === 1 ? " note moved to " : " notes moved to ") + (collection || "Unfiled"), false)
        }
        function onWorkspaceCreated(id) { window.creating = false; creationDialog.close(); window.chosenWorkspace = id }
        function onCategoryCreated(name) { window.creating = false; creationDialog.close(); if (!window.organising) window.chosenCategory = name; window.trash = false; window.refreshQuery() }
        function onCategoryChanged(message) { window.showNotice(message, false) }
        function onErrorChanged() {
            if (window.creating && window.c.error) { window.creationError = window.c.error; window.creating = false }
            if (moveDialog.visible && window.c.error) moveDialog.errorText = window.c.error
        }
        function onStateChanged() {
            if (!window.c.connected) window.queryStarted = false
            if (window.c.connected && !window.queryStarted) { window.queryStarted = true; window.refreshQuery() }
            if (!window.loadedId && window.c.connected) window.loadDocument()
        }
    }
    Timer { id: noticeTimer; interval: 6500; onTriggered: window.notice = "" }
    Timer { id: searchTimer; interval: 180; onTriggered: window.refreshQuery() }
    Shortcut { sequence: "Meta+Shift+P"; enabled: window.c.recording; onActivated: window.c.pause() }
    Shortcut { sequence: "Meta+Shift+C"; enabled: !!window.c.body; onActivated: window.c.copy() }
    Shortcut { sequences: [StandardKey.Find]; onActivated: window.organising ? organiser.findInEditor() : noteEditor.focusSearch() }
    Shortcut { sequence: "Meta+Shift+F"; onActivated: window.organising ? organiser.focusSearch() : searchField.forceActiveFocus() }
    Shortcut { sequence: "Meta+E"; enabled: !!window.c.selectedId; onActivated: exportDialog.open() }
    Shortcut { sequence: "Meta+1"; onActivated: window.chooseSection("notes") }
    Shortcut { sequence: "Meta+2"; onActivated: window.chooseSection("organise") }
    Shortcut { sequence: "Meta+3"; onActivated: window.chooseSection("trash") }
    Shortcut { sequence: "Escape"; enabled: noteDragGhost.dragging; onActivated: { noteDragGhost.Drag.cancel(); noteDragGhost.dragging = false } }
    FieldMenu {
        id: sidebarNoteMenu
        FieldMenuItem { text: "Copy transcript"; enabled: window.contextNoteIds.length === 1; onTriggered: window.c.copyNote(window.contextNote.id) }
        FieldMenuItem { text: "Rename note"; enabled: window.contextNoteIds.length === 1 && !window.contextNote.deleted; onTriggered: window.renameNote(window.contextNote.id) }
        FieldMenuItem { text: "Retry unfinished audio"; enabled: window.contextNoteIds.length === 1 && (window.contextNote.errors || 0) > 0; onTriggered: window.c.retry(window.contextNote.id) }
        FieldMenuItem {
            text: window.contextNoteIds.length > 1 ? "Move " + window.contextNoteIds.length + " notes to category…" : "Move to category…"
            enabled: !window.contextNote.deleted && window.c.connected && !window.c.moving
            onTriggered: window.openMove(window.contextNoteIds, window.contextNote.workspace)
        }
        FieldMenuGap { }
        FieldMenuItem {
            text: window.contextNote.deleted ? "Restore note" : "Move note to Trash"
            enabled: window.contextNoteIds.length === 1 && (!!window.contextNote.deleted || window.canTrash(window.contextNote))
            onTriggered: window.contextNote.deleted ? window.c.restoreNote(window.contextNote.id) : window.c.trashNote(window.contextNote.id)
        }
    }
    FieldMenu {
        id: categoryMenu
        FieldMenuItem { text: "New note in this category"; onTriggered: window.newNote(window.contextCategory) }
        FieldMenuItem { text: "New category…"; onTriggered: window.create("category") }
    }
    FieldMenu {
        id: workspaceMenu
        FieldMenuItem { text: "New note"; onTriggered: window.newNote() }
        FieldMenuItem { text: "New category…"; onTriggered: window.create("category") }
        FieldMenuItem { text: "New workspace…"; onTriggered: window.create("workspace") }
    }
    Rectangle {
        id: noteDragGhost
        parent: Overlay.overlay
        property string noteId: ""
        property string noteTitle: ""
        property bool dragging: false
        visible: dragging; width: 210; height: 38; z: 100
        color: T.ink
        Drag.active: dragging; Drag.source: noteDragGhost; Drag.keys: ["fieldnotes-note"]
        Drag.supportedActions: Qt.MoveAction; Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
        Text { anchors.fill: parent; anchors.margins: 10; text: noteDragGhost.noteTitle; color: T.floodInk; font.family: T.mono; font.pixelSize: T.value; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
    }
    FileDialog { id: exportDialog; title: "Export note"; fileMode: FileDialog.SaveFile; nameFilters: ["Markdown notes (*.md)", "Text files (*.txt)"]; defaultSuffix: "md"; onAccepted: window.c.exportNote(selectedFile) }
    FieldDialog {
        id: moveDialog
        property var noteIds: []
        property string workspace: ""
        property string errorText: ""
        anchors.centerIn: parent; width: 360
        title: noteIds.length === 1 ? "Move note to category" : "Move " + noteIds.length + " notes to category"
        closePolicy: window.c.moving ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text { text: "workspace"; color: T.ink; font.family: T.sans; font.pixelSize: T.label }
                Item { Layout.fillWidth: true }
                Text { text: window.workspaceName(moveDialog.workspace); color: T.muted; font.family: T.mono; font.pixelSize: T.value }
            }
            Text { text: "category"; color: T.ink; font.family: T.sans; font.pixelSize: T.label }
            FieldCombo {
                id: moveCategory
                Layout.fillWidth: true; textRole: "name"
                Accessible.name: "Destination category"
                enabled: !window.c.moving
                model: [{name: "unfiled", value: ""}].concat(window.c.categories.filter(n => n.workspace === moveDialog.workspace).map(n => ({name: n.name, value: n.name})))
            }
            Text { Layout.fillWidth: true; visible: !!moveDialog.errorText; text: T.lower(moveDialog.errorText); color: T.magenta; wrapMode: Text.WordWrap; font.family: T.mono; font.pixelSize: T.value }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                ActionButton { text: "Cancel"; quiet: true; enabled: !window.c.moving; onClicked: moveDialog.close() }
                ActionButton {
                    text: window.c.moving ? "Moving…" : "Move"
                    enabled: window.c.connected && !window.c.moving && moveCategory.currentIndex >= 0
                    onClicked: { moveDialog.errorText = ""; window.c.moveNotes(moveDialog.noteIds, moveDialog.workspace, moveCategory.model[moveCategory.currentIndex].value) }
                }
            }
        }
    }
    FieldDialog {
        id: creationDialog
        anchors.centerIn: parent
        width: 360; modal: true
        title: window.creationKind === "workspace" ? "New workspace" : "New category"
        function submit() {
            if (!creationName.text.trim() || window.creating) return
            window.creating = true; window.creationError = ""
            if (window.creationKind === "workspace") window.c.createWorkspace(creationName.text)
            else window.c.createCategory(window.chosenWorkspace, creationName.text)
        }
        contentItem: ColumnLayout {
            spacing: 8
            FieldText { id: creationName; Layout.fillWidth: true; placeholderText: "name"; Accessible.name: "Name"; enabled: !window.creating; onAccepted: creationDialog.submit() }
            Text { Layout.fillWidth: true; Layout.preferredHeight: 32; text: T.lower(window.creationError); color: T.magenta; wrapMode: Text.WordWrap; font.family: T.mono; font.pixelSize: T.small }
            RowLayout {
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; quiet: true; enabled: !window.creating; onClicked: creationDialog.close() }
            ActionButton { text: window.creating ? "Creating…" : "Create"; enabled: !!creationName.text.trim() && !window.creating && window.c.connected; onClicked: creationDialog.submit() }
            }
        }
    }
    FieldDialog {
        id: filterDialog
        anchors.centerIn: parent; width: 420; modal: true; title: "Voice filter"
        contentItem: ColumnLayout {
            spacing: 18
            FieldSlider {
                id: voiceSlider
                Layout.fillWidth: true
                label: "minimum level"; unit: "dBFS"
                from: -90; to: -20; stepSize: 1; value: preferences.voiceDb
                Accessible.name: "Minimum voice level"; onMoved: preferences.voiceDb = value
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: -12
                Text { text: "quiet"; font.family: T.mono; font.pixelSize: T.small; color: T.muted }
                Item { Layout.fillWidth: true }
                Text { text: "near"; font.family: T.mono; font.pixelSize: T.small; color: T.muted }
            }
            FieldCheck { id: motionCheck; text: "Reduce motion"; checked: preferences.reduceMotion; onToggled: preferences.reduceMotion = checked }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } ActionButton { text: "Close"; keys: "esc"; onClicked: filterDialog.close() } }
        }
    }
    menuBar: MenuBar {
        Menu {
            title: "File"
            Action { text: "New note"; shortcut: StandardKey.New; onTriggered: window.newNote() }
            Action { text: "New workspace…"; onTriggered: window.create("workspace") }
            Action { text: "New category…"; onTriggered: window.create("category") }
            MenuSeparator { }
            Action { text: window.c.recording ? "Stop recording" : "Record a session"; shortcut: "Meta+R"; onTriggered: window.recordToggle() }
            Action { text: window.c.paused ? "Resume recording" : "Pause recording"; enabled: window.c.recording; onTriggered: window.c.pause() }
            Action { text: "Voice filter…"; onTriggered: filterDialog.open() }
            MenuSeparator { }
            Action { text: "Export note…"; enabled: !!window.c.selectedId; onTriggered: exportDialog.open() }
            Action { text: "Quit Fieldnotes"; shortcut: StandardKey.Quit; onTriggered: window.close() }
        }
        Menu {
            title: "Edit"
            Action { text: "Undo edit"; shortcut: StandardKey.Undo; enabled: window.focusedEditor().canUndo; onTriggered: window.focusedEditor().undo() }
            Action { text: "Redo edit"; shortcut: StandardKey.Redo; enabled: window.focusedEditor().canRedo; onTriggered: window.focusedEditor().redo() }
            MenuSeparator { }
            Action { text: "Copy transcript"; enabled: !!window.c.body; onTriggered: window.c.copy() }
            Action { text: "Copy with timestamps"; enabled: !!window.c.body; onTriggered: window.c.copy(true) }
            Action { text: "Find notes"; onTriggered: window.organising ? organiser.focusSearch() : searchField.forceActiveFocus() }
        }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 0

        RowLayout {
            id: header
            Layout.fillWidth: true; Layout.preferredHeight: 52
            Layout.leftMargin: 24; Layout.rightMargin: 24
            spacing: 22
            Repeater {
                model: ["notes", "organise", "trash"]
                Text {
                    id: sectionTitle
                    required property string modelData
                    required property int index
                    readonly property bool current: window.section === modelData
                    readonly property bool dropping: modelData === "trash" && trashDrop.containsDrag
                    text: modelData
                    font.family: T.sans; font.pixelSize: T.section
                    color: dropping ? T.floodInk : current ? T.ink : sectionHover.hovered ? T.alpha(T.ink, .7) : T.dim
                    Accessible.role: Accessible.PageTab; Accessible.name: modelData; Accessible.selected: current
                    Rectangle { visible: sectionTitle.dropping; z: -1; anchors.fill: parent; anchors.margins: -4; color: T.accent }
                    HoverHandler { id: sectionHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: window.chooseSection(sectionTitle.modelData) }
                    DropArea {
                        id: trashDrop
                        anchors.fill: parent; anchors.margins: -8; enabled: sectionTitle.modelData === "trash"; keys: ["fieldnotes-note"]
                        onEntered: drag => { drag.accepted = drag.source === noteDragGhost && !!noteDragGhost.noteId }
                        onDropped: drop => {
                            if (drop.source === noteDragGhost && noteDragGhost.noteId) { window.c.trashNote(noteDragGhost.noteId); drop.accept(Qt.MoveAction) }
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Text { text: "workspace"; color: T.ink; font.family: T.sans; font.pixelSize: T.label }
            FieldCombo {
                id: workspacePicker
                Layout.preferredWidth: window.width < 1000 ? 150 : 200
                model: window.c.workspaces; textRole: "name"
                currentIndex: Math.max(0, window.c.workspaces.findIndex(n => n.id === window.chosenWorkspace))
                Accessible.name: "Workspace"
                onActivated: window.chosenWorkspace = model[currentIndex].id
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onPressed: mouse => workspaceMenu.popup(workspacePicker, mouse.x, mouse.y) }
            }
            ActionButton { text: "+"; quiet: true; Layout.leftMargin: -20; Accessible.name: "New workspace"; onClicked: window.create("workspace") }
            Row {
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8
                    color: window.c.engineStatus === "ready" ? T.ink : window.c.engineStatus === "error" ? T.magenta : T.amber
                }
                Text {
                    text: "phonon-2"; font.family: T.mono; font.pixelSize: T.value; color: T.muted
                    ToolTip.visible: engineHover.hovered && window.c.engineStatus === "error"; ToolTip.text: T.lower(window.c.engineError)
                    HoverHandler { id: engineHover }
                }
            }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent; spacing: 0; visible: !window.organising
                Rectangle {
                    Layout.preferredWidth: 280; Layout.fillHeight: true; color: T.panel
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: window.height < 700 ? 12 : 16; spacing: window.height < 700 ? 8 : 12
                        ActionButton { text: "New note"; keys: "⌘N"; Layout.fillWidth: true; enabled: window.c.connected; onClicked: window.newNote() }
                        FieldText {
                            id: searchField
                            Layout.fillWidth: true; placeholderText: "search"
                            Accessible.name: "Search notes"
                            onTextChanged: searchTimer.restart()
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: 4; visible: !window.trash
                            Text { text: "categories"; color: T.muted; font.family: T.sans; font.pixelSize: 13 }
                            Item { Layout.fillWidth: true }
                            ActionButton { text: "+"; quiet: true; implicitHeight: 22; Accessible.name: "New category"; onClicked: window.create("category") }
                        }
                        ListView {
                            id: categoryList
                            PixelScroll { viewport: categoryList }
                            visible: !window.trash
                            Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, window.height * 0.26)
                            model: window.categoryRows; clip: true; spacing: 0
                            boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds
                            ScrollBar.vertical: FieldScrollBar { }
                            delegate: ItemDelegate {
                                id: categoryDelegate
                                required property var modelData
                                readonly property bool current: !window.trash && window.chosenCategory === modelData.value
                                readonly property color inkColour: visualFocus || current ? T.floodInk : T.ink
                                width: ListView.view.width; height: 28; leftPadding: 10; rightPadding: 10; topPadding: 0; bottomPadding: 0; hoverEnabled: true
                                Accessible.name: modelData.name
                                onClicked: { window.trash = false; window.chosenCategory = modelData.value; window.refreshQuery() }
                                MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onPressed: mouse => { window.contextCategory = categoryDelegate.modelData.value === "*" ? "" : categoryDelegate.modelData.value; categoryMenu.popup(categoryDelegate, mouse.x, mouse.y) } }
                                background: Rectangle { color: categoryDelegate.visualFocus ? T.accent : categoryDelegate.current ? T.ink : categoryDelegate.hovered ? T.cell : "transparent" }
                                contentItem: RowLayout {
                                    spacing: 10
                                    Text { Layout.fillWidth: true; text: categoryDelegate.modelData.name; color: categoryDelegate.inkColour; font.family: T.sans; font.pixelSize: 13; elide: Text.ElideRight }
                                    Text { text: categoryDelegate.modelData.count === undefined ? "" : categoryDelegate.modelData.count; color: categoryDelegate.visualFocus || categoryDelegate.current ? T.alpha(T.floodInk, .6) : T.muted; font.family: T.mono; font.pixelSize: T.small }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: 4; spacing: 8
                            Text { text: window.trash ? "in trash" : "notes"; color: T.muted; font.family: T.sans; font.pixelSize: 13 }
                            Text { text: window.c.total; color: T.muted; font.family: T.mono; font.pixelSize: T.small }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                text: window.showNoteSelection ? "Done" : "Select"
                                quiet: !window.showNoteSelection; highlighted: window.showNoteSelection; implicitHeight: 22; visible: !window.trash
                                enabled: window.c.connected && noteList.count > 0
                                Accessible.name: window.showNoteSelection ? "Finish selecting notes" : "Select multiple notes"
                                onClicked: { if (window.showNoteSelection) window.finishSelection(); else { window.c.clearNoteSelection(); window.selectingNotes = true } }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 2; visible: window.showNoteSelection && !window.trash
                            Text { Layout.fillWidth: true; text: window.c.selectedNoteIds.length + " selected"; color: T.ink; font.family: T.mono; font.pixelSize: T.value }
                            ActionButton { text: "All"; quiet: true; Accessible.name: noteList.count < window.c.total ? "Select all loaded notes" : "Select all notes"; onClicked: window.c.selectAllNotes() }
                            ActionButton { text: "Move"; enabled: window.c.connected && window.c.selectedNoteIds.length > 0 && !window.c.moving; onClicked: window.openMove(window.c.selectedNoteIds, window.chosenWorkspace) }
                        }
                        ListView {
                            id: noteList
                            PixelScroll { viewport: noteList }
                            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 52; clip: true; spacing: 0
                            model: window.c.notes
                            boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds
                            ScrollBar.vertical: FieldScrollBar { }
                            Keys.onPressed: event => {
                                if (window.trash) return
                                if (event.matches(StandardKey.SelectAll)) { window.selectingNotes = true; window.c.selectAllNotes(); event.accepted = true }
                                else if (event.key === Qt.Key_Escape && window.showNoteSelection) { window.finishSelection(); event.accepted = true }
                            }
                            onAtYEndChanged: if (atYEnd && count < window.c.total) window.c.loadMore()
                            delegate: ItemDelegate {
                                id: noteDelegate
                                required property var modelData
                                required property int index
                                width: ListView.view.width; height: 52
                                leftPadding: 10; rightPadding: 6; topPadding: 8; bottomPadding: 8; hoverEnabled: true
                                Accessible.name: modelData.title + ", " + (modelData.collection || "Unfiled")
                                property bool selectedForMove: window.c.selectedNoteIds.indexOf(modelData.id) >= 0
                                readonly property bool current: window.showNoteSelection || window.c.selectedNoteIds.length ? selectedForMove : window.c.selectedId === modelData.id
                                readonly property bool inverted: current || visualFocus
                                readonly property var noteState: T.noteState(modelData)
                                Accessible.role: Accessible.ListItem
                                Accessible.selected: selectedForMove
                                onClicked: { noteList.currentIndex = index; forceActiveFocus(); window.chooseNote(modelData.id, Qt.NoModifier) }
                                Keys.onPressed: event => {
                                    if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && !window.showNoteSelection && window.canTrash(modelData)) { window.c.trashNote(modelData.id); event.accepted = true }
                                    else if (event.key === Qt.Key_Space && !window.trash) { window.chooseNote(modelData.id, event.modifiers); event.accepted = true }
                                    else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier)) { window.openNoteMenu(modelData, noteDelegate, 12, height); event.accepted = true }
                                }
                                MouseArea {
                                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) window.openNoteMenu(noteDelegate.modelData, noteDelegate, mouse.x, mouse.y)
                                        else { noteList.currentIndex = noteDelegate.index; noteDelegate.forceActiveFocus(); window.chooseNote(noteDelegate.modelData.id, mouse.modifiers) }
                                    }
                                }
                                DragHandler {
                                    id: noteDrag
                                    target: null; acceptedButtons: Qt.LeftButton; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    enabled: !window.showNoteSelection && window.canTrash(noteDelegate.modelData)
                                    function positionGhost() {
                                        let p = noteDelegate.mapToItem(noteDragGhost.parent, centroid.position.x, centroid.position.y)
                                        noteDragGhost.x = p.x - noteDragGhost.width / 2
                                        noteDragGhost.y = p.y - noteDragGhost.height / 2
                                    }
                                    onCentroidChanged: if (active && noteDragGhost.dragging) positionGhost()
                                    onActiveChanged: {
                                        if (active) {
                                            noteDragGhost.noteId = noteDelegate.modelData.id
                                            noteDragGhost.noteTitle = noteDelegate.modelData.title
                                            positionGhost(); noteDragGhost.dragging = true
                                        } else {
                                            if (noteDragGhost.dragging) noteDragGhost.Drag.drop()
                                            noteDragGhost.dragging = false; noteDragGhost.noteId = ""
                                        }
                                    }
                                    onCanceled: { noteDragGhost.Drag.cancel(); noteDragGhost.dragging = false }
                                }
                                background: Rectangle { color: noteDelegate.visualFocus ? T.accent : noteDelegate.current ? T.ink : noteDelegate.hovered ? T.cell : "transparent" }
                                contentItem: RowLayout {
                                    spacing: 10
                                    FieldCheck {
                                        id: noteCheck
                                        visible: window.showNoteSelection; checked: noteDelegate.selectedForMove
                                        Layout.preferredWidth: 12
                                        Accessible.name: "Select note: " + noteDelegate.modelData.title
                                        onCheckedChanged: if (checked !== noteDelegate.selectedForMove) window.c.selectNoteRow(noteDelegate.modelData.id, true)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text { Layout.fillWidth: true; text: noteDelegate.modelData.title; font.family: T.sans; font.pixelSize: 13; color: noteDelegate.inverted ? T.floodInk : T.ink; elide: Text.ElideRight }
                                            Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; color: T.record; visible: noteDelegate.modelData.status === "recording" || noteDelegate.modelData.status === "paused" }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text {
                                                Layout.fillWidth: true
                                                text: (noteDelegate.modelData.collection || "unfiled") + "  " + (noteDelegate.noteState.text || T.date(noteDelegate.modelData.created))
                                                font.family: T.mono; font.pixelSize: T.small
                                                color: noteDelegate.inverted ? T.alpha(T.floodInk, .6) : T.muted; elide: Text.ElideRight
                                            }
                                            Rectangle { visible: !!noteDelegate.noteState.text && noteDelegate.noteState.color !== T.record; Layout.preferredWidth: 6; Layout.preferredHeight: 6; color: noteDelegate.noteState.color }
                                        }
                                    }
                                    ActionButton {
                                        id: rowCopy
                                        property bool confirmed: false
                                        visible: (noteDelegate.hovered || noteDelegate.current || confirmed) && !window.showNoteSelection
                                        text: confirmed ? "copied" : "copy"; quiet: true; implicitHeight: 22; leftPadding: 6; rightPadding: 6
                                        onBand: noteDelegate.inverted
                                        enabled: window.c.connected
                                        Accessible.name: confirmed ? "Note copied" : "Copy note: " + noteDelegate.modelData.title
                                        onClicked: window.c.copyNote(noteDelegate.modelData.id)
                                        Timer { id: rowCopyReset; interval: 1800; onTriggered: rowCopy.confirmed = false }
                                        Connections { target: window.c; function onNoteCopied(id) { if (id === noteDelegate.modelData.id) { rowCopy.confirmed = true; rowCopyReset.restart() } } }
                                    }
                                }
                            }
                            footer: ActionButton { width: noteList.width; text: "Load more"; quiet: true; visible: noteList.count < window.c.total; height: visible ? 32 : 0; onClicked: window.c.loadMore() }
                            Text { anchors.centerIn: parent; text: searchField.text ? "no matches" : window.trash ? "trash is empty" : "no notes"; color: T.dim; font.family: T.mono; font.pixelSize: T.value; visible: !noteList.count }
                            MouseArea { anchors.fill: parent; enabled: !noteList.count; acceptedButtons: Qt.RightButton; onPressed: mouse => workspaceMenu.popup(noteList, mouse.x, mouse.y) }
                        }
                    }
                }
                ColumnLayout {
                    id: mainPane
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.leftMargin: window.width < 1000 ? 20 : 32; Layout.rightMargin: window.width < 1000 ? 16 : 24
                    Layout.topMargin: 8; Layout.bottomMargin: 12
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true; spacing: 2
                        TextField {
                            id: titleField
                            Layout.fillWidth: true; Layout.minimumWidth: 80; implicitHeight: 36
                            readOnly: window.c.trashed || !window.c.selectedId
                            placeholderText: window.c.selectedId ? "untitled" : "no note"
                            font.family: T.sans; font.pixelSize: 24
                            color: T.ink; placeholderTextColor: T.dim; padding: 0; leftPadding: 0; selectByMouse: true
                            selectionColor: T.alpha(T.accent, .38); selectedTextColor: T.ink
                            Accessible.name: "Note title"
                            TextContextMenu { field: titleField }
                            onTextEdited: if (!window.syncing) window.c.updateTitle(text)
                            background: Rectangle { anchors.fill: parent; anchors.leftMargin: -12; color: "transparent"; border.width: titleField.activeFocus ? 1 : 0; border.color: T.accent }
                        }
                        ActionButton {
                            id: locationButton
                            text: window.workspaceName(window.c.workspace) + " / " + (window.c.collection || "unfiled") + "  ⌄"
                            font.family: T.mono; font.pixelSize: T.value; lowercase: false
                            Layout.maximumWidth: window.width < 1000 ? 170 : 260; quiet: true
                            enabled: !!window.c.selectedId && !window.c.trashed
                            Accessible.name: "Note location: " + text
                            onClicked: locationPopup.open()
                            Popup {
                                id: locationPopup
                                x: Math.min(0, locationButton.width - width)
                                y: locationButton.height; width: 280; padding: 16
                                background: Rectangle { color: T.cell }
                                contentItem: ColumnLayout {
                                    spacing: 6
                                    Text { text: "workspace"; font.family: T.sans; font.pixelSize: 13; color: T.ink }
                                    FieldCombo {
                                        Layout.fillWidth: true
                                        model: window.c.workspaces; textRole: "name"; Accessible.name: "Note workspace"
                                        currentIndex: Math.max(0, window.c.workspaces.findIndex(n => n.id === window.c.workspace))
                                        onActivated: window.c.updateWorkspace(model[currentIndex].id)
                                    }
                                    Text { Layout.topMargin: 8; text: "category"; font.family: T.sans; font.pixelSize: 13; color: T.ink }
                                    FieldCombo {
                                        Layout.fillWidth: true
                                        model: window.noteCategories; textRole: "name"; Accessible.name: "Note category"
                                        currentIndex: Math.max(0, window.noteCategories.findIndex(n => n.value === window.c.collection))
                                        onActivated: window.c.updateCollection(model[currentIndex].value)
                                    }
                                }
                            }
                        }
                        CopyButton { id: copyButton; compact: true; keys: "⌘⇧C"; enabled: !!window.c.body; reduceMotion: window.reducedMotion; onClicked: window.c.copy() }
                        ActionButton {
                            id: moreButton
                            text: "…"; implicitWidth: 28; quiet: true
                            enabled: !!window.c.selectedId; Accessible.name: "More note actions"
                            onClicked: noteMenu.popup(moreButton.width - noteMenu.width, moreButton.height)
                            FieldMenu {
                                id: noteMenu
                                FieldMenuItem { text: "Export note…"; onTriggered: exportDialog.open() }
                                FieldMenuItem { text: "Copy with timestamps"; enabled: !!window.c.body; onTriggered: window.c.copy(true) }
                                FieldMenuItem { text: "Retry unfinished audio"; enabled: window.c.failed > 0 || window.c.engineStatus === "error"; onTriggered: window.c.retry() }
                                FieldMenuItem { text: "Voice filter…"; onTriggered: filterDialog.open() }
                                FieldMenuGap { }
                                FieldMenuItem { text: window.c.trashed ? "Restore note" : "Move note to trash"; enabled: window.c.editable || window.c.trashed; onTriggered: window.c.trashed ? window.c.restoreNote() : window.c.deleteNote() }
                            }
                        }
                    }
                    NoteEditor {
                        id: noteEditor
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 190
                        readOnly: !window.c.editable
                        allowFocusMode: true; focusedWriting: window.focusedWriting
                        statusText: !window.c.selectedId ? "" : window.c.trashed ? "in trash" : window.c.saving ? "saving" : window.c.pending ? "transcribing " + window.c.pending : "saved"
                        statusColour: window.c.selectedId && !window.c.trashed && !window.c.saving && window.c.pending ? T.amber : "transparent"
                        onFocusModeRequested: window.focusedWriting = !window.focusedWriting
                        placeholderText: !window.c.selectedId ? "" : window.c.noteStatus === "recording" || window.c.noteStatus === "paused" ? "listening" : window.c.pending ? "transcribing" : ""
                        onEdited: value => window.c.updateBody(value)
                    }
                    RowLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: 22; spacing: 8
                        readonly property string message: window.c.error || (window.c.engineStatus === "error" ? window.c.engineError || "transcription failed" : window.notice || (window.c.pending && !window.c.recording ? "finishing transcription" : ""))
                        readonly property bool failing: !!window.c.error || window.c.engineStatus === "error"
                        Rectangle { visible: !!parent.message; Layout.preferredWidth: 6; Layout.preferredHeight: 6; color: parent.failing ? T.magenta : window.notice ? T.ink : T.amber }
                        Text {
                            Layout.fillWidth: true
                            text: T.lower(parent.message)
                            color: parent.failing ? T.ink : T.muted; font.family: T.mono; font.pixelSize: T.value; elide: Text.ElideRight
                            ToolTip.visible: statusHover.hovered && truncated; ToolTip.text: text
                            HoverHandler { id: statusHover }
                        }
                        ActionButton { text: "Undo"; implicitHeight: 22; quiet: true; visible: !!window.notice && window.undoVisible; onClicked: { window.c.undoDelete(); window.notice = "" } }
                        ActionButton { text: "Retry"; implicitHeight: 22; quiet: true; visible: window.c.engineStatus === "error"; onClicked: window.c.retry() }
                        ActionButton { text: "Dismiss"; implicitHeight: 22; quiet: true; visible: !!window.c.error; onClicked: window.c.dismissError() }
                    }
                }
            }
            OrganiseView {
                id: organiser
                anchors.fill: parent; visible: window.organising
                controller: window.c; workspace: window.chosenWorkspace
                notice: window.notice
                onWorkspaceChosen: id => window.chosenWorkspace = id
                onBackRequested: window.organising = false
                onSearchChanged: if (window.organising) window.refreshQuery()
                onMoveRequested: ids => window.openMove(ids, window.chosenWorkspace)
                onCreateCategoryRequested: window.create("category")
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 40
            visible: window.focusedWriting && window.c.recording
            color: T.band
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24; spacing: 12
                Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; color: T.record; opacity: window.c.paused ? .45 : 1 }
                Text { text: window.c.clock(window.c.seconds); color: T.bandInk; font.family: T.mono; font.pixelSize: T.value }
                Text { Layout.fillWidth: true; text: window.c.paused ? "paused" : "recording"; color: T.bandMuted; font.family: T.mono; font.pixelSize: T.value }
                ActionButton { onBand: true; text: window.c.paused ? "Resume" : "Pause"; keys: "⌘⇧P"; enabled: !window.c.stopping; onClicked: window.c.pause() }
                ActionButton { onBand: true; text: window.c.stopping ? "Stopping" : "Stop"; keys: "⌘R"; enabled: !window.c.stopping; onClicked: window.c.stop() }
            }
        }
        RecordingConsole {
            visible: !window.focusedWriting
            Layout.fillWidth: true; Layout.preferredHeight: implicitHeight
            controller: window.c; compact: window.height < 760
            reduceMotion: window.reducedMotion; motionActive: window.active && window.visibility !== Window.Minimized
            voiceDb: preferences.voiceDb; deviceId: window.deviceId
            destinationWorkspace: window.c.recording ? window.c.capture.workspace || window.recordingWorkspace : window.recordingWorkspace
            destinationCategory: window.c.recording ? window.c.capture.collection || "" : window.recordingCategory
            onDestinationChosen: workspace => window.chooseRecordingWorkspace(workspace)
            onDestinationCategoryChosen: category => window.recordingCategory = category
            destination: window.workspaceName(window.c.recording ? window.c.capture.workspace : window.recordingWorkspace) + " / " + (window.c.recording ? window.c.capture.collection || "unfiled" : window.recordingCategory || "unfiled")
            onRecordRequested: window.recordToggle()
            onPauseRequested: window.c.pause()
            onDeviceChosen: device => window.deviceId = device
            onVoiceDbChosen: value => preferences.voiceDb = value
            onFilterRequested: filterDialog.open()
        }
    }
}
