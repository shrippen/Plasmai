import QtQuick
import QtTest
import "../../contents/code/filmDays.js" as FilmDays

TestCase {
    name: "FilmDays"

    function test_otherDayEntriesAndSpan() {
        function pid(ts) { return ts.project }
        var a = { id: 1, project: 5, begin: "2026-09-23T09:00:00+0200", end: "2026-09-23T12:00:00+0200" }
        var b = { id: 2, project: 5, begin: "2026-09-23T13:00:00+0200", end: "2026-09-23T19:00:00+0200" }
        var c = { id: 3, project: 6, begin: "2026-09-23T07:00:00+0200", end: "2026-09-23T08:00:00+0200" }
        var running = { id: 4, project: 5, begin: "2026-09-23T20:00:00+0200", end: null }
        var early = { id: 5, project: 5, begin: "2026-09-23T06:00:00+0200", end: "2026-09-23T07:00:00+0200" }
        var others = FilmDays.otherDayEntries([a, b, c, running, early], a, 5, pid)
        compare(others.length, 2)
        compare(others[0].id, 5)    // sorted by begin
        compare(others[1].id, 2)
        compare(FilmDays.otherDayEntries([a, b], null, 5, pid).length, 0)
        var span = FilmDays.daySpan([a, b])
        compare(span.seconds, 9 * 3600)
        compare(span.endMs - span.beginMs, 10 * 3600 * 1000)
        verify(isNaN(FilmDays.daySpan([]).beginMs))
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

    function projectOf(ts) {
        return ts.project
    }

    function test_pickDayEntrySkipsRunningEntry() {
        var running = { id: 1, project: 5, begin: "2026-09-23T09:00:00", end: null }
        var stopped = { id: 2, project: 7, begin: "2026-09-23T08:00:00", end: "2026-09-23T08:30:00" }
        var stoppedSame = { id: 3, project: 5, begin: "2026-09-23T07:00:00", end: "2026-09-23T08:00:00" }
        compare(FilmDays.pickDayEntry([running, stopped], 5, projectOf), null)
        compare(FilmDays.pickDayEntry([running, stopped, stoppedSame], 5, projectOf).id, 3)
    }

    function test_pickDayEntryOnlySameProject() {
        var a = { id: 1, project: 7, end: "2026-09-23T10:00:00" }
        var b = { id: 2, project: 5, end: "2026-09-23T18:00:00" }
        compare(FilmDays.pickDayEntry([a, b], 5, projectOf).id, 2)
        compare(FilmDays.pickDayEntry([a, b], null, projectOf), null)
        compare(FilmDays.pickDayEntry([a], 5, projectOf), null)
    }

    // A film day with travel entries (Kimai time format +0200).
    function travelDay() {
        return [
            { id: 4246, project: 155, begin: "2026-09-25T21:31:00+0200", end: "2026-09-25T21:56:00+0200" },
            { id: 4245, project: 155, begin: "2026-09-25T13:15:00+0200", end: "2026-09-25T21:30:00+0200" },
            { id: 4244, project: 155, begin: "2026-09-25T12:15:00+0200", end: "2026-09-25T12:45:00+0200" },
            { id: 4243, project: 153, begin: "2026-09-25T09:59:00+0200", end: "2026-09-25T11:22:36+0200" }
        ]
    }

    // The plugin's day summary names the film day's span: that entry, not the first one.
    function test_pickDayEntryMatchesSummarySpan() {
        var span = { begin: "2026-09-25T13:15:00+02:00", end: "2026-09-25T21:30:00+02:00" }
        compare(FilmDays.pickDayEntry(travelDay(), 155, projectOf, span).id, 4245)
    }

    // Without a summary the longest entry of the project is the film day.
    function test_pickDayEntryLongestWithoutSpan() {
        compare(FilmDays.pickDayEntry(travelDay(), 155, projectOf).id, 4245)
        compare(FilmDays.pickDayEntry(travelDay(), 155, projectOf, null).id, 4245)
    }

    // Travel and other activities of the project are no film day of their own
    // and must not be offered for merging: only the film day's activity counts.
    function test_otherDayEntriesOnlySameActivity() {
        var day = [
            { id: 4246, project: 155, activity: 12, begin: "2026-09-25T21:31:00+0200", end: "2026-09-25T21:56:00+0200" },
            { id: 4245, project: 155, activity: 40, begin: "2026-09-25T13:15:00+0200", end: "2026-09-25T21:30:00+0200" },
            { id: 4244, project: 155, activity: 12, begin: "2026-09-25T12:15:00+0200", end: "2026-09-25T12:45:00+0200" },
            { id: 4247, project: 155, activity: 40, begin: "2026-09-25T08:00:00+0200", end: "2026-09-25T09:00:00+0200" }
        ]
        var activityOf = function(ts) { return ts.activity }
        var others = FilmDays.otherDayEntries(day, day[1], 155, projectOf, activityOf)
        compare(others.map(function(o) { return o.id }), [4247])
    }

    // The film day screen's state: running (the timer on this project today),
    // done (an entry), before (today or later, nothing yet), manual (a past day).
    function test_phaseOf() {
        compare(FilmDays.phaseOf({ running: true, match: null, daysFromToday: 0 }), "running")
        compare(FilmDays.phaseOf({ running: false, match: { id: 1 }, daysFromToday: -1 }), "done")
        compare(FilmDays.phaseOf({ running: false, match: null, daysFromToday: 0 }), "before")
        compare(FilmDays.phaseOf({ running: false, match: null, daysFromToday: 2 }), "before")
        compare(FilmDays.phaseOf({ running: false, match: null, daysFromToday: -1 }), "manual")
    }

    // Before the first entry of the day: the project's usual film activity,
    // i.e. the activity of its longest recent entry (not the travel).
    function test_suggestedActivityId() {
        var recent = [
            { project: 155, activity: 12, begin: "2026-09-25T21:31:00+0200", end: "2026-09-25T21:56:00+0200" },
            { project: 155, activity: 40, begin: "2026-09-25T13:15:00+0200", end: "2026-09-25T21:30:00+0200" },
            { project: 153, activity: 7, begin: "2026-09-25T09:59:00+0200", end: "2026-09-25T18:22:36+0200" }
        ]
        var activityOf = function(ts) { return ts.activity }
        compare(FilmDays.suggestedActivityId(recent, 155, projectOf, activityOf), 40)
        compare(FilmDays.suggestedActivityId(recent, 999, projectOf, activityOf), null)
    }

    // Production shooting day: distinct days with entries up to the day.
    function test_countShootingDays() {
        var e = [
            { begin: "2026-09-10T08:00:00+0200" }, { begin: "2026-09-10T14:00:00+0200" },
            { begin: "2026-09-24T11:50:00+0200" }, { begin: "2026-09-25T13:15:00+0200" },
            { begin: "2026-09-27T08:00:00+0200" }
        ]
        var beginOf = function(ts) { return ts.begin }
        var r = FilmDays.countShootingDays(e, "2026-09-25", beginOf)
        compare(r.count, 3)
        verify(r.includesDay)
        r = FilmDays.countShootingDays(e, "2026-09-26", beginOf)
        compare(r.count, 3)
        verify(!r.includesDay)
    }

    function test_saveTargetIdOnlyForSameProject() {
        var other = { id: 1, project: 7, end: "2026-09-23T10:00:00" }
        compare(FilmDays.saveTargetId(other, 5, projectOf), null)
        compare(FilmDays.saveTargetId(other, "7", projectOf), 1)
        compare(FilmDays.saveTargetId({ id: 3, project: 5, end: null }, 5, projectOf), null)
        compare(FilmDays.saveTargetId(null, 5, projectOf), null)
    }

    // ── Drehzettel API mapping ──

    function serverDay(overrides) {
        var d = {
            date: "2026-09-14", engagementId: 1, breakMinutes: null, catering: false,
            category: null, note: null, dayType: "workday", productionDay: null,
            extraPayCents: 0, shootingDayNumber: null, defaultBreakMinutes: 45,
            effectiveCategory: "workday"
        }
        for (var k in (overrides || {})) {
            d[k] = overrides[k]
        }
        return d
    }

    function test_toApiMapsEveryField() {
        var api = FilmDays.toApi({
            breakMinutes: 30, catering: "yes", category: "", dayType: "travel",
            productionDay: 37, surchargeDay: 6, extraPayCents: 2500, note: "  Nacht  "
        })
        compare(api.breakMinutes, 30)
        compare(api.catering, true)
        compare(api.category, null)
        compare(api.dayType, "travel")
        compare(api.shootingDayNumber, 37)
        compare(api.productionDay, 6)
        compare(api.extraPayCents, 2500)
        compare(api.note, "Nacht")
    }

    function test_toApiEmptyValues() {
        var api = FilmDays.toApi({
            breakMinutes: null, catering: "no", category: "holiday", dayType: "workday",
            productionDay: 0, surchargeDay: null, extraPayCents: 0, note: "   "
        })
        compare(api.breakMinutes, null)
        compare(api.catering, false)
        compare(api.category, "holiday")
        compare(api.shootingDayNumber, null)   // local 0 = not set (B5)
        compare(api.productionDay, null)
        compare(api.note, null)
    }

    function test_toApiClampsRanges() {
        var api = FilmDays.toApi({ breakMinutes: 900, productionDay: 5000, surchargeDay: 9, extraPayCents: -3,
                                   note: new Array(600).join("x") })
        compare(api.breakMinutes, 720)
        compare(api.shootingDayNumber, 999)
        compare(api.productionDay, 7)
        compare(api.extraPayCents, 0)
        compare(api.note.length, 500)
    }

    function test_fromApiRoundTrip() {
        var local = FilmDays.fromApi(serverDay({ breakMinutes: 60, catering: true, category: "sunday",
            dayType: "travel", shootingDayNumber: 12, productionDay: 3, extraPayCents: 999, note: "n" }))
        compare(local.breakMinutes, 60)
        compare(local.catering, "yes")
        compare(local.category, "sunday")
        compare(local.dayType, "travel")
        compare(local.productionDay, 12)
        compare(local.surchargeDay, 3)
        compare(local.extraPayCents, 999)
        compare(local.note, "n")
        compare(Object.keys(FilmDays.toApiPatch(local, serverDay({ breakMinutes: 60, catering: true,
            category: "sunday", dayType: "travel", shootingDayNumber: 12, productionDay: 3,
            extraPayCents: 999, note: "n" }))).length, 0)
    }

    function test_fromApiDefaults() {
        var local = FilmDays.fromApi(serverDay())
        compare(local.breakMinutes, null)   // null = ruleset default, not 45
        compare(local.catering, "no")
        compare(local.category, "")
        compare(local.productionDay, null)
        compare(local.note, "")
    }

    function test_fromApiOldPluginHasNoExtraPay() {
        var json = serverDay()
        delete json.extraPayCents
        compare(FilmDays.fromApi(json).extraPayCents, 0)
    }

    function test_toApiPatchOnlyChangedKeys() {
        var server = serverDay({ catering: true, note: "alt" })
        var local = FilmDays.fromApi(server)
        local.breakMinutes = 30
        local.note = "neu"
        var patch = FilmDays.toApiPatch(local, server)
        // The note is the Kimai entry's description: never part of the film-day PUT.
        compare(Object.keys(patch).sort().join(","), "breakMinutes")
        compare(patch.breakMinutes, 30)
    }

    function test_noteOfEntry() {
        compare(FilmDays.noteOf({ description: "  Regen " }), "Regen")
        compare(FilmDays.noteOf({ description: null }), "")
        compare(FilmDays.noteOf(null), "")
    }

    function test_toApiPatchResetToDefaultSendsNull() {
        var server = serverDay({ breakMinutes: 30, category: "holiday" })
        var local = FilmDays.fromApi(server)
        local.breakMinutes = null
        local.category = ""
        var patch = FilmDays.toApiPatch(local, server)
        compare(patch.breakMinutes, null)
        compare(patch.category, null)
        compare(Object.keys(patch).length, 2)
    }

    function test_toApiPatchSkipsKeysUnknownToServer() {
        var server = serverDay()
        delete server.extraPayCents
        delete server.shootingDayNumber
        var patch = FilmDays.toApiPatch({ extraPayCents: 500, productionDay: 4, catering: "yes" }, server)
        verify(!patch.hasOwnProperty("extraPayCents"))
        verify(!patch.hasOwnProperty("shootingDayNumber"))
        compare(patch.catering, true)
    }

    function test_toApiPatchWithoutServerSendsAll() {
        compare(Object.keys(FilmDays.toApiPatch(FilmDays.entryDefaults(), null)).length,
                FilmDays.API_FIELDS.length)
    }
}
