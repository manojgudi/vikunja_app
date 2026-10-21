import QtQuick 2.0
import "../../qml/js/util.js" as Util

// Starts the real app QML once per process, so several runs in a row act
// like closing and reopening the app. SMOKE_PHASE picks what this run checks:
//   login   - expects the login page, signs in with username and password,
//             and accepts the storage prompt if one appears (no Secrets
//             daemon in the build engine, so it does)
//   decline - like login, but says no to the storage prompt
//   reopen  - expects to land on the home page without signing in
//   signout - expects the home page, then signs out
//   after   - expects the login page again
//   stale   - the login page is showing although the session is restored
//             (what a reminder start used to leave behind); expects home
//   reminder - like a start by timed: a reminder call arrives right away,
//             racing the start page's own session restore; expects home
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
        interval: 8000
        onTriggered: {
            if (smokePhase === "login" || smokePhase === "decline") {
                driver.expectPage("LoginPage")
                api.loginWithPassword(smokeUrl, smokeUser, smokePassword, "", function(r) {
                    driver.steps++
                    if (!r.ok)
                        console.error("Error: sign in failed " + r.error)
                    driver.log(smokePhase + ": storage prompt needed: " + api.storageChoiceNeeded)
                    win.pageStack.replace(Qt.resolvedUrl(smokeQmlDir + "/pages/HomePage.qml"), {}, 1)
                    win.askStorageChoice()
                    prompt.start()
                })
            } else if (smokePhase === "cover") {
                // Needs open tasks due later today on the server.
                // 14:00 with five tasks due today at different times, one
                // overdue from the morning, one tomorrow and one done.
                var base = new Date(2026, 9, 21, 14, 0, 0)
                function at(h, m, extra) {
                    var t = { due_date: new Date(2026, 9, 21, h, m).toISOString(), done: false }
                    for (var k in extra) t[k] = extra[k]
                    return t
                }
                var c = Util.coverCounts([at(9, 0), at(14, 30), at(16, 0), at(18, 15), at(20, 0), at(23, 59),
                                          { due_date: new Date(2026, 9, 22, 9, 0).toISOString(), done: false },
                                          at(15, 0, { done: true })], base)
                driver.steps++
                driver.log("cover: " + c.today + " due later today, " + c.overdue + " overdue")
                if (c.today !== 5 || c.overdue !== 1)
                    console.error("Error: cover counts wrong")
                // And against the server (needs a task due later today).
                api.request("GET", "/tasks", { filter: "done = false && due_date < now+2d", filter_include_nulls: "false" }, null, function(r) {
                    driver.log("cover (server): ok=" + r.ok + " status=" + r.status + " tasks=" + (r.data ? r.data.length : -1) + " " + r.error)
                    var live = Util.coverCounts(r.data || [], new Date())
                    driver.log("cover (server): " + live.today + " due later today, " + live.overdue + " overdue")
                    if (live.today < 1)
                        console.error("Error: cover counts no task due later today")
                    driver.done()
                })
            } else if (smokePhase === "stale") {
                win.pageStack.replace(Qt.resolvedUrl(smokeQmlDir + "/pages/LoginPage.qml"), {}, 1)
                stale.start()
            } else if (smokePhase === "reopen" || smokePhase === "reminder") {
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

    property Timer stale: Timer {
        interval: 4000
        onTriggered: {
            driver.expectPage("HomePage")
            driver.done()
        }
    }

    property Timer prompt: Timer {
        interval: 2000
        onTriggered: {
            driver.steps++
            if (win.pageStack.currentPage.objectName !== "storageChoiceDialog")
                console.error("Error: expected the storage prompt but the app shows " + driver.pageName())
            else
                driver.log(smokePhase + ": storage prompt shown")
            if (smokePhase === "login")
                win.pageStack.currentPage.accept()
            else
                win.pageStack.currentPage.reject()
            finish.start()
        }
    }

    property Timer finish: Timer {
        interval: 2000
        onTriggered: {
            driver.log(smokePhase + ": token kept in " + api.tokenStorage + ", fallback " + api.fileFallback)
            driver.done()
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
        if (smokePhase === "reminder")
            appBridge.reminderDue("test", 0, Math.floor(Date.now() / 1000))
        settle.start()
    }
}
