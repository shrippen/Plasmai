import QtQuick
import QtTest
import "../../contents/code/workContractAdjust.js" as WorkAdjust
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/workTotals.js" as WorkTotals

TestCase {
    name: "WorkContractAdjust"

    function weekPrefs() {
        return {
            work_contract_type: "week",
            hours_per_week: 40 * 3600,
            work_days_week: "1,2,3,4,5"
        }
    }

    function test_vacationReducesRemainingWeek() {
        // Monday 2026-08-17
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var base = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, [], [])
        compare(base, 40 * 3600)

        var absences = [{
            type: "vacation",
            status: "approved",
            startDate: "2026-08-19",
            endDate: "2026-08-19",
            halfDay: false
        }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        compare(adjusted, 32 * 3600)
    }

    function test_publicHolidayReducesWeek() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var holidays = [{ date: "2026-08-20", halfDay: false }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, [], holidays)
        compare(adjusted, 32 * 3600)
    }

    function test_halfDayVacation() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var absences = [{
            type: "vacation",
            status: "approved",
            startDate: "2026-08-19",
            endDate: "2026-08-19",
            halfDay: true
        }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        compare(adjusted, 36 * 3600)
    }

    function test_unapprovedVacationIgnored() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var absences = [{
            type: "vacation",
            status: "requested",
            startDate: "2026-08-19",
            endDate: "2026-08-19",
            halfDay: false
        }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        compare(adjusted, 40 * 3600)
    }

    function test_holidaySourceFromProbes() {
        compare(WorkAdjust.holidaySourceFromProbes(200, 404), WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
        compare(WorkAdjust.holidaySourceFromProbes(403, 200), WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
        compare(WorkAdjust.holidaySourceFromProbes(404, 200), WorkAdjust.SOURCE_WORK_CONTRACT)
        compare(WorkAdjust.holidaySourceFromProbes(404, 403), WorkAdjust.SOURCE_WORK_CONTRACT)
        compare(WorkAdjust.holidaySourceFromProbes(404, 404), WorkAdjust.SOURCE_NONE)
        compare(KimaiApi.holidaySourceFromProbes(404, 200), "work-contract")
    }

    function test_workContractHolidayTypeAndSnakeCase() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var absences = [{
            type: "holiday",
            status: "approved",
            date: "2026-08-19T00:00:00+02:00",
            half_day: false
        }]
        var holidays = [{ date: "2026-08-20T00:00:00+02:00", half_day: true }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, holidays)
        // Wednesday full holiday + Thursday half public holiday: 40 - 8 - 4
        compare(adjusted, 28 * 3600)
    }

    function test_workContractWrappedCollection() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var wrapped = {
            data: [{
                type: "holiday",
                status: "approved",
                date: "2026-08-19",
                half_day: false
            }]
        }
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, wrapped, [])
        compare(adjusted, 32 * 3600)
    }

    function test_timeOffDurationHours() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var absences = [{
            type: "time_off",
            status: "approved",
            date: "2026-08-19",
            duration: 4
        }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        compare(adjusted, 36 * 3600)
    }

    function test_absenceCreditAvoidsDoubleCount() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var absences = [{
            type: "holiday",
            status: "approved",
            date: "2026-08-19",
            half_day: false
        }]
        var entries = [{
            begin: "2026-08-19T08:00:00",
            end: "2026-08-19T16:00:00",
            duration: 8 * 3600
        }]
        var target = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        var credit = WorkTotals.absenceCreditSeconds(prefs, monday, absences, [], entries, monday.getTime())
        compare(target, 32 * 3600)
        compare(credit, 8 * 3600)
        compare(target - (40 * 3600) + credit, 0)
        // remaining = target - tracked + credit = 32h - 8h + 8h = 32h of work still expected
        compare(target - (8 * 3600) + credit, 32 * 3600)
    }

    function test_pluginCacheExpiresAfterOneHour() {
        var ttl = WorkAdjust.HOLIDAY_PLUGIN_TTL_MS
        compare(ttl, 60 * 60 * 1000)
        var entry = WorkAdjust.holidayPluginCacheEntry(WorkAdjust.SOURCE_WORK_CONTRACT, 1000)
        compare(WorkAdjust.holidayPluginCacheSource(entry, 1000), WorkAdjust.SOURCE_WORK_CONTRACT)
        compare(WorkAdjust.holidayPluginCacheSource(entry, 1000 + ttl - 1), WorkAdjust.SOURCE_WORK_CONTRACT)
        compare(WorkAdjust.holidayPluginCacheSource(entry, 1000 + ttl), "")
        compare(WorkAdjust.holidayPluginCacheSource(null, Date.now()), "")
        KimaiApi.resetHolidayPluginCache()
        KimaiApi.rememberHolidayPlugin("https://kimai.example/", WorkAdjust.SOURCE_HOLIDAY_BUNDLE, 5000)
        compare(KimaiApi.cachedHolidayPlugin("https://kimai.example", 5000 + 10), WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
        compare(KimaiApi.cachedHolidayPlugin("https://kimai.example", 5000 + ttl), "")
        KimaiApi.resetHolidayPluginCache()
    }

    function test_officialWorkContractApiDocumentShape() {
        // Shape from kimai/api-php Absence + PublicHoliday models (no live plugin).
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var absences = [
            {
                id: 42,
                user: { id: 1, alias: "Arian" },
                date: "2026-08-19T00:00:00+02:00",
                duration: null,
                type: "holiday",
                status: "approved",
                half_day: false
            },
            {
                id: 43,
                user: { id: 1 },
                date: "2026-08-21",
                type: "sickness",
                status: "new",
                half_day: true
            },
            {
                id: 44,
                date: "2026-08-18",
                type: "holiday",
                status: "rejected",
                half_day: false
            }
        ]
        var holidays = [{
            id: 7,
            date: "2026-08-20T00:00:00+02:00",
            name: "Assumption",
            half_day: false,
            public_holiday_group: { id: 1, name: "DE-TH" }
        }]
        var adjusted = WorkTotals.effectiveWeekTargetSeconds(prefs, monday, absences, holidays)
        // Wed holiday 8h + Thu public holiday 8h + Fri half sickness 4h; rejected Tue ignored
        compare(adjusted, 20 * 3600)
    }

    function test_hydraMemberWrapper() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var wrapped = {}
        wrapped["hydra:member"] = [{
            type: "holiday",
            status: "confirmed",
            date: "2026-08-19",
            half_day: false
        }]
        compare(WorkTotals.effectiveWeekTargetSeconds(weekPrefs(), monday, wrapped, []), 32 * 3600)
    }

    // -- Daily and weekly target from Kimai's work preferences

    function test_weekdayIsIsoMonday1Sunday7() {
        compare(KimaiApi.kimaiWeekday(new Date(2026, 7, 17)), 1)
        compare(KimaiApi.kimaiWeekday(new Date(2026, 7, 22)), 6)
        compare(KimaiApi.kimaiWeekday(new Date(2026, 7, 23)), 7)
    }

    function test_preferenceMapByName() {
        var user = { preferences: [{ name: "hours_per_week", value: "144000" }, null, { value: "x" }] }
        compare(JSON.stringify(KimaiApi.preferenceMap(user)), '{"hours_per_week":"144000"}')
        compare(JSON.stringify(KimaiApi.preferenceMap(null)), "{}")
    }

    function test_dayTargetFromWeekContract() {
        var monday = new Date(2026, 7, 17)
        var saturday = new Date(2026, 7, 22)
        compare(KimaiApi.workDaySecondsFromPrefs(weekPrefs(), monday), 8 * 3600)
        compare(KimaiApi.workDaySecondsFromPrefs(weekPrefs(), saturday), 0)
        compare(KimaiApi.workDaySecondsFromPrefs(null, monday), 0)
        compare(KimaiApi.workDaySecondsFromPrefs({}, monday), 0)
    }

    function test_dayTargetFromDayContract() {
        var prefs = { work_contract_type: "day", work_monday: "28800", work_tuesday: "14400" }
        compare(KimaiApi.workDaySecondsFromPrefs(prefs, new Date(2026, 7, 17)), 28800)
        compare(KimaiApi.workDaySecondsFromPrefs(prefs, new Date(2026, 7, 18)), 14400)
        compare(KimaiApi.workDaySecondsFromPrefs(prefs, new Date(2026, 7, 19)), 0)
    }

    function test_dayTargetFromMonthContract() {
        var prefs = { work_contract_type: "month", hours_per_month: 21.67 * 8 * 3600, work_days_month: "1,2,3,4,5" }
        compare(KimaiApi.workDaySecondsFromPrefs(prefs, new Date(2026, 7, 17)), 8 * 3600)
        compare(KimaiApi.workDaySecondsFromPrefs(prefs, new Date(2026, 7, 23)), 0)
    }

    function test_weekTargetPerContractType() {
        var anyDay = new Date(2026, 7, 19)
        compare(KimaiApi.workWeekSecondsFromPrefs(weekPrefs(), anyDay), 40 * 3600)
        var days = { work_contract_type: "day", work_monday: "28800", work_friday: "14400" }
        compare(KimaiApi.workWeekSecondsFromPrefs(days, anyDay), 28800 + 14400)
        compare(KimaiApi.workWeekSecondsFromPrefs({ work_contract_type: "none" }, anyDay), 0)
        compare(KimaiApi.workWeekSecondsFromPrefs(null, anyDay), 0)
    }
}
