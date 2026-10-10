import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../code/dateTimeFormat.js" as DTF
import ".."
import "." as Controls

// Date picker of DateField, see Label.qml: a calendar popup under the field.
// openFor(date) shows it, picked(date) reports the day (noon, local time).
QQC2.Popup {
    id: picker

    /** The date shown as selected. */
    property var selected: new Date()
    property int calendarMonth: (new Date()).getMonth()
    property int calendarYear: (new Date()).getFullYear()

    signal picked(var date)

    function openFor(date) {
        picker.selected = date
        picker.calendarMonth = date.getMonth()
        picker.calendarYear = date.getFullYear()
        picker.open()
    }

    // The field sets parent and y; the popup sits at its right edge.
    x: parent ? Math.max(0, parent.width - width) : 0
    width: Kirigami.Units.gridUnit * 14
    padding: Kirigami.Units.smallSpacing
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Controls.ToolButton {
                Layout.preferredWidth: TouchUi.active ? TouchUi.buttonMinHeight : implicitWidth
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                icon.name: "go-previous"
                onClicked: {
                    if (picker.calendarMonth === 0) {
                        picker.calendarMonth = 11
                        picker.calendarYear -= 1
                    } else {
                        picker.calendarMonth -= 1
                    }
                }
            }
            Controls.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                text: Qt.locale().standaloneMonthName(picker.calendarMonth) + " " + picker.calendarYear
            }
            Controls.ToolButton {
                Layout.preferredWidth: TouchUi.active ? TouchUi.buttonMinHeight : implicitWidth
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                icon.name: "go-next"
                onClicked: {
                    if (picker.calendarMonth === 11) {
                        picker.calendarMonth = 0
                        picker.calendarYear += 1
                    } else {
                        picker.calendarMonth += 1
                    }
                }
            }
        }

        QQC2.DayOfWeekRow {
            Layout.fillWidth: true
            locale: Qt.locale()
        }

        QQC2.MonthGrid {
            id: monthGrid
            Layout.fillWidth: true
            month: picker.calendarMonth
            year: picker.calendarYear
            locale: Qt.locale()
            spacing: 2

            delegate: QQC2.ItemDelegate {
                id: dayCell
                required property var model
                implicitWidth: Kirigami.Units.gridUnit * TouchUi.calendarCellGu
                implicitHeight: Kirigami.Units.gridUnit * TouchUi.calendarCellGu
                enabled: model.month === monthGrid.month
                highlighted: {
                    var sel = DTF.coerceDate(picker.selected)
                    return !!sel
                             && model.year === sel.getFullYear()
                             && model.month === sel.getMonth()
                             && model.day === sel.getDate()
                }
                contentItem: Controls.Label {
                    text: model.day
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: model.month === monthGrid.month ? 1 : 0.35
                    font.bold: dayCell.highlighted
                }
                onClicked: {
                    picker.picked(new Date(model.year, model.month, model.day, 12, 0, 0, 0))
                    picker.close()
                }
            }
        }
    }
}
