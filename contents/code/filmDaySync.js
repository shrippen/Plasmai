.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./filmDays.js" as FilmDays

/**
 * Film-day orchestration shared by the Plasmoid (contents/ui/main.qml) and
 * the app (app/qml/FilmDayPage.qml): whether the Drehzettel plugin can take
 * the extras, loading a day, and the two-step save (Kimai timesheet, then
 * film-day PUT).
 *
 * Online only: the extras live in the plugin on the server. Plasmai keeps
 * no copy on the device and queues nothing; a failed write is reported.
 *
 *   ctx = {
 *     url, token,          Kimai server and API token of the active profile
 *     profileKey,          profileKey(profileId, url)
 *     mode,                Mode.* from resolveMode()
 *     ping,                last ping body (features, permissions) or null
 *     memo,                plain object kept by the caller between calls
 *                          (engagement lists 1 h, day cache)
 *     tracker,             timesheet API (default KimaiApi)
 *     nowMs                optional clock for tests
 *   }
 */

var Mode = {
    /** No Drehzettel plugin (ping 404 / no v1): begin and end only. */
    NO_PLUGIN: "noPlugin",
    /** Plugin present: extras on the server. */
    SERVER: "server",
    /** Server mode, but no project picked yet. */
    NO_PROJECT: "noProject",
    /** Server mode, project+date outside any engagement of the user. */
    NO_ENGAGEMENT: "noEngagement",
    /** Plugin present, token owner lacks the "drehzettel" permission. */
    NO_PERMISSION: "noPermission",
    /** Plugin state or day not reachable right now (network, 5xx). */
    OFFLINE: "offline"
}

var ENGAGEMENT_CACHE_MS = 3600 * 1000
var PRODUCTION_DAY_CACHE_MS = 10 * 60 * 1000
/** Days before today the background prefetch fills (the last month). */
var PREFETCH_DAYS = 31
/** A new prefetch of the last month at most this often per profile. */
var PREFETCH_INTERVAL_MS = 3600 * 1000

/** Where a day's answers come from (ctx.source). */
var Source = {
    /** Only the day cache; a missing answer marks ctx.missed. */
    CACHE: "cache",
    /** The server; answers are stored in the day cache. */
    LIVE: "live"
}

function profileKey(profileId, kimaiUrl) {
    return String(profileId || "") + "|" + KimaiApi.normalizeUrl(kimaiUrl)
}

function trackerOf(ctx) {
    return (ctx && ctx.tracker) ? ctx.tracker : KimaiApi
}

function nowOf(ctx) {
    return (ctx && typeof ctx.nowMs === "number") ? ctx.nowMs : Date.now()
}

function memoOf(ctx) {
    if (!ctx.memo) {
        ctx.memo = {}
    }
    if (!ctx.memo.engagements) {
        ctx.memo.engagements = {}
    }
    if (!ctx.memo.productionDays) {
        ctx.memo.productionDays = {}
    }
    if (!ctx.memo.days) {
        ctx.memo.days = {}
    }
    if (!ctx.memo.prefetched) {
        ctx.memo.prefetched = {}
    }
    return ctx.memo
}

/** Mode from a KimaiApi.detectDrehzettel() answer. */
function modeFromDetection(detection) {
    var state = detection ? detection.state : KimaiApi.PluginState.UNKNOWN
    if (state === KimaiApi.PluginState.PRESENT) {
        return KimaiApi.drehzettelCanView(detection.data) ? Mode.SERVER : Mode.NO_PERMISSION
    }
    if (state === KimaiApi.PluginState.ABSENT) {
        return Mode.NO_PLUGIN
    }
    if (state === KimaiApi.PluginState.FORBIDDEN) {
        return Mode.NO_PERMISSION
    }
    return Mode.OFFLINE
}

/**
 * Probe the plugin (cached 24 h per profile in probeCache, a parsed
 * pluginProbesJson map). callback({ mode, ping, probeCache }) where
 * probeCache is the updated map to persist, or null if unchanged.
 */
