import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    property string url
    Column {
        width: parent.width
        spacing: Theme.paddingLarge
        DialogHeader { acceptText: qsTr("Open") }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.WrapAnywhere
            text: qsTr("Open this link in the browser?") + "\n\n" + url
        }
    }
}
