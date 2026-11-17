import QtQuick
import QtTest
import "../qml"

/** StatsPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "StatsPageClosed"
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
                    property bool available: true
                    property var ping: ({})
                    function fetch(range, cb) { tc.pending.push(cb) }
                }
                property var entries: QtObject {
                    function fetchRange(begin, end, cb) { tc.pending.push(cb) }
                }
                property var connection: QtObject { property bool configured: true; property var capabilities: ({}) }
                property var catalog: QtObject { property var customersById: ({}) }
                property var totals: QtObject {
                    property int todayTargetSeconds: 0
                    property int weekEffectiveTargetSeconds: 0
                    property bool hasWorkContract: false
                }
                property var settings: QtObject { property int workDayBegin: 0; property int workDayEnd: 0 }
                function refresh() {}
            }
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { StatsPage { } }
        }
    }

    /** Opens the page, lets `open` start requests, destroys it, calls the stored answers; returns what they threw. */
    function lateAnswers(open, answer) {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        pending = []
        open(obj)
        verify(pending.length > 0)
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb(answer) } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    function test_late_trips_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.loadTrips() }, { ok: true, data: [] }), [])
    }

    function test_late_range_answer_does_not_throw() {
        const now = new Date()
        compare(lateAnswers(function(p) { p.loadRange(new Date(now.getTime() - 1e9), now) }, { ok: true, data: [] }), [])
    }
}
