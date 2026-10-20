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
            { name: "project page shows tasks", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.tasks || p.tasks.length !== 1) console.error("Error: project page has " + (p.tasks ? p.tasks.length : "no") + " tasks")
                done()
            } },
            { name: "kanban page", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.kanbanView) console.error("Error: no kanban view found")
                push("KanbanPage.qml", { projectId: ctx.project.id, view: p.kanbanView, project: p.project })
                done()
            } },
            { name: "kanban has buckets", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.buckets || p.buckets.length < 1) console.error("Error: kanban has no buckets")
                ctx.buckets = p.buckets
                done()
            } },
            { name: "kanban move task", fn: function(done) {
                var p = win.pageStack.currentPage
                p.moveTask(ctx.task, ctx.buckets[ctx.buckets.length - 1].id)
                done()
            } },
            { name: "kanban add bucket dialog", fn: function(done) { win.pageStack.currentPage.addBucket(); done() } },
            { name: "close dialog", fn: function(done) { pop(); pop(); pop(); done() } },
            { name: "task page", fn: function(done) { win.openTask(ctx.task.id); done() } },
            { name: "task page loaded", fn: function(done) {
                var p = win.pageStack.currentPage
                if (!p.task || p.task.title !== "Smoke task") console.error("Error: task page did not load the task")
                done()
            } },
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
            { name: "submit add task", fn: function(done) {
                var d = win.pageStack.currentPage
                d.children[0] // keep dialog alive
                done()
            } },
            { name: "close add task", fn: function(done) { pop(); done() } },
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
            { name: "sign out", fn: function(done) { api.logout(); win.signedOut(); done() } }
        ])
    }
}
