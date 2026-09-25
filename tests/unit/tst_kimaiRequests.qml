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
}
