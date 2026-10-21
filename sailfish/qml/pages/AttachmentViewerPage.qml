import QtQuick 2.0
import Sailfish.Silica 1.0

// Shows an image attachment from memory (image://attachment/...), so looking
// at it leaves nothing on the phone. Saving it is a separate, explicit step.
Page {
    id: page
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property int taskId
    property var attachment
    property string source: ""
    property string errorText: ""

    signal saveRequested()

    allowedOrientations: Orientation.All

    Component.onCompleted: {
        api.previewAttachment(taskId, attachment.id, function(r) {
            if (r.ok) source = r.data
            else errorText = r.error
        })
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: Math.max(width, image.width * image.scale)
        contentHeight: Math.max(height, image.height * image.scale)

        PullDownMenu {
            MenuItem {
                text: qsTr("Save to Downloads")
                onClicked: page.saveRequested()
            }
        }

        Image {
            id: image
            anchors.centerIn: parent
            width: flick.width
            height: flick.height
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: page.source
            sourceSize.width: 2048
            sourceSize.height: 2048
            cache: false
        }

        PinchArea {
            anchors.fill: parent
            pinch.target: image
            pinch.minimumScale: 1
            pinch.maximumScale: 6
        }
    }

    PageHeader {
        title: page.attachment ? page.attachment.file.name : ""
        visible: image.status !== Image.Ready
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.source.length === 0 && page.errorText.length === 0
    }

    ViewPlaceholder {
        enabled: page.errorText.length > 0 || image.status === Image.Error
        text: qsTr("Could not show the image")
        hintText: page.errorText
    }
}
