import QtQuick
import QtTest
import "../../contents/code/workContractAdjust.js" as WorkAdjust
import "../../contents/code/kimaiApi.js" as KimaiApi

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
        var base = KimaiApi.effectiveWeekTargetSeconds(prefs, monday, [], [])
        compare(base, 40 * 3600)

        var absences = [{
            type: "vacation",
            status: "approved",
            startDate: "2026-08-19",
            endDate: "2026-08-19",
            halfDay: false
        }]
        var adjusted = KimaiApi.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        compare(adjusted, 32 * 3600)
    }

    function test_publicHolidayReducesWeek() {
        var monday = new Date(2026, 7, 17, 12, 0, 0)
        var prefs = weekPrefs()
        var holidays = [{ date: "2026-08-20", halfDay: false }]
        var adjusted = KimaiApi.effectiveWeekTargetSeconds(prefs, monday, [], holidays)
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
        var adjusted = KimaiApi.effectiveWeekTargetSeconds(prefs, monday, absences, [])
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
        var adjusted = KimaiApi.effectiveWeekTargetSeconds(prefs, monday, absences, [])
        compare(adjusted, 40 * 3600)
    }
}
