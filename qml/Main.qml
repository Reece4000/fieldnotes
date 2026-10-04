pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: window
    width: Qt.application.arguments.indexOf("--compact") >= 0 ? 800 : 1280
    height: Qt.application.arguments.indexOf("--compact") >= 0 ? 620 : 900
    minimumWidth: 760; minimumHeight: 580
    visible: true; title: "Fieldnotes"; color: "#f3f7f0"
    flags: Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint
    // The background extends through the native title bar; ApplicationWindow
    // keeps interactive content inside the system-reported safe area.
    background: Item {
        Rectangle { width: 264; height: parent.height; color: "#eaf0e5" }
        Rectangle { x: 264; width: 1; height: parent.height; color: "#dfe6d8" }
    }
    palette.window: "#fbfcf7"; palette.base: "#f9faf5"; palette.button: "#e8edde"
    palette.buttonText: "#293d2b"; palette.text: "#293d2b"
    palette.placeholderText: "#7b8872"; palette.highlight: "#dfe8d5"; palette.highlightedText: "#293d2b"
    // qmllint disable unqualified
    property var c: appController
    // qmllint enable unqualified
    property string chosenWorkspace: preferences.lastWorkspace
    property string recordingWorkspace: chosenWorkspace
    property string recordingCategory: recordingWorkspace === chosenWorkspace ? currentCategory() : ""
    function chooseRecordingWorkspace(workspace) { recordingWorkspace = workspace; recordingCategory = "" }
    property string chosenCategory: "*"
    property bool trash: false
    property int deviceId: -1
    property bool syncing: false
    property bool queryStarted: false
    property int findPosition: -1
    function workspaceName(id) { let w = c.workspaces.find(n => n.id === id); return w ? w.name : "" }
    function revealCursor() {
        if ((!editor.activeFocus && !transcriptSearch.activeFocus) || syncing) return
        let y = editor.cursorRectangle.y
        transcriptView.contentY = Math.max(0, Math.min(transcriptView.contentHeight - transcriptView.height, y < transcriptView.contentY ? y : y + editor.cursorRectangle.height > transcriptView.contentY + transcriptView.height ? y + editor.cursorRectangle.height - transcriptView.height : transcriptView.contentY))
    }
    function findTranscript(backwards) {
        let needle = transcriptSearch.text.toLowerCase(), haystack = editor.text.toLowerCase()
        if (!needle) { findPosition = -1; editor.deselect(); return }
        let position = backwards ? haystack.lastIndexOf(needle, findPosition > 0 ? findPosition - 1 : haystack.length) : haystack.indexOf(needle, findPosition < 0 ? 0 : findPosition + needle.length)
        if (position < 0) position = backwards ? haystack.lastIndexOf(needle) : haystack.indexOf(needle)
        findPosition = position
        if (position >= 0) { editor.cursorPosition = position; editor.select(position, position + needle.length); revealCursor() } else editor.deselect()
    }
    property string loadedId: ""
    property string notice: ""
    property bool undoVisible: false
    property string creationKind: "category"
    property bool creating: false
    property string creationError: ""
    property bool reducedMotion: preferences.reduceMotion || c.systemReduceMotion
    property var categoryRows: [{name: "All notes", value: "*"}, {name: "Unfiled", value: ""}].concat(
        c.categories.filter(n => n.workspace === chosenWorkspace).map(n => ({name: n.name, value: n.name, count: n.count})))
    property var noteCategories: [{name: "Unfiled", value: ""}].concat(
        c.categories.filter(n => n.workspace === c.workspace).map(n => ({name: n.name, value: n.name})))
    Settings { id: preferences; location: window.c.settingsFile; property double voiceDb: -44; property bool reduceMotion: false; property string lastWorkspace: "inbox" }
    function refreshQuery() { if (c.connected) c.query(chosenWorkspace, chosenCategory, searchField.text, trash) }
    function currentCategory() { return chosenCategory === "*" || trash ? "" : chosenCategory }
    function recordToggle() { if (c.connected) { if (c.recording) c.stop(); else c.record(deviceId, recordingCategory, recordingWorkspace, preferences.voiceDb) } }
    function newNote() { c.newNote(currentCategory(), chosenWorkspace) }
    function focusedEditor() { return titleField.activeFocus ? titleField : editor }
    function showNotice(text, undo) { notice = text; undoVisible = undo || false; noticeTimer.restart() }
    function create(kind) { creationKind = kind; creating = false; creationError = ""; creationName.text = ""; creationDialog.open(); creationName.forceActiveFocus() }
    function loadDocument() {
        syncing = true
        let changed = loadedId !== c.selectedId
        let follow = !changed && transcriptView.contentY >= Math.max(0, transcriptView.contentHeight - transcriptView.height) - 24
        if (titleField.text !== c.title) titleField.text = c.title
        if (editor.text !== c.body) {
            let position = editor.cursorPosition
            editor.text = c.body
            editor.cursorPosition = changed ? 0 : Math.min(position, editor.length)
        }
        loadedId = c.selectedId
        if (changed) { transcriptSearch.text = ""; findPosition = -1 }
        if (changed || follow) Qt.callLater(function() { transcriptView.contentY = changed ? 0 : Math.max(0, transcriptView.contentHeight - transcriptView.height) })
        syncing = false
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
        function onWorkspaceCreated(id) { window.creating = false; creationDialog.close(); window.chosenWorkspace = id }
        function onCategoryCreated(name) { window.creating = false; creationDialog.close(); window.chosenCategory = name; window.trash = false; window.refreshQuery() }
        function onErrorChanged() { if (window.creating && window.c.error) { window.creationError = window.c.error; window.creating = false } }
        function onStateChanged() {
            if (window.c.connected && !window.queryStarted) { window.queryStarted = true; window.refreshQuery() }
            if (!window.loadedId && window.c.connected) window.loadDocument()
        }
    }
    Timer { id: noticeTimer; interval: 6500; onTriggered: window.notice = "" }
    Timer { id: searchTimer; interval: 180; onTriggered: window.refreshQuery() }
    Shortcut { sequence: "Meta+Shift+P"; enabled: window.c.recording; onActivated: window.c.pause() }
    Shortcut { sequence: "Meta+Shift+C"; enabled: !!window.c.body; onActivated: window.c.copy() }
    Shortcut { sequences: [StandardKey.Find]; onActivated: transcriptSearch.forceActiveFocus() }
    Shortcut { sequence: "Meta+Shift+F"; onActivated: searchField.forceActiveFocus() }
    Shortcut { sequence: "Meta+E"; enabled: !!window.c.selectedId; onActivated: exportDialog.open() }
    FileDialog { id: exportDialog; title: "Export note"; fileMode: FileDialog.SaveFile; nameFilters: ["Markdown notes (*.md)", "Text files (*.txt)"]; defaultSuffix: "md"; onAccepted: window.c.exportNote(selectedFile) }
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
            TextField { id: creationName; Layout.fillWidth: true; placeholderText: window.creationKind === "workspace" ? "e.g. HCI research" : "e.g. Debugging runs"; Accessible.name: "Name"; selectByMouse: true; enabled: !window.creating; color: "#293d2b"; placeholderTextColor: "#738275"; leftPadding: 10; implicitHeight: 36; background: Rectangle { radius: 5; color: "white"; border.color: creationName.activeFocus ? "#61866c" : "#cbd5c6" } onAccepted: creationDialog.submit() }
            Text { Layout.fillWidth: true; Layout.preferredHeight: 32; text: window.creationError; color: "#a33d28"; wrapMode: Text.WordWrap; font.pixelSize: 11 }
            RowLayout {
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; enabled: !window.creating; onClicked: creationDialog.close() }
            ActionButton { text: window.creating ? "Creating…" : "Create"; enabled: !!creationName.text.trim() && !window.creating && window.c.connected; onClicked: creationDialog.submit() }
            }
        }
    }
    FieldDialog {
        id: filterDialog
        anchors.centerIn: parent; width: 410; modal: true; title: "Voice filter"
        contentItem: ColumnLayout {
            spacing: 14
            Text { Layout.fillWidth: true; text: "Speech detection is always on. Ignore speech quieter than this level to reduce distant voices."; wrapMode: Text.WordWrap; color: "#40533a"; font.pixelSize: 13 }
            RowLayout { Layout.fillWidth: true; Text { text: "Quiet voices"; font.pixelSize: 11; color: "#65765c" } Item { Layout.fillWidth: true } Text { text: "Nearby voices"; font.pixelSize: 11; color: "#65765c" } }
            Slider {
                id: voiceSlider
                Layout.fillWidth: true; from: -65; to: -20; stepSize: 1; value: preferences.voiceDb; Accessible.name: "Minimum voice level"; onMoved: preferences.voiceDb = value
                background: Rectangle { x: voiceSlider.leftPadding; y: (voiceSlider.height - height) / 2; width: voiceSlider.availableWidth; height: 5; radius: 3; color: "#d8e1d5"; Rectangle { width: voiceSlider.visualPosition * parent.width; height: parent.height; radius: 3; color: "#6f987a" } }
                handle: Rectangle { x: voiceSlider.leftPadding + voiceSlider.visualPosition * (voiceSlider.availableWidth - width); y: (voiceSlider.height - height) / 2; implicitWidth: 22; implicitHeight: 22; radius: 11; color: voiceSlider.pressed ? "#edf3e8" : "white"; border.color: voiceSlider.activeFocus ? "#264e38" : "#76957a"; border.width: 2 }
            }
            Text { text: "Minimum voice level: " + Math.round(preferences.voiceDb) + " dBFS"; color: "#40533a"; font.pixelSize: 12 }
            Text { Layout.fillWidth: true; text: "Applies to new recordings. If your own quiet speech is missed, move towards Quiet voices. Louder background speech can still pass the filter."; wrapMode: Text.WordWrap; color: "#65765c"; font.pixelSize: 11 }
            CheckBox {
                id: motionCheck
                text: "Reduce motion"; checked: preferences.reduceMotion; onToggled: preferences.reduceMotion = checked
                spacing: 10
                indicator: Rectangle { x: motionCheck.leftPadding; y: (motionCheck.height - height) / 2; implicitWidth: 20; implicitHeight: 20; radius: 4; color: motionCheck.checked ? "#4c755b" : "#ffffff"; border.color: motionCheck.activeFocus ? "#244332" : "#9daf9e"; border.width: motionCheck.activeFocus ? 2 : 1; Text { anchors.centerIn: parent; text: motionCheck.checked ? "✓" : ""; color: "white"; font.pixelSize: 15 } }
                contentItem: Text { text: motionCheck.text; color: "#293d2b"; font.pixelSize: 13; leftPadding: motionCheck.indicator.width + motionCheck.spacing; verticalAlignment: Text.AlignVCenter }
            }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } ActionButton { text: "Close"; onClicked: filterDialog.close() } }
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
            Action { text: "Find notes"; onTriggered: searchField.forceActiveFocus() }
        }
    }
    RowLayout {
        anchors.fill: parent; spacing: 0
        Rectangle {
            Layout.preferredWidth: 264; Layout.fillHeight: true; color: "#eaf0e5"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Fieldnotes"; color: "#263b29"; font.pixelSize: 25; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    ActionButton { text: "+"; font.pixelSize: 22; implicitWidth: 34; implicitHeight: 34; padding: 5; background: Rectangle { radius: width / 2; color: "#f8fbf5"; border.color: "#dce6d4" } Accessible.name: "New note"; enabled: window.c.connected; onClicked: window.newNote(); ToolTip.visible: hovered; ToolTip.text: "New note · ⌘N" }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 4
                    FieldCombo {
                        id: workspacePicker
                        glyph: "workspace"
                        Layout.fillWidth: true
                        model: window.c.workspaces; textRole: "name"
                        currentIndex: Math.max(0, window.c.workspaces.findIndex(n => n.id === window.chosenWorkspace))
                        Accessible.name: "Workspace"
                        onActivated: window.chosenWorkspace = model[currentIndex].id
                    }
                    ActionButton { text: "+"; quiet: true; Accessible.name: "New workspace"; onClicked: window.create("workspace"); ToolTip.visible: hovered; ToolTip.text: "New workspace" }
                }
                TextField {
                    id: searchField
                    Layout.fillWidth: true; implicitHeight: 34; placeholderText: "Search this workspace"
                    font.pixelSize: 12; color: "#293d2b"; leftPadding: 33; selectByMouse: true
                    FieldIcon { name: "search"; width: 16; height: 16; x: 10; anchors.verticalCenter: parent.verticalCenter; tint: "#7a8d7d" }
                    Accessible.name: "Search notes"
                    onTextChanged: searchTimer.restart()
                    background: Rectangle { color: "#f9faf5"; radius: 5; border.color: searchField.activeFocus ? "#64815a" : "#d5ddcd" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "CATEGORIES"; color: "#697962"; font.pixelSize: 9; font.letterSpacing: 1.4; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    ActionButton { text: "+"; quiet: true; implicitHeight: 24; Accessible.name: "New category"; onClicked: window.create("category"); ToolTip.visible: hovered; ToolTip.text: "New category" }
                }
                ListView {
                    id: categoryList
                    Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, 182)
                    model: window.categoryRows; clip: true; spacing: 2
                    boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    delegate: ItemDelegate {
                        id: categoryDelegate
                        required property var modelData
                        width: ListView.view.width; height: 33; leftPadding: 9; rightPadding: 9; hoverEnabled: true
                        Accessible.name: modelData.name
                        onClicked: { window.trash = false; window.chosenCategory = modelData.value; window.refreshQuery() }
                        background: Rectangle { radius: 4; color: !window.trash && window.chosenCategory === categoryDelegate.modelData.value ? "#dce5d3" : categoryDelegate.hovered ? "#e4eadd" : "transparent"; border.width: categoryDelegate.activeFocus ? 1 : 0; border.color: "#55784c" }
                        contentItem: RowLayout {
                            spacing: 13
                            FieldIcon { Layout.preferredWidth: 18; Layout.preferredHeight: 18; name: categoryDelegate.modelData.value === "*" ? "document" : /hci|test/i.test(categoryDelegate.modelData.name) ? "flask" : /debug/i.test(categoryDelegate.modelData.name) ? "gear" : /idea/i.test(categoryDelegate.modelData.name) ? "idea" : "folder" }
                            Text { Layout.fillWidth: true; text: categoryDelegate.modelData.name; color: "#344c30"; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { text: categoryDelegate.modelData.count === undefined ? "" : categoryDelegate.modelData.count; color: "#6e7c64"; font.pixelSize: 10 }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#d4ddcb" }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: window.trash ? "TRASH" : "NOTES"; color: "#697962"; font.pixelSize: 9; font.letterSpacing: 1.4; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    Text { text: window.c.total; color: "#697962"; font.pixelSize: 11 }
                }
                ListView {
                    id: noteList
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
                    model: window.c.notes
                    boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds
                    flickDeceleration: 5000; maximumFlickVelocity: 1400
                    ScrollBar.vertical: ScrollBar { }
                    onAtYEndChanged: if (atYEnd && count < window.c.total) window.c.loadMore()
                    delegate: ItemDelegate {
                        id: noteDelegate
                        required property var modelData
                        width: ListView.view.width; height: 58
                        leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 7; hoverEnabled: true
                        Accessible.name: modelData.title + ", " + (modelData.collection || "Unfiled")
                        onClicked: window.c.selectNote(modelData.id)
                        background: Rectangle { radius: 4; color: window.c.selectedId === noteDelegate.modelData.id ? "#dce5d3" : noteDelegate.hovered ? "#e4eadd" : "transparent"; border.width: noteDelegate.activeFocus ? 1 : 0; border.color: "#55784c" }
                        contentItem: ColumnLayout {
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true; spacing: 5
                                Text { Layout.fillWidth: true; text: noteDelegate.modelData.title; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#293c2a"; elide: Text.ElideRight }
                                Button {
                                    id: rowCopy
                                    property bool confirmed: false
                                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                    padding: 4; hoverEnabled: true
                                    enabled: window.c.connected
                                    Accessible.name: confirmed ? "Note copied" : "Copy note: " + noteDelegate.modelData.title
                                    onClicked: window.c.copyNote(noteDelegate.modelData.id)
                                    background: Rectangle { radius: 4; color: rowCopy.down ? "#cfdbc5" : rowCopy.hovered ? "#d4dfcb" : "transparent"; border.width: rowCopy.activeFocus ? 1 : 0; border.color: "#55784c" }
                                    contentItem: Item {
                                        FieldIcon { anchors.centerIn: parent; width: 14; height: 14; name: "copy"; tint: "#597361"; opacity: rowCopy.confirmed ? 0 : 1 }
                                        Text { anchors.centerIn: parent; text: "✓"; color: "#365f43"; font.pixelSize: 15; opacity: rowCopy.confirmed ? 1 : 0; Behavior on opacity { NumberAnimation { duration: window.reducedMotion ? 0 : 120 } } }
                                    }
                                    ToolTip.visible: hovered; ToolTip.text: "Copy transcript"
                                    Timer { id: rowCopyReset; interval: 1800; onTriggered: rowCopy.confirmed = false }
                                    Connections { target: window.c; function onNoteCopied(id) { if (id === noteDelegate.modelData.id) { rowCopy.confirmed = true; rowCopyReset.restart() } } }
                                }
                                Rectangle { Layout.preferredWidth: 5; Layout.preferredHeight: 5; radius: 3; color: "#b44530"; visible: noteDelegate.modelData.status === "recording" || noteDelegate.modelData.status === "paused" }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (noteDelegate.modelData.collection || "Unfiled") + " · " + (noteDelegate.modelData.errors ? "Needs retry" : noteDelegate.modelData.status === "recording" ? "Recording" : noteDelegate.modelData.status === "paused" ? "Paused" : noteDelegate.modelData.pending ? "Transcribing" : Qt.formatDateTime(new Date(noteDelegate.modelData.created * 1000), "dd MMM, HH:mm"))
                                font.pixelSize: 10; color: noteDelegate.modelData.errors ? "#a73a29" : "#6c7b65"; elide: Text.ElideRight
                            }
                        }
                    }
                    footer: ActionButton { width: noteList.width; text: "Load more notes"; visible: noteList.count < window.c.total; height: visible ? 32 : 0; onClicked: window.c.loadMore() }
                    Text { anchors.centerIn: parent; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: searchField.text ? "No matching notes." : window.trash ? "Trash is empty." : "No notes here yet.\nRecord a session or add a note."; color: "#74806c"; font.pixelSize: 12; visible: !noteList.count }
                }
                RowLayout {
                    Layout.fillWidth: true
                    ActionButton { text: "Trash"; glyph: "trash"; quiet: !window.trash; implicitHeight: 28; onClicked: { window.trash = !window.trash; window.chosenCategory = "*" } }
                    Item { Layout.fillWidth: true }
                    Rectangle { Layout.preferredWidth: 5; Layout.preferredHeight: 5; radius: 3; color: window.c.engineStatus === "ready" ? "#557d46" : window.c.engineStatus === "error" ? "#b44530" : "#b39140" }
                    Text { text: "Phonon-2"; font.pixelSize: 10; color: "#62735c"; ToolTip.visible: engineHover.hovered; ToolTip.text: window.c.engineStatus === "ready" ? "Local transcription ready" : window.c.engineStatus === "error" ? window.c.engineError : "Preparing the local model"; HoverHandler { id: engineHover } }
                }
            }
        }
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: "#dce2d6" }
        ColumnLayout {
            id: mainPane
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.margins: window.width < 1000 ? 16 : 24
            Layout.topMargin: 12; Layout.bottomMargin: 16
            spacing: window.height < 760 ? 12 : 16
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    TextField {
                        id: titleField
                        Layout.fillWidth: true; implicitHeight: 34
                        readOnly: window.c.trashed || !window.c.selectedId
                        placeholderText: window.c.selectedId ? "Untitled note" : "Select a note"
                        font.pixelSize: 24; font.weight: Font.DemiBold
                        color: "#123b2b"; placeholderTextColor: "#6a7c70"; padding: 0; selectByMouse: true
                        Accessible.name: "Note title"
                        onTextEdited: if (!window.syncing) window.c.updateTitle(text)
                        background: Rectangle { color: "transparent"; border.width: titleField.activeFocus ? 1 : 0; border.color: "#8da67d"; radius: 3 }
                    }
                    CopyButton { id: copyButton; implicitHeight: 32; enabled: !!window.c.body; reduceMotion: window.reducedMotion; onClicked: window.c.copy(); ToolTip.visible: hovered; ToolTip.text: "Copy without timestamps · ⌘⇧C" }
                    ActionButton { text: "Export"; glyph: "export"; implicitHeight: 32; enabled: !!window.c.selectedId; onClicked: exportDialog.open() }
                    ActionButton {
                        id: moreButton
                        text: "…"; implicitHeight: 28; implicitWidth: 28; padding: 4; quiet: true
                        enabled: !!window.c.selectedId; Accessible.name: "More note actions"
                        onClicked: noteMenu.popup(moreButton.width - noteMenu.width, moreButton.height + 4)
                        FieldMenu {
                            id: noteMenu
                            FieldMenuItem { text: "Copy with timestamps"; enabled: !!window.c.body; onTriggered: window.c.copy(true) }
                            FieldMenuItem { text: "Retry unfinished audio"; enabled: window.c.failed > 0 || window.c.engineStatus === "error"; onTriggered: window.c.retry() }
                            FieldMenuItem { text: "Voice filter…"; onTriggered: filterDialog.open() }
                            MenuSeparator { padding: 4; contentItem: Rectangle { implicitHeight: 1; color: "#dce2d4" } }
                            FieldMenuItem { text: window.c.trashed ? "Restore note" : "Move note to trash"; enabled: window.c.editable || window.c.trashed; onTriggered: window.c.trashed ? window.c.restoreNote() : window.c.deleteNote() }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    FieldCombo {
                        Layout.preferredWidth: Math.min(160, mainPane.width / 3); glyph: window.width < 1000 ? "" : "folder"; implicitHeight: 28
                        enabled: !!window.c.selectedId && !window.c.trashed
                        model: window.c.workspaces; textRole: "name"
                        currentIndex: Math.max(0, window.c.workspaces.findIndex(n => n.id === window.c.workspace))
                        Accessible.name: "Note workspace"
                        onActivated: window.c.updateWorkspace(model[currentIndex].id)
                    }
                    FieldCombo {
                        Layout.preferredWidth: Math.min(160, mainPane.width / 3); glyph: window.width < 1000 ? "" : /hci|test/i.test(window.c.collection) ? "flask" : "folder"; implicitHeight: 28
                        enabled: !!window.c.selectedId && !window.c.trashed
                        model: window.noteCategories; textRole: "name"
                        currentIndex: Math.max(0, window.noteCategories.findIndex(n => n.value === window.c.collection))
                        Accessible.name: "Note category"
                        onActivated: window.c.updateCollection(model[currentIndex].value)
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; visible: !!window.c.selectedId; color: window.c.failed ? "#b44530" : "#669276" }
                    Text {
                        text: !window.c.selectedId ? "" : window.c.trashed ? "In Trash" : window.c.saving ? "Saving…" : window.c.pending ? "Transcribing · " + window.c.pending : "Saved"
                        color: "#65796c"; font.pixelSize: 10
                        ToolTip.visible: saveHover.hovered && window.c.updated > 0
                        ToolTip.text: "Edited " + Qt.formatDateTime(new Date(window.c.updated * 1000), "dd MMM, HH:mm")
                        HoverHandler { id: saveHover }
                    }
                }
            }
            Surface {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 146
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 20; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        FieldIcon { name: "document"; Layout.preferredWidth: 20; Layout.preferredHeight: 20; tint: "#8e9e90" }
                        Text { text: "TRANSCRIPT"; font.pixelSize: 10; font.letterSpacing: 1.6; font.weight: Font.DemiBold; color: "#61776a" }
                        Item { Layout.fillWidth: true }
                        TextField {
                            id: transcriptSearch
                            Layout.preferredWidth: Math.min(220, mainPane.width / 3); implicitHeight: 30
                            placeholderText: "Find in transcript"; color: "#293d2b"; placeholderTextColor: "#768377"; font.pixelSize: 11; selectByMouse: true; leftPadding: 30
                            FieldIcon { name: "search"; width: 15; height: 15; x: 9; anchors.verticalCenter: parent.verticalCenter; tint: "#7a8d7d" }
                            Accessible.name: "Search transcript"
                            onAccepted: window.findTranscript(false)
                            onTextEdited: { window.findPosition = -1; window.findTranscript(false) }
                            background: Rectangle { color: "#f8faf6"; radius: 5; border.color: transcriptSearch.activeFocus ? "#64815a" : "#e0e7dd" }
                        }
                        ActionButton { text: "↑"; padding: 4; implicitWidth: 28; implicitHeight: 28; quiet: true; enabled: !!transcriptSearch.text; Accessible.name: "Previous transcript match"; onClicked: window.findTranscript(true) }
                        ActionButton { text: "↓"; padding: 4; implicitWidth: 28; implicitHeight: 28; quiet: true; enabled: !!transcriptSearch.text; Accessible.name: "Next transcript match"; onClicked: window.findTranscript(false) }
                    }
                    Flickable {
                        id: transcriptView
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        contentWidth: width; contentHeight: editor.height
                        boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds
                        flickDeceleration: 5000; maximumFlickVelocity: 1400; acceptedButtons: Qt.NoButton
                        ScrollBar.vertical: ScrollBar { }
                        TextArea {
                            id: editor
                            width: transcriptView.width
                            height: Math.max(transcriptView.height, implicitHeight)
                            textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap; selectByMouse: true
                            readOnly: !window.c.editable; persistentSelection: true
                            font.pixelSize: 14; color: "#47574d"; selectionColor: "#cddfba"; selectedTextColor: "#20331c"
                            leftPadding: 0; rightPadding: 14; topPadding: 2; bottomPadding: 18
                            placeholderTextColor: "#768377"
                            placeholderText: !window.c.selectedId ? "Select a note or start recording."
                                : window.c.noteStatus === "recording" || window.c.noteStatus === "paused" ? "Waiting for the first transcribed section…"
                                : window.c.pending ? "Transcribing…" : "Write a note…"
                            Accessible.name: "Note transcript"
                            onTextChanged: if (!window.syncing && window.c.editable) window.c.updateBody(text)
                            onCursorRectangleChanged: window.revealCursor()
                            background: Rectangle { color: "transparent" }
                        }
                    }
                    Text { Layout.fillWidth: true; Layout.preferredHeight: 14; opacity: transcriptSearch.text ? 1 : 0; text: window.findPosition < 0 ? "No matches" : "Match highlighted"; color: "#6a7c70"; font.pixelSize: 10 }
                }
            }
            RecordingConsole {
                Layout.fillWidth: true; Layout.preferredHeight: implicitHeight
                Layout.minimumHeight: implicitHeight; Layout.maximumHeight: implicitHeight
                controller: window.c; compact: window.height < 760
                reduceMotion: window.reducedMotion; motionActive: window.active && window.visibility !== Window.Minimized
                voiceDb: preferences.voiceDb; deviceId: window.deviceId
                destinationWorkspace: window.c.recording ? window.c.capture.workspace || window.recordingWorkspace : window.recordingWorkspace
                destinationCategory: window.c.recording ? window.c.capture.collection || "" : window.recordingCategory
                onDestinationChosen: workspace => window.chooseRecordingWorkspace(workspace)
                onDestinationCategoryChosen: category => window.recordingCategory = category
                destination: window.workspaceName(window.c.recording ? window.c.capture.workspace : window.recordingWorkspace) + " / " + (window.c.recording ? window.c.capture.collection || "Unfiled" : window.recordingCategory || "Unfiled")
                onRecordRequested: window.recordToggle()
                onPauseRequested: window.c.pause()
                onDeviceChosen: device => window.deviceId = device
                onFilterRequested: filterDialog.open()
            }
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 0; Layout.maximumHeight: 0
                RowLayout {
                width: parent.width; height: 20; y: -8; spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: window.c.error || (window.c.engineStatus === "error" ? "Transcription failed. Audio retained for retry. " + window.c.engineError : window.notice || (window.c.pending && !window.c.recording ? "Finishing transcription…" : ""))
                    color: window.c.error || window.c.engineStatus === "error" ? "#a33d28" : "#6e7d5e"; font.pixelSize: 11; elide: Text.ElideRight
                    ToolTip.visible: statusHover.hovered && !!text; ToolTip.text: text
                    HoverHandler { id: statusHover }
                }
                ActionButton { text: "Undo"; implicitHeight: 20; font.pixelSize: 11; quiet: true; visible: !!window.notice && window.undoVisible; onClicked: { window.c.undoDelete(); window.notice = "" } }
                ActionButton { text: "Retry"; implicitHeight: 20; font.pixelSize: 11; quiet: true; visible: window.c.engineStatus === "error"; onClicked: window.c.retry() }
                ActionButton { text: "Dismiss"; implicitHeight: 20; font.pixelSize: 11; quiet: true; visible: !!window.c.error; onClicked: window.c.dismissError() }
                }
            }
        }
    }
}
