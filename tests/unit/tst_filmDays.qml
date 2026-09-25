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
            productionDay: 37, consecutiveDay: 6, extraPayCents: 2500, note: "  Nacht  "
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
            productionDay: 0, consecutiveDay: null, extraPayCents: 0, note: "   "
        })
        compare(api.breakMinutes, null)
        compare(api.catering, false)
        compare(api.category, "holiday")
        compare(api.shootingDayNumber, null)   // local 0 = not set (B5)
        compare(api.productionDay, null)
        compare(api.note, null)
    }

    function test_toApiClampsRanges() {
        var api = FilmDays.toApi({ breakMinutes: 900, productionDay: 5000, extraPayCents: -3,
                                   note: new Array(600).join("x") })
        compare(api.breakMinutes, 720)
        compare(api.shootingDayNumber, 999)
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
        compare(local.consecutiveDay, 3)
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

    function test_fromApiKeepsLocalExtraPayForOldPlugin() {
        var json = serverDay()
        delete json.extraPayCents
        compare(FilmDays.fromApi(json, { extraPayCents: 700 }).extraPayCents, 700)
    }

    function test_toApiPatchOnlyChangedKeys() {
        var server = serverDay({ catering: true, note: "alt" })
        var local = FilmDays.fromApi(server)
        local.breakMinutes = 30
        local.note = "neu"
        var patch = FilmDays.toApiPatch(local, server)
        compare(Object.keys(patch).sort().join(","), "breakMinutes,note")
        compare(patch.breakMinutes, 30)
        compare(patch.note, "neu")
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

    function test_isServerEmpty() {
        verify(FilmDays.isServerEmpty(serverDay()))
        verify(!FilmDays.isServerEmpty(serverDay({ catering: true })))
        verify(!FilmDays.isServerEmpty(serverDay({ breakMinutes: 45 })))
        verify(!FilmDays.isServerEmpty(serverDay({ dayType: "travel" })))
        verify(!FilmDays.isServerEmpty(serverDay({ shootingDayNumber: 3 })))
        verify(!FilmDays.isServerEmpty(serverDay({ note: "x" })))
        verify(!FilmDays.isServerEmpty(serverDay({ extraPayCents: 1 })))
    }

    function test_baseAndServerMatch() {
        var server = serverDay({ note: "a" })
        var base = FilmDays.baseForPatch(server, { note: "b", catering: true })
        compare(base.note, "a")
        compare(base.catering, false)
        verify(FilmDays.serverMatchesBase(server, base))
        verify(!FilmDays.serverMatchesBase(serverDay({ note: "c" }), base))
    }

    // ── migration planner ──

    function test_planMigrationFiltersAndSorts() {
        var map = {}
        map = FilmDays.set(map, 1, "2026-09-02", FilmDays.entryDefaults())
        map = FilmDays.set(map, 1, "2026-09-01", FilmDays.entryDefaults())
        map = FilmDays.set(map, 9, "2026-09-01", FilmDays.entryDefaults())    // other instance's project
        map = FilmDays.set(map, "", "2026-09-01", FilmDays.entryDefaults())   // no project
        map["1|garbage"] = {}
        var plan = FilmDays.planMigration(map, [1, 2], "p|http://k")
        compare(plan.length, 2)
        compare(plan[0].date, "2026-09-01")
        compare(plan[1].date, "2026-09-02")
        compare(String(plan[0].projectId), "1")
        compare(plan[0].entry.breakMinutes, 45)
    }

    function test_planMigrationSkipsMigratedForSameProfileOnly() {
        var map = FilmDays.set({}, 1, "2026-09-01", FilmDays.entryDefaults())
        map = FilmDays.markMigrated(map, "1|2026-09-01", "p|http://k", "pushed", "2026-09-25T10:00:00Z")
        compare(FilmDays.planMigration(map, [1], "p|http://k").length, 0)
        compare(FilmDays.planMigration(map, [1], "other|http://x").length, 1)
        compare(map["1|2026-09-01"].migrated["p|http://k"].result, "pushed")
        // local values stay (rollback possible)
        compare(FilmDays.get(map, 1, "2026-09-01").breakMinutes, 45)
    }

    function test_planMigrationFlagsLongNote() {
        var e = FilmDays.entryDefaults()
        e.note = new Array(502).join("y")
        var plan = FilmDays.planMigration(FilmDays.set({}, 1, "2026-09-01", e), [1], "p")
        verify(plan[0].noteTruncated)
    }

    function test_migrationDecision() {
        var local = FilmDays.entryDefaults()     // explicit 45 break (B7)
        local.catering = "yes"
        local.productionDay = 0                  // 0 = empty (B5)
        var push = FilmDays.migrationDecision(local, serverDay())
        compare(push.action, "push")
        compare(push.patch.breakMinutes, 45)
        compare(push.patch.catering, true)
        verify(!push.patch.hasOwnProperty("shootingDayNumber"))
        compare(FilmDays.migrationDecision(local, serverDay({ breakMinutes: 45, catering: true })).action, "same")
        compare(FilmDays.migrationDecision(local, serverDay({ breakMinutes: 30 })).action, "conflict")
    }
}
