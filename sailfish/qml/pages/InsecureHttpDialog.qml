import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground
    property string host

    Column {
        width: parent.width
        spacing: Theme.paddingLarge

        DialogHeader { acceptText: qsTr("Allow") }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.highlightColor
            text: qsTr("Unencrypted connection")
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            text: qsTr("%1 uses plain HTTP: your password, token and tasks travel unencrypted, so others on the network could read or change them.\n\nOnly allow this on a network you trust. HTTPS (even self-signed) is much safer.").arg(host)
        }
    }
}
