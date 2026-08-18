import QtQuick
import QtTest
import "../../contents/code/timeTracker.js" as TimeTracker

TestCase {
    name: "TimeTracker"

    function test_providerIds() {
        var ids = TimeTracker.providerIds()
        verify(ids.indexOf("kimai") >= 0)
        verify(ids.indexOf("clockify") >= 0)
        verify(ids.indexOf("toggl") >= 0)
        verify(ids.indexOf("solidtime") >= 0)
    }

    function test_normalizeAndMeta() {
        compare(TimeTracker.normalizeProviderId("KIMAI"), "kimai")
        compare(TimeTracker.normalizeProviderId(""), "kimai")
        compare(TimeTracker.providerMeta("kimai").needsUrl, true)
        compare(TimeTracker.providerMeta("clockify").needsUrl, false)
        verify(TimeTracker.providerCapabilities("kimai").colorDistinction)
        verify(TimeTracker.providerCapabilities("kimai").tags)
        verify(TimeTracker.providerCapabilities("kimai").billableEdit)
        verify(TimeTracker.providerCapabilities("toggl").tags)
        verify(!TimeTracker.providerCapabilities("clockify").tags)
        verify(TimeTracker.providerCapabilities("clockify").billableEdit)
        verify(TimeTracker.providerCapabilities("kimai").deleteEntry)
        verify(TimeTracker.providerCapabilities("kimai").editStopped)
        verify(TimeTracker.providerCapabilities("clockify").deleteEntry)
        verify(TimeTracker.providerCapabilities("toggl").editStopped)
        verify(TimeTracker.providerCapabilities("kimai").createEntities)
        verify(TimeTracker.providerCapabilities("clockify").createEntities)
        verify(TimeTracker.isImplemented("kimai"))
    }

    function test_resolveUrl() {
        compare(TimeTracker.resolveUrl({ provider: "kimai", url: "https://a.example/" }),
                "https://a.example")
        compare(TimeTracker.resolveUrl({ provider: "clockify", url: "" }),
                "https://api.clockify.me/api/v1")
    }

    function test_apiShape() {
        var api = TimeTracker.api("kimai")
        compare(typeof api.loadProjects, "function")
        compare(typeof api.startTracking, "function")
        compare(typeof api.deleteTimesheet, "function")
        compare(typeof api.createCustomer, "function")
        compare(typeof api.createProject, "function")
        compare(typeof api.createActivity, "function")
        var clockify = TimeTracker.api("clockify")
        compare(typeof clockify.loadProjects, "function")
        compare(typeof clockify.deleteTimesheet, "function")
    }

    function test_displayNames() {
        compare(TimeTracker.providerDisplayName("kimai"), "Kimai")
        var names = TimeTracker.providerNames()
        verify(names.length === TimeTracker.providerIds().length)
    }
}