function resolveMode(url, token, profileId, probeCache, options, callback) {
    var o = options || {}
    var key = KimaiApi.pluginCacheKey(profileId, url, KimaiApi.DREHZETTEL_PLUGIN)
    KimaiApi.detectDrehzettel(url, token, {
        cache: probeCache, key: key, nowMs: o.nowMs, force: !!o.force
    }, function(det) {
        callback({
            mode: modeFromDetection(det),
            ping: det.data || null,
            probeCache: det.cacheEntry ? KimaiApi.storePluginCache(probeCache, key, det.cacheEntry) : null
        })
    })
}

/** The extras are shown and editable only with the day loaded from the server. */
function extrasVisible(mode) {
    return mode === Mode.SERVER
}

function extrasEditable(mode) {
    return mode === Mode.SERVER
}

function hasId(value) {
    return value !== null && value !== undefined && value !== ""
}

/**
 * D1 engagement list of dateStr (cached 1 h per profile+date in memo).
 * callback(list) or callback(null) without the "engagements" feature or on
 * an error.
 */
function loadEngagements(ctx, dateStr, callback) {
    if (!KimaiApi.drehzettelHasFeature(ctx.ping, "engagements")) {
        callback(null)
        return
    }
    var memo = memoOf(ctx)
    var ekey = String(ctx.profileKey) + "|" + dateStr
    var cached = memo.engagements[ekey]
    // The day cache takes any age; the live check keeps the 1 h.
    if (cached && (ctx.source === Source.CACHE || nowOf(ctx) - cached.at < ENGAGEMENT_CACHE_MS)) {
        callback(cached.list)
        return
    }
    if (ctx.source === Source.CACHE) {
        ctx.missed = true
        callback(null)
        return
    }
    KimaiApi.fetchDrehzettelEngagements(ctx.url, ctx.token, dateStr, function(result) {
        if (!result.ok) {
            callback(null)
            return
        }
        if (cached && JSON.stringify(cached.list) !== JSON.stringify(result.data)) {
            ctx.changed = true
        }
        memo.engagements[ekey] = { at: nowOf(ctx), list: result.data }
        callback(result.data)
    })
}

/**
 * Ruleset name of the project's engagement on dateStr, from the D1 list
 * or engagement-status for older plugins.
 */
function loadRulesetName(ctx, projectId, dateStr, callback) {
    if (KimaiApi.drehzettelHasFeature(ctx.ping, "engagements")) {
        loadEngagements(ctx, dateStr, function(list) {
            for (var i = 0; i < (list || []).length; i++) {
                if (list[i] && String(list[i].projectId) === String(projectId)) {
                    callback(list[i].rulesetName || "")
                    return
                }
            }
            callback("")
        })
        return
    }
    dayCall(ctx, dateStr, "status|" + projectId, function(done) {
        KimaiApi.fetchEngagementStatus(ctx.url, ctx.token, projectId, dateStr, done)
    }, function(result) {
        callback(result.ok && result.data && result.data.active ? (result.data.rulesetName || "") : "")
    })
}

/** The day's engagements (D1), [] without an engagement, the feature or the plugin. */
function dayEngagements(ctx, dateStr, callback) {
    if (ctx.mode === Mode.NO_PLUGIN || ctx.mode === Mode.NO_PERMISSION) {
        callback([])
        return
    }
    loadEngagements(ctx, dateStr, function(list) {
        var out = []
        for (var i = 0; i < (list || []).length; i++) {
            if (list[i] && hasId(list[i].projectId)) {
                out.push(list[i])
            }
        }
        callback(out)
    })
}

function engagementOf(engagements, projectId) {
    for (var i = 0; i < (engagements || []).length; i++) {
        if (String(engagements[i].projectId) === String(projectId)) {
            return engagements[i]
        }
    }
    return null
}

/**
 * Production shooting day of the engagement on dateStr, and its film
 * activity: the project's entries from fromDateStr (the engagement's start)
 * to dateStr. With the engagement's whitelist `activityIds` (plugin) the
 * count is the distinct days with whitelisted entries and the film activity
 * the longest of them. Without one the film activity is activityId, or else
 * the activity of the longest entry; the count is the distinct days with
 * entries of it. ids = { projectOf, activityOf }. callback({ count, includesDay, activityId })
 * or callback(null) on an error. Cached per profile, project and day for 10 minutes.
 */
