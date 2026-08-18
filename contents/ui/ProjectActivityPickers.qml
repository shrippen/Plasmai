import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

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

    readonly property alias projectCombo: projectCombo
    readonly property alias activityCombo: activityCombo

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectActivated(int index)
    signal createProjectRequested()
    signal createActivityRequested()

    spacing: 0

    function closePickers() {
        projectCombo.closePopup()
        activityCombo.closePopup()
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.projectVisible
        spacing: Kirigami.Units.smallSpacing

        SearchableCombo {
            id: projectCombo
            Layout.fillWidth: true
            enabled: root.projectEnabled
            items: root.projectPickerModel
            placeholderText: i18n("Select project…")
            viewportItem: root.pickerViewport
            useSharedDirection: true
            openBelow: root.pickerOpenBelow
            onAboutToOpen: root.aboutToOpenPicker(projectCombo, activityCombo)
            onActivated: function(index) {
                root.projectActivated(index)
            }
        }

        PlasmaComponents3.ToolButton {
            visible: root.showCreateActions
            text: i18n("Create project")
            icon.name: "list-add"
            display: QQC2.AbstractButton.IconOnly
            Accessible.name: text
            enabled: root.projectEnabled
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            onClicked: root.createProjectRequested()
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.activityVisible
        spacing: Kirigami.Units.smallSpacing

        SearchableCombo {
            id: activityCombo
            Layout.fillWidth: true
            enabled: root.activityEnabled
                     && (!root.requireProjectSelection || projectCombo.currentIndex >= 0)
            items: root.activityPickerModel
            placeholderText: i18n("Select activity…")
            sectionTitleMap: root.activitySectionTitles
            viewportItem: root.pickerViewport
            useSharedDirection: true
            openBelow: root.pickerOpenBelow
            onAboutToOpen: root.aboutToOpenPicker(projectCombo, activityCombo)
        }

        PlasmaComponents3.ToolButton {
            visible: root.showCreateActions
            text: i18n("Create activity")
            icon.name: "list-add"
            display: QQC2.AbstractButton.IconOnly
            Accessible.name: text
            enabled: root.activityEnabled && projectCombo.currentIndex >= 0
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            onClicked: root.createActivityRequested()
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }
}
