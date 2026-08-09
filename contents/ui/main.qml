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
    readonly property string kwalletScript: scriptPath("../code/kwallet.sh")
    readonly property string idleScript: scriptPath("../code/idle.sh")
    readonly property string notifyScript: scriptPath("../code/notify.sh")
    readonly property string sharedConfigScript: scriptPath("../code/sharedConfig.sh")

    function scriptPath(relative) {
        var url = Qt.resolvedUrl(relative).toString()
        if (url.indexOf("file://") === 0) {
            return url.substring(7)
        }
        return url
    }

    property var profiles: Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl)
    property var activeProfile: Profiles.profileById(profiles, plasmoid.configuration.activeProfileId || "default")
    property string kimaiUrl: KimaiApi.normalizeUrl(
        (activeProfile && activeProfile.url) ? activeProfile.url : plasmoid.configuration.kimaiUrl)
    property string apiToken: ""
    property bool tokenLoaded: false
    property bool isConfigured: kimaiUrl.length > 0 && apiToken.length > 0
    property bool credentialsLoading: false

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

    readonly property var activitySectionTitles: ({
        "project": i18n("Project-specific"),
        "global": i18n("Global activities")
    })

    readonly property string errorMessage: userMessage.length > 0 ? userMessage : apiErrorText(lastError)

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

    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    Plasmoid.icon: connectionState === "error" ? "network-disconnect"
                     : isTracking ? "chronometer" : "chronometer-pause"
    Plasmoid.title: isTracking ? currentProject + " · " + currentActivity : i18n("Plasmai")

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Toggle Plasmai tracking")
            icon.name: "chronometer"
            shortcut: "Meta+Shift+K"
            onTriggered: root.toggleTracking()
        },
        PlasmaCore.Action {
            text: i18n("Stop Plasmai tracking")
            icon.name: "media-playback-stop"
            shortcut: "Meta+Shift+S"
            onTriggered: root.requestStop()
        }
    ]

    toolTipMainText: isTracking ? currentProject + " · " + currentActivity : i18n("Plasmai")
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
        if (isTracking) {
            return KimaiApi.formatDuration(elapsedSeconds)
        }
        return i18n("Click to open tracker")
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
        onTriggered: root.refreshActiveTimesheet(false)
    }

    Timer {
        id: idleTimer
        interval: 60000
        running: root.isTracking && plasmoid.configuration.idleStopEnabled && root.isConfigured
        repeat: true
        onTriggered: root.checkIdle()
    }

    function apiErrorText(error) {
        if (!error) {
            return ""
        }
        if (error.type === "config") {
            return i18n("Configure Kimai URL and API token")
        }
        if (error.type === KimaiApi.ErrorType.Network) {
            return i18n("Cannot reach Kimai. Check your network, URL, or TLS certificate.")
        }
        if (error.type === KimaiApi.ErrorType.Unauthorized) {
            return i18n("Authentication failed. Check your API token.")
        }
        if (error.type === KimaiApi.ErrorType.NotFound) {
            return i18n("Server not found. Check your Kimai URL.")
        }
        if (error.type === KimaiApi.ErrorType.Forbidden) {
            return i18n("Access denied. Your token may lack required permissions.")
        }
        if (error.type === KimaiApi.ErrorType.Server) {
            return i18n("Kimai server error (%1).", error.status)
        }
        if (error.detail) {
            return i18n("Request failed: %1", error.detail)
        }
        return i18n("Request failed (%1).", error.status)
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
                if (callback) {
                    callback()
                }
            })
        })
    }

    function persistSharedConfig() {
        Secret.loadSharedConfig(execSource, sharedConfigScript, function(existing) {
            // This instance's configuration wins (used after a configure session).
            var shared = SharedConfig.merge(
                existing || {},
                SharedConfig.fromConfiguration(plasmoid.configuration)
            )
            Secret.saveSharedConfig(execSource, sharedConfigScript, shared)
        })
    }

    function switchProfile(profileId) {
        var currentId = plasmoid.configuration.activeProfileId || "default"
        if (currentId !== profileId) {
            plasmoid.configuration.activeProfileId = profileId
        }
        resetTrackingState()
        reloadCredentials(function() {
            refreshAll()
            refreshPinnedEntries()
        })
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
        elapsedSeconds = 0
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

        var beginDate = new Date(timesheet.begin)
        if (!isNaN(beginDate.getTime())) {
            elapsedSeconds = Math.max(0, Math.floor((Date.now() - beginDate.getTime()) / 1000))
        }
    }

    function refreshActiveTimesheet(showLoading) {
        if (!isConfigured) {
            return
        }
        if (showLoading !== false) {
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

    function refreshRecentTimesheets() {
        if (!isConfigured) {
            recentTimesheets = []
            return
        }

        loadingRecent = true
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

    function refreshProjects() {
        if (!isConfigured) {
            projects = []
            customers = []
            customersById = ({})
            projectPickerModel = []
            return
        }

        loadingProjects = true
        KimaiApi.loadCustomers(kimaiUrl, apiToken, function(customersResult) {
            customers = customersResult.ok ? (customersResult.data || []) : []
            customersById = KimaiApi.buildCustomersById(customers)
            KimaiApi.loadProjects(kimaiUrl, apiToken, function(result) {
                loadingProjects = false
                if (result.ok) {
                    clearError()
                    projects = result.data || []
                    projectPickerModel = KimaiApi.projectPickerItems(projects, customers)
                    refreshPinnedEntries()
                } else {
                    setError(result.error)
                    projects = []
                    projectPickerModel = []
                }
            })
        })
    }

    function refreshPinnedEntries() {
        var pinned = Favorites.parsePinned(plasmoid.configuration.pinnedActivities)
        if (pinned.length === 0 || !isConfigured) {
            pinnedEntries = []
            return
        }

        loadingPinned = true
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

    function refreshAll() {
        reloadProfiles()
        if (kimaiUrl.length === 0 || apiToken.length === 0) {
            connectionState = "offline"
            if (tokenLoaded) {
                setError({ type: "config", status: 0, detail: "" })
            }
            return
        }
        connectionState = "connecting"
        refreshActiveTimesheet(true)
        refreshRecentTimesheets()
        refreshProjects()
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
            if (result.ok) {
                activities = result.data || []
                activityPickerModel = KimaiApi.activityPickerItems(activities, projectId)
            } else {
                setError(result.error)
                activities = []
                activityPickerModel = []
            }
            activityCombo.currentIndex = -1
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

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                source: root.connectionState === "error" ? "network-disconnect"
                        : root.isTracking ? "chronometer" : "chronometer-pause"
                active: compactRoot.containsMouse
            }

            PlasmaComponents3.Label {
                visible: plasmoid.configuration.showProjectInPanel && root.isTracking && root.currentProject.length > 0
                text: root.currentProject
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.maximumWidth: Kirigami.Units.gridUnit * 8
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            PlasmaComponents3.Label {
                visible: plasmoid.configuration.showElapsedInPanel && root.isTracking
                text: KimaiApi.formatDuration(root.elapsedSeconds)
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
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

        Flickable {
            id: popupFlickable
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            clip: true
            contentWidth: width
            contentHeight: popupColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                policy: QQC2.ScrollBar.AsNeeded
            }

            onMovementStarted: root.dismissPickerPopups()
            onFlickStarted: root.dismissPickerPopups()
            onContentYChanged: {
                if (projectCombo.popupOpen || activityCombo.popupOpen) {
                    root.dismissPickerPopups()
                }
            }

            ColumnLayout {
                id: popupColumn
                width: popupFlickable.width
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

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: root.errorMessage.length > 0
                    type: Kirigami.MessageType.Error
                    text: root.errorMessage
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.errorMessage.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Button {
                        text: i18n("Retry")
                        icon.name: "view-refresh"
                        onClicked: root.reloadCredentials(function() { root.refreshAll() })
                    }

                    PlasmaComponents3.Button {
                        text: i18n("Configure")
                        icon.name: "configure"
                        onClicked: root.openConfigure()
                    }
                }

                Kirigami.Separator { Layout.fillWidth: true }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Current")
                }

                Kirigami.AbstractCard {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        LoadingRow {
                            Layout.fillWidth: true
                            visible: root.loadingActive
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: !root.loadingActive
                            text: root.isTracking ? i18n("Tracking active") : i18n("Not tracking")
                            font.bold: true
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: !root.loadingActive && root.isTracking
                            text: i18n("Project: %1", root.currentProject || i18n("None"))
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: !root.loadingActive && root.isTracking
                            text: i18n("Activity: %1", root.currentActivity || i18n("None"))
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: !root.loadingActive && root.isTracking && root.currentDescription.length > 0
                            text: root.currentDescription
                            wrapMode: Text.WordWrap
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.85
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: !root.loadingActive && root.isTracking
                            text: KimaiApi.formatDuration(root.elapsedSeconds)
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                        }

                        PlasmaComponents3.Button {
                            Layout.fillWidth: true
                            visible: !root.loadingActive && root.isTracking
                            enabled: !root.isBusy
                            text: i18n("Stop")
                            icon.name: "media-playback-stop"
                            onClicked: root.requestStop()
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: root.pinnedEntries.length > 0 || root.loadingPinned
                }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    visible: root.pinnedEntries.length > 0 || root.loadingPinned
                    text: i18n("Favorites")
                }

                Flow {
                    Layout.fillWidth: true
                    visible: !root.loadingPinned && root.pinnedEntries.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.pinnedEntries
                        delegate: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            CustomerColorDot {
                                customerColor: modelData.customerColor || "#d2d6de"
                                sizeFactor: 0.55
                                Layout.alignment: Qt.AlignVCenter
                            }

                            PlasmaComponents3.Button {
                                enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                                text: modelData.projectName + " · " + modelData.activityName
                                icon.name: root.isTracking ? "media-skip-forward" : "favorite"
                                onClicked: root.startPinned(modelData)
                            }
                        }
                    }
                }

                LoadingRow {
                    Layout.fillWidth: true
                    visible: root.loadingPinned
                }

                Kirigami.Separator { Layout.fillWidth: true }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Recent")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.loadingRecent ? 0 : root.recentTimesheets
                        delegate: QQC2.ItemDelegate {
                            Layout.fillWidth: true
                            enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                            onClicked: root.restartFromRecent(modelData)
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                CustomerColorDot {
                                    customerColor: KimaiApi.customerColorFromTimesheet(modelData, root.customersById)
                                    sizeFactor: 0.55
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Kirigami.Icon {
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    source: "media-playback-start"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: KimaiApi.projectName(modelData) + " · " + KimaiApi.activityName(modelData)
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: root.formatRelativeTime(modelData.end || modelData.begin)
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.7
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.loadingRecent
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: 3
                            LoadingRow { Layout.fillWidth: true }
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.isConfigured && !root.loadingRecent && root.recentTimesheets.length === 0 && root.connectionState !== "error"
                        text: i18n("No recent activities")
                        opacity: 0.7
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }

                Kirigami.Separator { Layout.fillWidth: true }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("New activity")
                }

                LoadingRow {
                    Layout.fillWidth: true
                    visible: root.loadingProjects
                }

                SearchableCombo {
                    id: projectCombo
                    Layout.fillWidth: true
                    visible: !root.loadingProjects
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
                    visible: !root.loadingProjects
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
                    visible: !root.loadingProjects
                    enabled: root.isConfigured && !root.isBusy && root.connectionState !== "error"
                    placeholderText: i18n("Description (optional)")
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.loadingProjects
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
                        text: i18n("Switch to new activity")
                        icon.name: "media-skip-forward"
                        onClicked: {
                            var project = projectCombo.currentItem.value
                            var activity = activityCombo.currentItem.value
                            root.switchToActivity(project.id, activity.id, project.name, activity.name, descriptionField.text)
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        reloadCredentials(function() {
            refreshAll()
        })
    }

    Connections {
        target: plasmoid
        function onUserConfiguringChanged() {
            if (plasmoid.userConfiguring) {
                // Pull shared settings before editing so we don't save stale values.
                root.reloadCredentials(function() {})
            } else {
                root.persistSharedConfig()
                root.reloadCredentials(function() {
                    root.refreshAll()
                })
            }
        }
    }

    Connections {
        target: plasmoid.configuration
        function onProfilesJsonChanged() {
            root.reloadProfiles()
            if (!plasmoid.userConfiguring) {
                root.reloadCredentials(function() { root.refreshAll() })
            }
        }
        function onActiveProfileIdChanged() {
            root.reloadProfiles()
            if (!plasmoid.userConfiguring) {
                root.reloadCredentials(function() {
                    root.refreshAll()
                    root.refreshPinnedEntries()
                })
            }
        }
        function onKimaiUrlChanged() {
            root.reloadProfiles()
            if (!plasmoid.userConfiguring) {
                root.reloadCredentials(function() { root.refreshAll() })
            }
        }
        function onRefreshIntervalChanged() {
            pollTimer.interval = Math.max(10, plasmoid.configuration.refreshInterval) * 1000
        }
        function onRecentCountChanged() { root.refreshRecentTimesheets() }
        function onPinnedActivitiesChanged() { root.refreshPinnedEntries() }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded) {
                root.reloadCredentials(function() {
                    root.refreshAll()
                })
            }
        }
    }
}
