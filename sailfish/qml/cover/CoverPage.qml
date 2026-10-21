import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

CoverBackground {
    id: cover

    // Open tasks due from now until midnight (phone time), and open tasks
    // whose due time has passed.
    property var tasks: []
    property int today: 0
    property int overdue: 0

    function refresh() {
        if (!api.authenticated) {
            tasks = []
            today = 0
            overdue = 0
            return
        }
        api.request("GET", "/tasks", {
            filter: "done = false && due_date < now+2d",
            filter_include_nulls: "false",
            sort_by: ["due_date"],
            order_by: ["asc"],
            per_page: 50
        }, null, function(r) {
            if (!r.ok) {
                api.diag("cover: tasks request failed, status " + r.status)
                return
            }
            var c = Util.coverCounts(r.data || [], new Date())
            overdue = c.overdue
            today = c.today
            tasks = c.tasks
        })
    }

    onStatusChanged: if (status === Cover.Active) refresh()

    // Counts change as time passes, so refresh while the cover is visible.
    Timer {
        interval: 60000
        repeat: true
        running: cover.status === Cover.Active && api.authenticated
        onTriggered: cover.refresh()
    }

    Connections {
        target: api
        onSessionChanged: cover.refresh()
    }

    Connections {
        target: app
        onTaskRevisionChanged: cover.refresh()
    }

    Image {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.itemSizeLarge }
        source: Qt.resolvedUrl("../images/logo.png")
        width: parent.width * 0.5
        height: width
        opacity: 0.15
        fillMode: Image.PreserveAspectFit
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.paddingLarge }
        spacing: Theme.paddingSmall

        Label {
            text: api.authenticated ? qsTr("%n due later today", "", cover.today) : qsTr("Vikunja")
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.highlightColor
        }
        Label {
            visible: cover.overdue > 0
            text: qsTr("%n overdue", "", cover.overdue)
            font.pixelSize: Theme.fontSizeSmall
            color: "#ff4d4d"
        }
        Repeater {
            model: app.hideDetails ? [] : cover.tasks.slice(0, 4)
            Label {
                width: parent.width
                text: modelData.title
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
                color: Util.isOverdue(modelData) ? "#ff4d4d" : Theme.primaryColor
            }
        }
    }

    CoverActionList {
        enabled: api.authenticated
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: cover.refresh()
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-new"
            onTriggered: {
                app.activate()
                app.openAddTask()
            }
        }
    }
}
