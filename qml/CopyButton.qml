import QtQuick
import QtQuick.Controls
Button {
    id: control
    property bool confirmed: false
    property bool reduceMotion: false
    function confirm() { confirmed = true; reset.restart() }
    implicitWidth: 110; implicitHeight: 36
    hoverEnabled: true
    Accessible.name: confirmed ? "Transcript copied" : "Copy transcript"
    Timer { id: reset; interval: 1800; onTriggered: control.confirmed = false }
    contentItem: Item {
        FieldIcon { name: "copy"; width: 18; height: 18; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; tint: control.enabled ? "#426354" : "#92988d" }
        Text { text: "Copy"; anchors.left: parent.left; anchors.leftMargin: 26; anchors.verticalCenter: parent.verticalCenter; color: control.enabled ? "#293d2b" : "#92988d"; font.pixelSize: 13 }
        Text {
            text: "✓"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            color: "#507644"; font.pixelSize: 16
            opacity: control.confirmed ? 1 : 0
            scale: control.confirmed ? 1 : .7
            Behavior on opacity { NumberAnimation { duration: control.reduceMotion ? 0 : 120 } }
            Behavior on scale { NumberAnimation { duration: control.reduceMotion ? 0 : 120; easing.type: Easing.OutCubic } }
        }
    }
    leftPadding: 10; rightPadding: 10
    background: Rectangle { radius: 7; color: control.down ? "#d7dfce" : control.hovered ? "#e5ebde" : "#f8faf5"; border.color: control.activeFocus ? "#55784c" : "#d4ddce"; border.width: control.activeFocus ? 2 : 1 }
}
