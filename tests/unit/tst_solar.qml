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
}
