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

    function test_hoursMinutes() {
        compare(DateTimeFormat.hoursMinutes(0), "0:00")
        compare(DateTimeFormat.hoursMinutes(5 * 60 + 59), "0:05")
        compare(DateTimeFormat.hoursMinutes(88 * 60), "1:28")
        compare(DateTimeFormat.hoursMinutes(50 * 3600 + 34 * 60), "50:34")
        compare(DateTimeFormat.hoursMinutes(-(15 * 3600 + 31 * 60)), "−15:31")
    }

    // Recent entries grouped by local day for the Kante time line (variant B).
    function test_groupByDay() {
        var now = new Date(2026, 8, 26, 16, 0, 0)
        var e = [
            { id: 1, begin: new Date(2026, 8, 25, 21, 31).toISOString(), duration: 1500 },
            { id: 2, begin: new Date(2026, 8, 25, 13, 15).toISOString(), duration: 29700 },
            { id: 3, begin: new Date(2026, 8, 24, 11, 50).toISOString(), duration: 37140 },
            { id: 4, begin: new Date(2026, 8, 23, 20, 19).toISOString(), duration: 5880 }
        ]
        var g = DateTimeFormat.groupByDay(e, now, function(x) { return x.begin })
        compare(g.length, 3)
        compare(g[0].daysAgo, 1)
        compare(g[0].entries.map(function(x) { return x.id }), [1, 2])
        compare(g[1].daysAgo, 2)
        compare(g[2].entries.length, 1)
        compare(DateTimeFormat.groupByDay([], now, function(x) { return x.begin }).length, 0)
    }

    function test_dayHeaderLabel() {
        var now = new Date(2026, 8, 26, 16, 0, 0)
        compare(DateTimeFormat.dayHeaderLabel(new Date(2026, 8, 26), now, "Today", "Yesterday"), "Today")
        compare(DateTimeFormat.dayHeaderLabel(new Date(2026, 8, 25), now, "Today", "Yesterday"), "Yesterday")
        var d = new Date(2026, 8, 23)
        compare(DateTimeFormat.dayHeaderLabel(d, now, "Today", "Yesterday"),
                Qt.locale().dayName(d.getDay(), 0) + ", " + DateTimeFormat.formatLocaleDate(d))
    }

    function test_entryTimeLabel() {
        var now = new Date(2026, 8, 26, 16, 0, 0)
        var clock = function(h, m) { return DateTimeFormat.formatLocaleTime(h, m) }
        // same day: begin – end, running: begin – now label
        compare(DateTimeFormat.entryTimeLabel(new Date(2026, 8, 26, 7, 42), new Date(2026, 8, 26, 9, 40), now, "now"),
                clock(7, 42) + " – " + clock(9, 40))
        compare(DateTimeFormat.entryTimeLabel(new Date(2026, 8, 26, 7, 42), null, now, "now"),
                clock(7, 42) + " – now")
        // this week: short weekday + begin
        compare(DateTimeFormat.entryTimeLabel(new Date(2026, 8, 24, 13, 20), new Date(2026, 8, 24, 14, 0), now, "now"),
                Qt.locale().dayName(new Date(2026, 8, 24).getDay(), 1) + " " + clock(13, 20))
        // older: day + short month + begin
        compare(DateTimeFormat.entryTimeLabel(new Date(2026, 8, 12, 8, 5), new Date(2026, 8, 12, 9, 0), now, "now"),
                "12 " + Qt.locale().standaloneMonthName(8, 1) + " " + clock(8, 5))
        compare(DateTimeFormat.entryTimeLabel(null, null, now, "now"), "")
        compare(DateTimeFormat.entryTimeLabel("not a date", null, now, "now"), "")
    }

    // One parser for every backend's stamps (Kimai, ISO, provider variants).
    function test_parseStamp() {
        var utc = Date.UTC(2026, 8, 25, 11, 15, 0)
        compare(DateTimeFormat.stampMs("2026-09-25T13:15:00+0200"), utc)
        compare(DateTimeFormat.stampMs("2026-09-25T13:15:00+02:00"), utc)
        compare(DateTimeFormat.stampMs("2026-09-25T13:15:00.000+0200"), utc)
        compare(DateTimeFormat.stampMs("2026-09-25T11:15:00Z"), utc)
        compare(DateTimeFormat.stampMs("2026-09-25T11:15:00.000Z"), utc)
        // no offset: local time
        compare(DateTimeFormat.stampMs("2026-09-25T13:15:00"), new Date(2026, 8, 25, 13, 15, 0).getTime())
        compare(DateTimeFormat.stampMs("2026-09-25 13:15:00"), new Date(2026, 8, 25, 13, 15, 0).getTime())
        // form input without seconds ("yyyy-MM-dd hh:mm")
        compare(DateTimeFormat.stampMs("2026-09-25 13:15"), new Date(2026, 8, 25, 13, 15, 0).getTime())
        compare(DateTimeFormat.stampMs(" 2026-09-25T13:15 "), new Date(2026, 8, 25, 13, 15, 0).getTime())
        // date only: local midnight (Date() takes UTC, the day before west of UTC)
        compare(DateTimeFormat.stampMs("2026-09-25"), new Date(2026, 8, 25).getTime())
        // Date and ms pass through; the result is a copy
        var d = new Date(utc)
        var parsed = DateTimeFormat.parseStamp(d)
        compare(parsed.getTime(), utc)
        verify(parsed !== d)
        compare(DateTimeFormat.stampMs(utc), utc)
        // nothing usable: Invalid Date, never the epoch
        verify(isNaN(DateTimeFormat.stampMs(null)))
        verify(isNaN(DateTimeFormat.stampMs(undefined)))
        verify(isNaN(DateTimeFormat.stampMs("")))
        verify(isNaN(DateTimeFormat.stampMs("not a date")))
    }
}
