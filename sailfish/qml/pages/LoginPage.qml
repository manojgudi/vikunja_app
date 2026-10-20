import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property bool busy: false
    property bool usePassword: methodBox.currentIndex === 1
    property bool needTotp: false
    property string errorText: ""

    backNavigation: false

    function signIn() {
        errorText = ""
        busy = true
        var done = function(r) {
            busy = false
            if (r.ok) {
                passwordField.text = ""
                tokenField.text = ""
                totpField.text = ""
                app.currentUser = r.data
                app.loadProjects()
                app.loadLabels()
                pageStack.replace(Qt.resolvedUrl("HomePage.qml"))
                return
            }
            handleError(r)
        }
        if (usePassword)
            api.loginWithPassword(serverField.text, userField.text, passwordField.text, totpField.text, done)
        else
            api.loginWithToken(serverField.text, tokenField.text, done)
    }

    function handleError(r) {
        if (r.errorCode === "insecure_http") {
            var host = hostOf(r.data && r.data.server ? r.data.server : serverField.text)
            var d = pageStack.push(Qt.resolvedUrl("InsecureHttpDialog.qml"), { host: host })
            d.accepted.connect(function() {
                api.allowInsecureHost(host)
                signIn()
            })
            return
        }
        if (r.errorCode === "tls_untrusted") {
            var c = pageStack.push(Qt.resolvedUrl("CertificateDialog.qml"), { certificate: r.certificate })
            c.accepted.connect(function() {
                api.trustCertificate(r.certificate.host, r.certificate.port, r.certificate.sha256)
                signIn()
            })
            return
        }
        if (r.errorCode === "totp_required" || r.errorCode === "totp_invalid") {
            needTotp = true
            totpField.forceActiveFocus()
        }
        errorText = r.error
    }

    function hostOf(url) {
        var m = /^[a-z]+:\/\/([^\/:]+)/i.exec(util.normalizeServerUrl(url))
        return m ? m[1] : url
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Sign in to Vikunja") }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: Qt.resolvedUrl("../images/logo.png")
                width: Theme.itemSizeExtraLarge
                height: width
                fillMode: Image.PreserveAspectFit
            }

            TextField {
                id: serverField
                width: parent.width
                label: qsTr("Server address")
                placeholderText: "https://vikunja.example.com"
                text: api.serverUrl
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: usePassword ? userField.forceActiveFocus() : tokenField.forceActiveFocus()
            }

            ComboBox {
                id: methodBox
                width: parent.width
                label: qsTr("Sign in with")
                menu: ContextMenu {
                    MenuItem { text: qsTr("API token") }
                    MenuItem { text: qsTr("Username and password") }
                }
            }

            PasswordField {
                id: tokenField
                visible: !usePassword
                width: parent.width
                label: qsTr("API token")
                placeholderText: qsTr("tk_...")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: signIn()
            }

            Label {
                visible: !usePassword
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Create a token in the Vikunja web app under Settings → API Tokens. Give it access to projects, tasks, labels and comments.")
            }

            TextField {
                id: userField
                visible: usePassword
                width: parent.width
                label: qsTr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordField.forceActiveFocus()
            }

            PasswordField {
                id: passwordField
                visible: usePassword
                width: parent.width
                EnterKey.iconSource: needTotp ? "image://theme/icon-m-enter-next" : "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: needTotp ? totpField.forceActiveFocus() : signIn()
            }

            TextField {
                id: totpField
                visible: usePassword
                width: parent.width
                label: needTotp ? qsTr("Two-factor code (required)") : qsTr("Two-factor code (if enabled)")
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegExpValidator { regExp: /^[0-9]{0,8}$/ }
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: signIn()
            }

            Label {
                visible: usePassword
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Your password is used once to create a revocable API token for this phone, then forgotten. The token appears in Vikunja under Settings → API Tokens.")
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: "#ff4d4d"
                text: errorText
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Sign in")
                enabled: !busy && serverField.text.length > 0
                         && (usePassword ? (userField.text.length > 0 && passwordField.text.length > 0) : tokenField.text.length > 0)
                onClicked: signIn()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: busy
                visible: busy
            }

            Label {
                visible: !api.persistentLogin
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Sailfish Secrets is not available, so you will need to sign in again each time the app starts. Nothing is stored unencrypted.")
            }
        }
        VerticalScrollDecorator {}
    }
}
