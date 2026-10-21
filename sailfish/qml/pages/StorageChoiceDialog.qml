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
                text: qsTr("Secure storage unavailable")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Sailfish Secrets refused the token, so you would have to sign in at every start.\n\nThe app can keep it in a private file instead. Other apps can't open that file, but it isn't encrypted: root or developer mode could read it.\n\nYou can change this later in Settings.")
            }
        }
        VerticalScrollDecorator {}
    }
}
