import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "../code/dateTimeFormat.js" as DTF
import "."

/**
 * Manual timesheet editor — project/activity pickers plus date/time fields
 * with calendar and time popups, and a live duration readout.
 */
ColumnLayout {
    id: root

    width: parent ? parent.width : implicitWidth

    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activitySectionTitles: ({})
    property bool pickerOpenBelow: true
    property Item pickerViewport: null
    property bool busy: false
    property bool configured: true
    property bool connectionOk: true

    property bool supportsBillableEdit: true
    property bool supportsTags: true
    property bool showCreateActions: false
    property string tagLookupUrl: ""
    property string tagLookupToken: ""
    /** True when editing a stopped Recent entry (same form as Add entry). */
    property bool editingExisting: false
    property var pendingProjectId: null
    property var pendingActivityId: null
    property bool suppressProjectSignal: false

    readonly property alias projectCombo: pickers.projectCombo
    readonly property alias activityCombo: pickers.activityCombo

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectChosen(var projectId)
    signal saveRequested(var projectId, var activityId, string beginText, string endText, string description, bool billable, var tags)
    signal cancelled()
    signal createProjectRequested()
    signal createActivityRequested()

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
        pendingProjectId = null
        pendingActivityId = null
        metaFields.resetDefaults()
    }

    function hasId(value) {
        return value !== null && value !== undefined && value !== ""
    }

    function parseStampDate(raw, fallback) {
        if (raw) {
            var d = new Date(String(raw))
            if (isNaN(d.getTime())) {
                d = new Date(String(raw).replace(" ", "T"))
            }
            if (!isNaN(d.getTime())) {
                return d
            }
        }
        return fallback || new Date()
    }

    function selectProjectId(projectId) {
        if (!hasId(projectId)) {
            projectCombo.currentIndex = -1
            return false
        }
        for (var i = 0; i < projectCombo.items.length; i++) {
            var item = projectCombo.items[i]
            if (item && item.value && String(item.value.id) === String(projectId)) {
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
        if (!ts) {
            return
        }
        var begin = parseStampDate(ts.begin, new Date(Date.now() - 60 * 60 * 1000))
        var end = parseStampDate(ts.end, new Date())
        beginDate.setDate(begin)
        beginTime.setTime(begin.getHours(), begin.getMinutes())
        endDate.setDate(end)
        endTime.setTime(end.getHours(), end.getMinutes())
        descriptionField.text = ts.description || ""

        pendingActivityId = KimaiApi.activityId(ts)
        pendingProjectId = KimaiApi.projectId(ts)
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
        metaFields.loadFromTimesheet(ts)
    }

    Component.onCompleted: resetDefaults()

    onVisibleChanged: {
        if (visible && editingExisting && hasId(pendingProjectId)) {
            Qt.callLater(function() {
                if (root.visible && root.editingExisting) {
                    root.trySelectPendingProject()
                    root.trySelectPendingActivity()
                }
            })
        }
    }

    onProjectPickerModelChanged: {
        if (!visible || !editingExisting) {
            return
        }
        Qt.callLater(function() {
            trySelectPendingProject()
            trySelectPendingActivity()
        })
    }

    onActivityPickerModelChanged: {
        if (!visible || !editingExisting) {
            return
        }
        Qt.callLater(trySelectPendingActivity)
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.8
        text: root.editingExisting
              ? i18n("Change project, activity, range, billable, and tags for this finished entry.")
              : i18n("Create a finished entry with project, activity, and time range.")
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
        showCreateActions: root.showCreateActions
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
        onCreateProjectRequested: root.createProjectRequested()
        onCreateActivityRequested: root.createActivityRequested()
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

    TimesheetMetaFields {
        id: metaFields
        Layout.fillWidth: true
        showBillable: root.supportsBillableEdit
        showTags: root.supportsTags
        tagLookupUrl: root.tagLookupUrl
        tagLookupToken: root.tagLookupToken
        pickerViewport: root.pickerViewport
        enabled: root.configured && !root.busy
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            enabled: root.configured && !root.busy && root.connectionOk
                     && projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0
                     && root.rangeValid
            text: root.editingExisting ? i18n("Save changes") : i18n("Save entry")
            icon.name: "document-save"
            onClicked: {
                var project = projectCombo.currentItem.value
                var activity = activityCombo.currentItem.value
                root.saveRequested(
                    project.id,
                    activity.id,
                    root.stampText(beginDate, beginTime),
                    root.stampText(endDate, endTime),
                    descriptionField.text,
                    metaFields.billable,
                    metaFields.tags)
            }
        }

        PlasmaComponents3.Button {
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Cancel")
            onClicked: root.cancelled()
        }
    }
}
