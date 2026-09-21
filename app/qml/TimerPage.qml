import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"

Kirigami.Page {
    id: page
    title: i18n("Plasmai")

    property bool editingActive: false
    property var editActivityPickerModel: []
    property bool showNewActivityForm: false
    property var newActivityPickerModel: []
    property string newActivityDescription: ""

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
        }
    ]

    function connIcon() { return !root.isConfigured ? "network-disconnect" : root.connectionState === "error" ? "network-disconnect" : root.connectionState === "connecting" ? "view-refresh" : "network-connect" }
    function connColor() { return !root.isConfigured ? Kirigami.Theme.disabledTextColor : root.connectionState === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor }
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
        var flick = pageScroll.contentItem
        if (!fi || !flick || Qt.inputMethod.keyboardRectangle.height <= 0) return
        // The window already resizes for the keyboard: bring the focused field to the top of
        // the viewport so its suggestion popup has the whole remaining height below it.
        var pos = flick.mapFromItem(fi, 0, 0)
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        // pos is relative to the viewport, not to the scrolled content
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + pos.y - Kirigami.Units.largeSpacing))
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        Material.theme: Material.Dark
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: col
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing
            // ══════ CONNECTION STATUS ══════
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
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.7); font.pointSize: Kirigami.Theme.smallFont.pointSize; elide: Text.ElideRight
                    Layout.fillWidth: true; maximumLineCount: 1
                }
                QQC2.BusyIndicator { running: root.isBusy || root.connectionState === "connecting"; visible: running; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small }
            }

            // ══════ SETUP / ERROR STATES ══════
            Kirigami.PlaceholderMessage {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
                visible: !root.isConfigured
                icon.name: "configure"
                text: i18n("Connect a time tracker")
                explanation: i18n("Add your service, server URL (if needed), and API token to start tracking.")
                helpfulAction: Kirigami.Action { text: i18n("Configure Plasmai"); onTriggered: pageStack.push(connectionComponent) }
            }
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.isConfigured && root.connectionState === "error"
                type: Kirigami.MessageType.Error
                text: root.errorMessage.length > 0 ? root.errorMessage : i18n("Connection problem")
                actions: [
                    Kirigami.Action { text: i18n("Retry"); icon.name: "view-refresh"; onTriggered: root.refreshAll() },
                    Kirigami.Action { text: i18n("Configure"); icon.name: "configure"; onTriggered: pageStack.push(connectionComponent) }
                ]
            }

            // ══════ TIMER CARD ══════
            Rectangle {
                Layout.fillWidth: true; Layout.topMargin: root.isConfigured ? Kirigami.Units.smallSpacing : 0
                visible: root.isConfigured
                Material.theme: Material.Dark
                radius: Kirigami.Units.smallSpacing
                implicitHeight: heroCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                color: root.isTracking ? Qt.alpha(Kirigami.Theme.positiveTextColor, 0.08) : Qt.alpha(Kirigami.Theme.textColor, 0.05)
                border.width: root.isTracking ? 2 : 1
                border.color: root.isTracking ? Qt.alpha(Kirigami.Theme.positiveTextColor, 0.35) : Qt.alpha(Kirigami.Theme.textColor, 0.14)

                ColumnLayout { id: heroCol; anchors.fill: parent; anchors.margins: Kirigami.Units.largeSpacing; spacing: Kirigami.Units.smallSpacing

                    RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            text: KimaiApi.formatDuration(root.elapsedSeconds)
                            font.family: "monospace"; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 12; font.bold: true
                            color: Kirigami.Theme.positiveTextColor
                            Layout.fillWidth: true
                        }
                        QQC2.Label { text: root.currentCustomer || ""; color: Qt.alpha(Kirigami.Theme.textColor, 0.7); visible: root.isTracking && root.currentCustomer.length > 0 }
                        QQC2.Button {
                            Material.theme: Material.Dark
                            Material.background: Qt.lighter(Kirigami.Theme.backgroundColor, 1.7)
                            Material.foreground: Kirigami.Theme.textColor
                            visible: root.isTracking
                            text: i18n("Stop")
                            icon.name: "media-playback-stop"
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            onClicked: root.confirmBeforeStop ? confirmDialog.open() : root.stopTracking()
                        }
                    }

                    RowLayout { visible: root.isTracking; Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                        CustomerColorDot { customerColor: root.currentCustomerColor; colorCategory: root.currentColorCategory; entityId: root.currentColorEntityId; sizeFactor: 0.9 }
                        QQC2.Label { text: root.currentProject || ""; color: Kirigami.Theme.textColor; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.Label { text: "·"; color: Kirigami.Theme.disabledTextColor; Layout.preferredWidth: 12 }
                        QQC2.Label { text: root.currentActivity || ""; color: Qt.alpha(Kirigami.Theme.textColor, 0.7); elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.ToolButton {
                            icon.name: "document-edit"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Edit")
                            onClicked: page.openEdit()
                            QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered && !Kirigami.Settings.isMobile; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
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
                        previousTimesheet: root.recentTimesheets.length > 0 ? root.recentTimesheets[0] : null
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

                    DaySparkline {
                        Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: root.isConfigured && !page.editingActive && root.showSparkline
                        entries: root.todayTimesheets
                        targetSeconds: root.todayTargetSeconds
                        workDayBegin: root.workDayBegin; workDayEnd: root.workDayEnd
                        latitude: root.latitude; longitude: root.longitude
                        nowTick: root.sparklineNowTick
                        showArcs: root.showSparklineArcs
                        flyoutOpen: page.visible
                    }

                    ColumnLayout { Layout.fillWidth: true; spacing: 0; visible: !page.editingActive
                        QQC2.Label { text: page.workSummaryText(); color: Qt.alpha(Kirigami.Theme.textColor, 0.7); Layout.fillWidth: true; elide: Text.ElideRight }
                        QQC2.Label {
                            visible: root.hasWorkContract
                            Layout.fillWidth: true
                            text: page.remainingText()
                            color: page.isOverTime() ? Kirigami.Theme.neutralTextColor : Qt.alpha(Kirigami.Theme.textColor, 0.7)
                            font.bold: page.isOverTime()
                            elide: Text.ElideRight
                        }
                    }
                    // ══════ DESCRIPTION FIELD ══════
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: descField.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.smallSpacing; color: Kirigami.Theme.backgroundColor; border.width: 1; border.color: descField.activeFocus ? Kirigami.Theme.positiveTextColor : Qt.alpha(Kirigami.Theme.textColor, 0.14)
                        visible: root.isTracking && !page.editingActive
                        QQC2.TextField {
                            id: descField; anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing
                            text: root.isTracking ? root.descriptionDraft : ""
                            placeholderText: i18n("Description…")
                            placeholderTextColor: Qt.alpha(Kirigami.Theme.textColor, 0.55)
                            background: Item {}
                            onEditingFinished: root.saveDescription(text)
                        }
                        Kirigami.Icon {
                            visible: root.descriptionSavedFlash; anchors.centerIn: descField
                            width: Kirigami.Units.iconSizes.small; height: Kirigami.Units.iconSizes.small
                            source: "dialog-ok-apply"; color: Kirigami.Theme.positiveTextColor
                        }
                    }

                    // ══════ NOT TRACKING PLACEHOLDER ══════
                    QQC2.Label {
                        Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
                        visible: root.isConfigured && !root.isTracking
                        text: root.pinnedEntries.length > 0 ? i18n("No activity. Tap a favorite to start.") : i18n("No activity.")
                        color: Kirigami.Theme.disabledTextColor; wrapMode: Text.WordWrap
                    }

                    // ══════ CONTINUE BUTTON ══════
                    QQC2.Button {
                    Material.theme: Material.Dark
                    Material.background: Qt.lighter(Kirigami.Theme.backgroundColor, 1.7)
                    Material.foreground: Kirigami.Theme.textColor
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

            // ══════ FAVORITES ══════
            Kirigami.Heading {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                level: 4; text: i18n("Favorites")
                visible: root.showFavorites && root.pinnedEntries.length > 0
            }
            GridLayout {
                Layout.fillWidth: true
                visible: root.showFavorites && root.pinnedEntries.length > 0
                columns: Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * TouchUi.favoriteCellGu)))
                columnSpacing: Kirigami.Units.smallSpacing; rowSpacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: root.showFavorites ? root.pinnedEntries : []
                    delegate: ActivityListRow {
                        required property var modelData
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
                color: Kirigami.Theme.disabledTextColor; wrapMode: Text.WordWrap
            }

            // ══════ RECENT ══════
            Kirigami.Heading {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                level: 4; text: i18n("Recent")
                visible: root.showRecent && root.recentTimesheets.length > 0
            }
            Repeater {
                model: root.showRecent ? root.recentTimesheets : []
                delegate: ActivityListRow {
                    required property var modelData
                    property string tsKey: root.switchHintKey(modelData)
                    readonly property var barColorInfo: KimaiApi.barColorInfoFromTimesheet(modelData, root.customersById)
                    titleText: KimaiApi.displayActivityName(modelData, root.allActivities, root.activitiesByProject)
                    subtitleText: {
                        var bits = [KimaiApi.displayProjectName(modelData, root.projects)]
                        var secs = modelData.duration || 0
                        if (secs > 0) bits.push(KimaiApi.formatDurationShort(secs))
                        bits.push(root.formatRelativeTime(modelData.end || modelData.begin))
                        return bits.join(" · ")
                    }
                    customerColor: barColorInfo.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    colorCategory: barColorInfo.category || ""
                    entityId: barColorInfo.id
                    showHistoryActions: true
                    canPin: true; isPinned: root.isPinned(KimaiApi.projectId(modelData), KimaiApi.activityId(modelData))
                    canEditStopped: root.providerCapabilities.editStopped
                    canSplitEntry: root.providerCapabilities.editStopped
                    canDeleteEntry: root.providerCapabilities.deleteEntry
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

            // ══════ NEW / SWITCH ACTIVITY ══════
            QQC2.Button {
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
                QQC2.TextField {
                    Layout.fillWidth: true
                    placeholderText: i18n("Description (optional)")
                    text: page.newActivityDescription
                    onEditingFinished: page.newActivityDescription = text
                }
                RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                    QQC2.Button {
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
                    QQC2.Button { text: i18n("Cancel"); onClicked: page.showNewActivityForm = false }
                }
            }

            // ══════ BOTTOM SPACER ══════
            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing + (Qt.inputMethod.visible ? Kirigami.Units.gridUnit * 14 : 0) }
        }
    }

    // ══════ DIALOGS ══════
    Kirigami.PromptDialog {
        id: confirmDialog
        title: i18n("Stop tracking?")
        subtitle: i18n("Stop %1 · %2?", root.currentProject, root.currentActivity)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.stopTracking()
    }
    Kirigami.PromptDialog {
        id: deleteDialog
        property var target: null
        title: i18n("Delete entry?")
        subtitle: i18n("Really delete this entry?")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: { if (target) root.deleteEntry(target); target = null }
    }
    Kirigami.PromptDialog {
        id: switchDialog
        title: i18n("Switch activity")
        subtitle: root.pendingSwitchTimesheet ? i18n("Switch to %1 · %2?", KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.projects), KimaiApi.displayActivityName(root.pendingSwitchTimesheet, root.allActivities, root.activitiesByProject)) : ""
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: {
            var ts = root.pendingSwitchTimesheet; root.pendingSwitchTimesheet = null
            if (ts) root.switchToActivity(KimaiApi.projectId(ts), KimaiApi.activityId(ts), KimaiApi.displayProjectName(ts, root.projects), KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject), ts.description || "")
        }
        onRejected: root.pendingSwitchTimesheet = null
    }
    Kirigami.Dialog {
        id: splitDialog
        property var target: null
        title: i18n("Split entry")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
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
            QQC2.Button { Layout.fillWidth: true; text: i18n("Keep time"); onClicked: root.keepIdleTime() }
            QQC2.Button { Layout.fillWidth: true; text: i18n("Discard idle"); onClicked: root.discardIdleTime(false) }
            QQC2.Button { Layout.fillWidth: true; text: i18n("Discard and continue"); onClicked: root.discardIdleTime(true) }
        }
    }
}
