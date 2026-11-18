import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/offlineOwner.js" as Owner

/**
 * Two profiles with different tokens, switched in the real order (useProfile, openFor, the token
 * read): the waiting changes and the snapshot of a profile stay as they are, on disk too, and its
 * running timer stays. No network at all.
 */
TestCase {
    name: "SessionProfiles"

    readonly property var tokens: ({ p1: "T1", p2: "T2" })
    readonly property var urls: ({ p1: "http://a.test", p2: "http://b.test" })

    property var files: ({})
    property var shared: null

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb(tokens[id], null) },
            loadLocal: function(_ds, name, cb) { cb(files[name] ? "ok" : "missing", files[name] ? JSON.parse(JSON.stringify(files[name])) : null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = JSON.parse(JSON.stringify(payload)); cb(true, null) }
        }
    }

    // Nothing answers: every request is a network error.
    function route() {
        return {
            handles: function() { return true },
            token: "",
            request: function() {
                const xhr = {
                    readyState: 0, status: 0, statusText: "", responseText: "", onreadystatechange: null,
                    open: function() {}, setRequestHeader: function() {}, getResponseHeader: function() { return null },
                    abort: function() {},
                    send: function() { xhr.readyState = 4; xhr.onreadystatechange() }
                }
                return xhr
            }
        }
    }

    function ownerOf(id) {
        return { server: Owner.serverOf(urls[id]), mark: Owner.markOf(tokens[id]), account: "5", name: "User" }
    }

    function outboxOf(id) {
        const by = { server: Owner.serverOf(urls[id]), mark: Owner.markOf(tokens[id]) }
        return { v: 1, counter: 1, owner: ownerOf(id), held: [], ops: [
            { opId: "local:" + id, kind: "create", entryId: "local:" + id, state: "pending", attempts: 0, maybeSent: false,
              error: null, by: by, fields: { begin: "2026-09-28T09:00:00+0200", project: 1, activity: 2 } }] }
    }

    function snapshotOf(id) {
        return { v: 1, savedAt: 1, activeId: null, recentIds: [9], reads: {}, filmDays: {}, owner: ownerOf(id),
                 entries: { "9": { id: 9, begin: "2026-09-27T09:00:00+0200", end: "2026-09-27T10:00:00+0200",
                                   project: { id: 1, name: "P" }, activity: { id: 2, name: "A" } } } }
    }

    Component {
        id: sessionComponent
        Ui.Session { setupMode: Ui.Session.Setup.Run }
    }

    function init() {
        const list = [{ id: "p1", name: "One", url: urls.p1, provider: "kimai" },
                      { id: "p2", name: "Two", url: urls.p2, provider: "kimai" }]
        shared = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "p1" }
        shared[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
        files = {}
        for (const id of ["p1", "p2"]) {
            files["offline-outbox-tui-" + id] = outboxOf(id)
            files["offline-state-tui-" + id] = snapshotOf(id)
        }
        Platform.setBackend(backend())
        KimaiApi.setUrlRoute(route())
    }

    function cleanup() {
        KimaiApi.setUrlRoute(null)
    }

    function disk() {
        return JSON.stringify(files)
    }

    function switchTo(s, id) {
        let done = false
        s.connection.useProfile(Profiles.profileById(s.connection.profiles, id)).then(function() { done = true })
        tryVerify(function() { return done })
        wait(100)
    }

    function checkIntact(s, id) {
        compare(s.sync.state.host.key, "tui-" + id)
        compare(s.sync.unsynced, 1, id + " keeps its waiting change")
        compare(s.sync.held, 0, id + " parks nothing")
        compare(Object.keys(s.sync.state.snapshot.entries).length, 1, id + " keeps its snapshot")
    }

    // Leaving a profile and coming back, offline: ops, snapshot (also on disk) and the timer stay.
    function test_switchingProfilesChangesNothing() {
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "tokenLoaded", true)
        wait(100)
        const before = disk()
        checkIntact(s, "p1")

        switchTo(s, "p2")
        checkIntact(s, "p2")
        switchTo(s, "p1")
        checkIntact(s, "p1")
        switchTo(s, "p2")
        checkIntact(s, "p2")
        tryVerify(function() { return s.timer.tracking }, 3000)
        compare(disk(), before, "nothing was written")
    }
}
