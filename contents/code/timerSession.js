.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./timesheetFields.js" as TimesheetFields

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

/** Key of project, activity and entry id: marks the row an "already running" hint belongs to. */
function switchHintKey(timesheet) {
    var id = timesheet && timesheet.id !== undefined && timesheet.id !== null ? timesheet.id : ""
    return String(KimaiApi.projectId(timesheet)) + "|" + String(KimaiApi.activityId(timesheet)) + "|" + String(id)
}
