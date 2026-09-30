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

    // Pickers: Kante shows a KanteSearchCombo; a row names its customer (no section heads).
    function test_searchableCombo_data() {
        return test_dateField_data()
    }

    function test_searchableCombo(data) {
        KanteStyle.kind = data.kind
        var items = [{ label: "Website", section: "ACME", rowColor: "#d65d0e" },
                     { label: "Support", section: "global" }]
        var combo = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/SearchableCombo.qml")), this,
                                          { width: 300, items: items, sectionTitleMap: { global: "Global activities" } })
        var kante = findItem(combo, function(i) { return i.newEntered !== undefined })
        verify(kante !== null)
        compare(kante.visible, data.kante)
        compare(combo.kanteModel[0].text, "Website · ACME")
        compare(Qt.color(combo.kanteModel[0].color), Qt.color("#d65d0e"))
        compare(combo.kanteModel[1].text, "Support")

        combo.currentIndex = 1
        compare(kante.currentIndex, 1)

        editSpy.signalName = "activated"
        editSpy.target = combo
        kante.choose(0)
        compare(combo.currentIndex, 0)
        compare(editSpy.count, 1)
        compare(editSpy.signalArguments[0][0], 0)
    }
}
