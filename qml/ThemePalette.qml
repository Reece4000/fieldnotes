import QtQuick

// The current theme's colours, one shared instance (see Theme.js). The themes are
// TapeTop's device themes, so the instruments share one vocabulary. Each colour keeps
// one meaning: accent is the cursor, track4 (amber) work still to do, track2 (magenta)
// a failure, record recording only, readout the clock only.
QtObject {
    id: palette
    property string themeId: "instrument-light"
    readonly property var themes: [
        { id: "instrument-light", name: "instrument light", appearance: "light", ground: "#e9eaed", panel: "#d8dade", cell: "#cdd0d5", ink: "#111216", muted: "#5c616b", dim: "#8f949c", band: "#1c1e22", bandInk: "#eceef2", bandKey: "#2c2f35", bandMuted: "#8a8f98", accent: "#0b7f86", onAccent: "#ffffff", record: "#d23a2f", readout: "#111216", track2: "#c2185b", track4: "#b86a00" },
        { id: "paper", name: "paper", appearance: "light", ground: "#f3efe6", panel: "#e3ded1", cell: "#d5cfbf", ink: "#1c1a16", muted: "#5f5a4f", dim: "#9a9485", band: "#23211d", bandInk: "#f3efe6", bandKey: "#37342e", bandMuted: "#8f897c", accent: "#2457d6", onAccent: "#ffffff", record: "#c8372c", readout: "#1c1a16", track2: "#c23b6e", track4: "#b5651d" },
        { id: "studio", name: "studio", appearance: "light", ground: "#f7f8fa", panel: "#e5e8ed", cell: "#d6dae1", ink: "#0d0f14", muted: "#535a67", dim: "#959bab", band: "#0d0f14", bandInk: "#f7f8fa", bandKey: "#272b34", bandMuted: "#858b98", accent: "#b2237e", onAccent: "#ffffff", record: "#cf332b", readout: "#0d0f14", track2: "#1f6fd1", track4: "#c46a12" },
        { id: "sand", name: "sand", appearance: "light", ground: "#ece4d4", panel: "#dad0bc", cell: "#cbc0a9", ink: "#2a2117", muted: "#5c4f3f", dim: "#a3967f", band: "#3a3024", bandInk: "#f1e9da", bandKey: "#4c4031", bandMuted: "#a89a82", accent: "#9e4813", onAccent: "#ffffff", record: "#b3261e", readout: "#2a2117", track2: "#2f6b78", track4: "#7a5a9a" },
        { id: "instrument", name: "instrument", appearance: "dark", ground: "#0c0d10", panel: "#16181c", cell: "#1f2227", ink: "#eceef2", muted: "#7d838f", dim: "#4a4f58", band: "#c6c8ce", bandInk: "#111216", bandKey: "#aeb1b8", bandMuted: "#4d5159", accent: "#34c6cc", onAccent: "#0c0d10", record: "#e5483d", readout: "#e8fa42", track2: "#f2477f", track4: "#f0a33a" },
        { id: "graphite", name: "graphite", appearance: "dark", ground: "#121110", panel: "#1d1b19", cell: "#272521", ink: "#ede9e1", muted: "#8c867b", dim: "#524d45", band: "#dad4c8", bandInk: "#141311", bandKey: "#c3bdb0", bandMuted: "#5c574e", accent: "#e9a43b", onAccent: "#141311", record: "#e4523f", readout: "#f2b54a", track2: "#e0675a", track4: "#6fb8a6" },
        { id: "night", name: "night", appearance: "dark", ground: "#0b0d14", panel: "#151926", cell: "#1e2334", ink: "#e6e9f5", muted: "#7c84a2", dim: "#464d68", band: "#cad0e8", bandInk: "#0f1220", bandKey: "#b1b8d6", bandMuted: "#4d5472", accent: "#8291ff", onAccent: "#0b0d14", record: "#ff5d6c", readout: "#a9b6ff", track2: "#e66fc4", track4: "#e8b65a" },
        { id: "carbon", name: "carbon", appearance: "dark", ground: "#000000", panel: "#101010", cell: "#1a1a1a", ink: "#f4f4f4", muted: "#8a8a8a", dim: "#474747", band: "#f4f4f4", bandInk: "#000000", bandKey: "#d6d6d6", bandMuted: "#6b6b6b", accent: "#ff7a1a", onAccent: "#000000", record: "#ff3b30", readout: "#ff7a1a", track2: "#2fb8ff", track4: "#ffd23a" },
        { id: "lodo", name: "lodo", appearance: "dark", ground: "#044a4c", panel: "#055b5b", cell: "#076a6b", ink: "#e8f7f4", muted: "#93c6c2", dim: "#458685", band: "#c3dcd9", bandInk: "#04393b", bandKey: "#a8c7c4", bandMuted: "#3d6462", accent: "#ffd75b", onAccent: "#04393b", record: "#ff7366", readout: "#c2f5ee", track2: "#ff8fa3", track4: "#ffb04a" }
    ]
    readonly property var current: themes.find(t => t.id === themeId) || themes[0]
    readonly property string appearance: current.appearance
    readonly property bool light: appearance === "light"
    readonly property color ground: current.ground
    readonly property color panel: current.panel
    readonly property color cell: current.cell
    readonly property color ink: current.ink
    readonly property color muted: current.muted
    readonly property color dim: current.dim
    readonly property color band: current.band
    readonly property color bandInk: current.bandInk
    readonly property color bandKey: current.bandKey
    readonly property color bandMuted: current.bandMuted
    readonly property color bandDot: Qt.rgba(bandMuted.r, bandMuted.g, bandMuted.b, .4)
    readonly property color accent: current.accent
    readonly property color floodInk: current.onAccent
    readonly property color amber: current.track4
    readonly property color magenta: current.track2
    readonly property color record: current.record
    readonly property color readout: current.readout
    // The readout window is the ground: dark on a silver band, light on a dark one.
    readonly property color chip: current.ground
}
