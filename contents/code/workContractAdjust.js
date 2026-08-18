.pragma library

/**
 * Adjust weekly work targets using absences and public holidays.
 *
 * Sources (never both on one Kimai):
 * - holiday-bundle: /api/holiday/* (kimai-holiday-bundle)
 * - work-contract: /api/absences and /api/public-holidays (WorkContractBundle)
 *
 * REDUCE semantics for vacation/sickness/holiday on contracted work days.
 * WorkContractBundle may also auto-book those hours as timesheets; credit
 * those durations so remaining hours are not subtracted twice.
 */

var SOURCE_NONE = "none"
var SOURCE_HOLIDAY_BUNDLE = "holiday-bundle"
var SOURCE_WORK_CONTRACT = "work-contract"
/** Re-probe which absence plugin is installed (same Kimai URL can switch). */
var HOLIDAY_PLUGIN_TTL_MS = 60 * 60 * 1000

function holidayPluginCacheEntry(source, atMs) {
    return { source: source || SOURCE_NONE, at: atMs || 0 }
}

/** Return cached source, or "" if missing/stale (caller must probe again). */
function holidayPluginCacheSource(entry, nowMs, ttlMs) {
    if (!entry || !entry.source) {
        return ""
    }
    var ttl = ttlMs > 0 ? ttlMs : HOLIDAY_PLUGIN_TTL_MS
    var now = nowMs || Date.now()
    if (now - Number(entry.at || 0) >= ttl) {
        return ""
    }
    return entry.source
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

function dateKey(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function parseIsoDate(text) {
    if (!text) {
        return null
    }
    var parts = String(text).substring(0, 10).split("-")
    if (parts.length !== 3) {
        return null
    }
    var y = parseInt(parts[0], 10)
    var m = parseInt(parts[1], 10) - 1
    var d = parseInt(parts[2], 10)
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
        return null
    }
    return new Date(y, m, d)
}

function unwrapCollection(data) {
    if (Array.isArray(data)) {
        return data
    }
    if (!data) {
        return []
    }
    if (Array.isArray(data.data)) {
        return data.data
    }
    if (Array.isArray(data.items)) {
        return data.items
    }
    if (Array.isArray(data["hydra:member"])) {
        return data["hydra:member"]
    }
    return []
}

function isHalfDayFlag(obj) {
    if (!obj) {
        return false
    }
    return !!(obj.halfDay || obj.half_day)
}

function absenceTypeOf(absence) {
    return String(absence && absence.type || "").toLowerCase().replace(/-/g, "_")
}

function pluginPresentFromStatus(status) {
    return status === 200 || status === 403
}

function holidaySourceFromProbes(holidayTypesStatus, workContractTypesStatus) {
    if (pluginPresentFromStatus(holidayTypesStatus)) {
        return SOURCE_HOLIDAY_BUNDLE
    }
    if (pluginPresentFromStatus(workContractTypesStatus)) {
        return SOURCE_WORK_CONTRACT
    }
    return SOURCE_NONE
}

function normalizeAbsence(raw) {
    if (!raw) {
        return null
    }
    var start = raw.startDate || raw.start_date || raw.date
    var end = raw.endDate || raw.end_date || start
    var startText = String(start || "").substring(0, 10)
    if (!startText) {
        return null
    }
    var duration = raw.duration
    return {
        type: absenceTypeOf(raw),
        status: String(raw.status || "").toLowerCase(),
        startDate: startText,
        endDate: String(end || startText).substring(0, 10),
        halfDay: isHalfDayFlag(raw),
        duration: duration === null || duration === undefined || duration === "" ? null : Number(duration)
    }
}

function normalizeAbsences(list) {
    var raw = unwrapCollection(list)
    var out = []
    for (var i = 0; i < raw.length; i++) {
        var item = normalizeAbsence(raw[i])
        if (item) {
            out.push(item)
        }
    }
    return out
}

function normalizePublicHoliday(raw) {
    if (!raw) {
        return null
    }
    var date = String(raw.date || "").substring(0, 10)
    if (!date) {
        return null
    }
    return {
        date: date,
        halfDay: isHalfDayFlag(raw)
    }
}

function normalizePublicHolidays(list) {
    var raw = unwrapCollection(list)
    var out = []
    for (var i = 0; i < raw.length; i++) {
        var item = normalizePublicHoliday(raw[i])
        if (item) {
            out.push(item)
        }
    }
    return out
}

function isApprovedAbsence(absence) {
    if (!absence) {
        return false
    }
    var status = String(absence.status || "").toLowerCase()
    var type = absenceTypeOf(absence)
    if (status === "rejected" || status === "declined" || status === "denied") {
        return false
    }
    if (status === "approved" || status === "confirmed" || status === "accepted" || status === "") {
        return true
    }
    // Requested / open / new: sickness is effective without an approval step.
    return type === "sickness" || type === "sickness_relative"
}

function absenceReducesExpected(absence) {
    var type = absenceTypeOf(absence)
    return type === "vacation"
        || type === "holiday"
        || type === "sickness"
        || type === "sickness_relative"
        || type === "time_off"
        || type === "other"
}

function absenceCoversDate(absence, date) {
    if (!isApprovedAbsence(absence) || !absenceReducesExpected(absence)) {
        return false
    }
    var start = parseIsoDate(absence.startDate)
    var end = parseIsoDate(absence.endDate || absence.startDate)
    if (!start || !end) {
        return false
    }
    var day = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    var from = new Date(start.getFullYear(), start.getMonth(), start.getDate())
    var to = new Date(end.getFullYear(), end.getMonth(), end.getDate())
    return day.getTime() >= from.getTime() && day.getTime() <= to.getTime()
}

function publicHolidayForDate(publicHolidays, date) {
    var key = dateKey(date)
    for (var i = 0; i < (publicHolidays || []).length; i++) {
        var ph = publicHolidays[i]
        if (ph && String(ph.date || "").substring(0, 10) === key) {
            return ph
        }
    }
    return null
}

/** Time-off duration: Kimai seconds, or hours when the value is a small integer. */
function durationToSeconds(duration) {
    var n = Number(duration)
    if (!n || n <= 0 || isNaN(n)) {
        return 0
    }
    if (n < 1000) {
        return Math.floor(n * 3600)
    }
    return Math.floor(n)
}

function reduceSecondsForCovering(covering, baseExpected) {
    if (!covering || baseExpected <= 0) {
        return 0
    }
    var timed = durationToSeconds(covering.duration)
    if (timed > 0) {
        return Math.min(baseExpected, timed)
    }
    return covering.halfDay ? Math.floor(baseExpected / 2) : baseExpected
}

function reduceFromBase(baseExpected, date, absences, publicHolidays) {
    if (baseExpected <= 0) {
        return 0
    }
    var covering = null
    for (var a = 0; a < (absences || []).length; a++) {
        var absence = absences[a]
        if (absenceCoversDate(absence, date)) {
            covering = absence
            break
        }
    }
    var ph = publicHolidayForDate(publicHolidays, date)
    var reduce = 0
    if (covering) {
        reduce = reduceSecondsForCovering(covering, baseExpected)
    }
    if (ph) {
        var phReduce = ph.halfDay ? Math.floor(baseExpected / 2) : baseExpected
        reduce = Math.max(reduce, phReduce)
    }
    return Math.min(baseExpected, reduce)
}

function reduceSecondsForDay(prefs, date, absences, publicHolidays, daySecondsFn) {
    if (!prefs || typeof daySecondsFn !== "function") {
        return 0
    }
    return reduceFromBase(daySecondsFn(prefs, date), date, absences, publicHolidays)
}

function mondayOfWeek(weekAnchorDate) {
    var start = new Date(weekAnchorDate.getFullYear(), weekAnchorDate.getMonth(), weekAnchorDate.getDate())
    var day = start.getDay()
    var offset = day === 0 ? 6 : day - 1
    start.setDate(start.getDate() - offset)
    return start
}

function forEachWeekDay(weekAnchorDate, fn) {
    var start = mondayOfWeek(weekAnchorDate)
    for (var i = 0; i < 7; i++) {
        fn(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i))
    }
}

