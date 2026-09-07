import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "platform/appBackend.js" as AppBackend
import "../contents/code/platform.js" as Platform
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/profiles.js" as Profiles
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/favorites.js" as Favorites
import "../contents/code/sharedConfig.js" as SharedConfig

Kirigami.ApplicationWindow {
    id: root

    // ── Dark theme colors (matching Plasmoid Breeze Dark) ──
    readonly property color bgWindow:      "#2b2d30"
    readonly property color bgSurface:     "#353739"
    readonly property color bgCard:        Qt.rgba(0.15, 0.16, 0.18, 1)
    readonly property color bgCardTracking: Qt.rgba(0.09, 0.20, 0.12, 1)
    readonly property color bgInput:       "#3d4044"
    readonly property color bgDrawer:      "#2b2d30"
    readonly property color bgDialog:      "#353739"
    readonly property color clrBorder:     "#3d4044"
    readonly property color clrBorderTracking: Qt.rgba(0.15, 0.68, 0.38, 0.35)
    readonly property color clrSeparator:  "#4a4a4a"
    readonly property color clrText:       "#e0e0e0"
    readonly property color clrTextSec:    "#9a9a9a"
    readonly property color clrTextMuted:  "#6a6a6a"
    readonly property color clrAccent:     "#27ae60"
    readonly property color clrPositive:   "#27ae60"
    readonly property color clrWarning:    "#e67e22"
    readonly property color clrDanger:     "#e74c3c"
    readonly property color clrButton:     "#3d4044"
    readonly property color clrButtonBorder: "#555555"

    title: i18n("Plasmai")
    width: 420; height: 720; visible: true
    color: bgWindow

    property var profiles: []; property var activeProfile: null
    readonly property string providerId: activeProfile && activeProfile.provider ? activeProfile.provider : "kimai"
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

    property int refreshInterval: 30; property int recentCount: 10
    property bool confirmBeforeStop: false; property bool showWorkSummary: true
    property bool showRecent: true; property bool showFavorites: true
    property string workDayBegin: "09:00"; property string workDayEnd: "17:00"

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
    readonly property color currentCustomerColor: activeTimesheet ? (KimaiApi.barColorInfoFromTimesheet(activeTimesheet, customersById).color || KimaiApi.DEFAULT_CUSTOMER_COLOR) : KimaiApi.DEFAULT_CUSTOMER_COLOR

    readonly property real todayLiveSeconds: todayTotalSeconds + (isTracking ? elapsedSeconds : 0)
    readonly property real weekLiveSeconds: weekTotalSeconds + (isTracking ? elapsedSeconds : 0)
    readonly property real remainingTodaySeconds: hasWorkContract ? (todayTargetSeconds - todayLiveSeconds) : 0
    readonly property real remainingWeekSeconds: hasWorkContract ? (weekTargetSeconds - weekLiveSeconds) : 0

    function remainingTodayText() { return remainingTodaySeconds >= 0 ? i18n("%1 left today", KimaiApi.formatDurationShort(remainingTodaySeconds)) : i18n("%1 over today", KimaiApi.formatDurationShort(-remainingTodaySeconds)) }
    function remainingWeekText() { return remainingWeekSeconds >= 0 ? i18n("%1 left this week", KimaiApi.formatDurationShort(remainingWeekSeconds)) : i18n("%1 over this week", KimaiApi.formatDurationShort(-remainingWeekSeconds)) }

    Timer { id: elapsedTimer; interval: 1000; running: root.isTracking; repeat: true; onTriggered: root.elapsedSeconds++ }
    Timer { id: refreshTimer; interval: root.refreshInterval * 1000; running: root.isConfigured && root.connectionState === "online"; repeat: true; onTriggered: root.refreshAll() }
    Timer { id: alreadyRunningHintTimer; interval: 1400; repeat: false; onTriggered: root.alreadyRunningHintKey = "" }
    Timer { id: sparklineTimer; interval: 30000; running: root.isConfigured; repeat: true; onTriggered: root.sparklineNowTick++ }
    Timer { id: descriptionSaveTimer; interval: 800; repeat: false; onTriggered: root.saveCurrentDescription() }
    Timer { id: descriptionFlashTimer; interval: 2500; repeat: false; onTriggered: root.descriptionSavedFlash = false }

    function formatElapsed(sec) { var h = Math.floor(sec / 3600); var m = Math.floor((sec % 3600) / 60); if (h > 0) return i18n("%1h %2m", h, m); return i18n("%1m %2s", m, sec % 60) }
    function currentConfig() { return { kimaiUrl: activeProfile ? (activeProfile.url || "") : "", profilesJson: profiles ? Profiles.serializeProfiles(profiles) : "", activeProfileId: activeProfile ? activeProfile.id : "default" } }
    function activityCatalog() { return allActivities }

    function loadApiToken() {
        if (!activeProfile) { apiToken = ""; tokenLoaded = true; return }
        Platform.loadToken(null, activeProfile.id).then(function(token) {
            apiToken = token || ""; tokenLoaded = true; connectionState = token ? "online" : "offline"
            if (token) refreshAll()
        }).catch(function() { apiToken = ""; tokenLoaded = true; connectionState = "error" })
    }

    function refreshAll() {
        if (!apiToken) return
        isBusy = true; var url = TimeTracker.resolveUrl(activeProfile)
        tracker.fetchActiveTimesheet(url, apiToken, function(result) {
            isBusy = false
            if (result.ok) applyActiveTimesheet(result.data && result.data.length > 0 ? result.data[0] : null)
            else { connectionState = "error"; errorMessage = result.error ? (result.error.statusText || "") : "" }
        })
        tracker.fetchRecentTimesheets(url, apiToken, recentCount, function(result) {
            if (result.ok) recentTimesheets = KimaiApi.hydrateTimesheets(KimaiApi.deduplicateRecent(result.data || []), projects, activityCatalog(), activitiesByProject)
        })
        tracker.loadProjects(url, apiToken, function(result) { if (result.ok) projects = result.data || [] })
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
        var wf = new Date(now); wf.setDate(now.getDate() - now.getDay()); wf.setHours(0, 0, 0, 0)
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
        pinnedEntries = []
        for (var i = 0; i < pinIds.length; i++) {
            var parts = pinIds[i].split(":"); var pid = parts[0] || ""; var aid = parts.length > 1 ? parts[1] : ""
            var proj = null; var act = null
            for (var p = 0; p < projects.length; p++) { if (String(projects[p].id) === pid || String(projects[p].name) === pid) { proj = projects[p]; break } }
            if (proj && aid) { for (var a = 0; a < allActivities.length; a++) { if (String(allActivities[a].id) === aid) { act = allActivities[a]; break } } }
            pinnedEntries.push({ projectId: pid, projectName: proj ? proj.name : pid, activityId: aid, activityName: act ? act.name : aid, color: proj && proj.color ? proj.color : KimaiApi.DEFAULT_CUSTOMER_COLOR })
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

    function isPinned(projectId, activityId) { return pinnedActivities.indexOf(projectId + ":" + activityId) >= 0 }

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
        tracker.stopTracking(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, function(result) {
            isBusy = false; applyActiveTimesheet(null); refreshAll()
        })
    }

    function continueRecent(ts) {
        if (!ts) return; isBusy = true
        tracker.restartTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, ts.id, function(result) {
            isBusy = false; if (result.ok) refreshAll()
        })
    }

    function patchActiveEntry(fields) {
        if (!currentTimesheetId) return; isBusy = true
        tracker.patchTimesheet(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, fields, function(result) {
            isBusy = false; if (result.ok) refreshAll()
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
            isBusy = false; if (result.ok) refreshAll()
        })
    }

    function startTracking(projectId, activityId, projectLabel, activityLabel, description) {
        if (isTracking) { requestRestartFromRecent({project: projectId, activity: activityId, description: description || ""}); return }
        isBusy = true
        tracker.startTracking(TimeTracker.resolveUrl(activeProfile), apiToken, projectId, activityId, description || "", function(result) {
            isBusy = false
            if (result.ok && result.data) { applyActiveTimesheet(KimaiApi.hydrateTimesheets([result.data], projects, activityCatalog(), activitiesByProject)[0] || result.data); refreshAll() }
        })
    }

    function switchToActivity(projectId, activityId, projectLabel, activityLabel, description) {
        if (!isConfigured || isBusy) return
        if (!isTracking) { startTracking(projectId, activityId, projectLabel, activityLabel, description); return }
        isBusy = true
        tracker.stopTracking(TimeTracker.resolveUrl(activeProfile), apiToken, currentTimesheetId, function(stopResult) {
            if (!stopResult.ok) { isBusy = false; return }
            applyActiveTimesheet(null)
            tracker.startTracking(TimeTracker.resolveUrl(activeProfile), apiToken, projectId, activityId, description || "", function(startResult) {
                isBusy = false
                if (startResult.ok && startResult.data) { applyActiveTimesheet(KimaiApi.hydrateTimesheets([startResult.data], projects, activityCatalog(), activitiesByProject)[0] || startResult.data); refreshAll() }
                else refreshAll()
            })
        })
    }

    function switchHintKey(ts) {
        var pid = KimaiApi.projectId(ts); var aid = KimaiApi.activityId(ts)
        var idPart = ts && ts.id !== undefined && ts.id !== null ? ts.id : ""
        return String(pid) + "|" + String(aid) + "|" + String(idPart)
    }

    function requestRestartFromRecent(ts) {
        if (!isConfigured || isBusy || !ts) return
        if (!isTracking) { continueRecent(ts); return }
        var pid = KimaiApi.projectId(ts); var aid = KimaiApi.activityId(ts)
        if (activeTimesheet && String(KimaiApi.projectId(activeTimesheet)) === String(pid) && String(KimaiApi.activityId(activeTimesheet)) === String(aid)) {
            alreadyRunningHintKey = switchHintKey(ts); alreadyRunningHintTimer.restart(); return
        }
        pendingSwitchTimesheet = ts; switchDialog.open()
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
                if (typeof shared.pinnedActivities === "string") pinnedActivities = shared.pinnedActivities
                if (typeof shared.workDayBegin === "string") workDayBegin = shared.workDayBegin
                if (typeof shared.workDayEnd === "string") workDayEnd = shared.workDayEnd
            }
            loadApiToken()
        })
    }

    globalDrawer: Kirigami.GlobalDrawer {
        id: globalDrawer
        title: i18n("Plasmai")
        isMenu: false
        modal: true

        background: Rectangle { color: root.bgDrawer }

        actions: [
            Kirigami.Action {
                text: i18n("Timer")
                onTriggered: { pageStack.pop(pageStack.get(0)); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Add Entry")
                onTriggered: { pageStack.push(manualPageComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Statistics")
                onTriggered: { pageStack.push(statsPageComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Connection")
                onTriggered: { pageStack.push(connectionComponent); globalDrawer.close() }
            },
            Kirigami.Action {
                text: i18n("Settings")
                onTriggered: { pageStack.push(settingsComponent); globalDrawer.close() }
            }
        ]
    }

    contextDrawer: Kirigami.ContextDrawer {
        id: contextDrawer
    }

    pageStack.initialPage: TimerPage { }
    Component.onCompleted: { Platform.setBackend(AppBackend.create(TokenStore, FileStore)); loadSharedAndConnect() }
    Component { id: manualPageComponent; ManualEntryPage { } }
    Component { id: statsPageComponent; StatsPage { } }
    Component { id: settingsComponent; SettingsPage { } }
    Component { id: connectionComponent; ConnectionPage { } }
}

