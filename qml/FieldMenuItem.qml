import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// Menus are mono and lowercase; the item under the cursor inverts, a checked item is a lit square.
MenuItem {
    id: control
    implicitHeight: 28
    leftPadding: 10
    rightPadding: 10
    hoverEnabled: true
    indicator: Item { }
    contentItem: Item {
        Rectangle {
            visible: control.checkable
            width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter
            color: control.checked ? (control.highlighted ? T.floodInk : T.ink) : "transparent"
            border.width: control.checked ? 0 : 1; border.color: control.highlighted ? T.floodInk : T.dim
        }
        Text {
            anchors.fill: parent; anchors.leftMargin: control.checkable ? 16 : 0
            text: T.lower(control.text)
            font.family: T.mono; font.pixelSize: T.value
            color: !control.enabled ? T.dim : control.highlighted ? T.floodInk : T.ink
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    background: Rectangle { color: control.enabled && control.highlighted ? T.ink : "transparent" }
}