function effectiveDayTargetFromNormalized(prefs, date, absences, publicHolidays, daySecondsFn) {
    var baseExpected = daySecondsFn(prefs, date)
    return Math.max(0, baseExpected - reduceFromBase(baseExpected, date, absences, publicHolidays))
}

function effectiveDayTargetSeconds(prefs, date, absences, publicHolidays, daySecondsFn) {
    if (!prefs || typeof daySecondsFn !== "function") {
        return 0
    }
    return effectiveDayTargetFromNormalized(
        prefs, date, normalizeAbsences(absences), normalizePublicHolidays(publicHolidays), daySecondsFn)
}

/** Sum contracted seconds Mon–Sun minus vacation/holidays on work days. */
function effectiveWeekTargetSeconds(prefs, weekAnchorDate, absences, publicHolidays, daySecondsFn) {
    if (!prefs || typeof daySecondsFn !== "function" || !weekAnchorDate) {
        return 0
    }
    absences = normalizeAbsences(absences)
    publicHolidays = normalizePublicHolidays(publicHolidays)
    var total = 0
    forEachWeekDay(weekAnchorDate, function(current) {
        total += effectiveDayTargetFromNormalized(prefs, current, absences, publicHolidays, daySecondsFn)
    })
    return total
}

function entrySecondsOnLocalDate(entry, date, nowMs) {
    if (!entry || !entry.begin) {
        return 0
    }
    var begin = new Date(entry.begin)
    if (isNaN(begin.getTime())) {
        return 0
    }
    if (dateKey(begin) !== dateKey(date)) {
        return 0
    }
    if (entry.end) {
        var end = new Date(entry.end)
        if (!isNaN(end.getTime())) {
            return Math.max(0, Math.floor((end.getTime() - begin.getTime()) / 1000))
        }
    }
    if (entry.duration !== undefined && entry.duration !== null && entry.duration !== "") {
        var n = Number(entry.duration)
        if (!isNaN(n) && n > 0) {
            return Math.floor(n)
        }
    }
    var now = nowMs || Date.now()
    return Math.max(0, Math.floor((now - begin.getTime()) / 1000))
}

