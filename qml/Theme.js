.pragma library
// Instrument modernism. A field above, a band below; colour only where it carries
// meaning. The colours live in one shared ThemePalette (`T.p.ink`, `T.p.accent`…), so
// every binding follows a theme change. Every shape is square.

var p = Qt.createComponent(Qt.resolvedUrl("ThemePalette.qml")).createObject(null)

var sans = "Geist"
var mono = "Geist Mono"
var segment = "DSEG14 Modern"

// Sizes in pixels. Section titles are large and muted; the current one is ink.
var section = 26
var label = 14
var value = 12
var small = 11

function alpha(color, a) { var c = Qt.color(color); return Qt.rgba(c.r, c.g, c.b, a) }
function lower(s) { return s ? String(s).toLowerCase() : "" }
// A note's state as a word and its colour: amber is work still to do, magenta needs you,
// red is recording.
function noteState(note) {
    if (!note) return { text: "", color: p.muted, recording: false }
    if (note.errors) return { text: "needs retry", color: p.magenta, recording: false }
    if (note.status === "recording") return { text: "recording", color: p.record, recording: true }
    if (note.status === "paused") return { text: "paused", color: p.record, recording: true }
    if (note.pending) return { text: "transcribing", color: p.amber, recording: false }
    return { text: "", color: p.muted, recording: false }
}
function date(seconds) { return Qt.formatDateTime(new Date(seconds * 1000), "dd MMM HH:mm").toLowerCase() }
