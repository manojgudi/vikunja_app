import QtQuick 2.0

// Starts the real app QML once per process, so several runs in a row act
// like closing and reopening the app. SMOKE_PHASE picks what this run checks:
//   login   - expects the login page, signs in with username and password
//   reopen  - expects to land on the home page without signing in
//   signout - expects the home page, then signs out
//   after   - expects the login page again
QtObject {
    id: driver

    property var win: null
    property bool finished: false
    property int steps: 0

    function log(m) { console.log("SMOKE: " + m) }

    function pageName() {
        var p = win.pageStack.currentPage
        return p ? String(p).split("_QML")[0].split("(")[0] : ""
    }

    function expectPage(name) {
        steps++
        if (pageName() !== name)
            console.error("Error: expected " + name + " but the app shows " + pageName())
        else
            log(smokePhase + ": app shows " + name)
    }

    function done() {
        finished = true
        Qt.quit()
    }

    property Timer settle: Timer {
        interval: 4000
        onTriggered: {
            if (smokePhase === "login") {
                driver.expectPage("LoginPage")
                api.loginWithPassword(smokeUrl, smokeUser, smokePassword, "", function(r) {
                    driver.steps++
                    if (!r.ok)
                        console.error("Error: sign in failed " + r.error)
                    driver.log("login: token kept in " + api.tokenStorage)
                    driver.done()
                })
            } else if (smokePhase === "reopen") {
                driver.expectPage("HomePage")
                driver.done()
            } else if (smokePhase === "signout") {
                driver.expectPage("HomePage")
                api.logout()
                win.signedOut()
                driver.done()
            } else {
                driver.expectPage("LoginPage")
                driver.done()
            }
        }
    }

    Component.onCompleted: {
        var c = Qt.createComponent(smokeQmlDir + "/harbour-vikunja.qml")
        if (c.status !== Component.Ready) {
            console.error("Error: " + c.errorString())
            Qt.quit()
            return
        }
        win = c.createObject(null)
        settle.start()
    }
}
