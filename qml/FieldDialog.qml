import QtQuick
import QtQuick.Controls
Dialog {
    id: control
    modal: true
    padding: 22
    topPadding: 12
    background: Rectangle { color: "#fafcf8"; radius: 12; border.color: "#cbd5c9" }
    header: Item {
        implicitHeight: 56
        Text { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 22; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; text: control.title; color: "#213c32"; font.pixelSize: 18; font.weight: Font.DemiBold }
    }
    Overlay.modal: Rectangle { color: "#660f241c" }
}
