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
                // Password sign-in is the only way in now; older sessions may still use a pasted token.
                visible: api.authMethod !== "password"
                label: qsTr("Signed in with")
                value: qsTr("API token")
            }
            DetailItem {
                visible: api.tokenExpires.length > 0
                label: qsTr("Token expires")
                value: Util.formatDate(Util.parseDate(api.tokenExpires))
            }
            DetailItem {
                label: qsTr("Token stored")
                value: api.tokenStorage === "secrets" ? qsTr("Encrypted")
                     : api.tokenStorage === "file" ? qsTr("Private file") : qsTr("Memory only")
            }
            TextSwitch {
                // Only offered when Secrets is not doing its job.
                visible: !api.secretsWorking && api.persistentLogin
                text: qsTr("Store the token in a file")
                description: qsTr("Unencrypted file that only this app can read")
                checked: api.fileFallback === "allowed"
                automaticCheck: false
                onClicked: api.setFileFallback(!checked)
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
                description: qsTr("For new tasks from home and the cover")
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
                             ? qsTr("Arrive even when the app is closed")
                             : qsTr("Only while the app is running")
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
                description: qsTr("No task titles in notifications or on the cover")
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
                      ? qsTr("%n scheduled, synced %1", "", app.reminders.scheduled).arg(app.reminders.lastSync)
                      : qsTr("Not synced yet")
            }
            Item { width: 1; height: Theme.paddingMedium }
            ButtonLayout {
                Button {
                    text: qsTr("Test now")
                    onClicked: app.reminders.sendTest(false)
                }
                Button {
                    visible: app.reminders.systemAlarms
                    text: qsTr("Test in 1 min")
                onClicked: {
                    if (alarms.scheduleTest(60))
                        app.notify(qsTr("Close the app now; the reminder arrives in a minute."))
                    else
                        app.notify(qsTr("Could not schedule the test reminder"))
                    }
                }
            }

            SectionHeader { text: qsTr("Appearance") }
            ComboBox {
                label: qsTr("Theme")
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
                text: qsTr("None yet")
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
            DetailItem { label: qsTr("Version"); value: qsTr("%1 (beta)").arg(appVersion) }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Tasks are never stored on the phone. The app runs sandboxed and keeps its token encrypted. This is beta software, provided without warranty.")
            }

            Item { width: 1; height: Theme.paddingLarge }
            ButtonLayout {
                Button {
                    text: qsTr("Sign out")
                    onClicked: Remorse.popupAction(page, qsTr("Signing out"), function() {
                        api.logout()
                        app.signedOut()
                    })
                }
            }
            Item { width: 1; height: Theme.paddingMedium }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Clears the token, reminders and previews from this phone. To revoke the token on the server, delete it in Vikunja under Settings → API Tokens.")
            }
        }
        VerticalScrollDecorator {}
    }
}
