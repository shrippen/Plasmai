import QtQuick
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi

/**
 * Colored customer marker. Always occupies a fixed slot width so dots and
 * labels stay horizontally aligned across section headers and rows.
 */
Item {
    id: root

    property color customerColor: KimaiApi.DEFAULT_CUSTOMER_COLOR
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
        color: KimaiApi.normalizeCustomerColor(root.customerColor)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)
    }
}
