import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

Page {
    id: page
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property int taskId
    property var comments: []
    property bool loading: false
    property int editingId: 0
    signal commentsCounted(int n)

    function load() {
        loading = true
        api.request("GET", "/tasks/" + taskId + "/comments", {}, null, function(r) {
            loading = false
            if (!r.ok) {
                app.showError(r)
                return
            }
            comments = r.data || []
            page.commentsCounted(comments.length)
        })
    }

    function send() {
        var text = input.text.trim()
        if (text.length === 0)
            return
        var body = { comment: util.plainToHtml(text) }
        var method = editingId > 0 ? "POST" : "PUT"
        var path = "/tasks/" + taskId + "/comments" + (editingId > 0 ? "/" + editingId : "")
        api.request(method, path, {}, body, function(r) {
            if (r.ok) {
                input.text = ""
                editingId = 0
                load()
            } else {
                app.showError(r)
            }
        })
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader { title: qsTr("Comments") }

            Label {
                visible: page.comments.length === 0 && !page.loading
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeLarge
                text: qsTr("No comments yet")
            }

            Repeater {
                model: page.comments

                ListItem {
                    id: item
                    property var comment: modelData
                    property bool mine: comment && comment.author && app.currentUser && comment.author.id === app.currentUser.id
                    contentHeight: commentColumn.height + 2 * Theme.paddingMedium

                    Column {
                        id: commentColumn
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall / 2

                        Label {
                            width: parent.width
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                            text: item.comment ? Util.userName(item.comment.author) + " · " + Util.formatDate(Util.parseDate(item.comment.created)) : ""
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            text: item.comment ? util.sanitizeHtml(item.comment.comment) : ""
                            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                    }

                    menu: ContextMenu {
                        enabled: item.mine
                        MenuItem {
                            text: qsTr("Edit")
                            onClicked: {
                                page.editingId = item.comment.id
                                input.text = util.htmlToPlain(item.comment.comment)
                                input.forceActiveFocus()
                            }
                        }
                        MenuItem {
                            text: qsTr("Delete")
                            onClicked: {
                                var id = item.comment.id
                                item.remorseDelete(function() {
                                    api.request("DELETE", "/tasks/" + page.taskId + "/comments/" + id, {}, null, function(r) {
                                        if (r.ok) page.load(); else app.showError(r)
                                    })
                                })
                            }
                        }
                    }
                }
            }

            TextArea {
                id: input
                width: parent.width
                label: page.editingId > 0 ? qsTr("Edit comment") : qsTr("New comment")
                placeholderText: qsTr("Write a comment")
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge
                Button {
                    visible: page.editingId > 0
                    text: qsTr("Cancel")
                    onClicked: { page.editingId = 0; input.text = "" }
                }
                Button {
                    text: page.editingId > 0 ? qsTr("Save") : qsTr("Send")
                    enabled: input.text.trim().length > 0
                    onClicked: page.send()
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
