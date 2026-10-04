pragma ComponentBehavior: Bound
import QtQuick
Item {
    id: reelIndicator
    property bool recording: false
    property bool paused: false
    property bool reduceMotion: false
    property bool motionActive: true
    implicitWidth: 30; implicitHeight: 30
    Accessible.role: Accessible.Indicator
    Accessible.name: recording ? paused ? "Recording paused" : "Recording reel" : "Recorder idle"
    Rectangle {
        id: reel
        anchors.fill: parent; radius: width / 2
        color: "#f0f4ee"; border.color: "#95ad9c"
        NumberAnimation on rotation {
            id: spin
            from: 0; to: 360; duration: 4000; loops: Animation.Infinite
            running: reelIndicator.recording && !reelIndicator.reduceMotion && reelIndicator.visible
            paused: spin.running && (reelIndicator.paused || !reelIndicator.motionActive)
        }
        Repeater {
            model: 3
            Rectangle {
                id: hole
                required property int index
                width: 6; height: 9; radius: 3; color: "#a7bca9"
                x: (reel.width - width) / 2; y: 3
                transform: Rotation { origin.x: 3; origin.y: reel.height / 2 - 3; angle: hole.index * 120 }
            }
        }
        Rectangle { width: 4; height: 4; radius: 2; color: "#426454"; anchors.centerIn: parent }
    }
}
