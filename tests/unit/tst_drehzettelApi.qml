import QtQuick
import QtTest
import "../../contents/code/drehzettelApi.js" as DrehzettelApi

TestCase {
    name: "DrehzettelApi"

    function test_supportsV1() {
        verify(DrehzettelApi.supportsV1({ installed: true, apiVersions: ["v1"] }))
        verify(!DrehzettelApi.supportsV1({ installed: true, apiVersions: ["v2"] }))
        verify(!DrehzettelApi.supportsV1({ installed: false, apiVersions: ["v1"] }))
        verify(!DrehzettelApi.supportsV1(null))
        verify(!DrehzettelApi.supportsV1(undefined))
    }

    function test_categories() {
        compare(DrehzettelApi.CATEGORIES.length, 4)
        verify(DrehzettelApi.CATEGORIES.indexOf("workday") >= 0)
        verify(DrehzettelApi.CATEGORIES.indexOf("saturday") >= 0)
        verify(DrehzettelApi.CATEGORIES.indexOf("sunday") >= 0)
        verify(DrehzettelApi.CATEGORIES.indexOf("holiday") >= 0)
    }

    function test_dateParam() {
        var d = new Date(2026, 8, 24, 15, 30, 0)
        compare(DrehzettelApi.dateParam(d), "2026-09-24")
        compare(DrehzettelApi.dateParam("2026-09-24T00:00:00"), "2026-09-24")
    }

    function test_filmDayEndpoint() {
        var d = new Date(2026, 8, 24)
        compare(DrehzettelApi.filmDayEndpoint(42, d), "/api/drehzettel/v1/film-days/2026-09-24?project=42")
    }

    function test_pingCache() {
        DrehzettelApi.resetPingCache()
        verify(DrehzettelApi.cachedPing("https://kimai.example.com") === null)
        DrehzettelApi.storePing("https://kimai.example.com/", { installed: true, pluginVersion: "0.1.0", apiVersions: ["v1"] })
        var cached = DrehzettelApi.cachedPing("https://kimai.example.com")
        verify(cached !== null)
        compare(cached.installed, true)
        // Expired entries are not returned.
        verify(DrehzettelApi.cachedPing("https://kimai.example.com", Date.now() + 60 * 60 * 1000) === null)
        DrehzettelApi.resetPingCache()
    }

    function test_configErrorWithoutCredentials() {
        var received = null
        DrehzettelApi.engagementStatus("", "", 1, new Date(), function(result) {
            received = result
        })
        verify(received !== null)
        verify(!received.ok)
        compare(received.error.type, "config")
    }
}
