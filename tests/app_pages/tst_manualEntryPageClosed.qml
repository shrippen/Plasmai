import QtQuick
import QtTest
import "../qml"

/** ManualEntryPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "ManualEntryPageClosed"
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
                property var entries: QtObject {
                    property bool canCreate: true
                    function write(id, fields, cb) { tc.pending.push(cb) }
                }
                property var catalog: QtObject {
                    property var projectPickerModel: []
                    property var customers: []
                    function loadActivities(projectId, cb) { tc.pending.push(function() { cb([]) }) }
                }
                property var connection: QtObject {
                    property bool configured: true
                    property string state: "ok"
                    property var profiles: []
                    property var profile: null
                    property var capabilities: ({})
                }
            }
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { ManualEntryPage { } }
        }
    }

    /** Opens the page, lets `open` start a request, destroys it, calls the stored answers; returns what they threw. */
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

    function test_late_write_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.doSave(1, 2, "", "", "", null, []) }, { ok: false }), [])
    }

    function test_late_project_activities_answer_does_not_throw() {
        function findView(item) {
            if (typeof item.projectChosen === "function") {
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
        compare(lateAnswers(function(p) {
            const view = findView(p)
            verify(view !== null)
            view.projectChosen(7)
        }, null), [])
    }

    function test_late_edit_activities_answer_does_not_throw() {
        const h = createTemporaryObject(host, tc)
        pending = []
        const obj = h.pageComponent.createObject(h, { editTs: { id: 5, project: { id: 1 } } })
        verify(obj !== null)
        compare(pending.length, 1)
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb() } catch (e) { thrown.push(String(e)) }
        }
        compare(thrown, [])
    }
}
