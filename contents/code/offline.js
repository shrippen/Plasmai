.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./dateTimeFormat.js" as DTF

/**
 * Offline layer (ROADMAP pillar 6), Kimai only. A session wraps the tracker:
 * pages keep their calls, the session answers them when the network is gone.
 *
 *   read  ──► server ──ok──► snapshot (on disk) ──► answer (+ pending ops laid over)
 *               └─network error──► answer from the snapshot
 *
 *   write ──► offline or ops waiting? ──no──► server ──network error──┐
 *               │yes                                                 ▼
 *               └──────────────────────────────► outbox (on disk) ──► local answer
 *
 *   replay: after every good answer, strictly in order, stops at the first
 *   failure. Network error → later. Server refuses → the op waits as
 *   "failed" (retry / discard). Entry changed on the server since it was
 *   loaded → "conflict" (overwrite / discard). Nothing is dropped silently.
 *
 * Offline-capable: start, stop, add entry, edit and delete an entry, restart
 * (continue), film day extras. Everything else (master data, split, merge)
 * answers { type: "offline" } while offline; the views disable it.
 *
 * State lives in the session object, never in module globals: widgets in one
 * plasmashell share this library.
 *
 * host: {
 *   key        profile key; "" = no offline layer (not Kimai), the tracker is passed through
 *   url(), token()
 *   load(name) → Promise<object|null>, save(name, object) → Promise   (client-private files)
 *   now()      ms, optional
 *   changed()  offline flag, ops or snapshot changed (views re-read), optional
 *   idChanged(localId, serverId)   a local entry got its server id, optional
 * }
 */

var LOCAL_PREFIX = "local:"
var OFFLINE = "offline"

var Op = {
    CREATE: "create",
    PATCH: "patch",
    DELETE: "delete",
    FILM_DAY: "filmDay"
}

var State = {
    PENDING: "pending",
    FAILED: "failed",
    CONFLICT: "conflict"
}

/** Entries kept in the snapshot (stats, week totals, film days of the last month). */
var KEEP_DAYS = 45
var DAY_MS = 24 * 3600 * 1000
/** A lost create answer: a server entry this close to the local begin is the same one. */
var DUPLICATE_WINDOW_MS = 3 * 60 * 1000
/** Fields compared for conflicts (what Plasmai edits). */
var CHECKED_FIELDS = ["begin", "end", "description", "project", "activity"]
var SNAPSHOT_VERSION = 1

/** Reads answered from the snapshot by their call (catalogs, user). */
var CACHED_READS = ["loadProjects", "loadCustomers", "loadAllActivities", "loadActivities",
                    "fetchCurrentUser", "testConnection"]

function isLocalId(id) {
    return String(id).indexOf(LOCAL_PREFIX) === 0
}

function isNetworkError(result) {
    return !!(result && !result.ok && result.error && result.error.type === KimaiApi.ErrorType.Network)
}

function offlineFail() {
    return { ok: false, error: { type: OFFLINE, status: 0, detail: "" } }
}

function copy(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value))
}

function nowOf(s) {
    return s.host.now ? s.host.now() : Date.now()
}

function notify(s) {
    if (s.host.changed) {
        s.host.changed()
    }
}

function stateName(s) {
    return "offline-state-" + s.host.key
}

function outboxName(s) {
    return "offline-outbox-" + s.host.key
}

function newLocalId(s) {
    s.counter += 1
    return LOCAL_PREFIX + nowOf(s).toString(36) + "-" + s.counter
}

// -- Snapshot ------------------------------------------------------------------

function emptySnapshot() {
    return { v: SNAPSHOT_VERSION, savedAt: 0, entries: {}, activeId: null, recentIds: [], reads: {}, filmDays: {} }
}

function entryEndMs(ts, nowMs) {
    return ts.end ? DTF.stampMs(ts.end) : nowMs
}

function rememberEntries(s, list) {
    for (var i = 0; i < (list || []).length; i++) {
        var ts = list[i]
        if (ts && ts.id !== undefined && ts.id !== null) {
            s.snapshot.entries[String(ts.id)] = ts
        }
    }
}

