pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

// The silver band: the recorder is the surface you play, so it spans the window's foot.
// Readout, keys, the live input as the hero, then where the recording goes.
Rectangle {
    id: recorderConsole
    required property var controller
    property bool reduceMotion: false
    property bool motionActive: true
    property bool compact: false
    property int deviceId: -1
    property string destination: ""
    property string destinationCategory: ""
    property string destinationWorkspace: "inbox"
    property double voiceDb: -72
    // Column alignment with the panels above: the first column's width and the gap after it.
    property real leadWidth: 212
    property real leadGap: 24
    readonly property bool narrow: width < 1040
    readonly property bool capturing: controller.recording && !controller.stopping
    readonly property real inner: height - 2 * margin
    readonly property real margin: compact ? 16 : 20
    readonly property real gap: narrow ? 16 : 24
    readonly property real rowHeight: compact ? 24 : 28
    signal recordRequested()
    signal pauseRequested()
    signal deviceChosen(int device)
    signal destinationChosen(string workspace)
    signal destinationCategoryChosen(string category)
    signal voiceDbChosen(double value)
    signal filterRequested()
    color: T.p.band
    implicitHeight: compact ? 120 : 152

    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24
        anchors.topMargin: recorderConsole.margin; anchors.bottomMargin: recorderConsole.margin
        spacing: recorderConsole.gap

        ColumnLayout {
            Layout.preferredWidth: recorderConsole.leadWidth; Layout.fillHeight: true
            Layout.rightMargin: recorderConsole.leadGap - recorderConsole.gap
            spacing: 0
            Readout {
                Layout.fillWidth: true
                Layout.preferredHeight: recorderConsole.compact ? 50 : 66
                size: recorderConsole.narrow || recorderConsole.compact ? 24 : 30
                text: recorderConsole.controller.clock(recorderConsole.controller.recording ? recorderConsole.controller.seconds : 0)
                lit: recorderConsole.controller.recording
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 18; spacing: 8
                Rectangle {
                    Layout.preferredWidth: 8; Layout.preferredHeight: 8
                    color: recorderConsole.controller.recording ? T.p.record : recorderConsole.controller.connected ? T.p.bandInk : T.p.amber
                    opacity: recorderConsole.controller.paused ? .45 : 1
                }
                Text {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    text: recorderConsole.controller.stopping ? "stopping" : recorderConsole.capturing ? recorderConsole.controller.paused ? "paused" : "recording" : recorderConsole.controller.connected ? "ready" : "connecting"
                    font.family: T.mono; font.pixelSize: T.value; color: T.p.bandInk
                }
            }
        }

        Row {
            Layout.fillHeight: true
            spacing: 8
            BandKey {
                id: recordKey
                width: recorderConsole.inner; height: recorderConsole.inner
                keys: "⌘R"
                text: recorderConsole.controller.stopping ? "stopping" : recorderConsole.capturing ? "stop" : "rec"
                flood: recorderConsole.controller.recording ? T.p.record : "transparent"
                enabled: recorderConsole.controller.connected && !recorderConsole.controller.stopping
                Accessible.name: recorderConsole.controller.stopping ? "Stopping recording" : recorderConsole.capturing ? "Stop recording" : "Start recording"
                onClicked: recorderConsole.recordRequested()
            }
            BandKey {
                width: Math.round(recorderConsole.inner * .72); height: recorderConsole.inner
                keys: "⌘⇧P"
                text: recorderConsole.controller.paused ? "resume" : "pause"
                enabled: recorderConsole.capturing
                Accessible.name: recorderConsole.controller.paused ? "Resume recording" : "Pause recording"
                onClicked: recorderConsole.pauseRequested()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 120
            spacing: 6
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 18
                Text { text: "level"; font.family: T.sans; font.pixelSize: T.label; color: T.p.bandInk }
                Item { Layout.fillWidth: true }
                Text {
                    text: recorderConsole.capturing && !recorderConsole.controller.paused ? Math.round(recorderConsole.controller.decibels) : "—"
                    font.family: T.mono; font.pixelSize: T.value; color: T.p.bandMuted
                }
                Text { text: "dBFS"; font.family: T.mono; font.pixelSize: T.small; color: T.p.bandMuted }
            }
            Waveform {
                Layout.fillWidth: true; Layout.fillHeight: true
                samples: recorderConsole.controller.waveform
                capturing: recorderConsole.capturing; paused: recorderConsole.controller.paused
            }
            Row {
                id: levelMeter
                Layout.fillWidth: true; Layout.preferredHeight: 6
                spacing: 2
                readonly property int cells: 32
                Repeater {
                    model: levelMeter.cells
                    Rectangle {
                        required property int index
                        width: (levelMeter.width - (levelMeter.cells - 1) * levelMeter.spacing) / levelMeter.cells
                        height: levelMeter.height
                        readonly property bool lit: recorderConsole.capturing && !recorderConsole.controller.paused && index < recorderConsole.controller.level * levelMeter.cells
                        color: lit ? (index >= levelMeter.cells - 3 ? T.p.magenta : T.p.bandInk) : T.p.bandKey
                    }
                }
                Accessible.role: Accessible.Indicator
                Accessible.name: "Microphone input level"
            }
        }

        ColumnLayout {
            Layout.preferredWidth: recorderConsole.narrow ? 190 : 300; Layout.fillHeight: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: recorderConsole.rowHeight; spacing: 0
                Text { Layout.preferredWidth: 64; text: "input"; font.family: T.sans; font.pixelSize: 13; color: T.p.bandInk }
                FieldCombo {
                    id: devicePicker
                    Layout.fillWidth: true; Layout.preferredHeight: recorderConsole.rowHeight
                    onBand: true
                    enabled: !recorderConsole.controller.recording
                    model: [{id: -1, name: "default microphone"}].concat(recorderConsole.controller.devices)
                    textRole: "name"
                    currentIndex: Math.max(0, model.findIndex(n => n.id === recorderConsole.deviceId))
                    Accessible.name: "Recording microphone"
                    onActivated: recorderConsole.deviceChosen(model[currentIndex].id)
                }
            }
            Item { Layout.fillHeight: true }
            FieldSlider {
                Layout.fillWidth: true; Layout.preferredHeight: recorderConsole.rowHeight
                inline: true; onBand: true
                label: "filter"; unit: "dBFS"
                from: -90; to: -20; stepSize: 1
                value: recorderConsole.voiceDb
                valueText: Math.round(value)
                Accessible.name: "Minimum voice level"
                onMoved: recorderConsole.voiceDbChosen(value)
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: recorderConsole.rowHeight; spacing: 0
                Text { Layout.preferredWidth: 64; text: "save to"; font.family: T.sans; font.pixelSize: 13; color: T.p.bandInk }
                FieldCombo {
                    Layout.fillWidth: true; Layout.preferredHeight: recorderConsole.rowHeight
                    onBand: true
                    enabled: !recorderConsole.controller.recording
                    model: recorderConsole.controller.workspaces; textRole: "name"
                    displayText: recorderConsole.destination
                    currentIndex: Math.max(0, model.findIndex(n => n.id === recorderConsole.destinationWorkspace))
                    Accessible.name: "Workspace for new recordings"
                    onActivated: recorderConsole.destinationChosen(model[currentIndex].id)
                }
            }
        }
    }
}
