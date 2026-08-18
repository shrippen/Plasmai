import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "."

/**
 * Overflow create dialog for customer / project / activity.
 * One form, mode switches fields; pickers stay the normal path.
 */
QQC2.Dialog {
    id: root

    property string mode: "project" // customer | project | activity
    property var customers: []
    property var selectedProjectId: null
    property string selectedProjectName: ""

    readonly property var customerRows: {
        var rows = []
        var list = root.customers || []
        for (var i = 0; i < list.length; i++) {
            var c = list[i] || {}
            rows.push({
                id: c.id,
                name: c.name || "",
                color: KimaiApi.normalizeCustomerColor(c.color)
            })
        }
        return rows
    }

    signal submitted(string mode, var payload)

    modal: true
    standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
    padding: Kirigami.Units.largeSpacing
    title: {
        if (mode === "customer") {
            return i18n("Create customer")
        }
        if (mode === "activity") {
            return i18n("Create activity")
        }
        return i18n("Create project")
    }

    function resetForMode(nextMode) {
        mode = nextMode
        nameField.text = ""
        customerCombo.currentIndex = -1
        refreshOk()
    }

    function refreshOk() {
        var btn = standardButton(QQC2.Dialog.Ok)
        if (!btn) {
            return
        }
        var named = nameField.text.trim().length > 0
        if (mode === "project") {
            btn.enabled = named && customerCombo.currentIndex >= 0
        } else {
            btn.enabled = named
        }
    }

    onAboutToShow: {
        nameField.text = ""
        customerCombo.currentIndex = -1
        Qt.callLater(refreshOk)
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.mediumSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.8
            visible: root.mode === "activity" && root.selectedProjectName.length > 0
            text: i18n("Activity will be added to %1.", root.selectedProjectName)
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: i18n("Name")
            font.bold: true
            opacity: 0.85
        }

        QQC2.TextField {
            id: nameField
            Layout.fillWidth: true
            Accessible.name: i18n("Name")
            onTextChanged: root.refreshOk()
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.mode === "project"
            text: i18n("Customer")
            font.bold: true
            opacity: 0.85
        }

        QQC2.ComboBox {
            id: customerCombo
            Layout.fillWidth: true
            visible: root.mode === "project"
            model: root.customerRows
            textRole: "name"
            Accessible.name: i18n("Customer")
            onActivated: root.refreshOk()

            contentItem: Item {
                ColorLabelRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: customerCombo.currentIndex >= 0
                                     && customerCombo.currentIndex < root.customerRows.length
                    customerRole: true
                    customerColor: visible
                                   ? root.customerRows[customerCombo.currentIndex].color
                                   : KimaiApi.DEFAULT_CUSTOMER_COLOR
                    colorCategory: "customer"
                    entityId: visible ? root.customerRows[customerCombo.currentIndex].id : null
                    label: visible ? root.customerRows[customerCombo.currentIndex].name : ""
                    labelPointSize: Kirigami.Theme.defaultFont.pointSize
                    labelBold: false
                    labelOpacity: 1.0
                }
                PlasmaComponents3.Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: customerCombo.currentIndex < 0
                    text: i18n("Select customer…")
                    opacity: 0.65
                    elide: Text.ElideRight
                }
            }

            delegate: QQC2.ItemDelegate {
                width: customerCombo.width
                height: Math.max(implicitHeight, TouchUi.pickerEntryHeight)
                leftPadding: Kirigami.Units.smallSpacing
                rightPadding: Kirigami.Units.smallSpacing
                topPadding: TouchUi.listRowPadding / 2
                bottomPadding: TouchUi.listRowPadding / 2
                spacing: 0
                highlighted: customerCombo.highlightedIndex === index
                onClicked: customerCombo.currentIndex = index

                contentItem: ColorLabelRow {
                    width: parent ? parent.width : implicitWidth
                    customerRole: true
                    customerColor: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    colorCategory: "customer"
                    entityId: modelData.id
                    label: modelData.name
                    labelPointSize: Kirigami.Theme.defaultFont.pointSize
                    labelBold: false
                    labelOpacity: 1.0
                }
            }
        }

        PlasmaComponents3.Button {
            visible: root.mode === "project"
            text: i18n("Create customer")
            icon.name: "list-add"
            Accessible.name: text
            onClicked: {
                root.mode = "customer"
                nameField.text = ""
                root.refreshOk()
            }
        }
    }

    onAccepted: {
        var payload = { name: nameField.text.trim() }
        if (root.mode === "project" && customerCombo.currentIndex >= 0
                && root.customerRows[customerCombo.currentIndex]) {
            payload.customer = root.customerRows[customerCombo.currentIndex].id
        }
        if (root.mode === "activity") {
            payload.project = root.selectedProjectId
        }
        root.submitted(root.mode, payload)
    }
}