function pruneEntries(s) {
    var limit = nowOf(s) - KEEP_DAYS * DAY_MS
    var keep = {}
    keep[String(s.snapshot.activeId)] = true
    for (var i = 0; i < s.snapshot.recentIds.length; i++) {
        keep[String(s.snapshot.recentIds[i])] = true
    }
    for (var id in s.snapshot.entries) {
        var ts = s.snapshot.entries[id]
        if (!keep[id] && entryEndMs(ts, nowOf(s)) < limit) {
            delete s.snapshot.entries[id]
        }
    }
}

function saveSnapshot(s) {
    s.snapshot.savedAt = nowOf(s)
    pruneEntries(s)
    var text = JSON.stringify(s.snapshot)
    if (text === s.savedSnapshotText) {
        return
    }
    s.savedSnapshotText = text
    s.host.save(stateName(s), s.snapshot)
}

function saveOutbox(s) {
    s.host.save(outboxName(s), { v: SNAPSHOT_VERSION, counter: s.counter, ops: s.ops })
}

// -- Overlay: the snapshot or a server answer plus what waits in the outbox ----

function opsFor(s, entryId) {
    return s.ops.filter(function(op) { return op.entryId !== undefined && String(op.entryId) === String(entryId) })
}

function applyFields(ts, fields) {
    var out = copy(ts)
    for (var k in fields) {
        out[k] = fields[k]
    }
    // Views show Kimai's duration (seconds); keep it in step with begin and end.
    if (out.begin && out.end) {
        out.duration = Math.max(0, Math.round((DTF.stampMs(out.end) - DTF.stampMs(out.begin)) / 1000))
    }
    return out
}

/** ts with its waiting patches, or null when a delete waits for it. */
function overlayEntry(s, ts) {
    var out = ts
    var ops = opsFor(s, ts.id)
    for (var i = 0; i < ops.length; i++) {
        if (ops[i].kind === Op.DELETE) {
            return null
        }
        if (ops[i].kind === Op.PATCH) {
            out = applyFields(out, ops[i].fields)
        }
    }
    return out
}

/** Entries created offline, as timesheets (with their later patches). */
function localEntries(s) {
    var out = []
    for (var i = 0; i < s.ops.length; i++) {
        var op = s.ops[i]
        if (op.kind === Op.CREATE) {
            var ts = overlayEntry(s, applyFields({ id: op.entryId }, op.fields))
            if (ts) {
                out.push(ts)
            }
        }
    }
    return out
}

function overlayList(s, list) {
    var out = []
    for (var i = 0; i < (list || []).length; i++) {
        var ts = overlayEntry(s, list[i])
        if (ts) {
            out.push(ts)
        }
    }
    return out
}

function byBeginDesc(a, b) {
    return DTF.stampMs(b.begin) - DTF.stampMs(a.begin)
}

function overlayActive(s, serverList) {
    var running = overlayList(s, serverList).filter(function(ts) { return !ts.end })
    var local = localEntries(s).filter(function(ts) { return !ts.end })
    return local.concat(running).sort(byBeginDesc).slice(0, 1)
}

function overlayRecent(s, serverList, size) {
    var list = localEntries(s).concat(overlayList(s, serverList))
    return list.sort(byBeginDesc).slice(0, size || list.length)
}

function overlaps(ts, beginMs, endMs, nowMs) {
    return DTF.stampMs(ts.begin) <= endMs && entryEndMs(ts, nowMs) >= beginMs
}

function overlayRange(s, serverList, beginDate, endDate) {
    var b = beginDate.getTime()
    var e = endDate.getTime()
    var nowMs = nowOf(s)
    var local = localEntries(s).filter(function(ts) { return overlaps(ts, b, e, nowMs) })
    return local.concat(overlayList(s, serverList))
}

function snapshotEntries(s) {
    var out = []
    for (var id in s.snapshot.entries) {
        out.push(s.snapshot.entries[id])
    }
    return out
}

function snapshotRange(s, beginDate, endDate) {
    var b = beginDate.getTime()
    var e = endDate.getTime()
    var nowMs = nowOf(s)
    return snapshotEntries(s).filter(function(ts) { return overlaps(ts, b, e, nowMs) })
}

function snapshotRecent(s) {
    var out = []
    for (var i = 0; i < s.snapshot.recentIds.length; i++) {
        var ts = s.snapshot.entries[String(s.snapshot.recentIds[i])]
        if (ts) {
            out.push(ts)
        }
    }
    return out
}

