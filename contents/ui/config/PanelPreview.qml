import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Kante"

/** Mock of the running timer in the taskbar, for the indicator setting. */
Rectangle {
    id: preview

    property int mode: 0
    property bool showProject: true
    property bool showElapsed: true

    implicitWidth: Kirigami.Units.gridUnit * 20
    implicitHeight: Kirigami.Units.gridUnit * 2.6
    clip: true
    color: Kirigami.Theme.backgroundColor
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
        anchors.rightMargin: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: 1
            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Layout.preferredWidth
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
            }
        }
        Item { Layout.fillWidth: true }

        Item {
            id: widget
            Layout.preferredWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Layout.preferredWidth
                    source: Qt.resolvedUrl("../../images/icon.svg")
                    isMask: true
                    color: Kirigami.Theme.textColor
                }
                Text {
                    visible: preview.showProject
                    text: "Website-Relaunch"
                    color: Kirigami.Theme.textColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                RecDot {
                    visible: preview.mode === 0
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    visible: preview.showElapsed
                    text: "1:24:07"
                    color: Kirigami.Theme.textColor
                    font.family: KanteStyle.monoFamily
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                }
            }
            RecEdge { mode: preview.mode }
        }

        Text {
            text: "11:42"
            color: Kirigami.Theme.textColor
            opacity: 0.8
            font.family: KanteStyle.monoFamily
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
}
