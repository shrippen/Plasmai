import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/filmDays.js" as FilmDays
import "../contents/code/filmDaySync.js" as FilmDaySync
import "../contents/code/dateTimeFormat.js" as DTF
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: i18n("Film day")

    property bool loadingFilmDay: false
    property bool saving: false
    property var selectedDate: new Date()
    property var filmDayTimesheet: null
    /** Film-day JSON the next save diffs against (server mode). */
    property var filmDayServer: null
    property string filmDayLoadMode: ""
    property int loadSerial: 0

    function currentUrl() { return TimeTracker.resolveUrl(root.activeProfile) }

    /** Shown entry's time label ("12:15–12:45") for the other activities. */
    function spanText(ts) {
        function clock(v) {
            var d = v ? new Date(v) : null
            return d && !isNaN(d.getTime()) ? DTF.formatLocaleTime(d.getHours(), d.getMinutes()) : "…"
        }
        return clock(ts.begin) + "–" + clock(ts.end)
    }

    /** preferSelected: the engagement chooser picked the project, it wins over the day's engagement. */
    function loadForDate(date, preferSelected) {
        page.selectedDate = date
        var selectedProjectIdForDay = (filmDayView.projectCombo.currentIndex >= 0)
            ? filmDayView.projectCombo.currentItem.value.id : null
        page.loadingFilmDay = true
        // Only the latest load may fill the view (fast day steps / project picks).
        var serial = ++page.loadSerial
        var dateStr = KimaiApi.localDateString(date)
        function hydrate(raw) {
            return KimaiApi.hydrateTimesheets(raw, root.projects, root.activityCatalog(), root.activitiesByProject)
        }
        // One engagement per day: it decides the project; the plugin's day
        // summary decides which of the project's entries is the film day.
        // Cached days show at once; the live answer follows when it differs.
        FilmDaySync.openDay(root.filmDayContext(), date, selectedProjectIdForDay,
                            { projectOf: KimaiApi.projectId, activityOf: KimaiApi.activityId }, hydrate,
                            function(r, entries) {
                    if (serial !== page.loadSerial) return
                    var day = r.day
                    page.loadingFilmDay = false
                    page.filmDayTimesheet = r.match
                    page.filmDayServer = day.server
                    page.filmDayLoadMode = day.mode
                    if (day.mode === FilmDaySync.Mode.SERVER && root.filmDayMode === FilmDaySync.Mode.OFFLINE) {
                        root.filmDayMode = FilmDaySync.Mode.SERVER
                    }
                    var daysFromToday = -DTF.daysBefore(date, new Date())
                    var info = FilmDaySync.viewInfo(r, {
                        entries: entries, active: root.isTracking ? root.activeTimesheet : null,
                        recent: root.recentTimesheets, daysFromToday: daysFromToday,
                        ids: { projectOf: KimaiApi.projectId, activityOf: KimaiApi.activityId },
                        labelOf: function(ts) {
                            return KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject)
                                + " · " + KimaiApi.displayProjectName(ts, root.projects)
                        },
                        timeOf: page.spanText
                    })
                    page.filmDayTimesheet = r.match
                    filmDayView.applyLoadedDay(date, info.timesheet, day,
                        KimaiApi.customerCurrencyOfProject(root.projectById(r.projectId), root.customers),
                        r.others, r.projectId, {
                            phase: info.phase, isToday: info.isToday, activityId: info.activityId,
                            engagement: r.engagement, engagements: r.engagements,
                            otherActivities: info.otherActivities
                        })
                    page.loadProductionDay(serial, r, info, dateStr)
                }, !!preferSelected)
    }

    /** Production shooting day of the engagement, filled in once counted. */
    function loadProductionDay(serial, r, info, dateStr) {
        if (!r.engagement || !r.engagement.validFrom) return
        FilmDaySync.productionDay(root.filmDayContext(), r.projectId, info.activityId, r.activityIds,
                                  String(r.engagement.validFrom), dateStr,
                                  { projectOf: KimaiApi.projectId, activityOf: KimaiApi.activityId }, function(count) {
            if (serial !== page.loadSerial || !count) return
            // A day without its entry yet (before the start) is the next shooting day.
            var n = count.includesDay ? count.count : (info.phase === "before" ? count.count + 1 : 0)
            filmDayView.productionDayNumber = n
            // No activity from the day or Recent: the engagement's usual film activity.
            if (filmDayView.activityCombo.currentIndex < 0 && count.activityId !== null) {
                filmDayView.pendingActivityId = count.activityId
                filmDayView.trySelectPendingActivity()
            }
        })
    }

    /** Direct save of the extras (no busy state: the fields stay usable). */
    function saveExtrasNow(fields) {
        var projectId = filmDayView.projectCombo.currentIndex >= 0 ? filmDayView.projectCombo.currentItem.value.id : null
        var dateStr = KimaiApi.localDateString(page.selectedDate)
        FilmDaySync.saveExtras(root.filmDayContext(), {
            projectId: projectId, dateStr: dateStr, fields: fields,
            server: page.filmDayServer, dayMode: page.filmDayLoadMode
        }, function(result) {
            if (result.extras === "failed") {
                root.showPassiveNotification(i18n("The film day was not saved: %1",
                                                  (result.error && result.error.detail) || ApiErrors.text(result.error)))
                return
            }
            if (result.server) page.filmDayServer = result.server
            if (result.extras === "saved" && KimaiApi.drehzettelHasFeature(root.filmDayContext().ping, "daySummary")) {
                KimaiApi.fetchDaySummary(page.currentUrl(), root.apiToken, projectId, dateStr, function(sres) {
                    if (sres.ok && sres.data && typeof sres.data.payCents === "number") {
                        filmDayView.earningsCents = sres.data.payCents
                    }
                })
            }
        })
    }

    function parseLocalStamp(text) {
        var s = String(text || "").trim().replace(" ", "T")
        if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s)) {
            s += ":00"
        }
        return new Date(s)
    }

    function stepDay(deltaDays) {
        var next = new Date(page.selectedDate)
        next.setDate(next.getDate() + deltaDays)
        loadForDate(next)
    }

    /** Saves entry and extras. direct: begin / end of the shown entry changed (no message, fields stay usable). */
    function doSave(projectId, activityId, beginText, endText, filmDayFields, direct) {
        if (page.saving) return
        var beginDate = page.parseLocalStamp(beginText)
        var endDate = page.parseLocalStamp(endText)
        if (isNaN(beginDate.getTime()) || isNaN(endDate.getTime())) {
            root.showPassiveNotification(i18n("Enter valid begin and end date/time."))
            return
        }
        if (endDate.getTime() <= beginDate.getTime()) {
            root.showPassiveNotification(i18n("End must be after begin."))
            return
        }
        page.saving = !direct
        var breakMinutes = filmDayView.extrasVisible ? filmDayView.effectiveBreakMinutes : 0
        // B3: the other entries of the project on this day, deleted after a successful save.
        var mergeIds = filmDayView.mergeOthers ? filmDayView.otherEntryIds() : []
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
            server: page.filmDayServer,
            dayMode: page.filmDayLoadMode
        }, function(result) {
            page.saving = false
            if (!result.ok) {
                root.showPassiveNotification(ApiErrors.text(result.error))
                return
            }
            function finish(deleteReport) {
                if (deleteReport && deleteReport.failed.length > 0) {
                    // Stay on the page: the day still has more than one entry.
                    root.showPassiveNotification(i18np("%1 other entry of this day could not be deleted: %2",
                                                       "%1 other entries of this day could not be deleted: %2",
                                                       deleteReport.failed.length, ApiErrors.text(deleteReport.failed[0].error)))
                    page.loadForDate(page.selectedDate)
                    return
                }
                if (result.extras === "failed") {
                    // Stay on the page so the field can be fixed or the save repeated.
                    root.showPassiveNotification(i18n("Begin and end were saved, but the film day extras were not: %1",
                                                      (result.error && result.error.detail) || ApiErrors.text(result.error)))
                    page.loadForDate(page.selectedDate)
                    return
                }
                if (!direct) {
                    root.sendNotification(
                        i18n("Shooting day saved"),
                        KimaiApi.formatDurationShort(FilmDays.workSecondsFromSpan(
                            beginDate.getTime(), endDate.getTime(), breakMinutes)))
                }
                page.loadForDate(page.selectedDate)
            }
            if (mergeIds.length > 0) {
                FilmDaySync.deleteEntries(root.filmDayContext(), mergeIds, finish)
            } else {
                finish(null)
            }
        })
    }

    Component.onCompleted: {
        if (root.projectPickerModel.length === 0) {
            root.refreshAll()
        }
        page.loadingFilmDay = true
        root.resolveFilmDayMode(false, function() {
            page.loadForDate(page.selectedDate)
        })
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        // The scroll bar sits at the screen edge; the content keeps the page margin.
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: (pageScroll.availableWidth - page.rightPadding)
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
                elapsedSeconds: root.elapsedSeconds
                onSaveRequested: function(projectId, activityId, beginText, endText, filmDayFields) {
                    page.doSave(projectId, activityId, beginText, endText, filmDayFields, false)
                }
                onTimesEdited: function(beginText, endText) {
                    page.doSave(filmDayView.projectCombo.currentItem.value.id, filmDayView.activityCombo.currentItem.value.id,
                                beginText, endText, filmDayView.currentEntryFields(), true)
                }
                onExtrasEdited: function(fields) { page.saveExtrasNow(fields) }
                onStartRequested: function(projectId, activityId, projectLabel, activityLabel) {
                    root.switchToActivity(projectId, activityId, projectLabel, activityLabel, "")
                }
                onStopRequested: root.stopTracking()
                onRunningBeginEdited: function(beginText) {
                    root.patchActiveEntry({ begin: KimaiApi.localDateTimeString(page.parseLocalStamp(beginText)) })
                }
                tripsAvailable: root.canEditTrips
                onTripRequested: root.openTripForTimesheet(page.filmDayTimesheet)
                onEngagementPicked: function(projectId) {
                    filmDayView.selectProjectId(projectId)
                    page.loadForDate(page.selectedDate, true)
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

    // The film day follows the main page's timer (Start, Stop, a switch elsewhere).
    Connections {
        target: root
        function onIsTrackingChanged() { page.loadForDate(page.selectedDate) }
    }

    CreateEntityDialog {
        id: createEntityDialog
        onSubmitted: function(mode, payload) {
            if (mode === "customer") root.createCustomer(payload)
            else if (mode === "project") root.createProject(payload)
            else if (mode === "activity") root.createActivity(payload)
        }
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: pageScroll
        anchors.fill: parent
        z: 10
        flickable: pageScroll.contentItem
        busy: page.loadingFilmDay
        onRefreshRequested: { root.resolveFilmDayMode(true, function() { page.loadForDate(page.selectedDate) }) }
    }
}
