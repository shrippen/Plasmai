import QtQuick
import QtTest
import "../../contents/code/statsData.js" as StatsData

TestCase {
    name: "StatsData"

    // Chart axes end on round values; the half-way line is round too.
    function test_axisMaxSeconds() {
        var h = 3600, m = 60
        compare(StatsData.axisMaxSeconds(0), 0)
        compare(StatsData.axisMaxSeconds(12 * h + 21 * m), 14 * h)
        compare(StatsData.axisMaxSeconds(12 * h), 12 * h)
        compare(StatsData.axisMaxSeconds(50 * m), 1 * h)
        compare(StatsData.axisMaxSeconds(7 * m), 10 * m)
        compare(StatsData.axisMaxSeconds(30 * h), 32 * h)
        compare(StatsData.axisMaxSeconds(100 * h), 100 * h)
    }

    function test_filterBillable() {
        var entries = [
            { id: 1, billable: true },
            { id: 2, billable: false },
            { id: 3, billable: true }
        ]
        compare(StatsData.filterBillable(entries, StatsData.BILLABLE_ALL).length, 3)
        compare(StatsData.filterBillable(entries, StatsData.BILLABLE_ONLY).length, 2)
        compare(StatsData.filterBillable(entries, StatsData.BILLABLE_NONE).length, 1)
        compare(StatsData.filterBillable(entries, StatsData.BILLABLE_NONE)[0].id, 2)
    }

    function test_weekHelpers() {
        var day = new Date(2026, 7, 13, 10, 0, 0)
        var start = StatsData.startOfWeek(day)
        compare(start.getDay(), 1)
        var next = StatsData.addDays(day, 1)
        compare(next.getDate(), 14)
    }

    function test_isBillable() {
        verify(StatsData.isBillable({ billable: true }))
        verify(!StatsData.isBillable({ billable: false }))
        verify(!StatsData.isBillable(null))
    }

    function test_overlapAndHourly() {
        var day = new Date(2026, 7, 13, 12, 0, 0)
        var entries = [{
            begin: new Date(2026, 7, 13, 9, 0, 0).toISOString(),
            end: new Date(2026, 7, 13, 10, 30, 0).toISOString(),
            billable: true,
            project: { id: 1, name: "P" },
            activity: { id: 2, name: "A" }
        }]
        var dayHits = StatsData.entriesOverlappingDay(entries, day, Date.now())
        compare(dayHits.length, 1)
        var hours = StatsData.hourlyBreakdown(entries, day, Date.now())
        compare(hours.length, 24)
        verify(hours[9].seconds > 0)
        verify(hours[10].seconds > 0)
        compare(hours[8].seconds, 0)
    }

    function test_paletteWraps() {
        compare(StatsData.paletteColor(0), StatsData.PALETTE[0])
        compare(StatsData.paletteColor(StatsData.PALETTE.length), StatsData.PALETTE[0])
    }

    // Nothing loaded: the asked days, padded to whole weeks (Mon..Sun).
    function test_missingSpan_padsToWeeks() {
        var span = StatsData.missingSpan(0, 0, 0, new Date(2026, 7, 12, 10), new Date(2026, 7, 13, 10))
        compare(span.begin.getDay(), 1)
        compare(span.begin.getDate(), 10)
        compare(span.end.getDay(), 0)
        compare(span.end.getDate(), 16)
    }

    function test_missingSpan_coveredIsNull() {
        var b = new Date(2026, 7, 10).getTime()
        var e = new Date(2026, 7, 16, 23).getTime()
        compare(StatsData.missingSpan(b, e, 3, new Date(2026, 7, 11), new Date(2026, 7, 12)), null)
    }

    // An empty list is not "loaded", even with a range.
    function test_missingSpan_emptyListFetchesAgain() {
        var b = new Date(2026, 7, 10).getTime()
        var e = new Date(2026, 7, 16, 23).getTime()
        verify(StatsData.missingSpan(b, e, 0, new Date(2026, 7, 11), new Date(2026, 7, 12)) !== null)
    }

    // Asking before the loaded range grows it; the loaded end stays.
    function test_missingSpan_growsLoadedRange() {
        var b = new Date(2026, 7, 10).getTime()
        var e = new Date(2026, 7, 16, 23).getTime()
        var span = StatsData.missingSpan(b, e, 3, new Date(2026, 6, 28), new Date(2026, 7, 12))
        compare(span.begin.getDate(), 27)
        compare(span.begin.getMonth(), 6)
        compare(span.end.getDate(), 16)
    }

    function test_prefetchSpan() {
        var span = StatsData.prefetchSpan(new Date(2026, 7, 13, 10))
        compare(span.begin.getDate(), 13)
        compare(span.begin.getMonth(), 6)
        compare(span.end.getDate(), 16)
    }

    function test_replaceWeek_keeps_other_weeks() {
        var b = new Date(2026, 7, 10).getTime()
        var e = new Date(2026, 7, 16, 23, 59).getTime()
        var list = [{ id: 1, begin: "2026-08-03T10:00:00+0000" }, { id: 2, begin: "2026-08-12T10:00:00+0000" }]
        var out = StatsData.replaceWeek(list, [{ id: 3, begin: "2026-08-13T10:00:00+0000" }], b, e)
        compare(out.map(function(x) { return x.id }), [1, 3])
    }
}
