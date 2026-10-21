import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

// Row of preset colors; the first entry means "no color".
Flow {
    id: row

    property string selected: ""
    signal picked(string hex)

    x: Theme.horizontalPageMargin
    width: parent.width - 2 * Theme.horizontalPageMargin
    spacing: Theme.paddingMedium

    Repeater {
        model: Util.colors
        MouseArea {
            width: Theme.itemSizeExtraSmall
            height: width
            onClicked: row.picked(modelData)
            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall
                radius: width / 2
                color: modelData ? Util.cssColor(modelData) : "transparent"
                border.width: (row.selected || "") === modelData ? Theme.paddingSmall : 1
                border.color: (row.selected || "") === modelData ? Theme.highlightColor : Theme.secondaryColor
            }
            Label {
                visible: !modelData
                anchors.centerIn: parent
                text: "∅"
                color: Theme.secondaryColor
            }
        }
    }
}
