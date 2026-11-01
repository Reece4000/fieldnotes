.pragma library
// Instrument modernism. A near-black field above, a silver band below; colour only
// where it carries meaning, one meaning each:
//   accent (turquoise)  where the cursor is: the focused container floods, the current cell inverts
//   amber               transcription work still to do (pending audio, the model loading)
//   magenta             something failed and needs you (needs retry, errors, clipping)
//   record (red)        recording, and nothing else
//   readout             the clock, and nothing else
// Everything else is greyscale. Every shape is square.

var ground = "#0c0d10"
var panel = "#16181c"
var cell = "#1f2227"
var ink = "#eceef2"
var muted = "#7d838f"
var dim = "#4a4f58"

var band = "#c6c8ce"
var bandInk = "#111216"
var bandMuted = "#4d5159"
var bandKey = "#aeb1b8"
var bandDot = "#a4a7af"
var chip = "#121418"

var accent = "#34c6cc"
var magenta = "#f2477f"
var amber = "#f0a33a"
var record = "#e5483d"
var readout = "#e8fa42"
var floodInk = "#0c0d10"

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
function pad(n) { return n < 10 ? "0" + n : String(n) }
// A note's state, as a word and its colour: amber is work still to do, magenta needs you.
function noteState(note) {
    if (!note) return { text: "", color: muted }
    if (note.errors) return { text: "needs retry", color: magenta }
    if (note.status === "recording") return { text: "recording", color: record }
    if (note.status === "paused") return { text: "paused", color: record }
    if (note.pending) return { text: "transcribing", color: amber }
    return { text: "", color: muted }
}
function date(seconds) { return Qt.formatDateTime(new Date(seconds * 1000), "dd MMM HH:mm").toLowerCase() }
