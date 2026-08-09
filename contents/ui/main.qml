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
import "../code/secret.js" as Secret
import "../code/profiles.js" as Profiles
import "../code/favorites.js" as Favorites
import "../code/sharedConfig.js" as SharedConfig
import "."

PlasmoidItem {
    id: root

    readonly property int invalidTimesheetId: -1
    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/kwallet.sh"))
    readonly property string idleScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/idle.sh"))
    readonly property string notifyScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/notify.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/sharedConfig.sh"))

    property var profiles: Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl)
    property var activeProfile: Profiles.profileById(profiles, plasmoid.configuration.activeProfileId || "default")
    property string kimaiUrl: KimaiApi.normalizeUrl(
        (activeProfile && activeProfile.url) ? activeProfile.url : plasmoid.configuration.kimaiUrl)
    property string apiToken: ""
    property bool tokenLoaded: false
    property bool isConfigured: kimaiUrl.length > 0 && apiToken.length > 0
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

    property int currentTimesheetId: invalidTimesheetId
    property string currentProject: ""
    property string currentActivity: ""
    property string currentDescription: ""
    property int elapsedSeconds: 0
    property var recentTimesheets: []
    property var projects: []
    property var customers: []
    property var customersById: ({})
    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activities: []
    property var pinnedEntries: []
    property var activitiesByProject: ({})
    property int selectedProjectId: 0
    /** Shared open direction for project + activity pickers (true = below). */
    property bool pickerOpenBelow: true
    property bool showNewActivityForm: false
    property bool savingDescription: false
    property bool suppressDescHandler: false
    property bool descriptionSavedFlash: false

    property int todaySeconds: 0
    property int weekSeconds: 0
    property int todayTargetSeconds: 0
    property int weekTargetSeconds: 0
    property bool hasWorkContract: false
    property int totalsElapsedAnchor: 0
    property string currentCustomerColor: KimaiApi.DEFAULT_CUSTOMER_COLOR
    property var workPrefs: ({})
    property var todayTimesheets: []
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
            refreshAll(true)
        })
    }

    function hardReload() {
        reloadCredentials(function() {
            syncDisplayStateFromConfig()
            refreshAll(false)
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
        Secret.load(execSource, kwalletScript, activeProfile.id, function(token, err) {
            if (err) {
                setError({ type: KimaiApi.ErrorType.Network, status: 0, detail: err })
                apiToken = ""
            } else {
                apiToken = token || ""
                if (!token || kimaiUrl.length === 0) {
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
        currentTimesheetId = invalidTimesheetId
        currentProject = ""
        currentActivity = ""
        currentDescription = ""
        currentCustomerColor = KimaiApi.DEFAULT_CUSTOMER_COLOR
        elapsedSeconds = 0
        descriptionSavedFlash = false
        descriptionSavedFlashTimer.stop()
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        }
    }

    function applyActiveTimesheet(timesheet) {
        if (!timesheet) {
            if (isTracking) {
                resetTrackingState()
            }
            return
        }

        isTracking = true
        currentTimesheetId = timesheet.id
        currentProject = KimaiApi.projectName(timesheet)
        currentActivity = KimaiApi.activityName(timesheet)
        currentDescription = timesheet.description || ""
        currentCustomerColor = KimaiApi.customerColorFromTimesheet(timesheet, customersById)
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        }

        var beginDate = new Date(timesheet.begin)
        if (!isNaN(beginDate.getTime())) {
            elapsedSeconds = Math.max(0, Math.floor((Date.now() - beginDate.getTime()) / 1000))
        }

        suppressDescHandler = true
        if (typeof descriptionEdit !== "undefined" && descriptionEdit) {
            descriptionEdit.text = currentDescription
        }
        suppressDescHandler = false
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

    function saveCurrentDescription() {
        if (!isTracking || currentTimesheetId === invalidTimesheetId || savingDescription || isBusy) {
            return
        }
        if (typeof descriptionEdit === "undefined" || !descriptionEdit) {
            return
        }
        var text = descriptionEdit.text
        if (text === currentDescription) {
            return
        }
        savingDescription = true
        descriptionSavedFlash = false
        KimaiApi.patchTimesheet(kimaiUrl, apiToken, currentTimesheetId, { description: text }, function(result) {
            savingDescription = false
            if (result.ok) {
                suppressDescHandler = true
                currentDescription = text
                if (descriptionEdit) {
                    descriptionEdit.text = text
                }
                suppressDescHandler = false
                clearError()
                descriptionSavedFlash = true
                descriptionSavedFlashTimer.restart()
            } else {
                setError(result.error)
                suppressDescHandler = true
                if (descriptionEdit) {
                    descriptionEdit.text = currentDescription
                }
                suppressDescHandler = false
            }
        })
    }

    function applyActivitiesResult(projectId, result, activityIdToSelect) {
        if (result.ok) {
            activities = result.data || []
            activityPickerModel = KimaiApi.activityPickerItems(activities, projectId)
            if (activityIdToSelect) {
                for (var a = 0; a < activityPickerModel.length; a++) {
                    if (activityPickerModel[a].value && activityPickerModel[a].value.id === activityIdToSelect) {
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
            if (projectPickerModel[i].value && projectPickerModel[i].value.id === projectId) {
                idx = i
                break
            }
        }
        if (idx < 0) {
            return
        }
        projectCombo.currentIndex = idx
        selectedProjectId = projectId
        KimaiApi.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
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

        KimaiApi.fetchActiveTimesheet(kimaiUrl, apiToken, function(result) {
            loadingActive = false
            if (result.ok) {
                clearError()
                if (result.data.length > 0) {
                    applyActiveTimesheet(result.data[0])
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
        KimaiApi.fetchRecentTimesheets(kimaiUrl, apiToken, plasmoid.configuration.recentCount, function(result) {
            loadingRecent = false
            if (result.ok) {
                clearError()
                recentTimesheets = KimaiApi.deduplicateRecent(result.data || [])
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
            return
        }

        var now = new Date()
        KimaiApi.fetchCurrentUser(kimaiUrl, apiToken, function(userResult) {
            if (userResult.ok) {
                workPrefs = KimaiApi.preferenceMap(userResult.data)
                todayTargetSeconds = KimaiApi.workDaySecondsFromPrefs(workPrefs, now)
                weekTargetSeconds = KimaiApi.workWeekSecondsFromPrefs(workPrefs, now)
                hasWorkContract = weekTargetSeconds > 0 || todayTargetSeconds > 0
            } else {
                workPrefs = ({})
                todayTargetSeconds = 0
                weekTargetSeconds = 0
                hasWorkContract = false
            }

            KimaiApi.fetchTimesheetsRange(
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

    function refreshProjects(quiet) {
        if (!isConfigured) {
            projects = []
            customers = []
            customersById = ({})
            projectPickerModel = []
            return
        }

        if (!quiet) {
            loadingProjects = true
        }
        KimaiApi.loadCustomers(kimaiUrl, apiToken, function(customersResult) {
            customers = customersResult.ok ? (customersResult.data || []) : []
            customersById = KimaiApi.buildCustomersById(customers)
            KimaiApi.loadProjects(kimaiUrl, apiToken, function(result) {
                loadingProjects = false
                if (result.ok) {
                    clearError()
                    projects = result.data || []
                    projectPickerModel = KimaiApi.projectPickerItems(projects, customers)
                    refreshPinnedEntries(quiet)
                    if (!isTracking) {
                        Qt.callLater(root.preloadLastActivity)
                    }
                } else {
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
            plasmoid.configuration.pinnedActivities, projects, activitiesByProject, customersById)
        loadingPinned = false

        for (var i = 0; i < pinned.length; i++) {
            (function(projectId) {
                if (activitiesByProject[projectId]) {
                    return
                }
                KimaiApi.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
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
                            plasmoid.configuration.pinnedActivities, projects, activitiesByProject, customersById)
                    }
                })
            })(pinned[i].projectId)
        }
    }

    function refreshAll(quiet) {
        reloadProfiles()
        if (kimaiUrl.length === 0 || apiToken.length === 0) {
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
        refreshProjects(!!quiet)
        refreshWorkTotals()
    }

    function loadActivitiesForProject(projectId) {
        selectedProjectId = projectId || 0
        if (!isConfigured || !projectId) {
            activities = []
            activityPickerModel = []
            activityCombo.currentIndex = -1
            return
        }

        KimaiApi.loadActivities(kimaiUrl, apiToken, projectId, function(result) {
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
        KimaiApi.startTracking(kimaiUrl, apiToken, projectId, activityId, description, function(result) {
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
        KimaiApi.stopTracking(kimaiUrl, apiToken, currentTimesheetId, function(stopResult) {
            if (!stopResult.ok) {
                isBusy = false
                setError(stopResult.error)
                return
            }
            resetTrackingState()
            KimaiApi.startTracking(kimaiUrl, apiToken, projectId, activityId, description, function(startResult) {
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
        KimaiApi.stopTracking(kimaiUrl, apiToken, currentTimesheetId, function(result) {
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
            userMessage = i18n("Stop the current timer before starting another")
            return
        }

        isBusy = true
        userMessage = ""
        lastError = null
        KimaiApi.restartTimesheet(kimaiUrl, apiToken, timesheet.id, function(result) {
            if (result.ok) {
                clearError()
                applyActiveTimesheet(result.data || timesheet)
                refreshRecentTimesheets()
                refreshWorkTotals()
                isBusy = false
                if (plasmoid.configuration.notifyOnStart) {
                    sendNotification(
                        i18n("Tracking started"),
                        KimaiApi.projectName(timesheet) + " · " + KimaiApi.activityName(timesheet))
                }
                return
            }

            var pid = KimaiApi.projectId(timesheet)
            var aid = KimaiApi.activityId(timesheet)
            if (pid && aid) {
                isBusy = false
                startTracking(pid, aid, KimaiApi.projectName(timesheet), KimaiApi.activityName(timesheet), timesheet.description || "")
            } else {
                isBusy = false
                setError(result.error)
            }
        })
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
            contentWidth: availableWidth
            // Gap between content and the slim scrollbar.
            rightPadding: slimScrollBar.visible
                          ? slimScrollBar.width + Kirigami.Units.smallSpacing * 2
                          : 0
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
                width: popupScroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: i18n("Plasmai")
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
                    text: i18n("Connect your Kimai account")
                    explanation: i18n("Add your server URL and API token to start tracking time from the panel.")
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
                    implicitHeight: heroColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            visible: root.isTracking
                            Layout.preferredWidth: 4
                            Layout.fillHeight: true
                            radius: 2
                            color: root.currentCustomerColor
                        }

                        ColumnLayout {
                            id: heroColumn
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            LoadingRow {
                                Layout.fillWidth: true
                                visible: root.loadingActive && !root.isTracking && root.currentProject.length === 0
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                visible: root.isTracking
                                text: KimaiApi.formatDuration(root.elapsedSeconds)
                                font.family: "monospace"
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 6
                                font.bold: true
                                color: Kirigami.Theme.positiveTextColor
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                visible: !root.loadingActive && !root.isTracking
                                text: i18n("Not tracking")
                                font.bold: true
                                opacity: 0.85
                            }

                            DaySparkline {
                                Layout.fillWidth: true
                                Layout.topMargin: 1
                                Layout.bottomMargin: 1
                                visible: root.isConfigured && root.showSparklineHere
                                entries: root.todayTimesheets
                                targetSeconds: root.todayTargetSeconds
                                workDayBegin: root.workDayBegin
                                workDayEnd: root.workDayEnd
                                latitude: plasmoid.configuration.latitude
                                longitude: plasmoid.configuration.longitude
                                nowTick: root.elapsedSeconds
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
                                Layout.fillWidth: true
                                opacity: root.showWorkSummaryHere ? 1 : 0
                                visible: opacity > 0
                                spacing: 1
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Row {
                                    spacing: Kirigami.Units.smallSpacing
                                    PlasmaComponents3.Label {
                                        text: i18n("Today %1", KimaiApi.formatDurationShort(root.todayLiveSeconds))
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.8
                                    }
                                    PlasmaComponents3.Label {
                                        text: "·"
                                        opacity: 0.45
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("Week %1", KimaiApi.formatDurationShort(root.weekLiveSeconds))
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.8
                                    }
                                }

                                Row {
                                    visible: root.hasWorkContract
                                             && (root.todayTargetSeconds > 0 || root.weekTargetSeconds > 0)
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents3.Label {
                                        visible: root.todayTargetSeconds > 0
                                        text: root.remainingTodayText()
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.75
                                        color: root.remainingTodaySeconds >= 0
                                               ? Kirigami.Theme.textColor
                                               : Kirigami.Theme.neutralTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        visible: root.todayTargetSeconds > 0 && root.weekTargetSeconds > 0
                                        text: "·"
                                        opacity: 0.4
                                    }
                                    PlasmaComponents3.Label {
                                        visible: root.weekTargetSeconds > 0
                                        text: root.remainingWeekText()
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.75
                                        color: root.remainingWeekSeconds >= 0
                                               ? Kirigami.Theme.textColor
                                               : Kirigami.Theme.neutralTextColor
                                    }
                                }
                            }

                            Item {
                                id: descriptionRow
                                Layout.fillWidth: true
                                visible: root.isTracking
                                implicitHeight: descriptionEdit.implicitHeight

                                Kirigami.ActionTextField {
                                    id: descriptionEdit
                                    anchors.fill: parent
                                    enabled: !root.isBusy && !root.savingDescription
                                    placeholderText: i18n("Description")
                                    onAccepted: root.saveCurrentDescription()
                                    Keys.onReturnPressed: function(event) {
                                        root.saveCurrentDescription()
                                        event.accepted = true
                                    }
                                    Keys.onEnterPressed: function(event) {
                                        root.saveCurrentDescription()
                                        event.accepted = true
                                    }
                                    Keys.onEscapePressed: function(event) {
                                        text = root.currentDescription
                                        event.accepted = true
                                    }

                                    rightActions: [
                                        Kirigami.Action {
                                            id: descriptionSaveAction
                                            icon.name: root.descriptionSavedFlash
                                                       ? "dialog-ok-apply"
                                                       : "document-save"
                                            text: i18n("Save description")
                                            visible: root.descriptionSavedFlash
                                                     || (descriptionEdit.text !== root.currentDescription
                                                         && !root.savingDescription)
                                            enabled: !root.descriptionSavedFlash
                                                     && !root.savingDescription
                                                     && descriptionEdit.text !== root.currentDescription
                                            onTriggered: root.saveCurrentDescription()
                                        }
                                    ]
                                }

                                QQC2.BusyIndicator {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    z: 2
                                    visible: root.savingDescription
                                    running: visible
                                }
                            }

                            PlasmaComponents3.Button {
                                Layout.fillWidth: true
                                visible: root.isTracking
                                enabled: !root.isBusy
                                text: i18n("Stop")
                                icon.name: "media-playback-stop"
                                onClicked: root.requestStop()
                            }

                            PlasmaComponents3.Button {
                                Layout.fillWidth: true
                                visible: root.showContinueHere && !root.isTracking && root.lastRecent
                                enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                                text: i18n("Continue · %1 · %2",
                                           KimaiApi.projectName(root.lastRecent),
                                           KimaiApi.activityName(root.lastRecent))
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
                            titleText: root.pinnedEntries[index].activityName
                            subtitleText: root.pinnedEntries[index].projectName
                            rowEnabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                            showPlayIcon: true
                            onClicked: root.startPinned(root.pinnedEntries[index])
                            tooltipText: root.pinnedEntries[index].projectName
                                         + " · " + root.pinnedEntries[index].activityName
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
                            customerColor: KimaiApi.customerColorFromTimesheet(root.recentTimesheets[index], root.customersById)
                            titleText: KimaiApi.activityName(root.recentTimesheets[index])
                            subtitleText: {
                                var ts = root.recentTimesheets[index]
                                var bits = [KimaiApi.projectName(ts)]
                                var secs = KimaiApi.timesheetDurationSeconds(ts)
                                if (secs > 0) {
                                    bits.push(KimaiApi.formatDurationShort(secs))
                                }
                                bits.push(root.formatRelativeTime(ts.end || ts.begin))
                                return bits.join(" · ")
                            }
                            rowEnabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                            onClicked: root.restartFromRecent(root.recentTimesheets[index])
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
                             && root.selectedProjectId > 0
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

    onCurrentDescriptionChanged: {
        if (suppressDescHandler) {
            return
        }
        if (typeof descriptionEdit !== "undefined" && descriptionEdit) {
            suppressDescHandler = true
            descriptionEdit.text = currentDescription
            suppressDescHandler = false
        }
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
