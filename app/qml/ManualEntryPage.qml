import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: page.editMode ? i18n("Edit entry") : i18n("Add entry")

    property bool busy: false
    property var editTs: null
    readonly property bool editMode: editTs !== null
    property var activityPickerModel: []

    function doSave(projectId, activityId, beginText, endText, description, billable, tags) {
        page.busy = true
        var url = TimeTracker.resolveUrl(root.activeProfile)
        var fields = { project: projectId, activity: activityId, begin: beginText, end: endText, description: description, tags: tags }
        if (billable !== undefined && billable !== null) fields.billable = billable
        // Refresh right away: otherwise Recent and the totals stay stale until the next poll.
        var cb = function(r) { page.busy = false; if (r.ok) { root.noteDroppedFields(r); root.refreshAll(); pageStack.pop() } }
        if (page.editMode && page.editTs) root.tracker.patchTimesheet(url, root.apiToken, page.editTs.id, fields, cb)
        else root.tracker.createTimesheet(url, root.apiToken, fields, cb)
    }

    Component.onCompleted: {
        if (editTs) {
            var pid = KimaiApi.projectId(editTs)
            root.loadActivitiesForProject(pid, function(model) {
                page.activityPickerModel = model
                manualEntryView.loadFromTimesheet(page.editTs)
            })
        }
    }

    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() {
            keyboardScrollTimer.restart()
        }
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
        var pos = flick.mapFromItem(fi, 0, 0)
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        // pos is relative to the viewport, not to the scrolled content. The window already resizes
        // for the keyboard, so put the field at the top: its suggestion popup gets the whole height below.
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + pos.y - Kirigami.Units.largeSpacing))
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: formCol
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: !root.isConfigured ? "network-disconnect" : root.connectionState === "error" ? "network-disconnect" : "network-connect"
                    color: !root.isConfigured ? KanteStyle.disabledTextColor : root.connectionState === "error" ? KanteStyle.negativeTextColor : KanteStyle.positiveTextColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                QQC2.Label {
                    text: root.activeProfile ? (root.activeProfile.url || root.activeProfile.provider || "") : ""
                    color: Qt.alpha(KanteStyle.textColor, 0.7); elide: Text.ElideRight; Layout.fillWidth: true
                }
            }

            ManualEntryView {
                id: manualEntryView
                Layout.fillWidth: true
                projectPickerModel: root.projectPickerModel
                activityPickerModel: page.activityPickerModel
                busy: page.busy
                configured: root.isConfigured
                connectionOk: root.connectionState !== "error"
                editingExisting: page.editMode
                supportsBillableEdit: root.providerCapabilities.billableEdit
                supportsTags: root.providerCapabilities.tags
                showCreateActions: root.providerCapabilities.createEntities
                tagLookupUrl: root.tagLookupUrl
                tagLookupToken: root.apiToken
                onProjectChosen: function(projectId) {
                    root.loadActivitiesForProject(projectId, function(model) { page.activityPickerModel = model })
                }
                onSaveRequested: function(projectId, activityId, beginText, endText, description, billable, tags) {
                    page.doSave(projectId, activityId, beginText, endText, description, billable, tags)
                }
                onCancelled: pageStack.pop()
                onCreateProjectRequested: { createEntityDialog.customers = root.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
                onCreateActivityRequested: {
                    createEntityDialog.selectedProjectId = manualEntryView.projectCombo.currentItem ? manualEntryView.projectCombo.currentItem.value.id : null
                    createEntityDialog.selectedProjectName = manualEntryView.projectCombo.currentItem ? manualEntryView.projectCombo.currentItem.value.name : ""
                    createEntityDialog.resetForMode("activity"); createEntityDialog.open()
                }
            }

            // Room to scroll the focused field up while the keyboard is visible (suggestion popups need it)
            Item { Layout.fillWidth: true; Layout.preferredHeight: Qt.inputMethod.visible ? Kirigami.Units.gridUnit * 14 : 0 }
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

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: pageScroll
        anchors.fill: parent
        z: 10
        flickable: pageScroll.contentItem
        busy: root.isBusy
        onRefreshRequested: root.refreshAll()
    }
}
