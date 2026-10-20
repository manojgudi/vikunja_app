import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property string title
    property alias label: field.label
    property alias text: field.text
    property bool numeric: false

    canAccept: field.text.trim().length > 0

    Column {
        width: parent.width
        DialogHeader { title: dialog.title }
        TextField {
            id: field
            width: parent.width
            focus: true
            inputMethodHints: dialog.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
            validator: dialog.numeric ? intValidator : null
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: if (dialog.canAccept) dialog.accept()
        }
    }

    IntValidator { id: intValidator; bottom: 0; top: 10000 }
}
