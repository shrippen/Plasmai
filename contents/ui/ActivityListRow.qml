import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

QQC2.ItemDelegate {
    id: root

    property color customerColor: "#d2d6de"
    property string titleText: ""
    property string subtitleText: ""
    property string tooltipText: ""
    property bool showPlayIcon: true
    property bool rowEnabled: true

    enabled: rowEnabled
    hoverEnabled: true

    QQC2.ToolTip.visible: root.hovered && root.tooltipText.length > 0
    QQC2.ToolTip.text: root.tooltipText
    QQC2.ToolTip.delay: 600

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        CustomerColorDot {
            customerColor: root.customerColor
            sizeFactor: 0.55
            Layout.alignment: Qt.AlignVCenter
        }

        Kirigami.Icon {
            visible: root.showPlayIcon
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
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
    }
}
