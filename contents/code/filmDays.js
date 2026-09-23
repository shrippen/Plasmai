.pragma library

/**
 * Local film-day extras (break, catering, day category/type, production-day
 * counter, extra pay, note) for the Filmday view. Kimai's own API has no
 * place for these yet, so they live in shared.json (filmDaysJson), keyed by
 * project + date. Values mirror the enum strings used by the (separate)
 * kimai-drehzettel-bundle plugin so a later switch to its API is a storage
 * change, not a vocabulary change.
 */

var DayCategory = {
    AUTO: "",
    WORKDAY: "workday",
    SATURDAY: "saturday",
    SUNDAY: "sunday",
    HOLIDAY: "holiday"
}

var DayType = {
    WORKDAY: "workday",
    TRAVEL: "travel"
}

var Catering = {
    YES: "yes",
    NO: "no"
}

function dayKey(projectId, dateStr) {
    return String(projectId || "") + "|" + String(dateStr || "")
}

function entryDefaults() {
    return {
        breakMinutes: 45,
        catering: Catering.NO,
        category: DayCategory.AUTO,
        dayType: DayType.WORKDAY,
        productionDay: null,
        extraPayCents: 0,
        note: ""
    }
}

function parse(jsonStr) {
    if (!jsonStr) {
        return {}
    }
    try {
        var data = JSON.parse(jsonStr)
        return (data && typeof data === "object") ? data : {}
    } catch (e) {
        return {}
    }
}

function serialize(map) {
    return JSON.stringify(map || {})
}

function get(map, projectId, dateStr) {
    var key = dayKey(projectId, dateStr)
    var stored = (map || {})[key]
    var entry = entryDefaults()
    if (!stored) {
        return entry
    }
    for (var field in entry) {
        if (Object.prototype.hasOwnProperty.call(stored, field)) {
            entry[field] = stored[field]
        }
    }
    return entry
}

/** Returns a new map with the entry set (does not mutate the input). */
function set(map, projectId, dateStr, entry) {
    var next = {}
    var key
    for (key in (map || {})) {
        next[key] = map[key]
    }
    next[dayKey(projectId, dateStr)] = entry
    return next
}

/** ISO weekday (1=Monday..7=Sunday) as used by KimaiApi.kimaiWeekday. */
function categoryFromWeekday(isoWeekday) {
    if (isoWeekday === 6) {
        return DayCategory.SATURDAY
    }
    if (isoWeekday === 7) {
        return DayCategory.SUNDAY
    }
    return DayCategory.WORKDAY
}

/** Stored override wins; otherwise derive from the weekday (never holiday — not detectable here). */
function effectiveCategory(entry, isoWeekday) {
    if (entry && entry.category) {
        return entry.category
    }
    return categoryFromWeekday(isoWeekday)
}

/** Net work time in seconds: span minus break, floored at 0. */
function workSecondsFromSpan(beginMs, endMs, breakMinutes) {
    if (!(beginMs >= 0) || !(endMs > beginMs)) {
        return 0
    }
    var spanSeconds = Math.floor((endMs - beginMs) / 1000)
    var breakSeconds = Math.max(0, Number(breakMinutes) || 0) * 60
    return Math.max(0, spanSeconds - breakSeconds)
}
