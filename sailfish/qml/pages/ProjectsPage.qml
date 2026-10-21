import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

Page {
    id: page
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property bool showArchived: false
    property var tree: []
    property bool loading: false

    function rebuild() {
        tree = Util.projectTree(app.projects, showArchived)
        model.clear()
        for (var i = 0; i < tree.length; ++i)
            model.append({ idx: i })
    }

    function refresh() {
        loading = true
        app.loadProjects(function(r) {
            loading = false
            if (!r.ok) app.showError(r)
        })
    }

    function editProject(project, parentId) {
        var d = pageStack.push(Qt.resolvedUrl("ProjectEditDialog.qml"), { project: project, parentId: parentId || 0 })
        d.saved.connect(function() { refresh() })
    }

    Component.onCompleted: rebuild()

    Connections {
        target: app
        onProjectRevisionChanged: page.rebuild()
    }

    ListModel { id: model }

    SilicaListView {
        anchors.fill: parent
        model: model

        header: PageHeader { title: qsTr("Projects") }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: page.showArchived ? qsTr("Hide archived") : qsTr("Show archived")
                onClicked: { page.showArchived = !page.showArchived; page.rebuild() }
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.refresh()
            }
            MenuItem {
                text: qsTr("New project")
                onClicked: page.editProject(null, 0)
            }
        }

        delegate: ListItem {
            id: item
            property var entry: page.tree[model.idx]
            property var project: entry ? entry.project : null
            property bool pseudo: project && project.id < 0

            contentHeight: Theme.itemSizeSmall

            Rectangle {
                visible: !!(project && project.hex_color)
                x: Theme.horizontalPageMargin + entry.depth * Theme.paddingLarge * 2 - Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.paddingSmall
                height: parent.height * 0.6
                color: project ? Util.cssColor(project.hex_color) : "transparent"
            }

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin + (entry ? entry.depth : 0) * Theme.paddingLarge * 2
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: project ? (project.title + (project.is_archived ? " " + qsTr("(archived)") : "")) : ""
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : (project && project.is_archived ? Theme.secondaryColor : Theme.primaryColor)
            }

            onClicked: pageStack.push(Qt.resolvedUrl("ProjectPage.qml"), { projectId: project.id })

            menu: ContextMenu {
                enabled: !item.pseudo
                MenuItem {
                    text: qsTr("Edit")
                    onClicked: page.editProject(item.project, item.project.parent_project_id)
                }
                MenuItem {
                    text: qsTr("Add sub-project")
                    onClicked: page.editProject(null, item.project.id)
                }
                MenuItem {
                    text: item.project && item.project.is_archived ? qsTr("Unarchive") : qsTr("Archive")
                    onClicked: {
                        var p = Util.clone(item.project)
                        p.is_archived = !p.is_archived
                        api.request("POST", "/projects/" + p.id, {}, p, function(r) {
                            if (r.ok) page.refresh(); else app.showError(r)
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var id = item.project.id
                        item.remorseDelete(function() {
                            api.request("DELETE", "/projects/" + id, {}, null, function(r) {
                                if (r.ok) page.refresh(); else app.showError(r)
                            })
                        })
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: model.count === 0 && !page.loading
            text: qsTr("No projects")
            hintText: qsTr("Pull down to create one")
        }

        VerticalScrollDecorator {}
    }
}
