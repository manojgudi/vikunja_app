import QtQuick 2.0
import Nemo.Notifications 1.0
import "../js/util.js" as Util

// Reminder and due-date notifications.
//
// With timed (the system alarm service) available, every upcoming due date
// and reminder is handed to timed, which starts the app in the background
// when one is due, even if the app is closed (see Alarms in C++). The list is
// re-synced whenever tasks change and every few hours in the background.
// Without timed the app checks once a minute while it runs.
QtObject {
    id: service

    property bool active: false
    property bool enabled: api.setting("notifications", true) !== false && api.setting("notifications", true) !== "false"
    property bool systemAlarms: alarms.available
    property var events: []
    property var shown: ({})
    property var notifications: []
    property int scheduled: 0
    property string lastSync: ""

    function clear() {
        events = []
        shown = {}
        for (var i = 0; i < notifications.length; ++i)
            notifications[i].close()
        notifications = []
        alarms.clear()
        scheduled = 0
    }

    function eventsFrom(tasks) {
        var list = []
        for (var i = 0; i < tasks.length; ++i) {
            var t = tasks[i]
            if (t.done)
                continue
            var due = Util.parseDate(t.due_date)
            if (due)
                list.push({ key: t.id + ":due:" + due.getTime(), task: t, taskId: t.id, time: due.getTime(), kind: "due" })
            var rs = t.reminders || []
            for (var j = 0; j < rs.length; ++j) {
                var rd = Util.parseDate(rs[j].reminder)
                if (rd)
                    list.push({ key: t.id + ":rem:" + rd.getTime(), task: t, taskId: t.id, time: rd.getTime(), kind: "reminder" })
            }
        }
        list.sort(function(a, b) { return a.time - b.time })
        return list
    }

    function refresh(callback) {
        if (!active || !enabled) {
            if (callback) callback(false)
            return
        }
        var query = {
            filter: "done = false && (due_date > now-1d || reminders > now-1d)",
            filter_include_nulls: "false",
            per_page: 200
        }
        api.request("GET", "/tasks", query, null, function(r) {
            if (!r.ok) {
                if (callback) callback(false)
                return
            }
            events = eventsFrom(r.data || [])
            if (systemAlarms) {
                var future = []
                var now = Date.now()
                for (var i = 0; i < events.length; ++i)
                    if (events[i].time > now)
                        future.push({ taskId: events[i].taskId, time: events[i].time, kind: events[i].kind })
                alarms.schedule(future, 6)
                scheduled = Math.min(future.length, 64)
                lastSync = Qt.formatDateTime(new Date(), "hh:mm")
            } else {
                check()
            }
            if (callback) callback(true)
        })
    }

    // In-app fallback when timed is missing.
    function check() {
        if (!active || !enabled || systemAlarms)
            return
        var now = Date.now()
        var last = Number(api.setting("lastReminderCheck", now - 60000))
        if (isNaN(last) || last > now || now - last > 86400000)
            last = now - 60000
        var fired = 0
        for (var i = 0; i < events.length && fired < 10; ++i) {
            var e = events[i]
            if (e.time > last && e.time <= now && !shown[e.key]) {
                shown[e.key] = true
                publish(e.task, e.kind, e.time)
                fired++
            }
        }
        api.setSetting("lastReminderCheck", now)
    }

    // Called when timed wakes the app. The attributes only say which task and
    // when; the task is fetched from the server, and the notification is only
    // shown if that task really has a due date or reminder at that time.
    function handleAlarm(taskId, kind, time, done) {
        function finish() { if (done) done() }
        if (kind === "sync") {
            refresh(finish)
            return
        }
        if (kind === "test") {
            sendTest(true)
            finish()
            return
        }
        if (!enabled || taskId <= 0) {
            finish()
            return
        }
        if (!api.authenticated) {
            publishGeneric(kind)
            finish()
            return
        }
        api.request("GET", "/tasks/" + taskId, {}, null, function(r) {
            if (!r.ok) {
                // Offline or the token is unavailable: still remind, without details.
                if (r.status !== 404 && r.status !== 403)
                    publishGeneric(kind)
                finish()
                return
            }
            var list = eventsFrom([r.data])
            for (var i = 0; i < list.length; ++i) {
                var e = list[i]
                if (e.kind === kind && Math.abs(e.time - time) < 60000 && e.time <= Date.now() + 60000 && !shown[e.key]) {
                    shown[e.key] = true
                    publish(e.task, e.kind, e.time)
                    break
                }
            }
            finish()
        })
    }

    function addActions(n, taskId) {
        if (appBridge.service.length === 0)
            return
        var acts = [
            { name: "default", displayName: qsTr("Open"), service: appBridge.service, path: appBridge.path,
              iface: appBridge.iface, method: taskId > 0 ? "openTask" : "activate", arguments: taskId > 0 ? [ taskId ] : [] }
        ]
        if (taskId > 0)
            acts.push({ name: "done", displayName: qsTr("Mark done"), service: appBridge.service, path: appBridge.path,
                        iface: appBridge.iface, method: "markDone", arguments: [ taskId ] })
        n.remoteActions = acts
    }

    function publish(task, kind, time) {
        var n = notificationComponent.createObject(service)
        var hide = app.hideDetails
        n.summary = hide ? qsTr("Vikunja task") : task.title
        n.body = kind === "due"
                ? (hide ? qsTr("A task is due now") : qsTr("Due %1").arg(Util.formatDate(new Date(time))))
                : (hide ? qsTr("You have a task reminder") : qsTr("Reminder"))
        n.previewSummary = n.summary
        n.previewBody = n.body
        addActions(n, task.id)
        n.publish()
        notifications.push(n)
    }

    function publishGeneric(kind) {
        var n = notificationComponent.createObject(service)
        n.summary = qsTr("Vikunja")
        n.body = kind === "due" ? qsTr("A task is due now") : qsTr("You have a task reminder")
        n.previewSummary = n.summary
        n.previewBody = n.body
        addActions(n, 0)
        n.publish()
        notifications.push(n)
    }

    function sendTest(scheduled) {
        var n = notificationComponent.createObject(service)
        n.summary = qsTr("Vikunja")
        n.body = scheduled ? qsTr("Scheduled reminder test: reminders work with the app closed")
                           : qsTr("Notifications are working")
        n.previewSummary = n.summary
        n.previewBody = n.body
        addActions(n, 0)
        n.publish()
        notifications.push(n)
    }

    property Component notificationComponent: Component {
        Notification {
            appName: "Vikunja"
            appIcon: "harbour-vikunja"
            // Short alert tone or vibration and a banner, see
            // notifications/x-harbour-vikunja.reminder.conf.
            category: "x-harbour-vikunja.reminder"
            urgency: Notification.Normal
        }
    }

    property Timer checkTimer: Timer {
        interval: 60000
        repeat: true
        running: service.active && service.enabled && !service.systemAlarms
        triggeredOnStart: true
        onTriggered: service.check()
    }

    property Timer refreshTimer: Timer {
        interval: 15 * 60000
        repeat: true
        running: service.active && service.enabled
        triggeredOnStart: true
        onTriggered: service.refresh()
    }

    // Re-sync shortly after any task is created, edited or completed.
    property Timer changeTimer: Timer {
        interval: 1500
        onTriggered: service.refresh()
    }

    property Connections appConnections: Connections {
        target: app
        onTaskRevisionChanged: service.changeTimer.restart()
    }

    onEnabledChanged: if (!enabled) alarms.clear()
    onActiveChanged: if (!active) clear()
}
