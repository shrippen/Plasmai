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
 *                          (engagement lists, 1 h)
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
    if (cached && nowOf(ctx) - cached.at < ENGAGEMENT_CACHE_MS) {
        callback(cached.list)
        return
    }
    KimaiApi.fetchDrehzettelEngagements(ctx.url, ctx.token, dateStr, function(result) {
        if (!result.ok) {
            callback(null)
            return
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
    KimaiApi.fetchEngagementStatus(ctx.url, ctx.token, projectId, dateStr, function(result) {
        callback(result.ok && result.data && result.data.active ? (result.data.rulesetName || "") : "")
    })
}

/**
 * Project of the day's engagement (there is at most one engagement per day;
 * entries of other activities that day belong to none). callback(projectId)
 * or callback(null) without an engagement or without the D1 list.
 */
function dayEngagementProject(ctx, dateStr, callback) {
    if (ctx.mode === Mode.NO_PLUGIN || ctx.mode === Mode.NO_PERMISSION) {
        callback(null)
        return
    }
    loadEngagements(ctx, dateStr, function(list) {
        var first = (list && list.length) ? list[0] : null
        callback(first && hasId(first.projectId) ? first.projectId : null)
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
    KimaiApi.fetchFilmDay(ctx.url, ctx.token, projectId, dateStr, function(result) {
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
            KimaiApi.fetchDaySummary(ctx.url, ctx.token, projectId, dateStr, function(sres) {
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
 * else the project's longest. ids = { projectOf, activityOf } read an entry's
 * project and activity id. callback({ projectId, match, others, day }) with
 * `day` from loadDay(); `others` are further entries of the film day's
 * activity only.
 */
function resolveDay(ctx, entries, selectedProjectId, dateStr, ids, callback) {
    dayEngagementProject(ctx, dateStr, function(engaged) {
        var projectId = hasId(engaged) ? engaged : selectedProjectId
        loadDay(ctx, projectId, dateStr, function(day) {
            var summary = day.summary
            var span = (summary && summary.hasEntry !== false && summary.begin && summary.end)
                ? { begin: summary.begin, end: summary.end } : null
            var match = FilmDays.pickDayEntry(entries, projectId, ids.projectOf, span)
            callback({
                projectId: hasId(projectId) ? projectId : null,
                match: match,
                others: FilmDays.otherDayEntries(entries, match, projectId, ids.projectOf, ids.activityOf),
                day: day
            })
        })
    })
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
