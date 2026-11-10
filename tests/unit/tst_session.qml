import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/demoKimai.js" as DemoKimai
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig

/**
 * Session.qml against the demo Kimai (in memory, no network): open, the
 * running entry, recents, stop, start, switch. The platform backend is an
 * in-memory shared.json and file store.
 */
TestCase {
    name: "Session"

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
        tryVerify(function() { return s.recent.list.length > 0 })
        return s
    }

    // The demo has a timer running (a shoot or the standby timer).
    function test_openShowsRunningEntryAndRecents() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        verify(KimaiApi.projectId(s.timer.active) > 0)
        verify(s.timer.elapsedSeconds >= 0)
        verify(s.connection.url.indexOf("demo.invalid") >= 0)
        tryVerify(function() { return s.totals.todayEntries.length > 0 })
    }

    function test_stopThenStartThenSwitch() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        const stopSpy = createTemporaryObject(signalSpy, this, { target: s, signalName: "stopped" })

        s.timer.stop()
        tryCompare(s.timer, "tracking", false)
        compare(stopSpy.count, 1)

        const first = s.recent.list[0]
        s.timer.start(KimaiApi.projectId(first), KimaiApi.activityId(first), "", "", "Test")
        tryCompare(s.timer, "tracking", true)
        compare(String(KimaiApi.activityId(s.timer.active)), String(KimaiApi.activityId(first)))

        const startSpy = createTemporaryObject(signalSpy, this, { target: s, signalName: "started" })
        const other = s.recent.list.filter(function(r) {
            return String(KimaiApi.activityId(r)) !== String(KimaiApi.activityId(first))
        })[0]
        verify(!!other)
        // Like the views: no switch while a refresh or write runs.
        tryCompare(s, "busy", false)
        s.timer.switchTo(KimaiApi.projectId(other), KimaiApi.activityId(other), "", "", "")
        tryVerify(function() { return s.timer.tracking && String(KimaiApi.activityId(s.timer.active)) === String(KimaiApi.activityId(other)) })
        compare(startSpy.count, 1)
        compare(startSpy.signalArguments[0][1], Ui.Session.Origin.Switch)
    }

    // The poll refreshes every 30 s: it shows the loading indicator, but does not lock
    // the inputs (session.busy), which restyled every control twice per poll.
    function test_refreshDoesNotLock() {
        const s = openDemo()
        tryCompare(s, "busy", false)
        tryCompare(s, "refreshing", false)
        s.refresh()
        verify(s.refreshing, "the indicator shows the refresh")
        verify(!s.busy, "inputs stay usable")
        tryCompare(s, "refreshing", false)
    }

    // Review of PR #50: without the lock of every refresh, a favorite or a recent row tapped
    // before the first answer started a timer while one ran on the server (no switch question),
    // and after a profile switch Stop sent the old profile's entry. Until the running entry is
    // known, writes wait; the poll keeps the inputs usable.
    function test_writesWaitForTheRunningEntry() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        tryCompare(s, "refreshing", false)
        verify(!s.locked, "known running entry: usable")
        s.timer.loaded = false
        verify(s.locked, "not known yet: locked")
        compare(s.timer.startPinned({ projectId: "1", activityId: "1" }), Ui.Session.Restart.Ignored)
        compare(s.timer.requestRestart(s.recent.list[0]), Ui.Session.Restart.Ignored)
        compare(s.timer.start("1", "1", "", "", ""), Ui.Session.Restart.Ignored)
        s.timer.stop()
        s.timer.continueEntry(s.recent.list[0])
        verify(!s.busy, "no write was sent")
        verify(s.timer.tracking)
        s.refresh()
        tryCompare(s.timer, "loaded", true)
        verify(!s.locked)
    }

    // A refresh asked before a write answers the state before it: dropped, the
    // write refreshes itself once it is through.
    function test_staleRefreshDropped() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        tryCompare(s, "refreshing", false)
        const shown = []
        function onActive() { shown.push(!!s.timer.active) }
        s.timer.refresh()
        s.timer.activeChanged.connect(onActive)
        s.timer.stop()
        tryCompare(s.timer, "tracking", false)
        tryCompare(s, "refreshing", false)
        s.timer.activeChanged.disconnect(onActive)
        // The demo world is shared by the tests: its timer runs again.
        DemoKimai.reset()
        compare(shown, [false], "only the stop shows")
    }

    // The poll reloads today and the week; the same entries keep the same arrays, so the
    // day sparkline and the charts do not recompute (sun and moon paths, every bar).
    function test_sameTotalsKeepArrays() {
        const s = openDemo()
        tryVerify(function() { return s.totals.todayEntries.length > 0 })
        const today = s.totals.todayEntries
        const week = s.totals.weekEntries
        let changes = 0
        function onChange() { changes++ }
        s.totals.todayEntriesChanged.connect(onChange)
        s.totals.weekEntriesChanged.connect(onChange)
        s.totals.refresh()
        wait(50)
        // Kimai: the running entry's duration has grown since the last poll.
        const grown = JSON.parse(JSON.stringify(today))
        grown.forEach(function(ts) { if (!ts.end) { ts.duration = (ts.duration || 0) + 30 } })
        s.totals.show(week, grown)
        s.totals.todayEntriesChanged.disconnect(onChange)
        s.totals.weekEntriesChanged.disconnect(onChange)
        compare(changes, 0, "nothing new: no change signals")
        verify(s.totals.todayEntries === today)
        verify(s.totals.weekEntries === week)
    }

    function test_noSharedMeansSetup() {
        Platform.setBackend(backend(null))
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "state", s.connection.needsSetup)
    }

    Component {
        id: signalSpy
        SignalSpy { }
    }
}
