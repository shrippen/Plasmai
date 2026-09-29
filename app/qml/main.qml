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
import "../contents/code/dateTimeFormat.js" as DTF
import "../contents/code/workTotals.js" as WorkTotals
import "../contents/code/timerSession.js" as TimerSession
import "../contents/code/offline.js" as Offline
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
    // The drawer lives in the overlay, outside contentItem.
    KanteScope { target: globalDrawer.contentItem }
    KanteScope { target: globalDrawer.background }
    // Android (Material): the scope stays out, and older Kirigami colours the entries
    // from Kirigami.Theme, so the drawer gets Kante's text colour directly.
    Binding {
        target: globalDrawer.contentItem ? globalDrawer.contentItem.Kirigami.Theme : null
        property: "textColor"
        value: KanteStyle.textColor
        when: KanteStyle.materialStyle && KanteStyle.themed && !!globalDrawer.contentItem
        restoreMode: Binding.RestoreBindingOrValue
    }
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
    /** The film day is offered only with the Drehzettel plugin and its view permission, like trips. */
    readonly property bool filmDayAvailable: isConfigured && providerCapabilities.filmDays
        && filmDayMode !== FilmDaySync.Mode.NO_PLUGIN && filmDayMode !== FilmDaySync.Mode.NO_PERMISSION

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
            persist: function(part) { if (root.offlineSession) Offline.rememberFilmDays(root.offlineSession, part) },
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
        var begin = DTF.parseStamp(ts.begin)
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
    readonly property var networkStatusService: typeof networkStatus !== "undefined" ? networkStatus : null

    title: i18n("Plasmai")
    width: 420; height: 720; visible: true

    property var profiles: []; property var activeProfile: null
    readonly property string providerId: activeProfile && activeProfile.provider ? activeProfile.provider : "kimai"
    readonly property var providerMeta: TimeTracker.providerMeta(providerId)
    readonly property string tagLookupUrl: TimeTracker.resolveUrl(activeProfile)
    // Offline layer (offline.js, Kimai only): reads answer from the snapshot, writes wait in the outbox.
    property var offlineSession: null
    property int offlineRevision: 0
    readonly property var tracker: offlineSession ? offlineSession.tracker : TimeTracker.api(providerId)
    readonly property bool offline: offlineRevision >= 0 && !!offlineSession && Offline.isOffline(offlineSession)
    readonly property int unsyncedCount: offlineRevision >= 0 && offlineSession ? Offline.pendingCount(offlineSession) : 0
    readonly property double offlineStateAt: offlineRevision >= 0 && offlineSession ? Offline.stateAt(offlineSession) : 0
    readonly property int unsyncedStuck: offlineRevision >= 0 && offlineSession
        ? Offline.ops(offlineSession).filter(function(op) { return op.state !== Offline.State.PENDING }).length : 0
    /** Master data and multi-entry changes need the server (offline.js: online only). */
    readonly property bool canCreateEntities: providerCapabilities.createEntities && !offline
    function isUnsynced(entryId) { return offlineRevision >= 0 && !!offlineSession && Offline.isUnsynced(offlineSession, entryId) }
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
    // Absences, public holidays and time tracked on them (holiday / WorkContract plugin), as in the Plasmoid.
    property var workPrefs: ({}); property var weekAbsences: []; property var weekPublicHolidays: []; property var weekTimesheets: []
    property real weekAbsenceCreditSeconds: 0; property real todayAbsenceCreditSeconds: 0
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

    // Totals include the running entry up to their load (workTotals.js); add the timer's progress since.
    property real totalsElapsedAnchor: 0
    readonly property real todayLiveSeconds: todayTotalSeconds + (isTracking ? Math.max(0, elapsedSeconds - totalsElapsedAnchor) : 0)
    readonly property real weekLiveSeconds: weekTotalSeconds + (isTracking ? Math.max(0, elapsedSeconds - totalsElapsedAnchor) : 0)
    readonly property real remainingTodaySeconds: hasWorkContract ? (todayTargetSeconds - todayLiveSeconds + todayAbsenceCreditSeconds) : 0
    readonly property real remainingWeekSeconds: hasWorkContract ? (weekTargetSeconds - weekLiveSeconds + weekAbsenceCreditSeconds) : 0

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
            var v = TimerSession.verdict(idleMs, root.idleIgnoreUntilActive, idleStopMinutes)
            root.idleIgnoreUntilActive = v.ignoring
            if (v.prompt) root.promptIdle(idleMs)
        })
    }

    function promptIdle(idleMs) {
        pendingIdleMs = idleMs
        pendingIdleSince = TimerSession.idleSince(Date.now(), idleMs)
        pendingIdleSnapshot = TimerSession.snapshot(activeTimesheet, currentTimesheetId,
            { project: currentProject, activity: currentActivity, description: currentDescription })
        idleDialogPending = true
    }

    function clearPendingIdle() {
        pendingIdleSnapshot = null; pendingIdleMs = 0; pendingIdleSince = 0; idleDialogPending = false
    }

    function keepIdleTime() {
        idleIgnoreUntilActive = true
        clearPendingIdle()
    }

    function discardIdleTime(andContinue) {
        var snap = pendingIdleSnapshot
        var idleSince = pendingIdleSince > 0 ? pendingIdleSince : TimerSession.idleSince(Date.now(), pendingIdleMs)
        clearPendingIdle()
        if (!snap || !snap.timesheetId) { stopTracking(); return }
        // Stop where idle began (not "now − idle" at click time, which keeps
        // the time the dialog sat open), never before the entry's begin.
        var endDate = TimerSession.discardEnd(snap, idleSince)
        isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, snap.timesheetId,
            { end: KimaiApi.localDateTimeString(endDate) }, function(result) {
            isBusy = false
            if (!result.ok) { reportWriteError(result, i18n("Could not stop tracking")); return }
            applyActiveTimesheet(null); refreshAll()
            if (notifyOnIdleStop) sendNotification(i18n("Idle time discarded"), snap.projectName + " · " + snap.activityName)
            if (andContinue && TimerSession.canContinue(snap)) {
                startTracking(snap.projectId, snap.activityId, snap.projectName, snap.activityName, snap.description || "")
            }
        })
    }

    function checkForgotToStart() {
        var day = TimerSession.forgotToStartDay({
            enabled: notifyForgotToStart, configured: isConfigured, tracking: isTracking,
            workDayBegin: workDayBegin, workDayEnd: workDayEnd, lastDay: forgotReminderDay
        }, new Date())
        if (!day) return
        forgotReminderDay = day
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

    /** Offline session of the active profile (its own files, "app-" + profile). Resolves once loaded. */
    function openOfflineSession() {
        var key = providerId === TimeTracker.PROVIDER_KIMAI && activeProfile
            ? "app-" + String(activeProfile.id).replace(/[^A-Za-z0-9_-]/g, "_") : ""
        if (offlineSession && offlineSession.host.key === key) return Promise.resolve()
        var session = Offline.createSession(TimeTracker.api(providerId), {
            key: key,
            url: function() { return TimeTracker.resolveUrl(root.activeProfile) },
            token: function() { return root.apiToken },
            load: function(name) { return Platform.loadLocal(null, name) },
            save: function(name, obj) { return Platform.saveLocal(null, name, obj).catch(function(err) { console.warn("Plasmai: could not save", name, err) }) },
            changed: function() { root.offlineRevision++ },
            // A timer started offline got its server id: keep following it.
            idChanged: function(localId, serverId) { if (String(root.currentTimesheetId) === String(localId)) root.currentTimesheetId = serverId }
        })
        offlineSession = session
        return Offline.load(session).then(function() {
            FilmDaySync.restoreMemo(root.filmDayContext(), Offline.filmDays(session))
        })
    }

    function loadApiToken() {
        if (!activeProfile) { apiToken = ""; tokenLoaded = true; return }
        openOfflineSession().then(function() { root.readToken() })
    }

    /** The profile's token, then the first refresh (after the offline session is loaded). */
    function readToken() {
        var routedToken = KimaiApi.routeToken(activeProfile.url); // internal builds: the demo brings its own
        (routedToken ? Promise.resolve(routedToken) : Platform.loadToken(null, activeProfile.id)).then(function(token) {
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
        // The whole catalog (loadActivities needs a project and answered nothing here).
        if (typeof tracker.loadAllActivities === "function") tracker.loadAllActivities(url, apiToken, function(result) {
            if (result.ok) { activities = result.data || []; allActivities = result.data || [] }
        })
        refreshWorkTotals(); refreshPinnedEntries()
    }

    /** Totals, targets and absence credit: workTotals.js, shared with the Plasmoid. */
    function refreshWorkTotals() {
        if (!apiToken) return
        WorkTotals.load({ tracker: tracker, url: TimeTracker.resolveUrl(activeProfile), token: apiToken,
                          holidayBundle: providerCapabilities.holidayBundle }, new Date(), function(t) {
            workPrefs = t.prefs; hasWorkContract = t.hasWorkContract
            todayTargetSeconds = t.todayTargetSeconds; weekTargetSeconds = t.weekEffectiveTargetSeconds
            weekAbsences = t.absences; weekPublicHolidays = t.publicHolidays
            if (!t.entriesLoaded) return
            weekAbsenceCreditSeconds = t.weekAbsenceCreditSeconds; todayAbsenceCreditSeconds = t.todayAbsenceCreditSeconds
            weekTimesheets = t.weekEntries
            todayTimesheets = KimaiApi.hydrateTimesheets(t.todayEntries, projects, activityCatalog(), activitiesByProject)
            todayTotalSeconds = t.todaySeconds; weekTotalSeconds = t.weekSeconds
            totalsElapsedAnchor = elapsedSeconds
        })
    }

    // Favorites: favorites.js, the same pins and rows as the Plasmoid (shared setting).
    function refreshPinnedEntries() {
        var entries = Favorites.resolvePinnedEntries(pinnedActivities, projects, activitiesByProject, customersById, allActivities)
        if (JSON.stringify(entries) !== JSON.stringify(pinnedEntries)) pinnedEntries = entries
        for (var k = 0; k < entries.length; k++) {
            var pid = String(entries[k].projectId)
            if (!entries[k].activityKnown && !activitiesByProject[pid] && projects.length > 0) loadActivitiesForProject(pid, function() {})
        }
    }

    function togglePin(projectId, activityId) {
        pinnedActivities = Favorites.togglePinned(pinnedActivities, projectId, activityId)
        Platform.patchShared(null, currentConfig(), { pinnedActivities: pinnedActivities })
        refreshPinnedEntries()
    }

    function isPinned(projectId, activityId) { return Favorites.isPinned(pinnedActivities, projectId, activityId) }

    function applyActiveTimesheet(ts) {
        var wasTracking = isTracking
        if (!ts) { isTracking = false; currentTimesheetId = null; currentProject = ""; currentActivity = ""
            currentCustomer = ""; currentDescription = ""; activeTimesheet = null; elapsedSeconds = 0; return }
        var state = TimerSession.activeState(ts, sessionCatalogs(), Date.now())
        // A refresh while the user types must not replace the unsaved text.
        var editing = TimerSession.editingDescription({ draft: descriptionDraft, current: currentDescription,
                                                        sameEntry: wasTracking && currentTimesheetId === ts.id })
        isTracking = true; currentTimesheetId = state.timesheetId; activeTimesheet = ts
        currentProject = state.project
        currentActivity = state.activity
        currentCustomer = state.customer
        currentDescription = state.description
        if (!editing) descriptionDraft = currentDescription
        if (state.elapsedSeconds >= 0) elapsedSeconds = state.elapsedSeconds
        // Starts from this app set isTracking before the refresh, so only foreign timers get here.
        if (!wasTracking && notifyOnStart) sendNotification(i18n("Tracking in progress"), currentProject + " · " + currentActivity + " · " + KimaiApi.formatDurationShort(elapsedSeconds))
    }

    /** A write failed: say so instead of silently refreshing. */
    function reportWriteError(result, what) {
        if (!result || result.ok) return
        var detail = (result.error && result.error.detail) || ApiErrors.text(result.error)
        showPassiveNotification(detail ? i18n("%1: %2", what, detail) : what)
    }

    function stopTracking() {
        if (!currentTimesheetId) return
        isBusy = true
        var summary = currentProject + " · " + currentActivity
        tracker.stopTracking(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, function(result) {
            isBusy = false
            if (!result.ok) { reportWriteError(result, i18n("Could not stop tracking")); refreshAll(); return }
            if (notifyOnStop) sendNotification(i18n("Stopped"), summary)
            applyActiveTimesheet(null); refreshAll()
        })
    }

    function continueRecent(ts) {
        if (!ts) return; isBusy = true
        tracker.restartTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, function(result) {
            isBusy = false; reportWriteError(result, i18n("Could not start tracking"))
            // Set the new entry now, so the refresh does not report it as started elsewhere.
            if (result.ok && result.data) applyActiveTimesheet(KimaiApi.hydrateTimesheets([result.data], projects, activityCatalog(), activitiesByProject)[0] || result.data)
            refreshAll()
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
            isBusy = false; reportWriteError(result, i18n("Could not save the entry")); if (result.ok) { noteDroppedFields(result); refreshAll() }
        })
    }

    function deleteEntry(ts) {
        if (!ts || !ts.id) return; isBusy = true
        tracker.deleteTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, function(result) {
            isBusy = false; reportWriteError(result, i18n("Could not delete the entry")); if (result.ok) refreshAll()
        })
    }

    function editStoppedEntry(ts, fields) {
        if (!ts || !ts.id) return; isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, fields, function(result) {
            isBusy = false; reportWriteError(result, i18n("Could not save the entry")); if (result.ok) { noteDroppedFields(result); refreshAll() }
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
            if (!result.ok) { isBusy = false; reportWriteError(result, i18n("Could not split the entry")); return }
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
            reportWriteError(result, i18n("Could not start tracking"))
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
        TimerSession.switchTimer(tracker, TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId,
                                 { projectId: projectId, activityId: activityId, description: description, extras: extras }, {
            stopped: function() { applyActiveTimesheet(null) },
            started: function(ts) {
                isBusy = false
                rememberLastUsed(projectId, activityId, projectLabel, activityLabel)
                applyActiveTimesheet(KimaiApi.hydrateTimesheets([ts], projects, activityCatalog(), activitiesByProject)[0] || ts); refreshAll()
            },
            failed: function(phase, result) {
                isBusy = false
                reportWriteError(result, phase === "stop" ? i18n("Could not stop tracking") : i18n("Could not start tracking"))
                if (phase === "start") refreshAll()
            }
        })
    }

    function switchHintKey(ts) { return TimerSession.switchHintKey(ts) }
    function sessionCatalogs() { return { projects: projects, activities: allActivities, activitiesByProject: activitiesByProject, customersById: customersById } }

    function startPinned(entry) {
        if (!entry || !isConfigured || isBusy) return
        if (isTracking) { requestRestartFromRecent({ project: entry.projectId, activity: entry.activityId }); return }
        startTracking(entry.projectId, entry.activityId, entry.projectName, entry.activityName, "")
    }

    function requestRestartFromRecent(ts) {
        if (!isConfigured || isBusy || !ts) return
        if (!isTracking) { continueRecent(ts); return }
        if (TimerSession.sameActivity(activeTimesheet, ts)) {
            alreadyRunningHintKey = switchHintKey(ts); alreadyRunningHintTimer.restart(); return
        }
        pendingSwitchTimesheet = ts; switchConfirmRequested()
    }

    function formatRelativeTime(isoDate) {
        if (!isoDate) return ""
        var date = DTF.parseStamp(isoDate); if (isNaN(date.getTime())) return ""
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
        // Text typed while the request runs stays unsaved (and is saved next).
        var text = descriptionDraft
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, { description: text }, function(result) {
            savingDescription = false
            if (result.ok) { currentDescription = text; descriptionSavedFlash = true; descriptionFlashTimer.restart() }
            if (descriptionDraft !== text) descriptionSaveTimer.restart()
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

    /** Android Back, decided once per press (AndroidBackFilter in main.cpp): "handled" when it
     *  closed a drawer here, "pass" for Qt/Kirigami (an open dialog or menu, a subpage to go
     *  back from), "leave" on the first page with nothing open (the app goes to the background). */
    function androidBack() {
        if (globalDrawer.drawerOpen) { globalDrawer.drawerOpen = false; return "handled" }
        if (contextDrawer.drawerOpen) { contextDrawer.drawerOpen = false; return "handled" }
        // Open dialogs and menus sit in the overlay as popup items (next to Kirigami's
        // always visible passive-notification area, which does not count).
        var overlayItems = root.overlay ? root.overlay.children : []
        for (var i = 0; i < overlayItems.length; ++i) {
            if (overlayItems[i].visible && String(overlayItems[i]).indexOf("PopupItem") >= 0) return "pass"
        }
        if (pageStack.depth > 1 || pageStack.layers.depth > 1) return "pass"
        return "leave"
    }

    /** Kirigami's drawer button in the header has only an icon and no accessible name (screen
     *  readers and AT-SPI see an unnamed button). Name every one of them; they come and go
     *  with the pages. */
    function nameDrawerButtons(item) {
        if (!item) return
        if (String(item).indexOf("HandleButton") === 0) {
            item.Accessible.name = i18n("Menu")
        }
        var kids = item.children || []
        for (var i = 0; i < kids.length; ++i) nameDrawerButtons(kids[i])
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
        // Android: the entries take their text colour from Material, not from Kirigami.Theme.
        Material.foreground: KanteStyle.themed ? KanteStyle.textColor : (Material.theme === Material.Dark ? "#ffffff" : "#1c1b1f")
        // Sometimes the slide-in does not run (Kirigami disables the enter transition while the
        // drawer peeks under a touch): the drawer counts as open at position 0, invisible, and the
        // next tap closes it. Slide it in when it is still at 0 shortly after opening.
        onAboutToShow: slideInGuard.restart()
        Timer {
            id: slideInGuard
            interval: 350
            onTriggered: {
                if (globalDrawer.visible && globalDrawer.drawerOpen && globalDrawer.position < 0.05) {
                    slideIn.restart()
                }
            }
        }
        NumberAnimation {
            id: slideIn
            target: globalDrawer
            property: "position"
            to: 1
            duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }

        actions: [
            Kirigami.Action {
                text: i18n("Timer")
                onTriggered: { pageStack.pop(pageStack.get(0)); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("Add Entry")
                onTriggered: { root.navigateTo(manualPageComponent); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("Statistics")
                onTriggered: { root.navigateTo(statsPageComponent); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("Trips")
                visible: root.mileageAvailable
                onTriggered: { root.navigateTo(tripsPageComponent); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("Favorites")
                onTriggered: { root.navigateTo(favoritesComponent); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("Connection")
                onTriggered: { root.navigateTo(connectionComponent); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("Settings")
                onTriggered: { root.navigateTo(settingsComponent); globalDrawer.drawerOpen = false }
            },
            Kirigami.Action {
                text: i18n("About")
                onTriggered: { root.navigateTo(aboutComponent); globalDrawer.drawerOpen = false }
            }
        ]
    }

    contextDrawer: Kirigami.ContextDrawer {
        id: contextDrawer
    }

    // Actions in the top toolbar (like the Plasmoid header) instead of Kirigami's bottom bar on mobile
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.ToolBar
    pageStack.globalToolBar.showNavigationButtons: Kirigami.ApplicationHeaderStyle.ShowBackButton

    // Page headers (and their drawer buttons) are built after the page switch.
    Timer {
        id: drawerButtonNamer
        interval: 300
        onTriggered: root.nameDrawerButtons(root.contentItem)
    }
    // Back online: refresh now instead of on the next poll (which after an error can be minutes away).
    Connections {
        target: root.networkStatusService
        function onReachableChanged() { if (root.networkStatusService.reachable && root.isConfigured) root.refreshAll() }
    }
    Connections {
        target: root.pageStack
        function onCurrentItemChanged() { drawerButtonNamer.restart() }
        function onDepthChanged() { drawerButtonNamer.restart() }
    }

    // Offline and sync state under every page; "Show" lists what is not synced yet.
    footer: QQC2.Pane {
        visible: root.offline || root.unsyncedCount > 0
        padding: Kirigami.Units.smallSpacing
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        OfflineStatus {
            id: offlineBar
            anchors.fill: parent
            offline: root.offline
            stateAt: root.offlineStateAt
            unsynced: root.unsyncedCount
            stuck: root.unsyncedStuck
            onDetailsRequested: root.navigateTo(unsyncedComponent)
        }
    }

    pageStack.initialPage: TimerPage { }
    Component.onCompleted: {
        drawerButtonNamer.restart()
        Platform.setBackend(AppBackend.create(TokenStore, FileStore,
            typeof idleWatcher !== "undefined" ? idleWatcher : undefined,
            typeof notifier !== "undefined" ? notifier : undefined))
        loadSharedAndConnect()
    }
    // Internal builds only (-DPLASMAI_DEMO): the demo Kimai; published builds lack DemoHook.qml.
    Loader {
        id: demoHook
        active: typeof plasmaiDemoBuild !== "undefined" && plasmaiDemoBuild
        source: "DemoHook.qml"
        onLoaded: item.appRoot = root
    }

    Component { id: manualPageComponent; ManualEntryPage { } }
    Component { id: statsPageComponent; StatsPage { } }
    Component { id: filmDayPageComponent; FilmDayPage { } }
    Component { id: tripsPageComponent; TripsPage { } }
    Component { id: tripEditPageComponent; TripEditPage { } }
    Component { id: settingsComponent; SettingsPage { } }
    Component { id: connectionComponent; ConnectionPage { } }
    Component { id: favoritesComponent; FavoritesPage { } }
    Component { id: aboutComponent; AboutPage { } }
    Component { id: unsyncedComponent; UnsyncedPage { } }
}

