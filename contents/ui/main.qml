import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../code/kimaiApi.js" as KimaiApi
import "../code/timeTracker.js" as TimeTracker
import "../code/secret.js" as Secret
import "../code/profiles.js" as Profiles
import "../code/favorites.js" as Favorites
import "../code/sharedConfig.js" as SharedConfig
import "../code/colorDistinct.js" as ColorDistinct
import "../code/maintenanceCache.js" as CatalogCache
import "."

PlasmoidItem {
    id: root

    readonly property var invalidTimesheetId: null
    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/kwallet.sh"))
    readonly property string idleScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/idle.sh"))
    readonly property string notifyScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/notify.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/sharedConfig.sh"))

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
    property string mainViewMode: "main"  // main | manual | stats
    /** Inline editor for the running timesheet (start / project / activity). */
    property bool editingActiveEntry: false
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

    property var currentTimesheetId: invalidTimesheetId
    property string currentProject: ""
    property string currentActivity: ""
    property string currentCustomer: ""
    property string currentDescription: ""
    /** Last active timesheet object (for re-resolving names after catalog load). */
    property var activeTimesheet: null
    /** Recent entry waiting for switch confirmation while a timer is running. */
    property var pendingSwitchTimesheet: null
    property int elapsedSeconds: 0
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
    /** True when the description field differs from the last saved/server value. */
    property bool descriptionDirty: false
    /** Draft text from the description field (avoids fragile id lookups from root). */
    property string descriptionDraft: ""
    /** Focus tracked from the field itself (root cannot read descriptionEdit.id). */
    property bool descriptionFieldFocused: false

    property int todaySeconds: 0
    property int weekSeconds: 0
    property int todayTargetSeconds: 0
    property int weekTargetSeconds: 0
    property bool hasWorkContract: false
    property int totalsElapsedAnchor: 0
    property string currentCustomerColor: KimaiApi.DEFAULT_CUSTOMER_COLOR
    property string currentColorCategory: ""
    property var currentColorEntityId: null
    property var workPrefs: ({})
    property var todayTimesheets: []
    /** Extended timesheet cache for the statistics view (multiple weeks). */
    property var statsTimesheets: []
    property var statsRangeBeginMs: 0
    property var statsRangeEndMs: 0
    property bool loadingStats: false
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

    /** Rebuild distinction maps when the Plasma color scheme accents change. */
    readonly property string themePaletteKey: [
        String(Kirigami.Theme.highlightColor),
        String(Kirigami.Theme.positiveTextColor),
        String(Kirigami.Theme.neutralTextColor),
        String(Kirigami.Theme.negativeTextColor),
        String(Kirigami.Theme.linkColor),
        String(Kirigami.Theme.activeTextColor)
    ].join("|")
    onThemePaletteKeyChanged: root.rebuildColorMaps(true)

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

    readonly property int todayLiveSeconds:
        todaySeconds + (isTracking ? Math.max(0, elapsedSeconds - totalsElapsedAnchor) : 0)
    readonly property int weekLiveSeconds:
        weekSeconds + (isTracking ? Math.max(0, elapsedSeconds - totalsElapsedAnchor) : 0)
    readonly property int remainingWeekSeconds: hasWorkContract ? (weekTargetSeconds - weekLiveSeconds) : 0
    readonly property int remainingTodaySeconds: hasWorkContract ? (todayTargetSeconds - todayLiveSeconds) : 0

    readonly property var lastRecent: recentTimesheets.length > 0 ? recentTimesheets[0] : null
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
        if (typeof projectCombo !== "undefined" && projectCombo) {
            projectCombo.closePopup()
        }
        if (typeof activityCombo !== "undefined" && activityCombo) {
            activityCombo.closePopup()
        }
    }

    function updatePickerOpenDirection() {
        var fallbackIdeal = Kirigami.Units.gridUnit * 2 * 10
        var ideal = fallbackIdeal
        if (typeof projectCombo !== "undefined" && projectCombo) {
            ideal = Math.max(ideal, projectCombo.idealPopupHeight())
        }
        if (typeof activityCombo !== "undefined" && activityCombo) {
            ideal = Math.max(ideal, activityCombo.idealPopupHeight())
        }
        var minBelow = Math.min(projectCombo.spaceBelow(), activityCombo.spaceBelow())
        var minAbove = Math.min(projectCombo.spaceAbove(), activityCombo.spaceAbove())
        if (minBelow >= ideal) {
            pickerOpenBelow = true
        } else if (minAbove >= ideal) {
            pickerOpenBelow = false
        } else {
            pickerOpenBelow = minBelow >= minAbove
        }
    }

    // Panel: compact icon; desktop: full widget (so display settings apply in-place).
    preferredRepresentation: compactPopupLayout ? compactRepresentation : fullRepresentation
    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    // Translucent background uses the theme assets that participate in KWin blur.
    Plasmoid.backgroundHints: plasmoid.configuration.useBlurBackground
        ? PlasmaCore.Types.TranslucentBackground
        : PlasmaCore.Types.DefaultBackground

    Plasmoid.icon: connectionState === "error" ? "network-disconnect"
                     : isTracking ? "media-record" : "chronometer"
    // Keep stable: Plasma's config dialog title is "Settings for %1" / Plasmoid.title.
    Plasmoid.title: i18n("Plasmai")

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Toggle Plasmai tracking")
            icon.name: "chronometer"
            onTriggered: root.toggleTracking()
        },
        PlasmaCore.Action {
            text: i18n("Stop Plasmai tracking")
            icon.name: "media-playback-stop"
            onTriggered: root.requestStop()
        }
    ]

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

    Timer {
        id: pollTimer
        interval: Math.max(10, plasmoid.configuration.refreshInterval) * 1000
        running: root.isConfigured && root.connectionState !== "connecting"
        repeat: true
        onTriggered: {
            root.refreshActiveTimesheet(true)
            root.refreshWorkTotals()
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
        id: descriptionSavedFlashTimer
        interval: 900
        repeat: false
        onTriggered: root.descriptionSavedFlash = false
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
        root.prepareContextualActions()
        plasmoidContextMenu.visualParent = visualParent
        plasmoidContextMenu.rebuild()
        plasmoidContextMenu.open(x, y)
    }

    function sendNotification(summary, body) {
        Secret.notify(execSource, notifyScript, summary, body || "")
    }

    function checkIdle() {
        if (!isTracking || !plasmoid.configuration.idleStopEnabled) {
            return
        }
        Secret.runIdle(execSource, idleScript, function(idleMs, err) {
            if (idleMs < 0) {
                return
            }
            var thresholdMs = plasmoid.configuration.idleStopMinutes * 60 * 1000
            if (idleMs >= thresholdMs) {
                stopTracking(true)
            }
        })
    }

    function syncTrackerSession() {
        TimeTracker.applySession(providerId, activeProfile)
    }

    function openManualEntry() {
        if (!isConfigured) {
            return
        }
        editingActiveEntry = false
        mainViewMode = "manual"
        if (projectPickerModel.length === 0) {
            refreshProjects(false)
        }
        if (typeof manualEntryView !== "undefined" && manualEntryView) {
            manualEntryView.resetDefaults()
        }
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
            if (editingActiveEntry && activeEditView) {
                activeEditView.loadFromTimesheet(root.activeTimesheet)
            }
        })
    }

    function closeActiveEdit() {
        editingActiveEntry = false
    }

    function saveActiveEdit(projectId, activityId, beginText) {
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
            activity: activityId
        }, function(result) {
            isBusy = false
            if (result && result.ok) {
                clearError()
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
        dismissPickerPopups()
    }

    function createManualEntry(projectId, activityId, beginText, endText, description) {
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
        tracker.createTimesheet(kimaiUrl, apiToken, {
            begin: KimaiApi.localDateTimeString(beginDate),
            end: KimaiApi.localDateTimeString(endDate),
            project: projectId,
            activity: activityId,
            description: description || ""
        }, function(result) {
            isBusy = false
            if (result.ok) {
                clearError()
                returnToMainView()
                refreshRecentTimesheets()
                refreshWorkTotals()
                sendNotification(i18n("Entry added"), description || i18n("Manual time entry"))
            } else {
                setError(result.error)
            }
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
        Secret.loadSharedConfig(execSource, sharedConfigScript, function(shared) {
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
        Secret.persistSharedPatch(
            execSource, sharedConfigScript, plasmoid.configuration,
            SharedConfig.fromConfiguration(plasmoid.configuration),
            callback
        )
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
        Secret.load(execSource, kwalletScript, activeProfile.id, function(token, err) {
            if (err) {
                setError({ type: KimaiApi.ErrorType.Network, status: 0, detail: err })
                apiToken = ""
            } else {
                apiToken = token || ""
                syncTrackerSession()
                var needsUrl = providerMeta.needsUrl
                if (!token || (needsUrl && kimaiUrl.length === 0)) {
                    setError({ type: "config", status: 0, detail: "" })
                } else {
                    clearError()
                }
            }
            tokenLoaded = true
            if (callback) {
                callback()
            }
        })
    }

    function resetTrackingState() {
        isTracking = false
        editingActiveEntry = false
        currentTimesheetId = invalidTimesheetId
        currentProject = ""
        currentActivity = ""
        currentCustomer = ""
        currentDescription = ""
        activeTimesheet = null
        currentCustomerColor = KimaiApi.DEFAULT_CUSTOMER_COLOR
        currentColorCategory = ""
        currentColorEntityId = null
        elapsedSeconds = 0
        descriptionSavedFlash = false
        descriptionSavedFlashTimer.stop()
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

    function applyActiveTimesheet(timesheet) {
        if (!timesheet) {
            if (isTracking) {
                resetTrackingState()
            }
            return
        }

        isTracking = true
        activeTimesheet = timesheet
        currentTimesheetId = timesheet.id
        currentProject = KimaiApi.displayProjectName(timesheet, projects)
        currentActivity = KimaiApi.displayActivityName(timesheet, allActivities, activitiesByProject)
        currentCustomer = KimaiApi.customerNameFromTimesheet(timesheet, customersById)
        currentCustomerColor = KimaiApi.customerColorFromTimesheet(timesheet, customersById)
        var barInfo = KimaiApi.barColorInfoFromTimesheet(timesheet, customersById)
        currentColorCategory = barInfo.category
        currentColorEntityId = barInfo.id
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
        descriptionSavedFlash = false
        lastError = null
        userMessage = ""
        tracker.patchTimesheet(kimaiUrl, apiToken, currentTimesheetId, { description: text }, function(result) {
            savingDescription = false
            if (result && result.ok) {
                syncDescriptionField(text)
                clearError()
                descriptionSavedFlash = true
                descriptionSavedFlashTimer.restart()
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
                        activityCombo.currentIndex = a
                        return
                    }
                }
            }
            activityCombo.currentIndex = -1
            return
        }
        setError(result.error)
        activities = []
        activityPickerModel = []
        activityCombo.currentIndex = -1
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
        projectCombo.currentIndex = idx
        selectedProjectId = projectId
        tracker.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
            applyActivitiesResult(projectId, result, activityIdToSelect)
        })
    }

    function preloadLastActivity() {
        if (isTracking || !lastRecent || !isConfigured) {
            return
        }
        var pid = KimaiApi.projectId(lastRecent)
        var aid = KimaiApi.activityId(lastRecent)
        if (!pid || !aid) {
            return
        }
        if (projectPickerModel.length === 0) {
            return
        }
        selectProjectById(pid, aid)
        if (typeof descriptionField !== "undefined" && descriptionField) {
            descriptionField.text = lastRecent.description || ""
        }
    }

    function continueLastActivity() {
        if (!lastRecent) {
            return
        }
        restartFromRecent(lastRecent)
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
                }
            )
        })
    }

    function applyThemeColorPalette() {
        ColorDistinct.setThemePalette([
            Kirigami.Theme.highlightColor,
            Kirigami.Theme.positiveTextColor,
            Kirigami.Theme.neutralTextColor,
            Kirigami.Theme.negativeTextColor,
            Kirigami.Theme.linkColor,
            Kirigami.Theme.activeTextColor,
            Kirigami.Theme.visitedLinkColor
        ])
    }

    function rebuildColorMaps(force) {
        root.applyThemeColorPalette()
        var distinctionOn = providerCapabilities.colorDistinction
            && plasmoid.configuration.colorDistinctionEnabled !== false
        ColorDistinct.configure(
            distinctionOn,
            plasmoid.configuration.colorSimilarityPercent || 22
        )
        var extra = (allActivities || []).slice()
        if (activities && activities.length) {
            for (var ai = 0; ai < activities.length; ai++) {
                extra.push(activities[ai])
            }
        }
        var acts = ColorDistinct.flattenActivitiesByProject(activitiesByProject, extra)
        ColorDistinct.rebuild(customers, projects, acts, !!force)
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
            var barInfo = KimaiApi.barColorInfoFromTimesheet(activeTimesheet, customersById)
            currentColorCategory = barInfo.category
            currentColorEntityId = barInfo.id
            if (editingActiveEntry) {
                Qt.callLater(function() {
                    if (editingActiveEntry && typeof activeEditView !== "undefined" && activeEditView) {
                        activeEditView.loadFromTimesheet(root.activeTimesheet)
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
            rebuildColorMaps()
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
                        rebuildColorMaps()
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
    }

    function loadActivitiesForProject(projectId) {
        selectedProjectId = projectId || null
        if (!isConfigured || !projectId) {
            activities = []
            activityPickerModel = []
            activityCombo.currentIndex = -1
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
                applyActiveTimesheet(result.data)
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
                    applyActiveTimesheet(startResult.data)
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
            switchToActivity(entry.projectId, entry.activityId, entry.projectName, entry.activityName, "")
        } else {
            startTracking(entry.projectId, entry.activityId, entry.projectName, entry.activityName, "")
        }
    }

    function toggleTracking() {
        if (!isConfigured) {
            openConfigure()
            return
        }
        if (isTracking) {
            requestStop()
        } else if (recentTimesheets.length > 0) {
            restartFromRecent(recentTimesheets[0])
        } else if (pinnedEntries.length > 0) {
            startPinned(pinnedEntries[0])
        } else {
            expanded = !expanded
        }
    }

    function requestStop() {
        if (!isConfigured || isBusy || !isTracking || currentTimesheetId === invalidTimesheetId) {
            return
        }
        if (plasmoid.configuration.confirmBeforeStop) {
            stopConfirmDialog.open()
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
                    || result.data || timesheet)
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
            userMessage = i18n("Already tracking this activity")
            return
        }

        pendingSwitchTimesheet = timesheet
        switchRecentDialog.open()
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

    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        Layout.minimumWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: Kirigami.Units.iconSizes.medium
        Layout.preferredWidth: Layout.minimumWidth

        onClicked: root.expanded = !root.expanded

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: root.isTracking
                   ? Qt.rgba(Kirigami.Theme.positiveTextColor.r,
                             Kirigami.Theme.positiveTextColor.g,
                             Kirigami.Theme.positiveTextColor.b, 0.12)
                   : "transparent"
            border.width: root.isTracking ? 1 : 0
            border.color: Qt.rgba(Kirigami.Theme.positiveTextColor.r,
                                  Kirigami.Theme.positiveTextColor.g,
                                  Kirigami.Theme.positiveTextColor.b, 0.35)
        }

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                source: root.connectionState === "error" ? "network-disconnect"
                        : root.isTracking ? "media-record" : "chronometer"
                active: compactRoot.containsMouse
                color: root.isTracking ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
            }

            PlasmaComponents3.Label {
                visible: root.panelProjectLabel.length > 0
                text: root.panelProjectLabel
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.maximumWidth: Kirigami.Units.gridUnit * 10
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            PlasmaComponents3.Label {
                visible: root.isTracking && plasmoid.configuration.showElapsedInPanel
                text: KimaiApi.formatDuration(root.elapsedSeconds)
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: true
            }
        }
    }

    fullRepresentation: Item {
        id: popupRoot
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

        function scheduleSparkCutouts() {
            sparkCutoutTimer.restart()
        }

        property var sparklineItem: null

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

        QQC2.Dialog {
            id: stopConfirmDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("Stop tracking?")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 18, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

            contentItem: PlasmaComponents3.Label {
                text: i18n("Stop tracking %1 · %2?", root.currentProject, root.currentActivity)
                wrapMode: Text.WordWrap
            }

            onAccepted: root.stopTracking(false)
        }

        QQC2.Dialog {
            id: switchRecentDialog
            parent: popupRoot
            anchors.centerIn: parent
            title: i18n("Switch activity?")
            modal: true
            width: Math.min(Kirigami.Units.gridUnit * 20, popupRoot.width * 0.95)
            standardButtons: QQC2.Dialog.NoButton

            readonly property string pendingProject: root.pendingSwitchTimesheet
                ? KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.projects)
                : ""
            readonly property string pendingActivity: root.pendingSwitchTimesheet
                ? KimaiApi.displayActivityName(
                    root.pendingSwitchTimesheet, root.allActivities, root.activitiesByProject)
                : ""

            contentItem: PlasmaComponents3.Label {
                wrapMode: Text.WordWrap
                text: i18n("Stop %1 · %2 and start %3 · %4?",
                           root.currentProject, root.currentActivity,
                           switchRecentDialog.pendingProject, switchRecentDialog.pendingActivity)
            }

            footer: QQC2.DialogButtonBox {
                PlasmaComponents3.Button {
                    text: i18n("Switch")
                    QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.AcceptRole
                }
                PlasmaComponents3.Button {
                    text: i18n("Cancel")
                    QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                }
            }

            onAccepted: root.confirmSwitchFromRecent()
            onRejected: root.pendingSwitchTimesheet = null
            onDiscarded: root.pendingSwitchTimesheet = null
        }

        Connections {
            target: popupScroll.contentItem
            ignoreUnknownSignals: true
            function onContentYChanged() {
                if (projectCombo.popupOpen || activityCombo.popupOpen) {
                    root.dismissPickerPopups()
                }
            }
            function onMovementStarted() {
                root.dismissPickerPopups()
            }
            function onFlickStarted() {
                root.dismissPickerPopups()
            }
        }

        PlasmaComponents3.ScrollView {
            id: popupScroll
            anchors {
                fill: parent
                margins: Kirigami.Units.smallSpacing
            }
            clip: true
            // Always reserve space for the overlay scrollbar so right-aligned
            // labels and wide filter rows are not clipped underneath it.
            readonly property int scrollGutter: slimScrollBar.width + Kirigami.Units.smallSpacing * 2
            contentWidth: Math.max(0, width - scrollGutter)
            rightPadding: 0
            leftPadding: 0

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
                    color: Kirigami.Theme.textColor
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
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaExtras.Heading {
                        Layout.fillWidth: true
                        level: 3
                        text: root.mainViewMode === "stats" ? i18n("Statistics")
                              : (root.mainViewMode === "manual" ? i18n("Add entry") : i18n("Plasmai"))
                    }

                    PlasmaComponents3.ToolButton {
                        visible: root.isConfigured && root.mainViewMode === "main"
                        icon.name: "list-add"
                        text: i18n("Add entry")
                        display: QQC2.AbstractButton.IconOnly
                        enabled: !root.isBusy && root.connectionState !== "error"
                        onClicked: root.openManualEntry()
                        PlasmaComponents3.ToolTip.text: i18n("Add a manual time entry")
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    PlasmaComponents3.ToolButton {
                        visible: root.isConfigured && root.mainViewMode === "main"
                                 && root.providerCapabilities.statistics
                        icon.name: "view-statistics"
                        text: i18n("Statistics")
                        display: QQC2.AbstractButton.IconOnly
                        enabled: !root.isBusy
                        onClicked: root.openStatsView()
                        PlasmaComponents3.ToolTip.text: i18n("Show statistics")
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    PlasmaComponents3.ToolButton {
                        visible: root.mainViewMode === "manual" || root.mainViewMode === "stats"
                        icon.name: "go-previous"
                        text: i18n("Back")
                        display: QQC2.AbstractButton.IconOnly
                        onClicked: root.returnToMainView()
                        PlasmaComponents3.ToolTip.text: i18n("Back to timer")
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }

                QQC2.ComboBox {
                    id: profileSwitcher
                    Layout.fillWidth: true
                    visible: root.profiles.length > 1
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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: root.connectionIcon()
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: root.connectionLabel()
                    }

                    QQC2.BusyIndicator {
                        running: root.isBusy || root.connectionState === "connecting" || root.credentialsLoading
                        visible: running
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                }

                Kirigami.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 8
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
                    Layout.fillWidth: true
                    visible: root.showErrorState
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
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "manual" && root.isConfigured
                    projectPickerModel: root.projectPickerModel
                    activityPickerModel: root.activityPickerModel
                    activitySectionTitles: root.activitySectionTitles
                    pickerOpenBelow: root.pickerOpenBelow
                    busy: root.isBusy
                    configured: root.isConfigured
                    connectionOk: root.connectionState !== "error"
                    onAboutToOpenPicker: root.updatePickerOpenDirection()
                    onProjectChosen: function(projectId) {
                        root.loadActivitiesForProject(projectId)
                    }
                    onSaveRequested: function(projectId, activityId, beginText, endText, description) {
                        root.createManualEntry(projectId, activityId, beginText, endText, description)
                    }
                    onCancelled: root.returnToMainView()
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
                    onBackRequested: root.returnToMainView()
                    onNeedMoreHistory: function(rangeBegin, rangeEnd) {
                        root.loadStatsRange(rangeBegin, rangeEnd)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: root.mainViewMode === "main"

                // —— Hero ——
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.isConfigured && !root.showSetupState
                    radius: 6
                    color: root.isTracking
                           ? Qt.rgba(Kirigami.Theme.positiveTextColor.r,
                                     Kirigami.Theme.positiveTextColor.g,
                                     Kirigami.Theme.positiveTextColor.b, 0.08)
                           : Qt.rgba(Kirigami.Theme.textColor.r,
                                     Kirigami.Theme.textColor.g,
                                     Kirigami.Theme.textColor.b, 0.04)
                    border.width: 1
                    border.color: root.isTracking
                                  ? Qt.rgba(Kirigami.Theme.positiveTextColor.r,
                                            Kirigami.Theme.positiveTextColor.g,
                                            Kirigami.Theme.positiveTextColor.b, 0.28)
                                  : Qt.rgba(Kirigami.Theme.textColor.r,
                                            Kirigami.Theme.textColor.g,
                                            Kirigami.Theme.textColor.b, 0.12)
                    implicitHeight: heroColumn.implicitHeight + Kirigami.Units.smallSpacing * 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        anchors.topMargin: Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.35))
                        anchors.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        ColumnLayout {
                            id: heroColumn
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            LoadingRow {
                                Layout.fillWidth: true
                                visible: root.loadingActive && !root.isTracking && root.currentProject.length === 0
                            }

                            RowLayout {
                                id: trackingHeader
                                Layout.fillWidth: true
                                visible: root.isTracking
                                spacing: Kirigami.Units.smallSpacing
                                z: 3
                                onWidthChanged: daySparkline.scheduleHeaderCutouts()
                                onHeightChanged: daySparkline.scheduleHeaderCutouts()
                                onVisibleChanged: daySparkline.scheduleHeaderCutouts()

                                PlasmaComponents3.Label {
                                    id: elapsedLabel
                                    Layout.alignment: Qt.AlignVCenter
                                    text: KimaiApi.formatDuration(root.elapsedSeconds)
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 6
                                    font.bold: true
                                    color: Kirigami.Theme.positiveTextColor
                                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                                }

                                Item { Layout.fillWidth: true }

                                PlasmaComponents3.Label {
                                    id: customerLabel
                                    visible: root.currentCustomer.length > 0
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.maximumWidth: trackingHeader.width * 0.55
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    text: root.currentCustomer
                                    opacity: 0.9
                                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                                    onVisibleChanged: daySparkline.scheduleHeaderCutouts()
                                }
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                visible: !root.loadingActive && !root.isTracking
                                text: i18n("Not tracking")
                                font.bold: true
                                opacity: 0.85
                            }

                            DaySparkline {
                                id: daySparkline
                                Layout.fillWidth: true
                                // Pull sky arcs up under the timer / customer row
                                Layout.topMargin: {
                                    if (!(visible && root.isTracking && trackingHeader.visible
                                          && plasmoid.configuration.showSparklineArcs)) {
                                        return 1
                                    }
                                    return -Math.round(trackingHeader.height * 0.984)
                                }
                                Layout.bottomMargin: 0
                                z: 1
                                visible: root.isConfigured && root.showSparklineHere
                                entries: root.todayTimesheets
                                targetSeconds: root.todayTargetSeconds
                                workDayBegin: root.workDayBegin
                                workDayEnd: root.workDayEnd
                                latitude: plasmoid.configuration.latitude
                                longitude: plasmoid.configuration.longitude
                                nowTick: root.elapsedSeconds
                                showArcs: plasmoid.configuration.showSparklineArcs
                                headerMaskItems: [elapsedLabel, customerLabel]
                                Component.onCompleted: {
                                    popupRoot.sparklineItem = daySparkline
                                    scheduleHeaderCutouts()
                                }
                                Component.onDestruction: {
                                    if (popupRoot.sparklineItem === daySparkline) {
                                        popupRoot.sparklineItem = null
                                    }
                                }
                                onWidthChanged: scheduleHeaderCutouts()
                                onHeightChanged: scheduleHeaderCutouts()
                                onVisibleChanged: scheduleHeaderCutouts()
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                visible: root.isTracking && heroColumn.width >= Kirigami.Units.gridUnit * 16
                                text: root.currentProject + " · " + root.currentActivity
                                elide: Text.ElideRight
                                font.bold: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.isTracking && heroColumn.width < Kirigami.Units.gridUnit * 16
                                spacing: 0
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.currentProject
                                    elide: Text.ElideRight
                                    font.bold: true
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.currentActivity
                                    elide: Text.ElideRight
                                    opacity: 0.85
                                }
                            }

                            ColumnLayout {
                                id: workSummaryBlock
                                Layout.fillWidth: true
                                visible: root.isTracking || root.showWorkSummaryHere
                                spacing: Kirigami.Units.smallSpacing / 2

                                // Beside only when there is clear room for stats + both actions.
                                readonly property bool actionsBeside: root.isTracking
                                    && root.showWorkSummaryHere
                                    && workSummaryBlock.width >= Kirigami.Units.gridUnit * 22

                                // Stats on their own row (full width). Actions sit beside only when wide.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    visible: root.showWorkSummaryHere || workSummaryBlock.actionsBeside

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                        visible: root.showWorkSummaryHere
                                        opacity: root.showWorkSummaryHere ? 1 : 0
                                        spacing: 1
                                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing
                                            PlasmaComponents3.Label {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: i18n("Today %1", KimaiApi.formatDurationShort(root.todayLiveSeconds))
                                                    + " · "
                                                    + i18n("Week %1", KimaiApi.formatDurationShort(root.weekLiveSeconds))
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                opacity: 0.8
                                                elide: Text.ElideRight
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: root.hasWorkContract
                                                     && (root.todayTargetSeconds > 0 || root.weekTargetSeconds > 0)
                                            spacing: Kirigami.Units.smallSpacing

                                            PlasmaComponents3.Label {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                visible: root.todayTargetSeconds > 0 || root.weekTargetSeconds > 0
                                                text: {
                                                    var bits = []
                                                    if (root.todayTargetSeconds > 0) {
                                                        bits.push(root.remainingTodayText())
                                                    }
                                                    if (root.weekTargetSeconds > 0) {
                                                        bits.push(root.remainingWeekText())
                                                    }
                                                    return bits.join(" · ")
                                                }
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                opacity: 0.75
                                                elide: Text.ElideRight
                                                color: (root.remainingTodaySeconds < 0 || root.remainingWeekSeconds < 0)
                                                       ? Kirigami.Theme.neutralTextColor
                                                       : Kirigami.Theme.textColor
                                            }
                                        }
                                    }

                                    PlasmaComponents3.ToolButton {
                                        id: editActiveBesideButton
                                        visible: workSummaryBlock.actionsBeside
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        Layout.preferredWidth: implicitWidth
                                        enabled: !root.isBusy
                                        text: i18n("Edit")
                                        icon.name: "document-edit"
                                        display: QQC2.AbstractButton.IconOnly
                                        down: root.editingActiveEntry
                                        onClicked: {
                                            if (root.editingActiveEntry) {
                                                root.closeActiveEdit()
                                            } else {
                                                root.openActiveEdit()
                                            }
                                        }
                                        PlasmaComponents3.ToolTip.text: i18n("Edit start, project, and activity")
                                        PlasmaComponents3.ToolTip.visible: hovered
                                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    }

                                    PlasmaComponents3.Button {
                                        id: stopBesideButton
                                        visible: workSummaryBlock.actionsBeside
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        Layout.preferredWidth: implicitWidth
                                        enabled: !root.isBusy
                                        text: i18n("Stop")
                                        icon.name: "media-playback-stop"
                                        onClicked: root.requestStop()
                                    }
                                }

                                // Narrow / no-summary: Edit + Stop on the line under the stats
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.isTracking && !workSummaryBlock.actionsBeside
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents3.ToolButton {
                                        enabled: !root.isBusy
                                        text: i18n("Edit")
                                        icon.name: "document-edit"
                                        display: QQC2.AbstractButton.IconOnly
                                        down: root.editingActiveEntry
                                        onClicked: {
                                            if (root.editingActiveEntry) {
                                                root.closeActiveEdit()
                                            } else {
                                                root.openActiveEdit()
                                            }
                                        }
                                        PlasmaComponents3.ToolTip.text: i18n("Edit start, project, and activity")
                                        PlasmaComponents3.ToolTip.visible: hovered
                                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    }

                                    PlasmaComponents3.Button {
                                        Layout.fillWidth: true
                                        enabled: !root.isBusy
                                        text: i18n("Stop")
                                        icon.name: "media-playback-stop"
                                        onClicked: root.requestStop()
                                    }
                                }
                            }

                            ActiveEditView {
                                id: activeEditView
                                Layout.fillWidth: true
                                visible: root.isTracking && root.editingActiveEntry
                                timesheet: root.activeTimesheet
                                elapsedSeconds: root.elapsedSeconds
                                projectPickerModel: root.projectPickerModel
                                activityPickerModel: root.activityPickerModel
                                activitySectionTitles: root.activitySectionTitles
                                pickerOpenBelow: root.pickerOpenBelow
                                busy: root.isBusy
                                configured: root.isConfigured
                                connectionOk: root.connectionState !== "error"
                                onAboutToOpenPicker: root.updatePickerOpenDirection()
                                onProjectChosen: function(projectId) {
                                    root.loadActivitiesForProject(projectId)
                                }
                                onSaveRequested: function(projectId, activityId, beginText) {
                                    root.saveActiveEdit(projectId, activityId, beginText)
                                }
                                onCancelled: root.closeActiveEdit()
                            }

                            Item {
                                id: descriptionFieldWrap
                                Layout.fillWidth: true
                                visible: root.isTracking
                                // Avoid anchors.fill ↔ implicitHeight feedback (zero-height field).
                                height: descriptionEdit.implicitHeight
                                implicitHeight: descriptionEdit.implicitHeight

                                QQC2.TextField {
                                    id: descriptionEdit
                                    width: parent.width
                                    enabled: !root.savingDescription
                                    placeholderText: i18n("Description")
                                    rightPadding: descriptionSaveButton.visible
                                        ? descriptionSaveButton.width + Kirigami.Units.smallSpacing * 2
                                        : leftPadding

                                    function applyDraftFromRoot() {
                                        if (text === root.descriptionDraft) {
                                            return
                                        }
                                        root.suppressDescHandler = true
                                        text = root.descriptionDraft
                                        root.suppressDescHandler = false
                                    }

                                    Connections {
                                        target: root
                                        function onDescriptionDraftChanged() {
                                            descriptionEdit.applyDraftFromRoot()
                                        }
                                    }

                                    Component.onCompleted: applyDraftFromRoot()
                                    onVisibleChanged: {
                                        if (visible) {
                                            applyDraftFromRoot()
                                        }
                                    }

                                    onActiveFocusChanged: {
                                        root.descriptionFieldFocused = activeFocus
                                    }

                                    onTextChanged: {
                                        if (root.suppressDescHandler) {
                                            return
                                        }
                                        root.descriptionDraft = text
                                        root.descriptionDirty = (text !== root.currentDescription)
                                    }

                                    onAccepted: root.saveCurrentDescription()
                                    Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            root.saveCurrentDescription()
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Escape) {
                                            root.syncDescriptionField(root.currentDescription)
                                            event.accepted = true
                                        }
                                    }
                                }

                                PlasmaComponents3.ToolButton {
                                    id: descriptionSaveButton
                                    z: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: Kirigami.Units.smallSpacing / 2
                                    anchors.verticalCenter: descriptionEdit.verticalCenter
                                    width: Math.round(Kirigami.Units.iconSizes.small * 1.4)
                                    height: width
                                    padding: 0
                                    display: QQC2.AbstractButton.IconOnly
                                    icon.name: root.descriptionSavedFlash
                                               ? "dialog-ok-apply"
                                               : (root.savingDescription ? "view-refresh"
                                                  : "document-save")
                                    text: i18n("Save description")
                                    visible: root.descriptionSavedFlash
                                             || root.savingDescription
                                             || root.descriptionDirty
                                    enabled: root.descriptionDirty
                                             && !root.savingDescription
                                             && !root.descriptionSavedFlash
                                    onClicked: root.saveCurrentDescription()
                                    PlasmaComponents3.ToolTip.text: text
                                    PlasmaComponents3.ToolTip.visible: hovered
                                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                                }
                            }

                            PlasmaComponents3.Button {
                                Layout.fillWidth: true
                                visible: root.showContinueHere && !root.isTracking && root.lastRecent
                                enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                                text: i18n("Continue · %1 · %2",
                                           KimaiApi.displayProjectName(root.lastRecent, root.projects),
                                           KimaiApi.displayActivityName(root.lastRecent, root.allActivities, root.activitiesByProject))
                                icon.name: "media-playback-start"
                                onClicked: root.continueLastActivity()
                            }
                        }
                    }
                }

                // —— Favorites ——
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    opacity: root.showFavoritesHere ? 1 : 0
                    visible: opacity > 0 && root.isConfigured
                             && (root.pinnedEntries.length > 0 || root.loadingPinned || !root.compactPopupLayout)
                    text: i18n("Favorites")
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                GridLayout {
                    id: favoritesGrid
                    Layout.fillWidth: true
                    opacity: root.showFavoritesHere && !root.loadingPinned && root.pinnedEntries.length > 0 ? 1 : 0
                    visible: opacity > 0
                    columns: Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * 7)))
                    rowSpacing: Kirigami.Units.smallSpacing
                    columnSpacing: Kirigami.Units.smallSpacing
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Repeater {
                        model: root.favoritesVisibleCount
                        delegate: ActivityListRow {
                            Layout.fillWidth: true
                            customerColor: root.pinnedEntries[index].customerColor || KimaiApi.DEFAULT_CUSTOMER_COLOR
                            colorCategory: root.pinnedEntries[index].colorCategory || ""
                            entityId: root.pinnedEntries[index].entityId !== undefined
                                      ? root.pinnedEntries[index].entityId : null
                            titleText: root.pinnedEntries[index].activityName
                            subtitleText: {
                                var entry = root.pinnedEntries[index]
                                var bits = []
                                if (entry.customerName) {
                                    bits.push(entry.customerName)
                                }
                                if (entry.projectName) {
                                    bits.push(entry.projectName)
                                }
                                return bits.join(" · ")
                            }
                            rowEnabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                            showPlayIcon: true
                            onClicked: root.startPinned(root.pinnedEntries[index])
                            tooltipText: {
                                var entry = root.pinnedEntries[index]
                                var bits = []
                                if (entry.customerName) {
                                    bits.push(entry.customerName)
                                }
                                if (entry.projectName) {
                                    bits.push(entry.projectName)
                                }
                                if (entry.activityName) {
                                    bits.push(entry.activityName)
                                }
                                return bits.join(" · ")
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    opacity: root.showFavoritesHere
                             && root.isConfigured && !root.loadingPinned
                             && root.pinnedEntries.length === 0 && !root.compactPopupLayout ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("No favorites yet")
                        font.bold: true
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("Pin frequent project/activity pairs in the widget settings.")
                        opacity: 0.75
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    PlasmaComponents3.Button {
                        text: i18n("Configure favorites")
                        icon.name: "configure"
                        onClicked: root.openConfigure()
                    }
                }

                LoadingRow {
                    Layout.fillWidth: true
                    visible: root.showFavoritesHere && root.loadingPinned && root.pinnedEntries.length === 0
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: root.showFavoritesHere
                             && root.compactPopupLayout
                             && root.pinnedEntries.length > root.favoritesVisibleCount
                    text: i18n("+%1 more in settings", root.pinnedEntries.length - root.favoritesVisibleCount)
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                // —— Recent ——
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    opacity: root.showRecentHere && root.isConfigured ? 1 : 0
                    visible: opacity > 0
                    text: i18n("Recent")
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    opacity: root.showRecentHere && root.isConfigured ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Repeater {
                        model: root.loadingRecent && root.recentTimesheets.length === 0 ? 0 : root.recentVisibleCount
                        delegate: ActivityListRow {
                            Layout.fillWidth: true
                            readonly property var barInfo: KimaiApi.barColorInfoFromTimesheet(
                                root.recentTimesheets[index], root.customersById)
                            customerColor: barInfo.color
                            colorCategory: barInfo.category
                            entityId: barInfo.id
                            titleText: KimaiApi.displayActivityName(
                                root.recentTimesheets[index], root.allActivities, root.activitiesByProject)
                            subtitleText: {
                                var ts = root.recentTimesheets[index]
                                var bits = [KimaiApi.displayProjectName(ts, root.projects)]
                                var secs = KimaiApi.timesheetDurationSeconds(ts)
                                if (secs > 0) {
                                    bits.push(KimaiApi.formatDurationShort(secs))
                                }
                                bits.push(root.formatRelativeTime(ts.end || ts.begin))
                                return bits.join(" · ")
                            }
                            rowEnabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                            onClicked: root.requestRestartFromRecent(root.recentTimesheets[index])
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.loadingRecent && root.recentTimesheets.length === 0
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: root.compactPopupLayout ? 2 : 3
                            LoadingRow { Layout.fillWidth: true }
                        }
                    }

                    Kirigami.PlaceholderMessage {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                        visible: !root.loadingRecent && root.recentTimesheets.length === 0 && root.connectionState !== "error"
                        icon.name: "view-history"
                        text: i18n("No recent activities")
                        explanation: i18n("Start tracking to build your recent list.")
                    }
                }

                // —— New / switch ——
                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    opacity: root.showNewActivityHere && root.isConfigured
                             && root.compactPopupLayout && !root.showNewActivityForm ? 1 : 0
                    visible: opacity > 0
                    text: root.isTracking ? i18n("Switch to another activity…") : i18n("Start something else…")
                    icon.name: "list-add"
                    onClicked: root.showNewActivityForm = true
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    opacity: root.showNewActivityHere && root.isConfigured && root.showNewActivityForm ? 1 : 0
                    visible: opacity > 0
                    text: root.isTracking ? i18n("Switch activity") : i18n("New activity")
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                LoadingRow {
                    Layout.fillWidth: true
                    visible: root.showNewActivityHere && root.showNewActivityForm && root.loadingProjects
                             && root.projectPickerModel.length === 0
                }

                SearchableCombo {
                    id: projectCombo
                    Layout.fillWidth: true
                    visible: root.showNewActivityHere && root.showNewActivityForm && !root.loadingProjects
                    enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                    items: root.projectPickerModel
                    placeholderText: i18n("Select project…")
                    useSharedDirection: true
                    openBelow: root.pickerOpenBelow
                    onAboutToOpen: root.updatePickerOpenDirection()
                    onActivated: function(index) {
                        if (index < 0 || index >= items.length) {
                            root.loadActivitiesForProject(0)
                            return
                        }
                        var project = items[index].value
                        root.loadActivitiesForProject(project.id)
                    }
                }

                SearchableCombo {
                    id: activityCombo
                    Layout.fillWidth: true
                    visible: root.showNewActivityHere && root.showNewActivityForm
                             && (!root.loadingProjects || root.activityPickerModel.length > 0)
                    enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                             && !!root.selectedProjectId
                    items: root.activityPickerModel
                    placeholderText: i18n("Select activity…")
                    sectionTitleMap: root.activitySectionTitles
                    useSharedDirection: true
                    openBelow: root.pickerOpenBelow
                    onAboutToOpen: root.updatePickerOpenDirection()
                }

                QQC2.TextField {
                    id: descriptionField
                    Layout.fillWidth: true
                    visible: root.showNewActivityHere && root.showNewActivityForm
                    enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                    placeholderText: i18n("Description (optional)")
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.showNewActivityHere && root.showNewActivityForm
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Button {
                        Layout.fillWidth: true
                        enabled: root.isConfigured && !root.isBusy && !root.isTracking && root.connectionState !== "error"
                                 && projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0
                        text: i18n("Start")
                        icon.name: "media-playback-start"
                        onClicked: {
                            var project = projectCombo.currentItem.value
                            var activity = activityCombo.currentItem.value
                            root.startTracking(project.id, activity.id, project.name, activity.name, descriptionField.text)
                        }
                    }

                    PlasmaComponents3.Button {
                        Layout.fillWidth: true
                        visible: root.isTracking
                        enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                                 && projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0
                        text: i18n("Switch")
                        icon.name: "media-skip-forward"
                        onClicked: {
                            var project = projectCombo.currentItem.value
                            var activity = activityCombo.currentItem.value
                            root.switchToActivity(project.id, activity.id, project.name, activity.name, descriptionField.text)
                        }
                    }

                    PlasmaComponents3.Button {
                        visible: root.compactPopupLayout
                        text: i18n("Cancel")
                        onClicked: root.showNewActivityForm = false
                    }
                }
                } // main pane
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
        function onColorDistinctionEnabledChanged() { root.rebuildColorMaps(true) }
        function onColorSimilarityPercentChanged() { root.rebuildColorMaps(true) }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (!root.expanded) {
                return
            }
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
