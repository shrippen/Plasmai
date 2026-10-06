import QtQuick
import QtTest
import "../../contents/code/platform.js" as Platform

/** platform.js patchShared: serialized read-modify-write and data-map merge (B9). */
TestCase {
    name: "PlatformShared"

    property var disk: null
    property var pendingLoads: []
    property int saves: 0

    // Loads answer only when release() is called, so two patches can overlap.
    function fakeBackend() {
        return {
            loadSharedConfig: function(ds, cb) {
                pendingLoads.push(function() { cb(disk ? JSON.parse(JSON.stringify(disk)) : null) })
            },
            saveCatalogCache: function(ds, payload, cb) {
                saves++
                cb(true, null)
            },
            saveSharedConfig: function(ds, obj, cb) {
                disk = obj
                saves++
                cb(true, null)
            }
        }
    }

    function release() {
        tryVerify(function() { return pendingLoads.length > 0 })
        pendingLoads.shift()()
    }

    function init() {
        // A file of this version (settingsVersion): one without it is reset before any patch.
        disk = { recentCount: 5, pluginProbesJson: JSON.stringify({ app: 1 }), settingsVersion: 2 }
        pendingLoads = []
        saves = 0
        Platform.setBackend(fakeBackend())
    }

    function test_patchStampsSettingsVersion() {
        // Written by this version: never mistaken for pre-wizard settings.
        disk = { recentCount: 5 }
        var done = false
        Platform.patchShared(null, {}, { recentCount: 7 }).then(function() { done = true })
        release()
        tryVerify(function() { return done })
        compare(disk.recentCount, 7)
        compare(disk.settingsVersion, 2)
    }

    function test_checkSystemWithoutBackendCheck() {
        // The app's backend has no check: nothing to report, no System step.
        var got = null
        Platform.checkSystem(null).then(function(r) { got = r })
        tryVerify(function() { return got !== null })
        compare(Object.keys(got).length, 0)
    }

    function test_checkSystemAsksBackend() {
        var backend = fakeBackend()
        backend.checkSystem = function(ds, cb) { cb({ secretTool: false }) }
        Platform.setBackend(backend)
        var got = null
        Platform.checkSystem(null).then(function(r) { got = r })
        tryVerify(function() { return got !== null })
        compare(got.secretTool, false)
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

    // A patch that changes nothing on disk is not written (startup patches the same values).
    function test_unchangedPatchNotWritten() {
        var done = 0
        Platform.patchShared(null, {}, { recentCount: 5 }).then(function() { done++ })
        release()
        tryVerify(function() { return done === 1 })
        compare(saves, 0)
        Platform.patchShared(null, {}, { recentCount: 7 }).then(function() { done++ })
        release()
        tryVerify(function() { return done === 2 })
        compare(saves, 1)
        compare(disk.recentCount, 7)
    }

    // The catalog arrives in parts, each storing the whole cache: the same payload is written once.
    function test_sameCatalogWrittenOnce() {
        var done = 0
        Platform.saveCatalog(null, { p1: { projects: [1] } }).then(function() { done++ })
        Platform.saveCatalog(null, { p1: { projects: [1] } }).then(function() { done++ })
        tryVerify(function() { return done === 2 })
        compare(saves, 1)
        Platform.saveCatalog(null, { p1: { projects: [1, 2] } }).then(function() { done++ })
        tryVerify(function() { return done === 3 })
        compare(saves, 2)
    }
}
