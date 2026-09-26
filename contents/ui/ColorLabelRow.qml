import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

/**
 * Color bar + label with hierarchy.
 * Bars occupy a fixed left slot and are centered in that slot so thick
 * (customer) and thin (project) markers share one vertical axis.
 */
Item {
    id: root

    property bool customerRole: false
    property color customerColor: "#d2d6de"
    property bool showDot: true
    property string label: ""
    property bool labelBold: customerRole
    property real labelOpacity: customerRole ? 0.9 : 1.0
    property int labelPointSize: customerRole
                                 ? Kirigami.Theme.smallFont.pointSize
                                 : Kirigami.Theme.defaultFont.pointSize

    readonly property real slotSize: Kirigami.Units.iconSizes.small * 0.85
    /** Gap after the shared bar slot — larger for projects. */
    readonly property real labelGap: customerRole
                                     ? Kirigami.Units.smallSpacing
                                     : Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
    readonly property real labelX: slotSize + labelGap

    implicitHeight: Math.max(slotSize, labelItem.implicitHeight)
    implicitWidth: labelX + labelItem.implicitWidth
    height: Math.max(slotSize, labelItem.implicitHeight)

    CustomerColorDot {
        id: colorBar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        customerColor: root.customerColor
        showDot: root.showDot
        sizeFactor: root.customerRole ? 0.9 : 0.45
        slotSizeFactor: 0.85
    }

    PlasmaComponents3.Label {
        id: labelItem
        anchors.left: parent.left
        anchors.leftMargin: root.labelX
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.bold: root.labelBold
        font.pointSize: root.labelPointSize
        opacity: root.labelOpacity
        elide: Text.ElideRight
    }
}
