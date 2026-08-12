import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "../code/dateTimeFormat.js" as DTF

/**
 * Manual timesheet editor — project/activity pickers plus date/time fields
 * with calendar and time popups, and a live duration readout.
 */
ColumnLayout {
    id: root

    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activitySectionTitles: ({})
    property bool pickerOpenBelow: true
    property Item pickerViewport: null
    property bool busy: false
    property bool configured: true
    property bool connectionOk: true

    readonly property alias projectCombo: pickers.projectCombo
    readonly property alias activityCombo: pickers.activityCombo

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectChosen(var projectId)
    signal saveRequested(var projectId, var activityId, string beginText, string endText, string description)
    signal cancelled()

    function closePickers() {
        pickers.closePickers()
    }

    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }

    function combineStamp(dateField, timeField) {
        var d = DTF.coerceDate(dateField.selectedDate)
        if (!d) {
            d = dateField.parseDate(dateField.text)
        }
        if (!d) {
            return null
        }
        // hours/minutes are kept in sync by TimeField.setTime / digit entry
        return new Date(d.getFullYear(), d.getMonth(), d.getDate(),
                        timeField.hours, timeField.minutes, 0, 0)
    }

    function stampText(dateField, timeField) {
        var d = combineStamp(dateField, timeField)
        if (!d || isNaN(d.getTime())) {
            return ""
        }
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
            + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
    }

    readonly property int durationSeconds: {
        // Depend on structured values (not String(date), which is locale text)
        var _b = beginDate.selectedDateMs + beginTime.hours * 60 + beginTime.minutes
        var _e = endDate.selectedDateMs + endTime.hours * 60 + endTime.minutes
        var begin = combineStamp(beginDate, beginTime)
        var end = combineStamp(endDate, endTime)
        if (!begin || !end || isNaN(begin.getTime()) || isNaN(end.getTime())) {
            return -1
        }
        var secs = Math.floor((end.getTime() - begin.getTime()) / 1000)
        return secs > 0 ? secs : -1
    }

    readonly property bool rangeValid: durationSeconds > 0

    function resetDefaults() {
        var end = new Date()
        var begin = new Date(end.getTime() - 60 * 60 * 1000)
        beginDate.setDate(begin)
        beginTime.setTime(begin.getHours(), begin.getMinutes())
        endDate.setDate(end)
        endTime.setTime(end.getHours(), end.getMinutes())
        descriptionField.text = ""
        projectCombo.currentIndex = -1
        activityCombo.currentIndex = -1
    }

    Component.onCompleted: resetDefaults()

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.8
        text: i18n("Create a finished entry with project, activity, and time range.")
    }

    ProjectActivityPickers {
        id: pickers
        Layout.fillWidth: true
        projectPickerModel: root.projectPickerModel
        activityPickerModel: root.activityPickerModel
        activitySectionTitles: root.activitySectionTitles
        pickerOpenBelow: root.pickerOpenBelow
        pickerViewport: root.pickerViewport
        projectEnabled: root.configured && !root.busy && root.connectionOk
        activityEnabled: root.configured && !root.busy && root.connectionOk
        onAboutToOpenPicker: function(projectField, activityField) {
            root.aboutToOpenPicker(projectField, activityField)
        }
        onProjectActivated: function(index) {
            if (index < 0 || index >= pickers.projectPickerModel.length) {
                root.projectChosen(null)
                return
            }
            root.projectChosen(pickers.projectPickerModel[index].value.id)
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: i18n("Begin")
        font.bold: true
        opacity: 0.85
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        DateField {
            id: beginDate
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: root.configured && !root.busy
        }
        TimeField {
            id: beginTime
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: root.configured && !root.busy
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("End")
        font.bold: true
        opacity: 0.85
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        DateField {
            id: endDate
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: root.configured && !root.busy
        }
        TimeField {
            id: endTime
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            enabled: root.configured && !root.busy
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: root.rangeValid ? 0.9 : 0.65
        color: root.rangeValid ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor
        text: {
            if (root.durationSeconds > 0) {
                return i18n("Duration: %1", KimaiApi.formatDuration(root.durationSeconds))
            }
            if (beginDate.text.length === 0 && beginTime.text.length === 0
                && endDate.text.length === 0 && endTime.text.length === 0) {
                return i18n("Duration: —")
            }
            return i18n("Duration: invalid range")
        }
    }

    QQC2.TextField {
        id: descriptionField
        Layout.fillWidth: true
        enabled: root.configured && !root.busy
        placeholderText: i18n("Description (optional)")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            enabled: root.configured && !root.busy && root.connectionOk
                     && projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0
                     && root.rangeValid
            text: i18n("Save entry")
            icon.name: "document-save"
            onClicked: {
                var project = projectCombo.currentItem.value
                var activity = activityCombo.currentItem.value
                root.saveRequested(
                    project.id,
                    activity.id,
                    root.stampText(beginDate, beginTime),
                    root.stampText(endDate, endTime),
                    descriptionField.text)
            }
        }

        PlasmaComponents3.Button {
            text: i18n("Cancel")
            onClicked: root.cancelled()
        }
    }
}
