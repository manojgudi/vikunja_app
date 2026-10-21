import QtQuick 2.0
import Sailfish.Silica 1.0

// Asks whether to pin a certificate that failed normal validation.
Dialog {
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground
    property var certificate: ({})

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader { acceptText: qsTr("Trust") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: qsTr("Untrusted certificate")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The certificate of %1 could not be verified. If you run this server with a self-signed certificate, compare the fingerprint below with the one on your server before trusting it. Only this exact certificate will be accepted for this server.").arg(certificate.host)
            }

            DetailItem { label: qsTr("Subject"); value: certificate.subject || "-" }
            DetailItem { label: qsTr("Issuer"); value: certificate.issuer || "-" }
            DetailItem { label: qsTr("Expires"); value: certificate.expires || "-" }
            DetailItem { label: qsTr("Problems"); value: certificate.errors ? certificate.errors.join("\n") : "-" }

            SectionHeader { text: qsTr("SHA-256 fingerprint") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                font.family: "monospace"
                font.pixelSize: Theme.fontSizeSmall
                text: certificate.sha256 || ""
            }
        }
        VerticalScrollDecorator {}
    }
}
