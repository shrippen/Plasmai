import QtQuick
import QtTest
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/providerUtil.js" as ProviderUtil
import "../../contents/code/workContractAdjust.js" as WorkAdjust

/**
 * Request bodies / paging of kimaiApi.js against a fake XMLHttpRequest.
 * Each queued response is { status, body, headers }; requests are recorded.
 */
TestCase {
    name: "KimaiRequests"

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

    function test_createTimesheetNeverSendsExported() {
        responses = [{ status: 200, body: { id: 5 } }]
        var got = null
        KimaiApi.createTimesheet("http://k", "t", {
            begin: "2026-09-20T08:00:00", end: "2026-09-20T09:00:00",
            project: 2, activity: 2, description: "x", tags: []
        }, function(r) { got = r })
        verify(got.ok)
        compare(requests[0].method, "POST")
        var body = bodyOf(0)
        verify(!body.hasOwnProperty("exported"))
        verify(!body.hasOwnProperty("billable"))
        compare(body.tags, "")
    }

    function test_startOmitsBeginAndBillable() {
        responses = [{ status: 200, body: { id: 6, begin: "2026-09-25T10:00:00+0000" } }]
        var got = null
        KimaiApi.startTracking("http://k", "t", 2, 3, "d", function(r) { got = r })
        verify(got.ok)
        var body = bodyOf(0)
        verify(!body.hasOwnProperty("begin"))
        verify(!body.hasOwnProperty("exported"))
        verify(!body.hasOwnProperty("billable"))
        compare(body.project, 2)
        compare(body.activity, 3)
    }

    function test_manualEntryStillNeedsBegin() {
        var got = null
        KimaiApi.createTimesheet("http://k", "t", { end: "2026-09-20T09:00:00", project: 2, activity: 2 },
                                 function(r) { got = r })
        verify(!got.ok)
        compare(requests.length, 0)
    }

    function extraFieldsBody() {
        return {
            code: 400, message: "Validation Failed",
            errors: {
                errors: ["This form should not contain extra fields."],
                children: { begin: {}, end: {}, project: {}, activity: {}, description: {}, tags: {} }
            }
        }
    }

    function test_billableRejectedIsRetriedWithoutIt() {
        responses = [{ status: 400, body: extraFieldsBody() }, { status: 200, body: { id: 7 } }]
        var got = null
        KimaiApi.patchTimesheet("http://k", "t", 7, { billable: false, tags: ["a"] }, function(r) { got = r })
        verify(got.ok)
        compare(requests.length, 2)
        compare(bodyOf(0).billable, false)
        verify(!bodyOf(1).hasOwnProperty("billable"))
        compare(bodyOf(1).tags, "a")
        compare(got.droppedFields, ["billable"])

        // Learned: the next write for this server/token drops billable up front.
        responses = [{ status: 200, body: { id: 8 } }]
        got = null
        KimaiApi.createTimesheet("http://k", "t", {
            begin: "2026-09-20T08:00:00", end: "2026-09-20T09:00:00",
            project: 2, activity: 2, billable: true
        }, function(r) { got = r })
        verify(got.ok)
        compare(requests.length, 3)
        verify(!bodyOf(2).hasOwnProperty("billable"))
        compare(got.droppedFields, ["billable"])
    }

    function test_otherValidationErrorsAreNotRetried() {
        var body = extraFieldsBody()
        body.errors.children.billable = {}
        responses = [{ status: 400, body: body }]
        var got = null
        KimaiApi.patchTimesheet("http://k", "t", 7, { billable: true }, function(r) { got = r })
        verify(!got.ok)
        compare(requests.length, 1)
        verify(got.error.detail.indexOf("extra fields") >= 0)
    }

    function test_restartCopiesAll() {
        responses = [{ status: 200, body: { id: 9 } }]
        var got = null
        KimaiApi.restartTimesheet("http://k", "t", 4, function(r) { got = r })
        verify(got.ok)
        compare(requests[0].url, "http://k/api/timesheets/4/restart")
        compare(bodyOf(0).copy, "all")
    }

    function test_catalogLoadsOnceWithoutPaging() {
        var list = []
        for (var i = 0; i < 600; i++) {
            list.push({ id: i + 1, name: "C" + i })
        }
        responses = [{ status: 200, body: list }]
        var got = null
        KimaiApi.loadCustomers("http://k", "t", function(r) { got = r })
        verify(got.ok)
        compare(got.data.length, 600)
        compare(requests.length, 1)
        compare(requests[0].url.indexOf("page="), -1)
        compare(requests[0].url.indexOf("size="), -1)
    }

    function test_timesheetRangeUsesTotalPages() {
        var page1 = []
        for (var i = 0; i < 100; i++) {
            page1.push({ id: i + 1 })
        }
        responses = [
            { status: 200, body: page1, headers: { "X-Total-Pages": "2" } },
            { status: 200, body: [{ id: 101 }], headers: { "X-Total-Pages": "2" } }
        ]
        var got = null
        KimaiApi.fetchTimesheetsRange("http://k", "t", new Date(2026, 8, 21), new Date(2026, 8, 27, 23, 59, 59),
                                      function(r) { got = r })
        verify(got.ok)
        compare(got.data.length, 101)
        compare(requests.length, 2)
    }

    function test_timesheetRangeStopsAtLastPageAndOn404() {
        var page1 = []
        for (var i = 0; i < 100; i++) {
            page1.push({ id: i + 1 })
        }
        // Exactly 100 entries: header says one page, so no second request.
        responses = [{ status: 200, body: page1, headers: { "X-Total-Pages": "1" } }]
        var got = null
        KimaiApi.fetchTimesheetsRange("http://k", "t", new Date(2026, 8, 21), new Date(2026, 8, 27),
                                      function(r) { got = r })
        verify(got.ok)
        compare(got.data.length, 100)
        compare(requests.length, 1)

        // Without the header, a 404 past the last page ends the range.
        requests = []
        responses = [{ status: 200, body: page1 }, { status: 404, body: { code: 404, message: "Not Found" } }]
        got = null
        KimaiApi.fetchTimesheetsRange("http://k", "t", new Date(2026, 8, 21), new Date(2026, 8, 27),
                                      function(r) { got = r })
        verify(got.ok)
        compare(got.data.length, 100)
        compare(requests.length, 2)
    }

    function test_timesheetRangeFirstPageErrorFails() {
        responses = [{ status: 404, body: { code: 404 } }]
        var got = null
        KimaiApi.fetchTimesheetsRange("http://k", "t", new Date(2026, 8, 21), new Date(2026, 8, 27),
                                      function(r) { got = r })
        verify(!got.ok)
    }

    function test_hangingRequestTimesOut() {
        responses = []
        var got = null
        var calls = 0
        KimaiApi.fetchActiveTimesheet("http://k", "t", function(r) { got = r; calls++ })
        compare(got, null)
        verify(ProviderUtil.pendingRequestCount() >= 1)
        compare(ProviderUtil.abortStaleRequests(Date.now()), 0)
        compare(ProviderUtil.abortStaleRequests(Date.now() + ProviderUtil.REQUEST_TIMEOUT_MS + 1), 1)
        verify(requests[0].aborted)
        compare(calls, 1)
        verify(!got.ok)
        compare(got.error.status, 0)
        compare(got.error.detail, "Request timed out")
        compare(ProviderUtil.pendingRequestCount(), 0)
    }

    function test_pickersHideHiddenEntries() {
        var customers = [{ id: 1, name: "Visible", visible: true }, { id: 2, name: "Gone", visible: false }]
        var projects = [
            { id: 10, name: "P visible", customer: 1, visible: true },
            { id: 11, name: "P hidden", customer: 1, visible: false },
            { id: 12, name: "P of hidden customer", customer: 2, visible: true }
        ]
        var items = KimaiApi.projectPickerItems(projects, customers)
        compare(items.length, 1)
        compare(items[0].value.id, 10)

        var activities = [
            { id: 1, name: "A", project: null, visible: true },
            { id: 2, name: "B", project: null, visible: false },
            { id: 3, name: "C", project: 10 }
        ]
        var acts = KimaiApi.activityPickerItems(activities, 10, projects[0], {})
        compare(acts.length, 2)
    }

    function test_absenceDurationSecondsVsHours() {
        compare(WorkAdjust.durationToSeconds(4), 4 * 3600)
        compare(WorkAdjust.durationToSeconds(24), 24 * 3600)
        compare(WorkAdjust.durationToSeconds(900), 900)
        compare(WorkAdjust.durationToSeconds(8 * 3600), 8 * 3600)
    }

    function test_dayIntervalsWallClock() {
        var day = new Date(2026, 8, 25, 12, 0, 0)
        var entries = [{ begin: "2026-09-25T09:00:00", end: "2026-09-25T10:30:15" }]
        var iv = KimaiApi.dayIntervalsFromTimesheets(entries, day, day.getTime())
        compare(iv.length, 1)
        compare(iv[0].startSec, 9 * 3600)
        compare(iv[0].endSec, 10 * 3600 + 30 * 60 + 15)
    }

    // ── Plugin detection + Drehzettel API ──

    function pingBody() {
        return { installed: true, pluginVersion: "0.1.0", apiVersions: ["v1"],
                 permissions: { view: true, manage: false },
                 features: ["errorCodes", "engagements", "defaults", "extraPay", "daySummary", "shootingDayNumber"] }
    }

    function test_detectPresentReturnsCacheEntry() {
        responses = [{ status: 200, body: pingBody() }]
        var got = null
        KimaiApi.detectDrehzettel("http://k/", "t", { cache: {}, key: "k1", nowMs: 1000 }, function(r) { got = r })
        compare(requests[0].url, "http://k/api/drehzettel/ping")
        compare(requests[0].headers["Authorization"], "Bearer t")
        compare(got.state, "present")
        verify(!got.fromCache)
        compare(got.cacheEntry.state, "present")
        compare(got.cacheEntry.at, 1000)
        verify(KimaiApi.drehzettelHasFeature(got.data, "daySummary"))
        verify(KimaiApi.drehzettelCanView(got.data))
    }

    function test_detectWithoutV1IsAbsent() {
        responses = [{ status: 200, body: { installed: true, apiVersions: ["v2"] } }]
        var got = null
        KimaiApi.detectDrehzettel("http://k", "t", {}, function(r) { got = r })
        compare(got.state, "absent")
        compare(got.cacheEntry.data, null)
    }

    function test_detect404IsAbsent403Forbidden() {
        responses = [{ status: 404, body: { code: 404, message: "Not Found" } },
                     { status: 403, body: { code: 403, message: "Forbidden" } }]
        var a = null, b = null
        KimaiApi.detectDrehzettel("http://k", "t", {}, function(r) { a = r })
        KimaiApi.detectDrehzettel("http://k", "t", {}, function(r) { b = r })
        compare(a.state, "absent")
        compare(b.state, "forbidden")
        verify(b.cacheEntry !== null)
    }

    function test_detectUsesFreshCacheWithoutRequest() {
        var cache = KimaiApi.storePluginCache({}, "k1", { state: "present", at: 1000, data: pingBody() })
        var got = null
        KimaiApi.detectDrehzettel("http://k", "t", { cache: cache, key: "k1", nowMs: 2000 }, function(r) { got = r })
        compare(requests.length, 0)
        compare(got.state, "present")
        verify(got.fromCache)
        compare(got.cacheEntry, null)
    }

    function test_detectStaleCacheReprobes() {
        var cache = { k1: { state: "present", at: 0, data: pingBody() } }
        responses = [{ status: 404, body: {} }]
        var got = null
        KimaiApi.detectDrehzettel("http://k", "t",
            { cache: cache, key: "k1", nowMs: KimaiApi.PLUGIN_PROBE_TTL_MS + 1 }, function(r) { got = r })
        compare(requests.length, 1)
        compare(got.state, "absent")
        compare(got.cacheEntry.state, "absent")
    }

    function test_detectOfflineKeepsCachedState() {
        // Stale cache + network error: stay in server mode, do not flip to local.
        var cache = { k1: { state: "present", at: 0, data: pingBody() } }
        responses = [{ status: 0 }, { status: 503, body: {} }]
        var got = null
        KimaiApi.detectDrehzettel("http://k", "t",
            { cache: cache, key: "k1", nowMs: KimaiApi.PLUGIN_PROBE_TTL_MS * 3 }, function(r) { got = r })
        compare(got.state, "present")
        verify(got.fromCache)
        compare(got.cacheEntry, null)
        var noCache = null
        KimaiApi.detectDrehzettel("http://k", "t", { cache: {}, key: "k1" }, function(r) { noCache = r })
        compare(noCache.state, "unknown")
        compare(noCache.cacheEntry, null)
    }

    function test_detectForceIgnoresFreshCache() {
        var cache = { k1: { state: "absent", at: 1000, data: null } }
        responses = [{ status: 200, body: pingBody() }]
        var got = null
        KimaiApi.detectDrehzettel("http://k", "t", { cache: cache, key: "k1", nowMs: 1001, force: true }, function(r) { got = r })
        compare(requests.length, 1)
        compare(got.state, "present")
    }

    function test_pluginCacheKeyAndParse() {
        compare(KimaiApi.pluginCacheKey("p1", "HTTPS://k/", "drehzettel"), "p1|https://k|drehzettel")
        compare(Object.keys(KimaiApi.parsePluginCache("[1]")).length, 0)
        compare(Object.keys(KimaiApi.parsePluginCache("nope")).length, 0)
        compare(KimaiApi.parsePluginCache('{"a":{"state":"absent","at":1}}').a.state, "absent")
    }

    function test_drehzettelCanViewFalse() {
        verify(!KimaiApi.drehzettelCanView({ permissions: { view: false } }))
        verify(KimaiApi.drehzettelCanView({ apiVersions: ["v1"] }))
    }

    function test_fetchFilmDayRequest() {
        responses = [{ status: 200, body: { date: "2026-09-14", breakMinutes: null } }]
        var got = null
        KimaiApi.fetchFilmDay("http://k", "t", 5, "2026-09-14", function(r) { got = r })
        compare(requests[0].method, "GET")
        compare(requests[0].url, "http://k/api/drehzettel/v1/film-days/2026-09-14?project=5")
        verify(requests[0].url.indexOf("user=") < 0)
        verify(got.ok)
        compare(got.data.breakMinutes, null)
    }

    function test_fetchFilmDayRejectsBadDate() {
        var got = null
        KimaiApi.fetchFilmDay("http://k", "t", 5, "14.09.2026", function(r) { got = r })
        compare(requests.length, 0)
        verify(!got.ok)
    }

    function test_putFilmDaySendsOnlyPatch() {
        responses = [{ status: 200, body: { date: "2026-09-14", note: "x", catering: true } }]
        var got = null
        KimaiApi.putFilmDay("http://k", "t", 5, "2026-09-14", { note: "x" }, function(r) { got = r })
        compare(requests[0].method, "PUT")
        compare(requests[0].headers["Content-Type"], "application/json")
        compare(requests[0].url, "http://k/api/drehzettel/v1/film-days/2026-09-14?project=5")
        compare(requests[0].body, '{"note":"x"}')
        verify(got.ok)
    }

    function test_drehzettelErrorCodes() {
        responses = [
            { status: 404, body: { error: "No active engagement for this project, user and date.", code: "no_engagement" } },
            { status: 403, body: { error: "Access denied.", code: "forbidden" } },
            { status: 400, body: { error: "note: at most 500 characters", code: "invalid_value" } },
            { status: 404, body: { code: 404, message: "Not Found" } }
        ]
        var r = []
        KimaiApi.fetchFilmDay("http://k", "t", 5, "2026-09-14", function(x) { r.push(x) })
        KimaiApi.fetchFilmDay("http://k", "t", 5, "2026-09-14", function(x) { r.push(x) })
        KimaiApi.putFilmDay("http://k", "t", 5, "2026-09-14", { note: "x" }, function(x) { r.push(x) })
        KimaiApi.fetchFilmDay("http://k", "t", 5, "2026-09-14", function(x) { r.push(x) })
        compare(r[0].error.status, 404)
        compare(r[0].error.code, "no_engagement")
        compare(r[1].error.type, "forbidden")
        compare(r[1].error.code, "forbidden")
        compare(r[2].error.status, 400)
        compare(r[2].error.code, "invalid_value")
        compare(r[2].error.detail, "note: at most 500 characters")
        compare(r[3].error.code, "")   // plain Kimai 404: no plugin code
    }

    function test_engagementEndpoints() {
        responses = [
            { status: 200, body: [{ engagementId: 1, projectId: 1, rulesetName: "TV-FFS 2025" }] },
            { status: 200, body: { active: false, engagementId: null, toggleDefault: false, rulesetName: null } },
            { status: 200, body: { hasEntry: false, payCents: null, currency: "EUR" } },
            { status: 200, body: {} }
        ]
        var r = []
        KimaiApi.fetchDrehzettelEngagements("http://k", "t", "2026-09-14", function(x) { r.push(x) })
        KimaiApi.fetchEngagementStatus("http://k", "t", 2, "2026-09-14", function(x) { r.push(x) })
        KimaiApi.fetchDaySummary("http://k", "t", 2, "2026-09-14", function(x) { r.push(x) })
        KimaiApi.fetchDrehzettelEngagements("http://k", "t", "2026-09-14", function(x) { r.push(x) })
        compare(requests[0].url, "http://k/api/drehzettel/v1/engagements?date=2026-09-14")
        compare(requests[1].url, "http://k/api/drehzettel/v1/engagement-status?project=2&date=2026-09-14")
        compare(requests[2].url, "http://k/api/drehzettel/v1/days/2026-09-14/summary?project=2")
        compare(r[0].data[0].rulesetName, "TV-FFS 2025")
        compare(r[1].data.active, false)
        compare(r[2].data.currency, "EUR")
        compare(r[3].data.length, 0)   // non-array answer normalized
    }

    function test_customerCurrencyOfProject() {
        compare(KimaiApi.customerCurrencyOfProject({ customer: 3 }, [{ id: 3, currency: "CHF" }]), "CHF")
        compare(KimaiApi.customerCurrencyOfProject({ customer: { id: 3, currency: "EUR" } }, []), "EUR")
        compare(KimaiApi.customerCurrencyOfProject({ customer: 4 }, [{ id: 3, currency: "CHF" }]), "")
        compare(KimaiApi.customerCurrencyOfProject(null, []), "")
    }
}
