import QtQuick
import QtTest

// Manual entry, running-entry editor and film day fill their project and
// activity pickers from an entry's ids. The lists may load after the entry.
TestCase {
    id: test
    name: "ProjectPick"
    visible: true
    when: windowShown
    width: 600
    height: 800

    readonly property var projects: [
        { label: "Alpha", value: { id: 3 } },
        { label: "Beta", value: { id: 5 } }
    ]
    readonly property var activities: [
        { label: "Shoot", value: { id: 11 } },
        { label: "Edit", value: { id: 12 } }
    ]
    readonly property var views: ["ManualEntryView", "ActiveEditView", "FilmDayView"]

    SignalSpy { id: chosen; signalName: "projectChosen" }

    function create(name) {
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + name + ".qml"))
        verify(c.status === Component.Ready, c.errorString())
        const view = createTemporaryObject(c, test, { width: 600, visible: true, configured: true })
        if (name === "ManualEntryView") {
            view.editingExisting = true
        }
        chosen.target = view
        chosen.clear()
        return view
    }

    function load(view, name, ts) {
        if (name === "ManualEntryView") {
            view.loadFromTimesheet(ts)
        } else if (name === "ActiveEditView") {
            view.timesheet = ts
        } else {
            view.loadForDay(new Date(2026, 10, 9), ts, null, null, null)
        }
    }

    function lists(view) {
        view.projectPickerModel = projects
        view.activityPickerModel = activities
    }

    function views_data() {
        return views.map(function(v) { return { tag: v, name: v } })
    }

    function test_listsPresent_data() { return views_data() }
    function test_listsPresent(data) {
        const view = create(data.name)
        lists(view)
        load(view, data.name, { project: 5, activity: 12 })
        tryCompare(view.projectCombo, "currentIndex", 1)
        tryCompare(view.activityCombo, "currentIndex", 1)
        compare(chosen.count, 1)
        compare(chosen.signalArguments[0][0], 5)
    }

    function test_idAsObject_data() { return views_data() }
    function test_idAsObject(data) {
        const view = create(data.name)
        lists(view)
        load(view, data.name, { project: { id: 3 }, activity: { id: 11 } })
        tryCompare(view.projectCombo, "currentIndex", 0)
        tryCompare(view.activityCombo, "currentIndex", 0)
    }

    // The lists arrive after the entry: the ids wait and apply on arrival.
    function test_listsLate_data() { return views_data() }
    function test_listsLate(data) {
        const view = create(data.name)
        load(view, data.name, { project: 5, activity: 12 })
        compare(view.projectCombo.currentIndex, -1)
        compare(view.activityCombo.currentIndex, -1)

        view.projectPickerModel = projects
        tryCompare(view.projectCombo, "currentIndex", 1)
        compare(view.activityCombo.currentIndex, -1)
        compare(chosen.count, 1)
        compare(chosen.signalArguments[0][0], 5)

        view.activityPickerModel = activities
        tryCompare(view.activityCombo, "currentIndex", 1)
    }

    function test_unknownId_data() { return views_data() }
    function test_unknownId(data) {
        const view = create(data.name)
        lists(view)
        load(view, data.name, { project: 99, activity: 98 })
        wait(50)
        compare(view.projectCombo.currentIndex, -1)
        compare(view.activityCombo.currentIndex, -1)
        compare(chosen.count, 0)
    }
}
