.pragma library
.import "./dateTimeFormat.js" as DTF
.import "./entityNames.js" as Names
.import "./providerUtil.js" as ProviderUtil

/**
 * Shared timesheet extras: tags and billable.
 * Providers keep Kimai-shaped objects; this file normalizes the extras
 * so create/patch/UI do not fork per backend.
 */

function normalizeTags(value) {
    var out = []
    var seen = {}
    var i
    if (value === null || value === undefined || value === "") {
        return out
    }
    if (typeof value === "string") {
        var parts = value.split(/[,;]+/)
        for (i = 0; i < parts.length; i++) {
            pushTag(out, seen, parts[i])
        }
        return out
    }
    if (typeof value === "object" && value.length >= 0) {
        for (i = 0; i < value.length; i++) {
            var item = value[i]
            if (item && typeof item === "object") {
                pushTag(out, seen, item.name || item.tag || item.title || "")
            } else {
                pushTag(out, seen, item)
            }
        }
    }
    return out
}

function pushTag(out, seen, raw) {
    var tag = String(raw || "").trim()
    if (!tag) {
        return
    }
    var key = tag.toLowerCase()
    if (seen[key]) {
        return
    }
    seen[key] = true
    out.push(tag)
}

function formatTagString(value) {
    return normalizeTags(value).join(", ")
}

function tagsFromTimesheet(timesheet) {
    if (!timesheet) {
        return []
    }
    if (timesheet.tags !== undefined) {
        return normalizeTags(timesheet.tags)
    }
    if (timesheet.tagNames !== undefined) {
        return normalizeTags(timesheet.tagNames)
    }
    return []
}

/**
 * Checkbox default for the billable toggle (shown checked).
 * Callers omit billable for new entries so the backend auto-resolves.
 */
function defaultBillable() {
    return true
}

function billableFromTimesheet(timesheet, fallback) {
    if (timesheet && timesheet.billable !== undefined && timesheet.billable !== null) {
        return !!timesheet.billable
    }
    if (typeof fallback === "boolean") {
        return fallback
    }
    return defaultBillable()
}

function resolveBillable(fields, existing) {
    var f = fields || {}
    if (f.billable !== undefined && f.billable !== null) {
        return !!f.billable
    }
    if (existing && existing.billable !== undefined && existing.billable !== null) {
        return !!existing.billable
    }
    return defaultBillable()
}

function resolveTags(fields, existing) {
    var f = fields || {}
    if (f.tags !== undefined) {
        return normalizeTags(f.tags)
    }
    return tagsFromTimesheet(existing)
}

function attachKimaiShape(row, source) {
    if (!row) {
        return row
    }
    row.tags = tagsFromTimesheet(source || row)
    if (typeof row.billable !== "boolean") {
        row.billable = billableFromTimesheet(source || row, false)
    }
    return row
}

/** Parse Kimai-local (`YYYY-MM-DDTHH:mm:ss`), ISO, or Date into a local Date. */
function parseInstant(value) {
    if (value === null || value === undefined || value === "") {
        return null
    }
    if (typeof value === "object" && typeof value.getTime === "function") {
        return isNaN(value.getTime()) ? null : value
    }
    var d = DTF.parseStamp(value)
    return isNaN(d.getTime()) ? null : d
}

function midpointInstant(timesheet) {
    var begin = parseInstant(timesheet && timesheet.begin)
    var end = parseInstant(timesheet && timesheet.end)
    if (!begin || !end) {
        return null
    }
    return new Date(Math.floor((begin.getTime() + end.getTime()) / 2))
}

/**
 * Split a stopped timesheet at splitAt (strictly between begin and end).
 * firstEnd / secondBegin / secondEnd are Date objects. Copy project/activity
 * from the original; callers send ids via entityNames.projectId / activityId.
 */
