import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A square input: a cell that floods with the accent while it holds the cursor.
TextField {
    id: control
    implicitHeight: 28
    leftPadding: 10; rightPadding: 10
    selectByMouse: true
    font.family: T.mono; font.pixelSize: T.value
    color: activeFocus ? T.floodInk : T.ink
    placeholderTextColor: activeFocus ? T.alpha(T.floodInk, .55) : T.muted
    selectionColor: T.floodInk; selectedTextColor: T.accent
    verticalAlignment: TextInput.AlignVCenter
    background: Rectangle { color: control.activeFocus ? T.accent : control.hovered ? T.dim : T.cell }
    TextContextMenu { field: control }
}
