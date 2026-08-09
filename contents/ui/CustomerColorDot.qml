import QtQuick
import org.kde.kirigami as Kirigami
import "../code/colorDistinct.js" as ColorDistinct

/**
 * Colored hierarchy marker as a short vertical pill.
 * Thickness encodes importance (sizeFactor). Optionally resolves
 * within-category color distinction via colorCategory + entityId so every
 * bar uses the same shifted palette as the rest of the plasmoid.
 */
Item {
    id: root

    /** Raw or already-resolved Kimai/display color. */
    property color customerColor: "#d2d6de"
    /**
     * When set with entityId, color is passed through ColorDistinct.adjust
     * ("customer" | "project" | "activity").
     */
    property string colorCategory: ""
    property var entityId: null
    property bool showDot: true
    /**
     * Relative importance. Typical values:
     *  0.85–1.0 — customer / section / active timer (thicker)
     *  0.45–0.55 — project / activity row (thinner)
     */
    property real sizeFactor: 0.55
    /** Slot width uses the section size so bars share one vertical axis. */
    property real slotSizeFactor: 0.85

    readonly property color displayColor: {
        if (root.colorCategory.length > 0
                && root.entityId !== null && root.entityId !== undefined && root.entityId !== "") {
            return ColorDistinct.adjust(root.colorCategory, root.entityId, root.customerColor)
        }
        return root.customerColor
    }

    readonly property real slotSize: Math.max(8, Kirigami.Units.iconSizes.small * slotSizeFactor)
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
        visible: root.showDot
        color: root.displayColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.18)
    }
}
