.pragma library

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
 * Billable for a new entry when the user has not chosen: true.
 * Kimai’s API defaults omitted booleans to false, so callers must send this.
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
    var raw = String(value)
    var d = new Date(raw)
    if (isNaN(d.getTime())) {
        d = new Date(raw.replace(" ", "T"))
    }
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
 * from the original; callers send ids via kimaiApi.projectId / activityId.
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
