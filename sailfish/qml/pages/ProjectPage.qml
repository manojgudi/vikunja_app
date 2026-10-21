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

    property int projectId
    property var project: app.projectById(projectId)
    property var listView: null
    property var kanbanView: null
    property var tasks: []
    property bool loading: false
    property string errorText: ""
    property bool showDone: api.setting("showDone/" + projectId, false) === true || api.setting("showDone/" + projectId, false) === "true"
    property int currentPage: 1
    property int totalPages: 1
    // Projects with a kanban view open as a board unless the list was chosen.
    property string layout: String(api.setting("layout/" + projectId, "board"))
    readonly property bool boardMode: kanbanView !== null && layout !== "list"
    property alias board: boardLoader.item

    allowedOrientations: Orientation.All

    function setLayout(value) {
        layout = value
        api.setSetting("layout/" + projectId, value)
        if (value === "list") {
            currentPage = 1
            loadTasks(false)
        }
    }

    function loadProject() {
        loading = true
        api.request("GET", "/projects/" + projectId, {}, null, function(r) {
            if (!r.ok) {
                loading = false
                errorText = r.error
                return
            }
            project = r.data
            var views = (r.data.views || []).slice().sort(function(a, b) { return a.position - b.position })
            listView = null
            kanbanView = null
            for (var i = 0; i < views.length; ++i) {
                var k = views[i].view_kind
                if (!listView && (k === "list" || k === "table"))
                    listView = views[i]
                if (!kanbanView && k === "kanban")
                    kanbanView = views[i]
            }
            currentPage = 1
            if (boardMode)
                loading = false
            else
                loadTasks(false)
        })
    }

    function loadTasks(append) {
        loading = true
        var query = { page: currentPage, per_page: 50 }
        var path
        // A view's own filter (usually "done = false") is combined with any
        // filter we pass, so done tasks are fetched through /tasks instead.
        if (listView && !showDone) {
            path = "/projects/" + projectId + "/views/" + listView.id + "/tasks"
        } else {
            path = "/tasks"
            query.filter = "project = " + projectId + (showDone ? "" : " && done = false")
            query.sort_by = ["done", "id"]
            query.order_by = ["asc", "desc"]
        }
        api.request("GET", path, query, null, function(r) {
            loading = false
            if (!r.ok) {
                errorText = r.error
                return
            }
            errorText = ""
            totalPages = r.totalPages || 1
            tasks = append ? tasks.concat(r.data || []) : (r.data || [])
            model.clear()
            for (var i = 0; i < tasks.length; ++i)
                model.append({ idx: i })
        })
    }

    Component.onCompleted: loadProject()

    Connections {
        target: app
        onTaskRevisionChanged: if (!page.boardMode) { page.currentPage = 1; page.loadTasks(false) }
    }

    ListModel { id: model }

    Loader {
        id: boardLoader
        anchors.fill: parent
        active: page.boardMode
        sourceComponent: KanbanBoard {
            hostPage: page
            projectId: page.projectId
            view: page.kanbanView
            project: page.project
            onShowListRequested: page.setLayout("list")
        }
    }

    SilicaListView {
        anchors.fill: parent
        model: model
        visible: !page.boardMode

        header: PageHeader {
            title: page.project ? page.project.title : ""
            description: page.listView ? page.listView.title : ""
        }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.kanbanView !== null
                text: qsTr("Show as board")
                onClicked: page.setLayout("board")
            }
            MenuItem {
                text: page.showDone ? qsTr("Hide done tasks") : qsTr("Show done tasks")
                onClicked: {
                    page.showDone = !page.showDone
                    api.setSetting("showDone/" + page.projectId, page.showDone)
                    page.currentPage = 1
                    page.loadTasks(false)
                }
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.loadProject()
            }
            MenuItem {
                visible: page.projectId > 0
                text: qsTr("New task")
                onClicked: app.openAddTask(page.projectId)
            }
        }

        PushUpMenu {
            visible: page.currentPage < page.totalPages
            MenuItem {
                text: qsTr("Load more")
                onClicked: { page.currentPage++; page.loadTasks(true) }
            }
        }

        delegate: TaskListItem {
            id: delegate
            task: page.tasks[model.idx]
            onClicked: app.openTask(task.id)
            onToggleDone: app.setTaskDone(task, !task.done)
            menu: ContextMenu {
                MenuItem {
                    text: delegate.task && delegate.task.done ? qsTr("Mark not done") : qsTr("Mark done")
                    onClicked: app.setTaskDone(delegate.task, !delegate.task.done)
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var id = delegate.task.id
                        delegate.remorseDelete(function() {
                            api.request("DELETE", "/tasks/" + id, {}, null, function(r) {
                                if (r.ok) app.taskRevision++; else app.showError(r)
                            })
                        })
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: model.count === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Could not load tasks") : qsTr("No tasks")
            hintText: page.errorText.length > 0 ? page.errorText : qsTr("Pull down to add a task")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && model.count === 0
        }

        VerticalScrollDecorator {}
    }
}
