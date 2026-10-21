import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import "../components"
import "../js/util.js" as Util

Page {
    id: page
    objectName: "taskPage"
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property int taskId
    property var task: null
    property bool loading: false
    property string errorText: ""
    property int commentCount: -1

    function load() {
        loading = true
        api.request("GET", "/tasks/" + taskId, {}, null, function(r) {
            loading = false
            if (!r.ok) {
                errorText = r.error
                return
            }
            errorText = ""
            task = r.data
        })
        api.request("GET", "/tasks/" + taskId + "/comments", {}, null, function(r) {
            commentCount = r.ok ? (r.data || []).length : -1
        })
    }

    function edit() {
        var d = pageStack.push(Qt.resolvedUrl("TaskEditDialog.qml"), { task: Util.clone(task) })
        d.saved.connect(function(updated) {
            task = updated
            app.taskRevision++
        })
    }

    function download(att) {
        var d = pageStack.push(Qt.resolvedUrl("DownloadDialog.qml"), { fileName: att.file.name, fileSize: att.file.size })
        d.accepted.connect(function() {
            api.downloadAttachment(task.id, att.id, att.file.name, function(r) {
                if (!r.ok) {
                    app.showError(r)
                    return
                }
                app.notify(qsTr("Saved to %1").arg(r.data))
                if (d.openAfter && !appBridge.openFile(r.data))
                    app.notify(qsTr("No app found to open this file"))
            })
        })
    }

    property bool uploading: false

    function isImage(att) {
        var mime = att.file && att.file.mime ? String(att.file.mime) : ""
        if (mime.indexOf("image/") === 0)
            return /^image\/(png|jpeg|gif|webp|bmp)$/.test(mime)
        return /\.(png|jpe?g|gif|webp|bmp)$/i.test(att.file ? att.file.name : "")
    }

    function openAttachment(att) {
        if (isImage(att)) {
            var v = pageStack.push(Qt.resolvedUrl("AttachmentViewerPage.qml"), { taskId: task.id, attachment: att })
            v.saveRequested.connect(function() { download(att) })
        } else {
            download(att)
        }
    }

    function upload(path) {
        uploading = true
        api.uploadAttachment(task.id, path, function(r) {
            uploading = false
            if (!r.ok) {
                app.showError(r, qsTr("Could not attach the file"))
                return
            }
            app.notify(qsTr("File attached"))
            load()
        })
    }

    function pickFile() {
        pageStack.push(pickerComponent)
    }

    function deleteAttachment(item, att) {
        item.remorseDelete(function() {
            api.request("DELETE", "/tasks/" + task.id + "/attachments/" + att.id, {}, null, function(r) {
                if (r.ok) load(); else app.showError(r)
            })
        })
    }

    Component {
        id: pickerComponent
        ContentPickerPage {
            title: qsTr("Attach a file")
            onSelectedContentPropertiesChanged: {
                if (selectedContentProperties && selectedContentProperties.filePath)
                    page.upload(selectedContentProperties.filePath)
            }
        }
    }

    Component.onCompleted: load()

    Connections {
        target: app
        onTaskChanged: if (taskId === page.taskId) page.load()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            enabled: page.task !== null
            MenuItem {
                text: qsTr("Delete")
                onClicked: {
                    var id = page.task.id
                    Remorse.popupAction(page, qsTr("Deleting task"), function() {
                        api.request("DELETE", "/tasks/" + id, {}, null, function(r) {
                            if (r.ok) {
                                app.taskRevision++
                                pageStack.pop()
                            } else {
                                app.showError(r)
                            }
                        })
                    })
                }
            }
            MenuItem {
                text: qsTr("Labels")
                onClicked: {
                    var p = pageStack.push(Qt.resolvedUrl("TaskLabelsPage.qml"), { task: page.task })
                    p.changed.connect(function() { page.load(); app.taskRevision++ })
                }
            }
            MenuItem {
                text: qsTr("Edit")
                onClicked: page.edit()
            }
            MenuItem {
                text: page.task && page.task.done ? qsTr("Mark not done") : qsTr("Mark done")
                onClicked: app.setTaskDone(page.task, !page.task.done)
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: page.task ? page.task.title : ""
                description: page.task ? app.projectTitle(page.task.project_id) + (page.task.identifier ? " · " + page.task.identifier : "") : ""
            }

            Label {
                visible: page.errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: "#ff4d4d"
                text: page.errorText
            }

            TextSwitch {
                visible: page.task !== null
                text: qsTr("Done")
                checked: page.task ? page.task.done : false
                automaticCheck: false
                onClicked: app.setTaskDone(page.task, !page.task.done)
            }

            DetailItem {
                property var d: page.task ? Util.parseDate(page.task.due_date) : null
                visible: d !== null
                label: qsTr("Due")
                value: Util.formatDate(d)
            }
            DetailItem {
                property var d: page.task ? Util.parseDate(page.task.start_date) : null
                visible: d !== null
                label: qsTr("Starts")
                value: Util.formatDate(d)
            }
            DetailItem {
                property var d: page.task ? Util.parseDate(page.task.end_date) : null
                visible: d !== null
                label: qsTr("Ends")
                value: Util.formatDate(d)
            }
            Repeater {
                model: page.task && page.task.reminders ? page.task.reminders : []
                DetailItem {
                    label: qsTr("Reminder")
                    value: Util.formatDate(Util.parseDate(modelData.reminder))
                }
            }
            DetailItem {
                visible: !!(page.task && page.task.repeat_after > 0)
                label: qsTr("Repeats")
                value: page.task ? Util.describeRepeat(page.task.repeat_after) : ""
            }
            DetailItem {
                visible: !!(page.task && page.task.priority > 0)
                label: qsTr("Priority")
                value: page.task ? Util.priorityName(page.task.priority) : ""
            }
            DetailItem {
                visible: !!(page.task && page.task.percent_done > 0)
                label: qsTr("Progress")
                value: page.task ? Math.round(page.task.percent_done * 100) + " %" : ""
            }
            DetailItem {
                visible: !!(page.task && page.task.created_by)
                label: qsTr("Created by")
                value: page.task ? Util.userName(page.task.created_by) : ""
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall
                visible: !!(page.task && page.task.labels && page.task.labels.length > 0)
                Repeater {
                    model: page.task && page.task.labels ? page.task.labels : []
                    LabelChip { label: modelData }
                }
            }

            SectionHeader {
                text: qsTr("Description")
                visible: !!(page.task && page.task.description && page.task.description.length > 0)
            }
            Label {
                visible: !!(page.task && page.task.description && page.task.description.length > 0)
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                text: page.task ? "<style>a { color: " + Theme.highlightColor + "; }</style>" + util.sanitizeHtml(page.task.description) : ""
                linkColor: Theme.highlightColor
                onLinkActivated: {
                    var d = pageStack.push(Qt.resolvedUrl("OpenLinkDialog.qml"), { url: link })
                    d.accepted.connect(function() { Qt.openUrlExternally(link) })
                }
            }

            SectionHeader {
                text: qsTr("Attachments")
                visible: page.task !== null
            }
            Repeater {
                model: page.task && page.task.attachments ? page.task.attachments : []
                ListItem {
                    id: attItem
                    contentHeight: Theme.itemSizeSmall
                    Icon {
                        id: attIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: page.isImage(modelData) ? "image://theme/icon-m-image" : "image://theme/icon-m-attach"
                    }
                    Label {
                        anchors {
                            left: attIcon.right; leftMargin: Theme.paddingMedium
                            right: parent.right; rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: modelData.file.name
                        truncationMode: TruncationMode.Fade
                    }
                    onClicked: page.openAttachment(modelData)
                    menu: ContextMenu {
                        MenuItem {
                            text: page.isImage(modelData) ? qsTr("View") : qsTr("Open")
                            onClicked: page.openAttachment(modelData)
                        }
                        MenuItem {
                            visible: page.isImage(modelData)
                            text: qsTr("Save to Downloads")
                            onClicked: page.download(modelData)
                        }
                        MenuItem {
                            text: qsTr("Delete")
                            onClicked: page.deleteAttachment(attItem, modelData)
                        }
                    }
                }
            }

            BackgroundItem {
                visible: page.task !== null
                height: Theme.itemSizeSmall
                enabled: !page.uploading
                onClicked: page.pickFile()
                Icon {
                    id: addIcon
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-add"
                }
                Label {
                    anchors { left: addIcon.right; leftMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                    text: page.uploading ? qsTr("Uploading…") : qsTr("Attach a photo or file")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                BusyIndicator {
                    anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                    size: BusyIndicatorSize.ExtraSmall
                    running: page.uploading
                }
            }

            BackgroundItem {
                visible: page.task !== null
                height: Theme.itemSizeSmall
                onClicked: {
                    var p = pageStack.push(Qt.resolvedUrl("CommentsPage.qml"), { taskId: page.taskId })
                    p.commentsCounted.connect(function(n) { page.commentCount = n })
                }
                Label {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.commentCount >= 0 ? qsTr("Comments (%1)").arg(page.commentCount) : qsTr("Comments")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }
        }
        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading && page.task === null
    }
}
