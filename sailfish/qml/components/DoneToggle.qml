import QtQuick 2.0
import Sailfish.Silica 1.0

// Round "mark as done" button used in task lists.
MouseArea {
    id: toggle

    property bool checked

    width: Theme.itemSizeSmall
    height: Theme.itemSizeSmall

    Rectangle {
        anchors.centerIn: parent
        width: Theme.iconSizeSmallPlus
        height: width
        radius: width / 2
        color: toggle.checked ? Theme.rgba(Theme.highlightBackgroundColor, 0.6) : "transparent"
        border.width: Math.max(2, Theme.paddingSmall / 3)
        border.color: toggle.pressed ? Theme.highlightColor : Theme.secondaryColor
    }

    Image {
        anchors.centerIn: parent
        visible: toggle.checked
        source: "image://theme/icon-s-accept?" + Theme.primaryColor
    }
}
