import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A key on the band, drawn with its live meaning: the key legend top left, what it does
// bottom left. `flood` fills it while its state is on (red for recording only).
Button {
    id: control
    property string keys: ""
    property color flood: "transparent"
    readonly property bool flooded: flood.a > 0
    readonly property color legendColour: control.visualFocus || control.flooded ? T.floodInk : control.enabled ? T.bandInk : T.bandMuted
    hoverEnabled: true
    padding: 10
    font.family: T.sans; font.pixelSize: T.label
    Accessible.name: text
    contentItem: Item {
        Text {
            text: control.keys; font.family: T.mono; font.pixelSize: T.small
            color: T.alpha(control.legendColour, control.enabled ? .7 : .6)
        }
        Text {
            anchors.bottom: parent.bottom
            width: parent.width; elide: Text.ElideRight
            text: T.lower(control.text); font: control.font
            color: control.legendColour
        }
    }
    background: Rectangle {
        color: control.visualFocus ? T.accent
             : control.flooded ? (control.down ? Qt.darker(control.flood, 1.15) : control.flood)
             : !control.enabled ? T.alpha(T.bandKey, .45)
             : control.down ? T.bandInk
             : control.hovered ? Qt.lighter(T.bandKey, 1.06) : T.bandKey
    }
}
