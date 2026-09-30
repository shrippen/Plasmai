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

    // System: a round bar; Kante: a KanteSwatch in the entity colour.
    function test_colorDotShape_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, swatch: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, swatch: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, swatch: true }
        ]
    }

    function test_colorDotShape(data) {
        KanteStyle.kind = data.kind
        var dot = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/CustomerColorDot.qml")), this,
                                        { customerColor: "#336699" })
        verify(dot !== null)
        var bar = dot.children[0]
        var swatch = dot.children[1]
        verify(bar.radius > 0)
        compare(bar.visible, !data.swatch)
        compare(swatch.visible, data.swatch)
        compare(swatch.swatchColor, Qt.color("#336699"))
        compare(swatch.width, swatch.height)
    }

    // Kante: a swatch fits a short legend row.
    function test_colorDotSwatchFits() {
        KanteStyle.kind = KanteStyle.Kind.Kante
        var dot = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/CustomerColorDot.qml")), this,
                                        { height: 10 })
        compare(dot.children[1].height, 10)
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
