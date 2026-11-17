import QtQuick
import QtTest
import "../../contents/code/offline.js" as Offline
import "../../contents/code/offlineOutbox.js" as Outbox
import "../../contents/code/offlineState.js" as OfflineState
import "../../contents/code/dateTimeFormat.js" as DTF
import "../../contents/code/providerUtil.js" as ProviderUtil
import "../../contents/code/localFile.js" as LocalFile

/**
 * offline.js: snapshot answers, outbox, replay, local ids, conflicts. A fake
 * Kimai answers at once; `net` switches the network, `server` is its data.
 */
TestCase {
    name: "Offline"

    OfflineFakes { id: fakes }

    readonly property double t0: fakes.t0
    function stamp(h, m) { return fakes.stamp(h, m) }
    function netErr() { return fakes.netErr() }
    function fakeKimai() { return fakes.fakeKimai() }
    function fakeHost(files) { return fakes.fakeHost(files) }
    function call(fn) { return fakes.call(fn) }
    function session(k, h) { return fakes.session(k, h) }

    function test_readsFallBackToSnapshot() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        k.server[2] = { id: 2, begin: stamp(11, 0), project: 10, activity: 21 }
        var s = session(k)
        var t = s.tracker
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        call(function(cb) { t.loadProjects("u", "t", cb) })
        verify(!Offline.isOffline(s))
        compare(OfflineState.stateAt(s), t0)

        k.net = false
        var active = call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        verify(active.ok && active.offline)
        compare(active.data.length, 1)
        compare(active.data[0].id, 2)
        verify(Offline.isOffline(s))
        var recent = call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(recent.data.length, 2)
        var projects = call(function(cb) { t.loadProjects("u", "t", cb) })
        compare(projects.data[0].name, "P")
        var range = call(function(cb) {
            t.fetchTimesheetsRange("u", "t", new Date(2026, 8, 28, 0, 0), new Date(2026, 8, 28, 23, 59), cb)
        })
        compare(range.data.length, 2)
        // Never loaded: the network error stays.
        var none = call(function(cb) { t.fetchTimesheetsRange("u", "t", new Date(2026, 7, 1), new Date(2026, 7, 2), cb) })
        verify(none.ok)
        compare(none.data.length, 0)
    }

    // The poll reads the same answers again: the snapshot is written when they
    // change, and to keep its time current at most every SAVE_AGE_MS otherwise.
    function test_sameAnswersSaveOnce() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        var h = fakeHost()
        var saves = 0
        var save = h.save
        h.save = function(name, obj) { if (name.indexOf("offline-state-") === 0) saves++; return save(name, obj) }
        var t = session(k, h).tracker
        for (var i = 0; i < 3; i++) {
            h.clock = t0 + i * 30000
            call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        }
        compare(saves, 1)
        h.clock = t0 + OfflineState.SAVE_AGE_MS + 1
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(saves, 2)
        k.server[2] = { id: 2, begin: stamp(11, 0), project: 10, activity: 21 }
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(saves, 3)
    }

    // A refresh reads five or more answers in a row; with host.defer the snapshot
    // is compared and written once for all of them, not once per answer.
    function test_burstSavesOnce() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        k.server[2] = { id: 2, begin: stamp(11, 0), project: 10, activity: 21 }
        var h = fakeHost()
        var deferred = []
        h.defer = function(fn) { deferred.push(fn) }
        var saves = 0
        var save = h.save
        h.save = function(name, obj) { if (name.indexOf("offline-state-") === 0) saves++; return save(name, obj) }
        var t = session(k, h).tracker
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        call(function(cb) { t.loadProjects("u", "t", cb) })
        call(function(cb) { t.fetchTimesheetsRange("u", "t", new Date(2026, 8, 28, 0, 0), new Date(2026, 8, 28, 23, 59), cb) })
        compare(saves, 0, "nothing written before the burst ends")
        compare(deferred.length, 1, "one save waits for the burst")
        deferred.shift()()
        compare(saves, 1)
        var written = JSON.parse(h.files["offline-state-p1"])
        compare(Object.keys(written.entries).length, 2)
        verify(Object.keys(written.reads).some(function(key) { return key.indexOf("loadProjects") === 0 }))
    }

    // A running entry's duration grows with every poll; that alone writes nothing.
    function test_runningDurationIsNoChange() {
        var k = fakeKimai()
        k.server[2] = { id: 2, begin: stamp(11, 0), duration: 3600, project: 10, activity: 21 }
        var h = fakeHost()
        var saves = 0
        var save = h.save
        h.save = function(name, obj) {
            if (name.indexOf("offline-state-") === 0) {
                saves++
            }
            return save(name, obj)
        }
        var t = session(k, h).tracker
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        h.clock = t0 + 30000
        k.server[2].duration = 3630
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        compare(saves, 1)
        k.server[2].end = stamp(12, 1)
        k.server[2].duration = 3660
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        compare(saves, 2, "stopped: written")
    }

    // Date-range reads move on daily; those that ended before the kept days go.
    function test_oldRangeReadsArePruned() {
        var k = fakeKimai()
        var h = fakeHost()
        var t = session(k, h).tracker
        call(function(cb) { t.fetchTrips("u", "t", { from: "2026-07-01", to: "2026-07-31" }, cb) })
        call(function(cb) { t.fetchTrips("u", "t", { from: "2026-09-01", to: "2026-09-30" }, cb) })
        call(function(cb) { t.fetchTrips("u", "t", null, cb) })
        var reads = JSON.parse(h.files["offline-state-p1"]).reads
        var keys = Object.keys(reads)
        compare(keys.length, 2)
        verify(keys.indexOf('fetchTrips|{"from":"2026-09-01","to":"2026-09-30"}') >= 0)
        verify(keys.indexOf("fetchTrips|null") >= 0)
    }

    function test_startAndStopOffline() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        var t = s.tracker
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        k.calls = []
        var started = call(function(cb) { t.startTracking("u", "t", 10, 20, "Dreh", cb, {}) })
        verify(started.ok && started.queued)
        verify(Outbox.isLocalId(started.data.id))
        compare(started.data.begin, stamp(12, 0))
        compare(k.calls, [], "offline: no request")
        var active = call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        compare(active.data[0].id, started.data.id)
        verify(Outbox.isUnsynced(s, started.data.id))

        h.clock = t0 + 45 * 60000
        var stopped = call(function(cb) { t.stopTracking("u", "t", started.data.id, cb) })
        verify(stopped.ok)
        compare(Outbox.pendingCount(s), 1, "the stop went into the waiting create")
        active = call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        compare(active.data.length, 0)
        var recent = call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(recent.data[0].end, stamp(12, 45))
        compare(recent.data[0].duration, 45 * 60, "views show the duration")

        // Back online: the next read sends the outbox first.
        k.net = true
        k.calls = []
        active = call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        compare(k.calls, ["active", "create", "active"])
        compare(Outbox.pendingCount(s), 0)
        compare(h.renamed.length, 1)
        compare(h.renamed[0][1], 100)
        compare(k.server[100].begin, stamp(12, 0))
        compare(k.server[100].end, stamp(12, 45))
        compare(k.server[100].description, "Dreh")
        verify(!Offline.isOffline(s))
    }

    function test_opsWaitInOrderAndIdsFollow() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        k.net = false
        var a = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(8, 0), end: stamp(9, 0), project: 10, activity: 20 }, cb) })
        verify(Offline.isOffline(s) === true)
        // The create is not sent yet: a later patch of it is merged, not queued.
        call(function(cb) { t.patchTimesheet("u", "t", a.data.id, { description: "x" }, cb) })
        compare(Outbox.pendingCount(s), 1)
        k.net = true
        var sent = call(function(cb) { Outbox.replay(s, cb) })
        compare(sent, 1)
        compare(k.server[100].description, "x")
    }

    function test_writeWithNetworkErrorQueuesAndAvoidsDuplicate() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        // The create reaches the server, its answer is lost.
        k.loseAnswer = true
        var r = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(8, 0), end: stamp(9, 0), project: 10, activity: 20 }, cb) })
        verify(r.ok && r.queued)
        verify(Offline.isOffline(s))
        compare(Object.keys(k.server).length, 1)
        k.calls = []
        call(function(cb) { Outbox.replay(s, cb) })
        compare(k.calls[0], "range", "looks for the lost create first")
        verify(k.calls.indexOf("create") < 0, "no second create")
        compare(Object.keys(k.server).length, 1)
        compare(Outbox.pendingCount(s), 0)
    }

    function test_replayStopsAtFailure() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20, description: "" }
        var s = session(k)
        var t = s.tracker
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        k.net = false
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        var a = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(7, 0), end: stamp(8, 0), project: 10, activity: 20 }, cb) })
        call(function(cb) { t.patchTimesheet("u", "t", 1, { description: "later" }, cb) })
        compare(Outbox.pendingCount(s), 2)

        k.net = true
        k.refuse = { create: { type: "unknown", status: 400, detail: "overlap" } }
        call(function(cb) { Outbox.replay(s, cb) })
        var ops = Outbox.ops(s)
        compare(ops.length, 2)
        compare(ops[0].state, OfflineState.State.FAILED)
        compare(ops[0].error.detail, "overlap")
        compare(ops[1].state, OfflineState.State.PENDING)
        compare(k.server[1].description, "", "the later op waits")
        verify(k.calls.indexOf("patch 1") < 0)

        // Fixed elsewhere: retry sends both.
        k.refuse = null
        call(function(cb) { Outbox.retry(s, ops[0].opId, cb) })
        compare(Outbox.pendingCount(s), 0)
        compare(k.server[1].description, "later")
    }

    function test_discardCreateDropsItsOps() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        var a = call(function(cb) { t.startTracking("u", "t", 10, 20, "", cb, {}) })
        k.net = true
        k.refuse = { create: { type: "unknown", status: 400, detail: "no" } }
        call(function(cb) { Outbox.replay(s, cb) })
        var ops = Outbox.ops(s)
        compare(ops[0].state, OfflineState.State.FAILED)
        // Failed: a later stop cannot merge into it and waits as a patch.
        k.net = false
        call(function(cb) { t.stopTracking("u", "t", a.data.id, cb) })
        compare(Outbox.pendingCount(s), 2)
        Outbox.discard(s, ops[0].opId)
        compare(Outbox.pendingCount(s), 0)
    }

    function test_conflictWhenChangedOnServer() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20, description: "a" }
        var s = session(k)
        var t = s.tracker
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        k.net = false
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        call(function(cb) { t.patchTimesheet("u", "t", 1, { end: stamp(10, 30) }, cb) })
        // Meanwhile someone else changed the entry.
        k.server[1].description = "changed elsewhere"
        k.net = true
        call(function(cb) { Outbox.replay(s, cb) })
        var op = Outbox.ops(s)[0]
        compare(op.state, OfflineState.State.CONFLICT)
        compare(op.error.detail, "description")
        compare(op.server.description, "changed elsewhere")
        compare(k.server[1].end, stamp(10, 0), "not overwritten")
        call(function(cb) { Outbox.overwrite(s, op.opId, cb) })
        compare(k.server[1].end, stamp(10, 30))
        compare(Outbox.pendingCount(s), 0)
    }

    function test_deleteOfflineAndGoneOnServer() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        var s = session(k)
        var t = s.tracker
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        k.net = false
        call(function(cb) { t.deleteTimesheet("u", "t", 1, cb) })
        var recent = call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(recent.data.length, 0, "shown as deleted")
        delete k.server[1]
        k.net = true
        call(function(cb) { Outbox.replay(s, cb) })
        compare(Outbox.pendingCount(s), 0, "already gone counts as done")
    }

    function test_restartOfflineFromSnapshot() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: { id: 10 }, activity: { id: 20 },
                        description: "Szene 4", tags: ["a"] }
        var s = session(k)
        var t = s.tracker
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        k.net = false
        call(function(cb) { t.fetchRecentTimesheets("u", "t", 10, cb) })
        var r = call(function(cb) { t.restartTimesheet("u", "t", 1, cb) })
        verify(r.ok && r.queued)
        compare(r.data.project, "10")
        compare(r.data.description, "Szene 4")
        compare(r.data.end, undefined)
        var unknown = call(function(cb) { t.restartTimesheet("u", "t", 999, cb) })
        compare(unknown.error.type, ProviderUtil.ErrorType.Offline)
    }

    function test_onlineOnlyRefusedOffline() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        k.calls = []
        var r = call(function(cb) { t.createProject("u", "t", { name: "x" }, cb) })
        compare(r.error.type, ProviderUtil.ErrorType.Offline)
        compare(k.calls, [])
    }

    function test_outboxSurvivesRestart() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        k.net = false
        call(function(cb) { s.tracker.fetchActiveTimesheet("u", "t", cb) })
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "", cb, {}) })
        // A new session (app restart) on the same files.
        var h2 = fakeHost(h.files)
        var s2 = session(k, h2)
        var loaded = false
        Offline.load(s2).then(function() { loaded = true })
        tryVerify(function() { return loaded })
        compare(Outbox.pendingCount(s2), 1)
        var active = call(function(cb) { s2.tracker.fetchActiveTimesheet("u", "t", cb) })
        compare(active.data.length, 1)
        verify(Outbox.isLocalId(active.data[0].id))
        k.net = true
        // Started without network: the account is checked once the server is there.
        Offline.verify(s2)
        call(function(cb) { Outbox.replay(s2, cb) })
        compare(Outbox.pendingCount(s2), 0)
    }

    function test_outboxOfAnOlderVersionKeepsItsSetupError() {
        // Before the error kinds moved into ErrorType, a refused op stored "config".
        var h = fakeHost()
        h.files["offline-outbox-p1"] = JSON.stringify({ v: 1, counter: 1, ops: [
            { id: 1, kind: "create", state: "failed", fields: {}, error: { type: "config", status: 0, detail: "" } },
            { id: 2, kind: "create", state: "failed", fields: {}, error: { type: "unknown", status: 400, detail: "no" } }
        ] })
        var s = session(fakeKimai(), h)
        var loaded = false
        Offline.load(s).then(function() { loaded = true })
        tryVerify(function() { return loaded })
        var ops = Outbox.ops(s)
        compare(ops[0].error.type, ProviderUtil.ErrorType.NotConfigured)
        compare(ops[1].error.type, ProviderUtil.ErrorType.Unknown)
    }

    function test_writesWaitBehindQueueOnline() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(7, 0), end: stamp(8, 0), project: 10, activity: 20 }, cb) })
        k.net = true
        k.refuse = { create: { type: "unknown", status: 400, detail: "no" } }
        call(function(cb) { Outbox.replay(s, cb) })
        verify(!Offline.isOffline(s))
        // Online, but an op failed: a new write stays behind it (order).
        k.calls = []
        var r = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }, cb) })
        verify(r.queued)
        compare(Outbox.pendingCount(s), 2)
    }

    function test_otherProviderPassesThrough() {
        var k = fakeKimai()
        var h = fakeHost()
        h.key = ""
        var s = session(k, h)
        compare(s.tracker, k)
        k.net = false
        var r = call(function(cb) { s.tracker.fetchActiveTimesheet("u", "t", cb) })
        verify(!r.ok)
        verify(!Offline.isOffline(s))
    }

    function test_filmDaysPersisted() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        OfflineState.rememberFilmDays(s, { "2026-09-28": { timesheets: { at: 1, result: { ok: true, data: [] } } } })
        var s2 = session(k, fakeHost(h.files))
        var loaded = false
        Offline.load(s2).then(function() { loaded = true })
        tryVerify(function() { return loaded })
        verify(OfflineState.filmDays(s2)["2026-09-28"].timesheets.result.ok)
    }

    function test_tripsOffline() {
        var k = fakeKimai()
        k.trips[7] = { id: 7, date: "2026-09-28", distanceKm: 12, timesheet: null }
        var s = session(k)
        var t = s.tracker
        var range = { year: 2026, month: 9 }
        call(function(cb) { t.fetchTrips("u", "t", range, cb) })
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        // A trip of an entry made offline: it waits for the entry's server id.
        var entry = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(8, 0), end: stamp(9, 0), project: 10, activity: 20 }, cb) })
        var trip = call(function(cb) { t.createTrip("u", "t", { date: "2026-09-28", distanceKm: 30, timesheet: entry.data.id }, cb) })
        verify(trip.ok && trip.queued)
        call(function(cb) { t.patchTrip("u", "t", trip.data.id, { distanceKm: 31 }, cb) })
        call(function(cb) { t.patchTrip("u", "t", 7, { distanceKm: 13 }, cb) })
        compare(Outbox.pendingCount(s), 3, "entry, trip (with its patch), patch of trip 7")
        var list = call(function(cb) { t.fetchTrips("u", "t", range, cb) })
        verify(list.offline)
        compare(list.data.length, 2)
        compare(list.data[0].distanceKm, 13)
        compare(list.data[1].distanceKm, 31)
        var other = call(function(cb) { t.fetchTrips("u", "t", { year: 2026, month: 8 }, cb) })
        verify(!other.ok, "an unknown range stays an error")
        var accept = call(function(cb) { t.acceptTripSuggestion("u", "t", 1, {}, cb) })
        compare(accept.error.type, ProviderUtil.ErrorType.Offline)

        k.net = true
        call(function(cb) { Outbox.replay(s, cb) })
        compare(Outbox.pendingCount(s), 0)
        compare(k.trips[500].timesheet, 100, "linked to the entry's server id")
        compare(k.trips[500].distanceKm, 31)
        compare(k.trips[7].distanceKm, 13)
    }

    function test_tripDeleteAndDiscardedEntry() {
        var k = fakeKimai()
        k.trips[7] = { id: 7, date: "2026-09-28", distanceKm: 12 }
        var s = session(k)
        var t = s.tracker
        call(function(cb) { t.fetchTrips("u", "t", null, cb) })
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        call(function(cb) { t.deleteTrip("u", "t", 7, cb) })
        var entry = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(8, 0), end: stamp(9, 0), project: 10, activity: 20 }, cb) })
        call(function(cb) { t.createTrip("u", "t", { date: "2026-09-28", distanceKm: 5, timesheet: entry.data.id }, cb) })
        var list = call(function(cb) { t.fetchTrips("u", "t", null, cb) })
        compare(list.data.length, 1)
        compare(list.data[0].distanceKm, 5)
        // Discarding the entry keeps its trip, unlinked.
        var createOp = Outbox.ops(s).filter(function(o) { return o.kind === OfflineState.Op.CREATE })[0]
        Outbox.discard(s, createOp.opId)
        compare(Outbox.pendingCount(s), 2)
        k.net = true
        call(function(cb) { Outbox.replay(s, cb) })
        verify(!k.trips[7])
        compare(k.trips[500].timesheet, null)
    }

    // Film-day extras go through the inner tracker, online and again on replay.
    function test_filmDayExtrasQueueAndReplay() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        var online = call(function(cb) { t.putFilmDay("u", "t", 1, "2026-09-28", { note: "a" }, cb) })
        verify(online.ok && !online.queued)
        compare(k.filmDays["1|2026-09-28"].note, "a")

        k.net = false
        var queued = call(function(cb) { t.putFilmDay("u", "t", 1, "2026-09-28", { note: "b" }, cb) })
        verify(queued.ok && queued.queued)
        compare(Outbox.pendingCount(s), 1)
        compare(k.filmDays["1|2026-09-28"].note, "a")

        k.net = true
        call(function(cb) { Outbox.replay(s, cb) })
        compare(Outbox.pendingCount(s), 0)
        compare(k.filmDays["1|2026-09-28"].note, "b")
    }

    // Plugin calls reach the server as asked; their failure does not flip the layer offline.
    function test_pluginCallsReachServerUnobserved() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        compare(call(function(cb) { t.fetchDaySummary("u", "t", 1, "2026-09-28", cb) }).data.payCents, 100)
        k.net = false
        var failed = call(function(cb) { t.fetchDaySummary("u", "t", 1, "2026-09-28", cb) })
        compare(failed.error.type, "network")
        compare(call(function(cb) { t.detectDrehzettel("u", "t", {}, cb) }).state, "unknown")
        verify(!Offline.isOffline(s))
        compare(k.calls.filter(function(c) { return c === "summary" || c === "detect" }).length, 3)
    }
}
