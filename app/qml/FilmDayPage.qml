import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/filmDays.js" as FilmDays
import "../contents/code/filmDaySync.js" as FilmDaySync
import "shared"

Kirigami.Page {
    id: page
    title: i18n("Film day")

    property bool loadingFilmDay: false
    property bool saving: false
    property var selectedDate: new Date()
    property var filmDayTimesheet: null
    /** Film-day JSON the next save diffs against (server mode). */
    property var filmDayServer: null
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
                var entries = (result && result.ok) ? KimaiApi.hydrateTimesheets(
                    result.data || [], root.projects, root.activityCatalog(), root.activitiesByProject) : []
                var match = FilmDays.pickDayEntry(entries, selectedProjectIdForDay, KimaiApi.projectId)
                var dateStr = KimaiApi.localDateString(date)
                var entryProjectId = match ? KimaiApi.projectId(match) : selectedProjectIdForDay
                // P5: the engagement is checked per project + day (film-day GET answers 404 without one).
                FilmDaySync.loadDay(root.filmDayContext(), entryProjectId, dateStr, function(day) {
                    if (serial !== page.loadSerial) return
                    page.loadingFilmDay = false
                    page.filmDayTimesheet = match
                    page.filmDayServer = day.server
                    if (day.mode === FilmDaySync.Mode.SERVER && root.filmDayMode === FilmDaySync.Mode.OFFLINE) {
                        root.filmDayMode = FilmDaySync.Mode.SERVER
                    }
                    filmDayView.applyLoadedDay(date, match, day,
                        KimaiApi.customerCurrencyOfProject(root.projectById(entryProjectId), root.customers),
                        root.filmDayMigrationCount())
                })
            })
    }

    function stepDay(deltaDays) {
        var next = new Date(page.selectedDate)
        next.setDate(next.getDate() + deltaDays)
        loadForDate(next)
    }

    function runMigration() {
        if (filmDayView.migrationBusy || root.filmDayMode !== FilmDaySync.Mode.SERVER) return
        var ctx = root.filmDayContext()
        var candidates = FilmDaySync.migrationCandidates(ctx, root.projectIdsOfCatalog())
        if (candidates.length === 0) return
        filmDayView.migrationBusy = true
        FilmDaySync.migrate(ctx, candidates, function(report) {
            filmDayView.migrationBusy = false
            root.persistFilmDayKeys({ filmDaysJson: FilmDays.serialize(report.localMap) })
            filmDayView.showMigrationReport(report)
            page.loadForDate(page.selectedDate)
        })
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
        var breakMinutes = filmDayView.extrasVisible ? filmDayView.effectiveBreakMinutes : 0
        FilmDaySync.saveDay(root.filmDayContext(), {
            projectId: projectId,
            dateStr: KimaiApi.localDateString(page.selectedDate),
            existingId: FilmDays.saveTargetId(page.filmDayTimesheet, projectId, KimaiApi.projectId),
            timesheetFields: {
                begin: KimaiApi.localDateTimeString(beginDate),
                end: KimaiApi.localDateTimeString(endDate),
                project: projectId,
                activity: activityId
            },
            fields: filmDayFields,
            server: page.filmDayServer
        }, function(result) {
            page.saving = false
            if (!result.ok) {
                root.showPassiveNotification(ApiErrors.text(result.error))
                return
            }
            var patch = {}
            if (result.localMap) patch.filmDaysJson = FilmDays.serialize(result.localMap)
            if (result.pendingMap) patch.filmDaysPending = FilmDaySync.serializePending(result.pendingMap)
            if (Object.keys(patch).length > 0) root.persistFilmDayKeys(patch)
            if (result.extras === "queued") {
                root.showPassiveNotification(i18n("Begin and end were saved. The film day extras could not be sent and will be retried."))
            } else if (result.extras === "rejected") {
                // Stay on the page so the field can be fixed.
                root.showPassiveNotification(i18n("Begin and end were saved, but the server rejected the film day extras: %1",
                                                  (result.error && result.error.detail) || ApiErrors.text(result.error)))
                page.loadForDate(page.selectedDate)
                return
            }
            root.sendNotification(
                i18n("Shooting day saved"),
                KimaiApi.formatDuration(FilmDays.workSecondsFromSpan(
                    beginDate.getTime(), endDate.getTime(), breakMinutes)))
            pageStack.pop()
        })
    }

    Component.onCompleted: {
        if (root.projectPickerModel.length === 0) {
            root.refreshAll()
        }
        page.loadingFilmDay = true
        root.resolveFilmDayMode(false, function() {
            root.flushFilmDayPending()
            page.loadForDate(page.selectedDate)
        })
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
                onMigrationRequested: page.runMigration()
                onMigrationDismissed: {
                    root.filmDayMigrationDismissed = true
                    filmDayView.migrationCount = 0
                    filmDayView.migrationReport = ""
                }
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
