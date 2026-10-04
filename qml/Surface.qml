import QtQuick
import QtQuick.Effects
Rectangle {
    id: surface
    color: "#ffffff"; radius: 14; border.color: "#dfe7dc"
    RectangularShadow { anchors.fill: parent; z: -1; radius: surface.radius; blur: 16; offset.y: 5; color: "#12203927" }
}
