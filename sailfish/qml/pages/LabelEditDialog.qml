import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Dialog {
    id: dialog
    property string colorHex: "1973ff"
    signal created(var label)

    canAccept: titleField.text.trim().length > 0

    onAccepted: {
        api.request("PUT", "/labels", {}, { title: titleField.text.trim(), hex_color: colorHex }, function(r) {
            if (r.ok) dialog.created(r.data); else app.showError(r)
        })
    }

    Column {
        width: parent.width
        DialogHeader { title: qsTr("New label") }
        TextField {
            id: titleField
            width: parent.width
            label: qsTr("Title")
            focus: true
        }
        SectionHeader { text: qsTr("Color") }
        ColorRow {
            selected: dialog.colorHex
            onPicked: dialog.colorHex = hex
        }
    }
}
