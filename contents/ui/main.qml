import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQml.Models
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/secret.js" as Secret
import "../code/platform.js" as Platform
import "../code/desktopBackend.js" as DesktopBackend
import "../code/profiles.js" as Profiles
import "../code/favorites.js" as Favorites
import "../code/sharedConfig.js" as SharedConfig
import "../code/buildInfo.js" as BuildInfo
import "../code/timesheetFields.js" as TimesheetFields
import "../code/filmDays.js" as FilmDays
import "../code/dateTimeFormat.js" as DTF
import "../code/mileage.js" as Mileage
import "../code/statsData.js" as StatsData
import "../code/rowHit.js" as RowHit
import "."
import "Kante"
import "KantePlasma"

/**
 * The Plasmoid: panel chip and popup. Data and actions come from the session
 * layer (Session.qml); this file keeps view state (views, editors, dialogs,
 * flashes) and the platform glue (DataSource, notifications, plasmoid
 * actions, plasmoid.configuration ↔ shared.json).
 *
 *   plasmoid.configuration ◀─bridge─▶ shared.json ──▶ session ──▶ timer card, lists, views
 */
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

    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/kwallet.sh"))
    readonly property string idleScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/idle.sh"))
    readonly property string notifyScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/notify.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/sharedConfig.sh"))
    readonly property string catalogCacheScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/catalogCache.sh"))
    readonly property string systemCheckScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/systemCheck.sh"))
    readonly property string localStoreScript: Secret.fileUrlToPath(Qt.resolvedUrl("../code/localStore.sh"))

    // ── The session layer: data and actions (Session.qml) ──
    readonly property Session session: Session {
        dataSource: execSource
        // Files of this widget: two widgets in one plasmashell must not share an outbox.
        offlinePrefix: "plasmoid-" + Plasmoid.id + "-"
        setupMode: Session.Setup.Run
        catalog.useCache: true
        // No idle prompt while the settings dialog is open.
        reminders.idleAvailable: !plasmoid.userConfiguring
        reminders.notificationsAvailable: true
    }

    // ── View state ──
    property string mainViewMode: "main"  // main | manual | stats | filmday | trip | unsynced
    /** Inline editor for the running timesheet (start / project / activity). */
    property bool editingActiveEntry: false
    /** Stopped Recent timesheet currently in the Add-entry form (null = new entry). */
    property var editingStoppedTimesheet: null
    /** shared.json is read into plasmoid.configuration (reload); a reload asked meanwhile runs after. */
    property bool reloading: false
    property int queuedReload: -1
    /** The error of the last failed action, shown until the next poll (refresh errors: the layer's). */
    property var actionError: null
    property string userMessage: ""
    /** Transient hint key for "already tracking" feedback on Recent and Favorite rows. */
    property string alreadyRunningHintKey: ""
    /** Recent entry waiting for switch confirmation while a timer is running. */
    property var pendingSwitchTimesheet: null
    property var pendingDeleteTimesheet: null
    property var pendingSplitTimesheet: null
    /** A restart of this entry runs; if it fails, the entry starts anew. */
    property var continuing: null
    /** A start of this widget runs: trackingBegan is no news then. */
    property bool localStart: false
    /** The next stop is the idle prompt's (its own notification). */
    property bool stopFromIdle: false
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
    /** Bumps DaySparkline live edge; kept coarse to avoid per-second canvas work. */
    property int sparklineNowTick: 0
    /** The switch form's pickers: the chosen project and its activities. */
    property var activityPickerModel: []
    property var selectedProjectId: null
    /** Shared open direction for project + activity pickers (true = below). */
    property bool pickerOpenBelow: true
    property bool showNewActivityForm: false
    property bool descriptionSavedFlash: false
    /** 1 while the success check is held, then animated to 0. */
    property real descriptionSaveFlashOpacity: 1
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
    /** A manual entry is being saved. */
    property bool savingEntry: false

    // Statistics: entries of several weeks (the week's from the totals until more is asked).
    property var statsTimesheets: []
    property var statsRangeBeginMs: 0
    property var statsRangeEndMs: 0
    property bool loadingStats: false
    /** Trips of this week and month for the statistics (null = not loaded / no plugin). */
    property var statsTrips: null

    // Film day: the shown day; mode, probe and calls are session.filmDay's.
    property var filmDaySelectedDate: new Date()
    /** The Kimai entry for filmDaySelectedDate + the picked project, if any. */
    property var filmDayTimesheet: null
    /** Entry the film day's note belongs to (running or the day's), null before it exists. */
    property var filmDayNoteEntry: null
    /** The note as last loaded or saved (its entry's description). */
    property string filmDaySavedNote: ""
    property bool loadingFilmDay: false
    property bool savingFilmDay: false
    property int filmDayLoadSerial: 0
    /** Film-day JSON the next save diffs against (server mode). */
    property var filmDayServer: null
    property string filmDayLoadMode: ""

    // Trips: probe, meta and calls are session.trips'.
    /** Open trip suggestions (Dawarich), shown above Recent. */
    property var tripSuggestions: []
    property double tripSuggestionsLoadedAt: 0
    property bool tripBusy: false
    /** Suggestion being edited in the trip sheet before accepting it, or null. */
    property var tripSheetSuggestion: null

    readonly property string profileId: session.connection.profile ? session.connection.profile.id : ""
    readonly property string workDayBegin: session.settings.workDayBegin || KimaiApi.DEFAULT_WORK_DAY_BEGIN
    readonly property string workDayEnd: session.settings.workDayEnd || KimaiApi.DEFAULT_WORK_DAY_END

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
        const t = session.timer
        if (!t.tracking) {
            return ""
        }
        const showProject = plasmoid.configuration.showProjectInPanel
        const showActivity = plasmoid.configuration.showActivityInPanel
        if (showProject && showActivity && t.project && t.activity) {
            return t.project + " · " + t.activity
        }
        if (showActivity && t.activity) {
            return t.activity
        }
        if (showProject && t.project) {
            return t.project
        }
        return ""
    }

    readonly property var panelPills: KimaiApi.panelPillInfo(
        session.timer.active, session.catalog.projects, session.catalog.customersById)
    readonly property color currentCustomerColor: session.timer.colorInfo.color

    readonly property int recentVisibleCount: Math.min(
        Math.max(1, session.settings.recentCount),
        session.recent.list.length)
    readonly property int favoritesVisibleCount: compactPopupLayout
        ? Math.min(session.favorites.pinned.length, 6)
        : session.favorites.pinned.length

    readonly property var activitySectionTitles: ({
        "project": i18n("Project-specific"),
        "global": i18n("Global activities")
    })

    /** "error" also while an action's error shows; otherwise the layer's state. */
    readonly property string connectionState: actionError ? session.connection.error : session.connection.state
    readonly property string errorMessage: userMessage.length > 0
        ? userMessage : ApiErrors.text(actionError || session.connection.lastError)
    readonly property bool showSetupState: session.connection.tokenLoaded && !session.connection.configured
    readonly property bool showErrorState: errorMessage.length > 0 && connectionState === "error"
    /** Shown while shared.json is read or the session connects. */
    readonly property bool loading: session.busy || connectionState === "connecting" || reloading

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
                     : session.timer.tracking ? "media-record" : "chronometer"
    // Keep stable: Plasma's config dialog title is "Settings for %1" / Plasmoid.title.
    Plasmoid.title: i18n("Plasmai")

    toolTipMainText: session.timer.tracking ? session.timer.project + " · " + session.timer.activity : i18n("Plasmai")
    toolTipTextFormat: Text.PlainText
    toolTipSubText: {
        if (!session.connection.tokenLoaded) {
            return i18n("Loading…")
        }
        if (!session.connection.configured) {
            return i18n("Not configured — click to set up")
        }
        if (connectionState === "error" && errorMessage) {
            return errorMessage
        }
        var sync = []
        if (session.sync.offline) {
            sync.push(i18n("Offline"))
        }
        if (session.sync.unsynced > 0) {
            sync.push(i18np("%1 change not synced yet", "%1 changes not synced yet", session.sync.unsynced))
        }
        return sync.length ? sync.join(" · ") + "\n" + panelTooltipBody() : panelTooltipBody()
    }

    // BEGIN internal demo: scripts/package.sh removes this block and DemoHook.qml.
    Loader {
        source: "DemoHook.qml"
        onLoaded: {
            item.execSource = execSource
            item.plasmoidRoot = root
        }
    }
    // END internal demo

    ExecSource {
        id: execSource
    }

    Timer {
        id: sparklineRefreshTimer
        interval: 30000
        running: root.expanded && root.session.connection.configured && root.showSparklineHere
        repeat: true
        onTriggered: root.sparklineNowTick++
    }

    // An action's error shows until the next poll that finds the server (as before the layer).
    Timer {
        id: actionErrorTimer
        interval: Math.max(10, root.session.settings.refreshInterval) * 1000
        repeat: false
        onTriggered: {
            if (root.session.connection.state === root.session.connection.online) {
                root.clearError()
                return
            }
            restart()
        }
    }

    // Profile changes made in the app (shared.json): read by a shell process, so often only
    // while the popup is open; collapsed a minute is soon enough (the panel shows no profile).
    Timer {
        id: sharedConfigPollTimer
        interval: root.expanded ? 5000 : 60000
        running: !root.reloading && root.session.connection.tokenLoaded
        repeat: true
        onTriggered: root.pollSharedConfig()
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

    // ── plasmoid.configuration ↔ shared.json ──
    //
    //   reload(): shared.json ──▶ plasmoid.configuration ──▶ session.settings ──▶ session.open()
    //   settings dialog closed: plasmoid.configuration ──▶ shared.json ──▶ reload()
    //   session.settings.changed (pins, last used, probes, setup) ──▶ plasmoid.configuration
    //   a plasmoid.configuration key (settings dialog) ──▶ session.settings at once

    /** probe: Session.Probe.Fresh also drops the catalog cache (a reload after a change). */
    function reload(probe) {
        if (reloading) {
            queuedReload = Math.max(queuedReload, probe)
            return
        }
        reloading = true
        if (probe === Session.Probe.Fresh) {
            session.catalog.invalidate()
        }
        const done = function() {
            reloading = false
            const next = queuedReload
            queuedReload = -1
            if (next >= 0) {
                reload(next)
            }
        }
        Platform.loadShared(execSource).then(function(shared) {
            return root.resetOwnOld(shared)
        }).then(function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            } else if (root.ownConnection()) {
                // Migrate this instance's connection settings into the shared store.
                root.persistShared()
            }
            // Keys shared.json lacks keep this instance's values (main.xml's defaults).
            root.session.settings.apply(SharedConfig.fromConfiguration(plasmoid.configuration, { withoutDataMaps: true }))
            return root.session.open()
        }).then(done, done)
    }

    function ownConnection() {
        return (plasmoid.configuration.kimaiUrl || "").length > 0
               || (plasmoid.configuration.profilesJson || "").length > 0
    }

    /**
     * Settings of a version before the setup wizard (sharedConfig.js needsReset): once,
     * tokens cleared and every setting at its default, so the wizard runs. Resolves with
     * the settings to load. An instance without shared.json but with a connection of its
     * own (older still) counts as old too; a fresh one does not.
     */
    function resetOwnOld(shared) {
        const own = SharedConfig.fromConfiguration(plasmoid.configuration)
        const old = shared || (ownConnection() ? own : null)
        if (!SharedConfig.needsReset(old)) {
            return shared
        }
        const fresh = SharedConfig.resetShared()
        const ids = SharedConfig.profileIds(old).concat(SharedConfig.profileIds(own))
        const clears = ids.map(function(id) {
            return root.session.connection.clearToken(id).catch(function() {})
        })
        resetProfileView()
        session.catalog.invalidate()
        return Promise.all(clears).then(function() {
            return Platform.saveShared(execSource, fresh)
        }).then(function() { return fresh }, function() { return fresh })
    }

    /** This instance's configuration wins (after the settings dialog). */
    function persistShared() {
        // Film-day data maps are written on their own (merged, B9); a
        // stale copy here would drop what the app saved meanwhile.
        return Platform.patchShared(execSource, plasmoid.configuration,
            SharedConfig.fromConfiguration(plasmoid.configuration, { withoutDataMaps: true }))
    }

    function pollSharedConfig() {
        Platform.loadShared(execSource).then(function(shared) {
            if (!shared) {
                return
            }
            const changed = (shared.activeProfileId || "default") !== (plasmoid.configuration.activeProfileId || "default")
                            || (shared.profilesJson || "") !== (plasmoid.configuration.profilesJson || "")
            if (!changed) {
                return
            }
            SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            root.reload(Session.Probe.Fresh)
        })
    }

    // The layer changed a setting (pins, last used, probes, setup wizard): the settings dialog shows it.
    Connections {
        target: root.session.settings
        function onChanged(keys) {
            const s = root.session.settings
            for (let i = 0; i < keys.length; i++) {
                const key = keys[i]
                if (s.keys.indexOf(key) < 0 || plasmoid.configuration[key] === s[key]) {
                    continue
                }
                plasmoid.configuration[key] = s[key]
            }
        }
    }

    // The settings dialog changed a key: the layer takes it at once.
    Instantiator {
        model: root.session.settings.keys
        delegate: QtObject {
            required property string modelData
            readonly property var value: plasmoid.configuration[modelData]
            onValueChanged: root.takeConfig(modelData, value)
        }
    }

    function takeConfig(key, value) {
        if (SharedConfig.isDataMapKey(key) || value === undefined || session.settings[key] === value) {
            return
        }
        const patch = {}
        patch[key] = value
        session.settings.apply(patch)
    }

    // ── Words for the session's answers ──

    function formatRelativeTime(isoDate) {
        if (!isoDate) {
            return ""
        }
        var date = DTF.parseStamp(isoDate)
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
        if (!session.connection.configured) {
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
        const c = session.connection
        if (!c.configured) {
            return i18n("Not configured")
        }
        if (connectionState === "connecting") {
            return i18n("Connecting to %1…", c.url)
        }
        if (connectionState === "error") {
            return i18n("Connection problem")
        }
        const profileName = c.profile ? c.profile.name : ""
        return profileName.length > 0
               ? i18n("Connected to %1 (%2)", c.url, profileName)
               : i18n("Connected to %1", c.url)
    }

    /** An action failed: its error shows (error state) until the next poll. */
    function showError(error) {
        actionError = error || { type: "network", status: 0, detail: "empty result" }
        actionErrorTimer.restart()
    }

    function clearError() {
        actionError = null
        userMessage = ""
        actionErrorTimer.stop()
    }

    function notify(summary, body) {
        session.reminders.notify(summary, body)
    }

    Connections {
        target: root.session
        function onFailed(action, result) {
            root.reportFailure(action, result)
        }
        function onStarted(ts, origin, names) {
            root.clearError()
            root.continuing = null
            // trackingBegan follows at once: no "in progress" news for a start here.
            root.localStart = true
            Qt.callLater(function() { root.localStart = false })
            if (!root.session.settings.notifyOnStart) {
                return
            }
            root.notify(origin === Session.Origin.Switch ? i18n("Switched activity") : i18n("Tracking started"),
                        names.project + " · " + names.activity)
        }
        function onStopped(ts, names) {
            root.clearError()
            const idle = root.stopFromIdle
            root.stopFromIdle = false
            if (idle && root.session.settings.notifyOnIdleStop) {
                root.notify(i18n("Tracking stopped (idle)"), names.project + " · " + names.activity)
            } else if (!idle && root.session.settings.notifyOnStop) {
                root.notify(i18n("Tracking stopped"), names.project + " · " + names.activity)
            }
        }
        // A timer found by a refresh (started elsewhere, or before this widget ran).
        function onTrackingBegan(ts) {
            if (root.localStart) {
                return
            }
            const t = root.session.timer
            root.notify(i18n("Tracking in progress"),
                        t.project + " · " + t.activity + " · " + KimaiApi.formatDurationShort(t.elapsedSeconds))
        }
        /** Kimai saved the entry but ignored billable (no edit_billable permission). */
        function onDroppedFields(fields) {
            root.userMessage = i18n("Saved without the billable change: your Kimai account is not allowed to edit billable.")
        }
    }

    /** A failed action of the session, as the error line (refresh errors are the layer's). */
    function reportFailure(action, result) {
        if (action === Session.Action.Refresh) {
            return
        }
        if (action === Session.Action.SplitRange) {
            userMessage = i18n("Split time must be between begin and end.")
            return
        }
        if (action === Session.Action.Continue && startAnew(continuing)) {
            return
        }
        showError(result ? result.error : null)
        if (action === Session.Action.SplitSecond) {
            userMessage = i18n("The first half was saved, but the second half could not be created.")
        }
    }

    /** A restart failed: the same project and activity start as a new entry. */
    function startAnew(ts) {
        continuing = null
        const pid = ts ? KimaiApi.projectId(ts) : null
        const aid = ts ? KimaiApi.activityId(ts) : null
        if (!pid || !aid) {
            return false
        }
        session.timer.start(pid, aid, KimaiApi.displayProjectName(ts, session.catalog.projects),
                            KimaiApi.displayActivityName(ts, session.catalog.activities, session.catalog.activitiesByProject),
                            ts.description || "")
        return true
    }

    Connections {
        target: root.session.timer
        function onDescriptionSaved() {
            root.clearError()
            root.startDescriptionSavedFlash()
        }
        function onDescriptionFailed(result) {
            root.showError(result ? result.error : null)
        }
        function onTrackingChanged() {
            if (!root.session.timer.tracking) {
                root.resetTrackingView()
            }
            // The film day follows the timer (Start, Stop, a switch from the main view).
            if (root.mainViewMode === "filmday") {
                root.loadFilmDayForDate(root.filmDaySelectedDate)
            }
        }
        function onActiveChanged() {
            if (root.session.timer.tracking && !root.compactPopupLayout) {
                root.showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
            }
        }
    }

    Connections {
        target: root.session.reminders
        function onIdlePendingChanged() {
            if (!root.session.reminders.idlePending) {
                return
            }
            root.expanded = true
            if (root.idleDialogRef) {
                root.idleDialogRef.open()
                return
            }
            root.session.reminders.clearPending()
            root.stopFromIdle = true
            root.session.timer.stop()
        }
        function onIdleDiscarded(snap) {
            root.clearError()
            if (root.session.settings.notifyOnIdleStop) {
                root.notify(i18n("Idle time discarded"), snap.projectName + " · " + snap.activityName)
            }
        }
        function onForgotToStart() {
            if (plasmoid.userConfiguring) {
                return
            }
            root.notify(i18n("Nothing is tracking"), i18n("Work hours have started. Start a timer when you begin."))
        }
    }

    // A full catalog answer: pickers, statistics and the open editor take its names.
    Connections {
        target: root.session.catalog
        function onUpdated() {
            root.rebuildCatalogViews()
        }
    }

    // Outside the statistics the week's entries stand in for its first range.
    Connections {
        target: root.session.totals
        function onWeekEntriesChanged() {
            if (root.statsTimesheets.length && root.mainViewMode === "stats") {
                return
            }
            const now = new Date()
            root.statsTimesheets = root.session.totals.weekEntries
            root.statsRangeBeginMs = KimaiApi.startOfWeekMonday(now).getTime()
            root.statsRangeEndMs = KimaiApi.endOfWeekSunday(now).getTime()
        }
    }

    // The plugin probe answered: Detected trips load while the popup shows.
    Connections {
        target: root.session.trips
        function onCanEditChanged() {
            if (root.expanded) {
                root.loadTripSuggestions(false)
            }
        }
    }

    onProfileIdChanged: resetProfileView()

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

    function openCreateEntity(mode) {
        if (!session.connection.capabilities.createEntities || !createEntityDialogRef) {
            return
        }
        var projectName = ""
        if (root.switchPickersRef && root.switchPickersRef.projectCombo.currentItem) {
            projectName = root.switchPickersRef.projectCombo.currentItem.label || ""
        }
        createEntityDialogRef.selectedProjectId = selectedProjectId
        createEntityDialogRef.selectedProjectName = projectName
        createEntityDialogRef.customers = session.catalog.customers
        createEntityDialogRef.resetForMode(mode)
        expanded = true
        createEntityDialogRef.open()
    }

    function submitCreateEntity(mode, payload) {
        if (!payload) {
            return
        }
        userMessage = ""
        if (mode === "customer") {
            payload.customers = session.catalog.customers
        }
        const created = { customer: i18n("Customer created"), project: i18n("Project created"), activity: i18n("Activity created") }
        session.entries.createEntity(mode, payload, function(result) {
            if (!result || !result.ok || (mode !== "customer" && !result.data)) {
                root.showError(result ? result.error : null)
                return
            }
            root.clearError()
            // The new project or activity is picked once the catalog has it.
            if (mode === "project") {
                Qt.callLater(function() { root.selectProjectById(result.data.id, null) })
            } else if (mode === "activity") {
                Qt.callLater(function() { root.selectProjectById(payload.project, result.data.id) })
            }
            root.notify(created[mode], payload.name)
        })
    }

    /** An editor opens before the catalog came: ask for it now. */
    function ensureCatalog() {
        if (session.catalog.projects.length === 0) {
            session.catalog.refresh()
        }
    }

    function openUnsyncedView() {
        editingActiveEntry = false
        editingStoppedTimesheet = null
        mainViewMode = "unsynced"
    }

    function openManualEntry() {
        if (!session.connection.configured) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = null
        mainViewMode = "manual"
        ensureCatalog()
        if (root.manualEntryViewRef) {
            root.manualEntryViewRef.resetDefaults()
        }
    }

    function openStoppedEdit(timesheet) {
        if (!session.connection.configured || !timesheet) {
            return
        }
        if (timesheetIsRunning(timesheet)) {
            openActiveEdit()
            return
        }
        if (!session.connection.capabilities.editStopped) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = timesheet
        mainViewMode = "manual"
        ensureCatalog()
        Qt.callLater(function() {
            if (root.manualEntryViewRef
                    && root.editingStoppedTimesheet) {
                root.manualEntryViewRef.loadFromTimesheet(root.editingStoppedTimesheet)
            }
        })
    }

    function openActiveEdit() {
        if (!session.connection.configured || !session.timer.tracking || !session.timer.active) {
            return
        }
        editingActiveEntry = true
        ensureCatalog()
        // Prefill once the editor is visible (also handled by ActiveEditView.onVisibleChanged).
        Qt.callLater(function() {
            if (editingActiveEntry && root.activeEditViewRef) {
                root.activeEditViewRef.loadFromTimesheet(root.session.timer.active)
            }
        })
    }

    function closeActiveEdit() {
        editingActiveEntry = false
    }

    function saveActiveEdit(projectId, activityId, beginText, billable, tags) {
        if (!session.timer.tracking || session.busy || !session.timer.timesheetId) {
            return
        }
        const beginDate = DTF.parseStamp(beginText)
        if (isNaN(beginDate.getTime())) {
            userMessage = i18n("Enter a valid start date/time.")
            return
        }
        if (beginDate.getTime() > Date.now() + 60 * 1000) {
            userMessage = i18n("Start must not be in the future.")
            return
        }
        userMessage = ""
        session.timer.patchActive({
            begin: KimaiApi.localDateTimeString(beginDate),
            project: projectId,
            activity: activityId,
            billable: typeof billable === "boolean" ? billable : undefined,
            tags: tags || []
        }, function() {
            root.clearError()
            root.editingActiveEntry = false
        })
    }

    function openStatsView() {
        if (!session.connection.configured || !session.connection.capabilities.statistics) {
            return
        }
        mainViewMode = "stats"
        session.totals.refresh()
        loadStatsTrips()
        // Prefetch a few weeks so day/week switchers work immediately.
        const now = new Date()
        const begin = KimaiApi.startOfWeekMonday(now)
        begin.setDate(begin.getDate() - 7 * 4)
        loadStatsRange(begin, KimaiApi.endOfWeekSunday(now))
    }

    /**
     * Ensure statsTimesheets covers [beginDate, endDate]. Fetches when needed.
     */
    function loadStatsRange(beginDate, endDate) {
        if (!session.connection.configured || !beginDate || !endDate) {
            return
        }
        const bMs = beginDate.getTime()
        const eMs = endDate.getTime()
        if (statsRangeBeginMs && statsRangeEndMs
            && bMs >= statsRangeBeginMs && eMs <= statsRangeEndMs
            && statsTimesheets.length > 0) {
            rehydrateStatsTimesheets()
            return
        }
        // Padded to full weeks.
        const fetchBegin = KimaiApi.startOfWeekMonday(new Date(statsRangeBeginMs && statsRangeBeginMs < bMs ? statsRangeBeginMs : bMs))
        const fetchEnd = KimaiApi.endOfWeekSunday(new Date(statsRangeEndMs && statsRangeEndMs > eMs ? statsRangeEndMs : eMs))
        loadingStats = true
        session.entries.fetchRange(fetchBegin, fetchEnd, function(result) {
            root.loadingStats = false
            if (!result.ok) {
                return
            }
            root.statsTimesheets = result.data || []
            // An offline answer (the snapshot) does not count as loaded: fetch again once online.
            root.statsRangeBeginMs = result.offline ? 0 : fetchBegin.getTime()
            root.statsRangeEndMs = result.offline ? 0 : fetchEnd.getTime()
        })
    }

    function rehydrateStatsTimesheets() {
        if (!statsTimesheets || statsTimesheets.length === 0) {
            return
        }
        statsTimesheets = session.catalog.hydrate(statsTimesheets)
    }

    function returnToMainView() {
        mainViewMode = "main"
        editingStoppedTimesheet = null
        filmDayTimesheet = null
        tripSheetSuggestion = null
        dismissPickerPopups()
    }

    function openFilmDayView() {
        if (!session.connection.configured || !session.connection.capabilities.filmDays) {
            return
        }
        editingActiveEntry = false
        editingStoppedTimesheet = null
        mainViewMode = "filmday"
        ensureCatalog()
        // Load only once the mode is known (plugin present or not).
        loadingFilmDay = true
        session.filmDay.resolveMode(Session.Probe.Cached, function() {
            root.loadFilmDayForDate(root.filmDaySelectedDate)
        })
    }

    function stepFilmDay(deltaDays) {
        const next = new Date(filmDaySelectedDate)
        next.setDate(next.getDate() + deltaDays)
        loadFilmDayForDate(next)
    }

    /** Time label of an entry ("12:15–12:45") for the film day's other activities. */
    function filmDaySpanText(ts) {
        function clock(v) {
            const d = v ? DTF.parseStamp(v) : null
            return d && !isNaN(d.getTime()) ? DTF.formatLocaleTime(d.getHours(), d.getMinutes()) : "…"
        }
        return clock(ts.begin) + "–" + clock(ts.end)
    }

    /**
     * Loads the Kimai entry and film-day extras for `date` into the Filmday view.
     * preferSelected: the engagement chooser picked the project, it wins over the day's engagement.
     */
    function loadFilmDayForDate(date, preferSelected) {
        filmDaySelectedDate = date
        if (!session.connection.configured) {
            return
        }
        const view = root.filmDayViewRef
        const selectedProjectIdForDay = view && view.projectCombo.currentIndex >= 0
            ? view.projectCombo.currentItem.value.id : null
        loadingFilmDay = true
        // Only the latest load may fill the view (fast day steps / project picks).
        const serial = ++filmDayLoadSerial
        const dateStr = KimaiApi.localDateString(date)
        // One engagement per day: it decides the project; the plugin's day
        // summary decides which of the project's entries is the film day.
        // Cached days show at once; the live answer follows when it differs.
        session.filmDay.openDay(date, selectedProjectIdForDay, function(r, entries) {
            if (serial !== root.filmDayLoadSerial) {
                return
            }
            const day = r.day
            const cat = root.session.catalog
            root.loadingFilmDay = false
            root.filmDayTimesheet = r.match
            root.filmDayServer = day.server
            root.filmDayLoadMode = day.mode
            if (!root.filmDayViewRef) {
                return
            }
            const info = root.session.filmDay.viewInfo(r, {
                entries: entries, active: root.session.timer.tracking ? root.session.timer.active : null,
                recent: root.session.recent.list, daysFromToday: -DTF.daysBefore(date, new Date()),
                ids: root.session.filmDay.ids,
                labelOf: function(ts) {
                    return KimaiApi.displayActivityName(ts, cat.activities, cat.activitiesByProject)
                        + " · " + KimaiApi.displayProjectName(ts, cat.projects)
                },
                timeOf: root.filmDaySpanText
            })
            root.filmDayNoteEntry = info.timesheet
            root.filmDaySavedNote = FilmDays.noteOf(info.timesheet)
            root.filmDayViewRef.applyLoadedDay(date, info.timesheet, day,
                KimaiApi.customerCurrencyOfProject(cat.projectById(r.projectId), cat.customers),
                r.others, r.projectId, {
                    phase: info.phase, isToday: info.isToday, activityId: info.activityId,
                    engagement: r.engagement, engagements: r.engagements,
                    otherActivities: info.otherActivities
                })
            root.loadFilmDayProductionDay(serial, r, info, dateStr)
        }, !!preferSelected)
    }

    /** Production shooting day of the engagement, filled in once counted. */
    function loadFilmDayProductionDay(serial, r, info, dateStr) {
        if (!r.engagement || !r.engagement.validFrom) {
            return
        }
        session.filmDay.productionDay(r.projectId, info.activityId, r.activityIds,
                                      String(r.engagement.validFrom), dateStr, function(count) {
            const view = root.filmDayViewRef
            if (serial !== root.filmDayLoadSerial || !count || !view) {
                return
            }
            // A day without its entry yet (before the start) is the next shooting day.
            view.productionDayNumber = count.includesDay ? count.count
                : (info.phase === "before" ? count.count + 1 : 0)
            // No activity from the day or Recent: the engagement's usual film activity.
            if (view.activityCombo.currentIndex < 0 && count.activityId !== null) {
                view.pendingActivityId = count.activityId
                view.trySelectPendingActivity()
            }
        })
    }

    /** Direct save of the film day's extras (no busy state: the fields stay usable). */
    function saveFilmDayExtras(fields) {
        const view = root.filmDayViewRef
        if (!view) {
            return
        }
        const projectId = view.projectCombo.currentIndex >= 0 ? view.projectCombo.currentItem.value.id : null
        session.filmDay.saveExtras({
            projectId: projectId, dateStr: KimaiApi.localDateString(root.filmDaySelectedDate), fields: fields,
            server: filmDayServer, dayMode: filmDayLoadMode
        }, function(result) {
            if (result.extras === "failed") {
                root.userMessage = i18n("The film day was not saved: %1",
                                        (result.error && result.error.detail) || ApiErrors.text(result.error))
                return
            }
            if (result.server) {
                root.filmDayServer = result.server
            }
        }, function(payCents) {
            if (root.filmDayViewRef) {
                root.filmDayViewRef.earningsCents = payCents
            }
        })
    }

    /** The note is the entry's description; before the entry exists it goes with Start / Save. */
    function saveFilmDayNote(text) {
        session.filmDay.saveNote({
            timesheetId: filmDayNoteEntry ? filmDayNoteEntry.id : null, note: text, previous: filmDaySavedNote
        }, function(result) {
            if (result.saved === "failed") {
                root.showError(result.error)
                return
            }
            if (result.saved === "saved") {
                root.filmDaySavedNote = result.note
            }
        })
    }

    /** Saves entry and extras. direct: begin / end of the shown entry changed (no message, fields stay usable). */
    function saveFilmDay(projectId, activityId, beginText, endText, filmDayFields, direct) {
        if (!session.connection.configured || session.busy || savingFilmDay) {
            return
        }
        const beginDate = DTF.parseStamp(beginText)
        const endDate = DTF.parseStamp(endText)
        if (isNaN(beginDate.getTime()) || isNaN(endDate.getTime())) {
            userMessage = i18n("Enter valid begin and end date/time.")
            return
        }
        if (endDate.getTime() <= beginDate.getTime()) {
            userMessage = i18n("End must be after begin.")
            return
        }
        savingFilmDay = !direct
        userMessage = ""
        const view = root.filmDayViewRef
        const breakMinutes = (view && view.extrasVisible) ? view.effectiveBreakMinutes : 0
        // B3: the other entries of the project on this day, deleted after a successful save.
        const mergeIds = (view && view.mergeOthers) ? view.otherEntryIds() : []
        const existingId = FilmDays.saveTargetId(filmDayTimesheet, projectId, KimaiApi.projectId)
        const timesheetFields = {
            begin: KimaiApi.localDateTimeString(beginDate),
            end: KimaiApi.localDateTimeString(endDate),
            project: projectId,
            activity: activityId
        }
        // A new entry takes the note typed before it existed.
        if (!existingId && view) {
            timesheetFields.description = view.noteText()
        }
        session.filmDay.saveDay({
            projectId: projectId,
            dateStr: KimaiApi.localDateString(root.filmDaySelectedDate),
            existingId: existingId,
            timesheetFields: timesheetFields,
            fields: filmDayFields,
            server: filmDayServer,
            dayMode: filmDayLoadMode
        }, function(result) {
            root.savingFilmDay = false
            if (!result.ok) {
                root.showError(result.error)
                return
            }
            root.clearError()
            function finish(deleteReport) {
                const messages = []
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
                    root.userMessage = messages.join(" ")
                }
                root.session.refresh()
                if (!direct) {
                    root.notify(
                        i18n("Shooting day saved"),
                        KimaiApi.formatDurationShort(FilmDays.workSecondsFromSpan(
                            beginDate.getTime(), endDate.getTime(), breakMinutes)))
                }
                root.loadFilmDayForDate(root.filmDaySelectedDate)
            }
            if (mergeIds.length > 0) {
                root.session.filmDay.deleteEntries(mergeIds, finish)
            } else {
                finish(null)
            }
        })
    }

    // ── Trips (kimai-anfahrten) ──────────────────────────────────────────

    /** Another profile: its trips, suggestions and editors start empty. */
    function resetProfileView() {
        tripSuggestions = []
        tripSuggestionsLoadedAt = 0
        statsTrips = null
        resetTrackingView()
    }

    /** Open suggestions of the last 14 days, at most every 10 minutes unless forced (A5, lazy). */
    function loadTripSuggestions(force) {
        const ping = session.trips.ping
        if (!session.trips.canEdit || !Mileage.profileOf(ping).dawarichConfigured) {
            tripSuggestions = []
            return
        }
        if (!force && Date.now() - tripSuggestionsLoadedAt < 10 * 60 * 1000) {
            return
        }
        tripSuggestionsLoadedAt = Date.now()
        let range = null
        if (Mileage.hasFeature(ping, "dateRange")) {
            const from = new Date()
            from.setDate(from.getDate() - 14)
            range = { from: Mileage.dateString(from), to: Mileage.dateString(new Date()) }
        }
        session.trips.fetchSuggestions(function(r) {
            if (r.ok) {
                root.tripSuggestions = r.data
            }
        }, range)
    }

    function timesheetSummaryText(ts) {
        if (!ts) {
            return ""
        }
        const cat = session.catalog
        const bits = [KimaiApi.displayProjectName(ts, cat.projects),
                      KimaiApi.displayActivityName(ts, cat.activities, cat.activitiesByProject)]
        const begin = DTF.parseStamp(ts.begin)
        if (!isNaN(begin.getTime())) {
            bits.push(begin.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " "
                      + begin.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
        }
        return bits.filter(function(b) { return !!b }).join(" · ")
    }

    /** Show the trip sheet (mainViewMode "trip"). */
    function openTripSheet(form, original, linkedText, suggestion) {
        if (!session.trips.available) {
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
        openTripSheet(Mileage.emptyForm(session.trips.ping, Mileage.dateString(new Date())), null, "")
    }

    /** A3: trip linked to a Kimai entry (Recent row or the running entry). */
    function openTripForTimesheet(ts) {
        if (!ts) {
            return
        }
        openTripSheet(Mileage.formForTimesheet(session.trips.ping, ts, KimaiApi.projectId), null, timesheetSummaryText(ts))
    }

    function tripSaved(message) {
        tripBusy = false
        tripSheetSuggestion = null
        returnToMainView()
        if (message) {
            notify(i18n("Trip saved"), message)
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
        if (!session.trips.canEdit || tripBusy) {
            return
        }
        tripBusy = true
        const answered = function(r) {
            if (r.ok) {
                root.tripSaved(i18n("%1 km", Mileage.displayKm(Mileage.tripKm(r.data))))
            } else {
                root.tripFailed(r.error)
            }
        }
        if (tripSheetSuggestion) {
            const sg = tripSheetSuggestion
            session.trips.accept(sg.id, Mileage.acceptBodyFromForm(session.trips.ping, form, sg), answered)
            return
        }
        if (tripId !== null && tripId !== undefined) {
            if (Mileage.isEmptyBody(body)) {
                tripSaved("")
                return
            }
            session.trips.patch(tripId, body, answered)
            return
        }
        session.trips.create(body, answered)
    }

    function deleteTrip(tripId) {
        if (!session.trips.available || tripBusy) {
            return
        }
        tripBusy = true
        session.trips.remove(tripId, function(r) {
            if (r.ok) {
                root.tripSaved("")
            } else {
                root.tripFailed(r.error)
            }
        })
    }

    function removeSuggestion(sg) {
        tripSuggestions = tripSuggestions.filter(function(x) { return x.id !== sg.id })
    }

    /** A5: accept a detected trip as suggested. */
    function acceptTripSuggestion(sg) {
        if (!session.trips.canEdit || tripBusy || !sg) {
            return
        }
        tripBusy = true
        session.trips.accept(sg.id, {}, function(r) {
            root.tripBusy = false
            if (r.ok || (r.error && r.error.status === 409)) {
                // 409: accepted or dismissed elsewhere meanwhile.
                root.removeSuggestion(sg)
                root.statsTrips = null
            } else {
                root.userMessage = i18n("The trip could not be accepted: %1", (r.error && r.error.detail) || ApiErrors.text(r.error))
            }
        })
    }

    function dismissTripSuggestion(sg) {
        if (!session.trips.canEdit || tripBusy || !sg) {
            return
        }
        tripBusy = true
        session.trips.dismiss(sg.id, function(r) {
            root.tripBusy = false
            if (r.ok) {
                root.removeSuggestion(sg)
            } else {
                root.userMessage = i18n("The trip could not be dismissed: %1", (r.error && r.error.detail) || ApiErrors.text(r.error))
            }
        })
    }

    /** A6: trips of this week and month for the statistics summary. */
    function loadStatsTrips() {
        if (!session.trips.available) {
            statsTrips = null
            return
        }
        const now = new Date()
        const range = Mileage.hasFeature(session.trips.ping, "dateRange") ? StatsData.tripRangeFor(now) : { year: now.getFullYear() }
        session.trips.fetch(range, function(r) {
            root.statsTrips = r.ok ? r.data : null
        })
    }

    function createManualEntry(projectId, activityId, beginText, endText, description, billable, tags) {
        if (!session.connection.configured || session.busy || savingEntry) {
            return
        }
        const beginDate = DTF.parseStamp(beginText)
        const endDate = DTF.parseStamp(endText)
        if (isNaN(beginDate.getTime()) || isNaN(endDate.getTime())) {
            userMessage = i18n("Enter valid begin and end date/time.")
            return
        }
        if (endDate.getTime() <= beginDate.getTime()) {
            userMessage = i18n("End must be after begin.")
            return
        }
        savingEntry = true
        userMessage = ""
        const fields = {
            begin: KimaiApi.localDateTimeString(beginDate),
            end: KimaiApi.localDateTimeString(endDate),
            project: projectId,
            activity: activityId,
            description: description || "",
            billable: typeof billable === "boolean" ? billable : undefined,
            tags: tags || []
        }
        const editing = editingStoppedTimesheet
        const editingId = editing && editing.id !== undefined && editing.id !== "" ? editing.id : null
        const added = editingId === null
        session.entries.write(editingId, fields, function(result) {
            root.savingEntry = false
            if (!result.ok) {
                root.showError(result.error)
                return
            }
            root.clearError()
            root.returnToMainView()
            root.notify(
                added ? i18n("Entry added") : i18n("Entry updated"),
                description || (added ? i18n("Manual time entry") : i18n("Timesheet updated")))
        })
    }

    function syncDisplayStateFromConfig() {
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
        } else if (!plasmoid.configuration.popupShowNewActivity) {
            showNewActivityForm = false
        }
    }

    /** The profile switcher: shared.json names the new profile, then the widget reloads. */
    function switchProfile(id) {
        const c = session.connection
        resetProfileView()
        session.catalog.invalidate()
        if (c.profile && c.profile.id === id) {
            reload(Session.Probe.Fresh)
            return
        }
        const target = Profiles.profileById(c.profiles, id)
        const keys = { kimaiUrl: target ? (target.url || "") : "", profilesJson: plasmoid.configuration.profilesJson, activeProfileId: id }
        // The configuration change reloads (Connections below); shared.json must hold it first.
        const apply = function() { plasmoid.configuration.activeProfileId = id }
        c.saveProfiles(keys).then(apply, apply)
    }

    /** The timer stopped (here, elsewhere, another profile): its editors and flashes go. */
    function resetTrackingView() {
        editingActiveEntry = false
        editingStoppedTimesheet = null
        cancelDescriptionSavedFlash()
        if (!compactPopupLayout) {
            showNewActivityForm = plasmoid.configuration.desktopShowNewActivity
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

    /** Enter or the save button: the typed description now. */
    function saveCurrentDescription() {
        const t = session.timer
        if (!t.tracking || !t.timesheetId || t.savingDescription || t.draft === t.description) {
            return
        }
        cancelDescriptionSavedFlash()
        userMessage = ""
        t.flushDescription()
    }

    function remainingTodayText() {
        const r = session.totals.remainingTodaySeconds
        if (r >= 0) {
            return i18n("%1 left today", KimaiApi.formatDurationShort(r))
        }
        return i18n("%1 over today", KimaiApi.formatDurationShort(-r))
    }

    function remainingWeekText() {
        const r = session.totals.remainingWeekSeconds
        if (r >= 0) {
            return i18n("%1 left this week", KimaiApi.formatDurationShort(r))
        }
        return i18n("%1 over this week", KimaiApi.formatDurationShort(-r))
    }

    /** Panel hover tooltip body; respects Panel-Flyout work-summary setting. */
    function panelTooltipBody() {
        const showSummary = plasmoid.configuration.popupShowWorkSummary
        const t = session.timer
        const sum = session.totals
        const lines = []
        const line1 = []
        if (t.tracking) {
            line1.push(KimaiApi.formatDuration(t.elapsedSeconds))
        }
        if (showSummary) {
            line1.push(i18n("Today %1", KimaiApi.formatDurationShort(sum.todayLiveSeconds)))
        }
        if (line1.length > 0) {
            lines.push(line1.join(" · "))
        }
        if (showSummary && sum.hasWorkContract) {
            const line2 = []
            if (sum.todayTargetSeconds > 0) {
                line2.push(remainingTodayText())
            }
            if (sum.weekTargetSeconds > 0) {
                line2.push(remainingWeekText())
            }
            if (line2.length > 0) {
                lines.push(line2.join(" · "))
            }
        }
        return lines.join("\n")
    }

    /** The pickers live in fullRepresentation, which may not exist yet. */
    function setSwitchPickerIndex(combo, index) {
        if (root.switchPickersRef) {
            root.switchPickersRef[combo].currentIndex = index
        }
    }

    /** The switch form's activity picker for `projectId`, with `activityId` chosen when given. */
    function showActivities(projectId, activityId) {
        session.catalog.loadActivities(projectId, function(model) {
            root.activityPickerModel = model
            for (let a = 0; activityId && a < model.length; a++) {
                if (model[a].value && String(model[a].value.id) === String(activityId)) {
                    root.setSwitchPickerIndex("activityCombo", a)
                    return
                }
            }
            root.setSwitchPickerIndex("activityCombo", -1)
        })
    }

    function selectProjectById(projectId, activityIdToSelect) {
        if (!projectId) {
            return
        }
        const model = session.catalog.projectPickerModel
        let idx = -1
        for (let i = 0; i < model.length; i++) {
            if (model[i].value && String(model[i].value.id) === String(projectId)) {
                idx = i
                break
            }
        }
        if (idx < 0) {
            return
        }
        setSwitchPickerIndex("projectCombo", idx)
        selectedProjectId = projectId
        showActivities(projectId, activityIdToSelect)
    }

    function loadActivitiesForProject(projectId) {
        selectedProjectId = projectId || null
        if (!session.connection.configured || !projectId) {
            activityPickerModel = []
            setSwitchPickerIndex("activityCombo", -1)
            return
        }
        showActivities(projectId, null)
    }

    /** After a catalog answer: the pickers, statistics and the open editor take its names. */
    function rebuildCatalogViews() {
        if (selectedProjectId) {
            session.catalog.loadActivities(selectedProjectId, function(model) { root.activityPickerModel = model })
        }
        rehydrateStatsTimesheets()
        if (session.timer.active && editingActiveEntry) {
            Qt.callLater(function() {
                if (root.editingActiveEntry && root.activeEditViewRef) {
                    root.activeEditViewRef.loadFromTimesheet(root.session.timer.active)
                }
            })
        }
        if (!session.timer.tracking) {
            Qt.callLater(root.preloadLastActivity)
        }
    }

    /** Not tracking: the switch form starts with the last activity (Recent, or the last used). */
    function preloadLastActivity() {
        const last = session.recent.last
        const s = session.settings
        if (session.timer.tracking || !session.connection.configured) {
            return
        }
        const pid = last ? KimaiApi.projectId(last) : s.lastUsedProjectId
        const aid = last ? KimaiApi.activityId(last) : s.lastUsedActivityId
        if (!pid || !aid || session.catalog.projectPickerModel.length === 0) {
            return
        }
        selectProjectById(pid, aid)
        if (root.descriptionFieldRef && last) {
            root.descriptionFieldRef.text = last.description || ""
        }
    }

    function continueLastActivity() {
        const last = session.recent.last
        if (last) {
            requestRestartFromRecent(last)
            return
        }
        session.timer.startLastUsed()
    }

    /** The session's answer to a start or restart request: a hint on the row, or the switch question. */
    function presentRestart(decision, ts) {
        if (decision === Session.Restart.Hint) {
            alreadyRunningHintKey = session.timer.hintKey(ts)
            alreadyRunningHintTimer.restart()
            userMessage = ""
            return
        }
        if (decision !== Session.Restart.Confirm) {
            return
        }
        pendingSwitchTimesheet = ts
        if (switchRecentDialogRef) {
            switchRecentDialogRef.open()
        } else {
            confirmSwitchFromRecent()
        }
    }

    function startPinned(entry) {
        if (!entry) {
            return
        }
        presentRestart(session.timer.startPinned(entry), Favorites.asTimesheet(entry))
    }

    function requestStop() {
        const t = session.timer
        if (!session.connection.configured || session.busy || !t.tracking || !t.timesheetId) {
            return
        }
        if (session.settings.confirmBeforeStop && stopConfirmDialogRef) {
            stopConfirmDialogRef.open()
            return
        }
        t.stop()
    }

    function requestRestartFromRecent(timesheet) {
        if (!session.connection.configured || session.busy || !timesheet) {
            return
        }
        if (!session.timer.tracking) {
            userMessage = ""
            continuing = timesheet
        }
        presentRestart(session.timer.requestRestart(timesheet), timesheet)
    }

    function confirmSwitchFromRecent() {
        const timesheet = pendingSwitchTimesheet
        pendingSwitchTimesheet = null
        if (!timesheet) {
            return
        }
        const pid = KimaiApi.projectId(timesheet)
        const aid = KimaiApi.activityId(timesheet)
        if (!pid || !aid) {
            userMessage = i18n("Could not resolve project or activity for that entry")
            return
        }
        userMessage = ""
        const cat = session.catalog
        session.timer.switchTo(
            pid,
            aid,
            KimaiApi.displayProjectName(timesheet, cat.projects),
            KimaiApi.displayActivityName(timesheet, cat.activities, cat.activitiesByProject),
            timesheet.description || "")
    }

    function timesheetIsRunning(timesheet) {
        return !!(session.timer.tracking && timesheet && timesheet.id !== undefined && timesheet.id !== null
                  && String(timesheet.id) === String(session.timer.timesheetId))
    }

    function requestDeleteStopped(timesheet) {
        if (!session.connection.configured || session.busy || !timesheet || !session.connection.capabilities.deleteEntry) {
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
        const timesheet = pendingDeleteTimesheet
        pendingDeleteTimesheet = null
        if (!timesheet || timesheet.id === undefined || timesheet.id === null || timesheet.id === "") {
            return
        }
        userMessage = ""
        const cat = session.catalog
        session.entries.remove(timesheet, function() {
            root.clearError()
            root.notify(i18n("Entry deleted"),
                        KimaiApi.displayActivityName(timesheet, cat.activities, cat.activitiesByProject))
        })
    }

    function requestSplitStopped(timesheet) {
        if (!session.connection.configured || session.busy || !timesheet || !session.connection.capabilities.editStopped) {
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
        const timesheet = pendingSplitTimesheet
        pendingSplitTimesheet = null
        if (!timesheet) {
            return
        }
        const at = splitEntryDialogRef && typeof splitEntryDialogRef.splitInstant === "function"
                   ? splitEntryDialogRef.splitInstant()
                   : null
        if (!TimesheetFields.splitStoppedEntry(timesheet, at).ok) {
            userMessage = i18n("Split time must be between begin and end.")
            return
        }
        userMessage = ""
        const cat = session.catalog
        session.entries.split(timesheet, at, function() {
            root.clearError()
            root.notify(i18n("Entry split"),
                        KimaiApi.displayActivityName(timesheet, cat.activities, cat.activitiesByProject))
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

        // System keeps the theme-positive tint. The Kante styles keep the panel neutral and
        // mark a running timer with a small red indicator (config: trackingIndicator).
        readonly property color trackingColor: KanteStyle.active ? KanteStyle.textColor : KanteStyle.positiveTextColor
        readonly property int recMode: plasmoid.configuration.trackingIndicator

        Rectangle {
            anchors.fill: parent
            radius: 3
            visible: root.session.timer.tracking && !KanteStyle.active
            color: KanteStyle.tint(compactRoot.trackingColor, 0.12)
            border.width: 1
            border.color: KanteStyle.tint(compactRoot.trackingColor, 0.35)
        }

        RecEdge {
            mode: compactRoot.recMode
            active: root.session.timer.tracking && KanteStyle.active
        }

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: TouchUi.compactIconSize
                Layout.preferredHeight: TouchUi.compactIconSize
                // The Kante styles keep the Plasmai mark while tracking.
                source: root.connectionState === "error" ? "network-disconnect"
                        : (root.session.timer.tracking && !KanteStyle.active) ? "media-record" : Qt.resolvedUrl("../images/icon.svg")
                isMask: root.connectionState !== "error" && (!root.session.timer.tracking || KanteStyle.active)
                active: compactRoot.containsMouse
                color: root.session.timer.tracking ? compactRoot.trackingColor : KanteStyle.textColor
            }

            RowLayout {
                id: panelColorPills
                spacing: 1
                visible: root.session.timer.tracking
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

            RecDot {
                visible: root.session.timer.tracking && KanteStyle.active && compactRoot.recMode === 0
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                visible: root.session.timer.tracking && plasmoid.configuration.showElapsedInPanel
                text: KimaiApi.formatDurationPanel(root.session.timer.elapsedSeconds)
                font.family: KanteStyle.monoFamily
                font.pointSize: KanteStyle.smallFont.pointSize
                font.bold: true
                color: KanteStyle.active ? KanteStyle.textColor : Kirigami.Theme.textColor
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
        readonly property bool splitActive: root.mainViewMode === "main" && !root.session.setup.showWizard
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
                text: i18n("Stop tracking %1 · %2?", root.session.timer.project, root.session.timer.activity)
                wrapMode: Text.WordWrap
            }

            onAccepted: root.session.timer.stop()
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
                ? KimaiApi.customerNameFromTimesheet(root.pendingSwitchTimesheet, root.session.catalog.customersById)
                : ""
            readonly property string pendingProject: root.pendingSwitchTimesheet
                ? KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.session.catalog.projects)
                : ""
            readonly property string pendingActivity: root.pendingSwitchTimesheet
                ? KimaiApi.displayActivityName(
                    root.pendingSwitchTimesheet, root.session.catalog.activities, root.session.catalog.activitiesByProject)
                : ""
            readonly property var pendingBarInfo: root.pendingSwitchTimesheet
                ? KimaiApi.barColorInfoFromTimesheet(root.pendingSwitchTimesheet, root.session.catalog.customersById)
                : ({ color: PlasmaiColors.entityFallback, category: "", id: null })

            component ActivityCard: Rectangle {
                id: card
                property string caption: ""
                property string customerName: ""
                property string projectName: ""
                property string activityName: ""
                property color accentColor: PlasmaiColors.entityFallback
                property bool emphasize: false

                radius: 6
                color: emphasize
                       ? KanteStyle.tint(KanteStyle.highlightColor, 0.12)
                       : KanteStyle.tint(KanteStyle.textColor, 0.05)
                border.width: 1
                border.color: emphasize
                              ? KanteStyle.tint(KanteStyle.highlightColor, 0.35)
                              : KanteStyle.tint(KanteStyle.textColor, 0.14)
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
                        id: cardProjectRow
                        Layout.fillWidth: true
                        visible: card.projectName.length > 0
                        customerRole: false
                        customerColor: card.accentColor
                        label: card.projectName
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: cardProjectRow.labelX
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
                    customerName: root.session.timer.customer
                    projectName: root.session.timer.project
                    activityName: root.session.timer.activity
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
                                KimaiApi.displayProjectName(ts, root.session.catalog.projects),
                                KimaiApi.displayActivityName(ts, root.session.catalog.activities, root.session.catalog.activitiesByProject))
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
            // Closed without an answer: asked again at the next check.
            onClosed: {
                if (root.session.reminders.idlePending) {
                    root.session.reminders.clearPending()
                }
            }
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
                // Discarding rewrites the running entry's end: online only (offline.js).
                PlasmaComponents3.Label {
                    visible: root.session.sync.offline
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("Discarding idle time needs a connection to the server.")
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
                        root.session.reminders.keep()
                        idleDialog.close()
                    }
                }
                KantePlasmaButton {
                    Layout.fillWidth: true
                    enabled: !root.session.sync.offline
                    text: i18n("Discard idle")
                    Accessible.name: text
                    onClicked: {
                        root.session.reminders.discard(Session.AfterIdle.Stop)
                        idleDialog.close()
                    }
                }
                KantePlasmaButton {
                    Layout.fillWidth: true
                    enabled: !root.session.sync.offline
                    text: i18n("Discard and continue")
                    Accessible.name: text
                    onClicked: {
                        root.session.reminders.discard(Session.AfterIdle.Continue)
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
            customers: root.session.catalog.customers
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
                            text: root.mainViewMode === "unsynced" ? i18n("Not synced")
                                  : root.mainViewMode === "stats" ? i18n("Statistics")
                                  : (root.mainViewMode === "filmday" ? i18n("Film day")
                                  : (root.mainViewMode === "trip" ? (root.tripSheetRef ? root.tripSheetRef.title : i18n("Trip"))
                                  : (root.mainViewMode === "manual"
                                     ? (root.editingStoppedTimesheet ? i18n("Edit entry") : i18n("Add entry"))
                                      : (BuildInfo.BUILD > 0 ? (i18n("Plasmai") + " #" + BuildInfo.BUILD) : i18n("Plasmai")))))
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 2
                            visible: !root.session.setup.showWizard && Profiles.showsConnection(root.session.connection.profiles, root.session.connection.configured, root.connectionState)

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

                            KanteLoader {
                                visible: KanteStyle.active && root.loading
                                Layout.alignment: Qt.AlignVCenter
                            }

                            QQC2.BusyIndicator {
                                running: root.loading
                                visible: running && !KanteStyle.active
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        KantePlasmaToolButton {
                            visible: root.session.connection.configured && root.mainViewMode === "main"
                            icon.name: "list-add"
                            text: i18n("Add entry")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.session.busy && root.connectionState !== "error"
                            onClicked: root.openManualEntry()
                            PlasmaComponents3.ToolTip.text: i18n("Add a manual time entry")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.session.connection.configured && root.mainViewMode === "main"
                                     && root.session.connection.capabilities.statistics
                            icon.name: "view-statistics"
                            text: i18n("Statistics")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.session.busy
                            onClicked: root.openStatsView()
                            PlasmaComponents3.ToolTip.text: i18n("Show statistics")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.session.filmDay.available && root.mainViewMode === "main"
                            icon.name: "view-calendar-day"
                            text: i18n("Film day")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.session.busy && root.connectionState !== "error"
                            onClicked: root.openFilmDayView()
                            PlasmaComponents3.ToolTip.text: i18n("Log a shooting day")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.session.connection.configured && root.mainViewMode === "main" && root.session.trips.canEdit
                            icon.name: "mark-location"
                            text: i18n("Log trip")
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon
                                                    : QQC2.AbstractButton.IconOnly
                            enabled: !root.session.busy && !root.tripBusy && root.connectionState !== "error"
                            onClicked: root.openNewTrip()
                            PlasmaComponents3.ToolTip.text: i18n("Log a trip (Anfahrten plugin)")
                            PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }

                        KantePlasmaToolButton {
                            visible: root.mainViewMode === "manual" || root.mainViewMode === "stats"
                                     || root.mainViewMode === "filmday" || root.mainViewMode === "trip"
                                     || root.mainViewMode === "unsynced"
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
                    // Switching profiles is online only (offline.js): the outbox belongs to the profile.
                    enabled: !root.session.sync.offline
                    visible: root.session.connection.profiles.length > 1
                             && (root.mainViewMode === "main"
                                 || root.mainViewMode === "stats")
                             && !root.editingActiveEntry
                             && !root.editingStoppedTimesheet
                             && !(root.showNewActivityForm && root.compactPopupLayout)
                    model: root.session.connection.profiles.map(function(p) { return p.name })
                    currentIndex: {
                        for (var i = 0; i < root.session.connection.profiles.length; i++) {
                            if (root.session.connection.profiles[i].id === root.profileId) {
                                return i
                            }
                        }
                        return 0
                    }
                    onActivated: function(index) {
                        if (index >= 0 && index < root.session.connection.profiles.length) {
                            root.switchProfile(root.session.connection.profiles[index].id)
                        }
                    }
                }

                // Offline and sync state; "Show" opens the list of what is not synced yet.
                OfflineStatus {
                    Layout.fillWidth: true
                    visible: (root.session.sync.offline || root.session.sync.unsynced > 0) && root.mainViewMode !== "unsynced"
                    offline: root.session.sync.offline
                    stateAt: root.session.sync.stateAt
                    unsynced: root.session.sync.unsynced
                    stuck: root.session.sync.stuck
                    onDetailsRequested: root.openUnsyncedView()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "unsynced"
                    spacing: Kirigami.Units.largeSpacing

                    OfflineStatus {
                        Layout.fillWidth: true
                        offline: root.session.sync.offline
                        stateAt: root.session.sync.stateAt
                        unsynced: root.session.sync.unsynced
                        stuck: root.session.sync.stuck
                        showDetails: false
                    }

                    UnsyncedList {
                        Layout.fillWidth: true
                        ops: root.session.sync.ops
                        projects: root.session.catalog.projects
                        activities: root.session.catalog.activities
                        activitiesByProject: root.session.catalog.activitiesByProject
                        onRetryRequested: function(opId) {
                            root.session.sync.retry(opId)
                        }
                        onOverwriteRequested: function(opId) {
                            root.session.sync.overwrite(opId)
                        }
                        onDiscardRequested: function(opId) {
                            root.session.sync.discard(opId)
                        }
                    }
                }

                // First start: created only while needed, with the settings of that moment.
                Loader {
                    id: setupWizardLoader
                    // Flush with the header like the other views (add entry, film day, trip).
                    Layout.fillWidth: true
                    active: root.session.setup.showWizard && root.mainViewMode === "main"
                    visible: active
                    sourceComponent: SetupWizard {
                        setup: root.session.setup
                        profiles: root.session.connection.profiles
                        activeProfileId: root.profileId || "default"
                        supportsReminders: true
                        workDayBegin: root.session.settings.workDayBegin
                        workDayEnd: root.session.settings.workDayEnd
                        locationName: root.session.settings.locationName
                        notifyForgotToStart: root.session.settings.notifyForgotToStart
                        visualStyle: root.session.settings.visualStyle
                        onStyleChosen: function(style) { root.session.setup.applyStyle(style) }
                        onConnected: function(patch) { root.session.setup.applyConnection(patch) }
                        onFinished: function(patch) { root.session.setup.finish(patch) }
                    }
                }

                KantePlasmaButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: setupWizardLoader.active && root.showSetupState
                    flat: true
                    text: i18n("More options in the settings")
                    onClicked: root.openConfigure()
                }

                Kirigami.InlineMessage {
                    KanteMessageSkin { message: parent }
                    Layout.fillWidth: true
                    visible: root.showErrorState && !root.session.setup.showWizard
                    type: Kirigami.MessageType.Error
                    text: root.errorMessage
                    actions: [
                        Kirigami.Action {
                            text: i18n("Retry")
                            icon.name: "view-refresh"
                            onTriggered: root.reload(Session.Probe.Fresh)
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
                    visible: root.mainViewMode === "manual" && root.session.connection.configured
                    projectPickerModel: root.session.catalog.projectPickerModel
                    activityPickerModel: root.activityPickerModel
                    activitySectionTitles: root.activitySectionTitles
                    pickerOpenBelow: root.pickerOpenBelow
                    pickerViewport: popupScroll
                    busy: root.session.busy || root.savingEntry
                    configured: root.session.connection.configured
                    connectionOk: root.connectionState !== "error"
                    supportsBillableEdit: root.session.connection.capabilities.billableEdit
                    supportsTags: root.session.connection.capabilities.tags
                    tagSource: root.session.entries
                    showCreateActions: root.session.entries.canCreate
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

                // Built while shown only: its charts recompute on every poll's new entries.
                Loader {
                    Layout.fillWidth: true
                    active: root.mainViewMode === "stats" && root.session.connection.configured
                            && root.session.connection.capabilities.statistics
                    visible: active
                    sourceComponent: Component {
                        StatsView {
                            timesheets: root.statsTimesheets
                            customersById: root.session.catalog.customersById
                            todayTargetSeconds: root.session.totals.todayTargetSeconds
                            weekTargetSeconds: root.session.totals.weekTargetSeconds
                            hasWorkContract: root.session.totals.hasWorkContract
                                             && root.session.connection.capabilities.workContract
                            workDayBegin: root.workDayBegin
                            workDayEnd: root.workDayEnd
                            supportsBillableFilter: root.session.connection.capabilities.billableFilter
                            tripSummary: root.statsTrips ? StatsData.tripKmSummary(root.statsTrips, new Date()) : null
                            onBackRequested: root.returnToMainView()
                            onNeedMoreHistory: function(rangeBegin, rangeEnd) {
                                root.loadStatsRange(rangeBegin, rangeEnd)
                            }
                        }
                    }
                }

                FilmDayView {
                    id: filmDayView
                    onlineActions: !root.session.sync.offline
                    Component.onCompleted: root.filmDayViewRef = filmDayView
                    Component.onDestruction: {
                        if (root.filmDayViewRef === filmDayView) {
                            root.filmDayViewRef = null
                        }
                    }
                    Layout.fillWidth: true
                    visible: root.mainViewMode === "filmday" && root.session.connection.configured
                             && root.session.connection.capabilities.filmDays
                    projectPickerModel: root.session.catalog.projectPickerModel
                    activityPickerModel: root.activityPickerModel
                    activitySectionTitles: root.activitySectionTitles
                    pickerOpenBelow: root.pickerOpenBelow
                    pickerViewport: popupScroll
                    busy: root.session.busy || root.savingFilmDay || root.loadingFilmDay
                    configured: root.session.connection.configured
                    connectionOk: root.connectionState !== "error"
                    showCreateActions: root.session.entries.canCreate
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
                    // Ticks only while shown (it stays built, holding the chosen day).
                    elapsedSeconds: root.mainViewMode === "filmday" ? root.session.timer.elapsedSeconds : 0
                    onSaveRequested: function(projectId, activityId, beginText, endText, filmDayFields) {
                        root.saveFilmDay(projectId, activityId, beginText, endText, filmDayFields, false)
                    }
                    onTimesEdited: function(beginText, endText) {
                        root.saveFilmDay(filmDayView.projectCombo.currentItem.value.id, filmDayView.activityCombo.currentItem.value.id,
                                         beginText, endText, filmDayView.currentEntryFields(), true)
                    }
                    onExtrasEdited: function(fields) {
                        root.saveFilmDayExtras(fields)
                    }
                    onNoteEdited: function(text) {
                        root.saveFilmDayNote(text)
                    }
                    // Closing the popup or leaving the film day must not drop a note still being typed.
                    onVisibleChanged: {
                        if (!visible) {
                            filmDayView.flushPending()
                        }
                    }
                    onStartRequested: function(projectId, activityId, projectLabel, activityLabel) {
                        root.session.timer.switchTo(projectId, activityId, projectLabel, activityLabel, filmDayView.noteText())
                    }
                    onStopRequested: root.session.timer.stop()
                    onRunningBeginEdited: function(beginText) {
                        var ts = root.session.timer.active
                        if (ts) {
                            root.saveActiveEdit(KimaiApi.projectId(ts), KimaiApi.activityId(ts), beginText, ts.billable, ts.tags || [])
                        }
                    }
                    onEngagementPicked: function(projectId) {
                        filmDayView.selectProjectId(projectId)
                        root.loadFilmDayForDate(root.filmDaySelectedDate, true)
                    }
                    tripsAvailable: root.session.trips.canEdit
                    onTripRequested: root.openTripForTimesheet(root.filmDayTimesheet)
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
                    visible: root.mainViewMode === "trip" && root.session.trips.available
                    busy: root.session.busy || root.tripBusy
                    configured: root.session.connection.configured
                    connectionOk: root.connectionState !== "error"
                    ping: root.session.trips.ping
                    meta: root.session.trips.meta
                    vehicles: root.session.trips.vehicles
                    places: root.session.setup
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
                    visible: root.mainViewMode === "main" && !root.session.setup.showWizard && !popupRoot.splitActive

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
                        session: root.session
                        view: root
                        popupItem: popupRoot
                        pickerScroll: popupScroll
                    }
                }

                Component {
                    id: kanteTimerCard
                    TimerCardKante {
                        session: root.session
                        view: root
                        popupItem: popupRoot
                        pickerScroll: popupScroll
                    }
                }

                EntryLists {
                    id: listSection
                    session: root.session
                    view: root
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
        // A Recent row opens its entry menu instead.
        MouseArea {
            id: rightClickCatcher
            anchors.fill: parent
            z: 1000
            acceptedButtons: Qt.RightButton
            onPressed: function(mouse) {
                var row = RowHit.historyRowAt(popupRoot, mouse.x, mouse.y, rightClickCatcher)
                if (row) {
                    var p = popupRoot.mapToItem(row, mouse.x, mouse.y)
                    row.openHistoryMenu(p.x, p.y)
                    return
                }
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
            sharedConfigScript, catalogCacheScript, localStoreScript, systemCheckScript))
        showNewActivityForm = !compactPopupLayout && plasmoid.configuration.desktopShowNewActivity
        reload(Session.Probe.Fresh)
    }

    Connections {
        target: plasmoid
        function onUserConfiguringChanged() {
            if (plasmoid.userConfiguring) {
                // Pull shared settings before editing so we don't save stale values.
                root.reload(Session.Probe.Cached)
                return
            }
            // Persist first, then reload — otherwise a racing reload can
            // re-apply the old shared.json and undo display changes until restart.
            const after = function() { root.reload(Session.Probe.Fresh) }
            root.persistShared().then(after, after)
        }
    }

    // Connection keys changed (settings dialog closed, profile switcher, the app): connect again.
    Connections {
        target: plasmoid.configuration
        function onProfilesJsonChanged() {
            root.reloadUnlessConfiguring()
        }
        function onActiveProfileIdChanged() {
            root.resetProfileView()
            root.reloadUnlessConfiguring()
        }
        function onKimaiUrlChanged() {
            root.reloadUnlessConfiguring()
        }
        // The layer takes the new value first (takeConfig).
        function onRecentCountChanged() {
            Qt.callLater(function() {
                if (root.session.connection.configured) {
                    root.session.recent.refresh()
                }
            })
        }
        function onPinnedActivitiesChanged() {
            Qt.callLater(root.session.favorites.resolve)
        }

        function onDesktopShowNewActivityChanged() { root.syncDisplayStateFromConfig() }
        function onPopupShowNewActivityChanged() { root.syncDisplayStateFromConfig() }
    }

    function reloadUnlessConfiguring() {
        if (!plasmoid.userConfiguring) {
            reload(Session.Probe.Fresh)
        }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (!root.expanded) {
                // A note still being typed in the film day is saved on close.
                if (root.filmDayViewRef) {
                    root.filmDayViewRef.flushPending()
                }
                return
            }
            root.sparklineNowTick++
            if (!root.session.connection.configured || root.connectionState !== "online") {
                root.reload(Session.Probe.Cached)
                return
            }
            root.session.refresh()
            root.syncDisplayStateFromConfig()
            root.session.filmDay.resolveMode(Session.Probe.Cached)
            root.session.trips.resolve(Session.Probe.Cached, function() {
                if (root.expanded) {
                    root.loadTripSuggestions(false)
                }
            })
        }
    }
}
