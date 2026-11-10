import QtQuick
import QtTest
import "../../contents/code/solar.js" as Solar

TestCase {
    name: "Solar"

    function test_weimarFractionsSane() {
        var day = new Date(2026, 7, 13, 12, 0, 0)
        var r = Solar.daySolarFractions(day, 50.979, 11.33)
        verify(r.valid)
        verify(r.sunrise >= 0 && r.sunrise < 1)
        verify(r.sunset > r.sunrise)
        verify(r.sunset <= 1)
    }

    function test_invalidCoordsFallback() {
        var r = Solar.daySolarFractions(new Date(), Number.NaN, 0)
        verify(!r.valid)
        compare(r.sunrise, 6 / 24)
        compare(r.sunset, 18 / 24)
    }

    function test_polarNightApprox() {
        var winter = new Date(2026, 11, 21, 12, 0, 0)
        var r = Solar.daySolarFractions(winter, 89.0, 0)
        verify(r.valid)
        // Polar night or a very short day — sunset not after a late sunrise.
        verify(r.polarNight === true || r.sunset >= r.sunrise)
    }

    // Startup: the sky over a day depends on the day and the place only. DaySparkline asks again
    // whenever the entries change; each time sampled the moon 145 times (Pixel 6: several
    // thousand calls into this file while the timer page started).
    function test_skyOfADayIsWorkedOutOnce() {
        var morning = new Date(2031, 2, 4, 3, 0, 0)
        var noon = new Date(2031, 2, 4, 12, 0, 0)
        var before = Solar.lunarDaysSampled
        var a = Solar.daySkyModel(morning, 50.979, 11.33, 8 / 24, 18 / 24)
        var b = Solar.daySkyModel(noon, 50.979, 11.33, 9 / 24, 17 / 24)
        compare(Solar.lunarDaysSampled - before, 1, "one day, one place: the moon sampled once")
        compare(b.sun.sunrise, a.sun.sunrise)
        compare(b.moon.moonrise, a.moon.moonrise)
        Solar.daySkyModel(new Date(2031, 2, 5, 12, 0, 0), 50.979, 11.33, 8 / 24, 18 / 24)
        Solar.daySkyModel(noon, 48.1, 11.58, 8 / 24, 18 / 24)
        compare(Solar.lunarDaysSampled - before, 3, "another day or place is worked out anew")
    }

    // Any time zone (CI runs UTC, UTC-8 and UTC+14): each hour of a June day, cached against
    // worked out anew (another place in between empties the cache).
    function test_cachedSkyStillFollowsTheTimeOfDay() {
        var sunStates = {}
        for (var h = 0; h < 24; ++h) {
            var at = new Date(2031, 5, 10, h, 30, 0)
            Solar.daySkyModel(new Date(2031, 5, 10, 0, 0, 0), 50.979, 11.33, 8 / 24, 18 / 24)
            var cached = Solar.daySkyModel(at, 50.979, 11.33, 8 / 24, 18 / 24)
            Solar.daySkyModel(at, 48.1, 11.58, 8 / 24, 18 / 24)
            var fresh = Solar.daySkyModel(at, 50.979, 11.33, 8 / 24, 18 / 24)
            compare(cached.sun.up, fresh.sun.up, "sun at " + h + ":30")
            compare(cached.moon.up, fresh.moon.up, "moon at " + h + ":30")
            compare(cached.work.up, h >= 8 && h < 18, "working hours at " + h + ":30")
            compare(cached.now, (h + 0.5) / 24)
            sunStates[cached.sun.up] = true
        }
        verify(sunStates[true] && sunStates[false], "the sun rises and sets over the day")
    }
}
