import QtQuick

// Copies the transcript; the word itself confirms, so nothing needs an icon.
ActionButton {
    id: control
    property bool confirmed: false
    property bool reduceMotion: false
    property bool compact: false
    function confirm() { confirmed = true; reset.restart() }
    text: confirmed ? "Copied" : "Copy"
    quiet: compact
    Accessible.name: confirmed ? "Transcript copied" : "Copy transcript"
    Timer { id: reset; interval: 1800; onTriggered: control.confirmed = false }
}
