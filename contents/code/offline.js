.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./dateTimeFormat.js" as DTF
.import "./providerUtil.js" as ProviderUtil
.import "./offlineState.js" as OfflineState
.import "./offlineOutbox.js" as Outbox

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
 * (continue), film day extras, trips (add, edit, delete; a trip of an entry
 * made offline gets the entry's server id). Everything else (master data,
 * split, merge, trip suggestions) answers { type: "offline" } while offline;
 * the views disable it.
 *
 * State lives in the session object, never in module globals: widgets in one
 * plasmashell share this library.
 *
 * host: {
 *   key        profile key; "" = no offline layer (not Kimai), the tracker is passed through
 *   url(), token()
 *   load(name) → Promise<{ status, data }> (localFile.js; data with OK only)
 *   save(name, object) → Promise, rejects when the write failed   (client-private files)
 *   now()      ms, optional
 *   changed()  offline flag, ops or snapshot changed (views re-read), optional
 *   idChanged(localId, serverId)   a local entry got its server id, optional
 * }
 */

/** Reads answered from the snapshot by their call (catalogs, user). */
var CACHED_READS = ["loadProjects", "loadCustomers", "loadAllActivities", "loadActivities",
                    "fetchCurrentUser", "testConnection", "fetchMileageMeta", "fetchVehicles",
                    "fetchTripSuggestions"]

function offlineFail() {
    return { ok: false, error: { type: ProviderUtil.ErrorType.Offline, status: 0, detail: "" } }
}

function localNowString(s) {
    return DTF.localDateTimeString(new Date(OfflineState.nowOf(s)))
}

// -- The wrapped tracker --------------------------------------------------------

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
    return [name].concat(Array.prototype.slice.call(args, 2, cbIndex).map(function(arg) {
        return JSON.stringify(arg === undefined ? null : arg)
    })).join("|")
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
                Outbox.observe(s, result, true)
                // Back online with ops waiting: send them, then read again (the answer predates them).
                if (result.ok && again && Outbox.hasPending(s)) {
                    again = false
                    Outbox.replay(s, run)
                    return
                }
                if (result.ok) {
                    remember(result, args)
                    OfflineState.saveSnapshot(s)
                    callback({ ok: true, data: answer(result.data, args), droppedFields: result.droppedFields })
                    return
                }
                if (Outbox.isNetworkError(result)) {
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
        if (Outbox.hasPending(s) && !s.offline) {
            Outbox.replay(s, run)
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
                Outbox.observe(s, result)
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
        return hit === undefined ? undefined : OfflineState.copy(hit)
    })
}

/** Offline or ops waiting: goes to the outbox. Else the server, the outbox on a network error. */
function write(s, sendOnline, queue) {
    if (s.offline || s.ops.length) {
        queue(false)
        if (!s.offline) {
            Outbox.replay(s)
        }
        return
    }
    sendOnline(function(result, callback) {
        Outbox.observe(s, result)
        if (Outbox.isNetworkError(result)) {
            queue(true)
            return
        }
        callback(result)
    })
}

function localAnswer(s, entryId) {
    return { ok: true, data: OfflineState.knownEntry(s, entryId), queued: true }
}

function queueCreate(s, fields, callback, maybeSent) {
    var id = Outbox.newLocalId(s)
    Outbox.enqueue(s, { kind: OfflineState.Op.CREATE, entryId: id, fields: fields, maybeSent: !!maybeSent })
    callback(localAnswer(s, id))
}

/** Changes of an entry: into its waiting create, or a patch with the base for the conflict check. */
function queuePatch(s, entryId, fields, callback) {
    var create = Outbox.pendingCreate(s, entryId)
    if (create && create.state === OfflineState.State.PENDING) {
        create.fields = OfflineState.applyFields(create.fields, fields)
        Outbox.saveOutbox(s)
        OfflineState.notify(s)
    } else {
        Outbox.enqueue(s, { kind: OfflineState.Op.PATCH, entryId: entryId, fields: fields, base: Outbox.baseOf(OfflineState.knownEntry(s, entryId)) })
    }
    callback(localAnswer(s, entryId))
}

