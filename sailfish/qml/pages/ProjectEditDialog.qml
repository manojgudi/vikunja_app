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

    property var project: null
    property int parentId: 0
    property var parentChoices: []
    property string colorHex: project && project.hex_color ? project.hex_color : ""
    property string originalDescription: project ? util.htmlToPlain(project.description) : ""
    signal saved(var project)

    canAccept: titleField.text.trim().length > 0

    Component.onCompleted: {
        var choices = [{ id: 0, title: qsTr("None (top level)") }]
        for (var i = 0; i < app.projects.length; ++i) {
            var p = app.projects[i]
            if (p.id > 0 && (!project || p.id !== project.id))
                choices.push({ id: p.id, title: p.title })
        }
        parentChoices = choices
        for (var j = 0; j < choices.length; ++j)
            if (choices[j].id === parentId)
                parentBox.currentIndex = j
    }

    onAccepted: {
        var body = project ? Util.clone(project) : {}
        body.title = titleField.text.trim()
        if (descriptionField.text !== originalDescription)
            body.description = util.plainToHtml(descriptionField.text)
        body.parent_project_id = parentChoices[parentBox.currentIndex] ? parentChoices[parentBox.currentIndex].id : 0
        body.hex_color = colorHex
        var method = project ? "POST" : "PUT"
        var path = project ? "/projects/" + project.id : "/projects"
        api.request(method, path, {}, body, function(r) {
            if (r.ok) {
                dialog.saved(r.data)
            } else {
                app.showError(r)
            }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader { title: project ? qsTr("Edit project") : qsTr("New project") }

            TextField {
                id: titleField
                width: parent.width
                label: qsTr("Title")
                text: project ? project.title : ""
                focus: !project
            }

            TextArea {
                id: descriptionField
                width: parent.width
                label: qsTr("Description")
                placeholderText: label
                text: dialog.originalDescription
            }

            ComboBox {
                id: parentBox
                width: parent.width
                label: qsTr("Parent project")
                menu: ContextMenu {
                    Repeater {
                        model: dialog.parentChoices
                        MenuItem { text: modelData.title }
                    }
                }
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
