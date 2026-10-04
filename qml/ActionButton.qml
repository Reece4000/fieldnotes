import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string glyph: ""
    property bool primary: false
    property bool quiet: false
    property color accent: "#b44530"
    implicitHeight: 36
    implicitWidth: Math.max(36, Math.ceil(labelMetrics.advanceWidth) + 30 + (glyph ? 26 : 0))
    padding: 12
    topPadding: Math.max(2, (height - font.pixelSize - 6) / 2)
    bottomPadding: topPadding
    hoverEnabled: true
    font.pixelSize: 13
    Accessible.name: text
    TextMetrics { id: labelMetrics; text: control.text; font: control.font }
    contentItem: Item {
        FieldIcon { visible: !!control.glyph; name: control.glyph; width: 18; height: 18; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; tint: !control.enabled ? "#979b91" : control.primary ? "#fffaf2" : "#36574a" }
        Text {
            anchors.fill: parent; anchors.leftMargin: control.glyph ? 26 : 0
            text: control.text; font: control.font
            color: !control.enabled ? "#979b91" : control.primary ? "#fffaf2" : "#293e35"
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 7
        color: control.primary ? (control.down ? Qt.darker(control.accent, 1.2) : control.accent)
              : control.down ? "#d9ddd0" : control.hovered ? "#e6e8de" : control.quiet ? "transparent" : "#f8faf6"
        border.width: control.activeFocus ? 2 : control.quiet || control.primary ? 0 : 1
        border.color: control.activeFocus ? "#55784c" : "#d4d9cc"
        opacity: control.enabled ? 1 : 0.55
    }
}
