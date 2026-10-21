import QtQuick 2.0

// Run by the qmlsmoke harness (SMOKE_DRIVER) for tests/e2e/run.sh: signs in,
// creates a task with a reminder and a due date, lets the app hand them to
// timed, waits for the first one to fire while the app runs, then quits so
// the second one has to start the app.
QtObject {
    id: driver

    property var win: null
    property bool finished: false
    property int steps: 0
    property var reminderAt
    property var dueAt
    property int ticks: 0

    function log(m) { console.log("SMOKE: E2E " + m) }

    property Timer poll: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            driver.ticks++
            var n = win.reminders.notifications.length
            if (driver.steps === 1 && win.reminders.lastSync.length > 0) {
                driver.steps = 2
                driver.log("scheduled with timed: " + alarms.scheduledCount() + " event(s), systemAlarms=" + win.reminders.systemAlarms)
            }
            if (driver.steps === 2 && n > 0) {
                driver.steps = 3
                var last = win.reminders.notifications[n - 1]
                driver.log("notification while running: " + last.summary + " / " + last.body)
            }
            if (driver.steps === 3 || driver.ticks > 60) {
                if (driver.steps !== 3) console.error("Error: E2E no notification while running")
                driver.log("quitting; due date fires at " + driver.dueAt.toISOString())
                driver.finished = driver.steps === 3
                driver.poll.stop()
                Qt.quit()
            }
        }
    }

    Component.onCompleted: {
        var c = Qt.createComponent(smokeQmlDir + "/harbour-vikunja.qml")
        win = c.createObject(null)
        api.loginWithToken(smokeUrl, smokeToken, function(r) {
            if (!r.ok) { console.error("Error: login " + r.error); Qt.quit(); return }
            win.currentUser = r.data
            api.request("PUT", "/projects", {}, { title: "E2E project" }, function(p) {
                reminderAt = new Date(Date.now() + 25000)
                dueAt = new Date(Date.now() + 55000)
                api.request("PUT", "/projects/" + p.data.id + "/tasks", {}, {
                    title: "E2E reminder task", due_date: dueAt.toISOString(),
                    reminders: [{ reminder: reminderAt.toISOString() }]
                }, function(t) {
                    driver.log("task " + t.data.id + " reminder " + reminderAt.toISOString())
                    // Same path as the add-task dialog.
                    win.taskRevision++
                    driver.steps = 1
                    driver.poll.start()
                })
            })
        })
    }
}
