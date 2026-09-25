import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/filmDays.js" as FilmDays
import "../../contents/code/dateTimeFormat.js" as DTF
import "."

/**
 * Shooting-day entry: one Kimai timesheet (begin/end for one calendar day)
 * plus film-specific extras (break, catering, day category/type, production
 * shooting day, consecutive day, extra pay, note). Modeled on the Android
 * TimeSheet app's day screen; see kimai-drehzettel-bundle's
 * research/timesheet-app-analyse.md for the reference layout.
 *
 * Where the extras live is decided by the caller (filmDaySync.js) and passed
 * in as `mode`: on the Drehzettel plugin's server ("server"), in shared.json
 * when the plugin is not installed ("local"), or not at all when the project
 * has no engagement / the user lacks the permission (extras hidden, only
 * begin and end are saved). The earnings figure comes from the plugin's day
 * summary; it is never calculated client-side.
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

    /** filmDaySync.js Mode: local | server | noProject | noEngagement | noPermission | offline */
    property string mode: "local"
    /** Ruleset default break from the server (-1 = unknown); shown as the "Default" break option. */
    property int defaultBreakMinutes: -1
    property string rulesetName: ""
    /** ISO code of the project's customer currency ("" = unknown). */
    property string currency: ""
    /** Day pay from the plugin's day summary in cents, -1 = none. */
    property real earningsCents: -1
    /** Server mode without the plugin's extraPay feature: extra pay stays on this device. */
    property bool extraPayLocalOnly: false
    /** Changes of this day are queued and not on the server yet. */
    property bool pendingSync: false
    /** Local film days that could be copied to the server (P6), 0 = no offer. */
    property int migrationCount: 0
    property bool migrationBusy: false
    property string migrationReport: ""

    readonly property bool serverMode: mode === "server" || mode === "offline"
    readonly property bool extrasVisible: mode === "local" || mode === "server" || mode === "offline"
    readonly property bool extrasEnabled: configured && !busy && (mode === "local" || mode === "server")
    readonly property int fallbackBreakMinutes: defaultBreakMinutes >= 0 ? defaultBreakMinutes : FilmDays.DEFAULT_BREAK_MINUTES
    /** Break that applies: the chosen minutes, or the ruleset default when "Default" is picked. */
    readonly property int effectiveBreakMinutes: !extrasVisible ? 0
        : (breakSpin.value < 0 ? fallbackBreakMinutes : breakSpin.value)

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
    /** User picked a project: the day's entry and extras belong to it, reload them. */
    signal projectPicked(var projectId)
    signal dayStepRequested(int deltaDays)
    signal dayChosen(var date)
    signal saveRequested(var projectId, var activityId, string beginText, string endText, var filmDayFields)
    signal cancelled()
    signal createProjectRequested()
    signal createActivityRequested()
    signal migrationRequested()
    signal migrationDismissed()

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
        ? FilmDays.workSecondsFromSpan(beginInstant.getTime(), endInstant.getTime(), root.effectiveBreakMinutes)
        : 0

    function modeHint() {
        if (mode === "local") {
            return i18n("The Drehzettel plugin is not installed on this Kimai server, so break, catering, day type, shooting day, extra pay, and the note are kept on this device only. Begin and end are saved to Kimai like any entry.")
        }
        if (mode === "noEngagement") {
            return i18n("No active engagement for this project and day. Only begin and end are saved.")
        }
        if (mode === "noPermission") {
            return i18n("You lack the Drehzettel permission on this Kimai server. Only begin and end are saved.")
        }
        if (mode === "noProject") {
            return i18n("Pick a project to load its film day.")
        }
        if (mode === "offline") {
            return i18n("The Drehzettel plugin cannot be reached. Showing the last known values; the film day extras can be edited again once the server answers.")
        }
        if (pendingSync) {
            return i18n("Some changes of this day are not on the server yet. They are sent again automatically.")
        }
        return ""
    }

    function formatMoney(cents) {
        var text = Number(cents / 100).toLocaleString(Qt.locale(), "f", 2)
        return root.currency ? text + " " + root.currency : text
    }

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

    function applyEntryFields(entry) {
        var e = entry || FilmDays.entryDefaults()
        if (e.breakMinutes === null || e.breakMinutes === undefined) {
            // null = ruleset default (server mode); locally there is no default to fall back to.
            breakSpin.value = root.serverMode ? -1 : FilmDays.DEFAULT_BREAK_MINUTES
        } else {
            breakSpin.value = Math.max(0, Math.min(FilmDays.BREAK_MAX_MINUTES, e.breakMinutes))
        }
        breakSpin.previousValue = breakSpin.value
        cateringSwitch.checked = e.catering === FilmDays.Catering.YES
        categorySlider.value = indexOfValue(root.categoryOptions, e.category || FilmDays.DayCategory.AUTO)
        dayTypeSlider.value = indexOfValue(root.dayTypeOptions, e.dayType || FilmDays.DayType.WORKDAY)
        productionDaySpin.value = e.productionDay || 0
        consecutiveDaySpin.value = e.consecutiveDay || 0
        extraPayField.text = e.extraPayCents ? (e.extraPayCents / 100).toFixed(2) : ""
        noteField.text = String(e.note || "").substring(0, FilmDays.NOTE_MAX_LENGTH)
    }

    function currentEntryFields() {
        var extraPay = parseFloat(String(extraPayField.text).replace(",", "."))
        return {
            breakMinutes: breakSpin.value < 0 ? null : breakSpin.value,
            catering: cateringSwitch.checked ? FilmDays.Catering.YES : FilmDays.Catering.NO,
            category: root.categoryOptions[Math.round(categorySlider.value)].value,
            dayType: root.dayTypeOptions[Math.round(dayTypeSlider.value)].value,
            productionDay: productionDaySpin.value > 0 ? productionDaySpin.value : null,
            consecutiveDay: consecutiveDaySpin.value > 0 ? consecutiveDaySpin.value : null,
            extraPayCents: isNaN(extraPay) ? 0 : Math.max(0, Math.min(FilmDays.EXTRA_PAY_MAX_CENTS, Math.round(extraPay * 100))),
            note: String(noteField.text).trim()
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

    /**
     * Fill the view from a FilmDaySync.loadDay() result. `currency` is the
     * fallback when the day summary has none (customer currency from the catalog).
     */
    function applyLoadedDay(date, timesheet, day, currency, migrationCount) {
        var summary = day.summary || null
        root.mode = day.mode
        root.defaultBreakMinutes = day.defaultBreakMinutes
        root.rulesetName = day.rulesetName || ""
        root.currency = (summary && summary.currency) ? String(summary.currency) : (currency || "")
        root.earningsCents = (summary && typeof summary.payCents === "number") ? summary.payCents : -1
        root.extraPayLocalOnly = !!day.server && !Object.prototype.hasOwnProperty.call(day.server, "extraPayCents")
        root.pendingSync = !!day.pending
        root.migrationCount = migrationCount || 0
        root.loadForDay(date, timesheet, day.fields)
    }

    /** Summary line for a FilmDaySync.migrate() report. */
    function showMigrationReport(report) {
        var lines = [i18np("%1 film day copied to the server.", "%1 film days copied to the server.", report.pushed)]
        if (report.same > 0) {
            lines.push(i18np("%1 was already there.", "%1 were already there.", report.same))
        }
        if (report.conflicts.length > 0) {
            var dates = []
            for (var i = 0; i < report.conflicts.length; i++) {
                dates.push(report.conflicts[i].date)
            }
            lines.push(i18np("%1 day has other values on the server; the server values were kept and the local copy is unchanged: %2",
                             "%1 days have other values on the server; the server values were kept and the local copies are unchanged: %2",
                             report.conflicts.length, dates.join(", ")))
        }
        if (report.noEngagement > 0) {
            lines.push(i18np("%1 day has no engagement and stays on this device.",
                             "%1 days have no engagement and stay on this device.", report.noEngagement))
        }
        if (report.rejected > 0) {
            lines.push(i18np("%1 day was rejected by the server.", "%1 days were rejected by the server.", report.rejected))
        }
        if (report.stopped) {
            lines.push(i18n("Stopped early because the server could not be reached; the rest is copied next time."))
        }
        root.migrationReport = lines.join(" ")
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

    /** Hidden — keeps the working date-segment/calendar-popup logic, driven by the big header below. */
    DateField {
        id: dayField
        visible: false
        height: 0
        enabled: root.configured && !root.busy
        onDateEdited: {
            if (!root.suppressDayChosen) {
                root.dayChosen(DTF.coerceDate(dayField.selectedDate))
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: root.serverMode && root.rulesetName.length > 0
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        opacity: 0.85
        text: i18n("Film day · %1", root.rulesetName)
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: text.length > 0
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.8
        color: root.mode === "offline" || root.pendingSync ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
        text: root.modeHint()
    }

    /** One-time offer to copy local film days to the plugin (server wins on conflicts). */
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.mode === "server" && (root.migrationCount > 0 || root.migrationReport.length > 0)
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: root.migrationReport.length > 0 ? root.migrationReport
                : i18np("%1 film day saved on this device can be copied to the Drehzettel plugin. Days that already have other values on the server keep the server values.",
                        "%1 film days saved on this device can be copied to the Drehzettel plugin. Days that already have other values on the server keep the server values.",
                        root.migrationCount)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.migrationCount > 0
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Copy to server")
                icon.name: "cloud-upload"
                enabled: root.configured && !root.busy && !root.migrationBusy
                onClicked: root.migrationRequested()
            }
            QQC2.Button {
                flat: true
                text: i18n("Not now")
                enabled: !root.migrationBusy
                onClicked: root.migrationDismissed()
            }
            QQC2.BusyIndicator {
                visible: root.migrationBusy
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.ToolButton {
            icon.name: "go-previous"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Previous day")
            Accessible.name: text
            enabled: root.configured && !root.busy
            onClicked: root.dayStepRequested(-1)
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered && !TouchUi.active
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        QQC2.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            color: Kirigami.Theme.highlightColor
            wrapMode: Text.WordWrap
            text: root.selectedDay.toLocaleDateString(Qt.locale(), Locale.LongFormat)

            MouseArea {
                anchors.fill: parent
                enabled: root.configured && !root.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: dayField.openPicker()
            }
        }

        QQC2.ToolButton {
            icon.name: "go-next"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Next day")
            Accessible.name: text
            enabled: root.configured && !root.busy
            onClicked: root.dayStepRequested(1)
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered && !TouchUi.active
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    ProjectActivityPickers {
        id: pickers
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
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
            root.projectPicked(pickers.projectPickerModel[index].value.id)
        }
        onCreateProjectRequested: root.createProjectRequested()
        onCreateActivityRequested: root.createActivityRequested()
    }

    /** Three-column Begin / Break / End header, modeled on the TimeSheet app's day screen. */
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.75
                text: i18n("Begin")
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                color: Kirigami.Theme.highlightColor
                text: DTF.formatLocaleTime(beginTime.hours, beginTime.minutes)
            }
            TimeField {
                id: beginTime
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                enabled: root.configured && !root.busy
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.extrasVisible
            spacing: Kirigami.Units.smallSpacing / 2

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.75
                text: i18n("Break")
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                color: Kirigami.Theme.highlightColor
                text: root.pad2(Math.floor(root.effectiveBreakMinutes / 60)) + ":" + root.pad2(root.effectiveBreakMinutes % 60)
            }
            QQC2.SpinBox {
                id: breakSpin
                Layout.fillWidth: true
                // -1 = "Default": the ruleset's break (server mode only).
                from: root.serverMode ? -1 : 0
                to: FilmDays.BREAK_MAX_MINUTES
                value: 45
                stepSize: 15
                editable: true
                enabled: root.extrasEnabled
                textFromValue: function(value) {
                    return value < 0 ? i18n("Default (%1 min)", root.fallbackBreakMinutes)
                                     : i18np("%1 minute", "%1 minutes", value)
                }
                valueFromText: function(text) {
                    var n = parseInt(text, 10)
                    return isNaN(n) ? (root.serverMode ? -1 : 0) : n
                }
                property int previousValue: 45
                onValueModified: {
                    // Stepping up from "Default" (-1) lands on 15, not 14.
                    if (previousValue < 0 && value === 14) {
                        value = 15
                    }
                    previousValue = value
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.75
                text: i18n("End")
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                color: Kirigami.Theme.highlightColor
                text: DTF.formatLocaleTime(endTime.hours, endTime.minutes)
            }
            TimeField {
                id: endTime
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                enabled: root.configured && !root.busy
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: root.rangeValid ? 0.9 : 0.65
        color: root.rangeValid ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor
        text: root.rangeValid
              ? i18n("Work time: %1", KimaiApi.formatDuration(root.workSeconds))
              : i18n("Work time: invalid range")
    }

    /** Day category / catering / day type, as snapping sliders and a switch (TimeSheet-app style). */
    RowLayout {
        Layout.fillWidth: true
        visible: root.extrasVisible
        Layout.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: i18n("Day category")
            }
            QQC2.Slider {
                id: categorySlider
                Layout.fillWidth: true
                from: 0
                to: root.categoryOptions.length - 1
                stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                enabled: root.extrasEnabled
                QQC2.ToolTip.text: root.categoryOptions[Math.round(categorySlider.value)].label
                QQC2.ToolTip.visible: pressed
            }
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18n("Catering")
            }
            QQC2.Switch {
                id: cateringSwitch
                Layout.alignment: Qt.AlignHCenter
                enabled: root.extrasEnabled
                Accessible.name: i18n("Catering")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: i18n("Day type")
            }
            QQC2.Slider {
                id: dayTypeSlider
                Layout.fillWidth: true
                from: 0
                to: root.dayTypeOptions.length - 1
                stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                enabled: root.extrasEnabled
                QQC2.ToolTip.text: root.dayTypeOptions[Math.round(dayTypeSlider.value)].label
                QQC2.ToolTip.visible: pressed
            }
        }
    }

    /** Production shooting day ("Drehtag 37", informational) and the consecutive-day override. */
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.extrasVisible
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Production shooting day")
                elide: Text.ElideRight
                font.bold: true
                opacity: 0.85
            }
            QQC2.SpinBox {
                id: productionDaySpin
                Layout.fillWidth: true
                from: 0
                to: FilmDays.DAY_NUMBER_MAX
                editable: true
                enabled: root.extrasEnabled
                Accessible.name: i18n("Production shooting day")
                textFromValue: function(value) { return value === 0 ? i18n("Not set") : String(value) }
                valueFromText: function(text) {
                    var n = parseInt(text, 10)
                    return isNaN(n) ? 0 : n
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: root.serverMode
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Consecutive day (empty = automatic)")
                elide: Text.ElideRight
                font.bold: true
                opacity: 0.85
            }
            QQC2.SpinBox {
                id: consecutiveDaySpin
                Layout.fillWidth: true
                from: 0
                to: FilmDays.DAY_NUMBER_MAX
                editable: true
                enabled: root.extrasEnabled
                Accessible.name: i18n("Consecutive day (empty = automatic)")
                textFromValue: function(value) { return value === 0 ? i18n("Automatic") : String(value) }
                valueFromText: function(text) {
                    var n = parseInt(text, 10)
                    return isNaN(n) ? 0 : n
                }
            }
        }
    }

    /** Extra pay (editable) next to the day's pay from the plugin's day summary. */
    RowLayout {
        Layout.fillWidth: true
        visible: root.extrasVisible
        Layout.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                Layout.fillWidth: true
                text: root.extraPayLocalOnly ? i18n("Extra pay / expenses (this device only)") : i18n("Extra pay / expenses")
                elide: Text.ElideRight
                font.bold: true
                opacity: 0.85
            }
            QQC2.TextField {
                id: extraPayField
                Layout.fillWidth: true
                enabled: root.extrasEnabled
                placeholderText: root.currency ? "0.00 " + root.currency : "0.00"
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegularExpressionValidator { regularExpression: /[0-9]*[.,]?[0-9]{0,2}/ }
                background: Rectangle {
                    color: "transparent"
                    border.width: 0
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: extraPayField.activeFocus ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            QQC2.Label {
                text: i18n("Earnings (non-binding)")
                font.bold: true
                opacity: 0.85
            }
            QQC2.Label {
                Layout.fillWidth: true
                opacity: root.earningsCents >= 0 ? 0.9 : 0.55
                text: root.earningsCents >= 0 ? root.formatMoney(root.earningsCents) : "—"
                QQC2.ToolTip.text: root.serverMode
                    ? i18n("Day pay from the Drehzettel plugin (as saved on the server, without weekly overtime)")
                    : i18n("Needs the Drehzettel plugin on the Kimai server")
                QQC2.ToolTip.visible: earningsHover.hovered
                HoverHandler { id: earningsHover }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: root.extrasVisible

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Note")
            font.bold: true
            opacity: 0.85
        }
        QQC2.Label {
            visible: noteField.length > FilmDays.NOTE_MAX_LENGTH - 100
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: i18n("%1/%2", noteField.length, FilmDays.NOTE_MAX_LENGTH)
        }
    }

    QQC2.TextArea {
        id: noteField
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        visible: root.extrasVisible
        enabled: root.extrasEnabled
        wrapMode: Text.WordWrap
        placeholderText: i18n("Note (optional)")
        // TextArea has no maximumLength; the plugin rejects more than 500 characters.
        onTextChanged: {
            if (length > FilmDays.NOTE_MAX_LENGTH) {
                var pos = cursorPosition
                text = text.substring(0, FilmDays.NOTE_MAX_LENGTH)
                cursorPosition = Math.min(pos, length)
            }
        }
        background: Rectangle {
            color: "transparent"
            border.width: 0
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: noteField.activeFocus ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
            }
        }
    }

    QQC2.Button {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight * 1.3
        highlighted: true
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

    QQC2.Button {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
        flat: true
        text: i18n("Cancel")
        onClicked: root.cancelled()
    }
}
