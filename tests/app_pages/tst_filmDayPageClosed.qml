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
    property var errors: []

    function quiet() {}

    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property QtObject session: QtObject {
                property var filmDay: QtObject {
                    property var ids: ({})
                    function resolveMode(mode, cb) { tc.pending.push(cb) }
                    function openDay(date, projectId, cb, prefer) { tc.pending.push(function() { cb({}, []) }) }
                    function productionDay() {}
                    function viewInfo() { return {} }
                    function saveExtras() {}
                    function saveNote() {}
                    function saveDay() {}
                }
                property var catalog: QtObject {
                    property var projectPickerModel: []
                    property var activities: []
                    property var activitiesByProject: ({})
                    property var projects: []
                    property var customers: []
                    signal changed()
                    function loadActivities() {}
                    function projectById() { return null }
                }
                property var connection: QtObject { property bool configured: true; property string state: "ok" }
                property var timer: QtObject { property bool tracking: false; property var active: null; property int elapsedSeconds: 0 }
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

    function test_late_mode_answer_does_not_throw() {
        compare(lateAnswers(function() { compare(pending.length, 1) }), [])
    }

    function test_late_day_answer_does_not_throw() {
        // The mode answer arrives while the page is open and asks for the day.
        compare(lateAnswers(function() {
            pending.shift()()
            compare(pending.length, 1)
        }), [])
    }
}