function productionDay(ctx, projectId, activityId, activityIds, fromDateStr, dateStr, ids, callback) {
    if (!hasId(projectId) || !fromDateStr) {
        callback(null)
        return
    }
    var memo = memoOf(ctx)
    // One fetch from the engagement's start to today (or a later dateStr)
    // serves every day of it: day steps count from the same entries.
    var key = [ctx.profileKey, projectId, fromDateStr].join("|")
    var todayStr = KimaiApi.localDateString(new Date(nowOf(ctx)))
    var toStr = dateStr > todayStr ? dateStr : todayStr
    var whitelisted = !!activityIds && activityIds.length > 0
    function answer(entries) {
        if (whitelisted) {
            var listed = FilmDays.filmEntries(entries, activityIds, ids.activityOf)
            var longest = FilmDays.suggestedActivityId(listed, projectId, ids.projectOf, ids.activityOf)
            var listedCount = FilmDays.countShootingDays(listed, dateStr, function(ts) { return ts.begin })
            listedCount.activityId = hasId(longest) ? longest : activityIds[0]
            callback(listedCount)
            return
        }
        var activity = hasId(activityId) ? activityId
            : FilmDays.suggestedActivityId(entries, projectId, ids.projectOf, ids.activityOf)
        var film = []
        for (var i = 0; i < entries.length; i++) {
            if (hasId(activity) && String(ids.activityOf(entries[i])) === String(activity)) {
                film.push(entries[i])
            }
        }
        var count = FilmDays.countShootingDays(film, dateStr, function(ts) { return ts.begin })
        count.activityId = hasId(activity) ? activity : null
        callback(count)
    }
    var cached = memo.productionDays[key]
    if (cached && cached.toStr >= dateStr && nowOf(ctx) - cached.at < PRODUCTION_DAY_CACHE_MS) {
        answer(cached.entries)
        return
    }
    var from = new Date(fromDateStr + "T00:00:00")
    var to = new Date(toStr + "T23:59:59")
    trackerOf(ctx).fetchTimesheetsRange(ctx.url, ctx.token, from, to, function(result) {
        if (!result.ok) {
            callback(null)
            return
        }
        memo.productionDays[key] = { at: nowOf(ctx), toStr: toStr, entries: result.data || [] }
        answer(result.data || [])
    }, { project: projectId })
}

/**
 * Project of the day's engagement (there is at most one engagement per day;
 * entries of other activities that day belong to none). callback(projectId)
 * or callback(null) without an engagement or without the D1 list.
 */
function dayEngagementProject(ctx, dateStr, callback) {
    dayEngagements(ctx, dateStr, function(list) {
        callback(list.length ? list[0].projectId : null)
    })
}

function emptyLoad(mode, error) {
    return {
        mode: mode,
        fields: FilmDays.entryDefaults(),
        server: null,
        defaultBreakMinutes: -1,
        effectiveCategory: "",
        rulesetName: "",
        summary: null,
        error: error || null
    }
}

/**
 * Load the extras of (projectId, dateStr). callback(result):
 *   { mode, fields, server, defaultBreakMinutes, effectiveCategory,
 *     rulesetName, summary, error }
 * `server` is the film-day JSON the next save diffs against. Without a
 * server answer the extras stay hidden (mode is not SERVER).
 */
