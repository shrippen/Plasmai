import QtQuick
import QtTest
import "../qml"

/** FilmDayPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "FilmDayPageClosed"
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
                property var filmDay: QtObject {
                    property bool loading: false
                    property bool saving: false
                    property var dayTimesheet: null
                    function openView(probe, date, projectId, prefer, onDay, onProduction) {
                        tc.pending.push(function() { onDay({}); onProduction({}) })
                    }
                    function loadDay(date, projectId, prefer, onDay, onProduction) {
                        tc.pending.push(function() { onDay({}); onProduction({}) })
                    }
                    function saveExtras(req, cb, earnings) {
                        tc.pending.push(function() { cb({ extras: "saved" }); earnings(100) })
                    }
                    function saveNote(text, cb) { tc.pending.push(function() { cb({ saved: "saved", note: text }) }) }
                    function saveDay(req, cb) { tc.pending.push(function() { cb({ ok: true, invalid: "", deleteReport: null }) }) }
                }
                property var catalog: QtObject {
                    property var projectPickerModel: []
                    property var activities: []
                    property var activitiesByProject: ({})
                    property var projects: []
                    property var customers: []
                    signal changed()
                    function loadActivities(projectId, cb) { tc.pending.push(function() { cb([]) }) }
                    function projectById() { return null }
                }
                property var connection: QtObject { property bool configured: true; property string state: "ok" }
                property var timer: QtObject { property bool tracking: false; property var active: null; property int elapsedSeconds: 0 }
                property var reminders: QtObject { function notify() {} }
                property var sync: QtObject { property bool offline: false }
                property var entries: QtObject { property bool canCreate: true }
                property var trips: QtObject { property bool canEdit: false }
                property var recent: QtObject { property var list: [] }
                property bool busy: false
                function refresh() {}
            }
            function showPassiveNotification() {}
            function reportWriteError() {}
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { FilmDayPage { } }
        }
    }

    function init() {
        pending = []
    }

    /** Calls the stored answers of a page that is gone; returns what they threw. */
    function lateAnswers(open) {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        open()
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb() } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    /** The film day view inside the page: the item with the view's signal. */
    function findView(item) {
        if (typeof item.projectChosen === "function" && typeof item.otherEntryIds === "function") {
            return item
        }
        for (const child of item.children) {
            const found = findView(child)
            if (found) {
                return found
            }
        }
        return null
    }

    function test_late_day_answer_does_not_throw() {
        compare(lateAnswers(function() { compare(pending.length, 1) }), [])
    }

    /** Opens a page, lets `act(view)` start one request, closes the page; returns what the answer threw. */
    function lateRequest(act) {
        const h = createTemporaryObject(host, tc)
        const page = h.pageComponent.createObject(h)
        const view = findView(page)
        verify(view !== null)
        pending = []
        act(view)
        compare(pending.length, 1)
        page.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb() } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    function test_late_save_answer_does_not_throw() {
        compare(lateRequest(function(view) { view.saveRequested(7, 8, "2026-11-10T09:00:00", "2026-11-10T17:00:00", {}) }), [])
    }

    function test_late_extras_answer_does_not_throw() {
        compare(lateRequest(function(view) { view.extrasEdited({}) }), [])
    }

    function test_late_note_answer_does_not_throw() {
        compare(lateRequest(function(view) { view.noteEdited("text") }), [])
    }

    function test_late_activities_answer_does_not_throw() {
        const h = createTemporaryObject(host, tc)
        const page = h.pageComponent.createObject(h)
        const view = findView(page)
        verify(view !== null)
        pending = []
        view.projectChosen(7)
        compare(pending.length, 1)
        page.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb() } catch (e) { thrown.push(String(e)) }
        }
        compare(thrown, [])
    }
}