function splitStoppedEntry(timesheet, splitAt) {
    var begin = parseInstant(timesheet && timesheet.begin)
    var end = parseInstant(timesheet && timesheet.end)
    var at = parseInstant(splitAt)
    if (!begin || !end || !at) {
        return { ok: false, error: "missing" }
    }
    if (!(begin.getTime() < at.getTime() && at.getTime() < end.getTime())) {
        return { ok: false, error: "range" }
    }
    return {
        ok: true,
        firstEnd: at,
        secondBegin: at,
        secondEnd: end,
        description: (timesheet && timesheet.description) || "",
        billable: billableFromTimesheet(timesheet, true),
        tags: tagsFromTimesheet(timesheet)
    }
}

function _pushUniqueTimesheet(out, seen, ts) {
    if (!ts) {
        return
    }
    var key = (ts.id !== undefined && ts.id !== null) ? ("id:" + String(ts.id)) : ""
    if (!key) {
        var begin = parseInstant(ts.begin)
        var end = parseInstant(ts.end)
        key = "span:" + (begin ? begin.getTime() : "") + ":" + (end ? end.getTime() : "")
    }
    if (seen[key]) {
        return
    }
    seen[key] = true
    out.push(ts)
}

/**
 * Latest-ended stopped timesheet that is not `currentTimesheet`.
 * Recents are deduped by project/activity, so also scan todayList.
 */
function previousStoppedTimesheet(recentList, todayList, currentTimesheet) {
    var currentId = (currentTimesheet && currentTimesheet.id !== undefined
                     && currentTimesheet.id !== null)
        ? String(currentTimesheet.id) : ""
    var list = []
    var seen = {}
    var i
    for (i = 0; i < (recentList || []).length; i++) {
        _pushUniqueTimesheet(list, seen, recentList[i])
    }
    for (i = 0; i < (todayList || []).length; i++) {
        _pushUniqueTimesheet(list, seen, todayList[i])
    }
    var best = null
    var bestEnd = -Infinity
    for (i = 0; i < list.length; i++) {
        var ts = list[i]
        if (currentId && ts.id !== undefined && ts.id !== null && String(ts.id) === currentId) {
            continue
        }
        var end = parseInstant(ts.end)
        if (!end) {
            continue
        }
        if (end.getTime() >= bestEnd) {
            bestEnd = end.getTime()
            best = ts
        }
    }
    return best
}

/** True when begin is strictly before the previous timesheet's end. */
function beginIsBeforePreviousEnd(begin, previousTimesheet) {
    var start = parseInstant(begin)
    var prevEnd = parseInstant(previousTimesheet && previousTimesheet.end)
    if (!start || !prevEnd) {
        return false
    }
    return start.getTime() < prevEnd.getTime()
}

function tagEntityName(item) {
    if (typeof item === "string") {
        return String(item).trim()
    }
    return String(item && (item.name || item.tag || item.title) || "").trim()
}

/** Resolved display color from Kimai TagEntity (`color-safe` when explicit color is absent). */
function tagEntityColor(item) {
    if (!item || typeof item !== "object") {
        return ProviderUtil.DEFAULT_CUSTOMER_COLOR
    }
    var raw = item["color-safe"] || item.color || ""
    if (raw === null || raw === undefined || String(raw).trim().length === 0) {
        var name = tagEntityName(item)
        return name ? colorFromTagName(name) : ProviderUtil.DEFAULT_CUSTOMER_COLOR
    }
    return ProviderUtil.normalizeCustomerColor(raw)
}

