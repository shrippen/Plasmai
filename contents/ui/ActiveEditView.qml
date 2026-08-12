import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "../code/dateTimeFormat.js" as DTF
import "."

/**
 * Inline editor for the running timesheet: start time, project, and activity.
 * Prefills from the active timesheet; reuses New activity picker models.
 */
ColumnLayout {
    id: root

    width: parent ? parent.width : implicitWidth

    property var timesheet: null
    property int elapsedSeconds: 0
    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activitySectionTitles: ({})
    property bool pickerOpenBelow: true
    property Item pickerViewport: null
    property bool busy: false
    property bool configured: true
    property bool connectionOk: true
    /** Pending ids to select once picker models refresh. */
    property var pendingProjectId: null
    property var pendingActivityId: null
    property bool suppressProjectSignal: false

    readonly property alias projectCombo: pickers.projectCombo
    readonly property alias activityCombo: pickers.activityCombo

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectChosen(var projectId)
    signal saveRequested(var projectId, var activityId, string beginText)
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

    readonly property bool beginValid: {
        var _d = beginDate.selectedDateMs + beginTime.hours * 60 + beginTime.minutes
        var begin = combineStamp(beginDate, beginTime)
        return !!(begin && !isNaN(begin.getTime()) && begin.getTime() <= Date.now() + 60 * 1000)
    }

    function parseBeginDate(ts) {
        if (ts && ts.begin) {
            var raw = String(ts.begin)
            var d = new Date(raw)
            if (isNaN(d.getTime())) {
                d = new Date(raw.replace(" ", "T"))
            }
            if (!isNaN(d.getTime())) {
                return d
            }
        }
        return new Date(Date.now() - Math.max(0, root.elapsedSeconds) * 1000)
    }

    function hasId(value) {
        return value !== null && value !== undefined && value !== ""
    }

    function selectProjectId(projectId) {
        if (!hasId(projectId)) {
            projectCombo.currentIndex = -1
            return false
        }
        for (var i = 0; i < projectCombo.items.length; i++) {
            var item = projectCombo.items[i]
            if (item && item.value && String(item.value.id) === String(projectId)) {
                // Force label refresh even if index was already i
                if (projectCombo.currentIndex === i) {
                    projectCombo.currentIndex = -1
                }
                projectCombo.currentIndex = i
                return true
            }
        }
        projectCombo.currentIndex = -1
        return false
    }

    function trySelectPendingActivity() {
        if (!hasId(pendingActivityId)) {
            return
        }
        for (var i = 0; i < activityCombo.items.length; i++) {
            var item = activityCombo.items[i]
            if (item && item.value && String(item.value.id) === String(pendingActivityId)) {
                if (activityCombo.currentIndex === i) {
                    activityCombo.currentIndex = -1
                }
                activityCombo.currentIndex = i
                pendingActivityId = null
                return
            }
        }
    }

    function trySelectPendingProject() {
        if (!hasId(pendingProjectId)) {
            return
        }
        if (!selectProjectId(pendingProjectId)) {
            return
        }
        var pid = pendingProjectId
        pendingProjectId = null
        if (!suppressProjectSignal) {
            root.projectChosen(pid)
        }
    }

    function loadFromTimesheet(ts) {
        var sheet = ts || root.timesheet
        if (!sheet) {
            return
        }
        var begin = parseBeginDate(sheet)
        beginDate.setDate(begin)
        beginTime.setTime(begin.getHours(), begin.getMinutes())

        pendingActivityId = KimaiApi.activityId(sheet)
        pendingProjectId = KimaiApi.projectId(sheet)
        if (!hasId(pendingProjectId)) {
            pendingProjectId = null
        }
        if (!hasId(pendingActivityId)) {
            pendingActivityId = null
        }

        suppressProjectSignal = false
        if (hasId(pendingProjectId) && selectProjectId(pendingProjectId)) {
            var pid = pendingProjectId
            pendingProjectId = null
            root.projectChosen(pid)
        }
        Qt.callLater(trySelectPendingActivity)
    }

    onTimesheetChanged: {
        if (visible && timesheet) {
            loadFromTimesheet(timesheet)
        }
    }

    onVisibleChanged: {
        if (visible && timesheet) {
            Qt.callLater(function() {
                if (root.visible) {
                    root.loadFromTimesheet(root.timesheet)
                }
            })
        }
    }

    onProjectPickerModelChanged: {
        if (!visible) {
            return
        }
        Qt.callLater(function() {
            trySelectPendingProject()
            trySelectPendingActivity()
        })
    }

    onActivityPickerModelChanged: {
        if (!visible) {
            return
        }
        Qt.callLater(trySelectPendingActivity)
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.8
        text: i18n("Edit start time, project, and activity for the running entry.")
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
            pendingProjectId = null
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
        text: i18n("Start")
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
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.7
        color: root.beginValid ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor
        text: root.beginValid
              ? i18n("Elapsed time updates from the new start.")
              : i18n("Start must be a valid time not in the future.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            enabled: root.configured && !root.busy && root.connectionOk
                     && projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0
                     && root.beginValid
            text: i18n("Save")
            icon.name: "document-save"
            onClicked: {
                var project = projectCombo.currentItem.value
                var activity = activityCombo.currentItem.value
                root.saveRequested(project.id, activity.id, root.stampText(beginDate, beginTime))
            }
        }

        PlasmaComponents3.Button {
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Cancel")
            onClicked: root.cancelled()
        }
    }
}
