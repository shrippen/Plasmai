.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./filmDays.js" as FilmDays

/**
 * Film-day orchestration shared by the Plasmoid (contents/ui/main.qml) and
 * the app (app/qml/FilmDayPage.qml): which storage the extras use, loading a
 * day, the two-step save (Kimai timesheet, then film-day PUT) with an offline
 * queue, and the one-time migration of local film days to the server.
 *
 * Nothing here touches QML or shared.json directly: callers pass the parsed
 * maps in a context object and persist what the callbacks hand back.
 *
 *   ctx = {
 *     url, token,          Kimai server and API token of the active profile
 *     profileKey,          profileKey(profileId, url)
 *     mode,                Mode.* from resolveMode()
 *     ping,                last ping body (features, permissions) or null
 *     localMap,            FilmDays.parse(filmDaysJson)
 *     pendingMap,          parsePending(filmDaysPending)
 *     memo,                plain object kept by the caller between calls
 *                          (last-seen server days, engagement lists)
 *     tracker,             timesheet API (default KimaiApi)
 *     nowMs                optional clock for tests
 *   }
 */

var Mode = {
    /** No Drehzettel plugin (ping 404 / no v1): extras in shared.json. */
    LOCAL: "local",
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

function pendingKey(profKey, projectId, dateStr) {
    return String(profKey) + "|" + String(projectId) + "|" + String(dateStr)
}

function parsePending(jsonStr) {
    return FilmDays.parse(jsonStr)
}

function serializePending(map) {
    return FilmDays.serialize(map)
}

function copyMap(map) {
    var next = {}
    for (var k in (map || {})) {
        next[k] = map[k]
    }
    return next
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
    if (!ctx.memo.days) {
        ctx.memo.days = {}
    }
    if (!ctx.memo.engagements) {
        ctx.memo.engagements = {}
    }
    return ctx.memo
}

/** Transient = worth retrying later (network, timeout, 401 token hiccup, 5xx). */
function isTransientError(error) {
    var status = error ? (error.status || 0) : 0
    if (error && error.type === "config") {
        return false
    }
    return status === 0 || status === 401 || status >= 500
}

/** Mode from a KimaiApi.detectDrehzettel() answer. */
function modeFromDetection(detection) {
    var state = detection ? detection.state : KimaiApi.PluginState.UNKNOWN
    if (state === KimaiApi.PluginState.PRESENT) {
        return KimaiApi.drehzettelCanView(detection.data) ? Mode.SERVER : Mode.NO_PERMISSION
    }
    if (state === KimaiApi.PluginState.ABSENT) {
        return Mode.LOCAL
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

/** Modes that show the extras at all / let the user edit them. */
function extrasVisible(mode) {
    return mode === Mode.LOCAL || mode === Mode.SERVER || mode === Mode.OFFLINE
}

function extrasEditable(mode) {
    return mode === Mode.LOCAL || mode === Mode.SERVER
}

/** Apply a queued patch onto form fields so the user sees what will be sent. */
function applyPatchToFields(fields, patch) {
    var server = FilmDays.toApi(fields)
    for (var k in (patch || {})) {
        server[k] = patch[k]
    }
    return FilmDays.fromApi(server, fields)
}

function hasId(value) {
    return value !== null && value !== undefined && value !== ""
}

/**
 * Ruleset name of the project's engagement on dateStr, from the D1 list
 * (cached 1 h per profile+date) or engagement-status for older plugins.
 */
function loadRulesetName(ctx, projectId, dateStr, callback) {
    var memo = memoOf(ctx)
    var tracker = KimaiApi
    function pick(list) {
        for (var i = 0; i < (list || []).length; i++) {
            if (list[i] && String(list[i].projectId) === String(projectId)) {
                return list[i].rulesetName || ""
            }
        }
        return ""
    }
    if (KimaiApi.drehzettelHasFeature(ctx.ping, "engagements")) {
        var ekey = String(ctx.profileKey) + "|" + dateStr
        var cached = memo.engagements[ekey]
        if (cached && nowOf(ctx) - cached.at < ENGAGEMENT_CACHE_MS) {
            callback(pick(cached.list))
            return
        }
        tracker.fetchDrehzettelEngagements(ctx.url, ctx.token, dateStr, function(result) {
            if (!result.ok) {
                callback("")
                return
            }
            memo.engagements[ekey] = { at: nowOf(ctx), list: result.data }
            callback(pick(result.data))
        })
        return
    }
    tracker.fetchEngagementStatus(ctx.url, ctx.token, projectId, dateStr, function(result) {
        callback(result.ok && result.data && result.data.active ? (result.data.rulesetName || "") : "")
    })
}

function emptyLoad(mode, fields) {
    return {
        mode: mode,
        fields: fields || FilmDays.entryDefaults(),
        server: null,
        defaultBreakMinutes: -1,
        effectiveCategory: "",
        rulesetName: "",
        summary: null,
        pending: false,
        error: null
    }
}

/**
 * Load the extras of (projectId, dateStr). callback(result):
 *   { mode, fields, server, defaultBreakMinutes, effectiveCategory,
 *     rulesetName, summary, pending, error }
 * `server` is the film-day JSON the next save diffs against.
 */
function loadDay(ctx, projectId, dateStr, callback) {
    var localEntry = FilmDays.get(ctx.localMap, projectId, dateStr, ctx.profileKey)
    if (ctx.mode === Mode.LOCAL) {
        callback(emptyLoad(Mode.LOCAL, localEntry))
        return
    }
    if (ctx.mode === Mode.NO_PERMISSION) {
        callback(emptyLoad(Mode.NO_PERMISSION, null))
        return
    }
    if (!hasId(projectId)) {
        callback(emptyLoad(ctx.mode === Mode.OFFLINE ? Mode.OFFLINE : Mode.NO_PROJECT, null))
        return
    }
    var memo = memoOf(ctx)
    var dkey = pendingKey(ctx.profileKey, projectId, dateStr)
    var queued = (ctx.pendingMap || {})[dkey]

    function fromServer(json, mode, error) {
        var r = emptyLoad(mode, FilmDays.fromApi(json, localEntry))
        r.server = json
        r.error = error || null
        r.defaultBreakMinutes = (json && typeof json.defaultBreakMinutes === "number") ? json.defaultBreakMinutes : -1
        r.effectiveCategory = (json && json.effectiveCategory) ? String(json.effectiveCategory) : ""
        if (queued && queued.patch) {
            r.fields = applyPatchToFields(r.fields, queued.patch)
            r.pending = true
        }
        return r
    }

    KimaiApi.fetchFilmDay(ctx.url, ctx.token, projectId, dateStr, function(result) {
        if (!result.ok) {
            var err = result.error || {}
            if (err.status === 404 && !err.code && ctx.mode === Mode.OFFLINE) {
                // Plugin state unknown and a plain Kimai 404: plugin missing or
                // an old plugin without error codes, cannot tell. Stay careful.
                callback(emptyLoad(Mode.OFFLINE, null))
                return
            }
            if (err.status === 404) {
                callback(emptyLoad(Mode.NO_ENGAGEMENT, null))
                return
            }
            if (err.status === 403) {
                callback(emptyLoad(Mode.NO_PERMISSION, null))
                return
            }
            var seen = memo.days[dkey]
            var r = seen ? fromServer(seen, Mode.OFFLINE, err) : emptyLoad(Mode.OFFLINE, null)
            r.error = err
            if (!seen && queued && queued.patch) {
                r.fields = applyPatchToFields(r.fields, queued.patch)
                r.pending = true
            }
            callback(r)
            return
        }
        var json = result.data || {}
        memo.days[dkey] = json
        var out = fromServer(json, Mode.SERVER, null)
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
 * Two-step save: Kimai timesheet (create or patch), then the extras.
 *   req = { projectId, dateStr, timesheetFields, existingId, fields, server }
 * callback(result):
 *   { ok, stage: "timesheet"|"extras", extras, error, timesheet,
 *     localMap (new map to persist, or null), pendingMap (or null), server }
 * extras: "local" | "saved" | "unchanged" | "queued" | "rejected" | "skipped"
 * ok is false only when the timesheet write failed (nothing was saved).
 */
function saveDay(ctx, req, callback) {
    var tracker = trackerOf(ctx)
    function afterTimesheet(tsResult) {
        if (!tsResult.ok) {
            callback({ ok: false, stage: "timesheet", extras: "skipped", error: tsResult.error,
                       timesheet: null, localMap: null, pendingMap: null, server: null })
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
        var r = { stage: "extras", extras: extras, error: null, localMap: null, pendingMap: null, server: null }
        for (var k in (extra || {})) {
            r[k] = extra[k]
        }
        return r
    }
    if (ctx.mode === Mode.LOCAL) {
        callback(result("local", {
            localMap: FilmDays.set(ctx.localMap, req.projectId, req.dateStr, stripMeta(req.fields), ctx.profileKey)
        }))
        return
    }
    if (!hasId(req.projectId) || (ctx.mode !== Mode.SERVER && ctx.mode !== Mode.OFFLINE)) {
        callback(result("skipped"))
        return
    }
    var dkey = pendingKey(ctx.profileKey, req.projectId, req.dateStr)
    var base = req.server || null
    if (!base && ctx.mode === Mode.OFFLINE) {
        // Never seen this day on the server: nothing to diff a queued patch against.
        callback(result("skipped"))
        return
    }
    var patch = FilmDays.toApiPatch(req.fields, base)
    // A local-only extra pay for plugins without the extraPay feature.
    var localMap = null
    if (base && !Object.prototype.hasOwnProperty.call(base, "extraPayCents")) {
        localMap = FilmDays.set(ctx.localMap, req.projectId, req.dateStr, stripMeta(req.fields), ctx.profileKey)
    }
    var pendingWithout = copyMap(ctx.pendingMap)
    var hadPending = Object.prototype.hasOwnProperty.call(pendingWithout, dkey)
    delete pendingWithout[dkey]
    if (FilmDays.isEmptyPatch(patch)) {
        callback(result("unchanged", { localMap: localMap, pendingMap: hadPending ? pendingWithout : null, server: base }))
        return
    }
    function queue(error) {
        var next = copyMap(pendingWithout)
        next[dkey] = {
            patch: patch,
            base: FilmDays.baseForPatch(base, patch),
            queuedAt: new Date(nowOf(ctx)).toISOString()
        }
        callback(result("queued", { error: error || null, localMap: localMap, pendingMap: next }))
    }
    if (ctx.mode === Mode.OFFLINE) {
        queue(null)
        return
    }
    KimaiApi.putFilmDay(ctx.url, ctx.token, req.projectId, req.dateStr, patch, function(put) {
        if (put.ok) {
            memoOf(ctx).days[dkey] = put.data
            callback(result("saved", { localMap: localMap, pendingMap: hadPending ? pendingWithout : null, server: put.data }))
            return
        }
        if (isTransientError(put.error)) {
            queue(put.error)
            return
        }
        // 400 (field error), 403, 404: the patch would never be accepted; do not queue.
        callback(result("rejected", { error: put.error, localMap: localMap, pendingMap: hadPending ? pendingWithout : null }))
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

/** Local entry without bookkeeping keys the view does not own. */
function stripMeta(fields) {
    var out = {}
    var defaults = FilmDays.entryDefaults()
    for (var k in defaults) {
        out[k] = (fields && Object.prototype.hasOwnProperty.call(fields, k)) ? fields[k] : defaults[k]
    }
    return out
}

function pendingKeysForProfile(pendingMap, profKey) {
    var prefix = String(profKey) + "|"
    var keys = []
    for (var k in (pendingMap || {})) {
        if (k.indexOf(prefix) === 0) {
            keys.push(k)
        }
    }
    keys.sort()
    return keys
}

function countPending(pendingMap, profKey) {
    return pendingKeysForProfile(pendingMap, profKey).length
}

/**
 * Retry queued film-day patches of this profile, one by one. A patch is only
 * sent when the server still holds the values it was made against; if
 * someone changed the day meanwhile, the server wins and the patch is
 * dropped. Stops at the first transient failure (still offline).
 * callback({ pendingMap (null if unchanged), sent, dropped, rejected, kept })
 */
function flushPending(ctx, callback) {
    var keys = pendingKeysForProfile(ctx.pendingMap, ctx.profileKey)
    var next = copyMap(ctx.pendingMap)
    var report = { pendingMap: null, sent: 0, dropped: 0, rejected: 0, kept: 0 }
    var prefixLen = String(ctx.profileKey).length + 1
    var changed = false
    var i = 0
    function finish() {
        report.kept = pendingKeysForProfile(next, ctx.profileKey).length
        report.pendingMap = changed ? next : null
        callback(report)
    }
    function step() {
        if (i >= keys.length) {
            finish()
            return
        }
        var key = keys[i++]
        var rest = key.substring(prefixLen)
        var cut = rest.lastIndexOf("|")
        var projectId = rest.substring(0, cut)
        var dateStr = rest.substring(cut + 1)
        var item = next[key] || {}
        KimaiApi.fetchFilmDay(ctx.url, ctx.token, projectId, dateStr, function(got) {
            if (!got.ok) {
                if (isTransientError(got.error)) {
                    finish()
                    return
                }
                delete next[key]
                changed = true
                report.rejected += 1
                step()
                return
            }
            if (!FilmDays.serverMatchesBase(got.data, item.base)) {
                memoOf(ctx).days[key] = got.data
                delete next[key]
                changed = true
                report.dropped += 1
                step()
                return
            }
            KimaiApi.putFilmDay(ctx.url, ctx.token, projectId, dateStr, item.patch || {}, function(put) {
                if (!put.ok && isTransientError(put.error)) {
                    finish()
                    return
                }
                delete next[key]
                changed = true
                if (put.ok) {
                    memoOf(ctx).days[key] = put.data
                    report.sent += 1
                } else {
                    report.rejected += 1
                }
                step()
            })
        })
    }
    step()
}

/**
 * Local film days of this profile's projects not yet migrated (P6 planner).
 * projectIds: ids from the active profile's project catalog.
 */
function migrationCandidates(ctx, projectIds) {
    return FilmDays.planMigration(ctx.localMap, projectIds, ctx.profileKey)
}

/**
 * Copy local film days to the server, one by one (resumable, idempotent):
 *   server empty → PUT the local values          result "pushed"
 *   server equal                                  result "same"
 *   server differs → server wins, local kept     result "conflict"
 *   no engagement (404)                           result "noEngagement"
 *   PUT rejected (400)                            result "rejected"
 * Local entries are never deleted; each gets migrated[profileKey].
 * Stops on a transient error or 403 (report.stopped) — run again later.
 * callback({ localMap, pushed, same, conflicts: [{key, date, projectId}],
 *            noEngagement, rejected, stopped, error })
 */
function migrate(ctx, candidates, callback, progress) {
    var map = ctx.localMap
    var report = { localMap: null, pushed: 0, same: 0, conflicts: [], noEngagement: 0, rejected: 0, stopped: false, error: null }
    var i = 0
    function mark(c, res) {
        map = FilmDays.markMigrated(map, c.key, ctx.profileKey, res, new Date(nowOf(ctx)).toISOString())
    }
    function finish() {
        report.localMap = map
        callback(report)
    }
    function step() {
        if (typeof progress === "function") {
            progress(i, candidates.length)
        }
        if (i >= candidates.length) {
            finish()
            return
        }
        var c = candidates[i++]
        KimaiApi.fetchFilmDay(ctx.url, ctx.token, c.projectId, c.date, function(got) {
            if (!got.ok) {
                var st = got.error ? got.error.status : 0
                if (st === 404) {
                    report.noEngagement += 1
                    mark(c, "noEngagement")
                    step()
                    return
                }
                report.stopped = true
                report.error = got.error
                finish()
                return
            }
            var decision = FilmDays.migrationDecision(c.entry, got.data)
            if (decision.action === "same") {
                report.same += 1
                mark(c, "same")
                step()
                return
            }
            if (decision.action === "conflict") {
                report.conflicts.push({ key: c.key, date: c.date, projectId: c.projectId })
                mark(c, "conflict")
                step()
                return
            }
            KimaiApi.putFilmDay(ctx.url, ctx.token, c.projectId, c.date, decision.patch, function(put) {
                if (put.ok) {
                    report.pushed += 1
                    mark(c, "pushed")
                } else if (isTransientError(put.error) || put.error.status === 403) {
                    report.stopped = true
                    report.error = put.error
                    finish()
                    return
                } else {
                    report.rejected += 1
                    mark(c, "rejected")
                }
                step()
            })
        })
    }
    step()
}

// ── Conflict review (P6) ─────────────────────────────────────────────────

/** Open migration conflicts of this profile (FilmDays.conflictsForProfile). */
function conflictCandidates(ctx) {
    return FilmDays.conflictsForProfile(ctx.localMap, ctx.profileKey)
}

function countConflicts(ctx) {
    return conflictCandidates(ctx).length
}

/**
 * Load the server side of each conflict, one by one:
 *   [{ key, projectId, date, entry, server, diff, state, error }]
 * state: "ready" (values differ), "same" (the server meanwhile holds the
 * local values — nothing to decide), "noEngagement" (404), "error".
 * `same` ones are marked resolved in the returned localMap (null when
 * nothing changed). callback({ items, localMap }).
 */
function loadConflicts(ctx, conflicts, callback) {
    var items = []
    var map = ctx.localMap
    var changed = false
    var i = 0
    function step() {
        if (i >= (conflicts || []).length) {
            callback({ items: items, localMap: changed ? map : null })
            return
        }
        var c = conflicts[i++]
        KimaiApi.fetchFilmDay(ctx.url, ctx.token, c.projectId, c.date, function(got) {
            var item = { key: c.key, projectId: c.projectId, date: c.date, entry: c.entry,
                         server: null, diff: [], state: "error", error: null }
            if (!got.ok) {
                item.error = got.error
                item.state = got.error && got.error.status === 404 ? "noEngagement" : "error"
            } else {
                item.server = got.data
                item.diff = FilmDays.diffFields(c.entry, got.data)
                if (item.diff.length === 0) {
                    item.state = "same"
                    map = FilmDays.markMigrated(map, c.key, ctx.profileKey, "same", new Date(nowOf(ctx)).toISOString())
                    changed = true
                } else {
                    item.state = "ready"
                }
            }
            items.push(item)
            step()
        })
    }
    step()
}

/**
 * Decide one conflict. useLocal false: keep the server values (no request).
 * useLocal true: fetch the day again and PUT the local values where they
 * still differ (the user chose them over whatever the server holds now).
 * callback({ ok, localMap, server, error }); localMap is null when nothing
 * was recorded (failure).
 */
function resolveConflict(ctx, item, useLocal, callback) {
    function mark(result) {
        return FilmDays.markMigrated(ctx.localMap, item.key, ctx.profileKey, result, new Date(nowOf(ctx)).toISOString())
    }
    if (!useLocal) {
        callback({ ok: true, localMap: mark(FilmDays.ConflictResult.SERVER), server: item.server || null, error: null })
        return
    }
    KimaiApi.fetchFilmDay(ctx.url, ctx.token, item.projectId, item.date, function(got) {
        if (!got.ok) {
            callback({ ok: false, localMap: null, server: null, error: got.error })
            return
        }
        var patch = FilmDays.toApiPatch(item.entry, got.data)
        if (FilmDays.isEmptyPatch(patch)) {
            callback({ ok: true, localMap: mark(FilmDays.ConflictResult.LOCAL), server: got.data, error: null })
            return
        }
        KimaiApi.putFilmDay(ctx.url, ctx.token, item.projectId, item.date, patch, function(put) {
            if (!put.ok) {
                callback({ ok: false, localMap: null, server: null, error: put.error })
                return
            }
            memoOf(ctx).days[pendingKey(ctx.profileKey, item.projectId, item.date)] = put.data
            callback({ ok: true, localMap: mark(FilmDays.ConflictResult.LOCAL), server: put.data, error: null })
        })
    })
}
