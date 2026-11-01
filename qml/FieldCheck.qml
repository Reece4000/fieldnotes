import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A status square: lit when checked, an empty frame when not.
CheckBox {
    id: control
    property bool onBand: false
    spacing: 10
    padding: 0
    font.family: T.sans; font.pixelSize: 13
    indicator: Rectangle {
        x: control.leftPadding; y: (control.height - height) / 2
        implicitWidth: 10; implicitHeight: 10
        color: control.visualFocus ? T.p.accent : control.checked ? (control.onBand ? T.p.bandInk : T.p.ink) : "transparent"
        border.width: control.checked || control.visualFocus ? 0 : 1
        border.color: control.onBand ? T.p.bandMuted : T.p.muted
    }
    contentItem: Text {
        text: T.lower(control.text); font: control.font
        color: control.onBand ? T.p.bandInk : control.checked ? T.p.ink : T.p.muted
        leftPadding: control.text ? control.indicator.width + control.spacing : 0
        verticalAlignment: Text.AlignVCenter
    }
}
