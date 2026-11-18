.pragma library
.import "./dateTimeFormat.js" as DTF

/**
 * Stored state of the offline layer and what is laid over it. The snapshot is
 * the last server answers kept on disk; the overlay is a server answer or the
 * snapshot plus the changes waiting in the outbox (entries and trips). Ops are
 * stored and sent by offlineOutbox.js; the session (offline.js) ties both to
 * the tracker.
 */

var Op = {
    CREATE: "create",
    PATCH: "patch",
    DELETE: "delete",
    FILM_DAY: "filmDay",
    TRIP_CREATE: "tripCreate",
    TRIP_PATCH: "tripPatch",
    TRIP_DELETE: "tripDelete"
}

var State = {
    PENDING: "pending",
    FAILED: "failed",
    CONFLICT: "conflict"
}

/**
 * What is wrong with the files of the layer, for the session to show (no text here).
 * LOAD: the outbox cannot be read or is of another version, so it is not written
 * until a read works; SAVE: the last write failed (the next one carries everything);
 * BROKEN: the outbox file was no JSON and was set aside, the queue starts empty.
 */
var StorageError = {
    NONE: "",
    LOAD: "load",
    SAVE: "save",
    BROKEN: "broken"
}

/** Entries kept in the snapshot (stats, week totals, film days of the last month). */
var KEEP_DAYS = 45
var DAY_MS = 24 * 3600 * 1000
var SNAPSHOT_VERSION = 1
/**
 * Unchanged answers (the poll) write the snapshot again only this often, to keep
 * its time on disk (in memory it follows every answer). The file is some 400 KB.
 */
var SAVE_AGE_MS = 60 * 60 * 1000

function nowOf(s) {
    return s.host.now ? s.host.now() : Date.now()
}

function notify(s) {
    if (s.host.changed) {
        s.host.changed()
    }
}

function copy(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value))
}

function stateName(s) {
    return "offline-state-" + s.host.key
}

// -- Snapshot -------------------------------------------------------------------

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

/** Reads of a date range ({from, to}) that ended before the kept days: the poll moves on daily. */
function pruneReads(s) {
    const limit = new Date(nowOf(s) - KEEP_DAYS * DAY_MS)
    const day = DTF.dateKey(limit)
    for (const key in s.snapshot.reads) {
        const parts = key.split("|").slice(1)
        for (let i = 0; i < parts.length; i++) {
            let arg = null
            try {
                arg = JSON.parse(parts[i])
            } catch (e) {
            }
            if (arg && typeof arg.to === "string" && arg.to < day) {
                delete s.snapshot.reads[key]
                break
            }
        }
    }
}

/** Without what changes on its own: the duration of a running entry grows with every poll. */
function snapshotText(snapshot) {
    return JSON.stringify(snapshot, function(key, value) {
        if (key === "savedAt" || (key === "duration" && this && this.begin && !this.end)) {
            return undefined
        }
        return value
    })
}

/**
 * Saves the snapshot. With host.defer(fn) once for a burst of answers (a refresh
 * reads a dozen): comparing the text costs a stringify of the whole snapshot.
 */
function saveSnapshot(s) {
    // A closed session is written at once: its deferred save would replace the active session's.
    if (s.closed || !s.host.defer) {
        writeSnapshot(s)
        return
    }
    if (s.saveQueued) {
        return
    }
    s.saveQueued = true
    s.host.defer(function() {
        s.saveQueued = false
        writeSnapshot(s)
    })
}

/** Written when its content changed (compared without the time) or the file's time is old. */
function writeSnapshot(s) {
    pruneEntries(s)
    pruneReads(s)
    if (s.owner) {
        s.snapshot.owner = s.owner
    }
    var text = snapshotText(s.snapshot)
    s.snapshot.savedAt = nowOf(s)
    if (text === s.savedSnapshotText && s.snapshot.savedAt - s.savedSnapshotAt < SAVE_AGE_MS) {
        return
    }
    s.savedSnapshotText = text
    s.savedSnapshotAt = s.snapshot.savedAt
    // A lost snapshot is a smaller cache, not lost work: warn only.
    Promise.resolve(s.host.save(stateName(s), s.snapshot)).catch(function(err) {
        console.warn("Plasmai: could not save", stateName(s), err)
    })
}

