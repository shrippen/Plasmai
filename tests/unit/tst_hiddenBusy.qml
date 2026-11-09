import QtQuick
import QtTest
import "../../contents/ui"

// The poll sets session.busy twice every refresh. A view that is not shown
// must not follow it: every enabled change re-evaluates the style bindings of
// all controls below (42 ms per toggle in demo/bench.sh, refresh-busyOn).
TestCase {
    name: "HiddenBusy"
    visible: true
    when: windowShown
    width: 600
    height: 800

    readonly property var views: ["ManualEntryView", "FilmDayView", "ActiveEditView", "TripSheet"]

    /** enabled of every item below `item`, in tree order. */
    function enabledStates(item) {
        const out = []
        function walk(it) {
            out.push(it.enabled)
            for (let i = 0; i < it.children.length; i++) {
                walk(it.children[i])
            }
        }
        walk(item)
        return out
    }

    function create(name, shown) {
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + name + ".qml"))
        verify(c.status === Component.Ready, c.errorString())
        return createTemporaryObject(c, this, { width: 600, visible: shown, configured: true })
    }

    function test_hiddenIgnoresBusy_data() {
        return views.map(function(v) { return { tag: v, name: v } })
    }

    function test_hiddenIgnoresBusy(data) {
        const view = create(data.name, false)
        const before = enabledStates(view)
        view.busy = true
        compare(enabledStates(view), before, "a hidden view keeps its controls as they are")
    }

    // Shown, busy still locks the inputs; shown again while busy, too.
    function test_shownFollowsBusy_data() {
        return test_hiddenIgnoresBusy_data()
    }

    function test_shownFollowsBusy(data) {
        const view = create(data.name, true)
        const before = enabledStates(view)
        view.busy = true
        verify(JSON.stringify(enabledStates(view)) !== JSON.stringify(before), "busy locks inputs")
        const locked = enabledStates(view)
        view.visible = false
        view.visible = true
        compare(enabledStates(view), locked, "shown again while busy: still locked")
    }
}
