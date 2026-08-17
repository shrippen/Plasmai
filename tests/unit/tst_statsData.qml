import QtQuick
import QtTest
import "../../contents/code/statsData.js" as StatsData

TestCase {
    name: "StatsData"

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
        verify(StatsData.sameLocalDay(day, new Date(2026, 7, 13, 23, 0, 0)))
        verify(!StatsData.sameLocalDay(day, new Date(2026, 7, 14, 0, 30, 0)))
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
}
