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
        var projectIdRaw = String(pair[0]).trim()
        var activityIdRaw = String(pair[1]).trim()
        if (!projectIdRaw || !activityIdRaw) {
            continue
        }
        var projectIdNum = parseInt(projectIdRaw, 10)
        var activityIdNum = parseInt(activityIdRaw, 10)
        // Keep numeric ids as numbers (Kimai); leave UUID/string ids as strings.
        var projectId = (!isNaN(projectIdNum) && String(projectIdNum) === projectIdRaw) ? projectIdNum : projectIdRaw
        var activityId = (!isNaN(activityIdNum) && String(activityIdNum) === activityIdRaw) ? activityIdNum : activityIdRaw
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

/**
 * Resolve pinned rows for the UI.
 * allActivities (optional) is the full catalog from loadAllActivities — preferred over
 * per-project caches so favorites show names before those loads finish.
 */
function resolvePinnedEntries(pinnedStr, projects, activitiesByProject, customersById, allActivities) {
    var raw = parsePinned(pinnedStr)
    var result = []
    var projectMap = {}
    for (var p = 0; p < (projects || []).length; p++) {
        projectMap[String(projects[p].id)] = projects[p]
    }
    var activitiesById = KimaiApi.activitiesIndexFromCache(allActivities || [], activitiesByProject || {})

    for (var i = 0; i < raw.length; i++) {
        var entry = raw[i]
        var project = projectMap[String(entry.projectId)]
        var projectName = project ? (project.name || project.title || ("#" + entry.projectId))
            : ("#" + entry.projectId)
        var activity = activitiesById[String(entry.activityId)] || null
        if (!activity) {
            var acts = (activitiesByProject || {})[entry.projectId]
                || (activitiesByProject || {})[String(entry.projectId)]
            if (acts) {
                for (var a = 0; a < acts.length; a++) {
                    if (String(acts[a].id) === String(entry.activityId)) {
                        activity = acts[a]
                        break
                    }
                }
            }
        }
        var activityName = activity
            ? (activity.name || activity.title || ("#" + entry.activityId))
            : ("#" + entry.activityId)
        var customerName = KimaiApi.customerNameOfProject(project, customersById)
        var bar = KimaiApi.barColorInfo(activity, project, customersById)
        result.push({
            projectId: entry.projectId,
            activityId: entry.activityId,
            projectName: projectName,
            activityName: activityName,
            customerName: customerName,
            customerColor: bar.color,
            colorCategory: bar.category,
            entityId: bar.id
        })
    }
    return result
}
