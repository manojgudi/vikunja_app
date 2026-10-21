import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/util.js" as Util

Page {
    id: page
    objectName: "homePage"
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property var tasks: []
    property bool loading: false
    property string errorText: ""
    property bool onlyWithDueDate: api.setting("homeOnlyDue", false) === true || api.setting("homeOnlyDue", false) === "true"
    property int currentPage: 1
    property int totalPages: 1

    function reload() {
        currentPage = 1
        load(false)
    }

    function load(append) {
        loading = true
        var filter = "done = false"
        if (onlyWithDueDate)
            filter += " && due_date > 0001-01-01 00:00"
        api.request("GET", "/tasks", {
            filter: filter,
            filter_include_nulls: onlyWithDueDate ? "false" : "true",
            sort_by: ["due_date", "id"],
            order_by: ["asc", "desc"],
            per_page: 50,
            page: currentPage
        }, null, function(r) {
            loading = false
            if (!r.ok) {
                errorText = r.error
                return
            }
            errorText = ""
            totalPages = r.totalPages || 1
            var list = r.data || []
            // Tasks without a due date sort first on the server; show them last.
            var dated = [], undated = []
            for (var i = 0; i < list.length; ++i)
                (Util.parseDate(list[i].due_date) ? dated : undated).push(list[i])
            var merged = dated.concat(undated)
            tasks = append ? tasks.concat(merged) : merged
            rebuild()
        })
    }

    function rebuild() {
        sectionModel.clear()
        var dated = [], undated = []
        for (var i = 0; i < tasks.length; ++i)
            (Util.parseDate(tasks[i].due_date) ? dated : undated).push(i)
        var order = dated.concat(undated)
        for (var j = 0; j < order.length; ++j)
            sectionModel.append({ idx: order[j], section: Util.dueSection(tasks[order[j]]) })
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            if (pageStack.nextPage(page) === null)
                pageStack.pushAttached(Qt.resolvedUrl("ProjectsPage.qml"))
            app.openPendingTaskSoon()
        }
    }

    Component.onCompleted: reload()

    Connections {
        target: app
        onTaskRevisionChanged: page.reload()
    }

    ListModel { id: sectionModel }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: sectionModel

        header: PageHeader {
            title: qsTr("Upcoming")
            description: app.currentUser ? Util.userName(app.currentUser) : ""
        }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: page.onlyWithDueDate ? qsTr("Show tasks without due date") : qsTr("Only tasks with due date")
                onClicked: {
                    api.setSetting("homeOnlyDue", !page.onlyWithDueDate)
                    page.onlyWithDueDate = !page.onlyWithDueDate
                    page.reload()
                }
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
            MenuItem {
                text: qsTr("New task")
                onClicked: app.openAddTask()
            }
        }

        PushUpMenu {
            visible: page.currentPage < page.totalPages
            MenuItem {
                text: qsTr("Load more")
                onClicked: { page.currentPage++; page.load(true) }
            }
        }

        section.property: "section"
        section.delegate: SectionHeader { text: section }

        delegate: TaskListItem {
            id: delegate
            task: page.tasks[model.idx]
            showProject: true
            onClicked: app.openTask(task.id)
            onToggleDone: app.setTaskDone(task, !task.done)
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Mark done")
                    onClicked: app.setTaskDone(delegate.task, true)
                }
                MenuItem {
                    text: qsTr("Open project")
                    onClicked: pageStack.push(Qt.resolvedUrl("ProjectPage.qml"), { projectId: delegate.task.project_id })
                }
            }
        }

        ViewPlaceholder {
            enabled: sectionModel.count === 0 && !page.loading
            text: page.errorText.length > 0 ? qsTr("Could not load tasks") : qsTr("Nothing to do")
            hintText: page.errorText.length > 0 ? page.errorText : qsTr("Pull down to add a task")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && sectionModel.count === 0
        }

        VerticalScrollDecorator {}
    }
}
