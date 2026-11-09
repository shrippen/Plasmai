import QtQuick
import QtTest
import "../../contents/ui/Kante"

// Each chart has a System and a Kante variant; only one shows. The hidden one
// must not build its bars: opening the statistics created ~3,600 objects, about
// half of them in the variant that was not shown.
TestCase {
    name: "HiddenCharts"
    visible: true
    when: windowShown
    width: 800
    height: 600

    /** Items a hidden variant may keep (frames, empty labels), not one per bar. */
    readonly property int maxHiddenItems: 12

    function cleanup() {
        KanteStyle.kind = KanteStyle.Kind.System
    }

    /** A shown building block (KanteBarChart, colour dot): its own hidden parts are its business. */
    function isBlock(it) {
        return it.stackColors !== undefined || it.customerColor !== undefined
    }

    /** Items below `item` that are not shown because an ancestor (or they) are hidden. */
    function hiddenItems(item) {
        let n = 0
        function walk(it, hidden) {
            const h = hidden || !it.visible
            if (h) {
                n++
            } else if (isBlock(it)) {
                return
            }
            for (let i = 0; i < it.children.length; i++) {
                walk(it.children[i], h)
            }
        }
        for (let i = 0; i < item.children.length; i++) {
            walk(item.children[i], false)
        }
        return n
    }

    function hours() {
        const out = []
        for (let h = 0; h < 24; h++) {
            out.push({ label: String(h), seconds: h >= 8 && h < 18 ? 3000 : 0 })
        }
        return out
    }

    function week() {
        const out = []
        for (let d = 0; d < 7; d++) {
            out.push({ label: "D" + d, totalSeconds: 7200,
                       stacks: [{ key: "a", name: "A", seconds: 3600, color: "#d65d0e" },
                                { key: "b", name: "B", seconds: 3600, color: "#458588" }] })
        }
        return out
    }

    function rows() {
        const out = []
        for (let i = 0; i < 6; i++) {
            out.push({ key: "k" + i, name: "R" + i, seconds: 1800, ratio: 1 / 6, color: "#458588" })
        }
        return out
    }

    function create(name, props) {
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + name + ".qml"))
        verify(c.status === Component.Ready, c.errorString())
        return createTemporaryObject(c, this, Object.assign({ width: 600, height: 200 }, props))
    }

    function test_hiddenVariantEmpty_data() {
        const out = []
        const kinds = [{ name: "system", kind: KanteStyle.Kind.System }, { name: "kante", kind: KanteStyle.Kind.Kante }]
        for (let k = 0; k < kinds.length; k++) {
            out.push({ tag: "BarChart-" + kinds[k].name, kind: kinds[k].kind, chart: "BarChart", props: { model: hours() } })
            out.push({ tag: "StackedBarChart-" + kinds[k].name, kind: kinds[k].kind, chart: "StackedBarChart", props: { days: week() } })
            out.push({ tag: "PieChart-" + kinds[k].name, kind: kinds[k].kind, chart: "PieChart", props: { rows: rows(), totalSeconds: 10800 } })
        }
        return out
    }

    function test_hiddenVariantEmpty(data) {
        KanteStyle.kind = data.kind
        const chart = create(data.chart, data.props)
        wait(0)
        const n = hiddenItems(chart)
        verify(n <= maxHiddenItems, "hidden items: " + n)
    }
}
