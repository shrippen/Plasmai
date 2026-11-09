import QtQuick
import QtTest

// Every Recent and favourite row had its entry menu (five items) built at start,
// though it is opened now and then: about 1,200 objects in the widget. The menu
// is built when it opens first and kept for the next time.
TestCase {
    id: test
    name: "LazyRowMenu"
    visible: true
    when: windowShown
    width: 400
    height: 400

    SignalSpy { id: spy; signalName: "editRequested" }

    function menuItems(item) {
        let n = 0
        function walk(it) {
            if (it.triggered !== undefined && it.text !== undefined && it.menu !== undefined) {
                n++
            }
            for (let i = 0; i < it.children.length; i++) {
                walk(it.children[i])
            }
            for (let i = 0; it.data && i < it.data.length; i++) {
                if (it.data[i] && it.data[i].contentItem !== undefined && it.data[i].count !== undefined) {
                    n += it.data[i].count
                }
            }
        }
        walk(item)
        return n
    }

    function test_menuBuiltOnOpen() {
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/ActivityListRow.qml"))
        verify(c.status === Component.Ready, c.errorString())
        const row = createTemporaryObject(c, test, { width: 300, titleText: "Design", showHistoryActions: true,
                                                     canEditStopped: true, canDeleteEntry: true })
        compare(menuItems(row), 0, "closed: no menu")

        row.openHistoryMenu(10, 10)
        const menu = row.historyMenu
        verify(menu !== null)
        tryCompare(menu, "opened", true)
        verify(menu.count >= 2)
        spy.target = row
        spy.clear()
        let edit = null
        for (let i = 0; i < menu.count; i++) {
            // By its icon: tests run without translations (no i18n).
            if (menu.itemAt(i).icon.name === "document-edit") {
                edit = menu.itemAt(i)
            }
        }
        verify(edit !== null)
        edit.triggered()
        compare(spy.count, 1)
        menu.close()
        tryCompare(menu, "visible", false)

        row.openHistoryMenu(10, 10)
        verify(row.historyMenu === menu, "built once, kept")
    }
}
