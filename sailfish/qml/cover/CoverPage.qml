import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

CoverBackground {
    id: cover

    property var tasks: []
    property int overdue: 0

    function refresh() {
        if (!api.authenticated) {
            tasks = []
            return
        }
        api.request("GET", "/tasks", {
            filter: "done = false && due_date < now+7d",
            filter_include_nulls: "false",
            sort_by: ["due_date"],
            order_by: ["asc"],
            per_page: 20
        }, null, function(r) {
            if (!r.ok)
                return
            var list = r.data || []
            var n = 0
            for (var i = 0; i < list.length; ++i)
                if (Util.isOverdue(list[i])) n++
            overdue = n
            tasks = list
        })
    }

    onStatusChanged: if (status === Cover.Active) refresh()

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
            text: api.authenticated ? qsTr("%n upcoming", "", cover.tasks.length) : qsTr("Vikunja")
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
