import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Colored customer marker. Always occupies a fixed slot width so dots and
 * labels stay horizontally aligned across section headers and rows.
 */
Item {
    id: root

    property color customerColor: "#d2d6de"
    property bool showDot: true
    /** Relative to Kirigami.Units.iconSizes.small */
    property real sizeFactor: 0.55
    /** Slot width uses the section size so item dots center in the same column. */
    property real slotSizeFactor: 0.85

    readonly property real slotSize: Kirigami.Units.iconSizes.small * slotSizeFactor

    implicitWidth: slotSize
    implicitHeight: slotSize
    width: slotSize
    height: slotSize

    Rectangle {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.small * root.sizeFactor
        height: width
        radius: width / 2
        visible: root.showDot
        color: {
            var c = String(root.customerColor || "").trim()
            if (!c) {
                return "#d2d6de"
            }
            if (c.charAt(0) !== "#") {
                c = "#" + c
            }
            return c
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)
    }
}
