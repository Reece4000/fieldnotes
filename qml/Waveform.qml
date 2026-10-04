import QtQuick
Canvas {
    id: wave
    property var samples: []
    property bool capturing: false
    property bool paused: false
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
        ctx.strokeStyle = "#dae2d8"; ctx.lineWidth = 1
        ctx.beginPath(); ctx.moveTo(0, height / 2); ctx.lineTo(width, height / 2); ctx.stroke()
        if (!capturing) return
        ctx.strokeStyle = paused ? "#a1afa0" : "#72977a"; ctx.lineWidth = 2.5; ctx.lineCap = "round"
        let count = Math.min(samples.length, Math.floor(width / 5))
        for (let i = 0; i < count; i++) {
            let value = samples[Math.floor(i * samples.length / count)]
            let h = Math.max(2, value * (height - 6))
            let x = i * width / count + 2
            ctx.beginPath(); ctx.moveTo(x, (height - h) / 2); ctx.lineTo(x, (height + h) / 2); ctx.stroke()
        }
    }
}