function loadDay(ctx, projectId, dateStr, callback) {
    if (ctx.mode === Mode.NO_PLUGIN || ctx.mode === Mode.NO_PERMISSION) {
        callback(emptyLoad(ctx.mode))
        return
    }
    if (!hasId(projectId)) {
        callback(emptyLoad(ctx.mode === Mode.OFFLINE ? Mode.OFFLINE : Mode.NO_PROJECT))
        return
    }
    dayCall(ctx, dateStr, "filmDay|" + projectId, function(done) {
        KimaiApi.fetchFilmDay(ctx.url, ctx.token, projectId, dateStr, done)
    }, function(result) {
        if (!result.ok) {
            var err = result.error || {}
            if (err.status === 404 && !err.code && ctx.mode === Mode.OFFLINE) {
                // Plugin state unknown and a plain Kimai 404: plugin missing or
                // an old plugin without error codes, cannot tell. Stay careful.
                callback(emptyLoad(Mode.OFFLINE, err))
                return
            }
            if (err.status === 404) {
                callback(emptyLoad(Mode.NO_ENGAGEMENT))
                return
            }
            if (err.status === 403) {
                callback(emptyLoad(Mode.NO_PERMISSION))
                return
            }
            callback(emptyLoad(Mode.OFFLINE, err))
            return
        }
        var json = result.data || {}
        var out = emptyLoad(Mode.SERVER)
        out.fields = FilmDays.fromApi(json)
        out.server = json
        out.defaultBreakMinutes = typeof json.defaultBreakMinutes === "number" ? json.defaultBreakMinutes : -1
        out.effectiveCategory = json.effectiveCategory ? String(json.effectiveCategory) : ""
        var waiting = 1
        var wantSummary = KimaiApi.drehzettelHasFeature(ctx.ping, "daySummary")
        if (wantSummary) {
            waiting += 1
        }
        function done() {
            waiting -= 1
            if (waiting === 0) {
                callback(out)
            }
        }
        loadRulesetName(ctx, projectId, dateStr, function(name) {
            out.rulesetName = name
            done()
        })
        if (wantSummary) {
            dayCall(ctx, dateStr, "summary|" + projectId, function(summaryDone) {
                KimaiApi.fetchDaySummary(ctx.url, ctx.token, projectId, dateStr, summaryDone)
            }, function(sres) {
                out.summary = sres.ok ? sres.data : null
                done()
            })
        }
    })
}

/**
 * Everything the film-day view shows for dateStr, from the day's timesheets
 * (`entries`, hydrated): the project is the day's engagement, else
 * `selectedProjectId`; the entry is the one the plugin's day summary spans,
 * else the project's longest. With preferSelected the chosen project wins (the
 * engagement chooser). ids = { projectOf, activityOf } read an entry's project
 * and activity id. callback({ projectId, engagement, engagements, match,
 * others, day, activityIds }): `engagement` is the D1 entry of projectId (or
 * null), `day` from loadDay(), `others` further entries of the film day's
 * activity only. With the engagement's whitelist `activityIds` (plugin) only
 * whitelisted entries are film time, as in the plugin's begin and end of the
 * day: `match` and `others` come from them, others of any listed activity.
 */
function resolveDay(ctx, entries, selectedProjectId, dateStr, ids, callback, preferSelected) {
    dayEngagements(ctx, dateStr, function(engagements) {
        var engaged = engagements.length ? engagements[0].projectId : null
        var projectId = (preferSelected && hasId(selectedProjectId)) || !hasId(engaged) ? selectedProjectId : engaged
        loadDay(ctx, projectId, dateStr, function(day) {
            var summary = day.summary
            var span = (summary && summary.hasEntry !== false && summary.begin && summary.end)
                ? { begin: summary.begin, end: summary.end } : null
            var engagement = engagementOf(engagements, projectId)
            var activityIds = (engagement && engagement.activityIds) || []
            var film = FilmDays.filmEntries(entries, activityIds, ids.activityOf)
            var match = FilmDays.pickDayEntry(film, projectId, ids.projectOf, span)
            // Whitelist: every listed activity belongs to the one film day (Set + Dreh).
            var sameActivity = activityIds.length ? null : ids.activityOf
            callback({
                projectId: hasId(projectId) ? projectId : null,
                engagement: engagement,
                engagements: engagements,
                match: match,
                others: FilmDays.otherDayEntries(film, match, projectId, ids.projectOf, sameActivity),
                day: day,
                activityIds: activityIds
            })
        })
    })
}

/**
 * What the film day screen shows, from resolveDay()'s result `r` and the main
 * page's timer. opts = { entries (the day's), active (running entry or null),
 * recent (recent entries, for the usual film activity), daysFromToday, ids,
 * labelOf(ts), timeOf(ts) }. Returns { phase, isToday, timesheet, activityId,
 * otherActivities: [{ label, timeText }] }.
 */
