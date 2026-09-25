.pragma library

/**
 * Film-day extras (break, catering, day category/type, production shooting
 * day, extra pay, note) for the Filmday view. With kimai-drehzettel-bundle
 * installed they live on the server (mapping below, orchestration in
 * filmDaySync.js); without it they stay in shared.json (filmDaysJson), keyed
 * by profile + server + project + date ("<profileId>|<url>|<projectId>|<date>",
 * see scopedDayKey). Older keys have no profile
 * ("<projectId>|<date>"); they are still read as a fallback but never written.
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

/** Legacy key without profile (B8): only read, never written by the app. */
function dayKey(projectId, dateStr) {
    return String(projectId || "") + "|" + String(dateStr || "")
}

/**
 * Key scoped to one profile and Kimai server (B8): project ids of two
 * Kimai instances must not share a film day. profKey is
 * FilmDaySync.profileKey(profileId, url), the same prefix the pending
 * queue uses.
 */
function scopedDayKey(profKey, projectId, dateStr) {
    return String(profKey || "") + "|" + dayKey(projectId, dateStr)
}

/**
 * { profileKey, projectId, date, legacy } of a filmDaysJson key. Legacy keys
 * ("<projectId>|<date>") have profileKey null.
 */
function parseDayKey(key) {
    var parts = String(key || "").split("|")
    if (parts.length < 2) {
        return { profileKey: null, projectId: "", date: "", legacy: true }
    }
    var date = parts[parts.length - 1]
    var projectId = parts[parts.length - 2]
    if (parts.length === 2) {
        return { profileKey: null, projectId: projectId, date: date, legacy: true }
    }
    return { profileKey: parts.slice(0, parts.length - 2).join("|"), projectId: projectId, date: date, legacy: false }
}

/**
 * The key an entry of (profKey, projectId, date) is read from: the scoped
 * key when it exists, else the legacy key when that exists, else the
 * scoped key (where a save would put it). Without profKey: the legacy key.
 */
