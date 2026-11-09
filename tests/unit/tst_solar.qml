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

    function test_cachedSkyStillFollowsTheTimeOfDay() {
        var night = Solar.daySkyModel(new Date(2031, 5, 10, 2, 0, 0), 50.979, 11.33, 8 / 24, 18 / 24)
        var noon = Solar.daySkyModel(new Date(2031, 5, 10, 12, 0, 0), 50.979, 11.33, 8 / 24, 18 / 24)
        verify(!night.sun.up, "sun down at 2 am")
        verify(noon.sun.up, "sun up at noon")
        verify(!night.work.up)
        verify(noon.work.up)
        compare(noon.now, 0.5)
        var direct = Solar.dayLunarFractions(new Date(2031, 5, 10, 12, 0, 0), 50.979, 11.33)
        compare(noon.moon.up, direct.up, "moon up as worked out without the cache")
    }
}
