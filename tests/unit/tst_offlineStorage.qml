import QtQuick
import QtTest
import "../../contents/code/offline.js" as Offline
import "../../contents/code/offlineOutbox.js" as Outbox
import "../../contents/code/offlineState.js" as OfflineState
import "../../contents/code/providerUtil.js" as ProviderUtil
import "../../contents/code/localFile.js" as LocalFile

/**
 * The offline layer's files: a read that failed or is still running never lets a
 * write replace the outbox; a failed write is reported; a replay keeps to the
 * connection and the session it started with; a closed session writes its outbox and its snapshot at once.
 */
TestCase {
    name: "OfflineStorage"

    OfflineFakes { id: fakes }

    readonly property double t0: fakes.t0
    function stamp(h, m) { return fakes.stamp(h, m) }
    function netErr() { return fakes.netErr() }
    function fakeKimai() { return fakes.fakeKimai() }
    function fakeHost(files) { return fakes.fakeHost(files) }
    function call(fn) { return fakes.call(fn) }
    function session(k, h) { return fakes.session(k, h) }

    function loaded(s) {
        var done = false
        Offline.load(s).then(function() { done = true })
        tryVerify(function() { return done })
    }

    function startOffline(k, s) {
        k.net = false
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "", cb, {}) })
    }

    // A read that failed is not an empty outbox: the next write must not replace the file.
    function test_unreadableOutboxIsNotOverwritten() {
        var k = fakeKimai()
        var h = fakeHost()
        h.files["offline-outbox-p1"] = JSON.stringify({ v: 1, counter: 1, ops: [{ opId: "local:x", kind: "create", state: "pending", entryId: "local:x", fields: {} }] })
        var before = h.files["offline-outbox-p1"]
        h.readAs["offline-outbox-p1"] = LocalFile.Status.UNREADABLE
        var s = session(k, h)
        loaded(s)
        compare(s.storageError, OfflineState.StorageError.LOAD)
        startOffline(k, s)
        compare(h.files["offline-outbox-p1"], before)
        compare(Outbox.pendingCount(s), 1, "the change waits in memory")

        // The file reads again: its ops load, then both are written.
        tryVerify(function() { return !s.loadingOutbox })
        delete h.readAs["offline-outbox-p1"]
        // Any answer of the server tries the load again.
        Outbox.observe(s, { ok: false, error: { type: ProviderUtil.ErrorType.Unknown, status: 500, detail: "" } })
        tryCompare(s, "storageError", OfflineState.StorageError.NONE)
        compare(JSON.parse(h.files["offline-outbox-p1"]).ops.length, 2)
    }

    function test_foreignVersionOutboxIsNotOverwritten() {
        var k = fakeKimai()
        var h = fakeHost()
        h.files["offline-outbox-p1"] = JSON.stringify({ v: 2, counter: 1, ops: [{ kind: "future" }] })
        var before = h.files["offline-outbox-p1"]
        var s = session(k, h)
        loaded(s)
        startOffline(k, s)
        compare(h.files["offline-outbox-p1"], before)
        compare(s.storageError, OfflineState.StorageError.LOAD)
    }

    // The platform moved a file with broken JSON aside: start empty, say so, and write again.
    function test_brokenOutboxStartsEmptyAndReports() {
        var k = fakeKimai()
        var h = fakeHost()
        h.readAs["offline-outbox-p1"] = LocalFile.Status.BROKEN
        var s = session(k, h)
        loaded(s)
        compare(s.storageError, OfflineState.StorageError.BROKEN)
        startOffline(k, s)
        compare(JSON.parse(h.files["offline-outbox-p1"]).ops.length, 1)
        compare(s.storageError, OfflineState.StorageError.BROKEN, "reported for the session")
    }

    function test_saveErrorIsReportedAndNextWriteCarriesAll() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        h.failSave = true
        loaded(s)
        startOffline(k, s)
        tryCompare(s, "storageError", OfflineState.StorageError.SAVE)
        verify(!h.files["offline-outbox-p1"])
        h.failSave = false
        call(function(cb) { s.tracker.createTimesheet("u", "t", { begin: stamp(7, 0), end: stamp(8, 0), project: 10, activity: 20 }, cb) })
        tryCompare(s, "storageError", OfflineState.StorageError.NONE)
        compare(JSON.parse(h.files["offline-outbox-p1"]).ops.length, 2)
    }

    // A profile or URL change during a replay must not send the waiting ops to the new server.
    function twoCreatesWaiting(k, s) {
        k.net = false
        for (var i = 0; i < 2; i++) {
            call(function(cb) { s.tracker.createTimesheet("u", "t", { begin: stamp(7 + i, 0), end: stamp(8 + i, 0), project: 10, activity: 20 }, cb) })
        }
        k.net = true
        compare(Outbox.pendingCount(s), 2)
    }

    function test_urlChangeStopsReplay() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        twoCreatesWaiting(k, s)
        var urls = []
        var create = k.createTimesheet
        k.createTimesheet = function(u, t, f, cb) {
            urls.push(u)
            h.currentUrl = "https://other.test"
            create(u, t, f, cb)
        }
        call(function(cb) { Outbox.replay(s, cb) })
        compare(urls, ["https://kimai.test"])
        compare(Outbox.pendingCount(s), 1, "the second op stays pending")
        compare(Outbox.ops(s)[0].state, OfflineState.State.PENDING)
    }

    function test_closedSessionStopsReplay() {
        var k = fakeKimai()
        var s = session(k, fakeHost())
        twoCreatesWaiting(k, s)
        var create = k.createTimesheet
        k.createTimesheet = function(u, t, f, cb) {
            Offline.close(s)
            create(u, t, f, cb)
        }
        call(function(cb) { Outbox.replay(s, cb) })
        compare(Outbox.pendingCount(s), 1)
    }

    // The lost-answer search ran on A; the URL is B when it answers: nothing goes to B.
    function test_urlChangeBetweenSearchAndPatch() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        k.loseAnswer = true
        call(function(cb) { s.tracker.createTimesheet("u", "t", { begin: stamp(7, 0), end: stamp(8, 0), project: 10, activity: 20 }, cb) })
        compare(Outbox.pendingCount(s), 1)
        k.net = true
        var urls = []
        k.calls = []
        var range = k.fetchTimesheetsRange
        k.fetchTimesheetsRange = function(u, t, b, e, cb, f) {
            urls.push(u)
            range(u, t, b, e, function(r) { h.currentUrl = "https://other.test"; cb(r) }, f)
        }
        var create = k.createTimesheet
        var patch = k.patchTimesheet
        k.createTimesheet = function(u, t, f, cb) { urls.push(u); create(u, t, f, cb) }
        k.patchTimesheet = function(u, t, id, f, cb) { urls.push(u); patch(u, t, id, f, cb) }
        call(function(cb) { Outbox.replay(s, cb) })
        compare(urls, ["https://kimai.test"], "only the search went out")
        compare(Outbox.pendingCount(s), 1)
    }

    // The file is read while a change is made: nothing is written until the read is done,
    // then the file holds the loaded ops and the new one, once.
    function test_noWriteWhileTheOutboxLoads() {
        var k = fakeKimai()
        var h = fakeHost()
        h.files["offline-outbox-p1"] = JSON.stringify({ v: 1, counter: 1, ops: [
            { opId: "local:p", kind: "patch", entryId: 5, fields: { description: "x" }, state: "pending", base: null }
        ] })
        var before = h.files["offline-outbox-p1"]
        h.holdLoad = true
        var s = session(k, h)
        var done = false
        Offline.load(s).then(function() { done = true })
        startOffline(k, s)
        compare(h.files["offline-outbox-p1"], before, "not written while loading")
        h.release()
        tryVerify(function() { return done })
        var ops = JSON.parse(h.files["offline-outbox-p1"]).ops
        compare(ops.length, 2)
        compare(ops[0].opId, "local:p")
        compare(ops[1].kind, OfflineState.Op.CREATE)
        compare(h.saves.filter(function(n) { return n === "offline-outbox-p1" }).length, 1)
    }

    // A closed session never defers its snapshot (the deferred save would replace the active
    // one's); what it still learns is written at once.
    function test_closedSessionWritesItsSnapshotAtOnce() {
        var k = fakeKimai()
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        var h = fakeHost()
        var s = session(k, h)
        var deferred = 0
        h.defer = function() { deferred++ }
        Offline.close(s)
        call(function(cb) { s.tracker.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(deferred, 0)
        verify(h.files["offline-state-p1"])
    }

    // The outbox is the closed session's alone: a change queued after the switch is written at once.
    function test_closedSessionWritesItsOutbox() {
        var k = fakeKimai()
        var h = fakeHost()
        var s = session(k, h)
        loaded(s)
        Offline.close(s)
        startOffline(k, s)
        compare(JSON.parse(h.files["offline-outbox-p1"]).ops.length, 1)
    }
}
