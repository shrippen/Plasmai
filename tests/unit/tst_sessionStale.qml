import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/dateTimeFormat.js" as DTF
import "../../contents/code/entityNames.js" as Names
import "../../contents/code/demoKimai.js" as DemoKimai
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig

/**
 * The statistics' range goes stale after every write that changes an entry, whether or
 * not the write sets session.busy: real SessionEntries, SessionTimer and SessionFilmDay
 * against the demo Kimai.
 */
TestCase {
    name: "SessionStale"

    property var files: ({})

    function backend(shared) {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, _id, cb) { cb("", null) },
            loadLocal: function(_ds, name, cb) { cb(files[name] || null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = payload; cb(true, null) }
        }
    }

    function demoShared() {
        const list = Profiles.withDemoProfile(Profiles.defaultProfiles(), DemoKimai.DEMO_URL, "Demo")
        const shared = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "demo" }
        shared[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
        return shared
    }

    Component {
        id: sessionComponent
        Ui.Session { }
    }

    Component {
        id: signalSpy
        SignalSpy { }
    }

    function initTestCase() {
        KimaiApi.setUrlRoute(DemoKimai.ROUTE)
    }

    function cleanupTestCase() {
        KimaiApi.setUrlRoute(null)
    }

    function openDemo() {
        Platform.setBackend(backend(demoShared()))
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "state", s.connection.online)
        tryVerify(function() { return s.recent.list.length > 0 && s.catalog.projects.length > 0 })
        tryCompare(s, "busy", false)
        return s
    }

    function filmDay9to17(note) {
        const day = new Date()
        day.setDate(day.getDate() - 4)
        day.setHours(0, 0, 0, 0)
        return {
            projectId: DemoKimai.FILM_PROJECT, activityId: DemoKimai.SHOOTING, date: day,
            beginText: DTF.localDateString(day) + "T09:00:00", endText: DTF.localDateString(day) + "T17:00:00",
            fields: {}, direct: true, mergeIds: [], breakMinutes: 0, note: note
        }
    }

    // The statistics hold entries: every write that changes one marks them stale, busy or not.
    function staleAfter(s, action) {
        tryCompare(s, "busy", false)
        s.stats.stale = false
        action()
        tryVerify(function() { return s.stats.stale })
    }

    function test_writesMakeTheStatisticsStale() {
        const s = openDemo()
        const first = s.recent.list[0]
        const day = new Date()
        day.setDate(day.getDate() - 3)
        day.setHours(9, 0, 0, 0)
        const fields = { project: Names.projectId(first), activity: Names.activityId(first),
                         begin: DTF.localDateTimeString(day),
                         end: DTF.localDateTimeString(new Date(day.getTime() + 2 * 3600 * 1000)),
                         description: "stale marker" }
        let created = null
        staleAfter(s, function() { s.entries.write(null, fields, function(r) { created = r.data }) })
        tryVerify(function() { return created !== null })
        staleAfter(s, function() { s.entries.write(created.id, { description: "stale edited" }, function() {}) })
        staleAfter(s, function() { s.entries.edit(created, { description: "stale again" }) })
        staleAfter(s, function() { s.entries.split(created, new Date(day.getTime() + 3600 * 1000)) })
        staleAfter(s, function() { s.entries.remove(created) })
    }

    function test_filmDayWritesMakeTheStatisticsStale() {
        const s = openDemo()
        tryVerify(function() { return s.filmDay.available })
        const req = filmDay9to17("stale flow")
        let answer = null
        staleAfter(s, function() { s.filmDay.saveDay(req, function(r) { answer = r }) })
        tryVerify(function() { return answer !== null })
        verify(answer.ok)
    }

    function test_runningEntryWritesMakeTheStatisticsStale() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        staleAfter(s, function() { s.timer.patchActive({ description: "stale running" }) })
        staleAfter(s, function() { s.timer.stop() })
        tryVerify(function() { return !s.timer.tracking })
        staleAfter(s, function() { s.timer.continueEntry(s.recent.list[0]) })
    }

    function test_failedWriteLeavesTheStatisticsAlone() {
        const s = openDemo()
        tryCompare(s, "busy", false)
        s.stats.stale = false
        const failed = createTemporaryObject(signalSpy, this, { target: s, signalName: "failed" })
        s.entries.write(987654321, { description: "nobody" }, function() {})
        tryVerify(function() { return failed.count > 0 })
        verify(!s.stats.stale)
    }
}
