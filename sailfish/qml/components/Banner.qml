import QtQuick 2.0
import Sailfish.Silica 1.0

// Short in-app message shown at the top of the screen.
MouseArea {
    id: banner

    property alias text: label.text

    function show(message) {
        label.text = message
        opacity = 1
        hideTimer.restart()
    }

    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: label.height + 2 * Theme.paddingLarge
    z: 1000
    opacity: 0
    visible: opacity > 0
    onClicked: opacity = 0

    Behavior on opacity { FadeAnimator {} }

    Rectangle {
        anchors.fill: parent
        color: Theme.highlightDimmerColor
        opacity: 0.95
    }

    Label {
        id: label
        anchors {
            left: parent.left; right: parent.right
            leftMargin: Theme.horizontalPageMargin; rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        wrapMode: Text.Wrap
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Timer {
        id: hideTimer
        interval: 4000
        onTriggered: banner.opacity = 0
    }
}
