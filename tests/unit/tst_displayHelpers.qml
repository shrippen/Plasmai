import QtQuick
import QtTest
import "../../contents/code/dateTimeFormat.js" as DTF
import "../../contents/code/dayIntervals.js" as Intervals
import "../../contents/code/entityColors.js" as Colors
import "../../contents/code/entityNames.js" as Names
import "../../contents/code/entityPickers.js" as Pickers
import "../../contents/code/providerUtil.js" as ProviderUtil
import "../../contents/code/timesheetFields.js" as Fields
import "../../contents/code/workContractAdjust.js" as WorkAdjust

/** Display helpers and the day calculation every service uses (no requests). */
TestCase {
    name: "DisplayHelpers"

    // Short durations drop "0m" on full hours ("14h", chart axes, work time).
    function test_formatDurationShort() {
        compare(DTF.formatDurationShort(14 * 3600), "14h")
        compare(DTF.formatDurationShort(53 * 3600 + 21 * 60), "53h 21m")
        compare(DTF.formatDurationShort(45 * 60), "45m")
        compare(DTF.formatDurationShort(0), "0m")
    }

    // A time to write carries the device's offset, so Kimai converts it into the profile's zone.
    function test_localDateTimeStringCarriesTheOffset() {
        var d = new Date(2026, 8, 30, 4, 5, 6)
        var offset = -d.getTimezoneOffset()
        var abs = Math.abs(offset)
        var expected = "+0000"
        expected = (offset < 0 ? "-" : "+") + (Math.floor(abs / 60) < 10 ? "0" : "") + Math.floor(abs / 60)
            + (abs % 60 < 10 ? "0" : "") + (abs % 60)
        compare(DTF.localDateTimeString(d), "2026-09-30T04:05:06" + expected)
        verify(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}$/.test(DTF.localDateTimeString(d)))
        // The parser reads it back to the same instant.
        compare(new Date(DTF.localDateTimeString(d).replace(/([+-]\d{2})(\d{2})$/, "$1:$2")).getTime(), d.getTime())
    }

    function test_localDateString() {
        compare(DTF.localDateString(new Date(2026, 0, 5, 23, 59)), "2026-01-05")
    }

    // The query filters (begin/end) stay without an offset: Kimai answers 400 to one.
    function test_localQueryStringHasNoOffset() {
        compare(DTF.localQueryString(new Date(2026, 8, 30, 4, 5, 6)), "2026-09-30T04:05:06")
    }

    function test_formatDuration() {
        compare(DTF.formatDuration(0), "00:00:00")
        compare(DTF.formatDuration(65), "00:01:05")
        compare(DTF.formatDuration(3600 + 61), "01:01:01")
        compare(DTF.formatDurationPanel(59), "00:59")
        compare(DTF.formatDurationPanel(3600), "1:00:00")
    }

    function test_parseTimeToMinutes() {
        compare(Intervals.parseTimeToMinutes("09:00", 0), 9 * 60)
        compare(Intervals.parseTimeToMinutes("18:30", 0), 18 * 60 + 30)
        compare(Intervals.parseTimeToMinutes("bogus", 99), 99)
        compare(Intervals.parseTimeToMinutes("", 8 * 60), 8 * 60)
    }

    function test_isWithinWorkHours() {
        var noon = new Date(2026, 2, 10, 12, 0, 0)
        var early = new Date(2026, 2, 10, 7, 0, 0)
        var late = new Date(2026, 2, 10, 19, 0, 0)
        var night = new Date(2026, 2, 10, 23, 0, 0)
        var wee = new Date(2026, 2, 10, 3, 0, 0)
        verify(Intervals.isWithinWorkHours("08:00", "18:00", noon))
        verify(!Intervals.isWithinWorkHours("08:00", "18:00", early))
        verify(!Intervals.isWithinWorkHours("08:00", "18:00", late))
        verify(Intervals.isWithinWorkHours("22:00", "06:00", night))
        verify(Intervals.isWithinWorkHours("22:00", "06:00", wee))
        verify(!Intervals.isWithinWorkHours("22:00", "06:00", noon))
    }

    function test_splitActivities() {
        var acts = [
            { id: 1, name: "Global", project: null },
            { id: 2, name: "This", project: 4 },
            { id: 3, name: "Other", project: 9 }
        ]
        var split = Pickers.splitActivitiesForProject(acts, 4)
        compare(split.projectSpecific.length, 1)
        compare(split.projectSpecific[0].id, 2)
        compare(split.global.length, 1)
        var model = Pickers.activitiesListModel(acts, 4)
        compare(model.length, 2)
        compare(model[0].section, "project")
        compare(model[1].section, "global")
    }

    function test_projectsGroupedAndPicker() {
        var customers = [{ id: 1, name: "Acme", color: "#ff0000" }]
        var projects = [
            { id: 10, name: "Beta", customer: 1, color: "#00ff00" },
            { id: 11, name: "Alpha", customer: 1 }
        ]
        var rows = Pickers.projectsGroupedByCustomer(projects, customers)
        compare(rows.length, 2)
        compare(rows[0].project.name, "Alpha")
        compare(rows[0].customerName, "Acme")
        var items = Pickers.projectPickerItems(projects, customers)
        compare(items.length, 2)
        compare(items[0].value.id, 11)
    }

    function test_hydrateTimesheetNames() {
        var projects = [{ id: 4, name: "Proj", customer: 1 }]
        var activities = [{ id: 35, name: "Act" }]
        var entries = [{ id: 99, project: 4, activity: 35, duration: 60, tags: ["ops"], billable: true }]
        var out = Fields.hydrateTimesheets(entries, projects, activities, {})
        compare(out.length, 1)
        compare(Names.projectId(out[0]), 4)
        compare(Names.activityId(out[0]), 35)
        compare(out[0].tags[0], "ops")
        verify(out[0].billable)
    }

    function test_weekBoundsMonday() {
        var wed = new Date(2026, 7, 12, 15, 0, 0) // Wed Aug 12 2026
        var start = WorkAdjust.startOfWeekMonday(wed)
        compare(start.getDay(), 1)
        compare(start.getDate(), 10)
        var end = WorkAdjust.endOfWeekSunday(wed)
        compare(end.getDay(), 0)
        compare(end.getDate(), 16)
    }

    function test_buildCustomersById() {
        var map = Names.buildCustomersById([{ id: 1, name: "A" }, { id: 2, name: "B" }])
        compare(map["1"].name, "A")
        compare(map["2"].name, "B")
    }

    function test_deduplicateRecent() {
        var entries = [
            { project: 1, activity: 2, begin: "2026-01-01" },
            { project: 1, activity: 2, begin: "2026-01-02" },
            { project: 3, activity: 4, begin: "2026-01-03" }
        ]
        var uniq = Fields.deduplicateRecent(entries)
        compare(uniq.length, 2)
    }

    function test_panelPillInfo() {
        var customers = [{ id: 1, name: "Acme", color: "#ff0000" }]
        var byId = Names.buildCustomersById(customers)
        var projects = [{ id: 10, name: "Site", customer: 1, color: "#00aa00" }]
        var info = Colors.panelPillInfo(
            { project: 10, activity: 2 }, projects, byId)
        compare(info.customerId, 1)
        compare(info.projectId, 10)
        compare(info.customerColor, ProviderUtil.normalizeCustomerColor("#ff0000"))
        compare(info.projectColor, ProviderUtil.normalizeCustomerColor("#00aa00"))
        var noProjectColor = Colors.panelPillInfo(
            { project: { id: 11, customer: 1 } }, [], byId)
        compare(noProjectColor.customerColor, ProviderUtil.normalizeCustomerColor("#ff0000"))
        compare(noProjectColor.projectColor, noProjectColor.customerColor)
    }

    function test_colorPrecedence() {
        var byId = Names.buildCustomersById([{ id: 1, name: "Acme", color: "#ff0000" }])
        var red = ProviderUtil.normalizeCustomerColor("#ff0000")
        var green = ProviderUtil.normalizeCustomerColor("#00aa00")
        var blue = ProviderUtil.normalizeCustomerColor("#0000ff")
        var withColor = { id: 10, customer: 1, color: "#00aa00" }
        var noColor = { id: 11, customer: 1 }

        // project before customer
        compare(Colors.projectBarColor(withColor, byId), green)
        compare(Colors.projectBarColor(noColor, byId), red)
        compare(Colors.projectBarColor(null, byId), ProviderUtil.DEFAULT_CUSTOMER_COLOR)

        // activity before project before customer
        var ts = { project: withColor, activity: { id: 5, color: "#0000ff" } }
        compare(Colors.timesheetBarColor(ts, byId), blue)
        ts = { project: withColor, activity: { id: 5 } }
        compare(Colors.timesheetBarColor(ts, byId), green)
        ts = { project: noColor, activity: { id: 5 } }
        compare(Colors.timesheetBarColor(ts, byId), red)
        compare(Colors.timesheetBarColor(null, byId), ProviderUtil.DEFAULT_CUSTOMER_COLOR)
    }

    function test_tagEntityColor() {
        compare(Fields.tagEntityColor({ name: "ops", "color-safe": "#336699" }), "#336699")
        verify(Fields.tagEntityColor({ name: "generated" }).length > 0)
        compare(Fields.tagEntityName({ name: "review" }), "review")
    }

    // Names sort Aa→Zz: case and accents do not split the alphabet (Android's
    // localeCompare compares code points: "Zeta" before "alpha").
    function test_compareNames() {
        var names = ["zulu", "Beta", "ärger", "Zeta", "alpha"]
        names.sort(Names.compareNames)
        compare(names, ["alpha", "ärger", "Beta", "Zeta", "zulu"])
        var rows = Pickers.projectsGroupedByCustomer(
            [{ id: 1, name: "website", customer: 1 }, { id: 2, name: "Admin", customer: 1 }, { id: 3, name: "buch", customer: 2 }],
            [{ id: 1, name: "studio" }, { id: 2, name: "Agentur" }])
        compare(rows.map(function(r) { return r.project.name }), ["buch", "Admin", "website"])
        var acts = Pickers.activitiesListModel([{ id: 1, name: "meeting" }, { id: 2, name: "Design" }], 0)
        compare(acts.map(function(r) { return r.activity.name }), ["Design", "meeting"])
    }

    function test_pickersHideHiddenEntries() {
        var customers = [{ id: 1, name: "Visible", visible: true }, { id: 2, name: "Gone", visible: false }]
        var projects = [
            { id: 10, name: "P visible", customer: 1, visible: true },
            { id: 11, name: "P hidden", customer: 1, visible: false },
            { id: 12, name: "P of hidden customer", customer: 2, visible: true }
        ]
        var items = Pickers.projectPickerItems(projects, customers)
        compare(items.length, 1)
        compare(items[0].value.id, 10)

        var activities = [
            { id: 1, name: "A", project: null, visible: true },
            { id: 2, name: "B", project: null, visible: false },
            { id: 3, name: "C", project: 10 }
        ]
        var acts = Pickers.activityPickerItems(activities, 10, projects[0], {})
        compare(acts.length, 2)
    }

    function test_dayIntervalsWallClock() {
        var day = new Date(2026, 8, 25, 12, 0, 0)
        var entries = [{ begin: "2026-09-25T09:00:00", end: "2026-09-25T10:30:15" }]
        var iv = Intervals.dayIntervalsFromTimesheets(entries, day, day.getTime())
        compare(iv.length, 1)
        compare(iv[0].startSec, 9 * 3600)
        compare(iv[0].endSec, 10 * 3600 + 30 * 60 + 15)
    }

    function test_customerCurrencyOfProject() {
        compare(Names.customerCurrencyOfProject({ customer: 3 }, [{ id: 3, currency: "CHF" }]), "CHF")
        compare(Names.customerCurrencyOfProject({ customer: { id: 3, currency: "EUR" } }, []), "EUR")
        compare(Names.customerCurrencyOfProject({ customer: 4 }, [{ id: 3, currency: "CHF" }]), "")
        compare(Names.customerCurrencyOfProject(null, []), "")
    }
}
