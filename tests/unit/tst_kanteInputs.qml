import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"

// Kante enters dates and times with KanteDateField / KanteTimeField; DateField
// and TimeField keep their API (selectedDate, hours, minutes, setDate, setTime).
TestCase {
    name: "KanteInputs"
    visible: true
    when: windowShown
    width: 400
    height: 300

    SignalSpy {
        id: editSpy
    }

    function cleanup() {
        KanteStyle.kind = KanteStyle.Kind.System
        editSpy.target = null
        editSpy.clear()
    }

    function findItem(item, test) {
        if (test(item)) {
            return item
        }
        for (var i = 0; i < item.children.length; i++) {
            var found = findItem(item.children[i], test)
            if (found) {
                return found
            }
        }
        return null
    }

    function create(name) {
        var obj = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + name + ".qml")), this, { width: 300 })
        verify(obj !== null, name)
        return obj
    }

    function test_dateField_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, kante: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, kante: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, kante: true }
        ]
    }

    function test_dateField(data) {
        KanteStyle.kind = data.kind
        var field = create("DateField")
        var kante = findItem(field, function(i) { return i.dateEdited !== undefined && i.todayText !== undefined })
        verify(kante !== null)
        compare(kante.visible, data.kante)

        // Code -> Kante field.
        field.setDate(new Date(2026, 2, 12))
        compare(kante.date.toDateString(), new Date(2026, 2, 12).toDateString())

        // User in the Kante field -> DateField, with dateEdited.
        editSpy.signalName = "dateEdited"
        editSpy.target = field
        kante.pick(new Date(2026, 4, 1))
        compare(new Date(field.selectedDateMs).toDateString(), new Date(2026, 4, 1).toDateString())
        compare(editSpy.count, 1)

        // Emptied: the date stays.
        kante.pick(null)
        compare(new Date(field.selectedDateMs).toDateString(), new Date(2026, 4, 1).toDateString())
        compare(kante.date.toDateString(), new Date(2026, 4, 1).toDateString())
    }

    function test_timeField_data() {
        return test_dateField_data()
    }

    function test_timeField(data) {
        KanteStyle.kind = data.kind
        var field = create("TimeField")
        var kante = findItem(field, function(i) { return i.timeEdited !== undefined && i.minuteStep !== undefined })
        verify(kante !== null)
        compare(kante.visible, data.kante)

        field.setTime(9, 30)
        compare(kante.hour, 9)
        compare(kante.minute, 30)

        editSpy.signalName = "timeEdited"
        editSpy.target = field
        kante.pick(14, 5)
        compare(field.hours, 14)
        compare(field.minutes, 5)
        compare(editSpy.count, 1)

        kante.pick(-1, -1)
        compare(field.hours, 14)
        compare(kante.hour, 14)
    }
}