function snapshotActive(s) {
    var ts = s.snapshot.activeId !== null ? s.snapshot.entries[String(s.snapshot.activeId)] : null
    return ts && !ts.end ? [ts] : []
}

/** The last known version of an entry (for conflict checks and restart). */
function knownEntry(s, id) {
    var local = localEntries(s).filter(function(ts) { return String(ts.id) === String(id) })
    if (local.length) {
        return local[0]
    }
    var ts = s.snapshot.entries[String(id)]
    return ts ? overlayEntry(s, ts) : null
}

// -- Offline flag ------------------------------------------------------------

function setOffline(s, offline) {
    if (s.offline === offline) {
        return
    }
    s.offline = offline
    notify(s)
}

/**
 * Every answer tells whether the server is there (a refusal too); a good one
 * also starts a replay unless the caller does that itself.
 */
function observe(s, result, noReplay) {
    if (isNetworkError(result)) {
        setOffline(s, true)
        return
    }
    if (!result) {
        return
    }
    setOffline(s, false)
    if (result.ok && !noReplay && hasPending(s) && !s.replaying) {
        replay(s)
    }
}

// -- Outbox --------------------------------------------------------------------

function hasPending(s) {
    return s.ops.some(function(op) { return op.state === State.PENDING })
}

function enqueue(s, op) {
    op.opId = newLocalId(s)
    op.createdAt = nowOf(s)
    op.attempts = 0
    op.state = State.PENDING
    op.error = null
    s.ops.push(op)
    saveOutbox(s)
    notify(s)
    return op
}

/** A waiting create of entryId, which later changes can simply update. */
function pendingCreate(s, entryId) {
    for (var i = 0; i < s.ops.length; i++) {
        if (s.ops[i].kind === Op.CREATE && String(s.ops[i].entryId) === String(entryId)) {
            return s.ops[i]
        }
    }
    return null
}

function baseOf(ts) {
    if (!ts) {
        return null
    }
    var base = {}
    for (var i = 0; i < CHECKED_FIELDS.length; i++) {
        var k = CHECKED_FIELDS[i]
        base[k] = comparable(k, ts[k])
    }
    return base
}

function comparable(field, value) {
    if (field === "project" || field === "activity") {
        return value === null || value === undefined ? null
            : String(typeof value === "object" ? value.id : value)
    }
    if (field === "begin" || field === "end") {
        return value ? DTF.stampMs(value) : null
    }
    return value === null || value === undefined ? "" : String(value)
}

/** Fields that differ between the base and the server's entry now. */
function changedOnServer(base, server) {
    var out = []
    var now = baseOf(server)
    for (var k in base) {
        if (base[k] !== now[k]) {
            out.push(k)
        }
    }
    return out
}

function localNowString(s) {
    return KimaiApi.localDateTimeString(new Date(nowOf(s)))
}

// -- Replay --------------------------------------------------------------------

function rewriteId(s, localId, serverId) {
    for (var i = 0; i < s.ops.length; i++) {
        if (String(s.ops[i].entryId) === String(localId)) {
            s.ops[i].entryId = serverId
        }
    }
    if (s.host.idChanged) {
        s.host.idChanged(localId, serverId)
    }
}

function removeOp(s, op) {
    s.ops = s.ops.filter(function(o) { return o !== op })
}

function finish(s, op, result) {
    if (result.ok) {
        removeOp(s, op)
        return true
    }
    op.attempts += 1
    observe(s, result, true)
    if (!isNetworkError(result)) {
        op.state = State.FAILED
        op.error = result.error || null
    }
    return false
}

