import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"

// Kante draws Plasmai's charts with Kante components: hours as KanteBarChart
// (stacked with project colours, pies as bars), the week as KanteWeekTimeline.
// System keeps its own charts.
TestCase {
    name: "KanteCharts"
    visible: true
    when: windowShown
    width: 400
    height: 400

    readonly property var week: [
        { label: "Mo", totalSeconds: 27000, stacks: [{ key: "a", seconds: 18000, color: "#d65d0e" }, { key: "b", seconds: 9000, color: "#458588" }] },
        { label: "Tu", totalSeconds: 7200, stacks: [{ key: "b", seconds: 7200, color: "#458588" }] }
    ]

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

    function kanteBars(item) {
        return findItem(item, function(i) { return i.stackColors !== undefined })
    }

    function create(name, props) {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + name + ".qml"))
        var obj = createTemporaryObject(c, this, props)
        verify(obj !== null, name)
        return obj
    }

    function test_barChart() {
        var chart = create("BarChart", { width: 300, height: 120, model: [{ label: "9", seconds: 1800 }, { label: "", seconds: 3600 }] })
        var bars = kanteBars(chart)
        verify(!bars.visible)
        KanteStyle.kind = KanteStyle.Kind.Kante
        verify(bars.visible)
        verify(bars.axis)
        compare(bars.valueFormat, KanteBarChart.ValueFormat.Hours)
        compare(bars.values, [0.5, 1])
        compare(bars.labels, ["9", ""])
    }

    // Parts keep one index across days, so a project has one colour.
    function test_stackedBarChart() {
        var chart = create("StackedBarChart", { width: 300, height: 120, days: week })
        var bars = kanteBars(chart)
        verify(!bars.visible)
        KanteStyle.kind = KanteStyle.Kind.KanteLight
        verify(bars.visible)
        compare(bars.values, [[5, 2.5], [0, 2]])
        compare(bars.stackColors.length, 2)
        compare(Qt.color(bars.stackColors[1]), Qt.color("#458588"))
        compare(bars.labels, ["Mo", "Tu"])
    }

    // Kante has no pie: one bar per row in the row's colour.
    function test_pieChart() {
        var rows = [{ name: "Web", seconds: 7200, color: "#d65d0e", ratio: 0.8 }, { name: "App", seconds: 1800, color: "#458588", ratio: 0.2 }]
        var pie = create("PieChart", { width: 300, rows: rows, totalSeconds: 9000 })
        var bars = kanteBars(pie)
        verify(!bars.visible)
        KanteStyle.kind = KanteStyle.Kind.Kante
        verify(bars.visible)
        compare(bars.values, [[2, 0], [0, 0.5]])
        compare(Qt.color(bars.stackColors[0]), Qt.color("#d65d0e"))
    }

    function test_weeklyHourChart() {
        var days = [
            { label: "Mo", date: new Date(2000, 0, 3), totalSeconds: 3600, segments: [{ startHour: 9, endHour: 10, color: "#d65d0e", name: "Web", seconds: 3600 }] },
            { label: "Tu", date: new Date(), totalSeconds: 0, segments: [] }
        ]
        var chart = create("WeeklyHourChart", { width: 300, days: days, hourMin: 8, hourMax: 18 })
        var timeline = findItem(chart, function(i) { return i.dayNames !== undefined })
        verify(!timeline.visible)
        KanteStyle.kind = KanteStyle.Kind.Kante
        verify(timeline.visible)
        compare(timeline.dayNames, ["Mo", "Tu"])
        compare(timeline.entries.length, 1)
        compare(timeline.entries[0].day, 0)
        compare(timeline.entries[0].start, 9)
        compare(timeline.entries[0].end, 10)
        compare(timeline.spanFrom, 8)
        compare(timeline.spanTo, 18)
        compare(timeline.today, 1)
        verify(timeline.now >= 0)

        timeline.entryClicked(0)
        verify(timeline.tip.indexOf("Web") === 0)
    }
}
