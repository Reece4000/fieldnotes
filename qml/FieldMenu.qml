import QtQuick
import QtQuick.Controls
Menu {
    id: control
    width: 240
    padding: 6
    margins: 12
    overlap: 0
    background: Rectangle { color: "#fbfcf7"; radius: 7; border.color: "#c8d2be" }
    delegate: FieldMenuItem { }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 80 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 60 } }
}
