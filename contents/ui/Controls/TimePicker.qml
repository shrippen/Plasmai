import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../code/dateTimeFormat.js" as DTF
import ".."
import "../Kante"
import "." as Controls

// Time picker of TimeField, see Label.qml: hour and minute tumblers under the field.
// openFor(hours, minutes) shows it, picked(hours, minutes) reports the choice.
QQC2.Popup {
    id: picker

    signal picked(int hours, int minutes)

    function openFor(hours, minutes) {
        hourTumbler.currentIndex = hours
        minuteTumbler.currentIndex = minutes
        picker.open()
    }

    // The field sets parent and y; the popup sits at its right edge.
    x: parent ? Math.max(0, parent.width - width) : 0
    width: Kirigami.Units.gridUnit * (TouchUi.active ? 12 : 10)
    padding: Kirigami.Units.smallSpacing
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.75
            font.pointSize: KanteStyle.smallFont.pointSize
            text: i18n("Hours : Minutes")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            QQC2.Tumbler {
                id: hourTumbler
                Layout.preferredWidth: Kirigami.Units.gridUnit * TouchUi.tumblerWidthGu
                Layout.preferredHeight: Kirigami.Units.gridUnit * TouchUi.tumblerHeightGu
                model: 24
                visibleItemCount: 5
                delegate: Controls.Label {
                    text: DTF.pad2(modelData)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: Math.abs(QQC2.Tumbler.displacement) < 0.5 ? 1 : 0.4
                    font.bold: Math.abs(QQC2.Tumbler.displacement) < 0.5
                }
            }

            Controls.Label {
                text: ":"
                font.bold: true
                font.pointSize: KanteStyle.defaultFont.pointSize + 2
            }

            QQC2.Tumbler {
                id: minuteTumbler
                Layout.preferredWidth: Kirigami.Units.gridUnit * TouchUi.tumblerWidthGu
                Layout.preferredHeight: Kirigami.Units.gridUnit * TouchUi.tumblerHeightGu
                model: 60
                visibleItemCount: 5
                delegate: Controls.Label {
                    text: DTF.pad2(modelData)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: Math.abs(QQC2.Tumbler.displacement) < 0.5 ? 1 : 0.4
                    font.bold: Math.abs(QQC2.Tumbler.displacement) < 0.5
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Controls.Button {
                Layout.fillWidth: true
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                text: i18n("Cancel")
                onClicked: picker.close()
            }
            Controls.Button {
                Layout.fillWidth: true
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                text: i18n("Select")
                icon.name: "dialog-ok-apply"
                onClicked: {
                    picker.picked(hourTumbler.currentIndex, minuteTumbler.currentIndex)
                    picker.close()
                }
            }
        }
    }
}
