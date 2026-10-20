import QtQuick 2.0
import Sailfish.Silica 1.0

// Attachments leave the app's sandbox when saved, so ask first.
Dialog {
    property string fileName
    property int fileSize: 0
    property alias openAfter: openSwitch.checked

    Column {
        width: parent.width
        spacing: Theme.paddingMedium

        DialogHeader { acceptText: qsTr("Save") }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.highlightColor
            text: fileName
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            color: Theme.secondaryHighlightColor
            text: (fileSize > 0 ? Format.formatFileSize(fileSize) + "\n\n" : "")
                  + qsTr("The file will be saved to your Downloads folder, where other apps can read it.")
        }
        TextSwitch {
            id: openSwitch
            text: qsTr("Open after saving")
            checked: true
        }
    }
}
