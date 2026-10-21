import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    // Light/dark choice from the settings page.
    palette.colorScheme: app.colorScheme
    palette.highlightColor: app.highlightColor
    palette.secondaryHighlightColor: app.secondaryHighlightColor
    backgroundColor: app.pageBackground

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: true
    }

    function goHome() {
        pageStack.replace(Qt.resolvedUrl("HomePage.qml"), {}, PageStackAction.Immediate)
    }

    Timer {
        // Let the page stack finish its initial push first.
        interval: 0
        running: true
        onTriggered: {
            if (!api.restoreSession()) {
                // Not when started in the background: right after a reboot the
                // token can be locked until the phone is unlocked once.
                if (!appBridge.background || api.sessionNotice === "inactive")
                    alarms.clear()
                api.diag("startup: login page, background=" + appBridge.background + " notice=" + api.sessionNotice)
                pageStack.replace(Qt.resolvedUrl("LoginPage.qml"), {}, PageStackAction.Immediate)
                return
            }
            if (!appBridge.background)
                api.touchSession()
            app.loadUser(function(r) {
                api.diag("startup: user loaded ok=" + r.ok + " status=" + r.status + " authenticated=" + api.authenticated)
                if (!api.authenticated)
                    return // token rejected; the app already went back to the login page
                if (!r.ok && r.errorCode !== "http") {
                    // Offline or server unreachable: still open the app, lists show the error.
                    app.notify(r.error)
                }
                app.loadProjects()
                app.loadLabels()
                goHome()
                app.askStorageChoice()
            })
        }
    }
}
