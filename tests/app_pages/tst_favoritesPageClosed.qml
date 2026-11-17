import QtQuick
import QtTest
import "../qml"

/** FavoritesPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "FavoritesPageClosed"
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
                property var catalog: QtObject {
                    property var projectPickerModel: []
                    function loadActivities(projectId, cb) { tc.pending.push(function() { cb([]) }) }
                }
                property var connection: QtObject { property bool configured: true }
                property var favorites: QtObject {
                    function isPinned() { return false }
                    function toggle() {}
                }
            }
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { FavoritesPage { } }
        }
    }

    function test_late_activities_answer_does_not_throw() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        pending = []
        obj.toggleExpanded(7)
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
