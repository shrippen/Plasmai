import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../qml"

/** TripEditPage (app/qml): what the page asks of the session and how it shows the answers. */
TestCase {
    id: tc
    name: "TripEditPageWiring"
    when: windowShown
    width: 400
    height: 400

    property var calls: []
    property var shown: []

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
                    property bool busy: false
                    function save(body, tripId, form, suggestion, cb) {
                        tc.calls.push({ name: "save", body: body, tripId: tripId, suggestion: suggestion, cb: cb })
                    }
                    function remove(id, cb) { tc.calls.push({ name: "remove", tripId: id, cb: cb }) }
                }
                property var setup: QtObject {}
                property var connection: QtObject { property bool configured: true; property string state: "ok" }
            }
            function fill(text, args) { return text.replace(/%(\d)/g, function(m, n) { return args[n - 1] }) }
            function i18n(text) { return fill(text, Array.prototype.slice.call(arguments, 1)) }
            function showPassiveNotification(text) { tc.shown.push(text) }
            property alias stack: stack
            property var pageStack: stack
            Kirigami.PageRow {
                id: stack
                anchors.fill: parent
                initialPage: Kirigami.Page { title: "list" }
            }
            property Component pageComponent: Component { TripEditPage { } }
        }
    }

    function init() {
        calls = []
        shown = []
    }

    /** The trip sheet inside the page: the item with the sheet's save signal. */
    function findSheet(item) {
        if (typeof item.saveRequested === "function" && typeof item.load === "function") {
            return item
        }
        for (const child of item.children) {
            const found = findSheet(child)
            if (found) {
                return found
            }
        }
        return null
    }

    function openPage(props) {
        const h = createTemporaryObject(host, tc)
        const page = h.stack.push(h.pageComponent, props || {})
        verify(page !== null)
        const sheet = findSheet(page)
        verify(sheet !== null)
        return { host: h, page: page, sheet: sheet }
    }

    function test_save_hands_body_and_suggestion_to_the_session() {
        const sg = { id: 12 }
        const p = openPage({ suggestion: sg })
        p.sheet.saveRequested({ km: 5 }, null, { purpose: "business" })
        compare(calls.length, 1)
        compare(calls[0].name, "save")
        compare(calls[0].body.km, 5)
        compare(calls[0].tripId, null)
        compare(calls[0].suggestion.id, 12)
    }

    function test_saved_trip_is_shown_and_the_page_closes() {
        const p = openPage()
        p.sheet.saveRequested({ km: 5 }, null, {})
        calls[0].cb({ ok: true, data: { distance: 5 } })
        compare(shown.length, 1)
        verify(shown[0].indexOf("Trip saved") === 0)
        tryCompare(p.host.stack, "depth", 1)
    }

    function test_deleted_trip_closes_the_page_silently() {
        const p = openPage()
        p.sheet.deleteRequested(4)
        compare(calls[0].name, "remove")
        compare(calls[0].tripId, 4)
        calls[0].cb({ ok: true })
        compare(shown, [])
        tryCompare(p.host.stack, "depth", 1)
    }

    function test_failed_save_goes_to_the_sheet_and_keeps_the_page() {
        const p = openPage()
        p.sheet.saveRequested({ km: 5 }, 7, {})
        calls[0].cb({ ok: false, error: { type: "unknown", status: 400, detail: "Month is locked", fields: { distance: "too long" } } })
        compare(p.sheet.errorText, "Month is locked")
        compare(p.sheet.serverErrors.distance, "too long")
        compare(p.host.stack.depth, 2)
    }

    function test_failed_delete_goes_to_the_sheet() {
        const p = openPage()
        p.sheet.deleteRequested(4)
        calls[0].cb({ ok: false, error: { type: "unknown", status: 400, detail: "Not yours" } })
        compare(p.sheet.errorText, "Not yours")
        compare(p.host.stack.depth, 2)
    }
}
