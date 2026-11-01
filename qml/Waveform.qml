import QtQuick
import "Theme.js" as T

// The live microphone, drawn on the band: one square bar per sample on a faint dot grid.
Canvas {
    id: wave
    property var samples: []
    property bool capturing: false
    property bool paused: false
    property color lineColour: T.bandInk
    property color quietColour: T.bandMuted
    property color gridColour: T.bandDot
    onSamplesChanged: requestPaint()
    onCapturingChanged: requestPaint()
    onPausedChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Accessible.role: Accessible.Indicator
    Accessible.name: "Live microphone waveform"
    onPaint: {
        let ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = gridColour
        for (let y = 0; y <= height; y += 8) for (let x = 0; x <= width; x += 8) ctx.fillRect(Math.floor(x), Math.floor(y), 1, 1)
        let mid = Math.round(height / 2)
        ctx.fillStyle = quietColour
        ctx.fillRect(0, mid, width, 1)
        if (!capturing || !samples || !samples.length) return
        ctx.fillStyle = paused ? quietColour : lineColour
        let count = Math.min(samples.length, Math.floor(width / 4))
        for (let i = 0; i < count; i++) {
            let value = samples[Math.floor(i * samples.length / count)]
            let h = Math.max(1, Math.round(value * height))
            ctx.fillRect(Math.round(i * width / count), mid - Math.floor(h / 2), 2, h)
        }
    }
}
