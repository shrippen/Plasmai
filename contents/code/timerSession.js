.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./timesheetFields.js" as TimesheetFields
.import "./dateTimeFormat.js" as DTF

/**
 * Timer session rules shared by the Plasmoid and the app (ROADMAP pillar 5,
 * step 1): when idle time asks, what the idle dialog keeps, where a discard
 * ends the entry, when "nothing is tracking" reminds. The views keep the
 * dialogs, texts and requests.
 */

/** Idle this short (ms) counts as "back" after the user kept idle time. */
var ACTIVE_AGAIN_MS = 30000

var MINUTE_MS = 60 * 1000

/** Threshold in ms for the configured idle minutes (at least one minute). */
function thresholdMs(minutes) {
    var m = parseInt(minutes, 10)
    if (isNaN(m) || m < 1) {
        m = 1
    }
    return m * MINUTE_MS
}

/**
 * What an idle reading means: { prompt, ignoring } where ignoring is the new
 * "ignore until active" flag. After "keep", idle time is ignored until the
 * user was active again (idle below ACTIVE_AGAIN_MS).
 */
function verdict(idleMs, ignoring, minutes) {
    if (idleMs < 0) {
        return { prompt: false, ignoring: ignoring }
    }
    if (ignoring) {
        return { prompt: false, ignoring: idleMs >= ACTIVE_AGAIN_MS }
    }
    return { prompt: idleMs >= thresholdMs(minutes), ignoring: false }
}

/** The running entry as the idle dialog needs it after the timer changed. */
function snapshot(timesheet, timesheetId, names) {
    var begin = timesheet ? TimesheetFields.parseInstant(timesheet.begin) : null
    return {
        beginMs: begin ? begin.getTime() : 0,
        timesheetId: timesheetId,
        projectId: timesheet ? KimaiApi.projectId(timesheet) : null,
        activityId: timesheet ? KimaiApi.activityId(timesheet) : null,
        projectName: names.project,
        activityName: names.activity,
        description: names.description
    }
}

/** Wall-clock ms the idle period began: detection time minus idle time. */
function idleSince(nowMs, idleMs) {
    return nowMs - Math.max(0, idleMs)
}

/** End of the entry when idle time is discarded: idle start, never before the begin. */
function discardEnd(snap, sinceMs) {
    return new Date(Math.max(sinceMs, snap && snap.beginMs ? snap.beginMs : 0))
}

/** True when a discard can continue with the same project and activity. */
function canContinue(snap) {
    return !!(snap && snap.projectId && snap.activityId)
}

/**
 * Day key ("yyyy-MM-dd") to remind "nothing is tracking" for, or "" when not:
 * within work hours, not tracking, once per day.
 */
function forgotToStartDay(state, now) {
    if (!state.enabled || !state.configured || state.tracking) {
        return ""
    }
    if (!KimaiApi.isWithinWorkHours(state.workDayBegin, state.workDayEnd, now)) {
        return ""
    }
    var day = Qt.formatDate(now, "yyyy-MM-dd")
    return day === state.lastDay ? "" : day
}

/**
 * What the timer shows for the running entry. catalogs: { projects, activities,
 * activitiesByProject, customersById }. elapsedSeconds is -1 without a begin.
 */
function activeState(timesheet, catalogs, nowMs) {
    var begin = DTF.parseStamp(timesheet.begin)
    return {
        timesheetId: timesheet.id,
        project: KimaiApi.displayProjectName(timesheet, catalogs.projects),
        activity: KimaiApi.displayActivityName(timesheet, catalogs.activities, catalogs.activitiesByProject),
        customer: KimaiApi.customerNameFromTimesheet(timesheet, catalogs.customersById),
        customerColor: KimaiApi.customerColorFromTimesheet(timesheet, catalogs.customersById),
        description: timesheet.description || "",
        elapsedSeconds: isNaN(begin.getTime()) ? -1 : Math.max(0, Math.floor((nowMs - begin.getTime()) / 1000))
    }
}

/**
 * True while the user edits the running entry's description (focus, a pending
 * edit, unsaved text): a refresh must not replace the draft with the server's
 * text then. A different entry (started elsewhere) always takes its own text.
 */
function editingDescription(field) {
    if (field.sameEntry === false) {
        return false
    }
    return !!field.focused || !!field.dirty || (field.draft.length > 0 && field.draft !== field.current)
}

/** True when timesheet b has a's project and activity (b restarts what already runs). */
function sameActivity(a, b) {
    if (!a || !b) {
        return false
    }
    return String(KimaiApi.projectId(a)) === String(KimaiApi.projectId(b))
        && String(KimaiApi.activityId(a)) === String(KimaiApi.activityId(b))
}

/**
 * Switch the running timer: stop entry runningId, then start target
 * { projectId, activityId, description, extras }. The views react in steps:
 * stopped() between the two requests, started(timesheet), failed(phase, result)
 * with phase "stop" (nothing changed) or "start" (the timer is stopped).
 */
function switchTimer(tracker, url, token, runningId, target, steps) {
    tracker.stopTracking(url, token, runningId, function(stop) {
        if (!stop.ok) {
            steps.failed("stop", stop)
            return
        }
        steps.stopped()
        tracker.startTracking(url, token, target.projectId, target.activityId, target.description || "", function(start) {
            if (!start.ok || !start.data) {
                steps.failed("start", start)
                return
            }
            steps.started(start.data)
        }, target.extras || {})
    })
}

/** Key of project, activity and entry id: marks the row an "already running" hint belongs to. */
function switchHintKey(timesheet) {
    var id = timesheet && timesheet.id !== undefined && timesheet.id !== null ? timesheet.id : ""
    return String(KimaiApi.projectId(timesheet)) + "|" + String(KimaiApi.activityId(timesheet)) + "|" + String(id)
}
