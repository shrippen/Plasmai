import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/profiles.js" as Profiles
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
    KantePageTitle { page: page }
    title: page.editMode ? i18n("Edit entry") : i18n("Add entry")

    property bool busy: false
    property var editTs: null
    readonly property bool editMode: editTs !== null
    property var activityPickerModel: []

    function doSave(projectId, activityId, beginText, endText, description, billable, tags) {
        page.busy = true
        const fields = { project: projectId, activity: activityId, begin: beginText, end: endText, description: description, tags: tags }
        if (billable !== undefined && billable !== null) {
            fields.billable = billable
        }
        // The session refreshes right away: otherwise Recent and the totals stay stale until the next poll.
        session.entries.write(page.editMode && page.editTs ? page.editTs.id : null, fields, function(r) {
            page.busy = false
            if (r.ok) {
                pageStack.pop()
            }
        })
    }

    Component.onCompleted: {
        if (editTs) {
            var pid = KimaiApi.projectId(editTs)
            session.catalog.loadActivities(pid, function(model) {
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
        // The scroll bar sits at the screen edge; the content keeps the page margin.
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: formCol
            width: (pageScroll.availableWidth - page.rightPadding)
            spacing: Kirigami.Units.smallSpacing

            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                // Same rule as the timer page: only with several profiles or a problem.
                visible: Profiles.showsConnection(session.connection.profiles, session.connection.configured, session.connection.state)
                Kirigami.Icon {
                    source: !session.connection.configured ? "network-disconnect" : session.connection.state === "error" ? "network-disconnect" : "network-connect"
                    color: !session.connection.configured ? KanteStyle.disabledTextColor : session.connection.state === "error" ? KanteStyle.negativeTextColor : KanteStyle.positiveTextColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                QQC2.Label {
                    text: session.connection.profile ? (session.connection.profile.url || session.connection.profile.provider || "") : ""
                    color: Qt.alpha(KanteStyle.textColor, 0.7); elide: Text.ElideRight; Layout.fillWidth: true
                }
            }

            ManualEntryView {
                id: manualEntryView
                Layout.fillWidth: true
                projectPickerModel: session.catalog.projectPickerModel
                activityPickerModel: page.activityPickerModel
                busy: page.busy
                configured: session.connection.configured
                connectionOk: session.connection.state !== "error"
                editingExisting: page.editMode
                supportsBillableEdit: session.connection.capabilities.billableEdit
                supportsTags: session.connection.capabilities.tags
                showCreateActions: session.entries.canCreate
                tagSource: session.entries
                onProjectChosen: function(projectId) {
                    session.catalog.loadActivities(projectId, function(model) { page.activityPickerModel = model })
                }
                onSaveRequested: function(projectId, activityId, beginText, endText, description, billable, tags) {
                    page.doSave(projectId, activityId, beginText, endText, description, billable, tags)
                }
                onCancelled: pageStack.pop()
                onCreateProjectRequested: { createEntityDialog.customers = session.catalog.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
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
            session.entries.createEntity(mode, payload)
        }
    }

}
