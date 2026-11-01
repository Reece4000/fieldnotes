pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "Theme.js" as T

// A square field: the value in mono and a chevron. The menu is mono too; the option
// under the cursor inverts.
ComboBox {
    id: control
    property bool onBand: false
    readonly property bool focusFlood: control.visualFocus
    implicitHeight: 28
    implicitWidth: 180
    leftPadding: 10
    rightPadding: 26
    font.family: T.mono; font.pixelSize: T.value
    hoverEnabled: true
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.focusFlood ? T.p.floodInk : !control.enabled ? (control.onBand ? T.p.bandMuted : T.p.muted) : control.onBand ? T.p.bandInk : T.p.ink
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - 20; y: (control.height - height) / 2
        visible: control.enabled
        text: "⌄"; font.family: T.mono; font.pixelSize: 13
        color: control.focusFlood ? T.p.floodInk : control.onBand ? T.p.bandMuted : T.p.muted
    }
    background: Rectangle {
        color: control.focusFlood ? T.p.accent
             : control.onBand ? (control.enabled ? (control.hovered || control.popup.visible ? T.alpha(T.p.bandInk, .14) : T.p.bandKey) : "transparent")
             : control.enabled ? (control.hovered || control.popup.visible ? T.p.dim : T.p.cell) : "transparent"
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: control.popup.width - control.popup.leftPadding - control.popup.rightPadding
        height: 28
        leftPadding: 10; rightPadding: 10
        hoverEnabled: true
        Accessible.role: Accessible.MenuItem
        Accessible.name: control.textRole ? modelData[control.textRole] : modelData
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: control.textRole ? option.modelData[control.textRole] : option.modelData
            color: option.highlighted || option.hovered ? T.p.floodInk : control.currentIndex === option.index ? T.p.ink : T.p.muted
            font.family: T.mono; font.pixelSize: T.value; elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { color: option.highlighted || option.hovered ? T.p.ink : "transparent" }
    }
    popup: Popup {
        y: control.height
        width: Math.max(control.width, 200)
        implicitHeight: Math.min(300, menuList.contentHeight + topPadding + bottomPadding)
        padding: 4
        margins: 12
        background: Rectangle { color: T.p.cell }
        contentItem: ListView {
            id: menuList
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            boundsMovement: Flickable.StopAtBounds
            ScrollBar.vertical: FieldScrollBar { }
        }
    }
}