function runCreate(s, op, done) {
    var inner = s.inner
    function create() {
        inner.createTimesheet(s.host.url(), s.host.token(), op.fields, function(result) {
            if (result.ok && result.data) {
                rewriteId(s, op.entryId, result.data.id)
                rememberEntries(s, [result.data])
            }
            done(result)
        })
    }
    if (!op.maybeSent) {
        create()
        return
    }
    // The first try may have reached the server (its answer got lost): adopt that entry.
    var begin = DTF.stampMs(op.fields.begin)
    inner.fetchTimesheetsRange(s.host.url(), s.host.token(), new Date(begin - DUPLICATE_WINDOW_MS),
                               new Date(begin + DUPLICATE_WINDOW_MS), function(found) {
        if (!found.ok) {
            done(found)
            return
        }
        var same = (found.data || []).filter(function(ts) {
            return comparable("project", ts.project) === comparable("project", op.fields.project)
                && comparable("activity", ts.activity) === comparable("activity", op.fields.activity)
        })
        if (!same.length) {
            create()
            return
        }
        rewriteId(s, op.entryId, same[0].id)
        rememberEntries(s, [same[0]])
        // Fields changed offline after the lost create still have to go out.
        var rest = {}
        for (var k in op.fields) {
            if (k !== "begin") {
                rest[k] = op.fields[k]
            }
        }
        inner.patchTimesheet(s.host.url(), s.host.token(), same[0].id, rest, done)
    })
}

/** Reads the entry first: changed on the server since it was loaded → conflict. */
function checked(s, op, run, done) {
    if (!op.base || isLocalId(op.entryId)) {
        run()
        return
    }
    s.inner.fetchTimesheet(s.host.url(), s.host.token(), op.entryId, function(found) {
        if (!found.ok) {
            if (op.kind === Op.DELETE && found.error && found.error.status === 404) {
                done({ ok: true })
                return
            }
            done(found)
            return
        }
        var changed = changedOnServer(op.base, found.data)
        if (changed.length) {
            op.state = State.CONFLICT
            op.server = found.data
            op.error = { type: "conflict", status: 409, detail: changed.join(", ") }
            done(null)
            return
        }
        run()
    })
}

function runOp(s, op, done) {
    var url = s.host.url()
    var token = s.host.token()
    if (op.kind === Op.CREATE) {
        runCreate(s, op, done)
        return
    }
    if (op.kind === Op.PATCH) {
        checked(s, op, function() {
            s.inner.patchTimesheet(url, token, op.entryId, op.fields, function(result) {
                if (result.ok && result.data) {
                    rememberEntries(s, [result.data])
                }
                done(result)
            })
        }, done)
        return
    }
    if (op.kind === Op.DELETE) {
        checked(s, op, function() {
            s.inner.deleteTimesheet(url, token, op.entryId, function(result) {
                if (result.ok) {
                    delete s.snapshot.entries[String(op.entryId)]
                }
                done(result.ok || (result.error && result.error.status === 404) ? { ok: true } : result)
            })
        }, done)
        return
    }
    if (op.kind === Op.FILM_DAY) {
        KimaiApi.putFilmDay(url, token, op.projectId, op.dateStr, op.patch, done)
        return
    }
    done({ ok: false, error: { type: "unknown", status: 0, detail: "unknown op " + op.kind } })
}

/** Sends the outbox in order; callback(sent) when it stops (empty, offline or a failed op). */
function replay(s, callback) {
    if (s.replaying) {
        if (callback) {
            s.replayWaiters.push(callback)
        }
        return
    }
    s.replaying = true
    var sent = 0
    function stop() {
        s.replaying = false
        saveOutbox(s)
        saveSnapshot(s)
        notify(s)
        var waiters = s.replayWaiters
        s.replayWaiters = []
        if (callback) {
            callback(sent)
        }
        for (var i = 0; i < waiters.length; i++) {
            waiters[i](sent)
        }
    }
    function next() {
        var op = s.ops.length ? s.ops[0] : null
        if (!op || op.state !== State.PENDING) {
            stop()
            return
        }
        runOp(s, op, function(result) {
            if (!result || !finish(s, op, result)) {
                stop()
                return
            }
            sent += 1
            saveOutbox(s)
            next()
        })
    }
    next()
}

// -- The wrapped tracker -------------------------------------------------------

/** Last argument that is a function: the callback of a tracker call. */
function callbackIndex(args) {
    for (var i = args.length - 1; i >= 0; i--) {
        if (typeof args[i] === "function") {
            return i
        }
    }
    return -1
}

function readKey(name, args, cbIndex) {
    // url and token are not part of the key; the snapshot is per profile already.
    return [name].concat(Array.prototype.slice.call(args, 2, cbIndex)).join("|")
}