/** Deterministic accent when Kimai has not assigned an explicit tag color yet. */
function colorFromTagName(name) {
    var s = String(name || "")
    var hash = 0
    for (var i = 0; i < s.length; i++) {
        hash = ((hash << 5) - hash + s.charCodeAt(i)) | 0
    }
    var hue = Math.abs(hash) % 360
    var sNorm = 0.52
    var lNorm = 0.54
    var c = (1 - Math.abs(2 * lNorm - 1)) * sNorm
    var x = c * (1 - Math.abs((hue / 60) % 2 - 1))
    var m = lNorm - c / 2
    var r = 0
    var g = 0
    var b = 0
    if (hue < 60) {
        r = c; g = x; b = 0
    } else if (hue < 120) {
        r = x; g = c; b = 0
    } else if (hue < 180) {
        r = 0; g = c; b = x
    } else if (hue < 240) {
        r = 0; g = x; b = c
    } else if (hue < 300) {
        r = x; g = 0; b = c
    } else {
        r = c; g = 0; b = x
    }
    function hex(n) {
        var v = Math.round((n + m) * 255)
        if (v < 0) v = 0
        if (v > 255) v = 255
        var h = v.toString(16)
        return h.length === 1 ? "0" + h : h
    }
    return "#" + hex(r) + hex(g) + hex(b)
}

/** Shallow-merge cached entity fields onto a partial API object (names/colors). */
function mergeEntity(partial, cached) {
    if (!cached) {
        return partial
    }
    if (!partial) {
        return cached
    }
    var out = {}
    var k
    for (k in partial) {
        if (partial.hasOwnProperty(k)) {
            out[k] = partial[k]
        }
    }
    for (k in cached) {
        if (!cached.hasOwnProperty(k)) {
            continue
        }
        if (out[k] === null || out[k] === undefined || out[k] === "") {
            out[k] = cached[k]
        }
    }
    return out
}

/**
 * Expand bare project/activity IDs on timesheets using local caches so
 * stats grouping and legends get real names/colors.
 * Never replaces an embedded name with a blank cached name.
 */
function hydrateTimesheets(entries, projects, activities, activitiesByProject) {
    var projectsById = Names.indexById(projects)
    var activitiesById = Names.activitiesIndexFromCache(activities, activitiesByProject)
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        var ts = entries[i]
        if (!ts) {
            continue
        }
        var pid = Names.projectId(ts)
        var aid = Names.activityId(ts)
        var projectObj = (typeof ts.project === "object" && ts.project) ? ts.project : null
        var activityObj = (typeof ts.activity === "object" && ts.activity) ? ts.activity : null

        if (pid && projectsById[String(pid)]) {
            var cachedProject = projectsById[String(pid)]
            if (!projectObj) {
                projectObj = cachedProject
            } else {
                projectObj = mergeEntity(projectObj, cachedProject)
            }
        }
        if (aid && activitiesById[String(aid)]) {
            var cachedActivity = activitiesById[String(aid)]
            if (!activityObj) {
                activityObj = cachedActivity
            } else {
                activityObj = mergeEntity(activityObj, cachedActivity)
            }
        }

        // Normalize scalar IDs into stub objects so callers always see .name/.id
        if (!projectObj && pid) {
            projectObj = { id: pid, name: "" }
        }
        if (!activityObj && aid) {
            activityObj = { id: aid, name: "" }
        }
        if (projectObj && !Names.entityName(projectObj) && projectsById[String(pid)]) {
            projectObj = mergeEntity(projectObj, projectsById[String(pid)])
        }
        if (activityObj && !Names.entityName(activityObj) && activitiesById[String(aid)]) {
            activityObj = mergeEntity(activityObj, activitiesById[String(aid)])
        }

        var changed = projectObj !== ts.project || activityObj !== ts.activity
            || (typeof ts.project !== "object") || (typeof ts.activity !== "object")
        if (changed) {
            var copy = {}
            for (var k in ts) {
                if (ts.hasOwnProperty(k)) {
                    copy[k] = ts[k]
                }
            }
            if (projectObj) {
                copy.project = projectObj
            }
            if (activityObj) {
                copy.activity = activityObj
            }
            attachKimaiShape(copy, ts)
            out.push(copy)
        } else {
            attachKimaiShape(ts, ts)
            out.push(ts)
        }
    }
    return out
}

function deduplicateRecent(entries) {
    var seen = {}
    var result = []
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        var key = Names.projectId(entry) + ":" + Names.activityId(entry)
        if (seen[key]) {
            continue
        }
        seen[key] = true
        result.push(entry)
    }
    return result
}
