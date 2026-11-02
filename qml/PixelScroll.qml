import QtQuick

// macOS supplies trackpad movement and momentum as pixel deltas. Preserve those
// deltas directly, with a three-line step for conventional mouse wheels.
WheelHandler {
    required property Flickable viewport
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        const delta = event.pixelDelta.y || event.angleDelta.y / 120 * 60
        if (!delta) { event.accepted = false; return }
        viewport.cancelFlick()
        const bottom = viewport.originY + Math.max(0, viewport.contentHeight - viewport.height)
        viewport.contentY = Math.max(viewport.originY, Math.min(bottom, viewport.contentY - delta))
        event.accepted = true
    }
}
