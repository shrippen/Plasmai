import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"

// Statistics pane: the day of the activity distribution has its own switcher,
// and day and week share the width also when the day is empty.
TestCase {
    name: "StatsView"
    visible: true
    when: windowShown
    width: 1600
    height: 1400

    function cleanup() {
        KanteStyle.kind = KanteStyle.Kind.System
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

    function entry(day, hour) {
        return {
            begin: new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, 0, 0).toISOString(),
            end: new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour + 1, 0, 0).toISOString(),
            billable: true,
            project: { id: 1, name: "P" },
            activity: { id: 2, name: "Design" }
        }
    }

    function create() {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/StatsView.qml"))
        verify(c.status === Component.Ready, c.errorString())
        var now = new Date()
        var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
        return createTemporaryObject(c, this, { width: 1600, timesheets: [entry(yesterday, 9)] })
    }

    SignalSpy { id: rangeSpy; signalName: "needMoreHistory" }

    function test_pieDaySwitcher() {
        var view = create()
        compare(view.dayPieTotal, 0, "nothing today")
        rangeSpy.target = view
        rangeSpy.clear()
        view.shiftPieDay(-1)
        compare(view.pieDayOffset, -1)
        compare(view.dayPieTotal, 3600, "yesterday's hour")
        compare(view.dayPieRows[0].name, "Design")
        compare(rangeSpy.count, 1)
        verify(rangeSpy.signalArguments[0][0] <= view.selectedPieDay, "the range covers the chosen day")
        compare(view.dayOffset, 0, "time by hour keeps its own day")
    }

    function test_emptyDayKeepsHalfTheWidth() {
        KanteStyle.kind = KanteStyle.Kind.Kante
        var view = create()
        var pies = []
        findItem(view, function(i) {
            if (i.rows !== undefined && i.totalSeconds !== undefined && i.chartSize !== undefined) {
                pies.push(i)
            }
            return false
        })
        compare(pies.length, 2)
        waitForRendering(view)
        compare(pies[0].totalSeconds, 0, "day empty")
        verify(Math.abs(pies[0].width - pies[1].width) <= 1, pies[0].width + " vs " + pies[1].width)
        verify(pies[0].height >= pies[0].chartSize, "empty day keeps the chart height, not a strip")
    }
}
