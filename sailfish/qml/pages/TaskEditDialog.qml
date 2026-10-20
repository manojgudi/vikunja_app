import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/util.js" as Util

Dialog {
    id: dialog

    property var task
    property var reminderDates: []
    property var relativeReminders: []
    property string colorHex: task && task.hex_color ? task.hex_color : ""
    property var projectChoices: []
    property string originalDescription: task ? util.htmlToPlain(task.description) : ""
    signal saved(var task)

    canAccept: titleField.text.trim().length > 0

    Component.onCompleted: {
        var abs = [], rel = []
        var rs = task.reminders || []
        for (var i = 0; i < rs.length; ++i) {
            if (rs[i].relative_to)
                rel.push(rs[i])
            else if (Util.parseDate(rs[i].reminder))
                abs.push(Util.parseDate(rs[i].reminder))
        }
        reminderDates = abs
        relativeReminders = rel

        var choices = []
        for (var j = 0; j < app.projects.length; ++j)
            if (app.projects[j].id > 0 && !app.projects[j].is_archived)
                choices.push(app.projects[j])
        projectChoices = choices
        for (var k = 0; k < choices.length; ++k)
            if (choices[k].id === task.project_id)
                projectBox.currentIndex = k

        var rep = Util.splitRepeat(task.repeat_after)
        repeatAmount.text = rep.amount > 0 ? String(rep.amount) : ""
        repeatUnit.currentIndex = rep.unit
        priorityBox.currentIndex = task.priority || 0
    }

    function pickReminder(index) {
        var current = index >= 0 ? reminderDates[index] : (dueField.dateValue || new Date())
        var d = pageStack.push("Sailfish.Silica.DatePickerDialog", { date: current })
        d.accepted.connect(function() {
            var date = d.date
            var t = pageStack.push("Sailfish.Silica.TimePickerDialog", {
                hourMode: DateTime.TwentyFourHours, hour: current.getHours(), minute: current.getMinutes()
            })
            t.accepted.connect(function() {
                var picked = new Date(date.getFullYear(), date.getMonth(), date.getDate(), t.hour, t.minute, 0)
                var list = reminderDates.slice()
                if (index >= 0) list[index] = picked
                else list.push(picked)
                reminderDates = list
            })
        })
    }

    onAccepted: {
        var t = Util.clone(task)
        t.title = titleField.text.trim()
        t.done = doneSwitch.checked
        if (descriptionField.text !== originalDescription)
            t.description = util.plainToHtml(descriptionField.text)
        t.due_date = Util.toApiDate(dueField.dateValue)
        t.start_date = Util.toApiDate(startField.dateValue)
        t.end_date = Util.toApiDate(endField.dateValue)
        var reminders = relativeReminders.slice()
        for (var i = 0; i < reminderDates.length; ++i)
            reminders.push({ reminder: Util.toApiDate(reminderDates[i]) })
        t.reminders = reminders
        var amount = parseInt(repeatAmount.text, 10)
        t.repeat_after = amount > 0 ? amount * Util.repeatUnits[repeatUnit.currentIndex].seconds : 0
        t.priority = priorityBox.currentIndex
        t.percent_done = progressSlider.value / 100
        t.hex_color = colorHex
        var project = projectChoices[projectBox.currentIndex]
        if (project)
            t.project_id = project.id
        api.request("POST", "/tasks/" + task.id, {}, t, function(r) {
            if (r.ok) {
                dialog.saved(r.data)
            } else {
                app.showError(r, qsTr("Could not save the task"))
            }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader { title: qsTr("Edit task") }

            TextField {
                id: titleField
                width: parent.width
                label: qsTr("Title")
                text: task ? task.title : ""
            }

            TextSwitch {
                id: doneSwitch
                text: qsTr("Done")
                checked: task ? task.done : false
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

            TextArea {
                id: descriptionField
                width: parent.width
                label: qsTr("Description")
                placeholderText: label
                text: dialog.originalDescription
            }
            Label {
                visible: !!(task && util.hasRichFormatting(task.description) && descriptionField.text !== dialog.originalDescription)
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Rich formatting in the description will be simplified when you save your changes.")
            }

            SectionHeader { text: qsTr("Dates") }
            DateTimeField {
                id: dueField
                label: qsTr("Due")
                dateValue: task ? Util.parseDate(task.due_date) : null
            }
            DateTimeField {
                id: startField
                label: qsTr("Start")
                dateValue: task ? Util.parseDate(task.start_date) : null
            }
            DateTimeField {
                id: endField
                label: qsTr("End")
                dateValue: task ? Util.parseDate(task.end_date) : null
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Press and hold a date to clear it.")
            }

            SectionHeader { text: qsTr("Reminders") }
            Repeater {
                model: dialog.reminderDates
                ValueButton {
                    label: qsTr("Reminder")
                    value: Util.formatDate(modelData)
                    onClicked: dialog.pickReminder(index)
                    onPressAndHold: {
                        var list = dialog.reminderDates.slice()
                        list.splice(index, 1)
                        dialog.reminderDates = list
                    }
                }
            }
            Repeater {
                model: dialog.relativeReminders
                DetailItem {
                    label: qsTr("Relative reminder")
                    value: qsTr("%1 h from %2").arg(Math.round(modelData.relative_period / 3600)).arg(modelData.relative_to)
                }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Add reminder")
                onClicked: dialog.pickReminder(-1)
            }

            SectionHeader { text: qsTr("Repeat") }
            Row {
                width: parent.width
                TextField {
                    id: repeatAmount
                    width: parent.width / 3
                    label: qsTr("Every")
                    placeholderText: "0"
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 9999 }
                }
                ComboBox {
                    id: repeatUnit
                    width: parent.width * 2 / 3
                    label: qsTr("Unit")
                    menu: ContextMenu {
                        Repeater {
                            model: Util.repeatUnits
                            MenuItem { text: modelData.name }
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("Details") }
            ComboBox {
                id: priorityBox
                width: parent.width
                label: qsTr("Priority")
                menu: ContextMenu {
                    Repeater {
                        model: Util.priorities
                        MenuItem { text: modelData.name }
                    }
                }
            }

            Slider {
                id: progressSlider
                width: parent.width
                label: qsTr("Progress")
                minimumValue: 0
                maximumValue: 100
                stepSize: 10
                value: task ? Math.round((task.percent_done || 0) * 100) : 0
                valueText: Math.round(value) + " %"
            }

            SectionHeader { text: qsTr("Color") }
            ColorRow {
                selected: dialog.colorHex
                onPicked: dialog.colorHex = hex
            }
        }
        VerticalScrollDecorator {}
    }
}
