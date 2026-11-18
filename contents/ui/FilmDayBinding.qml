import QtQuick
import "../code/dateTimeFormat.js" as DTF
import "."

/**
 * Connects the film day view to the session, for the widget and the app alike:
 * the shown day, day steps, saving entry, extras and note, and the words for
 * what a save answered. The host sets `view` and `session`, and says only how a
 * message appears (problem, failed, noteFailed) and what else follows a save.
 *
 *   view signal ─▶ here ─▶ session.filmDay ─▶ answer ─▶ view / signal to host
 */
QtObject {
    id: binding

    property QtObject session: null
    property Item view: null
    /** The day the view shows. */
    property var selectedDate: new Date()
    /** False while the host cannot take a save (not set up, a write runs). */
    property bool canSave: true

    /** A save starts; the host drops its old message. */
    signal saveStarted()
    /** The entry was saved (extras or merge may still have failed, see problem). */
    signal saved()
    /** Words for the user: a span problem, a failed extra or a failed merge deletion. */
    signal problem(string text)
    /** The save was refused or failed as a whole. */
    signal failed(var error)
    /** The note did not save. */
    signal noteFailed(var error)

    /** The project the view has picked, null before. */
    function pickedProject() {
        if (!view || view.projectCombo.currentIndex < 0) {
            return null
        }
        return view.projectCombo.currentItem.value.id
    }

    /** Fills the view with the day the session loaded; a view that is gone shows nothing. */
    function showDay(loaded) {
        if (!binding || !view) {
            return
        }
        const r = loaded.r
        const info = loaded.info
        view.applyLoadedDay(loaded.date, info.timesheet, loaded.day, loaded.currency, r.others, r.projectId, {
            phase: info.phase, isToday: info.isToday, activityId: info.activityId,
            engagement: r.engagement, engagements: r.engagements,
            otherActivities: info.otherActivities
        })
    }

    function showProduction(production) {
        if (!binding || !view) {
            return
        }
        view.productionDayNumber = production.number
        // No activity from the day or Recent: the engagement's usual film activity.
        if (view.activityCombo.currentIndex < 0 && production.activityId !== null) {
            view.selectActivity(production.activityId)
        }
    }

    /** Shows the day when the view opens; a cached answer comes at once. */
    function open(probe) {
        session.filmDay.openView(probe, selectedDate, binding.pickedProject, false, binding.showDay, binding.showProduction)
    }

    /** Loads the entry and extras of `date` into the view. */
    function load(date) {
        selectedDate = date
        session.filmDay.loadDay(date, pickedProject(), false, showDay, showProduction)
    }

    function reload() {
        load(selectedDate)
    }

    /** The engagement chooser picked the project: it wins over the day's engagement. */
    function loadPickedEngagement() {
        session.filmDay.loadDay(selectedDate, pickedProject(), true, showDay, showProduction)
    }

    function step(deltaDays) {
        const next = new Date(selectedDate)
        next.setDate(next.getDate() + deltaDays)
        load(next)
    }

    /** Direct save of the extras (no busy state: the fields stay usable). */
    function saveExtras(fields) {
        if (!view) {
            return
        }
        session.filmDay.saveExtras({
            projectId: pickedProject(), date: selectedDate, fields: fields
        }, function(result) {
            if (!binding || result.extras !== "failed") {
                return
            }
            problem(i18n("The film day was not saved: %1", ApiErrors.withServer(result.error)))
        }, function(payCents) {
            if (!binding || !view) {
                return
            }
            view.earningsCents = payCents
        })
    }

    /** The note is the entry's description; before the entry exists it goes with Start / Save. */
    function saveNote(text) {
        session.filmDay.saveNote(text, function(result) {
            if (!binding || result.saved !== "failed") {
                return
            }
            noteFailed(result.error)
        })
    }

    /** Saves entry and extras of the form. */
    function saveForm(projectId, activityId, beginText, endText, fields) {
        send(projectId, activityId, beginText, endText, fields, false)
    }

    /** Saves after begin or end of the shown entry changed (no message, fields stay usable). */
    function saveTimes(beginText, endText) {
        send(view.projectCombo.currentItem.value.id, view.activityCombo.currentItem.value.id,
             beginText, endText, view.currentEntryFields(), true)
    }

    function send(projectId, activityId, beginText, endText, fields, direct) {
        if (!canSave) {
            return
        }
        saveStarted()
        session.filmDay.saveDay({
            projectId: projectId, activityId: activityId, date: selectedDate,
            beginText: beginText, endText: endText, fields: fields, direct: direct,
            // B3: the other entries of the project on this day, deleted after a successful save.
            mergeIds: (view && view.mergeOthers) ? view.otherEntryIds() : [],
            breakMinutes: (view && view.extrasVisible) ? view.effectiveBreakMinutes : 0,
            note: view ? view.noteText() : ""
        }, function(result) {
            if (!binding) {
                return
            }
            answered(result, direct)
        })
    }

    /** The words for what the save answered; a failed part keeps the user on the day. */
    function answered(result, direct) {
        // The film day's span problems are TimeProblem values (DATES, ORDER).
        if (result.invalid) {
            problem(EntryTexts.timeProblem(result.invalid))
            return
        }
        if (!result.ok) {
            failed(result.error)
            return
        }
        saved()

        const report = result.deleteReport
        const messages = []
        if (result.extras === "failed") {
            messages.push(i18n("Begin and end were saved, but the film day extras were not: %1",
                               ApiErrors.withServer(result.error)))
        }
        if (report && report.failed.length > 0) {
            // The day still has more than one entry.
            messages.push(i18np("%1 other entry of this day could not be deleted: %2",
                                "%1 other entries of this day could not be deleted: %2",
                                report.failed.length, ApiErrors.withServer(report.failed[0].error)))
        }
        if (messages.length > 0) {
            problem(messages.join(" "))
        } else if (!direct) {
            session.reminders.notify(i18n("Shooting day saved"), DTF.formatDurationShort(result.workSeconds))
        }
        reload()
    }

    // What the view shows of the session besides the day.
    readonly property list<QtObject> shown: [
        Binding { target: binding.view; property: "projectPickerModel"; value: binding.session.catalog.projectPickerModel },
        Binding { target: binding.view; property: "configured"; value: binding.session.connection.configured },
        Binding { target: binding.view; property: "showCreateActions"; value: binding.session.entries.canCreate },
        Binding { target: binding.view; property: "tripsAvailable"; value: binding.session.trips.canEdit },
        Binding { target: binding.view; property: "onlineActions"; value: !binding.session.sync.offline }
    ]

    readonly property Connections viewSignals: Connections {
        target: binding.view

        function onProjectPicked() { binding.reload() }
        function onDayStepRequested(deltaDays) { binding.step(deltaDays) }
        function onDayChosen(date) { binding.load(date) }
        function onSaveRequested(projectId, activityId, beginText, endText, fields) {
            binding.saveForm(projectId, activityId, beginText, endText, fields)
        }
        function onTimesEdited(beginText, endText) { binding.saveTimes(beginText, endText) }
        function onExtrasEdited(fields) { binding.saveExtras(fields) }
        function onNoteEdited(text) { binding.saveNote(text) }
        function onStartRequested(projectId, activityId, projectLabel, activityLabel) {
            binding.session.timer.switchTo(projectId, activityId, projectLabel, activityLabel, binding.view.noteText())
        }
        function onStopRequested() { binding.session.timer.stop() }
        function onEngagementPicked(projectId) {
            binding.view.selectProject(projectId)
            binding.loadPickedEngagement()
        }
    }
}
