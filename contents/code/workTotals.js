.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./dateTimeFormat.js" as DTF

/**
 * Work time of today and this week, the contract targets and the absence
 * credit: one computation for the Plasmoid and the app (ROADMAP pillar 5,
 * step 1). The views only bind the result.
 *
 *   load(ctx, now, callback)
 *     ├─ tracker.fetchCurrentUser        → work preferences → targets
 *     ├─ KimaiApi.fetchContractAdjustments (holiday plugin, with a contract)
 *     └─ tracker.fetchTimesheetsRange    → this week's entries
 *   summarize(...) → { todaySeconds, weekSeconds, targets, credits, … }
 *
 * Seconds include a running entry up to nowMs; the views add the timer's
 * progress since then (elapsed minus the anchor they keep at load time).
 */

/** Totals without a server answer (not configured, nothing loaded yet). */
function empty() {
    return {
        prefs: ({}),
        hasWorkContract: false,
        todayTargetSeconds: 0,
        weekTargetSeconds: 0,
        weekEffectiveTargetSeconds: 0,
        absences: [],
        publicHolidays: [],
        entriesLoaded: false,
        weekEntries: [],
        todayEntries: [],
        todaySeconds: 0,
        weekSeconds: 0,
        weekAbsenceCreditSeconds: 0,
        todayAbsenceCreditSeconds: 0
    }
}

/**
 * Entries of `weekEntries` that overlap the local day of `now` (a night shoot
 * from yesterday counts; the running entry until nowMs).
 */
function todayEntriesOf(weekEntries, now, nowMs) {
    var dayStart = KimaiApi.startOfLocalDay(now).getTime()
    var dayEnd = KimaiApi.endOfLocalDay(now).getTime()
    var out = []
    for (var i = 0; i < (weekEntries || []).length; i++) {
        var entry = weekEntries[i]
        if (!entry || !entry.begin) {
            continue
        }
        var begin = DTF.stampMs(entry.begin)
        if (isNaN(begin)) {
            continue
        }
        var end = entry.end ? DTF.stampMs(entry.end) : NaN
        var endMs = isNaN(end) ? nowMs : end
        if (begin < dayEnd + 1000 && endMs > dayStart) {
            out.push(entry)
        }
    }
    return out
}

/**
 * The totals from the loaded pieces. input = {
 *   now, nowMs,
 *   tracker          provider module (preferenceMap, work*SecondsFromPrefs)
 *   user             fetchCurrentUser data, or null (failed)
 *   holidayBundle    provider has the holiday / WorkContract plugins
 *   adjustments      { absences, publicHolidays } or null
 *   weekEntries      this week's raw entries, or null (fetch failed)
 * }
 */
function summarize(input) {
    var out = empty()
    var now = input.now
    var tracker = input.tracker

    if (input.user) {
        out.prefs = tracker.preferenceMap(input.user)
        out.todayTargetSeconds = tracker.workDaySecondsFromPrefs(out.prefs, now)
        out.weekTargetSeconds = tracker.workWeekSecondsFromPrefs(out.prefs, now)
        out.hasWorkContract = out.weekTargetSeconds > 0 || out.todayTargetSeconds > 0
    }
    out.weekEffectiveTargetSeconds = out.weekTargetSeconds

    // Approved vacation and public holidays lower the targets (holiday plugin).
    var adjusting = !!input.holidayBundle && out.hasWorkContract
    if (adjusting && input.adjustments) {
        out.absences = input.adjustments.absences || []
        out.publicHolidays = input.adjustments.publicHolidays || []
        out.weekEffectiveTargetSeconds = KimaiApi.effectiveWeekTargetSeconds(
            out.prefs, now, out.absences, out.publicHolidays)
        out.todayTargetSeconds = KimaiApi.effectiveDayTargetSeconds(
            out.prefs, now, out.absences, out.publicHolidays)
    }

    if (input.weekEntries) {
        out.entriesLoaded = true
        out.weekEntries = input.weekEntries
        out.weekSeconds = KimaiApi.sumTimesheetDurations(input.weekEntries, input.nowMs)
        out.todayEntries = todayEntriesOf(input.weekEntries, now, input.nowMs)
        var intervals = KimaiApi.dayIntervalsFromTimesheets(out.todayEntries, now, input.nowMs)
        for (var i = 0; i < intervals.length; i++) {
            out.todaySeconds += intervals[i].endSec - intervals[i].startSec
        }
    }

    // Time tracked on absence days does not use up the targets.
    if (adjusting) {
        out.weekAbsenceCreditSeconds = KimaiApi.absenceCreditSeconds(
            out.prefs, now, out.absences, out.publicHolidays, out.weekEntries, input.nowMs)
        out.todayAbsenceCreditSeconds = KimaiApi.dayAbsenceCreditSeconds(
            out.prefs, now, out.absences, out.publicHolidays, out.todayEntries, input.nowMs)
    }
    return out
}

