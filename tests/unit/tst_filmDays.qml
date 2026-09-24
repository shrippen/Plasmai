import QtQuick
import QtTest
import "../../contents/code/filmDays.js" as FilmDays

TestCase {
    name: "FilmDays"

    function test_dayKey() {
        compare(FilmDays.dayKey(12, "2026-09-23"), "12|2026-09-23")
    }

    function test_defaultsWhenMissing() {
        var entry = FilmDays.get({}, 12, "2026-09-23")
        compare(entry.breakMinutes, 45)
        compare(entry.catering, FilmDays.Catering.NO)
        compare(entry.category, FilmDays.DayCategory.AUTO)
        compare(entry.dayType, FilmDays.DayType.WORKDAY)
        compare(entry.productionDay, null)
        compare(entry.extraPayCents, 0)
        compare(entry.note, "")
    }

    function test_setThenGetRoundTrips() {
        var map = FilmDays.set({}, 12, "2026-09-23", {
            breakMinutes: 30,
            catering: FilmDays.Catering.YES,
            category: FilmDays.DayCategory.HOLIDAY,
            dayType: FilmDays.DayType.TRAVEL,
            productionDay: 6,
            extraPayCents: 1500,
            note: "Night exteriors"
        })
        var entry = FilmDays.get(map, 12, "2026-09-23")
        compare(entry.breakMinutes, 30)
        compare(entry.catering, FilmDays.Catering.YES)
        compare(entry.category, FilmDays.DayCategory.HOLIDAY)
        compare(entry.dayType, FilmDays.DayType.TRAVEL)
        compare(entry.productionDay, 6)
        compare(entry.extraPayCents, 1500)
        compare(entry.note, "Night exteriors")
    }

    function test_setDoesNotMutateInput() {
        var base = {}
        var next = FilmDays.set(base, 12, "2026-09-23", FilmDays.entryDefaults())
        compare(Object.keys(base).length, 0)
        compare(Object.keys(next).length, 1)
    }

    function test_serializeRoundTrip() {
        var map = FilmDays.set({}, 12, "2026-09-23", FilmDays.entryDefaults())
        var again = FilmDays.parse(FilmDays.serialize(map))
        compare(again["12|2026-09-23"].breakMinutes, 45)
    }

    function test_parseInvalidJsonFallsBack() {
        compare(Object.keys(FilmDays.parse("{not json")).length, 0)
        compare(Object.keys(FilmDays.parse("")).length, 0)
    }

    function test_categoryFromWeekday() {
        compare(FilmDays.categoryFromWeekday(1), FilmDays.DayCategory.WORKDAY)
        compare(FilmDays.categoryFromWeekday(5), FilmDays.DayCategory.WORKDAY)
        compare(FilmDays.categoryFromWeekday(6), FilmDays.DayCategory.SATURDAY)
        compare(FilmDays.categoryFromWeekday(7), FilmDays.DayCategory.SUNDAY)
    }

    function test_effectiveCategoryPrefersOverride() {
        compare(FilmDays.effectiveCategory({ category: FilmDays.DayCategory.HOLIDAY }, 1),
                FilmDays.DayCategory.HOLIDAY)
        compare(FilmDays.effectiveCategory({ category: FilmDays.DayCategory.AUTO }, 6),
                FilmDays.DayCategory.SATURDAY)
        compare(FilmDays.effectiveCategory(null, 7), FilmDays.DayCategory.SUNDAY)
    }

    function test_workSecondsFromSpan() {
        // 09:00 to 18:00 minus 45 min break = 8h15m
        var begin = new Date(2026, 8, 23, 9, 0, 0).getTime()
        var end = new Date(2026, 8, 23, 18, 0, 0).getTime()
        compare(FilmDays.workSecondsFromSpan(begin, end, 45), (8 * 3600) + (15 * 60))
    }

    function test_workSecondsFromSpanClampsAtZero() {
        var begin = new Date(2026, 8, 23, 9, 0, 0).getTime()
        var end = new Date(2026, 8, 23, 9, 30, 0).getTime()
        compare(FilmDays.workSecondsFromSpan(begin, end, 45), 0)
    }

    function test_workSecondsFromSpanInvalidRange() {
        compare(FilmDays.workSecondsFromSpan(100, 50, 0), 0)
        compare(FilmDays.workSecondsFromSpan(-1, 50, 0), 0)
    }
}
