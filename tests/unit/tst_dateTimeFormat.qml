import QtQuick
import QtTest
import "../../contents/code/dateTimeFormat.js" as DateTimeFormat

TestCase {
    name: "DateTimeFormat"

    function test_pad() {
        compare(DateTimeFormat.pad2(3), "03")
        compare(DateTimeFormat.pad2(12), "12")
        compare(DateTimeFormat.pad4(7), "0007")
        compare(DateTimeFormat.pad4(2026), "2026")
    }

    function test_coerceDate() {
        var d = DateTimeFormat.coerceDate(new Date(2026, 7, 13, 18, 45, 0))
        compare(d.getFullYear(), 2026)
        compare(d.getMonth(), 7)
        compare(d.getDate(), 13)
        compare(d.getHours(), 12)
        compare(DateTimeFormat.coerceDate(null), null)
        compare(DateTimeFormat.coerceDate(""), null)
        var fromMs = DateTimeFormat.coerceDate(Date.UTC(2026, 0, 2, 0, 0, 0))
        verify(fromMs !== null)
        compare(fromMs.getFullYear(), 2026)
    }

    function test_formatLocaleDateNotEmpty() {
        var text = DateTimeFormat.formatLocaleDate(new Date(2026, 7, 13, 12, 0, 0))
        verify(text.length > 0)
    }

    function test_daysInMonthAndClamp() {
        compare(DateTimeFormat.daysInMonth(2026, 1), 28)
        compare(DateTimeFormat.daysInMonth(2024, 1), 29)
        compare(DateTimeFormat.clampInt("9", 0, 5), 5)
        compare(DateTimeFormat.clampInt("x", 3, 9), 3)
    }

    function test_digitSegments() {
        var segs = DateTimeFormat.digitSegments("13.08.2026")
        verify(segs.length >= 3)
    }
}
