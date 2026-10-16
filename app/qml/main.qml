import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "platform/appBackend.js" as AppBackend
import "../contents/code/platform.js" as Platform
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/mileage.js" as Mileage
import "../contents/code/dateTimeFormat.js" as DTF
import "shared"
import "Kante"

Kirigami.ApplicationWindow {
    id: root
    signal switchConfirmRequested()
    Material.theme: Material.Dark

    // ── Visual style (shared.json visualStyle: 0 System, 1 Kante, 2 Kante Light), see Kante/KanteStyle.qml ──
    Binding {
        target: KanteStyle
        property: "kind"
        value: root.visualStyle
    }
    Binding {
        target: KanteStyle
        property: "preferDark"
        // Android always runs Material Dark (main.cpp), whatever Kirigami reports. Windows and
        // macOS have no Kirigami platform theme: the system's setting decides (main.cpp hands the
        // matching Breeze colors to Qt).
        value: Qt.platform.os === "android"
            || ((Qt.platform.os === "windows" || Qt.platform.os === "osx") && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)
    }
    Binding {
        target: KanteStyle
        property: "materialStyle"
        // Android runs the Material style (main.cpp): Kante reaches Kirigami
        // through the Material colors below, not through Kirigami.Theme.
        value: Qt.platform.os === "android"
    }

    // Windows and macOS: the tool bar and the Basic controls draw with the window's palette, not
    // with Kirigami.Theme. In Kante it takes Kante's ground and ink, so the header is one surface
    // with the page and its buttons show themselves only on hover (flat, like the Plasmoid's).
    readonly property bool desktopPalette: Qt.platform.os === "windows" || Qt.platform.os === "osx"
    Binding { target: root.palette; property: "window"; value: KanteStyle.backgroundColor; when: root.desktopPalette && KanteStyle.themed }
    Binding { target: root.palette; property: "button"; value: KanteStyle.backgroundColor; when: root.desktopPalette && KanteStyle.themed }
    Binding { target: root.palette; property: "windowText"; value: KanteStyle.textColor; when: root.desktopPalette && KanteStyle.themed }
    Binding { target: root.palette; property: "buttonText"; value: KanteStyle.textColor; when: root.desktopPalette && KanteStyle.themed }
    Binding { target: root.palette; property: "mid"; value: KanteStyle.ruleColor; when: root.desktopPalette && KanteStyle.themed }

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

    // ── The session layer: every page reads and acts through it (Session.qml) ──
    readonly property Session session: Session {
        offlinePrefix: "app-"
        setupMode: Session.Setup.Run
        reminders.idleAvailable: root.supportsIdleDetection
        reminders.notificationsAvailable: root.supportsNotifications
    }
    // Shown at once by the setup wizard's Look step and the settings page.
    readonly property int visualStyle: session.settings.visualStyle

    function timesheetSummaryText(ts) {
        if (!ts) return ""
        var bits = [KimaiApi.displayProjectName(ts, session.catalog.projects), KimaiApi.displayActivityName(ts, session.catalog.activities, session.catalog.activitiesByProject)]
        var begin = DTF.parseStamp(ts.begin)
        if (!isNaN(begin.getTime())) bits.push(begin.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " " + begin.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
        return bits.filter(function(b) { return !!b }).join(" · ")
    }

    /** Trip page for a new trip, or linked to a Kimai entry (Recent row, running entry, travel film day). */
    function openTripForTimesheet(ts) {
        if (!session.trips.canEdit) return
        pageStack.push(tripEditPageComponent, {
            form: ts ? Mileage.formForTimesheet(session.trips.ping, ts, KimaiApi.projectId) : Mileage.emptyForm(session.trips.ping, Mileage.dateString(new Date())),
            linkedText: timesheetSummaryText(ts)
        })
    }

    // ── Platform services offered by main.cpp (idle time, notifications, network, tray, autostart) ──
    readonly property bool supportsIdleDetection: typeof idleWatcher !== "undefined"
    readonly property bool supportsNotifications: typeof notifier !== "undefined"
    readonly property var networkStatusService: typeof networkStatus !== "undefined" ? networkStatus : null
    readonly property var trayService: typeof trayClient !== "undefined" ? trayClient : null
    readonly property var autostartService: typeof autostart !== "undefined" ? autostart : null
    readonly property var trackingNoticeService: typeof trackingNotice !== "undefined" ? trackingNotice : null

    // ── Tray client (Windows, ROADMAP pillar 7): icon state, tooltip and menu, like the Plasmoid's panel icon ──
    Binding {
        target: root.trayService
        when: !!root.trayService
        property: "tracking"
        value: root.session.timer.tracking
    }
    Binding {
        target: root.trayService
        when: !!root.trayService
        property: "toolTip"
        value: root.session.timer.tracking
            ? root.session.timer.project + " · " + root.session.timer.activity + " · " + KimaiApi.formatDurationShort(root.session.timer.elapsedSeconds)
            : (root.session.sync.offline ? i18n("Plasmai") + " · " + i18n("Offline") : i18n("Plasmai"))
    }
    Binding {
        target: root.trayService
        when: !!root.trayService
        property: "menu"
        value: root.trayMenu()
    }
    Connections {
        target: root.trayService
        function onMenuTriggered(id) { root.trayAction(id) }
    }

    // ── Permanent notification while a timer runs (Android, Plasma Mobile) ──
    /** What the notification shows ("" = none): a change posts it again. */
    readonly property string trackingNoticeKey: trackingNoticeService && Kirigami.Settings.isMobile && session.timer.tracking
        ? [session.timer.timesheetId, session.timer.project, session.timer.activity, session.timer.active ? session.timer.active.begin : ""].join("|") : ""
    onTrackingNoticeKeyChanged: Qt.callLater(updateTrackingNotice)
    Connections {
        target: Qt.application
        // Back in front after Android's permission dialog: now the notification can be posted.
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) {
                root.session.timer.sync()
            }
            if (Qt.platform.os === "android" && Qt.application.state === Qt.ApplicationActive) {
                root.updateTrackingNotice()
            }
        }
    }
    Connections {
        target: root.trackingNoticeService
        function onActivated() { root.show(); root.raise(); root.requestActivate() }
    }

    function updateTrackingNotice() {
        if (!trackingNoticeService) {
            return
        }
        if (trackingNoticeKey === "") {
            trackingNoticeService.hide()
            return
        }

        // The begin of the entry: Android counts the elapsed time from it.
        const t = session.timer
        let begin = t.active && t.active.begin ? DTF.parseStamp(t.active.begin) : null
        if (!begin || isNaN(begin.getTime())) {
            begin = new Date(Date.now() - t.elapsedSeconds * 1000)
        }
        trackingNoticeService.show(t.project + " · " + t.activity,
                                   i18n("Running since %1", DTF.formatLocaleTime(begin.getHours(), begin.getMinutes())),
                                   begin.getTime())
    }

    /** The tray icon's context menu (TrayController.menu): the timer, the popup, autostart, quit. */
    function trayMenu() {
        const t = session.timer
        const s = session.settings
        var items = [{ id: "open", text: i18n("Open Plasmai") }, { separator: true }]
        if (t.tracking) {
            items.push({ id: "stop", text: i18n("Stop %1 · %2", t.project, t.activity), enabled: !session.busy })
        } else if (t.hasLastUsed) {
            items.push({ id: "startLast", text: i18n("Start %1 · %2", s.lastUsedProjectName, s.lastUsedActivityName),
                         enabled: !session.busy && session.connection.configured })
        }
        items.push({ separator: true })
        if (autostartService) {
            items.push({ id: "autostart", text: i18n("Start at login"), checkable: true, checked: autostartService.enabled })
        }
        items.push({ id: "quit", text: i18n("Quit") })
        return items
    }

    function trayAction(id) {
        if (id === "open") {
            trayService.showPopup()
        } else if (id === "stop") {
            session.timer.stop()
        } else if (id === "startLast") {
            session.timer.startLastUsed()
        } else if (id === "autostart") {
            autostartService.enabled = !autostartService.enabled
        } else if (id === "quit") {
            Qt.quit()
        }
    }

    title: i18n("Plasmai")
    // The tray client shows the window as its popup (main.cpp, TrayController).
    width: 420; height: 720; visible: !trayService

    // ── View state ──
    property int sparklineNowTick: 0
    property string alreadyRunningHintKey: ""
    property bool descriptionSavedFlash: false
    property var pendingSwitchTimesheet: null

    function remainingTodayText() { var r = session.totals.remainingTodaySeconds; return r >= 0 ? i18n("%1 left today", KimaiApi.formatDurationShort(r)) : i18n("%1 over today", KimaiApi.formatDurationShort(-r)) }
    function remainingWeekText() { var r = session.totals.remainingWeekSeconds; return r >= 0 ? i18n("%1 left this week", KimaiApi.formatDurationShort(r)) : i18n("%1 over this week", KimaiApi.formatDurationShort(-r)) }

    Timer { id: alreadyRunningHintTimer; interval: 1400; repeat: false; onTriggered: root.alreadyRunningHintKey = "" }
    // Only while the window shows (the tray client hides it); catches up when shown again.
    Timer { id: sparklineTimer; interval: 30000; running: root.session.connection.configured && root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.sparklineNowTick++ }
    Timer { id: descriptionFlashTimer; interval: 2500; repeat: false; onTriggered: root.descriptionSavedFlash = false }

    // ── The session's signals, worded for this window ──
    Connections {
        target: root.session
        function onFailed(action, result) { root.reportFailure(action, result) }
        function onStarted(ts, origin, names) {
            if (origin === Session.Origin.Start && root.session.settings.notifyOnStart) {
                root.session.reminders.notify(i18n("Started"), names.project + " · " + names.activity)
            }
        }
        function onStopped(ts, names) {
            if (root.session.settings.notifyOnStop) {
                root.session.reminders.notify(i18n("Stopped"), names.project + " · " + names.activity)
            }
        }
        // Starts here notify above too; this one also covers timers started elsewhere.
        function onTrackingBegan(ts) {
            const t = root.session.timer
            if (root.session.settings.notifyOnStart) {
                root.session.reminders.notify(i18n("Tracking in progress"), t.project + " · " + t.activity + " · " + KimaiApi.formatDurationShort(t.elapsedSeconds))
            }
        }
        /** Kimai saved the entry but ignored billable (no edit_billable permission). */
        function onDroppedFields(fields) {
            root.showPassiveNotification(i18n("Saved without the billable change: your Kimai account is not allowed to edit billable."))
        }
    }
    Connections {
        target: root.session.timer
        function onDescriptionSaved() {
            root.descriptionSavedFlash = true
            descriptionFlashTimer.restart()
        }
    }
    Connections {
        target: root.session.reminders
        function onIdleDiscarded(snap) {
            if (root.session.settings.notifyOnIdleStop) {
                root.session.reminders.notify(i18n("Idle time discarded"), snap.projectName + " · " + snap.activityName)
            }
        }
        function onForgotToStart() {
            root.session.reminders.notify(i18n("Nothing is tracking"), i18n("Start tracking when you begin work."))
        }
    }

    /** A failed action of the session, as a passive notification. */
    function reportFailure(action, result) {
        switch (action) {
        case Session.Action.Start:
        case Session.Action.Switch:
        case Session.Action.Continue:
            reportWriteError(result, i18n("Could not start tracking"))
            return
        case Session.Action.Stop:
            reportWriteError(result, i18n("Could not stop tracking"))
            return
        case Session.Action.Save:
            reportWriteError(result, i18n("Could not save the entry"))
            return
        case Session.Action.Delete:
            reportWriteError(result, i18n("Could not delete the entry"))
            return
        case Session.Action.Split:
            reportWriteError(result, i18n("Could not split the entry"))
            return
        case Session.Action.SplitRange:
            showPassiveNotification(i18n("Split time must be between begin and end."))
            return
        case Session.Action.SplitSecond:
            showPassiveNotification(i18n("The first half was saved, but the second half could not be created."))
            return
        default:
            // Refresh: the connection line and its retry show it.
            return
        }
    }

    /** A write failed: say so instead of silently refreshing. */
    function reportWriteError(result, what) {
        if (!result || result.ok) return
        var detail = (result.error && result.error.detail) || ApiErrors.text(result.error)
        showPassiveNotification(detail ? i18n("%1: %2", what, detail) : what)
    }

    /** The session's answer to a start or restart request: a hint on the row, or the switch question. */
    function presentRestart(decision, ts) {
        if (decision === Session.Restart.Hint) {
            alreadyRunningHintKey = session.timer.hintKey(ts)
            alreadyRunningHintTimer.restart()
            return
        }
        if (decision === Session.Restart.Confirm) {
            pendingSwitchTimesheet = ts
            switchConfirmRequested()
        }
    }

    function requestRestartFromRecent(ts) {
        presentRestart(session.timer.requestRestart(ts), ts)
    }

    function startPinned(entry) {
        presentRestart(session.timer.startPinned(entry), entry ? { project: entry.projectId, activity: entry.activityId } : null)
    }

    function formatElapsed(sec) { var h = Math.floor(sec / 3600); var m = Math.floor((sec % 3600) / 60); if (h > 0) return i18n("%1h %2m", h, m); return i18n("%1m %2s", m, sec % 60) }

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
        flattenHeaderButton(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; ++i) nameDrawerButtons(kids[i])
    }

    property var flatButtons: []

    /** Windows and macOS (Basic style): the header's buttons draw a filled plate even at rest,
     *  a lighter grey on the bar. Like Kirigami's own header and the Plasmoid's, they show a
     *  plate on hover, press and check only. */
    function flattenHeaderButton(item) {
        if (!root.desktopPalette || flatButtons.indexOf(item) >= 0 || item.background === undefined
                || item.hovered === undefined || item.down === undefined || item.checked === undefined) {
            return
        }
        var name = String(item)
        if (name.indexOf("PrivateActionToolButton") !== 0 && name.indexOf("HandleButton") !== 0
                && name.indexOf("BackButton") !== 0 && name.indexOf("NavigationButton") !== 0) {
            return
        }
        flatButtons.push(item)
        item.background.opacity = Qt.binding(function() { return item.hovered || item.down || item.checked ? 1 : 0 })
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
                visible: root.session.trips.available
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
        function onReachableChanged() { if (root.networkStatusService.reachable && root.session.connection.configured) root.session.refresh() }
    }
    Connections {
        target: root.pageStack
        function onCurrentItemChanged() { drawerButtonNamer.restart() }
        function onDepthChanged() { drawerButtonNamer.restart() }
    }

    // Offline and sync state under every page; "Show" lists what is not synced yet.
    footer: QQC2.Pane {
        visible: root.session.sync.offline || root.session.sync.unsynced > 0
        padding: Kirigami.Units.smallSpacing
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        OfflineStatus {
            id: offlineBar
            anchors.fill: parent
            offline: root.session.sync.offline
            stateAt: root.session.sync.stateAt
            unsynced: root.session.sync.unsynced
            stuck: root.session.sync.stuck
            showDetails: !pageStack.currentItem || pageStack.currentItem.objectName !== "unsyncedPage"
            onDetailsRequested: root.navigateTo(unsyncedComponent)
        }
    }

    pageStack.initialPage: TimerPage { }
    Component.onCompleted: {
        drawerButtonNamer.restart()
        Platform.setBackend(AppBackend.create(TokenStore, FileStore,
            typeof idleWatcher !== "undefined" ? idleWatcher : undefined,
            typeof notifier !== "undefined" ? notifier : undefined))
        session.open()
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

