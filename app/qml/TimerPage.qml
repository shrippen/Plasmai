import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/timesheetFields.js" as TimesheetFields
import "../contents/code/dateTimeFormat.js" as DTF
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: i18n("Plasmai")

    property bool editingActive: false
    property var editActivityPickerModel: []
    property bool showNewActivityForm: false
    property var newActivityPickerModel: []
    property string newActivityDescription: ""
    /** Split into a fixed timer pane + an independently scrolling list pane once there's
        room for both to be useful side by side (landscape phone, tablet, a freely resized
        desktop window) — below that threshold everything stacks in one scrolling column. */
    readonly property bool isWideLayout: width >= Kirigami.Units.gridUnit * 38

    actions: [
        Kirigami.Action {
            visible: root.isConfigured
            icon.name: "list-add"
            text: i18n("Add entry")
            onTriggered: pageStack.push(manualPageComponent)
        },
        Kirigami.Action {
            visible: root.isConfigured
            icon.name: "view-statistics"
            text: i18n("Statistics")
            onTriggered: pageStack.push(statsPageComponent)
        },
        Kirigami.Action {
            visible: root.isConfigured && root.providerCapabilities.filmDays
            icon.name: "view-calendar-day"
            text: i18n("Film day")
            onTriggered: pageStack.push(filmDayPageComponent)
        }
    ]

    function connIcon() { return !root.isConfigured ? "network-disconnect" : root.connectionState === "error" ? "network-disconnect" : root.connectionState === "connecting" ? "view-refresh" : "network-connect" }
    function connColor() { return !root.isConfigured ? KanteStyle.disabledTextColor : root.connectionState === "error" ? KanteStyle.negativeTextColor : KanteStyle.positiveTextColor }
    function workSummaryText() {
        var bits = []
        bits.push(i18n("Today %1", KimaiApi.formatDurationShort(root.todayLiveSeconds)))
        bits.push(i18n("Week %1", KimaiApi.formatDurationShort(root.weekLiveSeconds)))
        return bits.join(" · ")
    }
    function remainingText() {
        if (!root.hasWorkContract) return ""
        var bits = []
        if (root.todayTargetSeconds > 0) bits.push(root.remainingTodayText())
        if (root.weekTargetSeconds > 0) bits.push(root.remainingWeekText())
        return bits.join(" · ")
    }
    function isOverTime() { return root.hasWorkContract && (root.remainingTodaySeconds < 0 || root.remainingWeekSeconds < 0) }

    function openEdit() {
        if (!root.isTracking || !root.activeTimesheet) return
        editingActive = true
        var pid = KimaiApi.projectId(root.activeTimesheet)
        root.loadActivitiesForProject(pid, function(model) { page.editActivityPickerModel = model })
        activeEditView.timesheet = root.activeTimesheet
    }

    function openNewActivityForm() {
        showNewActivityForm = true
        newActivityPickerModel = root.projectPickerModel
        newActivityDescription = ""
    }

    /** Move heroCard/listSection between the narrow single column and the wide two-pane
        layout. Done imperatively (rather than via a `parent:` binding on each item) so the
        order they're appended to their shared host is guaranteed — two independent bindings
        evaluating in unspecified order previously could parent listSection before heroCard,
        which then painted the list on top of the timer card. */
    function relayoutPanes() {
        if (isWideLayout) {
            heroCard.parent = wideLeftCol
            listSection.parent = wideRightCol
        } else {
            heroCard.parent = narrowCol
            listSection.parent = narrowCol
        }
    }
    onIsWideLayoutChanged: relayoutPanes()
    Component.onCompleted: relayoutPanes()

    Connections {
        target: root
        function onSwitchConfirmRequested() { switchDialog.open() }
    }

    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() { keyboardScrollTimer.restart() }
    }
    // Wait until the window has resized for the keyboard before scrolling the field into view.
    Timer {
        id: keyboardScrollTimer
        interval: 250
        onTriggered: page.ensureFocusedVisible()
    }

    function ensureFocusedVisible() {
        var fi = root.activeFocusItem
        if (!fi || Qt.inputMethod.keyboardRectangle.height <= 0) return
        // Walk up to whichever Flickable currently holds the focused field — in the wide
        // layout the timer pane and the list pane scroll independently, so this can't be a
        // fixed id the way a single shared ScrollView could.
        var flick = fi.parent
        while (flick && typeof flick.contentY === "undefined") flick = flick.parent
        if (!flick) return
        // The window already resizes for the keyboard: bring the focused field to the top of
        // the viewport so its suggestion popup has the whole remaining height below it.
        var pos = flick.mapFromItem(fi, 0, 0)
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        // pos is relative to the viewport, not to the scrolled content
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + pos.y - Kirigami.Units.largeSpacing))
    }

    // ══════ FIXED TOP AREA — connection status, setup/error (always full width, never split) ══════
    ColumnLayout {
        id: topBar
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon { source: page.connIcon(); color: page.connColor(); Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small }
            QQC2.Label {
                text: {
                    if (!root.isConfigured) return i18n("Not configured")
                    if (root.connectionState === "connecting") return i18n("Connecting…")
                    if (root.connectionState === "error") return i18n("Connection problem")
                    var profileName = root.activeProfile ? root.activeProfile.name || "" : ""
                    var url = root.activeProfile ? root.activeProfile.url || "" : ""
                    return profileName.length > 0 ? i18n("Connected to %1 (%2)", url, profileName) : i18n("Connected to %1", url)
                }
                color: Qt.alpha(KanteStyle.textColor, 0.7); font.pointSize: KanteStyle.smallFont.pointSize; elide: Text.ElideRight
                Layout.fillWidth: true; maximumLineCount: 1
            }
            QQC2.BusyIndicator { running: root.isBusy || root.connectionState === "connecting"; visible: running; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small }
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
            visible: !root.isConfigured
            icon.name: "configure"
            text: i18n("Connect a time tracker")
            explanation: i18n("Add your service, server URL (if needed), and API token to start tracking.")
            helpfulAction: Kirigami.Action { text: i18n("Configure Plasmai"); onTriggered: pageStack.push(connectionComponent) }
        }
        Kirigami.InlineMessage {
            KanteMessageSkin { message: parent }
            Layout.fillWidth: true
            visible: root.isConfigured && root.connectionState === "error"
            type: Kirigami.MessageType.Error
            text: root.errorMessage.length > 0 ? root.errorMessage : i18n("Connection problem")
            actions: [
                Kirigami.Action { text: i18n("Retry"); icon.name: "view-refresh"; onTriggered: root.refreshAll() },
                Kirigami.Action { text: i18n("Configure"); icon.name: "configure"; onTriggered: pageStack.push(connectionComponent) }
            ]
        }
    }

    // ══════ MAIN CONTENT — one shared column below the threshold, a fixed timer pane next
    // to an independently scrolling list pane above it. heroCard/listSection below are moved
    // between these hosts via their `parent:` binding rather than duplicated, so ids like
    // activeEditView and descField keep working from page-level code no matter which layout
    // is active. ══════
    Item {
        id: contentArea
        anchors.top: topBar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom

        QQC2.ScrollView {
            id: narrowScroll
            anchors.fill: parent
            visible: !page.isWideLayout
            Material.theme: Material.Dark
            contentWidth: availableWidth
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            ColumnLayout {
                id: narrowCol
                width: narrowScroll.availableWidth
                spacing: Kirigami.Units.smallSpacing
            }
        }

        RowLayout {
            id: wideRow
            anchors.fill: parent
            visible: page.isWideLayout
            spacing: Kirigami.Units.largeSpacing

            QQC2.ScrollView {
                id: wideLeftScroll
                Layout.preferredWidth: Math.round(contentArea.width * 0.4)
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                Layout.fillHeight: true
                Material.theme: Material.Dark
                contentWidth: availableWidth
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    id: wideLeftCol
                    width: wideLeftScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing
                }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            QQC2.ScrollView {
                id: wideRightScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                Material.theme: Material.Dark
                contentWidth: availableWidth
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    id: wideRightCol
                    width: wideRightScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing
                }
            }
        }
    }

    // ══════ TIMER CARD — stacked first in narrowCol, or pinned in wideLeftCol ══════
    Rectangle {
        id: heroCard
        Layout.fillWidth: true; Layout.topMargin: root.isConfigured ? Kirigami.Units.smallSpacing : 0
        visible: root.isConfigured
                Material.theme: Material.Dark
                radius: KanteStyle.active ? 0 : Kirigami.Units.smallSpacing
                implicitHeight: heroCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                color: KanteStyle.active ? "transparent"
                       : (root.isTracking ? Qt.alpha(KanteStyle.positiveTextColor, 0.08) : Qt.alpha(KanteStyle.textColor, 0.05))
                border.width: KanteStyle.active ? 0 : (root.isTracking ? 2 : 1)
                border.color: root.isTracking ? Qt.alpha(KanteStyle.positiveTextColor, 0.35) : Qt.alpha(KanteStyle.textColor, 0.14)

                KanteCard {
                    anchors.fill: parent
                    visible: KanteStyle.active
                    barColor: root.isTracking ? KanteStyle.accentColor : KanteStyle.frameColor
                }

                ColumnLayout { id: heroCol; anchors.fill: parent; anchors.margins: Kirigami.Units.largeSpacing; spacing: Kirigami.Units.smallSpacing

                    // Kante: "Running since 07:42" / "Not tracking" above the timer, with the
                    // trip and edit buttons, so the clock keeps the full width on phones.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: KanteStyle.active
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Label {
                            Layout.fillWidth: true
                            readonly property string beginClock: {
                                var ts = root.activeTimesheet
                                var d = ts && ts.begin ? new Date(ts.begin) : null
                                return d && !isNaN(d.getTime()) ? DTF.formatLocaleTime(d.getHours(), d.getMinutes()) : ""
                            }
                            text: root.isTracking
                                  ? (beginClock.length > 0 ? i18n("Running since %1", beginClock) : i18n("Running"))
                                  : i18n("Not tracking")
                            font: KanteStyle.labelFont()
                            color: KanteStyle.mutedTextColor
                            elide: Text.ElideRight
                        }
                        KanteToolButton {
                            visible: root.isTracking && root.canEditTrips && !!root.activeTimesheet
                            icon.name: "mark-location"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Log trip")
                            onClicked: root.openTripForTimesheet(root.activeTimesheet)
                        }
                        KanteToolButton {
                            visible: root.isTracking
                            icon.name: "document-edit"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Edit")
                            onClicked: page.openEdit()
                        }
                    }

                    RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            text: KimaiApi.formatDuration(root.elapsedSeconds)
                            font: KanteStyle.active ? KanteStyle.monoFont(KanteStyle.defaultFont.pointSize * 2.4, true)
                                              : Qt.font({ family: KanteStyle.monoFamily, pointSize: KanteStyle.defaultFont.pointSize + 12, bold: true })
                            color: !KanteStyle.active ? KanteStyle.positiveTextColor
                                   : (root.isTracking ? KanteStyle.accentTextColor : KanteStyle.tint(KanteStyle.textColor, 0.3))
                            // Kante: the big mono clock shrinks to the width left next to the buttons (phones).
                            Layout.minimumWidth: KanteStyle.active ? 0 : implicitWidth
                            Layout.fillWidth: KanteStyle.active
                            fontSizeMode: KanteStyle.active ? Text.HorizontalFit : Text.FixedSize
                            minimumPointSize: KanteStyle.defaultFont.pointSize * 1.4
                        }
                        Item { Layout.fillWidth: !KanteStyle.active }
                        KanteToolButton {
                            visible: !KanteStyle.active && root.isTracking && root.canEditTrips && !!root.activeTimesheet
                            icon.name: "mark-location"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Log trip")
                            onClicked: root.openTripForTimesheet(root.activeTimesheet)
                            QQC2.ToolTip.text: i18n("Log a trip for this entry"); QQC2.ToolTip.visible: hovered && !Kirigami.Settings.isMobile; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        KanteToolButton {
                            visible: !KanteStyle.active && root.isTracking
                            icon.name: "document-edit"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Edit")
                            onClicked: page.openEdit()
                            QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered && !Kirigami.Settings.isMobile; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        KanteButton {
                            Material.theme: Material.Dark
                            Material.background: Qt.lighter(KanteStyle.backgroundColor, 1.7)
                            Material.foreground: KanteStyle.textColor
                            emphasis: KanteButton.Emphasis.Destructive
                            visible: root.isTracking
                            text: i18n("Stop")
                            icon.name: "media-playback-stop"
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            onClicked: root.confirmBeforeStop ? confirmDialog.open() : root.stopTracking()
                        }
                    }

                    KanteDayStrip {
                        Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: KanteStyle.active && root.isConfigured && !page.editingActive && root.showSparkline
                        entries: root.todayTimesheets
                        customersById: root.customersById
                        workDayBegin: root.workDayBegin; workDayEnd: root.workDayEnd
                        nowTick: root.sparklineNowTick
                    }

                    DaySparkline {
                        Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: !KanteStyle.active && root.isConfigured && !page.editingActive && root.showSparkline
                        entries: root.todayTimesheets
                        targetSeconds: root.todayTargetSeconds
                        workDayBegin: root.workDayBegin; workDayEnd: root.workDayEnd
                        latitude: root.latitude; longitude: root.longitude
                        nowTick: root.sparklineNowTick
                        showArcs: root.showSparklineArcs
                        flyoutOpen: page.visible
                    }

                    // Kante: activity as the heading, project and customer below.
                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: KanteStyle.active && root.isTracking && !page.editingActive
                        text: root.currentActivity || ""
                        font: KanteStyle.headingFont(KanteStyle.defaultFont.pointSize * 1.3)
                        color: KanteStyle.strongTextColor
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: KanteStyle.active && root.isTracking && !page.editingActive
                        text: root.currentCustomer.length > 0 ? (root.currentProject || "") + " · " + root.currentCustomer : (root.currentProject || "")
                        color: KanteStyle.mutedTextColor
                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: !KanteStyle.active && root.isTracking && !page.editingActive && root.currentCustomer.length > 0
                        text: root.currentCustomer || ""; color: Qt.alpha(KanteStyle.textColor, 0.7)
                        elide: Text.ElideRight; maximumLineCount: 1
                    }

                    RowLayout { visible: !KanteStyle.active && root.isTracking && !page.editingActive; Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                        CustomerColorDot { customerColor: root.currentCustomerColor; sizeFactor: 0.9 }
                        QQC2.Label { text: root.currentProject || ""; color: KanteStyle.textColor; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.Label { text: "·"; color: KanteStyle.disabledTextColor; Layout.preferredWidth: 12 }
                        QQC2.Label { text: root.currentActivity || ""; color: Qt.alpha(KanteStyle.textColor, 0.7); elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                    }

                    ActiveEditView {
                        id: activeEditView
                        visible: page.editingActive
                        Layout.fillWidth: true
                        elapsedSeconds: root.elapsedSeconds
                        projectPickerModel: root.projectPickerModel
                        activityPickerModel: page.editActivityPickerModel
                        busy: root.isBusy
                        configured: root.isConfigured
                        connectionOk: root.connectionState !== "error"
                        supportsBillableEdit: root.providerCapabilities.billableEdit
                        supportsTags: root.providerCapabilities.tags
                        showCreateActions: root.providerCapabilities.createEntities
                        tagLookupUrl: root.tagLookupUrl
                        tagLookupToken: root.apiToken
                        // Recent is deduped per project/activity, so it can hide the latest stopped entry; the Plasmoid scans today too.
                        previousTimesheet: TimesheetFields.previousStoppedTimesheet(root.recentTimesheets, root.todayTimesheets, root.activeTimesheet)
                        overlapGuardEnabled: root.confirmStartBeforePreviousEnd
                        onProjectChosen: function(projectId) {
                            root.loadActivitiesForProject(projectId, function(model) { page.editActivityPickerModel = model })
                        }
                        onSaveRequested: function(projectId, activityId, beginText, billable, tags) {
                            root.patchActiveEntry({ project: projectId, activity: activityId, begin: beginText, billable: billable, tags: tags })
                            page.editingActive = false
                        }
                        onCancelled: page.editingActive = false
                        onCreateProjectRequested: { createEntityDialog.customers = root.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
                        onCreateActivityRequested: {
                            createEntityDialog.selectedProjectId = activeEditView.projectCombo.currentItem ? activeEditView.projectCombo.currentItem.value.id : null
                            createEntityDialog.selectedProjectName = activeEditView.projectCombo.currentItem ? activeEditView.projectCombo.currentItem.value.name : ""
                            createEntityDialog.resetForMode("activity"); createEntityDialog.open()
                        }
                    }

                    // Kante: today · week · what is left of the week, in monospace.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: KanteStyle.active && !page.editingActive
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label { text: i18n("Today %1", DTF.hoursMinutes(root.todayLiveSeconds)); font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false); color: KanteStyle.mutedTextColor }
                        QQC2.Label { text: i18n("Week %1", DTF.hoursMinutes(root.weekLiveSeconds)); font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false); color: KanteStyle.mutedTextColor }
                        Item { Layout.fillWidth: true }
                        QQC2.Label {
                            visible: root.hasWorkContract && root.weekTargetSeconds > 0
                            text: root.remainingWeekSeconds >= 0
                                  ? i18n("%1 left", DTF.hoursMinutes(root.remainingWeekSeconds))
                                  : i18n("%1 over", DTF.hoursMinutes(-root.remainingWeekSeconds))
                            font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, true)
                            color: root.remainingWeekSeconds >= 0 ? KanteStyle.positiveTextColor : KanteStyle.neutralTextColor
                        }
                    }

                    ColumnLayout { Layout.fillWidth: true; spacing: 0; visible: !KanteStyle.active && !page.editingActive
                        QQC2.Label { text: page.workSummaryText(); color: Qt.alpha(KanteStyle.textColor, 0.7); Layout.fillWidth: true; elide: Text.ElideRight }
                        QQC2.Label {
                            visible: root.hasWorkContract
                            Layout.fillWidth: true
                            text: page.remainingText()
                            color: page.isOverTime() ? KanteStyle.neutralTextColor : Qt.alpha(KanteStyle.textColor, 0.7)
                            font.bold: page.isOverTime()
                            elide: Text.ElideRight
                        }
                    }
                    // ══════ DESCRIPTION FIELD ══════
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: descField.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: KanteStyle.active ? 0 : Kirigami.Units.smallSpacing
                        color: KanteStyle.active ? "transparent" : KanteStyle.backgroundColor
                        border.width: KanteStyle.active ? 0 : 1
                        border.color: descField.activeFocus ? KanteStyle.positiveTextColor : Qt.alpha(KanteStyle.textColor, 0.14)
                        visible: root.isTracking && !page.editingActive
                        KanteTextField {
                            id: descField; anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing
                            rightPadding: descSaveButton.visible ? descSaveButton.width + Kirigami.Units.smallSpacing * 2 : leftPadding
                            text: root.isTracking ? root.descriptionDraft : ""
                            // Not placeholderText: Material's TextField floats that text above
                            // the value once it has ever had content or focus, and — because
                            // that float is driven by internal C++ state rather than a live
                            // QML binding — it keeps showing the stale placeholder even after
                            // this expression re-evaluates to "". A plain overlay Label avoids
                            // that entirely.
                            placeholderText: ""
                            background: Item {}
                            onTextEdited: root.saveDescription(text)
                            onEditingFinished: root.saveDescription(text)
                        }
                        QQC2.Label {
                            text: i18n("Description…")
                            visible: descField.length === 0
                            color: Qt.alpha(KanteStyle.textColor, 0.55)
                            anchors.left: descField.left; anchors.leftMargin: descField.leftPadding
                            anchors.verticalCenter: descField.verticalCenter
                        }
                        KanteToolButton {
                            id: descSaveButton
                            anchors.right: parent.right; anchors.rightMargin: Kirigami.Units.smallSpacing / 2
                            anchors.verticalCenter: descField.verticalCenter
                            display: QQC2.AbstractButton.IconOnly
                            icon.name: root.descriptionSavedFlash ? "dialog-ok-apply"
                                       : (root.savingDescription ? "view-refresh" : "document-save")
                            icon.color: root.descriptionSavedFlash ? KanteStyle.positiveTextColor : KanteStyle.textColor
                            text: i18n("Save description")
                            visible: root.descriptionSavedFlash || root.savingDescription
                                     || root.descriptionDraft !== root.currentDescription
                            enabled: root.descriptionDraft !== root.currentDescription
                                     && !root.savingDescription && !root.descriptionSavedFlash
                            onClicked: root.saveCurrentDescription()
                            QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered && !Kirigami.Settings.isMobile; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }

                    // ══════ NOT TRACKING PLACEHOLDER ══════
                    QQC2.Label {
                        Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
                        visible: root.isConfigured && !root.isTracking
                        text: root.pinnedEntries.length > 0 ? i18n("No activity. Tap a favorite to start.") : i18n("No activity.")
                        color: KanteStyle.disabledTextColor; wrapMode: Text.WordWrap
                    }

                    // ══════ CONTINUE BUTTON ══════
                    KanteButton {
                        emphasis: KanteButton.Emphasis.Primary
                    Material.theme: Material.Dark
                    Material.background: Qt.lighter(KanteStyle.backgroundColor, 1.7)
                    Material.foreground: KanteStyle.textColor
                        Layout.fillWidth: true
                        visible: !root.isTracking && root.isConfigured && root.showContinue && (root.lastRecent || root.hasLastUsed)
                        enabled: !root.isBusy && root.connectionState !== "error"
                        icon.name: "media-playback-start"
                        text: root.lastRecent
                              ? i18n("Continue · %1 · %2", KimaiApi.displayProjectName(root.lastRecent, root.projects), KimaiApi.displayActivityName(root.lastRecent, root.allActivities, root.activitiesByProject))
                              : i18n("Start · %1 · %2", root.lastUsedProjectName, root.lastUsedActivityName)
                        onClicked: root.lastRecent ? root.continueRecent(root.lastRecent) : root.startLastUsed()
                    }

                }
            }

    // ══════ FAVORITES / RECENT / NEW ACTIVITY — stacked after the timer card in narrowCol,
    // or pinned in wideRightCol as its own independently scrolling pane ══════
    ColumnLayout {
        id: listSection
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        // ══════ FAVORITES ══════
        KanteHeading {
            Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
            level: 4; text: i18n("Favorites")
            visible: root.showFavorites && root.pinnedEntries.length > 0
        }
        GridLayout {
            Layout.fillWidth: true
            columns: KanteStyle.active && width >= Kirigami.Units.gridUnit * 16 ? 2 : 1
            rowSpacing: KanteStyle.active ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
            columnSpacing: Kirigami.Units.smallSpacing
            Repeater {
                model: root.showFavorites ? root.pinnedEntries : []
                delegate: ActivityListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    presentation: ActivityListRow.Presentation.Tile
                    property string pinKey: root.switchHintKey({ project: modelData.projectId, activity: modelData.activityId })
                    titleText: modelData.activityName || ""
                    subtitleText: modelData.projectName || ""
                    customerColor: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    showHistoryActions: true
                    canPin: true; isPinned: true
                    runningHintVisible: root.alreadyRunningHintKey === pinKey
                    runningHintText: i18n("Already running.")
                    runningHintCounterText: KimaiApi.formatDurationShort(root.elapsedSeconds)
                    onRowActivated: root.startPinned(modelData)
                    onPinRequested: root.togglePin(modelData.projectId || "", modelData.activityId || "")
                }
            }
        }
        QQC2.Label {
            Layout.fillWidth: true; visible: root.isConfigured && root.showFavorites && root.pinnedEntries.length === 0
            text: i18n("Pin an entry from Recent to add it to your favorites.")
            color: KanteStyle.disabledTextColor; wrapMode: Text.WordWrap
        }

        // ══════ RECENT ══════
        KanteHeading {
            Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
            level: 4; text: i18n("Recent")
            visible: root.showRecent && root.recentTimesheets.length > 0
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: root.showRecent ? root.recentTimesheets : []
                delegate: ActivityListRow {
                    required property var modelData
                    property string tsKey: root.switchHintKey(modelData)
                    readonly property var barColorInfo: KimaiApi.barColorInfoFromTimesheet(modelData, root.customersById)
                    titleText: KimaiApi.displayActivityName(modelData, root.allActivities, root.activitiesByProject)
                    timeText: DTF.entryTimeLabel(modelData.begin, modelData.end, new Date(), i18n("now"))
                    durationText: (modelData.duration || 0) > 0 ? DTF.hoursMinutes(modelData.duration) : ""
                    subtitleText: {
                        // Kante: time and duration have their own columns in the time line.
                        if (KanteStyle.active) return KimaiApi.displayProjectName(modelData, root.projects)
                        var bits = [KimaiApi.displayProjectName(modelData, root.projects)]
                        var secs = modelData.duration || 0
                        if (secs > 0) bits.push(KimaiApi.formatDurationShort(secs))
                        bits.push(root.formatRelativeTime(modelData.end || modelData.begin))
                        return bits.join(" · ")
                    }
                    customerColor: barColorInfo.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    showHistoryActions: true
                    canPin: true; isPinned: root.isPinned(KimaiApi.projectId(modelData), KimaiApi.activityId(modelData))
                    canEditStopped: root.providerCapabilities.editStopped
                    canSplitEntry: root.providerCapabilities.editStopped
                    canDeleteEntry: root.providerCapabilities.deleteEntry
                    canLogTrip: root.canEditTrips
                    onTripRequested: root.openTripForTimesheet(modelData)
                    runningHintVisible: root.alreadyRunningHintKey === tsKey
                    runningHintText: i18n("Already running.")
                    runningHintCounterText: KimaiApi.formatDurationShort(root.elapsedSeconds)
                    onRowActivated: root.requestRestartFromRecent(modelData)
                    onPinRequested: root.togglePin(KimaiApi.projectId(modelData), KimaiApi.activityId(modelData))
                    onEditRequested: pageStack.push(manualPageComponent, { editTs: modelData })
                    onDeleteRequested: { deleteDialog.target = modelData; deleteDialog.open() }
                    onSplitRequested: { splitDialog.target = modelData; splitDialog.open() }
                }
            }
        }

        // ══════ NEW / SWITCH ACTIVITY ══════
        KanteButton {
            Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
            visible: root.isConfigured && root.showNewActivity && !page.showNewActivityForm
            text: root.isTracking ? i18n("Switch to another activity…") : i18n("Start something else…")
            icon.name: "media-skip-forward"
            onClicked: page.openNewActivityForm()
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            visible: root.showNewActivity && page.showNewActivityForm

            ProjectActivityPickers {
                id: newActivityPickers
                Layout.fillWidth: true
                projectPickerModel: root.projectPickerModel
                activityPickerModel: page.newActivityPickerModel
                showCreateActions: root.providerCapabilities.createEntities
                onProjectActivated: function(index) {
                    var projectId = index >= 0 ? root.projectPickerModel[index].value.id : null
                    root.loadActivitiesForProject(projectId, function(model) { page.newActivityPickerModel = model })
                }
                onCreateProjectRequested: { createEntityDialog.customers = root.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
                onCreateActivityRequested: {
                    createEntityDialog.selectedProjectId = newActivityPickers.projectCombo.currentItem ? newActivityPickers.projectCombo.currentItem.value.id : null
                    createEntityDialog.selectedProjectName = newActivityPickers.projectCombo.currentItem ? newActivityPickers.projectCombo.currentItem.value.name : ""
                    createEntityDialog.resetForMode("activity"); createEntityDialog.open()
                }
            }
            KanteTextField {
                Layout.fillWidth: true
                placeholderText: i18n("Description (optional)")
                text: page.newActivityDescription
                onEditingFinished: page.newActivityDescription = text
            }
            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                KanteButton {
                    Layout.fillWidth: true
                    text: root.isTracking ? i18n("Switch") : i18n("Start")
                    icon.name: root.isTracking ? "media-skip-forward" : "media-playback-start"
                    enabled: !root.isBusy && newActivityPickers.projectCombo.currentIndex >= 0 && newActivityPickers.activityCombo.currentIndex >= 0
                    onClicked: {
                        var proj = newActivityPickers.projectCombo.currentItem.value
                        var act = newActivityPickers.activityCombo.currentItem.value
                        root.switchToActivity(proj.id, act.id, proj.name, act.name || "", page.newActivityDescription)
                        page.showNewActivityForm = false
                    }
                }
                KanteButton { text: i18n("Cancel"); onClicked: page.showNewActivityForm = false }
            }
        }

        // ══════ BOTTOM SPACER ══════
        Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing + (Qt.inputMethod.visible ? Kirigami.Units.gridUnit * 14 : 0) }
    }

    // ══════ DIALOGS ══════
    Kirigami.PromptDialog {
        id: confirmDialog
        KanteDialogSkin { dialog: confirmDialog }
        title: i18n("Stop tracking?")
        subtitle: i18n("Stop %1 · %2?", root.currentProject, root.currentActivity)
        // Own footer actions: Qt's standard button texts stay English on Android.
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action { text: i18n("Stop"); icon.name: "dialog-ok"; onTriggered: confirmDialog.accept() },
            Kirigami.Action { text: i18n("Cancel"); icon.name: "dialog-cancel"; onTriggered: confirmDialog.reject() }
        ]
        onAccepted: root.stopTracking()
    }
    Kirigami.PromptDialog {
        id: deleteDialog
        KanteDialogSkin { dialog: deleteDialog }
        property var target: null
        title: i18n("Delete entry?")
        subtitle: i18n("Really delete this entry?")
        // Own footer actions: Qt's standard button texts stay English on Android.
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action { text: i18n("Delete"); icon.name: "dialog-ok"; onTriggered: deleteDialog.accept() },
            Kirigami.Action { text: i18n("Cancel"); icon.name: "dialog-cancel"; onTriggered: deleteDialog.reject() }
        ]
        onAccepted: { if (target) root.deleteEntry(target); target = null }
    }
    Kirigami.PromptDialog {
        id: switchDialog
        KanteDialogSkin { dialog: switchDialog }
        title: i18n("Switch activity")
        subtitle: root.pendingSwitchTimesheet ? i18n("Switch to %1 · %2?", KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.projects), KimaiApi.displayActivityName(root.pendingSwitchTimesheet, root.allActivities, root.activitiesByProject)) : ""
        // Own footer actions: Qt's standard button texts stay English on Android.
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action { text: i18n("Switch"); icon.name: "dialog-ok"; onTriggered: switchDialog.accept() },
            Kirigami.Action { text: i18n("Cancel"); icon.name: "dialog-cancel"; onTriggered: switchDialog.reject() }
        ]
        onAccepted: {
            var ts = root.pendingSwitchTimesheet; root.pendingSwitchTimesheet = null
            if (ts) root.switchToActivity(KimaiApi.projectId(ts), KimaiApi.activityId(ts), KimaiApi.displayProjectName(ts, root.projects), KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject), ts.description || "")
        }
        onRejected: root.pendingSwitchTimesheet = null
    }
    Kirigami.Dialog {
        id: splitDialog
        KanteDialogSkin { dialog: splitDialog }
        property var target: null
        title: i18n("Split entry")
        // Own footer actions: Qt's standard button texts stay English on Android.
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action { text: i18n("Split entry"); icon.name: "dialog-ok"; onTriggered: splitDialog.accept() },
            Kirigami.Action { text: i18n("Cancel"); icon.name: "dialog-cancel"; onTriggered: splitDialog.reject() }
        ]
        padding: Kirigami.Units.largeSpacing
        onAboutToShow: {
            if (!target) return
            var begin = new Date(target.begin); var end = target.end ? new Date(target.end) : new Date()
            var mid = new Date(begin.getTime() + (end.getTime() - begin.getTime()) / 2)
            splitDate.setDate(mid); splitTime.setTime(mid.getHours(), mid.getMinutes())
        }
        ColumnLayout { spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Split at:"); Layout.fillWidth: true }
            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                DateField { id: splitDate; Layout.fillWidth: true }
                TimeField { id: splitTime; Layout.fillWidth: true }
            }
        }
        onAccepted: {
            if (!target) return
            var d = new Date(splitDate.selectedDate)
            d.setHours(splitTime.hours, splitTime.minutes, 0, 0)
            root.splitEntry(target, d)
            target = null
        }
    }
    CreateEntityDialog {
        id: createEntityDialog
        onSubmitted: function(mode, payload) {
            if (mode === "customer") root.createCustomer(payload)
            else if (mode === "project") root.createProject(payload)
            else if (mode === "activity") root.createActivity(payload)
        }
    }

    Kirigami.Dialog {
        id: idleDialog
        KanteDialogSkin { dialog: idleDialog }
        title: i18n("You were idle")
        standardButtons: Kirigami.Dialog.NoButton
        padding: Kirigami.Units.largeSpacing
        closePolicy: Kirigami.Dialog.NoAutoClose
        visible: root.idleDialogPending

        ColumnLayout { spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: i18n("You were idle for %1. Keep this time, discard it, or discard and continue?", KimaiApi.formatDurationShort(Math.round(root.pendingIdleMs / 1000)))
            }
            KanteButton { Layout.fillWidth: true; text: i18n("Keep time"); onClicked: root.keepIdleTime() }
            KanteButton { Layout.fillWidth: true; text: i18n("Discard idle"); onClicked: root.discardIdleTime(false) }
            KanteButton { Layout.fillWidth: true; text: i18n("Discard and continue"); onClicked: root.discardIdleTime(true) }
        }
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: narrowScroll
        anchors.fill: parent
        z: 10
        flickable: narrowScroll.contentItem
        busy: root.isBusy
        onRefreshRequested: root.refreshAll()
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: wideLeftScroll
        anchors.fill: parent
        z: 10
        flickable: wideLeftScroll.contentItem
        busy: root.isBusy
        onRefreshRequested: root.refreshAll()
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: wideRightScroll
        anchors.fill: parent
        z: 10
        flickable: wideRightScroll.contentItem
        busy: root.isBusy
        onRefreshRequested: root.refreshAll()
    }
}