/**
 * Wraps one read: server first (after the outbox went out), then snapshot.
 * answer(serverResult) → data laid over; fallback() → data from the snapshot.
 */
function wrapRead(s, name, remember, answer, fallback) {
    return function() {
        var args = Array.prototype.slice.call(arguments)
        var cbIndex = callbackIndex(args)
        var callback = args[cbIndex]
        var again = true
        function run() {
            args[cbIndex] = function(result) {
                observe(s, result, true)
                // Back online with ops waiting: send them, then read again (the answer predates them).
                if (result.ok && again && hasPending(s)) {
                    again = false
                    replay(s, run)
                    return
                }
                if (result.ok) {
                    remember(result, args)
                    saveSnapshot(s)
                    callback({ ok: true, data: answer(result.data, args), droppedFields: result.droppedFields })
                    return
                }
                if (isNetworkError(result)) {
                    var data = fallback(args)
                    if (data !== undefined) {
                        callback({ ok: true, data: data, offline: true })
                        return
                    }
                }
                callback(result)
            }
            s.inner[name].apply(s.inner, args)
        }
        if (hasPending(s) && !s.offline) {
            replay(s, run)
        } else {
            run()
        }
    }
}

function passThrough(s, name) {
    return function() {
        var args = Array.prototype.slice.call(arguments)
        var cbIndex = callbackIndex(args)
        if (cbIndex >= 0) {
            var callback = args[cbIndex]
            args[cbIndex] = function(result) {
                observe(s, result)
                callback(result)
            }
        }
        return s.inner[name].apply(s.inner, args)
    }
}

function cachedRead(s, name) {
    return wrapRead(s, name, function(result, args) {
        s.snapshot.reads[readKey(name, args, callbackIndex(args))] = result.data
    }, function(data) {
        return data
    }, function(args) {
        var hit = s.snapshot.reads[readKey(name, args, callbackIndex(args))]
        return hit === undefined ? undefined : copy(hit)
    })
}

/** Offline or ops waiting: goes to the outbox. Else the server, the outbox on a network error. */
function write(s, sendOnline, queue) {
    if (s.offline || s.ops.length) {
        queue(false)
        if (!s.offline) {
            replay(s)
        }
        return
    }
    sendOnline(function(result, callback) {
        observe(s, result)
        if (isNetworkError(result)) {
            queue(true)
            return
        }
        callback(result)
    })
}

function localAnswer(s, entryId) {
    return { ok: true, data: knownEntry(s, entryId), queued: true }
}

function queueCreate(s, fields, callback, maybeSent) {
    var id = newLocalId(s)
    enqueue(s, { kind: Op.CREATE, entryId: id, fields: fields, maybeSent: !!maybeSent })
    callback(localAnswer(s, id))
}

/** Changes of an entry: into its waiting create, or a patch with the base for the conflict check. */
function queuePatch(s, entryId, fields, callback) {
    var create = pendingCreate(s, entryId)
    if (create && create.state === State.PENDING) {
        create.fields = applyFields(create.fields, fields)
        saveOutbox(s)
        notify(s)
    } else {
        enqueue(s, { kind: Op.PATCH, entryId: entryId, fields: fields, base: baseOf(knownEntry(s, entryId)) })
    }
    callback(localAnswer(s, entryId))
}

function queueDelete(s, entryId, callback) {
    var create = pendingCreate(s, entryId)
    if (create && create.state === State.PENDING) {
        // Never sent: drop the create and everything waiting on it.
        s.ops = s.ops.filter(function(op) { return String(op.entryId) !== String(entryId) })
        saveOutbox(s)
        notify(s)
    } else {
        enqueue(s, { kind: Op.DELETE, entryId: entryId, base: baseOf(knownEntry(s, entryId)) })
    }
    callback({ ok: true, data: null, queued: true })
}

function writeFields(fields) {
    var out = {}
    for (var k in fields) {
        if (fields[k] !== undefined) {
            out[k] = fields[k]
        }
    }
    return out
}

