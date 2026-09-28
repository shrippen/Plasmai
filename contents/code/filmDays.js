.pragma library
.import "./dateTimeFormat.js" as DTF

/**
 * Film-day extras (break, catering, day category/type, production shooting
 * day, extra pay, note) for the Filmday view. They live only in
 * kimai-drehzettel-bundle on the server (mapping below, orchestration in
 * filmDaySync.js); Plasmai keeps no copy on the device.
 * Values mirror the plugin's enum strings.
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

function entryDefaults() {
    return {
        breakMinutes: 45,
        catering: Catering.NO,
        category: DayCategory.AUTO,
        dayType: DayType.WORKDAY,
        productionDay: null,
        surchargeDay: null,
        extraPayCents: 0,
        note: ""
    }
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

function isStopped(timesheet) {
    return !!timesheet && !!timesheet.end
}

/**
 * The day's film-day entry of projectId: the stopped entry whose begin and end
 * match `span` (the plugin's day summary), otherwise the longest one; null
 * if there is none (save creates a new entry). Entries of other projects and
 * the running entry are never picked: saving would move them or stop the
 * live timer.
 */
function pickDayEntry(entries, projectId, projectIdOf, span) {
    if (projectId === null || projectId === undefined || projectId === "") {
        return null
    }
    var spanBegin = span ? stampMs(span.begin) : NaN
    var spanEnd = span ? stampMs(span.end) : NaN
    var best = null
    var bestSeconds = -1
    for (var i = 0; i < (entries || []).length; i++) {
        var ts = entries[i]
        if (!isStopped(ts) || String(projectIdOf(ts)) !== String(projectId)) {
            continue
        }
        var begin = stampMs(ts.begin)
        var end = stampMs(ts.end)
        // The plugin's day summary names the film day's span: take that entry.
        if (Math.abs(begin - spanBegin) < SPAN_TOLERANCE_MS && Math.abs(end - spanEnd) < SPAN_TOLERANCE_MS) {
            return ts
        }
        // Otherwise the longest entry; travel and other short entries stay "others".
        var seconds = (isNaN(begin) || isNaN(end)) ? 0 : (end - begin) / 1000
        if (seconds > bestSeconds) {
            best = ts
            bestSeconds = seconds
        }
    }
    return best
}

/**
 * Entry id a save may PATCH, or null to create a new entry. Only a stopped
 * entry of the saved project is reused; otherwise saving under another
 * project would move an unrelated entry.
 */
function saveTargetId(timesheet, projectId, projectIdOf) {
    if (!isStopped(timesheet) || timesheet.id === undefined || timesheet.id === null) {
        return null
    }
    if (String(projectIdOf(timesheet)) !== String(projectId)) {
        return null
    }
    return timesheet.id
}

/**
 * Whether activityId counts as film time under the engagement's whitelist
 * (plugin `activityIds`). Empty or missing: every activity counts (older
 * plugin, unrestricted engagement).
 */
function countsActivity(activityIds, activityId) {
    if (!activityIds || !activityIds.length) {
        return true
    }
    for (var i = 0; i < activityIds.length; i++) {
        if (String(activityIds[i]) === String(activityId)) {
            return true
        }
    }
    return false
}

/**
 * Entries the plugin counts for the film day: only whitelisted activities,
 * e.g. [40 Set, 41 Dreh] drops a private 12 Anfahrt on the same project.
 */
function filmEntries(entries, activityIds, activityIdOf) {
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        if (countsActivity(activityIds, activityIdOf(entries[i]))) {
            out.push(entries[i])
        }
    }
    return out
}

/** Entries count as the summary's span within a minute (seconds in Kimai stamps). */
var SPAN_TOLERANCE_MS = 60 * 1000

function stampMs(value) {
    return DTF.stampMs(value)
}

/**
 * Stopped entries of projectId on the day other than `picked` (B3: a film
 * day is one entry; more entries of the same project make the shown work
 * time wrong). With activityIdOf only entries of picked's activity count:
 * travel and other activities that day are no second film day. Sorted by
 * begin. Running entries are never included.
 */
function otherDayEntries(entries, picked, projectId, projectIdOf, activityIdOf) {
    if (!picked || projectId === null || projectId === undefined || projectId === "") {
        return []
    }
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        var ts = entries[i]
        if (ts === picked || !isStopped(ts) || String(projectIdOf(ts)) !== String(projectId)) {
            continue
        }
        if (activityIdOf && String(activityIdOf(ts)) !== String(activityIdOf(picked))) {
            continue
        }
        if (picked.id !== undefined && picked.id !== null && String(ts.id) === String(picked.id)) {
            continue
        }
        out.push(ts)
    }
    out.sort(function(a, b) { return stampMs(a.begin) - stampMs(b.begin) })
    return out
}

