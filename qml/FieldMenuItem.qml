import QtQuick
import QtQuick.Controls
MenuItem {
    id: control
    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    contentItem: Text {
        text: control.text
        font.pixelSize: 13
        color: !control.enabled ? "#92988d" : "#293d2b"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 4
        color: control.enabled && control.highlighted ? "#dfe8d5" : "transparent"
    }
}