function viewInfo(r, opts) {
    var ids = opts.ids
    var activityIds = r.activityIds || []
    var recent = FilmDays.filmEntries(opts.recent, activityIds, ids.activityOf)
    var filmActivity = r.match ? ids.activityOf(r.match)
        : FilmDays.suggestedActivityId(recent, r.projectId, ids.projectOf, ids.activityOf)
    if (!hasId(filmActivity) && activityIds.length) {
        filmActivity = activityIds[0]
    }
    var active = opts.active
    // A running entry outside the engagement's whitelist (commute) is never the film day.
    var counts = !!active && FilmDays.countsActivity(activityIds, ids.activityOf(active))
    // The film day is the day's longest entry, the running one with its time so far:
    // a shoot running after the commute counts, a drive home after the shoot does not.
    if (counts && r.match && opts.daysFromToday === 0 && String(ids.projectOf(active)) === String(r.projectId)) {
        var now = opts.nowMs || Date.now()
        var runningMs = now - FilmDays.stampMs(active.begin)
        var matchMs = FilmDays.stampMs(r.match.end) - FilmDays.stampMs(r.match.begin)
        if (runningMs > matchMs) {
            filmActivity = ids.activityOf(active)
        }
    }
    var running = counts && opts.daysFromToday === 0 && hasId(r.projectId)
        && String(ids.projectOf(active)) === String(r.projectId)
        && (activityIds.length > 0 || !hasId(filmActivity) || String(ids.activityOf(active)) === String(filmActivity))
    var shown = running ? active : r.match
    var skip = [shown].concat(r.others || [])
    var otherActivities = []
    for (var i = 0; i < (opts.entries || []).length; i++) {
        var ts = opts.entries[i]
        if (skip.indexOf(ts) >= 0 || (shown && hasId(ts.id) && String(ts.id) === String(shown.id))) {
            continue
        }
        otherActivities.push({ label: opts.labelOf(ts), timeText: opts.timeOf(ts) })
    }
    return {
        phase: FilmDays.phaseOf({ running: running, match: r.match, daysFromToday: opts.daysFromToday }),
        isToday: opts.daysFromToday === 0,
        timesheet: shown || null,
        activityId: running ? ids.activityOf(active) : filmActivity,
        otherActivities: otherActivities
    }
}

/**
 * Two-step save: Kimai timesheet (create or patch), then the extras.
 *   req = { projectId, dateStr, timesheetFields, existingId, fields, server, dayMode }
 *   dayMode: the mode loadDay() returned for this day; only SERVER sends extras.
 * callback(result):
 *   { ok, stage: "timesheet"|"extras", extras, error, timesheet, server }
 * extras: "saved" | "unchanged" | "failed" | "skipped"
 * ok is false only when the timesheet write failed (nothing was saved).
 */
function saveDay(ctx, req, callback) {
    var tracker = trackerOf(ctx)
    function afterTimesheet(tsResult) {
        if (!tsResult.ok) {
            callback({ ok: false, stage: "timesheet", extras: "skipped", error: tsResult.error,
                       timesheet: null, server: null })
            return
        }
        forgetDay(ctx, req.dateStr)
        saveExtras(ctx, req, function(extras) {
            extras.ok = true
            extras.timesheet = tsResult.data
            if (tsResult.droppedFields) {
                extras.droppedFields = tsResult.droppedFields
            }
            callback(extras)
        })
    }
    if (hasId(req.existingId)) {
        tracker.patchTimesheet(ctx.url, ctx.token, req.existingId, req.timesheetFields, afterTimesheet)
    } else {
        tracker.createTimesheet(ctx.url, ctx.token, req.timesheetFields, afterTimesheet)
    }
}

/** Second step of saveDay (also usable alone). */
function saveExtras(ctx, req, callback) {
    function result(extras, extra) {
        var r = { stage: "extras", extras: extras, error: null, server: null }
        for (var k in (extra || {})) {
            r[k] = extra[k]
        }
        return r
    }
    // Only a day loaded from the server has extras to send (no engagement,
    // no plugin, offline: begin and end only, the view says so).
    if (!hasId(req.projectId) || ctx.mode !== Mode.SERVER || req.dayMode !== Mode.SERVER || !req.server) {
        callback(result("skipped"))
        return
    }
    var patch = FilmDays.toApiPatch(req.fields, req.server)
    if (FilmDays.isEmptyPatch(patch)) {
        callback(result("unchanged", { server: req.server }))
        return
    }
    KimaiApi.putFilmDay(ctx.url, ctx.token, req.projectId, req.dateStr, patch, function(put) {
        if (put.ok) {
            forgetDay(ctx, req.dateStr)
            callback(result("saved", { server: put.data }))
            return
        }
        callback(result("failed", { error: put.error }))
    })
}

