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

    readonly property var ids: ({
        projectOf: function(ts) { return ts.project },
        activityOf: function(ts) { return ts.activity }
    })

    // One engagement per day: its project is the day's film-day project.
    function test_dayEngagementProject() {
        responses = [{ status: 200, body: [{ engagementId: 1, projectId: 155, rulesetName: "" }] },
                     { status: 200, body: [] }]
        var a, b
        Sync.dayEngagementProject(ctx("server"), "2026-09-25", function(p) { a = p })
        Sync.dayEngagementProject(ctx("server"), "2026-09-26", function(p) { b = p })
        compare(a, 155)
        compare(b, null)
        var c = null
        Sync.dayEngagementProject(ctx("server", { ping: ping(["errorCodes"]) }), "2026-09-25", function(p) { c = p })
        compare(requests.length, 2)
        compare(c, null)
    }

    // A day with travel entries and another project: no project picked, the
    // engagement decides the project and the summary the entry.
    function test_resolveDayFollowsEngagementAndSummary() {
        var entries = [
            { id: 4246, project: 155, activity: 12, begin: "2026-09-25T21:31:00+0200", end: "2026-09-25T21:56:00+0200" },
            { id: 4245, project: 155, activity: 40, begin: "2026-09-25T13:15:00+0200", end: "2026-09-25T21:30:00+0200" },
            { id: 4244, project: 155, activity: 12, begin: "2026-09-25T12:15:00+0200", end: "2026-09-25T12:45:00+0200" },
            { id: 4243, project: 153, activity: 7, begin: "2026-09-25T09:59:00+0200", end: "2026-09-25T11:22:36+0200" }
        ]
        responses = [
            { status: 200, body: [{ engagementId: 1, projectId: 155, rulesetName: "" }] },
            { status: 200, body: serverDay({ date: "2026-09-25", catering: true }) },
            { status: 200, body: { hasEntry: true, begin: "2026-09-25T13:15:00+02:00", end: "2026-09-25T21:30:00+02:00", payCents: 25500 } }
        ]
        var got = null
        Sync.resolveDay(ctx("server"), entries, null, "2026-09-25", ids, function(r) { got = r })
        compare(requests.length, 3)
        compare(got.projectId, 155)
        compare(got.match.id, 4245)
        // the travel entries are another activity, no duplicate film day
        compare(got.others.length, 0)
        compare(got.day.mode, "server")
        compare(got.day.fields.catering, "yes")
    }

    // No engagement on the day: the picked project stays.
    function test_resolveDayKeepsPickedProjectWithoutEngagement() {
        var entries = [{ id: 1, project: 7, begin: "2026-09-26T09:00:00+0200", end: "2026-09-26T10:00:00+0200" }]
        responses = [{ status: 200, body: [] },
                     { status: 404, body: { error: "x", code: "no_engagement" } }]
        var got = null
        Sync.resolveDay(ctx("server"), entries, 7, "2026-09-26", ids, function(r) { got = r })
        compare(got.projectId, 7)
        compare(got.match.id, 1)
        compare(got.day.mode, "noEngagement")
    }

    // resolveDay hands the day's engagements and the one in use to the view;
    // a picked project wins when asked to (the engagement chooser).
    function test_resolveDayEngagements() {
        var entries = [{ id: 1, project: 7, activity: 3, begin: "2026-09-26T09:00:00+0200", end: "2026-09-26T10:00:00+0200" }]
        responses = [
            { status: 200, body: [{ engagementId: 1, projectId: 155, crewRole: "1. Kameraassistenz" },
                                  { engagementId: 2, projectId: 7, crewRole: "Kamera" }] },
            { status: 200, body: serverDay({ date: "2026-09-26", engagementId: 2 }) },
            { status: 200, body: { hasEntry: true, begin: "2026-09-26T09:00:00+02:00", end: "2026-09-26T10:00:00+02:00" } }
        ]
        var got = null
        Sync.resolveDay(ctx("server"), entries, 7, "2026-09-26", ids, function(r) { got = r }, true)
        compare(got.projectId, 7)
        compare(got.engagements.length, 2)
        compare(got.engagement.crewRole, "Kamera")
        compare(got.match.id, 1)
    }

    // Production shooting day and the film activity from the engagement's
    // entries (project filter, from the engagement's start to the day).
    function test_productionDay() {
        responses = [{ status: 200, body: [
            { id: 1, project: 155, activity: 40, begin: "2026-09-10T08:00:00+0200", end: "2026-09-10T18:00:00+0200" },
            { id: 2, project: 155, activity: 12, begin: "2026-09-24T07:00:00+0200", end: "2026-09-24T07:30:00+0200" },
            { id: 3, project: 155, activity: 40, begin: "2026-09-24T11:50:00+0200", end: "2026-09-24T22:09:00+0200" },
            { id: 4, project: 155, activity: 40, begin: "2026-09-25T13:15:00+0200", end: "2026-09-25T21:30:00+0200" }] }]
        var got = null
        // no activity known yet: the longest entry's activity is the film activity
        Sync.productionDay(ctx("server"), 155, null, [], "2026-05-18", "2026-09-25", ids, function(r) { got = r })
        verify(requests[0].url.indexOf("project=155") > 0)
        verify(requests[0].url.indexOf("activity=") < 0)
        compare(got.activityId, 40)
        compare(got.count, 3)
        verify(got.includesDay)
    }

    // The engagement's whitelist decides the film activities: a day with only
    // a whitelisted activity counts, a commute-only day does not.
    function test_productionDayActivityWhitelist() {
        responses = [{ status: 200, body: [
            { id: 1, project: 155, activity: 12, begin: "2026-09-22T06:00:00+0200", end: "2026-09-22T18:00:00+0200" },
            { id: 2, project: 155, activity: 41, begin: "2026-09-23T08:00:00+0200", end: "2026-09-23T10:00:00+0200" },
            { id: 3, project: 155, activity: 40, begin: "2026-09-24T08:00:00+0200", end: "2026-09-24T12:00:00+0200" },
            { id: 4, project: 155, activity: 12, begin: "2026-09-25T06:00:00+0200", end: "2026-09-25T07:00:00+0200" }] }]
        var got = null
        Sync.productionDay(ctx("server"), 155, null, [40, 41], "2026-05-18", "2026-09-25", ids, function(r) { got = r })
        compare(got.count, 2)
        verify(!got.includesDay)
        compare(got.activityId, 40)
    }

    // Plugin whitelist: the film day spans all whitelisted entries (as the
    // plugin's begin and end), the longer commute of the same project is not it.
    function test_resolveDayActivityWhitelist() {
        var entries = [
            { id: 1, project: 155, activity: 12, begin: "2026-09-25T06:00:00+0200", end: "2026-09-25T09:30:00+0200" },
            { id: 2, project: 155, activity: 40, begin: "2026-09-25T09:30:00+0200", end: "2026-09-25T12:30:00+0200" },
            { id: 3, project: 155, activity: 41, begin: "2026-09-25T13:00:00+0200", end: "2026-09-25T15:00:00+0200" }
        ]
        responses = [
            { status: 200, body: [{ engagementId: 1, projectId: 155, activityIds: [40, 41] }] },
            { status: 200, body: serverDay({ date: "2026-09-25" }) },
            { status: 200, body: { hasEntry: true, begin: "2026-09-25T09:30:00+02:00", end: "2026-09-25T15:00:00+02:00" } }
        ]
        var got = null
        Sync.resolveDay(ctx("server"), entries, null, "2026-09-25", ids, function(r) { got = r })
        compare(got.match.id, 2)
        compare(got.others.map(function(e) { return e.id }), [3])
        compare(got.activityIds, [40, 41])
    }

    // Whitelist: any whitelisted activity running is the film day, a
    // non-whitelisted one (commute) is not; a single one is the suggestion.
    function test_viewInfoActivityWhitelist() {
        var shoot = { id: 9, project: 155, activity: 41, begin: "2026-09-26T07:42:00+0200", end: null }
        var v = Sync.viewInfo({ projectId: 155, match: null, others: [], activityIds: [40, 41] },
                              viewOpts({ entries: [shoot], active: shoot, daysFromToday: 0 }))
        compare(v.phase, "running")
        compare(v.activityId, 41)

        var commute = { id: 10, project: 155, activity: 12, begin: "2026-09-26T06:00:00+0200", end: null }
        v = Sync.viewInfo({ projectId: 155, match: null, others: [], activityIds: [40] },
                          viewOpts({ entries: [commute], active: commute, recent: [commute], daysFromToday: 0 }))
        compare(v.phase, "before")
        compare(v.activityId, 40)
    }

    // ── Day cache (openDay, prefetchDays) ──

    readonly property var shootDay: [
        { id: 7, project: 155, activity: 40, begin: "2026-09-25T08:00:00+0200", end: "2026-09-25T18:00:00+0200" }
    ]

    /** Live answers of one day open: timesheets, engagements, film day, summary. */
    function dayResponses(note) {
        return [
            { status: 200, body: shootDay },
            { status: 200, body: [{ engagementId: 1, projectId: 155, rulesetName: "R", validFrom: "2026-09-01" }] },
            { status: 200, body: serverDay({ date: "2026-09-25", note: note }) },
            { status: 200, body: { hasEntry: true, begin: "2026-09-25T08:00:00+02:00", end: "2026-09-25T18:00:00+02:00" } }
        ]
    }

    /** A ctx whose prefetch already ran (openDay tests see only the day's requests). */
    function cacheCtx() {
        var c = ctx("server")
        c.memo.prefetched = {}
        c.memo.prefetched[c.profileKey] = c.nowMs
        return c
    }

    function openDay(c, got) {
        Sync.openDay(c, new Date(2026, 8, 25), null, ids, function(raw) { return raw }, function(r, entries, source) {
            got.push({ r: r, entries: entries, source: source })
        })
    }

    // Uncached: one live render. Cached: at once from the cache, the equal
    // live answer does not render again.
    function test_openDayFromCache() {
        var c = cacheCtx()
        var got = []
        responses = dayResponses("seen")
        openDay(c, got)
        compare(got.length, 1)
        compare(got[0].source, Sync.Source.LIVE)
        compare(got[0].r.match.id, 7)
        compare(got[0].r.day.fields.note, "seen")

        got = []
        requests = []
        responses = [{ status: 200, body: shootDay }].concat(dayResponses("seen").slice(2))
        openDay(c, got)
        compare(got.length, 1)
        compare(got[0].source, Sync.Source.CACHE)
        compare(got[0].r.match.id, 7)
        compare(got[0].r.day.fields.note, "seen")
        // still checked live (engagements within their hour stay cached)
        compare(requests.length, 3)
    }

    // The live check differs from the cache: the view renders again.
    function test_openDayLiveChanged() {
        var c = cacheCtx()
        var got = []
        responses = dayResponses("old")
        openDay(c, got)
        got = []
        responses = [{ status: 200, body: shootDay }].concat(dayResponses("new").slice(2))
        openDay(c, got)
        compare(got.map(function(g) { return g.source }), [Sync.Source.CACHE, Sync.Source.LIVE])
        compare(got[0].r.day.fields.note, "old")
        compare(got[1].r.day.fields.note, "new")
    }

    // Offline after a cached open: the cached view stays.
    function test_openDayOfflineKeepsCache() {
        var c = cacheCtx()
        var got = []
        responses = dayResponses("seen")
        openDay(c, got)
        got = []
        responses = [{ status: 0 }, { status: 0 }, { status: 0 }]
        openDay(c, got)
        compare(got.length, 1)
        compare(got[0].source, Sync.Source.CACHE)
    }

    // A save drops the day: the next open waits for the server.
    function test_openDayAfterSave() {
        var c = cacheCtx()
        var got = []
        responses = dayResponses("seen")
        openDay(c, got)
        Sync.forgetDay(c, "2026-09-25")
        got = []
        responses = [{ status: 200, body: shootDay }].concat(dayResponses("seen").slice(2))
        openDay(c, got)
        compare(got.length, 1)
        compare(got[0].source, Sync.Source.LIVE)
    }

    // Prefetch: one timesheet fetch for the last month, split by the days an
    // entry overlaps (night shoot on both days), then the engaged days' extras.
    function test_prefetchDays() {
        var c = ctx("server", { nowMs: new Date(2026, 8, 26, 12, 0).getTime() })
        var night = { id: 8, project: 155, activity: 40, begin: "2026-09-25T20:00:00+0200", end: "2026-09-26T03:00:00+0200" }
        responses = [{ status: 200, body: [night] }]
        for (var i = 0; i < Sync.PREFETCH_DAYS; i++) {
            responses.push({ status: 200, body: [] })   // no engagement that day
        }
        var finished = false
        Sync.prefetchDays(c, function() { finished = true })
        verify(finished)
        compare(requests.length, 1 + Sync.PREFETCH_DAYS)
        verify(requests[0].url.indexOf("/api/timesheets") > 0)
        var days = c.memo.days[c.profileKey]
        compare(days["2026-09-25"].timesheets.result.data[0].id, 8)
        compare(days["2026-09-26"].timesheets.result.data[0].id, 8)
        compare(days["2026-09-24"].timesheets.result.data.length, 0)
        verify(!days["2026-08-26"])

        // within the hour: no second prefetch
        requests = []
        Sync.prefetchDays(c)
        compare(requests.length, 0)
    }

    // A prefetched engaged day opens from the cache.
    function test_prefetchedDayOpensFromCache() {
        var c = ctx("server", { nowMs: new Date(2026, 8, 25, 20, 0).getTime() })
        var engagement = [{ engagementId: 1, projectId: 155, rulesetName: "R", validFrom: "2026-09-01" }]
        responses = [{ status: 200, body: shootDay }, { status: 200, body: engagement },
                     { status: 200, body: serverDay({ date: "2026-09-25", note: "pre" }) },
                     { status: 200, body: { hasEntry: true, begin: "2026-09-25T08:00:00+02:00", end: "2026-09-25T18:00:00+02:00" } }]
        for (var i = 1; i < Sync.PREFETCH_DAYS; i++) {
            responses.push({ status: 200, body: [] })
        }
        Sync.prefetchDays(c)
        responses = []
        var got = []
        openDay(c, got)
        compare(got.length, 1)
        compare(got[0].source, Sync.Source.CACHE)
        compare(got[0].r.day.fields.note, "pre")
    }

    function travelDayEntries() {
        return [
            { id: 4246, project: 155, activity: 12, begin: "2026-09-25T21:31:00+0200", end: "2026-09-25T21:56:00+0200" },
            { id: 4245, project: 155, activity: 40, begin: "2026-09-25T13:15:00+0200", end: "2026-09-25T21:30:00+0200" },
            { id: 4243, project: 153, activity: 7, begin: "2026-09-25T09:59:00+0200", end: "2026-09-25T11:22:36+0200" }
        ]
    }

    function viewOpts(extra) {
        var o = { entries: travelDayEntries(), active: null, recent: travelDayEntries(), daysFromToday: -1, ids: ids,
                  labelOf: function(ts) { return "a" + ts.activity }, timeOf: function(ts) { return String(ts.id) } }
        for (var k in (extra || {})) o[k] = extra[k]
        return o
    }

    // A past day with its entry: done; the other activities are listed for information.
    function test_viewInfoDone() {
        var e = travelDayEntries()
        var v = Sync.viewInfo({ projectId: 155, match: e[1], others: [] }, viewOpts())
        compare(v.phase, "done")
        compare(v.timesheet.id, 4245)
        compare(v.otherActivities.map(function(o) { return o.label }), ["a12", "a7"])
    }

    // Today before the start: the usual film activity is suggested.
    function test_viewInfoBefore() {
        var v = Sync.viewInfo({ projectId: 155, match: null, others: [] }, viewOpts({ entries: [], daysFromToday: 0 }))
        compare(v.phase, "before")
        compare(v.activityId, 40)
        verify(v.isToday)
        compare(v.timesheet, null)
    }

    // The main timer runs on the film activity: running, the running entry is shown.
    function test_viewInfoRunning() {
        var active = { id: 9, project: 155, activity: 40, begin: "2026-09-26T07:42:00+0200", end: null }
        var v = Sync.viewInfo({ projectId: 155, match: null, others: [] },
                              viewOpts({ entries: [active], active: active, daysFromToday: 0 }))
        compare(v.phase, "running")
        compare(v.timesheet.id, 9)
        compare(v.otherActivities.length, 0)
        // travel running on the same project is not the film day
        var travel = { id: 10, project: 155, activity: 12, begin: "2026-09-26T07:00:00+0200", end: null }
        v = Sync.viewInfo({ projectId: 155, match: null, others: [] },
                          viewOpts({ entries: [travel], active: travel, daysFromToday: 0 }))
        compare(v.phase, "before")
    }

    // The shoot runs after a finished commute: running beats the shorter stopped entry;
    // the drive home after a finished shoot does not.
    function test_viewInfoRunningAfterCommute() {
        var commute = { id: 1, project: 155, activity: 12, begin: "2026-09-23T06:55:00+0200", end: "2026-09-23T07:30:00+0200" }
        var shoot = { id: 2, project: 155, activity: 40, begin: "2026-09-23T07:35:00+0200", end: null }
        var v = Sync.viewInfo({ projectId: 155, match: commute, others: [] },
                              viewOpts({ entries: [commute, shoot], active: shoot, recent: [], daysFromToday: 0,
                                         nowMs: new Date("2026-09-23T14:20:00+0200").getTime() }))
        compare(v.phase, "running")
        compare(v.timesheet.id, 2)
        compare(v.activityId, 40)
        compare(v.otherActivities.map(function(o) { return o.label }), ["a12"])

        var done = { id: 3, project: 155, activity: 40, begin: "2026-09-23T07:35:00+0200", end: "2026-09-23T18:45:00+0200" }
        var home = { id: 4, project: 155, activity: 12, begin: "2026-09-23T18:50:00+0200", end: null }
        v = Sync.viewInfo({ projectId: 155, match: done, others: [] },
                          viewOpts({ entries: [done, home], active: home, recent: [], daysFromToday: 0,
                                     nowMs: new Date("2026-09-23T19:10:00+0200").getTime() }))
        compare(v.phase, "done")
        compare(v.timesheet.id, 3)
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
