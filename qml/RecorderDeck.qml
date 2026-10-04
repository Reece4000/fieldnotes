pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    id: deck
    required property var controller
    property bool reduceMotion: false
    property bool motionActive: true
    property double voiceDb: -72
    signal filterRequested()
    implicitHeight: 68
    RowLayout {
        anchors.fill: parent
        spacing: 14
        Item {
            Layout.preferredWidth: 62; Layout.preferredHeight: 62
            Accessible.role: Accessible.Indicator
            Accessible.name: deck.controller.paused ? "Recording paused" : deck.controller.recording ? "Microphone recording" : "Recorder ready"
            Rectangle {
                id: reel
                width: 58; height: 58; anchors.centerIn: parent; radius: 29
                color: "#ded5b8"; border.color: "#94886a"; border.width: 1
                NumberAnimation on rotation {
                    id: reelSpin
                    from: 0; to: 360; duration: 3600; loops: Animation.Infinite
                    running: deck.controller.recording && !deck.reduceMotion && deck.visible
                    paused: reelSpin.running && (deck.controller.paused || !deck.motionActive)
                }
                Repeater {
                    model: 3
                    Rectangle {
                        id: spoke
                        required property int index
                        width: 13; height: 20; radius: 6
                        x: 22.5; y: 5
                        color: "#f8f5e9"; border.color: "#aa9f82"
                        transform: Rotation { origin.x: 6.5; origin.y: 24; angle: spoke.index * 120 }
                    }
                }
                Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: "#695e45"; border.color: "#f8f5e9"; border.width: 3 }
            }
            Rectangle { width: 6; height: 6; radius: 3; anchors.right: parent.right; anchors.bottom: parent.bottom; color: deck.controller.recording ? deck.controller.paused ? "#a79255" : "#b44530" : "#8a947d" }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text { text: deck.controller.recording ? deck.controller.paused ? "PAUSED" : "MICROPHONE · CAPTURING" : "MICROPHONE"; color: "#677057"; font.pixelSize: 9; font.letterSpacing: 1.3 }
                Item { Layout.fillWidth: true }
                Text { text: deck.controller.recording ? (deck.controller.paused ? "—" : Math.round(deck.controller.decibels) + " dBFS") : ""; color: "#677057"; font.family: "Menlo"; font.pixelSize: 10 }
            }
            Canvas {
                id: waveform
                Layout.fillWidth: true; Layout.preferredHeight: 34
                property var samples: deck.controller.waveform
                property bool capturing: deck.controller.recording
                property bool paused: deck.controller.paused
                onSamplesChanged: requestPaint()
                onCapturingChanged: requestPaint()
                onPausedChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    let ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#d5dbc8"; ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(0, height / 2); ctx.lineTo(width, height / 2); ctx.stroke()
                    if (!capturing) return
                    ctx.strokeStyle = paused ? "#a6ab98" : "#65734c"
                    ctx.lineWidth = 1.5
                    let count = Math.min(samples.length, Math.floor(width / 3))
                    for (let i = 0; i < count; i++) {
                        let value = samples[Math.floor(i * samples.length / count)]
                        let h = Math.max(1, value * (height - 4))
                        let x = i * width / count + 1
                        ctx.beginPath(); ctx.moveTo(x, (height - h) / 2); ctx.lineTo(x, (height + h) / 2); ctx.stroke()
                    }
                }
                Accessible.role: Accessible.Indicator
                Accessible.name: "Live microphone waveform"
            }
        }
        ActionButton { text: "Voice filter"; quiet: true; onClicked: deck.filterRequested(); ToolTip.visible: hovered; ToolTip.text: "Ignore noise and voices below " + Math.round(deck.voiceDb) + " dBFS" }
    }
}
