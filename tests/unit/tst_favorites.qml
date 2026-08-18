import QtQuick
import QtTest
import "../../contents/code/favorites.js" as Favorites

TestCase {
    name: "Favorites"

    function test_parseEmpty() {
        compare(Favorites.parsePinned("").length, 0)
        compare(Favorites.parsePinned(null).length, 0)
        compare(Favorites.parsePinned(";;;").length, 0)
        compare(Favorites.parsePinned("4").length, 0)
    }

    function test_parseNumericAndUuid() {
        var entries = Favorites.parsePinned("4:35;abc-id:def-id")
        compare(entries.length, 2)
        compare(entries[0].projectId, 4)
        compare(entries[0].activityId, 35)
        compare(entries[1].projectId, "abc-id")
        compare(entries[1].activityId, "def-id")
    }

    function test_serializeRoundTrip() {
        var src = "4:35;9:1"
        compare(Favorites.serializePinned(Favorites.parsePinned(src)), src)
    }

    function test_toggleAddAndRemove() {
        var s = Favorites.togglePinned("", 4, 35)
        compare(s, "4:35")
        verify(Favorites.isPinned(s, 4, 35))
        verify(!Favorites.isPinned(s, 4, 99))
        s = Favorites.togglePinned(s, 4, 35)
        compare(s, "")
    }

    function test_resolvePinnedUsesCatalog() {
        var projects = [{ id: 4, name: "P", customer: 1 }]
        var customersById = { "1": { id: 1, name: "C", color: "#ff0000" } }
        var allActivities = [{ id: 35, name: "Coding", project: 4 }]
        var rows = Favorites.resolvePinnedEntries("4:35", projects, {}, customersById, allActivities)
        compare(rows.length, 1)
        compare(rows[0].activityName, "Coding")
        compare(rows[0].projectId, 4)
    }

    function test_asTimesheetShape() {
        var ts = Favorites.asTimesheet({
            projectId: 4,
            activityId: 35,
            projectName: "P",
            activityName: "Coding",
            customerName: "C"
        })
        compare(ts.project.id, 4)
        compare(ts.activity.id, 35)
        compare(ts.project.name, "P")
        compare(ts.activity.name, "Coding")
        compare(ts.project.customer.name, "C")
        compare(Favorites.asTimesheet(null), null)
    }
}
