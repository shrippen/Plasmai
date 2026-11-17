.pragma library
.import "./providerUtil.js" as ProviderUtil
.import "./dateTimeFormat.js" as DTF
.import "./offlineState.js" as OfflineState
.import "./localFile.js" as LocalFile

/**
 * The outbox of the offline layer: changes made offline wait here, on disk, in
 * order, and are sent again by replay. Replay stops at the first failure;
 * a refusal leaves the op "failed", a change on the server since the entry was
 * loaded makes it a "conflict". The user acts on those with retry, overwrite
 * and discard. Nothing is dropped silently. What the waiting ops do to the
 * views is in offlineState.js (overlay).
 */

var LOCAL_PREFIX = "local:"
/** A lost create answer: a server entry this close to the local begin is the same one. */
var DUPLICATE_WINDOW_MS = 3 * 60 * 1000
/** Fields compared for conflicts (what Plasmai edits). */
var CHECKED_FIELDS = ["begin", "end", "description", "project", "activity"]

function isLocalId(id) {
    return String(id).indexOf(LOCAL_PREFIX) === 0
}

function isNetworkError(result) {
    return !!(result && !result.ok && result.error && result.error.type === ProviderUtil.ErrorType.Network)
}

function outboxName(s) {
    return "offline-outbox-" + s.host.key
}

function newLocalId(s) {
    s.counter += 1
    return LOCAL_PREFIX + OfflineState.nowOf(s).toString(36) + "-" + s.counter
}

/**
 * Writes the whole outbox, also for a closed session (the file has this one session only,
 * and a change that comes after the profile was left must not wait for its reopen).
 * Not while the file is being read or could not be read (it holds ops this run
 * does not know): the write waits for the read (saveWaits). A failed write sets
 * storageError, the next write carries everything again and a good one clears it.
 */
function saveOutbox(s) {
    if (s.outboxBlocked || s.loadingOutbox) {
        s.saveWaits = true
        return
    }
    s.saveWaits = false
    var written = s.host.save(outboxName(s), { v: OfflineState.SNAPSHOT_VERSION, counter: s.counter, ops: s.ops })
    Promise.resolve(written).then(function() {
        setStorageError(s, OfflineState.StorageError.NONE, OfflineState.StorageError.SAVE)
    }, function(err) {
        console.warn("Plasmai: could not save", outboxName(s), err)
        setStorageError(s, OfflineState.StorageError.SAVE)
    })
}

/** Sets the error; with `only` it replaces just that one (a good write clears a failed write only). */
function setStorageError(s, error, only) {
    if (s.storageError === error || (only !== undefined && s.storageError !== only)) {
        return
    }
    s.storageError = error
    OfflineState.notify(s)
}

// -- Offline flag ---------------------------------------------------------------

function setOffline(s, offline) {
    if (s.offline === offline) {
        return
    }
    s.offline = offline
    OfflineState.notify(s)
}

/**
 * Every answer tells whether the server is there (a refusal too); a good one
 * also starts a replay unless the caller does that itself.
 */
