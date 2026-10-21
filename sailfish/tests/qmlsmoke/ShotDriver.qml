import QtQuick 2.0

// Screenshots of pages for checking the layout. Needs a Wayland compositor
// (e.g. weston --backend=headless) and QT_QPA_PLATFORM=wayland-egl.
// SMOKE_PHASE: space-separated page file names to capture.
QtObject {
    id: driver
    property var win: null
    property bool finished: false
    property int steps: 0
    property var queue: []

    function log(m) { console.log("SMOKE: " + m) }

    property Timer timer: Timer { interval: 3000; onTriggered: driver.next() }

    function next() {
        if (queue.length === 0) { finished = true; Qt.quit(); return }
        var name = queue.shift()
        steps++
        if (name.indexOf("scroll:") === 0) {
            var flick = findFlickable(win.pageStack.currentPage)
            if (flick) flick.contentY = Math.min(parseInt(name.substring(7)), Math.max(0, flick.contentHeight - flick.height))
            timer.start()
            return
        }
        if (name.indexOf("theme:") === 0) {
            win.setThemeMode(name.substring(6))
            timer.start()
            return
        }
        if (name.indexOf("task:") === 0) {
            win.openTask(parseInt(name.substring(5)))
            timer.start()
            return
        }
        if (name.indexOf("project:") === 0) {
            win.pageStack.push(Qt.resolvedUrl(smokeQmlDir + "/pages/ProjectPage.qml"), { projectId: parseInt(name.substring(8)) }, 1)
            timer.start()
            return
        }
        if (name === "edit") {
            win.pageStack.currentPage.edit()
            timer.start()
            return
        }
        if (name === "pick") {
            win.pageStack.currentPage.pickFile()
            timer.start()
            return
        }
        if (name === "home") {
            // Tap "Home folder" on the file picker's first page.
            var list = findWith(win.pageStack.currentPage, "selected")
            list.selected({ name: "Home", path: homeDir })
            timer.start()
            return
        }
        if (name.indexOf("pickfile:") === 0) {
            // What the directory page sends when a file is tapped.
            win.pageStack.currentPage.filePicked({ filePath: homeDir + "/" + name.substring(9), fileName: name.substring(9),
                                                   url: "file://" + homeDir + "/" + name.substring(9), mimeType: "image/png" })
            timer.start()
            return
        }
        if (name === "attachments") {
            var p = win.pageStack.currentPage
            log("page " + String(p).split("_QML")[0] + " attachments: " + (p.task && p.task.attachments ? p.task.attachments.length : 0))
            timer.start()
            return
        }
        if (name === "add") {
            win.openAddTask()
            timer.start()
            return
        }
        if (name.indexOf("pop") === 0) {
            win.pageStack.pop(undefined, 1)
            timer.start()
            return
        }
        if (name.indexOf("shot:") === 0) {
            var file = shotDir + "/" + name.substring(5) + ".png"
            win.grabToImage(function(r) { r.saveToFile(file); driver.log("saved " + file); timer.start() })
            return
        }
        win.pageStack.push(Qt.resolvedUrl(smokeQmlDir + "/pages/" + name + ".qml"), {}, 1)
        timer.start()
    }

    function findWith(item, prop) {
        if (!item) return null
        for (var i = 0; i < item.children.length; ++i) {
            var c = item.children[i]
            if (c[prop] !== undefined) return c
            var f = findWith(c, prop)
            if (f) return f
        }
        return null
    }

    function findFlickable(item) {
        if (!item) return null
        for (var i = 0; i < item.children.length; ++i) {
            var c = item.children[i]
            if (c.contentHeight !== undefined && c.contentY !== undefined) return c
            var f = findFlickable(c)
            if (f) return f
        }
        return null
    }

    Component.onCompleted: {
        win = smokeRoot
        queue = smokePhase.split(" ")
        timer.interval = 6000
        timer.start()
        timer.interval = 3000
    }
}
