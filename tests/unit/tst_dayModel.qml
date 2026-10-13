import QtQuick
import QtTest
import "../../contents/code/dayModel.js" as DayModel

/**
 * dayModel.js: day blocks, gaps and the week grid behind the layouts.
 * Stamps are local times, so the days hold in every time zone.
 */
TestCase {
    name: "DayModel"

    // Wednesday 14:40; the week starts Monday 2026-10-12.
    readonly property var now: new Date(2026, 9, 14, 14, 40)

    function at(day, h, m) {
        return new Date(2026, 9, day, h, m).toISOString()
    }

    function entry(begin, end, project, activity) {
        return {
            begin: begin, end: end,
            project: { id: project, name: "P" + project },
            activity: { id: activity, name: "A" + activity }
        }
    }

    // A shoot, a gap, and the running entry until now.
    function test_blocksOfToday() {
        var shoot = entry(at(14, 8, 15), at(14, 12, 30), 1, 1)
        var running = entry(at(14, 13, 15), null, 2, 2)
        var b = DayModel.blocks([running, shoot], now, now.getTime())

        compare(b.length, 2)
        compare(b[0].fromHour, 8.25)
        compare(b[0].toHour, 12.5)
        verify(!b[0].running)
        compare(b[1].fromHour, 13.25)
        compare(Math.round(b[1].toHour * 60), 14 * 60 + 40)
        verify(b[1].running)
        compare(b[0].cut, DayModel.Cut.NONE)
    }

    // A night shift belongs to both days, cut at midnight.
    function test_nightShiftSplitsAtMidnight() {
        var night = entry(at(13, 22, 0), at(14, 3, 13), 3, 3)
        var tuesday = DayModel.blocks([night], new Date(2026, 9, 13, 12, 0), now.getTime())
        var wednesday = DayModel.blocks([night], now, now.getTime())

        compare(tuesday.length, 1)
        compare(tuesday[0].fromHour, 22)
        compare(tuesday[0].toHour, 24)
        compare(tuesday[0].cut, DayModel.Cut.AFTER)
        compare(wednesday[0].fromHour, 0)
        compare(Math.round(wednesday[0].toHour * 60), 3 * 60 + 13)
        compare(wednesday[0].cut, DayModel.Cut.BEFORE)
    }

    function test_blocksSkipOtherDaysAndBadStamps() {
        var monday = entry(at(12, 9, 0), at(12, 10, 0), 1, 1)
        var broken = entry("", at(14, 10, 0), 1, 1)
        compare(DayModel.blocks([monday, broken], now, now.getTime()).length, 0)
    }

    // 12:30–13:15 is a gap; a 5-minute gap is below the minimum.
    function test_gapsInWorkDay() {
        var b = DayModel.blocks([
            entry(at(14, 8, 15), at(14, 12, 30), 1, 1),
            entry(at(14, 12, 35), at(14, 12, 40), 1, 1),
            entry(at(14, 13, 15), at(14, 14, 0), 2, 2)
        ], now, now.getTime())
        var g = DayModel.gaps(b, 8, 14, 15)

        compare(g.length, 2)
        compare(g[0].fromHour, 8)
        compare(g[0].minutes, 15)
        compare(g[1].fromHour, 12 + 40 / 60)
        compare(g[1].minutes, 35)
    }

    // Overlapping blocks count once; the end of the window is a gap too.
    function test_gapsOverlapAndTail() {
        var b = DayModel.blocks([
            entry(at(14, 9, 0), at(14, 11, 0), 1, 1),
            entry(at(14, 10, 0), at(14, 10, 30), 2, 2)
        ], now, now.getTime())
        var g = DayModel.gaps(b, 9, 12, 15)

        compare(g.length, 1)
        compare(g[0].fromHour, 11)
        compare(g[0].toHour, 12)
        compare(g[0].minutes, 60)
        compare(DayModel.gaps([], 9, 12, 15)[0].minutes, 180)
    }

    // Rows per project and activity, seconds per weekday, biggest first.
    function test_weekGrid() {
        var h = 3600
        var g = DayModel.weekGrid([
            entry(at(12, 8, 0), at(12, 16, 0), 1, 1),
            entry(at(13, 9, 0), at(13, 10, 30), 2, 2),
            entry(at(14, 13, 15), null, 2, 2),
            entry(at(13, 22, 0), at(14, 2, 0), 1, 1),
            entry(at(5, 8, 0), at(5, 9, 0), 1, 1)
        ], now, now.getTime())

        compare(g.rows.length, 2)
        compare(g.rows[0].key, "1/1")
        compare(g.rows[0].project, "P1")
        compare(g.rows[0].activity, "A1")
        compare(g.rows[0].days[0], 8 * h)
        compare(g.rows[0].days[1], 2 * h - 1)
        compare(g.rows[0].days[2], 2 * h)
        compare(g.rows[1].days[1], 1.5 * h)
        compare(g.rows[1].days[2], 85 * 60)
        verify(g.rows[1].running)
        verify(!g.rows[0].running)
        compare(g.dayTotals[3], 0)
        compare(g.total, g.dayTotals.reduce(function(a, b) { return a + b }, 0))
    }
}
