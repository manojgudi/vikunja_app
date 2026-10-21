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

    property var pins: api.trustedCertificates()
    property var insecure: api.insecureHosts()
    property var projectChoices: []

    function refreshTrust() {
        pins = api.trustedCertificates()
        insecure = api.insecureHosts()
    }

    function boolSetting(key, def) {
        var v = api.setting(key, def)
        return v === true || v === "true"
    }

    Component.onCompleted: {
        var choices = [{ id: 0, title: qsTr("None") }]
        for (var i = 0; i < app.projects.length; ++i)
            if (app.projects[i].id > 0 && !app.projects[i].is_archived)
                choices.push(app.projects[i])
        projectChoices = choices
        for (var j = 0; j < choices.length; ++j)
            if (choices[j].id === app.defaultProjectId)
                defaultProjectBox.currentIndex = j
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader { title: qsTr("Settings") }

            SectionHeader { text: qsTr("Account") }
            DetailItem { label: qsTr("User"); value: app.currentUser ? Util.userName(app.currentUser) : "-" }
            DetailItem { label: qsTr("Server"); value: api.serverUrl }
            DetailItem { label: qsTr("Server version"); value: api.serverVersion || "-" }
            DetailItem {
                label: qsTr("Signed in with")
                value: api.authMethod === "password" ? qsTr("Password (app-created API token)") : qsTr("API token")
            }
            DetailItem {
                visible: api.tokenExpires.length > 0
                label: qsTr("Token expires")
                value: Util.formatDate(Util.parseDate(api.tokenExpires))
            }
            DetailItem {
                label: qsTr("Credential storage")
                value: api.persistentLogin ? qsTr("Sailfish Secrets (encrypted)") : qsTr("Memory only")
            }
            DetailItem {
                visible: api.insecureConnection
                label: qsTr("Connection")
                value: qsTr("Unencrypted HTTP")
            }

            ComboBox {
                id: defaultProjectBox
                width: parent.width
                label: qsTr("Default project")
                description: qsTr("Used for new tasks from the home page and the cover")
                menu: ContextMenu {
                    Repeater {
                        model: page.projectChoices
                        MenuItem { text: modelData.title }
                    }
                }
                onCurrentIndexChanged: {
                    var choice = page.projectChoices[currentIndex]
                    if (!choice || !app.currentUser || !app.currentUser.settings || choice.id === app.defaultProjectId)
                        return
                    var s = Util.clone(app.currentUser.settings)
                    s.default_project_id = choice.id
                    api.request("POST", "/user/settings/general", {}, s, function(r) {
                        if (r.ok) app.loadUser(); else app.showError(r)
                    })
                }
            }

            SectionHeader { text: qsTr("Notifications") }
            TextSwitch {
                text: qsTr("Reminders and due dates")
                description: app.reminders.systemAlarms
                             ? qsTr("Scheduled with the system alarm service, so they arrive even when the app is closed. Tasks added on other devices are picked up every few hours or when you open the app.")
                             : qsTr("The system alarm service is not available, so reminders only arrive while the app is running.")
                checked: page.boolSetting("notifications", true)
                onCheckedChanged: {
                    api.setSetting("notifications", checked)
                    app.reminders.enabled = checked
                    if (checked)
                        app.reminders.refresh()
                }
            }
            TextSwitch {
                text: qsTr("Hide task details")
                description: qsTr("Notifications and the cover show no task titles")
                checked: app.hideDetails
                onCheckedChanged: {
                    api.setSetting("hideDetails", checked)
                    app.hideDetails = checked
                }
            }
            Label {
                visible: app.reminders.systemAlarms && app.reminders.enabled
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: app.reminders.lastSync.length > 0
                      ? qsTr("%n upcoming reminder(s) scheduled, last synced at %1", "", app.reminders.scheduled).arg(app.reminders.lastSync)
                      : qsTr("Not synced yet")
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Send test notification")
                onClicked: app.reminders.sendTest(false)
            }
            Button {
                visible: app.reminders.systemAlarms
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Test reminder in 1 minute")
                onClicked: {
                    if (alarms.scheduleTest(60))
                        app.notify(qsTr("Close the app now; the reminder arrives in a minute."))
                    else
                        app.notify(qsTr("Could not schedule the test reminder"))
                }
            }

            SectionHeader { text: qsTr("Appearance") }
            ComboBox {
                label: qsTr("Theme")
                description: qsTr("Remembered on this device")
                currentIndex: app.themeMode === "light" ? 1 : app.themeMode === "dark" ? 2 : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("Follow ambience") }
                    MenuItem { text: qsTr("Light") }
                    MenuItem { text: qsTr("Dark") }
                }
                onCurrentIndexChanged: app.setThemeMode(["system", "light", "dark"][currentIndex])
            }

            SectionHeader { text: qsTr("Trusted certificates") }
            Label {
                visible: page.pins.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("None. Certificates you trust for self-signed servers appear here.")
            }
            Repeater {
                model: page.pins
                ListItem {
                    id: pinItem
                    contentHeight: pinColumn.height + 2 * Theme.paddingSmall
                    Column {
                        id: pinColumn
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        Label { text: modelData.hostPort; color: pinItem.highlighted ? Theme.highlightColor : Theme.primaryColor }
                        Label {
                            width: parent.width
                            wrapMode: Text.WrapAnywhere
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.family: "monospace"
                            color: Theme.secondaryColor
                            text: modelData.sha256
                        }
                    }
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Forget")
                            onClicked: { api.forgetCertificate(modelData.hostPort); page.refreshTrust() }
                        }
                    }
                }
            }

            SectionHeader {
                visible: page.insecure.length > 0
                text: qsTr("Servers allowed over HTTP")
            }
            Repeater {
                model: page.insecure
                ListItem {
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                    }
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Forget")
                            onClicked: { api.forgetInsecureHost(modelData); page.refreshTrust() }
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("About") }
            DetailItem { label: qsTr("Version"); value: appVersion }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Tasks are kept in memory only and never cached on the phone. The app runs inside the Sailfish sandbox, and its token is stored in Sailfish Secrets.")
            }

            Item { width: 1; height: Theme.paddingLarge }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Sign out")
                onClicked: Remorse.popupAction(page, qsTr("Signing out"), function() {
                    api.logout()
                    app.signedOut()
                })
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Signing out deletes the access token from this phone, cancels scheduled reminders, removes shown notifications and image previews, and resets your preferences here (except the theme). The token cannot revoke itself, so to invalidate it on the server too, delete it in the Vikunja web app under Settings → API Tokens. Files you saved to Downloads stay there.")
            }
        }
        VerticalScrollDecorator {}
    }
}
