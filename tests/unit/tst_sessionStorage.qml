import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig

/**
 * The session's offline files: a save that fails is reported (sync.storageError)
 * and the next write carries everything; a file that cannot be read is never
 * replaced by the queue of this run. In-memory platform backend.
 */
TestCase {
    name: "SessionStorage"

    readonly property string outbox: "offline-outbox-tui-p1"
    readonly property var fields: ({ begin: "2026-09-28T07:00:00+0200", end: "2026-09-28T08:00:00+0200", project: 1, activity: 2 })

    property var files: ({})
    property var readAs: ({})
    property bool failSave: false
    property var shared: null

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb("tok", null) },
            loadLocal: function(_ds, name, cb) {
                if (readAs[name]) {
                    cb(readAs[name], null)
                    return
                }
                cb(files[name] ? "ok" : "missing", files[name] || null)
            },
            saveLocal: function(_ds, name, payload, cb) {
                if (failSave) {
                    cb(false, "disk full")
                    return
                }
                files[name] = JSON.parse(JSON.stringify(payload))
                cb(true, null)
            }
        }
    }

    Component {
        id: sessionComponent
        Ui.Session { setupMode: Ui.Session.Setup.Run }
    }

    function init() {
        files = {}
        readAs = {}
        failSave = false
        const list = [{ id: "p1", name: "One", url: "http://127.0.0.1:9", provider: "kimai" }]
        shared = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "p1" }
        shared[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
    }

    function openSession() {
        Platform.setBackend(backend())
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "tokenLoaded", true)
        tryVerify(function() { return !!s.sync.state })
        wait(50)
        return s
    }

    // No server there: a write is a network error and waits in the outbox.
    function queueWrite(s) {
        let answered = false
        s.sync.state.tracker.createTimesheet("http://127.0.0.1:9", "tok", fields, function() { answered = true })
        tryVerify(function() { return answered })
    }

    function test_failedSaveIsReportedAndNextWriteCarriesAll() {
        const s = openSession()
        compare(s.sync.storageError, "")
        failSave = true
        queueWrite(s)
        tryCompare(s.sync, "storageError", "save")
        failSave = false
        queueWrite(s)
        tryCompare(s.sync, "storageError", "")
        compare(files[outbox].ops.length, 2)
    }

    function test_unreadableOutboxIsKept() {
        files[outbox] = { v: 1, counter: 1, ops: [{ opId: "local:x", kind: "create", state: "pending", entryId: "local:x", fields: {} }] }
        readAs[outbox] = "unreadable"
        const s = openSession()
        queueWrite(s)
        compare(files[outbox].ops.length, 1, "the file is as it was")
        compare(s.sync.storageError, "load")
    }
}
