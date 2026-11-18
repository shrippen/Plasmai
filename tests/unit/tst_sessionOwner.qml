import QtQuick
import QtTest
import "../../contents/ui/session" as Parts
import "../../contents/code/platform.js" as Platform
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/offlineOwner.js" as Owner

/**
 * SessionSync and the owner of the waiting changes: a changed address in the same profile is
 * noticed too, the account is checked before anything is sent, parked groups are listed and
 * can be sent or discarded, and a change of owner clears what the session shows.
 * A fake server answers at once; /api/users/me tells the account of the address.
 */
TestCase {
    name: "SessionOwner"

    readonly property string fileA: "offline-outbox-tui-a"
    readonly property var profA: ({ id: "a", provider: "kimai" })
    readonly property var owner: ({ server: "http://a.test", mark: Owner.markOf("tok"), account: "1", name: "One" })
    readonly property var parkedOp: ({ opId: "local:1", kind: "create", entryId: "local:1", state: "failed",
        attempts: 1, maybeSent: false, by: ({ server: "http://a.test", mark: Owner.markOf("tok") }), error: { type: "unknown", status: 500, detail: "x" },
        fields: { begin: "2026-09-28T07:00:00+0200", end: "2026-09-28T08:00:00+0200", project: 1, activity: 2 } })

    property var files: ({})
    property var requests: []
    property var accounts: ({})    // address → id /api/users/me answers with; 401 for "denied"
    property int cleared: 0
    property var timerApplied: []

    QtObject {
        id: fakeSession
        property string offlinePrefix: "tui-"
        property var dataSource: null
        property var connection: ({ url: "http://a.test", token: "tok" })
        property var timer: ({ followId: function() {}, apply: function(ts) { timerApplied.push(ts) } })
        property var filmDay: ({ context: function() { return {} } })
        property var catalog: ({ invalidate: function() { cleared++ } })
        function entriesWritten() { cleared++ }
        function refresh() { }
    }

    Component {
        id: syncComponent
        Parts.SessionSync { session: fakeSession }
    }

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
                        self.requests.push(xhr.method + " " + xhr.url)
                        let status = 200
                        let text = "[]"
                        if (xhr.url.indexOf("/api/users/me") > 0) {
                            const id = self.accounts[xhr.url.replace("/api/users/me", "")]
                            status = id === "denied" ? 401 : 200
                            text = JSON.stringify({ id: id, alias: "User " + id })
                        } else if (xhr.method === "POST") {
                            status = 201
                            text = JSON.stringify({ id: 77 })
                        }
                        xhr.status = status
                        xhr.responseText = text
                        xhr.readyState = 4
                        xhr.onreadystatechange()
                    }
                }
                return xhr
            }
        }
    }

    function init() {
        files = {}
        requests = []
        cleared = 0
        timerApplied = []
        accounts = { "http://a.test": "1", "http://a.test/kimai": "1", "http://b.test": "2" }
        files[fileA] = { v: 1, counter: 1, owner: owner, ops: [JSON.parse(JSON.stringify(parkedOp))], held: [] }
        Platform.setBackend({
            loadLocal: function(_ds, name, cb) { cb(files[name] ? "ok" : "missing", files[name] ? JSON.parse(JSON.stringify(files[name])) : null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = JSON.parse(JSON.stringify(payload)); cb(true, null) }
        })
        KimaiApi.setUrlRoute(fakeRoute())
        fakeSession.connection = { url: "http://a.test", token: "tok" }
    }

    function cleanup() {
        KimaiApi.setUrlRoute(null)
    }

    function opened(sync, url) {
        fakeSession.connection = { url: url, token: "tok" }
        let done = false
        sync.openFor(profA).then(function() { return sync.verify() }).then(function() { done = true })
        tryVerify(function() { return done })
    }

    function posts() {
        return requests.filter(function(r) { return r.indexOf("POST") === 0 })
    }

    // The address changes within the same profile: the waiting changes are parked, not sent there.
    function test_changedAddressInTheSameProfileParks() {
        const sync = createTemporaryObject(syncComponent, this)
        opened(sync, "http://a.test")
        compare(sync.unsynced, 1)
        compare(sync.held, 0)

        opened(sync, "http://a.test/kimai")
        compare(sync.unsynced, 0)
        compare(sync.held, 1)
        compare(sync.groups.length, 1)
        compare(sync.groups[0].name, "User 1", "the name the server gave last")
        compare(sync.groups[0].server, "http://a.test")
        compare(sync.groups[0].canAdopt, undefined)
        compare(posts().length, 0)
        compare(files[fileA].held.length, 1)
        compare(files[fileA].owner.server, "http://a.test/kimai")
    }

    function test_oldAddressSendsTheGroupAgain() {
        const sync = createTemporaryObject(syncComponent, this)
        opened(sync, "http://a.test")
        opened(sync, "http://a.test/kimai")
        compare(sync.held, 1)
        compare(posts().length, 0)
        opened(sync, "http://a.test")
        compare(sync.held, 0)
        compare(sync.unsynced, 1, "back in the queue, still refused")
        sync.retry(sync.ops[0].opId)
        tryCompare(sync, "unsynced", 0)
        compare(posts().length, 1)
        verify(posts()[0].indexOf("http://a.test/api/timesheets") > 0)
    }

    function test_discardGroupDropsIt() {
        const sync = createTemporaryObject(syncComponent, this)
        opened(sync, "http://a.test")
        opened(sync, "http://a.test/kimai")
        sync.discardGroup(sync.groups[0].id)
        compare(sync.held, 0)
        compare(files[fileA].held.length, 0)
        compare(posts().length, 0)
    }

    function test_otherAccountStaysParked() {
        const sync = createTemporaryObject(syncComponent, this)
        accounts["http://a.test"] = "2"
        opened(sync, "http://a.test")
        compare(sync.held, 1)
        compare(posts().length, 0)
    }

    function test_deniedCheckChangesNothing() {
        const sync = createTemporaryObject(syncComponent, this)
        accounts["http://a.test"] = "denied"
        opened(sync, "http://a.test")
        compare(sync.held, 0)
        compare(sync.unsynced, 1)
        compare(posts().length, 0)
    }

    // The owner changed: catalogs, the timer and the lists are not those of the new owner.
    function test_ownerChangeClearsWhatTheSessionShows() {
        const sync = createTemporaryObject(syncComponent, this)
        opened(sync, "http://a.test")
        cleared = 0
        timerApplied = []
        opened(sync, "http://b.test")
        verify(cleared >= 2)
        compare(timerApplied.length, 1)
        compare(timerApplied[0], null)
    }

    // The terminal client had no way out of a failed op, and every start waited behind it.
    function test_discardingAFailedOpLetsTheNextStartThrough() {
        const sync = createTemporaryObject(syncComponent, this)
        opened(sync, "http://a.test")
        compare(sync.stuck, 1)
        let queued = null
        sync.state.tracker.startTracking("http://a.test", "tok", 1, 2, "", function(r) { queued = r }, {})
        verify(queued.queued, "behind the failed op")
        compare(posts().length, 0)

        sync.discard("local:1")
        sync.discard(sync.ops[0].opId)
        let direct = null
        sync.state.tracker.startTracking("http://a.test", "tok", 1, 2, "", function(r) { direct = r }, {})
        verify(!direct.queued)
        compare(posts().length, 1)
    }
}
