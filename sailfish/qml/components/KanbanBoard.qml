import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

// Trello-style board: one column per bucket, side by side. A column is a bit
// narrower than the screen so the next one peeks in; in landscape two or
// more fit. Each column has its own pull-down menu.
SilicaItem {
    id: board

    property Page hostPage
    property int projectId
    property var view
    property var project
    property var buckets: []
    property bool loading: false
    property string errorText: ""
    readonly property alias currentIndex: columns.currentIndex

    signal showListRequested()

    readonly property real columnWidth: {
        var w = width - 2 * Theme.horizontalPageMargin
        var n = Math.max(1, Math.floor(width / (Theme.itemSizeHuge * 2.6)))
        // Leave room for the next column to peek in.
        return Math.floor((w - Theme.paddingLarge * 3) / n)
    }

    function load() {
        loading = true
        api.request("GET", "/projects/" + projectId + "/views/" + view.id + "/tasks", { per_page: 100 }, null, function(r) {
            loading = false
            if (!r.ok) {
                errorText = r.error
                return
            }
            errorText = ""
            var keep = columns.currentIndex
            buckets = r.data || []
            columns.currentIndex = Math.min(Math.max(keep, 0), buckets.length - 1)
        })
    }

    function bucketPath(bucketId) {
        return "/projects/" + projectId + "/views/" + view.id + "/buckets" + (bucketId ? "/" + bucketId : "")
    }

    function moveTask(task, bucketId) {
        var body = { task_id: task.id, bucket_id: bucketId, project_view_id: view.id, project_id: projectId }
        api.request("POST", bucketPath(bucketId) + "/tasks", {}, body, function(r) {
            if (r.ok) {
                app.taskRevision++
                load()
            } else {
                app.showError(r)
            }
        })
    }

    function addBucket() {
        var d = pageStack.push(Qt.resolvedUrl("../pages/TextInputDialog.qml"), { title: qsTr("New bucket"), label: qsTr("Title") })
        d.accepted.connect(function() {
            api.request("PUT", bucketPath(0), {}, { title: d.text }, function(r) {
                if (r.ok) load(); else app.showError(r)
            })
        })
        return d
    }

    function editBucket(bucket, field) {
        var limit = field === "limit"
        var d = pageStack.push(Qt.resolvedUrl("../pages/TextInputDialog.qml"), {
            title: limit ? qsTr("Task limit") : qsTr("Rename bucket"),
            label: limit ? qsTr("Maximum tasks (0 = no limit)") : qsTr("Title"),
            text: limit ? String(bucket.limit || 0) : bucket.title,
            numeric: limit
        })
        d.accepted.connect(function() {
            var b = { id: bucket.id, title: bucket.title, limit: bucket.limit || 0, position: bucket.position, project_view_id: view.id }
            if (limit) b.limit = parseInt(d.text, 10) || 0
            else b.title = d.text
            api.request("POST", bucketPath(bucket.id), {}, b, function(r) {
                if (r.ok) load(); else app.showError(r)
            })
        })
    }

    function deleteBucket(bucket) {
        Remorse.popupAction(hostPage, qsTr("Deleting bucket"), function() {
            api.request("DELETE", bucketPath(bucket.id), {}, null, function(r) {
                if (r.ok) load(); else app.showError(r)
            })
        })
    }

    Component.onCompleted: load()

    Connections {
        target: app
        onTaskRevisionChanged: board.load()
    }

    PageHeader {
        id: header
        title: board.project ? board.project.title : ""
        description: board.buckets.length > 0
                     ? qsTr("Board · %1 of %2").arg(columns.currentIndex + 1).arg(board.buckets.length)
                     : qsTr("Board")
    }

    SilicaListView {
        id: columns
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        orientation: ListView.Horizontal
        snapMode: ListView.SnapToItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: Theme.horizontalPageMargin
        preferredHighlightEnd: Theme.horizontalPageMargin + board.columnWidth
        boundsBehavior: Flickable.StopAtBounds
        spacing: Theme.paddingLarge
        model: board.buckets
        clip: true
        header: Item { width: Theme.horizontalPageMargin; height: 1 }
        footer: Item { width: Theme.horizontalPageMargin; height: 1 }

        delegate: Item {
            id: columnItem
            property var bucket: modelData
            property int bucketIndex: index
            width: board.columnWidth
            height: columns.height

            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: Theme.paddingMedium
                radius: Theme.paddingMedium
                color: Theme.rgba(board.palette.highlightBackgroundColor, 0.12)
            }

            SilicaListView {
                id: column
                anchors.fill: parent
                anchors.bottomMargin: Theme.paddingMedium
                clip: true
                model: columnItem.bucket.tasks || []

                header: Item {
                    width: column.width
                    height: Theme.itemSizeSmall
                    Label {
                        id: bucketTitle
                        anchors { left: parent.left; leftMargin: Theme.paddingLarge; right: countLabel.left; rightMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                        text: columnItem.bucket.title
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeMedium
                        color: board.palette.highlightColor
                    }
                    Label {
                        id: countLabel
                        anchors { right: parent.right; rightMargin: Theme.paddingLarge; verticalCenter: parent.verticalCenter }
                        text: columnItem.bucket.limit > 0 ? qsTr("%1/%2").arg(column.count).arg(columnItem.bucket.limit) : String(column.count)
                        font.pixelSize: Theme.fontSizeSmall
                        color: columnItem.bucket.limit > 0 && column.count >= columnItem.bucket.limit
                               ? board.palette.errorColor : board.palette.secondaryHighlightColor
                    }
                }

                PullDownMenu {
                    busy: board.loading
                    MenuItem { text: qsTr("Delete bucket"); onClicked: board.deleteBucket(columnItem.bucket) }
                    MenuItem { text: qsTr("Set task limit"); onClicked: board.editBucket(columnItem.bucket, "limit") }
                    MenuItem { text: qsTr("Rename bucket"); onClicked: board.editBucket(columnItem.bucket, "title") }
                    MenuItem { text: qsTr("New bucket"); onClicked: board.addBucket() }
                    MenuItem { text: qsTr("Show as list"); onClicked: board.showListRequested() }
                    MenuItem { text: qsTr("Refresh"); onClicked: board.load() }
                    MenuItem { text: qsTr("New task here"); onClicked: app.openAddTask(board.projectId, columnItem.bucket.id) }
                }

                delegate: TaskListItem {
                    id: taskItem
                    width: column.width
                    task: modelData
                    onClicked: app.openTask(task.id)
                    onToggleDone: app.setTaskDone(task, !task.done)
                    menu: ContextMenu {
                        MenuItem {
                            visible: columnItem.bucketIndex > 0
                            text: qsTr("Move to “%1”").arg(columnItem.bucketIndex > 0 ? board.buckets[columnItem.bucketIndex - 1].title : "")
                            onClicked: board.moveTask(taskItem.task, board.buckets[columnItem.bucketIndex - 1].id)
                        }
                        MenuItem {
                            visible: columnItem.bucketIndex < board.buckets.length - 1
                            text: qsTr("Move to “%1”").arg(columnItem.bucketIndex < board.buckets.length - 1 ? board.buckets[columnItem.bucketIndex + 1].title : "")
                            onClicked: board.moveTask(taskItem.task, board.buckets[columnItem.bucketIndex + 1].id)
                        }
                        MenuItem {
                            text: qsTr("Move to…")
                            onClicked: {
                                var p = pageStack.push(Qt.resolvedUrl("../pages/BucketPickerPage.qml"), { buckets: board.buckets, currentId: columnItem.bucket.id })
                                p.picked.connect(function(id) { board.moveTask(taskItem.task, id) })
                            }
                        }
                    }
                }

                footer: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
                    onClicked: app.openAddTask(board.projectId, columnItem.bucket.id)
                    Label {
                        anchors { left: parent.left; leftMargin: Theme.paddingLarge; verticalCenter: parent.verticalCenter }
                        text: qsTr("+ Add task")
                        color: parent.highlighted ? board.palette.highlightColor : board.palette.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                VerticalScrollDecorator {}
            }
        }

        ViewPlaceholder {
            enabled: board.buckets.length === 0 && !board.loading
            text: board.errorText.length > 0 ? qsTr("Could not load the board") : qsTr("No buckets")
            hintText: board.errorText
        }
        HorizontalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: board.loading && board.buckets.length === 0
    }
}