/**
 * Span covering all entries (earliest begin, latest end) and the sum of
 * their durations in seconds. { beginMs, endMs, seconds }; NaN times when
 * no entry has a valid stamp.
 */
function daySpan(entries) {
    var begin = NaN
    var end = NaN
    var seconds = 0
    for (var i = 0; i < (entries || []).length; i++) {
        var b = stampMs(entries[i].begin)
        var e = stampMs(entries[i].end)
        if (!isNaN(b) && (isNaN(begin) || b < begin)) {
            begin = b
        }
        if (!isNaN(e) && (isNaN(end) || e > end)) {
            end = e
        }
        if (!isNaN(b) && !isNaN(e) && e > b) {
            seconds += Math.floor((e - b) / 1000)
        }
    }
    return { beginMs: begin, endMs: end, seconds: seconds }
}

// ── kimai-drehzettel-bundle API mapping ──────────────────────────────────
//
// With the plugin installed the server is the source of truth for the extras
// (film-day GET/PUT). The view keeps working on the local entry shape above,
// with two differences in server mode:
//   breakMinutes    null = the ruleset default (defaultBreakMinutes)
//   surchargeDay    server `productionDay` ("Zuschlagstag", day 1–7 of the
//                   TV FFS calendar week for the 6th/7th-day surcharge), null = automatic
// and one renamed field (decision D7): the local `productionDay` counter is
// the production's running shooting day, i.e. the server's shootingDayNumber.
//
//   local               API
//   breakMinutes        breakMinutes       int 0–720 | null
//   catering yes/no     catering           bool
//   category ""         category           null | workday|saturday|sunday|holiday
//   dayType             dayType            workday|travel
//   productionDay 0/n   shootingDayNumber  null | 1–999
//   surchargeDay        productionDay      null | 1–7
//   extraPayCents       extraPayCents      int 0–10,000,000
//   note ""             note               null | trimmed, ≤ 500

var BREAK_MAX_MINUTES = 720
var DEFAULT_BREAK_MINUTES = 45
var NOTE_MAX_LENGTH = 500
var DAY_NUMBER_MAX = 999
var SURCHARGE_DAY_MAX = 7
var EXTRA_PAY_MAX_CENTS = 10000000

/** Keys the client may send in a PUT, in a stable order. */
var API_FIELDS = ["breakMinutes", "catering", "category", "dayType",
                  "shootingDayNumber", "productionDay", "extraPayCents", "note"]

function clampInt(value, min, max) {
    var n = Math.round(Number(value))
    if (isNaN(n)) {
        return min
    }
    return Math.max(min, Math.min(max, n))
}

/** null for "not set" (null, undefined, "", 0 or out of range), else 1..max. */
function optionalDayNumber(value, max) {
    if (value === null || value === undefined || value === "") {
        return null
    }
    var n = Math.round(Number(value))
    if (isNaN(n) || n < 1) {
        return null
    }
    return Math.min(max, n)
}

function trimmedNote(note) {
    var s = String(note === null || note === undefined ? "" : note).trim()
    return s.length > NOTE_MAX_LENGTH ? s.substring(0, NOTE_MAX_LENGTH).trim() : s
}

/** Full API representation of a local/form entry (all API_FIELDS). */
function toApi(local) {
    var e = local || entryDefaults()
    var breakMinutes = (e.breakMinutes === null || e.breakMinutes === undefined || e.breakMinutes === "")
        ? null : clampInt(e.breakMinutes, 0, BREAK_MAX_MINUTES)
    var category = e.category ? String(e.category) : null
    var note = trimmedNote(e.note)
    return {
        breakMinutes: breakMinutes,
        catering: e.catering === Catering.YES || e.catering === true,
        category: category,
        dayType: e.dayType === DayType.TRAVEL ? DayType.TRAVEL : DayType.WORKDAY,
        shootingDayNumber: optionalDayNumber(e.productionDay, DAY_NUMBER_MAX),
        productionDay: optionalDayNumber(e.surchargeDay, SURCHARGE_DAY_MAX),
        extraPayCents: clampInt(e.extraPayCents || 0, 0, EXTRA_PAY_MAX_CENTS),
        note: note.length ? note : null
    }
}

