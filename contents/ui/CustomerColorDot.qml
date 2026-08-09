import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Colored customer marker as a short vertical pill.
 * Thickness encodes hierarchy: larger sizeFactor → thicker (more important).
 * Occupies a fixed slot width so markers and labels stay aligned.
 */
Item {
    id: root

    property color customerColor: "#d2d6de"
    property bool showDot: true
    /**
     * Relative importance. Typical values:
     *  0.85–1.0 — customer / section / active timer (thicker)
     *  0.45–0.55 — project / activity row (thinner)
     */
    property real sizeFactor: 0.55
    /** Slot width uses the section size so bars share one vertical axis. */
    property real slotSizeFactor: 0.85

    readonly property real slotSize: Math.max(8, Kirigami.Units.iconSizes.small * slotSizeFactor)
    /** Thin ≈4–5px, thick ≈7–8px */
    readonly property real lineWidth: Math.max(4, Math.round(3.5 + root.sizeFactor * 4))

    implicitWidth: slotSize
    implicitHeight: slotSize
    // Keep a stable column width; height is owned by Layout / anchors.
    width: slotSize

    Rectangle {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.lineWidth
        // Shorter than the row so it reads as a pill, not a full-height rule.
        height: {
            var available = root.height
            if (available >= 8) {
                return Math.max(root.lineWidth * 2.2, Math.round(available * 0.62))
            }
            return Math.max(root.lineWidth * 2.2, Math.round(root.slotSize * 0.72))
        }
        // Fully rounded ends → capsule / pill.
        radius: height / 2
        visible: root.showDot
        color: root.customerColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.18)
    }
}
