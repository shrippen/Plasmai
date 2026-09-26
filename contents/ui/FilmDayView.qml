import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "../code/filmDays.js" as FilmDays
import "../code/dateTimeFormat.js" as DTF
import "."
import "Kante"
import "KantePlasma"

/**
 * Shooting day: an alternative to the timer page for a film day. The day's
 * engagement (at most one per day) names project and role; the screen has
 * four states (`phase`, FilmDays.phaseOf):
 *   before   Start the timer on the film activity (the timer of the main
 *            page), or enter times instead
 *   running  the running entry: begin (editable), elapsed time, Stop
 *   done     begin – end of the day's entry, saved as soon as they change
 *   manual   a past day without an entry: begin, end and Save
 * plus the film-specific extras (break, catering, day category/type,
 * surcharge day from "running" on, extra pay, note), saved directly. The
 * production shooting day is counted from the engagement's entries, never
 * typed.
 *
 * The extras live only in the Drehzettel plugin on the server; the caller
 * (filmDaySync.js) passes the state as `mode`. Only "server" shows them.
 * Without the plugin, without an engagement or permission, or while the
 * server cannot be reached, only begin and end are saved. The earnings
 * figure comes from the plugin's day summary; it is never calculated
 * client-side.
 */
ColumnLayout {
    id: root

    /** Duration label: h:mm in Kante (mono figures), "1h 5m" otherwise. */
    function durationText(seconds) {
        return KanteStyle.active ? DTF.hoursMinutes(seconds) : KimaiApi.formatDurationShort(seconds)
    }

    width: parent ? parent.width : implicitWidth

    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activitySectionTitles: ({})
    property bool pickerOpenBelow: true
    property Item pickerViewport: null
    property bool busy: false
    property bool configured: true
    /** The host can log trips (Anfahrten plugin); a finished travel day then offers one. */
    property bool tripsAvailable: false
    /** Labels of the day grid wrap, so the fields keep room on a phone. */
    readonly property real formLabelWidth: Math.max(Kirigami.Units.gridUnit * 6.5, width * 0.28)
    property bool connectionOk: true
    property bool showCreateActions: false

    /** filmDaySync.js Mode: noPlugin | server | noProject | noEngagement | noPermission | offline */
    property string mode: "noPlugin"
    /** Ruleset default break from the server (-1 = unknown); shown as the "Default" break option. */
    property int defaultBreakMinutes: -1
    property string rulesetName: ""
    /** ISO code of the project's customer currency ("" = unknown). */
    property string currency: ""
    /** Day pay from the plugin's day summary in cents, -1 = none. */
    property real earningsCents: -1
    /** False for plugins without the extraPay feature: the field is hidden. */
    property bool extraPayAvailable: true

    /** Screen state (FilmDays.phaseOf): before | running | done | manual. */
    property string phase: "before"
    /** The shown day is today (Start is offered only then). */
    property bool isToday: true
    /** "Enter times instead" on the Start screen. */
    property bool manualRequested: false
    readonly property string shownPhase: phase === "before" && manualRequested ? "manual" : phase
    /** The day's engagement in use (D1 entry, or null) and all of the day's engagements. */
    property var engagement: null
    property var engagements: []
    /** Production shooting day (the engagement's shooting days so far), 0 = unknown. */
    property int productionDayNumber: 0
    /** Engagement card: choose another engagement or project / activity. */
    property bool chooserOpen: false
    /** Running timer: seconds so far (from the main page's timer). */
    property int elapsedSeconds: 0
    /** Entries of other activities that day (travel …), for information only: [{ label, timeText }]. */
    property var otherActivities: []
    /** True while the view fills the extras (their change handlers must not save). */
    property bool fillingExtras: false
    readonly property bool hasFilmActivity: projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0

    /**
     * B3: further stopped entries of the picked project on this day besides
     * the one shown. Saving updates only the shown entry unless the user
     * merges them (mergeOthers: the caller deletes these after the save).
     */
    property var otherEntries: []
    readonly property var otherSpan: FilmDays.daySpan(otherEntries)
    readonly property bool mergeOthers: otherEntries.length > 0 && mergeable && mergeCheck.checked

    readonly property bool serverMode: mode === "server"
    readonly property bool extrasVisible: serverMode
    readonly property bool extrasEnabled: configured && !busy && serverMode
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
    /** Start the main page's timer on the film activity (begin now). */
    signal startRequested(var projectId, var activityId, string projectLabel, string activityLabel)
    signal stopRequested()
    /** Begin of the running entry changed ("yyyy-MM-dd hh:mm"). */
    signal runningBeginEdited(string beginText)
    /** Begin / end of the day's entry changed (done): save them now. */
    signal timesEdited(string beginText, string endText)
    /** Extras changed (before, running, done): save them now. */
    signal extrasEdited(var filmDayFields)
    /** Engagement chooser: use this engagement's project. */
    signal engagementPicked(var projectId)
    signal tripRequested()
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
    /** Merging needs every other entry inside the selected calendar day (the view edits times of one day). */
    readonly property bool mergeable: {
        if (otherEntries.length === 0 || isNaN(otherSpan.beginMs) || isNaN(otherSpan.endMs)) {
            return false
        }
        var b = new Date(otherSpan.beginMs)
        var e = new Date(otherSpan.endMs)
        var d = root.selectedDay
        function sameDay(x) {
            return x.getFullYear() === d.getFullYear() && x.getMonth() === d.getMonth() && x.getDate() === d.getDate()
        }
        return sameDay(b) && sameDay(e)
    }

    function otherEntryIds() {
        var ids = []
        for (var i = 0; i < otherEntries.length; i++) {
            if (hasId(otherEntries[i].id)) {
                ids.push(otherEntries[i].id)
            }
        }
        return ids
    }

    /** Stretch begin/end over the shown entry and all other entries of the day. */
    function applyMergedSpan() {
        if (!mergeable) {
            return
        }
        var b = otherSpan.beginMs
        var e = otherSpan.endMs
        if (beginInstant && beginInstant.getTime() < b) {
            b = beginInstant.getTime()
        }
        if (endInstant && endInstant.getTime() > e) {
            e = endInstant.getTime()
        }
        var bd = new Date(b)
        var ed = new Date(e)
        beginTime.setTime(bd.getHours(), bd.getMinutes())
        endTime.setTime(ed.getHours(), ed.getMinutes())
    }
    readonly property int workSeconds: rangeValid
        ? FilmDays.workSecondsFromSpan(beginInstant.getTime(), endInstant.getTime(), root.effectiveBreakMinutes)
        : 0

    function modeHint() {
        if (mode === "noPlugin") {
            return i18n("The Drehzettel plugin is not installed on this Kimai server. Only begin and end are saved.")
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
            return i18n("The Drehzettel plugin cannot be reached. Only begin and end can be saved right now.")
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

    /** Production shooting day as loaded from the server (not edited here). */
    property var serverProductionDay: null

    /** A user change of an extra: save after a short pause (direct save). */
    function extrasTouched() {
        if (!root.fillingExtras && root.shownPhase !== "manual") {
            extrasSaveTimer.restart()
        }
    }

    Timer {
        id: extrasSaveTimer
        interval: 800
        onTriggered: root.extrasEdited(root.currentEntryFields())
    }

    /** A user change of begin / end of a stopped entry: save after a short pause. */
    function timesTouched() {
        if (root.shownPhase === "done" && root.rangeValid) {
            timesSaveTimer.restart()
        }
    }

    Timer {
        id: timesSaveTimer
        interval: 800
        onTriggered: root.timesEdited(root.stampText(root.selectedDay, beginTime), root.stampText(root.selectedDay, endTime))
    }

    function applyEntryFields(entry) {
        root.fillingExtras = true
        var e = entry || FilmDays.entryDefaults()
        if (e.breakMinutes === null || e.breakMinutes === undefined) {
            // null = ruleset default (server mode); locally there is no default to fall back to.
            breakSpin.value = root.serverMode ? -1 : FilmDays.DEFAULT_BREAK_MINUTES
        } else {
            breakSpin.value = Math.max(0, Math.min(FilmDays.BREAK_MAX_MINUTES, e.breakMinutes))
        }
        breakSpin.previousValue = breakSpin.value
        cateringSwitch.checked = e.catering === FilmDays.Catering.YES
        categoryCombo.currentIndex = indexOfValue(root.categoryOptions, e.category || FilmDays.DayCategory.AUTO)
        dayTypeCombo.currentIndex = indexOfValue(root.dayTypeOptions, e.dayType || FilmDays.DayType.WORKDAY)
        // Counted from the engagement's entries, never typed: sent back unchanged.
        root.serverProductionDay = e.productionDay || null
        surchargeDaySpin.value = e.surchargeDay || 0
        extraPayField.text = e.extraPayCents ? (e.extraPayCents / 100).toFixed(2) : ""
        noteField.text = String(e.note || "").substring(0, FilmDays.NOTE_MAX_LENGTH)
        root.fillingExtras = false
    }

    function currentEntryFields() {
        var extraPay = parseFloat(String(extraPayField.text).replace(",", "."))
        return {
            breakMinutes: breakSpin.value < 0 ? null : breakSpin.value,
            catering: cateringSwitch.checked ? FilmDays.Catering.YES : FilmDays.Catering.NO,
            category: root.categoryOptions[Math.max(0, categoryCombo.currentIndex)].value,
            dayType: root.dayTypeOptions[Math.max(0, dayTypeCombo.currentIndex)].value,
            productionDay: root.serverProductionDay,
            surchargeDay: surchargeDaySpin.value > 0 ? surchargeDaySpin.value : null,
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
    function applyLoadedDay(date, timesheet, day, currency, otherEntries, projectId, info) {
        var i = info || {}
        root.phase = i.phase || "before"
        root.isToday = i.isToday !== false
        root.manualRequested = false
        root.chooserOpen = false
        root.engagement = i.engagement || null
        root.engagements = i.engagements || []
        root.productionDayNumber = i.productionDay || 0
        root.otherActivities = i.otherActivities || []
        var summary = day.summary || null
        root.mode = day.mode
        root.defaultBreakMinutes = day.defaultBreakMinutes
        root.rulesetName = day.rulesetName || ""
        root.currency = (summary && summary.currency) ? String(summary.currency) : (currency || "")
        root.earningsCents = (summary && typeof summary.payCents === "number") ? summary.payCents : -1
        root.extraPayAvailable = !!day.server && Object.prototype.hasOwnProperty.call(day.server, "extraPayCents")
        root.otherEntries = otherEntries || []
        mergeCheck.checked = false
        root.loadForDay(date, timesheet, day.fields, projectId, i.activityId)
    }

    /** Called by root after it loads the day's timesheet (if any) and film-day extras. */
    function loadForDay(date, timesheet, filmEntry, projectId, activityId) {
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
        } else if (hasId(projectId)) {
            // No entry yet, but the day's engagement names the project; the
            // activity is the project's usual film activity (or the running one).
            // Both stay pending until the project list has loaded.
            pendingProjectId = projectId
            pendingActivityId = hasId(activityId) ? activityId : null
            suppressProjectSignal = false
            trySelectPendingProject()
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

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: text.length > 0 && root.mode !== "noProject"
        wrapMode: Text.WordWrap
        font.pointSize: KanteStyle.smallFont.pointSize
        opacity: 0.8
        color: root.mode === "offline" ? KanteStyle.neutralTextColor : KanteStyle.textColor
        text: root.modeHint()
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        KantePlasmaToolButton {
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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.pointSize: KanteStyle.defaultFont.pointSize * 1.15
                color: KanteStyle.highlightColor
                wrapMode: Text.WordWrap
                text: root.selectedDay.toLocaleDateString(Qt.locale(), Locale.LongFormat)

                MouseArea {
                    anchors.fill: parent
                    enabled: root.configured && !root.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dayField.openPicker()
                }
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.isToday
                horizontalAlignment: Text.AlignHCenter
                text: i18n("Today")
                font: KanteStyle.labelFont()
                color: KanteStyle.mutedTextColor
            }
        }

        KantePlasmaToolButton {
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

    // ── Engagement: project, activity and role of the day ───────────────
    Item {
        id: engagementCard
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.engagement !== null || root.hasFilmActivity
        implicitHeight: cardRow.implicitHeight + Kirigami.Units.largeSpacing * 2

        KanteCard {
            anchors.fill: parent
            color: KanteStyle.cardColor
            borderColor: KanteStyle.frameColor
            barColor: root.shownPhase === "running" ? KanteStyle.accentColor : KanteStyle.frameColor
        }

        RowLayout {
            id: cardRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                PlasmaComponents3.Label {
                    text: root.engagement ? i18n("Engagement") : i18n("Project")
                    font: KanteStyle.labelFont()
                    color: KanteStyle.mutedTextColor
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.engagement && root.engagement.projectName ? root.engagement.projectName : root.projectCombo.currentLabel
                    font: KanteStyle.titleFont(KanteStyle.defaultFont.pointSize * 1.3)
                    color: KanteStyle.strongTextColor
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: [root.activityCombo.currentLabel || i18n("Pick an activity"),
                           root.engagement && root.engagement.crewRole ? root.engagement.crewRole : ""]
                          .filter(function(t) { return t.length > 0 }).join(" · ")
                    color: KanteStyle.mutedTextColor
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                    text: [root.engagement && root.engagement.customerName ? root.engagement.customerName : "",
                           root.productionDayNumber > 0 ? i18n("Shooting day %1", root.productionDayNumber) : "",
                           root.rulesetName]
                          .filter(function(t) { return t.length > 0 }).join(" · ")
                    font.pointSize: KanteStyle.smallFont.pointSize
                    color: KanteStyle.mutedTextColor
                }
            }

            KantePlasmaToolButton {
                Layout.alignment: Qt.AlignTop
                icon.name: "document-edit"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Change engagement")
                Accessible.name: text
                checkable: true
                checked: root.chooserOpen
                enabled: root.configured && !root.busy
                onClicked: root.chooserOpen = !root.chooserOpen
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    // Other engagements of the day, or any project and activity.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.chooserOpen || !engagementCard.visible
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: root.engagements.length > 1 ? root.engagements : []
            delegate: KantePlasmaButton {
                required property var modelData
                Layout.fillWidth: true
                checkable: true
                checked: root.engagement !== null && String(root.engagement.projectId) === String(modelData.projectId)
                text: [modelData.projectName || "", modelData.crewRole || ""].filter(function(t) { return t.length > 0 }).join(" · ")
                onClicked: {
                    root.chooserOpen = false
                    root.engagementPicked(modelData.projectId)
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: engagementCard.visible
            wrapMode: Text.WordWrap
            font.pointSize: KanteStyle.smallFont.pointSize
            color: KanteStyle.mutedTextColor
            text: i18n("Or pick another project and activity:")
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
                root.projectPicked(pickers.projectPickerModel[index].value.id)
            }
            onCreateProjectRequested: root.createProjectRequested()
            onCreateActivityRequested: root.createActivityRequested()
        }
    }

    // ── Before: start now, or enter times ───────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: root.shownPhase === "before"
        spacing: Kirigami.Units.smallSpacing

        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: (TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight) * 1.4
            visible: root.isToday
            highlighted: true
            emphasis: KantePlasmaButton.Emphasis.Primary
            icon.name: "media-playback-start"
            text: i18n("Start shooting day")
            enabled: root.configured && !root.busy && root.connectionOk && root.hasFilmActivity
            onClicked: root.startRequested(root.projectCombo.currentItem.value.id, root.activityCombo.currentItem.value.id,
                                           root.projectCombo.currentLabel, root.activityCombo.currentLabel)
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.isToday
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pointSize: KanteStyle.smallFont.pointSize
            color: KanteStyle.mutedTextColor
            text: i18n("Begins now, with the timer of the main page.")
        }
        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Enter times instead")
            icon.name: "document-edit"
            enabled: root.configured && !root.busy
            onClicked: root.manualRequested = true
        }
    }

    // ── Running: elapsed time of the main page's timer ──────────────────
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: root.shownPhase === "running"
        horizontalAlignment: Text.AlignHCenter
        text: KimaiApi.formatDuration(root.elapsedSeconds)
        font: KanteStyle.monoFont(KanteStyle.defaultFont.pointSize * 2.4, true)
        color: KanteStyle.active ? KanteStyle.accentTextColor : KanteStyle.positiveTextColor
    }

    // ── Begin / end: one display each, edited in place ──────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: root.shownPhase !== "before"
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: Kirigami.Units.smallSpacing / 2
            PlasmaComponents3.Label {
                text: i18n("Begin")
                font: KanteStyle.labelFont()
                color: KanteStyle.mutedTextColor
            }
            TimeField {
                id: beginTime
                Layout.fillWidth: true
                enabled: root.configured && !root.busy
                onTimeEdited: {
                    if (root.shownPhase === "running") {
                        root.runningBeginEdited(root.stampText(root.selectedDay, beginTime))
                    } else {
                        root.timesTouched()
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: Kirigami.Units.smallSpacing / 2
            PlasmaComponents3.Label {
                text: i18n("End")
                font: KanteStyle.labelFont()
                color: KanteStyle.mutedTextColor
            }
            TimeField {
                id: endTime
                Layout.fillWidth: true
                visible: root.shownPhase !== "running"
                enabled: root.configured && !root.busy
                onTimeEdited: root.timesTouched()
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.preferredHeight: beginTime.height
                visible: root.shownPhase === "running"
                verticalAlignment: Text.AlignVCenter
                text: i18n("running")
                color: KanteStyle.mutedTextColor
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: root.shownPhase !== "before"
        wrapMode: Text.WordWrap
        font.pointSize: KanteStyle.smallFont.pointSize
        color: root.shownPhase === "running" || root.rangeValid ? KanteStyle.textColor : KanteStyle.neutralTextColor
        text: {
            var bits = []
            if (root.extrasVisible) {
                bits.push(i18n("Break %1", root.durationText(root.effectiveBreakMinutes * 60)))
            }
            if (root.shownPhase === "running") {
                bits.push(i18n("Work time so far %1", root.durationText(Math.max(0, root.elapsedSeconds - root.effectiveBreakMinutes * 60))))
            } else {
                bits.push(root.rangeValid ? i18n("Work time %1", root.durationText(root.workSeconds)) : i18n("Work time: invalid range"))
            }
            if (root.earningsCents >= 0 && root.shownPhase === "done") {
                bits.push(root.formatMoney(root.earningsCents))
            }
            return bits.join(" · ")
        }
    }

    KantePlasmaButton {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.preferredHeight: (TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight) * 1.2
        visible: root.shownPhase === "running"
        emphasis: KantePlasmaButton.Emphasis.Destructive
        icon.name: "media-playback-stop"
        text: i18n("Stop shooting day")
        enabled: root.configured && !root.busy
        onClicked: root.stopRequested()
    }

    // A travel day usually comes with a trip: offer one linked to the day's entry.
    KantePlasmaButton {
        Layout.fillWidth: true
        visible: root.tripsAvailable && root.shownPhase === "done" && dayTypeCombo.currentIndex >= 0
                 && root.dayTypeOptions[dayTypeCombo.currentIndex].value === FilmDays.DayType.TRAVEL
        icon.name: "mark-location"
        text: i18n("Log trip")
        enabled: root.configured && !root.busy
        onClicked: root.tripRequested()
    }

    /** B3: more entries of the film day's activity on this day. */
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.otherEntries.length > 0 && root.shownPhase === "done"
        spacing: Kirigami.Units.smallSpacing / 2

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pointSize: KanteStyle.smallFont.pointSize
            color: KanteStyle.neutralTextColor
            text: i18np("This activity has %1 more entry on this day (%2); the work time above does not include it.",
                        "This activity has %1 more entries on this day (%2); the work time above does not include them.",
                        root.otherEntries.length, root.durationText(root.otherSpan.seconds))
        }

        PlasmaComponents3.CheckBox {
            KanteCheckSkin { control: parent }
            id: mergeCheck
            Layout.fillWidth: true
            visible: root.mergeable
            enabled: root.configured && !root.busy
            text: i18n("Merge into one entry")
            onToggled: {
                if (checked) {
                    root.applyMergedSpan()
                    root.saveRequested(root.projectCombo.currentItem.value.id, root.activityCombo.currentItem.value.id,
                                       root.stampText(root.selectedDay, beginTime), root.stampText(root.selectedDay, endTime),
                                       root.currentEntryFields())
                }
            }
        }
    }

    // Manual entry (a past day, or "Enter times instead"): explicit save.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.shownPhase === "manual"
        spacing: Kirigami.Units.smallSpacing

        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            highlighted: true
            emphasis: KantePlasmaButton.Emphasis.Primary
            enabled: root.configured && !root.busy && root.connectionOk && root.hasFilmActivity && root.rangeValid
            text: i18n("Save shooting day")
            icon.name: "document-save"
            onClicked: root.saveRequested(root.projectCombo.currentItem.value.id, root.activityCombo.currentItem.value.id,
                                          root.stampText(root.selectedDay, beginTime), root.stampText(root.selectedDay, endTime),
                                          root.currentEntryFields())
        }
        KantePlasmaButton {
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            visible: root.phase === "before"
            text: i18n("Cancel")
            onClicked: root.manualRequested = false
        }
    }

    // ── The day: film-day extras, saved directly ────────────────────────
    KanteHeading {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: root.extrasVisible
        level: 4
        text: i18n("Day")
    }

    GridLayout {
        Layout.fillWidth: true
        visible: root.extrasVisible
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label { text: i18n("Day type"); Layout.maximumWidth: root.formLabelWidth; wrapMode: Text.WordWrap }
        QQC2.ComboBox {
            KanteFieldSkin { control: parent }
            id: dayTypeCombo
            Layout.fillWidth: true
            model: root.dayTypeOptions.map(function(o) { return o.label })
            enabled: root.extrasEnabled
            onActivated: root.extrasTouched()
        }

        PlasmaComponents3.Label { text: i18n("Catering"); Layout.maximumWidth: root.formLabelWidth; wrapMode: Text.WordWrap }
        QQC2.Switch {
            KanteCheckSkin { control: parent; shape: KanteCheckSkin.Shape.Switch }
            id: cateringSwitch
            enabled: root.extrasEnabled
            Accessible.name: i18n("Catering")
            onToggled: root.extrasTouched()
        }

        PlasmaComponents3.Label { text: i18n("Break"); Layout.maximumWidth: root.formLabelWidth; wrapMode: Text.WordWrap }
        QQC2.SpinBox {
            KanteFieldSkin { control: parent }
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
                return value < 0 ? i18n("Default")
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
                root.extrasTouched()
            }
        }

        PlasmaComponents3.Label { text: i18n("Day category"); Layout.maximumWidth: root.formLabelWidth; wrapMode: Text.WordWrap }
        QQC2.ComboBox {
            KanteFieldSkin { control: parent }
            id: categoryCombo
            Layout.fillWidth: true
            model: root.categoryOptions.map(function(o) { return o.label })
            enabled: root.extrasEnabled
            onActivated: root.extrasTouched()
        }

        PlasmaComponents3.Label {
            visible: surchargeDaySpin.visible
            text: i18n("Surcharge day")
            Layout.maximumWidth: root.formLabelWidth
            wrapMode: Text.WordWrap
        }
        QQC2.SpinBox {
            KanteFieldSkin { control: parent }
            id: surchargeDaySpin
            Layout.fillWidth: true
            // Set once the day runs (1–7 of the TV FFS week; 0 = automatic).
            visible: root.serverMode && (root.shownPhase === "running" || root.shownPhase === "done")
            from: 0
            to: FilmDays.SURCHARGE_DAY_MAX
            editable: true
            enabled: root.extrasEnabled
            Accessible.name: i18n("Surcharge day")
            textFromValue: function(value) { return value === 0 ? i18n("Automatic") : String(value) }
            valueFromText: function(text) {
                var n = parseInt(text, 10)
                return isNaN(n) ? 0 : n
            }
            onValueModified: root.extrasTouched()
        }

        PlasmaComponents3.Label {
            visible: extraPayField.visible
            text: i18n("Extra pay / expenses")
            Layout.maximumWidth: root.formLabelWidth
            wrapMode: Text.WordWrap
        }
        KanteTextField {
            id: extraPayField
            Layout.fillWidth: true
            visible: root.extraPayAvailable && root.shownPhase !== "before"
            enabled: root.extrasEnabled
            placeholderText: root.currency ? "0.00 " + root.currency : "0.00"
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: RegularExpressionValidator { regularExpression: /[0-9]*[.,]?[0-9]{0,2}/ }
            onEditingFinished: root.extrasTouched()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.extrasVisible

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: i18n("Note")
        }
        PlasmaComponents3.Label {
            visible: noteField.length > FilmDays.NOTE_MAX_LENGTH - 100
            font.pointSize: KanteStyle.smallFont.pointSize
            opacity: 0.7
            text: i18n("%1/%2", noteField.length, FilmDays.NOTE_MAX_LENGTH)
        }
    }

    QQC2.TextArea {
        KanteFieldSkin { control: parent }
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
            root.extrasTouched()
        }
        background: Rectangle {
            // Material centers the first line in the background's implicit height;
            // without one its top padding turns negative (text above the field).
            implicitHeight: Kirigami.Units.gridUnit * 2.5
            color: "transparent"
            border.width: 0
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: noteField.activeFocus ? KanteStyle.highlightColor : KanteStyle.disabledTextColor
            }
        }
    }

    // ── Other activities of the day (travel …): information only ────────
    KanteHeading {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: root.otherActivities.length > 0
        level: 4
        text: i18n("Other activities")
    }

    Repeater {
        model: root.otherActivities
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: modelData.label
                elide: Text.ElideRight
                color: KanteStyle.mutedTextColor
            }
            PlasmaComponents3.Label {
                text: modelData.timeText
                font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false)
                color: KanteStyle.mutedTextColor
            }
        }
    }
}
