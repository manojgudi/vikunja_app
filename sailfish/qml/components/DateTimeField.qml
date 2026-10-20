import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/util.js" as Util

// Picks a date and then a time. `value` is a Date or null.
ValueButton {
    id: field

    property var dateValue: null
    property bool clearable: true

    value: dateValue ? Util.formatDate(field.dateValue) : qsTr("None")

    function pickTime(date) {
        var t = pageStack.push("Sailfish.Silica.TimePickerDialog", {
            hourMode: DateTime.TwentyFourHours,
            hour: field.dateValue ? field.dateValue.getHours() : 9,
            minute: field.dateValue ? field.dateValue.getMinutes() : 0
        })
        t.accepted.connect(function() {
            var d = new Date(date.getFullYear(), date.getMonth(), date.getDate(), t.hour, t.minute, 0)
            field.dateValue = d
        })
    }

    onClicked: {
        var dialog = pageStack.push("Sailfish.Silica.DatePickerDialog", {
            date: field.dateValue ? field.dateValue : new Date()
        })
        dialog.accepted.connect(function() {
            var picked = dialog.date
            pickTime(picked)
        })
    }

    onPressAndHold: if (clearable) field.dateValue = null
}
