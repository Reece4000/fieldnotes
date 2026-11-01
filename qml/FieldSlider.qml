import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A label–value pair and its track: ink label, mono value with a small unit, and a
// square 6-unit track with a 2 × 12 tick. Stacked, the track sits underneath; inline,
// label, track and value share one row. Keyboard focus floods the label.
Slider {
    id: control
    property string label: ""
    property string valueText: Math.round(value)
    property string unit: ""
    property bool onBand: false
    property bool inline: false
    property real labelWidth: 64
    readonly property color inkColour: onBand ? T.bandInk : T.ink
    readonly property color mutedColour: onBand ? T.bandMuted : T.muted
    implicitHeight: inline ? 28 : 44
    implicitWidth: 200
    padding: 0
    topPadding: inline ? 0 : 24
    leftPadding: inline ? labelWidth : 0
    rightPadding: inline ? valueRow.implicitWidth + 12 : 0
    hoverEnabled: true
    Accessible.name: label
    Rectangle {
        x: -3; y: labelText.y - 1; width: labelText.implicitWidth + 6; height: labelText.height + 2
        visible: control.visualFocus; color: T.accent
    }
    Text {
        id: labelText
        y: control.inline ? (control.height - height) / 2 : 0; height: 18
        text: T.lower(control.label)
        font.family: T.sans; font.pixelSize: control.inline ? 13 : T.label
        color: control.visualFocus ? T.floodInk : control.inkColour
        verticalAlignment: Text.AlignVCenter
    }
    Row {
        id: valueRow
        anchors.right: parent.right; y: control.inline ? (control.height - height) / 2 : 0; height: 18; spacing: 4
        Text { height: parent.height; text: control.valueText; font.family: T.mono; font.pixelSize: T.value; color: control.mutedColour; verticalAlignment: Text.AlignVCenter }
        Text { visible: !!control.unit; height: parent.height; text: control.unit; font.family: T.mono; font.pixelSize: T.small; color: control.mutedColour; verticalAlignment: Text.AlignVCenter }
    }
    background: Rectangle {
        x: control.leftPadding; y: control.topPadding + (control.availableHeight - height) / 2
        width: control.availableWidth; height: 6
        color: control.onBand ? T.bandKey : T.cell
        Rectangle { width: control.visualPosition * parent.width; height: parent.height; color: control.onBand ? T.bandInk : T.accent }
    }
    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + (control.availableHeight - height) / 2
        implicitWidth: 2; implicitHeight: 12
        color: control.inkColour
    }
}
