import QtQuick
import QtTest
import "../../contents/code/kimaiApi.js" as KimaiApi

TestCase {
    name: "KimaiApi"

    function test_normalizeUrl() {
        compare(KimaiApi.normalizeUrl("https://ki.example.com/"), "https://ki.example.com")
        compare(KimaiApi.normalizeUrl("https://ki.example.com///"), "https://ki.example.com")
        compare(KimaiApi.normalizeUrl(""), "")
    }

    function test_formatDuration() {
        compare(KimaiApi.formatDuration(0), "00:00:00")
        compare(KimaiApi.formatDuration(65), "00:01:05")
        compare(KimaiApi.formatDuration(3600 + 61), "01:01:01")
        compare(KimaiApi.formatDurationPanel(59), "00:59")
        compare(KimaiApi.formatDurationPanel(3600), "1:00:00")
    }

    function test_parseTimeToMinutes() {
        compare(KimaiApi.parseTimeToMinutes("09:00", 0), 9 * 60)
        compare(KimaiApi.parseTimeToMinutes("18:30", 0), 18 * 60 + 30)
        compare(KimaiApi.parseTimeToMinutes("bogus", 99), 99)
        compare(KimaiApi.parseTimeToMinutes("", 8 * 60), 8 * 60)
    }

    function test_splitActivities() {
        var acts = [
            { id: 1, name: "Global", project: null },
            { id: 2, name: "This", project: 4 },
            { id: 3, name: "Other", project: 9 }
        ]
        var split = KimaiApi.splitActivitiesForProject(acts, 4)
        compare(split.projectSpecific.length, 1)
        compare(split.projectSpecific[0].id, 2)
        compare(split.global.length, 1)
        var model = KimaiApi.activitiesListModel(acts, 4)
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
        var rows = KimaiApi.projectsGroupedByCustomer(projects, customers)
        compare(rows.length, 2)
        compare(rows[0].project.name, "Alpha")
        compare(rows[0].customerName, "Acme")
        var items = KimaiApi.projectPickerItems(projects, customers)
        compare(items.length, 2)
        compare(items[0].value.id, 11)
    }

    function test_hydrateTimesheetNames() {
        var projects = [{ id: 4, name: "Proj", customer: 1 }]
        var activities = [{ id: 35, name: "Act" }]
        var entries = [{ id: 99, project: 4, activity: 35, duration: 60 }]
        var out = KimaiApi.hydrateTimesheets(entries, projects, activities, {})
        compare(out.length, 1)
        compare(KimaiApi.projectId(out[0]), 4)
        compare(KimaiApi.activityId(out[0]), 35)
    }

    function test_weekBoundsMonday() {
        var wed = new Date(2026, 7, 12, 15, 0, 0) // Wed Aug 12 2026
        var start = KimaiApi.startOfWeekMonday(wed)
        compare(start.getDay(), 1)
        compare(start.getDate(), 10)
        var end = KimaiApi.endOfWeekSunday(wed)
        compare(end.getDay(), 0)
        compare(end.getDate(), 16)
    }

    function test_buildCustomersById() {
        var map = KimaiApi.buildCustomersById([{ id: 1, name: "A" }, { id: 2, name: "B" }])
        compare(map["1"].name, "A")
        compare(map["2"].name, "B")
    }

    function test_deduplicateRecent() {
        var entries = [
            { project: 1, activity: 2, begin: "2026-01-01" },
            { project: 1, activity: 2, begin: "2026-01-02" },
            { project: 3, activity: 4, begin: "2026-01-03" }
        ]
        var uniq = KimaiApi.deduplicateRecent(entries)
        compare(uniq.length, 2)
    }

    function test_panelPillInfo() {
        var customers = [{ id: 1, name: "Acme", color: "#ff0000" }]
        var byId = KimaiApi.buildCustomersById(customers)
        var projects = [{ id: 10, name: "Site", customer: 1, color: "#00aa00" }]
        var info = KimaiApi.panelPillInfo(
            { project: 10, activity: 2 }, projects, byId)
        compare(info.customerId, 1)
        compare(info.projectId, 10)
        compare(info.customerColor, KimaiApi.normalizeCustomerColor("#ff0000"))
        compare(info.projectColor, KimaiApi.normalizeCustomerColor("#00aa00"))
        var noProjectColor = KimaiApi.panelPillInfo(
            { project: { id: 11, customer: 1 } }, [], byId)
        compare(noProjectColor.customerColor, KimaiApi.normalizeCustomerColor("#ff0000"))
        compare(noProjectColor.projectColor, noProjectColor.customerColor)
    }
}
