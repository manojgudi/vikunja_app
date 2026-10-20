import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

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
                pageStack.replace(Qt.resolvedUrl("LoginPage.qml"), {}, PageStackAction.Immediate)
                return
            }
            app.loadUser(function(r) {
                if (!api.authenticated)
                    return // token rejected; the app already went back to the login page
                if (!r.ok && r.errorCode !== "http") {
                    // Offline or server unreachable: still open the app, lists show the error.
                    app.notify(r.error)
                }
                app.loadProjects()
                app.loadLabels()
                goHome()
            })
        }
    }
}
