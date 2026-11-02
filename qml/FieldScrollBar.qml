import QtQuick
import QtQuick.Controls
import "Theme.js" as T

ScrollBar {
    id: control
    property bool onBand: false
    padding: 0
    minimumSize: 0.08
    contentItem: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        color: control.pressed ? T.p.ink : control.onBand ? T.p.bandMuted : T.p.dim
        opacity: control.policy === ScrollBar.AlwaysOn || (control.active && control.size < 1.0) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }
}
