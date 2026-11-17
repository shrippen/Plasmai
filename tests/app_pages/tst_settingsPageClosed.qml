import QtQuick
import QtTest
import "../qml"

/** SettingsPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "SettingsPageClosed"
    when: windowShown
    width: 400
    height: 400

    property var pending: []

    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property int visualStyle: 0
            property QtObject session: QtObject {
                property var settings: QtObject {
                    property int refreshInterval: 60
                    property int recentCount: 5
                    property string locationName: ""
                    property real latitude: 0
                    property real longitude: 0
                    property int workDayBegin: 0
                    property int workDayEnd: 0
                    property int idleStopMinutes: 5
                    function set() {}
                }
                property var setup: QtObject {
                    function searchPlace(query, cb) { tc.pending.push(cb) }
                }
                property var trips: QtObject { function resolve() {} }
            }
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { SettingsPage { } }
        }
    }

    /** The place search timer of the page. */
    function findTimer(item) {
        const kids = [...item.data, ...item.resources]
        for (const kid of kids) {
            if (kid.interval === 400) {
                return kid
            }
            const found = kid.data !== undefined ? findTimer(kid) : null
            if (found) {
                return found
            }
        }
        return null
    }

    function test_late_place_answer_does_not_throw() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        const timer = findTimer(obj)
        verify(timer !== null)
        obj.locationQuery = "Berlin"
        pending = []
        timer.triggered()
        compare(pending.length, 1)
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb({ ok: true, results: [] }) } catch (e) { thrown.push(String(e)) }
        }
        compare(thrown, [])
    }
}