/** Server JSON normalized to toApi()'s value shapes (missing keys stay missing). */
function normalizeServer(json) {
    var out = {}
    var j = json || {}
    if (Object.prototype.hasOwnProperty.call(j, "breakMinutes")) {
        out.breakMinutes = (j.breakMinutes === null || j.breakMinutes === undefined) ? null : Number(j.breakMinutes)
    }
    if (Object.prototype.hasOwnProperty.call(j, "catering")) {
        out.catering = j.catering === true
    }
    if (Object.prototype.hasOwnProperty.call(j, "category")) {
        out.category = j.category ? String(j.category) : null
    }
    if (Object.prototype.hasOwnProperty.call(j, "dayType")) {
        out.dayType = j.dayType === DayType.TRAVEL ? DayType.TRAVEL : DayType.WORKDAY
    }
    if (Object.prototype.hasOwnProperty.call(j, "shootingDayNumber")) {
        out.shootingDayNumber = optionalDayNumber(j.shootingDayNumber, DAY_NUMBER_MAX)
    }
    if (Object.prototype.hasOwnProperty.call(j, "productionDay")) {
        out.productionDay = optionalDayNumber(j.productionDay, SURCHARGE_DAY_MAX)
    }
    if (Object.prototype.hasOwnProperty.call(j, "extraPayCents")) {
        out.extraPayCents = Number(j.extraPayCents) || 0
    }
    if (Object.prototype.hasOwnProperty.call(j, "note")) {
        var n = j.note === null || j.note === undefined ? "" : String(j.note)
        out.note = n.length ? n : null
    }
    return out
}

/**
 * Keys of the local entry that differ from the server, as a PUT body. With
 * `server` null every field is sent. Keys the server JSON does not have (an
 * older plugin without e.g. extraPay) are never sent: it would reject them.
 */
function toApiPatch(local, server) {
    var api = toApi(local)
    var patch = {}
    var norm = server ? normalizeServer(server) : null
    for (var i = 0; i < API_FIELDS.length; i++) {
        var key = API_FIELDS[i]
        if (norm) {
            if (!Object.prototype.hasOwnProperty.call(norm, key)) {
                continue
            }
            if (norm[key] === api[key]) {
                continue
            }
        }
        patch[key] = api[key]
    }
    return patch
}

function isEmptyPatch(patch) {
    for (var k in (patch || {})) {
        return false
    }
    return true
}

/**
 * Server JSON → form entry. Fields an older plugin does not store
 * (extraPayCents without the extraPay feature) get their defaults.
 */
function fromApi(json) {
    var n = normalizeServer(json)
    return {
        breakMinutes: n.hasOwnProperty("breakMinutes") ? n.breakMinutes : null,
        catering: n.catering ? Catering.YES : Catering.NO,
        category: n.category || DayCategory.AUTO,
        dayType: n.dayType || DayType.WORKDAY,
        productionDay: n.shootingDayNumber || null,
        surchargeDay: n.productionDay || null,
        extraPayCents: n.hasOwnProperty("extraPayCents") ? n.extraPayCents : 0,
        note: n.note || ""
    }
}

/**
 * State of the film day screen:
 *   running  the timer runs on the film day's project today
 *   done     the day has its entry
 *   before   today or later without an entry (Start)
 *   manual   a past day without an entry (enter begin and end)
 * state = { running, match, daysFromToday } (days after today, negative = past).
 */
function phaseOf(state) {
    if (state.running) {
        return "running"
    }
    if (state.match) {
        return "done"
    }
    return state.daysFromToday >= 0 ? "before" : "manual"
}

/** Activity of projectId's longest stopped entry in `entries` (the usual film activity), else null. */
function suggestedActivityId(entries, projectId, projectIdOf, activityIdOf) {
    var longest = pickDayEntry(entries, projectId, projectIdOf, null)
    return longest ? activityIdOf(longest) : null
}

/** Local "YYYY-MM-DD" of a stamp ("+0200" offsets too); "" if invalid. */
function localDateKey(value) {
    var ms = stampMs(value)
    if (isNaN(ms)) {
        return ""
    }
    var d = new Date(ms)
    var mm = d.getMonth() + 1
    var dd = d.getDate()
    return d.getFullYear() + "-" + (mm < 10 ? "0" : "") + mm + "-" + (dd < 10 ? "0" : "") + dd
}

/**
 * Production shooting day: distinct days with entries up to dateStr.
 * { count, includesDay } (includesDay: dateStr itself has an entry).
 */
function countShootingDays(entries, dateStr, beginOf) {
    var days = {}
    var count = 0
    for (var i = 0; i < (entries || []).length; i++) {
        var key = localDateKey(beginOf(entries[i]))
        if (!key || key > dateStr || days[key]) {
            continue
        }
        days[key] = true
        count += 1
    }
    return { count: count, includesDay: !!days[dateStr] }
}
