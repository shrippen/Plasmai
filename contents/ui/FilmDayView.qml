import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "../code/filmDays.js" as FilmDays
import "../code/dateTimeFormat.js" as DTF
import "."

/**
 * Shooting-day entry: one Kimai timesheet (begin/end for one calendar day)
 * plus film-specific extras that Kimai has no field for yet (break, catering,
 * day category/type, production-day counter, extra pay, note). Modeled on
 * the Android TimeSheet app's day screen; see kimai-drehzettel-bundle's
 * research/timesheet-app-analyse.md for the reference layout. The extras
 * are stored locally (filmDays.js / shared.json) until that plugin grows an
 * API — see the explanatory label below.
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
    property bool showCreateActions: false

    property var pendingProjectId: null
    property var pendingActivityId: null
    property bool suppressProjectSignal: false
    /** True while loadForDay() sets dayField programmatically (avoids re-triggering dayChosen). */
    property bool suppressDayChosen: false

    readonly property alias projectCombo: pickers.projectCombo
    readonly property alias activityCombo: pickers.activityCombo
    readonly property var selectedDay: DTF.coerceDate(dayField.selectedDate) || new Date()
    readonly property int isoWeekday: KimaiApi.kimaiWeekday(root.selectedDay)

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectChosen(var projectId)
    signal dayStepRequested(int deltaDays)
    signal dayChosen(var date)
    signal saveRequested(var projectId, var activityId, string beginText, string endText, var filmDayFields)
    signal cancelled()
    signal createProjectRequested()
    signal createActivityRequested()

    function closePickers() {
        pickers.closePickers()
    }

    function hasId(value) {
        return value !== null && value !== undefined && value !== ""
    }

    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }

    function stampText(date, timeField) {
        if (!date || isNaN(date.getTime())) {
            return ""
        }
        return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
            + " " + pad2(timeField.hours) + ":" + pad2(timeField.minutes)
    }

    function combineStamp(date, timeField) {
        if (!date || isNaN(date.getTime())) {
            return null
        }
        return new Date(date.getFullYear(), date.getMonth(), date.getDate(),
                        timeField.hours, timeField.minutes, 0, 0)
    }

    readonly property var beginInstant: combineStamp(root.selectedDay, beginTime)
    readonly property var endInstant: combineStamp(root.selectedDay, endTime)
    readonly property bool rangeValid: beginInstant && endInstant && endInstant.getTime() > beginInstant.getTime()
    readonly property int workSeconds: rangeValid
        ? FilmDays.workSecondsFromSpan(beginInstant.getTime(), endInstant.getTime(), breakSpin.value)
        : 0

    readonly property var categoryOptions: [
        { value: FilmDays.DayCategory.AUTO, label: i18n("Auto (from weekday)") },
        { value: FilmDays.DayCategory.WORKDAY, label: i18n("Workday") },
        { value: FilmDays.DayCategory.SATURDAY, label: i18n("Saturday") },
        { value: FilmDays.DayCategory.SUNDAY, label: i18n("Sunday") },
        { value: FilmDays.DayCategory.HOLIDAY, label: i18n("Holiday") }
    ]
    readonly property var dayTypeOptions: [
        { value: FilmDays.DayType.WORKDAY, label: i18n("Shooting day") },
        { value: FilmDays.DayType.TRAVEL, label: i18n("Travel day") }
    ]

    function indexOfValue(options, value) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === value) {
                return i
            }
        }
        return 0
    }

    function weekdayName(isoWeekday) {
        // QLocale.dayName is 1=Monday..7=Sunday, matching KimaiApi.kimaiWeekday.
        return Qt.locale().dayName(isoWeekday, Locale.LongFormat)
    }

    function applyEntryFields(entry) {
        var e = entry || FilmDays.entryDefaults()
        breakSpin.value = Math.max(0, Math.min(360, e.breakMinutes || 0))
        cateringCheck.checked = e.catering === FilmDays.Catering.YES
        categoryCombo.currentIndex = indexOfValue(root.categoryOptions, e.category || FilmDays.DayCategory.AUTO)
        dayTypeCombo.currentIndex = indexOfValue(root.dayTypeOptions, e.dayType || FilmDays.DayType.WORKDAY)
        productionDaySpin.value = e.productionDay || 0
        extraPayField.text = e.extraPayCents ? (e.extraPayCents / 100).toFixed(2) : ""
        noteField.text = e.note || ""
    }

    function currentEntryFields() {
        var extraPay = parseFloat(String(extraPayField.text).replace(",", "."))
        return {
            breakMinutes: breakSpin.value,
            catering: cateringCheck.checked ? FilmDays.Catering.YES : FilmDays.Catering.NO,
            category: root.categoryOptions[categoryCombo.currentIndex].value,
            dayType: root.dayTypeOptions[dayTypeCombo.currentIndex].value,
            productionDay: productionDaySpin.value > 0 ? productionDaySpin.value : null,
            extraPayCents: isNaN(extraPay) ? 0 : Math.round(extraPay * 100),
            note: noteField.text
        }
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
        return fallback
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

    /** Called by root after it loads the day's timesheet (if any) and film-day extras. */
    function loadForDay(date, timesheet, filmEntry) {
        var d = date || new Date()
        suppressDayChosen = true
        dayField.setDate(d)
        suppressDayChosen = false
        applyEntryFields(filmEntry)

        var defaultBegin = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 9, 0, 0, 0)
        var defaultEnd = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 18, 0, 0, 0)
        var begin = parseStampDate(timesheet ? timesheet.begin : null, defaultBegin)
        var end = parseStampDate(timesheet ? timesheet.end : null, defaultEnd)
        beginTime.setTime(begin.getHours(), begin.getMinutes())
        endTime.setTime(end.getHours(), end.getMinutes())

        if (timesheet) {
            pendingActivityId = KimaiApi.activityId(timesheet)
            pendingProjectId = KimaiApi.projectId(timesheet)
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
    }

    onVisibleChanged: {
        if (visible && hasId(pendingProjectId)) {
            Qt.callLater(function() {
                if (root.visible) {
                    root.trySelectPendingProject()
                    root.trySelectPendingActivity()
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
        text: i18n("Break, catering, day type, production-day count, and the note are kept on this device only, until the Drehzettel plugin has an API for them. Begin and end are saved to Kimai like any entry.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.ToolButton {
            Layout.preferredWidth: TouchUi.active ? TouchUi.buttonMinHeight : implicitWidth
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            icon.name: "go-previous"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Previous day")
            Accessible.name: text
            enabled: root.configured && !root.busy
            onClicked: root.dayStepRequested(-1)
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        DateField {
            id: dayField
            Layout.fillWidth: true
            enabled: root.configured && !root.busy
            onDateEdited: {
                if (!root.suppressDayChosen) {
                    root.dayChosen(DTF.coerceDate(dayField.selectedDate))
                }
            }
        }

        PlasmaComponents3.ToolButton {
            Layout.preferredWidth: TouchUi.active ? TouchUi.buttonMinHeight : implicitWidth
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            icon.name: "go-next"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Next day")
            Accessible.name: text
            enabled: root.configured && !root.busy
            onClicked: root.dayStepRequested(1)
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        opacity: 0.65
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: root.weekdayName(root.isoWeekday)
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

    TimeField {
        id: beginTime
        Layout.fillWidth: true
        enabled: root.configured && !root.busy
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("End")
        font.bold: true
        opacity: 0.85
    }

    TimeField {
        id: endTime
        Layout.fillWidth: true
        enabled: root.configured && !root.busy
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Break")
        font.bold: true
        opacity: 0.85
    }

    QQC2.SpinBox {
        id: breakSpin
        Layout.fillWidth: true
        from: 0
        to: 360
        value: 45
        stepSize: 15
        editable: true
        enabled: root.configured && !root.busy
        textFromValue: function(value) { return i18np("%1 minute", "%1 minutes", value) }
        valueFromText: function(text) {
            var n = parseInt(text, 10)
            return isNaN(n) ? 0 : n
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: root.rangeValid ? 0.9 : 0.65
        color: root.rangeValid ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor
        text: root.rangeValid
              ? i18n("Work time: %1", KimaiApi.formatDuration(root.workSeconds))
              : i18n("Work time: invalid range")
    }

    PlasmaComponents3.CheckBox {
        id: cateringCheck
        Layout.fillWidth: true
        enabled: root.configured && !root.busy
        text: i18n("Catering")
        Accessible.name: text
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Day category")
        font.bold: true
        opacity: 0.85
    }

    QQC2.ComboBox {
        id: categoryCombo
        Layout.fillWidth: true
        model: root.categoryOptions
        textRole: "label"
        enabled: root.configured && !root.busy
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Day type")
        font.bold: true
        opacity: 0.85
    }

    QQC2.ComboBox {
        id: dayTypeCombo
        Layout.fillWidth: true
        model: root.dayTypeOptions
        textRole: "label"
        enabled: root.configured && !root.busy
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Production day")
        font.bold: true
        opacity: 0.85
    }

    QQC2.SpinBox {
        id: productionDaySpin
        Layout.fillWidth: true
        from: 0
        to: 999
        editable: true
        enabled: root.configured && !root.busy
        textFromValue: function(value) { return value === 0 ? i18n("Not set") : String(value) }
        valueFromText: function(text) {
            var n = parseInt(text, 10)
            return isNaN(n) ? 0 : n
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Extra pay / expenses")
        font.bold: true
        opacity: 0.85
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: extraPayField
            Layout.fillWidth: true
            enabled: root.configured && !root.busy
            placeholderText: "0.00"
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: RegularExpressionValidator { regularExpression: /[0-9]*[.,]?[0-9]{0,2}/ }
        }

        PlasmaComponents3.Label {
            text: "€"
            opacity: 0.75
        }
    }

    QQC2.TextArea {
        id: noteField
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        enabled: root.configured && !root.busy
        wrapMode: Text.WordWrap
        placeholderText: i18n("Note (optional)")
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
            text: i18n("Save shooting day")
            icon.name: "document-save"
            onClicked: {
                var project = projectCombo.currentItem.value
                var activity = activityCombo.currentItem.value
                root.saveRequested(
                    project.id,
                    activity.id,
                    root.stampText(root.selectedDay, beginTime),
                    root.stampText(root.selectedDay, endTime),
                    root.currentEntryFields())
            }
        }

        PlasmaComponents3.Button {
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Cancel")
            onClicked: root.cancelled()
        }
    }
}
