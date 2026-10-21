import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/util.js" as Util

Page {
    id: page
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property var task
    property var selected: ({})
    property bool dirty: false
    signal changed()

    Component.onCompleted: {
        var s = {}
        var ls = task.labels || []
        for (var i = 0; i < ls.length; ++i)
            s[ls[i].id] = true
        selected = s
        app.loadLabels()
    }

    function save() {
        var list = []
        for (var i = 0; i < app.labels.length; ++i)
            if (selected[app.labels[i].id])
                list.push({ id: app.labels[i].id })
        api.request("POST", "/tasks/" + task.id + "/labels/bulk", {}, { labels: list }, function(r) {
            if (r.ok) page.changed(); else app.showError(r)
        })
    }

    onStatusChanged: if (status === PageStatus.Deactivating && dirty) save()

    SilicaListView {
        anchors.fill: parent
        model: app.labels

        header: PageHeader { title: qsTr("Labels") }

        PullDownMenu {
            MenuItem {
                text: qsTr("New label")
                onClicked: {
                    var d = pageStack.push(Qt.resolvedUrl("LabelEditDialog.qml"))
                    d.created.connect(function(label) {
                        var s = page.selected
                        s[label.id] = true
                        page.selected = s
                        page.dirty = true
                        app.loadLabels()
                    })
                }
            }
        }

        delegate: ListItem {
            id: item
            contentHeight: Theme.itemSizeSmall
            TextSwitch {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.title
                checked: page.selected[modelData.id] === true
                onCheckedChanged: {
                    if (checked === (page.selected[modelData.id] === true))
                        return
                    var s = page.selected
                    s[modelData.id] = checked
                    page.selected = s
                    page.dirty = true
                }
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                width: Theme.iconSizeSmall
                height: width
                radius: width / 2
                color: Util.cssColor(modelData.hex_color)
            }
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Delete label")
                    onClicked: {
                        var id = modelData.id
                        item.remorseDelete(function() {
                            api.request("DELETE", "/labels/" + id, {}, null, function(r) {
                                if (r.ok) { app.loadLabels(); page.changed() } else app.showError(r)
                            })
                        })
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: app.labels.length === 0
            text: qsTr("No labels")
            hintText: qsTr("Pull down to create one")
        }
        VerticalScrollDecorator {}
    }
}
