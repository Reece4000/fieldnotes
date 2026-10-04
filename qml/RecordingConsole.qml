pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
Surface {
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
    readonly property bool detailed: width > 760
    readonly property bool referenceLayout: detailed && !compact
    readonly property string microphoneName: devicePicker.displayText
    readonly property bool capturing: controller.recording && !controller.stopping
    // Reference: 3878 × 1074, measured in a proportional 2048 × 567 space.
    readonly property real sx: width / 2048
    readonly property real sy: height / 567
    readonly property real unit: Math.min(sx, sy)
    signal recordRequested()
    signal pauseRequested()
    signal deviceChosen(int device)
    signal destinationChosen(string workspace)
    signal destinationCategoryChosen(string category)
    signal filterRequested()
    implicitHeight: compact ? 188 : detailed ? Math.min(330, width * 567 / 2048) : 264

    Item {
        id: inputColumn
        x: recorderConsole.detailed ? 33 * recorderConsole.sx : 16
        width: recorderConsole.detailed ? 442 * recorderConsole.sx : recorderConsole.compact ? 148 : 190
        height: parent.height
        FieldCombo {
            id: devicePicker
            y: recorderConsole.referenceLayout ? 146 * recorderConsole.sy : recorderConsole.compact ? 25 : 54
            width: parent.width
            height: recorderConsole.referenceLayout ? 88 * recorderConsole.sy : 36
            font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12
            glyph: recorderConsole.detailed || !recorderConsole.compact ? "microphone" : ""
            enabled: !recorderConsole.controller.recording
            model: [{id: -1, name: "Default microphone"}].concat(recorderConsole.controller.devices)
            textRole: "name"
            currentIndex: Math.max(0, model.findIndex(n => n.id === recorderConsole.deviceId))
            Accessible.name: "Recording microphone"
            onActivated: recorderConsole.deviceChosen(model[currentIndex].id)
        }
        Row {
            x: recorderConsole.detailed ? 82 * recorderConsole.sx : 8
            y: recorderConsole.referenceLayout ? 301 * recorderConsole.sy : recorderConsole.compact ? 91 : 121
            spacing: recorderConsole.detailed ? 19 * recorderConsole.sx : 9
            TapeReel {
                width: recorderConsole.referenceLayout ? 58 * recorderConsole.unit : 28
                height: width
                recording: recorderConsole.capturing
                paused: recorderConsole.controller.paused
                reduceMotion: recorderConsole.reduceMotion
                motionActive: recorderConsole.motionActive
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: recorderConsole.controller.stopping ? "Input stopped" : recorderConsole.capturing ? recorderConsole.controller.paused ? "Input paused" : Math.round(recorderConsole.controller.decibels) + " dBFS" : "Not recording"
                color: "#6a7c70"
                font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12
            }
        }
        Row {
            id: levelMeter
            y: recorderConsole.referenceLayout ? 419 * recorderConsole.sy : recorderConsole.compact ? 143 : 177
            width: parent.width
            height: recorderConsole.referenceLayout ? 33 * recorderConsole.sy : 16
            spacing: recorderConsole.detailed ? 6 * recorderConsole.sx : 3
            Repeater {
                model: 24
                Rectangle {
                    required property int index
                    width: (inputColumn.width - 23 * levelMeter.spacing) / 24
                    height: levelMeter.height
                    radius: width / 2
                    color: recorderConsole.capturing && !recorderConsole.controller.paused && index < recorderConsole.controller.level * 24 ? (index > 21 ? "#bc543e" : "#39955f") : "#dfe7dc"
                }
            }
            Accessible.role: Accessible.Indicator
            Accessible.name: "Microphone input level"
        }
        Text {
            visible: !recorderConsole.detailed
            y: recorderConsole.compact ? 167 : 211
            width: parent.width
            text: "Save to " + recorderConsole.destination
            color: "#426151"; font.pixelSize: 11; elide: Text.ElideRight
            ToolTip.visible: destHover.hovered; ToolTip.text: text
            HoverHandler { id: destHover }
        }
        ActionButton {
            visible: !recorderConsole.detailed && !recorderConsole.compact
            y: 231; text: "Voice filter…"; quiet: true; implicitHeight: 26
            onClicked: recorderConsole.filterRequested()
        }
    }
    Item {
        id: transport
        x: recorderConsole.detailed ? 523 * recorderConsole.sx : inputColumn.x + inputColumn.width + 18
        width: recorderConsole.detailed ? 968 * recorderConsole.sx : recorderConsole.width - x - 16
        height: parent.height
        Rectangle {
            y: recorderConsole.referenceLayout ? 53 * recorderConsole.sy : 14
            width: recorderConsole.referenceLayout ? 337 * recorderConsole.sx : 160
            height: recorderConsole.referenceLayout ? 55 * recorderConsole.sy : 26
            anchors.horizontalCenter: parent.horizontalCenter
            radius: height / 2
            color: recorderConsole.controller.recording ? recorderConsole.controller.paused ? "#f4eedf" : "#fbefe9" : "#ecf2e8"
            Row {
                anchors.centerIn: parent
                spacing: recorderConsole.referenceLayout ? 17 * recorderConsole.unit : 8
                Rectangle {
                    width: recorderConsole.referenceLayout ? 15 * recorderConsole.unit : 7
                    height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                    color: recorderConsole.controller.recording ? recorderConsole.controller.paused ? "#a28139" : "#ce583e" : recorderConsole.controller.connected ? "#39955f" : "#a28139"
                }
                Text {
                    text: recorderConsole.controller.stopping ? "Stopping…" : recorderConsole.capturing ? recorderConsole.controller.paused ? "Paused" : "Recording" : recorderConsole.controller.connected ? "Ready to record" : "Connecting…"
                    color: "#365c45"; font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12; font.weight: Font.Medium
                }
            }
        }
        Text {
            y: recorderConsole.referenceLayout ? 133 * recorderConsole.sy : recorderConsole.compact ? 48 : 62
            anchors.horizontalCenter: parent.horizontalCenter
            text: recorderConsole.controller.clock(recorderConsole.controller.recording ? recorderConsole.controller.seconds : 0)
            color: "#103d2c"; font.pixelSize: recorderConsole.referenceLayout ? 72 * recorderConsole.unit : recorderConsole.compact ? 28 : 36
            font.family: "Helvetica Neue"; font.weight: Font.Medium
        }
        Waveform {
            width: parent.width
            height: recorderConsole.referenceLayout ? 160 * recorderConsole.sy : 66
            y: recordButton.y + (recordButton.height - height) / 2
            samples: recorderConsole.controller.waveform
            capturing: recorderConsole.capturing; paused: recorderConsole.controller.paused
        }
        RectangularShadow { anchors.fill: recordButton; radius: recordButton.width / 2; blur: 12; color: "#29c55238"; offset.y: 3 }
        Button {
            id: recordButton
            width: recorderConsole.referenceLayout ? 184 * recorderConsole.unit : recorderConsole.compact ? 60 : 86
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            y: recorderConsole.referenceLayout ? 333 * recorderConsole.sy - height / 2 : recorderConsole.compact ? 92 : 123
            enabled: recorderConsole.controller.connected && !recorderConsole.controller.stopping; hoverEnabled: true
            Accessible.name: recorderConsole.controller.stopping ? "Stopping recording" : recorderConsole.capturing ? "Stop recording" : "Start recording"
            onClicked: recorderConsole.recordRequested()
            background: Rectangle {
                radius: width / 2
                color: !recordButton.enabled ? "#aeaca5" : recordButton.down ? "#ac3f29" : recordButton.hovered ? "#c64b31" : "#d65a3d"
                border.color: recordButton.activeFocus ? "#294e3c" : "#fffdf8"; border.width: 3
            }
            contentItem: Item {
                Rectangle {
                    width: recorderConsole.capturing ? recordButton.width * .256 : recordButton.width * .349
                    height: width; radius: recorderConsole.capturing ? 4 : width / 2
                    color: "#fffaf5"; anchors.centerIn: parent
                }
            }
            ToolTip.visible: hovered; ToolTip.text: recorderConsole.controller.recording ? "Stop recording · ⌘R" : "Start recording · ⌘R"
        }
        Text {
            visible: !recorderConsole.controller.recording
            y: recorderConsole.referenceLayout ? 465 * recorderConsole.sy : recorderConsole.compact ? 162 : 221
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Click to start recording"; color: "#748177"
            font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12
        }
        Text {
            visible: !recorderConsole.controller.recording && !recorderConsole.compact
            y: recorderConsole.referenceLayout ? 509 * recorderConsole.sy : 244
            anchors.horizontalCenter: parent.horizontalCenter
            text: "⌘ R"; color: "#6a796e"; font.pixelSize: recorderConsole.referenceLayout ? 23 * recorderConsole.unit : 11
        }
        ActionButton {
            visible: recorderConsole.controller.recording
            y: recorderConsole.referenceLayout ? 455 * recorderConsole.sy : recorderConsole.compact ? 156 : 220
            anchors.horizontalCenter: parent.horizontalCenter
            text: recorderConsole.controller.paused ? "Resume" : "Pause"; quiet: true; implicitHeight: 28
            enabled: !recorderConsole.controller.stopping
            onClicked: recorderConsole.pauseRequested()
        }
    }
    Rectangle {
        visible: recorderConsole.detailed
        x: 1561 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 76 * recorderConsole.sy : 20
        width: 1; height: recorderConsole.referenceLayout ? 439 * recorderConsole.sy : 148; color: "#e2e9de"
    }
    Repeater {
        model: [ {icon: "microphone", y: 122, compactY: 30}, {icon: "waveform", y: 246, compactY: 80}, {icon: "folder", y: 384, compactY: 139} ]
        Rectangle {
            required property var modelData
            visible: recorderConsole.detailed
            x: 1614 * recorderConsole.sx; y: recorderConsole.referenceLayout ? modelData.y * recorderConsole.sy : modelData.compactY
            width: recorderConsole.referenceLayout ? 69 * recorderConsole.unit : 34; height: width
            radius: recorderConsole.referenceLayout ? 18 * recorderConsole.unit : 9; color: "#f0f5ed"
            FieldIcon { name: parent.modelData.icon; anchors.centerIn: parent; width: recorderConsole.referenceLayout ? 40 * recorderConsole.unit : 20; height: width }
        }
    }
    Text { visible: recorderConsole.detailed; x: 1710 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 129 * recorderConsole.sy : 27; text: "Input"; color: "#354d40"; font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12; font.weight: Font.Medium }
    Text { visible: recorderConsole.detailed; x: 1710 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 176 * recorderConsole.sy : 49; width: 300 * recorderConsole.sx; text: recorderConsole.microphoneName; color: "#6e7b71"; font.pixelSize: recorderConsole.referenceLayout ? 24 * recorderConsole.unit : 11; elide: Text.ElideRight }
    Text { visible: recorderConsole.detailed; x: 1710 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 238 * recorderConsole.sy : 73; text: "Voice filter"; color: "#354d40"; font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12; font.weight: Font.Medium }
    ActionButton {
        visible: recorderConsole.detailed
        x: 1710 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 278 * recorderConsole.sy : 91
        height: recorderConsole.referenceLayout ? 62 * recorderConsole.sy : 30; font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12
        text: Math.round(recorderConsole.voiceDb) + " dBFS  ⌄"; quiet: true
        onClicked: recorderConsole.filterRequested(); Accessible.name: "Voice filter settings"
    }
    Text { visible: recorderConsole.detailed; x: 1710 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 372 * recorderConsole.sy : 125; text: "Save to"; color: "#354d40"; font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12; font.weight: Font.Medium }
    FieldCombo {
        visible: recorderConsole.detailed
        x: 1711 * recorderConsole.sx; y: recorderConsole.referenceLayout ? 406 * recorderConsole.sy : 145
        width: 286 * recorderConsole.sx; height: recorderConsole.referenceLayout ? 62 * recorderConsole.sy : 30
        font.pixelSize: recorderConsole.referenceLayout ? 26 * recorderConsole.unit : 12
        enabled: !recorderConsole.controller.recording
        model: recorderConsole.controller.workspaces; textRole: "name"
        currentIndex: Math.max(0, model.findIndex(n => n.id === recorderConsole.destinationWorkspace))
        Accessible.name: "Workspace for new recordings"
        onActivated: recorderConsole.destinationChosen(model[currentIndex].id)
        ToolTip.visible: hovered; ToolTip.text: recorderConsole.destination
    }
}
