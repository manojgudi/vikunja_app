import QtQuick 2.0

// Drives the app through all pages. See main.cpp.
QtObject {
    id: driver

    property var win: null
    property bool finished: false
    property int steps: 0
    property var ctx: ({})
    property var queue: []

    function log(m) { console.log("SMOKE: " + m) }

    function run(list) {
        queue = list
        next()
    }

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

    function req(method, path, body, cb) {
        api.request(method, path, {}, body, function(r) {
            if (!r.ok) console.error("Error: API " + method + " " + path + " -> " + r.status + " " + r.error)
            cb(r)
        })
    }

    function push(page, props) {
        return win.pageStack.push(Qt.resolvedUrl(smokeQmlDir + "/pages/" + page), props || {}, 1 /* Immediate */)
    }

    function pop() { win.pageStack.pop(undefined, 1) }

    property Timer timer: Timer { interval: 1500; onTriggered: driver.next() }

    Component.onCompleted: {
        var c = Qt.createComponent(smokeQmlDir + "/harbour-vikunja.qml")
        if (c.status !== Component.Ready) {
            console.error("Error: " + c.errorString())
            Qt.quit()
            return
        }
        win = c.createObject(null)
        run([
            { name: "startup shows login", fn: function(done) { done() } },
            { name: "login with token", fn: function(done) {
                api.loginWithToken(smokeUrl, smokeToken, function(r) {
                    if (!r.ok) console.error("Error: login failed " + r.error)
                    win.currentUser = r.data
                    win.loadProjects(function() { win.loadLabels(function() { done() }) })
                })
            } },
            { name: "seed data", fn: function(done) {
                req("PUT", "/projects", { title: "Smoke project" }, function(p) {
                    ctx.project = p.data
                    req("PUT", "/projects/" + p.data.id + "/tasks", {
                        title: "Smoke task", description: "<p>Hello <b>world</b><img src='https://tracker.invalid/x.png'></p>",
                        due_date: new Date(Date.now() + 3600000).toISOString(), priority: 4,
                        reminders: [{ reminder: new Date(Date.now() + 1800000).toISOString() }]
                    }, function(t) {
                        ctx.task = t.data
                        req("PUT", "/tasks/" + t.data.id + "/comments", { comment: "<p>Smoke comment</p>" }, function() {
                            req("PUT", "/labels", { title: "smoke", hex_color: "e8445a" }, function(l) {
                                ctx.label = l.data
                                req("POST", "/tasks/" + t.data.id + "/labels/bulk", { labels: [{ id: l.data.id }] }, function() {
                                    win.loadProjects(function() { done() })
                                })
                            })
                        })
                    })
                })
            } },
            { name: "home page", fn: function(done) { win.pageStack.replace(Qt.resolvedUrl(smokeQmlDir + "/pages/HomePage.qml"), {}, 1); done() } },
            { name: "projects page", fn: function(done) { push("ProjectsPage.qml"); done() } },
            { name: "project page", fn: function(done) { push("ProjectPage.qml", { projectId: ctx.project.id }); done() } },
            { name: "project opens as board", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.kanbanView) console.error("Error: no kanban view found")
                if (!p.boardMode) console.error("Error: project did not open as a board")
                done()
            } },
            { name: "board has buckets", fn: function(done) {
                var b = win.pageStack.currentPage.board
                if (!b || !b.buckets || b.buckets.length < 1) console.error("Error: board has no buckets")
                else if (b.columnWidth <= 0 || b.columnWidth >= b.width) console.error("Error: bad column width " + b.columnWidth)
                ctx.buckets = b ? b.buckets : []
                var found = false
                for (var i = 0; i < ctx.buckets.length; ++i)
                    for (var j = 0; j < (ctx.buckets[i].tasks || []).length; ++j)
                        if (ctx.buckets[i].tasks[j].id === ctx.task.id) found = true
                if (!found) console.error("Error: smoke task not on the board")
                done()
            } },
            { name: "board move task", fn: function(done) {
                // The last bucket is usually "Done", which would hide the task from the list.
                win.pageStack.currentPage.board.moveTask(ctx.task, ctx.buckets[Math.min(1, ctx.buckets.length - 1)].id)
                done()
            } },
            { name: "board shows moved task", fn: function(done) {
                var b = win.pageStack.currentPage.board
                var last = b.buckets[Math.min(1, b.buckets.length - 1)]
                var ok = false
                for (var j = 0; j < (last.tasks || []).length; ++j)
                    if (last.tasks[j].id === ctx.task.id) ok = true
                if (!ok) console.error("Error: task not in the target bucket after the move")
                done()
            } },
            { name: "switch to list", fn: function(done) { win.pageStack.currentPage.setLayout("list"); done() } },
            { name: "list shows tasks", fn: function(done) {
                var p = win.pageStack.currentPage
                if (p.boardMode) console.error("Error: still in board mode")
                if (!p.tasks || p.tasks.length < 1) console.error("Error: list has " + (p.tasks ? p.tasks.length : "no") + " tasks")
                if (api.setting("layout/" + ctx.project.id, "") !== "list") console.error("Error: layout choice not saved")
                p.setLayout("board")
                done()
            } },
            { name: "board add bucket dialog", fn: function(done) { win.pageStack.currentPage.board.addBucket(); done() } },
            { name: "close dialog", fn: function(done) { pop(); pop(); pop(); done() } },
            { name: "date time dialog", fn: function(done) {
                var d = push("DateTimeDialog.qml", { selected: new Date(2026, 9, 22, 9, 30) })
                if (d.hour !== 9 || d.minute !== 30) console.error("Error: dialog time " + d.hour + ":" + d.minute)
                d.setTime(17, 45)
                var r = d.result()
                if (r.getHours() !== 17 || r.getMinutes() !== 45 || r.getDate() !== 22) console.error("Error: dialog result " + r)
                ctx.dtDialog = d
                d.accepted.connect(function() { ctx.dtSelected = d.selected })
                d.accept()
                done()
            } },
            { name: "date time dialog returns", fn: function(done) {
                if (win.pageStack.currentPage === ctx.dtDialog) console.error("Error: date dialog still open after accept")
                var s = ctx.dtSelected
                if (!s || s.getHours() !== 17 || s.getMinutes() !== 45) console.error("Error: accepted value " + s)
                done()
            } },
            { name: "task page from notification", fn: function(done) {
                // What tapping a reminder notification calls over D-Bus.
                appBridge.openTask(ctx.task.id)
                done()
            } },
            { name: "task page loaded", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.task || p.task.title !== "Smoke task") console.error("Error: task page did not load the task")
                done()
            } },
            { name: "attach photo", fn: function(done) {
                var p = win.pageStack.currentPage
                p.upload(smokePhoto)
                done()
            } },
            { name: "wait for upload", fn: function(done) { done() } },
            { name: "photo attached", fn: function(done) {
                var p = win.pageStack.currentPage
                var atts = p.task.attachments || []
                if (atts.length !== 1) console.error("Error: task has " + atts.length + " attachments after upload")
                else if (!p.isImage(atts[0])) console.error("Error: uploaded png not recognised as image " + JSON.stringify(atts[0].file))
                else { ctx.attachment = atts[0]; p.openAttachment(atts[0]) }
                done()
            } },
            { name: "photo preview", fn: function(done) {
                var v = win.pageStack.currentPage
                if (String(v.source).indexOf("image://attachment/") !== 0) console.error("Error: no in-memory preview, source=" + v.source + " " + v.errorText)
                pop()
                done()
            } },
            { name: "file picker", fn: function(done) { win.pageStack.currentPage.pickFile(); done() } },
            { name: "close picker", fn: function(done) { pop(); done() } },
            { name: "task edit dialog", fn: function(done) { win.pageStack.currentPage.edit(); done() } },
            { name: "save task edit", fn: function(done) {
                var d = win.pageStack.currentPage
                d.accept()
                done()
            } },
            { name: "comments page", fn: function(done) { push("CommentsPage.qml", { taskId: ctx.task.id }); done() } },
            { name: "comments loaded", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.comments || p.comments.length !== 1) console.error("Error: comments page has " + (p.comments ? p.comments.length : 0) + " comments")
                pop(); done()
            } },
            { name: "labels page", fn: function(done) { push("TaskLabelsPage.qml", { task: win.pageStack.currentPage.task }); done() } },
            { name: "back from labels", fn: function(done) { pop(); pop(); done() } },
            { name: "add task dialog", fn: function(done) { win.openAddTask(ctx.project.id); done() } },
            { name: "add task presets", fn: function(done) {
                var d = win.pageStack.currentPage
                d.preset("tomorrow")
                var v = d.dueValue()
                var t = new Date(); t.setDate(t.getDate() + 1)
                if (!v || v.getDate() !== t.getDate() || v.getHours() !== 9) console.error("Error: tomorrow preset gave " + v)
                d.preset("")
                if (d.dueValue() !== null) console.error("Error: none preset did not clear")
                // Due in 20 seconds, for the reminder check below.
                d.setDue(new Date(Date.now() + 20000))
                d.setTitle("Smoke reminder task")
                d.accept()
                done()
            } },
            { name: "wait for reminder sync", fn: function(done) { done() } },
            { name: "new task scheduled", fn: function(done) {
                var es = win.reminders.events
                var found = false
                for (var i = 0; i < es.length; ++i)
                    if (es[i].task.title === "Smoke reminder task" && es[i].kind === "due") { found = true; ctx.remEvent = es[i] }
                if (!found) console.error("Error: new task not picked up by reminders after creating it")
                done()
            } },
            { name: "alarm fires notification", fn: function(done) {
                var before = win.reminders.notifications.length
                // What timed sends: string attributes.
                var e = ctx.remEvent
                win.reminders.handleAlarm(e.taskId, "due", e.time, function() {
                    if (win.reminders.notifications.length !== before + 1) console.error("Error: alarm did not publish a notification")
                    var n = win.reminders.notifications[win.reminders.notifications.length - 1]
                    if (n && n.summary !== "Smoke reminder task") console.error("Error: notification summary " + n.summary)
                    // A forged call with a wrong time must not show anything.
                    win.reminders.handleAlarm(e.taskId, "reminder", e.time + 3600000, function() {
                        if (win.reminders.notifications.length !== before + 1) console.error("Error: forged alarm published a notification")
                        done()
                    })
                })
            } },
            { name: "theme light", fn: function(done) {
                win.setThemeMode("light")
                var p = win.pageStack.currentPage
                if (p.palette.colorScheme !== 1) console.error("Error: light theme not applied, scheme " + p.palette.colorScheme)
                if (String(p.backgroundColor) !== "#f5f5f7") console.error("Error: light background " + p.backgroundColor)
                var pc = p.palette.primaryColor
                if (pc.r > 0.5 && pc.g > 0.5 && pc.b > 0.5) console.error("Error: light theme text is still light " + pc)
                done()
            } },
            { name: "theme dark", fn: function(done) {
                win.setThemeMode("dark")
                var p = win.pageStack.currentPage
                var pc = p.palette.primaryColor
                if (p.palette.colorScheme !== 0 || pc.r < 0.5) console.error("Error: dark theme not applied " + pc)
                if (api.setting("theme", "") !== "dark") console.error("Error: theme not saved")
                win.setThemeMode("system")
                done()
            } },
            { name: "settings page", fn: function(done) { push("SettingsPage.qml"); done() } },
            { name: "test notification", fn: function(done) { win.reminders.sendTest(); win.reminders.refresh(); done() } },
            { name: "certificate dialog", fn: function(done) {
                push("CertificateDialog.qml", { certificate: { host: "h", port: 443, sha256: "AA:BB", subject: "s", issuer: "i", expires: "e", errors: ["x"] } })
                done()
            } },
            { name: "insecure dialog", fn: function(done) { pop(); push("InsecureHttpDialog.qml", { host: "h" }); done() } },
            { name: "download dialog", fn: function(done) { pop(); push("DownloadDialog.qml", { fileName: "a.txt", fileSize: 1234 }); done() } },
            { name: "cover", fn: function(done) {
                var c = win.cover
                if (!c) console.error("Error: no cover component")
                else { var o = win.cover.createObject(win); o.refresh() }
                pop(); pop(); done()
            } },
            { name: "verify edit persisted", fn: function(done) {
                req("GET", "/tasks/" + ctx.task.id, null, function(r) {
                    if (r.data.title !== "Smoke task") console.error("Error: task title changed unexpectedly")
                    if (!r.data.labels || r.data.labels.length !== 1) console.error("Error: labels lost after edit")
                    if ((r.data.reminders || []).length !== 1) console.error("Error: reminders lost after edit")
                    done()
                })
            } },
            { name: "cleanup", fn: function(done) {
                req("DELETE", "/projects/" + ctx.project.id, null, function() {
                    req("DELETE", "/labels/" + ctx.label.id, null, function() { done() })
                })
            } },
            { name: "sign out", fn: function(done) { api.logout(); win.signedOut(); done() } },
            { name: "login is password first", fn: function(done) {
                var p = win.pageStack.currentPage
                if (p.needTotp) console.error("Error: login starts at the 2FA step")
                p.handleError({ errorCode: "totp_required", error: "" })
                if (!p.needTotp) console.error("Error: 2FA step not shown after the server asked for it")
                p.backToPassword()
                if (p.needTotp) console.error("Error: back did not return to the password step")
                done()
            } }
        ])
    }
}
