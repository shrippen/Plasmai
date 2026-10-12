import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/timerSession.js" as TimerSession
import "../../code/dateTimeFormat.js" as DTF
import ".." as Ui

/**
 * The running entry and the actions on it: start, switch, stop, continue,
 * edit, and the description typed while it runs.
 *
 *   start ──▶ tracker.startTracking ──▶ started(Start) ─▶ apply(entry) ─▶ refresh
 *   (running) start / requestRestart ──▶ Hint (same activity) | Confirm (other)
 *   saveDescription(text) ─800 ms─▶ flushDescription ─▶ patch ─▶ descriptionSaved()
 */
QtObject {
    id: timer

    property QtObject session: null

    // ── State, read only for views ──
    property var active: null
    readonly property bool tracking: !!active
    property var timesheetId: null
    property string project: ""
    property string activity: ""
    property string customer: ""
    property string description: ""
    property int elapsedSeconds: 0
    /** Customer colour of the running entry ({ color, … }, KimaiApi.barColorInfoFromTimesheet). */
    readonly property var colorInfo: KimaiApi.barColorInfoFromTimesheet(active, session.catalog.customersById)
    /** The description as typed; saved after a pause (saveDescription). */
    property string draft: ""
    property bool savingDescription: false
    readonly property bool hasLastUsed: session.settings.lastUsedProjectId.length > 0
                                        && session.settings.lastUsedActivityId.length > 0

    signal descriptionSaved()

    property Timer tickTimer: Timer {
        interval: 1000
        repeat: true
        running: timer.tracking
        onTriggered: {
            timer.elapsedSeconds++
            timer.sync()
        }
    }

    property Timer descriptionTimer: Timer {
        interval: 800
        onTriggered: timer.flushDescription()
    }

    function refresh() {
        const c = session.connection
        session.busy = true
        c.tracker.fetchActiveTimesheet(c.url, c.token, function(result) {
            session.busy = false
            c.observe(result)
            if (!result.ok) {
                session.failed(Ui.Session.Action.Refresh, result)
                return
            }
            apply(result.data && result.data.length > 0 ? result.data[0] : null)
        })
    }

    /** Shows `ts` as the running entry (null: nothing runs). */
    function apply(ts) {
        const was = tracking
        if (!ts) {
            active = null
            timesheetId = null
            project = ""
            activity = ""
            customer = ""
            description = ""
            elapsedSeconds = 0
            return
        }

        const state = TimerSession.activeState(ts, session.catalog.catalogs(), Date.now())
        // A refresh while the user types must not replace the unsaved text.
        const editing = TimerSession.editingDescription({ draft: draft, current: description,
                                                          sameEntry: was && timesheetId === ts.id })
        timesheetId = state.timesheetId
        active = ts
        project = state.project
        activity = state.activity
        customer = state.customer
        description = state.description
        if (!editing) {
            draft = description
        }
        if (state.elapsedSeconds >= 0) {
            elapsedSeconds = state.elapsedSeconds
        }
        if (!was) {
            session.trackingBegan(ts)
        }
    }

    /** The counter from the entry's begin: ticks stand still while the app is suspended. */
    function sync() {
        const begin = active && active.begin ? DTF.parseStamp(active.begin) : null
        if (begin && !isNaN(begin.getTime())) {
            elapsedSeconds = Math.max(0, Math.floor((Date.now() - begin.getTime()) / 1000))
        }
    }

    /** A timer started offline got its server id: keep following it. */
    function followId(localId, serverId) {
        if (String(timesheetId) !== String(localId)) {
            return
        }
        timesheetId = serverId
        if (active) {
            active = Object.assign({}, active, { id: serverId })
        }
    }

    /** Starts a timer; while one runs this is a restart request (Hint or Confirm). */
    function start(projectId, activityId, projectLabel, activityLabel, description, extras) {
        if (tracking) {
            return requestRestart({ project: projectId, activity: activityId, description: description || "" })
        }
        const c = session.connection
        session.busy = true
        c.tracker.startTracking(c.url, c.token, projectId, activityId, description || "", function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Start, result)
            }
            if (!result.ok || !result.data) {
                return
            }
            session.started(result.data, Ui.Session.Origin.Start, { project: projectLabel || "", activity: activityLabel || "" })
            rememberLastUsed(projectId, activityId, projectLabel, activityLabel)
            apply(session.catalog.hydrate([result.data])[0] || result.data)
            session.refresh()
        }, extras || {})
        return Ui.Session.Restart.Started
    }

    /** Stops the running entry and starts another (starts when nothing runs). */
    function switchTo(projectId, activityId, projectLabel, activityLabel, description, extras) {
        if (!session.connection.configured || session.busy) {
            return Ui.Session.Restart.Ignored
        }
        if (!tracking) {
            return start(projectId, activityId, projectLabel, activityLabel, description, extras)
        }
        const c = session.connection
        session.busy = true
        TimerSession.switchTimer(c.tracker, c.url, c.token, timesheetId,
                                 { projectId: projectId, activityId: activityId, description: description, extras: extras }, {
            stopped: function() {
                apply(null)
            },
            started: function(ts) {
                session.busy = false
                session.started(ts, Ui.Session.Origin.Switch, { project: projectLabel || "", activity: activityLabel || "" })
                rememberLastUsed(projectId, activityId, projectLabel, activityLabel)
                apply(session.catalog.hydrate([ts])[0] || ts)
                session.refresh()
            },
            failed: function(phase, result) {
                session.busy = false
                session.failed(phase === "stop" ? Ui.Session.Action.Stop : Ui.Session.Action.Switch, result)
                if (phase === "start") {
                    session.refresh()
                }
            }
        })
        return Ui.Session.Restart.Started
    }

    function stop() {
        if (!timesheetId) {
            return
        }
        const c = session.connection
        const before = active
        const names = { project: project, activity: activity }
        session.busy = true
        c.tracker.stopTracking(c.url, c.token, timesheetId, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Stop, result)
                session.refresh()
                return
            }
            session.stopped(before, names)
            apply(null)
            session.refresh()
        })
    }

    /** Restarts a stopped entry (same project, activity, description). */
    function continueEntry(ts) {
        if (!ts) {
            return
        }
        const c = session.connection
        session.busy = true
        c.tracker.restartTimesheet(c.url, c.token, ts.id, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Continue, result)
            }
            // Set the new entry now, so the refresh does not report it as started elsewhere.
            if (result.ok && result.data) {
                const entry = session.catalog.hydrate([result.data])[0] || result.data
                session.started(entry, Ui.Session.Origin.Continue,
                                { project: KimaiApi.projectName(entry), activity: KimaiApi.activityName(entry) })
                apply(entry)
            }
            session.refresh()
        })
    }

    /**
     * A tap on a Recent row: continues it when nothing runs; while one runs, Hint
     * (the same activity runs already) or Confirm (the view asks before switching).
     */
    function requestRestart(ts) {
        if (!session.connection.configured || session.busy || !ts) {
            return Ui.Session.Restart.Ignored
        }
        if (!tracking) {
            continueEntry(ts)
            return Ui.Session.Restart.Continued
        }
        if (TimerSession.sameActivity(active, ts)) {
            return Ui.Session.Restart.Hint
        }
        return Ui.Session.Restart.Confirm
    }

    /** A favorite: { projectId, activityId, projectName, activityName }. */
    function startPinned(entry) {
        if (!entry || !session.connection.configured || session.busy) {
            return Ui.Session.Restart.Ignored
        }
        if (tracking) {
            return requestRestart({ project: entry.projectId, activity: entry.activityId })
        }
        return start(entry.projectId, entry.activityId, entry.projectName, entry.activityName, "")
    }

    /** Continue-button fallback before any Recent exists. */
    function startLastUsed() {
        const s = session.settings
        if (!hasLastUsed || tracking || session.busy) {
            return
        }
        start(s.lastUsedProjectId, s.lastUsedActivityId, s.lastUsedProjectName, s.lastUsedActivityName, "")
    }

    function rememberLastUsed(projectId, activityId, projectName, activityName) {
        if (!projectId || !activityId) {
            return
        }
        session.settings.set({
            lastUsedProjectId: String(projectId), lastUsedActivityId: String(activityId),
            lastUsedProjectName: String(projectName || ""), lastUsedActivityName: String(activityName || "")
        })
    }

    /** Key of a row's "already running" hint. */
    function hintKey(ts) {
        return TimerSession.switchHintKey(ts)
    }

    /** Changes the running entry (project, activity, begin, billable, tags). */
    function patchActive(fields) {
        if (!timesheetId) {
            return
        }
        const c = session.connection
        session.busy = true
        c.tracker.patchTimesheet(c.url, c.token, timesheetId, fields, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Save, result)
                return
            }
            session.noteDropped(result)
            session.refresh()
        })
    }

    /** Typed description: saved after a pause. */
    function saveDescription(text) {
        draft = text
        descriptionTimer.restart()
    }

    /** Saves the typed description now. */
    function flushDescription() {
        if (!tracking || !timesheetId || savingDescription || draft === description) {
            return
        }
        const c = session.connection
        savingDescription = true
        // Text typed while the request runs stays unsaved (and is saved next).
        const text = draft
        c.tracker.patchTimesheet(c.url, c.token, timesheetId, { description: text }, function(result) {
            savingDescription = false
            if (result.ok) {
                description = text
                descriptionSaved()
            }
            if (draft !== text) {
                descriptionTimer.restart()
            }
        })
    }
}
