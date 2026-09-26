import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../contents/code/kimaiApi.js" as KimaiApi
import "."
import "../Kante"

/**
 * Overflow create dialog for customer / project / activity.
 * One form, mode switches fields; pickers stay the normal path.
 */
Kirigami.Dialog {
    id: root
    KanteDialogSkin { dialog: root }

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

    // Own footer actions: Qt's standard button texts stay English on Android (no Qt translations there).
    readonly property bool canSubmit: nameField.text.trim().length > 0
                                      && (mode !== "project" || customerCombo.currentIndex >= 0)
    standardButtons: Kirigami.Dialog.NoButton
    customFooterActions: [
        Kirigami.Action {
            text: i18n("Save")
            icon.name: "dialog-ok"
            enabled: root.canSubmit
            onTriggered: root.accept()
        },
        Kirigami.Action {
            text: i18n("Cancel")
            icon.name: "dialog-cancel"
            onTriggered: root.reject()
        }
    ]
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
    }

    onAboutToShow: {
        nameField.text = ""
        customerCombo.currentIndex = -1
    }

    ColumnLayout {
        spacing: Kirigami.Units.mediumSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.8
            visible: root.mode === "activity" && root.selectedProjectName.length > 0
            text: i18n("Activity will be added to %1.", root.selectedProjectName)
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Name")
            font.bold: true
            opacity: 0.85
        }

        KanteTextField {
            id: nameField
            Layout.fillWidth: true
            Accessible.name: i18n("Name")
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: root.mode === "project"
            text: i18n("Customer")
            font.bold: true
            opacity: 0.85
        }

        QQC2.ComboBox {
            KanteFieldSkin { control: parent }
            id: customerCombo
            Layout.fillWidth: true
            visible: root.mode === "project"
            model: root.customerRows
            textRole: "name"
            Accessible.name: i18n("Customer")

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
                    label: visible ? root.customerRows[customerCombo.currentIndex].name : ""
                    labelPointSize: KanteStyle.defaultFont.pointSize
                    labelBold: false
                    labelOpacity: 1.0
                }
                QQC2.Label {
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
                    label: modelData.name
                    labelPointSize: KanteStyle.defaultFont.pointSize
                    labelBold: false
                    labelOpacity: 1.0
                }
            }
        }

        KanteButton {
            visible: root.mode === "project"
            text: i18n("Create customer")
            icon.name: "list-add"
            Accessible.name: text
            onClicked: {
                root.mode = "customer"
                nameField.text = ""
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
