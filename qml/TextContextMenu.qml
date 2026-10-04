pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: host
    required property var field
    parent: field
    anchors.fill: parent
    z: 100
    FieldMenu {
        id: menu
        FieldMenuItem { text: "Undo"; enabled: !host.field.readOnly && host.field.canUndo; onTriggered: host.field.undo() }
        FieldMenuItem { text: "Redo"; enabled: !host.field.readOnly && host.field.canRedo; onTriggered: host.field.redo() }
        MenuSeparator { padding: 4; contentItem: Rectangle { implicitHeight: 1; color: "#dce2d4" } }
        FieldMenuItem { text: "Cut"; enabled: !host.field.readOnly && !!host.field.selectedText; onTriggered: host.field.cut() }
        FieldMenuItem { text: "Copy"; enabled: !!host.field.selectedText; onTriggered: host.field.copy() }
        FieldMenuItem { text: "Paste"; enabled: !host.field.readOnly && host.field.canPaste; onTriggered: host.field.paste() }
        FieldMenuItem { text: "Delete selection"; enabled: !host.field.readOnly && !!host.field.selectedText; onTriggered: host.field.remove(host.field.selectionStart, host.field.selectionEnd) }
        MenuSeparator { padding: 4; contentItem: Rectangle { implicitHeight: 1; color: "#dce2d4" } }
        FieldMenuItem { text: "Select all"; enabled: !!host.field.text; onTriggered: host.field.selectAll() }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: mouse => menu.popup(host.field, mouse.x, mouse.y)
    }
}
