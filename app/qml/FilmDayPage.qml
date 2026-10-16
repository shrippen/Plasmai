import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/filmDays.js" as FilmDays
import "../contents/code/dateTimeFormat.js" as DTF
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
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
    /** Entry the note belongs to (running or the day's), null before it exists. */
    property var noteEntry: null
    /** The note as last loaded or saved (its entry's description). */
    property string savedNote: ""

    /** Shown entry's time label ("12:15–12:45") for the other activities. */
    function spanText(ts) {
        function clock(v) {
            var d = v ? DTF.parseStamp(v) : null
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
        // One engagement per day: it decides the project; the plugin's day
        // summary decides which of the project's entries is the film day.
        // Cached days show at once; the live answer follows when it differs.
        session.filmDay.openDay(date, selectedProjectIdForDay, function(r, entries) {
                    if (serial !== page.loadSerial) return
                    var day = r.day
                    page.loadingFilmDay = false
                    page.filmDayTimesheet = r.match
                    page.filmDayServer = day.server
                    page.filmDayLoadMode = day.mode
                    var daysFromToday = -DTF.daysBefore(date, new Date())
                    var info = session.filmDay.viewInfo(r, {
                        entries: entries, active: session.timer.tracking ? session.timer.active : null,
                        recent: session.recent.list, daysFromToday: daysFromToday,
                        ids: session.filmDay.ids,
                        labelOf: function(ts) {
                            return KimaiApi.displayActivityName(ts, session.catalog.activities, session.catalog.activitiesByProject)
                                + " · " + KimaiApi.displayProjectName(ts, session.catalog.projects)
                        },
                        timeOf: page.spanText
                    })
                    page.filmDayTimesheet = r.match
                    page.noteEntry = info.timesheet
                    page.savedNote = FilmDays.noteOf(info.timesheet)
                    filmDayView.applyLoadedDay(date, info.timesheet, day,
                        KimaiApi.customerCurrencyOfProject(session.catalog.projectById(r.projectId), session.catalog.customers),
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
        session.filmDay.productionDay(r.projectId, info.activityId, r.activityIds,
                                      String(r.engagement.validFrom), dateStr, function(count) {
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
        session.filmDay.saveExtras({
            projectId: projectId, dateStr: dateStr, fields: fields,
            server: page.filmDayServer, dayMode: page.filmDayLoadMode
        }, function(result) {
            if (result.extras === "failed") {
                root.showPassiveNotification(i18n("The film day was not saved: %1",
                                                  (result.error && result.error.detail) || ApiErrors.text(result.error)))
                return
            }
            if (result.server) page.filmDayServer = result.server
        }, function(payCents) {
            filmDayView.earningsCents = payCents
        })
    }

    /** The note is the entry's description; before the entry exists it goes with Start / Save. */
    function saveNote(text) {
        session.filmDay.saveNote({
            timesheetId: page.noteEntry ? page.noteEntry.id : null, note: text, previous: page.savedNote
        }, function(result) {
            if (result.saved === "failed") {
                root.reportWriteError({ ok: false, error: result.error }, i18n("Could not save the entry"))
                return
            }
            if (result.saved === "saved") {
                page.savedNote = result.note
            }
        })
    }

    function parseLocalStamp(text) {
        return DTF.parseStamp(text)
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
        var existingId = FilmDays.saveTargetId(page.filmDayTimesheet, projectId, KimaiApi.projectId)
        var timesheetFields = {
            begin: KimaiApi.localDateTimeString(beginDate),
            end: KimaiApi.localDateTimeString(endDate),
            project: projectId,
            activity: activityId
        }
        // A new entry takes the note typed before it existed.
        if (!existingId) {
            timesheetFields.description = filmDayView.noteText()
        }
        session.filmDay.saveDay({
            projectId: projectId,
            dateStr: KimaiApi.localDateString(page.selectedDate),
            existingId: existingId,
            timesheetFields: timesheetFields,
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
                    session.reminders.notify(
                        i18n("Shooting day saved"),
                        KimaiApi.formatDurationShort(FilmDays.workSecondsFromSpan(
                            beginDate.getTime(), endDate.getTime(), breakMinutes)))
                }
                page.loadForDate(page.selectedDate)
            }
            if (mergeIds.length > 0) {
                session.filmDay.deleteEntries(mergeIds, finish)
            } else {
                finish(null)
            }
        })
    }

    Component.onCompleted: {
        if (session.catalog.projectPickerModel.length === 0) {
            session.refresh()
        }
        page.loadingFilmDay = true
        session.filmDay.resolveMode(Session.Probe.Cached, function() {
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
                onlineActions: !session.sync.offline
                Layout.fillWidth: true
                projectPickerModel: session.catalog.projectPickerModel
                busy: page.loadingFilmDay || page.saving
                configured: session.connection.configured
                connectionOk: session.connection.state !== "error"
                showCreateActions: session.entries.canCreate
                onProjectChosen: function(projectId) {
                    session.catalog.loadActivities(projectId, function(model) { filmDayView.activityPickerModel = model })
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
                elapsedSeconds: session.timer.elapsedSeconds
                onSaveRequested: function(projectId, activityId, beginText, endText, filmDayFields) {
                    page.doSave(projectId, activityId, beginText, endText, filmDayFields, false)
                }
                onTimesEdited: function(beginText, endText) {
                    page.doSave(filmDayView.projectCombo.currentItem.value.id, filmDayView.activityCombo.currentItem.value.id,
                                beginText, endText, filmDayView.currentEntryFields(), true)
                }
                onExtrasEdited: function(fields) { page.saveExtrasNow(fields) }
                onNoteEdited: function(text) { page.saveNote(text) }
                onStartRequested: function(projectId, activityId, projectLabel, activityLabel) {
                    session.timer.switchTo(projectId, activityId, projectLabel, activityLabel, filmDayView.noteText())
                }
                onStopRequested: session.timer.stop()
                onRunningBeginEdited: function(beginText) {
                    session.timer.patchActive({ begin: KimaiApi.localDateTimeString(page.parseLocalStamp(beginText)) })
                }
                tripsAvailable: session.trips.canEdit
                onTripRequested: root.openTripForTimesheet(page.filmDayTimesheet)
                onEngagementPicked: function(projectId) {
                    filmDayView.selectProjectId(projectId)
                    page.loadForDate(page.selectedDate, true)
                }
                onCancelled: pageStack.pop()
                onCreateProjectRequested: { createEntityDialog.customers = session.catalog.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
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
        target: session.timer
        function onTrackingChanged() { page.loadForDate(page.selectedDate) }
    }

    // Leaving the page or the app must not drop a note still being typed: the
    // save starts right away (the request outlives the page).
    Component.onDestruction: filmDayView.flushPending()
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                filmDayView.flushPending()
            }
        }
    }

    CreateEntityDialog {
        id: createEntityDialog
        onSubmitted: function(mode, payload) {
            session.entries.createEntity(mode, payload)
        }
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: pageScroll
        anchors.fill: parent
        z: 10
        flickable: pageScroll.contentItem
        busy: page.loadingFilmDay
        onRefreshRequested: { session.filmDay.resolveMode(Session.Probe.Fresh, function() { page.loadForDate(page.selectedDate) }) }
    }
}
