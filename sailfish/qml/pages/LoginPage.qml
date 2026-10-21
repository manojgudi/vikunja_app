import QtQuick 2.0
import Sailfish.Silica 1.0

// Two steps, like the Vikunja Android app: server, username and password
// first; the two-factor code is only asked for when the account needs it.
Page {
    id: page
    objectName: "loginPage"
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    property bool busy: false
    property bool needTotp: false
    property string errorText: api.sessionNotice === "inactive"
                               ? qsTr("You were signed out because the app was not used for %1 days.").arg(30) : ""

    backNavigation: false

    // Signed in some other way while this page was showing (for example a
    // reminder start restored the session): go to the home page.
    Connections {
        target: api
        onSessionChanged: page.leaveIfSignedIn()
    }
    onStatusChanged: if (status === PageStatus.Active) leaveIfSignedIn()

    function leaveIfSignedIn() {
        if (api.authenticated && !busy && status === PageStatus.Active)
            app.leaveLoginPage()
    }

    function signIn() {
        errorText = ""
        busy = true
        api.loginWithPassword(serverField.text, userField.text, passwordField.text,
                              needTotp ? totpField.text : "", function(r) {
            busy = false
            if (r.ok) {
                passwordField.text = ""
                totpField.text = ""
                needTotp = false
                app.currentUser = r.data
                app.loadProjects()
                app.loadLabels()
                app.goHome()
                app.askStorageChoice()
                return
            }
            handleError(r)
        })
    }

    function backToPassword() {
        needTotp = false
        totpField.text = ""
        errorText = ""
        passwordField.forceActiveFocus()
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
        if (r.errorCode === "totp_required") {
            // Password was right; now the second step.
            needTotp = true
            errorText = ""
            totpField.forceActiveFocus()
            return
        }
        if (r.errorCode === "totp_invalid") {
            totpField.text = ""
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

            PageHeader { title: page.needTotp ? qsTr("Two-factor authentication") : qsTr("Sign in to Vikunja") }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: Qt.resolvedUrl("../images/logo.png")
                width: Theme.itemSizeExtraLarge
                height: width
                fillMode: Image.PreserveAspectFit
            }

            // Step 1
            Column {
                width: parent.width
                visible: !page.needTotp

                TextField {
                    id: serverField
                    width: parent.width
                    label: qsTr("Server address")
                    placeholderText: "https://vikunja.example.com"
                    text: api.serverUrl
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: userField.forceActiveFocus()
                }

                TextField {
                    id: userField
                    width: parent.width
                    label: qsTr("Username or email")
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: passwordField.forceActiveFocus()
                }

                PasswordField {
                    id: passwordField
                    width: parent.width
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: if (signInButton.enabled) page.signIn()
                }
            }

            // Step 2
            Column {
                width: parent.width
                visible: page.needTotp
                spacing: Theme.paddingMedium

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    text: qsTr("Enter the 6-digit code from your authenticator app for %1.").arg(userField.text)
                }

                TextField {
                    id: totpField
                    width: parent.width
                    label: qsTr("Authentication code")
                    inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
                    validator: RegExpValidator { regExp: /^[0-9]{0,8}$/ }
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: if (signInButton.enabled) page.signIn()
                }
            }

            Label {
                visible: page.errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.errorColor
                text: page.errorText
            }

            ButtonLayout {
                Button {
                    visible: page.needTotp
                    text: qsTr("Back")
                    enabled: !page.busy
                    onClicked: page.backToPassword()
                }
                Button {
                    id: signInButton
                    text: page.needTotp ? qsTr("Verify") : qsTr("Sign in")
                    enabled: !page.busy && serverField.text.length > 0 && userField.text.length > 0
                             && passwordField.text.length > 0 && (!page.needTotp || totpField.text.length >= 6)
                    onClicked: page.signIn()
                }
            }
            Item { width: 1; height: Theme.paddingMedium }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: page.busy
                visible: page.busy
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Your password goes only to your server, once, to create a token for this phone. You stay signed in until you sign out or skip the app for 30 days.")
            }

            Label {
                visible: !api.persistentLogin
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Secure storage is off: you'll sign in at every start.")
            }
        }
        VerticalScrollDecorator {}
    }
}
