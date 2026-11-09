import QtQuick
import QtTest

// Every date and time field in every view has a picker popup; the widget built
// all of them at start (42 day cells, 84 tumbler rows each) though one at a time
// is ever open. A closed picker holds no content; open, it works as before.
TestCase {
    id: test
    name: "LazyPickers"
    visible: true
    when: windowShown
    width: 600
    height: 600

    /** A closed popup keeps its frame, not its content. */
    readonly property int maxClosedItems: 5

    function countItems(item) {
        if (!item) {
            return 0
        }
        let n = 1
        for (let i = 0; i < item.children.length; i++) {
            n += countItems(item.children[i])
        }
        return n
    }

    function findItem(item, test) {
        if (!item) {
            return null
        }
        if (test(item)) {
            return item
        }
        for (let i = 0; i < item.children.length; i++) {
            const found = findItem(item.children[i], test)
            if (found) {
                return found
            }
        }
        return null
    }

    function create(name) {
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/Controls/" + name + ".qml"))
        verify(c.status === Component.Ready, c.errorString())
        return createTemporaryObject(c, test, { parent: test })
    }

    SignalSpy { id: spy }

    function test_datePicker() {
        const picker = create("DatePicker")
        const closed = countItems(picker.contentItem)
        verify(closed <= maxClosedItems, "closed: " + closed + " items")

        picker.openFor(new Date(2026, 10, 9, 12, 0))
        tryCompare(picker, "opened", true)
        const day = findItem(picker.contentItem, function(i) { return i.clicked !== undefined && i.enabled && i.contentItem && String(i.contentItem.text) === "18" })
        verify(day !== null, "day 18 shown")
        spy.target = picker
        spy.signalName = "picked"
        spy.clear()
        mouseClick(day)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0].getDate(), 18)
        compare(spy.signalArguments[0][0].getMonth(), 10)
    }

    function test_timePicker() {
        const picker = create("TimePicker")
        const closed = countItems(picker.contentItem)
        verify(closed <= maxClosedItems, "closed: " + closed + " items")

        picker.openFor(9, 30)
        tryCompare(picker, "opened", true)
        const select = findItem(picker.contentItem, function(i) { return i.text === "Select" && i.clicked !== undefined })
        verify(select !== null)
        spy.target = picker
        spy.signalName = "picked"
        spy.clear()
        mouseClick(select)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], 9)
        compare(spy.signalArguments[0][1], 30)

        // Opened again for another time: the tumblers start there.
        picker.openFor(14, 5)
        tryCompare(picker, "opened", true)
        spy.clear()
        mouseClick(findItem(picker.contentItem, function(i) { return i.text === "Select" && i.clicked !== undefined }))
        compare(spy.signalArguments[0][0], 14)
        compare(spy.signalArguments[0][1], 5)
    }
}
