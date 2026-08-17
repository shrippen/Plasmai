import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

QQC2.ItemDelegate {
    id: root

    property color customerColor: "#d2d6de"
    property string colorCategory: ""
    property var entityId: null
    property string titleText: ""
    property string subtitleText: ""
    property string tooltipText: ""
    property bool showPlayIcon: true
    property bool rowEnabled: true
    /** Short transient right-side hint (e.g. when clicking an already-running activity). */
    property bool runningHintVisible: false
    property string runningHintText: ""
    property string runningHintCounterText: ""

    enabled: rowEnabled
    hoverEnabled: true
    Accessible.role: Accessible.ListItem
    Accessible.name: titleText
    Accessible.description: i18n("Starts or switches this activity")
    implicitHeight: Math.max(contentItem.implicitHeight + topPadding + bottomPadding,
                             TouchUi.rowMinHeight)
    topPadding: TouchUi.listRowPadding
    bottomPadding: TouchUi.listRowPadding

    QQC2.ToolTip.visible: root.hovered && root.tooltipText.length > 0
    QQC2.ToolTip.text: root.tooltipText
    QQC2.ToolTip.delay: 600

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        CustomerColorDot {
            customerColor: root.customerColor
            colorCategory: root.colorCategory
            entityId: root.entityId
            sizeFactor: TouchUi.active ? 0.55 : 0.45
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
        }

        Kirigami.Icon {
            visible: root.showPlayIcon
            Layout.preferredWidth: TouchUi.iconSize
            Layout.preferredHeight: TouchUi.iconSize
            source: "media-playback-start"
            opacity: root.enabled ? 1 : 0.5
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: root.titleText
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.subtitleText.length > 0
                text: root.subtitleText
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            id: runningHintBox
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 0

            PlasmaComponents3.Label {
                id: runningHintTop
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.NoWrap
                text: runningHintText
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize + 2
                color: Kirigami.Theme.positiveTextColor
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                id: runningHintBottom
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.NoWrap
                text: runningHintCounterText
                font.family: "monospace"
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize + 2
                color: Kirigami.Theme.positiveTextColor
                elide: Text.ElideRight
            }

            // Fade-in/out without changing layout metrics.
            opacity: runningHintVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            visible: runningHintText.length > 0 || runningHintCounterText.length > 0
        }
    }
}
