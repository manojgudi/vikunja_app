import QtQuick 2.0
import Nemo.Notifications 1.0
import "../js/util.js" as Util

// Shows reminder and due-date notifications while the app is running
// (including when it is minimised to its cover). This is the Harbour-safe
// path: it uses no background daemon and no alarm scheduling.
QtObject {
    id: service

    property bool active: false
    property bool enabled: api.setting("notifications", true) !== false && api.setting("notifications", true) !== "false"
    property var events: []
    property var shown: ({})
    property var notifications: []

    function clear() {
        events = []
        shown = {}
        for (var i = 0; i < notifications.length; ++i)
            notifications[i].close()
        notifications = []
    }

    function refresh() {
        if (!active || !enabled)
            return
        var query = {
            filter: "done = false && (due_date > now-1d || reminders > now-1d)",
            filter_include_nulls: "false",
            per_page: 200
        }
        api.request("GET", "/tasks", query, null, function(r) {
            if (!r.ok)
                return
            var list = []
            var tasks = r.data || []
            for (var i = 0; i < tasks.length; ++i) {
                var t = tasks[i]
                var due = Util.parseDate(t.due_date)
                if (due)
                    list.push({ key: t.id + ":due:" + due.getTime(), task: t, time: due.getTime(), kind: "due" })
                var rs = t.reminders || []
                for (var j = 0; j < rs.length; ++j) {
                    var rd = Util.parseDate(rs[j].reminder)
                    if (rd)
                        list.push({ key: t.id + ":rem:" + rd.getTime(), task: t, time: rd.getTime(), kind: "reminder" })
                }
            }
            events = list
            check()
        })
    }

    function check() {
        if (!active || !enabled)
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
                publish(e)
                fired++
            }
        }
        api.setSetting("lastReminderCheck", now)
    }

    function publish(e) {
        var n = notificationComponent.createObject(service)
        var hide = app.hideDetails
        n.summary = hide ? qsTr("Vikunja task") : e.task.title
        n.body = e.kind === "due"
                ? (hide ? qsTr("A task is due now") : qsTr("Due %1").arg(Util.formatDate(new Date(e.time))))
                : (hide ? qsTr("You have a task reminder") : qsTr("Reminder"))
        n.previewSummary = n.summary
        n.previewBody = n.body
        if (appBridge.service.length > 0) {
            n.remoteActions = [
                { name: "default", displayName: qsTr("Open"), service: appBridge.service, path: appBridge.path,
                  iface: appBridge.iface, method: "openTask", arguments: [ e.task.id ] },
                { name: "done", displayName: qsTr("Mark done"), service: appBridge.service, path: appBridge.path,
                  iface: appBridge.iface, method: "markDone", arguments: [ e.task.id ] }
            ]
        }
        n.publish()
        notifications.push(n)
    }

    function sendTest() {
        var n = notificationComponent.createObject(service)
        n.summary = qsTr("Vikunja")
        n.body = qsTr("Notifications are working")
        n.previewSummary = n.summary
        n.previewBody = n.body
        n.publish()
        notifications.push(n)
    }

    property Component notificationComponent: Component {
        Notification {
            appName: "Vikunja"
            appIcon: "harbour-vikunja"
            urgency: Notification.Normal
        }
    }

    property Timer checkTimer: Timer {
        interval: 60000
        repeat: true
        running: service.active && service.enabled
        triggeredOnStart: true
        onTriggered: service.check()
    }

    property Timer refreshTimer: Timer {
        interval: 5 * 60000
        repeat: true
        running: service.active && service.enabled
        triggeredOnStart: true
        onTriggered: service.refresh()
    }

    onActiveChanged: if (!active) clear()
}