/** Takes the saved snapshot (a file of another version is ignored). */
function restoreSnapshot(s, state) {
    if (!state || state.v !== SNAPSHOT_VERSION) {
        return
    }
    s.snapshot = state
    s.savedSnapshotAt = state.savedAt || 0
    s.savedSnapshotText = snapshotText(state)
}

/** When the snapshot was last written from a server answer (ms, 0 = never). */
function stateAt(s) {
    return s.snapshot.savedAt || 0
}

/** Film day answers kept by filmDaySync (memo.days of this profile), persisted with the snapshot. */
function rememberFilmDays(s, days) {
    // Before the account check the answers may be of another owner.
    if (!s.enabled || !s.verified) {
        return
    }
    s.snapshot.filmDays = copy(days || {})
    saveSnapshot(s)
}

function filmDays(s) {
    return copy(s.snapshot.filmDays || {})
}

// -- Overlay: the snapshot or a server answer plus what waits in the outbox -----

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

// -- Trips (kimai-anfahrten) ----------------------------------------------------

function tripOps(s, tripId) {
    return s.ops.filter(function(op) { return op.tripId !== undefined && String(op.tripId) === String(tripId) })
}

/** trip with its waiting patches, or null when a delete waits for it. */
function overlayTrip(s, trip) {
    var out = trip
    var ops = tripOps(s, trip.id)
    for (var i = 0; i < ops.length; i++) {
        if (ops[i].kind === Op.TRIP_DELETE) {
            return null
        }
        if (ops[i].kind === Op.TRIP_PATCH) {
            out = applyTripBody(out, ops[i].body)
        }
    }
    return out
}

function applyTripBody(trip, body) {
    var out = copy(trip)
    for (var k in body) {
        out[k] = body[k]
    }
    return out
}

/** range {from, to} ("YYYY-MM-DD") or {year, month}, as fetchTrips takes it; none = all. */
function tripInRange(trip, range) {
    var date = String(trip.date || "")
    if (!range) {
        return true
    }
    if (range.from && range.to) {
        return date >= range.from && date <= range.to
    }
    var prefix = range.year ? String(range.year) : ""
    if (range.month) {
        prefix += "-" + (range.month < 10 ? "0" : "") + range.month
    }
    return date.indexOf(prefix) === 0
}

function localTrips(s) {
    var out = []
    for (var i = 0; i < s.ops.length; i++) {
        var op = s.ops[i]
        if (op.kind === Op.TRIP_CREATE) {
            var trip = overlayTrip(s, applyTripBody({ id: op.tripId }, op.body))
            if (trip) {
                out.push(trip)
            }
        }
    }
    return out
}

function overlayTrips(s, list, range) {
    var out = []
    for (var i = 0; i < (list || []).length; i++) {
        var trip = overlayTrip(s, list[i])
        if (trip) {
            out.push(trip)
        }
    }
    return out.concat(localTrips(s).filter(function(t) { return tripInRange(t, range) }))
}

/** The last known version of a trip: made offline, or from a cached trips answer. */
function knownTrip(s, tripId) {
    var local = localTrips(s).filter(function(t) { return String(t.id) === String(tripId) })
    if (local.length) {
        return local[0]
    }
    for (var key in s.snapshot.reads) {
        if (key.indexOf("fetchTrips|") !== 0) {
            continue
        }
        var list = s.snapshot.reads[key] || []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && String(list[i].id) === String(tripId)) {
                return overlayTrip(s, list[i])
            }
        }
    }
    return null
}
