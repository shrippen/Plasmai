import QtQuick
import QtTest
import "../../contents/code/platform.js" as Platform

/** platform.js patchShared: serialized read-modify-write and data-map merge (B9). */
TestCase {
    name: "PlatformShared"

    property var disk: null
    property var pendingLoads: []

    // Loads answer only when release() is called, so two patches can overlap.
    function fakeBackend() {
        return {
            loadSharedConfig: function(ds, cb) {
                pendingLoads.push(function() { cb(disk ? JSON.parse(JSON.stringify(disk)) : null) })
            },
            saveSharedConfig: function(ds, obj, cb) {
                disk = obj
                cb(true, null)
            }
        }
    }

    function release() {
        tryVerify(function() { return pendingLoads.length > 0 })
        pendingLoads.shift()()
    }

    function init() {
        disk = { recentCount: 5, pluginProbesJson: JSON.stringify({ app: 1 }) }
        pendingLoads = []
        Platform.setBackend(fakeBackend())
    }

    function test_dataMapMergedWithOtherWriter() {
        // This process last saw {app:1}; the Plasmoid has added "widget" on disk since.
        disk.pluginProbesJson = JSON.stringify({ app: 1, widget: 2 })
        var written = null
        Platform.patchShared(null, {}, { pluginProbesJson: JSON.stringify({ app: 1, mine: 3 }) },
                             { pluginProbesJson: JSON.stringify({ app: 1 }) }).then(function(w) { written = w })
        release()
        tryVerify(function() { return written !== null })
        var map = JSON.parse(disk.pluginProbesJson)
        compare(map.widget, 2)
        compare(map.mine, 3)
        compare(disk.recentCount, 5)
        compare(written.pluginProbesJson, disk.pluginProbesJson)
    }

    function test_patchesRunOneAfterAnother() {
        var done = 0
        Platform.patchShared(null, {}, { pluginProbesJson: JSON.stringify({ app: 1, a: 1 }) },
                             { pluginProbesJson: JSON.stringify({ app: 1 }) }).then(function() { done++ })
        Platform.patchShared(null, {}, { pluginProbesJson: JSON.stringify({ app: 1, a: 1, b: 2 }) },
                             { pluginProbesJson: JSON.stringify({ app: 1, a: 1 }) }).then(function() { done++ })
        // The second load must wait until the first save is done.
        tryVerify(function() { return pendingLoads.length === 1 })
        wait(20)
        compare(pendingLoads.length, 1)
        release()
        release()
        tryVerify(function() { return done === 2 })
        var map = JSON.parse(disk.pluginProbesJson)
        compare(map.a, 1)
        compare(map.b, 2)
    }
}
