import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/util.js" as Util

Dialog {
    id: dialog

    property int projectId
    property int bucketId: 0
    property string initialTitle: ""
    property var projectChoices: []
    property var customDue: null

    canAccept: titleField.text.trim().length > 0 && projectChoices.length > 0

    function dueFromChoice() {
        var now = new Date()
        var today = Util.startOfDay(now)
        switch (dueBox.currentIndex) {
        case 1: return new Date(today.getFullYear(), today.getMonth(), today.getDate(), 17, 0)
        case 2: var t = Util.addDays(today, 1); t.setHours(9); return t
        case 3: var m = Util.addDays(today, ((8 - today.getDay()) % 7) || 7); m.setHours(9); return m
        case 4: var s = Util.addDays(today, (6 - today.getDay() + 7) % 7); s.setHours(10); return s
        case 5: var w = Util.addDays(today, 7); w.setHours(9); return w
        case 6: return customDue
        }
        return null
    }

    Component.onCompleted: {
        var choices = []
        for (var i = 0; i < app.projects.length; ++i)
            if (app.projects[i].id > 0 && !app.projects[i].is_archived)
                choices.push(app.projects[i])
        projectChoices = choices
        for (var j = 0; j < choices.length; ++j)
            if (choices[j].id === projectId)
                projectBox.currentIndex = j
        titleField.forceActiveFocus()
    }

    onAccepted: {
        var project = projectChoices[projectBox.currentIndex]
        var body = { title: titleField.text.trim() }
        var due = dueFromChoice()
        if (due)
            body.due_date = Util.toApiDate(due)
        if (bucketId > 0)
            body.bucket_id = bucketId
        api.request("PUT", "/projects/" + project.id + "/tasks", {}, body, function(r) {
            if (r.ok) {
                app.taskRevision++
                app.notify(qsTr("Task added"))
            } else {
                app.showError(r, qsTr("Could not add the task"))
            }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader { title: qsTr("New task") }

            TextField {
                id: titleField
                width: parent.width
                label: qsTr("Title")
                placeholderText: qsTr("What needs to be done?")
                text: dialog.initialTitle
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }

            ComboBox {
                id: projectBox
                width: parent.width
                label: qsTr("Project")
                menu: ContextMenu {
                    Repeater {
                        model: dialog.projectChoices
                        MenuItem { text: modelData.title }
                    }
                }
            }

            ComboBox {
                id: dueBox
                width: parent.width
                label: qsTr("Due")
                menu: ContextMenu {
                    MenuItem { text: qsTr("No due date") }
                    MenuItem { text: qsTr("Today") }
                    MenuItem { text: qsTr("Tomorrow") }
                    MenuItem { text: qsTr("Next Monday") }
                    MenuItem { text: qsTr("This weekend") }
                    MenuItem { text: qsTr("In one week") }
                    MenuItem { text: qsTr("Pick a date…") }
                }
                onCurrentIndexChanged: if (currentIndex === 6) customField.clicked(null)
            }

            DateTimeField {
                id: customField
                visible: dueBox.currentIndex === 6
                label: qsTr("Due date")
                onDateValueChanged: dialog.customDue = dateValue
            }

            Label {
                visible: dialog.projectChoices.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                text: qsTr("Create a project first.")
            }
        }
    }
}