function observe(s, result, noReplay) {
    // The outbox file could not be read: any answer is a reason to try again.
    if (s.outboxBlocked) {
        loadOutbox(s)
    }
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

// -- Queue ----------------------------------------------------------------------

function hasPending(s) {
    return s.ops.some(function(op) { return op.state === OfflineState.State.PENDING })
}

function enqueue(s, op) {
    op.opId = newLocalId(s)
    op.createdAt = OfflineState.nowOf(s)
    op.attempts = 0
    op.state = OfflineState.State.PENDING
    op.error = null
    s.ops.push(op)
    saveOutbox(s)
    OfflineState.notify(s)
    return op
}

/** A waiting create of entryId, which later changes can simply update. */
function pendingCreate(s, entryId) {
    for (var i = 0; i < s.ops.length; i++) {
        if (s.ops[i].kind === OfflineState.Op.CREATE && String(s.ops[i].entryId) === String(entryId)) {
            return s.ops[i]
        }
    }
    return null
}

function pendingTripCreate(s, tripId) {
    var ops = OfflineState.tripOps(s, tripId).filter(function(op) { return op.kind === OfflineState.Op.TRIP_CREATE })
    return ops.length ? ops[0] : null
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

// -- Replay ---------------------------------------------------------------------

function rewriteId(s, localId, serverId) {
    for (var i = 0; i < s.ops.length; i++) {
        var op = s.ops[i]
        if (String(op.entryId) === String(localId)) {
            op.entryId = serverId
        }
        if (String(op.tripId) === String(localId)) {
            op.tripId = serverId
        }
        // A trip linked to an entry made offline.
        if (op.body && String(op.body.timesheet) === String(localId)) {
            op.body.timesheet = serverId
        }
    }
    // A closed session's ids belong to a profile that is no longer the active one.
    if (s.host.idChanged && !s.closed) {
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
        op.state = OfflineState.State.FAILED
        op.error = result.error || null
    }
    return false
}

/** The connection a replay started with. */
function connectionOf(s) {
    return { url: s.host.url(), token: s.host.token() }
}

/** The session was closed, or another profile, URL or token is active now. */
function moved(s, conn) {
    return !!s.closed || s.host.url() !== conn.url || s.host.token() !== conn.token
}

function runCreate(s, op, conn, done) {
    var inner = s.inner
    function create() {
        inner.createTimesheet(conn.url, conn.token, op.fields, function(result) {
            if (result.ok && result.data) {
                rewriteId(s, op.entryId, result.data.id)
                OfflineState.rememberEntries(s, [result.data])
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
    inner.fetchTimesheetsRange(conn.url, conn.token, new Date(begin - DUPLICATE_WINDOW_MS),
                               new Date(begin + DUPLICATE_WINDOW_MS), function(found) {
        if (moved(s, conn)) {
            done(null)
            return
        }
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
        OfflineState.rememberEntries(s, [same[0]])
        // Fields changed offline after the lost create still have to go out.
        var rest = {}
        for (var k in op.fields) {
            if (k !== "begin") {
                rest[k] = op.fields[k]
            }
        }
        inner.patchTimesheet(conn.url, conn.token, same[0].id, rest, done)
    })
}

/** Reads the entry first: changed on the server since it was loaded → conflict. */
function checked(s, op, conn, run, done) {
    if (!op.base || isLocalId(op.entryId)) {
        run()
        return
    }
    s.inner.fetchTimesheet(conn.url, conn.token, op.entryId, function(found) {
        if (moved(s, conn)) {
            done(null)
            return
        }
        if (!found.ok) {
            if (op.kind === OfflineState.Op.DELETE && found.error && found.error.status === 404) {
                done({ ok: true })
                return
            }
            done(found)
            return
        }
        var changed = changedOnServer(op.base, found.data)
        if (changed.length) {
            op.state = OfflineState.State.CONFLICT
            op.server = found.data
            op.error = { type: ProviderUtil.ErrorType.Conflict, status: 409, detail: changed.join(", ") }
            done(null)
            return
        }
        run()
    })
}

function runOp(s, op, conn, done) {
    var url = conn.url
    var token = conn.token
    if (op.kind === OfflineState.Op.CREATE) {
        runCreate(s, op, conn, done)
        return
    }
    if (op.kind === OfflineState.Op.PATCH) {
        checked(s, op, conn, function() {
            s.inner.patchTimesheet(url, token, op.entryId, op.fields, function(result) {
                if (result.ok && result.data) {
                    OfflineState.rememberEntries(s, [result.data])
                }
                done(result)
            })
        }, done)
        return
    }
    if (op.kind === OfflineState.Op.DELETE) {
        checked(s, op, conn, function() {
            s.inner.deleteTimesheet(url, token, op.entryId, function(result) {
                if (result.ok) {
                    delete s.snapshot.entries[String(op.entryId)]
                }
                done(result.ok || (result.error && result.error.status === 404) ? { ok: true } : result)
            })
        }, done)
        return
    }
    if (op.kind === OfflineState.Op.FILM_DAY) {
        s.inner.putFilmDay(url, token, op.projectId, op.dateStr, op.patch, done)
        return
    }
    if (op.kind === OfflineState.Op.TRIP_CREATE) {
        s.inner.createTrip(url, token, op.body, function(result) {
            if (result.ok && result.data) {
                rewriteId(s, op.tripId, result.data.id)
            }
            done(result)
        })
        return
    }
    if (op.kind === OfflineState.Op.TRIP_PATCH) {
        s.inner.patchTrip(url, token, op.tripId, op.body, done)
        return
    }
    if (op.kind === OfflineState.Op.TRIP_DELETE) {
        s.inner.deleteTrip(url, token, op.tripId, function(result) {
            done(result.ok || (result.error && result.error.status === 404) ? { ok: true } : result)
        })
        return
    }
    done({ ok: false, error: { type: ProviderUtil.ErrorType.Unknown, status: 0, detail: "unknown op " + op.kind } })
}

/**
 * Sends the outbox in order; callback(sent) when it stops (empty, offline, a failed op,
 * or the connection or session changed: the rest waits for the next replay).
 * URL and token are taken once, so no op goes to another server than the one it was started for.
 */
function replay(s, callback) {
    if (s.replaying) {
        if (callback) {
            s.replayWaiters.push(callback)
        }
        return
    }
    s.replaying = true
    var conn = connectionOf(s)
    var sent = 0
    function stop() {
        s.replaying = false
        saveOutbox(s)
        OfflineState.saveSnapshot(s)
        OfflineState.notify(s)
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
        if (!op || op.state !== OfflineState.State.PENDING || moved(s, conn)) {
            stop()
            return
        }
        runOp(s, op, conn, function(result) {
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

// -- Loading and what the user does with ops ------------------------------------

/** Outboxes saved before the error kinds moved into ErrorType stored "config" for missing access. */
var LEGACY_NOT_CONFIGURED = "config"

function migratedOps(ops) {
    return ops.map(function(op) {
        if (op.error && op.error.type === LEGACY_NOT_CONFIGURED) {
            op.error.type = ProviderUtil.ErrorType.NotConfigured
        }
        return op
    })
}

/** Takes the saved outbox; ops queued before that stay behind the loaded ones. */
function restoreOps(s, outbox) {
    s.counter = Math.max(s.counter, outbox.counter || 0)
    s.ops = migratedOps(outbox.ops || []).concat(s.ops)
}

/** Reads the outbox file again while it is blocked; resolves when this try is done. */
function loadOutbox(s) {
    if (s.loadingOutbox) {
        return s.loadingOutbox
    }
    s.loadingOutbox = s.host.load(outboxName(s)).then(function(file) {
        s.loadingOutbox = null
        applyLoaded(s, file)
        // Ops made while the file was read or could not be read: written behind the loaded ones.
        if (s.saveWaits && !s.outboxBlocked) {
            s.saveWaits = false
            saveOutbox(s)
        }
        OfflineState.notify(s)
    })
    return s.loadingOutbox
}

/** What a read of the outbox file means for the queue (statuses: localFile.js). */
function applyLoaded(s, file) {
    var Status = LocalFile.Status
    var StorageError = OfflineState.StorageError
    if (file.status === Status.BROKEN) {
        // Set aside by the platform: nothing to lose by writing a new one.
        s.outboxBlocked = false
        s.storageError = StorageError.BROKEN
        return
    }
    var unusable = file.status === Status.UNREADABLE
        || (file.status === Status.OK && (!file.data || file.data.v !== OfflineState.SNAPSHOT_VERSION))
    if (unusable) {
        s.outboxBlocked = true
        s.storageError = StorageError.LOAD
        return
    }
    if (file.status === Status.OK) {
        restoreOps(s, file.data)
    }
    s.outboxBlocked = false
    if (s.storageError === StorageError.LOAD) {
        s.storageError = StorageError.NONE
    }
}

/** Ops in order, for the "Unsynced" list. */
function ops(s) {
    return OfflineState.copy(s.ops)
}

function pendingCount(s) {
    return s.ops.length
}

/** True when entryId was made offline or has changes waiting. */
function isUnsynced(s, entryId) {
    return isLocalId(entryId) || OfflineState.opsFor(s, entryId).length > 0
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
        op.state = OfflineState.State.PENDING
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

/** Drops an op; dropping a create drops what waits on its entry (or trip) too. */
function discard(s, opId) {
    var op = findOp(s, opId)
    if (!op) {
        return
    }
    if (op.kind === OfflineState.Op.CREATE && isLocalId(op.entryId)) {
        s.ops = s.ops.filter(function(o) { return String(o.entryId) !== String(op.entryId) })
        // Trips of that entry stay, without the link to an entry that will never exist.
        for (var i = 0; i < s.ops.length; i++) {
            if (s.ops[i].body && String(s.ops[i].body.timesheet) === String(op.entryId)) {
                s.ops[i].body.timesheet = null
            }
        }
    } else if (op.kind === OfflineState.Op.TRIP_CREATE && isLocalId(op.tripId)) {
        s.ops = s.ops.filter(function(o) { return String(o.tripId) !== String(op.tripId) })
    } else {
        removeOp(s, op)
    }
    saveOutbox(s)
    OfflineState.notify(s)
}
