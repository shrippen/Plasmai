.pragma library
.import "kimaiApi.js" as KimaiApi

function parsePinned(pinnedStr) {
    if (!pinnedStr) {
        return []
    }
    var pairs = String(pinnedStr).split(";")
    var result = []
    for (var i = 0; i < pairs.length; i++) {
        var pair = pairs[i].split(":")
        if (pair.length !== 2) {
            continue
        }
        var projectId = parseInt(pair[0])
        var activityId = parseInt(pair[1])
        if (isNaN(projectId) || isNaN(activityId)) {
            continue
        }
        result.push({ projectId: projectId, activityId: activityId })
    }
    return result
}

function serializePinned(entries) {
    if (!entries || entries.length === 0) {
        return ""
    }
    var parts = []
    for (var i = 0; i < entries.length; i++) {
        parts.push(entries[i].projectId + ":" + entries[i].activityId)
    }
    return parts.join(";")
}

function togglePinned(pinnedStr, projectId, activityId) {
    var entries = parsePinned(pinnedStr)
    var found = -1
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].projectId === projectId && entries[i].activityId === activityId) {
            found = i
            break
        }
    }
    if (found >= 0) {
        entries.splice(found, 1)
    } else {
        entries.push({ projectId: projectId, activityId: activityId })
    }
    return serializePinned(entries)
}

function isPinned(pinnedStr, projectId, activityId) {
    var entries = parsePinned(pinnedStr)
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].projectId === projectId && entries[i].activityId === activityId) {
            return true
        }
    }
    return false
}

function resolvePinnedEntries(pinnedStr, projects, activitiesByProject, customersById) {
    var raw = parsePinned(pinnedStr)
    var result = []
    var projectMap = {}
    for (var p = 0; p < projects.length; p++) {
        projectMap[projects[p].id] = projects[p]
    }

    for (var i = 0; i < raw.length; i++) {
        var entry = raw[i]
        var project = projectMap[entry.projectId]
        var projectName = project ? project.name : ("#" + entry.projectId)
        var activityName = "#" + entry.activityId
        var customerColor = KimaiApi.customerColorOfProject(project, customersById)
        var acts = activitiesByProject[entry.projectId]
        if (acts) {
            for (var a = 0; a < acts.length; a++) {
                if (acts[a].id === entry.activityId) {
                    activityName = acts[a].name
                    break
                }
            }
        }
        result.push({
            projectId: entry.projectId,
            activityId: entry.activityId,
            projectName: projectName,
            activityName: activityName,
            customerColor: customerColor
        })
    }
    return result
}
