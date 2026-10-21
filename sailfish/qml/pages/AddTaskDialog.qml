import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/util.js" as Util

Dialog {
    id: dialog
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property int projectId
    property int bucketId: 0
    property string initialTitle: ""
    property var projectChoices: []

    canAccept: titleField.text.trim().length > 0 && projectChoices.length > 0

    // Quick presets fill in the due field; the user can still change the
    // date and time by tapping it.
    function preset(kind) {
        var today = Util.startOfDay(new Date())
        var d = null
        switch (kind) {
        case "today": d = new Date(today.getTime()); d.setHours(17); break
        case "tomorrow": d = Util.addDays(today, 1); d.setHours(9); break
        case "monday": d = Util.addDays(today, ((8 - today.getDay()) % 7) || 7); d.setHours(9); break
        case "weekend": d = Util.addDays(today, (6 - today.getDay() + 7) % 7); d.setHours(10); break
        case "week": d = Util.addDays(today, 7); d.setHours(9); break
        }
        dueField.dateValue = d
    }

    function dueValue() { return dueField.dateValue }
    function setDue(d) { dueField.dateValue = d }
    function setTitle(t) { titleField.text = t }

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
        var due = dueField.dateValue
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

            DateTimeField {
                id: dueField
                label: qsTr("Due")
            }

            Grid {
                id: presetGrid
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                columns: 2
                spacing: Theme.paddingMedium
                Repeater {
                    model: [
                        { kind: "", name: qsTr("None") },
                        { kind: "today", name: qsTr("Today") },
                        { kind: "tomorrow", name: qsTr("Tomorrow") },
                        { kind: "monday", name: qsTr("Monday") },
                        { kind: "weekend", name: qsTr("Weekend") },
                        { kind: "week", name: qsTr("In a week") }
                    ]
                    Button {
                        text: modelData.name
                        width: (presetGrid.width - presetGrid.spacing) / 2
                        onClicked: dialog.preset(modelData.kind)
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Tap the due date to pick a day and time.")
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
