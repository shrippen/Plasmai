import QtQml
import "../code/timeTracker.js" as TimeTracker
import "../code/kimaiApi.js" as KimaiApi
import "../code/profiles.js" as Profiles
import "../code/platform.js" as Platform
import "../code/sharedConfig.js" as SharedConfig
import "../code/offline.js" as Offline
import "../code/timerSession.js" as TimerSession
import "../code/workTotals.js" as WorkTotals

/**
 * The timer session without a view (ROADMAP pillar 8, step 2): profile,
 * token, offline outbox, running entry, recents, today and this week, and
 * the actions on them. QtQml only, so the terminal client runs it without
 * a window; layouts bind to it instead of to a main.qml.
 *
 *   view (layout, TUI) ──binds──▶ Session ──▶ tracker (Offline-wrapped provider)
 *        │                          │            └─ Kimai / Clockify / Toggl / SolidTime
 *        └──calls start/stop/…──────┘──▶ Platform (shared.json, tokens, files)
 *
 * No texts: failures come as failed(action, result); the view words them.
 * Platform.setBackend() must have run before open().
 */
QtObject {
    id: session

    /** Connection states. */
    readonly property string unconfigured: "unconfigured"
    readonly property string connecting: "connecting"
    readonly property string online: "online"
    readonly property string error: "error"
    readonly property string needsSetup: "needsSetup"

    /** Actions named in failed(). */
    readonly property string actionStart: "start"
    readonly property string actionStop: "stop"
    readonly property string actionSwitch: "switch"
    readonly property string actionContinue: "continue"
    readonly property string actionRefresh: "refresh"

    // ── Inputs ──
    /** Prefix of the offline files; each client keeps its own outbox ("tui-", "app-"). */
    property string offlinePrefix: "tui-"
    property int recentCount: 10
    property int refreshSeconds: 60
    /** Work day from shared.json ("HH:MM"), for gaps and the day band. */
    property string workDayBegin: "08:00"
    property string workDayEnd: "17:00"

    // ── State, read only for views ──
    property string connection: unconfigured
    property bool busy: false
    property var profiles: []
    property var profile: null
    readonly property string providerId: profile && profile.provider ? profile.provider : TimeTracker.PROVIDER_KIMAI
    readonly property string url: TimeTracker.resolveUrl(profile)
    property var active: null
    readonly property bool tracking: !!active
    property int elapsedSeconds: 0
    property var recent: []
    property var todayEntries: []
    property var weekEntries: []
    property int todaySeconds: 0
    property int weekSeconds: 0
    property var projects: []
    property var activities: []
    property var customersById: ({})
    property int offlineRevision: 0
    readonly property bool offline: offlineRevision >= 0 && !!offlineState && Offline.isOffline(offlineState)
    readonly property int unsynced: offlineRevision >= 0 && offlineState ? Offline.pendingCount(offlineState) : 0

    signal failed(string action, var result)
    signal started(var timesheet)
    signal stopped(var timesheet)

    // ── Private ──
    property string token: ""
    property var offlineState: null
    property var totalsMemo: ({})
    readonly property var tracker: offlineState ? offlineState.tracker : TimeTracker.api(providerId)

    property Timer pollTimer: Timer {
        interval: Math.max(10, session.refreshSeconds) * 1000
        repeat: true
        running: session.connection === session.online || session.connection === session.error
        onTriggered: session.refresh()
    }

    property Timer tickTimer: Timer {
        interval: 1000
        repeat: true
        running: session.tracking
        onTriggered: session.tick()
    }

    /** Reads shared.json, picks the active profile, loads its token and refreshes. */
    function open() {
        connection = connecting
        return Platform.loadShared(null).then(function(shared) {
            // Old settings are reset by the app's or widget's own start, not here.
            if (!shared || SharedConfig.needsReset(shared)) {
                connection = needsSetup
                return
            }
            if (typeof shared.recentCount === "number") {
                recentCount = shared.recentCount
            }
            if (typeof shared.workDayBegin === "string") {
                workDayBegin = shared.workDayBegin
            }
            if (typeof shared.workDayEnd === "string") {
                workDayEnd = shared.workDayEnd
            }
            profiles = Profiles.parseProfiles(shared.profilesJson || "", shared.kimaiUrl || "")
            useProfile(Profiles.profileById(profiles, shared.activeProfileId || "default"))
        })
    }

    /** Switches to `p`: its offline outbox, its token, a refresh. */
    function useProfile(p) {
        profile = p
        active = null
        recent = []
        token = ""
        if (!p) {
            connection = unconfigured
            return Promise.resolve()
        }
        TimeTracker.applySession(providerId, p)
        return openOffline().then(readToken)
    }

    function openOffline() {
        const kimai = providerId === TimeTracker.PROVIDER_KIMAI
        const key = kimai ? offlinePrefix + String(profile.id).replace(/[^A-Za-z0-9_-]/g, "_") : ""
        offlineState = Offline.createSession(TimeTracker.api(providerId), {
            key: key,
            url: function() { return session.url },
            token: function() { return session.token },
            load: function(name) { return Platform.loadLocal(null, name) },
            save: function(name, obj) {
                return Platform.saveLocal(null, name, obj).catch(function(err) {
                    console.warn("Plasmai: could not save", name, err)
                })
            },
            changed: function() { session.offlineRevision++ },
            // A timer started offline got its server id: keep following it.
            idChanged: function(localId, serverId) {
                if (session.active && String(session.active.id) === String(localId)) {
                    session.active = Object.assign({}, session.active, { id: serverId })
                }
            }
        })
        return Offline.load(offlineState)
    }

    function readToken() {
        // Internal builds route the demo address and bring its token.
        const routed = KimaiApi.routeToken(profile.url)
        const pending = routed ? Promise.resolve(routed) : Platform.loadToken(null, profile.id)
        return pending.then(function(t) {
            token = t || ""
            connection = token ? online : unconfigured
            if (token) {
                refresh()
            }
        }, function() {
            token = ""
            connection = error
        })
    }

    /** Running entry, recents, catalogs, today and week. */
    function refresh() {
        if (!token) {
            return
        }

        tracker.fetchActiveTimesheet(url, token, function(result) {
            if (!result.ok) {
                connection = error
                failed(actionRefresh, result)
                return
            }
            connection = online
            applyActive(result.data && result.data.length > 0 ? result.data[0] : null)
        })

        tracker.fetchRecentTimesheets(url, token, recentCount, function(result) {
            if (!result.ok) {
                return
            }
            recent = hydrate(KimaiApi.deduplicateRecent(result.data || []))
        })

        tracker.loadProjects(url, token, function(result) {
            if (result.ok) {
                projects = result.data || []
            }
        })
        tracker.loadCustomers(url, token, function(result) {
            if (result.ok) {
                customersById = indexById(result.data || [])
            }
        })
        if (typeof tracker.loadAllActivities === "function") {
            tracker.loadAllActivities(url, token, function(result) {
                if (result.ok) {
                    activities = result.data || []
                }
            })
        }

        refreshTotals()
    }

    function refreshTotals() {
        const caps = TimeTracker.providerCapabilities(providerId)
        WorkTotals.load({ tracker: tracker, url: url, token: token, memo: totalsMemo,
                          holidayBundle: caps.holidayBundle }, new Date(), function(t) {
            if (!t.entriesLoaded) {
                return
            }
            weekEntries = hydrate(t.weekEntries)
            todayEntries = hydrate(t.todayEntries)
            todaySeconds = t.todaySeconds
            weekSeconds = t.weekSeconds
        })
    }

    /** Starts a timer; while one runs this switches (stop, then start). */
    function start(projectId, activityId, description) {
        if (!token || busy) {
            return
        }
        if (tracking) {
            switchTo(projectId, activityId, description)
            return
        }
        busy = true
        tracker.startTracking(url, token, projectId, activityId, description || "", function(result) {
            busy = false
            if (!result.ok || !result.data) {
                failed(actionStart, result)
                return
            }
            applyActive(result.data)
            started(active)
            refresh()
        }, {})
    }

    function switchTo(projectId, activityId, description) {
        if (!token || busy || !tracking) {
            return
        }
        busy = true
        const before = active
        TimerSession.switchTimer(tracker, url, token, active.id,
                                 { projectId: projectId, activityId: activityId, description: description || "", extras: {} }, {
            stopped: function() {
                applyActive(null)
                stopped(before)
            },
            started: function(ts) {
                busy = false
                applyActive(ts)
                started(active)
                refresh()
            },
            failed: function(phase, result) {
                busy = false
                failed(phase === "stop" ? actionStop : actionSwitch, result)
                refresh()
            }
        })
    }

    function stop() {
        if (!token || busy || !tracking) {
            return
        }
        busy = true
        const before = active
        tracker.stopTracking(url, token, active.id, function(result) {
            busy = false
            if (!result.ok) {
                failed(actionStop, result)
                refresh()
                return
            }
            applyActive(null)
            stopped(before)
            refresh()
        })
    }

    /** Restarts a stopped entry (same project, activity, description). */
    function continueEntry(timesheet) {
        if (!token || busy || !timesheet) {
            return
        }
        if (tracking) {
            switchTo(KimaiApi.projectId(timesheet), KimaiApi.activityId(timesheet), timesheet.description || "")
            return
        }
        busy = true
        tracker.restartTimesheet(url, token, timesheet.id, function(result) {
            busy = false
            if (!result.ok || !result.data) {
                failed(actionContinue, result)
                refresh()
                return
            }
            applyActive(result.data)
            started(active)
            refresh()
        })
    }

    // ── Helpers ──

    function applyActive(ts) {
        active = ts ? hydrate([ts])[0] || ts : null
        tick()
    }

    function tick() {
        if (!active) {
            elapsedSeconds = 0
            return
        }
        const state = TimerSession.activeState(active, catalogs(), Date.now())
        elapsedSeconds = Math.max(0, state.elapsedSeconds)
    }

    function catalogs() {
        return { projects: projects, activities: activities, activitiesByProject: ({}), customersById: customersById }
    }

    function hydrate(list) {
        return KimaiApi.hydrateTimesheets(list || [], projects, activities, {})
    }

    function indexById(list) {
        const out = {}
        for (let i = 0; i < list.length; i++) {
            out[String(list[i].id)] = list[i]
        }
        return out
    }
}
