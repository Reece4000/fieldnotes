import QtQuick
import "Theme.js" as T

// The one readout: DSEG14 in a dark window, the unlit segments faintly behind.
Rectangle {
    id: readout
    property string text: "00:00:00"
    property real size: 30
    property bool lit: true
    color: T.chip
    implicitWidth: litText.implicitWidth + 32
    implicitHeight: size + 30
    Text {
        anchors.centerIn: parent
        text: readout.text.replace(/[0-9A-Za-z]/g, "~")
        font.family: T.segment; font.pixelSize: readout.size
        color: T.alpha(T.readout, .07)
    }
    Text {
        id: litText
        anchors.centerIn: parent
        text: readout.text
        font.family: T.segment; font.pixelSize: readout.size
        color: readout.lit ? T.readout : T.alpha(T.readout, .35)
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: readout.text
}
