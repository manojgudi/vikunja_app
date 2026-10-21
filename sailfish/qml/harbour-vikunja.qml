import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "cover"
import "components"
import "js/util.js" as Util

ApplicationWindow {
    id: app

    property var currentUser: null
    property var projects: []
    property var labels: []
    property int defaultProjectId: currentUser && currentUser.settings ? (currentUser.settings.default_project_id || 0) : 0
    property bool hideDetails: api.setting("hideDetails", false) === true || api.setting("hideDetails", false) === "true"

    // Bumped whenever tasks change somewhere so open lists can refresh.
    property int taskRevision: 0
    property int projectRevision: 0

    property alias reminders: reminderService

    // "system" follows the ambience; "light" and "dark" use a plain
    // background with matching text colours.
    property string themeMode: String(api.setting("theme", "system"))
    readonly property int colorScheme: themeMode === "light" ? Theme.DarkOnLight
                                     : themeMode === "dark" ? Theme.LightOnDark
                                     : Theme.colorScheme
    readonly property color highlightColor: themeMode === "system" ? Theme.highlightColor
                                          : Theme.highlightFromColor(Theme.highlightColor, colorScheme)
    readonly property color secondaryHighlightColor: themeMode === "system" ? Theme.secondaryHighlightColor
                                                   : Theme.secondaryHighlightFromColor(Theme.highlightColor, colorScheme)
    readonly property color pageBackground: themeMode === "light" ? "#f5f5f7"
                                          : themeMode === "dark" ? "#121216"
                                          : "transparent"

    function setThemeMode(mode) {
        api.setSetting("theme", mode)
        themeMode = mode
    }

    signal taskChanged(int taskId)

    initialPage: Component { StartupPage { } }
    cover: Component { CoverPage { } }
    allowedOrientations: defaultAllowedOrientations

    function notify(text) {
        banner.show(text)
    }

    function showError(result, fallback) {
        notify(result && result.error ? result.error : (fallback || qsTr("Something went wrong")))
    }

    function projectById(id) {
        for (var i = 0; i < projects.length; ++i)
            if (projects[i].id === id)
                return projects[i]
        return null
    }

    function projectTitle(id) {
        var p = projectById(id)
        return p ? p.title : ""
    }

    function loadUser(callback) {
        api.request("GET", "/user", {}, null, function(r) {
            if (r.ok)
                currentUser = r.data
            if (callback) callback(r)
        })
    }

    function loadProjects(callback) {
        var all = []
        function page(n) {
            api.request("GET", "/projects", { page: n, per_page: 50, is_archived: "true" }, null, function(r) {
                if (!r.ok) {
                    if (callback) callback(r)
                    return
                }
                all = all.concat(r.data || [])
                if (r.totalPages > n) {
                    page(n + 1)
                } else {
                    projects = all
                    projectRevision++
                    if (callback) callback(r)
                }
            })
        }
        page(1)
    }

    function loadLabels(callback) {
        api.request("GET", "/labels", { per_page: 200 }, null, function(r) {
            if (r.ok)
                labels = r.data || []
            if (callback) callback(r)
        })
    }

    function setTaskDone(task, done, callback) {
        var t = Util.clone(task)
        t.done = done
        api.request("POST", "/tasks/" + task.id, {}, t, function(r) {
            if (r.ok) {
                taskRevision++
                taskChanged(task.id)
            } else {
                showError(r)
            }
            if (callback) callback(r)
        })
    }

    function openTask(taskId) {
        pageStack.push(Qt.resolvedUrl("pages/TaskPage.qml"), { taskId: taskId })
    }

    // Replaces whatever is showing (start or login page, and anything a
    // notification put on top of it) with the home page.
    function goHome() {
        pageStack.replaceAbove(null, Qt.resolvedUrl("pages/HomePage.qml"), {}, PageStackAction.Immediate)
    }

    function homeShowing() {
        var p = pageStack.currentPage
        var bottom = null
        while (p) {
            bottom = p
            p = pageStack.previousPage(p)
        }
        return bottom !== null && bottom.objectName === "homePage"
    }

    // A task from a tapped reminder. It goes on top of the home page; while
    // the app is still starting (or signing in) it waits, because a page
    // pushed onto the start page is left with the endless start spinner
    // under it once the start page tries to go home.
    property int pendingTaskId: 0
    function showTask(taskId) {
        pendingTaskId = taskId
        openPendingTask()
    }
    // From page status handlers: pushing inside one confuses the page stack.
    function openPendingTaskSoon() {
        if (pendingTaskId > 0)
            pendingTimer.restart()
    }
    Timer {
        id: pendingTimer
        interval: 0
        onTriggered: app.openPendingTask()
    }
    function openPendingTask() {
        var taskId = pendingTaskId
        if (taskId <= 0 || !api.authenticated || !homeShowing() || pageStack.busy)
            return
        pendingTaskId = 0
        var top = pageStack.currentPage
        if (top && top.objectName === "taskPage" && top.taskId === taskId) {
            top.load()
            return
        }
        api.diag("opening task " + taskId + " from a notification")
        openTask(taskId)
    }

    function openAddTask(projectId, bucketId) {
        var dialog = pageStack.push(Qt.resolvedUrl("pages/AddTaskDialog.qml"),
                                    { projectId: projectId || defaultProjectId || (projects.length ? projects[0].id : 0),
                                      bucketId: bucketId || 0 })
        return dialog
    }

    // Asks once, on top of the home page, whether the token may be kept in a
    // private file because Secrets refused it.
    property bool storagePromptPending: false
    function askStorageChoice() {
        if (!api.storageChoiceNeeded || appBridge.background)
            return
        storagePromptPending = true
        showStoragePrompt()
    }
    function showStoragePrompt() {
        if (!storagePromptPending || pageStack.busy)
            return
        storagePromptPending = false
        if (api.storageChoiceNeeded)
            pageStack.push(Qt.resolvedUrl("pages/StorageChoiceDialog.qml"))
    }

    Connections {
        target: pageStack
        onBusyChanged: app.showStoragePrompt()
    }

    // The login page is showing but the session is already there.
    property bool leavingLogin: false
    function leaveLoginPage() {
        if (leavingLogin)
            return
        leavingLogin = true
        api.diag("login page showing with a session; going home")
        loadUser(function(r) {
            leavingLogin = false
            var page = pageStack.currentPage
            if (!api.authenticated || !page || page.objectName !== "loginPage")
                return
            loadProjects()
            loadLabels()
            goHome()
        })
    }

    function signedOut() {
        api.diag("signed out, showing login page")
        currentUser = null
        projects = []
        labels = []
        reminderService.clear()
        pendingTaskId = 0
        pageStack.clear()
        pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"), {}, PageStackAction.Immediate)
    }

    Connections {
        target: api
        onSessionExpired: {
            api.diag("session expired: server answered 401, signing out")
            app.notify(qsTr("Your session has expired or the token was revoked. Please sign in again."))
            api.logout()
            app.signedOut()
        }
    }

    Connections {
        target: pageStack
        onBusyChanged: if (!pageStack.busy) app.openPendingTask()
    }

    Connections {
        target: appBridge
        onActivateRequested: app.activate()
        onShowRequested: api.diag("window shown: page=" + String(pageStack.currentPage).split("(")[0]
                                  + " authenticated=" + api.authenticated)
        onOpenTaskRequested: {
            app.activate()
            app.showTask(taskId)
        }
        onMarkDoneRequested: {
            if (!api.authenticated)
                api.restoreSession()
            if (!api.authenticated)
                return
            api.request("GET", "/tasks/" + taskId, {}, null, function(r) {
                if (r.ok)
                    app.setTaskDone(r.data, true, function() { appBridge.backgroundDone() })
                else
                    appBridge.backgroundDone()
            })
        }
        onReminderRequested: {
            // The app may have been started just for this call.
            if (!api.authenticated && !api.restoreSession() && api.sessionNotice === "inactive") {
                // Signed out after 30 days without use: no more reminders.
                alarms.clear()
                appBridge.backgroundDone()
                return
            }
            reminderService.handleAlarm(taskId, kind, time, function() { appBridge.backgroundDone() })
        }
    }

    // Opening the app (not a background start) keeps the session alive.
    Connections {
        target: Qt.application
        onStateChanged: if (Qt.application.state === Qt.ApplicationActive && !appBridge.background) api.touchSession()
    }

    ReminderService {
        id: reminderService
        active: api.authenticated
    }

    Banner {
        id: banner
    }
}
