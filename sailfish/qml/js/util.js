.pragma library

// Vikunja uses 0001-01-01 for "no date".
function parseDate(value) {
    if (!value)
        return null
    var d = new Date(value)
    if (isNaN(d.getTime()) || d.getFullYear() < 1000)
        return null
    return d
}

function toApiDate(date) {
    return date ? date.toISOString() : null
}

function startOfDay(d) {
    var x = new Date(d.getTime())
    x.setHours(0, 0, 0, 0)
    return x
}

function addDays(d, n) {
    var x = new Date(d.getTime())
    x.setDate(x.getDate() + n)
    return x
}

function dayDiff(d, ref) {
    return Math.round((startOfDay(d).getTime() - startOfDay(ref || new Date()).getTime()) / 86400000)
}

function formatDate(d) {
    if (!d)
        return ""
    var diff = dayDiff(d)
    var time = Qt.formatTime(d, "hh:mm")
    var hasTime = !(d.getHours() === 0 && d.getMinutes() === 0)
    var day
    if (diff === 0) day = qsTr("Today")
    else if (diff === 1) day = qsTr("Tomorrow")
    else if (diff === -1) day = qsTr("Yesterday")
    else if (diff > 1 && diff < 7) day = Qt.formatDate(d, "dddd")
    else if (d.getFullYear() === new Date().getFullYear()) day = Qt.formatDate(d, "d MMM")
    else day = Qt.formatDate(d, "d MMM yyyy")
    return hasTime ? day + " " + time : day
}

function isOverdue(task) {
    var due = parseDate(task.due_date)
    return !task.done && due !== null && due.getTime() < Date.now()
}

// Section used on the upcoming list.
function dueSection(task) {
    var due = parseDate(task.due_date)
    if (!due)
        return qsTr("No due date")
    if (due.getTime() < Date.now() && dayDiff(due) < 0)
        return qsTr("Overdue")
    var diff = dayDiff(due)
    if (diff <= 0) return qsTr("Today")
    if (diff === 1) return qsTr("Tomorrow")
    if (diff < 7) return qsTr("Next 7 days")
    return qsTr("Later")
}

var priorities = [
    { value: 0, name: qsTr("Unset") },
    { value: 1, name: qsTr("Low") },
    { value: 2, name: qsTr("Medium") },
    { value: 3, name: qsTr("High") },
    { value: 4, name: qsTr("Urgent") },
    { value: 5, name: qsTr("DO NOW") }
]

function priorityName(p) {
    for (var i = 0; i < priorities.length; ++i)
        if (priorities[i].value === p)
            return priorities[i].name
    return ""
}

var colors = ["", "e8445a", "ff9f69", "f1db47", "00db60", "1973ff", "7f23ff", "ff4136", "ff851b", "4c9aff", "8b572a", "2ecc40"]

function cssColor(hex) {
    if (!hex)
        return "transparent"
    hex = String(hex).replace("#", "")
    if (!/^[0-9a-fA-F]{6}$/.test(hex))
        return "transparent"
    return "#" + hex
}

// Repeat intervals are stored in seconds.
var repeatUnits = [
    { name: qsTr("hours"), seconds: 3600 },
    { name: qsTr("days"), seconds: 86400 },
    { name: qsTr("weeks"), seconds: 604800 }
]

function splitRepeat(seconds) {
    if (!seconds)
        return { amount: 0, unit: 1 }
    for (var i = repeatUnits.length - 1; i >= 0; --i)
        if (seconds % repeatUnits[i].seconds === 0)
            return { amount: seconds / repeatUnits[i].seconds, unit: i }
    return { amount: Math.round(seconds / 3600), unit: 0 }
}

function describeRepeat(seconds) {
    if (!seconds)
        return ""
    var r = splitRepeat(seconds)
    return qsTr("Every %1 %2").arg(r.amount).arg(repeatUnits[r.unit].name)
}

function userName(user) {
    if (!user)
        return ""
    return user.name ? user.name : user.username
}

// Flattens the project list into a depth-first tree.
function projectTree(projects, showArchived) {
    var byParent = {}
    var ids = {}
    for (var i = 0; i < projects.length; ++i)
        ids[projects[i].id] = true
    for (i = 0; i < projects.length; ++i) {
        var p = projects[i]
        if (!showArchived && p.is_archived)
            continue
        var parent = (p.parent_project_id && ids[p.parent_project_id]) ? p.parent_project_id : 0
        if (!byParent[parent])
            byParent[parent] = []
        byParent[parent].push(p)
    }
    var out = []
    function walk(parent, depth) {
        var list = byParent[parent] || []
        list.sort(function(a, b) { return (a.position || 0) - (b.position || 0) })
        for (var j = 0; j < list.length; ++j) {
            out.push({ project: list[j], depth: depth })
            walk(list[j].id, depth + 1)
        }
    }
    walk(0, 0)
    return out
}

function clone(obj) {
    return JSON.parse(JSON.stringify(obj))
}

// For the cover: open tasks due from now until midnight (phone time) and
// open tasks already past due; the list shows the coming ones first.
function coverCounts(list, now) {
    var endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999)
    var coming = [], late = []
    for (var i = 0; i < list.length; ++i) {
        var due = parseDate(list[i].due_date)
        if (list[i].done || !due || due > endOfDay)
            continue
        if (due < now) late.push(list[i])
        else coming.push(list[i])
    }
    return { today: coming.length, overdue: late.length, tasks: coming.concat(late) }
}
