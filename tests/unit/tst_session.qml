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
