import QtQuick
import QtQuick.Controls
import "Theme.js" as T

Menu {
    id: control
    width: 248
    padding: 4
    margins: 12
    overlap: 0
    background: Rectangle { color: T.p.cell }
    delegate: FieldMenuItem { }
}
