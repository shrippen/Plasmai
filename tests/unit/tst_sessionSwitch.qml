import QtQuick
import QtTest
import "../../contents/ui/session" as Parts
import "../../contents/code/platform.js" as Platform
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/offlineOutbox.js" as Outbox

/**
 * SessionSync.openFor: leaving a profile while a replay's create is on its way and
 * coming back (also over other profiles and with reads answering meanwhile) sends
 * that create once and leaves the outbox empty. A fake server answers by hand.
 */
TestCase {
    name: "SessionSwitch"

    readonly property string fileA: "offline-outbox-tui-a"
    readonly property var profA: ({ id: "a", provider: "kimai" })
    readonly property var profB: ({ id: "b", provider: "kimai" })

    property var files: ({})
    property var posts: []      // bodies of the creates sent
    property var held: []       // answers waiting: { post, deliver(status, body) }
    property var reads: []      // reads waiting

    QtObject {
        id: fakeSession
        property string offlinePrefix: "tui-"
        property var dataSource: null
        property var connection: ({ url: "http://a.test", token: "tok" })
        property var timer: ({ followId: function() {} })
        property var filmDay: ({ context: function() { return {} } })
        function refresh() { }
    }

    Component {
        id: syncComponent
        Parts.SessionSync { session: fakeSession }
    }

    // A request that answers when the test says so.
    function fakeRoute() {
        const self = this
        return {
            handles: function() { return true },
            token: "tok",
            request: function() {
                const xhr = {
                    readyState: 0, status: 0, statusText: "", responseText: "", onreadystatechange: null,
                    method: "", url: "",
                    open: function(m, u) { xhr.method = m; xhr.url = u },
                    setRequestHeader: function() {},
                    getResponseHeader: function() { return null },
                    abort: function() {},
                    send: function(body) {
                        // The account check answers at once; the tests hold the reads and creates.
                        if (xhr.url.indexOf("/api/users/me") > 0) {
                            xhr.status = 200
                            xhr.responseText = JSON.stringify({ id: 1, alias: "One" })
                            xhr.readyState = 4
                            xhr.onreadystatechange()
                            return
                        }
                        const entry = { post: xhr.method === "POST", deliver: function(status, text) {
                            xhr.status = status
                            xhr.responseText = text
                            xhr.readyState = 4
                            xhr.onreadystatechange()
                        } }
                        if (entry.post) {
                            self.posts.push(body)
                            self.held.push(entry)
                        } else {
                            self.reads.push(entry)
                        }
                    }
                }
                return xhr
            }
        }
    }

    function init() {
        files = {}
        posts = []
        held = []
        reads = []
        fakeSession.connection = { url: "http://a.test", token: "tok" }
        files[fileA] = { v: 1, counter: 1, ops: [{ opId: "local:1", kind: "create", entryId: "local:1", state: "pending",
            attempts: 0, maybeSent: false, fields: { begin: "2026-09-28T07:00:00+0200", end: "2026-09-28T08:00:00+0200", project: 1, activity: 2 } }] }
        Platform.setBackend({
            loadLocal: function(_ds, name, cb) { cb(files[name] ? "ok" : "missing", files[name] ? JSON.parse(JSON.stringify(files[name])) : null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = JSON.parse(JSON.stringify(payload)); cb(true, null) }
        })
        KimaiApi.setUrlRoute(fakeRoute())
    }

    function cleanup() {
        KimaiApi.setUrlRoute(null)
    }

    function opened(sync, prof, url) {
        fakeSession.connection = { url: url, token: "tok" }
        let done = false
        sync.openFor(prof, prof.id === "a" ? "tokA" : "tokB").then(function() { return sync.verify() }).then(function() { done = true })
        return function() { return done }
    }

    function open(sync, prof, url) {
        tryVerify(opened(sync, prof, url))
    }

    function poll(sync) {
        sync.state.tracker.fetchActiveTimesheet(fakeSession.connection.url, "tok", function() {})
    }

    function answerReads() {
        while (reads.length) {
            reads.shift().deliver(200, "[]")
        }
    }

    function startReplay(sync) {
        Outbox.replay(sync.state, function() {})
        compare(posts.length, 1)
    }

    function answerCreate() {
        held.shift().deliver(201, JSON.stringify({ id: 77, begin: "2026-09-28T07:00:00+0200", end: "2026-09-28T08:00:00+0200", project: 1, activity: 2 }))
    }

    function backAndForth(rounds) {
        const sync = createTemporaryObject(syncComponent, this)
        open(sync, profA, "http://a.test")
        startReplay(sync)
        for (let i = 0; i < rounds; i++) {
            open(sync, profB, "http://b.test")
            poll(sync)
            answerReads()
            // Back to A with the create still on its way; its poll answers meanwhile.
            const done = opened(sync, profA, "http://a.test")
            poll(sync)
            answerReads()
            tryVerify(done)
        }
        answerCreate()
        answerReads()
        tryCompare(sync, "unsynced", 0)
        compare(posts.length, 1, "the create was sent once")
        compare(files[fileA].ops.length, 0)
        return sync
    }

    function test_roundTripWithCreateOnItsWay() {
        backAndForth(1)
    }

    function test_severalRoundTrips() {
        backAndForth(2)
    }

    // A read of the profile left answers "no network" after the switch: nothing is written for it.
    function test_offlineReadAfterLeaving() {
        // An op that waits for a decision: no replay, the poll is a plain read.
        files[fileA].ops[0].state = "failed"
        const sync = createTemporaryObject(syncComponent, this)
        open(sync, profA, "http://a.test")
        poll(sync)
        const before = JSON.stringify(files[fileA])
        open(sync, profB, "http://b.test")
        reads.shift().deliver(0, "")
        wait(20)
        compare(JSON.stringify(files[fileA]), before)
        open(sync, profA, "http://a.test")
        tryCompare(sync, "unsynced", 1)
    }

    // A write sent online when the profile is left, then no network: it is queued in the file of
    // the profile it belongs to at once (the process may end before the profile is opened again).
    function test_changeQueuedAfterLeavingIsWritten() {
        files[fileA].ops = []
        const sync = createTemporaryObject(syncComponent, this)
        open(sync, profA, "http://a.test")
        let answered = false
        sync.state.tracker.createTimesheet("http://a.test", "tok",
            { begin: "2026-09-28T09:00:00+0200", end: "2026-09-28T10:00:00+0200", project: 1, activity: 2 },
            function() { answered = true })
        compare(posts.length, 1)
        open(sync, profB, "http://b.test")
        held.shift().deliver(0, "")
        tryVerify(function() { return answered })
        compare(files[fileA].ops.length, 1)
    }
}
