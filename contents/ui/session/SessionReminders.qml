import QtQml
import "../../code/dateTimeFormat.js" as DTF
import "../../code/notices.js" as Notices
import "../../code/platform.js" as Platform
import "../../code/timerSession.js" as TimerSession
import ".." as Ui

/**
 * Idle detection while a timer runs, the forgot-to-start reminder and
 * notifications, where the platform offers them (the host says so).
 *
 *   every minute ─▶ Platform.checkIdle ─▶ verdict ─▶ idlePending ─▶ keep() | discard(after)
 *   every 5 min  ─▶ forgotToStartDay ─▶ notice(ForgotStart)
 *
 * Also decides when a system notice is due (notices.js) and says it as `notice(kind, names)`;
 * the view words it (EntryTexts.noticeTitle, noticeBody) and shows it.
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
    /** A start of this client just began: its refresh must not tell "in progress" once more. */
    property bool localStart: false

    /** Idle time was cut from the running entry; snap: TimerSession.snapshot. */
    signal idleDiscarded(var snap)
    /** Something to tell: kind is Notices.Kind; names { project, activity, elapsedSeconds } as far as it needs. */
    signal notice(string kind, var names)

    property Connections sessionEvents: Connections {
        target: reminders.session

        function onStarted(ts, origin, names) {
            reminders.localStart = true
            Qt.callLater(function() { reminders.localStart = false })
            const begin = origin === Ui.Session.Origin.Switch ? Notices.Begin.Switch : Notices.Begin.Start
            reminders.say(Notices.forStart(begin, reminders.session.settings), names)
        }

        function onStopped(ts, names, cause) {
            const why = cause === Ui.Session.StopCause.Idle ? Notices.Cause.Idle : Notices.Cause.Manual
            reminders.say(Notices.forStop(why, reminders.session.settings), names)
        }

        function onTrackingBegan(ts) {
            const t = reminders.session.timer
            const found = reminders.localStart ? Notices.Found.Own : Notices.Found.Elsewhere
            reminders.say(Notices.forFound(found, reminders.session.settings),
                          { project: t.project, activity: t.activity, elapsedSeconds: t.elapsedSeconds })
        }
    }

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

    function say(kind, names) {
        if (kind) {
            notice(kind, names)
        }
    }

    /** Stops the running entry for idle time: its notice says so. */
    function stopForIdle() {
        session.timer.stop(Ui.Session.StopCause.Idle)
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
        c.tracker.patchTimesheet(c.url, c.token, snap.timesheetId, { end: DTF.localDateTimeString(end) }, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Stop, result)
                return
            }
            session.timer.apply(null)
            session.entriesWritten()
            session.refresh()
            idleDiscarded(snap)
            say(Notices.forIdleDiscard(session.settings), { project: snap.projectName, activity: snap.activityName })
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
        notice(Notices.Kind.ForgotStart, {})
    }
}
