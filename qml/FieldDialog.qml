import QtQuick
import QtQuick.Controls
import "Theme.js" as T

Dialog {
    id: control
    modal: true
    padding: 24
    topPadding: 4
    background: Rectangle { color: T.p.panel }
    header: Item {
        implicitHeight: 64
        Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 24; anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: T.lower(control.title); color: T.p.ink; font.family: T.sans; font.pixelSize: 22; elide: Text.ElideRight
        }
    }
    Overlay.modal: Rectangle { color: T.alpha(T.p.ground, .72) }
}
