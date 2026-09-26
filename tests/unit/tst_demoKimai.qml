import QtQuick
import QtTest
import "../../contents/code/demoKimai.js" as Demo
import "../../contents/code/kimaiApi.js" as KimaiApi

TestCase {
    name: "DemoKimai"

    // Wednesday noon: the engagement's shooting days fall on the days before.
    readonly property var now: new Date(2026, 8, 23, 12, 0, 0)

    function init() {
        Demo.reset(now)
    }

    function get(path) {
        return Demo.handle("GET", Demo.DEMO_URL + path, undefined)
    }

    function send(method, path, body) {
        return Demo.handle(method, Demo.DEMO_URL + path, body === undefined ? undefined : JSON.stringify(body))
    }

    function test_onlyTheDemoUrl() {
        verify(Demo.isDemoUrl("https://demo.invalid"))
        verify(Demo.isDemoUrl("https://demo.invalid/"))
        verify(!Demo.isDemoUrl("https://kimai.example.org"))
        verify(!Demo.isDemoUrl(""))
    }

    function test_catalog() {
        var projects = get("/api/projects?visible=3").body
        verify(projects.length >= 3)
        verify(get("/api/customers").body.length >= 3)
        verify(get("/api/activities?visible=3").body.length >= 5)
        compare(get("/api/unknown").status, 404)
    }

    function test_historyAndRunningEntry() {
        var active = get("/api/timesheets/active").body
        compare(active.length, 1)
        verify(!active[0].end)
        var list = get("/api/timesheets?begin=2026-09-14T00:00:00&end=2026-09-20T23:59:59&full=1").body
        verify(list.length >= 8)
        for (var i = 0; i < list.length; i++) {
            verify(list[i].begin >= "2026-09-14", list[i].begin)
            verify(list[i].project.customer.name.length > 0)
        }
        verify(get("/api/timesheets/recent?size=10").body.length > 0)
    }

    function test_projectFilter() {
        var list = get("/api/timesheets?begin=2026-09-01T00:00:00&end=2026-09-23T23:59:59&project=10").body
        verify(list.length > 0)
        for (var i = 0; i < list.length; i++) {
            compare(list[i].project.id, 10)
        }
    }

    function test_startStopRestartDelete() {
        var running = get("/api/timesheets/active").body[0]
        compare(send("PATCH", "/api/timesheets/" + running.id + "/stop", {}).status, 200)
        compare(get("/api/timesheets/active").body.length, 0)
        var started = send("POST", "/api/timesheets", { project: 12, activity: 26, description: "Receipts" })
        compare(started.status, 200)
        compare(started.body.description, "Receipts")
        compare(get("/api/timesheets/active").body[0].id, started.body.id)
        send("PATCH", "/api/timesheets/" + started.body.id + "/stop", {})
        var again = send("PATCH", "/api/timesheets/" + started.body.id + "/restart", { copy: "all" })
        compare(again.body.activity.id, 26)
        compare(send("DELETE", "/api/timesheets/" + again.body.id).status, 204)
        compare(get("/api/timesheets/active").body.length, 0)
    }

    function test_patchTimes() {
        var entry = send("POST", "/api/timesheets", { project: 11, activity: 24, begin: "2026-09-23T08:00:00", end: "2026-09-23T09:30:00" }).body
        compare(entry.duration, 5400)
        var patched = send("PATCH", "/api/timesheets/" + entry.id, { end: "2026-09-23T10:00:00" }).body
        compare(patched.duration, 7200)
    }

    function test_filmDay() {
        verify(KimaiApi.drehzettelPingAccepts(get("/api/drehzettel/ping").body))
        var engagements = get("/api/drehzettel/v1/engagements?date=2026-09-22").body
        compare(engagements.length, 1)
        compare(engagements[0].projectId, 10)
        compare(get("/api/drehzettel/v1/engagements?date=2026-08-01").body.length, 0)
        var day = get("/api/drehzettel/v1/film-days/2026-09-22?project=10").body
        compare(day.dayType, "workday")
        var put = send("PUT", "/api/drehzettel/v1/film-days/2026-09-22?project=10", { note: "Night exterior" }).body
        compare(put.note, "Night exterior")
        var summary = get("/api/drehzettel/v1/days/2026-09-22/summary?project=10").body
        verify(summary.hasEntry)
        verify(summary.payCents > 0)
        compare(summary.currency, "EUR")
        compare(get("/api/drehzettel/v1/film-days/2026-09-22?project=11").status, 404)
    }

    function test_trips() {
        var ping = get("/api/mileage/ping").body
        verify(ping.permissions.editOwn)
        verify(get("/api/mileage/trips?from=2026-09-01&to=2026-09-30").body.length > 0)
        var trip = send("POST", "/api/mileage/trips", { date: "2026-09-23", purpose: "business", vehicle: "own_car", distanceKm: 12 })
        compare(trip.status, 201)
        compare(send("DELETE", "/api/mileage/trips/" + trip.body.id).status, 204)
    }

    function test_workContract() {
        var prefs = KimaiApi.preferenceMap(get("/api/users/me").body)
        compare(KimaiApi.workWeekSecondsFromPrefs(prefs, now), 40 * 3600)
    }

    // The app's request layer answers demo URLs without a network.
    function test_throughKimaiApi() {
        var result = null
        KimaiApi.loadProjects(Demo.DEMO_URL, "demo", function(r) { result = r })
        tryVerify(function() { return result !== null })
        verify(result.ok)
        verify(result.data.length >= 3)
    }
}
