import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../code/kimaiApi.js" as KimaiApi
import "../code/timeTracker.js" as TimeTracker
import "../code/secret.js" as Secret
import "../code/platform.js" as Platform
import "../code/desktopBackend.js" as DesktopBackend
import "../code/profiles.js" as Profiles
import "../code/favorites.js" as Favorites
import "../code/sharedConfig.js" as SharedConfig
import "../code/catalogCache.js" as CatalogCache
import "../code/buildInfo.js" as BuildInfo
import "../code/timesheetFields.js" as TimesheetFields
import "../code/filmDays.js" as FilmDays
import "../code/filmDaySync.js" as FilmDaySync
import "../code/mileage.js" as Mileage
import "../code/statsData.js" as StatsData
import "../code/providerUtil.js" as ProviderUtil
import "."
import "Kante"
import "KantePlasma"

PlasmoidItem {
    id: root

    Binding {
        target: TouchUi
        property: "preference"
        value: plasmoid.configuration.touchMode
    }

    Binding {
        target: KanteStyle
        property: "kind"
        value: plasmoid.configuration.visualStyle
    }

    readonly property var invalidTimesheetId: null
    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/kwallet.sh"))
    readonly property string idleScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/idle.sh"))
    readonly property string notifyScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/notify.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/sharedConfig.sh"))
    readonly property string catalogCacheScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/catalogCache.sh"))

    property var profiles: Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl)
    property var activeProfile: Profiles.profileById(profiles, plasmoid.configuration.activeProfileId || "default")
    readonly property string providerId: (activeProfile && activeProfile.provider)
        ? activeProfile.provider : "kimai"
    readonly property var providerMeta: TimeTracker.providerMeta(providerId)
    readonly property var providerCapabilities: TimeTracker.providerCapabilities(providerId)
    readonly property var tracker: TimeTracker.api(providerId)
    property string kimaiUrl: TimeTracker.resolveUrl(activeProfile || { url: plasmoid.configuration.kimaiUrl, provider: providerId })
    property string apiToken: ""
    property bool tokenLoaded: false
    property bool isConfigured: apiToken.length > 0 && (!providerMeta.needsUrl || kimaiUrl.length > 0)
    property string mainViewMode: "main"  // main | manual | stats | filmday | trip
    /** Inline editor for the running timesheet (start / project / activity). */
    property bool editingActiveEntry: false
    /** Stopped Recent timesheet currently in the Add-entry form (null = new entry). */
    property var editingStoppedTimesheet: null
    property bool credentialsLoading: false
    property var pendingCredentialCallbacks: []

    property bool isTracking: false
    property bool isBusy: false
    property var lastError: null
    property string connectionState: "offline"
    property bool loadingActive: false
    property bool loadingRecent: false
    property bool loadingProjects: false
    property bool loadingPinned: false
    property string userMessage: ""
    /** Transient hint key for "already tracking" feedback on Recent and Favorite rows. */
    property string alreadyRunningHintKey: ""

    property var currentTimesheetId: invalidTimesheetId
    property string currentProject: ""
    property string currentActivity: ""
    property string currentCustomer: ""
    property string currentDescription: ""
    /** Last active timesheet object (for re-resolving names after catalog load). */
    property var activeTimesheet: null
    /** Recent entry waiting for switch confirmation while a timer is running. */
    property var pendingSwitchTimesheet: null
    property var pendingDeleteTimesheet: null
    property var pendingSplitTimesheet: null
    /** Dialogs live inside fullRepresentation; keep refs so root JS can open them. */
    property var stopConfirmDialogRef: null
    property var switchRecentDialogRef: null
    property var deleteConfirmDialogRef: null
    property var splitEntryDialogRef: null
    property var idleDialogRef: null
    property var createEntityDialogRef: null
    property var switchPickersRef: null
    property var manualEntryViewRef: null
    property var tripSheetRef: null
    property var activeEditViewRef: null
    property var filmDayViewRef: null
    property var descriptionFieldRef: null
    property int pendingIdleMs: 0
    // Wall-clock ms when the idle period began (detection time − idle ms).
    property double pendingIdleSince: 0
    property bool idleIgnoreUntilActive: false
    property var pendingIdleSnapshot: null
    property string forgotReminderDay: ""
    property int elapsedSeconds: 0
    /** Bumps DaySparkline live edge; kept coarse to avoid per-second canvas work. */
    property int sparklineNowTick: 0
    property var recentTimesheets: []
    property var projects: []
    property var customers: []
    property var customersById: ({})
    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activities: []
    property var allActivities: []
    property var pinnedEntries: []
    property var activitiesByProject: ({})
    property var selectedProjectId: null
    /** Shared open direction for project + activity pickers (true = below). */
    property bool pickerOpenBelow: true
    property bool showNewActivityForm: false
    property bool savingDescription: false
    property bool suppressDescHandler: false
    property bool descriptionSavedFlash: false
    /** 1 while the success check is held, then animated to 0. */
    property real descriptionSaveFlashOpacity: 1
    /** True when the description field differs from the last saved/server value. */
    property bool descriptionDirty: false
    /** Draft text from the description field (avoids fragile id lookups from root). */
    property string descriptionDraft: ""
    /** Focus tracked from the field itself (root cannot read descriptionEdit.id). */
    property bool descriptionFieldFocused: false
    /** High-chroma positive for the description-save check (theme hue, boosted sat). */
    readonly property color descriptionSaveSuccessColor: {
        var base = KanteStyle.positiveTextColor
        var hue = (base.hslHue >= 0 && !isNaN(base.hslHue)) ? base.hslHue : 0.33
        var lightBg = KanteStyle.backgroundColor.hslLightness > 0.5
        return Qt.hsla(hue, 0.95, lightBg ? 0.34 : 0.62, 1)
    }
    /** Theme positive is already loud; the circle uses a desaturated sibling. */
    readonly property color descriptionSaveMutedColor: {
        var base = KanteStyle.positiveTextColor
        var hue = (base.hslHue >= 0 && !isNaN(base.hslHue)) ? base.hslHue : 0.33
        var lightBg = KanteStyle.backgroundColor.hslLightness > 0.5
        return Qt.hsla(hue, 0.38, lightBg ? 0.36 : 0.46, 1)
    }

    property int todaySeconds: 0
    property int weekSeconds: 0
    property int todayTargetSeconds: 0
    property int weekTargetSeconds: 0
    /** Contract week target minus approved vacation/public holidays. */
    property int weekEffectiveTargetSeconds: 0
    property var weekAbsences: []
    property var weekPublicHolidays: []
    property var weekTimesheetsForCredit: []
    property int weekAbsenceCreditSeconds: 0
    property int todayAbsenceCreditSeconds: 0
    property bool hasWorkContract: false
    property int totalsElapsedAnchor: 0
    property string currentCustomerColor: KimaiApi.DEFAULT_CUSTOMER_COLOR
    property var workPrefs: ({})
    property var todayTimesheets: []
    /** Extended timesheet cache for the statistics view (multiple weeks). */
    property var statsTimesheets: []
    property var statsRangeBeginMs: 0
    property var statsRangeEndMs: 0
    property bool loadingStats: false
    property var filmDaySelectedDate: new Date()
    /** The Kimai entry for filmDaySelectedDate + the picked project, if any. */
    property var filmDayTimesheet: null
    property bool loadingFilmDay: false
    property int filmDayLoadSerial: 0
    /** Where film-day extras live for the active profile (FilmDaySync.Mode), see filmDaySync.js. */
    property string filmDayMode: FilmDaySync.Mode.NO_PLUGIN
    /** Last Drehzettel ping body (features, permissions), or null. */
    property var filmDayPing: null
    /** Film-day JSON the next save diffs against (server mode). */
    property var filmDayServer: null
    property string filmDayLoadMode: ""
    /** Plain cache handed to filmDaySync (engagement lists); not reactive. */
    property var filmDayMemo: ({})
    readonly property var pluginProbeCache: KimaiApi.parsePluginCache(plasmoid.configuration.pluginProbesJson)
    // ── Trips (kimai-anfahrten / MileageBundle), see mileage.js ──
    /** KimaiApi.PluginState of /api/mileage/ping for the active profile. */
    property string mileageState: KimaiApi.PluginState.UNKNOWN
    property var mileagePing: null
    property var mileageMeta: null
    property var mileageVehicles: []
    /** Open trip suggestions (Dawarich), shown above Recent. */
    property var tripSuggestions: []
    property double tripSuggestionsLoadedAt: 0
    property bool tripBusy: false
    /** Suggestion being edited in the trip sheet before accepting it, or null. */
    property var tripSheetSuggestion: null
    /** Trips of this week and month for the statistics (null = not loaded / no plugin). */
    property var statsTrips: null
    readonly property bool mileageAvailable: isConfigured && providerCapabilities.mileage
        && plasmoid.configuration.showTrips !== false
        && mileageState === KimaiApi.PluginState.PRESENT && KimaiApi.mileageCanView(mileagePing)
    readonly property bool canEditTrips: mileageAvailable && Mileage.can(mileagePing, "editOwn")
    readonly property string filmDayProfileKey: FilmDaySync.profileKey(activeProfile ? activeProfile.id : "", kimaiUrl)
    readonly property string workDayBegin: {
        var v = plasmoid.configuration.workDayBegin
        return (v && String(v).length > 0) ? String(v) : KimaiApi.DEFAULT_WORK_DAY_BEGIN
    }
    readonly property string workDayEnd: {
        var v = plasmoid.configuration.workDayEnd
        return (v && String(v).length > 0) ? String(v) : KimaiApi.DEFAULT_WORK_DAY_END
    }

    readonly property bool compactPopupLayout:
        plasmoid.formFactor === PlasmaCore.Types.Horizontal
        || plasmoid.formFactor === PlasmaCore.Types.Vertical

    readonly property bool showWorkSummaryHere: compactPopupLayout
        ? plasmoid.configuration.popupShowWorkSummary
        : plasmoid.configuration.desktopShowWorkSummary
    readonly property bool showSparklineHere: compactPopupLayout
        ? plasmoid.configuration.popupShowSparkline
        : plasmoid.configuration.desktopShowSparkline
    readonly property bool showFavoritesHere: compactPopupLayout
        ? plasmoid.configuration.popupShowFavorites
        : plasmoid.configuration.desktopShowFavorites
    readonly property bool showRecentHere: compactPopupLayout
        ? plasmoid.configuration.popupShowRecent
        : plasmoid.configuration.desktopShowRecent
    readonly property bool showContinueHere: compactPopupLayout
        ? plasmoid.configuration.popupShowContinue
        : true
    readonly property bool showNewActivityHere: compactPopupLayout
        ? plasmoid.configuration.popupShowNewActivity
        : plasmoid.configuration.desktopShowNewActivity

    readonly property string panelProjectLabel: {
        if (!isTracking) {
            return ""
        }
        var showProject = plasmoid.configuration.showProjectInPanel
        var showActivity = plasmoid.configuration.showActivityInPanel
        if (showProject && showActivity && currentProject && currentActivity) {
            return currentProject + " · " + currentActivity
        }
        if (showActivity && currentActivity) {
            return currentActivity
        }
        if (showProject && currentProject) {
            return currentProject
        }
        return ""
    }

    readonly property var panelPills: KimaiApi.panelPillInfo(
        activeTimesheet, projects, customersById)

    readonly property int todayLiveSeconds:
        todaySeconds + (isTracking ? Math.max(0, elapsedSeconds - totalsElapsedAnchor) : 0)
    readonly property int weekLiveSeconds:
        weekSeconds + (isTracking ? Math.max(0, elapsedSeconds - totalsElapsedAnchor) : 0)
    readonly property int remainingWeekSeconds: hasWorkContract
        ? (weekEffectiveTargetSeconds - weekLiveSeconds + weekAbsenceCreditSeconds)
        : 0
    readonly property int remainingTodaySeconds: hasWorkContract
        ? (todayTargetSeconds - todayLiveSeconds + todayAbsenceCreditSeconds)
        : 0

    readonly property var lastRecent: recentTimesheets.length > 0 ? recentTimesheets[0] : null
    readonly property bool hasLastUsed: {
        var pid = String(plasmoid.configuration.lastUsedProjectId || "")
        var aid = String(plasmoid.configuration.lastUsedActivityId || "")
        return pid.length > 0 && aid.length > 0
    }
    readonly property int recentVisibleCount: Math.min(
        Math.max(1, plasmoid.configuration.recentCount),
        recentTimesheets.length)
    readonly property int favoritesVisibleCount: compactPopupLayout
        ? Math.min(pinnedEntries.length, 6)
        : pinnedEntries.length

    readonly property var activitySectionTitles: ({
        "project": i18n("Project-specific"),
        "global": i18n("Global activities")
    })

    readonly property string errorMessage: userMessage.length > 0 ? userMessage : ApiErrors.text(lastError)
    readonly property bool showSetupState: tokenLoaded && !isConfigured
    readonly property bool showErrorState: errorMessage.length > 0 && connectionState === "error"

    function dismissPickerPopups() {
        if (root.switchPickersRef) {
            root.switchPickersRef.closePickers()
        }
        if (root.manualEntryViewRef) {
            root.manualEntryViewRef.closePickers()
        }
        if (root.activeEditViewRef) {
            root.activeEditViewRef.closePickers()
        }
        if (root.filmDayViewRef) {
            root.filmDayViewRef.closePickers()
        }
    }

    function updatePickerOpenDirection(projectField, activityField) {
        var projectPicker = projectField
            || (root.switchPickersRef ? root.switchPickersRef.projectCombo : null)
        var activityPicker = activityField
            || (root.switchPickersRef ? root.switchPickersRef.activityCombo : null)
        if (!projectPicker || !activityPicker) {
            return
        }

        var fallbackIdeal = TouchUi.pickerEntryHeight * TouchUi.pickerDirectionEntries
        var ideal = Math.max(fallbackIdeal,
                             projectPicker.directionThresholdHeight(),
                             activityPicker.directionThresholdHeight())
        var spaceBelow = activityPicker.spaceBelow()
        // Upward opening is limited by the lower field; don't use the upper field's
        // (often much larger) space-above measurement.
        var spaceAbove = Math.min(projectPicker.spaceAbove(), activityPicker.spaceAbove())

        // Prefer below when it fits; open above only when below is too tight.
        var decidedOpenBelow
        if (spaceBelow >= ideal) {
            decidedOpenBelow = true
        } else if (spaceAbove >= ideal) {
            decidedOpenBelow = false
        } else {
            decidedOpenBelow = spaceBelow >= spaceAbove
        }

        pickerOpenBelow = decidedOpenBelow
    }

    // Panel: compact icon; desktop: full widget (so display settings apply in-place).
    preferredRepresentation: compactPopupLayout ? compactRepresentation : fullRepresentation
    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14


    Plasmoid.icon: connectionState === "error" ? "network-disconnect"
                     : isTracking ? "media-record" : "chronometer"
    // Keep stable: Plasma's config dialog title is "Settings for %1" / Plasmoid.title.
    Plasmoid.title: i18n("Plasmai")

    toolTipMainText: isTracking ? currentProject + " · " + currentActivity : i18n("Plasmai")
    toolTipTextFormat: Text.PlainText
    toolTipSubText: {
        if (!tokenLoaded) {
            return i18n("Loading…")
        }
        if (!isConfigured) {
            return i18n("Not configured — right-click to configure")
        }
        if (connectionState === "error" && errorMessage) {
            return errorMessage
        }
        return panelTooltipBody()
    }

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    Timer {
        id: elapsedTimer
        interval: 1000
        running: root.isTracking
        repeat: true
        onTriggered: root.elapsedSeconds++
    }

    // QML XMLHttpRequest has no timeout: abort requests that hang so
    // isBusy / loading flags cannot stay stuck.
    Timer {
        id: requestWatchdogTimer
        interval: 5000
        running: true
        repeat: true
        onTriggered: ProviderUtil.abortStaleRequests(Date.now())
    }

    Timer {
        id: sparklineRefreshTimer
        interval: 30000
        running: root.expanded && root.isConfigured && root.showSparklineHere
        repeat: true
        onTriggered: root.sparklineNowTick++
    }

    Timer {
        id: pollTimer
        interval: Math.max(10, plasmoid.configuration.refreshInterval) * 1000
        running: root.isConfigured && root.connectionState !== "connecting"
        repeat: true
        onTriggered: {
            root.refreshActiveTimesheet(true)
            root.refreshWorkTotals()
            // Keep the project / activity / customer catalog current so new
            // entities created in the Kimai web UI appear without requiring
            // a plasmoid restart.  refreshProjects checks CatalogCache.isFresh()
            // internally, so the API is hit at most every FRESH_MS (10 min).
            root.refreshProjects(true, false)
        }
    }

    Timer {
        id: sharedConfigPollTimer
        interval: 5000
        running: !root.credentialsLoading && root.tokenLoaded
        repeat: true
        onTriggered: {
            Platform.loadShared(execSource).then(function(shared) {
                if (!shared) return
                var newProfileId = shared.activeProfileId || "default"
                var newProfilesJson = shared.profilesJson || ""
                var changed = false
                if (newProfileId !== (plasmoid.configuration.activeProfileId || "default")) {
                    changed = true
                }
                if (newProfilesJson !== (plasmoid.configuration.profilesJson || "")) {
                    changed = true
                }
                if (changed) {
                    SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                    root.softReload()
                }
            })
        }
    }

    Timer {
        id: idleTimer
        interval: 60000
        running: root.isTracking && plasmoid.configuration.idleStopEnabled && root.isConfigured
        repeat: true
        onTriggered: root.checkIdle()
    }

    Timer {
        id: forgotReminderTimer
        interval: 5 * 60 * 1000
        running: root.isConfigured && !root.isTracking && plasmoid.configuration.notifyForgotToStart
        repeat: true
        onTriggered: root.checkForgotToStart()
    }

    Timer {
        id: descriptionSavedFlashTimer
        interval: 2200
        repeat: false
        onTriggered: descriptionSavedFade.start()
    }

    NumberAnimation {
        id: descriptionSavedFade
        target: root
        property: "descriptionSaveFlashOpacity"
        to: 0
        duration: 700
        easing.type: Easing.InCubic
        onFinished: {
            if (root.descriptionSaveFlashOpacity <= 0.05) {
                root.descriptionSavedFlash = false
                root.descriptionSaveFlashOpacity = 1
            }
        }
    }

    Timer {
        id: alreadyRunningHintTimer
        interval: 1400
        repeat: false
        onTriggered: root.alreadyRunningHintKey = ""
    }

    function formatRelativeTime(isoDate) {
        if (!isoDate) {
            return ""
        }
        var date = new Date(isoDate)
        if (isNaN(date.getTime())) {
            return ""
        }
        var diffSec = Math.floor((Date.now() - date.getTime()) / 1000)
        if (diffSec < 60) {
            return i18n("just now")
        }
        var diffMin = Math.floor(diffSec / 60)
        if (diffMin < 60) {
            return i18np("%1 minute ago", "%1 minutes ago", diffMin)
        }
        var diffHour = Math.floor(diffMin / 60)
        if (diffHour < 24) {
            return i18np("%1 hour ago", "%1 hours ago", diffHour)
        }
        var diffDay = Math.floor(diffHour / 24)
        if (diffDay === 1) {
            return i18n("yesterday")
        }
        if (diffDay < 7) {
            return i18np("%1 day ago", "%1 days ago", diffDay)
        }
        return date.toLocaleDateString(Qt.locale())
    }

    function connectionIcon() {
        if (!isConfigured) {
            return "network-disconnect"
        }
        if (connectionState === "connecting") {
            return "view-refresh"
        }
        if (connectionState === "error") {
            return "dialog-error"
        }
        return "network-connect"
    }

    function connectionLabel() {
        if (!isConfigured) {
            return i18n("Not configured")
        }
        if (connectionState === "connecting") {
            return i18n("Connecting to %1…", kimaiUrl)
        }
        if (connectionState === "error") {
            return i18n("Connection problem")
        }
        var profileName = activeProfile ? activeProfile.name : ""
        return profileName.length > 0
               ? i18n("Connected to %1 (%2)", kimaiUrl, profileName)
               : i18n("Connected to %1", kimaiUrl)
    }

    function setError(error) {
        lastError = error || null
        if (error) {
            connectionState = "error"
        }
    }

    function clearError() {
        lastError = null
        userMessage = ""
        if (isConfigured) {
            connectionState = "online"
        }
    }

    /** Kimai saved the entry but ignored billable (no edit_billable permission). */
    function noteDroppedFields(result) {
        if (result && result.droppedFields && result.droppedFields.indexOf("billable") >= 0) {
            userMessage = i18n("Saved without the billable change: your Kimai account is not allowed to edit billable.")
        }
    }

    function openConfigure() {
        var action = plasmoid.internalAction("configure")
        if (action) {
            action.trigger()
            return
        }
        // Fallback for older Plasma APIs
        action = plasmoid.action("configure")
        if (action) {
            action.trigger()
        }
    }

    /** Build and show the same applet context menu Plasma would (custom + system actions). */
    function openPlasmoidContextMenu(visualParent, x, y) {
        plasmoidContextMenu.visualParent = visualParent
        plasmoidContextMenu.rebuild()
        plasmoidContextMenu.open(x, y)
    }

    function sendNotification(summary, body) {
        Platform.sendNotification(execSource, summary, body || "")
    }

    function checkIdle() {
        if (!isTracking || !plasmoid.configuration.idleStopEnabled || plasmoid.userConfiguring) {
            return
        }
        if (idleDialogRef && idleDialogRef.visible) {
            return
        }
        Platform.checkIdle(execSource).then(function(idleMs) {
            if (idleMs < 0) {
                return
            }
            if (root.idleIgnoreUntilActive) {
                if (idleMs < 30000) {
                    root.idleIgnoreUntilActive = false
                }
                return
            }
            var idleMinutes = parseInt(plasmoid.configuration.idleStopMinutes, 10)
            if (isNaN(idleMinutes) || idleMinutes < 1) {
                idleMinutes = 1
            }
            var thresholdMs = idleMinutes * 60 * 1000
            if (idleMs >= thresholdMs) {
                root.promptIdle(idleMs)
            }
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
        expanded = true
        if (idleDialogRef) {
            idleDialogRef.open()
        } else {
            stopTracking(true)
        }
    }

    function keepIdleTime() {
        idleIgnoreUntilActive = true
        pendingIdleSnapshot = null
        pendingIdleMs = 0
        pendingIdleSince = 0
    }

    function discardIdleTime(andContinue) {
        var snap = pendingIdleSnapshot
        var idleSince = pendingIdleSince > 0 ? pendingIdleSince : Date.now() - Math.max(0, pendingIdleMs)
        pendingIdleSnapshot = null
        pendingIdleMs = 0
        pendingIdleSince = 0
        if (!snap || !snap.timesheetId) {
            stopTracking(true)
            return
        }
        // Stop where idle began (not "now − idle" at click time, which would
        // keep the time the dialog sat open), never before the entry's begin.
        var endMs = Math.max(idleSince, snap.beginMs || 0)
        var endDate = new Date(endMs)
        if (!tracker || typeof tracker.patchTimesheet !== "function") {
            stopTracking(true)
            return
        }
        isBusy = true
        lastError = null
        tracker.patchTimesheet(kimaiUrl, apiToken, snap.timesheetId, {
            end: KimaiApi.localDateTimeString(endDate)
        }, function(result) {
            isBusy = false
            if (!result || !result.ok) {
                setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
                return
            }
            clearError()
            resetTrackingState()
            refreshRecentTimesheets()
            refreshWorkTotals()
            if (plasmoid.configuration.notifyOnIdleStop) {
                sendNotification(
                    i18n("Idle time discarded"),
                    snap.projectName + " · " + snap.activityName)
            }
            if (andContinue && snap.projectId && snap.activityId) {
                startTracking(snap.projectId, snap.activityId, snap.projectName, snap.activityName, snap.description || "")
            }
        })
    }

    function checkForgotToStart() {
        if (!isConfigured || isTracking || plasmoid.userConfiguring) {
            return
        }
        if (!plasmoid.configuration.notifyForgotToStart) {
            return
        }
        if (!KimaiApi.isWithinWorkHours(plasmoid.configuration.workDayBegin, plasmoid.configuration.workDayEnd, new Date())) {
            return
        }
        var dayKey = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (forgotReminderDay === dayKey) {
            return
        }
        forgotReminderDay = dayKey
        sendNotification(
            i18n("Nothing is tracking"),
            i18n("Work hours have started. Start a timer when you begin."))
    }

    function rememberLastUsed(projectId, activityId, projectName, activityName) {
        if (plasmoid.userConfiguring || !projectId || !activityId) {
            return
        }
        plasmoid.configuration.lastUsedProjectId = String(projectId)
        plasmoid.configuration.lastUsedActivityId = String(activityId)
        plasmoid.configuration.lastUsedProjectName = String(projectName || "")
        plasmoid.configuration.lastUsedActivityName = String(activityName || "")
        Platform.patchShared(execSource, plasmoid.configuration, {
            lastUsedProjectId: plasmoid.configuration.lastUsedProjectId,
            lastUsedActivityId: plasmoid.configuration.lastUsedActivityId,
            lastUsedProjectName: plasmoid.configuration.lastUsedProjectName,
            lastUsedActivityName: plasmoid.configuration.lastUsedActivityName
        })
    }

    function startLastUsed() {
        if (!hasLastUsed || isTracking || isBusy) {
            return
        }
        startTracking(
            plasmoid.configuration.lastUsedProjectId,
            plasmoid.configuration.lastUsedActivityId,
            plasmoid.configuration.lastUsedProjectName || "",
            plasmoid.configuration.lastUsedActivityName || "",
            "")
    }

    function openCreateEntity(mode) {
        if (!providerCapabilities.createEntities || !createEntityDialogRef) {
            return
        }
        var projectName = ""
        if (root.switchPickersRef && root.switchPickersRef.projectCombo.currentItem) {
            projectName = root.switchPickersRef.projectCombo.currentItem.label || ""
        }
        createEntityDialogRef.selectedProjectId = selectedProjectId
        createEntityDialogRef.selectedProjectName = projectName
        createEntityDialogRef.customers = customers
        createEntityDialogRef.resetForMode(mode)
        expanded = true
        createEntityDialogRef.open()
    }

    function submitCreateEntity(mode, payload) {
        if (!tracker || !payload) {
            return
        }
        isBusy = true
        lastError = null
        userMessage = ""
        var fields = payload
        if (mode === "customer" && typeof tracker.createCustomer === "function") {
            fields.customers = customers
            tracker.createCustomer(kimaiUrl, apiToken, fields, function(result) {
                isBusy = false
                if (result && result.ok) {
                    clearError()
                    refreshProjects(false, true)
                    sendNotification(i18n("Customer created"), payload.name)
                } else {
                    setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
                }
            })
            return
        }
        if (mode === "project" && typeof tracker.createProject === "function") {
            tracker.createProject(kimaiUrl, apiToken, fields, function(result) {
                isBusy = false
                if (result && result.ok && result.data) {
                    clearError()
                    var newId = result.data.id
                    refreshProjects(false, true)
                    Qt.callLater(function() {
                        selectProjectById(newId, null)
                    })
                    sendNotification(i18n("Project created"), payload.name)
                } else {
                    setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
                }
            })
            return
        }
        if (mode === "activity" && typeof tracker.createActivity === "function") {
            tracker.createActivity(kimaiUrl, apiToken, fields, function(result) {
                isBusy = false
                if (result && result.ok && result.data) {
                    clearError()
                    var aid = result.data.id
                    var pid = fields.project
                    refreshProjects(false, true)
                    Qt.callLater(function() {
                        selectProjectById(pid, aid)
                    })
                    sendNotification(i18n("Activity created"), payload.name)
                } else {
                    setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
                }
            })
            return
        }
        isBusy = false
    }

    function syncTrackerSession() {
        TimeTracker.applySession(providerId, activeProfile)
    }

    function openManualEntry() {
        if (!isConfigured) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = null
        mainViewMode = "manual"
        if (projectPickerModel.length === 0) {
            refreshProjects(false)
        }
        if (root.manualEntryViewRef) {
            root.manualEntryViewRef.resetDefaults()
        }
    }

    function openStoppedEdit(timesheet) {
        if (!isConfigured || !timesheet) {
            return
        }
        if (isTracking && timesheet.id !== undefined && timesheet.id !== null
                && String(timesheet.id) === String(currentTimesheetId)) {
            openActiveEdit()
            return
        }
        if (!providerCapabilities.editStopped) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = timesheet
        mainViewMode = "manual"
        if (projectPickerModel.length === 0) {
            refreshProjects(false)
        }
        Qt.callLater(function() {
            if (root.manualEntryViewRef
                    && root.editingStoppedTimesheet) {
                root.manualEntryViewRef.loadFromTimesheet(root.editingStoppedTimesheet)
            }
        })
    }

    function openActiveEdit() {
        if (!isConfigured || !isTracking || !activeTimesheet) {
            return
        }
        editingActiveEntry = true
        if (projectPickerModel.length === 0) {
            refreshProjects(false)
        }
        // Prefill once the editor is visible (also handled by ActiveEditView.onVisibleChanged).
        Qt.callLater(function() {
            if (editingActiveEntry && root.activeEditViewRef) {
                root.activeEditViewRef.loadFromTimesheet(root.activeTimesheet)
            }
        })
    }

    function closeActiveEdit() {
        editingActiveEntry = false
    }

    function saveActiveEdit(projectId, activityId, beginText, billable, tags) {
        if (!isTracking || isBusy) {
            return
        }
        if (currentTimesheetId === invalidTimesheetId || currentTimesheetId === undefined
            || currentTimesheetId === null || currentTimesheetId === "") {
            return
        }
        if (!tracker || typeof tracker.patchTimesheet !== "function") {
            setError({ type: "config", status: 0, detail: i18n("This provider cannot update the running entry.") })
            return
        }
        function parseLocalStamp(text) {
            var s = String(text || "").trim().replace(" ", "T")
            if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s)) {
                s += ":00"
            }
            return new Date(s)
        }
        var beginDate = parseLocalStamp(beginText)
        if (isNaN(beginDate.getTime())) {
            userMessage = i18n("Enter a valid start date/time.")
            return
        }
        if (beginDate.getTime() > Date.now() + 60 * 1000) {
            userMessage = i18n("Start must not be in the future.")
            return
        }
        isBusy = true
        lastError = null
        userMessage = ""
        tracker.patchTimesheet(kimaiUrl, apiToken, currentTimesheetId, {
            begin: KimaiApi.localDateTimeString(beginDate),
            project: projectId,
            activity: activityId,
            billable: typeof billable === "boolean" ? billable : undefined,
            tags: tags || []
        }, function(result) {
            isBusy = false
            if (result && result.ok) {
                clearError()
                noteDroppedFields(result)
                editingActiveEntry = false
                if (result.data) {
                    var hydrated = KimaiApi.hydrateTimesheets(
                        [result.data], root.projects, root.activityCatalog(), root.activitiesByProject)
                    applyActiveTimesheet(hydrated[0] || result.data)
                } else {
                    refreshActiveTimesheet(true)
                }
                refreshRecentTimesheets(true)
                refreshWorkTotals()
            } else {
                setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
            }
        })
    }

    function openStatsView() {
        if (!isConfigured || !providerCapabilities.statistics) {
            return
        }
        mainViewMode = "stats"
        refreshWorkTotals()
        loadStatsTrips()
        // Prefetch a few weeks so day/week switchers work immediately.
        var now = new Date()
        var begin = KimaiApi.startOfWeekMonday(now)
        begin.setDate(begin.getDate() - 7 * 4)
        loadStatsRange(begin, KimaiApi.endOfWeekSunday(now))
    }

    /**
     * Ensure statsTimesheets covers [beginDate, endDate]. Fetches when needed.
     */
    function loadStatsRange(beginDate, endDate) {
        if (!isConfigured || !beginDate || !endDate) {
            return
        }
        var bMs = beginDate.getTime()
        var eMs = endDate.getTime()
        if (statsRangeBeginMs && statsRangeEndMs
            && bMs >= statsRangeBeginMs && eMs <= statsRangeEndMs
            && statsTimesheets.length > 0) {
            rehydrateStatsTimesheets()
            return
        }
        var fetchBegin = new Date(statsRangeBeginMs && statsRangeBeginMs < bMs ? statsRangeBeginMs : bMs)
        var fetchEnd = new Date(statsRangeEndMs && statsRangeEndMs > eMs ? statsRangeEndMs : eMs)
        // Pad to full weeks
        fetchBegin = KimaiApi.startOfWeekMonday(fetchBegin)
        fetchEnd = KimaiApi.endOfWeekSunday(fetchEnd)
        loadingStats = true
        tracker.fetchTimesheetsRange(kimaiUrl, apiToken, fetchBegin, fetchEnd, function(result) {
            loadingStats = false
            if (result.ok) {
                statsTimesheets = KimaiApi.hydrateTimesheets(
                    result.data || [], root.projects,
                    root.activityCatalog(),
                    root.activitiesByProject)
                statsRangeBeginMs = fetchBegin.getTime()
                statsRangeEndMs = fetchEnd.getTime()
            }
        })
    }

    function rehydrateStatsTimesheets() {
        if (!statsTimesheets || statsTimesheets.length === 0) {
            return
        }
        statsTimesheets = KimaiApi.hydrateTimesheets(
            statsTimesheets, root.projects,
            root.activityCatalog(),
            root.activitiesByProject)
    }

    function returnToMainView() {
        mainViewMode = "main"
        editingStoppedTimesheet = null
        filmDayTimesheet = null
        tripSheetSuggestion = null
        dismissPickerPopups()
    }

    function openFilmDayView() {
        if (!isConfigured || !providerCapabilities.filmDays) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = null
        mainViewMode = "filmday"
        if (projectPickerModel.length === 0) {
            refreshProjects(false)
        }
        // Load only once the mode is known (plugin present or not).
        loadingFilmDay = true
        resolveFilmDayMode(false, function() {
            loadFilmDayForDate(filmDaySelectedDate)
        })
    }

    function stepFilmDay(deltaDays) {
        var next = new Date(filmDaySelectedDate)
        next.setDate(next.getDate() + deltaDays)
        loadFilmDayForDate(next)
    }

    /**
     * Write data maps (pluginProbesJson). They are merged onto shared.json
     * key by key, so entries the app wrote meanwhile are kept (B9); the merged
     * result becomes the in-memory value unless it changed again in between.
     */
    function persistDataMaps(patch) {
        var bases = {}
        var key
        for (key in patch) {
            bases[key] = plasmoid.configuration[key]
            plasmoid.configuration[key] = patch[key]
        }
        Platform.patchShared(execSource, plasmoid.configuration, patch, bases).then(function(written) {
            for (var k in written) {
                if (plasmoid.configuration[k] === patch[k] && written[k] !== patch[k]) {
                    plasmoid.configuration[k] = written[k]
                }
            }
        }, function(err) {
            console.warn("Plasmai: could not save plugin probes:", err)
        })
    }

    /** Context for filmDaySync.js calls. */
    function filmDayContext() {
        return {
            url: kimaiUrl,
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
        if (!isConfigured || !providerCapabilities.drehzettelApi) {
            filmDayMode = FilmDaySync.Mode.NO_PLUGIN
            if (callback) callback()
            return
        }
        FilmDaySync.resolveMode(kimaiUrl, apiToken, activeProfile ? activeProfile.id : "", pluginProbeCache,
                                { force: !!force }, function(r) {
            filmDayMode = r.mode
            filmDayPing = r.ping
            if (r.probeCache) {
                persistDataMaps({ pluginProbesJson: JSON.stringify(r.probeCache) })
            }
            if (callback) callback()
        })
    }

    function projectOfId(projectId) {
        for (var i = 0; i < (projects || []).length; i++) {
            if (String(projects[i].id) === String(projectId)) {
                return projects[i]
            }
        }
        return null
    }

    /** Loads the Kimai entry and film-day extras for `date` into the Filmday view. */
    function loadFilmDayForDate(date) {
        filmDaySelectedDate = date
        if (!isConfigured) {
            return
        }
        var selectedProjectIdForDay = (root.filmDayViewRef
            && root.filmDayViewRef.projectCombo.currentIndex >= 0)
            ? root.filmDayViewRef.projectCombo.currentItem.value.id : null
        loadingFilmDay = true
        // Only the latest load may fill the view (fast day steps / project picks).
        var serial = ++filmDayLoadSerial
        tracker.fetchTimesheetsRange(
            kimaiUrl, apiToken, KimaiApi.startOfLocalDay(date), KimaiApi.endOfLocalDay(date),
            function(result) {
                if (serial !== filmDayLoadSerial) {
                    return
                }
                var entries = (result && result.ok) ? KimaiApi.hydrateTimesheets(
                    result.data || [], root.projects, root.activityCatalog(), root.activitiesByProject) : []
                var match = FilmDays.pickDayEntry(entries, selectedProjectIdForDay, KimaiApi.projectId)
                var dateStr = KimaiApi.localDateString(date)
                var entryProjectId = match ? KimaiApi.projectId(match) : selectedProjectIdForDay
                var others = FilmDays.otherDayEntries(entries, match, entryProjectId, KimaiApi.projectId)
                // P5: the engagement is checked per project + day (film-day GET answers 404 without one).
                FilmDaySync.loadDay(root.filmDayContext(), entryProjectId, dateStr, function(day) {
                    if (serial !== filmDayLoadSerial) {
                        return
                    }
                    loadingFilmDay = false
                    filmDayTimesheet = match
                    filmDayServer = day.server
                    filmDayLoadMode = day.mode
                    if (day.mode === FilmDaySync.Mode.SERVER && filmDayMode === FilmDaySync.Mode.OFFLINE) {
                        filmDayMode = FilmDaySync.Mode.SERVER
                    }
                    if (!root.filmDayViewRef) {
                        return
                    }
                    root.filmDayViewRef.applyLoadedDay(date, match, day,
                        KimaiApi.customerCurrencyOfProject(root.projectOfId(entryProjectId), root.customers),
                        others)
                })
            })
    }

    function saveFilmDay(projectId, activityId, beginText, endText, filmDayFields) {
        if (!isConfigured || isBusy) {
            return
        }
        function parseLocalStamp(text) {
            var s = String(text || "").trim().replace(" ", "T")
            if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s)) {
                s += ":00"
            }
            return new Date(s)
        }
        var beginDate = parseLocalStamp(beginText)
        var endDate = parseLocalStamp(endText)
        if (isNaN(beginDate.getTime()) || isNaN(endDate.getTime())) {
            userMessage = i18n("Enter valid begin and end date/time.")
            return
        }
        if (endDate.getTime() <= beginDate.getTime()) {
            userMessage = i18n("End must be after begin.")
            return
        }
        isBusy = true
        lastError = null
        userMessage = ""
        var dateStr = KimaiApi.localDateString(root.filmDaySelectedDate)
        var view = (root.filmDayViewRef) ? root.filmDayViewRef : null
        var breakMinutes = (view && view.extrasVisible) ? view.effectiveBreakMinutes : 0
        // B3: the other entries of the project on this day, deleted after a successful save.
        var mergeIds = (view && view.mergeOthers) ? view.otherEntryIds() : []
        FilmDaySync.saveDay(filmDayContext(), {
            projectId: projectId,
            dateStr: dateStr,
            existingId: FilmDays.saveTargetId(filmDayTimesheet, projectId, KimaiApi.projectId),
            timesheetFields: {
                begin: KimaiApi.localDateTimeString(beginDate),
                end: KimaiApi.localDateTimeString(endDate),
                project: projectId,
                activity: activityId
            },
            fields: filmDayFields,
            server: filmDayServer,
            dayMode: filmDayLoadMode
        }, function(result) {
            isBusy = false
            if (!result.ok) {
                setError(result.error)
                return
            }
            clearError()
            function finish(deleteReport) {
                var messages = []
                if (result.extras === "failed") {
                    messages.push(i18n("Begin and end were saved, but the film day extras were not: %1",
                                       (result.error && result.error.detail) || ApiErrors.text(result.error)))
                }
                if (deleteReport && deleteReport.failed.length > 0) {
                    messages.push(i18np("%1 other entry of this day could not be deleted: %2",
                                        "%1 other entries of this day could not be deleted: %2",
                                        deleteReport.failed.length, ApiErrors.text(deleteReport.failed[0].error)))
                }
                if (messages.length > 0) {
                    userMessage = messages.join(" ")
                }
                refreshRecentTimesheets()
                refreshWorkTotals()
                sendNotification(
                    i18n("Shooting day saved"),
                    KimaiApi.formatDuration(FilmDays.workSecondsFromSpan(
                        beginDate.getTime(), endDate.getTime(), breakMinutes)))
                loadFilmDayForDate(root.filmDaySelectedDate)
            }
            if (mergeIds.length > 0) {
                FilmDaySync.deleteEntries(filmDayContext(), mergeIds, finish)
            } else {
                finish(null)
            }
        })
    }

    // ── Trips (kimai-anfahrten) ──────────────────────────────────────────

    /** Probe the plugin (cached 24 h per profile in pluginProbesJson), then load /meta and vehicles once. */
    function resolveMileage(force, callback) {
        if (!isConfigured || !providerCapabilities.mileage || plasmoid.configuration.showTrips === false) {
            mileageState = KimaiApi.PluginState.UNKNOWN
            mileagePing = null
            if (callback) callback()
            return
        }
        var profileId = activeProfile ? activeProfile.id : ""
        var key = KimaiApi.pluginCacheKey(profileId, kimaiUrl, KimaiApi.MILEAGE_PLUGIN)
        KimaiApi.detectMileage(kimaiUrl, apiToken, { cache: pluginProbeCache, key: key, force: !!force }, function(det) {
            mileageState = det.state
            mileagePing = det.data || null
            if (det.cacheEntry) {
                persistDataMaps({ pluginProbesJson: JSON.stringify(KimaiApi.storePluginCache(pluginProbeCache, key, det.cacheEntry)) })
            }
            if (mileageAvailable && !mileageMeta) {
                KimaiApi.fetchMileageMeta(kimaiUrl, apiToken, function(r) {
                    if (r.ok) mileageMeta = r.data
                })
                KimaiApi.fetchVehicles(kimaiUrl, apiToken, function(r) {
                    if (r.ok) mileageVehicles = r.data
                })
            }
            if (callback) callback()
        })
    }

    function resetMileageState() {
        mileageState = KimaiApi.PluginState.UNKNOWN
        mileagePing = null
        mileageMeta = null
        mileageVehicles = []
        tripSuggestions = []
        tripSuggestionsLoadedAt = 0
        statsTrips = null
    }

    /** Open suggestions of the last 14 days, at most every 10 minutes unless forced (A5, lazy). */
    function loadTripSuggestions(force) {
        if (!canEditTrips || !Mileage.profileOf(mileagePing).dawarichConfigured) {
            tripSuggestions = []
            return
        }
        if (!force && Date.now() - tripSuggestionsLoadedAt < 10 * 60 * 1000) {
            return
        }
        tripSuggestionsLoadedAt = Date.now()
        var range = null
        if (Mileage.hasFeature(mileagePing, "dateRange")) {
            var from = new Date()
            from.setDate(from.getDate() - 14)
            range = { from: Mileage.dateString(from), to: Mileage.dateString(new Date()) }
        }
        KimaiApi.fetchTripSuggestions(kimaiUrl, apiToken, range, function(r) {
            if (r.ok) {
                tripSuggestions = r.data
            }
        })
    }

    function refreshMileage() {
        resolveMileage(false, function() {
            if (root.expanded) {
                loadTripSuggestions(false)
            }
        })
    }

    function timesheetSummaryText(ts) {
        if (!ts) {
            return ""
        }
        var bits = [KimaiApi.displayProjectName(ts, root.projects),
                    KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject)]
        var begin = new Date(String(ts.begin || ""))
        if (!isNaN(begin.getTime())) {
            bits.push(begin.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " "
                      + begin.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
        }
        return bits.filter(function(b) { return !!b }).join(" · ")
    }

    /** Show the trip sheet (mainViewMode "trip"). */
    function openTripSheet(form, original, linkedText, suggestion) {
        if (!mileageAvailable) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = null
        tripSheetSuggestion = suggestion || null
        mainViewMode = "trip"
        if (root.tripSheetRef) {
            root.tripSheetRef.load(form, original || null, linkedText || "", !!suggestion)
        }
    }

    function openNewTrip() {
        openTripSheet(Mileage.emptyForm(mileagePing, Mileage.dateString(new Date())), null, "")
    }

    /** A3: trip linked to a Kimai entry (Recent row or the running entry). */
    function openTripForTimesheet(ts) {
        if (!ts) {
            return
        }
        openTripSheet(Mileage.formForTimesheet(mileagePing, ts, KimaiApi.projectId), null, timesheetSummaryText(ts))
    }

    function tripSaved(message) {
        tripBusy = false
        tripSheetSuggestion = null
        returnToMainView()
        if (message) {
            sendNotification(i18n("Trip saved"), message)
        }
        statsTrips = null
        loadTripSuggestions(true)
    }

    function tripFailed(error) {
        tripBusy = false
        if (!root.tripSheetRef) {
            return
        }
        root.tripSheetRef.serverErrors = (error && error.fields) ? error.fields : ({})
        root.tripSheetRef.errorText = (error && error.detail) ? error.detail : ApiErrors.text(error)
    }

    function saveTrip(body, tripId, form) {
        if (!canEditTrips || tripBusy) {
            return
        }
        tripBusy = true
        if (tripSheetSuggestion) {
            var sg = tripSheetSuggestion
            KimaiApi.acceptTripSuggestion(kimaiUrl, apiToken, sg.id, Mileage.acceptBodyFromForm(mileagePing, form, sg), function(r) {
                if (r.ok) {
                    tripSaved(i18n("%1 km", Mileage.displayKm(Mileage.tripKm(r.data))))
                } else {
                    tripFailed(r.error)
                }
            })
            return
        }
        if (tripId !== null && tripId !== undefined) {
            if (Mileage.isEmptyBody(body)) {
                tripSaved("")
                return
            }
            KimaiApi.patchTrip(kimaiUrl, apiToken, tripId, body, function(r) {
                if (r.ok) tripSaved(i18n("%1 km", Mileage.displayKm(Mileage.tripKm(r.data))))
                else tripFailed(r.error)
            })
            return
        }
        KimaiApi.createTrip(kimaiUrl, apiToken, body, function(r) {
            if (r.ok) tripSaved(i18n("%1 km", Mileage.displayKm(Mileage.tripKm(r.data))))
            else tripFailed(r.error)
        })
    }

    function deleteTrip(tripId) {
        if (!mileageAvailable || tripBusy) {
            return
        }
        tripBusy = true
        KimaiApi.deleteTrip(kimaiUrl, apiToken, tripId, function(r) {
            if (r.ok) {
                tripSaved("")
            } else {
                tripFailed(r.error)
            }
        })
    }

    function removeSuggestion(sg) {
        tripSuggestions = tripSuggestions.filter(function(x) { return x.id !== sg.id })
    }

    /** A5: accept a detected trip as suggested. */
    function acceptTripSuggestion(sg) {
        if (!canEditTrips || tripBusy || !sg) {
            return
        }
        tripBusy = true
        KimaiApi.acceptTripSuggestion(kimaiUrl, apiToken, sg.id, {}, function(r) {
            tripBusy = false
            if (r.ok || (r.error && r.error.status === 409)) {
                // 409: accepted or dismissed elsewhere meanwhile.
                removeSuggestion(sg)
                statsTrips = null
            } else {
                userMessage = i18n("The trip could not be accepted: %1", (r.error && r.error.detail) || ApiErrors.text(r.error))
            }
        })
    }

    function dismissTripSuggestion(sg) {
        if (!canEditTrips || tripBusy || !sg) {
            return
        }
        tripBusy = true
        KimaiApi.dismissTripSuggestion(kimaiUrl, apiToken, sg.id, function(r) {
            tripBusy = false
            if (r.ok) {
                removeSuggestion(sg)
            } else {
                userMessage = i18n("The trip could not be dismissed: %1", (r.error && r.error.detail) || ApiErrors.text(r.error))
            }
        })
    }

    /** A6: trips of this week and month for the statistics summary. */
    function loadStatsTrips() {
        if (!mileageAvailable) {
            statsTrips = null
            return
        }
        var now = new Date()
        var range = Mileage.hasFeature(mileagePing, "dateRange") ? StatsData.tripRangeFor(now) : { year: now.getFullYear() }
        KimaiApi.fetchTrips(kimaiUrl, apiToken, range, function(r) {
            statsTrips = r.ok ? r.data : null
        })
    }

    function createManualEntry(projectId, activityId, beginText, endText, description, billable, tags) {
        if (!isConfigured || isBusy) {
            return
        }
        function parseLocalStamp(text) {
            var s = String(text || "").trim().replace(" ", "T")
            if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s)) {
                s += ":00"
            }
            var d = new Date(s)
            return d
        }
        var beginDate = parseLocalStamp(beginText)
        var endDate = parseLocalStamp(endText)
        if (isNaN(beginDate.getTime()) || isNaN(endDate.getTime())) {
            userMessage = i18n("Enter valid begin and end date/time.")
            return
        }
        if (endDate.getTime() <= beginDate.getTime()) {
            userMessage = i18n("End must be after begin.")
            return
        }
        isBusy = true
        lastError = null
        userMessage = ""
        var fields = {
            begin: KimaiApi.localDateTimeString(beginDate),
            end: KimaiApi.localDateTimeString(endDate),
            project: projectId,
            activity: activityId,
            description: description || "",
            billable: typeof billable === "boolean" ? billable : undefined,
            tags: tags || []
        }
        var editing = editingStoppedTimesheet
        var editingId = editing && editing.id
        function finishSave(result, added) {
            isBusy = false
            if (result.ok) {
                clearError()
                returnToMainView()
                noteDroppedFields(result)
                refreshRecentTimesheets()
                refreshWorkTotals()
                sendNotification(
                    added ? i18n("Entry added") : i18n("Entry updated"),
                    description || (added ? i18n("Manual time entry") : i18n("Timesheet updated")))
            } else {
                setError(result.error)
            }
        }
        if (editingId !== undefined && editingId !== null && editingId !== "") {
            if (!tracker || typeof tracker.patchTimesheet !== "function") {
                isBusy = false
                setError({ type: "config", status: 0, detail: i18n("This provider cannot update stopped entries.") })
                return
            }
            tracker.patchTimesheet(kimaiUrl, apiToken, editingId, fields, function(result) {
                finishSave(result, false)
            })
            return
        }
        tracker.createTimesheet(kimaiUrl, apiToken, fields, function(result) {
            finishSave(result, true)
        })
    }

    function reloadProfiles() {
        profiles = Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl)
        activeProfile = Profiles.profileById(profiles, plasmoid.configuration.activeProfileId || "default")
    }

    function reloadCredentials(callback) {
        if (callback) {
            pendingCredentialCallbacks.push(callback)
        }
        if (credentialsLoading) {
            return
        }
        credentialsLoading = true
        Platform.loadShared(execSource).then(function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            } else if ((plasmoid.configuration.kimaiUrl || "").length > 0
                       || (plasmoid.configuration.profilesJson || "").length > 0) {
                // Migrate this instance's connection settings into the shared store.
                persistSharedConfig()
            }
            reloadProfiles()
            loadApiToken(function() {
                credentialsLoading = false
                var cbs = pendingCredentialCallbacks
                pendingCredentialCallbacks = []
                for (var i = 0; i < cbs.length; i++) {
                    cbs[i]()
                }
                // Another caller may have queued work while we were flushing.
                if (pendingCredentialCallbacks.length > 0) {
                    reloadCredentials()
                }
            })
        })
    }

    function persistSharedConfig(callback) {
        // This instance's configuration wins (used after a configure session).
        Platform.patchShared(
            execSource, plasmoid.configuration,
            // Film-day data maps are written on their own (merged, B9); a
            // stale copy here would drop what the app saved meanwhile.
            SharedConfig.fromConfiguration(plasmoid.configuration, { withoutDataMaps: true })
        ).then(function() {
            if (callback) { callback() }
        })
    }

    function softReload() {
        reloadCredentials(function() {
            syncDisplayStateFromConfig()
            refreshAll(true, true)
        })
    }

    function hardReload() {
        reloadCredentials(function() {
            syncDisplayStateFromConfig()
            refreshAll(false, true)
        })
    }

    function syncDisplayStateFromConfig() {
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        } else if (!plasmoid.configuration.popupShowNewActivity) {
            showNewActivityForm = false
        }
    }

    function switchProfile(profileId) {
        var currentId = plasmoid.configuration.activeProfileId || "default"
        resetTrackingState()
        CatalogCache.clear()
        if (currentId !== profileId) {
            // Connections.onActiveProfileIdChanged performs the soft reload.
            plasmoid.configuration.activeProfileId = profileId
            return
        }
        softReload()
    }

    function loadApiToken(callback) {
        reloadProfiles()
        if (!activeProfile) {
            apiToken = ""
            tokenLoaded = true
            setError({ type: "config", status: 0, detail: "" })
            if (callback) {
                callback()
            }
            return
        }
        syncTrackerSession()
        Platform.loadToken(execSource, activeProfile.id).then(function(token) {
            apiToken = token || ""
            syncTrackerSession()
            var needsUrl = providerMeta.needsUrl
            if (!token || (needsUrl && kimaiUrl.length === 0)) {
                setError({ type: "config", status: 0, detail: "" })
            } else {
                clearError()
            }
            tokenLoaded = true
            if (callback) {
                callback()
            }
        }).catch(function(err) {
            setError({ type: KimaiApi.ErrorType.Network, status: 0, detail: err })
            apiToken = ""
            tokenLoaded = true
            if (callback) {
                callback()
            }
        })
    }

    function resetTrackingState() {
        resetMileageState()
        isTracking = false
        editingActiveEntry = false
        editingStoppedTimesheet = null
        currentTimesheetId = invalidTimesheetId
        currentProject = ""
        currentActivity = ""
        currentCustomer = ""
        currentDescription = ""
        activeTimesheet = null
        currentCustomerColor = KimaiApi.DEFAULT_CUSTOMER_COLOR
        elapsedSeconds = 0
        cancelDescriptionSavedFlash()
        descriptionDirty = false
        descriptionDraft = ""
        descriptionFieldFocused = false
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        }
    }

    function syncDescriptionField(text) {
        suppressDescHandler = true
        currentDescription = text || ""
        descriptionDraft = currentDescription
        descriptionDirty = false
        // TextField is under fullRepresentation — push via onDescriptionDraftChanged there.
        Qt.callLater(function() {
            suppressDescHandler = false
        })
    }

    function applyActiveTimesheet(timesheet, fromLocalStart) {
        if (!timesheet) {
            if (isTracking) {
                resetTrackingState()
            }
            return
        }

        var wasTracking = isTracking
        isTracking = true
        activeTimesheet = timesheet
        currentTimesheetId = timesheet.id
        currentProject = KimaiApi.displayProjectName(timesheet, projects)
        currentActivity = KimaiApi.displayActivityName(timesheet, allActivities, activitiesByProject)
        currentCustomer = KimaiApi.customerNameFromTimesheet(timesheet, customersById)
        currentCustomerColor = KimaiApi.customerColorFromTimesheet(timesheet, customersById)
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        }

        var beginDate = new Date(timesheet.begin)
        if (!isNaN(beginDate.getTime())) {
            elapsedSeconds = Math.max(0, Math.floor((Date.now() - beginDate.getTime()) / 1000))
        }

        var serverDescription = timesheet.description || ""
        var editing = descriptionFieldFocused || descriptionDirty
            || (descriptionDraft.length > 0 && descriptionDraft !== currentDescription)
        if (!editing) {
            syncDescriptionField(serverDescription)
        }

        if (!wasTracking && !fromLocalStart) {
            var label = currentProject + " · " + currentActivity
            sendNotification(
                i18n("Tracking in progress"),
                label + " · " + KimaiApi.formatDurationShort(elapsedSeconds))
        }
    }

    function cancelDescriptionSavedFlash() {
        descriptionSavedFlashTimer.stop()
        descriptionSavedFade.stop()
        descriptionSavedFlash = false
        descriptionSaveFlashOpacity = 1
    }

    function startDescriptionSavedFlash() {
        descriptionSavedFade.stop()
        descriptionSaveFlashOpacity = 1
        descriptionSavedFlash = true
        descriptionSavedFlashTimer.restart()
    }

    function saveCurrentDescription() {
        if (!isTracking) {
            return
        }
        if (currentTimesheetId === invalidTimesheetId || currentTimesheetId === undefined || currentTimesheetId === null || currentTimesheetId === "") {
            return
        }
        if (savingDescription) {
            return
        }
        var text = descriptionDraft
        if (text === currentDescription) {
            descriptionDirty = false
            return
        }
        if (!isConfigured || !apiToken) {
            return
        }
        if (!tracker || typeof tracker.patchTimesheet !== "function") {
            setError({ type: "config", status: 0, detail: i18n("This provider cannot update descriptions.") })
            return
        }

        savingDescription = true
        cancelDescriptionSavedFlash()
        lastError = null
        userMessage = ""
        tracker.patchTimesheet(kimaiUrl, apiToken, currentTimesheetId, { description: text }, function(result) {
            savingDescription = false
            if (result && result.ok) {
                syncDescriptionField(text)
                clearError()
                root.startDescriptionSavedFlash()
            } else {
                setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
            }
        })
    }

    function remainingTodayText() {
        if (remainingTodaySeconds >= 0) {
            return i18n("%1 left today", KimaiApi.formatDurationShort(remainingTodaySeconds))
        }
        return i18n("%1 over today", KimaiApi.formatDurationShort(-remainingTodaySeconds))
    }

    function remainingWeekText() {
        if (remainingWeekSeconds >= 0) {
            return i18n("%1 left this week", KimaiApi.formatDurationShort(remainingWeekSeconds))
        }
        return i18n("%1 over this week", KimaiApi.formatDurationShort(-remainingWeekSeconds))
    }

    function workSummaryText(includeRemaining) {
        var bits = [
            i18n("Today %1", KimaiApi.formatDurationShort(todayLiveSeconds)),
            i18n("Week %1", KimaiApi.formatDurationShort(weekLiveSeconds))
        ]
        if (includeRemaining && hasWorkContract) {
            if (todayTargetSeconds > 0) {
                bits.push(remainingTodayText())
            }
            if (weekTargetSeconds > 0) {
                bits.push(remainingWeekText())
            }
        }
        return bits.join(" · ")
    }

    /** Panel hover tooltip body; respects Panel-Flyout work-summary setting. */
    function panelTooltipBody() {
        var showSummary = plasmoid.configuration.popupShowWorkSummary
        var lines = []
        var line1 = []
        if (isTracking) {
            line1.push(KimaiApi.formatDuration(elapsedSeconds))
        }
        if (showSummary) {
            line1.push(i18n("Today %1", KimaiApi.formatDurationShort(todayLiveSeconds)))
        }
        if (line1.length > 0) {
            lines.push(line1.join(" · "))
        }
        if (showSummary && hasWorkContract) {
            var line2 = []
            if (todayTargetSeconds > 0) {
                line2.push(remainingTodayText())
            }
            if (weekTargetSeconds > 0) {
                line2.push(remainingWeekText())
            }
            if (line2.length > 0) {
                lines.push(line2.join(" · "))
            }
        }
        return lines.join("\n")
    }

    function applyActivitiesResult(projectId, result, activityIdToSelect) {
        if (result.ok) {
            activities = result.data || []
            if (projectId) {
                var copy = {}
                var key
                for (key in activitiesByProject) {
                    if (activitiesByProject.hasOwnProperty(key)) {
                        copy[key] = activitiesByProject[key]
                    }
                }
                copy[String(projectId)] = activities
                activitiesByProject = copy
            }
            var project = null
            for (var p = 0; p < projects.length; p++) {
                if (String(projects[p].id) === String(projectId)) {
                    project = projects[p]
                    break
                }
            }
            activityPickerModel = KimaiApi.activityPickerItems(
                activities, projectId, project, customersById)
            if (activityIdToSelect) {
                for (var a = 0; a < activityPickerModel.length; a++) {
                    if (activityPickerModel[a].value
                        && String(activityPickerModel[a].value.id) === String(activityIdToSelect)) {
                        setSwitchPickerIndex("activityCombo", a)
                        return
                    }
                }
            }
            setSwitchPickerIndex("activityCombo", -1)
            return
        }
        setError(result.error)
        activities = []
        activityPickerModel = []
        setSwitchPickerIndex("activityCombo", -1)
    }

    /** The pickers live in fullRepresentation, which may not exist yet. */
    function setSwitchPickerIndex(combo, index) {
        if (root.switchPickersRef) {
            root.switchPickersRef[combo].currentIndex = index
        }
    }

    function selectProjectById(projectId, activityIdToSelect) {
        if (!projectId) {
            return
        }
        var idx = -1
        for (var i = 0; i < projectPickerModel.length; i++) {
            if (projectPickerModel[i].value
                && String(projectPickerModel[i].value.id) === String(projectId)) {
                idx = i
                break
            }
        }
        if (idx < 0) {
            return
        }
        setSwitchPickerIndex("projectCombo", idx)
        selectedProjectId = projectId
        tracker.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
            applyActivitiesResult(projectId, result, activityIdToSelect)
        })
    }

    function preloadLastActivity() {
        if (isTracking || !isConfigured) {
            return
        }
        var pid = lastRecent ? KimaiApi.projectId(lastRecent) : plasmoid.configuration.lastUsedProjectId
        var aid = lastRecent ? KimaiApi.activityId(lastRecent) : plasmoid.configuration.lastUsedActivityId
        if (!pid || !aid) {
            return
        }
        if (projectPickerModel.length === 0) {
            return
        }
        selectProjectById(pid, aid)
        if (root.descriptionFieldRef && lastRecent) {
            root.descriptionFieldRef.text = lastRecent.description || ""
        }
    }

    function continueLastActivity() {
        if (lastRecent) {
            restartFromRecent(lastRecent)
            return
        }
        startLastUsed()
    }

    function refreshActiveTimesheet(quiet) {
        if (!isConfigured) {
            return
        }
        if (!quiet) {
            loadingActive = true
        }

        tracker.fetchActiveTimesheet(kimaiUrl, apiToken, function(result) {
            loadingActive = false
            if (result.ok) {
                clearError()
                if (result.data.length > 0) {
                    var hydratedActive = KimaiApi.hydrateTimesheets(
                        [result.data[0]], root.projects, root.activityCatalog(), root.activitiesByProject)
                    applyActiveTimesheet(hydratedActive[0] || result.data[0])
                } else if (isTracking) {
                    resetTrackingState()
                }
            } else {
                setError(result.error)
            }
        })
    }

    function refreshRecentTimesheets(quiet) {
        if (!isConfigured) {
            recentTimesheets = []
            return
        }

        if (!quiet) {
            loadingRecent = true
        }
        tracker.fetchRecentTimesheets(kimaiUrl, apiToken, plasmoid.configuration.recentCount, function(result) {
            loadingRecent = false
            if (result.ok) {
                clearError()
                recentTimesheets = KimaiApi.hydrateTimesheets(
                    KimaiApi.deduplicateRecent(result.data || []),
                    root.projects,
                    root.activityCatalog(),
                    root.activitiesByProject)
            } else {
                setError(result.error)
                recentTimesheets = []
            }
        })
    }

    function refreshWorkTotals() {
        if (!isConfigured) {
            todaySeconds = 0
            weekSeconds = 0
            todayTargetSeconds = 0
            weekTargetSeconds = 0
            weekEffectiveTargetSeconds = 0
            weekAbsences = []
            weekPublicHolidays = []
            weekTimesheetsForCredit = []
            weekAbsenceCreditSeconds = 0
            todayAbsenceCreditSeconds = 0
            hasWorkContract = false
            todayTimesheets = []
            statsTimesheets = []
            statsRangeBeginMs = 0
            statsRangeEndMs = 0
            return
        }

        var now = new Date()
        tracker.fetchCurrentUser(kimaiUrl, apiToken, function(userResult) {
            if (userResult.ok) {
                workPrefs = tracker.preferenceMap(userResult.data)
                todayTargetSeconds = tracker.workDaySecondsFromPrefs(workPrefs, now)
                weekTargetSeconds = tracker.workWeekSecondsFromPrefs(workPrefs, now)
                hasWorkContract = weekTargetSeconds > 0 || todayTargetSeconds > 0
            } else {
                workPrefs = ({})
                todayTargetSeconds = 0
                weekTargetSeconds = 0
                hasWorkContract = false
            }

            function applyAbsenceCredit() {
                if (!providerCapabilities.holidayBundle || !hasWorkContract || !workPrefs) {
                    weekAbsenceCreditSeconds = 0
                    todayAbsenceCreditSeconds = 0
                    return
                }
                var nowMs = Date.now()
                weekAbsenceCreditSeconds = KimaiApi.absenceCreditSeconds(
                    workPrefs, now, weekAbsences, weekPublicHolidays, weekTimesheetsForCredit, nowMs)
                todayAbsenceCreditSeconds = KimaiApi.dayAbsenceCreditSeconds(
                    workPrefs, now, weekAbsences, weekPublicHolidays, todayTimesheets, nowMs)
            }

            function applyEffectiveWeekTarget() {
                weekEffectiveTargetSeconds = weekTargetSeconds
                if (providerCapabilities.holidayBundle && hasWorkContract && workPrefs) {
                    weekEffectiveTargetSeconds = KimaiApi.effectiveWeekTargetSeconds(
                        workPrefs, now, weekAbsences, weekPublicHolidays)
                    todayTargetSeconds = KimaiApi.effectiveDayTargetSeconds(
                        workPrefs, now, weekAbsences, weekPublicHolidays)
                }
                applyAbsenceCredit()
            }

            if (providerCapabilities.holidayBundle && hasWorkContract) {
                KimaiApi.fetchContractAdjustments(kimaiUrl, apiToken, now, workPrefs, function(adjResult) {
                    var data = (adjResult && adjResult.ok && adjResult.data) ? adjResult.data : null
                    weekAbsences = data && data.absences ? data.absences : []
                    weekPublicHolidays = data && data.publicHolidays ? data.publicHolidays : []
                    applyEffectiveWeekTarget()
                })
            } else {
                weekAbsences = []
                weekPublicHolidays = []
                applyEffectiveWeekTarget()
            }

            tracker.fetchTimesheetsRange(
                kimaiUrl, apiToken,
                KimaiApi.startOfWeekMonday(now),
                KimaiApi.endOfWeekSunday(now),
                function(weekResult) {
                    if (!weekResult.ok) {
                        return
                    }
                    var nowMs = Date.now()
                    var weekEntries = weekResult.data || []
                    weekTimesheetsForCredit = weekEntries
                    weekSeconds = KimaiApi.sumTimesheetDurations(weekEntries, nowMs)

                    var dayStart = KimaiApi.startOfLocalDay(now).getTime()
                    var dayEnd = KimaiApi.endOfLocalDay(now).getTime()
                    var todayEntries = []
                    for (var i = 0; i < weekEntries.length; i++) {
                        var entry = weekEntries[i]
                        if (!entry || !entry.begin) {
                            continue
                        }
                        var begin = new Date(entry.begin)
                        if (isNaN(begin.getTime())) {
                            continue
                        }
                        var endMs = nowMs
                        if (entry.end) {
                            var end = new Date(entry.end)
                            if (!isNaN(end.getTime())) {
                                endMs = end.getTime()
                            }
                        }
                        // Include entries that overlap today (not only those that started today).
                        if (begin.getTime() < dayEnd + 1000 && endMs > dayStart) {
                            todayEntries.push(entry)
                        }
                    }
                    todayTimesheets = todayEntries
                    // Keep current week available for stats until a wider fetch completes.
                    if (!statsTimesheets.length || mainViewMode !== "stats") {
                        statsTimesheets = KimaiApi.hydrateTimesheets(
                            weekEntries, root.projects,
                            root.activityCatalog(),
                            root.activitiesByProject)
                        statsRangeBeginMs = KimaiApi.startOfWeekMonday(now).getTime()
                        statsRangeEndMs = KimaiApi.endOfWeekSunday(now).getTime()
                    }
                    var dayIntervals = KimaiApi.dayIntervalsFromTimesheets(todayEntries, now, nowMs)
                    todaySeconds = 0
                    for (var j = 0; j < dayIntervals.length; j++) {
                        todaySeconds += dayIntervals[j].endSec - dayIntervals[j].startSec
                    }
                    totalsElapsedAnchor = elapsedSeconds
                    applyAbsenceCredit()
                }
            )
        })
    }

    function rebuildCatalogViews() {
        if (projects && projects.length) {
            projectPickerModel = KimaiApi.projectPickerItems(projects, customers)
        }
        if (selectedProjectId) {
            var project = null
            for (var p = 0; p < projects.length; p++) {
                if (String(projects[p].id) === String(selectedProjectId)) {
                    project = projects[p]
                    break
                }
            }
            activityPickerModel = KimaiApi.activityPickerItems(
                activities, selectedProjectId, project, customersById)
        }
        if (Favorites.parsePinned(plasmoid.configuration.pinnedActivities).length > 0) {
            pinnedEntries = Favorites.resolvePinnedEntries(
                plasmoid.configuration.pinnedActivities, projects, activitiesByProject,
                customersById, allActivities)
        }
        rehydrateStatsTimesheets()
        if (recentTimesheets && recentTimesheets.length) {
            recentTimesheets = KimaiApi.hydrateTimesheets(
                recentTimesheets, projects, activityCatalog(), activitiesByProject)
        }
        if (activeTimesheet) {
            currentProject = KimaiApi.displayProjectName(activeTimesheet, projects)
            currentActivity = KimaiApi.displayActivityName(activeTimesheet, allActivities, activitiesByProject)
            currentCustomer = KimaiApi.customerNameFromTimesheet(activeTimesheet, customersById)
            currentCustomerColor = KimaiApi.customerColorFromTimesheet(activeTimesheet, customersById)
            if (editingActiveEntry) {
                Qt.callLater(function() {
                    if (editingActiveEntry && root.activeEditViewRef) {
                        root.activeEditViewRef.loadFromTimesheet(root.activeTimesheet)
                    }
                })
            }
        }
    }

    function activityCatalog() {
        return allActivities.length ? allActivities : activities
    }

    function refreshProjects(quiet, forceCatalog) {
        if (!isConfigured) {
            projects = []
            customers = []
            customersById = ({})
            projectPickerModel = []
            return
        }

        var profileId = activeProfile ? activeProfile.id : ""
        // Reuse in-process catalog when fresh (expand/poll paths); force after config/profile changes.
        if (!forceCatalog && CatalogCache.isFresh(profileId) && root.projects.length > 0) {
            rebuildCatalogViews()
            refreshPinnedEntries(true)
            return
        }
        if (!forceCatalog && CatalogCache.isFetching()) {
            return
        }

        if (!quiet) {
            loadingProjects = true
        }
        CatalogCache.setFetching(true)
        tracker.loadCustomers(kimaiUrl, apiToken, function(customersResult) {
            customers = customersResult.ok ? (customersResult.data || []) : []
            customersById = KimaiApi.buildCustomersById(customers)
            tracker.loadProjects(kimaiUrl, apiToken, function(result) {
                loadingProjects = false
                if (result.ok) {
                    clearError()
                    projects = result.data || []
                    function afterActivities(acts) {
                        allActivities = acts || []
                        CatalogCache.storeEntities(profileId, customers, projects, allActivities)
                        Platform.saveCatalog(execSource, CatalogCache.exportPayload())
                        rebuildCatalogViews()
                        refreshPinnedEntries(true)
                        if (!isTracking) {
                            Qt.callLater(root.preloadLastActivity)
                        }
                    }
                    if (typeof tracker.loadAllActivities === "function") {
                        tracker.loadAllActivities(kimaiUrl, apiToken, function(actResult) {
                            afterActivities(actResult.ok ? (actResult.data || []) : [])
                        })
                    } else {
                        afterActivities([])
                    }
                } else {
                    CatalogCache.setFetching(false)
                    setError(result.error)
                    projects = []
                    projectPickerModel = []
                }
            })
        })
    }

    function refreshPinnedEntries(quiet) {
        var pinned = Favorites.parsePinned(plasmoid.configuration.pinnedActivities)
        if (pinned.length === 0 || !isConfigured) {
            pinnedEntries = []
            return
        }

        if (!quiet) {
            loadingPinned = true
        }
        pinnedEntries = Favorites.resolvePinnedEntries(
            plasmoid.configuration.pinnedActivities, projects, activitiesByProject,
            customersById, allActivities)
        loadingPinned = false

        for (var i = 0; i < pinned.length; i++) {
            (function(projectId) {
                if (activitiesByProject[projectId] || activitiesByProject[String(projectId)]) {
                    return
                }
                // Names already resolved from allActivities; still cache per-project lists for colors.
                if (allActivities && allActivities.length > 0) {
                    return
                }
                tracker.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
                    if (result.ok) {
                        var copy = {}
                        var key
                        for (key in activitiesByProject) {
                            if (activitiesByProject.hasOwnProperty(key)) {
                                copy[key] = activitiesByProject[key]
                            }
                        }
                        copy[projectId] = result.data || []
                        activitiesByProject = copy
                        pinnedEntries = Favorites.resolvePinnedEntries(
                            plasmoid.configuration.pinnedActivities, projects, activitiesByProject,
                            customersById, allActivities)
                    }
                })
            })(pinned[i].projectId)
        }
    }

    function refreshAll(quiet, forceCatalog) {
        reloadProfiles()
        syncTrackerSession()
        if (!isConfigured) {
            connectionState = "offline"
            if (tokenLoaded) {
                setError({ type: "config", status: 0, detail: "" })
            }
            return
        }
        if (!quiet) {
            connectionState = "connecting"
        }
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        }
        refreshActiveTimesheet(!!quiet)
        refreshRecentTimesheets(!!quiet)
        refreshProjects(!!quiet, !!forceCatalog)
        refreshWorkTotals()
        refreshMileage()
    }

    function loadActivitiesForProject(projectId) {
        selectedProjectId = projectId || null
        if (!isConfigured || !projectId) {
            activities = []
            activityPickerModel = []
            setSwitchPickerIndex("activityCombo", -1)
            return
        }

        tracker.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
            applyActivitiesResult(projectId, result)
        })
    }

    function startTracking(projectId, activityId, projectLabel, activityLabel, description) {
        if (!isConfigured || isBusy || isTracking) {
            return
        }

        isBusy = true
        lastError = null
        userMessage = ""
        tracker.startTracking(kimaiUrl, apiToken, projectId, activityId, description, function(result) {
            isBusy = false
            if (result.ok && result.data) {
                clearError()
                applyActiveTimesheet(result.data, true)
                rememberLastUsed(projectId, activityId, projectLabel, activityLabel)
                refreshRecentTimesheets()
                refreshWorkTotals()
                if (plasmoid.configuration.notifyOnStart) {
                    sendNotification(
                        i18n("Tracking started"),
                        projectLabel + " · " + activityLabel)
                }
            } else {
                setError(result.error)
            }
        })
    }

    function switchToActivity(projectId, activityId, projectLabel, activityLabel, description) {
        if (!isConfigured || isBusy) {
            return
        }
        if (!isTracking) {
            startTracking(projectId, activityId, projectLabel, activityLabel, description)
            return
        }
        if (currentTimesheetId === invalidTimesheetId) {
            return
        }

        isBusy = true
        lastError = null
        userMessage = ""
        tracker.stopTracking(kimaiUrl, apiToken, currentTimesheetId, function(stopResult) {
            if (!stopResult.ok) {
                isBusy = false
                setError(stopResult.error)
                return
            }
            resetTrackingState()
            tracker.startTracking(kimaiUrl, apiToken, projectId, activityId, description, function(startResult) {
                isBusy = false
                if (startResult.ok && startResult.data) {
                    clearError()
                    applyActiveTimesheet(startResult.data, true)
                    refreshRecentTimesheets()
                    refreshWorkTotals()
                    if (plasmoid.configuration.notifyOnStart) {
                        sendNotification(
                            i18n("Switched activity"),
                            projectLabel + " · " + activityLabel)
                    }
                } else {
                    setError(startResult.error)
                    refreshRecentTimesheets()
                }
            })
        })
    }

    function startPinned(entry) {
        if (!entry) {
            return
        }
        if (isTracking) {
            requestRestartFromRecent(Favorites.asTimesheet(entry))
            return
        }
        startTracking(entry.projectId, entry.activityId, entry.projectName, entry.activityName, "")
    }

    function requestStop() {
        if (!isConfigured || isBusy || !isTracking || currentTimesheetId === invalidTimesheetId) {
            return
        }
        if (plasmoid.configuration.confirmBeforeStop) {
            if (stopConfirmDialogRef) {
                stopConfirmDialogRef.open()
            } else {
                stopTracking(false)
            }
        } else {
            stopTracking(false)
        }
    }

    function stopTracking(fromIdle) {
        if (!isConfigured || isBusy || !isTracking || currentTimesheetId === invalidTimesheetId) {
            return
        }

        var stoppedProject = currentProject
        var stoppedActivity = currentActivity
        isBusy = true
        lastError = null
        tracker.stopTracking(kimaiUrl, apiToken, currentTimesheetId, function(result) {
            isBusy = false
            if (result.ok) {
                clearError()
                resetTrackingState()
                refreshRecentTimesheets()
                refreshWorkTotals()
                if (fromIdle && plasmoid.configuration.notifyOnIdleStop) {
                    sendNotification(
                        i18n("Tracking stopped (idle)"),
                        stoppedProject + " · " + stoppedActivity)
                } else if (!fromIdle && plasmoid.configuration.notifyOnStop) {
                    sendNotification(
                        i18n("Tracking stopped"),
                        stoppedProject + " · " + stoppedActivity)
                }
            } else {
                setError(result.error)
            }
        })
    }

    function restartFromRecent(timesheet) {
        if (!isConfigured || isBusy || !timesheet) {
            return
        }

        if (isTracking) {
            requestRestartFromRecent(timesheet)
            return
        }

        isBusy = true
        userMessage = ""
        lastError = null
        tracker.restartTimesheet(kimaiUrl, apiToken, timesheet.id, function(result) {
            if (result.ok) {
                clearError()
                applyActiveTimesheet(
                    (KimaiApi.hydrateTimesheets(
                        [result.data || timesheet], root.projects, root.activityCatalog(), root.activitiesByProject)[0])
                    || result.data || timesheet, true)
                refreshRecentTimesheets()
                refreshWorkTotals()
                isBusy = false
                if (plasmoid.configuration.notifyOnStart) {
                    sendNotification(
                        i18n("Tracking started"),
                        KimaiApi.displayProjectName(timesheet, root.projects)
                            + " · "
                            + KimaiApi.displayActivityName(timesheet, root.allActivities, root.activitiesByProject))
                }
                return
            }

            var pid = KimaiApi.projectId(timesheet)
            var aid = KimaiApi.activityId(timesheet)
            if (pid && aid) {
                isBusy = false
                startTracking(pid, aid,
                    KimaiApi.displayProjectName(timesheet, root.projects),
                    KimaiApi.displayActivityName(timesheet, root.allActivities, root.activitiesByProject),
                    timesheet.description || "")
            } else {
                isBusy = false
                setError(result.error)
            }
        })
    }

    function switchHintKey(timesheet) {
        var pid = KimaiApi.projectId(timesheet)
        var aid = KimaiApi.activityId(timesheet)
        var idPart = (timesheet && timesheet.id !== undefined && timesheet.id !== null) ? timesheet.id : ""
        return String(pid) + "|" + String(aid) + "|" + String(idPart)
    }

    function requestRestartFromRecent(timesheet) {
        if (!isConfigured || isBusy || !timesheet) {
            return
        }
        if (!isTracking) {
            restartFromRecent(timesheet)
            return
        }

        var pid = KimaiApi.projectId(timesheet)
        var aid = KimaiApi.activityId(timesheet)
        if (activeTimesheet
                && String(KimaiApi.projectId(activeTimesheet)) === String(pid)
                && String(KimaiApi.activityId(activeTimesheet)) === String(aid)) {
            alreadyRunningHintKey = switchHintKey(timesheet)
            alreadyRunningHintTimer.restart()
            userMessage = ""
            return
        }

        pendingSwitchTimesheet = timesheet
        if (switchRecentDialogRef) {
            switchRecentDialogRef.open()
        } else {
            confirmSwitchFromRecent()
        }
    }

    function confirmSwitchFromRecent() {
        var timesheet = pendingSwitchTimesheet
        pendingSwitchTimesheet = null
        if (!timesheet) {
            return
        }
        var pid = KimaiApi.projectId(timesheet)
        var aid = KimaiApi.activityId(timesheet)
        if (!pid || !aid) {
            userMessage = i18n("Could not resolve project or activity for that entry")
            return
        }
        switchToActivity(
            pid,
            aid,
            KimaiApi.displayProjectName(timesheet, root.projects),
            KimaiApi.displayActivityName(timesheet, root.allActivities, root.activitiesByProject),
            timesheet.description || "")
    }

    function timesheetIsRunning(timesheet) {
        return !!(isTracking && timesheet && timesheet.id !== undefined && timesheet.id !== null
                  && String(timesheet.id) === String(currentTimesheetId))
    }

    function requestDeleteStopped(timesheet) {
        if (!isConfigured || isBusy || !timesheet || !providerCapabilities.deleteEntry) {
            return
        }
        if (timesheetIsRunning(timesheet) || !timesheet.end) {
            return
        }
        if (timesheet.id === undefined || timesheet.id === null || timesheet.id === "") {
            return
        }
        pendingDeleteTimesheet = timesheet
        if (deleteConfirmDialogRef) {
            deleteConfirmDialogRef.open()
        }
    }

    function confirmDeleteStopped() {
        var timesheet = pendingDeleteTimesheet
        pendingDeleteTimesheet = null
        if (!timesheet || timesheet.id === undefined || timesheet.id === null || timesheet.id === "") {
            return
        }
        if (!tracker || typeof tracker.deleteTimesheet !== "function") {
            setError({ type: "config", status: 0, detail: i18n("This provider cannot delete entries.") })
            return
        }
        isBusy = true
        lastError = null
        userMessage = ""
        tracker.deleteTimesheet(kimaiUrl, apiToken, timesheet.id, function(result) {
            isBusy = false
            if (result && result.ok) {
                clearError()
                refreshRecentTimesheets()
                refreshWorkTotals()
                sendNotification(
                    i18n("Entry deleted"),
                    KimaiApi.displayActivityName(timesheet, root.allActivities, root.activitiesByProject))
            } else {
                setError(result ? result.error : { type: "network", status: 0, detail: "empty result" })
            }
        })
    }

    function requestSplitStopped(timesheet) {
        if (!isConfigured || isBusy || !timesheet || !providerCapabilities.editStopped) {
            return
        }
        if (timesheetIsRunning(timesheet) || !timesheet.end) {
            return
        }
        pendingSplitTimesheet = timesheet
        if (splitEntryDialogRef) {
            splitEntryDialogRef.open()
        }
    }

    function confirmSplitStopped() {
        var timesheet = pendingSplitTimesheet
        pendingSplitTimesheet = null
        if (!timesheet) {
            return
        }
        var at = splitEntryDialogRef && typeof splitEntryDialogRef.splitInstant === "function"
                 ? splitEntryDialogRef.splitInstant()
                 : null
        var split = TimesheetFields.splitStoppedEntry(timesheet, at)
        if (!split.ok) {
            userMessage = i18n("Split time must be between begin and end.")
            return
        }
        if (!tracker || typeof tracker.patchTimesheet !== "function"
                || typeof tracker.createTimesheet !== "function") {
            setError({ type: "config", status: 0, detail: i18n("This provider cannot split entries.") })
            return
        }
        isBusy = true
        lastError = null
        userMessage = ""
        tracker.patchTimesheet(kimaiUrl, apiToken, timesheet.id, {
            end: KimaiApi.localDateTimeString(split.firstEnd)
        }, function(patchResult) {
            if (!patchResult || !patchResult.ok) {
                isBusy = false
                setError(patchResult ? patchResult.error : { type: "network", status: 0, detail: "empty result" })
                return
            }
            tracker.createTimesheet(kimaiUrl, apiToken, {
                begin: KimaiApi.localDateTimeString(split.secondBegin),
                end: KimaiApi.localDateTimeString(split.secondEnd),
                project: KimaiApi.projectId(timesheet),
                activity: KimaiApi.activityId(timesheet),
                description: timesheet.description || "",
                billable: TimesheetFields.billableFromTimesheet(timesheet, true),
                tags: TimesheetFields.tagsFromTimesheet(timesheet)
            }, function(createResult) {
                isBusy = false
                if (createResult && createResult.ok) {
                    clearError()
                    refreshRecentTimesheets()
                    refreshWorkTotals()
                    sendNotification(
                        i18n("Entry split"),
                        KimaiApi.displayActivityName(timesheet, root.allActivities, root.activitiesByProject))
                } else {
                    setError(createResult ? createResult.error : { type: "network", status: 0, detail: "empty result" })
                    userMessage = i18n("The first half was saved, but the second half could not be created.")
                }
            })
        })
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        Accessible.role: Accessible.Button
        Accessible.name: i18n("Plasmai")
        Accessible.description: i18n("Open or close the Plasmai popup")
        Accessible.onPressAction: root.expanded = !root.expanded

        Layout.minimumWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: TouchUi.compactIconSize
        Layout.preferredWidth: Layout.minimumWidth

        onClicked: root.expanded = !root.expanded

        // Tracking tint: theme positive (System, Kante Light) or the Kante accent, square in Kante.
        readonly property color trackingColor: KanteStyle.themed ? KanteStyle.accentColor : KanteStyle.positiveTextColor

        Rectangle {
            anchors.fill: parent
            radius: KanteStyle.themed ? 0 : 3
            color: root.isTracking
                   ? Qt.rgba(compactRoot.trackingColor.r,
                             compactRoot.trackingColor.g,
                             compactRoot.trackingColor.b, 0.12)
                   : "transparent"
            border.width: root.isTracking ? 1 : 0
            border.color: Qt.rgba(compactRoot.trackingColor.r,
                                  compactRoot.trackingColor.g,
                                  compactRoot.trackingColor.b, 0.35)
        }

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: TouchUi.compactIconSize
                Layout.preferredHeight: TouchUi.compactIconSize
                // Kante keeps the Plasmai mark while tracking, tinted with the accent.
                source: root.connectionState === "error" ? "network-disconnect"
                        : (root.isTracking && !KanteStyle.themed) ? "media-record" : Qt.resolvedUrl("../images/icon.svg")
                isMask: root.connectionState !== "error" && (!root.isTracking || KanteStyle.themed)
                active: compactRoot.containsMouse
                color: root.isTracking ? compactRoot.trackingColor : KanteStyle.textColor
            }

            RowLayout {
                id: panelColorPills
                spacing: 1
                visible: root.isTracking
                         && (plasmoid.configuration.showCustomerColorInPanel
                             || plasmoid.configuration.showProjectColorInPanel)
                Layout.preferredHeight: TouchUi.compactIconSize
                Layout.alignment: Qt.AlignVCenter

                CustomerColorDot {
                    visible: plasmoid.configuration.showCustomerColorInPanel
                    Layout.fillHeight: true
                    Layout.preferredWidth: implicitWidth
                    customerColor: root.panelPills.customerColor
                    sizeFactor: 0.9
                    slotSizeFactor: 0.7
                }

                CustomerColorDot {
                    visible: plasmoid.configuration.showProjectColorInPanel
                    Layout.fillHeight: true
                    Layout.preferredWidth: implicitWidth
                    customerColor: root.panelPills.projectColor
                    sizeFactor: 0.45
                    slotSizeFactor: 0.7
                }
            }

            PlasmaComponents3.Label {
                visible: root.panelProjectLabel.length > 0
                text: root.panelProjectLabel
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.maximumWidth: Kirigami.Units.gridUnit * 10
                font.pointSize: KanteStyle.smallFont.pointSize
            }

            PlasmaComponents3.Label {
                visible: root.isTracking && plasmoid.configuration.showElapsedInPanel
                text: KimaiApi.formatDurationPanel(root.elapsedSeconds)
                font.family: KanteStyle.monoFamily
                font.pointSize: KanteStyle.smallFont.pointSize
                font.bold: true
                color: KanteStyle.themed ? compactRoot.trackingColor : Kirigami.Theme.textColor
            }
        }
    }

    fullRepresentation: Item {
        id: popupRoot

        KanteScope { target: popupRoot }
        Layout.preferredWidth: Kirigami.Units.gridUnit * TouchUi.flyoutPreferredWidthGu
        Layout.preferredHeight: Kirigami.Units.gridUnit * TouchUi.flyoutPreferredHeightGu
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * TouchUi.flyoutMinHeightGu

        function scheduleSparkCutouts() {
            sparkCutoutTimer.restart()
        }

        property var sparklineItem: null

        /** Once the widget (a freely resizable desktop Planar item, unlike the fixed-size
            panel popup) is wide enough for a fixed timer pane and a separately scrolling
            list pane to both be useful, split the main view the same way the phone app does
            in landscape. Below the threshold everything stacks in the single popupScroll,
            unchanged from before. */
        readonly property bool isWideLayout: width >= Kirigami.Units.gridUnit * 44
        readonly property bool splitActive: root.mainViewMode === "main" && !root.showSetupState
                                             && isWideLayout

        /** Move heroCard/listSection between the single-column host (mainPaneHost) and the
            wide two-pane hosts (wideLeftCol/wideRightCol). Done imperatively rather than via
            a `parent:` binding on each item so the order they're appended to their shared
            host is guaranteed — two independent bindings evaluating in unspecified order can
            otherwise parent listSection before heroCard, which then paints the list on top
            of the timer card. */
        function relayoutMainPane() {
            if (splitActive) {
                heroCard.parent = wideLeftCol
                listSection.parent = wideRightCol
            } else {
                heroCard.parent = mainPaneHost
                listSection.parent = mainPaneHost
            }
        }
        onSplitActiveChanged: relayoutMainPane()
        Component.onCompleted: relayoutMainPane()

        function refreshSparkCutouts() {
            if (sparklineItem) {
                sparklineItem.scheduleHeaderCutouts()
            }
        }

        Timer {
            id: sparkCutoutTimer
            interval: 16
            repeat: false
            onTriggered: popupRoot.refreshSparkCutouts()
        }

        KanteDialog {
            id: stopConfirmDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("Stop tracking?")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 18, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

            Component.onCompleted: root.stopConfirmDialogRef = stopConfirmDialog
            Component.onDestruction: {
                if (root.stopConfirmDialogRef === stopConfirmDialog) {
                    root.stopConfirmDialogRef = null
                }
            }

            contentItem: PlasmaComponents3.Label {
                text: i18n("Stop tracking %1 · %2?", root.currentProject, root.currentActivity)
                wrapMode: Text.WordWrap
            }

            onAccepted: root.stopTracking(false)
        }

        KanteDialog {
            id: switchRecentDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("Switch activity")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 22, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.NoButton
            padding: Kirigami.Units.largeSpacing

            Component.onCompleted: root.switchRecentDialogRef = switchRecentDialog
            Component.onDestruction: {
                if (root.switchRecentDialogRef === switchRecentDialog) {
                    root.switchRecentDialogRef = null
                }
            }

            readonly property string pendingCustomer: root.pendingSwitchTimesheet
                ? KimaiApi.customerNameFromTimesheet(root.pendingSwitchTimesheet, root.customersById)
                : ""
            readonly property string pendingProject: root.pendingSwitchTimesheet
                ? KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.projects)
                : ""
            readonly property string pendingActivity: root.pendingSwitchTimesheet
                ? KimaiApi.displayActivityName(
                    root.pendingSwitchTimesheet, root.allActivities, root.activitiesByProject)
                : ""
            readonly property var pendingBarInfo: root.pendingSwitchTimesheet
                ? KimaiApi.barColorInfoFromTimesheet(root.pendingSwitchTimesheet, root.customersById)
                : ({ color: KimaiApi.DEFAULT_CUSTOMER_COLOR, category: "", id: null })

            component ActivityCard: Rectangle {
                id: card
                property string caption: ""
                property string customerName: ""
                property string projectName: ""
                property string activityName: ""
                property color accentColor: KimaiApi.DEFAULT_CUSTOMER_COLOR
                property bool emphasize: false

                radius: 6
                color: emphasize
                       ? Qt.rgba(KanteStyle.highlightColor.r,
                                 KanteStyle.highlightColor.g,
                                 KanteStyle.highlightColor.b, 0.12)
                       : Qt.rgba(KanteStyle.textColor.r,
                                 KanteStyle.textColor.g,
                                 KanteStyle.textColor.b, 0.05)
                border.width: 1
                border.color: emphasize
                              ? Qt.rgba(KanteStyle.highlightColor.r,
                                        KanteStyle.highlightColor.g,
                                        KanteStyle.highlightColor.b, 0.35)
                              : Qt.rgba(KanteStyle.textColor.r,
                                        KanteStyle.textColor.g,
                                        KanteStyle.textColor.b, 0.14)
                implicitHeight: cardColumn.implicitHeight + Kirigami.Units.smallSpacing * 2

                ColumnLayout {
                    id: cardColumn
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Math.round(Kirigami.Units.smallSpacing * 0.5)

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: card.caption
                        font.pointSize: KanteStyle.smallFont.pointSize
                        opacity: 0.65
                        elide: Text.ElideRight
                    }

                    ColorLabelRow {
                        Layout.fillWidth: true
                        visible: card.customerName.length > 0
                        customerRole: true
                        customerColor: card.accentColor
                        label: card.customerName
                    }

                    ColorLabelRow {
                        Layout.fillWidth: true
                        visible: card.projectName.length > 0
                        customerRole: false
                        customerColor: card.accentColor
                        label: card.projectName
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.small * 0.85
                                           + Kirigami.Units.largeSpacing
                                           + Kirigami.Units.smallSpacing
                        text: card.activityName
                        font.bold: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }
                }
            }

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                ActivityCard {
                    Layout.fillWidth: true
                    caption: i18n("Current")
                    customerName: root.currentCustomer
                    projectName: root.currentProject
                    activityName: root.currentActivity
                    accentColor: root.currentCustomerColor
                    emphasize: false
                }

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: "go-down"
                    color: KanteStyle.textColor
                    opacity: 0.55
                }

                ActivityCard {
                    Layout.fillWidth: true
                    caption: i18n("Switch to")
                    customerName: switchRecentDialog.pendingCustomer
                    projectName: switchRecentDialog.pendingProject
                    activityName: switchRecentDialog.pendingActivity
                    accentColor: switchRecentDialog.pendingBarInfo.color
                    emphasize: true
                }
            }

            footer: QQC2.DialogButtonBox {
                KantePlasmaButton {
                    text: i18n("Switch")
                    icon.name: "media-playback-start"
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.AcceptRole
                }
                KantePlasmaButton {
                    text: i18n("Cancel")
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                }
            }

            onAccepted: root.confirmSwitchFromRecent()
            onRejected: root.pendingSwitchTimesheet = null
            onDiscarded: root.pendingSwitchTimesheet = null
        }

        KanteDialog {
            id: deleteConfirmDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("Delete entry?")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 18, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

            Component.onCompleted: root.deleteConfirmDialogRef = deleteConfirmDialog
            Component.onDestruction: {
                if (root.deleteConfirmDialogRef === deleteConfirmDialog) {
                    root.deleteConfirmDialogRef = null
                }
            }

            contentItem: PlasmaComponents3.Label {
                wrapMode: Text.WordWrap
                text: {
                    var ts = root.pendingDeleteTimesheet
                    if (!ts) {
                        return i18n("Delete this finished entry? This cannot be undone.")
                    }
                    return i18n("Delete \"%1 · %2\"? This cannot be undone.",
                                KimaiApi.displayProjectName(ts, root.projects),
                                KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject))
                }
            }

            onAccepted: root.confirmDeleteStopped()
            onRejected: root.pendingDeleteTimesheet = null
        }

        KanteDialog {
            id: splitEntryDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("Split entry")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 22, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
            padding: Kirigami.Units.largeSpacing

            Component.onCompleted: root.splitEntryDialogRef = splitEntryDialog
            Component.onDestruction: {
                if (root.splitEntryDialogRef === splitEntryDialog) {
                    root.splitEntryDialogRef = null
                }
            }

            function splitInstant() {
                var d = splitDate.selectedDate
                if (!d || typeof d.getFullYear !== "function") {
                    d = new Date(splitDate.selectedDateMs)
                }
                if (!d || isNaN(d.getTime())) {
                    return null
                }
                return new Date(d.getFullYear(), d.getMonth(), d.getDate(),
                                splitTime.hours, splitTime.minutes, 0, 0)
            }

            function refreshOkButton() {
                var btn = standardButton(QQC2.Dialog.Ok)
                if (!btn) {
                    return
                }
                var split = TimesheetFields.splitStoppedEntry(
                    root.pendingSplitTimesheet, splitInstant())
                btn.enabled = split.ok
            }

            onAboutToShow: {
                var mid = TimesheetFields.midpointInstant(root.pendingSplitTimesheet)
                if (!mid) {
                    mid = new Date()
                }
                splitDate.setDate(mid)
                splitTime.setTime(mid.getHours(), mid.getMinutes())
                refreshOkButton()
            }

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("The first half keeps the original start. The second half starts at the split time.")
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: i18n("Split at")
                    font.bold: true
                    opacity: 0.85
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    DateField {
                        id: splitDate
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        onDateEdited: splitEntryDialog.refreshOkButton()
                    }
                    TimeField {
                        id: splitTime
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        onTimeEdited: splitEntryDialog.refreshOkButton()
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.8
                    color: {
                        var split = TimesheetFields.splitStoppedEntry(
                            root.pendingSplitTimesheet, splitEntryDialog.splitInstant())
                        return split.ok ? KanteStyle.textColor : KanteStyle.neutralTextColor
                    }
                    text: {
                        var _tick = splitDate.selectedDateMs + splitTime.hours * 60 + splitTime.minutes
                        var split = TimesheetFields.splitStoppedEntry(
                            root.pendingSplitTimesheet, splitEntryDialog.splitInstant())
                        return split.ok
                               ? i18n("Both halves will have a positive duration.")
                               : i18n("Split time must be between begin and end.")
                    }
                }
            }

            onAccepted: root.confirmSplitStopped()
            onRejected: root.pendingSplitTimesheet = null
        }

        KanteDialog {
            id: idleDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("You were idle")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 22, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.NoButton
            padding: Kirigami.Units.largeSpacing

            Component.onCompleted: root.idleDialogRef = idleDialog
            Component.onDestruction: {
                if (root.idleDialogRef === idleDialog) {
                    root.idleDialogRef = null
                }
            }

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("Keep the time, discard the idle gap, or discard and continue the same activity.")
                }
            }

            footer: RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                KantePlasmaButton {
                    Layout.fillWidth: true
                    text: i18n("Keep time")
                    Accessible.name: text
                    onClicked: {
                        root.keepIdleTime()
                        idleDialog.close()
                    }
                }
                KantePlasmaButton {
                    Layout.fillWidth: true
                    text: i18n("Discard idle")
                    Accessible.name: text
                    onClicked: {
                        root.discardIdleTime(false)
                        idleDialog.close()
                    }
                }
                KantePlasmaButton {
                    Layout.fillWidth: true
                    text: i18n("Discard and continue")
                    Accessible.name: text
                    onClicked: {
                        root.discardIdleTime(true)
                        idleDialog.close()
                    }
                }
            }
        }

        CreateEntityDialog {
            id: createEntityDialog
            parent: popupRoot
            anchors.centerIn: parent
            width: Math.min(Kirigami.Units.gridUnit * 22, popupRoot.width * 0.95)
            customers: root.customers
            selectedProjectId: root.selectedProjectId
            Component.onCompleted: root.createEntityDialogRef = createEntityDialog
            Component.onDestruction: {
                if (root.createEntityDialogRef === createEntityDialog) {
                    root.createEntityDialogRef = null
                }
            }
            onSubmitted: function(mode, payload) {
                root.submitCreateEntity(mode, payload)
            }
        }

        PlasmaComponents3.ScrollView {
            id: popupScroll
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            // Hugs its own content (header/profile switcher — mainPaneHost is emptied out by
            // relayoutMainPane() in this state) instead of filling the popup, so wideSplitRow
            // below can take the rest of the height for its own two independently scrolling
            // panes. Below the split threshold this still fills the full popup, unchanged.
            height: popupRoot.splitActive
                    ? Math.min(parent.height - Kirigami.Units.smallSpacing * 2, popupColumn.implicitHeight)
                    : parent.height - Kirigami.Units.smallSpacing * 2
            clip: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
            readonly property bool vScrollNeeded: contentItem
                                                  ? contentItem.contentHeight > contentItem.height + 1
                                                  : false
            // Reserve scrollbar lane only while vertical scrolling is needed.
            readonly property int scrollGutter: vScrollNeeded
                                               ? (slimScrollBar.width + Kirigami.Units.smallSpacing * 2)
                                               : 0
            contentWidth: Math.max(0, width - scrollGutter)
            rightPadding: 0
            leftPadding: 0

            // Track scroll position so pickers close even if Connections to
            // contentItem was established before the Flickable existed.
            readonly property real scrollPos: contentItem ? contentItem.contentY : 0
            onScrollPosChanged: root.dismissPickerPopups()

            // Custom slim scrollbar — Plasma theme bars stay wide via SVG hints.
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                id: slimScrollBar
                parent: popupScroll
                x: popupScroll.mirrored ? 0 : popupScroll.width - width
                y: popupScroll.topPadding
                height: popupScroll.availableHeight
                width: 4
                padding: 0
                policy: QQC2.ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: KanteStyle.textColor
                    opacity: slimScrollBar.pressed ? 0.55
                             : (slimScrollBar.hovered ? 0.4 : 0.28)
                }
                background: Item {}
            }

            WheelHandler {
                onWheel: root.dismissPickerPopups()
            }

            ColumnLayout {
                id: popupColumn
                width: popupScroll.contentWidth
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    id: headerBlock
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        id: headerTextColumn
                        Layout.fillWidth: true
                        spacing: 0

                        KantePlasmaHeading {
                            Layout.fillWidth: true
                            level: 3
                            pageTitle: true
                            text: root.mainViewMode === "stats" ? i18n("Statistics")
                                  : (root.mainViewMode === "filmday" ? i18n("Film day")
                                  : (root.mainViewMode === "trip" ? (root.tripSheetRef ? root.tripSheetRef.title : i18n("Trip"))
                                  : (root.mainViewMode === "manual"
                                     ? (root.editingStoppedTimesheet ? i18n("Edit entry") : i18n("Add entry"))
                                      : (BuildInfo.BUILD > 0 ? (i18n("Plasmai") + " #" + BuildInfo.BUILD) : i18n("Plasmai")))))
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 2

                            Kirigami.Icon {
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                source: root.connectionIcon()
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pointSize: KanteStyle.smallFont.pointSize
                                text: root.connectionLabel()
                            }

                            QQC2.BusyIndicator {
                                running: root.isBusy || root.connectionState === "connecting" || root.credentialsLoading
                                visible: running
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        KantePlasmaToolButton {
                            visible: root.isConfigured && root.mainViewMode === "main"
                            icon.name: "list-add"
                            text: i18n("Add entry")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.isBusy && root.connectionState !== "error"
                            onClicked: root.openManualEntry()
                            PlasmaComponents3.ToolTip.text: i18n("Add a manual time entry")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.isConfigured && root.mainViewMode === "main"
                                     && root.providerCapabilities.statistics
                            icon.name: "view-statistics"
                            text: i18n("Statistics")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.isBusy
                            onClicked: root.openStatsView()
                            PlasmaComponents3.ToolTip.text: i18n("Show statistics")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.isConfigured && root.mainViewMode === "main"
                                     && root.providerCapabilities.filmDays
                            icon.name: "view-calendar-day"
                            text: i18n("Film day")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.isBusy && root.connectionState !== "error"
                            onClicked: root.openFilmDayView()
                            PlasmaComponents3.ToolTip.text: i18n("Log a shooting day")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.isConfigured && root.mainViewMode === "main" && root.canEditTrips
                            icon.name: "mark-location"
                            text: i18n("Log trip")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.isBusy && !root.tripBusy && root.connectionState !== "error"
                            onClicked: root.openNewTrip()
                            PlasmaComponents3.ToolTip.text: i18n("Log a trip (Anfahrten plugin)")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.mainViewMode === "manual" || root.mainViewMode === "stats"
                                     || root.mainViewMode === "filmday" || root.mainViewMode === "trip"
                            icon.name: "go-previous"
                            text: i18n("Back")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            onClicked: root.returnToMainView()
                            PlasmaComponents3.ToolTip.text: i18n("Back to timer")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }

                QQC2.ComboBox {
                    KanteFieldSkin { control: parent }
                    id: profileSwitcher
                    Layout.fillWidth: true
                    visible: root.profiles.length > 1
                             && (root.mainViewMode === "main"
                                 || root.mainViewMode === "stats")
                             && !root.editingActiveEntry
                             && !root.editingStoppedTimesheet
                             && !(root.showNewActivityForm && root.compactPopupLayout)
                    model: root.profiles.map(function(p) { return p.name })
                    currentIndex: {
                        for (var i = 0; i < root.profiles.length; i++) {
                            if (root.profiles[i].id === (plasmoid.configuration.activeProfileId || "default")) {
                                return i
                            }
                        }
                        return 0
                    }
                    onActivated: function(index) {
                        if (index >= 0 && index < root.profiles.length) {
                            root.switchProfile(root.profiles[index].id)
                        }
                    }
                }

                Kirigami.PlaceholderMessage {
                    Layout.fillWidth: true
                    // Layout.preferredHeight ignores `visible` (Qt Quick Layouts still
                    // reserve it), so an explicit fixed height here would otherwise leave a
                    // permanent gap above the wide split view even while this is hidden.
                    Layout.preferredHeight: root.showSetupState ? Kirigami.Units.gridUnit * 8 : 0
                    visible: root.showSetupState
                    icon.name: "configure"
                    text: i18n("Connect a time tracker")
                    explanation: i18n("Add your service, server URL (if needed), and API token to start tracking from the panel.")
                    helpfulAction: Kirigami.Action {
                        text: i18n("Configure Plasmai")
                        icon.name: "configure"
                        onTriggered: root.openConfigure()
                    }
                }

                Kirigami.InlineMessage {
                    KanteMessageSkin { message: parent }
                    Layout.fillWidth: true
                    visible: root.showErrorState && !root.showSetupState
                    type: Kirigami.MessageType.Error
                    text: root.errorMessage
                    actions: [
                        Kirigami.Action {
                            text: i18n("Retry")
                            icon.name: "view-refresh"
                            onTriggered: root.hardReload()
                        },
                        Kirigami.Action {
                            text: i18n("Configure")
                            icon.name: "configure"
                            onTriggered: root.openConfigure()
                        }
                    ]
                }

                ManualEntryView {
                    id: manualEntryView
                    Component.onCompleted: root.manualEntryViewRef = manualEntryView
                    Component.onDestruction: {
                        if (root.manualEntryViewRef === manualEntryView) {
                            root.manualEntryViewRef = null
                        }
                    }
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "manual" && root.isConfigured
                    projectPickerModel: root.projectPickerModel
                    activityPickerModel: root.activityPickerModel
                    activitySectionTitles: root.activitySectionTitles
                    pickerOpenBelow: root.pickerOpenBelow
                    pickerViewport: popupScroll
                    busy: root.isBusy
                    configured: root.isConfigured
                    connectionOk: root.connectionState !== "error"
                    supportsBillableEdit: root.providerCapabilities.billableEdit
                    supportsTags: root.providerCapabilities.tags
                    tagLookupUrl: root.kimaiUrl
                    tagLookupToken: root.apiToken
                    showCreateActions: root.providerCapabilities.createEntities
                    editingExisting: root.editingStoppedTimesheet !== null && root.editingStoppedTimesheet !== undefined
                    onAboutToOpenPicker: function(projectField, activityField) {
                        root.updatePickerOpenDirection(projectField, activityField)
                    }
                    onProjectChosen: function(projectId) {
                        root.loadActivitiesForProject(projectId)
                    }
                    onSaveRequested: function(projectId, activityId, beginText, endText, description, billable, tags) {
                        root.createManualEntry(projectId, activityId, beginText, endText, description, billable, tags)
                    }
                    onCancelled: root.returnToMainView()
                    onCreateProjectRequested: root.openCreateEntity("project")
                    onCreateActivityRequested: root.openCreateEntity("activity")
                }

                StatsView {
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "stats" && root.isConfigured
                             && root.providerCapabilities.statistics
                    timesheets: root.statsTimesheets
                    customersById: root.customersById
                    todayTargetSeconds: root.todayTargetSeconds
                    weekTargetSeconds: root.weekTargetSeconds
                    hasWorkContract: root.hasWorkContract
                                     && root.providerCapabilities.workContract
                    workDayBegin: root.workDayBegin
                    workDayEnd: root.workDayEnd
                    supportsBillableFilter: root.providerCapabilities.billableFilter
                    tripSummary: root.statsTrips ? StatsData.tripKmSummary(root.statsTrips, new Date()) : null
                    onBackRequested: root.returnToMainView()
                    onNeedMoreHistory: function(rangeBegin, rangeEnd) {
                        root.loadStatsRange(rangeBegin, rangeEnd)
                    }
                }

                FilmDayView {
                    id: filmDayView
                    Component.onCompleted: root.filmDayViewRef = filmDayView
                    Component.onDestruction: {
                        if (root.filmDayViewRef === filmDayView) {
                            root.filmDayViewRef = null
                        }
                    }
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "filmday" && root.isConfigured
                             && root.providerCapabilities.filmDays
                    projectPickerModel: root.projectPickerModel
                    activityPickerModel: root.activityPickerModel
                    activitySectionTitles: root.activitySectionTitles
                    pickerOpenBelow: root.pickerOpenBelow
                    pickerViewport: popupScroll
                    busy: root.isBusy || root.loadingFilmDay
                    configured: root.isConfigured
                    connectionOk: root.connectionState !== "error"
                    showCreateActions: root.providerCapabilities.createEntities
                    onAboutToOpenPicker: function(projectField, activityField) {
                        root.updatePickerOpenDirection(projectField, activityField)
                    }
                    onProjectChosen: function(projectId) {
                        root.loadActivitiesForProject(projectId)
                    }
                    onProjectPicked: function(projectId) {
                        root.loadFilmDayForDate(root.filmDaySelectedDate)
                    }
                    onDayStepRequested: function(deltaDays) {
                        root.stepFilmDay(deltaDays)
                    }
                    onDayChosen: function(date) {
                        root.loadFilmDayForDate(date)
                    }
                    onSaveRequested: function(projectId, activityId, beginText, endText, filmDayFields) {
                        root.saveFilmDay(projectId, activityId, beginText, endText, filmDayFields)
                    }
                    onCancelled: root.returnToMainView()
                    onCreateProjectRequested: root.openCreateEntity("project")
                    onCreateActivityRequested: root.openCreateEntity("activity")
                }

                TripSheet {
                    id: tripSheet
                    Component.onCompleted: root.tripSheetRef = tripSheet
                    Component.onDestruction: {
                        if (root.tripSheetRef === tripSheet) {
                            root.tripSheetRef = null
                        }
                    }
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "trip" && root.mileageAvailable
                    busy: root.isBusy || root.tripBusy
                    configured: root.isConfigured
                    connectionOk: root.connectionState !== "error"
                    ping: root.mileagePing
                    meta: root.mileageMeta
                    vehicles: root.mileageVehicles
                    onSaveRequested: function(body, tripId, form) {
                        root.saveTrip(body, tripId, form)
                    }
                    onDeleteRequested: function(tripId) {
                        root.deleteTrip(tripId)
                    }
                    onCancelled: root.returnToMainView()
                }

                ColumnLayout {
                    id: mainPaneHost
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    // Also hidden (not just emptied by relayoutMainPane()) once the wide split
                    // view takes over, so it never reserves layout space in popupColumn.
                    visible: root.mainViewMode === "main" && !root.showSetupState && !popupRoot.splitActive

                // —— Hero —— (heroCard/listSection below are moved into the wide split-view
                // panes via popupRoot.relayoutMainPane() when there's room for both side by
                // side; see that function and wideSplitRow further down.)
                // System or Kante timer card; heroCard is what relayoutMainPane() moves.
                Loader {
                    id: heroCard
                    Layout.fillWidth: true
                    visible: item !== null && item.shown
                    sourceComponent: KanteStyle.active ? kanteTimerCard : systemTimerCard
                }

                Component {
                    id: systemTimerCard
                    TimerCard {
                        widget: root
                        popupItem: popupRoot
                        pickerScroll: popupScroll
                    }
                }

                Component {
                    id: kanteTimerCard
                    TimerCardKante {
                        widget: root
                        popupItem: popupRoot
                        pickerScroll: popupScroll
                    }
                }

                EntryLists {
                    id: listSection
                    widget: root
                    pickerScroll: popupScroll
                }
                } // main pane
            }
        }

        // Wide split view: heroCard/listSection are moved here (out of mainPaneHost, inside
        // popupScroll above) via relayoutMainPane() whenever the widget is wide enough — see
        // popupRoot.splitActive. Anchored below popupScroll itself (a plain sibling Item,
        // sized to hug its own remaining header content in that state) rather than to
        // something inside popupScroll's Flickable — anchoring across a Flickable boundary
        // doesn't track that content's layout changes reliably.
        RowLayout {
            id: wideSplitRow
            visible: popupRoot.splitActive
            anchors {
                top: popupScroll.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: Kirigami.Units.smallSpacing
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.ScrollView {
                id: wideLeftPane
                Layout.preferredWidth: Math.round(wideSplitRow.width * 0.42)
                Layout.minimumWidth: Kirigami.Units.gridUnit * 14
                Layout.fillHeight: true
                clip: true

                // A plain centered Item rather than a ScrollView: the timer card's content is
                // short and fixed, so pinning it to the top of a pane as tall as the favorites
                // list on the right left it looking stranded in empty space below. Centering
                // it vertically instead reads as a deliberate "now tracking" panel.
                ColumnLayout {
                    id: wideLeftCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Kirigami.Units.smallSpacing
                }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            PlasmaComponents3.ScrollView {
                id: wideRightScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: wideRightCol
                    width: wideRightScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing
                }
            }
        }

        // Labels/buttons steal right-clicks from the containment. Capture RMB
        // anywhere on the widget and open the standard applet context menu.
        MouseArea {
            anchors.fill: parent
            z: 1000
            acceptedButtons: Qt.RightButton
            onPressed: function(mouse) {
                root.openPlasmoidContextMenu(popupRoot, mouse.x, mouse.y)
            }
        }
    }

    PlasmaExtras.Menu {
        id: plasmoidContextMenu

        function rebuild() {
            clearMenuItems()
            var customs = Plasmoid.contextualActions
            var i
            for (i = 0; i < customs.length; i++) {
                var customAction = customs[i]
                if (!customAction || customAction.visible === false) {
                    continue
                }
                addMenuItem(plasmoidMenuItemComponent.createObject(plasmoidContextMenu, {
                    action: customAction
                }))
            }
            addMenuItem(plasmoidMenuItemComponent.createObject(plasmoidContextMenu, {
                separator: true
            }))
            var internalNames = ["alternatives", "configure", "remove"]
            for (i = 0; i < internalNames.length; i++) {
                var internalAction = Plasmoid.internalAction(internalNames[i])
                if (!internalAction || internalAction.visible === false) {
                    continue
                }
                addMenuItem(plasmoidMenuItemComponent.createObject(plasmoidContextMenu, {
                    action: internalAction
                }))
            }
        }
    }

    Component {
        id: plasmoidMenuItemComponent
        PlasmaExtras.MenuItem { }
    }

    Component.onCompleted: {
        Platform.setBackend(DesktopBackend.create(kwalletScript, idleScript, notifyScript,
            sharedConfigScript, catalogCacheScript))
        showNewActivityForm = !compactPopupLayout && plasmoid.configuration.desktopShowNewActivity
        hardReload()
    }

    Connections {
        target: plasmoid
        function onUserConfiguringChanged() {
            if (plasmoid.userConfiguring) {
                // Pull shared settings before editing so we don't save stale values.
                root.reloadCredentials()
            } else {
                // Persist first, then reload — otherwise a racing softReload can
                // re-apply the old shared.json and undo display changes until restart.
                root.persistSharedConfig(function() {
                    root.softReload()
                })
            }
        }
    }

    Connections {
        target: plasmoid.configuration
        function onProfilesJsonChanged() {
            if (!plasmoid.userConfiguring) {
                root.softReload()
            } else {
                root.reloadProfiles()
            }
        }
        function onActiveProfileIdChanged() {
            root.resetTrackingState()
            if (!plasmoid.userConfiguring) {
                root.softReload()
            } else {
                root.reloadProfiles()
            }
        }
        function onKimaiUrlChanged() {
            if (!plasmoid.userConfiguring) {
                root.softReload()
            } else {
                root.reloadProfiles()
            }
        }
        function onRefreshIntervalChanged() {
            pollTimer.interval = Math.max(10, plasmoid.configuration.refreshInterval) * 1000
        }
        function onRecentCountChanged() { root.refreshRecentTimesheets(true) }
        function onPinnedActivitiesChanged() { root.refreshPinnedEntries(true) }

        function onDesktopShowNewActivityChanged() { root.syncDisplayStateFromConfig() }
        function onPopupShowNewActivityChanged() { root.syncDisplayStateFromConfig() }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (!root.expanded) {
                return
            }
            root.sparklineNowTick++
            if (root.isConfigured && root.connectionState === "online") {
                root.refreshAll(true)
            } else {
                root.reloadCredentials(function() {
                    root.refreshAll(root.isConfigured)
                })
            }
        }
    }
}
