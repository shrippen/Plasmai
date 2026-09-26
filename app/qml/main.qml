import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "platform/appBackend.js" as AppBackend
import "../contents/code/platform.js" as Platform
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/profiles.js" as Profiles
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/filmDays.js" as FilmDays
import "../contents/code/filmDaySync.js" as FilmDaySync
import "../contents/code/mileage.js" as Mileage
import "../contents/code/favorites.js" as Favorites
import "../contents/code/sharedConfig.js" as SharedConfig
import "../contents/code/providerUtil.js" as ProviderUtil
import "../contents/code/timesheetFields.js" as TimesheetFields
import "shared"
import "Kante"

Kirigami.ApplicationWindow {
    id: root
    signal switchConfirmRequested()
    Material.theme: Material.Dark

    // ── Visual style (shared.json visualStyle: 0 System, 1 Kante, 2 Kante Light), see Kante/KanteStyle.qml ──
    property int visualStyle: 0

    Binding {
        target: KanteStyle
        property: "kind"
        value: root.visualStyle
    }
    Binding {
        target: KanteStyle
        property: "preferDark"
        // Android always runs Material Dark (main.cpp), whatever Kirigami reports.
        value: Qt.platform.os === "android"
    }
    Binding {
        target: KanteStyle
        property: "materialStyle"
        // Android runs the Material style (main.cpp): Kante reaches Kirigami
        // through the Material colors below, not through Kirigami.Theme.
        value: Qt.platform.os === "android"
    }

    // Kante: Gruvbox ground and accent for the window, Material (Android) and
    // Kirigami (Plasma Mobile) controls. Restored when switched back; Kante Light
    // keeps the platform colors.
    KanteScope { target: root.contentItem }
    Binding { target: root; property: "color"; value: KanteStyle.backgroundColor; when: KanteStyle.themed; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: root.Material; property: "accent"; value: KanteStyle.accentColor; when: KanteStyle.themed; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: root.Material; property: "background"; value: KanteStyle.backgroundColor; when: KanteStyle.themed; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: root.Material; property: "foreground"; value: KanteStyle.textColor; when: KanteStyle.themed; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: root.Material; property: "primary"; value: KanteStyle.backgroundColor; when: KanteStyle.themed; restoreMode: Binding.RestoreBindingOrValue }

    // ── Provider capabilities (tags, billable, statistics, …) ──
    readonly property var providerCapabilities: TimeTracker.providerCapabilities(providerId)

    // ── Location (sun/moon accuracy for the day sparkline) ──
    property real latitude: 0
    property real longitude: 0
    property string locationName: ""

    // ── Behavior ──
    property bool confirmStartBeforePreviousEnd: true

    // ── Last used project/activity (Continue-button fallback before any Recent exists) ──
    property string lastUsedProjectId: ""
    property string lastUsedActivityId: ""
    property string lastUsedProjectName: ""
    property string lastUsedActivityName: ""
    readonly property bool hasLastUsed: lastUsedProjectId.length > 0 && lastUsedActivityId.length > 0

    function rememberLastUsed(projectId, activityId, projectName, activityName) {
        if (!projectId || !activityId) return
        lastUsedProjectId = String(projectId); lastUsedActivityId = String(activityId)
        lastUsedProjectName = String(projectName || ""); lastUsedActivityName = String(activityName || "")
        Platform.patchShared(null, currentConfig(), {
            lastUsedProjectId: lastUsedProjectId, lastUsedActivityId: lastUsedActivityId,
            lastUsedProjectName: lastUsedProjectName, lastUsedActivityName: lastUsedActivityName
        })
    }

    function startLastUsed() {
        if (!hasLastUsed || isTracking || isBusy) return
        startTracking(lastUsedProjectId, lastUsedActivityId, lastUsedProjectName, lastUsedActivityName, "")
    }

    // ── Film day extras (break, catering, day type, …), see filmDaySync.js ──
    // Only on the Drehzettel plugin (online only); pluginProbesJson holds the
    // per-profile probe.
    property string pluginProbesJson: ""
    readonly property var pluginProbeCache: KimaiApi.parsePluginCache(pluginProbesJson)
    property string filmDayMode: FilmDaySync.Mode.NO_PLUGIN
    property var filmDayPing: null
    /** Plain cache handed to filmDaySync (engagement lists); not reactive. */
    property var filmDayMemo: ({})
    readonly property string filmDayProfileKey: FilmDaySync.profileKey(activeProfile ? activeProfile.id : "", TimeTracker.resolveUrl(activeProfile))

    /**
     * Write data maps (pluginProbesJson) merged onto shared.json key by key,
     * so entries the Plasmoid wrote since the app loaded them are kept (B9).
     */
    function persistDataMaps(patch) {
        var bases = {}
        for (var key in patch) {
            bases[key] = root[key]
            root[key] = patch[key]
        }
        Platform.patchShared(null, currentConfig(), patch, bases).then(function(written) {
            for (var k in written) {
                if (root[k] === patch[k] && written[k] !== patch[k]) root[k] = written[k]
            }
        }, function(err) {
            console.warn("Plasmai: could not save plugin probes:", err)
        })
    }

    function filmDayContext() {
        return {
            url: TimeTracker.resolveUrl(activeProfile),
            token: apiToken,
            profileKey: filmDayProfileKey,
            mode: filmDayMode,
            ping: filmDayPing,
            memo: filmDayMemo,
            tracker: tracker
        }
    }

    /** Probe the Drehzettel plugin (cached 24 h per profile in shared.json). */
    function resolveFilmDayMode(force, callback) {
        if (!apiToken || !providerCapabilities.drehzettelApi) {
            filmDayMode = FilmDaySync.Mode.NO_PLUGIN
            if (callback) callback()
            return
        }
        FilmDaySync.resolveMode(TimeTracker.resolveUrl(activeProfile), apiToken, activeProfile ? activeProfile.id : "",
                                pluginProbeCache, { force: !!force }, function(r) {
            filmDayMode = r.mode
            filmDayPing = r.ping
            if (r.probeCache) persistDataMaps({ pluginProbesJson: JSON.stringify(r.probeCache) })
            if (callback) callback()
        })
    }

    // ── Trips (kimai-anfahrten / MileageBundle), see mileage.js ──
    property bool showTrips: true
    property string mileageState: KimaiApi.PluginState.UNKNOWN
    property var mileagePing: null
    property var mileageMeta: null
    property var mileageVehicles: []
    property string mileageProfileKey: ""
    readonly property bool mileageAvailable: isConfigured && providerCapabilities.mileage && showTrips
        && mileageState === KimaiApi.PluginState.PRESENT && KimaiApi.mileageCanView(mileagePing)
    readonly property bool canEditTrips: mileageAvailable && Mileage.can(mileagePing, "editOwn")

    /** Probe the plugin (cached 24 h per profile in pluginProbesJson); /meta and vehicles once per profile. */
    function resolveMileage(force, callback) {
        var url = TimeTracker.resolveUrl(activeProfile)
        var key = KimaiApi.pluginCacheKey(activeProfile ? activeProfile.id : "", url, KimaiApi.MILEAGE_PLUGIN)
        if (key !== mileageProfileKey) {
            mileageProfileKey = key
            mileageState = KimaiApi.PluginState.UNKNOWN
            mileagePing = null; mileageMeta = null; mileageVehicles = []
        }
        if (!apiToken || !providerCapabilities.mileage || !showTrips) {
            if (callback) callback()
            return
        }
        KimaiApi.detectMileage(url, apiToken, { cache: pluginProbeCache, key: key, force: !!force }, function(det) {
            mileageState = det.state
            mileagePing = det.data || null
            if (det.cacheEntry) persistDataMaps({ pluginProbesJson: JSON.stringify(KimaiApi.storePluginCache(pluginProbeCache, key, det.cacheEntry)) })
            if (mileageAvailable && !mileageMeta) {
                KimaiApi.fetchMileageMeta(url, apiToken, function(r) { if (r.ok) mileageMeta = r.data })
                KimaiApi.fetchVehicles(url, apiToken, function(r) { if (r.ok) mileageVehicles = r.data })
            }
            if (callback) callback()
        })
    }

    function timesheetSummaryText(ts) {
        if (!ts) return ""
        var bits = [KimaiApi.displayProjectName(ts, projects), KimaiApi.displayActivityName(ts, allActivities, activitiesByProject)]
        var begin = new Date(String(ts.begin || ""))
        if (!isNaN(begin.getTime())) bits.push(begin.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " " + begin.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
        return bits.filter(function(b) { return !!b }).join(" · ")
    }

    /** Trip page for a new trip, or linked to a Kimai entry (Recent row, running entry, travel film day). */
    function openTripForTimesheet(ts) {
        if (!canEditTrips) return
        pageStack.push(tripEditPageComponent, {
            form: ts ? Mileage.formForTimesheet(mileagePing, ts, KimaiApi.projectId) : Mileage.emptyForm(mileagePing, Mileage.dateString(new Date())),
            linkedText: timesheetSummaryText(ts)
        })
    }

    // ── Platform capability flags (native idle/notification bridge, Linux-only) ──
    readonly property bool supportsIdleDetection: typeof idleWatcher !== "undefined"
    readonly property bool supportsNotifications: typeof notifier !== "undefined"

    title: i18n("Plasmai")
    width: 420; height: 720; visible: true

    property var profiles: []; property var activeProfile: null
    readonly property string providerId: activeProfile && activeProfile.provider ? activeProfile.provider : "kimai"
    readonly property var providerMeta: TimeTracker.providerMeta(providerId)
    readonly property string tagLookupUrl: TimeTracker.resolveUrl(activeProfile)
    readonly property var tracker: TimeTracker.api(providerId)
    property string apiToken: ""; property bool tokenLoaded: false
    property bool isConfigured: apiToken.length > 0
    property string connectionState: "offline"; property string errorMessage: ""

    property bool isTracking: false; property bool isBusy: false
    property var currentTimesheetId: null
    property string currentProject: ""; property string currentActivity: ""
    property string currentCustomer: ""; property string currentDescription: ""
    property var activeTimesheet: null; property int elapsedSeconds: 0

    property var recentTimesheets: []; property var projects: []
    property var customers: []; property var customersById: ({})
    property var activities: []; property var allActivities: []
    property var activitiesByProject: ({})

    property string pinnedActivities: ""; property var pinnedEntries: []
    onProjectsChanged: refreshPinnedEntries()
    onAllActivitiesChanged: refreshPinnedEntries()
    onActivitiesByProjectChanged: refreshPinnedEntries()

    property int refreshInterval: 30; property int recentCount: 10
    property bool confirmBeforeStop: false; property bool showWorkSummary: true
    property bool showRecent: true; property bool showFavorites: true
    property string workDayBegin: "09:00"; property string workDayEnd: "17:00"
    property bool showSparkline: true; property bool showSparklineArcs: true
    property bool showContinue: true; property bool showNewActivity: true

    // ── Idle detection / notifications (native bridge on Linux, no-op on Android) ──
    property bool idleStopEnabled: false; property int idleStopMinutes: 10
    property bool notifyOnStart: true; property bool notifyOnStop: true
    property bool notifyOnIdleStop: true; property bool notifyForgotToStart: false

    property real todayTotalSeconds: 0; property real weekTotalSeconds: 0
    property real todayTargetSeconds: 0; property real weekTargetSeconds: 0
    property bool hasWorkContract: false
    property bool loadingActive: false
    property var todayTimesheets: []
    property int sparklineNowTick: 0
    property string alreadyRunningHintKey: ""
    property bool savingDescription: false
    property bool descriptionSavedFlash: false
    property string descriptionDraft: ""
    property var pendingSwitchTimesheet: null

    readonly property var lastRecent: recentTimesheets.length > 0 ? recentTimesheets[0] : null
    readonly property var currentBarColorInfo: KimaiApi.barColorInfoFromTimesheet(activeTimesheet, customersById)
    readonly property color currentCustomerColor: currentBarColorInfo.color || KimaiApi.DEFAULT_CUSTOMER_COLOR

    readonly property real todayLiveSeconds: todayTotalSeconds + (isTracking ? elapsedSeconds : 0)
    readonly property real weekLiveSeconds: weekTotalSeconds + (isTracking ? elapsedSeconds : 0)
    readonly property real remainingTodaySeconds: hasWorkContract ? (todayTargetSeconds - todayLiveSeconds) : 0
    readonly property real remainingWeekSeconds: hasWorkContract ? (weekTargetSeconds - weekLiveSeconds) : 0

    function remainingTodayText() { return remainingTodaySeconds >= 0 ? i18n("%1 left today", KimaiApi.formatDurationShort(remainingTodaySeconds)) : i18n("%1 over today", KimaiApi.formatDurationShort(-remainingTodaySeconds)) }
    function remainingWeekText() { return remainingWeekSeconds >= 0 ? i18n("%1 left this week", KimaiApi.formatDurationShort(remainingWeekSeconds)) : i18n("%1 over this week", KimaiApi.formatDurationShort(-remainingWeekSeconds)) }

    Timer { id: elapsedTimer; interval: 1000; running: root.isTracking; repeat: true; onTriggered: root.elapsedSeconds++ }
    // Keeps polling after an error too, so the app recovers by itself once the network is back.
    Timer { id: refreshTimer; interval: root.refreshInterval * 1000; running: root.isConfigured && (root.connectionState === "online" || root.connectionState === "error"); repeat: true; onTriggered: root.refreshAll() }
    Timer { id: alreadyRunningHintTimer; interval: 1400; repeat: false; onTriggered: root.alreadyRunningHintKey = "" }
    Timer { id: sparklineTimer; interval: 30000; running: root.isConfigured; repeat: true; onTriggered: root.sparklineNowTick++ }
    Timer { id: descriptionSaveTimer; interval: 800; repeat: false; onTriggered: root.saveCurrentDescription() }
    Timer { id: descriptionFlashTimer; interval: 2500; repeat: false; onTriggered: root.descriptionSavedFlash = false }
    Timer { id: idlePollTimer; interval: 60000; running: root.isTracking && root.idleStopEnabled && root.supportsIdleDetection; repeat: true; onTriggered: root.checkIdle() }
    // QML XMLHttpRequest has no timeout: abort hung requests so isBusy cannot stay stuck.
    Timer { id: requestWatchdogTimer; interval: 5000; running: true; repeat: true; onTriggered: ProviderUtil.abortStaleRequests(Date.now()) }
    Timer { id: forgotToStartTimer; interval: 300000; running: root.isConfigured && root.supportsNotifications; repeat: true; onTriggered: root.checkForgotToStart() }

    // ── Idle detection state ──
    property bool idleIgnoreUntilActive: false
    property int pendingIdleMs: 0
    // Wall-clock ms when the idle period began (detection time − idle ms).
    property double pendingIdleSince: 0
    property var pendingIdleSnapshot: null
    property bool idleDialogPending: false
    property string forgotReminderDay: ""

    function sendNotification(summary, body) {
        if (!root.supportsNotifications) return
        Platform.sendNotification(null, summary, body || "")
    }

    function checkIdle() {
        if (!isTracking || !idleStopEnabled || idleDialogPending) return
        Platform.checkIdle(null).then(function(idleMs) {
            if (idleMs < 0) return
            if (root.idleIgnoreUntilActive) {
                if (idleMs < 30000) root.idleIgnoreUntilActive = false
                return
            }
            var thresholdMs = Math.max(1, idleStopMinutes) * 60 * 1000
            if (idleMs >= thresholdMs) root.promptIdle(idleMs)
        })
    }

    function promptIdle(idleMs) {
        pendingIdleMs = idleMs
        pendingIdleSince = Date.now() - Math.max(0, idleMs)
        var beginInstant = activeTimesheet ? TimesheetFields.parseInstant(activeTimesheet.begin) : null
        pendingIdleSnapshot = {
            beginMs: beginInstant ? beginInstant.getTime() : 0,
            timesheetId: currentTimesheetId,
            projectId: activeTimesheet ? KimaiApi.projectId(activeTimesheet) : null,
            activityId: activeTimesheet ? KimaiApi.activityId(activeTimesheet) : null,
            projectName: currentProject,
            activityName: currentActivity,
            description: currentDescription
        }
        idleDialogPending = true
    }

    function keepIdleTime() {
        idleIgnoreUntilActive = true
        pendingIdleSnapshot = null; pendingIdleMs = 0; pendingIdleSince = 0; idleDialogPending = false
    }

    function discardIdleTime(andContinue) {
        var snap = pendingIdleSnapshot
        var idleSince = pendingIdleSince > 0 ? pendingIdleSince : Date.now() - Math.max(0, pendingIdleMs)
        pendingIdleSnapshot = null; pendingIdleMs = 0; pendingIdleSince = 0; idleDialogPending = false
        if (!snap || !snap.timesheetId) { stopTracking(); return }
        // Stop where idle began (not "now − idle" at click time, which keeps
        // the time the dialog sat open), never before the entry's begin.
        var endDate = new Date(Math.max(idleSince, snap.beginMs || 0))
        isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, snap.timesheetId,
            { end: KimaiApi.localDateTimeString(endDate) }, function(result) {
            isBusy = false
            if (!result.ok) return
            applyActiveTimesheet(null); refreshAll()
            if (notifyOnIdleStop) sendNotification(i18n("Idle time discarded"), snap.projectName + " · " + snap.activityName)
            if (andContinue && snap.projectId && snap.activityId) {
                startTracking(snap.projectId, snap.activityId, snap.projectName, snap.activityName, snap.description || "")
            }
        })
    }

    function checkForgotToStart() {
        if (!isConfigured || isTracking || !notifyForgotToStart) return
        if (!KimaiApi.isWithinWorkHours(workDayBegin, workDayEnd, new Date())) return
        var dayKey = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (forgotReminderDay === dayKey) return
        forgotReminderDay = dayKey
        sendNotification(i18n("Nothing is tracking"), i18n("Start tracking when you begin work."))
    }

    function formatElapsed(sec) { var h = Math.floor(sec / 3600); var m = Math.floor((sec % 3600) / 60); if (h > 0) return i18n("%1h %2m", h, m); return i18n("%1m %2s", m, sec % 60) }
    function currentConfig() { return { kimaiUrl: activeProfile ? (activeProfile.url || "") : "", profilesJson: profiles ? Profiles.serializeProfiles(profiles) : "", activeProfileId: activeProfile ? activeProfile.id : "default" } }
    function activityCatalog() { return allActivities }

    // ── Project/Activity picker models (SearchableCombo-shaped), shared by
    // ActiveEditView and ManualEntryView across pages. ──
    readonly property var projectPickerModel: KimaiApi.projectPickerItems(projects, customers)

    function projectById(projectId) {
        if (!projectId) return null
        for (var i = 0; i < projects.length; i++) {
            if (String(projects[i].id) === String(projectId)) return projects[i]
        }
        return null
    }

    /** Loads (and caches) project-scoped activities, then hands back a picker model. */
    function loadActivitiesForProject(projectId, callback) {
        if (!projectId) { callback(KimaiApi.activityPickerItems(allActivities, null, null, customersById)); return }
        var cached = activitiesByProject[String(projectId)]
        if (cached) { callback(KimaiApi.activityPickerItems(cached, projectId, root.projectById(projectId), customersById)); return }
        tracker.loadActivities(TimeTracker.resolveUrl(activeProfile), apiToken, projectId, function(result) {
            if (result.ok) {
                var copy = Object.assign({}, activitiesByProject)
                copy[String(projectId)] = result.data || []
                activitiesByProject = copy
                callback(KimaiApi.activityPickerItems(result.data || [], projectId, root.projectById(projectId), customersById))
            } else {
                callback(KimaiApi.activityPickerItems(allActivities, projectId, root.projectById(projectId), customersById))
            }
        })
    }

    function loadApiToken() {
        if (!activeProfile) { apiToken = ""; tokenLoaded = true; return }
        Platform.loadToken(null, activeProfile.id).then(function(token) {
            apiToken = token || ""; tokenLoaded = true; connectionState = token ? "online" : "offline"
            if (token) { refreshAll(); resolveFilmDayMode(false); resolveMileage(false) }
        }).catch(function() { apiToken = ""; tokenLoaded = true; connectionState = "error" })
    }

    function refreshAll() {
        if (!apiToken) return
        isBusy = true; var url = TimeTracker.resolveUrl(activeProfile)
        tracker.fetchActiveTimesheet(url, apiToken, function(result) {
            isBusy = false
            // A good answer clears an earlier error; refreshTimer only runs while "online", so without this one failed poll stopped all refreshes.
            if (result.ok) { connectionState = "online"; errorMessage = ""; applyActiveTimesheet(result.data && result.data.length > 0 ? result.data[0] : null) }
            else { connectionState = "error"; errorMessage = result.error ? (result.error.statusText || "") : "" }
        })
        tracker.fetchRecentTimesheets(url, apiToken, recentCount, function(result) {
            if (!result.ok) return
            // Only replace the model when it actually changed: a new array resets the list delegates and closes open row menus.
            var fresh = KimaiApi.hydrateTimesheets(KimaiApi.deduplicateRecent(result.data || []), projects, activityCatalog(), activitiesByProject)
            if (JSON.stringify(fresh) !== JSON.stringify(recentTimesheets)) recentTimesheets = fresh
        })
        tracker.loadProjects(url, apiToken, function(result) { if (result.ok) { projects = result.data || [] } })
        tracker.loadCustomers(url, apiToken, function(result) {
            if (result.ok) { customers = result.data || []; customersById = {}; for (var i = 0; i < customers.length; i++) customersById[String(customers[i].id)] = customers[i] }
        })
        tracker.loadActivities(url, apiToken, null, function(result) {
            if (result.ok) { activities = result.data || []; allActivities = result.data || [] }
        })
        refreshWorkTotals(); refreshPinnedEntries()
    }

    function refreshWorkTotals() {
        if (!apiToken) return; var url = TimeTracker.resolveUrl(activeProfile)
        var now = new Date(); var tf = new Date(now); tf.setHours(0, 0, 0, 0)
        var wf = KimaiApi.startOfWeekMonday(now) // Kimai weeks start on Monday, like the Plasmoid and statistics
        tracker.fetchTimesheetsRange(url, apiToken, tf, now, function(r) {
            if (r.ok) { var d = r.data || []; var t = 0; for (var i = 0; i < d.length; i++) t += d[i].duration || 0; todayTotalSeconds = t; todayTimesheets = KimaiApi.hydrateTimesheets(d, projects, activityCatalog(), activitiesByProject) }
        })
        tracker.fetchTimesheetsRange(url, apiToken, wf, now, function(r) {
            if (r.ok) { var t = 0; var d = r.data || []; for (var i = 0; i < d.length; i++) t += d[i].duration || 0; weekTotalSeconds = t }
        })
        tracker.fetchCurrentUser(url, apiToken, function(result) {
            if (result.ok) {
                var prefs = tracker.preferenceMap(result.data)
                todayTargetSeconds = tracker.workDaySecondsFromPrefs(prefs, now)
                weekTargetSeconds = tracker.workWeekSecondsFromPrefs(prefs, now)
                hasWorkContract = todayTargetSeconds > 0 || weekTargetSeconds > 0
            } else { todayTargetSeconds = 0; weekTargetSeconds = 0; hasWorkContract = false }
        })
    }

    function refreshPinnedEntries() {
        var pinStr = pinnedActivities
        if (!pinStr || pinStr.length === 0) { pinnedEntries = []; return }
        var pinIds = pinStr.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
        var entries = []
        for (var i = 0; i < pinIds.length; i++) {
            var parts = pinIds[i].split(":"); var pid = parts[0] || ""; var aid = parts.length > 1 ? parts[1] : ""
            var proj = null; var act = null
            for (var p = 0; p < projects.length; p++) { if (String(projects[p].id) === pid || String(projects[p].name) === pid) { proj = projects[p]; break } }
            if (proj && aid) { for (var a = 0; a < allActivities.length; a++) { if (String(allActivities[a].id) === aid) { act = allActivities[a]; break } } }
            if (!act && aid) { var byProj = activitiesByProject[pid] || []; for (var b = 0; b < byProj.length; b++) { if (String(byProj[b].id) === aid) { act = byProj[b]; break } } }
            entries.push({ projectId: pid, projectName: proj ? proj.name : pid, activityId: aid, activityName: act ? act.name : aid, color: proj ? KimaiApi.barColorInfo(act, proj, customersById).color : KimaiApi.DEFAULT_CUSTOMER_COLOR })
        }
        if (JSON.stringify(entries) !== JSON.stringify(pinnedEntries)) pinnedEntries = entries
        for (var k = 0; k < entries.length; k++) {
            var ePid = String(entries[k].projectId)
            if (entries[k].activityId && entries[k].activityName === entries[k].activityId && !activitiesByProject[ePid] && projects.length > 0)
                loadActivitiesForProject(ePid, function() {})
        }
    }

    function togglePin(projectId, activityId) {
        var key = projectId + ":" + activityId
        var pins = pinnedActivities ? pinnedActivities.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 }) : []
        var idx = -1; for (var i = 0; i < pins.length; i++) { if (pins[i] === key) { idx = i; break } }
        if (idx >= 0) pins.splice(idx, 1); else pins.push(key)
        pinnedActivities = pins.join(",")
        Platform.patchShared(null, currentConfig(), { pinnedActivities: pinnedActivities })
        refreshPinnedEntries()
    }

    function isPinned(projectId, activityId) {
        var key = projectId + ":" + activityId
        return pinnedActivities.split(",").some(function(s) { return s.trim() === key })
    }

    function applyActiveTimesheet(ts) {
        if (!ts) { isTracking = false; currentTimesheetId = null; currentProject = ""; currentActivity = ""
            currentCustomer = ""; currentDescription = ""; activeTimesheet = null; elapsedSeconds = 0; return }
        isTracking = true; currentTimesheetId = ts.id; activeTimesheet = ts
        currentProject = KimaiApi.displayProjectName(ts, projects)
        currentActivity = KimaiApi.displayActivityName(ts, allActivities, activitiesByProject)
        currentCustomer = KimaiApi.customerNameFromTimesheet(ts, customersById)
        currentDescription = ts.description || ""; descriptionDraft = currentDescription
        var begin = new Date(ts.begin)
        if (!isNaN(begin.getTime())) elapsedSeconds = Math.max(0, Math.floor((Date.now() - begin.getTime()) / 1000))
    }

    function stopTracking() {
        if (!currentTimesheetId) return
        isBusy = true
        var summary = currentProject + " · " + currentActivity
        tracker.stopTracking(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, function(result) {
            isBusy = false
            if (result.ok && notifyOnStop) sendNotification(i18n("Stopped"), summary)
            applyActiveTimesheet(null); refreshAll()
        })
    }

    function continueRecent(ts) {
        if (!ts) return; isBusy = true
        tracker.restartTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, function(result) {
            isBusy = false; if (result.ok) refreshAll()
        })
    }

    /** Kimai saved the entry but ignored billable (no edit_billable permission). */
    function noteDroppedFields(result) {
        if (result && result.droppedFields && result.droppedFields.indexOf("billable") >= 0) {
            showPassiveNotification(i18n("Saved without the billable change: your Kimai account is not allowed to edit billable."))
        }
    }

    function patchActiveEntry(fields) {
        if (!currentTimesheetId) return; isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, fields, function(result) {
            isBusy = false; if (result.ok) { noteDroppedFields(result); refreshAll() }
        })
    }

    function deleteEntry(ts) {
        if (!ts || !ts.id) return; isBusy = true
        tracker.deleteTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, function(result) {
            isBusy = false; if (result.ok) refreshAll()
        })
    }

    function editStoppedEntry(ts, fields) {
        if (!ts || !ts.id) return; isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, fields, function(result) {
            isBusy = false; if (result.ok) { noteDroppedFields(result); refreshAll() }
        })
    }

    /** Splits a stopped entry at splitDate: patches its end, creates a twin from there to the original end. */
    function splitEntry(ts, splitDate) {
        if (!ts || !ts.id || !splitDate) return
        // Same as the Plasmoid: split must fall inside the entry; the twin
        // keeps project/activity (write keys project/activity, not *Id),
        // description, billable and tags, with a local end stamp.
        var split = TimesheetFields.splitStoppedEntry(ts, splitDate)
        if (!split.ok) { showPassiveNotification(i18n("Split time must be between begin and end.")); return }
        isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id,
            { end: KimaiApi.localDateTimeString(split.firstEnd) }, function(result) {
            if (!result.ok) { isBusy = false; return }
            var fields = {
                project: KimaiApi.projectId(ts), activity: KimaiApi.activityId(ts),
                begin: KimaiApi.localDateTimeString(split.secondBegin),
                end: KimaiApi.localDateTimeString(split.secondEnd),
                description: split.description, billable: split.billable, tags: split.tags
            }
            tracker.createTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, fields, function(r2) {
                isBusy = false
                if (!r2.ok) { showPassiveNotification(i18n("The first half was saved, but the second half could not be created.")) }
                refreshAll()
            })
        })
    }

    function createCustomer(fields, callback) {
        isBusy = true
        tracker.createCustomer(TimeTracker.resolveUrl(activeProfile), apiToken, fields, function(result) {
            isBusy = false; if (result.ok) refreshAll(); if (callback) callback(result)
        })
    }

    function createProject(fields, callback) {
        isBusy = true
        tracker.createProject(TimeTracker.resolveUrl(activeProfile), apiToken, fields, function(result) {
            isBusy = false; if (result.ok) refreshAll(); if (callback) callback(result)
        })
    }

    function createActivity(fields, callback) {
        isBusy = true
        tracker.createActivity(TimeTracker.resolveUrl(activeProfile), apiToken, fields, function(result) {
            isBusy = false; if (result.ok) refreshAll(); if (callback) callback(result)
        })
    }

    function startTracking(projectId, activityId, projectLabel, activityLabel, description, extras) {
        if (isTracking) { requestRestartFromRecent({project: projectId, activity: activityId, description: description || ""}); return }
        isBusy = true
        tracker.startTracking(TimeTracker.resolveUrl(activeProfile), apiToken, projectId, activityId, description || "", function(result) {
            isBusy = false
            if (result.ok && result.data) {
                if (notifyOnStart) sendNotification(i18n("Started"), (projectLabel || "") + " · " + (activityLabel || ""))
                rememberLastUsed(projectId, activityId, projectLabel, activityLabel)
                applyActiveTimesheet(KimaiApi.hydrateTimesheets([result.data], projects, activityCatalog(), activitiesByProject)[0] || result.data); refreshAll()
            }
        }, extras || {})
    }

    function switchToActivity(projectId, activityId, projectLabel, activityLabel, description, extras) {
        if (!isConfigured || isBusy) return
        if (!isTracking) { startTracking(projectId, activityId, projectLabel, activityLabel, description, extras); return }
        isBusy = true
        tracker.stopTracking(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, function(stopResult) {
            if (!stopResult.ok) { isBusy = false; return }
            applyActiveTimesheet(null)
            tracker.startTracking(TimeTracker.resolveUrl(activeProfile), apiToken, projectId, activityId, description || "", function(startResult) {
                isBusy = false
                if (startResult.ok && startResult.data) {
                    rememberLastUsed(projectId, activityId, projectLabel, activityLabel)
                    applyActiveTimesheet(KimaiApi.hydrateTimesheets([startResult.data], projects, activityCatalog(), activitiesByProject)[0] || startResult.data); refreshAll()
                }
                else refreshAll()
            }, extras || {})
        })
    }

    function switchHintKey(ts) {
        var pid = KimaiApi.projectId(ts); var aid = KimaiApi.activityId(ts)
        var idPart = ts && ts.id !== undefined && ts.id !== null ? ts.id : ""
        return String(pid) + "|" + String(aid) + "|" + String(idPart)
    }

    function startPinned(entry) {
        if (!entry || !isConfigured || isBusy) return
        if (isTracking) { requestRestartFromRecent({ project: entry.projectId, activity: entry.activityId }); return }
        startTracking(entry.projectId, entry.activityId, entry.projectName, entry.activityName, "")
    }

    function requestRestartFromRecent(ts) {
        if (!isConfigured || isBusy || !ts) return
        if (!isTracking) { continueRecent(ts); return }
        var pid = KimaiApi.projectId(ts); var aid = KimaiApi.activityId(ts)
        if (activeTimesheet && String(KimaiApi.projectId(activeTimesheet)) === String(pid) && String(KimaiApi.activityId(activeTimesheet)) === String(aid)) {
            alreadyRunningHintKey = switchHintKey(ts); alreadyRunningHintTimer.restart(); return
        }
        pendingSwitchTimesheet = ts; switchConfirmRequested()
    }

    function formatRelativeTime(isoDate) {
        if (!isoDate) return ""
        var date = new Date(isoDate); if (isNaN(date.getTime())) return ""
        var diffSec = Math.floor((Date.now() - date.getTime()) / 1000)
        if (diffSec < 60) return i18n("just now")
        var diffMin = Math.floor(diffSec / 60)
        if (diffMin < 60) return i18n("%1m ago", diffMin)
        var diffHour = Math.floor(diffMin / 60)
        if (diffHour < 24) return i18n("%1h ago", diffHour)
        var diffDay = Math.floor(diffHour / 24)
        if (diffDay === 1) return i18n("yesterday")
        return i18n("%1d ago", diffDay)
    }

    function saveCurrentDescription() {
        if (!isTracking || !currentTimesheetId) return
        if (savingDescription) return
        if (descriptionDraft === currentDescription) return
        savingDescription = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, { description: descriptionDraft }, function(result) {
            savingDescription = false
            if (result.ok) { currentDescription = descriptionDraft; descriptionSavedFlash = true; descriptionFlashTimer.restart() }
        })
    }

    function saveDescription(text) {
        descriptionDraft = text
        descriptionSaveTimer.restart()
    }

    function loadSharedAndConnect() {
        Platform.loadShared(null).then(function(shared) {
            if (shared) SharedConfig.applyToConfiguration(currentConfig(), shared)
            profiles = Profiles.parseProfiles(shared ? shared.profilesJson : "", shared ? shared.kimaiUrl : "")
            activeProfile = Profiles.profileById(profiles, shared ? shared.activeProfileId : "default")
            if (shared) {
                if (typeof shared.refreshInterval === "number") refreshInterval = shared.refreshInterval
                if (typeof shared.recentCount === "number") recentCount = shared.recentCount
                if (typeof shared.confirmBeforeStop === "boolean") confirmBeforeStop = shared.confirmBeforeStop
                if (typeof shared.popupShowWorkSummary === "boolean") showWorkSummary = shared.popupShowWorkSummary
                if (typeof shared.popupShowRecent === "boolean") showRecent = shared.popupShowRecent
                if (typeof shared.popupShowFavorites === "boolean") showFavorites = shared.popupShowFavorites
                if (typeof shared.popupShowContinue === "boolean") showContinue = shared.popupShowContinue
                if (typeof shared.popupShowNewActivity === "boolean") showNewActivity = shared.popupShowNewActivity
                if (typeof shared.pinnedActivities === "string") pinnedActivities = shared.pinnedActivities
                if (typeof shared.workDayBegin === "string") workDayBegin = shared.workDayBegin
                if (typeof shared.workDayEnd === "string") workDayEnd = shared.workDayEnd
                if (typeof shared.popupShowSparkline === "boolean") showSparkline = shared.popupShowSparkline
                if (typeof shared.showSparklineArcs === "boolean") showSparklineArcs = shared.showSparklineArcs
                if (typeof shared.latitude === "number") latitude = shared.latitude
                if (typeof shared.longitude === "number") longitude = shared.longitude
                if (typeof shared.locationName === "string") locationName = shared.locationName
                if (typeof shared.confirmStartBeforePreviousEnd === "boolean") confirmStartBeforePreviousEnd = shared.confirmStartBeforePreviousEnd
                if (typeof shared.idleStopEnabled === "boolean") idleStopEnabled = shared.idleStopEnabled
                if (typeof shared.idleStopMinutes === "number") idleStopMinutes = shared.idleStopMinutes
                if (typeof shared.notifyOnStart === "boolean") notifyOnStart = shared.notifyOnStart
                if (typeof shared.notifyOnStop === "boolean") notifyOnStop = shared.notifyOnStop
                if (typeof shared.notifyOnIdleStop === "boolean") notifyOnIdleStop = shared.notifyOnIdleStop
                if (typeof shared.notifyForgotToStart === "boolean") notifyForgotToStart = shared.notifyForgotToStart
                if (typeof shared.lastUsedProjectId === "string") lastUsedProjectId = shared.lastUsedProjectId
                if (typeof shared.pluginProbesJson === "string") pluginProbesJson = shared.pluginProbesJson
                if (typeof shared.showTrips === "boolean") showTrips = shared.showTrips
                if (typeof shared.visualStyle === "number") visualStyle = shared.visualStyle
                if (typeof shared.lastUsedActivityId === "string") lastUsedActivityId = shared.lastUsedActivityId
                if (typeof shared.lastUsedProjectName === "string") lastUsedProjectName = shared.lastUsedProjectName
                if (typeof shared.lastUsedActivityName === "string") lastUsedActivityName = shared.lastUsedActivityName
            }
            loadApiToken()
        })
    }

    /** Drawer navigation is flat: return to the timer page first so pages don't stack up. */
    function navigateTo(component) {
        if (pageStack.depth > 1) pageStack.pop(pageStack.get(0))
        pageStack.push(component)
    }

    globalDrawer: Kirigami.GlobalDrawer {
        id: globalDrawer
        title: i18n("Plasmai")
        isMenu: false
        modal: true

        actions: [
            Kirigami.Action {
                text: i18n("Timer")
                onTriggered: { pageStack.pop(pageStack.get(0)); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Add Entry")
                onTriggered: { root.navigateTo(manualPageComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Statistics")
                onTriggered: { root.navigateTo(statsPageComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Trips")
                visible: root.mileageAvailable
                onTriggered: { root.navigateTo(tripsPageComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Favorites")
                onTriggered: { root.navigateTo(favoritesComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Connection")
                onTriggered: { root.navigateTo(connectionComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Settings")
                onTriggered: { root.navigateTo(settingsComponent); globalDrawer.close() }
            }
        ]
    }

    contextDrawer: Kirigami.ContextDrawer {
        id: contextDrawer
    }

    // Actions in the top toolbar (like the Plasmoid header) instead of Kirigami's bottom bar on mobile
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.ToolBar
    pageStack.globalToolBar.showNavigationButtons: Kirigami.ApplicationHeaderStyle.ShowBackButton

    pageStack.initialPage: TimerPage { }
    Component.onCompleted: {
        Platform.setBackend(AppBackend.create(TokenStore, FileStore,
            typeof idleWatcher !== "undefined" ? idleWatcher : undefined,
            typeof notifier !== "undefined" ? notifier : undefined))
        loadSharedAndConnect()
    }
    Component { id: manualPageComponent; ManualEntryPage { } }
    Component { id: statsPageComponent; StatsPage { } }
    Component { id: filmDayPageComponent; FilmDayPage { } }
    Component { id: tripsPageComponent; TripsPage { } }
    Component { id: tripEditPageComponent; TripEditPage { } }
    Component { id: settingsComponent; SettingsPage { } }
    Component { id: connectionComponent; ConnectionPage { } }
    Component { id: favoritesComponent; FavoritesPage { } }
}

