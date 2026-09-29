import QtQuick
import QtTest
import "../../contents/code/offline.js" as Offline

/**
 * offline.js: snapshot answers, outbox, replay, local ids, conflicts. A fake
 * Kimai answers at once; `net` switches the network, `server` is its data.
 */
TestCase {
    name: "Offline"

    // 2026-09-28 12:00 local
    readonly property double t0: new Date(2026, 8, 28, 12, 0).getTime()

    function stamp(h, m) {
        var d = new Date(2026, 8, 28, h, m)
        var p = function(n) { return (n < 10 ? "0" : "") + n }
        return "2026-09-28T" + p(h) + ":" + p(m) + ":00"
    }

    function netErr() { return { ok: false, error: { type: "network", status: 0, detail: "" } } }

    function fakeKimai() {
        var k = {
            net: true,
            calls: [],
            nextId: 100,
            server: {},              // id → timesheet
            refuse: null,            // name → error (server-side refusal)
            loseAnswer: false,       // next write reaches the server, answer lost
            projects: [{ id: 10, name: "P" }]
        }
        function answer(name, cb, fn) {
            k.calls.push(name)
            if (!k.net) { cb(netErr()); return }
            if (k.refuse && k.refuse[name]) { cb({ ok: false, error: k.refuse[name] }); return }
            var result = fn()
            if (k.loseAnswer) { k.loseAnswer = false; cb(netErr()); return }
            cb(result)
        }
        function list() { var out = []; for (var id in k.server) out.push(JSON.parse(JSON.stringify(k.server[id]))); return out }
        k.fetchActiveTimesheet = function(u, t, cb) {
            answer("active", cb, function() { return { ok: true, data: list().filter(function(ts) { return !ts.end }) } })
        }
        k.fetchRecentTimesheets = function(u, t, size, cb) {
            answer("recent", cb, function() { return { ok: true, data: list().slice(0, size) } })
        }
        k.fetchTimesheetsRange = function(u, t, b, e, cb, filters) {
            answer("range", cb, function() {
                return { ok: true, data: list().filter(function(ts) {
                    return new Date(ts.begin).getTime() <= e.getTime()
                        && (ts.end ? new Date(ts.end).getTime() : e.getTime()) >= b.getTime() }) }
            })
        }
        k.fetchTimesheet = function(u, t, id, cb) {
            answer("get " + id, cb, function() {
                return k.server[id] ? { ok: true, data: JSON.parse(JSON.stringify(k.server[id])) }
                                    : { ok: false, error: { type: "not_found", status: 404, detail: "" } }
            })
        }
        k.createTimesheet = function(u, t, f, cb) {
            answer("create", cb, function() {
                var ts = JSON.parse(JSON.stringify(f)); ts.id = k.nextId++; k.server[ts.id] = ts
                return { ok: true, data: ts }
            })
        }
        k.startTracking = function(u, t, pid, aid, desc, cb, extras) {
            answer("start", cb, function() {
                var ts = { id: k.nextId++, begin: stamp(12, 0), project: pid, activity: aid, description: desc || "" }
                k.server[ts.id] = ts
                return { ok: true, data: ts }
            })
        }
        k.stopTracking = function(u, t, id, cb) {
            answer("stop " + id, cb, function() { k.server[id].end = stamp(12, 30); return { ok: true, data: null } })
        }
        k.restartTimesheet = function(u, t, id, cb) {
            answer("restart " + id, cb, function() { return { ok: true, data: null } })
        }
        k.patchTimesheet = function(u, t, id, f, cb) {
            answer("patch " + id, cb, function() {
                for (var key in f) k.server[id][key] = f[key]
                return { ok: true, data: JSON.parse(JSON.stringify(k.server[id])) }
            })
        }
        k.deleteTimesheet = function(u, t, id, cb) {
            answer("delete " + id, cb, function() { delete k.server[id]; return { ok: true, data: null } })
        }
        k.loadProjects = function(u, t, cb) {
            answer("projects", cb, function() { return { ok: true, data: k.projects } })
        }
        k.createProject = function(u, t, f, cb) {
            answer("createProject", cb, function() { return { ok: true, data: { id: 11 } } })
        }
        return k
    }

    function fakeHost(files) {
        var h = {
            key: "p1",
            files: files || {},
            clock: t0,
            changes: 0,
            renamed: [],
            url: function() { return "https://kimai.test" },
            token: function() { return "tok" },
            load: function(name) { return Promise.resolve(h.files[name] ? JSON.parse(h.files[name]) : null) },
            save: function(name, obj) { h.files[name] = JSON.stringify(obj); return Promise.resolve(true) },
            now: function() { return h.clock },
            changed: function() { h.changes += 1 },
            idChanged: function(localId, serverId) { h.renamed.push([localId, serverId]) }
        }
        return h
    }

    function call(fn) {
        var out = null
        fn(function(r) { out = r })
        return out
    }

    function session(k, h) {
        return Offline.createSession(k, h || fakeHost())
    }

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
        compare(Offline.stateAt(s), t0)

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
        verify(Offline.isLocalId(started.data.id))
        compare(started.data.begin, stamp(12, 0))
        compare(k.calls, [], "offline: no request")
        var active = call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        compare(active.data[0].id, started.data.id)
        verify(Offline.isUnsynced(s, started.data.id))

        h.clock = t0 + 45 * 60000
        var stopped = call(function(cb) { t.stopTracking("u", "t", started.data.id, cb) })
        verify(stopped.ok)
        compare(Offline.pendingCount(s), 1, "the stop went into the waiting create")
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
        compare(Offline.pendingCount(s), 0)
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
        compare(Offline.pendingCount(s), 1)
        k.net = true
        var sent = call(function(cb) { Offline.replay(s, cb) })
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
        call(function(cb) { Offline.replay(s, cb) })
        compare(k.calls[0], "range", "looks for the lost create first")
        verify(k.calls.indexOf("create") < 0, "no second create")
        compare(Object.keys(k.server).length, 1)
        compare(Offline.pendingCount(s), 0)
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
        compare(Offline.pendingCount(s), 2)

        k.net = true
        k.refuse = { create: { type: "unknown", status: 400, detail: "overlap" } }
        call(function(cb) { Offline.replay(s, cb) })
        var ops = Offline.ops(s)
        compare(ops.length, 2)
        compare(ops[0].state, Offline.State.FAILED)
        compare(ops[0].error.detail, "overlap")
        compare(ops[1].state, Offline.State.PENDING)
        compare(k.server[1].description, "", "the later op waits")
        verify(k.calls.indexOf("patch 1") < 0)

        // Fixed elsewhere: retry sends both.
        k.refuse = null
        call(function(cb) { Offline.retry(s, ops[0].opId, cb) })
        compare(Offline.pendingCount(s), 0)
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
        call(function(cb) { Offline.replay(s, cb) })
        var ops = Offline.ops(s)
        compare(ops[0].state, Offline.State.FAILED)
        // Failed: a later stop cannot merge into it and waits as a patch.
        k.net = false
        call(function(cb) { t.stopTracking("u", "t", a.data.id, cb) })
        compare(Offline.pendingCount(s), 2)
        Offline.discard(s, ops[0].opId)
        compare(Offline.pendingCount(s), 0)
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
        call(function(cb) { Offline.replay(s, cb) })
        var op = Offline.ops(s)[0]
        compare(op.state, Offline.State.CONFLICT)
        compare(op.error.detail, "description")
        compare(op.server.description, "changed elsewhere")
        compare(k.server[1].end, stamp(10, 0), "not overwritten")
        call(function(cb) { Offline.overwrite(s, op.opId, cb) })
        compare(k.server[1].end, stamp(10, 30))
        compare(Offline.pendingCount(s), 0)
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
        call(function(cb) { Offline.replay(s, cb) })
        compare(Offline.pendingCount(s), 0, "already gone counts as done")
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
        compare(unknown.error.type, "offline")
    }

    function test_onlineOnlyRefusedOffline() {
        var k = fakeKimai()
        var s = session(k)
        var t = s.tracker
        k.net = false
        call(function(cb) { t.fetchActiveTimesheet("u", "t", cb) })
        k.calls = []
        var r = call(function(cb) { t.createProject("u", "t", { name: "x" }, cb) })
        compare(r.error.type, "offline")
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
        compare(Offline.pendingCount(s2), 1)
        var active = call(function(cb) { s2.tracker.fetchActiveTimesheet("u", "t", cb) })
        compare(active.data.length, 1)
        verify(Offline.isLocalId(active.data[0].id))
        k.net = true
        call(function(cb) { Offline.replay(s2, cb) })
        compare(Offline.pendingCount(s2), 0)
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
        call(function(cb) { Offline.replay(s, cb) })
        verify(!Offline.isOffline(s))
        // Online, but an op failed: a new write stays behind it (order).
        k.calls = []
        var r = call(function(cb) { t.createTimesheet("u", "t", { begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }, cb) })
        verify(r.queued)
        compare(Offline.pendingCount(s), 2)
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
        Offline.rememberFilmDays(s, { "2026-09-28": { timesheets: { at: 1, result: { ok: true, data: [] } } } })
        var s2 = session(k, fakeHost(h.files))
        var loaded = false
        Offline.load(s2).then(function() { loaded = true })
        tryVerify(function() { return loaded })
        verify(Offline.filmDays(s2)["2026-09-28"].timesheets.result.ok)
    }
}