/**
 * Delete the other entries of a merged film day (B3), one by one.
 * callback({ deleted, failed: [{ id, error }] }). Failures do not stop the
 * rest; the caller reports them.
 */
function deleteEntries(ctx, ids, callback) {
    var tracker = trackerOf(ctx)
    var report = { deleted: 0, failed: [] }
    var i = 0
    function step() {
        if (i >= (ids || []).length) {
            callback(report)
            return
        }
        var id = ids[i++]
        tracker.deleteTimesheet(ctx.url, ctx.token, id, function(res) {
            if (res && res.ok) {
                report.deleted += 1
            } else {
                report.failed.push({ id: id, error: res ? res.error : null })
            }
            step()
        })
    }
    step()
}

// ── Day cache ────────────────────────────────────────────────────────────
//
// Stale-while-revalidate for the film day screen: a day opens from the
// cache at once, then the live answers replace it only when they differ.
//
//   openDay ─┬─► CACHE pass: all answers cached? ──► callback(.., CACHED)
//            └─► LIVE pass: server, stores answers ──► callback(.., LIVE)
//                    (skipped when the cached view was shown and nothing changed)
//
// prefetchDays() fills the last month in the background; older days load live.
//
//   memo.days[profileKey][dateStr][what] = { at, result }
//   what: "timesheets" | "filmDay|<project>" | "summary|<project>" | "status|<project>"

/** A copy of ctx for one pass (missed / changed are per pass). */
function withSource(ctx, source) {
    memoOf(ctx)
    var out = {}
    for (var k in ctx) {
        out[k] = ctx[k]
    }
    out.source = source
    out.missed = false
    out.changed = false
    return out
}

function dayStore(ctx, dateStr) {
    var memo = memoOf(ctx)
    var profile = memo.days[ctx.profileKey] || (memo.days[ctx.profileKey] = {})
    return profile[dateStr] || (profile[dateStr] = {})
}

/** Answers worth keeping: success, and "no engagement" / "no permission" (404/403). */
function cacheable(result) {
    if (result.ok) {
        return true
    }
    var status = result.error ? result.error.status : 0
    return status === 404 || status === 403
}

function storeAnswer(ctx, dateStr, what, result) {
    if (!cacheable(result)) {
        // Network error: a view shown from the cache stays (offline stays usable).
        return
    }
    var store = dayStore(ctx, dateStr)
    var before = store[what]
    if (!before || JSON.stringify(before.result) !== JSON.stringify(result)) {
        ctx.changed = true
    }
    store[what] = { at: nowOf(ctx), result: result }
}

/**
 * One answer of dateStr: from the day cache (Source.CACHE) or from `live`
 * (stored). Without a source (saves, older callers) always live, stored too.
 */
function dayCall(ctx, dateStr, what, live, callback) {
    if (ctx.source === Source.CACHE) {
        var hit = dayStore(ctx, dateStr)[what]
        if (!hit) {
            ctx.missed = true
            callback({ ok: false, data: null, error: { type: "cache", status: 0, detail: "" } })
            return
        }
        callback(hit.result)
        return
    }
    live(function(result) {
        storeAnswer(ctx, dateStr, what, result)
        callback(result)
    })
}

/** Drops the cached answers of dateStr (after a save: the next open is live only). */
function forgetDay(ctx, dateStr) {
    var memo = memoOf(ctx)
    if (memo.days[ctx.profileKey]) {
        delete memo.days[ctx.profileKey][dateStr]
    }
}

/** Timesheets of the local day `date` (raw, not hydrated). */
function dayTimesheets(ctx, date, callback) {
    dayCall(ctx, KimaiApi.localDateString(date), "timesheets", function(done) {
        trackerOf(ctx).fetchTimesheetsRange(ctx.url, ctx.token,
            KimaiApi.startOfLocalDay(date), KimaiApi.endOfLocalDay(date), done)
    }, callback)
}

/**
 * Opens `date` on the film day screen: resolveDay() from the cache first,
 * then live. callback(r, entries, source) runs up to twice: Source.CACHE when
 * every answer was cached, Source.LIVE unless it equals the cached view.
 * hydrate(raw) turns raw timesheets into the view's entries. Starts the
 * background prefetch of the last month (at most hourly per profile).
 */