function wrapTracker(s) {
    var inner = s.inner
    var t = {}
    for (var name in inner) {
        if (typeof inner[name] === "function") {
            t[name] = passThrough(s, name)
        } else {
            t[name] = inner[name]
        }
    }
    for (var i = 0; i < CACHED_READS.length; i++) {
        if (typeof inner[CACHED_READS[i]] === "function") {
            t[CACHED_READS[i]] = cachedRead(s, CACHED_READS[i])
        }
    }

    t.fetchActiveTimesheet = wrapRead(s, "fetchActiveTimesheet", function(result) {
        rememberEntries(s, result.data)
        s.snapshot.activeId = result.data && result.data.length ? result.data[0].id : null
    }, function(data) {
        return overlayActive(s, data)
    }, function() {
        return overlayActive(s, snapshotActive(s))
    })

    t.fetchRecentTimesheets = wrapRead(s, "fetchRecentTimesheets", function(result) {
        rememberEntries(s, result.data)
        s.snapshot.recentIds = (result.data || []).map(function(ts) { return ts.id })
    }, function(data, args) {
        return overlayRecent(s, data, args[2])
    }, function(args) {
        return overlayRecent(s, snapshotRecent(s), args[2])
    })

    t.fetchTimesheetsRange = wrapRead(s, "fetchTimesheetsRange", function(result, args) {
        // Filtered answers (one project) are incomplete for the range; keep the entries only.
        rememberEntries(s, result.data)
    }, function(data, args) {
        return overlayRange(s, data, args[2], args[3])
    }, function(args) {
        var filters = args[5]
        var list = overlayRange(s, snapshotRange(s, args[2], args[3]), args[2], args[3])
        if (filters && filters.project) {
            list = list.filter(function(ts) {
                return comparable("project", ts.project) === String(filters.project)
            })
        }
        return list
    })

    t.createTimesheet = function(url, token, fields, callback) {
        write(s, function(done) {
            inner.createTimesheet(url, token, fields, function(result) { done(result, callback) })
        }, function(maybeSent) {
            var f = writeFields(fields)
            if (!f.begin) {
                f.begin = localNowString(s)
            }
            queueCreate(s, f, callback, maybeSent)
        })
    }

    t.startTracking = function(url, token, projectId, activityId, description, callback, extras) {
        write(s, function(done) {
            inner.startTracking(url, token, projectId, activityId, description, function(result) {
                done(result, callback)
            }, extras)
        }, function(maybeSent) {
            var extra = extras || {}
            // Offline the begin is the device's time (online Kimai stamps its own "now").
            queueCreate(s, writeFields({
                begin: localNowString(s), project: projectId, activity: activityId,
                description: description || "", tags: extra.tags,
                billable: extra.billable === undefined || extra.billable === null ? undefined : !!extra.billable
            }), callback, maybeSent)
        })
    }

    t.restartTimesheet = function(url, token, timesheetId, callback) {
        write(s, function(done) {
            inner.restartTimesheet(url, token, timesheetId, function(result) { done(result, callback) })
        }, function(maybeSent) {
            var from = knownEntry(s, timesheetId)
            if (!from) {
                callback(offlineFail())
                return
            }
            queueCreate(s, writeFields({
                begin: localNowString(s), project: comparable("project", from.project),
                activity: comparable("activity", from.activity), description: from.description || "",
                tags: from.tags, billable: from.billable
            }), callback, maybeSent)
        })
    }

    t.stopTracking = function(url, token, timesheetId, callback) {
        write(s, function(done) {
            inner.stopTracking(url, token, timesheetId, function(result) { done(result, callback) })
        }, function() {
            queuePatch(s, timesheetId, { end: localNowString(s) }, function(result) {
                callback({ ok: true, data: null, queued: true })
            })
        })
    }

    t.patchTimesheet = function(url, token, timesheetId, fields, callback) {
        write(s, function(done) {
            inner.patchTimesheet(url, token, timesheetId, fields, function(result) { done(result, callback) })
        }, function() {
            queuePatch(s, timesheetId, writeFields(fields), callback)
        })
    }

    t.deleteTimesheet = function(url, token, timesheetId, callback) {
        write(s, function(done) {
            inner.deleteTimesheet(url, token, timesheetId, function(result) { done(result, callback) })
        }, function() {
            queueDelete(s, timesheetId, callback)
        })
    }

    /** Film day extras (the Drehzettel plugin), queued like the entry of the day. */
    t.putFilmDay = function(url, token, projectId, dateStr, patch, callback) {
        write(s, function(done) {
            KimaiApi.putFilmDay(url, token, projectId, dateStr, patch, function(result) { done(result, callback) })
        }, function() {
            enqueue(s, { kind: Op.FILM_DAY, projectId: projectId, dateStr: dateStr, patch: patch })
            callback({ ok: true, data: null, queued: true })
        })
    }

    // Online only: new ids others depend on.
    var onlineOnly = ["createCustomer", "createProject", "createActivity"]
    for (i = 0; i < onlineOnly.length; i++) {
        (function(name) {
            if (typeof inner[name] !== "function") {
                return
            }
            t[name] = function() {
                var args = Array.prototype.slice.call(arguments)
                var cbIndex = callbackIndex(args)
                if (s.offline) {
                    args[cbIndex](offlineFail())
                    return
                }
                passThrough(s, name).apply(null, args)
            }
        })(onlineOnly[i])
    }
    return t
}

