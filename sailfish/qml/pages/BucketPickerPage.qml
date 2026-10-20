import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    property var buckets: []
    property int currentId: 0
    signal picked(int bucketId)

    SilicaListView {
        anchors.fill: parent
        model: page.buckets
        header: PageHeader { title: qsTr("Move to bucket") }
        delegate: ListItem {
            enabled: modelData.id !== page.currentId
            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.title
                color: modelData.id === page.currentId ? Theme.secondaryColor : (highlighted ? Theme.highlightColor : Theme.primaryColor)
            }
            onClicked: {
                page.picked(modelData.id)
                pageStack.pop()
            }
        }
    }
}
