import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/util.js" as Util

Page {
    id: page

    property int projectId
    property var view
    property var project
    property var buckets: []
    property bool loading: false
    property string errorText: ""

    allowedOrientations: Orientation.All

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
        var d = pageStack.push(Qt.resolvedUrl("TextInputDialog.qml"), { title: qsTr("New bucket"), label: qsTr("Title") })
        d.accepted.connect(function() {
            api.request("PUT", bucketPath(0), {}, { title: d.text }, function(r) {
                if (r.ok) load(); else app.showError(r)
            })
        })
    }

    function editBucket(bucket, field) {
        var limit = field === "limit"
        var d = pageStack.push(Qt.resolvedUrl("TextInputDialog.qml"), {
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
        Remorse.popupAction(page, qsTr("Deleting bucket"), function() {
            api.request("DELETE", bucketPath(bucket.id), {}, null, function(r) {
                if (r.ok) load(); else app.showError(r)
            })
        })
    }

    Component.onCompleted: load()

    Connections {
        target: app
        onTaskChanged: page.load()
    }

    SilicaListView {
        id: columns
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        model: page.buckets
        clip: true

        delegate: SilicaListView {
            id: column
            property var bucket: modelData
            property int bucketIndex: index
            width: columns.width
            height: columns.height
            model: bucket.tasks || []

            header: PageHeader {
                title: column.bucket.title
                description: (page.project ? page.project.title + " · " : "")
                             + (column.bucket.limit > 0 ? qsTr("%1 of %2 tasks").arg(column.count).arg(column.bucket.limit)
                                                        : qsTr("%n task(s)", "", column.count))
                             + "  " + (column.bucketIndex + 1) + "/" + page.buckets.length
            }

            PullDownMenu {
                busy: page.loading
                MenuItem { text: qsTr("Delete bucket"); onClicked: page.deleteBucket(column.bucket) }
                MenuItem { text: qsTr("Set task limit"); onClicked: page.editBucket(column.bucket, "limit") }
                MenuItem { text: qsTr("Rename bucket"); onClicked: page.editBucket(column.bucket, "title") }
                MenuItem { text: qsTr("New bucket"); onClicked: page.addBucket() }
                MenuItem { text: qsTr("Refresh"); onClicked: page.load() }
                MenuItem { text: qsTr("New task here"); onClicked: app.openAddTask(page.projectId, column.bucket.id) }
            }

            delegate: TaskListItem {
                id: taskItem
                task: modelData
                onClicked: app.openTask(task.id)
                onToggleDone: app.setTaskDone(task, !task.done)
                menu: ContextMenu {
                    MenuItem {
                        visible: column.bucketIndex > 0
                        text: qsTr("Move to “%1”").arg(column.bucketIndex > 0 ? page.buckets[column.bucketIndex - 1].title : "")
                        onClicked: page.moveTask(taskItem.task, page.buckets[column.bucketIndex - 1].id)
                    }
                    MenuItem {
                        visible: column.bucketIndex < page.buckets.length - 1
                        text: qsTr("Move to “%1”").arg(column.bucketIndex < page.buckets.length - 1 ? page.buckets[column.bucketIndex + 1].title : "")
                        onClicked: page.moveTask(taskItem.task, page.buckets[column.bucketIndex + 1].id)
                    }
                    MenuItem {
                        text: qsTr("Move to…")
                        onClicked: {
                            var p = pageStack.push(Qt.resolvedUrl("BucketPickerPage.qml"), { buckets: page.buckets, currentId: column.bucket.id })
                            p.picked.connect(function(id) { page.moveTask(taskItem.task, id) })
                        }
                    }
                }
            }

            ViewPlaceholder {
                enabled: column.count === 0
                text: qsTr("Empty bucket")
                hintText: qsTr("Swipe sideways for other buckets")
            }
            VerticalScrollDecorator {}
        }

        ViewPlaceholder {
            enabled: page.buckets.length === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Could not load the board") : qsTr("No buckets")
            hintText: page.errorText
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading && page.buckets.length === 0
    }
}
