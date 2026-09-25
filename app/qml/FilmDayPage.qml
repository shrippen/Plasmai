import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/filmDays.js" as FilmDays
import "shared"

Kirigami.Page {
    id: page
    title: i18n("Film day")

    property bool loadingFilmDay: false
    property bool saving: false
    property var selectedDate: new Date()
    property var filmDayTimesheet: null
    property int loadSerial: 0

    function currentUrl() { return TimeTracker.resolveUrl(root.activeProfile) }

    function loadForDate(date) {
        page.selectedDate = date
        var selectedProjectIdForDay = (filmDayView.projectCombo.currentIndex >= 0)
            ? filmDayView.projectCombo.currentItem.value.id : null
        page.loadingFilmDay = true
        // Only the latest load may fill the view (fast day steps / project picks).
        var serial = ++page.loadSerial
        root.tracker.fetchTimesheetsRange(
            page.currentUrl(), root.apiToken, KimaiApi.startOfLocalDay(date), KimaiApi.endOfLocalDay(date),
            function(result) {
                if (serial !== page.loadSerial) return
                page.loadingFilmDay = false
                var entries = (result && result.ok) ? KimaiApi.hydrateTimesheets(
                    result.data || [], root.projects, root.activityCatalog(), root.activitiesByProject) : []
                var match = FilmDays.pickDayEntry(entries, selectedProjectIdForDay, KimaiApi.projectId)
                page.filmDayTimesheet = match
                var dateStr = KimaiApi.localDateString(date)
                var entryProjectId = match ? KimaiApi.projectId(match) : selectedProjectIdForDay
                var filmEntry = FilmDays.get(root.filmDaysMap, entryProjectId, dateStr)
                filmDayView.loadForDay(date, match, filmEntry)
            })
    }

    function stepDay(deltaDays) {
        var next = new Date(page.selectedDate)
        next.setDate(next.getDate() + deltaDays)
        loadForDate(next)
    }

    function doSave(projectId, activityId, beginText, endText, filmDayFields) {
        if (page.saving) return
        function parseLocalStamp(text) {
            var s = String(text || "").trim().replace(" ", "T")
            if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s)) {
                s += ":00"
            }
            return new Date(s)
        }
        var beginDate = parseLocalStamp(beginText)
        var endDate = parseLocalStamp(endText)
        if (isNaN(beginDate.getTime()) || isNaN(endDate.getTime())) {
            root.showPassiveNotification(i18n("Enter valid begin and end date/time."))
            return
        }
        if (endDate.getTime() <= beginDate.getTime()) {
            root.showPassiveNotification(i18n("End must be after begin."))
            return
        }
        page.saving = true
        var fields = {
            begin: KimaiApi.localDateTimeString(beginDate),
            end: KimaiApi.localDateTimeString(endDate),
            project: projectId,
            activity: activityId
        }
        var existingId = FilmDays.saveTargetId(page.filmDayTimesheet, projectId, KimaiApi.projectId)
        function afterSave(result) {
            page.saving = false
            if (!result.ok) {
                root.showPassiveNotification(ApiErrors.text(result.error))
                return
            }
            var dateStr = KimaiApi.localDateString(page.selectedDate)
            root.saveFilmDayEntry(projectId, dateStr, filmDayFields)
            root.sendNotification(
                i18n("Shooting day saved"),
                KimaiApi.formatDuration(FilmDays.workSecondsFromSpan(
                    beginDate.getTime(), endDate.getTime(), filmDayFields.breakMinutes)))
            pageStack.pop()
        }
        if (existingId !== undefined && existingId !== null && existingId !== "") {
            root.tracker.patchTimesheet(page.currentUrl(), root.apiToken, existingId, fields, afterSave)
        } else {
            root.tracker.createTimesheet(page.currentUrl(), root.apiToken, fields, afterSave)
        }
    }

    Component.onCompleted: {
        if (root.projectPickerModel.length === 0) {
            root.refreshAll()
        }
        loadForDate(page.selectedDate)
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            FilmDayView {
                id: filmDayView
                Layout.fillWidth: true
                projectPickerModel: root.projectPickerModel
                busy: page.loadingFilmDay || page.saving
                configured: root.isConfigured
                connectionOk: root.connectionState !== "error"
                showCreateActions: root.providerCapabilities.createEntities
                onProjectChosen: function(projectId) {
                    root.loadActivitiesForProject(projectId, function(model) { filmDayView.activityPickerModel = model })
                }
                onProjectPicked: function(projectId) {
                    page.loadForDate(page.selectedDate)
                }
                onDayStepRequested: function(deltaDays) {
                    page.stepDay(deltaDays)
                }
                onDayChosen: function(date) {
                    page.loadForDate(date)
                }
                onSaveRequested: function(projectId, activityId, beginText, endText, filmDayFields) {
                    page.doSave(projectId, activityId, beginText, endText, filmDayFields)
                }
                onCancelled: pageStack.pop()
                onCreateProjectRequested: { createEntityDialog.customers = root.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
                onCreateActivityRequested: {
                    createEntityDialog.selectedProjectId = filmDayView.projectCombo.currentItem ? filmDayView.projectCombo.currentItem.value.id : null
                    createEntityDialog.selectedProjectName = filmDayView.projectCombo.currentItem ? filmDayView.projectCombo.currentItem.value.name : ""
                    createEntityDialog.resetForMode("activity"); createEntityDialog.open()
                }
            }
        }
    }

    CreateEntityDialog {
        id: createEntityDialog
        onSubmitted: function(mode, payload) {
            if (mode === "customer") root.createCustomer(payload)
            else if (mode === "project") root.createProject(payload)
            else if (mode === "activity") root.createActivity(payload)
        }
    }
}
