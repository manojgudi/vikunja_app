import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

// Shows a date and time; tapping opens one dialog for both. `dateValue` is a
// Date or null.
ValueButton {
    id: field

    property var dateValue: null
    property bool clearable: true
    property var defaultDate: null

    value: dateValue ? Util.formatDate(field.dateValue) : qsTr("None")

    function open() {
        var start = field.dateValue
        if (!start) {
            start = field.defaultDate ? new Date(field.defaultDate.getTime()) : Util.addDays(Util.startOfDay(new Date()), 1)
            if (!field.defaultDate)
                start.setHours(9)
        }
        var d = pageStack.push(Qt.resolvedUrl("../pages/DateTimeDialog.qml"), {
            selected: start, title: field.label, clearable: field.clearable && field.dateValue !== null
        })
        d.accepted.connect(function() {
            field.dateValue = d.cleared ? null : d.selected
        })
    }

    onClicked: open()
    onPressAndHold: if (clearable) field.dateValue = null
}