function openDay(ctx, date, selectedProjectId, ids, hydrate, callback, preferSelected) {
    var dateStr = KimaiApi.localDateString(date)
    function run(pass, done) {
        dayTimesheets(pass, date, function(result) {
            var entries = result.ok ? hydrate(result.data || []) : []
            resolveDay(pass, entries, selectedProjectId, dateStr, ids, function(r) {
                done(r, entries)
            }, preferSelected)
        })
    }

    var shown = false
    var cached = withSource(ctx, Source.CACHE)
    run(cached, function(r, entries) {
        if (cached.missed) {
            return
        }
        shown = true
        callback(r, entries, Source.CACHE)
    })

    var live = withSource(ctx, Source.LIVE)
    run(live, function(r, entries) {
        if (!shown || live.changed) {
            callback(r, entries, Source.LIVE)
        }
        prefetchDays(ctx)
    })
}

/** Local "YYYY-MM-DD" keys of the days `ts` overlaps (a running entry until now). */
function overlappedDays(ts, nowMs) {
    var begin = FilmDays.stampMs(ts.begin)
    var end = ts.end ? FilmDays.stampMs(ts.end) : nowMs
    if (isNaN(begin) || isNaN(end)) {
        return []
    }
    var out = []
    var day = new Date(begin)
    day.setHours(0, 0, 0, 0)
    while (day.getTime() <= end) {
        out.push(KimaiApi.localDateString(day))
        day.setDate(day.getDate() + 1)
    }
    return out
}

/**
 * Background fill of the day cache for the last PREFETCH_DAYS days: one
 * timesheet fetch split by day (as Kimai's range filter: every day an entry
 * overlaps), then day by day, newest first, the extras of the day's
 * engagement. Days without an engagement stay live. done() when finished or
 * skipped (prefetched within PREFETCH_INTERVAL_MS).
 */
function prefetchDays(ctx, done) {
    var finish = done || function() {}
    var memo = memoOf(ctx)
    var last = memo.prefetched[ctx.profileKey]
    if (last !== undefined && nowOf(ctx) - last < PREFETCH_INTERVAL_MS) {
        finish()
        return
    }
    memo.prefetched[ctx.profileKey] = nowOf(ctx)
    var live = withSource(ctx, Source.LIVE)

    var today = new Date(nowOf(ctx))
    var dates = []
    for (var i = 0; i < PREFETCH_DAYS; i++) {
        var d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - i)
        dates.push(d)
    }
    var first = dates[dates.length - 1]

    trackerOf(ctx).fetchTimesheetsRange(ctx.url, ctx.token,
        KimaiApi.startOfLocalDay(first), KimaiApi.endOfLocalDay(today), function(result) {
        if (!result.ok) {
            delete memo.prefetched[ctx.profileKey]
            finish()
            return
        }
        splitTimesheets(live, dates, result.data || [])
        prefetchExtras(live, dates, 0, finish)
    })
}

/** Stores a range fetch as the per-day "timesheets" answers of `dates`. */
function splitTimesheets(ctx, dates, entries) {
    var byDay = {}
    for (var i = 0; i < dates.length; i++) {
        byDay[KimaiApi.localDateString(dates[i])] = []
    }
    for (var j = 0; j < entries.length; j++) {
        var keys = overlappedDays(entries[j], nowOf(ctx))
        for (var k = 0; k < keys.length; k++) {
            if (byDay[keys[k]]) {
                byDay[keys[k]].push(entries[j])
            }
        }
    }
    for (var key in byDay) {
        storeAnswer(ctx, key, "timesheets", { ok: true, data: byDay[key], error: null })
    }
}

/** Day by day (one at a time, the server is not flooded): engagements, then loadDay(). */
function prefetchExtras(ctx, dates, index, done) {
    if (index >= dates.length || ctx.mode !== Mode.SERVER) {
        done()
        return
    }
    var dateStr = KimaiApi.localDateString(dates[index])
    function next() {
        prefetchExtras(ctx, dates, index + 1, done)
    }
    dayEngagements(ctx, dateStr, function(engagements) {
        if (!engagements.length) {
            next()
            return
        }
        loadDay(ctx, engagements[0].projectId, dateStr, next)
    })
}
