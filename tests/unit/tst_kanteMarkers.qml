import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"

// Kante draws entity colours and markers as squares and loading rows as
// KanteSkeleton lines; System keeps the round marks and the pulsing bars.
TestCase {
    name: "KanteMarkers"
    visible: true
    when: windowShown
    width: 400
    height: 200

    function cleanup() {
        KanteStyle.kind = KanteStyle.Kind.System
    }

    function test_colorDotShape_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, round: true },
            { tag: "kante", kind: KanteStyle.Kind.Kante, round: false },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, round: false }
        ]
    }

    function test_colorDotShape(data) {
        KanteStyle.kind = data.kind
        var dot = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/CustomerColorDot.qml")), this)
        verify(dot !== null)
        var bar = dot.children[0]
        compare(bar.radius > 0, data.round)
    }

    function test_recDotShape() {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/RecDot.qml"))
        var dot = createTemporaryObject(c, this)
        verify(dot.radius > 0)
        KanteStyle.kind = KanteStyle.Kind.Kante
        compare(dot.radius, 0)
    }

    function test_loadingRow() {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/LoadingRow.qml"))
        var row = createTemporaryObject(c, this, { width: 200, rowCount: 2 })
        verify(row !== null)
        var skeleton = row.children[0]
        compare(skeleton.visible, false)
        compare(skeleton.lines, 2)
        KanteStyle.kind = KanteStyle.Kind.Kante
        compare(skeleton.visible, true)
        compare(row.opacity, 1)
    }
}
