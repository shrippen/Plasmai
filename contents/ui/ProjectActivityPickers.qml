import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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

    readonly property alias projectCombo: projectCombo
    readonly property alias activityCombo: activityCombo

    signal aboutToOpenPicker(var projectField, var activityField)
    signal projectActivated(int index)

    spacing: 0

    function closePickers() {
        projectCombo.closePopup()
        activityCombo.closePopup()
    }

    SearchableCombo {
        id: projectCombo
        Layout.fillWidth: true
        visible: root.projectVisible
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

    SearchableCombo {
        id: activityCombo
        Layout.fillWidth: true
        visible: root.activityVisible
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
}
