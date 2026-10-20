import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

ListItem {
    id: item

    property var task
    property bool showProject: false
    signal toggleDone()

    contentHeight: Math.max(Theme.itemSizeMedium, column.height + 2 * Theme.paddingMedium)

    Rectangle {
        visible: !!(task && task.hex_color)
        width: Theme.paddingSmall
        height: parent.height
        color: task ? Util.cssColor(task.hex_color) : "transparent"
    }

    DoneToggle {
        id: check
        anchors { left: parent.left; leftMargin: Theme.horizontalPageMargin - Theme.paddingMedium; verticalCenter: parent.verticalCenter }
        checked: task ? task.done : false
        onClicked: item.toggleDone()
    }

    Column {
        id: column
        anchors {
            left: check.right; right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        spacing: Theme.paddingSmall / 2

        Label {
            width: parent.width
            text: task ? task.title : ""
            truncationMode: TruncationMode.Fade
            font.strikeout: task && task.done
            color: item.highlighted ? Theme.highlightColor : (task && task.done ? Theme.secondaryColor : Theme.primaryColor)
        }

        Row {
            spacing: Theme.paddingMedium
            width: parent.width
            Label {
                property var due: task ? Util.parseDate(task.due_date) : null
                visible: due !== null
                text: Util.formatDate(due)
                font.pixelSize: Theme.fontSizeExtraSmall
                color: task && Util.isOverdue(task) ? "#ff4d4d" : Theme.secondaryHighlightColor
            }
            Label {
                visible: !!(task && task.priority >= 3)
                text: task ? Util.priorityName(task.priority) : ""
                font.pixelSize: Theme.fontSizeExtraSmall
                color: task && task.priority >= 4 ? "#ff4d4d" : Theme.secondaryHighlightColor
            }
            Label {
                visible: showProject && text.length > 0
                text: task ? app.projectTitle(task.project_id) : ""
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                truncationMode: TruncationMode.Fade
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.paddingSmall
            visible: !!(task && task.labels && task.labels.length > 0)
            Repeater {
                model: task && task.labels ? task.labels : []
                LabelChip { label: modelData }
            }
        }
    }
}