// -- Session -------------------------------------------------------------------

/**
 * A session for one profile. Without host.key (another provider) the tracker
 * is the inner one and everything else is a no-op.
 */
function createSession(inner, host) {
    var s = {
        inner: inner,
        host: host,
        enabled: !!host.key,
        offline: false,
        ops: [],
        counter: 0,
        snapshot: emptySnapshot(),
        savedSnapshotText: "",
        replaying: false,
        replayWaiters: []
    }
    s.tracker = s.enabled ? wrapTracker(s) : inner
    return s
}

/** Loads snapshot and outbox from disk; ops queued before that stay behind the loaded ones. */
function load(s) {
    if (!s.enabled) {
        return Promise.resolve()
    }
    return Promise.all([s.host.load(stateName(s)), s.host.load(outboxName(s))]).then(function(parts) {
        var state = parts[0]
        if (state && state.v === SNAPSHOT_VERSION) {
            s.snapshot = state
            s.savedSnapshotText = JSON.stringify(state)
        }
        var outbox = parts[1]
        if (outbox && outbox.v === SNAPSHOT_VERSION) {
            s.counter = Math.max(s.counter, outbox.counter || 0)
            s.ops = (outbox.ops || []).concat(s.ops)
        }
        notify(s)
    })
}

function isOffline(s) {
    return s.enabled && s.offline
}

/** When the snapshot was last written from a server answer (ms, 0 = never). */
function stateAt(s) {
    return s.snapshot.savedAt || 0
}

/** Ops in order, for the "Unsynced" list. */
function ops(s) {
    return copy(s.ops)
}

function pendingCount(s) {
    return s.ops.length
}

/** True when entryId was made offline or has changes waiting. */
function isUnsynced(s, entryId) {
    return isLocalId(entryId) || opsFor(s, entryId).length > 0
}

function findOp(s, opId) {
    for (var i = 0; i < s.ops.length; i++) {
        if (s.ops[i].opId === opId) {
            return s.ops[i]
        }
    }
    return null
}

/** Sends a failed op again (after the cause was fixed elsewhere). */
function retry(s, opId, callback) {
    var op = findOp(s, opId)
    if (op) {
        op.state = State.PENDING
        op.error = null
        saveOutbox(s)
    }
    replay(s, callback)
}

/** Conflict: send the local change anyway (the server's version is overwritten). */
function overwrite(s, opId, callback) {
    var op = findOp(s, opId)
    if (op) {
        op.base = null
        op.server = null
    }
    retry(s, opId, callback)
}

/** Drops an op; dropping a create drops what waits on its entry too. */
function discard(s, opId) {
    var op = findOp(s, opId)
    if (!op) {
        return
    }
    if (op.kind === Op.CREATE && isLocalId(op.entryId)) {
        s.ops = s.ops.filter(function(o) { return String(o.entryId) !== String(op.entryId) })
    } else {
        removeOp(s, op)
    }
    saveOutbox(s)
    notify(s)
}

/** Film day answers kept by filmDaySync (memo.days of this profile), persisted with the snapshot. */
function rememberFilmDays(s, days) {
    if (!s.enabled) {
        return
    }
    s.snapshot.filmDays = copy(days || {})
    saveSnapshot(s)
}

function filmDays(s) {
    return copy(s.snapshot.filmDays || {})
}
