pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
ComboBox {
    id: control
    property string glyph: ""
    implicitHeight: 36
    implicitWidth: 180
    leftPadding: glyph ? 38 : 12
    rightPadding: 30
    font.pixelSize: 12
    hoverEnabled: true
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled ? "#293d2b" : "#92988d"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    FieldIcon { visible: !!control.glyph; name: control.glyph; width: 19; height: 19; x: 12; anchors.verticalCenter: parent.verticalCenter; tint: control.enabled ? "#426354" : "#939f96" }
    indicator: Text { x: control.width - 23; y: (control.height - height) / 2; text: "⌄"; font.pixelSize: 17; color: "#5c7252" }
    background: Rectangle {
        color: !control.enabled ? "#f0f2e9" : control.hovered ? "#e3eadb" : "#f9fbf7"
        radius: 7; border.color: control.activeFocus ? "#55784c" : "#d0d9c6"
        border.width: control.activeFocus ? 2 : 1
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: control.popup.width - 12
        height: 34
        hoverEnabled: true
        Accessible.role: Accessible.MenuItem
        Accessible.name: control.textRole ? modelData[control.textRole] : modelData
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: control.textRole ? option.modelData[control.textRole] : option.modelData
            color: "#293d2b"; font.pixelSize: 12; elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            font.weight: control.currentIndex === option.index ? Font.DemiBold : Font.Normal
        }
        background: Rectangle { radius: 4; color: option.highlighted || option.hovered ? "#dfe8d5" : "transparent" }
    }
    popup: Popup {
        y: control.height + 4
        width: Math.max(control.width, 200)
        implicitHeight: Math.min(270, menuList.contentHeight + 12)
        padding: 6
        margins: 12
        background: Rectangle { color: "#fbfcf7"; radius: 7; border.color: "#c8d2be" }
        contentItem: ListView {
            id: menuList
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            boundsMovement: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
        }
    }
}
