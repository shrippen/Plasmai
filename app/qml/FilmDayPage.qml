import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/dateTimeFormat.js" as DTF
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
    KantePageTitle { page: page }
    title: i18n("Film day")

    property var selectedDate: new Date()

    /** The project the view has picked, null before. */
    function pickedProject() {
        return filmDayView.projectCombo.currentIndex >= 0 ? filmDayView.projectCombo.currentItem.value.id : null
    }

    /** Fills the view with the day the session loaded; a page that is gone shows nothing. */
    function showDay(loaded) {
        if (!page) { return }
        var r = loaded.r
        var info = loaded.info
        filmDayView.applyLoadedDay(loaded.date, info.timesheet, loaded.day, loaded.currency, r.others, r.projectId, {
            phase: info.phase, isToday: info.isToday, activityId: info.activityId,
            engagement: r.engagement, engagements: r.engagements,
            otherActivities: info.otherActivities
        })
    }

    function showProduction(production) {
        if (!page) { return }
        filmDayView.productionDayNumber = production.number
        // No activity from the day or Recent: the engagement's usual film activity.
        if (filmDayView.activityCombo.currentIndex < 0 && production.activityId !== null) {
            filmDayView.pendingActivityId = production.activityId
            filmDayView.trySelectPendingActivity()
        }
    }

    /** preferSelected: the engagement chooser picked the project, it wins over the day's engagement. */
    function loadForDate(date, preferSelected) {
        page.selectedDate = date
        session.filmDay.loadDay(date, pickedProject(), !!preferSelected, page.showDay, page.showProduction)
    }

    /** Direct save of the extras (no busy state: the fields stay usable). */
    function saveExtrasNow(fields) {
        session.filmDay.saveExtras({
            projectId: pickedProject(), date: page.selectedDate, fields: fields
        }, function(result) {
            if (!page) { return }
            if (result.extras === "failed") {
                root.showPassiveNotification(i18n("The film day was not saved: %1",
                                                  ApiErrors.withServer(result.error)))
            }
        }, function(payCents) {
            if (!page) { return }
            filmDayView.earningsCents = payCents
        })
    }

    /** The note is the entry's description; before the entry exists it goes with Start / Save. */
    function saveNote(text) {
        session.filmDay.saveNote(text, function(result) {
            if (!page) { return }
            if (result.saved === "failed") {
                root.reportWriteError({ ok: false, error: result.error }, i18n("Could not save the entry"))
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
        session.filmDay.saveDay({
            projectId: projectId, activityId: activityId, date: page.selectedDate,
            beginText: beginText, endText: endText, fields: filmDayFields, direct: direct,
            // B3: the other entries of the project on this day, deleted after a successful save.
            mergeIds: filmDayView.mergeOthers ? filmDayView.otherEntryIds() : [],
            breakMinutes: filmDayView.extrasVisible ? filmDayView.effectiveBreakMinutes : 0,
            note: filmDayView.noteText()
        }, function(result) {
            if (!page) { return }
            page.saved(result, direct)
        })
    }

    function saved(result, direct) {
        if (result.invalid) {
            root.showPassiveNotification(EntryTexts.timeProblem(result.invalid))
            return
        }
        if (!result.ok) {
            root.showPassiveNotification(ApiErrors.withServer(result.error))
            return
        }
        var report = result.deleteReport
        var messages = []
        if (report && report.failed.length > 0) {
            // The day still has more than one entry.
            messages.push(i18np("%1 other entry of this day could not be deleted: %2",
                                "%1 other entries of this day could not be deleted: %2",
                                report.failed.length, ApiErrors.withServer(report.failed[0].error)))
        }
        if (result.extras === "failed") {
            messages.push(i18n("Begin and end were saved, but the film day extras were not: %1",
                               ApiErrors.withServer(result.error)))
        }
        if (messages.length > 0) {
            // Stay on the page so the field can be fixed or the save repeated.
            root.showPassiveNotification(messages.join(" "))
        } else if (!direct) {
            session.reminders.notify(i18n("Shooting day saved"), DTF.formatDurationShort(result.workSeconds))
        }
        page.loadForDate(page.selectedDate)
    }

    Component.onCompleted: {
        if (session.catalog.projectPickerModel.length === 0) {
            session.refresh()
        }
        session.filmDay.openView(Session.Probe.Cached, page.selectedDate, page.pickedProject, false, page.showDay, page.showProduction)
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
                busy: session.filmDay.loading || session.filmDay.saving
                configured: session.connection.configured
                connectionOk: session.connection.state !== "error"
                showCreateActions: session.entries.canCreate
                onProjectChosen: function(projectId) {
                    session.catalog.loadActivities(projectId, function(model) {
                        if (!page) { return }
                        filmDayView.activityPickerModel = model
                    })
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
                    session.timer.patchActive({ begin: DTF.localDateTimeString(page.parseLocalStamp(beginText)) })
                }
                tripsAvailable: session.trips.canEdit
                onTripRequested: root.openTripForTimesheet(session.filmDay.dayTimesheet)
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
        busy: session.filmDay.loading
        onRefreshRequested: session.filmDay.openView(Session.Probe.Fresh, page.selectedDate, page.pickedProject, false,
                                                     page.showDay, page.showProduction)
    }
}
