import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig

/**
 * Another account on the same profile: the connection counts it as another
 * connection; a catalog belongs to its server. In-memory platform backend, a server
 * that is not there.
 */
TestCase {
    name: "SessionAccount"

    property var files: ({})
    property var tokens: ({})
    property var shared: null

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb(tokens[id] || "", null) },
            loadLocal: function(_ds, name, cb) { cb(files[name] || null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = payload; cb(true, null) }
        }
    }

    Component {
        id: sessionComponent
        Ui.Session { setupMode: Ui.Session.Setup.Run }
    }

    function init() {
        files = {}
        tokens = {}
    }

    function ownShared(url) {
        const list = [{ id: "p1", name: "One", url: url, provider: "kimai" }]
        const s = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "p1" }
        s[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
        return s
    }

    function openOwn(token) {
        shared = ownShared("http://127.0.0.1:9")
        tokens = { p1: token }
        Platform.setBackend(backend())
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "tokenLoaded", true)
        return s
    }

    function reloadToken(s, token) {
        tokens.p1 = token
        let done = false
        s.connection.reloadToken().then(function() { done = true })
        tryVerify(function() { return done })
    }

    // Clear, then save another account's token: the answers of the first are another account's.
    function test_clearedThenOtherAccountCountsAsAnother() {
        const s = openOwn("account-a")
        const before = s.connection.generation
        reloadToken(s, "")
        reloadToken(s, "account-b")
        compare(s.connection.generation, before + 1)
    }

    function test_clearedThenSameAccountKeepsAnswers() {
        const s = openOwn("account-a")
        const before = s.connection.generation
        reloadToken(s, "")
        reloadToken(s, "account-a")
        compare(s.connection.generation, before)
    }

    // The Favorites page takes a catalog kept in memory only from the server it was loaded from.
    function test_catalogOfAnotherServerIsNotCached() {
        const s = openOwn("account-a")
        s.catalog.keep({ profileId: "p1", url: "http://a.test", projects: [{ id: 1 }], customers: [], activities: [] })
        verify(s.catalog.cached("p1", "http://a.test") !== null)
        compare(s.catalog.cached("p1", "http://b.test"), null)
    }
}