function queueDelete(s, entryId, callback) {
    var create = Outbox.pendingCreate(s, entryId)
    if (create && create.state === OfflineState.State.PENDING) {
        // Never sent: drop the create and everything waiting on it.
        s.ops = s.ops.filter(function(op) { return String(op.entryId) !== String(entryId) })
        Outbox.saveOutbox(s)
        OfflineState.notify(s)
    } else {
        Outbox.enqueue(s, { kind: OfflineState.Op.DELETE, entryId: entryId, base: Outbox.baseOf(OfflineState.knownEntry(s, entryId)) })
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

function wrapTrips(s, t) {
    var inner = s.inner
    t.fetchTrips = wrapRead(s, "fetchTrips", function(result, args) {
        s.snapshot.reads[readKey("fetchTrips", args, callbackIndex(args))] = result.data
    }, function(data, args) {
        return OfflineState.overlayTrips(s, data, args[2])
    }, function(args) {
        var hit = s.snapshot.reads[readKey("fetchTrips", args, callbackIndex(args))]
        return hit === undefined ? undefined : OfflineState.overlayTrips(s, OfflineState.copy(hit), args[2])
    })

    t.createTrip = function(url, token, body, callback) {
        write(s, function(done) {
            inner.createTrip(url, token, body, function(result) { done(result, callback) })
        }, function() {
            var id = Outbox.newLocalId(s)
            Outbox.enqueue(s, { kind: OfflineState.Op.TRIP_CREATE, tripId: id, body: OfflineState.copy(body || {}) })
            callback({ ok: true, data: OfflineState.knownTrip(s, id), queued: true })
        })
    }

    t.patchTrip = function(url, token, tripId, body, callback) {
        write(s, function(done) {
            inner.patchTrip(url, token, tripId, body, function(result) { done(result, callback) })
        }, function() {
            var create = Outbox.pendingTripCreate(s, tripId)
            if (create && create.state === OfflineState.State.PENDING) {
                create.body = OfflineState.applyTripBody(create.body, body || {})
                Outbox.saveOutbox(s)
                OfflineState.notify(s)
            } else {
                Outbox.enqueue(s, { kind: OfflineState.Op.TRIP_PATCH, tripId: tripId, body: OfflineState.copy(body || {}) })
            }
            callback({ ok: true, data: OfflineState.knownTrip(s, tripId), queued: true })
        })
    }

    t.deleteTrip = function(url, token, tripId, callback) {
        write(s, function(done) {
            inner.deleteTrip(url, token, tripId, function(result) { done(result, callback) })
        }, function() {
            var create = Outbox.pendingTripCreate(s, tripId)
            if (create && create.state === OfflineState.State.PENDING) {
                s.ops = s.ops.filter(function(op) { return String(op.tripId) !== String(tripId) })
                Outbox.saveOutbox(s)
                OfflineState.notify(s)
            } else {
                Outbox.enqueue(s, { kind: OfflineState.Op.TRIP_DELETE, tripId: tripId })
            }
            callback({ ok: true, data: null, queued: true })
        })
    }
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
        OfflineState.rememberEntries(s, result.data)
        s.snapshot.activeId = result.data && result.data.length ? result.data[0].id : null
    }, function(data) {
        return OfflineState.overlayActive(s, data)
    }, function() {
        return OfflineState.overlayActive(s, OfflineState.snapshotActive(s))
    })

    t.fetchRecentTimesheets = wrapRead(s, "fetchRecentTimesheets", function(result) {
        OfflineState.rememberEntries(s, result.data)
        s.snapshot.recentIds = (result.data || []).map(function(ts) { return ts.id })
    }, function(data, args) {
        return OfflineState.overlayRecent(s, data, args[2])
    }, function(args) {
        return OfflineState.overlayRecent(s, OfflineState.snapshotRecent(s), args[2])
    })

    t.fetchTimesheetsRange = wrapRead(s, "fetchTimesheetsRange", function(result, args) {
        // Filtered answers (one project) are incomplete for the range; keep the entries only.
        OfflineState.rememberEntries(s, result.data)
    }, function(data, args) {
        return OfflineState.overlayRange(s, data, args[2], args[3])
    }, function(args) {
        var filters = args[5]
        var list = OfflineState.overlayRange(s, OfflineState.snapshotRange(s, args[2], args[3]), args[2], args[3])
        if (filters && filters.project) {
            list = list.filter(function(ts) {
                return Outbox.comparable("project", ts.project) === String(filters.project)
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
            var from = OfflineState.knownEntry(s, timesheetId)
            if (!from) {
                callback(offlineFail())
                return
            }
            queueCreate(s, writeFields({
                begin: localNowString(s), project: Outbox.comparable("project", from.project),
                activity: Outbox.comparable("activity", from.activity), description: from.description || "",
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
            Outbox.enqueue(s, { kind: OfflineState.Op.FILM_DAY, projectId: projectId, dateStr: dateStr, patch: patch })
            callback({ ok: true, data: null, queued: true })
        })
    }

    if (typeof inner.createTrip === "function") {
        wrapTrips(s, t)
    }

    // Online only: new ids others depend on (trip suggestions are the server's to turn into trips).
    var onlineOnly = ["createCustomer", "createProject", "createActivity",
                      "acceptTripSuggestion", "dismissTripSuggestion"]
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

// -- Session --------------------------------------------------------------------

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
        snapshot: OfflineState.emptySnapshot(),
        savedSnapshotText: "",
        savedSnapshotAt: 0,
        saveQueued: false,
        replaying: false,
        replayWaiters: [],
        closed: false,
        // The outbox file could not be read: it is not written until a read works.
        outboxBlocked: false,
        loadingOutbox: null,
        storageError: OfflineState.StorageError.NONE
    }
    s.tracker = s.enabled ? wrapTracker(s) : inner
    return s
}

/** Loads snapshot and outbox from disk. */
function load(s) {
    if (!s.enabled) {
        return Promise.resolve()
    }
    return Promise.all([s.host.load(OfflineState.stateName(s)), Outbox.loadOutbox(s)]).then(function(parts) {
        OfflineState.restoreSnapshot(s, parts[0].data)
        OfflineState.notify(s)
    })
}

/** The profile of this session is not the active one any more: a replay in flight stops. */
function close(s) {
    s.closed = true
}

function isOffline(s) {
    return s.enabled && s.offline
}
