import QtQuick 2.0
import Sailfish.Silica 1.0

// Asked once when Sailfish Secrets refuses the token: may it be kept in a
// private file instead? Accept allows it, going back declines.
Dialog {
    id: dialog
    objectName: "storageChoiceDialog"
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    onAccepted: api.setFileFallback(true)
    onRejected: api.setFileFallback(false)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Keep me signed in")
                cancelText: qsTr("Don't")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: qsTr("Secure storage refused the sign-in")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Sailfish Secrets did not accept this app's access token, so it is only kept in memory and you would have to sign in again every time the app starts.\n\nThe app can instead keep the token in a file in its private folder. Other sandboxed apps cannot see that folder, but the file is not encrypted: apps that run without the sandbox, or anyone with developer mode or root, could read it.\n\nThe token only gives access to your tasks, projects, labels, comments and attachments, and you can delete it any time in the Vikunja web app under Settings, API Tokens. You can change this choice later in Settings.")
            }
        }
        VerticalScrollDecorator {}
    }
}
