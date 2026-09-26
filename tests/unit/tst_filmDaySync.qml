import QtQuick
import QtTest
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/filmDays.js" as FilmDays
import "../../contents/code/filmDaySync.js" as Sync

/**
 * filmDaySync.js (mode, load, two-step save; online only, nothing on the device)
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
                  mode: mode, ping: ping(), memo: {}, nowMs: 5000 }
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

    function test_resolveModeNoPluginNoPermissionOffline() {
        responses = [{ status: 404, body: {} },
                     { status: 200, body: { apiVersions: ["v1"], permissions: { view: false, manage: false } } },
                     { status: 0 }]
        var r = []
        Sync.resolveMode("http://k", "t", "a", {}, {}, function(x) { r.push(x) })
        Sync.resolveMode("http://k", "t", "b", {}, {}, function(x) { r.push(x) })
        Sync.resolveMode("http://k", "t", "c", {}, {}, function(x) { r.push(x) })
        compare(r[0].mode, "noPlugin")
        compare(r[1].mode, "noPermission")
        compare(r[2].mode, "offline")
        compare(r[2].probeCache, null)
    }

    function test_loadNoPluginSkipsRequest() {
        var got = null
        Sync.loadDay(ctx("noPlugin"), 3, "2026-09-14", function(r) { got = r })
        compare(requests.length, 0)
        compare(got.mode, "noPlugin")
        verify(!Sync.extrasVisible(got.mode))
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

    function test_loadOfflineHidesExtras() {
        var c = ctx("server", { ping: ping([]) })
        responses = [{ status: 200, body: serverDay({ note: "seen" }) },
                     { status: 200, body: { active: true, rulesetName: "R" } },
                     { status: 0 }]
        var first = null, second = null
        Sync.loadDay(c, 1, "2026-09-14", function(r) { first = r })
        Sync.loadDay(c, 1, "2026-09-14", function(r) { second = r })
        compare(first.mode, "server")
        compare(second.mode, "offline")
        // online only: nothing seen earlier is shown again
        compare(second.fields.note, "")
        compare(second.server, null)
        verify(second.error !== null)
        verify(!Sync.extrasVisible(second.mode))
        verify(!Sync.extrasEditable(second.mode))
    }

    function saveReq(fields, server, existingId) {
        return { projectId: 1, dateStr: "2026-09-14", existingId: existingId,
                 timesheetFields: { begin: "2026-09-14T09:00:00", end: "2026-09-14T18:00:00", project: 1, activity: 2 },
                 fields: fields, server: server, dayMode: Sync.Mode.SERVER }
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

    function test_saveTransientPutIsReported() {
        var server = serverDay()
        var fields = FilmDays.fromApi(server)
        fields.catering = "yes"
        responses = [{ status: 200, body: { id: 5 } }, { status: 0 }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(fields, server, 5), function(r) { got = r })
        verify(got.ok)
        compare(got.extras, "failed")
        verify(!got.hasOwnProperty("pendingMap"))
    }

    function test_save400IsReported() {
        var server = serverDay()
        var fields = FilmDays.fromApi(server)
        fields.breakMinutes = 30
        responses = [{ status: 200, body: { id: 5 } }, { status: 400, body: { error: "bad", code: "invalid_value" } }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(fields, server, 5), function(r) { got = r })
        compare(got.extras, "failed")
        compare(got.error.code, "invalid_value")
    }

    function test_saveNoEngagementSkipsExtras() {
        responses = [{ status: 200, body: { id: 5 } }]
        var fields = FilmDays.entryDefaults()
        fields.breakMinutes = 30
        var req = saveReq(fields, null, 5)
        req.dayMode = Sync.Mode.NO_ENGAGEMENT
        var got = null
        Sync.saveDay(ctx("server"), req, function(r) { got = r })
        compare(requests.length, 1)
        compare(got.ok, true)
        compare(got.extras, "skipped")
    }

    function test_saveNoPluginSkipsExtras() {
        responses = [{ status: 200, body: { id: 5 } }]
        var fields = FilmDays.entryDefaults()
        fields.note = "lokal"
        var req = saveReq(fields, null, 5)
        req.dayMode = Sync.Mode.NO_PLUGIN
        var got = null
        Sync.saveDay(ctx("noPlugin"), req, function(r) { got = r })
        compare(requests.length, 1)
        compare(got.extras, "skipped")
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

    function test_saveOldPluginNeverSendsExtraPay() {
        var server = serverDay()
        delete server.extraPayCents
        var fields = FilmDays.fromApi(server)
        fields.extraPayCents = 1200
        responses = [{ status: 200, body: { id: 5 } }]
        var got = null
        Sync.saveDay(ctx("server"), saveReq(fields, server, 5), function(r) { got = r })
        compare(requests.length, 1)
        compare(got.extras, "unchanged")
    }
}