function storedKey(map, projectId, dateStr, profKey) {
    var legacy = dayKey(projectId, dateStr)
    if (profKey === undefined || profKey === null) {
        return legacy
    }
    var scoped = scopedDayKey(profKey, projectId, dateStr)
    var m = map || {}
    if (Object.prototype.hasOwnProperty.call(m, scoped)) {
        return scoped
    }
    if (Object.prototype.hasOwnProperty.call(m, legacy)) {
        return legacy
    }
    return scoped
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

/**
 * Entry of (projectId, dateStr) with defaults filled in. With profKey the
 * profile's own entry wins, a legacy entry is the fallback (see storedKey).
 */
function get(map, projectId, dateStr, profKey) {
    var key = storedKey(map, projectId, dateStr, profKey)
    return entryFromStored((map || {})[key])
}

/** Stored map value → entry with defaults for missing fields (bookkeeping keys dropped). */
function entryFromStored(stored) {
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

/**
 * Returns a new map with the entry set (does not mutate the input). With
 * profKey it goes to the scoped key; a legacy entry of the same project
 * and day stays untouched (it may belong to another profile).
 */
function set(map, projectId, dateStr, entry, profKey) {
    var next = {}
    var key
    for (key in (map || {})) {
        next[key] = map[key]
    }
    var target = (profKey === undefined || profKey === null)
        ? dayKey(projectId, dateStr) : scopedDayKey(profKey, projectId, dateStr)
    next[target] = entry
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

function isStopped(timesheet) {
    return !!timesheet && !!timesheet.end
}

/**
 * Kimai entry of projectId on the day: the first stopped one, else null
 * (save creates a new entry). Entries of other projects and the running
 * entry are never picked: saving would move them or stop the live timer.
 */
function pickDayEntry(entries, projectId, projectIdOf) {
    if (projectId === null || projectId === undefined || projectId === "") {
        return null
    }
    for (var i = 0; i < (entries || []).length; i++) {
        var ts = entries[i]
        if (isStopped(ts) && String(projectIdOf(ts)) === String(projectId)) {
            return ts
        }
    }
    return null
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

function stampMs(value) {
    if (!value) {
        return NaN
    }
    var d = new Date(String(value))
    if (isNaN(d.getTime())) {
        d = new Date(String(value).replace(" ", "T"))
    }
    return d.getTime()
}

/**
 * Stopped entries of projectId on the day other than `picked` (B3: a film
 * day is one entry; more entries of the same project make the shown work
 * time wrong). Sorted by begin. Running entries are never included.
 */
function otherDayEntries(entries, picked, projectId, projectIdOf) {
    if (!picked || projectId === null || projectId === undefined || projectId === "") {
        return []
    }
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        var ts = entries[i]
        if (ts === picked || !isStopped(ts) || String(projectIdOf(ts)) !== String(projectId)) {
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
 * Server JSON → local/form entry. `localExtras` supplies fields an older
 * plugin does not store (extraPayCents without the extraPay feature).
 */
function fromApi(json, localExtras) {
    var n = normalizeServer(json)
    var fallback = localExtras || entryDefaults()
    return {
        breakMinutes: n.hasOwnProperty("breakMinutes") ? n.breakMinutes : null,
        catering: n.catering ? Catering.YES : Catering.NO,
        category: n.category || DayCategory.AUTO,
        dayType: n.dayType || DayType.WORKDAY,
        productionDay: n.shootingDayNumber || null,
        surchargeDay: n.productionDay || null,
        extraPayCents: n.hasOwnProperty("extraPayCents") ? n.extraPayCents : (Number(fallback.extraPayCents) || 0),
        note: n.note || ""
    }
}

/** Server has nothing stored for the day (all defaults): safe to push local values. */
function isServerEmpty(json) {
    var n = normalizeServer(json)
    return (n.breakMinutes === null || n.breakMinutes === undefined)
        && !n.catering
        && !n.category
        && (n.dayType === undefined || n.dayType === DayType.WORKDAY)
        && !n.shootingDayNumber
        && !n.productionDay
        && !n.extraPayCents
        && !n.note
}

/** Values of `server` for the keys of `patch` (the base a queued patch was made against). */
function baseForPatch(server, patch) {
    var norm = normalizeServer(server)
    var base = {}
    for (var k in (patch || {})) {
        base[k] = Object.prototype.hasOwnProperty.call(norm, k) ? norm[k] : null
    }
    return base
}

/** True when the server still holds `base` for every key (nobody changed it meanwhile). */
function serverMatchesBase(server, base) {
    var norm = normalizeServer(server)
    for (var k in (base || {})) {
        var v = Object.prototype.hasOwnProperty.call(norm, k) ? norm[k] : null
        if (v !== base[k]) {
            return false
        }
    }
    return true
}

/**
 * Local film days that could move to the server for one profile, sorted by
 * date, without a migration result for `profileKey` yet:
 *   - the profile's own (scoped) entries;
 *   - legacy entries without profile (B8) whose project id is in
 *     `projectIds` (the active profile's catalog), unless the profile has
 *     its own entry for that project and day. Two Kimai instances with the
 *     same project id both see such an entry; the server-wins rule keeps
 *     that safe.
 * Other profiles' scoped entries are never offered.
 */
function planMigration(map, projectIds, profileKey) {
    var known = {}
    var i
    for (i = 0; i < (projectIds || []).length; i++) {
        known[String(projectIds[i])] = true
    }
    var m = map || {}
    var out = []
    for (var key in m) {
        var parts = parseDayKey(key)
        if (!parts.projectId || !/^\d{4}-\d{2}-\d{2}$/.test(parts.date)) {
            continue
        }
        if (parts.legacy) {
            if (!known[parts.projectId]
                || Object.prototype.hasOwnProperty.call(m, scopedDayKey(profileKey, parts.projectId, parts.date))) {
                continue
            }
        } else if (parts.profileKey !== String(profileKey)) {
            continue
        }
        var stored = m[key] || {}
        if (stored.migrated && stored.migrated[profileKey]) {
            continue
        }
        var entry = entryFromStored(stored)
        out.push({
            key: key,
            projectId: parts.projectId,
            date: parts.date,
            entry: entry,
            noteTruncated: String(entry.note || "").trim().length > NOTE_MAX_LENGTH
        })
    }
    out.sort(function(a, b) {
        return a.date < b.date ? -1 : (a.date > b.date ? 1 : (a.projectId < b.projectId ? -1 : 1))
    })
    return out
}

/**
 * What migrating one local entry against the server's GET answer does:
 *   { action: "push", patch }  server empty → PUT the local values
 *   { action: "same" }         server already equal
 *   { action: "conflict" }     server has other values → server wins
 * A local break of 45 is sent as explicit 45 (B7: locally a default cannot be
 * told from a deliberate value). A local productionDay 0 is empty (B5).
 */
function migrationDecision(localEntry, serverJson) {
    var patch = toApiPatch(localEntry, serverJson)
    if (isEmptyPatch(patch)) {
        return { action: "same", patch: {} }
    }
    if (isServerEmpty(serverJson)) {
        return { action: "push", patch: patch }
    }
    return { action: "conflict", patch: patch }
}

/** Returns a new map with the migration result recorded on `key` for `profileKey`. */
function markMigrated(map, key, profileKey, result, atIso) {
    var next = {}
    for (var k in (map || {})) {
        next[k] = map[k]
    }
    var stored = next[key]
    if (!stored) {
        return next
    }
    var copy = {}
    for (var f in stored) {
        copy[f] = stored[f]
    }
    var migrated = {}
    for (var p in (stored.migrated || {})) {
        migrated[p] = stored.migrated[p]
    }
    migrated[profileKey] = { result: String(result), at: String(atIso || "") }
    copy.migrated = migrated
    next[key] = copy
    return next
}
