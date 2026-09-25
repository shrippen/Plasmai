import QtQuick
import QtTest
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/filmDays.js" as FilmDays
import "../../contents/code/filmDaySync.js" as Sync

/**
 * filmDaySync.js (mode, load, two-step save, pending queue, migration)
 * against a fake XMLHttpRequest. Responses are consumed in request order.
 */
TestCase {
    name: "FilmDaySync"

    property var requests: []
    property var responses: []

    function fakeXhr() {
        var xhr = {
            readyState: 0,
            status: 0,
            statusText: "",
            responseText: "",
            method: "",
            url: "",
            body: undefined,
            headers: {},
            responseHeaders: {},
            aborted: false,
            onreadystatechange: null,
            onerror: null,
            open: function(method, url) {
                xhr.method = method
                xhr.url = url
            },
            setRequestHeader: function(name, value) {
                xhr.headers[name] = value
            },
            getResponseHeader: function(name) {
                var v = xhr.responseHeaders[name]
                return v === undefined ? null : v
            },
            abort: function() {
                xhr.aborted = true
                xhr.readyState = 4
                xhr.status = 0
                if (xhr.onreadystatechange) {
                    xhr.onreadystatechange()
                }
            },
            send: function(body) {
                xhr.body = body
                requests.push(xhr)
                var next = responses.shift()
                if (!next) {
                    return // never answers (timeout test)
                }
                xhr.status = next.status
                xhr.responseText = next.body === undefined ? "" : JSON.stringify(next.body)
                xhr.responseHeaders = next.headers || {}
                xhr.readyState = 4
                xhr.onreadystatechange()
            }
        }
        return xhr
    }

    function init() {
        requests = []
        responses = []
        KimaiApi.resetDeniedWriteFields()
        KimaiApi.setRequestFactory(fakeXhr)
    }

    function cleanup() {
        KimaiApi.setRequestFactory(null)
    }

    function bodyOf(i) {
        return JSON.parse(requests[i].body)
    }

    function serverDay(o) {
        var d = { date: "2026-09-14", engagementId: 1, breakMinutes: null, catering: false,
                  category: null, note: null, dayType: "workday", productionDay: null,
                  extraPayCents: 0, shootingDayNumber: null, defaultBreakMinutes: 45,
                  effectiveCategory: "workday" }
        for (var k in (o || {})) d[k] = o[k]
        return d
    }

    function ping(features) {
        return { installed: true, apiVersions: ["v1"], permissions: { view: true, manage: false },
                 features: features || ["errorCodes", "engagements", "defaults", "extraPay", "daySummary", "shootingDayNumber"] }
    }

    function ctx(mode, extra) {
        var c = { url: "http://k", token: "t", profileKey: Sync.profileKey("p1", "http://k"),
                  mode: mode, ping: ping(), localMap: {}, pendingMap: {}, memo: {}, nowMs: 5000 }
        for (var k in (extra || {})) c[k] = extra[k]
        return c
    }

    function test_resolveModeServerAndCache() {
        responses = [{ status: 200, body: ping() }]
        var got = null
        Sync.resolveMode("http://k", "t", "p1", {}, { nowMs: 10 }, function(r) { got = r })
        compare(got.mode, "server")
        verify(got.probeCache !== null)
        compare(got.probeCache["p1|http://k|drehzettel"].state, "present")
        // second call served from the cache, no request
        var again = null
        Sync.resolveMode("http://k", "t", "p1", got.probeCache, { nowMs: 20 }, function(r) { again = r })
        compare(requests.length, 1)
        compare(again.mode, "server")
        compare(again.probeCache, null)
    }

    function test_resolveModeLocalNoPermissionOffline() {
        responses = [{ status: 404, body: {} },
                     { status: 200, body: { apiVersions: ["v1"], permissions: { view: false, manage: false } } },
                     { status: 0 }]
        var r = []
        Sync.resolveMode("http://k", "t", "a", {}, {}, function(x) { r.push(x) })
        Sync.resolveMode("http://k", "t", "b", {}, {}, function(x) { r.push(x) })
        Sync.resolveMode("http://k", "t", "c", {}, {}, function(x) { r.push(x) })
        compare(r[0].mode, "local")
        compare(r[1].mode, "noPermission")
        compare(r[2].mode, "offline")
        compare(r[2].probeCache, null)
    }

    function test_loadLocal() {
        var c = ctx("local", { localMap: FilmDays.set({}, 3, "2026-09-14", { breakMinutes: 20, catering: "yes" }) })
        var got = null
        Sync.loadDay(c, 3, "2026-09-14", function(r) { got = r })
        compare(requests.length, 0)
        compare(got.mode, "local")
        compare(got.fields.breakMinutes, 20)
        compare(got.fields.catering, "yes")
    }

    function test_loadServerWithRulesetAndSummary() {
        responses = [
            { status: 200, body: serverDay({ breakMinutes: 30, shootingDayNumber: 37 }) },
            { status: 200, body: [{ engagementId: 1, projectId: 1, rulesetName: "TV-FFS" }] },
            { status: 200, body: { payCents: 41000, currency: "EUR" } }
        ]
        var got = null
        Sync.loadDay(ctx("server"), 1, "2026-09-14", function(r) { got = r })
        compare(got.mode, "server")
        compare(got.fields.breakMinutes, 30)
        compare(got.fields.productionDay, 37)
        compare(got.defaultBreakMinutes, 45)
        compare(got.rulesetName, "TV-FFS")
        compare(got.summary.payCents, 41000)
        verify(got.server !== null)
    }

    function test_loadEngagementListCached() {
        var c = ctx("server", { ping: ping(["engagements"]) })
        responses = [
            { status: 200, body: serverDay() },
            { status: 200, body: [{ projectId: 1, rulesetName: "R" }] },
            { status: 200, body: serverDay() }
        ]
        var a = null, b = null
        Sync.loadDay(c, 1, "2026-09-14", function(r) { a = r })
        Sync.loadDay(c, 1, "2026-09-14", function(r) { b = r })
        compare(requests.length, 3)
        compare(b.rulesetName, "R")
    }

    function test_loadOldPluginUsesEngagementStatus() {
        var c = ctx("server", { ping: { apiVersions: ["v1"] } })
        responses = [
            { status: 200, body: serverDay() },
            { status: 200, body: { active: true, engagementId: 1, rulesetName: "Old" } }
        ]
        var got = null
        Sync.loadDay(c, 1, "2026-09-14", function(r) { got = r })
        verify(requests[1].url.indexOf("/engagement-status?project=1") > 0)
        compare(got.rulesetName, "Old")
    }

    function test_loadNoEngagementAndForbidden() {
        responses = [{ status: 404, body: { error: "x", code: "no_engagement" } },
                     { status: 403, body: { error: "x", code: "forbidden" } }]
        var r = []
        Sync.loadDay(ctx("server"), 2, "2026-09-14", function(x) { r.push(x) })
        Sync.loadDay(ctx("server"), 2, "2026-09-14", function(x) { r.push(x) })
        compare(r[0].mode, "noEngagement")
        compare(r[1].mode, "noPermission")
    }

    function test_loadWithoutProject() {
        var got = null
        Sync.loadDay(ctx("server"), null, "2026-09-14", function(r) { got = r })
        compare(requests.length, 0)
        compare(got.mode, "noProject")
    }

    function test_loadOfflineShowsLastSeen() {
        var c = ctx("server", { ping: ping([]) })
        responses = [{ status: 200, body: serverDay({ note: "seen" }) },
                     { status: 200, body: { active: true, rulesetName: "R" } },
                     { status: 0 }]
        var first = null, second = null
        Sync.loadDay(c, 1, "2026-09-14", function(r) { first = r })
        Sync.loadDay(c, 1, "2026-09-14", function(r) { second = r })
        compare(first.mode, "server")
        compare(second.mode, "offline")
        compare(second.fields.note, "seen")
        verify(!Sync.extrasEditable(second.mode))
        verify(Sync.extrasVisible(second.mode))
    }

    function test_loadShowsQueuedPatch() {
        var c = ctx("server", { ping: ping([]) })
        c.pendingMap[Sync.pendingKey(c.profileKey, 1, "2026-09-14")] = { patch: { note: "queued" }, base: { note: null } }
        responses = [{ status: 200, body: serverDay() }, { status: 200, body: { active: true } }]
        var got = null
        Sync.loadDay(c, 1, "2026-09-14", function(r) { got = r })
        verify(got.pending)
        compare(got.fields.note, "queued")
    }

    function saveReq(fields, server, existingId) {
        return { projectId: 1, dateStr: "2026-09-14", existingId: existingId,
                 timesheetFields: { begin: "2026-09-14T09:00:00", end: "2026-09-14T18:00:00", project: 1, activity: 2 },
                 fields: fields, server: server }
    }

    function test_saveServerTwoStepOnlyChangedKeys() {
        var server = serverDay({ catering: true })
        var fields = FilmDays.fromApi(server)
        fields.note = "Nacht"
        responses = [{ status: 200, body: { id: 77 } }, { status: 200, body: serverDay({ catering: true, note: "Nacht" }) }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(fields, server, 77), function(r) { got = r })
        compare(requests[0].method, "PATCH")
        compare(requests[0].url, "http://k/api/timesheets/77")
        compare(requests[1].method, "PUT")
        compare(JSON.parse(requests[1].body).note, "Nacht")
        compare(Object.keys(JSON.parse(requests[1].body)).length, 1)
        verify(got.ok)
        compare(got.extras, "saved")
        compare(got.server.note, "Nacht")
        compare(got.localMap, null)
    }

    function test_saveUnchangedSkipsPut() {
        var server = serverDay()
        responses = [{ status: 200, body: { id: 5 } }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(FilmDays.fromApi(server), server, null), function(r) { got = r })
        compare(requests.length, 1)
        compare(requests[0].method, "POST")
        compare(got.extras, "unchanged")
    }

    function test_saveTimesheetFailureStopsBeforePut() {
        responses = [{ status: 500, body: {} }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(FilmDays.entryDefaults(), serverDay(), 5), function(r) { got = r })
        compare(requests.length, 1)
        verify(!got.ok)
        compare(got.stage, "timesheet")
    }

    function test_saveTransientPutIsQueued() {
        var server = serverDay()
        var fields = FilmDays.fromApi(server)
        fields.catering = "yes"
        responses = [{ status: 200, body: { id: 5 } }, { status: 0 }]
        var c = ctx("server")
        var got = null
        Sync.saveDay(c, saveReq(fields, server, 5), function(r) { got = r })
        verify(got.ok)
        compare(got.extras, "queued")
        var q = got.pendingMap[Sync.pendingKey(c.profileKey, 1, "2026-09-14")]
        compare(q.patch.catering, true)
        compare(q.base.catering, false)
        compare(Sync.countPending(got.pendingMap, c.profileKey), 1)
        compare(Sync.countPending(got.pendingMap, "other"), 0)
    }

    function test_save400IsRejectedNotQueued() {
        var server = serverDay()
        var fields = FilmDays.fromApi(server)
        fields.breakMinutes = 30
        responses = [{ status: 200, body: { id: 5 } }, { status: 400, body: { error: "bad", code: "invalid_value" } }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(fields, server, 5), function(r) { got = r })
        compare(got.extras, "rejected")
        compare(got.error.code, "invalid_value")
        compare(got.pendingMap, null)
    }

    function test_saveLocalMode() {
        responses = [{ status: 200, body: { id: 5 } }]
        var fields = FilmDays.entryDefaults()
        fields.note = "lokal"
        var got = null
        var c = ctx("local")
        Sync.saveDay(c, saveReq(fields, null, 5), function(r) { got = r })
        compare(requests.length, 1)
        compare(got.extras, "local")
        compare(FilmDays.get(got.localMap, 1, "2026-09-14", c.profileKey).note, "lokal")
        // B8: stored under profile + server, not under the bare project id
        verify(got.localMap["p1|http://k|1|2026-09-14"] !== undefined)
        verify(got.localMap["1|2026-09-14"] === undefined)
        compare(FilmDays.get(got.localMap, 1, "2026-09-14", Sync.profileKey("p2", "http://other")).note, "")
    }

    function test_loadLocalPrefersOwnOverLegacy() {
        var legacy = FilmDays.entryDefaults()
        legacy.note = "legacy"
        var own = FilmDays.entryDefaults()
        own.note = "own"
        var map = FilmDays.set({}, 3, "2026-09-14", legacy)
        var c = ctx("local", { localMap: map })
        var got = null
        Sync.loadDay(c, 3, "2026-09-14", function(r) { got = r })
        compare(got.fields.note, "legacy")
        c.localMap = FilmDays.set(map, 3, "2026-09-14", own, c.profileKey)
        Sync.loadDay(c, 3, "2026-09-14", function(r) { got = r })
        compare(got.fields.note, "own")
        // the legacy entry stays for other profiles
        compare(c.localMap["3|2026-09-14"].note, "legacy")
    }

    function test_deleteEntriesReportsFailures() {
        responses = [{ status: 204 }, { status: 403, body: { code: 403, message: "Access denied." } }, { status: 200 }]
        var got = null
        Sync.deleteEntries(ctx("server"), [7, 8, 9], function(r) { got = r })
        compare(requests.length, 3)
        compare(requests[0].method, "DELETE")
        compare(requests[0].url, "http://k/api/timesheets/7")
        compare(got.deleted, 2)
        compare(got.failed.length, 1)
        compare(got.failed[0].id, 8)
        compare(got.failed[0].error.status, 403)
    }

    function test_saveOldPluginKeepsExtraPayLocal() {
        var server = serverDay()
        delete server.extraPayCents
        var fields = FilmDays.fromApi(server)
        fields.extraPayCents = 1200
        responses = [{ status: 200, body: { id: 5 } }]
        var got = null
        var c = ctx("server")
        Sync.saveDay(c, saveReq(fields, server, 5), function(r) { got = r })
        compare(requests.length, 1)
        compare(got.extras, "unchanged")
        compare(FilmDays.get(got.localMap, 1, "2026-09-14", c.profileKey).extraPayCents, 1200)
    }

    function test_flushPendingSendsWhenBaseUnchanged() {
        var c = ctx("server")
        c.pendingMap[Sync.pendingKey(c.profileKey, 1, "2026-09-14")] = { patch: { catering: true }, base: { catering: false } }
        c.pendingMap[Sync.pendingKey(c.profileKey, 1, "2026-09-15")] = { patch: { note: "mine" }, base: { note: null } }
        c.pendingMap["other|http://x|1|2026-09-14"] = { patch: { note: "x" }, base: { note: null } }
        responses = [
            { status: 200, body: serverDay() },                          // 14th: unchanged → PUT
            { status: 200, body: serverDay({ catering: true }) },
            { status: 200, body: serverDay({ note: "theirs" }) }         // 15th: changed → server wins
        ]
        var got = null
        Sync.flushPending(c, function(r) { got = r })
        compare(requests.length, 3)
        compare(requests[1].method, "PUT")
        compare(requests[1].body, '{"catering":true}')
        compare(got.sent, 1)
        compare(got.dropped, 1)
        compare(got.kept, 0)
        verify(got.pendingMap["other|http://x|1|2026-09-14"] !== undefined)
    }

    function test_flushPendingStopsWhenOffline() {
        var c = ctx("server")
        c.pendingMap[Sync.pendingKey(c.profileKey, 1, "2026-09-14")] = { patch: { catering: true }, base: { catering: false } }
        responses = [{ status: 0 }]
        var got = null
        Sync.flushPending(c, function(r) { got = r })
        compare(got.kept, 1)
        compare(got.pendingMap, null)
    }

    function test_migrateRules() {
        var map = {}
        var e = FilmDays.entryDefaults()
        e.catering = "yes"
        map = FilmDays.set(map, 1, "2026-09-01", e)   // server empty → push
        map = FilmDays.set(map, 1, "2026-09-02", e)   // server equal → same
        map = FilmDays.set(map, 1, "2026-09-03", e)   // server differs → conflict
        map = FilmDays.set(map, 2, "2026-09-01", e)   // no engagement
        var c = ctx("server", { localMap: map })
        var plan = Sync.migrationCandidates(c, [1, 2])
        compare(plan.length, 4)
        responses = [
            { status: 200, body: serverDay() },                                  // 1|09-01 GET
            { status: 200, body: serverDay({ breakMinutes: 45, catering: true }) }, // 1|09-01 PUT
            { status: 404, body: { error: "x", code: "no_engagement" } },         // 2|09-01
            { status: 200, body: serverDay({ breakMinutes: 45, catering: true }) }, // 1|09-02
            { status: 200, body: serverDay({ breakMinutes: 30 }) }                 // 1|09-03
        ]
        var got = null
        Sync.migrate(c, plan, function(r) { got = r })
        compare(requests[1].method, "PUT")
        compare(JSON.parse(requests[1].body).breakMinutes, 45)
        compare(got.pushed, 1)
        compare(got.same, 1)
        compare(got.conflicts.length, 1)
        compare(got.conflicts[0].date, "2026-09-03")
        compare(got.noEngagement, 1)
        verify(!got.stopped)
        c.localMap = got.localMap
        compare(Sync.migrationCandidates(c, [1, 2]).length, 0)
        // local values are kept
        compare(FilmDays.get(got.localMap, 1, "2026-09-03").catering, "yes")
    }

    function test_migrateStopsOfflineAndResumes() {
        var map = FilmDays.set({}, 1, "2026-09-01", FilmDays.entryDefaults())
        map = FilmDays.set(map, 1, "2026-09-02", FilmDays.entryDefaults())
        var c = ctx("server", { localMap: map })
        responses = [{ status: 200, body: serverDay({ breakMinutes: 45 }) }, { status: 0 }]
        var got = null
        Sync.migrate(c, Sync.migrationCandidates(c, [1]), function(r) { got = r })
        verify(got.stopped)
        compare(got.same, 1)
        c.localMap = got.localMap
        compare(Sync.migrationCandidates(c, [1]).length, 1)
    }

    // ── P6 conflict review ──

    function conflictMap() {
        var e = FilmDays.entryDefaults()
        e.catering = "yes"
        e.note = "lokal"
        var map = FilmDays.set({}, 1, "2026-09-03", e)
        map = FilmDays.set(map, 1, "2026-09-04", e)
        map = FilmDays.set(map, 1, "2026-09-05", e)
        var pk = Sync.profileKey("p1", "http://k")
        map = FilmDays.markMigrated(map, "1|2026-09-03", pk, "conflict", "x")
        map = FilmDays.markMigrated(map, "1|2026-09-04", pk, "conflict", "x")
        map = FilmDays.markMigrated(map, "1|2026-09-05", pk, "pushed", "x")
        map = FilmDays.markMigrated(map, "1|2026-09-05", "other|http://x", "conflict", "x")
        return map
    }

    function test_conflictCandidatesPerProfile() {
        var c = ctx("server", { localMap: conflictMap() })
        var list = Sync.conflictCandidates(c)
        compare(list.length, 2)
        compare(list[0].date, "2026-09-03")
        compare(String(list[0].projectId), "1")
        compare(list[0].entry.note, "lokal")
        compare(Sync.countConflicts(ctx("server", { localMap: conflictMap(), profileKey: "other|http://x" })), 1)
    }

    function test_loadConflictsDiffAndSame() {
        var c = ctx("server", { localMap: conflictMap() })
        responses = [
            { status: 200, body: serverDay({ breakMinutes: 30, note: "server" }) },            // 09-03 differs
            { status: 200, body: serverDay({ breakMinutes: 45, catering: true, note: "lokal" }) } // 09-04 equal now
        ]
        var got = null
        Sync.loadConflicts(c, Sync.conflictCandidates(c), function(r) { got = r })
        compare(got.items.length, 2)
        compare(got.items[0].state, "ready")
        var fields = got.items[0].diff.map(function(d) { return d.field })
        compare(fields.join(","), "breakMinutes,catering,note")
        compare(got.items[0].diff[0].local, 45)
        compare(got.items[0].diff[0].server, 30)
        compare(got.items[1].state, "same")
        verify(got.localMap !== null)
        c.localMap = got.localMap
        compare(Sync.countConflicts(c), 1)
    }

    function test_resolveConflictKeepServer() {
        var c = ctx("server", { localMap: conflictMap() })
        var item = Sync.conflictCandidates(c)[0]
        var got = null
        Sync.resolveConflict(c, item, false, function(r) { got = r })
        compare(requests.length, 0)
        verify(got.ok)
        compare(got.localMap["1|2026-09-03"].migrated[c.profileKey].result, "resolvedServer")
        compare(got.localMap["1|2026-09-03"].note, "lokal")   // local copy stays
    }

    function test_resolveConflictUseLocalSendsDiffAgainstFreshServer() {
        var c = ctx("server", { localMap: conflictMap() })
        var item = Sync.conflictCandidates(c)[0]
        responses = [
            { status: 200, body: serverDay({ breakMinutes: 45, catering: false, note: "neu" }) },
            { status: 200, body: serverDay({ breakMinutes: 45, catering: true, note: "lokal" }) }
        ]
        var got = null
        Sync.resolveConflict(c, item, true, function(r) { got = r })
        compare(requests[1].method, "PUT")
        compare(requests[1].body, '{"catering":true,"note":"lokal"}')
        verify(got.ok)
        compare(got.localMap["1|2026-09-03"].migrated[c.profileKey].result, "resolvedLocal")
        c.localMap = got.localMap
        compare(Sync.countConflicts(c), 1)
    }

    function test_resolveConflictUseLocalFailureKeepsOpen() {
        var c = ctx("server", { localMap: conflictMap() })
        var item = Sync.conflictCandidates(c)[0]
        responses = [{ status: 200, body: serverDay() }, { status: 400, body: { error: "note: too long", code: "invalid_value" } }]
        var got = null
        Sync.resolveConflict(c, item, true, function(r) { got = r })
        verify(!got.ok)
        compare(got.localMap, null)
        compare(got.error.detail, "note: too long")
    }
}
