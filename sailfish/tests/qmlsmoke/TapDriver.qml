import QtQuick 2.0

// The whole life of a tapped reminder, in a process started like the
// D-Bus activated app (SMOKE_BACKGROUND): the open call arrives while the
// start page is still loading, then the user reads the task, goes back,
// edits, saves, marks it done and taps more reminders. Needs a saved
// session (run RestartDriver's login phase first). SMOKE_PHASE:
//   tap      - the open call arrives right away
//   tapslow  - the open call arrives after the start page went home
//   donebg   - "Mark done" on a notification while the app is not open
//   taplogin - the session is gone (signed out or expired): the tap shows
//              the login page, and the task opens once signed in. Signs out,
//              so run it last.
QtObject {
    id: driver

    property var win: null
    property bool finished: false
    property int steps: 0
    property var ctx: ({})
    property var queue: []
    property bool backgroundFinished: false

    function log(m) { console.log("SMOKE: " + m) }

    function pageName(p) {
        p = p || win.pageStack.currentPage
        return p ? String(p).split("_QML")[0].split("(")[0] : ""
    }

    function stack() {
        var names = []
        var cur = win.pageStack.currentPage
        while (cur) {
            names.unshift(pageName(cur))
            cur = win.pageStack.previousPage(cur)
        }
        return names.join(" > ")
    }

    function expectStack(want) {
        var got = stack()
        if (got !== want)
            console.error("Error: expected pages " + want + " but the app has " + got)
        else
            log("  pages: " + got)
    }

    function run(list) { queue = list; next() }

    function next() {
        if (queue.length === 0) {
            log("all steps done")
            finished = true
            Qt.quit()
            return
        }
        var step = queue.shift()
        steps++
        log("step " + steps + ": " + step.name)
        try {
            step.fn(function() { timer.start() })
        } catch (e) {
            console.error("Error in step " + step.name + ": " + e + " " + e.stack)
            timer.start()
        }
    }

    property Timer timer: Timer { interval: 2500; onTriggered: driver.next() }
    // As soon as the event loop runs (Qt 5.6 has no Qt.callLater).
    property var soonCall: null
    property Timer soon: Timer { interval: 0; onTriggered: driver.soonCall() }
    function callSoon(fn) { soonCall = fn; soon.start() }

    function req(method, path, body, cb) {
        api.request(method, path, {}, body, function(r) {
            if (!r.ok) console.error("Error: API " + method + " " + path + " -> " + r.status + " " + r.error)
            cb(r)
        })
    }

    // What the user's back gesture does.
    function back() { win.pageStack.navigateBack(1 /* Immediate */) }

    function startApp() {
        var c = Qt.createComponent(smokeQmlDir + "/harbour-vikunja.qml")
        if (c.status !== Component.Ready) {
            console.error("Error: " + c.errorString())
            Qt.quit()
            return
        }
        win = c.createObject(null)
    }

    function taskSteps() {
        return [
            { name: "tapped task is showing, home page under it", fn: function(done) {
                if (appBridge.background) console.error("Error: still in background after the tap")
                var p = win.pageStack.currentPage
                if (pageName(p) !== "TaskPage" || p.taskId !== ctx.id) console.error("Error: expected the task page for " + ctx.id + ", app shows " + pageName(p))
                else if (!p.task || p.task.title !== "Tap lifecycle task") console.error("Error: task page did not load the task")
                expectStack("HomePage > TaskPage")
                done()
            } },
            { name: "back", fn: function(done) { back(); done() } },
            { name: "home page, not loading", fn: function(done) {
                expectStack("HomePage")
                var home = win.pageStack.currentPage
                if (home.loading) console.error("Error: home page still loading after back")
                done()
            } },
            { name: "still home a while later", fn: function(done) { expectStack("HomePage"); done() } },
            { name: "tap again while the app is open", fn: function(done) { appBridge.openTask(ctx.id); done() } },
            { name: "task page again", fn: function(done) { expectStack("HomePage > TaskPage"); done() } },
            { name: "same reminder tapped twice", fn: function(done) { appBridge.openTask(ctx.id); done() } },
            { name: "no second copy of the task", fn: function(done) { expectStack("HomePage > TaskPage"); done() } },
            { name: "edit", fn: function(done) { win.pageStack.currentPage.edit(); done() } },
            { name: "edit dialog open", fn: function(done) {
                expectStack("HomePage > TaskPage > TaskEditDialog")
                var d = win.pageStack.currentPage
                d.titleText = "Tap lifecycle task edited"
                d.accept()
                done()
            } },
            { name: "saved, back on the task", fn: function(done) {
                expectStack("HomePage > TaskPage")
                var p = win.pageStack.currentPage
                if (!p.task || p.task.title !== "Tap lifecycle task edited") console.error("Error: task page shows " + (p.task ? p.task.title : null) + " after save")
                req("GET", "/tasks/" + ctx.id, null, function(r) {
                    if (r.data.title !== "Tap lifecycle task edited") console.error("Error: edit not saved on the server")
                    done()
                })
            } },
            { name: "mark done on the task page", fn: function(done) {
                var p = win.pageStack.currentPage
                win.setTaskDone(p.task, true)
                done()
            } },
            { name: "task shows done", fn: function(done) {
                var p = win.pageStack.currentPage
                expectStack("HomePage > TaskPage")
                if (!p.task || !p.task.done) console.error("Error: task page not done after marking it done")
                req("GET", "/tasks/" + ctx.id, null, function(r) {
                    if (!r.data.done) console.error("Error: done not saved on the server")
                    done()
                })
            } },
            { name: "mark undone again", fn: function(done) { win.setTaskDone(win.pageStack.currentPage.task, false); done() } },
            { name: "edit and cancel", fn: function(done) { win.pageStack.currentPage.edit(); done() } },
            { name: "cancel the edit", fn: function(done) { win.pageStack.currentPage.reject(); done() } },
            { name: "back on the task after cancel", fn: function(done) { expectStack("HomePage > TaskPage"); done() } },
            { name: "back to home", fn: function(done) { back(); done() } },
            { name: "home after editing", fn: function(done) { expectStack("HomePage"); done() } },
            { name: "Mark done from a notification while open", fn: function(done) { appBridge.markDone(ctx.id); done() } },
            { name: "done, still home, app still running", fn: function(done) {
                expectStack("HomePage")
                if (driver.backgroundFinished) console.error("Error: the open app wanted to exit after Mark done")
                req("GET", "/tasks/" + ctx.id, null, function(r) {
                    if (!r.data.done) console.error("Error: Mark done from the notification did not save")
                    done()
                })
            } },
            { name: "open settings, then tap a reminder", fn: function(done) {
                win.pageStack.push(Qt.resolvedUrl(smokeQmlDir + "/pages/SettingsPage.qml"), {}, 1)
                appBridge.openTask(ctx.id)
                done()
            } },
            { name: "task over settings", fn: function(done) { expectStack("HomePage > SettingsPage > TaskPage"); done() } },
            { name: "back to settings", fn: function(done) { back(); done() } },
            { name: "settings", fn: function(done) { expectStack("HomePage > SettingsPage"); back(); done() } },
            { name: "home at the end", fn: function(done) {
                expectStack("HomePage")
                if (driver.backgroundFinished) console.error("Error: app asked to exit while in use")
                done()
            } },
            { name: "cleanup", fn: function(done) { req("DELETE", "/tasks/" + ctx.id, null, function() { done() }) } }
        ]
    }

    Component.onCompleted: {
        appBridge.backgroundFinished.connect(function() { driver.backgroundFinished = true; driver.log("background finished") })
        if (!api.authenticated) {
            console.error("Error: no saved session; run the login phase first")
            Qt.quit()
            return
        }
        // A task the reminder is about, made before the app starts.
        req("GET", "/projects", null, function(r) {
            var project = (r.data || []).filter(function(p) { return p.id > 0 && !p.is_archived })[0]
            req("PUT", "/projects/" + project.id + "/tasks", { title: "Tap lifecycle task" }, function(t) {
                ctx.id = t.data.id
                log("task " + ctx.id)
                startApp()
                if (smokePhase === "tap") {
                    // lipstick's call waits in the bus until the app owns
                    // its name, so it lands as soon as the event loop runs.
                    callSoon(function() { appBridge.openTask(ctx.id) })
                    timer.start()
                    queue = taskSteps()
                } else if (smokePhase === "tapslow") {
                    run([
                        { name: "wait for the start page", fn: function(done) { done() } },
                        { name: "wait more", fn: function(done) { done() } },
                        { name: "start page done, still hidden", fn: function(done) {
                            expectStack("HomePage")
                            if (!appBridge.background) console.error("Error: window shown without a tap")
                            appBridge.openTask(ctx.id)
                            done()
                        } }
                    ].concat(taskSteps()))
                } else if (smokePhase === "taplogin") {
                    run([
                        { name: "wait for the start page", fn: function(done) { done() } },
                        { name: "sign out, then tap", fn: function(done) {
                            api.logout()
                            win.signedOut()
                            appBridge.openTask(ctx.id)
                            done()
                        } },
                        { name: "login page, task waits", fn: function(done) {
                            expectStack("LoginPage")
                            api.loginWithPassword(smokeUrl, smokeUser, smokePassword, "", function(r) {
                                if (!r.ok) console.error("Error: sign in failed " + r.error)
                                // What the login page does on success.
                                win.currentUser = r.data
                                win.goHome()
                                done()
                            })
                        } },
                        { name: "task opens after signing in", fn: function(done) {
                            expectStack("HomePage > TaskPage")
                            back()
                            done()
                        } },
                        { name: "back to home", fn: function(done) {
                            expectStack("HomePage")
                            req("DELETE", "/tasks/" + ctx.id, null, function() { done() })
                        } }
                    ])
                } else if (smokePhase === "donebg") {
                    callSoon(function() { appBridge.markDone(ctx.id) })
                    run([
                        { name: "wait", fn: function(done) { done() } },
                        { name: "wait for the exit delay", fn: function(done) { done() } },
                        { name: "done saved, window never shown, app exits", fn: function(done) {
                            if (!appBridge.background) console.error("Error: Mark done showed the window")
                            if (!driver.backgroundFinished) console.error("Error: background instance did not finish")
                            req("GET", "/tasks/" + ctx.id, null, function(r) {
                                if (!r.data.done) console.error("Error: Mark done in the background did not save")
                                req("DELETE", "/tasks/" + ctx.id, null, function() { done() })
                            })
                        } }
                    ])
                }
            })
        })
    }
}
