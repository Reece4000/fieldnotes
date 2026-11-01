pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as T

ColumnLayout {
    id: root
    property alias text: source.text
    property alias editor: source
    property bool readOnly: false
    property string placeholderText: "Write a note… Markdown is supported."
    property string accessibleName: "Note editor"
    property string statusText: ""
    property color statusColour: "transparent"
    // The editor fills its pane edge to edge; the insets keep the text on the pane's grid,
    // so the footer bar can span the full width and the text scrolls under a tone step.
    property real leftInset: 0
    property real rightInset: 0
    property color footerColour: T.p.cell
    property alias footerItems: footerSlot.data
    property bool preview: false
    property bool allowFocusMode: false
    property bool focusedWriting: false
    property string documentId: ""
    property bool syncing: false
    property bool searchVisible: false
    property int findPosition: -1
    readonly property int wordCount: text.trim() ? text.trim().split(/\s+/).length : 0
    signal edited(string value)
    signal focusModeRequested()
    spacing: 0

    function loadDocument(id, value) {
        let changed = documentId !== id
        let follow = !changed && sourceView.contentY >= Math.max(0, sourceView.contentHeight - sourceView.height) - 24
        syncing = true
        if (changed) {
            // Force a different value to reset undo, including a previously emptied note.
            source.text = source.length ? "" : "\n"
            documentId = id
            preview = false
            searchField.text = ""; searchVisible = false; findPosition = -1
        }
        if (source.text !== value) {
            let cursor = source.cursorPosition
            source.text = value
            source.cursorPosition = changed ? 0 : Math.min(cursor, source.length)
        }
        syncing = false
        if (changed || follow) Qt.callLater(function() {
            sourceView.contentY = changed ? 0 : Math.max(0, sourceView.contentHeight - sourceView.height)
            if (changed) previewView.contentY = 0
        })
    }
    function focusEditor() { preview = false; source.forceActiveFocus() }
    function focusedEditor() { return preview ? rendered : source }
    function togglePreview() {
        preview = !preview
        if (preview) { searchVisible = false; rendered.forceActiveFocus() }
        else { source.forceActiveFocus(); revealCursor() }
    }
    function focusSearch() { preview = false; searchVisible = true; searchField.forceActiveFocus(); searchField.selectAll() }
    function revealCursor() {
        if (syncing || preview || (!source.activeFocus && !searchField.activeFocus)) return
        let y = source.cursorRectangle.y, bottom = y + source.cursorRectangle.height
        if (y < sourceView.contentY) sourceView.contentY = y
        else if (bottom > sourceView.contentY + sourceView.height) sourceView.contentY = bottom - sourceView.height
    }
    function find(backwards) {
        let needle = searchField.text.toLowerCase(), haystack = text.toLowerCase()
        if (!needle) { findPosition = -1; source.deselect(); return }
        let position = backwards ? haystack.lastIndexOf(needle, findPosition > 0 ? findPosition - 1 : haystack.length) : haystack.indexOf(needle, findPosition < 0 ? 0 : findPosition + needle.length)
        if (position < 0) position = backwards ? haystack.lastIndexOf(needle) : haystack.indexOf(needle)
        findPosition = position
        if (position >= 0) { source.select(position, position + needle.length); revealCursor() }
        else source.deselect()
    }
    function replace(start, end, value, selectionStart, selectionEnd) {
        if (readOnly || preview) return
        source.select(start, end)
        // One native replacement keeps each toolbar action a single undo step.
        source.cursorSelection.text = value
        source.select(selectionStart, selectionEnd)
        source.forceActiveFocus()
        revealCursor()
    }
    function wrap(before, after, placeholder) {
        if (readOnly || preview) return
        let start = source.selectionStart, end = source.selectionEnd
        let selected = text.slice(start, end) || placeholder
        if (start >= before.length && text.slice(start - before.length, start) === before && text.slice(end, end + after.length) === after) {
            replace(start - before.length, end + after.length, selected, start - before.length, start - before.length + selected.length)
        } else replace(start, end, before + selected + after, start + before.length, start + before.length + selected.length)
    }
    function prefixLines(prefix) {
        if (readOnly || preview) return
        let start = text.lastIndexOf("\n", Math.max(0, source.selectionStart - 1)) + 1
        if (source.selectionStart === 0) start = 0
        let end = source.selectionEnd
        if (end > start && text[end - 1] === "\n") end -= 1
        else { let next = text.indexOf("\n", end); end = next < 0 ? text.length : next }
        let lines = text.slice(start, end).split("\n")
        let remove = lines.every(line => line.startsWith(prefix))
        let value = lines.map(line => remove ? line.slice(prefix.length) : prefix + line).join("\n")
        replace(start, end, value, start, start + value.length)
    }
    function insertLink() {
        if (readOnly || preview) return
        let start = source.selectionStart, end = source.selectionEnd
        let label = text.slice(start, end) || "link text"
        let value = "[" + label + "](https://)"
        let urlStart = start + label.length + 3
        replace(start, end, value, urlStart, urlStart + 8)
    }

    RowLayout {
        Layout.fillWidth: true; Layout.leftMargin: root.leftInset; Layout.rightMargin: root.rightInset; spacing: 2
        ActionButton {
            text: "Write"; highlighted: !root.preview; flooded: !root.preview && source.activeFocus; quiet: root.preview; enabled: !!root.documentId
            Accessible.name: "Write Markdown"; Accessible.checkable: true; Accessible.checked: !root.preview
            onClicked: root.focusEditor()
        }
        ActionButton {
            text: "Preview"; highlighted: root.preview; flooded: root.preview && rendered.activeFocus; quiet: !root.preview; enabled: !!root.documentId
            Accessible.name: "Preview Markdown"; Accessible.checkable: true; Accessible.checked: root.preview
            onClicked: { root.preview = true; root.searchVisible = false; rendered.forceActiveFocus() }
        }
        Item { Layout.preferredWidth: 14 }
        ActionButton { visible: !root.preview && !root.readOnly && root.width > 600; text: "B"; keys: "⌘B"; quiet: true; focusPolicy: Qt.TabFocus; Accessible.name: "Bold"; onClicked: root.wrap("**", "**", "bold text") }
        ActionButton { visible: !root.preview && !root.readOnly && root.width > 600; text: "I"; keys: "⌘I"; quiet: true; focusPolicy: Qt.TabFocus; Accessible.name: "Italic"; onClicked: root.wrap("*", "*", "italic text") }
        ActionButton { visible: !root.preview && !root.readOnly && root.width > 800; text: "Heading"; quiet: true; focusPolicy: Qt.TabFocus; onClicked: root.prefixLines("## ") }
        ActionButton { visible: !root.preview && !root.readOnly && root.width > 800; text: "List"; quiet: true; focusPolicy: Qt.TabFocus; onClicked: root.prefixLines("- ") }
        ActionButton { visible: !root.preview && !root.readOnly && root.width > 800; text: "Link"; keys: "⌘K"; quiet: true; focusPolicy: Qt.TabFocus; onClicked: root.insertLink() }
        ActionButton {
            id: more
            visible: !root.preview && !root.readOnly
            text: "Format ⌄"; quiet: true; focusPolicy: Qt.TabFocus
            Accessible.name: "More Markdown formatting"
            onClicked: formatMenu.popup(more, 0, height)
            FieldMenu {
                id: formatMenu
                FieldMenuItem { text: "Bold"; onTriggered: root.wrap("**", "**", "bold text") }
                FieldMenuItem { text: "Italic"; onTriggered: root.wrap("*", "*", "italic text") }
                FieldMenuItem { text: "Heading"; onTriggered: root.prefixLines("## ") }
                FieldMenuItem { text: "List"; onTriggered: root.prefixLines("- ") }
                FieldMenuItem { text: "Link"; onTriggered: root.insertLink() }
                FieldMenuItem { text: "Task list"; onTriggered: root.prefixLines("- [ ] ") }
                FieldMenuItem { text: "Quote"; onTriggered: root.prefixLines("> ") }
                FieldMenuItem { text: "Inline code"; onTriggered: root.wrap("`", "`", "code") }
                FieldMenuItem { text: "Code block"; onTriggered: root.wrap("\n```\n", "\n```\n", "code") }
            }
        }
        Item { Layout.fillWidth: true }
        ActionButton { text: root.focusedWriting ? "Recorder" : "Focus"; highlighted: root.focusedWriting; quiet: !root.focusedWriting; visible: root.allowFocusMode; onClicked: root.focusModeRequested() }
        ActionButton { text: "Find"; keys: "⌘F"; quiet: true; enabled: !!root.text; onClicked: root.focusSearch() }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.leftMargin: root.leftInset; Layout.rightMargin: root.rightInset; Layout.topMargin: 6
        visible: root.searchVisible; spacing: 2
        FieldText {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "find in note"; Accessible.name: "Find in note"
            onTextEdited: { root.findPosition = -1; root.find(false) }
            onAccepted: root.find(false)
            Keys.onEscapePressed: { root.searchVisible = false; source.forceActiveFocus() }
        }
        Text {
            Layout.leftMargin: 10; Layout.rightMargin: 6
            text: !searchField.text ? "" : root.findPosition < 0 ? "none" : "found"
            font.family: T.mono; font.pixelSize: T.value; color: root.findPosition < 0 ? T.p.muted : T.p.ink
        }
        ActionButton { text: "↑"; implicitWidth: 28; quiet: true; Accessible.name: "Previous match"; enabled: !!searchField.text; onClicked: root.find(true) }
        ActionButton { text: "↓"; implicitWidth: 28; quiet: true; Accessible.name: "Next match"; enabled: !!searchField.text; onClicked: root.find(false) }
        ActionButton { text: "Close"; keys: "esc"; quiet: true; onClicked: { root.searchVisible = false; source.forceActiveFocus() } }
    }
    Item {
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 36; Layout.topMargin: 6
        Flickable {
            id: sourceView
            objectName: "noteScroll"
            PixelScroll { viewport: sourceView }
            anchors.fill: parent; clip: true; visible: !root.preview
            contentWidth: width; contentHeight: source.height
            boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
            ScrollBar.vertical: FieldScrollBar { }
            TextArea {
                id: source
                width: sourceView.width; height: Math.max(sourceView.height, implicitHeight)
                textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap; selectByMouse: true; persistentSelection: true
                readOnly: root.readOnly; font.family: T.sans; font.pixelSize: 15; color: T.p.ink
                selectionColor: T.alpha(T.p.accent, .38); selectedTextColor: T.p.ink; placeholderTextColor: T.p.muted
                leftPadding: root.leftInset; rightPadding: root.rightInset; topPadding: 10; bottomPadding: 24
                placeholderText: T.lower(root.placeholderText); Accessible.name: root.accessibleName
                onTextChanged: if (!root.syncing && !root.readOnly) root.edited(text)
                onCursorRectangleChanged: root.revealCursor()
                background: Item { }
                TextContextMenu { field: source }
            }
        }
        Flickable {
            id: previewView
            objectName: "previewScroll"
            PixelScroll { viewport: previewView }
            anchors.fill: parent; clip: true; visible: root.preview
            contentWidth: width; contentHeight: rendered.height
            boundsBehavior: Flickable.StopAtBounds; boundsMovement: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
            ScrollBar.vertical: FieldScrollBar { }
            TextArea {
                id: rendered
                objectName: "markdownPreview"
                width: previewView.width; height: Math.max(previewView.height, implicitHeight)
                text: root.preview ? root.text : ""
                textFormat: TextEdit.MarkdownText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                font.family: T.sans; font.pixelSize: 15; color: T.p.ink
                selectionColor: T.alpha(T.p.accent, .38); selectedTextColor: T.p.ink
                leftPadding: root.leftInset; rightPadding: root.rightInset; topPadding: 10; bottomPadding: 24
                placeholderText: "nothing to preview"; placeholderTextColor: T.p.muted
                Accessible.name: "Markdown preview"
                onLinkActivated: link => { if (/^https?:\/\//i.test(link) || /^mailto:/i.test(link)) Qt.openUrlExternally(link) }
                background: Item { }
                TextContextMenu { field: rendered }
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: 34
        color: root.footerColour
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: root.leftInset; anchors.rightMargin: root.rightInset; spacing: 6
            Text { text: "words"; font.family: T.sans; font.pixelSize: 12; color: T.p.muted }
            Text { text: root.wordCount; font.family: T.mono; font.pixelSize: T.value; color: T.p.ink }
            RowLayout { id: footerSlot; Layout.fillWidth: true; Layout.leftMargin: 18; spacing: 8 }
            Rectangle { visible: root.statusColour.a > 0 && !!root.statusText; Layout.preferredWidth: 6; Layout.preferredHeight: 6; color: root.statusColour }
            Text { text: T.lower(root.statusText || (root.preview ? "preview" : root.readOnly ? "read only" : "markdown")); font.family: T.mono; font.pixelSize: T.value; color: T.p.muted }
        }
    }
    Shortcut { sequence: "Meta+B"; enabled: source.activeFocus && !root.readOnly && !root.preview; onActivated: root.wrap("**", "**", "bold text") }
    Shortcut { sequence: "Meta+I"; enabled: source.activeFocus && !root.readOnly && !root.preview; onActivated: root.wrap("*", "*", "italic text") }
    Shortcut { sequence: "Meta+K"; enabled: source.activeFocus && !root.readOnly && !root.preview; onActivated: root.insertLink() }
    Shortcut { sequence: "Meta+Shift+M"; enabled: root.visible && (source.activeFocus || rendered.activeFocus); onActivated: root.togglePreview() }
}
