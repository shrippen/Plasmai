import QtQuick
import QtCore
import QtTest
import "../../contents/ui"
import "../../contents/code/secret.js" as Secret

// The widget learnt of a change to shared.json (another widget, the settings) by
// reading it every 5 s through a shell process while open, every 60 s closed.
// SharedConfigWatch tells of a new file by a directory watcher, without a process.
TestCase {
    id: test
    name: "SharedConfigWatch"
    when: windowShown

    readonly property string dir: String(StandardPaths.writableLocation(StandardPaths.CacheLocation)).replace("file://", "")
                                  + "/plasmai-watch-" + Date.now()

    ExecSource { id: exec }
    SignalSpy { id: spy; signalName: "changed" }

    /** Saves like sharedConfig.sh: a new file moved into place. */
    function write(value) {
        let done = false
        Secret._run(exec, "mkdir -p '" + dir + "' && printf %s '" + value + "' > '" + dir + "/.tmp' && mv '"
                    + dir + "/.tmp' '" + dir + "/shared.json'", function() { done = true })
        tryVerify(function() { return done }, 5000)
    }

    function cleanupTestCase() {
        let done = false
        Secret._run(exec, "rm -rf '" + dir + "'", function() { done = true })
        tryVerify(function() { return done }, 5000)
    }

    function test_changeIsReported() {
        write("{}")
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/SharedConfigWatch.qml"))
        verify(c.status === Component.Ready, c.errorString())
        const watch = createTemporaryObject(c, test, { folder: "file://" + dir, fileName: "shared.json" })
        spy.target = watch
        wait(500)
        compare(spy.count, 0, "loading the folder is no change")

        write("{\"a\":1}")
        tryVerify(function() { return spy.count > 0 }, 5000, "a new file is reported")
    }
}
