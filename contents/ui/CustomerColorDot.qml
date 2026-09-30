import QtQuick
import org.kde.kirigami as Kirigami
import "Kante"

/**
 * Colored hierarchy marker as a short vertical pill; a KanteSwatch in Kante.
 * Thickness (System) or swatch size (Kante) encodes importance (sizeFactor).
 */
Item {
    id: root

    /** Kimai/display color. */
    property color customerColor: PlasmaiColors.entityFallback
    property bool showDot: true
    /**
     * Relative importance. Typical values:
     *  0.85–1.0 — customer / section / active timer (thicker)
     *  0.45–0.55 — project / activity row (thinner)
     */
    property real sizeFactor: 0.55
    /** Slot width uses the section size so bars share one vertical axis. */
    property real slotSizeFactor: 0.85

    readonly property real slotSize: KanteStyle.active
                                     ? Math.max(slotProbe.implicitWidth, swatch.implicitWidth)
                                     : Math.max(8, Kirigami.Units.iconSizes.small * slotSizeFactor)
    /** Thin ≈4–5px, thick ≈7–8px */
    readonly property real lineWidth: Math.max(4, Math.round(3.5 + root.sizeFactor * 4))

    implicitWidth: slotSize
    implicitHeight: slotSize
    width: slotSize

    Rectangle {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.lineWidth
        height: {
            var available = root.height
            if (available >= 8) {
                return Math.max(root.lineWidth * 2.2, Math.round(available * 0.62))
            }
            return Math.max(root.lineWidth * 2.2, Math.round(root.slotSize * 0.72))
        }
        radius: height / 2
        visible: root.showDot && !KanteStyle.active
        color: root.customerColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.18)
    }

    /** Kante swatch size for an importance: customer Normal, project Small, below Dense. */
    function swatchSize(factor) {
        if (factor >= 0.85) {
            return KanteSwatch.Size.Normal
        }
        return factor >= 0.45 ? KanteSwatch.Size.Small : KanteSwatch.Size.Dense
    }

    // Slot of the section size, so swatches of all sizes share one vertical axis.
    KanteSwatch {
        id: slotProbe
        visible: false
        size: root.swatchSize(root.slotSizeFactor)
    }

    // Kante: the entity colour is a swatch (a square); shrinks into short legend rows.
    KanteSwatch {
        id: swatch
        size: root.swatchSize(root.sizeFactor)
        anchors.centerIn: parent
        width: root.height > 0 ? Math.min(implicitWidth, root.height) : implicitWidth
        height: width
        visible: root.showDot && KanteStyle.active
        swatchColor: root.customerColor
    }
}
