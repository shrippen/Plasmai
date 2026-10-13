import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/platform.js" as Platform
import "../../code/timerSession.js" as TimerSession
import ".." as Ui

/**
 * Idle detection while a timer runs, the forgot-to-start reminder and
 * notifications, where the platform offers them (the host says so).
 *
 *   every minute ─▶ Platform.checkIdle ─▶ verdict ─▶ idlePending ─▶ keep() | discard(after)
 *   every 5 min  ─▶ forgotToStartDay ─▶ forgotToStart()
 */
QtObject {
    id: reminders

    property QtObject session: null

    // ── Inputs: what the platform offers ──
    property bool idleAvailable: false
    property bool notificationsAvailable: false

    // ── Idle state ──
    /** The user chose to keep idle time: no prompt until active again. */
    property bool ignoreUntilActive: false
    property bool idlePending: false
    property int pendingMs: 0
    /** Wall-clock ms when the idle period began (detection time − idle ms). */
    property double pendingSince: 0
    property var snapshot: null
    property string forgotDay: ""

    /** Idle time was cut from the running entry; snap: TimerSession.snapshot. */
    signal idleDiscarded(var snap)
    signal forgotToStart()

    property Timer idleTimer: Timer {
        interval: 60000
        repeat: true
        running: reminders.idleAvailable && reminders.session.timer.tracking && reminders.session.settings.idleStopEnabled
        onTriggered: reminders.checkIdle()
    }

    property Timer forgotTimer: Timer {
        interval: 300000
        repeat: true
        running: reminders.notificationsAvailable && reminders.session.connection.configured
        onTriggered: reminders.checkForgot()
    }

    function notify(summary, body) {
        if (!notificationsAvailable) {
            return
        }
        Platform.sendNotification(session.dataSource, summary, body || "")
    }

    function checkIdle() {
        if (!session.timer.tracking || !session.settings.idleStopEnabled || idlePending) {
            return
        }
        Platform.checkIdle(session.dataSource).then(function(idleMs) {
            const v = TimerSession.verdict(idleMs, ignoreUntilActive, session.settings.idleStopMinutes)
            ignoreUntilActive = v.ignoring
            if (v.prompt) {
                promptIdle(idleMs)
            }
        })
    }

    function promptIdle(idleMs) {
        const t = session.timer
        pendingMs = idleMs
        pendingSince = TimerSession.idleSince(Date.now(), idleMs)
        snapshot = TimerSession.snapshot(t.active, t.timesheetId,
                                         { project: t.project, activity: t.activity, description: t.description })
        idlePending = true
    }

    function clearPending() {
        snapshot = null
        pendingMs = 0
        pendingSince = 0
        idlePending = false
    }

    function keep() {
        ignoreUntilActive = true
        clearPending()
    }

    /** Ends the entry where idle began; after: Session.AfterIdle (Continue starts it again). */
    function discard(after) {
        const snap = snapshot
        const since = pendingSince > 0 ? pendingSince : TimerSession.idleSince(Date.now(), pendingMs)
        clearPending()
        if (!snap || !snap.timesheetId) {
            session.timer.stop()
            return
        }

        // Stop where idle began (not "now − idle" at click time, which keeps
        // the time the dialog sat open), never before the entry's begin.
        const end = TimerSession.discardEnd(snap, since)
        const c = session.connection
        session.busy = true
        c.tracker.patchTimesheet(c.url, c.token, snap.timesheetId, { end: KimaiApi.localDateTimeString(end) }, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Stop, result)
                return
            }
            session.timer.apply(null)
            session.refresh()
            idleDiscarded(snap)
            if (after === Ui.Session.AfterIdle.Continue && TimerSession.canContinue(snap)) {
                session.timer.start(snap.projectId, snap.activityId, snap.projectName, snap.activityName, snap.description || "")
            }
        })
    }

    function checkForgot() {
        const s = session.settings
        const day = TimerSession.forgotToStartDay({
            enabled: s.notifyForgotToStart, configured: session.connection.configured, tracking: session.timer.tracking,
            workDayBegin: s.workDayBegin, workDayEnd: s.workDayEnd, lastDay: forgotDay
        }, new Date())
        if (!day) {
            return
        }
        forgotDay = day
        forgotToStart()
    }
}
