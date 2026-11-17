import QtQuick
import QtTest
import "../qml"
import "../qml/shared"

/**
 * TripsPage (app/qml): an answer that arrives after the page is gone touches
 * nothing; the list follows what the session reports, whichever page asked.
 */
TestCase {
    id: tc
    name: "TripsPageClosed"
    when: windowShown
    width: 400
    height: 400

    property var pending: []
    property int fetches: 0

    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property QtObject session: QtObject {
                property var trips: QtObject {
                    property bool available: true
                    property bool canEdit: true
                    property var ping: ({ features: [], profile: { dawarichConfigured: true, commuteKm: 12 } })
                    property var meta: null
                    property bool busy: false
                    signal changed(int change, var data)
                    function fetch(query, cb) { tc.fetches++; tc.pending.push(cb) }
                    function fetchSuggestions(cb) { tc.pending.push(cb) }
                    function logCommute(cb) { tc.pending.push(cb) }
                    function acceptSuggestion(sg, cb) { tc.pending.push(cb) }
                    function dismissSuggestion(sg, cb) { tc.pending.push(cb) }
                    function resolve() {}
                }
                property var sync: QtObject { property bool offline: false; property int unsynced: 0 }
            }
            function showPassiveNotification() {}
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { TripsPage { } }
        }
    }

    function init() {
        pending = []
        fetches = 0
    }

    /** Opens the page, lets `open` start requests, destroys it, calls the stored answers with `answer`; returns what they threw. */
    function lateAnswers(open, answer) {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        pending = []
        open(obj)
        const count = pending.length
        verify(count > 0)
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb(answer) } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    function test_late_trips_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.reload() }, { ok: true, data: [] }), [])
    }

    function test_late_trips_error_does_not_throw() {
        compare(lateAnswers(function(p) { p.reload() }, { ok: false, error: { detail: "x" } }), [])
    }

    function test_late_commute_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.commuteToday() }, { ok: true, data: { distance: 12 } }), [])
    }

    function test_late_commute_failure_does_not_throw() {
        compare(lateAnswers(function(p) { p.commuteToday() }, { ok: false, error: { detail: "x" } }), [])
    }

    function test_late_accept_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.accept({ id: 3 }) }, { ok: true }), [])
    }

    function test_late_accept_failure_does_not_throw() {
        compare(lateAnswers(function(p) { p.accept({ id: 3 }) }, { ok: false, error: { detail: "x" } }), [])
    }

    function test_late_dismiss_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.dismiss({ id: 3 }) }, { ok: true }), [])
    }

    function test_late_dismiss_failure_does_not_throw() {
        compare(lateAnswers(function(p) { p.dismiss({ id: 3 }) }, { ok: false, error: { detail: "x" } }), [])
    }

    // Saved on another page, maybe answered after that page closed: the list reloads.
    function test_reloads_when_trip_saved() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        const before = tc.fetches

        h.session.trips.changed(Session.TripChange.Saved, { id: 1 })

        compare(tc.fetches, before + 1)
        obj.destroy()
    }

    function test_reloads_when_suggestion_accepted() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        const before = tc.fetches

        h.session.trips.changed(Session.TripChange.Accepted, { id: 2 })

        compare(tc.fetches, before + 1)
        obj.destroy()
    }

    function test_dismissed_suggestion_leaves_the_list() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        obj.suggestions = [{ id: 2 }, { id: 3 }]

        h.session.trips.changed(Session.TripChange.Dismissed, { id: 2 })

        compare(obj.suggestions.length, 1)
        compare(obj.suggestions[0].id, 3)
        obj.destroy()
    }
}