function trackedSecondsOnLocalDate(entries, date, nowMs) {
    var total = 0
    for (var i = 0; i < (entries || []).length; i++) {
        total += entrySecondsOnLocalDate(entries[i], date, nowMs)
    }
    return total
}

/**
 * Timesheet seconds that already fill reduced contract days (auto-booked
 * absences/holidays). Add this to remaining so target reduce + bookings
 * do not double-count.
 */
function absenceCreditSeconds(prefs, weekAnchorDate, absences, publicHolidays, entries, nowMs, daySecondsFn) {
    if (!prefs || typeof daySecondsFn !== "function" || !weekAnchorDate) {
        return 0
    }
    absences = normalizeAbsences(absences)
    publicHolidays = normalizePublicHolidays(publicHolidays)
    var credit = 0
    forEachWeekDay(weekAnchorDate, function(current) {
        var reduce = reduceSecondsForDay(prefs, current, absences, publicHolidays, daySecondsFn)
        if (reduce <= 0) {
            return
        }
        credit += Math.min(trackedSecondsOnLocalDate(entries, current, nowMs), reduce)
    })
    return credit
}

function dayAbsenceCreditSeconds(prefs, date, absences, publicHolidays, entries, nowMs, daySecondsFn) {
    if (!prefs || typeof daySecondsFn !== "function" || !date) {
        return 0
    }
    absences = normalizeAbsences(absences)
    publicHolidays = normalizePublicHolidays(publicHolidays)
    var reduce = reduceSecondsForDay(prefs, date, absences, publicHolidays, daySecondsFn)
    if (reduce <= 0) {
        return 0
    }
    return Math.min(trackedSecondsOnLocalDate(entries, date, nowMs), reduce)
}
