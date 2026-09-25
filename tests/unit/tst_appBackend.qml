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
}
