import QtQuick
import "../../contents/code/offline.js" as Offline
import "../../contents/code/dateTimeFormat.js" as DTF
import "../../contents/code/localFile.js" as LocalFile

/** Fakes for the offline tests: a Kimai that answers at once and a host with files in memory. */
QtObject {
    // 2026-09-28 12:00 local
    readonly property double t0: new Date(2026, 8, 28, 12, 0).getTime()

    function stamp(h, m) {
        // What the layer writes: the device time with its offset (see DTF.localDateTimeString).
        return DTF.localDateTimeString(new Date(2026, 8, 28, h, m))
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
        // Trips (kimai-anfahrten)
        k.trips = {}
        k.nextTrip = 500
        k.fetchTrips = function(u, t, range, cb) {
            answer("trips", cb, function() {
                var out = []
                for (var id in k.trips) out.push(JSON.parse(JSON.stringify(k.trips[id])))
                return { ok: true, data: out }
            })
        }
        k.createTrip = function(u, t, body, cb) {
            answer("createTrip", cb, function() {
                var trip = JSON.parse(JSON.stringify(body)); trip.id = k.nextTrip++; k.trips[trip.id] = trip
                return { ok: true, data: trip }
            })
        }
        k.patchTrip = function(u, t, id, body, cb) {
            answer("patchTrip " + id, cb, function() {
                for (var key in body) k.trips[id][key] = body[key]
                return { ok: true, data: k.trips[id] }
            })
        }
        k.deleteTrip = function(u, t, id, cb) {
            answer("deleteTrip " + id, cb, function() { delete k.trips[id]; return { ok: true, data: null } })
        }
        k.acceptTripSuggestion = function(u, t, id, body, cb) {
            answer("accept", cb, function() { return { ok: true, data: {} } })
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
            // name → status the file reads with instead of its content (unreadable, broken)
            readAs: {},
            // a function: load answers only when it is called (a slow disk)
            holdLoad: null,
            saves: [],
            failSave: false,
            currentUrl: "https://kimai.test",
            url: function() { return h.currentUrl },
            token: function() { return "tok" },
            load: function(name) {
                if (h.holdLoad && name.indexOf("offline-outbox-") === 0) {
                    return new Promise(function(resolve) {
                        h.release = function() {
                            h.holdLoad = null
                            resolve(h.load(name))
                        }
                    })
                }
                if (h.readAs[name]) {
                    return Promise.resolve({ status: h.readAs[name], data: null })
                }
                return Promise.resolve(h.files[name]
                    ? { status: LocalFile.Status.OK, data: JSON.parse(h.files[name]) }
                    : { status: LocalFile.Status.MISSING, data: null })
            },
            save: function(name, obj) {
                h.saves.push(name)
                if (h.failSave) {
                    return Promise.reject("disk full")
                }
                h.files[name] = JSON.stringify(obj)
                return Promise.resolve(true)
            },
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
}
