import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "."
import "Controls" as Controls

/**
 * Shared project + activity picker pair used across the main view, manual entry,
 * and active-entry editor. Keeps popup direction and styling consistent.
 */
ColumnLayout {
    id: root

    property var projectPickerModel: []
    property var activityPickerModel: []
    property var activitySectionTitles: ({})
    property bool pickerOpenBelow: true
    property Item pickerViewport: null
    property bool projectEnabled: true
    property bool activityEnabled: true
    property bool projectVisible: true
    property bool activityVisible: true
    property bool requireProjectSelection: true
    property bool showCreateActions: false

    /** Ids to select once the lists hold them (an entry loads before its lists do). */
    property var pendingProjectId: null
    property var pendingActivityId: null
    readonly property bool hasPendingProject: hasId(pendingProjectId)

    readonly property alias projectCombo: projectPicker
    readonly property alias activityCombo: activityPicker

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectActivated(int index)
    signal pendingProjectSelected(var projectId)
    signal activityActivated(int index)
    signal createProjectRequested()
    signal createActivityRequested()

    spacing: Kirigami.Settings.isMobile ? Kirigami.Units.largeSpacing : 0

    function closePickers() {
        projectPicker.closePopup()
        activityPicker.closePopup()
    }

    function hasId(value) {
        return value !== null && value !== undefined && value !== ""
    }

    // Picks the item whose value.id is `id`; false, selection untouched, if the list lacks it.
    // The index is reset first so a pick of the current item still fires its change.
    function selectId(combo, id) {
        for (let i = 0; i < combo.items.length; i++) {
            const item = combo.items[i]
            if (!item || !item.value || String(item.value.id) !== String(id)) {
                continue
            }
            if (combo.currentIndex === i) {
                combo.currentIndex = -1
            }
            combo.currentIndex = i
            return true
        }
        return false
    }

    // Unlike the activity, a project that is not picked clears the field.
    function selectProjectId(projectId) {
        if (hasId(projectId) && selectId(projectPicker, projectId)) {
            return true
        }
        projectPicker.currentIndex = -1
        return false
    }

    // Remembers both ids and picks what the lists already hold; the rest follows on trySelect*.
    function setPending(projectId, activityId) {
        pendingProjectId = hasId(projectId) ? projectId : null
        pendingActivityId = hasId(activityId) ? activityId : null
        trySelectPendingProject()
        Qt.callLater(trySelectPendingActivity)
    }

    function trySelectPendingProject() {
        if (!hasId(pendingProjectId) || !selectProjectId(pendingProjectId)) {
            return
        }
        const projectId = pendingProjectId
        pendingProjectId = null
        pendingProjectSelected(projectId)
    }

    function trySelectPendingActivity() {
        if (!hasId(pendingActivityId)) {
            return
        }
        if (selectId(activityPicker, pendingActivityId)) {
            pendingActivityId = null
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.projectVisible
        spacing: Kirigami.Units.smallSpacing

        SearchableCombo {
            id: projectPicker
            Layout.fillWidth: true
            enabled: root.projectEnabled
            items: root.projectPickerModel
            placeholderText: i18n("Select project…")
            viewportItem: root.pickerViewport
            useSharedDirection: true
            openBelow: root.pickerOpenBelow
            onAboutToOpen: root.aboutToOpenPicker(projectPicker, activityPicker)
            onActivated: function(index) {
                root.pendingProjectId = null
                root.projectActivated(index)
            }
        }

        Controls.ToolButton {
            visible: root.showCreateActions
            text: i18n("Create project")
            icon.name: "list-add"
            display: QQC2.AbstractButton.IconOnly
            Accessible.name: text
            enabled: root.projectEnabled
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            onClicked: root.createProjectRequested()
            Controls.ToolTip.text: text
            Controls.ToolTip.visible: hovered && !Kirigami.Settings.isMobile
            Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.activityVisible
        spacing: Kirigami.Units.smallSpacing

        SearchableCombo {
            id: activityPicker
            Layout.fillWidth: true
            enabled: root.activityEnabled
                     && (!root.requireProjectSelection || projectPicker.currentIndex >= 0)
            items: root.activityPickerModel
            placeholderText: i18n("Select activity…")
            sectionTitleMap: root.activitySectionTitles
            viewportItem: root.pickerViewport
            useSharedDirection: true
            openBelow: root.pickerOpenBelow
            onAboutToOpen: root.aboutToOpenPicker(projectPicker, activityPicker)
            onActivated: function(index) {
                root.activityActivated(index)
            }
        }

        Controls.ToolButton {
            visible: root.showCreateActions
            text: i18n("Create activity")
            icon.name: "list-add"
            display: QQC2.AbstractButton.IconOnly
            Accessible.name: text
            enabled: root.activityEnabled && projectPicker.currentIndex >= 0
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            onClicked: root.createActivityRequested()
            Controls.ToolTip.text: text
            Controls.ToolTip.visible: hovered && !Kirigami.Settings.isMobile
            Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }
}
