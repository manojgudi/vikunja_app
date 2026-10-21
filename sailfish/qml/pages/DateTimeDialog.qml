import QtQuick 2.0
import Sailfish.Silica 1.0

// Date and time in one dialog, so accepting it returns straight to the page
// that opened it.
Dialog {
    id: dialog
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property date selected: new Date()
    property string title: qsTr("Due date")
    property bool clearable: false
    property bool cleared: false

    property alias hour: timePicker.hour
    property alias minute: timePicker.minute

    Component.onCompleted: setTime(selected.getHours(), selected.getMinutes())

    function result() {
        var d = datePicker.date
        return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hour, minute, 0)
    }

    function setTime(h, m) {
        hour = h
        minute = m
    }

    onAccepted: selected = result()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: dialog.clearable
            MenuItem {
                text: qsTr("No date")
                onClicked: {
                    dialog.cleared = true
                    dialog.accept()
                }
            }
        }

        Column {
            id: column
            width: parent.width

            DialogHeader { title: dialog.title }

            DatePicker {
                id: datePicker
                date: dialog.selected
                daysVisible: true
            }

            SectionHeader {
                text: qsTr("Time: %1").arg((dialog.hour < 10 ? "0" : "") + dialog.hour + ":" + (dialog.minute < 10 ? "0" : "") + dialog.minute)
            }

            // Inline clock: no second dialog, so Accept goes straight back.
            TimePicker {
                id: timePicker
                anchors.horizontalCenter: parent.horizontalCenter
                hourMode: DateTime.TwentyFourHours
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                Repeater {
                    model: [ [9, 0], [12, 0], [17, 0], [20, 0] ]
                    Button {
                        preferredWidth: Theme.buttonWidthExtraSmall
                        text: (modelData[0] < 10 ? "0" : "") + modelData[0] + ":00"
                        onClicked: dialog.setTime(modelData[0], modelData[1])
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
