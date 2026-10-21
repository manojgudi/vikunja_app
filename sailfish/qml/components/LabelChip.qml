import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

Rectangle {
    property var label

    radius: Theme.paddingSmall
    height: chipText.height + Theme.paddingSmall
    width: chipText.width + 2 * Theme.paddingMedium
    color: label && label.hex_color ? Util.cssColor(label.hex_color) : Theme.rgba(Theme.highlightBackgroundColor, 0.3)

    Label {
        id: chipText
        anchors.centerIn: parent
        text: label ? label.title : ""
        font.pixelSize: Theme.fontSizeExtraSmall
        color: "white"
    }
}
