import QtQuick
import QtTest
import "../../app/qml/platform/appBackend.js" as AppBackend

TestCase {
    name: "AppBackend"

    // Minimal stand-in for a C++ signal: connect / disconnect / emit.
    function fakeSignal() {
        var handlers = []
        return {
            connect: function(fn) { handlers.push(fn) },
            disconnect: function(fn) {
                var i = handlers.indexOf(fn)
                if (i >= 0) {
                    handlers.splice(i, 1)
                }
            },
            emit: function() {
                var copy = handlers.slice()
                for (var i = 0; i < copy.length; i++) {
                    copy[i].apply(null, arguments)
                }
            },
            count: function() { return handlers.length }
        }
    }

    function test_tokenLoadsForTwoProfilesBothAnswer() {
        var loaded = fakeSignal()
        var store = { loaded: loaded, saved: fakeSignal(), removed: fakeSignal(), load: function() {} }
        var backend = AppBackend.create(store, {}, undefined, undefined)
        var got = {}
        backend.loadToken(null, "a", function(token) { got.a = token })
        backend.loadToken(null, "b", function(token) { got.b = token })
        // Keychain jobs finish in any order.
        loaded.emit("b", "tb")
        loaded.emit("a", "ta")
        compare(got.a, "ta")
        compare(got.b, "tb")
        compare(loaded.count(), 0)
    }

    function test_idleCheckAnswers() {
        var idle = { idleChecked: fakeSignal(), checkIdle: function() { idle.idleChecked.emit(1234, true) } }
        var backend = AppBackend.create({}, {}, idle, undefined)
        var ms = null
        backend.runIdle(null, function(value) { ms = value })
        compare(ms, 1234)
    }

    // The app tells a missing file from an unreadable one and from broken JSON.
    function test_loadLocalStatus() {
        var localLoaded = fakeSignal()
        var store = { localLoaded: localLoaded, loadLocal: function() {} }
        var backend = AppBackend.create({}, store, undefined, undefined)
        var got = []
        function ask(status, text) {
            backend.loadLocal(null, "f", function(st, obj) { got.push([st, obj]) })
            localLoaded.emit("f", text, status)
        }
        ask("missing", "")
        ask("unreadable", "")
        ask("ok", "{\"v\":1}")
        ask("ok", "{broken")
        ask("ok", "")
        compare(got[0], ["missing", null])
        compare(got[1], ["unreadable", null])
        compare(got[2][0], "ok")
        compare(got[2][1].v, 1)
        compare(got[3], ["broken", null])
        compare(got[4], ["broken", null], "an empty file is no JSON")
    }

    function test_quarantineLocal() {
        var done = fakeSignal()
        var asked = []
        var store = { localQuarantined: done, quarantineLocal: function(name) { asked.push(name) } }
        var backend = AppBackend.create({}, store, undefined, undefined)
        var got = null
        backend.quarantineLocal(null, "f", function(ok) { got = ok })
        compare(asked, ["f"])
        done.emit("f", true)
        compare(got, true)
    }
}
