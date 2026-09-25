import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../code/timesheetFields.js" as Fields
import "."

/**
 * Optional billable checkbox and searchable tag pills for create/edit.
 * Hidden per provider capability — one UI, no per-backend fork.
 */
ColumnLayout {
    id: root

    property bool showBillable: true
    property bool showTags: true
    property string tagLookupUrl: ""
    property string tagLookupToken: ""
    property Item pickerViewport: null

    property bool billableTouched: false
    // Billable as loaded from an existing entry (null for new entries).
    property var loadedBillable: null
    readonly property bool billable: billableCheck.checked
    // Only a value the user actually changed is sent: Kimai auto-resolves
    // billable otherwise, and rejects the field without edit_billable permission.
    readonly property var billableOrNull: (billableTouched && billableCheck.checked !== loadedBillable)
                                          ? billableCheck.checked : null
    readonly property var tags: tagPicker.normalizedTags

    visible: showBillable || showTags
    spacing: Kirigami.Units.smallSpacing

    function loadFromTimesheet(timesheet) {
        billableTouched = false
        billableCheck.checked = Fields.billableFromTimesheet(timesheet, Fields.defaultBillable())
        loadedBillable = billableCheck.checked
        tagPicker.setTags(Fields.tagsFromTimesheet(timesheet))
    }

    function resetDefaults() {
        billableTouched = false
        loadedBillable = null
        billableCheck.checked = Fields.defaultBillable()
        tagPicker.setTags([])
    }

    QQC2.CheckBox {
        id: billableCheck
        visible: root.showBillable
        Layout.fillWidth: true
        enabled: root.enabled
        checked: true
        text: i18n("Billable")
        Accessible.name: text
        onClicked: root.billableTouched = true
    }

    TagPicker {
        id: tagPicker
        visible: root.showTags
        Layout.fillWidth: true
        enabled: root.enabled
        kimaiUrl: root.tagLookupUrl
        apiToken: root.tagLookupToken
        pickerViewport: root.pickerViewport
    }
}
