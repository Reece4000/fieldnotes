import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A square input: a cell that floods with the accent while it holds the cursor.
TextField {
    id: control
    // On a cell-tone bar the field sits back in the panel tone.
    property bool onCell: false
    implicitHeight: 28
    leftPadding: 10; rightPadding: 10
    selectByMouse: true
    font.family: T.mono; font.pixelSize: T.value
    color: activeFocus ? T.p.floodInk : T.p.ink
    placeholderTextColor: activeFocus ? T.alpha(T.p.floodInk, .55) : T.p.muted
    selectionColor: T.p.floodInk; selectedTextColor: T.p.accent
    verticalAlignment: TextInput.AlignVCenter
    background: Rectangle { color: control.activeFocus ? T.p.accent : control.hovered ? T.p.dim : control.onCell ? T.p.panel : T.p.cell }
    TextContextMenu { field: control }
}
