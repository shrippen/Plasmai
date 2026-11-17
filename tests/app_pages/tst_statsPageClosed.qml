import QtQuick
import QtTest
import "../qml"

/** StatsPage (app/qml): shows the session's statistics part and leaves nothing behind when closed. */
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
                property var stats: QtObject {
                    property var timesheets: []
                    property var trips: null
                    property bool loading: false
                    function open() { tc.pending.push("open") }
                    function load(begin, end) { tc.pending.push([begin, end]) }
                    function forget() {}
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

    // The page loads through the session and shows what it holds; it keeps nothing of its own.
    function test_page_opens_the_session_part() {
        pending = []
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        verify(pending.indexOf("open") >= 0)
        obj.destroy()
        wait(0)
    }

    // A page that is gone leaves the part usable: no callback of the page is left to throw.
    function test_page_leaves_no_callbacks() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        obj.destroy()
        wait(0)
        h.session.stats.timesheets = [{ id: 1 }]
        h.session.stats.trips = []
        h.session.stats.loading = true
    }
}
