import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"

Kirigami.Page {
    id: page
    title: ""
    background: Rectangle { color: root.bgWindow }

    property var expandedProjectId: null
    property var expandedActivities: []

    function toggleExpanded(projectId) {
        if (page.expandedProjectId === projectId) {
            page.expandedProjectId = null
            page.expandedActivities = []
            return
        }
        page.expandedProjectId = projectId
        page.expandedActivities = []
        root.loadActivitiesForProject(projectId, function(model) {
            if (page.expandedProjectId === projectId) page.expandedActivities = model
        })
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
        clip: true
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: col
            width: parent.width
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading { level: 1; text: i18n("Favorites") }
            QQC2.Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                opacity: 0.75
                text: i18n("Tap a project to see its activities, then pin the ones you use often.")
            }

            Kirigami.PlaceholderMessage {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
                visible: !root.isConfigured
                icon.name: "configure"
                text: i18n("Connect a time tracker first")
            }

            Repeater {
                model: root.isConfigured ? root.projectPickerModel : []
                delegate: ColumnLayout {
                    id: projectDelegate
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    QQC2.ItemDelegate {
                        Layout.fillWidth: true
                        contentItem: ColorLabelRow {
                            customerRole: false
                            customerColor: projectDelegate.modelData.rowColor || KimaiApi.DEFAULT_CUSTOMER_COLOR
                            colorCategory: projectDelegate.modelData.rowColorCategory || ""
                            entityId: projectDelegate.modelData.rowEntityId
                            label: (projectDelegate.modelData.section ? projectDelegate.modelData.section + " · " : "") + projectDelegate.modelData.label
                        }
                        onClicked: page.toggleExpanded(projectDelegate.modelData.value.id)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        visible: page.expandedProjectId === projectDelegate.modelData.value.id
                        spacing: 0

                        QQC2.BusyIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            running: visible
                            visible: page.expandedProjectId === projectDelegate.modelData.value.id && page.expandedActivities.length === 0
                        }

                        Repeater {
                            model: page.expandedProjectId === projectDelegate.modelData.value.id ? page.expandedActivities : []
                            delegate: QQC2.CheckDelegate {
                                required property var modelData
                                Layout.fillWidth: true
                                checked: root.isPinned(projectDelegate.modelData.value.id, modelData.value.id)
                                text: modelData.label
                                onToggled: root.togglePin(projectDelegate.modelData.value.id, modelData.value.id)
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }
}
