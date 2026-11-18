import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/offlineOwner.js" as Owner

/**
 * The first refresh does not wait for /api/users/me: with that answer held, the entries are
 * loaded and shown, nothing waiting is sent and nothing is kept in the snapshot. Once the
 * account is known the waiting change goes out.
 */
TestCase {
    name: "SessionVerify"

    readonly property string outbox: "offline-outbox-tui-p1"
    readonly property string snapshot: "offline-state-tui-p1"
    readonly property var entry: ({ id: 3, begin: "2026-09-28T07:00:00+0200", end: "2026-09-28T08:00:00+0200",
                                    project: { id: 1, name: "P" }, activity: { id: 2, name: "A" }, description: "" })

    property var files: ({})
    property var shared: null
    property var meWaiting: []
    property var posts: []

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb("tok", null) },
            loadLocal: function(_ds, name, cb) { cb(files[name] ? "ok" : "missing", files[name] ? JSON.parse(JSON.stringify(files[name])) : null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = JSON.parse(JSON.stringify(payload)); cb(true, null) }
        }
    }

    function route() {
        const self = this
        return {
            handles: function() { return true },
            token: "",
            request: function() {
                const xhr = {
                    readyState: 0, status: 0, statusText: "", responseText: "", onreadystatechange: null, method: "", url: "",
                    open: function(m, u) { xhr.method = m; xhr.url = u },
                    setRequestHeader: function() {},
                    getResponseHeader: function() { return null },
                    abort: function() {},
                    send: function() {
                        function answer(status, body) {
                            xhr.status = status
                            xhr.responseText = JSON.stringify(body)
                            xhr.readyState = 4
                            xhr.onreadystatechange()
                        }
                        if (xhr.url.indexOf("/api/users/me") > 0) {
                            self.meWaiting.push(function() { answer(200, { id: 1, alias: "One" }) })
                            return
                        }
                        if (xhr.method === "POST") {
                            self.posts.push(xhr.url)
                            answer(201, { id: 77 })
                            return
                        }
                        answer(200, xhr.url.indexOf("/active") > 0 ? [] : [self.entry])
                    }
                }
                return xhr
            }
        }
    }

    Component {
        id: sessionComponent
        Ui.Session { setupMode: Ui.Session.Setup.Run }
    }

    function init() {
        const list = [{ id: "p1", name: "One", url: "http://a.test", provider: "kimai" }]
        shared = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "p1" }
        shared[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
        meWaiting = []
        posts = []
        files = {}
        files[outbox] = { v: 1, counter: 1, owner: { server: "http://a.test", mark: Owner.markOf("tok"), account: "1", name: "One" }, held: [], ops: [
            { opId: "local:1", kind: "create", entryId: "local:1", state: "pending", attempts: 0, maybeSent: false, error: null, by: { server: "http://a.test", mark: Owner.markOf("tok") },
              fields: { begin: "2026-09-28T09:00:00+0200", end: "2026-09-28T10:00:00+0200", project: 1, activity: 2 } }] }
        Platform.setBackend(backend())
        KimaiApi.setUrlRoute(route())
    }

    function cleanup() {
        KimaiApi.setUrlRoute(null)
    }

    function test_entriesShowWhileTheAccountCheckHangs() {
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryVerify(function() { return s.recent.list.length > 0 }, 5000)
        verify(meWaiting.length >= 1, "the check was asked")
        compare(posts.length, 0, "nothing sent before the check")
        compare(s.sync.unsynced, 1)
        wait(50)
        verify(!files[snapshot] || Object.keys(files[snapshot].entries || {}).length === 0, "nothing kept in the snapshot")

        // The answer comes: the account is the owner's, the waiting change goes out.
        meWaiting.shift()()
        tryVerify(function() { return posts.length === 1 }, 5000)
        tryCompare(s.sync, "unsynced", 0)
    }
}
