import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"

Kirigami.Page {
    id: page
    title: ""
    background: Rectangle { color: root.bgWindow }

    property bool busy: false
    property var editTs: null
    readonly property bool editMode: editTs !== null
    property var activityPickerModel: []

    function doSave(projectId, activityId, beginText, endText, description, billable, tags) {
        page.busy = true
        var url = TimeTracker.resolveUrl(root.activeProfile)
        var fields = { project: projectId, activity: activityId, begin: beginText, end: endText, description: description, tags: tags }
        if (billable !== undefined && billable !== null) fields.billable = billable
        var cb = function(r) { page.busy = false; if (r.ok) pageStack.pop() }
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
            Qt.callLater(function() { page.ensureFocusedVisible() })
        }
    }

    function ensureFocusedVisible() {
        var fi = root.activeFocusItem
        if (!fi || !flickable) return
        var kb = Qt.inputMethod.keyboardRectangle
        var kbHeight = kb ? kb.height : 0
        if (kbHeight <= 0) return
        var pos = flickable.mapFromItem(fi, 0, 0)
        var itemBottom = pos.y + fi.height + 12
        var visibleBottom = flickable.height - kbHeight
        if (itemBottom > visibleBottom) {
            flickable.contentY += (itemBottom - visibleBottom)
        } else if (pos.y < flickable.contentY) {
            flickable.contentY = pos.y
        }
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: formCol.implicitHeight + Kirigami.Units.largeSpacing * 2
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: formCol
            width: parent.width
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading { level: 1; text: page.editMode ? i18n("Edit entry") : i18n("Add entry") }

            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: !root.isConfigured ? "network-disconnect" : root.connectionState === "error" ? "network-disconnect" : "network-connect"
                    color: !root.isConfigured ? root.clrTextMuted : root.connectionState === "error" ? root.clrDanger : root.clrPositive
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                QQC2.Label {
                    text: root.activeProfile ? (root.activeProfile.url || root.activeProfile.provider || "") : ""
                    color: root.clrTextSec; elide: Text.ElideRight; Layout.fillWidth: true
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
        }
    } // Flickable

    CreateEntityDialog {
        id: createEntityDialog
        onSubmitted: function(mode, payload) {
            if (mode === "customer") root.createCustomer(payload)
            else if (mode === "project") root.createProject(payload)
            else if (mode === "activity") root.createActivity(payload)
        }
    }
}
