import QtQuick
import QtTest
import "../qml"

/** TripEditPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "TripEditPageClosed"
    when: windowShown
    width: 400
    height: 400

    property var pending: []

    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property QtObject session: QtObject {
                property var trips: QtObject {
                    property var ping: ({})
                    property var meta: null
                    property var vehicles: []
                    function accept(id, body, cb) { tc.pending.push(cb) }
                    function patch(id, body, cb) { tc.pending.push(cb) }
                    function create(body, cb) { tc.pending.push(cb) }
                    function remove(id, cb) { tc.pending.push(cb) }
                }
                property var setup: QtObject {}
                property var connection: QtObject { property bool configured: true; property string state: "ok" }
            }
            function showPassiveNotification() {}
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { TripEditPage { } }
        }
    }

    /** Opens the page, lets `open` start a request, destroys it, calls the stored answer; returns what it threw. */
    function lateAnswers(open, answer) {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        pending = []
        open(obj)
        compare(pending.length, 1)
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb(answer) } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    function test_late_save_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.save({ km: 5 }, null, {}) }, { ok: true, data: null }), [])
    }

    function test_late_save_failure_does_not_throw() {
        compare(lateAnswers(function(p) { p.save({ km: 5 }, null, {}) }, { ok: false, error: { detail: "x" } }), [])
    }

    function test_late_patch_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.save({ km: 5 }, 4, {}) }, { ok: true, data: null }), [])
    }

    function test_late_remove_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.remove(4) }, { ok: true }), [])
    }

    function test_late_remove_failure_does_not_throw() {
        compare(lateAnswers(function(p) { p.remove(4) }, { ok: false, error: { detail: "x" } }), [])
    }
}