/**
 * How long the user (work preferences) and the absences stay good in a memo:
 * the poll (30 s) needs the week's entries, these change a few times a year.
 */
var MEMO_MS = 10 * 60 * 1000

/**
 * The user and, with a contract and the holiday plugin, the absences and
 * public holidays: callback(user, adjustments). From ctx.memo (a plain object
 * the caller keeps, in memory only) while of the same server, token and week
 * and younger than MEMO_MS; only answers are kept, a failure asks again.
 */
function loadContract(ctx, now, callback) {
    var nowMs = typeof ctx.nowMs === "number" ? ctx.nowMs : Date.now()
    var week = KimaiApi.startOfWeekMonday(now).getTime()
    var key = ctx.url + "\n" + ctx.token + "\n" + week
    var memo = ctx.memo
    if (memo && memo.user && memo.key === key && nowMs - memo.at < MEMO_MS) {
        callback(memo.user, memo.adjustments)
        return
    }
    function keep(user, adjustments) {
        if (memo && user) {
            memo.user = user
            memo.adjustments = adjustments
            memo.key = key
            memo.at = nowMs
        }
        callback(user, adjustments)
    }
    ctx.tracker.fetchCurrentUser(ctx.url, ctx.token, function(result) {
        var user = result.ok ? result.data : null
        var prefs = user ? ctx.tracker.preferenceMap(user) : null
        var contract = !!prefs && (ctx.tracker.workWeekSecondsFromPrefs(prefs, now) > 0
                                   || ctx.tracker.workDaySecondsFromPrefs(prefs, now) > 0)
        if (!ctx.holidayBundle || !contract) {
            keep(user, null)
            return
        }
        KimaiApi.fetchContractAdjustments(ctx.url, ctx.token, now, prefs, function(adj) {
            keep(user, (adj && adj.ok && adj.data) ? adj.data : { absences: [], publicHolidays: [] })
        })
    })
}

/**
 * Loads and summarizes. ctx = { tracker, url, token, holidayBundle, nowMs?, memo? }.
 * The requests run in parallel; callback(totals) once all answered.
 * totals.entriesLoaded is false when the week's entries failed: keep the
 * previous seconds then.
 */
function load(ctx, now, callback) {
    var input = {
        now: now,
        nowMs: 0,
        tracker: ctx.tracker,
        user: null,
        holidayBundle: !!ctx.holidayBundle,
        adjustments: null,
        weekEntries: null
    }
    var waiting = 2

    function done() {
        waiting -= 1
        if (waiting > 0) {
            return
        }
        input.nowMs = typeof ctx.nowMs === "number" ? ctx.nowMs : Date.now()
        callback(summarize(input))
    }

    loadContract(ctx, now, function(user, adjustments) {
        input.user = user
        input.adjustments = adjustments
        done()
    })

    ctx.tracker.fetchTimesheetsRange(ctx.url, ctx.token,
        KimaiApi.startOfWeekMonday(now), KimaiApi.endOfWeekSunday(now), function(result) {
        input.weekEntries = result.ok ? (result.data || []) : null
        done()
    })
}
