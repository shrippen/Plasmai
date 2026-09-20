import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"

Kirigami.Page {
    id: page; title: ""
    padding: 0
    background: Rectangle { color: root.bgWindow }

    property bool editingActive: false
    property var editActivityPickerModel: []
    property bool showNewActivityForm: false
    property var newActivityPickerModel: []
    property string newActivityDescription: ""

    function connIcon() { return !root.isConfigured ? "network-disconnect" : root.connectionState === "error" ? "network-disconnect" : root.connectionState === "connecting" ? "view-refresh" : "network-connect" }
    function connColor() { return !root.isConfigured ? root.clrTextMuted : root.connectionState === "error" ? root.clrDanger : root.clrPositive }
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

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
        clip: true
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: col; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Kirigami.Units.largeSpacing; spacing: Kirigami.Units.smallSpacing

            // ══════ HEADER ══════
            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading { level: 1; text: i18n("Plasmai"); Layout.fillWidth: true }
                QQC2.ToolButton {
                    visible: root.isConfigured
                    icon.name: "list-add"
                    text: i18n("Add entry")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: pageStack.push(manualPageComponent)
                    QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                QQC2.ToolButton {
                    visible: root.isConfigured
                    icon.name: "view-statistics"
                    text: i18n("Statistics")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: pageStack.push(statsPageComponent)
                    QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

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
                    color: root.clrTextSec; font.pointSize: Kirigami.Theme.smallFont.pointSize; elide: Text.ElideRight
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
                radius: Kirigami.Units.smallSpacing
                height: heroCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                color: root.isTracking ? root.bgCardTracking : root.bgCard
                border.width: root.isTracking ? 2 : 1
                border.color: root.isTracking ? root.clrBorderTracking : root.clrBorder

                ColumnLayout { id: heroCol; anchors.fill: parent; anchors.margins: Kirigami.Units.largeSpacing; spacing: Kirigami.Units.smallSpacing

                    RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            text: KimaiApi.formatDuration(root.elapsedSeconds)
                            font.family: "monospace"; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 12; font.bold: true
                            color: root.clrAccent
                            Layout.fillWidth: true
                        }
                        QQC2.Label { text: root.currentCustomer || ""; color: root.clrTextSec; visible: root.isTracking && root.currentCustomer.length > 0 }
                        QQC2.Button {
                            visible: root.isTracking
                            text: i18n("Stop")
                            icon.name: "media-playback-stop"
                            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                            onClicked: root.confirmBeforeStop ? confirmDialog.open() : root.stopTracking()
                        }
                    }

                    RowLayout { visible: root.isTracking; Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                        CustomerColorDot { customerColor: root.currentCustomerColor; colorCategory: root.currentColorCategory; entityId: root.currentColorEntityId; sizeFactor: 0.9 }
                        QQC2.Label { text: root.currentProject || ""; color: root.clrText; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.Label { text: "·"; color: root.clrTextMuted; Layout.preferredWidth: 12 }
                        QQC2.Label { text: root.currentActivity || ""; color: root.clrTextSec; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.ToolButton {
                            icon.name: "document-edit"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Edit")
                            onClicked: page.openEdit()
                            QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
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

                    RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.largeSpacing; visible: !page.editingActive
                        QQC2.Label { text: page.workSummaryText(); color: root.clrTextSec; Layout.fillWidth: true }
                        QQC2.Label {
                            visible: root.hasWorkContract
                            text: page.remainingText()
                            color: page.isOverTime() ? root.clrWarning : root.clrTextSec
                            font.bold: page.isOverTime()
                        }
                    }
                }
            }

            // ══════ DESCRIPTION FIELD ══════
            Rectangle {
                Layout.fillWidth: true; height: descField.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.smallSpacing; color: root.bgInput; border.width: 1; border.color: descField.activeFocus ? root.clrAccent : root.clrBorder
                visible: root.isTracking && !page.editingActive
                QQC2.TextField {
                    id: descField; anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing
                    text: root.isTracking ? root.descriptionDraft : ""
                    placeholderText: i18n("Description…")
                    background: Item {}
                    onEditingFinished: root.saveDescription(text)
                }
                Kirigami.Icon {
                    visible: root.descriptionSavedFlash; anchors.centerIn: descField
                    width: Kirigami.Units.iconSizes.small; height: Kirigami.Units.iconSizes.small
                    source: "dialog-ok-apply"; color: root.clrAccent
                }
            }

            // ══════ NOT TRACKING PLACEHOLDER ══════
            Kirigami.PlaceholderMessage {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.isConfigured && !root.isTracking
                icon.name: "chronometer"
                text: root.pinnedEntries.length > 0 ? i18n("No activity. Tap a favorite to start.") : i18n("No activity.")
            }

            // ══════ CONTINUE BUTTON ══════
            QQC2.Button {
                Layout.fillWidth: true
                visible: !root.isTracking && root.isConfigured && root.showContinue && (root.lastRecent || root.hasLastUsed)
                enabled: !root.isBusy && root.connectionState !== "error"
                icon.name: "media-playback-start"
                text: root.lastRecent
                      ? i18n("Continue · %1 · %2", KimaiApi.displayProjectName(root.lastRecent, root.projects), KimaiApi.displayActivityName(root.lastRecent, root.allActivities, root.activitiesByProject))
                      : i18n("Start · %1 · %2", root.lastUsedProjectName, root.lastUsedActivityName)
                onClicked: root.lastRecent ? root.continueRecent(root.lastRecent) : root.startLastUsed()
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
                        property string pinKey: String(modelData.projectId || "") + "|" + String(modelData.activityId || "")
                        titleText: modelData.projectName || ""
                        subtitleText: modelData.activityName || ""
                        customerColor: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                        showHistoryActions: true
                        canPin: true; isPinned: true
                        runningHintVisible: root.alreadyRunningHintKey === pinKey
                        runningHintText: i18n("Already running.")
                        runningHintCounterText: KimaiApi.formatDurationShort(root.elapsedSeconds)
                        onRowActivated: if (root.isConfigured && !root.isBusy) root.requestRestartFromRecent({ project: modelData.projectId, activity: modelData.activityId })
                        onPinRequested: root.togglePin(modelData.projectId || "", modelData.activityId || "")
                    }
                }
            }
            QQC2.Label {
                Layout.fillWidth: true; visible: root.isConfigured && root.showFavorites && root.pinnedEntries.length === 0
                text: i18n("Pin an entry from Recent to add it to your favorites.")
                color: root.clrTextMuted; wrapMode: Text.WordWrap
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
                    canPin: true; isPinned: root.isPinned(modelData.project || "", modelData.activity || "")
                    canEditStopped: root.providerCapabilities.editStopped
                    canSplitEntry: root.providerCapabilities.editStopped
                    canDeleteEntry: root.providerCapabilities.deleteEntry
                    runningHintVisible: root.alreadyRunningHintKey === tsKey
                    runningHintText: i18n("Already running.")
                    runningHintCounterText: KimaiApi.formatDurationShort(root.elapsedSeconds)
                    onRowActivated: root.requestRestartFromRecent(modelData)
                    onPinRequested: root.togglePin(modelData.project || "", modelData.activity || "")
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
            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    } // Flickable

    // ══════ DIALOGS ══════
    QQC2.Dialog {
        id: confirmDialog; title: i18n("Stop tracking?"); modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(Kirigami.Units.gridUnit * 20, parent ? parent.width * 0.9 : 320)
        anchors.centerIn: parent
        contentItem: QQC2.Label { width: confirmDialog.availableWidth; text: i18n("Stop %1 · %2?", root.currentProject, root.currentActivity); wrapMode: Text.WordWrap }
        onAccepted: root.stopTracking()
    }
    QQC2.Dialog {
        id: deleteDialog; property var target: null
        title: i18n("Delete entry?"); modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(Kirigami.Units.gridUnit * 20, parent ? parent.width * 0.9 : 320)
        anchors.centerIn: parent
        contentItem: QQC2.Label { width: deleteDialog.availableWidth; text: i18n("Really delete this entry?"); wrapMode: Text.WordWrap }
        onAccepted: { if (target) root.deleteEntry(target); target = null }
    }
    QQC2.Dialog {
        id: switchDialog; modal: true
        title: i18n("Switch activity")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(Kirigami.Units.gridUnit * 20, parent ? parent.width * 0.9 : 320)
        anchors.centerIn: parent
        contentItem: QQC2.Label {
            width: switchDialog.availableWidth
            text: root.pendingSwitchTimesheet ? i18n("Switch to %1 · %2?", KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.projects), KimaiApi.displayActivityName(root.pendingSwitchTimesheet, root.allActivities, root.activitiesByProject)) : ""
            wrapMode: Text.WordWrap
        }
        onAccepted: {
            var ts = root.pendingSwitchTimesheet; root.pendingSwitchTimesheet = null
            if (ts) root.switchToActivity(KimaiApi.projectId(ts), KimaiApi.activityId(ts), KimaiApi.displayProjectName(ts, root.projects), KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject), ts.description || "")
        }
        onRejected: root.pendingSwitchTimesheet = null
    }
    QQC2.Dialog {
        id: splitDialog; property var target: null
        title: i18n("Split entry"); modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(Kirigami.Units.gridUnit * 20, parent ? parent.width * 0.9 : 320)
        anchors.centerIn: parent
        onAboutToShow: {
            if (!target) return
            var begin = new Date(target.begin); var end = target.end ? new Date(target.end) : new Date()
            var mid = new Date(begin.getTime() + (end.getTime() - begin.getTime()) / 2)
            splitDate.setDate(mid); splitTime.setTime(mid.getHours(), mid.getMinutes())
        }
        contentItem: ColumnLayout { spacing: Kirigami.Units.smallSpacing
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

    QQC2.Dialog {
        id: idleDialog
        title: i18n("You were idle")
        modal: true
        standardButtons: QQC2.Dialog.NoButton
        width: Math.min(Kirigami.Units.gridUnit * 20, parent ? parent.width * 0.9 : 320)
        anchors.centerIn: parent
        closePolicy: QQC2.Popup.NoAutoClose
        visible: root.idleDialogPending

        contentItem: ColumnLayout { spacing: Kirigami.Units.smallSpacing
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
