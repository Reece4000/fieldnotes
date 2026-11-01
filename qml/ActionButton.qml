import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A flat square key. Quiet keys are bare words; `highlighted` inverts the cell for the
// current choice; keyboard focus floods the key with the accent.
Button {
    id: control
    property bool primary: false
    property bool quiet: false
    property bool onBand: false
    property string keys: ""
    // Labels are lowercase; user content (names, titles) keeps its case.
    property bool lowercase: true
    readonly property string label: lowercase ? T.lower(text) : text
    readonly property bool focusFlood: control.visualFocus || (control.activeFocus && control.focusReason === Qt.TabFocusReason)
    readonly property color fill: !control.enabled ? (control.quiet ? "transparent" : control.onBand ? T.alpha(T.bandKey, .5) : T.panel)
        : control.focusFlood ? T.accent
        : control.down || control.highlighted ? (control.onBand ? T.bandInk : T.ink)
        : control.hovered ? (control.onBand ? T.bandKey : T.cell)
        : control.quiet ? "transparent" : control.onBand ? T.bandKey : T.cell
    readonly property color labelColour: !control.enabled ? (control.onBand ? T.bandMuted : T.dim)
        : control.focusFlood ? T.floodInk
        : control.down || control.highlighted ? (control.onBand ? T.band : T.floodInk)
        : control.quiet && !control.hovered ? (control.onBand ? T.bandMuted : T.muted)
        : control.onBand ? T.bandInk : T.ink
    implicitHeight: 28
    implicitWidth: Math.max(implicitHeight, Math.ceil(labelMetrics.advanceWidth) + leftPadding + rightPadding + (keys ? Math.ceil(keyMetrics.advanceWidth) + 10 : 0))
    leftPadding: 10; rightPadding: 10
    topPadding: 0; bottomPadding: 0
    hoverEnabled: true
    font.family: T.sans; font.pixelSize: 13
    Accessible.name: text
    TextMetrics { id: labelMetrics; text: control.label; font: control.font }
    TextMetrics { id: keyMetrics; text: control.keys; font.family: T.mono; font.pixelSize: T.small }
    contentItem: Item {
        Text {
            anchors.left: parent.left; anchors.right: keyLegend.visible ? keyLegend.left : parent.right
            anchors.rightMargin: keyLegend.visible ? 10 : 0
            height: parent.height
            text: control.label; font: control.font; color: control.labelColour
            horizontalAlignment: control.keys ? Text.AlignLeft : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
        Text {
            id: keyLegend
            visible: !!control.keys
            anchors.right: parent.right; height: parent.height
            text: control.keys; font.family: T.mono; font.pixelSize: T.small
            color: T.alpha(control.labelColour, .6); verticalAlignment: Text.AlignVCenter
        }
    }
    background: Rectangle { color: control.fill }
}
